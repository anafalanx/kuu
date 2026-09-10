/*
 * re.c -- the `re` module: regular expressions, on PCRE2.
 *
 *   re.find(s, pattern [, init [, flags]])          -> start, stop, captures... | nil
 *   re.match(s, pattern [, init [, flags]])         -> captures... | the whole match | nil
 *   re.gmatch(s, pattern [, flags])                 -> an iterator over the same
 *   re.gsub(s, pattern, replacement [, n [, flags]]) -> result, count
 *   re.split(s, pattern [, flags])                  -> { piece, ... }
 *   re.exec(s, pattern [, init [, flags]])          -> { start, stop, [1]..[n], name = ... } | nil
 *   re.compile(pattern [, flags])                   -> regex: the same as methods, plus .groups and .names
 *   re.escape(s)                                    -> s with every metacharacter escaped
 *
 * Flags: i caseless, m multiline, s dotall, x extended, b bytes (no UTF),
 * u Unicode classes for \d \w \b.  Patterns and subjects are UTF-8 unless b;
 * a subject that is not valid UTF-8 is refused by name rather than matched
 * wrongly.  A newline is CR, LF, or CRLF.  Replacement strings use $1,
 * ${name}, $0, and $$; a function or table works as in string.gsub.
 * Compiled patterns are cached, so the plain functions cost no more than the
 * methods.  Positions are Lua's: one-based, inclusive, in bytes.
 */
#include "err.h"
#include "hold.h"
#include "state.h"

#include "lauxlib.h"

#ifndef PCRE2_CODE_UNIT_WIDTH
#define PCRE2_CODE_UNIT_WIDTH 8
#endif
#ifndef PCRE2_STATIC
#define PCRE2_STATIC
#endif
#include <pcre2.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define KU_RE_META "kuu.re"
#define KU_RE_CACHE "kuu.re.cache"
#define KU_RE_CACHE_MAX 128
#define KU_RE_NONE ((PCRE2_SIZE)-1)

typedef struct ku_re {
    pcre2_code *code;
    uint32_t groups;
    int utf;
} ku_re;

static ku_re *check_re(lua_State *L, int idx)
{
    return (ku_re *)luaL_checkudata(L, idx, KU_RE_META);
}

static int re_gc(lua_State *L)
{
    ku_re *r = check_re(L, 1);
    if (r->code != NULL) {
        pcre2_code_free(r->code);
        r->code = NULL;
    }
    return 0;
}

/* ---- compiling ------------------------------------------------------------------------- */

static uint32_t parse_flags(lua_State *L, const char *flags, int *utf)
{
    uint32_t options = 0;
    int bytes = 0, ucp = 0;
    for (const char *f = flags; *f != '\0'; f++) {
        switch (*f) {
        case 'i':
            options |= PCRE2_CASELESS;
            break;
        case 'm':
            options |= PCRE2_MULTILINE;
            break;
        case 's':
            options |= PCRE2_DOTALL;
            break;
        case 'x':
            options |= PCRE2_EXTENDED;
            break;
        case 'b':
            bytes = 1;
            break;
        case 'u':
            ucp = 1;
            break;
        default:
            ku_err_raise(L, "RE", "badvalue", "unknown flag '%c'; the flags are i m s x b u", *f);
        }
    }
    if (bytes && ucp) {
        ku_err_raise(L, "RE", "badvalue", "flags b and u exclude each other");
    }
    *utf = !bytes;
    if (!bytes) {
        options |= PCRE2_UTF;
    }
    if (ucp) {
        options |= PCRE2_UCP;
    }
    return options | PCRE2_NEVER_BACKSLASH_C;
}

/* The table of group names, name -> number, built once per pattern. */
static void push_names(lua_State *L, pcre2_code *code)
{
    uint32_t count = 0, entry_size = 0;
    PCRE2_SPTR table = NULL;
    pcre2_pattern_info(code, PCRE2_INFO_NAMECOUNT, &count);
    pcre2_pattern_info(code, PCRE2_INFO_NAMEENTRYSIZE, &entry_size);
    pcre2_pattern_info(code, PCRE2_INFO_NAMETABLE, &table);
    lua_createtable(L, 0, (int)count);
    for (uint32_t i = 0; i < count && table != NULL; i++) {
        PCRE2_SPTR entry = table + (size_t)i * entry_size;
        int number = (entry[0] << 8) | entry[1];
        lua_pushinteger(L, number);
        lua_setfield(L, -2, (const char *)(entry + 2));
    }
}

/* Compile, or raise RE badpattern; leaves the new regex on the stack. */
static ku_re *compile_new(lua_State *L, const char *pattern, size_t length, const char *flags)
{
    int utf = 1;
    uint32_t options = parse_flags(L, flags, &utf);
    int code_error = 0;
    PCRE2_SIZE offset = 0;
    pcre2_code *code = pcre2_compile((PCRE2_SPTR)pattern, length, options, &code_error, &offset, NULL);
    if (code == NULL) {
        PCRE2_UCHAR message[256];
        pcre2_get_error_message(code_error, message, sizeof message);
        ku_err_raise(L, "RE", "badpattern", "%s, at offset %u in the pattern", (const char *)message, (unsigned)offset);
    }
    ku_re *r = (ku_re *)lua_newuserdatauv(L, sizeof *r, 1);
    r->code = code;
    r->groups = 0;
    r->utf = utf;
    luaL_setmetatable(L, KU_RE_META);
    pcre2_pattern_info(code, PCRE2_INFO_CAPTURECOUNT, &r->groups);
    push_names(L, code);
    lua_setiuservalue(L, -2, 1);
    return r;
}

/* The regex for (pattern, flags), from the cache or freshly compiled; the
 * regex is left on the stack so that it stays alive for the caller. */
static ku_re *cached(lua_State *L, int pattern_idx, int flags_idx)
{
    size_t length = 0;
    const char *pattern = luaL_checklstring(L, pattern_idx, &length);
    const char *flags = luaL_optstring(L, flags_idx, "");
    lua_getfield(L, LUA_REGISTRYINDEX, KU_RE_CACHE);
    /* the key: flags, a NUL, the pattern */
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    luaL_addstring(&b, flags);
    luaL_addchar(&b, '\0');
    luaL_addlstring(&b, pattern, length);
    luaL_pushresult(&b);
    lua_pushvalue(L, -1);
    lua_gettable(L, -3); /* [cache, key, regex?] */
    ku_re *r = (ku_re *)luaL_testudata(L, -1, KU_RE_META);
    if (r != NULL) {
        lua_remove(L, -2);
        lua_remove(L, -2); /* [regex] */
        return r;
    }
    lua_pop(L, 1); /* [cache, key] */
    lua_pushnil(L);
    int entries = 0;
    while (lua_next(L, -3) != 0) {
        lua_pop(L, 1);
        if (++entries >= KU_RE_CACHE_MAX) {
            lua_pop(L, 1);
            break;
        }
    }
    if (entries >= KU_RE_CACHE_MAX) {
        /* full: start over rather than grow without bound */
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, LUA_REGISTRYINDEX, KU_RE_CACHE);
        lua_replace(L, -3); /* [newcache, key] */
    }
    r = compile_new(L, pattern, length, flags); /* [cache, key, regex] */
    lua_pushvalue(L, -2);
    lua_pushvalue(L, -2);
    lua_settable(L, -5); /* cache[key] = regex */
    lua_remove(L, -2);
    lua_remove(L, -2); /* [regex] */
    return r;
}

/* ---- matching -------------------------------------------------------------------------- */

/* Match offsets belong to an operation, never to the cached pattern.  Lua
 * callbacks and table metamethods can run that same pattern recursively. */
static void match_free(void *ptr)
{
    pcre2_match_data_free((pcre2_match_data *)ptr);
}

static pcre2_match_data *new_match(lua_State *L, ku_re *r, int close)
{
    ku_hold *hold = ku_hold_new(L, match_free);
    if (close) {
        lua_toclose(L, -1);
    }
    hold->ptr = pcre2_match_data_create_from_pattern(r->code, NULL);
    if (hold->ptr == NULL) {
        ku_err_raise(L, "RE", "oserror", "out of memory");
    }
    return (pcre2_match_data *)hold->ptr;
}

/* pcre2_match with kuu's error mapping: the count of set pairs, or
 * PCRE2_ERROR_NOMATCH; anything else is raised. */
static int do_match(lua_State *L, ku_re *r, pcre2_match_data *match, const char *s, size_t n, size_t start, uint32_t options)
{
    int rc = pcre2_match(r->code, (PCRE2_SPTR)s, n, start, options, match, NULL);
    if (rc >= 0 || rc == PCRE2_ERROR_NOMATCH) {
        return rc;
    }
    if (rc == PCRE2_ERROR_MATCHLIMIT || rc == PCRE2_ERROR_DEPTHLIMIT || rc == PCRE2_ERROR_HEAPLIMIT) {
        return ku_err_raise(L, "RE", "limit", "the match exceeded the engine's limits; the pattern is likely catastrophic on this input");
    }
    if (rc <= PCRE2_ERROR_UTF8_ERR1 && rc >= PCRE2_ERROR_UTF8_ERR21) {
        return ku_err_raise(L, "RE", "invalid", "the subject is not valid UTF-8 at byte %u; flag b matches bytes",
                            (unsigned)pcre2_get_startchar(match) + 1);
    }
    if (rc == PCRE2_ERROR_BADUTFOFFSET) {
        return ku_err_raise(L, "RE", "invalid", "init is inside a UTF-8 character");
    }
    PCRE2_UCHAR message[256];
    pcre2_get_error_message(rc, message, sizeof message);
    return ku_err_raise(L, "RE", "oserror", "%s", (const char *)message);
}

/* Push the captures of the last match, or the whole match when the pattern
 * has none; unset groups are nil.  Returns the count pushed. */
static int push_captures(lua_State *L, ku_re *r, pcre2_match_data *match, const char *s, int pairs)
{
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
    if (r->groups == 0) {
        lua_pushlstring(L, s + ov[0], ov[1] - ov[0]);
        return 1;
    }
    luaL_checkstack(L, (int)r->groups + 2, "too many captures");
    for (uint32_t i = 1; i <= r->groups; i++) {
        if ((int)i >= pairs || ov[2 * i] == PCRE2_UNSET) {
            lua_pushnil(L);
        } else {
            lua_pushlstring(L, s + ov[2 * i], ov[2 * i + 1] - ov[2 * i]);
        }
    }
    return (int)r->groups;
}

/* Lua's init: one-based, negative from the end; the zero-based offset, or
 * n + 1 when it lies beyond the subject. */
static size_t start_offset(lua_State *L, int idx, size_t n)
{
    lua_Integer init = luaL_optinteger(L, idx, 1);
    if (init < 0) {
        init = (lua_Integer)n + init + 1;
        if (init < 1) {
            init = 1;
        }
    } else if (init == 0) {
        init = 1;
    }
    if ((size_t)init > n + 1) {
        return n + 1;
    }
    return (size_t)init - 1;
}

/* One character forward, past a CRLF as one; n + 1 at the end. */
static size_t advance(const char *s, size_t n, size_t pos, int utf)
{
    if (pos >= n) {
        return n + 1;
    }
    if (s[pos] == '\r' && pos + 1 < n && s[pos + 1] == '\n') {
        return pos + 2;
    }
    pos++;
    if (utf) {
        while (pos < n && ((unsigned char)s[pos] & 0xC0) == 0x80) {
            pos++;
        }
    }
    return pos;
}

/* The next match at or after `pos`, never an empty match at `empty_at`
 * (the previous empty match), so that iteration always progresses.
 * Returns pairs (> 0) with *pos advanced past the match, or 0 at the end.
 * PCRE2 validates the whole subject as UTF-8 on every call; within one
 * operation the subject cannot change, so once a call has validated it,
 * *checked says so and the rest skip the scan, or a megabyte of gsub would
 * be quadratic. */
static int next_match(lua_State *L, ku_re *r, pcre2_match_data *match, const char *s, size_t n, size_t *pos, size_t *empty_at, int *checked)
{
    for (;;) {
        if (*pos > n) {
            return 0;
        }
        int retry = *empty_at == *pos;
        uint32_t options = retry ? (PCRE2_NOTEMPTY_ATSTART | PCRE2_ANCHORED) : 0;
        if (*checked) {
            options |= PCRE2_NO_UTF_CHECK;
        }
        int rc = do_match(L, r, match, s, n, *pos, options);
        *checked = 1; /* it returned, so the subject passed */
        if (rc == PCRE2_ERROR_NOMATCH) {
            if (!retry) {
                *pos = n + 1;
                return 0;
            }
            *pos = advance(s, n, *pos, r->utf);
            *empty_at = KU_RE_NONE;
            continue;
        }
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
        *empty_at = (ov[1] == ov[0]) ? ov[1] : KU_RE_NONE;
        *pos = ov[1];
        return rc;
    }
}

/* ---- the operations, shared by functions and methods ----------------------------------- */

static int find_impl(lua_State *L, ku_re *r, int sidx, int init_idx)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, sidx, &n);
    size_t start = start_offset(L, init_idx, n);
    if (start > n) {
        lua_pushnil(L);
        return 1;
    }
    pcre2_match_data *match = new_match(L, r, 1);
    int rc = do_match(L, r, match, s, n, start, 0);
    if (rc == PCRE2_ERROR_NOMATCH) {
        lua_pushnil(L);
        return 1;
    }
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
    lua_pushinteger(L, (lua_Integer)ov[0] + 1);
    lua_pushinteger(L, (lua_Integer)ov[1]);
    if (r->groups == 0) {
        return 2;
    }
    return 2 + push_captures(L, r, match, s, rc);
}

static int match_impl(lua_State *L, ku_re *r, int sidx, int init_idx)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, sidx, &n);
    size_t start = start_offset(L, init_idx, n);
    if (start > n) {
        lua_pushnil(L);
        return 1;
    }
    pcre2_match_data *match = new_match(L, r, 1);
    int rc = do_match(L, r, match, s, n, start, 0);
    if (rc == PCRE2_ERROR_NOMATCH) {
        lua_pushnil(L);
        return 1;
    }
    return push_captures(L, r, match, s, rc);
}

static int exec_impl(lua_State *L, ku_re *r, int ridx, int sidx, int init_idx)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, sidx, &n);
    size_t start = start_offset(L, init_idx, n);
    if (start > n) {
        lua_pushnil(L);
        return 1;
    }
    pcre2_match_data *match = new_match(L, r, 1);
    int rc = do_match(L, r, match, s, n, start, 0);
    if (rc == PCRE2_ERROR_NOMATCH) {
        lua_pushnil(L);
        return 1;
    }
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
    lua_createtable(L, (int)r->groups, 2);
    lua_pushinteger(L, (lua_Integer)ov[0] + 1);
    lua_setfield(L, -2, "start");
    lua_pushinteger(L, (lua_Integer)ov[1]);
    lua_setfield(L, -2, "stop");
    for (uint32_t i = 1; i <= r->groups; i++) {
        if ((int)i >= rc || ov[2 * i] == PCRE2_UNSET) {
            lua_pushboolean(L, 0);
        } else {
            lua_pushlstring(L, s + ov[2 * i], ov[2 * i + 1] - ov[2 * i]);
        }
        lua_rawseti(L, -2, (lua_Integer)i);
    }
    /* named groups: name = the same value */
    lua_getiuservalue(L, ridx, 1);
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        lua_Integer number = lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_pushvalue(L, -1);        /* the name */
        lua_rawgeti(L, -4, number);  /* the value */
        lua_settable(L, -5);         /* result[name] = value */
    }
    lua_pop(L, 1);
    return 1;
}

/* gmatch: a closure over the subject (1), the regex (2), the next offset
 * (3), the offset of the previous empty match (4), and whether the subject
 * has been validated as UTF-8 (5), and its own match block (6). */
static int gmatch_iter(lua_State *L)
{
    size_t n = 0;
    const char *s = lua_tolstring(L, lua_upvalueindex(1), &n);
    ku_re *r = (ku_re *)lua_touserdata(L, lua_upvalueindex(2));
    size_t pos = (size_t)lua_tointeger(L, lua_upvalueindex(3));
    lua_Integer empty_raw = lua_tointeger(L, lua_upvalueindex(4));
    size_t empty_at = empty_raw < 0 ? KU_RE_NONE : (size_t)empty_raw;
    int checked = lua_toboolean(L, lua_upvalueindex(5));
    ku_hold *hold = (ku_hold *)lua_touserdata(L, lua_upvalueindex(6));
    pcre2_match_data *match = (pcre2_match_data *)hold->ptr;
    int rc = next_match(L, r, match, s, n, &pos, &empty_at, &checked);
    lua_pushinteger(L, (lua_Integer)pos);
    lua_replace(L, lua_upvalueindex(3));
    lua_pushinteger(L, empty_at == KU_RE_NONE ? -1 : (lua_Integer)empty_at);
    lua_replace(L, lua_upvalueindex(4));
    lua_pushboolean(L, checked);
    lua_replace(L, lua_upvalueindex(5));
    if (rc == 0) {
        return 0;
    }
    return push_captures(L, r, match, s, rc);
}

static int gmatch_impl(lua_State *L, int ridx, int sidx)
{
    luaL_checklstring(L, sidx, NULL);
    lua_pushvalue(L, sidx);
    lua_pushvalue(L, ridx);
    lua_pushinteger(L, 0);
    lua_pushinteger(L, -1);
    lua_pushboolean(L, 0);
    new_match(L, check_re(L, ridx), 0);
    lua_pushcclosure(L, gmatch_iter, 6);
    return 1;
}

/* Append the expansion of a replacement string: $0, $1..$99, ${name}, $$. */
static void expand_replacement(lua_State *L, luaL_Buffer *b, ku_re *r, pcre2_match_data *match, int ridx, const char *s, int pairs,
                               const char *repl, size_t rlen)
{
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
    for (size_t i = 0; i < rlen; i++) {
        if (repl[i] != '$') {
            luaL_addchar(b, repl[i]);
            continue;
        }
        if (i + 1 >= rlen) {
            ku_err_raise(L, "RE", "badvalue", "a lone $ ends the replacement; write $$ for a dollar");
        }
        char c = repl[i + 1];
        long group = -1;
        if (c == '$') {
            luaL_addchar(b, '$');
            i++;
            continue;
        }
        if (c >= '0' && c <= '9') {
            group = c - '0';
            i++;
            if (i + 1 < rlen && repl[i + 1] >= '0' && repl[i + 1] <= '9') {
                group = group * 10 + (repl[i + 1] - '0');
                i++;
            }
        } else if (c == '{') {
            const char *close = memchr(repl + i + 2, '}', rlen - i - 2);
            if (close == NULL) {
                ku_err_raise(L, "RE", "badvalue", "an unclosed ${ in the replacement");
            }
            size_t name_len = (size_t)(close - (repl + i + 2));
            char name[64];
            if (name_len == 0 || name_len >= sizeof name) {
                ku_err_raise(L, "RE", "badvalue", "a bad group name in the replacement");
            }
            memcpy(name, repl + i + 2, name_len);
            name[name_len] = '\0';
            int digits = 1;
            for (size_t k = 0; k < name_len; k++) {
                if (name[k] < '0' || name[k] > '9') {
                    digits = 0;
                }
            }
            if (digits) {
                group = strtol(name, NULL, 10);
            } else {
                lua_getiuservalue(L, ridx, 1);
                lua_getfield(L, -1, name);
                if (!lua_isinteger(L, -1)) {
                    ku_err_raise(L, "RE", "badvalue", "the pattern has no group named '%s'", name);
                }
                group = (long)lua_tointeger(L, -1);
                lua_pop(L, 2);
            }
            i += name_len + 2;
        } else {
            ku_err_raise(L, "RE", "badvalue", "a bad $ escape in the replacement; write $$ for a dollar");
        }
        if (group > (long)r->groups) {
            ku_err_raise(L, "RE", "badvalue", "the replacement names group %ld, the pattern has %u", group, (unsigned)r->groups);
        }
        if (group < pairs && ov[2 * group] != PCRE2_UNSET) {
            luaL_addlstring(b, s + ov[2 * group], ov[2 * group + 1] - ov[2 * group]);
        }
    }
}

/* Append the replacement for the current match, whatever kind `ridx_repl` is. */
static void add_replacement(lua_State *L, luaL_Buffer *b, ku_re *r, pcre2_match_data *match, int ridx, int repl_idx, const char *s, int pairs)
{
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
    size_t start = ov[0], stop = ov[1];
    int type = lua_type(L, repl_idx);
    if (type == LUA_TSTRING || type == LUA_TNUMBER) {
        size_t rlen = 0;
        const char *repl = lua_tolstring(L, repl_idx, &rlen);
        expand_replacement(L, b, r, match, ridx, s, pairs, repl, rlen);
        return;
    }
    if (type == LUA_TFUNCTION) {
        lua_pushvalue(L, repl_idx);
        int pushed = push_captures(L, r, match, s, pairs);
        lua_call(L, pushed, 1);
    } else { /* a table: looked up by the first capture, or the whole match */
        if (r->groups == 0 || pairs <= 1 || ov[2] == PCRE2_UNSET) {
            lua_pushlstring(L, s + ov[0], ov[1] - ov[0]);
        } else {
            lua_pushlstring(L, s + ov[2], ov[3] - ov[2]);
        }
        lua_gettable(L, repl_idx);
    }
    if (lua_isnil(L, -1) || (lua_isboolean(L, -1) && !lua_toboolean(L, -1))) {
        lua_pop(L, 1);
        luaL_addlstring(b, s + start, stop - start); /* bounds saved before calling Lua */
        return;
    }
    if (lua_type(L, -1) != LUA_TSTRING && lua_type(L, -1) != LUA_TNUMBER) {
        ku_err_raise(L, "RE", "badvalue", "a replacement must be a string or a number, got %s", luaL_typename(L, -1));
    }
    luaL_addvalue(b);
}

static int gsub_impl(lua_State *L, ku_re *r, int ridx, int sidx, int repl_idx, int n_idx)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, sidx, &n);
    int type = lua_type(L, repl_idx);
    if (type != LUA_TSTRING && type != LUA_TNUMBER && type != LUA_TFUNCTION && type != LUA_TTABLE) {
        return ku_err_raise(L, "RE", "badvalue", "the replacement must be a string, a function, or a table");
    }
    lua_Integer max = luaL_optinteger(L, n_idx, -1);
    pcre2_match_data *match = new_match(L, r, 1);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    size_t pos = 0, empty_at = KU_RE_NONE, last = 0;
    int checked = 0;
    lua_Integer count = 0;
    while (max < 0 || count < max) {
        int rc = next_match(L, r, match, s, n, &pos, &empty_at, &checked);
        if (rc == 0) {
            break;
        }
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
        luaL_addlstring(&b, s + last, ov[0] - last);
        last = ov[1]; /* keep the outer bounds before calling Lua */
        add_replacement(L, &b, r, match, ridx, repl_idx, s, rc);
        count++;
    }
    if (last < n) {
        luaL_addlstring(&b, s + last, n - last);
    }
    luaL_pushresult(&b);
    lua_pushinteger(L, count);
    return 2;
}

static int split_impl(lua_State *L, ku_re *r, int sidx)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, sidx, &n);
    pcre2_match_data *match = new_match(L, r, 1);
    lua_newtable(L);
    lua_Integer count = 0;
    size_t pos = 0, empty_at = KU_RE_NONE, last = 0;
    int checked = 0;
    for (;;) {
        int rc = next_match(L, r, match, s, n, &pos, &empty_at, &checked);
        if (rc == 0) {
            break;
        }
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(match);
        if (ov[0] == ov[1]) {
            if (ov[0] == last || ov[0] >= n) {
                continue; /* an empty match at a boundary makes no piece */
            }
        }
        lua_pushlstring(L, s + last, ov[0] - last);
        lua_rawseti(L, -2, ++count);
        last = ov[1];
    }
    lua_pushlstring(L, s + last, n - last);
    lua_rawseti(L, -2, ++count);
    return 1;
}

/* ---- the functions --------------------------------------------------------------------- */

/* The functions fix their argument count before fetching the regex, which
 * `cached` leaves on top, so an omitted argument stays nil in its slot. */
static int l_re_find(lua_State *L)
{
    lua_settop(L, 4);
    ku_re *r = cached(L, 2, 4);
    return find_impl(L, r, 1, 3);
}

static int l_re_match(lua_State *L)
{
    lua_settop(L, 4);
    ku_re *r = cached(L, 2, 4);
    return match_impl(L, r, 1, 3);
}

static int l_re_exec(lua_State *L)
{
    lua_settop(L, 4);
    ku_re *r = cached(L, 2, 4);
    return exec_impl(L, r, 5, 1, 3);
}

static int l_re_gmatch(lua_State *L)
{
    lua_settop(L, 3);
    cached(L, 2, 3);
    return gmatch_impl(L, 4, 1);
}

static int l_re_gsub(lua_State *L)
{
    lua_settop(L, 5);
    ku_re *r = cached(L, 2, 5);
    return gsub_impl(L, r, 6, 1, 3, 4);
}

static int l_re_split(lua_State *L)
{
    lua_settop(L, 3);
    ku_re *r = cached(L, 2, 3);
    return split_impl(L, r, 1);
}

static int l_re_compile(lua_State *L)
{
    size_t length = 0;
    const char *pattern = luaL_checklstring(L, 1, &length);
    const char *flags = luaL_optstring(L, 2, "");
    compile_new(L, pattern, length, flags);
    return 1;
}

static int l_re_escape(lua_State *L)
{
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        int plain = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c >= 0x80;
        if (!plain) {
            luaL_addchar(&b, '\\');
        }
        luaL_addchar(&b, (char)c);
    }
    luaL_pushresult(&b);
    return 1;
}

/* ---- the methods ----------------------------------------------------------------------- */

static int m_find(lua_State *L)
{
    return find_impl(L, check_re(L, 1), 2, 3);
}

static int m_match(lua_State *L)
{
    return match_impl(L, check_re(L, 1), 2, 3);
}

static int m_exec(lua_State *L)
{
    return exec_impl(L, check_re(L, 1), 1, 2, 3);
}

static int m_gmatch(lua_State *L)
{
    check_re(L, 1);
    return gmatch_impl(L, 1, 2);
}

static int m_gsub(lua_State *L)
{
    return gsub_impl(L, check_re(L, 1), 1, 2, 3, 4);
}

static int m_split(lua_State *L)
{
    return split_impl(L, check_re(L, 1), 2);
}

static int re_index(lua_State *L)
{
    ku_re *r = check_re(L, 1);
    const char *key = luaL_checkstring(L, 2);
    if (strcmp(key, "groups") == 0) {
        lua_pushinteger(L, (lua_Integer)r->groups);
        return 1;
    }
    if (strcmp(key, "names") == 0) {
        lua_getiuservalue(L, 1, 1);
        return 1;
    }
    lua_getfield(L, lua_upvalueindex(1), key); /* the methods */
    return 1;
}

static int re_tostring(lua_State *L)
{
    ku_re *r = check_re(L, 1);
    lua_pushfstring(L, "kuu.re (%d groups)", (int)r->groups);
    return 1;
}

int ku_open_re(lua_State *L)
{
    if (luaL_newmetatable(L, KU_RE_META)) {
        static const luaL_Reg methods[] = {
            {"find", m_find}, {"match", m_match}, {"exec", m_exec}, {"gmatch", m_gmatch},
            {"gsub", m_gsub}, {"split", m_split}, {NULL, NULL},
        };
        luaL_newlib(L, methods);
        lua_pushcclosure(L, re_index, 1);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, re_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, re_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
    lua_getfield(L, LUA_REGISTRYINDEX, KU_RE_CACHE);
    if (lua_isnil(L, -1)) {
        lua_newtable(L);
        lua_setfield(L, LUA_REGISTRYINDEX, KU_RE_CACHE);
    }
    lua_pop(L, 1);
    static const luaL_Reg functions[] = {
        {"find", l_re_find},     {"match", l_re_match}, {"exec", l_re_exec},       {"gmatch", l_re_gmatch},
        {"gsub", l_re_gsub},     {"split", l_re_split}, {"compile", l_re_compile}, {"escape", l_re_escape},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
