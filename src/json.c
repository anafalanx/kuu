/*
 * json.c -- the `json` module on yyjson: strict reading, exact writing.
 *
 *   local v = json.decode(text)          -- or nil, err JSON parse | depth | duplicate
 *   local s = json.encode(v)             -- or raised JSON badvalue for the unencodable
 *   json.encode(v, { pretty = true })
 *   json.null                            -- the one value that means JSON null
 *   json.array(t)                        -- mark t as an array (also: decoded arrays)
 *   json.is_array(t)
 *
 * The mapping, which is the hard part:
 *   null    <-> json.null, a sentinel, so a null inside an array keeps its slot
 *   true/false <-> booleans
 *   number  <-> integer when it is a whole number within 64 bits, else float
 *   string  <-> string (must be UTF-8 both ways; refused otherwise)
 *   array   <-> table with the json.array metatable, elements at 1..n
 *   object  <-> table with string keys
 * An unmarked table encodes as an array when its keys are exactly 1..n with
 * n > 0, and as an object otherwise; `{}` is an object, `json.array{}` is `[]`.
 * Duplicate object keys are refused on decode (last-wins is a silent lie), and
 * nesting is capped at 512 so a hostile document cannot exhaust the stack.
 */
#include "err.h"
#include "wintext.h"

#include "lauxlib.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "yyjson.h"

#define KU_JSON_MAX_DEPTH 512
#define KU_JSON_ARRAY_META "kuu.json.array"
#define KU_JSON_OBJECT_META "kuu.json.object"
#define KU_JSON_NULL_KEY "kuu.json.null"

/* ---- the sentinels -------------------------------------------------------- */

static void push_null(lua_State *L)
{
    lua_getfield(L, LUA_REGISTRYINDEX, KU_JSON_NULL_KEY);
}

static int is_null(lua_State *L, int idx)
{
    if (lua_type(L, idx) != LUA_TUSERDATA && lua_type(L, idx) != LUA_TLIGHTUSERDATA) {
        return 0;
    }
    push_null(L);
    int same = lua_rawequal(L, idx, -1);
    lua_pop(L, 1);
    return same;
}

static void mark_array(lua_State *L, int idx)
{
    idx = lua_absindex(L, idx);
    luaL_getmetatable(L, KU_JSON_ARRAY_META);
    lua_setmetatable(L, idx);
}

static int is_marked_array(lua_State *L, int idx)
{
    if (!lua_getmetatable(L, idx)) {
        return 0;
    }
    luaL_getmetatable(L, KU_JSON_ARRAY_META);
    int same = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    return same;
}

static void mark_object(lua_State *L, int idx)
{
    idx = lua_absindex(L, idx);
    luaL_getmetatable(L, KU_JSON_OBJECT_META);
    lua_setmetatable(L, idx);
}

static int is_marked_object(lua_State *L, int idx)
{
    if (!lua_getmetatable(L, idx)) {
        return 0;
    }
    luaL_getmetatable(L, KU_JSON_OBJECT_META);
    int same = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    return same;
}

/* ---- decode ------------------------------------------------------------------ */

typedef struct decode_state {
    lua_State *L;
    const char *duplicate;
    int too_deep;
} decode_state;

typedef struct key_ref {
    const char *ptr;
    size_t len;
} key_ref;

static int compare_keys(const void *a, const void *b)
{
    const key_ref *x = (const key_ref *)a, *y = (const key_ref *)b;
    if (x->len != y->len) {
        return x->len < y->len ? -1 : 1;
    }
    return memcmp(x->ptr, y->ptr, x->len);
}

/* 1 when the object repeats a key (*bad names it), 0 otherwise, -1 on oom. */
static int has_duplicate(yyjson_val *obj, const char **bad)
{
    size_t n = yyjson_obj_size(obj);
    if (n < 2) {
        return 0;
    }
    yyjson_obj_iter it;
    yyjson_val *k;
    if (n <= 16) {
        yyjson_obj_iter_init(obj, &it);
        while ((k = yyjson_obj_iter_next(&it)) != NULL) {
            yyjson_obj_iter rest = it;
            yyjson_val *k2;
            while ((k2 = yyjson_obj_iter_next(&rest)) != NULL) {
                if (yyjson_get_len(k2) == yyjson_get_len(k) &&
                    memcmp(yyjson_get_str(k2), yyjson_get_str(k), yyjson_get_len(k)) == 0) {
                    *bad = yyjson_get_str(k);
                    return 1;
                }
            }
        }
        return 0;
    }
    key_ref *keys = (key_ref *)malloc(n * sizeof *keys);
    if (keys == NULL) {
        return -1;
    }
    size_t count = 0;
    yyjson_obj_iter_init(obj, &it);
    while (count < n && (k = yyjson_obj_iter_next(&it)) != NULL) {
        keys[count].ptr = yyjson_get_str(k);
        keys[count].len = yyjson_get_len(k);
        count++;
    }
    qsort(keys, count, sizeof *keys, compare_keys);
    for (size_t i = 1; i < count; i++) {
        if (keys[i].len == keys[i - 1].len && memcmp(keys[i].ptr, keys[i - 1].ptr, keys[i].len) == 0) {
            *bad = keys[i].ptr;
            free(keys);
            return 1;
        }
    }
    free(keys);
    return 0;
}

/* Push the Lua value for `v`.  Returns 0 on success; on failure returns -1
 * with the state's duplicate/too_deep set (nothing is left on the stack). */
static int push_value(decode_state *s, yyjson_val *v, int depth)
{
    lua_State *L = s->L;
    if (depth > KU_JSON_MAX_DEPTH) {
        s->too_deep = 1;
        return -1;
    }
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL:
        push_null(L);
        return 0;
    case YYJSON_TYPE_BOOL:
        lua_pushboolean(L, yyjson_get_bool(v));
        return 0;
    case YYJSON_TYPE_NUM:
        switch (yyjson_get_subtype(v)) {
        case YYJSON_SUBTYPE_SINT:
            lua_pushinteger(L, (lua_Integer)yyjson_get_sint(v));
            return 0;
        case YYJSON_SUBTYPE_UINT: {
            uint64_t u = yyjson_get_uint(v);
            if (u <= (uint64_t)INT64_MAX) {
                lua_pushinteger(L, (lua_Integer)u);
            } else {
                lua_pushnumber(L, (lua_Number)u); /* beyond 64-bit signed: a float */
            }
            return 0;
        }
        default:
            lua_pushnumber(L, yyjson_get_real(v));
            return 0;
        }
    case YYJSON_TYPE_STR:
        lua_pushlstring(L, yyjson_get_str(v), yyjson_get_len(v));
        return 0;
    case YYJSON_TYPE_ARR: {
        size_t n = yyjson_arr_size(v);
        luaL_checkstack(L, 4, "json");
        lua_createtable(L, (int)(n > 0x7fffffff ? 0x7fffffff : n), 0);
        mark_array(L, -1);
        yyjson_arr_iter it;
        yyjson_arr_iter_init(v, &it);
        yyjson_val *element;
        lua_Integer i = 1;
        while ((element = yyjson_arr_iter_next(&it)) != NULL) {
            if (push_value(s, element, depth + 1) != 0) {
                lua_pop(L, 1);
                return -1;
            }
            lua_rawseti(L, -2, i++);
        }
        return 0;
    }
    case YYJSON_TYPE_OBJ: {
        const char *bad = NULL;
        int dup = has_duplicate(v, &bad);
        if (dup != 0) {
            s->duplicate = dup > 0 ? bad : "";
            return -1;
        }
        luaL_checkstack(L, 4, "json");
        lua_createtable(L, 0, (int)yyjson_obj_size(v));
        yyjson_obj_iter it;
        yyjson_obj_iter_init(v, &it);
        yyjson_val *key;
        while ((key = yyjson_obj_iter_next(&it)) != NULL) {
            lua_pushlstring(L, yyjson_get_str(key), yyjson_get_len(key));
            if (push_value(s, yyjson_obj_iter_get_val(key), depth + 1) != 0) {
                lua_pop(L, 2);
                return -1;
            }
            lua_rawset(L, -3);
        }
        return 0;
    }
    default:
        push_null(L);
        return 0;
    }
}

/* json.decode(text) -> value | nil, err */
static int l_json_decode(lua_State *L)
{
    size_t length = 0;
    const char *text = luaL_checklstring(L, 1, &length);
    yyjson_read_err error;
    yyjson_doc *doc = yyjson_read_opts((char *)text, length, YYJSON_READ_NOFLAG, NULL, &error);
    if (doc == NULL) {
        return ku_err_fail(L, "JSON", "parse", "%s at byte %zu", error.msg, error.pos);
    }
    decode_state s = {L, NULL, 0};
    int top = lua_gettop(L);
    if (push_value(&s, yyjson_doc_get_root(doc), 1) != 0) {
        lua_settop(L, top);
        /* The duplicate key points into doc: format the error before freeing it. */
        int results = s.too_deep
            ? ku_err_fail(L, "JSON", "depth", "the document nests deeper than %d", KU_JSON_MAX_DEPTH)
            : ku_err_fail(L, "JSON", "duplicate", "object key '%s' appears twice", s.duplicate);
        yyjson_doc_free(doc);
        return results;
    }
    yyjson_doc_free(doc);
    return 1;
}

/* ---- encode ------------------------------------------------------------------ */

/* Is the table at idx a sequence 1..n (n > 0) with no other keys? */
static int is_sequence(lua_State *L, int idx, lua_Integer *length)
{
    idx = lua_absindex(L, idx);
    lua_Integer n = (lua_Integer)lua_rawlen(L, idx);
    lua_Integer seen = 0;
    lua_pushnil(L);
    while (lua_next(L, idx) != 0) {
        lua_pop(L, 1);
        if (!lua_isinteger(L, -1)) {
            lua_pop(L, 1);
            return 0;
        }
        lua_Integer k = lua_tointeger(L, -1);
        if (k < 1 || k > n) {
            lua_pop(L, 1);
            return 0;
        }
        seen++;
    }
    *length = n;
    return seen == n && n > 0;
}

static yyjson_mut_val *build(lua_State *L, yyjson_mut_doc *doc, int idx, int depth)
{
    idx = lua_absindex(L, idx);
    if (depth > KU_JSON_MAX_DEPTH) {
        ku_err_raise(L, "JSON", "depth", "the value nests deeper than %d (a cycle?)", KU_JSON_MAX_DEPTH);
    }
    switch (lua_type(L, idx)) {
    case LUA_TNIL:
        return yyjson_mut_null(doc);
    case LUA_TBOOLEAN:
        return yyjson_mut_bool(doc, lua_toboolean(L, idx));
    case LUA_TNUMBER:
        if (lua_isinteger(L, idx)) {
            return yyjson_mut_sint(doc, (int64_t)lua_tointeger(L, idx));
        } else {
            double d = lua_tonumber(L, idx);
            if (isnan(d) || isinf(d)) {
                ku_err_raise(L, "JSON", "badvalue", "JSON has no representation for NaN or infinity");
            }
            return yyjson_mut_real(doc, d);
        }
    case LUA_TSTRING: {
        size_t length = 0;
        const char *s = lua_tolstring(L, idx, &length);
        if (!ku_utf8_valid((const unsigned char *)s, length)) {
            ku_err_raise(L, "JSON", "encoding", "a string is not valid UTF-8");
        }
        return yyjson_mut_strn(doc, s, length);
    }
    case LUA_TTABLE: {
        lua_Integer n = 0;
        luaL_checkstack(L, 4, "json");
        /* An ordered object: an array of { key, value } pairs emitted in the
         * order given.  A Lua table has no key order, so a document that is
         * compared byte for byte -- a manifest, a lockfile, a golden fixture --
         * cannot be built from one.  Checked before the array tests, because
         * the pair list is itself a sequence. */
        if (is_marked_object(L, idx)) {
            yyjson_mut_val *ordered = yyjson_mut_obj(doc);
            n = (lua_Integer)lua_rawlen(L, idx);
            for (lua_Integer i = 1; i <= n; i++) {
                lua_rawgeti(L, idx, i);
                if (lua_type(L, -1) != LUA_TTABLE || lua_rawlen(L, -1) != 2) {
                    ku_err_raise(L, "JSON", "badvalue",
                                 "json.object entry %d must be a { key, value } pair", (int)i);
                }
                lua_rawgeti(L, -1, 1);
                if (lua_type(L, -1) != LUA_TSTRING) {
                    ku_err_raise(L, "JSON", "badvalue",
                                 "json.object key %d must be a string, got %s",
                                 (int)i, luaL_typename(L, -1));
                }
                size_t klen = 0;
                const char *k = lua_tolstring(L, -1, &klen);
                if (!ku_utf8_valid((const unsigned char *)k, klen)) {
                    ku_err_raise(L, "JSON", "encoding", "an object key is not valid UTF-8");
                }
                yyjson_mut_val *key = yyjson_mut_strn(doc, k, klen);
                lua_pop(L, 1);
                lua_rawgeti(L, -1, 2);
                yyjson_mut_val *value = build(L, doc, -1, depth + 1);
                lua_pop(L, 2);
                yyjson_mut_obj_add(ordered, key, value);
            }
            return ordered;
        }
        if (is_marked_array(L, idx) || is_sequence(L, idx, &n)) {
            yyjson_mut_val *arr = yyjson_mut_arr(doc);
            n = (lua_Integer)lua_rawlen(L, idx);
            for (lua_Integer i = 1; i <= n; i++) {
                lua_rawgeti(L, idx, i);
                yyjson_mut_val *element = build(L, doc, -1, depth + 1);
                lua_pop(L, 1);
                yyjson_mut_arr_append(arr, element);
            }
            return arr;
        }
        yyjson_mut_val *obj = yyjson_mut_obj(doc);
        lua_pushnil(L);
        while (lua_next(L, idx) != 0) {
            if (lua_type(L, -2) != LUA_TSTRING) {
                ku_err_raise(L, "JSON", "badvalue", "object keys must be strings, got %s", luaL_typename(L, -2));
            }
            size_t klen = 0;
            const char *k = lua_tolstring(L, -2, &klen);
            if (!ku_utf8_valid((const unsigned char *)k, klen)) {
                ku_err_raise(L, "JSON", "encoding", "an object key is not valid UTF-8");
            }
            yyjson_mut_val *key = yyjson_mut_strn(doc, k, klen);
            yyjson_mut_val *value = build(L, doc, -1, depth + 1);
            yyjson_mut_obj_add(obj, key, value);
            lua_pop(L, 1);
        }
        return obj;
    }
    case LUA_TUSERDATA:
    case LUA_TLIGHTUSERDATA:
        if (is_null(L, idx)) {
            return yyjson_mut_null(doc);
        }
        /* fall through */
    default:
        ku_err_raise(L, "JSON", "badvalue", "cannot encode a %s", luaL_typename(L, idx));
        return NULL;
    }
}

/* The protected body of encode: (value, doc, pretty) -> text.  build() raises
 * on unencodable values; running it here under lua_pcall lets the caller free
 * the document on either path. */
static int encode_body(lua_State *L)
{
    yyjson_mut_doc *doc = (yyjson_mut_doc *)lua_touserdata(L, 2);
    int pretty = lua_toboolean(L, 3);
    yyjson_mut_val *root = build(L, doc, 1, 1);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_write_err error;
    size_t length = 0;
    char *text = yyjson_mut_write_opts(doc, pretty ? YYJSON_WRITE_PRETTY_TWO_SPACES : YYJSON_WRITE_NOFLAG,
                                       NULL, &length, &error);
    if (text == NULL) {
        return ku_err_raise(L, "JSON", "badvalue", "%s", error.msg);
    }
    lua_pushlstring(L, text, length);
    free(text);
    return 1;
}

/* json.encode(value [, { pretty = true }]) -> text */
static int l_json_encode(lua_State *L)
{
    luaL_checkany(L, 1);
    int pretty = 0;
    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        lua_getfield(L, 2, "pretty");
        pretty = lua_toboolean(L, -1);
        lua_pop(L, 1);
    }
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (doc == NULL) {
        return ku_err_raise(L, "JSON", "oserror", "out of memory");
    }
    lua_pushcfunction(L, encode_body);
    lua_pushvalue(L, 1);
    lua_pushlightuserdata(L, doc);
    lua_pushboolean(L, pretty);
    int status = lua_pcall(L, 3, 1, 0);
    yyjson_mut_doc_free(doc);
    if (status != LUA_OK) {
        return lua_error(L); /* the error object is on top */
    }
    return 1;
}

/* json.array([t]) -> t marked as an array */
static int l_json_array(lua_State *L)
{
    if (lua_isnoneornil(L, 1)) {
        lua_settop(L, 0);
        lua_newtable(L);
    } else {
        luaL_checktype(L, 1, LUA_TTABLE);
        lua_settop(L, 1);
    }
    mark_array(L, 1);
    return 1;
}

static int l_json_is_array(lua_State *L)
{
    lua_pushboolean(L, lua_type(L, 1) == LUA_TTABLE && is_marked_array(L, 1));
    return 1;
}

/* json.object([pairs]) -> pairs marked as an object with a decided key order */
static int l_json_object(lua_State *L)
{
    if (lua_isnoneornil(L, 1)) {
        lua_settop(L, 0);
        lua_newtable(L);
    } else {
        luaL_checktype(L, 1, LUA_TTABLE);
        lua_settop(L, 1);
    }
    mark_object(L, 1);
    return 1;
}

static int l_json_is_object(lua_State *L)
{
    lua_pushboolean(L, lua_type(L, 1) == LUA_TTABLE && is_marked_object(L, 1));
    return 1;
}

static int null_tostring(lua_State *L)
{
    lua_pushliteral(L, "null");
    return 1;
}

int ku_open_json(lua_State *L)
{
    if (luaL_newmetatable(L, KU_JSON_ARRAY_META)) {
        lua_pushliteral(L, "json.array");
        lua_setfield(L, -2, "__name");
    }
    lua_pop(L, 1);
    if (luaL_newmetatable(L, KU_JSON_OBJECT_META)) {
        lua_pushliteral(L, "json.object");
        lua_setfield(L, -2, "__name");
    }
    lua_pop(L, 1);
    /* json.null: one userdata, kept in the registry so every module sees the
     * same value, with a __tostring that says what it is. */
    lua_getfield(L, LUA_REGISTRYINDEX, KU_JSON_NULL_KEY);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newuserdatauv(L, 1, 0);
        lua_createtable(L, 0, 2);
        lua_pushcfunction(L, null_tostring);
        lua_setfield(L, -2, "__tostring");
        lua_pushliteral(L, "json.null");
        lua_setfield(L, -2, "__name");
        lua_setmetatable(L, -2);
        lua_pushvalue(L, -1);
        lua_setfield(L, LUA_REGISTRYINDEX, KU_JSON_NULL_KEY);
    }
    int null_index = lua_gettop(L);
    static const luaL_Reg functions[] = {
        {"decode", l_json_decode},
        {"encode", l_json_encode},
        {"array", l_json_array},
        {"is_array", l_json_is_array},
        {"object", l_json_object},
        {"is_object", l_json_is_object},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    lua_pushvalue(L, null_index);
    lua_setfield(L, -2, "null");
    return 1;
}
