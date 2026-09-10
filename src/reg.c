/*
 * reg.c -- the `reg` module: the registry, typed.
 *
 *   reg.get(key, name)                  -> value, type | nil, err   name nil or "" is the default value
 *   reg.set(key, name, value [, type])  -> true | nil, err          creates the key when needed
 *   reg.delete(key, name)               -> true | nil, err          one value
 *   reg.values(key)                     -> { { name, type, value }, ... } sorted by name | nil, err
 *   reg.keys(key)                       -> { name, ... } sorted | nil, err
 *   reg.exists(key)                     -> boolean
 *   reg.create(key)                     -> true | nil, err
 *   reg.remove(key)                     -> true | nil, err          the key and everything under it
 *
 * A key is "HKCU\Software\Vendor\App", with either slash; the roots are
 * HKLM, HKCU, HKCR, HKU, HKCC and their long names.  Types are string
 * (REG_SZ), expandstring, multistring (a list of strings), dword, qword,
 * and binary (bytes); anything else reads as bytes and names itself
 * "unknown".  set without a type stores a string as string, an integer as
 * dword (qword when it does not fit), and a list as multistring.  kuu is a
 * 64-bit process and sees the 64-bit view.  Errors are REG: notfound,
 * access (run elevated), badvalue, encoding, oserror.
 */
#include "err.h"
#include "state.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

typedef struct reg_key {
    HKEY root;
    wchar_t *path; /* below the root, backslashes, no trailing one; "" for the root itself */
} reg_key;

static const struct {
    const char *name;
    HKEY key;
} roots[] = {
    {"HKLM", HKEY_LOCAL_MACHINE},   {"HKEY_LOCAL_MACHINE", HKEY_LOCAL_MACHINE},
    {"HKCU", HKEY_CURRENT_USER},    {"HKEY_CURRENT_USER", HKEY_CURRENT_USER},
    {"HKCR", HKEY_CLASSES_ROOT},    {"HKEY_CLASSES_ROOT", HKEY_CLASSES_ROOT},
    {"HKU", HKEY_USERS},            {"HKEY_USERS", HKEY_USERS},
    {"HKCC", HKEY_CURRENT_CONFIG},  {"HKEY_CURRENT_CONFIG", HKEY_CURRENT_CONFIG},
};

/* The root named by the key at `idx`, and the text below it; raises REG
 * badvalue and allocates nothing, so callers can check every argument
 * before they allocate anything a raise would leak. */
static HKEY check_root(lua_State *L, int idx, const char **rest)
{
    const char *text = ku_check_cstring(L, idx, "REG", "key");
    const char *slash = strpbrk(text, "\\/");
    size_t root_length = slash != NULL ? (size_t)(slash - text) : strlen(text);
    HKEY root = NULL;
    for (size_t i = 0; i < sizeof roots / sizeof roots[0]; i++) {
        if (strlen(roots[i].name) == root_length && _strnicmp(text, roots[i].name, root_length) == 0) {
            root = roots[i].key;
        }
    }
    if (root == NULL) {
        ku_err_raise(L, "REG", "badvalue", "'%s' does not start with a registry root such as HKCU", text);
    }
    *rest = slash != NULL ? slash + 1 : "";
    if (!ku_utf8_valid((const unsigned char *)*rest, strlen(*rest))) {
        ku_err_raise(L, "REG", "badvalue", "the key is not valid UTF-8");
    }
    return root;
}

/* The path below the root as the registry wants it: backslashes, no trailing one. */
static wchar_t *key_path(lua_State *L, const char *rest)
{
    wchar_t *path = ku_utf8_to_wide(rest);
    if (path == NULL) {
        ku_err_raise(L, "REG", "oserror", "out of memory");
    }
    for (wchar_t *p = path; *p != L'\0'; p++) {
        if (*p == L'/') {
            *p = L'\\';
        }
    }
    size_t n = wcslen(path);
    while (n > 0 && path[n - 1] == L'\\') {
        path[--n] = L'\0';
    }
    return path;
}

static void parse_key(lua_State *L, int idx, reg_key *k)
{
    const char *rest = NULL;
    k->root = check_root(L, idx, &rest);
    k->path = key_path(L, rest);
}

/* nil, REG <code> for a registry status */
static int fail(lua_State *L, LSTATUS status, const char *what)
{
    if (status == ERROR_FILE_NOT_FOUND) {
        return ku_err_fail(L, "REG", "notfound", "%s: no such key or value", what);
    }
    if (status == ERROR_ACCESS_DENIED) {
        return ku_err_fail(L, "REG", "access", "%s: access denied; this needs an elevated kuu", what);
    }
    char *text = ku_win_error_message((DWORD)status);
    int n = ku_err_fail(L, "REG", "oserror", "%s: %s (error %ld)", what, text != NULL ? text : "", (long)status);
    free(text);
    return n;
}

static int push_wide(lua_State *L, const wchar_t *wide, size_t count)
{
    while (count > 0 && wide[count - 1] == L'\0') {
        count--;
    }
    if (count == 0) {
        lua_pushliteral(L, "");
        return 1;
    }
    char *utf8 = ku_wide_to_utf8(wide, (int)count);
    if (utf8 == NULL) {
        return 0;
    }
    lua_pushstring(L, utf8);
    free(utf8);
    return 1;
}

/* Push value and type, or return 0 without pushing for invalid UTF-16. */
static int push_value(lua_State *L, DWORD type, const unsigned char *data, DWORD size)
{
    switch (type) {
    case REG_SZ:
    case REG_EXPAND_SZ:
        if (size % sizeof(wchar_t) != 0 || !push_wide(L, (const wchar_t *)data, size / sizeof(wchar_t))) {
            return 0;
        }
        lua_pushstring(L, type == REG_SZ ? "string" : "expandstring");
        return 1;
    case REG_MULTI_SZ: {
        if (size % sizeof(wchar_t) != 0) {
            return 0;
        }
        const wchar_t *w = (const wchar_t *)data;
        size_t n = size / sizeof(wchar_t), i = 0;
        lua_Integer count = 0;
        lua_newtable(L);
        while (i < n && w[i] != L'\0') {
            size_t start = i;
            while (i < n && w[i] != L'\0') {
                i++;
            }
            if (!push_wide(L, w + start, i - start)) {
                lua_pop(L, 1);
                return 0;
            }
            lua_rawseti(L, -2, ++count);
            i++;
        }
        lua_pushstring(L, "multistring");
        return 1;
    }
    case REG_DWORD: {
        DWORD v = 0;
        memcpy(&v, data, size < sizeof v ? size : sizeof v);
        lua_pushinteger(L, (lua_Integer)v);
        lua_pushstring(L, "dword");
        return 1;
    }
    case REG_DWORD_BIG_ENDIAN: {
        DWORD v = 0;
        if (size >= 4) {
            v = ((DWORD)data[0] << 24) | ((DWORD)data[1] << 16) | ((DWORD)data[2] << 8) | (DWORD)data[3];
        }
        lua_pushinteger(L, (lua_Integer)v);
        lua_pushstring(L, "dword");
        return 1;
    }
    case REG_QWORD: {
        unsigned long long v = 0;
        memcpy(&v, data, size < sizeof v ? size : sizeof v);
        lua_pushinteger(L, (lua_Integer)v);
        lua_pushstring(L, "qword");
        return 1;
    }
    default:
        lua_pushlstring(L, (const char *)data, size);
        lua_pushstring(L, type == REG_BINARY ? "binary" : type == REG_NONE ? "none" : "unknown");
        return 1;
    }
}

static wchar_t *value_name(lua_State *L, int idx)
{
    const char *name = lua_isnoneornil(L, idx) ? "" : ku_check_cstring(L, idx, "REG", "value name");
    wchar_t *wide = ku_utf8_to_wide(name);
    if (wide == NULL) {
        ku_err_raise(L, "REG", "badvalue", "the value name is not valid UTF-8");
    }
    return wide;
}

/* reg.get(key, name) */
static int l_reg_get(lua_State *L)
{
    const char *rest = NULL;
    HKEY root = check_root(L, 1, &rest);
    luaL_optstring(L, 2, "");
    wchar_t *name = value_name(L, 2);
    reg_key k;
    k.root = root;
    k.path = key_path(L, rest);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(k.root, k.path, 0, KEY_QUERY_VALUE, &h);
    free(k.path);
    if (st != ERROR_SUCCESS) {
        free(name);
        return fail(L, st, "get");
    }
    DWORD type = 0, size = 0;
    st = RegQueryValueExW(h, name, NULL, &type, NULL, &size);
    if (st != ERROR_SUCCESS) {
        RegCloseKey(h);
        free(name);
        return fail(L, st, "get");
    }
    unsigned char *data = (unsigned char *)calloc(1, (size_t)size + 2 * sizeof(wchar_t));
    if (data == NULL) {
        RegCloseKey(h);
        free(name);
        return ku_err_raise(L, "REG", "oserror", "out of memory");
    }
    st = RegQueryValueExW(h, name, NULL, &type, data, &size);
    RegCloseKey(h);
    free(name);
    if (st != ERROR_SUCCESS) {
        free(data);
        return fail(L, st, "get");
    }
    int valid = push_value(L, type, data, size);
    free(data);
    if (!valid) {
        return ku_err_fail(L, "REG", "encoding", "the value is not valid UTF-16");
    }
    return 2;
}

/* The bytes to store for `value` at index 3 as `type_name`; raises REG badvalue. */
static unsigned char *encode_value(lua_State *L, const char *type_name, DWORD *type, DWORD *size)
{
    if (strcmp(type_name, "string") == 0 || strcmp(type_name, "expandstring") == 0) {
        const char *s = ku_check_cstring(L, 3, "REG", "text value");
        wchar_t *wide = ku_utf8_to_wide(s);
        if (wide == NULL) {
            ku_err_raise(L, "REG", "badvalue", "the value is not valid UTF-8");
        }
        *type = strcmp(type_name, "string") == 0 ? REG_SZ : REG_EXPAND_SZ;
        *size = (DWORD)((wcslen(wide) + 1) * sizeof(wchar_t));
        return (unsigned char *)wide;
    }
    if (strcmp(type_name, "multistring") == 0) {
        luaL_checktype(L, 3, LUA_TTABLE);
        lua_Integer n = luaL_len(L, 3);
        size_t total = 1; /* the closing NUL */
        for (lua_Integer i = 1; i <= n; i++) {
            lua_rawgeti(L, 3, i);
            if (lua_type(L, -1) != LUA_TSTRING) {
                ku_err_raise(L, "REG", "badvalue", "a multistring is a list of strings");
            }
            size_t len = 0;
            const char *s = ku_check_cstring(L, -1, "REG", "multistring entry");
            lua_tolstring(L, -1, &len);
            if (len == 0) {
                ku_err_raise(L, "REG", "badvalue", "a multistring cannot hold an empty string");
            }
            wchar_t *wide = ku_utf8_to_wide(s);
            if (wide == NULL) {
                ku_err_raise(L, "REG", "badvalue", "a multistring entry is not valid UTF-8");
            }
            total += wcslen(wide) + 1;
            free(wide);
            lua_pop(L, 1);
        }
        if (n == 0) {
            total++; /* an empty list is two NULs */
        }
        wchar_t *buffer = (wchar_t *)calloc(total, sizeof(wchar_t));
        if (buffer == NULL) {
            ku_err_raise(L, "REG", "oserror", "out of memory");
        }
        size_t at = 0;
        for (lua_Integer i = 1; i <= n; i++) {
            lua_rawgeti(L, 3, i);
            wchar_t *wide = ku_utf8_to_wide(lua_tostring(L, -1));
            lua_pop(L, 1);
            if (wide != NULL) {
                size_t len = wcslen(wide);
                memcpy(buffer + at, wide, (len + 1) * sizeof(wchar_t));
                at += len + 1;
                free(wide);
            }
        }
        *type = REG_MULTI_SZ;
        *size = (DWORD)(total * sizeof(wchar_t));
        return (unsigned char *)buffer;
    }
    if (strcmp(type_name, "dword") == 0) {
        lua_Integer v = luaL_checkinteger(L, 3);
        if (v < 0 || v > 0xffffffffLL) {
            ku_err_raise(L, "REG", "badvalue", "a dword is 0 to 4294967295");
        }
        DWORD *d = (DWORD *)malloc(sizeof *d);
        if (d == NULL) {
            ku_err_raise(L, "REG", "oserror", "out of memory");
        }
        *d = (DWORD)v;
        *type = REG_DWORD;
        *size = sizeof *d;
        return (unsigned char *)d;
    }
    if (strcmp(type_name, "qword") == 0) {
        lua_Integer v = luaL_checkinteger(L, 3);
        unsigned long long *q = (unsigned long long *)malloc(sizeof *q);
        if (q == NULL) {
            ku_err_raise(L, "REG", "oserror", "out of memory");
        }
        *q = (unsigned long long)v;
        *type = REG_QWORD;
        *size = sizeof *q;
        return (unsigned char *)q;
    }
    if (strcmp(type_name, "binary") == 0) {
        size_t len = 0;
        const char *b = luaL_checklstring(L, 3, &len);
        unsigned char *copy = (unsigned char *)malloc(len > 0 ? len : 1);
        if (copy == NULL) {
            ku_err_raise(L, "REG", "oserror", "out of memory");
        }
        memcpy(copy, b, len);
        *type = REG_BINARY;
        *size = (DWORD)len;
        return copy;
    }
    ku_err_raise(L, "REG", "badvalue", "unknown type '%s'; use string, expandstring, multistring, dword, qword, or binary", type_name);
    return NULL;
}

/* reg.set(key, name, value [, type]) */
static int l_reg_set(lua_State *L)
{
    luaL_checkstring(L, 1);
    const char *type_name = lua_isnoneornil(L, 4) ? NULL : ku_check_cstring(L, 4, "REG", "type");
    if (type_name == NULL) {
        switch (lua_type(L, 3)) {
        case LUA_TSTRING:
            type_name = "string";
            break;
        case LUA_TNUMBER: {
            if (!lua_isinteger(L, 3)) {
                return ku_err_raise(L, "REG", "badvalue", "a number must be an integer; the registry has no floats");
            }
            lua_Integer v = lua_tointeger(L, 3);
            type_name = v >= 0 && v <= 0xffffffffLL ? "dword" : "qword";
            break;
        }
        case LUA_TTABLE:
            type_name = "multistring";
            break;
        default:
            return ku_err_raise(L, "REG", "badvalue", "a value is a string, an integer, or a list of strings");
        }
    }
    /* every check that can raise comes before the first allocation */
    const char *rest = NULL;
    HKEY root = check_root(L, 1, &rest);
    const char *value_name_text = lua_isnoneornil(L, 2) ? "" : ku_check_cstring(L, 2, "REG", "value name");
    DWORD type = 0, size = 0;
    unsigned char *data = encode_value(L, type_name, &type, &size);
    wchar_t *name = ku_utf8_to_wide(value_name_text);
    if (name == NULL) {
        free(data);
        return ku_err_raise(L, "REG", "badvalue", "the value name is not valid UTF-8");
    }
    wchar_t *path = key_path(L, rest);
    HKEY h = NULL;
    LSTATUS st = RegCreateKeyExW(root, path, 0, NULL, 0, KEY_SET_VALUE, NULL, &h, NULL);
    free(path);
    if (st == ERROR_SUCCESS) {
        st = RegSetValueExW(h, name, 0, type, data, size);
        RegCloseKey(h);
    }
    free(name);
    free(data);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "set");
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* reg.delete(key, name) */
static int l_reg_delete(lua_State *L)
{
    const char *rest = NULL;
    HKEY root = check_root(L, 1, &rest);
    luaL_optstring(L, 2, "");
    wchar_t *name = value_name(L, 2);
    reg_key k;
    k.root = root;
    k.path = key_path(L, rest);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(k.root, k.path, 0, KEY_SET_VALUE, &h);
    free(k.path);
    if (st == ERROR_SUCCESS) {
        st = RegDeleteValueW(h, name);
        RegCloseKey(h);
    }
    free(name);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "delete");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int compare_by_name(lua_State *L)
{
    lua_getfield(L, 1, "name");
    lua_getfield(L, 2, "name");
    int less = lua_compare(L, -2, -1, LUA_OPLT);
    lua_pushboolean(L, less);
    return 1;
}

/* sort the table on top of the stack with table.sort, by name when `by_name` */
static void sort_top(lua_State *L, int by_name)
{
    lua_getglobal(L, "table");
    lua_getfield(L, -1, "sort");
    lua_remove(L, -2);
    lua_pushvalue(L, -2);
    if (by_name) {
        lua_pushcfunction(L, compare_by_name);
        lua_call(L, 2, 0);
    } else {
        lua_call(L, 1, 0);
    }
}

/* reg.values(key) */
static int l_reg_values(lua_State *L)
{
    reg_key k;
    parse_key(L, 1, &k);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(k.root, k.path, 0, KEY_QUERY_VALUE, &h);
    free(k.path);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "values");
    }
    DWORD count = 0, max_name = 0, max_data = 0;
    RegQueryInfoKeyW(h, NULL, NULL, NULL, NULL, NULL, NULL, &count, &max_name, &max_data, NULL, NULL);
    wchar_t *name = (wchar_t *)malloc(((size_t)max_name + 2) * sizeof(wchar_t));
    DWORD capacity = max_data + 8;
    unsigned char *data = (unsigned char *)malloc(capacity);
    if (name == NULL || data == NULL) {
        free(name);
        free(data);
        RegCloseKey(h);
        return ku_err_raise(L, "REG", "oserror", "out of memory");
    }
    lua_createtable(L, (int)count, 0);
    lua_Integer n = 0;
    for (DWORD i = 0;;) {
        DWORD name_length = max_name + 2, size = capacity, type = 0;
        st = RegEnumValueW(h, i, name, &name_length, NULL, &type, data, &size);
        if (st == ERROR_MORE_DATA) {
            unsigned char *grown = (unsigned char *)realloc(data, (size_t)size + 8);
            if (grown == NULL) {
                break;
            }
            data = grown;
            capacity = size + 8;
            continue; /* the same index again */
        }
        if (st != ERROR_SUCCESS) {
            break;
        }
        lua_createtable(L, 0, 3);
        if (!push_wide(L, name, name_length)) {
            RegCloseKey(h);
            free(name);
            free(data);
            return ku_err_fail(L, "REG", "encoding", "a value name is not valid UTF-16");
        }
        lua_setfield(L, -2, "name");
        if (push_value(L, type, data, size)) {
            lua_setfield(L, -3, "type");
            lua_setfield(L, -2, "value");
        } else {
            lua_pushstring(L, type == REG_SZ ? "string" : type == REG_EXPAND_SZ ? "expandstring" : "multistring");
            lua_setfield(L, -2, "type");
            lua_pushlstring(L, (const char *)data, size);
            lua_setfield(L, -2, "bytes");
        }
        lua_rawseti(L, -2, ++n);
        i++;
    }
    RegCloseKey(h);
    free(name);
    free(data);
    sort_top(L, 1);
    return 1;
}

/* reg.keys(key) */
static int l_reg_keys(lua_State *L)
{
    reg_key k;
    parse_key(L, 1, &k);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(k.root, k.path, 0, KEY_ENUMERATE_SUB_KEYS | KEY_QUERY_VALUE, &h);
    free(k.path);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "keys");
    }
    DWORD count = 0, max_name = 0;
    RegQueryInfoKeyW(h, NULL, NULL, NULL, &count, &max_name, NULL, NULL, NULL, NULL, NULL, NULL);
    wchar_t *name = (wchar_t *)malloc(((size_t)max_name + 2) * sizeof(wchar_t));
    if (name == NULL) {
        RegCloseKey(h);
        return ku_err_raise(L, "REG", "oserror", "out of memory");
    }
    lua_createtable(L, (int)count, 0);
    lua_Integer n = 0;
    for (DWORD i = 0;; i++) {
        DWORD name_length = max_name + 2;
        st = RegEnumKeyExW(h, i, name, &name_length, NULL, NULL, NULL, NULL);
        if (st != ERROR_SUCCESS) {
            break;
        }
        if (!push_wide(L, name, name_length)) {
            RegCloseKey(h);
            free(name);
            return ku_err_fail(L, "REG", "encoding", "a key name is not valid UTF-16");
        }
        lua_rawseti(L, -2, ++n);
    }
    RegCloseKey(h);
    free(name);
    sort_top(L, 0);
    return 1;
}

/* reg.exists(key) */
static int l_reg_exists(lua_State *L)
{
    reg_key k;
    parse_key(L, 1, &k);
    HKEY h = NULL;
    LSTATUS st = RegOpenKeyExW(k.root, k.path, 0, KEY_QUERY_VALUE, &h);
    free(k.path);
    if (st == ERROR_SUCCESS) {
        RegCloseKey(h);
    }
    lua_pushboolean(L, st == ERROR_SUCCESS || st == ERROR_ACCESS_DENIED);
    return 1;
}

/* reg.create(key) */
static int l_reg_create(lua_State *L)
{
    reg_key k;
    parse_key(L, 1, &k);
    HKEY h = NULL;
    LSTATUS st = RegCreateKeyExW(k.root, k.path, 0, NULL, 0, KEY_QUERY_VALUE, NULL, &h, NULL);
    free(k.path);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "create");
    }
    RegCloseKey(h);
    lua_pushboolean(L, 1);
    return 1;
}

/* reg.remove(key) */
static int l_reg_remove(lua_State *L)
{
    reg_key k;
    parse_key(L, 1, &k);
    if (k.path[0] == L'\0' || wcschr(k.path, L'\\') == NULL) {
        free(k.path);
        return ku_err_raise(L, "REG", "badvalue", "remove takes a key at least two levels below a root, such as HKCU\\Software\\Vendor");
    }
    LSTATUS st = RegDeleteTreeW(k.root, k.path);
    free(k.path);
    if (st != ERROR_SUCCESS) {
        return fail(L, st, "remove");
    }
    lua_pushboolean(L, 1);
    return 1;
}

int ku_open_reg(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"get", l_reg_get},       {"set", l_reg_set},       {"delete", l_reg_delete}, {"values", l_reg_values},
        {"keys", l_reg_keys},     {"exists", l_reg_exists}, {"create", l_reg_create}, {"remove", l_reg_remove},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
