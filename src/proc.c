/*
 * proc.c -- the `proc` module: children with decided lifetimes.
 *
 *   local r = proc.run { "git", "status", cwd = ".", timeout = "30s" }
 *   -- r = { status = "exit"|"timeout"|"killed", code = 0, out = "...",
 *   --       err = "...", pid = 4120, elapsed = 0.41, truncated = false }
 *   -- or nil, err with PROC notfound | launch | badvalue | encoding | usage
 *   local c <close> = proc.start { "server.exe", timeout = "10m" }
 *   c.pid; c:running(); c:wait("5s"); c:kill(); c:close()
 *   local pid = proc.detach { "updater.exe" }   -- outlives kuu, on purpose
 *   proc.alive(pid); proc.kill(pid)
 *
 * Every supervised child is born into its own Job Object with KILL_ON_JOB_CLOSE
 * and its stdout, stderr, and stdin are overlapped pipes on the loop's
 * completion port; the job's messages arrive on the same port.  A child is
 * complete when its whole job is empty and its pipes have reached EOF; a
 * grandchild that outlives the child keeps the result open, as it should.
 * No thread is created per child.
 */
#include "err.h"
#include "launch.h"
#include "loop.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KU_CHILD_META "kuu.child"
#define KU_READ_CHUNK 65536
#define KU_WRITE_CHUNK 65536
#define KU_DEFAULT_MAXOUT ((size_t)64 * 1024 * 1024)

enum { IO_OUT = 1, IO_ERR = 2, IO_IN = 3 };

/* The outcome of a child, shared by the child and by every waiter that saw it. */
typedef struct ku_result {
    int refs;
    const char *status;
    DWORD code;
    DWORD pid;
    double elapsed;
    unsigned char *out, *err;
    size_t out_len, err_len;
    int truncated;
} ku_result;

typedef struct ku_stream {
    HANDLE handle;
    ku_io *io;
    unsigned char *data;
    size_t len, cap, limit;
    int truncated;
    int eof;
    DWORD error;
} ku_stream;

typedef struct ku_child {
    ku_source job_src, io_src;
    ku_loop *loop;
    HANDLE job, process;
    DWORD pid;
    ku_stream out, err;
    HANDLE in_handle;
    ku_io *in_io;
    unsigned char *in_data;
    size_t in_len, in_off;
    int in_done;
    int job_zero, exited, done, killed, timed_out;
    int closed;   /* the Lua side released it */
    DWORD exit_code;
    int64_t start_ms;
    ku_timer deadline;
    ku_waiter *waiters;
    ku_result *result;
} ku_child;

/* ---- results ------------------------------------------------------------------- */

static void result_unref(ku_result *r)
{
    if (r != NULL && --r->refs == 0) {
        free(r->out);
        free(r->err);
        free(r);
    }
}

static void push_result(lua_State *L, const ku_result *r)
{
    lua_createtable(L, 0, 7);
    lua_pushstring(L, r->status);
    lua_setfield(L, -2, "status");
    lua_pushinteger(L, (lua_Integer)r->code);
    lua_setfield(L, -2, "code");
    lua_pushinteger(L, (lua_Integer)r->pid);
    lua_setfield(L, -2, "pid");
    lua_pushlstring(L, (const char *)r->out, r->out_len);
    lua_setfield(L, -2, "out");
    lua_pushlstring(L, (const char *)r->err, r->err_len);
    lua_setfield(L, -2, "err");
    lua_pushnumber(L, r->elapsed);
    lua_setfield(L, -2, "elapsed");
    lua_pushboolean(L, r->truncated);
    lua_setfield(L, -2, "truncated");
}

/* ---- streams -------------------------------------------------------------------- */

static void stream_append(ku_stream *s, const unsigned char *bytes, size_t n)
{
    if (s->len + n > s->limit) {
        n = s->limit > s->len ? s->limit - s->len : 0;
        s->truncated = 1;
    }
    if (n == 0) {
        return;
    }
    if (s->len + n > s->cap) {
        size_t cap = s->cap ? s->cap : 65536;
        while (cap < s->len + n) {
            cap *= 2;
        }
        if (cap > s->limit) {
            cap = s->limit;
        }
        unsigned char *grown = (unsigned char *)realloc(s->data, cap);
        if (grown == NULL) {
            s->truncated = 1;
            return;
        }
        s->data = grown;
        s->cap = cap;
    }
    memcpy(s->data + s->len, bytes, n);
    s->len += n;
}

static void stream_finish(ku_stream *s, DWORD error)
{
    s->eof = 1;
    if (error != 0 && error != ERROR_BROKEN_PIPE && error != ERROR_PIPE_NOT_CONNECTED &&
        error != ERROR_HANDLE_EOF && error != ERROR_OPERATION_ABORTED && error != ERROR_NO_DATA) {
        s->error = error;
    }
}

static void child_check_done(ku_child *c);

static int stream_post_read(ku_child *c, ku_stream *s, int kind)
{
    ku_io *io = ku_io_new(c->loop, &c->io_src, s->handle, KU_READ_CHUNK);
    if (io == NULL) {
        stream_finish(s, ERROR_NOT_ENOUGH_MEMORY);
        return -1;
    }
    io->kind = kind;
    s->io = io;
    if (!ReadFile(s->handle, io->buf, io->cap, NULL, &io->ov)) {
        DWORD error = GetLastError();
        if (error != ERROR_IO_PENDING) {
            s->io = NULL;
            ku_io_free(io);
            stream_finish(s, error);
            return 0;
        }
    }
    ku_io_posted(io); /* a packet arrives for a synchronous success as well */
    return 0;
}

static void stdin_finish(ku_child *c, DWORD error)
{
    (void)error; /* a child that stops reading its stdin is not a failure */
    if (c->in_handle != NULL) {
        CloseHandle(c->in_handle);
        c->in_handle = NULL;
    }
    c->in_done = 1;
}

static void stdin_post(ku_child *c)
{
    if (c->in_off >= c->in_len) {
        stdin_finish(c, 0); /* everything written: EOF for the child */
        return;
    }
    ku_io *io = ku_io_new(c->loop, &c->io_src, c->in_handle, 0);
    if (io == NULL) {
        stdin_finish(c, ERROR_NOT_ENOUGH_MEMORY);
        return;
    }
    io->kind = IO_IN;
    c->in_io = io;
    size_t remaining = c->in_len - c->in_off;
    DWORD chunk = remaining > KU_WRITE_CHUNK ? KU_WRITE_CHUNK : (DWORD)remaining;
    if (!WriteFile(c->in_handle, c->in_data + c->in_off, chunk, NULL, &io->ov)) {
        DWORD error = GetLastError();
        if (error != ERROR_IO_PENDING) {
            c->in_io = NULL;
            ku_io_free(io);
            stdin_finish(c, error);
            return;
        }
    }
    ku_io_posted(io);
}

static void child_on_io(ku_source *src, ku_io *io, DWORD bytes, DWORD error)
{
    ku_child *c = (ku_child *)src->owner;
    if (io->kind == IO_IN) {
        c->in_io = NULL;
        ku_io_free(io);
        if (error != 0) {
            stdin_finish(c, error);
        } else {
            c->in_off += bytes;
            if (c->closed || c->job_zero) {
                stdin_finish(c, 0);
            } else {
                stdin_post(c);
            }
        }
        child_check_done(c);
        return;
    }
    ku_stream *s = io->kind == IO_OUT ? &c->out : &c->err;
    s->io = NULL;
    if (error == 0) {
        if (bytes > 0) {
            stream_append(s, io->buf, bytes);
        }
        ku_io_free(io);
        if (c->closed) {
            stream_finish(s, 0);
        } else {
            stream_post_read(c, s, io->kind == IO_OUT ? IO_OUT : IO_ERR);
        }
    } else {
        ku_io_free(io);
        stream_finish(s, error);
    }
    child_check_done(c);
}

static void child_on_job(ku_source *src, DWORD message, DWORD pid)
{
    ku_child *c = (ku_child *)src->owner;
    switch (message) {
    case JOB_OBJECT_MSG_EXIT_PROCESS:
    case JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS:
        if (pid == c->pid && !c->exited && c->process != NULL) {
            DWORD code = 0;
            if (GetExitCodeProcess(c->process, &code) && code != STILL_ACTIVE) {
                c->exited = 1;
                c->exit_code = code;
            }
        }
        break;
    case JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO:
        if (!c->job_zero) {
            c->job_zero = 1;
            ku_loop_received(c->loop);
            if (c->in_io != NULL) {
                CancelIoEx(c->in_handle, &c->in_io->ov); /* nobody reads it any more */
            }
            child_check_done(c);
        }
        break;
    default:
        break;
    }
}

static void child_free(ku_child *c)
{
    while (c->waiters != NULL) { /* only on the shutdown path: never resumed */
        ku_waiter *w = c->waiters;
        c->waiters = w->next;
        free(w);
    }
    result_unref(c->result);
    free(c->out.data);
    free(c->err.data);
    free(c->in_data);
    free(c);
}

/* Kill whatever still runs.  The job does the whole tree at once. */
static void child_kill(ku_child *c)
{
    if (c->done) {
        return;
    }
    c->killed = 1;
    if (c->job != NULL && TerminateJobObject(c->job, 1)) {
        return;
    }
    if (c->process != NULL) {
        TerminateProcess(c->process, 1);
    }
}

static void child_check_done(ku_child *c)
{
    if (c->done || !(c->job_zero && c->out.eof && c->err.eof && c->in_done)) {
        return;
    }
    c->done = 1;
    if (!c->exited && c->process != NULL) {
        DWORD code = 0;
        if (GetExitCodeProcess(c->process, &code)) {
            c->exited = 1;
            c->exit_code = code;
        }
    }
    ku_timer_cancel(c->loop, &c->deadline);
    if (c->process != NULL) {
        CloseHandle(c->process);
        c->process = NULL;
    }
    if (c->job != NULL) {
        CloseHandle(c->job); /* ACTIVE_PROCESS_ZERO was the job's last message */
        c->job = NULL;
    }
    if (c->out.handle != NULL) {
        CloseHandle(c->out.handle);
        c->out.handle = NULL;
    }
    if (c->err.handle != NULL) {
        CloseHandle(c->err.handle);
        c->err.handle = NULL;
    }
    ku_result *r = (ku_result *)calloc(1, sizeof *r);
    if (r != NULL) {
        r->refs = 1;
        r->status = c->timed_out ? "timeout" : c->killed ? "killed" : "exit";
        r->code = c->exit_code;
        r->pid = c->pid;
        r->elapsed = (double)(ku_now_ms() - c->start_ms) / 1000.0;
        r->out = c->out.data;
        r->out_len = c->out.len;
        r->err = c->err.data;
        r->err_len = c->err.len;
        r->truncated = c->out.truncated || c->err.truncated;
        c->out.data = NULL;
        c->out.len = c->out.cap = 0;
        c->err.data = NULL;
        c->err.len = c->err.cap = 0;
    }
    c->result = r;
    while (c->waiters != NULL) {
        ku_waiter *w = c->waiters;
        c->waiters = w->next;
        w->next = NULL;
        if (r != NULL) {
            r->refs++;
        }
        w->data = r;
        ku_wake(w);
    }
    if (c->closed) {
        child_free(c);
    }
}

static void child_deadline(ku_timer *timer)
{
    ku_child *c = (ku_child *)timer->owner;
    if (!c->done) {
        c->timed_out = 1;
        child_kill(c);
    }
}

/* The Lua side lets go: kill what runs, cancel what is outstanding, and free
 * the child now if it is quiescent or when its last completion arrives. */
static void child_release(ku_child *c)
{
    if (c->closed) {
        return;
    }
    c->closed = 1;
    if (!c->done) {
        child_kill(c);
        if (c->out.io != NULL) {
            CancelIoEx(c->out.handle, &c->out.io->ov);
        }
        if (c->err.io != NULL) {
            CancelIoEx(c->err.handle, &c->err.io->ov);
        }
        if (c->in_io != NULL) {
            CancelIoEx(c->in_handle, &c->in_io->ov);
        }
        return; /* the completions finish the job; child_check_done frees */
    }
    child_free(c);
}

/* ---- the launch spec ------------------------------------------------------------ */

typedef struct ku_spec {
    int argc;
    const char **argv;
    const char *cwd;
    int env_count;
    const char **env_keys;
    const char **env_values;
    int64_t timeout_ms; /* -1: none */
    const unsigned char *stdin_data;
    size_t stdin_len;
    int has_stdin;
    size_t maxout;
} ku_spec;

static const char *spec_string(lua_State *L, int idx, const char *what, size_t *len)
{
    int type = lua_type(L, idx);
    if (type != LUA_TSTRING && type != LUA_TNUMBER) {
        ku_err_raise(L, "PROC", "badvalue", "%s must be a string, got %s", what, luaL_typename(L, idx));
    }
    return lua_tolstring(L, idx, len);
}

/* Keep the value at `idx` alive for the rest of the call by storing it in the
 * anchor table at `keep`; the spec's pointers into Lua strings stay valid. */
static void anchor(lua_State *L, int keep, int idx)
{
    lua_pushvalue(L, idx);
    lua_rawseti(L, keep, (lua_Integer)lua_rawlen(L, keep) + 1);
}

/* Parse the call's arguments into a spec.  Every string the spec points into
 * is anchored in a table that lives on the stack for the duration of the
 * call.  Raises PROC usage/badvalue for programming errors. */
static void parse_spec(lua_State *L, ku_spec *spec, int allow_options)
{
    memset(spec, 0, sizeof *spec);
    spec->timeout_ms = -1;
    spec->maxout = KU_DEFAULT_MAXOUT;
    int top = lua_gettop(L);
    lua_newtable(L);
    int keep = top + 1;
    if (top == 0) {
        ku_err_raise(L, "PROC", "usage", "a command is required: proc.run{ \"exe\", \"arg\", ... }");
    }
    if (lua_type(L, 1) != LUA_TTABLE) {
        /* proc.run("exe", "arg", ...) */
        spec->argc = top;
        spec->argv = (const char **)lua_newuserdatauv(L, sizeof(char *) * (size_t)top, 0);
        for (int i = 1; i <= top; i++) {
            size_t len = 0;
            const char *s = spec_string(L, i, "each command argument", &len);
            if (strlen(s) != len) {
                ku_err_raise(L, "PROC", "badvalue", "command argument %d contains a NUL byte", i);
            }
            spec->argv[i - 1] = s;
        }
        return;
    }
    if (top != 1) {
        ku_err_raise(L, "PROC", "usage", "pass either one table or plain string arguments");
    }
    lua_Integer n = (lua_Integer)lua_rawlen(L, 1);
    if (n < 1) {
        ku_err_raise(L, "PROC", "usage", "the table needs the command at [1]");
    }
    if (n > 4096) {
        ku_err_raise(L, "PROC", "badvalue", "too many command arguments");
    }
    luaL_checkstack(L, (int)n + 64, "command arguments");
    spec->argc = (int)n;
    spec->argv = (const char **)lua_newuserdatauv(L, sizeof(char *) * (size_t)n, 0);
    for (lua_Integer i = 1; i <= n; i++) {
        lua_rawgeti(L, 1, i);
        size_t len = 0;
        const char *s = spec_string(L, -1, "each command argument", &len);
        if (strlen(s) != len) {
            ku_err_raise(L, "PROC", "badvalue", "command argument %d contains a NUL byte", (int)i);
        }
        anchor(L, keep, -1);
        lua_pop(L, 1);
        spec->argv[i - 1] = s;
    }
    /* Named options.  Anything unrecognised is a mistake worth stopping for. */
    lua_pushnil(L);
    while (lua_next(L, 1) != 0) {
        if (lua_type(L, -2) == LUA_TNUMBER) {
            lua_Integer k = lua_tointeger(L, -2);
            if (lua_isinteger(L, -2) && k >= 1 && k <= n) {
                lua_pop(L, 1);
                continue;
            }
            ku_err_raise(L, "PROC", "usage", "unexpected numeric key in the command table");
        }
        if (lua_type(L, -2) != LUA_TSTRING) {
            ku_err_raise(L, "PROC", "usage", "option names must be strings");
        }
        const char *key = lua_tostring(L, -2);
        if (!allow_options) {
            ku_err_raise(L, "PROC", "usage", "option '%s' is not accepted here", key);
        }
        if (strcmp(key, "cwd") == 0) {
            size_t len = 0;
            const char *s = spec_string(L, -1, "cwd", &len);
            if (strlen(s) != len || len == 0) {
                ku_err_raise(L, "PROC", "badvalue", "cwd must be a non-empty path without NUL bytes");
            }
            anchor(L, keep, -1);
            spec->cwd = s;
        } else if (strcmp(key, "timeout") == 0) {
            if (ku_check_duration(L, -1, &spec->timeout_ms) != 0) {
                ku_err_raise(L, "PROC", "badvalue", "timeout must be a duration such as \"30s\"");
            }
        } else if (strcmp(key, "maxout") == 0) {
            int64_t bytes = 0;
            if (ku_check_bytes(L, -1, &bytes) != 0 || bytes < 0) {
                ku_err_raise(L, "PROC", "badvalue", "maxout must be a size such as \"16M\"");
            }
            spec->maxout = (size_t)bytes;
        } else if (strcmp(key, "stdin") == 0) {
            if (lua_type(L, -1) != LUA_TSTRING) {
                ku_err_raise(L, "PROC", "badvalue", "stdin must be a string of bytes");
            }
            size_t len = 0;
            const char *s = lua_tolstring(L, -1, &len);
            anchor(L, keep, -1);
            spec->stdin_data = (const unsigned char *)s;
            spec->stdin_len = len;
            spec->has_stdin = 1;
        } else if (strcmp(key, "env") == 0) {
            if (lua_type(L, -1) != LUA_TTABLE) {
                ku_err_raise(L, "PROC", "badvalue", "env must be a table of NAME = value");
            }
            int env_index = lua_gettop(L);
            int count = 0;
            lua_pushnil(L);
            while (lua_next(L, env_index) != 0) {
                count++;
                lua_pop(L, 1);
            }
            if (count > 4096) {
                ku_err_raise(L, "PROC", "badvalue", "too many environment entries");
            }
            luaL_checkstack(L, 8, "environment");
            /* The two arrays live in the keep table, not on the stack, so the
             * option loop's key/value discipline is undisturbed. */
            spec->env_keys = (const char **)lua_newuserdatauv(L, sizeof(char *) * (size_t)(count + 1), 0);
            anchor(L, keep, -1);
            lua_pop(L, 1);
            spec->env_values = (const char **)lua_newuserdatauv(L, sizeof(char *) * (size_t)(count + 1), 0);
            anchor(L, keep, -1);
            lua_pop(L, 1);
            spec->env_count = 0;
            lua_pushnil(L);
            while (lua_next(L, env_index) != 0) {
                if (lua_type(L, -2) != LUA_TSTRING) {
                    ku_err_raise(L, "PROC", "badvalue", "environment names must be strings");
                }
                size_t klen = 0;
                const char *k = lua_tolstring(L, -2, &klen);
                if (strlen(k) != klen || klen == 0 || strchr(k, '=') != NULL) {
                    ku_err_raise(L, "PROC", "badvalue",
                                 "environment names must be non-empty and contain neither '=' nor NUL");
                }
                const char *v = NULL;
                if (lua_type(L, -1) == LUA_TBOOLEAN && !lua_toboolean(L, -1)) {
                    v = NULL; /* false removes the variable */
                } else {
                    size_t vlen = 0;
                    v = spec_string(L, -1, "an environment value", &vlen);
                    if (strlen(v) != vlen) {
                        ku_err_raise(L, "PROC", "badvalue", "environment values may not contain NUL bytes");
                    }
                }
                anchor(L, keep, -2);
                anchor(L, keep, -1);
                spec->env_keys[spec->env_count] = k;
                spec->env_values[spec->env_count] = v;
                spec->env_count++;
                lua_pop(L, 1);
            }
        } else {
            ku_err_raise(L, "PROC", "usage", "unknown option '%s'", key);
        }
        lua_pop(L, 1);
    }
}

/* ---- pipes ---------------------------------------------------------------------- */

static int make_pipe(int inbound, HANDLE *ours, HANDLE *theirs, ku_fail *fail)
{
    static unsigned long long counter;
    wchar_t name[128];
    _snwprintf(name, sizeof name / sizeof name[0], L"\\\\.\\pipe\\kuu.%lu.%llu",
               (unsigned long)GetCurrentProcessId(), ++counter);
    *ours = CreateNamedPipeW(name,
                             (inbound ? PIPE_ACCESS_INBOUND : PIPE_ACCESS_OUTBOUND) |
                                 FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                             PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                             1, 65536, 65536, 0, NULL);
    if (*ours == INVALID_HANDLE_VALUE) {
        *ours = NULL;
        return ku_fail_set(fail, "PROC", "oserror", "cannot create a pipe (error %lu)",
                           (unsigned long)GetLastError());
    }
    *theirs = CreateFileW(name, inbound ? GENERIC_WRITE : GENERIC_READ, 0, NULL, OPEN_EXISTING,
                          FILE_ATTRIBUTE_NORMAL, NULL);
    if (*theirs == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        CloseHandle(*ours);
        *ours = NULL;
        *theirs = NULL;
        return ku_fail_set(fail, "PROC", "oserror", "cannot open the child's pipe end (error %lu)",
                           (unsigned long)error);
    }
    return 0;
}

/* ---- launching a supervised child --------------------------------------------- */

static int child_launch(lua_State *L, const ku_spec *spec, ku_child **out, ku_fail *fail)
{
    *out = NULL;
    char *exe = NULL;
    int resolved = ku_resolve_exe(spec->argv[0], &exe);
    if (resolved == 1) {
        return ku_fail_set(fail, "PROC", "notfound", "cannot find '%s' on PATH", spec->argv[0]);
    }
    if (resolved == 2) {
        return ku_fail_set(fail, "PROC", "encoding", "the command name is not valid UTF-8");
    }
    wchar_t *env = NULL;
    if (spec->env_count > 0 &&
        ku_env_block(spec->env_count, spec->env_keys, spec->env_values, &env, fail) != 0) {
        free(exe);
        return 1;
    }
    ku_child *c = (ku_child *)calloc(1, sizeof *c);
    if (c == NULL) {
        free(exe);
        free(env);
        return ku_fail_set(fail, "PROC", "oserror", "out of memory");
    }
    ku_loop *lp = ku_loop_of(L);
    c->loop = lp;
    c->job_src.kind = KU_SRC_JOB;
    c->job_src.owner = c;
    c->job_src.on_job = child_on_job;
    c->io_src.kind = KU_SRC_IO;
    c->io_src.owner = c;
    c->io_src.on_io = child_on_io;
    c->out.limit = spec->maxout;
    c->err.limit = spec->maxout;
    ku_timer_init(&c->deadline, child_deadline, c);

    HANDLE their_in = NULL, their_out = NULL, their_err = NULL;
    int rc = 1;
    c->job = ku_job_new(fail);
    if (c->job == NULL) {
        goto fail;
    }
    if (ku_loop_attach_job(lp, c->job, &c->job_src) != 0) {
        ku_fail_set(fail, "PROC", "oserror", "cannot attach the job to the loop (error %lu)",
                    (unsigned long)GetLastError());
        goto fail;
    }
    if (make_pipe(1, &c->out.handle, &their_out, fail) != 0 ||
        make_pipe(1, &c->err.handle, &their_err, fail) != 0) {
        goto fail;
    }
    if (spec->has_stdin) {
        if (make_pipe(0, &c->in_handle, &their_in, fail) != 0) {
            goto fail;
        }
        if (spec->stdin_len > 0) {
            c->in_data = (unsigned char *)malloc(spec->stdin_len);
            if (c->in_data == NULL) {
                ku_fail_set(fail, "PROC", "oserror", "out of memory");
                goto fail;
            }
            memcpy(c->in_data, spec->stdin_data, spec->stdin_len);
            c->in_len = spec->stdin_len;
        }
    } else {
        their_in = ku_open_nul(0);
        if (their_in == NULL) {
            ku_fail_set(fail, "PROC", "oserror", "cannot open the null device");
            goto fail;
        }
        c->in_done = 1;
    }
    if (ku_loop_attach(lp, c->out.handle, &c->io_src) != 0 ||
        ku_loop_attach(lp, c->err.handle, &c->io_src) != 0 ||
        (c->in_handle != NULL && ku_loop_attach(lp, c->in_handle, &c->io_src) != 0)) {
        ku_fail_set(fail, "PROC", "oserror", "cannot attach a pipe to the loop (error %lu)",
                    (unsigned long)GetLastError());
        goto fail;
    }
    ku_stdio io = {their_in, their_out, their_err};
    c->start_ms = ku_now_ms();
    if (ku_launch(exe, spec->argc, spec->argv, spec->cwd, c->job, &io, env, &c->pid, &c->process, fail) != 0) {
        goto fail;
    }
    /* From here the child exists: the job is live and will report. */
    ku_loop_expect(lp);
    CloseHandle(their_in);
    CloseHandle(their_out);
    CloseHandle(their_err);
    their_in = their_out = their_err = NULL;
    stream_post_read(c, &c->out, IO_OUT);
    stream_post_read(c, &c->err, IO_ERR);
    if (c->in_handle != NULL) {
        stdin_post(c);
    }
    if (spec->timeout_ms >= 0) {
        ku_timer_arm(lp, &c->deadline, spec->timeout_ms);
    }
    free(exe);
    free(env);
    *out = c;
    return 0;

fail:
    if (their_in != NULL) {
        CloseHandle(their_in);
    }
    if (their_out != NULL) {
        CloseHandle(their_out);
    }
    if (their_err != NULL) {
        CloseHandle(their_err);
    }
    if (c->out.handle != NULL) {
        CloseHandle(c->out.handle);
    }
    if (c->err.handle != NULL) {
        CloseHandle(c->err.handle);
    }
    if (c->in_handle != NULL) {
        CloseHandle(c->in_handle);
    }
    if (c->job != NULL) {
        CloseHandle(c->job); /* no process ever joined it: no message will come */
    }
    free(c->in_data);
    free(c);
    free(exe);
    free(env);
    return rc;
}

/* ---- the child userdata ---------------------------------------------------------- */

typedef struct ku_child_box {
    ku_child *child;
} ku_child_box;

static ku_child_box *check_box(lua_State *L, int idx)
{
    return (ku_child_box *)luaL_checkudata(L, idx, KU_CHILD_META);
}

static ku_child *check_child(lua_State *L, int idx)
{
    ku_child_box *box = check_box(L, idx);
    if (box->child == NULL) {
        ku_err_raise(L, "PROC", "closed", "the child has been closed");
    }
    return box->child;
}

static void push_child_box(lua_State *L, ku_child *c)
{
    ku_child_box *box = (ku_child_box *)lua_newuserdatauv(L, sizeof *box, 0);
    box->child = c;
    luaL_setmetatable(L, KU_CHILD_META);
}

static int wait_push(lua_State *L, ku_waiter *w)
{
    ku_result *r = (ku_result *)w->data;
    if (w->timed_out || r == NULL) {
        return ku_err_fail(L, "PROC", "timeout", "the child is still running");
    }
    push_result(L, r);
    result_unref(r);
    return 1;
}

static void wait_timeout(ku_waiter *w)
{
    ku_child *c = (ku_child *)w->owner;
    ku_waiter **link = &c->waiters;
    while (*link != NULL) {
        if (*link == w) {
            *link = w->next;
            w->next = NULL;
            return;
        }
        link = &(*link)->next;
    }
}

/* Park the caller until the child is complete (or `timeout_ms` passes). */
static int child_wait(lua_State *L, ku_child *c, int64_t timeout_ms)
{
    ku_waiter *w = ku_waiter_new(c->loop, c, wait_push);
    if (w == NULL) {
        return ku_err_raise(L, "PROC", "oserror", "out of memory");
    }
    if (c->done) {
        if (c->result != NULL) {
            c->result->refs++;
        }
        w->data = c->result;
        ku_wake(w);
        return ku_wait(L, w, -1);
    }
    w->on_timeout = wait_timeout;
    w->next = c->waiters;
    c->waiters = w;
    return ku_wait(L, w, timeout_ms);
}

/* proc.run{...} / proc.run("exe", ...) */
static int l_proc_run(lua_State *L)
{
    ku_spec spec;
    parse_spec(L, &spec, 1);
    ku_child *c = NULL;
    ku_fail fail;
    if (child_launch(L, &spec, &c, &fail) != 0) {
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    push_child_box(L, c); /* anchored while we wait; released when collected */
    return child_wait(L, c, -1);
}

/* proc.start{...} */
static int l_proc_start(lua_State *L)
{
    ku_spec spec;
    parse_spec(L, &spec, 1);
    ku_child *c = NULL;
    ku_fail fail;
    if (child_launch(L, &spec, &c, &fail) != 0) {
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    push_child_box(L, c);
    return 1;
}

/* proc.detach{...} -> pid */
static int l_proc_detach(lua_State *L)
{
    ku_spec spec;
    parse_spec(L, &spec, 1);
    if (spec.has_stdin || spec.timeout_ms >= 0) {
        return ku_err_raise(L, "PROC", "usage", "detach accepts only cwd and env options");
    }
    char *exe = NULL;
    int resolved = ku_resolve_exe(spec.argv[0], &exe);
    if (resolved == 1) {
        return ku_err_fail(L, "PROC", "notfound", "cannot find '%s' on PATH", spec.argv[0]);
    }
    if (resolved == 2) {
        return ku_err_fail(L, "PROC", "encoding", "the command name is not valid UTF-8");
    }
    ku_fail fail;
    wchar_t *env = NULL;
    if (spec.env_count > 0 && ku_env_block(spec.env_count, spec.env_keys, spec.env_values, &env, &fail) != 0) {
        free(exe);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    HANDLE nul = ku_open_nul(1);
    if (nul == NULL) {
        free(exe);
        free(env);
        return ku_err_fail(L, "PROC", "oserror", "cannot open the null device");
    }
    ku_stdio io = {nul, nul, nul};
    DWORD pid = 0;
    HANDLE process = NULL;
    int rc = ku_launch(exe, spec.argc, spec.argv, spec.cwd, NULL, &io, env, &pid, &process, &fail);
    CloseHandle(nul);
    free(exe);
    free(env);
    if (rc != 0) {
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    CloseHandle(process); /* not supervised: it runs on */
    lua_pushinteger(L, (lua_Integer)pid);
    return 1;
}

/* proc.alive(pid) -> boolean */
static int l_proc_alive(lua_State *L)
{
    lua_Integer pid = luaL_checkinteger(L, 1);
    if (pid <= 0 || pid > 0xffffffffLL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, (DWORD)pid);
    if (h == NULL) {
        /* Access denied means it exists; anything else means it does not. */
        lua_pushboolean(L, GetLastError() == ERROR_ACCESS_DENIED);
        return 1;
    }
    int alive = WaitForSingleObject(h, 0) == WAIT_TIMEOUT;
    CloseHandle(h);
    lua_pushboolean(L, alive);
    return 1;
}

/* proc.kill(pid) -> true | nil, err */
static int l_proc_kill(lua_State *L)
{
    lua_Integer pid = luaL_checkinteger(L, 1);
    if (pid <= 0 || pid > 0xffffffffLL) {
        return ku_err_fail(L, "PROC", "badvalue", "pid must be a positive integer");
    }
    HANDLE h = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, (DWORD)pid);
    if (h == NULL) {
        DWORD error = GetLastError();
        if (error == ERROR_ACCESS_DENIED) {
            return ku_err_fail(L, "PROC", "access", "no permission to terminate process %d", (int)pid);
        }
        return ku_err_fail(L, "PROC", "notfound", "no process %d", (int)pid);
    }
    if (!TerminateProcess(h, 1) && GetLastError() != ERROR_ACCESS_DENIED) {
        DWORD error = GetLastError();
        CloseHandle(h);
        char *text = ku_win_error_message(error);
        int n = ku_err_fail(L, "PROC", "oserror", "cannot terminate process %d: %s", (int)pid,
                            text != NULL ? text : "unknown error");
        free(text);
        return n;
    }
    WaitForSingleObject(h, 2000);
    CloseHandle(h);
    lua_pushboolean(L, 1);
    return 1;
}

/* child:wait([timeout]) */
static int l_child_wait(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    int64_t timeout_ms = -1;
    if (!lua_isnoneornil(L, 2) && ku_check_duration(L, 2, &timeout_ms) != 0) {
        return ku_err_raise(L, "PROC", "badvalue", "wait timeout must be a duration such as \"30s\"");
    }
    return child_wait(L, c, timeout_ms);
}

static int l_child_kill(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    child_kill(c);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_child_running(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    lua_pushboolean(L, !c->done);
    return 1;
}

static int l_child_close(lua_State *L)
{
    ku_child_box *box = check_box(L, 1);
    if (box->child != NULL) {
        child_release(box->child);
        box->child = NULL;
    }
    return 0;
}

static int l_child_index(lua_State *L)
{
    ku_child_box *box = check_box(L, 1);
    const char *key = luaL_checkstring(L, 2);
    if (strcmp(key, "pid") == 0) {
        if (box->child == NULL) {
            lua_pushnil(L);
        } else {
            lua_pushinteger(L, (lua_Integer)box->child->pid);
        }
        return 1;
    }
    luaL_getmetatable(L, KU_CHILD_META);
    lua_getfield(L, -1, "methods");
    lua_getfield(L, -1, key);
    return 1;
}

static int l_child_tostring(lua_State *L)
{
    ku_child_box *box = check_box(L, 1);
    if (box->child == NULL) {
        lua_pushliteral(L, "kuu.child (closed)");
    } else {
        lua_pushfstring(L, "kuu.child pid=%d (%s)", (int)box->child->pid,
                        box->child->done ? "finished" : "running");
    }
    return 1;
}

int ku_open_proc(lua_State *L)
{
    if (luaL_newmetatable(L, KU_CHILD_META)) {
        static const luaL_Reg methods[] = {
            {"wait", l_child_wait},
            {"kill", l_child_kill},
            {"running", l_child_running},
            {"close", l_child_close},
            {NULL, NULL},
        };
        luaL_newlib(L, methods);
        lua_setfield(L, -2, "methods");
        lua_pushcfunction(L, l_child_index);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_child_close);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, l_child_close);
        lua_setfield(L, -2, "__close");
        lua_pushcfunction(L, l_child_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
    static const luaL_Reg functions[] = {
        {"run", l_proc_run},
        {"start", l_proc_start},
        {"detach", l_proc_detach},
        {"alive", l_proc_alive},
        {"kill", l_proc_kill},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
