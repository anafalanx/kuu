/*
 * sched.c -- the `sched` module: tasks and sleep.
 *
 *   local t = sched.spawn(fn, ...)   -- a coroutine the loop runs concurrently
 *   local a, b = t:join("30s")       -- fn's results; re-raises fn's error;
 *                                    -- nil, err SCHED timeout when late
 *   t:status()                       -- "running" | "done" | "failed"
 *   sched.sleep("250ms")             -- park; sleep(0) lets other tasks run
 *
 * Tasks are coroutines, not threads: one runs at a time and they switch only
 * where a palette call waits.  A task stays alive while running even when the
 * program drops its handle; results wait in the task until joined or the task
 * is collected.  The program ends when the main chunk returns, whatever tasks
 * still run.
 */
#include "err.h"
#include "loop.h"
#include "values.h"

#include "lauxlib.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define KU_TASK_META "kuu.task"

enum { TASK_RUNNING = 0, TASK_DONE = 1, TASK_FAILED = 2 };

typedef struct ku_task {
    ku_driver driver;
    ku_loop *loop;
    int state;
    int results_ref; /* a table of results (done) or the error object (failed) */
    int nresults;
    int live_ref; /* keeps the userdata alive while the task runs */
    ku_waiter *joiners;
} ku_task;

static ku_task *check_task(lua_State *L, int idx)
{
    return (ku_task *)luaL_checkudata(L, idx, KU_TASK_META);
}

static void task_unlink(ku_task *t, ku_waiter *w)
{
    ku_waiter **link = &t->joiners;
    while (*link != NULL) {
        if (*link == w) {
            *link = w->next;
            w->next = NULL;
            return;
        }
        link = &(*link)->next;
    }
}

static void task_finished(ku_driver *driver, int nresults)
{
    ku_task *t = (ku_task *)driver->owner;
    lua_State *L = ku_loop_state(t->loop);
    lua_State *co = driver->co;
    if (driver->status == LUA_OK) {
        lua_createtable(L, nresults, 0);
        int table = lua_gettop(L);
        luaL_checkstack(L, nresults + 1, "task results");
        lua_xmove(co, L, nresults);
        for (int i = nresults; i >= 1; i--) {
            lua_rawseti(L, table, i);
        }
        t->nresults = nresults;
        t->state = TASK_DONE;
    } else {
        lua_xmove(co, L, 1);
        t->state = TASK_FAILED;
    }
    t->results_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_closethread(co, L); /* pending <close> variables of the task */
    luaL_unref(L, LUA_REGISTRYINDEX, driver->ref);
    driver->ref = LUA_NOREF;
    driver->co = NULL;

    while (t->joiners != NULL) {
        ku_waiter *w = t->joiners;
        t->joiners = w->next;
        w->next = NULL;
        lua_rawgeti(L, LUA_REGISTRYINDEX, t->results_ref);
        w->data_ref = luaL_ref(L, LUA_REGISTRYINDEX); /* the waiter's own reference */
        w->data = (void *)(intptr_t)(t->state == TASK_FAILED ? -1 : t->nresults);
        ku_wake(w);
    }
    luaL_unref(L, LUA_REGISTRYINDEX, t->live_ref);
    t->live_ref = LUA_NOREF;
}

/* sched.spawn(fn, ...) */
static int l_sched_spawn(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TFUNCTION);
    int nargs = lua_gettop(L) - 1;
    ku_loop *lp = ku_loop_of(L);
    ku_task *t = (ku_task *)lua_newuserdatauv(L, sizeof *t, 0);
    memset(t, 0, sizeof *t);
    t->loop = lp;
    t->results_ref = LUA_NOREF;
    t->live_ref = LUA_NOREF;
    t->driver.owner = t;
    t->driver.on_finish = task_finished;
    t->driver.ref = LUA_NOREF;
    luaL_setmetatable(L, KU_TASK_META);
    int task_index = lua_gettop(L);

    lua_State *co = lua_newthread(L);
    luaL_checkstack(co, nargs + 1, "task arguments");
    for (int i = 1; i <= nargs + 1; i++) {
        lua_pushvalue(L, i);
    }
    lua_xmove(L, co, nargs + 1);
    if (ku_driver_start(lp, &t->driver, co, nargs) != 0) {
        return ku_err_raise(L, "SCHED", "oserror", "out of memory starting a task");
    }
    lua_pop(L, 1); /* the thread: the driver holds a reference */
    lua_pushvalue(L, task_index);
    t->live_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    return 1;
}

static int join_push(lua_State *L, ku_waiter *w)
{
    if (w->timed_out) {
        return ku_err_fail(L, "SCHED", "timeout", "join timed out");
    }
    int n = (int)(intptr_t)w->data;
    lua_rawgeti(L, LUA_REGISTRYINDEX, w->data_ref);
    if (n < 0) {
        w->raise = 1; /* the task's error object, re-raised in the joiner */
        return 1;
    }
    if (lua_type(L, -1) != LUA_TTABLE) {
        return luaL_error(L, "kuu internal: task results are missing");
    }
    int table = lua_gettop(L);
    luaL_checkstack(L, n + 1, "task results");
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, table, i);
    }
    lua_remove(L, table);
    return n;
}

static void join_timeout(ku_waiter *w)
{
    task_unlink((ku_task *)w->owner, w);
}

/* task:join([timeout]) */
static int l_task_join(lua_State *L)
{
    ku_task *t = check_task(L, 1);
    int64_t timeout_ms = -1;
    if (!lua_isnoneornil(L, 2) && ku_check_duration(L, 2, &timeout_ms) != 0) {
        return ku_err_raise(L, "SCHED", "badvalue", "join timeout must be a duration such as \"30s\"");
    }
    ku_waiter *w = ku_waiter_new(t->loop, t, join_push);
    if (w == NULL) {
        return ku_err_raise(L, "SCHED", "oserror", "out of memory");
    }
    if (t->state != TASK_RUNNING) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, t->results_ref);
        w->data_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        w->data = (void *)(intptr_t)(t->state == TASK_FAILED ? -1 : t->nresults);
        ku_wake(w);
        timeout_ms = -1;
    } else {
        w->on_timeout = join_timeout;
        w->next = t->joiners;
        t->joiners = w;
    }
    return ku_wait(L, w, timeout_ms);
}

static int l_task_status(lua_State *L)
{
    ku_task *t = check_task(L, 1);
    lua_pushstring(L, t->state == TASK_RUNNING ? "running" : t->state == TASK_DONE ? "done" : "failed");
    return 1;
}

static int l_task_gc(lua_State *L)
{
    ku_task *t = check_task(L, 1);
    if (t->results_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, t->results_ref);
        t->results_ref = LUA_NOREF;
    }
    return 0;
}

static int l_task_tostring(lua_State *L)
{
    ku_task *t = check_task(L, 1);
    lua_pushfstring(L, "kuu.task (%s)",
                    t->state == TASK_RUNNING ? "running" : t->state == TASK_DONE ? "done" : "failed");
    return 1;
}

static int sleep_push(lua_State *L, ku_waiter *w)
{
    (void)L;
    (void)w;
    return 0;
}

/* sched.sleep(duration) */
static int l_sched_sleep(lua_State *L)
{
    int64_t ms = 0;
    if (ku_check_duration(L, 1, &ms) != 0) {
        return ku_err_raise(L, "SCHED", "badvalue", "sleep needs a duration such as \"250ms\"");
    }
    ku_waiter *w = ku_waiter_new(ku_loop_of(L), NULL, sleep_push);
    if (w == NULL) {
        return ku_err_raise(L, "SCHED", "oserror", "out of memory");
    }
    return ku_wait(L, w, ms);
}

/* sched.clock() -> monotonic seconds, for measuring; not wall time */
static int l_sched_clock(lua_State *L)
{
    lua_pushnumber(L, (lua_Number)ku_now_ms() / 1000.0);
    return 1;
}

/* sched.now() -> wall-clock seconds since the Unix epoch, sub-millisecond */
static int l_sched_now(lua_State *L)
{
    FILETIME ft;
    GetSystemTimePreciseAsFileTime(&ft);
    long long ticks = ((long long)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    lua_pushnumber(L, (lua_Number)(ticks - 116444736000000000LL) / 10000000.0);
    return 1;
}

int ku_open_sched(lua_State *L)
{
    if (luaL_newmetatable(L, KU_TASK_META)) {
        static const luaL_Reg methods[] = {
            {"join", l_task_join},
            {"status", l_task_status},
            {NULL, NULL},
        };
        luaL_newlib(L, methods);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_task_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, l_task_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
    static const luaL_Reg functions[] = {
        {"spawn", l_sched_spawn},
        {"sleep", l_sched_sleep},
        {"clock", l_sched_clock},
        {"now", l_sched_now},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
