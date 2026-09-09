/*
 * text.c -- the `text` module: strict conversions between UTF-8 and the
 * encodings Windows programs actually emit.
 *
 *   text.decode(bytes, "cp1252")     -- UTF-8, or nil, err TEXT invalid
 *   text.encode(str, "utf-16le")     -- bytes, or nil, err TEXT unencodable
 *   text.valid(bytes)                -- true when the bytes are strict UTF-8
 *   text.encodings()                 -- the names accepted
 *
 * Every conversion is strict: a byte sequence that is not valid in the named
 * encoding is refused, never replaced by U+FFFD or a best-fit character,
 * because a silently rewritten name or path is worse than a reported one.
 * Encodings: utf-8, utf-16le, utf-16be, latin1, ansi (the system code page),
 * oem (the console code page), and cpNNN for any Windows code page number.
 */
#include "err.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

enum { ENC_UTF8 = -1, ENC_UTF16LE = -2, ENC_UTF16BE = -3 };

static int lower_eq(const char *a, const char *b)
{
    while (*a && *b) {
        char x = *a, y = *b;
        if (x >= 'A' && x <= 'Z') {
            x = (char)(x + 32);
        }
        if (y >= 'A' && y <= 'Z') {
            y = (char)(y + 32);
        }
        if (x != y) {
            return 0;
        }
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

/* Resolve an encoding name to a code page or one of the ENC_ constants;
 * returns 0 when the name is unknown. */
static int resolve_encoding(const char *name, int *out)
{
    if (lower_eq(name, "utf-8") || lower_eq(name, "utf8")) {
        *out = ENC_UTF8;
    } else if (lower_eq(name, "utf-16le") || lower_eq(name, "utf-16") || lower_eq(name, "utf16le")) {
        *out = ENC_UTF16LE;
    } else if (lower_eq(name, "utf-16be") || lower_eq(name, "utf16be")) {
        *out = ENC_UTF16BE;
    } else if (lower_eq(name, "latin1") || lower_eq(name, "iso-8859-1")) {
        *out = 28591;
    } else if (lower_eq(name, "ansi")) {
        *out = (int)GetACP();
    } else if (lower_eq(name, "oem")) {
        *out = (int)GetOEMCP();
    } else if ((name[0] == 'c' || name[0] == 'C') && (name[1] == 'p' || name[1] == 'P') && name[2] != '\0') {
        char *end = NULL;
        long page = strtol(name + 2, &end, 10);
        if (*end != '\0' || page <= 0 || page > 65535) {
            return 0;
        }
        *out = (int)page;
    } else {
        return 0;
    }
    return 1;
}

static void swap_utf16(wchar_t *units, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        unsigned u = (unsigned)units[i];
        units[i] = (wchar_t)(((u & 0xff) << 8) | (u >> 8));
    }
}

/* Bytes in the given encoding -> UTF-16 (malloc'd), strict.  Returns 0, or -1
 * on invalid input, -2 on an unsupported code page, -3 on allocation. */
static int to_wide(const unsigned char *bytes, size_t length, int encoding, wchar_t **out, size_t *out_count)
{
    if (encoding == ENC_UTF16LE || encoding == ENC_UTF16BE) {
        if (length % 2 != 0) {
            return -1;
        }
        size_t count = length / 2;
        wchar_t *w = (wchar_t *)malloc((count + 1) * sizeof(wchar_t));
        if (w == NULL) {
            return -3;
        }
        memcpy(w, bytes, length);
        if (encoding == ENC_UTF16BE) {
            swap_utf16(w, count);
        }
        for (size_t i = 0; i < count; i++) { /* surrogates must pair */
            unsigned u = (unsigned)w[i];
            if (u >= 0xd800 && u <= 0xdbff) {
                if (i + 1 >= count || (unsigned)w[i + 1] < 0xdc00 || (unsigned)w[i + 1] > 0xdfff) {
                    free(w);
                    return -1;
                }
                i++;
            } else if (u >= 0xdc00 && u <= 0xdfff) {
                free(w);
                return -1;
            }
        }
        w[count] = L'\0';
        *out = w;
        *out_count = count;
        return 0;
    }
    UINT page = encoding == ENC_UTF8 ? CP_UTF8 : (UINT)encoding;
    if (length == 0) {
        wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t));
        if (w == NULL) {
            return -3;
        }
        w[0] = L'\0';
        *out = w;
        *out_count = 0;
        return 0;
    }
    if (length > (size_t)INT_MAX) {
        return -1;
    }
    /* MB_ERR_INVALID_CHARS is what makes the conversion strict.  Code pages
     * that do not support the flag (a few legacy ones) fail with
     * ERROR_INVALID_FLAGS, reported as unsupported rather than converted
     * leniently. */
    int n = MultiByteToWideChar(page, MB_ERR_INVALID_CHARS, (const char *)bytes, (int)length, NULL, 0);
    if (n <= 0) {
        DWORD error = GetLastError();
        return (error == ERROR_INVALID_PARAMETER || error == ERROR_INVALID_FLAGS) ? -2 : -1;
    }
    wchar_t *w = (wchar_t *)malloc(((size_t)n + 1) * sizeof(wchar_t));
    if (w == NULL) {
        return -3;
    }
    if (MultiByteToWideChar(page, MB_ERR_INVALID_CHARS, (const char *)bytes, (int)length, w, n) <= 0) {
        free(w);
        return -1;
    }
    w[n] = L'\0';
    *out = w;
    *out_count = (size_t)n;
    return 0;
}

/* UTF-16 -> bytes in the given encoding (malloc'd), strict: a character the
 * code page cannot represent is refused (-1), never best-fit. */
static int from_wide(const wchar_t *w, size_t count, int encoding, unsigned char **out, size_t *out_length)
{
    if (encoding == ENC_UTF16LE || encoding == ENC_UTF16BE) {
        size_t length = count * 2;
        unsigned char *bytes = (unsigned char *)malloc(length + 1);
        if (bytes == NULL) {
            return -3;
        }
        memcpy(bytes, w, length);
        if (encoding == ENC_UTF16BE) {
            swap_utf16((wchar_t *)bytes, count);
        }
        *out = bytes;
        *out_length = length;
        return 0;
    }
    UINT page = encoding == ENC_UTF8 ? CP_UTF8 : (UINT)encoding;
    if (count == 0) {
        unsigned char *bytes = (unsigned char *)malloc(1);
        if (bytes == NULL) {
            return -3;
        }
        bytes[0] = 0;
        *out = bytes;
        *out_length = 0;
        return 0;
    }
    if (count > (size_t)INT_MAX) {
        return -1;
    }
    /* WC_ERR_INVALID_CHARS exists only for UTF-8; other code pages report
     * unrepresentable characters through lpUsedDefaultChar. */
    DWORD flags = page == CP_UTF8 ? WC_ERR_INVALID_CHARS : WC_NO_BEST_FIT_CHARS;
    BOOL used_default = FALSE;
    LPBOOL used = page == CP_UTF8 ? NULL : &used_default;
    int n = WideCharToMultiByte(page, flags, w, (int)count, NULL, 0, NULL, used);
    if (n <= 0) {
        DWORD error = GetLastError();
        if (error == ERROR_INVALID_FLAGS) { /* a code page without WC_NO_BEST_FIT_CHARS */
            return -2;
        }
        return (error == ERROR_INVALID_PARAMETER) ? -2 : -1;
    }
    if (used_default) {
        return -1;
    }
    unsigned char *bytes = (unsigned char *)malloc((size_t)n + 1);
    if (bytes == NULL) {
        return -3;
    }
    if (WideCharToMultiByte(page, flags, w, (int)count, (char *)bytes, n, NULL, used) <= 0 || used_default) {
        free(bytes);
        return -1;
    }
    bytes[n] = 0;
    *out = bytes;
    *out_length = (size_t)n;
    return 0;
}

static int report(lua_State *L, int status, const char *encoding, const char *what)
{
    switch (status) {
    case -1:
        return ku_err_fail(L, "TEXT", "invalid", "the %s is not valid %s", what, encoding);
    case -2:
        return ku_err_fail(L, "TEXT", "unsupported", "encoding '%s' is not available on this system", encoding);
    default:
        return ku_err_raise(L, "TEXT", "oserror", "out of memory");
    }
}

/* text.decode(bytes, encoding) -> utf8 | nil, err */
static int l_text_decode(lua_State *L)
{
    size_t length = 0;
    const char *bytes = luaL_checklstring(L, 1, &length);
    const char *name = luaL_checkstring(L, 2);
    int encoding = 0;
    if (!resolve_encoding(name, &encoding)) {
        return ku_err_raise(L, "TEXT", "badvalue", "unknown encoding '%s'; see text.encodings()", name);
    }
    if (encoding == ENC_UTF8) { /* validation only; no conversion needed */
        if (!ku_utf8_valid((const unsigned char *)bytes, length)) {
            return ku_err_fail(L, "TEXT", "invalid", "the bytes are not valid UTF-8");
        }
        lua_settop(L, 1);
        return 1;
    }
    wchar_t *wide = NULL;
    size_t count = 0;
    int status = to_wide((const unsigned char *)bytes, length, encoding, &wide, &count);
    if (status != 0) {
        return report(L, status, name, "input");
    }
    unsigned char *utf8 = NULL;
    size_t utf8_length = 0;
    status = from_wide(wide, count, ENC_UTF8, &utf8, &utf8_length);
    free(wide);
    if (status != 0) {
        return report(L, status, name, "input");
    }
    lua_pushlstring(L, (const char *)utf8, utf8_length);
    free(utf8);
    return 1;
}

/* text.encode(utf8, encoding) -> bytes | nil, err */
static int l_text_encode(lua_State *L)
{
    size_t length = 0;
    const char *text = luaL_checklstring(L, 1, &length);
    const char *name = luaL_checkstring(L, 2);
    int encoding = 0;
    if (!resolve_encoding(name, &encoding)) {
        return ku_err_raise(L, "TEXT", "badvalue", "unknown encoding '%s'; see text.encodings()", name);
    }
    if (!ku_utf8_valid((const unsigned char *)text, length)) {
        return ku_err_fail(L, "TEXT", "invalid", "the string is not valid UTF-8");
    }
    if (encoding == ENC_UTF8) {
        lua_settop(L, 1);
        return 1;
    }
    wchar_t *wide = NULL;
    size_t count = 0;
    int status = to_wide((const unsigned char *)text, length, ENC_UTF8, &wide, &count);
    if (status != 0) {
        return report(L, status, "UTF-8", "string");
    }
    unsigned char *bytes = NULL;
    size_t bytes_length = 0;
    status = from_wide(wide, count, encoding, &bytes, &bytes_length);
    free(wide);
    if (status == -1) {
        return ku_err_fail(L, "TEXT", "unencodable", "the string has characters that %s cannot represent", name);
    }
    if (status != 0) {
        return report(L, status, name, "string");
    }
    lua_pushlstring(L, (const char *)bytes, bytes_length);
    free(bytes);
    return 1;
}

static int l_text_valid(lua_State *L)
{
    size_t length = 0;
    const char *bytes = luaL_checklstring(L, 1, &length);
    lua_pushboolean(L, ku_utf8_valid((const unsigned char *)bytes, length));
    return 1;
}

/* ---- base64 and hex ------------------------------------------------------------------ */

static const char B64_STANDARD[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const char B64_URL[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/* text.tobase64(bytes [, { url = true }]) -> text.  The url alphabet uses
 * '-' and '_' and carries no padding. */
static int l_text_tobase64(lua_State *L)
{
    size_t n = 0;
    const unsigned char *in = (const unsigned char *)luaL_checklstring(L, 1, &n);
    int url = 0;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "url");
        url = lua_toboolean(L, -1);
        lua_pop(L, 1);
    }
    const char *alphabet = url ? B64_URL : B64_STANDARD;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    size_t i = 0;
    for (; i + 3 <= n; i += 3) {
        unsigned v = ((unsigned)in[i] << 16) | ((unsigned)in[i + 1] << 8) | in[i + 2];
        char quad[4] = {alphabet[v >> 18], alphabet[(v >> 12) & 63], alphabet[(v >> 6) & 63], alphabet[v & 63]};
        luaL_addlstring(&b, quad, 4);
    }
    if (i < n) {
        int two = i + 1 < n;
        unsigned v = (unsigned)in[i] << 16;
        if (two) {
            v |= (unsigned)in[i + 1] << 8;
        }
        char quad[4] = {alphabet[v >> 18], alphabet[(v >> 12) & 63], two ? alphabet[(v >> 6) & 63] : '=', '='};
        luaL_addlstring(&b, quad, url ? (size_t)(two ? 3 : 2) : 4);
    }
    luaL_pushresult(&b);
    return 1;
}

static int b64_value(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') {
        return c - 'A';
    }
    if (c >= 'a' && c <= 'z') {
        return c - 'a' + 26;
    }
    if (c >= '0' && c <= '9') {
        return c - '0' + 52;
    }
    if (c == '+' || c == '-') {
        return 62;
    }
    if (c == '/' || c == '_') {
        return 63;
    }
    return -1;
}

/* text.frombase64(text) -> bytes | nil, err.  Either alphabet, padding
 * optional, whitespace ignored; anything else is TEXT invalid. */
static int l_text_frombase64(lua_State *L)
{
    size_t n = 0;
    const unsigned char *in = (const unsigned char *)luaL_checklstring(L, 1, &n);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    unsigned acc = 0;
    int bits = 0;
    int padded = 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = in[i];
        if (c == '\r' || c == '\n' || c == ' ' || c == '\t') {
            continue;
        }
        if (c == '=') {
            padded = 1;
            continue;
        }
        if (padded) {
            return ku_err_fail(L, "TEXT", "invalid", "base64 has data after its padding, at byte %zu", i + 1);
        }
        int v = b64_value(c);
        if (v < 0) {
            return ku_err_fail(L, "TEXT", "invalid", "not base64: byte %u at %zu", (unsigned)c, i + 1);
        }
        acc = (acc << 6) | (unsigned)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            luaL_addchar(&b, (char)((acc >> bits) & 0xff));
        }
    }
    if (bits >= 6) {
        return ku_err_fail(L, "TEXT", "invalid", "base64 ends with a lone character");
    }
    luaL_pushresult(&b);
    return 1;
}

/* text.tohex(bytes) -> lower-case hex; text.fromhex(text) -> bytes | nil, err */
static int l_text_tohex(lua_State *L)
{
    size_t n = 0;
    const unsigned char *in = (const unsigned char *)luaL_checklstring(L, 1, &n);
    static const char digits[] = "0123456789abcdef";
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (size_t i = 0; i < n; i++) {
        luaL_addchar(&b, digits[in[i] >> 4]);
        luaL_addchar(&b, digits[in[i] & 15]);
    }
    luaL_pushresult(&b);
    return 1;
}

static int l_text_fromhex(lua_State *L)
{
    size_t n = 0;
    const unsigned char *in = (const unsigned char *)luaL_checklstring(L, 1, &n);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    int have = 0;
    unsigned value = 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = in[i];
        unsigned digit;
        if (c == '\r' || c == '\n' || c == ' ' || c == '\t') {
            continue;
        }
        if (c >= '0' && c <= '9') {
            digit = c - '0';
        } else if (c >= 'a' && c <= 'f') {
            digit = c - 'a' + 10;
        } else if (c >= 'A' && c <= 'F') {
            digit = c - 'A' + 10;
        } else {
            return ku_err_fail(L, "TEXT", "invalid", "not hex: byte %u at %zu", (unsigned)c, i + 1);
        }
        value = (value << 4) | digit;
        if (++have == 2) {
            luaL_addchar(&b, (char)value);
            have = 0;
            value = 0;
        }
    }
    if (have != 0) {
        return ku_err_fail(L, "TEXT", "invalid", "hex has an odd number of digits");
    }
    luaL_pushresult(&b);
    return 1;
}

/* ---- case ---------------------------------------------------------------------------- */

/* text.upper(s), text.lower(s) -> the string case-mapped by Windows' invariant
 * rules, which are the rules the file system folds names with; Lua's own
 * string.upper knows ASCII only.  Invalid UTF-8 is nil, err TEXT invalid. */
static int case_map(lua_State *L, DWORD flag)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    if (n == 0) {
        lua_pushliteral(L, "");
        return 1;
    }
    if (n > 0x3fffffff) {
        return ku_err_fail(L, "TEXT", "toobig", "the string is too long to case-map");
    }
    int wide_len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, (int)n, NULL, 0);
    if (wide_len <= 0) {
        return ku_err_fail(L, "TEXT", "invalid", "the string is not valid UTF-8");
    }
    wchar_t *wide = (wchar_t *)malloc((size_t)wide_len * sizeof(wchar_t));
    if (wide == NULL) {
        return ku_err_raise(L, "TEXT", "oserror", "out of memory");
    }
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, (int)n, wide, wide_len);
    int mapped_len = LCMapStringEx(LOCALE_NAME_INVARIANT, flag, wide, wide_len, NULL, 0, NULL, NULL, 0);
    wchar_t *mapped = mapped_len > 0 ? (wchar_t *)malloc((size_t)mapped_len * sizeof(wchar_t)) : NULL;
    if (mapped == NULL || LCMapStringEx(LOCALE_NAME_INVARIANT, flag, wide, wide_len, mapped, mapped_len, NULL, NULL, 0) <= 0) {
        free(wide);
        free(mapped);
        return ku_err_raise(L, "TEXT", "oserror", "the case mapping failed");
    }
    free(wide);
    int utf8_len = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, mapped, mapped_len, NULL, 0, NULL, NULL);
    char *utf8 = utf8_len > 0 ? (char *)malloc((size_t)utf8_len) : NULL;
    if (utf8 == NULL || WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, mapped, mapped_len, utf8, utf8_len, NULL, NULL) <= 0) {
        free(mapped);
        free(utf8);
        return ku_err_raise(L, "TEXT", "oserror", "the case mapping failed");
    }
    free(mapped);
    lua_pushlstring(L, utf8, (size_t)utf8_len);
    free(utf8);
    return 1;
}

static int l_text_upper(lua_State *L)
{
    return case_map(L, LCMAP_UPPERCASE);
}

static int l_text_lower(lua_State *L)
{
    return case_map(L, LCMAP_LOWERCASE);
}

static int l_text_encodings(lua_State *L)
{
    static const char *const names[] = {"utf-8", "utf-16le", "utf-16be", "latin1", "ansi", "oem", "cpNNN", NULL};
    lua_newtable(L);
    for (int i = 0; names[i] != NULL; i++) {
        lua_pushstring(L, names[i]);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

int ku_open_text(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"decode", l_text_decode},
        {"encode", l_text_encode},
        {"valid", l_text_valid},
        {"encodings", l_text_encodings},
        {"tobase64", l_text_tobase64},
        {"frombase64", l_text_frombase64},
        {"tohex", l_text_tohex},
        {"fromhex", l_text_fromhex},
        {"upper", l_text_upper},
        {"lower", l_text_lower},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
