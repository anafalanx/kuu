/* state.c -- building the program's Lua state; see state.h. */
#include "state.h"
#include "program.h"
#include "wintext.h"

#include "lauxlib.h"
#include "lualib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KU_PATH_MAX 4096

static void drop_field(lua_State *L, const char *table, const char *field)
{
    if (lua_getglobal(L, table) == LUA_TTABLE) {
        lua_pushnil(L);
        lua_setfield(L, -2, field);
    }
    lua_pop(L, 1);
}

/* `load` with the mode forced to "t": kuu never runs a binary chunk, whatever
 * the caller asked for.  The argument count is preserved because `load`
 * distinguishes an absent `env` from an explicit nil. */
static int ku_load(lua_State *L)
{
    int n = lua_gettop(L);
    if (n < 3) {
        lua_settop(L, 3);
        n = 3;
    }
    lua_pushliteral(L, "t");
    lua_replace(L, 3);
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_insert(L, 1);
    lua_call(L, n, LUA_MULTRET);
    return lua_gettop(L);
}

/* A dotted module name becomes a relative path.  Anything that is not a plain
 * dotted name (separators, drive letters, empty or "." / ".." segments) is
 * refused, so `require` can only reach below the root. */
static int module_relative(const char *name, char *out, size_t capacity)
{
    size_t n = strlen(name);
    if (n == 0 || n + 1 > capacity) {
        return 0;
    }
    size_t segment = 0;
    int dots_only = 1;
    for (size_t i = 0; i <= n; i++) {
        char c = name[i];
        if (c == '\0' || c == '.') {
            if (segment == 0 || dots_only) {
                return 0;
            }
            out[i] = (c == '.') ? '/' : '\0';
            segment = 0;
            dots_only = 1;
            continue;
        }
        if (c == '/' || c == '\\' || c == ':') {
            return 0;
        }
        out[i] = c;
        segment++;
        if (c != '.') {
            dots_only = 0;
        }
    }
    return 1;
}

static int ku_searcher(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    const char *root = lua_tostring(L, lua_upvalueindex(1));
    char relative[KU_PATH_MAX];
    if (!module_relative(name, relative, sizeof relative)) {
        lua_pushfstring(L, "\n\tmodule name '%s' is not a plain dotted name", name);
        return 1;
    }
    static const char *const tails[2] = {".lua", "/init.lua"};
    char missing[2 * KU_PATH_MAX + 64];
    missing[0] = '\0';
    size_t missing_used = 0;
    for (int t = 0; t < 2; t++) {
        char path[KU_PATH_MAX];
        int written = snprintf(path, sizeof path, "%s/%s%s", root, relative, tails[t]);
        if (written < 0 || (size_t)written >= sizeof path) {
            return luaL_error(L, "module path for '%s' is too long", name);
        }
        wchar_t *wide = ku_utf8_to_wide(path);
        if (wide == NULL) {
            return luaL_error(L, "module path '%s' is not valid UTF-8", path);
        }
        ku_program program;
        ku_fail fail;
        int status = ku_program_read_file(wide, path, &program, &fail);
        free(wide);
        if (status != 0) {
            if (strcmp(fail.code, "notfound") == 0) {
                int more = snprintf(missing + missing_used, sizeof missing - missing_used,
                                    "\n\tno file '%s'", path);
                if (more > 0 && (size_t)more < sizeof missing - missing_used) {
                    missing_used += (size_t)more;
                }
                continue;
            }
            return luaL_error(L, "cannot load module '%s': %s", name, fail.message);
        }
        char chunkname[KU_PATH_MAX + 1];
        snprintf(chunkname, sizeof chunkname, "@%s", path);
        status = luaL_loadbufferx(L, program.text, program.length, chunkname, "t");
        ku_program_free(&program);
        if (status != LUA_OK) {
            return luaL_error(L, "error loading module '%s' from file '%s':\n\t%s",
                              name, path, lua_tostring(L, -1));
        }
        lua_pushstring(L, path);
        return 2;
    }
    lua_pushstring(L, missing);
    return 1;
}

/* The `rt` module is the table built at state creation, handed out by
 * `require "rt"`. */
static int ku_rt_open(lua_State *L)
{
    lua_pushvalue(L, lua_upvalueindex(1));
    return 1;
}

static void push_rt_table(lua_State *L, const ku_launch *launch)
{
    lua_createtable(L, 0, 6);
    lua_pushliteral(L, KUU_VERSION);
    lua_setfield(L, -2, "version");
    lua_pushliteral(L, LUA_RELEASE);
    lua_setfield(L, -2, "lua");
    lua_pushstring(L, launch->exe);
    lua_setfield(L, -2, "exe");
    lua_pushstring(L, launch->route);
    lua_setfield(L, -2, "route");
    if (launch->program != NULL) {
        lua_pushstring(L, launch->program);
        lua_setfield(L, -2, "program");
    }
    lua_createtable(L, launch->argc, 0);
    for (int i = 0; i < launch->argc; i++) {
        lua_pushstring(L, launch->argv[i]);
        lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "args");
}

lua_State *ku_state_new(const ku_launch *launch, ku_fail *fail)
{
    lua_State *L = luaL_newstate();
    if (L == NULL) {
        ku_fail_set(fail, "STATE", "oserror", "cannot create the Lua state");
        return NULL;
    }
    luaL_openselectedlibs(L, LUA_GLIBK | LUA_LOADLIBK | LUA_COLIBK | LUA_IOLIBK |
                                 LUA_MATHLIBK | LUA_OSLIBK | LUA_STRLIBK | LUA_TABLIBK |
                                 LUA_UTF8LIBK, 0);

    /* Hazards a runtime owns: processes and files belong to the palette, with
     * decided lifetimes and UTF-8 paths; these CRT-backed functions have
     * neither. */
    drop_field(L, "io", "popen");
    drop_field(L, "os", "execute");
    drop_field(L, "os", "remove");
    drop_field(L, "os", "rename");
    drop_field(L, "os", "tmpname");
    drop_field(L, "_G", "dofile");
    drop_field(L, "_G", "loadfile");

    lua_getglobal(L, "load");
    lua_pushcclosure(L, ku_load, 1);
    lua_setglobal(L, "load");

    lua_getglobal(L, "package");
    lua_pushliteral(L, "");
    lua_setfield(L, -2, "path");
    lua_pushliteral(L, "");
    lua_setfield(L, -2, "cpath");
    lua_pushnil(L);
    lua_setfield(L, -2, "loadlib");
    lua_getfield(L, -1, "searchers"); /* [preload, lua, c, croot] */
    lua_pushstring(L, launch->root);
    lua_pushcclosure(L, ku_searcher, 1);
    lua_rawseti(L, -2, 2);
    lua_pushnil(L);
    lua_rawseti(L, -2, 4);
    lua_pushnil(L);
    lua_rawseti(L, -2, 3);
    lua_pop(L, 1);
    lua_getfield(L, -1, "preload");
    push_rt_table(L, launch);
    lua_pushcclosure(L, ku_rt_open, 1);
    lua_setfield(L, -2, "rt");
    lua_pop(L, 2);
    return L;
}
