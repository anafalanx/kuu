/*
 * sync.c -- the `sync` module: one at a time, across processes.
 *
 *   sync.try(name)   -> lock | nil, err (SYNC busy)   acquire now or not at all
 *   lock:release()   -> true                          idempotent; also on <close> and collection
 *   lock.abandoned   -> true when the previous holder died without releasing
 *
 * A named Windows mutex in the Local namespace, so two kuu processes on one
 * machine take turns.  When a holder dies the kernel hands the mutex over as
 * abandoned, but only to a process that still has a handle to the same
 * object: a mutex whose last handle closes is simply gone, and the next
 * taker would get a fresh one that was never abandoned.  So this process
 * keeps one handle per name open for as long as it lives, and locks borrow
 * it.  A Windows mutex is also recursive for the thread that owns it, and
 * all of kuu is one thread, so the module remembers which names it holds and
 * refuses a second acquisition: a lock is exclusive, never re-entrant.  The
 * wait with a timeout, `sync.lock(name, timeout)`, is Lua on top of `try`
 * (lua/sync/wait.lua) so that it sleeps on the loop and other tasks run.
 */
#include "err.h"
#include "state.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

#define KU_LOCK_META "kuu.lock"
#define KU_MUTEX_META "kuu.sync.mutex"
#define KU_LOCK_HELD "kuu.sync.held"     /* registry: name -> the lock this process holds */
#define KU_LOCK_HANDLES "kuu.sync.handles" /* registry: name -> the open mutex handle */
#define KU_LOCK_NAME_MAX 200

typedef struct ku_mutex {
    HANDLE handle;
} ku_mutex;

typedef struct ku_lock {
    HANDLE mutex; /* borrowed from the handle table; never closed here */
    char *name;
    int held;
} ku_lock;

static int mutex_gc(lua_State *L)
{
    ku_mutex *m = (ku_mutex *)luaL_checkudata(L, 1, KU_MUTEX_META);
    if (m->handle != NULL) {
        CloseHandle(m->handle);
        m->handle = NULL;
    }
    return 0;
}

/* The process-wide handle for `name`, opened on first use and kept.  NULL
 * with GetLastError set when it cannot be opened. */
static HANDLE mutex_for(lua_State *L, const char *name)
{
    lua_getfield(L, LUA_REGISTRYINDEX, KU_LOCK_HANDLES);
    lua_getfield(L, -1, name);
    ku_mutex *known = (ku_mutex *)luaL_testudata(L, -1, KU_MUTEX_META);
    if (known != NULL && known->handle != NULL) {
        HANDLE h = known->handle;
        lua_pop(L, 2);
        return h;
    }
    lua_pop(L, 1);
    wchar_t *wide = ku_utf8_to_wide(name);
    if (wide == NULL) {
        lua_pop(L, 1);
        SetLastError(ERROR_NO_UNICODE_TRANSLATION);
        return NULL;
    }
    static const wchar_t prefix[] = L"Local\\kuu.";
    wchar_t *full = (wchar_t *)malloc((wcslen(prefix) + wcslen(wide) + 1) * sizeof(wchar_t));
    if (full == NULL) {
        free(wide);
        lua_pop(L, 1);
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return NULL;
    }
    wcscpy(full, prefix);
    wcscat(full, wide);
    free(wide);
    HANDLE h = CreateMutexW(NULL, FALSE, full);
    DWORD error = h == NULL ? GetLastError() : 0;
    free(full);
    if (h == NULL) {
        lua_pop(L, 1);
        SetLastError(error);
        return NULL;
    }
    ku_mutex *m = (ku_mutex *)lua_newuserdatauv(L, sizeof *m, 0);
    m->handle = h;
    luaL_setmetatable(L, KU_MUTEX_META);
    lua_setfield(L, -2, name);
    lua_pop(L, 1);
    return h;
}

/* Forget `lock` in the held table, if it is the one recorded there. */
static void forget_held(lua_State *L, ku_lock *lock, int lock_index)
{
    lua_getfield(L, LUA_REGISTRYINDEX, KU_LOCK_HELD);
    lua_getfield(L, -1, lock->name);
    int mine = lua_rawequal(L, -1, lock_index);
    lua_pop(L, 1);
    if (mine) {
        lua_pushnil(L);
        lua_setfield(L, -2, lock->name);
    }
    lua_pop(L, 1);
}

static int lock_release(lua_State *L)
{
    ku_lock *lock = (ku_lock *)luaL_checkudata(L, 1, KU_LOCK_META);
    if (lock->held) {
        forget_held(L, lock, 1);
        ReleaseMutex(lock->mutex);
        lock->held = 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int lock_gc(lua_State *L)
{
    ku_lock *lock = (ku_lock *)luaL_checkudata(L, 1, KU_LOCK_META);
    lock_release(L);
    free(lock->name);
    lock->name = NULL;
    return 0;
}

static int lock_tostring(lua_State *L)
{
    ku_lock *lock = (ku_lock *)luaL_checkudata(L, 1, KU_LOCK_META);
    lua_pushfstring(L, "kuu.lock (%s)", lock->held ? "held" : "released");
    return 1;
}

static int lock_index(lua_State *L)
{
    const char *key = luaL_checkstring(L, 2);
    if (strcmp(key, "abandoned") == 0) {
        lua_getiuservalue(L, 1, 1);
        return 1;
    }
    if (strcmp(key, "release") == 0) {
        lua_pushcfunction(L, lock_release);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

/* sync.try(name) -> lock | nil, err */
static int l_sync_try(lua_State *L)
{
    size_t length = 0;
    const char *name = luaL_checklstring(L, 1, &length);
    if (length == 0 || length > KU_LOCK_NAME_MAX) {
        return ku_err_raise(L, "SYNC", "badvalue", "a lock name is 1 to %d bytes", KU_LOCK_NAME_MAX);
    }
    for (size_t i = 0; i < length; i++) {
        if (name[i] == '\\' || (unsigned char)name[i] < 0x20) {
            return ku_err_raise(L, "SYNC", "badvalue", "a lock name has no backslash and no control character");
        }
    }
    /* exclusive within this process too */
    lua_getfield(L, LUA_REGISTRYINDEX, KU_LOCK_HELD);
    lua_getfield(L, -1, name);
    ku_lock *holder = (ku_lock *)luaL_testudata(L, -1, KU_LOCK_META);
    lua_pop(L, 2);
    if (holder != NULL && holder->held) {
        return ku_err_fail(L, "SYNC", "busy", "'%s' is already held by this process", name);
    }
    HANDLE mutex = mutex_for(L, name);
    if (mutex == NULL) {
        DWORD error = GetLastError();
        if (error == ERROR_NO_UNICODE_TRANSLATION) {
            return ku_err_raise(L, "SYNC", "encoding", "the lock name is not valid UTF-8");
        }
        char *text = ku_win_error_message(error);
        int n = ku_err_raise(L, "SYNC", "oserror", "cannot open the lock '%s': %s", name, text != NULL ? text : "");
        free(text);
        return n;
    }
    DWORD waited = WaitForSingleObject(mutex, 0);
    if (waited != WAIT_OBJECT_0 && waited != WAIT_ABANDONED) {
        if (waited == WAIT_TIMEOUT) {
            return ku_err_fail(L, "SYNC", "busy", "'%s' is held elsewhere", name);
        }
        return ku_err_raise(L, "SYNC", "oserror", "waiting for the lock '%s' failed", name);
    }
    ku_lock *lock = (ku_lock *)lua_newuserdatauv(L, sizeof *lock, 1);
    lock->mutex = mutex;
    lock->held = 1;
    lock->name = _strdup(name);
    luaL_setmetatable(L, KU_LOCK_META);
    lua_pushboolean(L, waited == WAIT_ABANDONED);
    lua_setiuservalue(L, -2, 1);
    if (lock->name == NULL) {
        ReleaseMutex(mutex);
        lock->held = 0;
        return ku_err_raise(L, "SYNC", "oserror", "out of memory");
    }
    lua_getfield(L, LUA_REGISTRYINDEX, KU_LOCK_HELD);
    lua_pushvalue(L, -2);
    lua_setfield(L, -2, name);
    lua_pop(L, 1);
    return 1;
}

int ku_open_sync(lua_State *L)
{
    if (luaL_newmetatable(L, KU_LOCK_META)) {
        lua_pushcfunction(L, lock_index);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, lock_release);
        lua_setfield(L, -2, "__close");
        lua_pushcfunction(L, lock_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, lock_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
    if (luaL_newmetatable(L, KU_MUTEX_META)) {
        lua_pushcfunction(L, mutex_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    static const char *const tables[] = {KU_LOCK_HELD, KU_LOCK_HANDLES, NULL};
    for (int i = 0; tables[i] != NULL; i++) {
        lua_getfield(L, LUA_REGISTRYINDEX, tables[i]);
        if (lua_isnil(L, -1)) {
            lua_newtable(L);
            lua_setfield(L, LUA_REGISTRYINDEX, tables[i]);
        }
        lua_pop(L, 1);
    }
    static const luaL_Reg functions[] = {
        {"try", l_sync_try},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
