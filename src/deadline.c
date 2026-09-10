/* Coroutine-local, nested deadline scopes. Lua owns every scope and token. */
#include "deadline.h"
#include "err.h"
#include "loop.h"
#include "values.h"
#include "lauxlib.h"

#define DEADLINE_KEY "kuu.deadlines"
#define DEADLINE_META "kuu.deadline"

typedef struct deadline_scope {
    int64_t due_ms; /* the earliest enclosing deadline, including this one */
    int active;
} deadline_scope;

static void push_scopes(lua_State *L)
{
    lua_getfield(L, LUA_REGISTRYINDEX, DEADLINE_KEY);
    if (!lua_isnil(L, -1)) {
        return;
    }
    lua_pop(L, 1);
    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "k");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_pushvalue(L, -1);
    lua_setfield(L, LUA_REGISTRYINDEX, DEADLINE_KEY);
}

static int scope_close(lua_State *L)
{
    deadline_scope *scope = luaL_checkudata(L, 1, DEADLINE_META);
    if (scope->active) {
        push_scopes(L);
        int scopes = lua_gettop(L);
        lua_getiuservalue(L, 1, 3); /* owner coroutine */
        lua_pushvalue(L, -1);
        lua_rawget(L, scopes);
        int current = lua_rawequal(L, 1, -1);
        lua_pop(L, 1);
        if (current) {
            lua_getiuservalue(L, 1, 1); /* previous scope */
            lua_rawset(L, scopes);
        } else {
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
        scope->active = 0;
    }
    return 0;
}

static int scope_enter(lua_State *L)
{
    int64_t ms;
    if (ku_check_duration(L, 1, &ms) != 0) {
        return ku_err_raise(L, "SCHED", "badvalue", "deadline needs a duration such as 30s");
    }
    push_scopes(L);
    int scopes = lua_gettop(L);
    lua_pushthread(L);
    lua_rawget(L, scopes);
    int previous = lua_gettop(L);
    deadline_scope *parent = luaL_testudata(L, previous, DEADLINE_META);
    deadline_scope *scope = lua_newuserdatauv(L, sizeof *scope, 3);
    int token = lua_gettop(L);
    scope->due_ms = ku_now_ms() + ms;
    scope->active = 1;
    luaL_setmetatable(L, DEADLINE_META);
    lua_pushvalue(L, previous);
    lua_setiuservalue(L, token, 1);
    if (parent != NULL && parent->due_ms < scope->due_ms) {
        scope->due_ms = parent->due_ms;
        lua_getiuservalue(L, previous, 2);
    } else {
        lua_pushvalue(L, token);
    }
    lua_setiuservalue(L, token, 2); /* effective token */
    lua_pushthread(L);
    lua_setiuservalue(L, token, 3);
    lua_pushthread(L);
    lua_pushvalue(L, token);
    lua_rawset(L, scopes);
    return 1;
}

int ku_deadline_current(lua_State *L, int64_t *due_ms)
{
    lua_getfield(L, LUA_REGISTRYINDEX, DEADLINE_KEY);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    lua_pushthread(L);
    lua_rawget(L, -2);
    deadline_scope *scope = luaL_testudata(L, -1, DEADLINE_META);
    if (scope == NULL || !scope->active) {
        lua_pop(L, 2);
        return 0;
    }
    *due_ms = scope->due_ms;
    lua_getiuservalue(L, -1, 2);
    lua_remove(L, -2);
    lua_remove(L, -2);
    return 1;
}

void ku_deadline_open(lua_State *L)
{
    if (luaL_newmetatable(L, DEADLINE_META)) {
        lua_pushcfunction(L, scope_close);
        lua_setfield(L, -2, "__close");
        lua_pushliteral(L, "kuu.deadline");
        lua_setfield(L, -2, "__metatable");
    }
    lua_pop(L, 1);
    lua_pushcfunction(L, scope_enter);
    lua_setfield(L, -2, "_deadline_enter");
    lua_pushcfunction(L, scope_close);
    lua_setfield(L, -2, "_deadline_leave");
}
