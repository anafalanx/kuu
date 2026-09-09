/*
 * env.c -- the `env` module: environment variables, this process's and the
 * persisted ones.
 *
 *   env.get(name)                       -> value | nil        the live environment, UTF-8
 *   env.set(name, value)                -> true               this process and its children from now on;
 *                                                             nil or false removes
 *   env.all()                           -> { NAME = value }
 *   env.expand(text)                    -> text               %VAR% references filled in
 *   env.persisted(name [, scope])       -> value, type | nil  the stored value, unexpanded
 *   env.persist(name, value [, scope])  -> true | nil, err    store, then broadcast the change
 *   env.forget(name [, scope])          -> true | nil, err    remove, then broadcast the change
 *
 * Scope is "user" (the default: HKCU\Environment) or "machine" (the
 * Session Manager's Environment key, which needs an elevated kuu).  A value
 * holding a % is stored as expandstring, as Windows does for PATH.  After a
 * write, WM_SETTINGCHANGE "Environment" is broadcast so Explorer and new
 * consoles pick it up; processes already running, kuu included, keep their
 * copy.  Errors are ENV: badvalue, notfound, access, oserror.
 */
#include "err.h"
#include "state.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

static wchar_t *checked_name(lua_State *L, int idx)
{
    size_t length = 0;
    const char *name = luaL_checklstring(L, idx, &length);
    if (length == 0 || strchr(name, '=') != NULL) {
        ku_err_raise(L, "ENV", "badvalue", "a variable name is non-empty and has no =");
    }
    wchar_t *wide = ku_utf8_to_wide(name);
    if (wide == NULL) {
        ku_err_raise(L, "ENV", "badvalue", "the name is not valid UTF-8");
    }
    return wide;
}

/* env.get(name) */
static int l_env_get(lua_State *L)
{
    wchar_t *name = checked_name(L, 1);
    DWORD need = GetEnvironmentVariableW(name, NULL, 0);
    if (need == 0) {
        free(name);
        lua_pushnil(L);
        return 1;
    }
    wchar_t *value = (wchar_t *)malloc((size_t)need * sizeof(wchar_t));
    if (value == NULL || GetEnvironmentVariableW(name, value, need) == 0) {
        free(name);
        free(value);
        lua_pushnil(L);
        return 1;
    }
    free(name);
    char *utf8 = ku_wide_to_utf8(value, -1);
    free(value);
    lua_pushstring(L, utf8 != NULL ? utf8 : "");
    free(utf8);
    return 1;
}

/* env.set(name, value) */
static int l_env_set(lua_State *L)
{
    wchar_t *name = checked_name(L, 1);
    wchar_t *value = NULL;
    if (!lua_isnoneornil(L, 2) && !(lua_isboolean(L, 2) && !lua_toboolean(L, 2))) {
        const char *text = lua_tostring(L, 2);
        if (text == NULL) {
            free(name);
            return ku_err_raise(L, "ENV", "badvalue", "a value is a string, or nil to remove");
        }
        value = ku_utf8_to_wide(text);
        if (value == NULL) {
            free(name);
            return ku_err_raise(L, "ENV", "badvalue", "the value is not valid UTF-8");
        }
    }
    BOOL ok = SetEnvironmentVariableW(name, value);
    DWORD error = ok ? 0 : GetLastError();
    free(name);
    free(value);
    if (!ok && !(value == NULL && error == ERROR_ENVVAR_NOT_FOUND)) {
        char *text = ku_win_error_message(error);
        int n = ku_err_raise(L, "ENV", "oserror", "cannot set the variable: %s", text != NULL ? text : "");
        free(text);
        return n;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* env.all() */
static int l_env_all(lua_State *L)
{
    wchar_t *block = GetEnvironmentStringsW();
    if (block == NULL) {
        return ku_err_raise(L, "ENV", "oserror", "cannot read the environment");
    }
    lua_newtable(L);
    for (const wchar_t *entry = block; *entry != L'\0'; entry += wcslen(entry) + 1) {
        if (entry[0] == L'=') {
            continue; /* the shell's hidden drive entries */
        }
        const wchar_t *eq = wcschr(entry, L'=');
        if (eq == NULL) {
            continue;
        }
        char *name = ku_wide_to_utf8(entry, (int)(eq - entry));
        char *value = ku_wide_to_utf8(eq + 1, -1);
        if (name != NULL && value != NULL) {
            lua_pushstring(L, value);
            lua_setfield(L, -2, name);
        }
        free(name);
        free(value);
    }
    FreeEnvironmentStringsW(block);
    return 1;
}

/* env.expand(text) */
static int l_env_expand(lua_State *L)
{
    const char *text = luaL_checkstring(L, 1);
    wchar_t *wide = ku_utf8_to_wide(text);
    if (wide == NULL) {
        return ku_err_raise(L, "ENV", "badvalue", "the text is not valid UTF-8");
    }
    DWORD need = ExpandEnvironmentStringsW(wide, NULL, 0);
    wchar_t *out = (wchar_t *)malloc(((size_t)need + 1) * sizeof(wchar_t));
    if (need == 0 || out == NULL || ExpandEnvironmentStringsW(wide, out, need + 1) == 0) {
        free(wide);
        free(out);
        return ku_err_raise(L, "ENV", "oserror", "cannot expand the text");
    }
    free(wide);
    char *utf8 = ku_wide_to_utf8(out, -1);
    free(out);
    lua_pushstring(L, utf8 != NULL ? utf8 : "");
    free(utf8);
    return 1;
}

/* ---- persisted ------------------------------------------------------------------- */

static const wchar_t *MACHINE_KEY = L"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment";
static const wchar_t *USER_KEY = L"Environment";

/* the root and path for `scope` at `idx`; raises ENV badvalue */
static HKEY scope_key(lua_State *L, int idx, const wchar_t **path)
{
    const char *scope = luaL_optstring(L, idx, "user");
    if (strcmp(scope, "user") == 0) {
        *path = USER_KEY;
        return HKEY_CURRENT_USER;
    }
    if (strcmp(scope, "machine") == 0) {
        *path = MACHINE_KEY;
        return HKEY_LOCAL_MACHINE;
    }
    ku_err_raise(L, "ENV", "badvalue", "the scope is \"user\" or \"machine\"");
    return NULL;
}

static int fail(lua_State *L, LSTATUS status, const char *what)
{
    if (status == ERROR_FILE_NOT_FOUND) {
        return ku_err_fail(L, "ENV", "notfound", "%s: no such persisted variable", what);
    }
    if (status == ERROR_ACCESS_DENIED) {
        return ku_err_fail(L, "ENV", "access", "%s: access denied; the machine scope needs an elevated kuu", what);
    }
    char *text = ku_win_error_message((DWORD)status);
    int n = ku_err_fail(L, "ENV", "oserror", "%s: %s (error %ld)", what, text != NULL ? text : "", (long)status);
    free(text);
    return n;
}

static void broadcast(void)
{
    DWORD_PTR result = 0;
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)L"Environment", SMTO_ABORTIFHUNG, 2000, &result);
}

/* env.persisted(name [, scope]) */
static int l_env_persisted(lua_State *L)
{
    const wchar_t *path = NULL;
    HKEY root = scope_key(L, 2, &path);
    wchar_t *name = checked_name(L, 1);
    DWORD type = 0, size = 0;
    LSTATUS st = RegGetValueW(root, path, name, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, &type, NULL, &size);
    if (st != ERROR_SUCCESS) {
        free(name);
        if (st == ERROR_FILE_NOT_FOUND) {
            lua_pushnil(L);
            return 1;
        }
        return fail(L, st, "persisted");
    }
    wchar_t *value = (wchar_t *)calloc((size_t)size + 2, 1);
    if (value == NULL) {
        free(name);
        return ku_err_raise(L, "ENV", "oserror", "out of memory");
    }
    st = RegGetValueW(root, path, name, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, &type, value, &size);
    free(name);
    if (st != ERROR_SUCCESS) {
        free(value);
        return fail(L, st, "persisted");
    }
    char *utf8 = ku_wide_to_utf8(value, -1);
    free(value);
    lua_pushstring(L, utf8 != NULL ? utf8 : "");
    free(utf8);
    lua_pushstring(L, type == REG_EXPAND_SZ ? "expandstring" : "string");
    return 2;
}

/* env.persist(name, value [, scope]) */
static int l_env_persist(lua_State *L)
{
    const char *text = luaL_checkstring(L, 2);
    const wchar_t *path = NULL;
    HKEY root = scope_key(L, 3, &path);
    wchar_t *name = checked_name(L, 1);
    wchar_t *value = ku_utf8_to_wide(text);
    if (value == NULL) {
        free(name);
        return ku_err_raise(L, "ENV", "badvalue", "the value is not valid UTF-8");
    }
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(root, path, 0, KEY_SET_VALUE, &h);
    if (st == ERROR_SUCCESS) {
        DWORD type = wcschr(value, L'%') != NULL ? REG_EXPAND_SZ : REG_SZ;
        st = RegSetValueExW(h, name, 0, type, (const BYTE *)value, (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
        RegCloseKey(h);
    }
    free(name);
    free(value);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "persist");
    }
    broadcast();
    lua_pushboolean(L, 1);
    return 1;
}

/* env.forget(name [, scope]) */
static int l_env_forget(lua_State *L)
{
    const wchar_t *path = NULL;
    HKEY root = scope_key(L, 2, &path);
    wchar_t *name = checked_name(L, 1);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(root, path, 0, KEY_SET_VALUE, &h);
    if (st == ERROR_SUCCESS) {
        st = RegDeleteValueW(h, name);
        RegCloseKey(h);
    }
    free(name);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "forget");
    }
    broadcast();
    lua_pushboolean(L, 1);
    return 1;
}

int ku_open_env(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"get", l_env_get},       {"set", l_env_set},       {"all", l_env_all},       {"expand", l_env_expand},
        {"persisted", l_env_persisted}, {"persist", l_env_persist}, {"forget", l_env_forget},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
