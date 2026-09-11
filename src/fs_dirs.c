/*
 * fs_dirs.c -- directory enumeration and the `fs.dirs` walk.
 *
 * The walk never presents a silent partial result: every omitted branch is
 * accounted for by `errors`, `pruned`, `depthlimited`, or a `links` row.
 * Name-surrogate reparse points (junctions, symlinks, mount points, DFS) are
 * reported and not entered; other reparse tags, such as cloud placeholders,
 * remain ordinary content.  Classification is rechecked on a handle right
 * before descent, so replacing a scanned directory with a junction cannot
 * escape the requested tree.  This is machteld's dirs.c, whose every rule was
 * measured, carried into Lua.
 */
#include "err.h"
#include "fs_internal.h"
#include "wintext.h"

#include "lauxlib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* 64 KB is a throughput choice: a component is at most 255 UTF-16 units, so
 * the largest FILE_ID_BOTH_DIR_INFO entry is about 622 bytes.  The buffer
 * still grows, on BOTH failure codes: measured, a too-small buffer returns
 * ERROR_NOT_ENOUGH_MEMORY, never the ERROR_MORE_DATA the documentation
 * suggests. */
#define KU_ENUM_BUFFER 65536

HANDLE ku_fs_open_dir(const wchar_t *path, int follow)
{
    DWORD flags = FILE_FLAG_BACKUP_SEMANTICS;
    if (!follow) {
        flags |= FILE_FLAG_OPEN_REPARSE_POINT;
    }
    return CreateFileW(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                       OPEN_EXISTING, flags, NULL);
}

/* Sibling order is part of the contract: NTFS hands entries back in its
 * index order, a case-insensitive collation disjoint from byte order.  UTF-8
 * unsigned byte order is code-point order; a signed compare would put every
 * non-ASCII name before 'a', and UTF-16 order misplaces supplementary planes. */
static int compare_children(const void *a, const void *b)
{
    const ku_child_entry *x = (const ku_child_entry *)a;
    const ku_child_entry *y = (const ku_child_entry *)b;
    const char *xn = x->name != NULL ? x->name : "";
    const char *yn = y->name != NULL ? y->name : "";
    size_t xl = strlen(xn), yl = strlen(yn);
    size_t m = xl < yl ? xl : yl;
    int c = memcmp(xn, yn, m);
    if (c != 0) {
        return c;
    }
    return xl < yl ? -1 : (xl > yl ? 1 : 0);
}

void ku_fs_children_free(ku_children *children)
{
    for (size_t i = 0; i < children->count; i++) {
        free(children->items[i].wname);
        free(children->items[i].name);
    }
    free(children->items);
    memset(children, 0, sizeof *children);
}

int ku_fs_enumerate(HANDLE dir, ku_children *children)
{
    memset(children, 0, sizeof *children);
    size_t buffer_size = KU_ENUM_BUFFER;
    /* malloc, not a stack array: the info class needs 8-byte alignment. */
    char *buffer = (char *)malloc(buffer_size);
    if (buffer == NULL) {
        children->error = ERROR_NOT_ENOUGH_MEMORY;
        return -1;
    }
    BOOL ok = GetFileInformationByHandleEx(dir, FileIdBothDirectoryRestartInfo, buffer, (DWORD)buffer_size);
    while (!ok && (GetLastError() == ERROR_MORE_DATA || GetLastError() == ERROR_NOT_ENOUGH_MEMORY) &&
           buffer_size < (size_t)16 * 1024 * 1024) {
        char *bigger = (char *)realloc(buffer, buffer_size * 2);
        if (bigger == NULL) {
            break;
        }
        buffer = bigger;
        buffer_size *= 2;
        ok = GetFileInformationByHandleEx(dir, FileIdBothDirectoryRestartInfo, buffer, (DWORD)buffer_size);
    }
    if (!ok) {
        DWORD error = GetLastError();
        free(buffer);
        if (error == ERROR_NO_MORE_FILES) {
            return 0; /* an empty directory */
        }
        children->error = error;
        return -1;
    }
    size_t capacity = 0;
    /* The restart call returns the FIRST batch; it is not a seek.  Process
     * what was returned, then ask for more: do-while, never while. */
    do {
        size_t offset = 0;
        for (;;) {
            if (offset + offsetof(FILE_ID_BOTH_DIR_INFO, FileName) > buffer_size) {
                children->overrun = 1;
                break;
            }
            FILE_ID_BOTH_DIR_INFO *e = (FILE_ID_BOTH_DIR_INFO *)(buffer + offset);
            if (e->FileNameLength % sizeof(wchar_t) != 0 ||
                offset + offsetof(FILE_ID_BOTH_DIR_INFO, FileName) + e->FileNameLength > buffer_size) {
                children->overrun = 1;
                break;
            }
            size_t nlen = e->FileNameLength / sizeof(wchar_t);
            int skip = (nlen == 1 && e->FileName[0] == L'.') ||
                       (nlen == 2 && e->FileName[0] == L'.' && e->FileName[1] == L'.');
            if (!skip) {
                if (children->count == capacity) {
                    size_t next = capacity ? capacity * 2 : 32;
                    ku_child_entry *grown = (ku_child_entry *)realloc(children->items, next * sizeof *grown);
                    if (grown == NULL) {
                        children->lost++;
                        skip = 1;
                    } else {
                        children->items = grown;
                        capacity = next;
                    }
                }
            }
            if (!skip) {
                ku_child_entry *k = &children->items[children->count];
                memset(k, 0, sizeof *k);
                k->name = ku_wide_to_utf8(e->FileName, (int)nlen);
                if (k->name == NULL) {
                    children->unrepresentable++; /* see wintext.h: refused, not renamed */
                } else {
                    k->wname = (wchar_t *)malloc((nlen + 1) * sizeof(wchar_t));
                    if (k->wname == NULL) {
                        free(k->name);
                        k->name = NULL;
                        children->lost++;
                    } else {
                        memcpy(k->wname, e->FileName, nlen * sizeof(wchar_t));
                        k->wname[nlen] = L'\0';
                        k->wlen = nlen;
                        k->attributes = e->FileAttributes;
                        /* EaSize is the reparse tag only when the reparse bit is
                         * set; otherwise it is a real EA size, or stale. */
                        k->tag = (e->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? e->EaSize : 0;
                        k->size = e->EndOfFile.QuadPart;
                        k->mtime = e->LastWriteTime.QuadPart;
                        k->ctime = e->CreationTime.QuadPart;
                        k->atime = e->LastAccessTime.QuadPart;
                        children->count++;
                    }
                }
            }
            if (e->NextEntryOffset == 0) {
                break;
            }
            size_t used = offsetof(FILE_ID_BOTH_DIR_INFO, FileName) + e->FileNameLength;
            if (e->NextEntryOffset % sizeof(LONGLONG) != 0 || e->NextEntryOffset < used ||
                e->NextEntryOffset > buffer_size - offset) {
                children->overrun = 1;
                break;
            }
            offset += e->NextEntryOffset;
        }
        if (children->overrun) {
            break;
        }
        ok = GetFileInformationByHandleEx(dir, FileIdBothDirectoryInfo, buffer, (DWORD)buffer_size);
    } while (ok);
    DWORD last = GetLastError();
    free(buffer);
    if (!children->overrun && !ok && last != ERROR_NO_MORE_FILES) {
        children->error = last; /* a partial list, kept AND reported */
    }
    if (children->count > 1) {
        qsort(children->items, children->count, sizeof *children->items, compare_children);
    }
    return 0;
}

/* ---- links ---------------------------------------------------------------------- */

const char *ku_fs_link_type(DWORD tag, int is_directory)
{
    if (tag == IO_REPARSE_TAG_SYMLINK) {
        return is_directory ? "directory symlink" : "file symlink";
    }
    if (tag == KU_TAG_MOUNT_POINT) {
        return "junction";
    }
    return NULL;
}

/* mingw's headers do not declare the reparse payload; both link shapes put
 * the same four offsets first and only the symlink adds Flags, so the arms
 * cannot share one struct. */
typedef struct reparse_data {
    DWORD ReparseTag;
    WORD ReparseDataLength;
    WORD Reserved;
    union {
        struct {
            WORD SubstituteNameOffset;
            WORD SubstituteNameLength;
            WORD PrintNameOffset;
            WORD PrintNameLength;
            ULONG Flags;
            WCHAR PathBuffer[1];
        } Symlink;
        struct {
            WORD SubstituteNameOffset;
            WORD SubstituteNameLength;
            WORD PrintNameOffset;
            WORD PrintNameLength;
            WCHAR PathBuffer[1];
        } Mount;
    } u;
} reparse_data;

#define KU_SYMLINK_RELATIVE 0x00000001u

char *ku_fs_link_target(const wchar_t *path, int is_directory)
{
    DWORD flags = FILE_FLAG_OPEN_REPARSE_POINT;
    if (is_directory) {
        flags |= FILE_FLAG_BACKUP_SEMANTICS;
    }
    HANDLE h = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                           flags, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        return NULL;
    }
    char *raw = (char *)malloc(MAXIMUM_REPARSE_DATA_BUFFER_SIZE);
    if (raw == NULL) {
        CloseHandle(h);
        return NULL;
    }
    DWORD got = 0;
    BOOL ok = DeviceIoControl(h, FSCTL_GET_REPARSE_POINT, NULL, 0, raw, MAXIMUM_REPARSE_DATA_BUFFER_SIZE, &got, NULL);
    CloseHandle(h);
    if (!ok || got < sizeof(DWORD)) {
        free(raw);
        return NULL;
    }
    reparse_data *r = (reparse_data *)raw;
    const WCHAR *base;
    WORD off, len;
    size_t header;
    int relative = 0;
    /* The fixed part must be present before its fields are read, per arm:
     * the symlink arm reads twenty bytes in. */
    if (r->ReparseTag == IO_REPARSE_TAG_SYMLINK) {
        header = offsetof(reparse_data, u.Symlink.PathBuffer);
        if ((size_t)got < header) {
            free(raw);
            return NULL;
        }
        base = r->u.Symlink.PathBuffer;
        off = r->u.Symlink.SubstituteNameOffset;
        len = r->u.Symlink.SubstituteNameLength;
        relative = (r->u.Symlink.Flags & KU_SYMLINK_RELATIVE) != 0;
    } else if (r->ReparseTag == KU_TAG_MOUNT_POINT) {
        header = offsetof(reparse_data, u.Mount.PathBuffer);
        if ((size_t)got < header) {
            free(raw);
            return NULL;
        }
        base = r->u.Mount.PathBuffer;
        off = r->u.Mount.SubstituteNameOffset;
        len = r->u.Mount.SubstituteNameLength;
    } else {
        free(raw);
        return NULL;
    }
    /* `off` is relative to PathBuffer, not to the struct: the check that
     * added the union's offset was 12 and 8 bytes short and read past the
     * buffer.  Network and user-space file systems can return malformed
     * payloads, so the check is mandatory. */
    if (header + (size_t)off + (size_t)len > (size_t)got) {
        free(raw);
        return NULL;
    }
    const WCHAR *name = (const WCHAR *)((const char *)base + off);
    size_t n = len / sizeof(WCHAR);
    char *out = NULL;
    if (!relative && n >= 4 && name[0] == L'\\' && name[1] == L'?' && name[2] == L'?' && name[3] == L'\\') {
        name += 4;
        n -= 4;
        if (n >= 4 && (name[0] == L'U' || name[0] == L'u') && (name[1] == L'N' || name[1] == L'n') &&
            (name[2] == L'C' || name[2] == L'c') && name[3] == L'\\') {
            char *tail = ku_wide_to_utf8(name + 3, (int)(n - 3)); /* \\server\share */
            if (tail != NULL) {
                size_t tl = strlen(tail);
                out = (char *)malloc(tl + 2);
                if (out != NULL) {
                    out[0] = '\\';
                    memcpy(out + 1, tail, tl + 1);
                }
                free(tail);
            }
            free(raw);
            return out;
        }
    }
    out = ku_wide_to_utf8(name, (int)n);
    free(raw);
    return out;
}

/* ---- wildcard --------------------------------------------------------------------- */

static unsigned char fold(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') ? (unsigned char)(c + 32) : c;
}

int ku_fs_wildcard(const char *p, const char *s)
{
    const char *star = NULL, *mark = NULL;
    while (*s) {
        if (*p == '*') {
            star = p++;
            mark = s;
        } else if (*p == '?' || fold((unsigned char)*p) == fold((unsigned char)*s)) {
            p++;
            s++;
        } else if (star != NULL) {
            p = star + 1;
            s = ++mark;
        } else {
            return 0;
        }
    }
    while (*p == '*') {
        p++;
    }
    return *p == '\0';
}

double ku_fs_time_seconds(LONGLONG filetime)
{
    /* FILETIME counts 100 ns from 1601-01-01; the Unix epoch is 11644473600 s later. */
    return (double)(filetime - 116444736000000000LL) / 10000000.0;
}

/* ---- the walk --------------------------------------------------------------------- */

typedef struct walk_item {
    wchar_t *path;
    int depth;
    int reparse;
    DWORD tag;
    int surrogate;
    int noenter;
    int pruned;
} walk_item;

typedef struct walk {
    lua_State *L;
    int paths;   /* stack index of the paths array */
    int skipped; /* stack index of the skipped (pruned) array */
    int links;   /* stack index of the links array */
    int errors;  /* stack index of the errors array */
    lua_Integer path_count, skipped_count, link_count, error_count;
    lua_Integer count, pruned, depthlimited, maxdepth;
    int depthcap;
    int unc;
    const char **prune;
    int prune_count;
} walk;

static void walk_error(walk *w, const wchar_t *path, DWORD error)
{
    lua_State *L = w->L;
    char *shown = ku_wpath_show(path, w->unc);
    char *reason = ku_win_error_message(error);
    lua_createtable(L, 0, 3);
    lua_pushstring(L, shown != NULL ? shown : "");
    lua_setfield(L, -2, "path");
    lua_pushinteger(L, (lua_Integer)error);
    lua_setfield(L, -2, "win32");
    lua_pushstring(L, reason != NULL ? reason : "");
    lua_setfield(L, -2, "reason");
    lua_rawseti(L, w->errors, ++w->error_count);
    free(shown);
    free(reason);
}

static void walk_link_row(walk *w, const char *shown, DWORD tag, int surrogate, const char *action,
                          const wchar_t *full)
{
    lua_State *L = w->L;
    lua_createtable(L, 0, 6);
    lua_pushstring(L, shown != NULL ? shown : "");
    lua_setfield(L, -2, "path");
    char hex[16];
    snprintf(hex, sizeof hex, "0x%08lx", (unsigned long)tag);
    lua_pushstring(L, hex);
    lua_setfield(L, -2, "tag");
    lua_pushboolean(L, surrogate);
    lua_setfield(L, -2, "surrogate");
    lua_pushstring(L, action);
    lua_setfield(L, -2, "action");
    if (ku_tag_is_name(tag)) {
        const char *type = ku_fs_link_type(tag, 1);
        char *target = ku_fs_link_target(full, 1);
        lua_pushstring(L, type != NULL ? type : "unknown");
        lua_setfield(L, -2, "type");
        if (target != NULL) {
            lua_pushstring(L, target);
            lua_setfield(L, -2, "target");
        }
        free(target);
    }
    lua_rawseti(L, w->links, ++w->link_count);
}

static int walk_run(walk *w, const wchar_t *root, int root_reparse, DWORD root_tag)
{
    lua_State *L = w->L;
    size_t n = 0, capacity = 64;
    walk_item *stack = (walk_item *)malloc(capacity * sizeof *stack);
    if (stack == NULL) {
        return -1;
    }
    stack[0].path = _wcsdup(root);
    if (stack[0].path == NULL) {
        free(stack);
        return -1;
    }
    stack[0].depth = 0;
    stack[0].reparse = root_reparse;
    stack[0].tag = root_reparse ? root_tag : 0;
    stack[0].surrogate = root_reparse && (root_tag & KU_TAG_SURROGATE) != 0;
    stack[0].noenter = root_reparse && ku_tag_is_name(root_tag);
    stack[0].pruned = 0;
    n = 1;

    while (n > 0) {
        walk_item it = stack[--n];
        luaL_checkstack(L, 8, "fs.dirs");
        /* Emission precedes every policy decision: pop, list, count, then
         * decide about descending.  Every skip is a descent skip. */
        /* Decide before emitting.  A pruned directory was excluded by name, so
         * it belongs in `skipped`, never in `paths`: listing it there made the
         * obvious walk -- list the files of every path -- read exactly the
         * content the prune was asked to exclude.  The depth cap and a name
         * surrogate still emit into `paths`, because those directories are the
         * frontier the caller asked to stop at rather than names it excluded. */
        int depth_stop = (w->depthcap >= 0 && it.depth >= w->depthcap);
        int prune_stop = (!depth_stop && it.pruned);

        char *shown = ku_wpath_show(it.path, w->unc);
        if (shown != NULL) {
            lua_pushstring(L, shown);
            if (prune_stop) {
                lua_rawseti(L, w->skipped, ++w->skipped_count);
            } else {
                lua_rawseti(L, w->paths, ++w->path_count);
                w->count++;
            }
        } else {
            walk_error(w, it.path, ERROR_NOT_ENOUGH_MEMORY);
        }
        if (it.depth > w->maxdepth) {
            w->maxdepth = it.depth;
        }
        const char *action = "descended";
        int stop = 0;
        HANDLE h = INVALID_HANDLE_VALUE;
        if (depth_stop) {
            w->depthlimited++;
            action = "depthlimited";
            stop = 1;
        }
        if (prune_stop) {
            w->pruned++;
            action = "pruned";
            stop = 1;
        }
        /* The parent's scan said surrogate: believe it (it can only refuse a
         * descent).  The root is exempt: you named it, you get it. */
        if (!stop && it.noenter && it.depth > 0) {
            action = "nofollow";
            stop = 1;
        }
        if (!stop) {
            h = ku_fs_open_dir(it.path, it.depth == 0);
            if (h == INVALID_HANDLE_VALUE) {
                walk_error(w, it.path, GetLastError());
                action = "failed";
                stop = 1;
            }
        }
        if (!stop && it.depth > 0) {
            /* Reclassify on the handle: a directory replaced by a junction
             * since the scan must not be entered. */
            FILE_ATTRIBUTE_TAG_INFO info;
            memset(&info, 0, sizeof info);
            if (GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info) &&
                (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
                it.reparse = 1;
                it.tag = info.ReparseTag;
                it.surrogate = (it.tag & KU_TAG_SURROGATE) != 0;
                it.noenter = ku_tag_is_name(it.tag);
                CloseHandle(h);
                h = INVALID_HANDLE_VALUE;
                if (it.noenter) {
                    action = "nofollow";
                    stop = 1;
                } else {
                    h = ku_fs_open_dir(it.path, 1); /* content behind a filter: follow */
                    if (h == INVALID_HANDLE_VALUE) {
                        walk_error(w, it.path, GetLastError());
                        action = "failed";
                        stop = 1;
                    }
                }
            }
        }
        if (!stop) {
            ku_children kids;
            int got = ku_fs_enumerate(h, &kids);
            CloseHandle(h);
            h = INVALID_HANDLE_VALUE;
            if (got != 0) {
                walk_error(w, it.path, kids.error);
                action = "failed";
            } else {
                if (kids.error != 0) {
                    walk_error(w, it.path, kids.error);
                }
                if (kids.overrun) {
                    walk_error(w, it.path, ERROR_INVALID_DATA);
                }
                for (size_t i = 0; i < kids.unrepresentable; i++) {
                    walk_error(w, it.path, ERROR_NO_UNICODE_TRANSLATION);
                }
                for (size_t i = 0; i < kids.lost; i++) {
                    walk_error(w, it.path, ERROR_NOT_ENOUGH_MEMORY);
                }
                /* Directories only, pushed in reverse so they pop ascending:
                 * depth-first pre-order in sibling order. */
                size_t plen = wcslen(it.path);
                size_t dropped = 0;
                for (size_t i = kids.count; i-- > 0;) {
                    ku_child_entry *k = &kids.items[i];
                    if (!(k->attributes & FILE_ATTRIBUTE_DIRECTORY)) {
                        continue;
                    }
                    if (n == capacity) {
                        size_t next = capacity * 2;
                        walk_item *grown = (walk_item *)realloc(stack, next * sizeof *grown);
                        if (grown == NULL) {
                            dropped++;
                            continue;
                        }
                        stack = grown;
                        capacity = next;
                    }
                    wchar_t *child = ku_wpath_join(it.path, plen, k->wname, k->wlen);
                    if (child == NULL) {
                        dropped++;
                        continue;
                    }
                    int pruned = 0;
                    for (int p = 0; p < w->prune_count; p++) {
                        if (ku_fs_wildcard(w->prune[p], k->name)) {
                            pruned = 1;
                            break;
                        }
                    }
                    int reparse = (k->attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
                    stack[n].path = child;
                    stack[n].depth = it.depth + 1;
                    stack[n].reparse = reparse;
                    stack[n].tag = reparse ? k->tag : 0;
                    stack[n].surrogate = reparse && (k->tag & KU_TAG_SURROGATE) != 0;
                    stack[n].noenter = reparse && ku_tag_is_name(k->tag);
                    stack[n].pruned = pruned;
                    n++;
                }
                for (size_t i = 0; i < dropped; i++) {
                    walk_error(w, it.path, ERROR_NOT_ENOUGH_MEMORY);
                }
            }
            ku_fs_children_free(&kids);
        }
        if (h != INVALID_HANDLE_VALUE) {
            CloseHandle(h);
        }
        if (it.reparse) {
            walk_link_row(w, shown, it.tag, it.surrogate, action, it.path);
        }
        free(shown);
        free(it.path);
    }
    free(stack);
    return 0;
}

/* fs.dirs(root [, { depth = n, prune = { "pattern", ... } }]) */
int ku_fs_dirs(lua_State *L)
{
    const char *root_utf8 = luaL_checkstring(L, 1);
    walk w;
    memset(&w, 0, sizeof w);
    w.L = L;
    w.depthcap = -1;
    const char *prune_storage[64];
    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        lua_getfield(L, 2, "depth");
        if (!lua_isnil(L, -1)) {
            int is_integer = 0;
            lua_Integer d = lua_tointegerx(L, -1, &is_integer);
            /* Negative is not "unlimited" and neither is zero: unlimited is
             * spelled by omission, and depth 0 emits the root alone. */
            if (!is_integer || d < 0 || d > 0x7fffffff) {
                return ku_err_raise(L, "FS", "badvalue", "depth must be a non-negative integer");
            }
            w.depthcap = (int)d;
        }
        lua_pop(L, 1);
        lua_getfield(L, 2, "prune");
        if (!lua_isnil(L, -1)) {
            if (lua_type(L, -1) != LUA_TTABLE) {
                return ku_err_raise(L, "FS", "badvalue", "prune must be an array of patterns");
            }
            lua_Integer count = (lua_Integer)lua_rawlen(L, -1);
            if (count > 64) {
                return ku_err_raise(L, "FS", "badvalue", "at most 64 prune patterns");
            }
            for (lua_Integer i = 1; i <= count; i++) {
                lua_rawgeti(L, -1, i);
                if (lua_type(L, -1) != LUA_TSTRING) {
                    return ku_err_raise(L, "FS", "badvalue", "prune patterns must be strings");
                }
                prune_storage[w.prune_count++] = lua_tostring(L, -1); /* anchored: the option table holds it */
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
        w.prune = prune_storage;
    }
    ku_wpath root;
    ku_fail fail;
    if (ku_wpath_make(root_utf8, &root, &fail) != 0) {
        return ku_err_raise(L, fail.domain, fail.code, "%s", fail.message);
    }
    w.unc = root.unc;
    /* The root is validated on a handle before the first emission: backup
     * semantics open files too, and a file root would otherwise be listed as
     * a directory and then fail. */
    HANDLE rh = ku_fs_open_dir(root.text, 1);
    if (rh == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        HANDLE raw = ku_fs_open_dir(root.text, 0);
        ku_wpath_free(&root);
        if (raw != INVALID_HANDLE_VALUE) {
            CloseHandle(raw);
            return ku_err_fail(L, "FS", "dangling", "'%s' exists but its target cannot be resolved", root_utf8);
        }
        ku_fs_fail(&fail, error, "open", root_utf8);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
    FILE_ATTRIBUTE_TAG_INFO root_info;
    memset(&root_info, 0, sizeof root_info);
    BOOL ok = GetFileInformationByHandleEx(rh, FileAttributeTagInfo, &root_info, sizeof root_info);
    CloseHandle(rh);
    if (!ok || !(root_info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
        ku_wpath_free(&root);
        return ku_err_fail(L, "FS", "badvalue", "'%s' is not a directory", root_utf8);
    }
    /* The root's own reparse identity needs a raw open: a followed handle
     * answers with the target's attributes.  A junction root is descended
     * (you named it) but disclosed. */
    int root_reparse = 0;
    DWORD root_tag = 0;
    HANDLE rawh = ku_fs_open_dir(root.text, 0);
    if (rawh != INVALID_HANDLE_VALUE) {
        FILE_ATTRIBUTE_TAG_INFO info;
        memset(&info, 0, sizeof info);
        if (GetFileInformationByHandleEx(rawh, FileAttributeTagInfo, &info, sizeof info) &&
            (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            root_reparse = 1;
            root_tag = info.ReparseTag;
        }
        CloseHandle(rawh);
    }
    if (!root_reparse) {
        /* A cloud filter consumes its own reparse point on open, so the
         * parent's scan is asked, for the disclosure only, never the veto. */
        WIN32_FIND_DATAW found;
        HANDLE fh = FindFirstFileW(root.text, &found);
        if (fh != INVALID_HANDLE_VALUE) {
            if ((found.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
                (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
                root_reparse = 1;
                root_tag = found.dwReserved0;
            }
            FindClose(fh);
        }
    }

    lua_settop(L, 2);
    lua_createtable(L, 0, 9); /* 3: result */
    lua_newtable(L);          /* 4: paths */
    lua_newtable(L);          /* 5: links */
    lua_newtable(L);          /* 6: errors */
    lua_newtable(L);          /* 7: skipped */
    w.paths = 4;
    w.links = 5;
    w.errors = 6;
    w.skipped = 7;
    int status = walk_run(&w, root.text, root_reparse, root_tag);
    char *shown_root = ku_wpath_show(root.text, root.unc);
    ku_wpath_free(&root);
    if (status != 0) {
        free(shown_root);
        return ku_err_fail(L, "FS", "oserror", "the walk could not be started");
    }
    lua_pushstring(L, shown_root != NULL ? shown_root : "");
    lua_setfield(L, 3, "root");
    free(shown_root);
    lua_pushvalue(L, 4);
    lua_setfield(L, 3, "paths");
    lua_pushvalue(L, 5);
    lua_setfield(L, 3, "links");
    lua_pushvalue(L, 6);
    lua_setfield(L, 3, "errors");
    lua_pushvalue(L, 7);
    lua_setfield(L, 3, "skipped");
    lua_pushinteger(L, w.count);
    lua_setfield(L, 3, "dirs");
    lua_pushinteger(L, w.pruned);
    lua_setfield(L, 3, "pruned");
    lua_pushinteger(L, w.depthlimited);
    lua_setfield(L, 3, "depthlimited");
    lua_pushinteger(L, w.maxdepth);
    lua_setfield(L, 3, "maxdepth");
    lua_settop(L, 3);
    return 1;
}
