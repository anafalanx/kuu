/*
 * fs_watch.c -- `fs.watch`: directory change notification on the loop.
 *
 *   local w <close> = fs.watch("C:/work/src", { recursive = true })
 *   local events, e = w:read("30s")   -- { {action=, path=, from=}, ... } | nil, FS timeout
 *   w:info()                          -- { directory, recursive, pending, dropped }
 *   w:close()
 *
 * ReadDirectoryChangesW is posted on the completion port and re-posted as
 * each batch arrives, so no thread is needed and nothing is missed between
 * batches.  The first read is issued before `watch` returns: until it is,
 * the OS records nothing.  Zero bytes returned means the OS buffer overflowed
 * and changes happened it could not describe; that is an event, `overflow`,
 * never silence.  Events queue up to 8192; beyond that they are counted as
 * dropped rather than allowed to exhaust memory.  Paths are relative to the
 * watched directory with forward slashes.  Unless `raw = true`, a read
 * coalesces one batch per path with precedence removed, added, renamed,
 * modified, and a rename pair becomes one `renamed` event with `from`.
 * A watch is a trigger: after `overflow` or `dropped`, reconcile from a scan.
 */
#include "err.h"
#include "fs_internal.h"
#include "loop.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#include <stdlib.h>
#include <string.h>

#define KU_WATCH_META "kuu.watch"
#define KU_WATCH_BUFFER 65536
#define KU_WATCH_QUEUE_MAX 8192

enum { ACT_ADDED = 1, ACT_REMOVED = 2, ACT_MODIFIED = 3, ACT_RENAMED = 4, ACT_OVERFLOW = 5 };

typedef struct watch_event {
    int action;
    char *path; /* UTF-8, relative, forward slashes */
    char *from; /* the old name of a rename, else NULL */
} watch_event;

typedef struct ku_watch {
    ku_source src;
    ku_loop *loop;
    HANDLE dir;
    ku_io *io;
    char *directory;      /* as given, for info */
    int recursive, raw;
    watch_event *events;
    size_t count, capacity;
    int dropped;
    int closed;           /* the Lua side let go */
    int stopped;          /* no read outstanding, none will be posted */
    DWORD error;          /* a failure that ended the watch */
    char *pending_old;    /* a RENAMED_OLD_NAME waiting for its NEW_NAME */
    ku_waiter *waiters;
    int woken;            /* readers woken but not yet resumed: they still hold `w` */
} ku_watch;

static void event_free(watch_event *e)
{
    free(e->path);
    free(e->from);
}

static void watch_free(ku_watch *w)
{
    while (w->waiters != NULL) {
        ku_waiter *waiter = w->waiters;
        w->waiters = waiter->next;
        free(waiter);
    }
    for (size_t i = 0; i < w->count; i++) {
        event_free(&w->events[i]);
    }
    free(w->events);
    free(w->directory);
    free(w->pending_old);
    if (w->dir != NULL) {
        CloseHandle(w->dir);
    }
    free(w);
}

static void wake_all(ku_watch *w)
{
    while (w->waiters != NULL) {
        ku_waiter *waiter = w->waiters;
        w->waiters = waiter->next;
        waiter->next = NULL;
        waiter->data = w;
        w->woken++;
        ku_wake(waiter);
    }
}

/* The watch is freed by whoever lets go of it last: the Lua handle, the
 * outstanding read's completion, or the last woken reader. */
static void watch_maybe_free(ku_watch *w)
{
    if (w->closed && w->io == NULL && w->woken == 0) {
        watch_free(w);
    }
}

static void push_event(ku_watch *w, int action, char *path, char *from)
{
    if (w->count >= KU_WATCH_QUEUE_MAX) {
        w->dropped++;
        free(path);
        free(from);
        return;
    }
    if (w->count == w->capacity) {
        size_t next = w->capacity ? w->capacity * 2 : 64;
        watch_event *grown = (watch_event *)realloc(w->events, next * sizeof *grown);
        if (grown == NULL) {
            w->dropped++;
            free(path);
            free(from);
            return;
        }
        w->events = grown;
        w->capacity = next;
    }
    /* every field, explicitly: realloc leaves garbage */
    w->events[w->count].action = action;
    w->events[w->count].path = path;
    w->events[w->count].from = from;
    w->count++;
}

static int post_read(ku_watch *w)
{
    ku_io *io = ku_io_new(w->loop, &w->src, w->dir, KU_WATCH_BUFFER);
    if (io == NULL) {
        w->error = ERROR_NOT_ENOUGH_MEMORY;
        w->stopped = 1;
        return -1;
    }
    w->io = io;
    const DWORD filter = FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_LAST_WRITE |
                         FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_CREATION;
    if (!ReadDirectoryChangesW(w->dir, io->buf, io->cap, w->recursive, filter, NULL, &io->ov, NULL)) {
        DWORD error = GetLastError();
        if (error != ERROR_IO_PENDING) {
            w->io = NULL;
            ku_io_free(io);
            w->error = error;
            w->stopped = 1;
            return -1;
        }
    }
    ku_io_posted(io);
    return 0;
}

static char *relative_utf8(const wchar_t *name, size_t units)
{
    char *utf8 = ku_wide_to_utf8(name, (int)units);
    if (utf8 == NULL) {
        return NULL;
    }
    for (char *c = utf8; *c; c++) {
        if (*c == '\\') {
            *c = '/';
        }
    }
    return utf8;
}

static void parse_batch(ku_watch *w, const unsigned char *buffer, DWORD bytes)
{
    if (bytes == 0) {
        push_event(w, ACT_OVERFLOW, _strdup(""), NULL); /* the OS could not describe what happened */
        w->dropped++;
        return;
    }
    size_t offset = 0;
    for (;;) {
        if (offset + offsetof(FILE_NOTIFY_INFORMATION, FileName) > bytes) {
            break;
        }
        const FILE_NOTIFY_INFORMATION *info = (const FILE_NOTIFY_INFORMATION *)(buffer + offset);
        if (info->FileNameLength % sizeof(wchar_t) != 0 ||
            offset + offsetof(FILE_NOTIFY_INFORMATION, FileName) + info->FileNameLength > bytes) {
            w->dropped++; /* a malformed record: counted, not walked into */
            break;
        }
        char *path = relative_utf8(info->FileName, info->FileNameLength / sizeof(wchar_t));
        if (path == NULL) {
            w->dropped++;
        } else {
            switch (info->Action) {
            case FILE_ACTION_ADDED:
                push_event(w, ACT_ADDED, path, NULL);
                break;
            case FILE_ACTION_REMOVED:
                push_event(w, ACT_REMOVED, path, NULL);
                break;
            case FILE_ACTION_MODIFIED:
                push_event(w, ACT_MODIFIED, path, NULL);
                break;
            case FILE_ACTION_RENAMED_OLD_NAME:
                free(w->pending_old);
                w->pending_old = path;
                break;
            case FILE_ACTION_RENAMED_NEW_NAME:
                push_event(w, ACT_RENAMED, path, w->pending_old);
                w->pending_old = NULL;
                break;
            default:
                free(path);
                break;
            }
        }
        if (info->NextEntryOffset == 0) {
            break;
        }
        size_t used = offsetof(FILE_NOTIFY_INFORMATION, FileName) + info->FileNameLength;
        if (info->NextEntryOffset < used || info->NextEntryOffset % sizeof(DWORD) != 0 ||
            info->NextEntryOffset > bytes - offset) {
            w->dropped++;
            break;
        }
        offset += info->NextEntryOffset;
    }
}

static void watch_on_io(ku_source *src, ku_io *io, DWORD bytes, DWORD error)
{
    ku_watch *w = (ku_watch *)src->owner;
    w->io = NULL;
    if (w->closed) {
        ku_io_free(io);
        w->stopped = 1;
        watch_maybe_free(w);
        return;
    }
    if (error != 0) {
        ku_io_free(io);
        w->error = error;
        w->stopped = 1;
        wake_all(w);
        return;
    }
    parse_batch(w, io->buf, bytes);
    ku_io_free(io);
    post_read(w);
    if (w->count > 0 || w->stopped) {
        wake_all(w);
    }
}

/* ---- the userdata ---------------------------------------------------------------- */

typedef struct watch_box {
    ku_watch *watch;
} watch_box;

static watch_box *check_box(lua_State *L, int idx)
{
    return (watch_box *)luaL_checkudata(L, idx, KU_WATCH_META);
}

static ku_watch *check_watch(lua_State *L, int idx)
{
    watch_box *box = check_box(L, idx);
    if (box->watch == NULL) {
        ku_err_raise(L, "FS", "closed", "the watch has been closed");
    }
    return box->watch;
}

static const char *action_name(int action)
{
    switch (action) {
    case ACT_ADDED:
        return "added";
    case ACT_REMOVED:
        return "removed";
    case ACT_MODIFIED:
        return "modified";
    case ACT_RENAMED:
        return "renamed";
    default:
        return "overflow";
    }
}

/* Precedence when one path saw several actions in a batch. */
static int rank(int action)
{
    switch (action) {
    case ACT_OVERFLOW:
        return 5;
    case ACT_REMOVED:
        return 4;
    case ACT_ADDED:
        return 3;
    case ACT_RENAMED:
        return 2;
    default:
        return 1;
    }
}

static void push_event_table(lua_State *L, const watch_event *e)
{
    lua_createtable(L, 0, 3);
    lua_pushstring(L, action_name(e->action));
    lua_setfield(L, -2, "action");
    lua_pushstring(L, e->path != NULL ? e->path : "");
    lua_setfield(L, -2, "path");
    if (e->from != NULL) {
        lua_pushstring(L, e->from);
        lua_setfield(L, -2, "from");
    }
}

/* Move the queued events into a Lua array, coalescing unless raw. */
static void drain_events(lua_State *L, ku_watch *w)
{
    lua_createtable(L, (int)w->count, 0);
    lua_Integer n = 0;
    if (w->raw) {
        for (size_t i = 0; i < w->count; i++) {
            push_event_table(L, &w->events[i]);
            lua_rawseti(L, -2, ++n);
            event_free(&w->events[i]);
        }
        w->count = 0;
        return;
    }
    /* Coalesce: the first event for a path keeps its position; a later event
     * on the same path replaces the action when its rank is higher, and a
     * rename's `from` is kept.  Rank order is a decision from observations,
     * never last-wins. */
    for (size_t i = 0; i < w->count; i++) {
        watch_event *e = &w->events[i];
        if (e->path == NULL) {
            continue;
        }
        for (size_t j = 0; j < i; j++) {
            watch_event *earlier = &w->events[j];
            if (earlier->path != NULL && strcmp(earlier->path, e->path) == 0) {
                if (rank(e->action) > rank(earlier->action)) {
                    earlier->action = e->action;
                }
                if (e->from != NULL && earlier->from == NULL) {
                    earlier->from = e->from;
                    e->from = NULL;
                }
                free(e->path);
                e->path = NULL; /* merged away */
                break;
            }
        }
    }
    for (size_t i = 0; i < w->count; i++) {
        if (w->events[i].path != NULL) {
            push_event_table(L, &w->events[i]);
            lua_rawseti(L, -2, ++n);
        }
        event_free(&w->events[i]);
    }
    w->count = 0;
}

static int read_push(lua_State *L, ku_waiter *waiter)
{
    ku_watch *w = (ku_watch *)waiter->owner;
    int n;
    if (waiter->timed_out) {
        n = ku_err_fail(L, "FS", "timeout", "no changes within the wait");
        return n; /* removed from the list by read_timeout; never woken */
    }
    w->woken--;
    if (w->closed) {
        n = ku_err_fail(L, "FS", "closed", "the watch was closed while waiting");
    } else if (w->count > 0) {
        drain_events(L, w);
        n = 1;
    } else if (w->stopped) {
        char *text = ku_win_error_message(w->error);
        n = ku_err_fail(L, "FS", "oserror", "the watch stopped: %s", text != NULL ? text : "unknown error");
        free(text);
    } else {
        n = ku_err_fail(L, "FS", "oserror", "the watch woke without events"); /* should not happen */
    }
    watch_maybe_free(w);
    return n;
}

static void read_timeout(ku_waiter *waiter)
{
    ku_watch *w = (ku_watch *)waiter->owner;
    ku_waiter **link = &w->waiters;
    while (*link != NULL) {
        if (*link == waiter) {
            *link = waiter->next;
            waiter->next = NULL;
            return;
        }
        link = &(*link)->next;
    }
}

/* watch:read([timeout]) */
static int l_watch_read(lua_State *L)
{
    ku_watch *w = check_watch(L, 1);
    int64_t timeout_ms = -1;
    if (!lua_isnoneornil(L, 2) && ku_check_duration(L, 2, &timeout_ms) != 0) {
        return ku_err_raise(L, "FS", "badvalue", "read timeout must be a duration such as \"30s\"");
    }
    if (w->count > 0) {
        drain_events(L, w);
        return 1;
    }
    if (w->stopped) {
        char *text = ku_win_error_message(w->error);
        int n = ku_err_fail(L, "FS", "oserror", "the watch stopped: %s", text != NULL ? text : "unknown error");
        free(text);
        return n;
    }
    ku_waiter *waiter = ku_waiter_new(w->loop, w, read_push);
    if (waiter == NULL) {
        return ku_err_raise(L, "FS", "oserror", "out of memory");
    }
    waiter->on_timeout = read_timeout;
    waiter->next = w->waiters;
    w->waiters = waiter;
    return ku_wait(L, waiter, timeout_ms);
}

static int l_watch_info(lua_State *L)
{
    ku_watch *w = check_watch(L, 1);
    lua_createtable(L, 0, 5);
    lua_pushstring(L, w->directory);
    lua_setfield(L, -2, "directory");
    lua_pushboolean(L, w->recursive);
    lua_setfield(L, -2, "recursive");
    lua_pushinteger(L, (lua_Integer)w->count);
    lua_setfield(L, -2, "pending");
    lua_pushinteger(L, w->dropped);
    lua_setfield(L, -2, "dropped");
    lua_pushboolean(L, !w->stopped);
    lua_setfield(L, -2, "armed");
    return 1;
}

static void watch_release(ku_watch *w)
{
    if (w->closed) {
        return;
    }
    w->closed = 1;
    w->stopped = 1;
    if (w->error == 0) {
        w->error = ERROR_OPERATION_ABORTED;
    }
    wake_all(w); /* parked readers wake and find it closed */
    if (w->io != NULL) {
        CancelIoEx(w->dir, &w->io->ov); /* the completion lets go of the read */
    }
    watch_maybe_free(w);
}

static int l_watch_close(lua_State *L)
{
    watch_box *box = check_box(L, 1);
    if (box->watch != NULL) {
        watch_release(box->watch);
        box->watch = NULL;
    }
    return 0;
}

static int l_watch_tostring(lua_State *L)
{
    watch_box *box = check_box(L, 1);
    if (box->watch == NULL) {
        lua_pushliteral(L, "kuu.watch (closed)");
    } else {
        lua_pushfstring(L, "kuu.watch %s", box->watch->directory);
    }
    return 1;
}

void ku_fs_watch_meta(lua_State *L)
{
    if (luaL_newmetatable(L, KU_WATCH_META)) {
        static const luaL_Reg methods[] = {
            {"read", l_watch_read},
            {"info", l_watch_info},
            {"close", l_watch_close},
            {NULL, NULL},
        };
        luaL_newlib(L, methods);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_watch_close);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, l_watch_close);
        lua_setfield(L, -2, "__close");
        lua_pushcfunction(L, l_watch_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
}

/* fs.watch(dir [, { recursive = true, raw = false }]) */
int ku_fs_watch(lua_State *L)
{
    const char *shown = luaL_checkstring(L, 1);
    int recursive = 1, raw = 0;
    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        lua_pushnil(L);
        while (lua_next(L, 2) != 0) {
            const char *key = lua_type(L, -2) == LUA_TSTRING ? lua_tostring(L, -2) : "?";
            if (strcmp(key, "recursive") == 0) {
                recursive = lua_toboolean(L, -1);
            } else if (strcmp(key, "raw") == 0) {
                raw = lua_toboolean(L, -1);
            } else {
                return ku_err_raise(L, "FS", "usage", "unknown option '%s'", key);
            }
            lua_pop(L, 1);
        }
    }
    ku_wpath path;
    ku_fail fail;
    if (ku_wpath_make(shown, &path, &fail) != 0) {
        return ku_err_raise(L, fail.domain, fail.code, "%s", fail.message);
    }
    HANDLE dir = CreateFileW(path.text, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                             NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
    ku_wpath_free(&path);
    if (dir == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        ku_fs_fail(&fail, error, "watch", shown);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    ku_watch *w = (ku_watch *)calloc(1, sizeof *w);
    if (w == NULL) {
        CloseHandle(dir);
        return ku_err_raise(L, "FS", "oserror", "out of memory");
    }
    w->loop = ku_loop_of(L);
    w->src.kind = KU_SRC_IO;
    w->src.owner = w;
    w->src.on_io = watch_on_io;
    w->dir = dir;
    w->recursive = recursive;
    w->raw = raw;
    w->directory = _strdup(shown);
    if (ku_loop_attach(w->loop, dir, &w->src) != 0) {
        DWORD error = GetLastError();
        watch_free(w);
        ku_fs_fail(&fail, error, "watch", shown);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    /* Armed before we return: a directory that cannot be watched fails here,
     * by name, instead of turning into permanent silence. */
    if (post_read(w) != 0) {
        DWORD error = w->error;
        watch_free(w);
        ku_fs_fail(&fail, error, "watch", shown);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    watch_box *box = (watch_box *)lua_newuserdatauv(L, sizeof *box, 0);
    box->watch = w;
    luaL_setmetatable(L, KU_WATCH_META);
    return 1;
}
