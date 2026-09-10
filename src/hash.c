/*
 * hash.c -- the `hash` module: digests, HMAC, and random bytes from Windows CNG.
 *
 *   hash.sum("sha256", bytes)           -- lowercase hex
 *   hash.sum("sha256", bytes, { raw = true })   -- the digest bytes
 *   hash.file("sha256", path)           -- streamed, 64 KiB at a time
 *   hash.hmac("sha256", key, bytes)
 *   hash.random(32)                     -- bytes from the system RNG
 *   local h = hash.start("sha256"); h:update(a); h:update(b); h:final()
 *   hash.algorithms()                   -- { "md5", "sha1", "sha256", "sha384", "sha512" }
 *
 * Lua strings are bytes, so the question machteld had to settle by a byte rule
 * (which bytes of a value get hashed) does not arise: what you pass is what is
 * hashed, and `hash.sum("sha256", "abc")` agrees with sha256sum everywhere.
 * bcrypt.dll is part of Windows; nothing is vendored.
 */
#include "err.h"
#include "fspath.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <stdlib.h>
#include <string.h>

#define KU_HASH_META "kuu.hash"
#define KU_HASH_CHUNK (64 * 1024)
#define KU_HASH_MAX_DIGEST 64
#define KU_HASH_RANDOM_MAX (1 << 20)

typedef struct algorithm {
    const char *name;
    LPCWSTR id;
} algorithm;

/* A table of values rather than functions: `hash.algorithms()` answers from it,
 * so the manual can never claim a set the binary does not have. */
static const algorithm ALGORITHMS[] = {
    {"md5", BCRYPT_MD5_ALGORITHM},
    {"sha1", BCRYPT_SHA1_ALGORITHM},
    {"sha256", BCRYPT_SHA256_ALGORITHM},
    {"sha384", BCRYPT_SHA384_ALGORITHM},
    {"sha512", BCRYPT_SHA512_ALGORITHM},
    {NULL, NULL},
};

typedef struct ku_hasher {
    BCRYPT_ALG_HANDLE provider;
    BCRYPT_HASH_HANDLE hash;
    DWORD digest_length;
    int finished;
} ku_hasher;

static const algorithm *find_algorithm(lua_State *L, int idx)
{
    const char *name = luaL_checkstring(L, idx);
    for (const algorithm *a = ALGORITHMS; a->name != NULL; a++) {
        if (strcmp(a->name, name) == 0) {
            return a;
        }
    }
    ku_err_raise(L, "HASH", "badvalue", "unknown algorithm '%s'; see hash.algorithms()", name);
    return NULL;
}

/* Open a provider and a hash object; `key` non-NULL makes it an HMAC.  On
 * failure raises HASH oserror. */
static void open_hasher(lua_State *L, const algorithm *a, const unsigned char *key, size_t key_length,
                        ku_hasher *h)
{
    memset(h, 0, sizeof *h);
    ULONG flags = key != NULL ? BCRYPT_ALG_HANDLE_HMAC_FLAG : 0;
    if (BCryptOpenAlgorithmProvider(&h->provider, a->id, NULL, flags) != 0) {
        ku_err_raise(L, "HASH", "oserror", "cannot open the %s provider", a->name);
    }
    DWORD length = 0, written = 0;
    if (BCryptGetProperty(h->provider, BCRYPT_HASH_LENGTH, (PUCHAR)&length, sizeof length, &written, 0) != 0 ||
        length == 0 || length > KU_HASH_MAX_DIGEST) {
        BCryptCloseAlgorithmProvider(h->provider, 0);
        ku_err_raise(L, "HASH", "oserror", "cannot read the %s digest length", a->name);
    }
    h->digest_length = length;
    if (key_length > ULONG_MAX) {
        BCryptCloseAlgorithmProvider(h->provider, 0);
        ku_err_raise(L, "HASH", "badvalue", "the HMAC key is too large");
    }
    if (BCryptCreateHash(h->provider, &h->hash, NULL, 0, (PUCHAR)key, (ULONG)key_length, 0) != 0) {
        BCryptCloseAlgorithmProvider(h->provider, 0);
        ku_err_raise(L, "HASH", "oserror", "cannot create the %s hash object", a->name);
    }
}

static void close_hasher(ku_hasher *h)
{
    if (h->hash != NULL) {
        BCryptDestroyHash(h->hash);
        h->hash = NULL;
    }
    if (h->provider != NULL) {
        BCryptCloseAlgorithmProvider(h->provider, 0);
        h->provider = NULL;
    }
}

static int hasher_update(ku_hasher *h, const unsigned char *data, size_t length)
{
    while (length > 0) {
        ULONG chunk = length > 0x7fffffff ? 0x7fffffff : (ULONG)length;
        if (BCryptHashData(h->hash, (PUCHAR)data, chunk, 0) != 0) {
            return -1;
        }
        data += chunk;
        length -= chunk;
    }
    return 0;
}

static void push_digest(lua_State *L, const unsigned char *digest, DWORD length, int raw)
{
    if (raw) {
        lua_pushlstring(L, (const char *)digest, length);
        return;
    }
    static const char HEX[] = "0123456789abcdef";
    char hex[2 * KU_HASH_MAX_DIGEST];
    for (DWORD i = 0; i < length; i++) {
        hex[2 * i] = HEX[digest[i] >> 4];
        hex[2 * i + 1] = HEX[digest[i] & 15];
    }
    lua_pushlstring(L, hex, 2 * length);
}

/* The optional trailing options table: { raw = true } */
static int want_raw(lua_State *L, int idx)
{
    if (lua_isnoneornil(L, idx)) {
        return 0;
    }
    luaL_checktype(L, idx, LUA_TTABLE);
    lua_getfield(L, idx, "raw");
    int raw = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return raw;
}

/* hash.sum(algorithm, data [, { raw = true }]) */
static int l_hash_sum(lua_State *L)
{
    const algorithm *a = find_algorithm(L, 1);
    size_t length = 0;
    const char *data = luaL_checklstring(L, 2, &length);
    int raw = want_raw(L, 3);
    ku_hasher h;
    open_hasher(L, a, NULL, 0, &h);
    unsigned char digest[KU_HASH_MAX_DIGEST];
    int ok = hasher_update(&h, (const unsigned char *)data, length) == 0 &&
             BCryptFinishHash(h.hash, digest, h.digest_length, 0) == 0;
    close_hasher(&h);
    if (!ok) {
        return ku_err_raise(L, "HASH", "oserror", "hashing failed");
    }
    push_digest(L, digest, h.digest_length, raw);
    return 1;
}

/* hash.hmac(algorithm, key, data [, { raw = true }]) */
static int l_hash_hmac(lua_State *L)
{
    const algorithm *a = find_algorithm(L, 1);
    size_t key_length = 0, length = 0;
    const char *key = luaL_checklstring(L, 2, &key_length);
    const char *data = luaL_checklstring(L, 3, &length);
    int raw = want_raw(L, 4);
    ku_hasher h;
    open_hasher(L, a, (const unsigned char *)key, key_length, &h);
    unsigned char digest[KU_HASH_MAX_DIGEST];
    int ok = hasher_update(&h, (const unsigned char *)data, length) == 0 &&
             BCryptFinishHash(h.hash, digest, h.digest_length, 0) == 0;
    close_hasher(&h);
    if (!ok) {
        return ku_err_raise(L, "HASH", "oserror", "hmac failed");
    }
    push_digest(L, digest, h.digest_length, raw);
    return 1;
}

/* hash.file(algorithm, path [, { raw = true }]) -> hex | nil, err */
static int l_hash_file(lua_State *L)
{
    const algorithm *a = find_algorithm(L, 1);
    const char *path = ku_check_cstring(L, 2, "HASH", "file path");
    int raw = want_raw(L, 3);
    ku_wpath wide;
    ku_fail fail;
    if (ku_wpath_make(path, &wide, &fail) != 0) {
        return ku_err_fail(L, "HASH", fail.code, "%s", fail.message);
    }
    HANDLE file = CreateFileW(wide.text, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                              FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    DWORD error = file == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
    ku_wpath_free(&wide);
    if (file == INVALID_HANDLE_VALUE) {
        char *text = ku_win_error_message(error);
        const char *code = (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) ? "notfound"
                           : error == ERROR_ACCESS_DENIED                                    ? "access"
                                                                                             : "oserror";
        int n = ku_err_fail(L, "HASH", code, "cannot open '%s': %s", path, text != NULL ? text : "");
        free(text);
        return n;
    }
    ku_hasher h;
    open_hasher(L, a, NULL, 0, &h);
    unsigned char *buffer = (unsigned char *)malloc(KU_HASH_CHUNK);
    if (buffer == NULL) {
        close_hasher(&h);
        CloseHandle(file);
        return ku_err_raise(L, "HASH", "oserror", "out of memory");
    }
    DWORD read_error = 0;
    int ok = 1;
    for (;;) {
        DWORD got = 0;
        if (!ReadFile(file, buffer, KU_HASH_CHUNK, &got, NULL)) {
            read_error = GetLastError();
            ok = 0;
            break;
        }
        if (got == 0) {
            break;
        }
        if (hasher_update(&h, buffer, got) != 0) {
            ok = 0;
            break;
        }
    }
    free(buffer);
    CloseHandle(file);
    unsigned char digest[KU_HASH_MAX_DIGEST];
    if (ok && BCryptFinishHash(h.hash, digest, h.digest_length, 0) != 0) {
        ok = 0;
    }
    close_hasher(&h);
    if (!ok) {
        char *text = read_error != 0 ? ku_win_error_message(read_error) : NULL;
        int n = ku_err_fail(L, "HASH", "oserror", "cannot read '%s': %s", path,
                            text != NULL ? text : "hashing failed");
        free(text);
        return n;
    }
    push_digest(L, digest, h.digest_length, raw);
    return 1;
}

/* hash.random(count) -> bytes */
static int l_hash_random(lua_State *L)
{
    lua_Integer count = luaL_checkinteger(L, 1);
    if (count < 1 || count > KU_HASH_RANDOM_MAX) {
        return ku_err_raise(L, "HASH", "badvalue", "count must be between 1 and %d", KU_HASH_RANDOM_MAX);
    }
    unsigned char *buffer = (unsigned char *)malloc((size_t)count);
    if (buffer == NULL) {
        return ku_err_raise(L, "HASH", "oserror", "out of memory");
    }
    if (BCryptGenRandom(NULL, buffer, (ULONG)count, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
        free(buffer);
        return ku_err_raise(L, "HASH", "oserror", "the system random generator failed");
    }
    lua_pushlstring(L, (const char *)buffer, (size_t)count);
    free(buffer);
    return 1;
}

/* hash.uuid() -> a random UUID (version 4), lower case, with hyphens */
static int l_hash_uuid(lua_State *L)
{
    unsigned char b[16];
    if (BCryptGenRandom(NULL, b, sizeof b, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
        return ku_err_raise(L, "HASH", "oserror", "the system random generator failed");
    }
    b[6] = (unsigned char)((b[6] & 0x0f) | 0x40); /* version 4 */
    b[8] = (unsigned char)((b[8] & 0x3f) | 0x80); /* variant 1 */
    char text[37];
    snprintf(text, sizeof text, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", b[0], b[1],
             b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]);
    lua_pushstring(L, text);
    return 1;
}

static int l_hash_algorithms(lua_State *L)
{
    lua_newtable(L);
    int i = 1;
    for (const algorithm *a = ALGORITHMS; a->name != NULL; a++) {
        lua_pushstring(L, a->name);
        lua_rawseti(L, -2, i++);
    }
    return 1;
}

/* ---- incremental hashing ------------------------------------------------ */

static ku_hasher *check_hasher(lua_State *L)
{
    ku_hasher *h = (ku_hasher *)luaL_checkudata(L, 1, KU_HASH_META);
    if (h->hash == NULL) {
        ku_err_raise(L, "HASH", "closed", "this hash has already been finished");
    }
    return h;
}

/* hash.start(algorithm) -> hasher */
static int l_hash_start(lua_State *L)
{
    const algorithm *a = find_algorithm(L, 1);
    ku_hasher *h = (ku_hasher *)lua_newuserdatauv(L, sizeof *h, 0);
    memset(h, 0, sizeof *h);
    luaL_setmetatable(L, KU_HASH_META);
    open_hasher(L, a, NULL, 0, h);
    return 1;
}

static int l_hasher_update(lua_State *L)
{
    ku_hasher *h = check_hasher(L);
    size_t length = 0;
    const char *data = luaL_checklstring(L, 2, &length);
    if (hasher_update(h, (const unsigned char *)data, length) != 0) {
        return ku_err_raise(L, "HASH", "oserror", "hashing failed");
    }
    lua_settop(L, 1);
    return 1; /* the hasher, for chaining */
}

static int l_hasher_final(lua_State *L)
{
    ku_hasher *h = check_hasher(L);
    int raw = want_raw(L, 2);
    unsigned char digest[KU_HASH_MAX_DIGEST];
    int ok = BCryptFinishHash(h->hash, digest, h->digest_length, 0) == 0;
    DWORD length = h->digest_length;
    close_hasher(h);
    if (!ok) {
        return ku_err_raise(L, "HASH", "oserror", "hashing failed");
    }
    push_digest(L, digest, length, raw);
    return 1;
}

static int l_hasher_gc(lua_State *L)
{
    ku_hasher *h = (ku_hasher *)luaL_checkudata(L, 1, KU_HASH_META);
    close_hasher(h);
    return 0;
}

int ku_open_hash(lua_State *L)
{
    if (luaL_newmetatable(L, KU_HASH_META)) {
        static const luaL_Reg methods[] = {
            {"update", l_hasher_update},
            {"final", l_hasher_final},
            {NULL, NULL},
        };
        luaL_newlib(L, methods);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_hasher_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, l_hasher_gc);
        lua_setfield(L, -2, "__close");
    }
    lua_pop(L, 1);
    static const luaL_Reg functions[] = {
        {"sum", l_hash_sum},
        {"hmac", l_hash_hmac},
        {"file", l_hash_file},
        {"random", l_hash_random},
        {"start", l_hash_start},
        {"algorithms", l_hash_algorithms},
        {"uuid", l_hash_uuid},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
