/*
 * fs.c -- the `fs` module: files and directories as Windows actually has them.
 *
 *   fs.read(path [, { encoding = "utf-8", maxbytes = "1G" }])  -> bytes | nil, err
 *   fs.write(path, data [, { atomic = true, append = false }]) -> true | nil, err
 *   fs.stat(path [, { follow = true }])   -> table | nil, err
 *   fs.exists(path)                       -> "file" | "directory" | "link" | "other" | false
 *   fs.mkdir(path [, { parents = true }]) -> true | nil, err
 *   fs.remove(path [, { recursive = false }])
 *   fs.rename(from, to [, { replace = false }])
 *   fs.copy(from, to [, { replace = false }])
 *   fs.list(dir)                          -> { entries = {...}, errors = {...} }
 *   fs.dirs(root [, { depth, prune }])    -> the walk (fs_dirs.c)
 *   fs.canon(path)                        -> { path, volume, file, kind, links }
 *   fs.same(a, b)                         -> boolean
 *   fs.link(path)                         -> false | { type, target, tag }
 *   fs.watch(dir [, opts])                -> watcher (fs_watch.c)
 *   fs.cwd(), fs.chdir(path), fs.temp(), fs.absolute(path)
 *   fs.tempfile { dir, prefix, suffix }, fs.tempdir { dir, prefix } -> a new path
 *   fs.space(dir)                         -> { total, free, available } bytes
 *   join, dirname, basename, ext, stem, relative, glob: Lua, in lua/fs/path.lua
 *
 * Paths in are UTF-8 and become `\\?\`-prefixed absolute UTF-16 (fspath.h);
 * paths out are UTF-8 with forward slashes.  Identity comes from handles, not
 * names.  A malformed path raises FS badvalue; a path that is not there is
 * `nil, err` with FS notfound.
 */
#include "err.h"
#include "fs_internal.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <bcrypt.h>

#define KU_FS_DEFAULT_MAXREAD ((int64_t)1 << 30)

/* ---- helpers ------------------------------------------------------------------- */

static void path_arg(lua_State *L, int idx, ku_wpath *out)
{
    const char *utf8 = luaL_checkstring(L, idx);
    ku_fail fail;
    if (ku_wpath_make(utf8, out, &fail) != 0) {
        ku_err_raise(L, fail.domain, fail.code, "%s", fail.message);
    }
}

static int fail_with(lua_State *L, const ku_fail *fail)
{
    return ku_err_fail(L, fail->domain, fail->code, "%s", fail->message);
}

static int fail_win(lua_State *L, DWORD error, const char *verb, const char *what)
{
    ku_fail fail;
    ku_fs_fail(&fail, error, verb, what);
    return fail_with(L, &fail);
}

static int opt_boolean(lua_State *L, int idx, const char *name, int fallback)
{
    if (lua_isnoneornil(L, idx)) {
        return fallback;
    }
    luaL_checktype(L, idx, LUA_TTABLE);
    lua_getfield(L, idx, name);
    int value = lua_isnil(L, -1) ? fallback : lua_toboolean(L, -1);
    lua_pop(L, 1);
    return value;
}

static void check_options(lua_State *L, int idx, const char *const *allowed)
{
    if (lua_isnoneornil(L, idx)) {
        return;
    }
    luaL_checktype(L, idx, LUA_TTABLE);
    lua_pushnil(L);
    while (lua_next(L, idx) != 0) {
        lua_pop(L, 1);
        const char *key = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : NULL;
        int known = 0;
        for (int i = 0; key != NULL && allowed[i] != NULL; i++) {
            if (strcmp(key, allowed[i]) == 0) {
                known = 1;
                break;
            }
        }
        if (!known) {
            ku_err_raise(L, "FS", "usage", "unknown option '%s'", key != NULL ? key : "?");
        }
    }
}

static const char *kind_of(DWORD attributes, DWORD tag)
{
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) && ku_tag_is_name(tag)) {
        return "link";
    }
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
        return "directory";
    }
    if (attributes & FILE_ATTRIBUTE_DEVICE) {
        return "other";
    }
    return "file";
}

/* Open for metadata; `follow` == 0 opens a reparse point itself. */
static HANDLE open_meta(const wchar_t *path, int follow)
{
    DWORD flags = FILE_FLAG_BACKUP_SEMANTICS;
    if (!follow) {
        flags |= FILE_FLAG_OPEN_REPARSE_POINT;
    }
    return CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                       OPEN_EXISTING, flags, NULL);
}

/* ---- read / write ----------------------------------------------------------------- */

/* fs.read(path [, { encoding = "utf-8", maxbytes = size }]) */
static int l_fs_read(lua_State *L)
{
    static const char *const options[] = {"encoding", "maxbytes", NULL};
    check_options(L, 2, options);
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    int64_t max_bytes = KU_FS_DEFAULT_MAXREAD;
    const char *encoding = NULL;
    if (!lua_isnoneornil(L, 2)) {
        lua_getfield(L, 2, "maxbytes");
        if (!lua_isnil(L, -1) && ku_check_bytes(L, -1, &max_bytes) != 0) {
            ku_wpath_free(&path);
            return ku_err_raise(L, "FS", "badvalue", "maxbytes must be a size such as \"16M\"");
        }
        lua_pop(L, 1);
        lua_getfield(L, 2, "encoding");
        if (!lua_isnil(L, -1)) {
            encoding = luaL_checkstring(L, -1);
        }
        lua_pop(L, 1);
    }
    HANDLE h = CreateFileW(path.text, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                           OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "open", shown);
    }
    ku_wpath_free(&path);
    if (GetFileType(h) != FILE_TYPE_DISK) {
        CloseHandle(h);
        return ku_err_fail(L, "FS", "badvalue", "'%s' is not a regular file", shown);
    }
    LARGE_INTEGER size;
    if (!GetFileSizeEx(h, &size)) {
        DWORD error = GetLastError();
        CloseHandle(h);
        return fail_win(L, error, "measure", shown);
    }
    if (size.QuadPart > max_bytes) {
        CloseHandle(h);
        return ku_err_fail(L, "FS", "toobig", "'%s' is %lld bytes, over the %lld byte limit", shown,
                           (long long)size.QuadPart, (long long)max_bytes);
    }
    size_t wanted = (size_t)size.QuadPart;
    unsigned char *bytes = (unsigned char *)malloc(wanted > 0 ? wanted : 1);
    if (bytes == NULL) {
        CloseHandle(h);
        return ku_err_raise(L, "FS", "oserror", "out of memory reading '%s'", shown);
    }
    size_t got = 0;
    while (got < wanted) {
        DWORD chunk = (wanted - got) > 0x40000000 ? 0x40000000 : (DWORD)(wanted - got);
        DWORD received = 0;
        if (!ReadFile(h, bytes + got, chunk, &received, NULL)) {
            DWORD error = GetLastError();
            free(bytes);
            CloseHandle(h);
            return fail_win(L, error, "read", shown);
        }
        if (received == 0) {
            break;
        }
        got += received;
    }
    CloseHandle(h);
    if (encoding == NULL) {
        lua_pushlstring(L, (const char *)bytes, got);
        free(bytes);
        return 1;
    }
    /* Text: a UTF-8 BOM is dropped, then the bytes are decoded strictly
     * through the text module. */
    size_t start = (got >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) ? 3 : 0;
    lua_pushlstring(L, (const char *)bytes + start, got - start);
    free(bytes);
    lua_getglobal(L, "require");
    lua_pushliteral(L, "text");
    lua_call(L, 1, 1);
    lua_getfield(L, -1, "decode");
    lua_pushvalue(L, -3);   /* the bytes */
    lua_pushstring(L, encoding);
    lua_call(L, 2, 2);      /* decoded | nil, err */
    if (lua_isnil(L, -2)) {
        return 2;           /* nil, err from text.decode (TEXT invalid) */
    }
    lua_pop(L, 1);
    return 1;
}

static int write_all(HANDLE h, const unsigned char *data, size_t length, DWORD *error)
{
    size_t done = 0;
    while (done < length) {
        DWORD chunk = (length - done) > 0x40000000 ? 0x40000000 : (DWORD)(length - done);
        DWORD written = 0;
        if (!WriteFile(h, data + done, chunk, &written, NULL)) {
            *error = GetLastError();
            return -1;
        }
        done += written;
    }
    return 0;
}

/* fs.write(path, data [, { atomic = true, append = false }]) */
static int l_fs_write(lua_State *L)
{
    static const char *const options[] = {"atomic", "append", NULL};
    check_options(L, 3, options);
    size_t length = 0;
    const char *data = luaL_checklstring(L, 2, &length);
    int append = opt_boolean(L, 3, "append", 0);
    int atomic = opt_boolean(L, 3, "atomic", !append);
    if (append && atomic) {
        return ku_err_raise(L, "FS", "usage", "append and atomic cannot both be set");
    }
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    DWORD error = 0;
    if (!atomic) {
        HANDLE h = CreateFileW(path.text, GENERIC_WRITE | (append ? FILE_APPEND_DATA : 0), FILE_SHARE_READ, NULL,
                               append ? OPEN_ALWAYS : CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h == INVALID_HANDLE_VALUE) {
            error = GetLastError();
            ku_wpath_free(&path);
            return fail_win(L, error, "open for writing", shown);
        }
        if (append) {
            LARGE_INTEGER zero = {{0, 0}};
            SetFilePointerEx(h, zero, NULL, FILE_END);
        }
        int rc = write_all(h, (const unsigned char *)data, length, &error);
        CloseHandle(h);
        ku_wpath_free(&path);
        if (rc != 0) {
            return fail_win(L, error, "write", shown);
        }
        lua_pushboolean(L, 1);
        return 1;
    }
    /* Atomic: write a sibling temporary file, then rename it over the target,
     * so the destination holds either the old bytes or all of the new ones. */
    wchar_t suffix[48];
    _snwprintf(suffix, sizeof suffix / sizeof suffix[0], L".kuu-%lu-%llu.tmp", (unsigned long)GetCurrentProcessId(),
               (unsigned long long)GetTickCount64());
    size_t temp_length = path.length + wcslen(suffix);
    wchar_t *temp = (wchar_t *)malloc((temp_length + 1) * sizeof(wchar_t));
    if (temp == NULL) {
        ku_wpath_free(&path);
        return ku_err_raise(L, "FS", "oserror", "out of memory");
    }
    wcscpy(temp, path.text);
    wcscat(temp, suffix);
    HANDLE h = CreateFileW(temp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        free(temp);
        ku_wpath_free(&path);
        return fail_win(L, error, "create a temporary file beside", shown);
    }
    int rc = write_all(h, (const unsigned char *)data, length, &error);
    if (rc == 0 && !FlushFileBuffers(h)) {
        error = GetLastError();
        rc = -1;
    }
    CloseHandle(h);
    if (rc != 0) {
        DeleteFileW(temp);
        free(temp);
        ku_wpath_free(&path);
        return fail_win(L, error, "write", shown);
    }
    if (!MoveFileExW(temp, path.text, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        error = GetLastError();
        DeleteFileW(temp);
        free(temp);
        ku_wpath_free(&path);
        return fail_win(L, error, "replace", shown);
    }
    free(temp);
    ku_wpath_free(&path);
    lua_pushboolean(L, 1);
    return 1;
}

/* ---- stat / exists ------------------------------------------------------------------ */

static void push_time(lua_State *L, LONGLONG filetime, const char *field)
{
    lua_pushnumber(L, ku_fs_time_seconds(filetime));
    lua_setfield(L, -2, field);
}

static void push_identity(lua_State *L, const BY_HANDLE_FILE_INFORMATION *info)
{
    /* Fixed-width hex strings, not integers: a 64-bit index does not fit a
     * signed integer on every volume, and identity is compared, not computed. */
    char volume[24], file[24];
    snprintf(volume, sizeof volume, "%016llx", (unsigned long long)info->dwVolumeSerialNumber);
    snprintf(file, sizeof file, "%016llx",
             ((unsigned long long)info->nFileIndexHigh << 32) | (unsigned long long)info->nFileIndexLow);
    lua_pushstring(L, volume);
    lua_setfield(L, -2, "volume");
    lua_pushstring(L, file);
    lua_setfield(L, -2, "file");
    lua_pushinteger(L, (lua_Integer)info->nNumberOfLinks);
    lua_setfield(L, -2, "links");
}

/* Open following (or not); on a dangling link report FS dangling rather than
 * notfound.  Returns INVALID_HANDLE_VALUE after pushing nil, err. */
static HANDLE open_or_fail(lua_State *L, const ku_wpath *path, const char *shown, int follow, int *pushed)
{
    *pushed = 0;
    HANDLE h = open_meta(path->text, follow);
    if (h != INVALID_HANDLE_VALUE) {
        return h;
    }
    DWORD error = GetLastError();
    if (follow) {
        HANDLE raw = open_meta(path->text, 0);
        if (raw != INVALID_HANDLE_VALUE) {
            CloseHandle(raw);
            *pushed = ku_err_fail(L, "FS", "dangling", "'%s' exists but its target cannot be resolved", shown);
            return INVALID_HANDLE_VALUE;
        }
    }
    *pushed = fail_win(L, error, "open", shown);
    return INVALID_HANDLE_VALUE;
}

/* fs.stat(path [, { follow = true }]) */
static int l_fs_stat(lua_State *L)
{
    static const char *const options[] = {"follow", NULL};
    check_options(L, 2, options);
    int follow = opt_boolean(L, 2, "follow", 1);
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    int pushed = 0;
    HANDLE h = open_or_fail(L, &path, shown, follow, &pushed);
    ku_wpath_free(&path);
    if (h == INVALID_HANDLE_VALUE) {
        return pushed;
    }
    BY_HANDLE_FILE_INFORMATION info;
    FILE_ATTRIBUTE_TAG_INFO tag_info;
    memset(&info, 0, sizeof info);
    memset(&tag_info, 0, sizeof tag_info);
    if (!GetFileInformationByHandle(h, &info) ||
        !GetFileInformationByHandleEx(h, FileAttributeTagInfo, &tag_info, sizeof tag_info)) {
        DWORD error = GetLastError();
        CloseHandle(h);
        return fail_win(L, error, "identify", shown);
    }
    CloseHandle(h);
    DWORD tag = (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? tag_info.ReparseTag : 0;
    lua_createtable(L, 0, 14);
    lua_pushstring(L, kind_of(info.dwFileAttributes, tag));
    lua_setfield(L, -2, "kind");
    lua_pushinteger(L, (lua_Integer)(((unsigned long long)info.nFileSizeHigh << 32) | info.nFileSizeLow));
    lua_setfield(L, -2, "size");
    push_time(L, ((LONGLONG)info.ftLastWriteTime.dwHighDateTime << 32) | info.ftLastWriteTime.dwLowDateTime, "mtime");
    push_time(L, ((LONGLONG)info.ftCreationTime.dwHighDateTime << 32) | info.ftCreationTime.dwLowDateTime, "ctime");
    push_time(L, ((LONGLONG)info.ftLastAccessTime.dwHighDateTime << 32) | info.ftLastAccessTime.dwLowDateTime, "atime");
    lua_pushinteger(L, (lua_Integer)info.dwFileAttributes);
    lua_setfield(L, -2, "attrs");
    lua_pushboolean(L, (info.dwFileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0);
    lua_setfield(L, -2, "hidden");
    lua_pushboolean(L, (info.dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0);
    lua_setfield(L, -2, "readonly");
    lua_pushboolean(L, (info.dwFileAttributes & FILE_ATTRIBUTE_SYSTEM) != 0);
    lua_setfield(L, -2, "system");
    if (tag != 0) {
        char hex[16];
        snprintf(hex, sizeof hex, "0x%08lx", (unsigned long)tag);
        lua_pushstring(L, hex);
        lua_setfield(L, -2, "reparse");
    }
    push_identity(L, &info);
    return 1;
}

/* fs.exists(path) -> kind | false; the name itself, never its target */
static int l_fs_exists(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    HANDLE h = open_meta(path.text, 0);
    ku_wpath_free(&path);
    if (h == INVALID_HANDLE_VALUE) {
        lua_pushboolean(L, 0);
        return 1;
    }
    FILE_ATTRIBUTE_TAG_INFO info;
    memset(&info, 0, sizeof info);
    BOOL ok = GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info);
    CloseHandle(h);
    if (!ok) {
        lua_pushboolean(L, 0);
        return 1;
    }
    DWORD tag = (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? info.ReparseTag : 0;
    lua_pushstring(L, kind_of(info.FileAttributes, tag));
    return 1;
}

/* ---- mkdir / remove / rename / copy ------------------------------------------------- */

static int is_directory_now(const wchar_t *path)
{
    HANDLE h = open_meta(path, 1);
    if (h == INVALID_HANDLE_VALUE) {
        return 0;
    }
    FILE_ATTRIBUTE_TAG_INFO info;
    BOOL ok = GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info);
    CloseHandle(h);
    return ok && (info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY);
}

/* fs.mkdir(path [, { parents = true }]) */
static int l_fs_mkdir(lua_State *L)
{
    static const char *const options[] = {"parents", NULL};
    check_options(L, 2, options);
    int parents = opt_boolean(L, 2, "parents", 1);
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    if (CreateDirectoryW(path.text, NULL)) {
        ku_wpath_free(&path);
        lua_pushboolean(L, 1);
        return 1;
    }
    DWORD error = GetLastError();
    if (error == ERROR_ALREADY_EXISTS) {
        int is_dir = is_directory_now(path.text);
        ku_wpath_free(&path);
        if (is_dir) {
            lua_pushboolean(L, 1);
            return 1;
        }
        return ku_err_fail(L, "FS", "exists", "'%s' exists and is not a directory", shown);
    }
    if (error != ERROR_PATH_NOT_FOUND || !parents) {
        ku_wpath_free(&path);
        return fail_win(L, error, "create directory", shown);
    }
    /* Create the missing ancestors from the top down.  Components start after
     * the prefix and the root (\\?\C:\ or \\?\UNC\server\share\). */
    size_t start = path.unc ? 8 : 4;
    size_t components_seen = 0;
    for (size_t i = start; i <= path.length; i++) {
        if (path.text[i] != L'\\' && path.text[i] != L'\0') {
            continue;
        }
        components_seen++;
        if ((path.unc && components_seen <= 2) || (!path.unc && components_seen <= 1)) {
            continue; /* the share or the drive root */
        }
        wchar_t saved = path.text[i];
        path.text[i] = L'\0';
        if (!CreateDirectoryW(path.text, NULL)) {
            DWORD e = GetLastError();
            if (e != ERROR_ALREADY_EXISTS) {
                path.text[i] = saved;
                ku_wpath_free(&path);
                return fail_win(L, e, "create directory", shown);
            }
        }
        path.text[i] = saved;
    }
    int made = is_directory_now(path.text);
    ku_wpath_free(&path);
    if (!made) {
        return ku_err_fail(L, "FS", "exists", "'%s' exists and is not a directory", shown);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int remove_one(const wchar_t *path, DWORD attributes, DWORD *error)
{
    if (attributes & FILE_ATTRIBUTE_READONLY) {
        SetFileAttributesW(path, attributes & ~(DWORD)FILE_ATTRIBUTE_READONLY);
    }
    BOOL ok = (attributes & FILE_ATTRIBUTE_DIRECTORY) ? RemoveDirectoryW(path) : DeleteFileW(path);
    if (!ok) {
        *error = GetLastError();
        return -1;
    }
    return 0;
}

/* Remove a tree without ever following a reparse point: a junction or
 * symlink directory is removed as a link, its target untouched. */
static int remove_tree(const wchar_t *root, DWORD *error, wchar_t **failed)
{
    typedef struct item {
        wchar_t *path;
        int expanded;
    } item;
    size_t n = 0, capacity = 64;
    item *stack = (item *)malloc(capacity * sizeof *stack);
    if (stack == NULL) {
        *error = ERROR_NOT_ENOUGH_MEMORY;
        return -1;
    }
    stack[0].path = _wcsdup(root);
    stack[0].expanded = 0;
    n = 1;
    int rc = 0;
    while (n > 0 && rc == 0) {
        item it = stack[n - 1];
        if (it.expanded) {
            n--;
            if (!RemoveDirectoryW(it.path)) {
                *error = GetLastError();
                *failed = it.path;
                rc = -1;
                break;
            }
            free(it.path);
            continue;
        }
        stack[n - 1].expanded = 1;
        HANDLE h = ku_fs_open_dir(it.path, 0);
        if (h == INVALID_HANDLE_VALUE) {
            *error = GetLastError();
            *failed = _wcsdup(it.path);
            rc = -1;
            break;
        }
        ku_children kids;
        int got = ku_fs_enumerate(h, &kids);
        CloseHandle(h);
        if (got != 0) {
            *error = kids.error;
            *failed = _wcsdup(it.path);
            rc = -1;
            break;
        }
        if (kids.error != 0 || kids.unrepresentable > 0 || kids.overrun) {
            *error = kids.error != 0 ? kids.error : ERROR_NO_UNICODE_TRANSLATION;
            *failed = _wcsdup(it.path);
            ku_fs_children_free(&kids);
            rc = -1;
            break;
        }
        size_t plen = wcslen(it.path);
        for (size_t i = 0; i < kids.count && rc == 0; i++) {
            ku_child_entry *k = &kids.items[i];
            wchar_t *child = ku_wpath_join(it.path, plen, k->wname, k->wlen);
            if (child == NULL) {
                *error = ERROR_NOT_ENOUGH_MEMORY;
                *failed = _wcsdup(it.path);
                rc = -1;
                break;
            }
            int plain_dir = (k->attributes & FILE_ATTRIBUTE_DIRECTORY) && !(k->attributes & FILE_ATTRIBUTE_REPARSE_POINT);
            if (plain_dir) {
                if (n == capacity) {
                    item *grown = (item *)realloc(stack, capacity * 2 * sizeof *grown);
                    if (grown == NULL) {
                        *error = ERROR_NOT_ENOUGH_MEMORY;
                        *failed = child;
                        rc = -1;
                        break;
                    }
                    stack = grown;
                    capacity *= 2;
                }
                stack[n].path = child;
                stack[n].expanded = 0;
                n++;
            } else {
                if (remove_one(child, k->attributes, error) != 0) {
                    *failed = child;
                    rc = -1;
                    break;
                }
                free(child);
            }
        }
        ku_fs_children_free(&kids);
    }
    for (size_t i = 0; i < n; i++) {
        if (rc != 0 && stack[i].path == *failed) {
            continue;
        }
        free(stack[i].path);
    }
    free(stack);
    return rc;
}

/* fs.remove(path [, { recursive = false }]) */
static int l_fs_remove(lua_State *L)
{
    static const char *const options[] = {"recursive", NULL};
    check_options(L, 2, options);
    int recursive = opt_boolean(L, 2, "recursive", 0);
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    HANDLE h = open_meta(path.text, 0);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "remove", shown);
    }
    FILE_ATTRIBUTE_TAG_INFO info;
    memset(&info, 0, sizeof info);
    BOOL ok = GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info);
    CloseHandle(h);
    if (!ok) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "identify", shown);
    }
    DWORD error = 0;
    int plain_dir = (info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT);
    if (plain_dir && recursive) {
        wchar_t *failed = NULL;
        if (remove_tree(path.text, &error, &failed) != 0) {
            char *where = failed != NULL ? ku_wpath_show(failed, path.unc) : NULL;
            free(failed);
            ku_wpath_free(&path);
            int n = fail_win(L, error, "remove", where != NULL ? where : shown);
            free(where);
            return n;
        }
        ku_wpath_free(&path);
        lua_pushboolean(L, 1);
        return 1;
    }
    if (remove_one(path.text, info.FileAttributes, &error) != 0) {
        ku_wpath_free(&path);
        if (error == ERROR_DIR_NOT_EMPTY) {
            return ku_err_fail(L, "FS", "notempty", "'%s' is not empty; pass { recursive = true }", shown);
        }
        return fail_win(L, error, "remove", shown);
    }
    ku_wpath_free(&path);
    lua_pushboolean(L, 1);
    return 1;
}

/* fs.rename(from, to [, { replace = false }]) */
static int l_fs_rename(lua_State *L)
{
    static const char *const options[] = {"replace", NULL};
    check_options(L, 3, options);
    int replace = opt_boolean(L, 3, "replace", 0);
    ku_wpath from, to;
    path_arg(L, 1, &from);
    path_arg(L, 2, &to);
    const char *shown = lua_tostring(L, 1);
    DWORD flags = MOVEFILE_COPY_ALLOWED | (replace ? MOVEFILE_REPLACE_EXISTING : 0);
    BOOL ok = MoveFileExW(from.text, to.text, flags);
    DWORD error = ok ? 0 : GetLastError();
    ku_wpath_free(&from);
    ku_wpath_free(&to);
    if (!ok) {
        return fail_win(L, error, "rename", shown);
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* fs.copy(from, to [, { replace = false }]) */
static int l_fs_copy(lua_State *L)
{
    static const char *const options[] = {"replace", NULL};
    check_options(L, 3, options);
    int replace = opt_boolean(L, 3, "replace", 0);
    ku_wpath from, to;
    path_arg(L, 1, &from);
    path_arg(L, 2, &to);
    const char *shown = lua_tostring(L, 1);
    BOOL ok = CopyFileExW(from.text, to.text, NULL, NULL, NULL, replace ? 0 : COPY_FILE_FAIL_IF_EXISTS);
    DWORD error = ok ? 0 : GetLastError();
    ku_wpath_free(&from);
    ku_wpath_free(&to);
    if (!ok) {
        return fail_win(L, error, "copy", shown);
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* ---- list ----------------------------------------------------------------------------- */

/* fs.list(dir) -> { entries = { {name, kind, size, mtime, attrs, reparse?}... }, errors = {...} } */
static int l_fs_list(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    int pushed = 0;
    HANDLE probe = open_or_fail(L, &path, shown, 1, &pushed);
    if (probe == INVALID_HANDLE_VALUE) {
        ku_wpath_free(&path);
        return pushed;
    }
    CloseHandle(probe);
    HANDLE h = ku_fs_open_dir(path.text, 1);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "list", shown);
    }
    ku_children kids;
    int got = ku_fs_enumerate(h, &kids);
    CloseHandle(h);
    ku_wpath_free(&path);
    if (got != 0) {
        DWORD error = kids.error;
        if (error == ERROR_INVALID_PARAMETER) {
            return ku_err_fail(L, "FS", "badvalue", "'%s' is not a directory", shown);
        }
        return fail_win(L, error, "list", shown);
    }
    lua_createtable(L, 0, 2);
    lua_createtable(L, (int)kids.count, 0);
    for (size_t i = 0; i < kids.count; i++) {
        ku_child_entry *k = &kids.items[i];
        lua_createtable(L, 0, 6);
        lua_pushstring(L, k->name);
        lua_setfield(L, -2, "name");
        lua_pushstring(L, kind_of(k->attributes, k->tag));
        lua_setfield(L, -2, "kind");
        lua_pushinteger(L, (lua_Integer)k->size);
        lua_setfield(L, -2, "size");
        push_time(L, k->mtime, "mtime");
        lua_pushinteger(L, (lua_Integer)k->attributes);
        lua_setfield(L, -2, "attrs");
        if (k->attributes & FILE_ATTRIBUTE_REPARSE_POINT) {
            char hex[16];
            snprintf(hex, sizeof hex, "0x%08lx", (unsigned long)k->tag);
            lua_pushstring(L, hex);
            lua_setfield(L, -2, "reparse");
        }
        lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    lua_setfield(L, -2, "entries");
    lua_newtable(L);
    lua_Integer errors = 0;
    for (size_t i = 0; i < kids.unrepresentable; i++) {
        lua_pushliteral(L, "a name is not representable as UTF-8");
        lua_rawseti(L, -2, ++errors);
    }
    for (size_t i = 0; i < kids.lost; i++) {
        lua_pushliteral(L, "an entry was lost for lack of memory");
        lua_rawseti(L, -2, ++errors);
    }
    if (kids.overrun) {
        lua_pushliteral(L, "the directory listing was malformed");
        lua_rawseti(L, -2, ++errors);
    }
    if (kids.error != 0) {
        char *text = ku_win_error_message(kids.error);
        lua_pushfstring(L, "the listing stopped early: %s", text != NULL ? text : "");
        free(text);
        lua_rawseti(L, -2, ++errors);
    }
    lua_setfield(L, -2, "errors");
    ku_fs_children_free(&kids);
    return 1;
}

/* ---- canon / same / link ---------------------------------------------------------------- */

static int push_canon(lua_State *L, const ku_wpath *path, const char *shown)
{
    int pushed = 0;
    HANDLE h = open_or_fail(L, path, shown, 1, &pushed);
    if (h == INVALID_HANDLE_VALUE) {
        return pushed;
    }
    BY_HANDLE_FILE_INFORMATION info;
    memset(&info, 0, sizeof info);
    if (!GetFileInformationByHandle(h, &info)) {
        DWORD error = GetLastError();
        CloseHandle(h);
        return fail_win(L, error, "identify", shown);
    }
    DWORD need = GetFinalPathNameByHandleW(h, NULL, 0, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (need == 0) {
        DWORD error = GetLastError();
        CloseHandle(h);
        return fail_win(L, error, "resolve", shown);
    }
    wchar_t *final = (wchar_t *)malloc(((size_t)need + 1) * sizeof(wchar_t));
    if (final == NULL) {
        CloseHandle(h);
        return ku_err_raise(L, "FS", "oserror", "out of memory");
    }
    DWORD wrote = GetFinalPathNameByHandleW(h, final, need, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    CloseHandle(h);
    if (wrote == 0 || wrote >= need + 1) {
        free(final);
        return ku_err_fail(L, "FS", "oserror", "cannot resolve '%s'", shown);
    }
    final[wrote] = L'\0';
    char *resolved = ku_wpath_show(final, 0);
    free(final);
    if (resolved == NULL) {
        return ku_err_fail(L, "FS", "encoding", "the resolved path of '%s' is not representable", shown);
    }
    lua_createtable(L, 0, 5);
    lua_pushstring(L, resolved);
    lua_setfield(L, -2, "path");
    free(resolved);
    lua_pushstring(L, (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? "directory" : "file");
    lua_setfield(L, -2, "kind");
    push_identity(L, &info);
    return 1;
}

/* fs.canon(path) -> { path, volume, file, kind, links } | nil, err */
static int l_fs_canon(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    int n = push_canon(L, &path, lua_tostring(L, 1));
    ku_wpath_free(&path);
    return n;
}

/* fs.same(a, b) -> boolean | nil, err */
static int l_fs_same(lua_State *L)
{
    ku_wpath a, b;
    path_arg(L, 1, &a);
    path_arg(L, 2, &b);
    int n = push_canon(L, &a, lua_tostring(L, 1));
    ku_wpath_free(&a);
    if (n == 2) {
        ku_wpath_free(&b);
        return 2;
    }
    n = push_canon(L, &b, lua_tostring(L, 2));
    ku_wpath_free(&b);
    if (n == 2) {
        return 2;
    }
    lua_getfield(L, -2, "volume");
    lua_getfield(L, -2, "volume");
    int same = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    lua_getfield(L, -2, "file");
    lua_getfield(L, -2, "file");
    same = same && lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    lua_pushboolean(L, same);
    return 1;
}

/* fs.link(path) -> false | { type, target, tag } | nil, err */
static int l_fs_link(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    HANDLE h = open_meta(path.text, 0);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "open", shown);
    }
    FILE_ATTRIBUTE_TAG_INFO info;
    memset(&info, 0, sizeof info);
    BOOL ok = GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info);
    CloseHandle(h);
    if (!ok) {
        DWORD error = GetLastError();
        ku_wpath_free(&path);
        return fail_win(L, error, "identify", shown);
    }
    if (!(info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) || !ku_tag_is_name(info.ReparseTag)) {
        ku_wpath_free(&path);
        lua_pushboolean(L, 0);
        return 1;
    }
    int is_dir = (info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const char *type = ku_fs_link_type(info.ReparseTag, is_dir);
    char *target = ku_fs_link_target(path.text, is_dir);
    ku_wpath_free(&path);
    lua_createtable(L, 0, 3);
    lua_pushstring(L, type != NULL ? type : "unknown");
    lua_setfield(L, -2, "type");
    if (target != NULL) {
        lua_pushstring(L, target);
        lua_setfield(L, -2, "target");
    }
    free(target);
    char hex[16];
    snprintf(hex, sizeof hex, "0x%08lx", (unsigned long)info.ReparseTag);
    lua_pushstring(L, hex);
    lua_setfield(L, -2, "tag");
    return 1;
}

/* ---- cwd / temp / absolute ---------------------------------------------------------------- */

static int push_shown_directory(lua_State *L, DWORD (*getter)(DWORD, LPWSTR), const char *what)
{
    DWORD n = getter(0, NULL);
    if (n == 0) {
        return ku_err_raise(L, "FS", "oserror", "cannot read the %s", what);
    }
    wchar_t *buffer = (wchar_t *)malloc(((size_t)n + 1) * sizeof(wchar_t));
    if (buffer == NULL) {
        return ku_err_raise(L, "FS", "oserror", "out of memory");
    }
    DWORD got = getter(n + 1, buffer);
    if (got == 0 || got > n + 1) {
        free(buffer);
        return ku_err_raise(L, "FS", "oserror", "cannot read the %s", what);
    }
    while (got > 3 && buffer[got - 1] == L'\\') {
        buffer[--got] = L'\0';
    }
    char *utf8 = ku_wpath_show(buffer, 0);
    free(buffer);
    if (utf8 == NULL) {
        return ku_err_raise(L, "FS", "encoding", "the %s is not representable", what);
    }
    lua_pushstring(L, utf8);
    free(utf8);
    return 1;
}

static int l_fs_cwd(lua_State *L)
{
    return push_shown_directory(L, GetCurrentDirectoryW, "current directory");
}

/* ---- temporary names, free space --------------------------------------------------------- */

static int random_hex(wchar_t *out, size_t bytes_wanted)
{
    unsigned char bytes[16];
    if (bytes_wanted > sizeof bytes ||
        BCryptGenRandom(NULL, bytes, (ULONG)bytes_wanted, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
        return -1;
    }
    static const wchar_t digits[] = L"0123456789abcdef";
    for (size_t i = 0; i < bytes_wanted; i++) {
        out[i * 2] = digits[bytes[i] >> 4];
        out[i * 2 + 1] = digits[bytes[i] & 15];
    }
    out[bytes_wanted * 2] = L'\0';
    return 0;
}

static int plain_name_part(const char *s)
{
    for (; *s != '\0'; s++) {
        if (*s == '/' || *s == '\\' || *s == ':' || (unsigned char)*s < 0x20) {
            return 0;
        }
    }
    return 1;
}

/* fs.tempfile { dir, prefix, suffix } and fs.tempdir { dir, prefix }: a new,
 * uniquely named file or directory, created exclusively so two callers never
 * get the same name; the path comes back absolute. */
static int temp_make(lua_State *L, int directory)
{
    static const char *const file_options[] = {"dir", "prefix", "suffix", NULL};
    static const char *const dir_options[] = {"dir", "prefix", NULL};
    check_options(L, 1, directory ? dir_options : file_options);
    const char *prefix = "kuu-", *suffix = "";
    int has_dir = 0;
    if (lua_istable(L, 1)) {
        lua_getfield(L, 1, "prefix");
        if (!lua_isnil(L, -1)) {
            prefix = luaL_checkstring(L, -1);
        }
        lua_getfield(L, 1, "suffix");
        if (!lua_isnil(L, -1)) {
            suffix = luaL_checkstring(L, -1);
        }
        lua_getfield(L, 1, "dir");
        has_dir = !lua_isnil(L, -1);
        if (!has_dir) {
            lua_pop(L, 1);
        }
    }
    if (!plain_name_part(prefix) || !plain_name_part(suffix)) {
        return ku_err_raise(L, "FS", "badvalue", "prefix and suffix must be plain name parts");
    }
    if (!has_dir) {
        push_shown_directory(L, GetTempPathW, "temporary directory");
    }
    const char *shown_dir = luaL_checkstring(L, -1);
    ku_wpath dir;
    path_arg(L, lua_gettop(L), &dir);
    wchar_t *wprefix = ku_utf8_to_wide(prefix);
    wchar_t *wsuffix = ku_utf8_to_wide(suffix);
    if (wprefix == NULL || wsuffix == NULL) {
        free(wprefix);
        free(wsuffix);
        ku_wpath_free(&dir);
        return ku_err_raise(L, "FS", "encoding", "prefix and suffix must be valid UTF-8");
    }
    size_t plen = wcslen(wprefix), slen = wcslen(wsuffix);
    for (int attempt = 0; attempt < 32; attempt++) {
        wchar_t random[17];
        if (random_hex(random, 8) != 0) {
            break;
        }
        size_t nlen = plen + 16 + slen;
        wchar_t *name = (wchar_t *)malloc((nlen + 1) * sizeof(wchar_t));
        if (name == NULL) {
            break;
        }
        wcscpy(name, wprefix);
        wcscat(name, random);
        wcscat(name, wsuffix);
        wchar_t *candidate = ku_wpath_join(dir.text, dir.length, name, nlen);
        free(name);
        if (candidate == NULL) {
            break;
        }
        BOOL ok;
        DWORD error = 0;
        if (directory) {
            ok = CreateDirectoryW(candidate, NULL);
        } else {
            HANDLE h = CreateFileW(candidate, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
            ok = h != INVALID_HANDLE_VALUE;
            if (ok) {
                CloseHandle(h);
            }
        }
        if (!ok) {
            error = GetLastError();
        }
        if (ok) {
            char *shown = ku_wpath_show(candidate, dir.unc);
            free(candidate);
            free(wprefix);
            free(wsuffix);
            ku_wpath_free(&dir);
            if (shown == NULL) {
                return ku_err_raise(L, "FS", "encoding", "the temporary path is not representable");
            }
            lua_pushstring(L, shown);
            free(shown);
            return 1;
        }
        free(candidate);
        if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS) {
            free(wprefix);
            free(wsuffix);
            ku_wpath_free(&dir);
            return fail_win(L, error, directory ? "create a temporary directory in" : "create a temporary file in",
                            shown_dir);
        }
    }
    free(wprefix);
    free(wsuffix);
    ku_wpath_free(&dir);
    return ku_err_raise(L, "FS", "oserror", "cannot find a free temporary name in '%s'", shown_dir);
}

static int l_fs_tempfile(lua_State *L)
{
    return temp_make(L, 0);
}

static int l_fs_tempdir(lua_State *L)
{
    return temp_make(L, 1);
}

/* fs.space(dir) -> { total, free, available }: bytes on the volume holding
 * `dir`; `available` is what this user may still use, under any quota. */
static int l_fs_space(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    ULARGE_INTEGER available, total, free_bytes;
    BOOL ok = GetDiskFreeSpaceExW(path.text, &available, &total, &free_bytes);
    DWORD error = ok ? 0 : GetLastError();
    ku_wpath_free(&path);
    if (!ok) {
        return fail_win(L, error, "measure the space at", shown);
    }
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, (lua_Integer)total.QuadPart);
    lua_setfield(L, -2, "total");
    lua_pushinteger(L, (lua_Integer)free_bytes.QuadPart);
    lua_setfield(L, -2, "free");
    lua_pushinteger(L, (lua_Integer)available.QuadPart);
    lua_setfield(L, -2, "available");
    return 1;
}

/* fs.chdir(path) -> true | nil, err.  Process-wide: every task and every
 * child started afterwards sees it. */
static int l_fs_chdir(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    const char *shown = lua_tostring(L, 1);
    /* SetCurrentDirectoryW wants an ordinary path, not a \\?\ one. */
    const wchar_t *plain = path.text + (path.unc ? 8 : 4);
    wchar_t *target = path.unc ? (wchar_t *)malloc((wcslen(plain) + 3) * sizeof(wchar_t)) : NULL;
    if (path.unc) {
        if (target == NULL) {
            ku_wpath_free(&path);
            return ku_err_raise(L, "FS", "oserror", "out of memory");
        }
        wcscpy(target, L"\\\\");
        wcscat(target, plain);
    }
    BOOL ok = SetCurrentDirectoryW(path.unc ? target : plain);
    DWORD error = ok ? 0 : GetLastError();
    free(target);
    ku_wpath_free(&path);
    if (!ok) {
        return fail_win(L, error, "change directory to", shown);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_fs_temp(lua_State *L)
{
    return push_shown_directory(L, GetTempPathW, "temporary directory");
}

/* fs.absolute(path) -> the normalised absolute spelling, forward slashes */
static int l_fs_absolute(lua_State *L)
{
    ku_wpath path;
    path_arg(L, 1, &path);
    char *shown = ku_wpath_show(path.text, path.unc);
    ku_wpath_free(&path);
    if (shown == NULL) {
        return ku_err_raise(L, "FS", "encoding", "the path is not representable");
    }
    lua_pushstring(L, shown);
    free(shown);
    return 1;
}

int ku_open_fs(lua_State *L)
{
    ku_fs_watch_meta(L);
    static const luaL_Reg functions[] = {
        {"read", l_fs_read},
        {"write", l_fs_write},
        {"stat", l_fs_stat},
        {"exists", l_fs_exists},
        {"mkdir", l_fs_mkdir},
        {"remove", l_fs_remove},
        {"rename", l_fs_rename},
        {"copy", l_fs_copy},
        {"list", l_fs_list},
        {"dirs", ku_fs_dirs},
        {"canon", l_fs_canon},
        {"same", l_fs_same},
        {"link", l_fs_link},
        {"watch", ku_fs_watch},
        {"cwd", l_fs_cwd},
        {"chdir", l_fs_chdir},
        {"temp", l_fs_temp},
        {"tempfile", l_fs_tempfile},
        {"tempdir", l_fs_tempdir},
        {"space", l_fs_space},
        {"absolute", l_fs_absolute},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
