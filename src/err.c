/* err.c -- the one error shape; see err.h. */
#include "err.h"

#include "lauxlib.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define KU_ERR_META "kuu.err"

static int err_tostring(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_getfield(L, 1, "domain");
    lua_getfield(L, 1, "code");
    lua_getfield(L, 1, "message");
    const char *domain = lua_tostring(L, -3);
    const char *code = lua_tostring(L, -2);
    const char *message = lua_tostring(L, -1);
    lua_pushfstring(L, "%s %s: %s", domain != NULL ? domain : "?",
                    code != NULL ? code : "?", message != NULL ? message : "");
    return 1;
}

static void push_meta(lua_State *L)
{
    if (luaL_newmetatable(L, KU_ERR_META)) {
        lua_pushcfunction(L, err_tostring);
        lua_setfield(L, -2, "__tostring");
        lua_pushliteral(L, KU_ERR_META);
        lua_setfield(L, -2, "__name");
    }
}

static void push_err_v(lua_State *L, const char *domain, const char *code,
                       const char *format, va_list args)
{
    char message[1024];
    vsnprintf(message, sizeof message, format, args);
    lua_createtable(L, 0, 3);
    lua_pushstring(L, domain);
    lua_setfield(L, -2, "domain");
    lua_pushstring(L, code);
    lua_setfield(L, -2, "code");
    lua_pushstring(L, message);
    lua_setfield(L, -2, "message");
    push_meta(L);
    lua_setmetatable(L, -2);
}

void ku_err_push(lua_State *L, const char *domain, const char *code,
                 const char *format, ...)
{
    va_list args;
    va_start(args, format);
    push_err_v(L, domain, code, format, args);
    va_end(args);
}

int ku_err_fail(lua_State *L, const char *domain, const char *code,
                const char *format, ...)
{
    lua_pushnil(L);
    va_list args;
    va_start(args, format);
    push_err_v(L, domain, code, format, args);
    va_end(args);
    return 2;
}

int ku_err_raise(lua_State *L, const char *domain, const char *code,
                 const char *format, ...)
{
    va_list args;
    va_start(args, format);
    push_err_v(L, domain, code, format, args);
    va_end(args);
    return lua_error(L);
}

/* err.new(domain, code, message [, extra]) */
static int l_err_new(lua_State *L)
{
    const char *domain = luaL_checkstring(L, 1);
    const char *code = luaL_checkstring(L, 2);
    const char *message = luaL_optstring(L, 3, "");
    int has_extra = lua_gettop(L) >= 4 && lua_type(L, 4) == LUA_TTABLE;
    ku_err_push(L, domain, code, "%s", message);
    int result = lua_gettop(L);
    if (has_extra) {
        lua_pushnil(L);
        while (lua_next(L, 4) != 0) {
            lua_pushvalue(L, -2);   /* [.., k, v, k] */
            lua_insert(L, -2);      /* [.., k, k, v] */
            lua_settable(L, result); /* err[k] = v; the iteration key stays */
        }
    }
    lua_settop(L, result);
    return 1;
}

/* err.is(value [, domain [, code]]) */
static int l_err_is(lua_State *L)
{
    if (lua_type(L, 1) != LUA_TTABLE || !lua_getmetatable(L, 1)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    push_meta(L);
    int same = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    if (!same) {
        lua_pushboolean(L, 0);
        return 1;
    }
    if (!lua_isnoneornil(L, 2)) {
        const char *domain = luaL_checkstring(L, 2);
        lua_getfield(L, 1, "domain");
        const char *have = lua_tostring(L, -1);
        int match = have != NULL && strcmp(have, domain) == 0;
        lua_pop(L, 1);
        if (!match) {
            lua_pushboolean(L, 0);
            return 1;
        }
    }
    if (!lua_isnoneornil(L, 3)) {
        const char *code = luaL_checkstring(L, 3);
        lua_getfield(L, 1, "code");
        const char *have = lua_tostring(L, -1);
        int match = have != NULL && strcmp(have, code) == 0;
        lua_pop(L, 1);
        if (!match) {
            lua_pushboolean(L, 0);
            return 1;
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

int ku_open_err(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"new", l_err_new},
        {"is", l_err_is},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
