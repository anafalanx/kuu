/*
 * proc.c -- the `proc` module: children with decided lifetimes.
 *
 *   local r = proc.run { "git", "status", cwd = ".", timeout = "30s" }
 *   -- r = { status = "exit"|"timeout"|"killed", code = 0, out = "...",
 *   --       err = "...", pid = 4120, elapsed = 0.41, truncated = false }
 *   -- or nil, err with PROC notfound | launch | badvalue | encoding | usage
 *   local c <close> = proc.start { "server.exe", timeout = "10m" }
 *   c.pid; c:running(); c:wait("5s"); c:kill(); c:close()
 *   local s <close> = proc.start { "tool.exe", stream = true }
 *   s:write("input\n"); s:close_stdin(); s:read("line", "5s"); for l in s:lines() do end
 *   proc.start { "vim", inherit = true }   -- the child gets kuu's own console
 *   proc.wait_any({ a, b }, "1m"); proc.wait_all({ a, b })
 *   local pid = proc.detach { "updater.exe" }   -- outlives kuu, on purpose
 *   proc.alive(pid); proc.kill(pid)
 *
 * Every supervised child is born into its own Job Object with KILL_ON_JOB_CLOSE
 * and its stdout, stderr, and stdin are overlapped pipes on the loop's
 * completion port; the job's messages arrive on the same port.  A child is
 * complete when its whole job is empty and its pipes have reached EOF; a
 * grandchild that outlives the child keeps the result open, as it should.
 * In stream mode the program reads the pipes itself, with backpressure, and
 * completion means the tree is gone.  No thread is created per child.
 */
#include "err.h"
#include "launch.h"
#include "loop.h"
#include "procinfo.h"
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
#define KU_STDIN_QUEUE_MAX ((size_t)64 * 1024 * 1024)

enum { IO_OUT = 1, IO_ERR = 2, IO_IN = 3 };
enum { READ_LINE = 1, READ_ALL = 2, READ_BYTES = 3, READ_SOME = 4, READ_CLOSED = 5 };

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

typedef struct ku_child ku_child;

typedef struct ku_stream {
    int kind;             /* IO_OUT or IO_ERR */
    HANDLE handle;
    ku_io *io;            /* the outstanding read, or NULL */
    unsigned char *data;
    size_t start, len, cap; /* bytes [start, len) are unread */
    size_t limit;         /* capture: truncation point; stream: backpressure point */
    int truncated;
    int paused;           /* stream mode: no read posted until the reader consumes */
    int eof;
    DWORD error;
    ku_waiter *reader;    /* the one parked reader, stream mode */
} ku_stream;

typedef struct read_request {
    int mode;
    size_t n;
} read_request;

struct ku_child {
    ku_source job_src, io_src;
    ku_loop *loop;
    HANDLE job, process;
    DWORD pid;
    int stream, inherit;
    ku_stream out, err;
    HANDLE in_handle;
    ku_io *in_io;
    unsigned char *in_data;
    size_t in_len, in_off, in_cap;
    int in_close_pending;  /* close stdin once the queue drains */
    int in_done;
    int job_zero, exited, done, killed, timed_out;
    int closed;            /* the Lua side released it */
    int woken;             /* readers woken but not yet resumed: they still hold `c` */
    DWORD exit_code;
    int64_t start_ms;
    ku_timer deadline;
    ku_waiter *waiters;    /* parked wait() callers */
    ku_result *result;
};

/* ---- results ------------------------------------------------------------------- */

static void result_unref(ku_result *r)
{
    if (r != NULL && --r->refs == 0) {
        free(r->out);
        free(r->err);
        free(r);
    }
}

static ku_result *result_ref(ku_result *r)
{
    if (r != NULL) {
        r->refs++;
    }
    return r;
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

static void child_check_done(ku_child *c);
static void child_maybe_free(ku_child *c);
static int stream_post_read(ku_child *c, ku_stream *s);

static size_t stream_available(const ku_stream *s)
{
    return s->len - s->start;
}

static void stream_compact(ku_stream *s)
{
    if (s->start == 0) {
        return;
    }
    if (s->start >= s->len) {
        s->start = 0;
        s->len = 0;
    } else if (s->start > s->cap / 2) {
        memmove(s->data, s->data + s->start, s->len - s->start);
        s->len -= s->start;
        s->start = 0;
    }
}

static void stream_append(ku_child *c, ku_stream *s, const unsigned char *bytes, size_t n)
{
    if (!c->stream && s->len + n > s->limit) {
        n = s->limit > s->len ? s->limit - s->len : 0;
        s->truncated = 1; /* capture mode: the rest is dropped, and said so */
    }
    if (n == 0) {
        return;
    }
    stream_compact(s);
    if (s->len + n > s->cap) {
        size_t cap = s->cap ? s->cap : 65536;
        while (cap < s->len + n) {
            cap *= 2;
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

/* Can the parked reader's request be answered now? */
static int request_ready(const ku_stream *s, const read_request *r)
{
    size_t available = stream_available(s);
    if (s->eof) {
        return 1;
    }
    switch (r->mode) {
    case READ_LINE:
        return memchr(s->data + s->start, '\n', available) != NULL;
    case READ_BYTES:
        return available >= r->n;
    case READ_SOME:
        return available > 0;
    default:
        return 0; /* READ_ALL waits for EOF */
    }
}

/* Consume `n` unread bytes; in stream mode, resume reading when the buffer
 * has drained below the backpressure point. */
static void stream_consume(ku_child *c, ku_stream *s, size_t n)
{
    s->start += n;
    stream_compact(s);
    if (s->paused && !s->eof && stream_available(s) < s->limit) {
        s->paused = 0;
        stream_post_read(c, s);
    }
}

/* Answer a ready request: pushes one value (a string, or nil at EOF). */
static int request_take(lua_State *L, ku_child *c, ku_stream *s, const read_request *r)
{
    size_t available = stream_available(s);
    const unsigned char *p = s->data + s->start;
    switch (r->mode) {
    case READ_LINE: {
        const unsigned char *newline = available > 0 ? (const unsigned char *)memchr(p, '\n', available) : NULL;
        if (newline == NULL) {
            if (available == 0) {
                lua_pushnil(L); /* EOF */
                return 1;
            }
            lua_pushlstring(L, (const char *)p, available); /* the last, unterminated line */
            stream_consume(c, s, available);
            return 1;
        }
        size_t n = (size_t)(newline - p);
        size_t line = n;
        if (line > 0 && p[line - 1] == '\r') {
            line--;
        }
        lua_pushlstring(L, (const char *)p, line);
        stream_consume(c, s, n + 1);
        return 1;
    }
    case READ_ALL:
        lua_pushlstring(L, (const char *)p, available);
        stream_consume(c, s, available);
        return 1;
    case READ_BYTES:
    case READ_SOME: {
        if (available == 0) {
            lua_pushnil(L);
            return 1;
        }
        size_t n = (r->mode == READ_BYTES && available > r->n) ? r->n : available;
        lua_pushlstring(L, (const char *)p, n);
        stream_consume(c, s, n);
        return 1;
    }
    default:
        lua_pushnil(L);
        return 1;
    }
}

/* Data arrived or EOF: wake the reader if its request can now be answered. */
static void stream_notify(ku_child *c, ku_stream *s)
{
    ku_waiter *w = s->reader;
    if (w != NULL && request_ready(s, (const read_request *)w->data)) {
        s->reader = NULL;
        c->woken++;
        ku_wake(w);
    }
}

static int stream_post_read(ku_child *c, ku_stream *s)
{
    if (c->stream && stream_available(s) >= s->limit) {
        s->paused = 1; /* backpressure: the child blocks until the program reads */
        return 0;
    }
    ku_io *io = ku_io_new(c->loop, &c->io_src, s->handle, KU_READ_CHUNK);
    if (io == NULL) {
        stream_finish(s, ERROR_NOT_ENOUGH_MEMORY);
        return -1;
    }
    io->kind = s->kind;
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

/* ---- stdin ------------------------------------------------------------------------ */

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
    if (c->in_handle == NULL || c->in_io != NULL) {
        return;
    }
    if (c->in_off >= c->in_len) {
        c->in_off = 0;
        c->in_len = 0;
        if (c->in_close_pending) {
            stdin_finish(c, 0); /* everything written: EOF for the child */
        }
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

static int stdin_queue(ku_child *c, const unsigned char *bytes, size_t n)
{
    if (c->in_off > 0 && c->in_io == NULL) {
        memmove(c->in_data, c->in_data + c->in_off, c->in_len - c->in_off);
        c->in_len -= c->in_off;
        c->in_off = 0;
    }
    if (c->in_len - c->in_off + n > KU_STDIN_QUEUE_MAX) {
        return -1;
    }
    if (c->in_len + n > c->in_cap) {
        size_t cap = c->in_cap ? c->in_cap : 65536;
        while (cap < c->in_len + n) {
            cap *= 2;
        }
        unsigned char *grown = (unsigned char *)realloc(c->in_data, cap);
        if (grown == NULL) {
            return -1;
        }
        c->in_data = grown;
        c->in_cap = cap;
    }
    memcpy(c->in_data + c->in_len, bytes, n);
    c->in_len += n;
    return 0;
}

/* ---- completions ----------------------------------------------------------------- */

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
        child_maybe_free(c);
        return;
    }
    ku_stream *s = io->kind == IO_OUT ? &c->out : &c->err;
    s->io = NULL;
    if (error == 0) {
        if (bytes > 0) {
            stream_append(c, s, io->buf, bytes);
        }
        ku_io_free(io);
        if (c->closed) {
            stream_finish(s, 0);
        } else {
            stream_post_read(c, s);
        }
    } else {
        ku_io_free(io);
        stream_finish(s, error);
    }
    stream_notify(c, s);
    child_check_done(c);
    child_maybe_free(c);
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
            /* Nobody reads stdin any more: let a pending write go, or close. */
            if (c->in_io != NULL) {
                CancelIoEx(c->in_handle, &c->in_io->ov);
            } else if (c->in_handle != NULL) {
                stdin_finish(c, 0);
            }
            child_check_done(c);
            child_maybe_free(c);
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
    if (c->out.handle != NULL) {
        CloseHandle(c->out.handle);
    }
    if (c->err.handle != NULL) {
        CloseHandle(c->err.handle);
    }
    if (c->in_handle != NULL) {
        CloseHandle(c->in_handle);
    }
    if (c->process != NULL) {
        CloseHandle(c->process);
    }
    if (c->job != NULL) {
        CloseHandle(c->job);
    }
    free(c);
}

/* Free once the Lua side has let go and nothing can still touch `c`: no
 * outstanding I/O, no woken reader, and the job has reported. */
static void child_maybe_free(ku_child *c)
{
    if (c->closed && c->done && c->out.io == NULL && c->err.io == NULL && c->in_io == NULL && c->woken == 0) {
        child_free(c);
    }
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
    if (c->done || !c->job_zero || !c->in_done) {
        return;
    }
    if (!c->stream && !c->inherit && !(c->out.eof && c->err.eof)) {
        return; /* capture mode: the whole output is part of the result */
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
    if (!c->stream) {
        /* Capture mode: the pipes are at EOF; stream mode keeps them for the reader. */
        if (c->out.handle != NULL) {
            CloseHandle(c->out.handle);
            c->out.handle = NULL;
        }
        if (c->err.handle != NULL) {
            CloseHandle(c->err.handle);
            c->err.handle = NULL;
        }
    }
    ku_result *r = (ku_result *)calloc(1, sizeof *r);
    if (r != NULL) {
        r->refs = 1;
        r->status = c->timed_out ? "timeout" : c->killed ? "killed" : "exit";
        r->code = c->exit_code;
        r->pid = c->pid;
        r->elapsed = (double)(ku_now_ms() - c->start_ms) / 1000.0;
        if (!c->stream && !c->inherit) {
            r->out = c->out.data;
            r->out_len = c->out.len;
            r->err = c->err.data;
            r->err_len = c->err.len;
            r->truncated = c->out.truncated || c->err.truncated;
            c->out.data = NULL;
            c->out.len = c->out.cap = c->out.start = 0;
            c->err.data = NULL;
            c->err.len = c->err.cap = c->err.start = 0;
        } else {
            r->out = (unsigned char *)calloc(1, 1);
            r->err = (unsigned char *)calloc(1, 1);
        }
    }
    c->result = r;
    while (c->waiters != NULL) {
        ku_waiter *w = c->waiters;
        c->waiters = w->next;
        w->next = NULL;
        w->data = result_ref(r);
        ku_wake(w);
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

static void wake_reader_closed(ku_child *c, ku_stream *s)
{
    ku_waiter *w = s->reader;
    if (w != NULL) {
        s->reader = NULL;
        ((read_request *)w->data)->mode = READ_CLOSED; /* the push must not touch c */
        c->woken++;
        ku_wake(w);
    }
}

/* The Lua side lets go: kill what runs, cancel what is outstanding, wake
 * parked readers, and free the child now or when its last completion lands. */
static void child_release(ku_child *c)
{
    if (c->closed) {
        return;
    }
    c->closed = 1;
    wake_reader_closed(c, &c->out);
    wake_reader_closed(c, &c->err);
    if (!c->done) {
        child_kill(c);
    }
    if (c->out.io != NULL) {
        CancelIoEx(c->out.handle, &c->out.io->ov);
    }
    if (c->err.io != NULL) {
        CancelIoEx(c->err.handle, &c->err.io->ov);
    }
    if (c->in_io != NULL) {
        CancelIoEx(c->in_handle, &c->in_io->ov);
    }
    child_maybe_free(c);
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
    int stream;
    int inherit;
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
    luaL_checkstack(L, 64, "command arguments");
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
        } else if (strcmp(key, "stream") == 0) {
            spec->stream = lua_toboolean(L, -1);
        } else if (strcmp(key, "inherit") == 0) {
            spec->inherit = lua_toboolean(L, -1);
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
    if (spec->stream && spec->inherit) {
        ku_err_raise(L, "PROC", "usage", "stream and inherit cannot both be set");
    }
    if (spec->inherit && spec->has_stdin) {
        ku_err_raise(L, "PROC", "usage", "inherit gives the child kuu's own stdin; a stdin string cannot be combined with it");
    }
    if (spec->stream && spec->has_stdin) {
        ku_err_raise(L, "PROC", "usage", "in stream mode write to stdin with child:write(); a stdin string cannot be combined with it");
    }
}

/* ---- pipes ---------------------------------------------------------------------- */

static int make_pipe(int inbound, HANDLE *ours, HANDLE *theirs, ku_fail *fail)
{
    static unsigned long long counter;
    wchar_t name[128];
    _snwprintf(name, sizeof name / sizeof name[0], L"\\\\.\\pipe\\kuu.%lu.%llu", (unsigned long)GetCurrentProcessId(),
               ++counter);
    *ours = CreateNamedPipeW(name,
                             (inbound ? PIPE_ACCESS_INBOUND : PIPE_ACCESS_OUTBOUND) | FILE_FLAG_OVERLAPPED |
                                 FILE_FLAG_FIRST_PIPE_INSTANCE,
                             PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536,
                             65536, 0, NULL);
    if (*ours == INVALID_HANDLE_VALUE) {
        *ours = NULL;
        return ku_fail_set(fail, "PROC", "oserror", "cannot create a pipe (error %lu)", (unsigned long)GetLastError());
    }
    *theirs = CreateFileW(name, inbound ? GENERIC_WRITE : GENERIC_READ, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                          NULL);
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
    if (spec->env_count > 0 && ku_env_block(spec->env_count, spec->env_keys, spec->env_values, &env, fail) != 0) {
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
    c->stream = spec->stream;
    c->inherit = spec->inherit;
    c->out.kind = IO_OUT;
    c->err.kind = IO_ERR;
    c->out.limit = spec->maxout;
    c->err.limit = spec->maxout;
    ku_timer_init(&c->deadline, child_deadline, c);

    HANDLE their_in = NULL, their_out = NULL, their_err = NULL, nul = NULL;
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
    if (c->inherit) {
        /* The child gets kuu's own console: colours, pagers, prompts.  A
         * missing standard handle (a GUI parent) falls back to the null
         * device per stream.  Nothing is captured and nothing is written. */
        HANDLE si = GetStdHandle(STD_INPUT_HANDLE), so = GetStdHandle(STD_OUTPUT_HANDLE),
               se = GetStdHandle(STD_ERROR_HANDLE);
        if (si == INVALID_HANDLE_VALUE || si == NULL || so == INVALID_HANDLE_VALUE || so == NULL ||
            se == INVALID_HANDLE_VALUE || se == NULL) {
            nul = ku_open_nul(1);
            if (nul == NULL) {
                ku_fail_set(fail, "PROC", "oserror", "cannot open the null device");
                goto fail;
            }
        }
        their_in = (si != INVALID_HANDLE_VALUE && si != NULL) ? si : nul;
        their_out = (so != INVALID_HANDLE_VALUE && so != NULL) ? so : nul;
        their_err = (se != INVALID_HANDLE_VALUE && se != NULL) ? se : nul;
        c->out.eof = 1;
        c->err.eof = 1;
        c->in_done = 1;
    } else {
        if (make_pipe(1, &c->out.handle, &their_out, fail) != 0 || make_pipe(1, &c->err.handle, &their_err, fail) != 0) {
            goto fail;
        }
        if (spec->has_stdin || c->stream) {
            if (make_pipe(0, &c->in_handle, &their_in, fail) != 0) {
                goto fail;
            }
            if (spec->has_stdin) {
                if (spec->stdin_len > 0 && stdin_queue(c, spec->stdin_data, spec->stdin_len) != 0) {
                    ku_fail_set(fail, "PROC", "oserror", "out of memory");
                    goto fail;
                }
                c->in_close_pending = 1; /* the whole string, then EOF */
            }
        } else {
            nul = ku_open_nul(0);
            if (nul == NULL) {
                ku_fail_set(fail, "PROC", "oserror", "cannot open the null device");
                goto fail;
            }
            their_in = nul;
            c->in_done = 1;
        }
        if (ku_loop_attach(lp, c->out.handle, &c->io_src) != 0 || ku_loop_attach(lp, c->err.handle, &c->io_src) != 0 ||
            (c->in_handle != NULL && ku_loop_attach(lp, c->in_handle, &c->io_src) != 0)) {
            ku_fail_set(fail, "PROC", "oserror", "cannot attach a pipe to the loop (error %lu)",
                        (unsigned long)GetLastError());
            goto fail;
        }
    }
    ku_stdio io = {their_in, their_out, their_err};
    c->start_ms = ku_now_ms();
    if (ku_launch(exe, spec->argc, spec->argv, spec->cwd, c->job, &io, env, &c->pid, &c->process, fail) != 0) {
        goto fail;
    }
    /* From here the child exists: the job is live and will report. */
    ku_loop_expect(lp);
    if (!c->inherit) {
        CloseHandle(their_in == nul ? nul : their_in);
        CloseHandle(their_out);
        CloseHandle(their_err);
        stream_post_read(c, &c->out);
        stream_post_read(c, &c->err);
        if (c->in_handle != NULL) {
            stdin_post(c); /* writes what is queued; an empty queue in stream mode just waits */
        }
    } else if (nul != NULL) {
        CloseHandle(nul);
    }
    if (spec->timeout_ms >= 0) {
        ku_timer_arm(lp, &c->deadline, spec->timeout_ms);
    }
    free(exe);
    free(env);
    *out = c;
    return 0;

fail:
    if (their_in != NULL && their_in != nul && !c->inherit) {
        CloseHandle(their_in);
    }
    if (their_out != NULL && !c->inherit) {
        CloseHandle(their_out);
    }
    if (their_err != NULL && !c->inherit) {
        CloseHandle(their_err);
    }
    if (nul != NULL) {
        CloseHandle(nul);
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

/* ---- wait -------------------------------------------------------------------------- */

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

static void unlink_waiter(ku_waiter **list, ku_waiter *w)
{
    while (*list != NULL) {
        if (*list == w) {
            *list = w->next;
            w->next = NULL;
            return;
        }
        list = &(*list)->next;
    }
}

static void wait_timeout(ku_waiter *w)
{
    unlink_waiter(&((ku_child *)w->owner)->waiters, w);
}

/* Park the caller until the child is complete (or `timeout_ms` passes). */
static int child_wait(lua_State *L, ku_child *c, int64_t timeout_ms)
{
    ku_waiter *w = ku_waiter_new(c->loop, c, wait_push);
    if (w == NULL) {
        return ku_err_raise(L, "PROC", "oserror", "out of memory");
    }
    if (c->done) {
        w->data = result_ref(c->result);
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
    if (spec.stream) {
        return ku_err_raise(L, "PROC", "usage", "stream mode needs proc.start, so the program can read");
    }
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

/* ---- wait_any / wait_all: one coroutine, several children ---------------------------- */

typedef struct multi_wait {
    ku_waiter *main;
    int count;
    int need_all;
    int remaining;     /* children not yet complete */
    int winner;        /* wait_any: the first index that completed, else -1 */
    ku_waiter **subs;  /* per child: a sub-waiter in its list, or NULL when not needed */
    ku_child **children;
    ku_result **results; /* snapshots, filled as children complete */
} multi_wait;

static void multi_sub_woken(ku_waiter *sub)
{
    multi_wait *m = (multi_wait *)sub->tag;
    int index = -1;
    for (int i = 0; i < m->count; i++) {
        if (m->subs[i] == sub) {
            index = i;
            break;
        }
    }
    if (index < 0) {
        result_unref((ku_result *)sub->data);
        return;
    }
    m->results[index] = (ku_result *)sub->data; /* the child's snapshot, already referenced */
    sub->data = NULL;
    m->subs[index] = NULL;
    m->remaining--;
    if (m->winner < 0) {
        m->winner = index;
    }
    if (!m->need_all || m->remaining == 0) {
        ku_wake(m->main);
    }
}

static void multi_cleanup(multi_wait *m)
{
    for (int i = 0; i < m->count; i++) {
        ku_waiter *sub = m->subs[i];
        if (sub != NULL) {
            if (m->children[i] != NULL) {
                unlink_waiter(&m->children[i]->waiters, sub);
            }
            result_unref((ku_result *)sub->data);
            free(sub);
        }
        result_unref(m->results[i]);
    }
    free(m->subs);
    free(m->children);
    free(m->results);
    free(m);
}

static int multi_push(lua_State *L, ku_waiter *w)
{
    multi_wait *m = (multi_wait *)w->tag;
    int n;
    if (w->timed_out) {
        n = ku_err_fail(L, "PROC", "timeout", m->need_all ? "not every child finished in time"
                                                             : "no child finished in time");
    } else if (m->need_all) {
        lua_createtable(L, m->count, 0);
        for (int i = 0; i < m->count; i++) {
            push_result(L, m->results[i]);
            lua_rawseti(L, -2, i + 1);
        }
        n = 1;
    } else {
        lua_rawgeti(L, 1, m->winner + 1); /* the winning child handle, from the array argument */
        push_result(L, m->results[m->winner]);
        n = 2;
    }
    multi_cleanup(m);
    return n;
}

static void multi_timeout(ku_waiter *w)
{
    (void)w; /* the subs are unlinked in multi_cleanup when the push runs */
}

/* Abandoned without a push (a deadlock raised into an in-place wait): the
 * subs must leave their children now, and everything but the main waiter,
 * which the loop frees, goes with them. */
static void multi_abandon(ku_waiter *w)
{
    multi_wait *m = (multi_wait *)w->tag;
    m->main = NULL;
    multi_cleanup(m);
}

static int multi_wait_call(lua_State *L, int need_all)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    int count = (int)lua_rawlen(L, 1);
    if (count < 1) {
        return ku_err_raise(L, "PROC", "usage", "pass an array of at least one child");
    }
    int64_t timeout_ms = -1;
    if (!lua_isnoneornil(L, 2) && ku_check_duration(L, 2, &timeout_ms) != 0) {
        return ku_err_raise(L, "PROC", "badvalue", "the timeout must be a duration such as \"30s\"");
    }
    ku_loop *lp = ku_loop_of(L);
    multi_wait *m = (multi_wait *)calloc(1, sizeof *m);
    if (m == NULL) {
        return ku_err_raise(L, "PROC", "oserror", "out of memory");
    }
    m->count = count;
    m->need_all = need_all;
    m->winner = -1;
    m->subs = (ku_waiter **)calloc((size_t)count, sizeof *m->subs);
    m->children = (ku_child **)calloc((size_t)count, sizeof *m->children);
    m->results = (ku_result **)calloc((size_t)count, sizeof *m->results);
    m->main = ku_waiter_new(lp, NULL, multi_push);
    if (m->subs == NULL || m->children == NULL || m->results == NULL || m->main == NULL) {
        free(m->main);
        multi_cleanup(m);
        return ku_err_raise(L, "PROC", "oserror", "out of memory");
    }
    m->main->tag = m;
    m->main->on_timeout = multi_timeout;
    m->main->on_abandon = multi_abandon;
    for (int i = 0; i < count; i++) {
        lua_rawgeti(L, 1, i + 1);
        ku_child_box *box = (ku_child_box *)luaL_testudata(L, -1, KU_CHILD_META);
        if (box == NULL || box->child == NULL) {
            free(m->main);
            multi_cleanup(m);
            return ku_err_raise(L, "PROC", "usage", "entry %d is not an open child", i + 1);
        }
        lua_pop(L, 1);
        ku_child *c = box->child;
        m->children[i] = c;
        if (c->done) {
            m->results[i] = result_ref(c->result);
            if (m->winner < 0) {
                m->winner = i;
            }
            continue;
        }
        ku_waiter *sub = ku_waiter_new(lp, c, NULL);
        if (sub == NULL) {
            free(m->main);
            multi_cleanup(m);
            return ku_err_raise(L, "PROC", "oserror", "out of memory");
        }
        sub->tag = m;
        sub->on_wake = multi_sub_woken;
        sub->next = c->waiters;
        c->waiters = sub;
        m->subs[i] = sub;
        m->remaining++;
    }
    if ((need_all && m->remaining == 0) || (!need_all && m->winner >= 0)) {
        ku_wake(m->main); /* already satisfied: no parking needed */
        return ku_wait(L, m->main, -1);
    }
    return ku_wait(L, m->main, timeout_ms);
}

static int l_proc_wait_any(lua_State *L)
{
    return multi_wait_call(L, 0);
}

static int l_proc_wait_all(lua_State *L)
{
    return multi_wait_call(L, 1);
}

/* ---- detach / alive / kill ------------------------------------------------------------- */

/* proc.detach{...} -> pid */
static int l_proc_detach(lua_State *L)
{
    ku_spec spec;
    parse_spec(L, &spec, 1);
    if (spec.has_stdin || spec.timeout_ms >= 0 || spec.stream || spec.inherit) {
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

/* ---- child methods ---------------------------------------------------------------------- */

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

/* Reads --------------------------------------------------------------------------------- */

static int read_push(lua_State *L, ku_waiter *w)
{
    read_request *request = (read_request *)w->data;
    ku_child *c = (ku_child *)w->owner;
    int n;
    if (request->mode == READ_CLOSED) {
        c->woken--;
        n = ku_err_fail(L, "PROC", "closed", "the child was closed while reading");
        child_maybe_free(c);
    } else if (w->timed_out) {
        n = ku_err_fail(L, "PROC", "timeout", "nothing to read within the wait");
    } else {
        c->woken--;
        ku_stream *s = (ku_stream *)w->tag;
        n = request_take(L, c, s, request);
    }
    free(request);
    return n;
}

static void read_timeout(ku_waiter *w)
{
    ku_stream *s = (ku_stream *)w->tag;
    if (s->reader == w) {
        s->reader = NULL;
    }
}

/* Abandoned without a push: forget the reader and free the request, which
 * only read_push would have freed. */
static void read_abandon(ku_waiter *w)
{
    read_timeout(w);
    free(w->data);
    w->data = NULL;
}

static int stream_read(lua_State *L, ku_child *c, ku_stream *s, int what_index, int timeout_index)
{
    if (!c->stream) {
        return ku_err_raise(L, "PROC", "usage", "reading needs proc.start{ ..., stream = true }");
    }
    read_request request = {READ_LINE, 0};
    if (!lua_isnoneornil(L, what_index)) {
        if (lua_type(L, what_index) == LUA_TNUMBER) {
            lua_Integer n = luaL_checkinteger(L, what_index);
            if (n < 1) {
                return ku_err_raise(L, "PROC", "badvalue", "read a positive number of bytes");
            }
            request.mode = READ_BYTES;
            request.n = (size_t)n;
        } else {
            const char *what = luaL_checkstring(L, what_index);
            if (strcmp(what, "line") == 0) {
                request.mode = READ_LINE;
            } else if (strcmp(what, "all") == 0) {
                request.mode = READ_ALL;
            } else if (strcmp(what, "some") == 0) {
                request.mode = READ_SOME;
            } else {
                return ku_err_raise(L, "PROC", "badvalue", "read \"line\", \"all\", \"some\", or a byte count");
            }
        }
    }
    int64_t timeout_ms = -1;
    if (!lua_isnoneornil(L, timeout_index) && ku_check_duration(L, timeout_index, &timeout_ms) != 0) {
        return ku_err_raise(L, "PROC", "badvalue", "read timeout must be a duration such as \"30s\"");
    }
    if (s->reader != NULL) {
        return ku_err_raise(L, "PROC", "busy", "another task is already reading this stream");
    }
    if (request_ready(s, &request)) {
        return request_take(L, c, s, &request);
    }
    read_request *heap = (read_request *)malloc(sizeof *heap);
    ku_waiter *w = ku_waiter_new(c->loop, c, read_push);
    if (heap == NULL || w == NULL) {
        free(heap);
        free(w);
        return ku_err_raise(L, "PROC", "oserror", "out of memory");
    }
    *heap = request;
    w->data = heap;
    w->tag = s;
    w->on_timeout = read_timeout;
    w->on_abandon = read_abandon;
    s->reader = w;
    return ku_wait(L, w, timeout_ms);
}

static int l_child_read(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    return stream_read(L, c, &c->out, 2, 3);
}

static int l_child_read_err(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    return stream_read(L, c, &c->err, 2, 3);
}

/* The iterator behind child:lines() / child:err_lines(): reads one line. */
static int lines_step(lua_State *L)
{
    lua_settop(L, 0);
    lua_pushvalue(L, lua_upvalueindex(1)); /* the child */
    ku_child *c = check_child(L, 1);
    ku_stream *s = lua_toboolean(L, lua_upvalueindex(2)) ? &c->err : &c->out;
    lua_pushliteral(L, "line");
    return stream_read(L, c, s, 2, 3);
}

static int l_child_lines(lua_State *L)
{
    check_child(L, 1);
    lua_settop(L, 1);
    lua_pushboolean(L, 0);
    lua_pushcclosure(L, lines_step, 2);
    return 1;
}

static int l_child_err_lines(lua_State *L)
{
    check_child(L, 1);
    lua_settop(L, 1);
    lua_pushboolean(L, 1);
    lua_pushcclosure(L, lines_step, 2);
    return 1;
}

/* child:write(bytes) -> true | nil, err */
static int l_child_write(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    size_t length = 0;
    const char *bytes = luaL_checklstring(L, 2, &length);
    if (!c->stream) {
        return ku_err_raise(L, "PROC", "usage", "writing needs proc.start{ ..., stream = true }");
    }
    if (c->in_handle == NULL || c->in_close_pending) {
        return ku_err_fail(L, "PROC", "closed", "the child's stdin is closed");
    }
    if (stdin_queue(c, (const unsigned char *)bytes, length) != 0) {
        return ku_err_fail(L, "PROC", "toobig", "more than 64 MiB is queued for the child's stdin");
    }
    stdin_post(c);
    lua_pushboolean(L, 1);
    return 1;
}

/* child:close_stdin() -> true */
static int l_child_close_stdin(lua_State *L)
{
    ku_child *c = check_child(L, 1);
    if (c->in_handle != NULL) {
        c->in_close_pending = 1;
        stdin_post(c); /* closes now if nothing is queued or in flight */
        child_check_done(c);
    }
    lua_pushboolean(L, 1);
    return 1;
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
            {"read", l_child_read},
            {"read_err", l_child_read_err},
            {"lines", l_child_lines},
            {"err_lines", l_child_err_lines},
            {"write", l_child_write},
            {"close_stdin", l_child_close_stdin},
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
        {"wait_any", l_proc_wait_any},
        {"wait_all", l_proc_wait_all},
        {"detach", l_proc_detach},
        {"alive", l_proc_alive},
        {"kill", l_proc_kill},
        {"list", ku_proc_list},
        {"find", ku_proc_find},
        {"tree", ku_proc_tree},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
