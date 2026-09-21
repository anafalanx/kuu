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
#include "values.h"
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
    char *relative; /* private collector: project-relative, '/' separators */
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
    int files;   /* private collector only; zero keeps fs.dirs unchanged */
    lua_Integer path_count, skipped_count, link_count, error_count;
    lua_Integer file_count, enumerated;
    lua_Integer count, pruned, depthlimited, maxdepth;
    int depthcap;
    int unc;
    const char **prune;
    int prune_count;
    const char **exclude_dirs;
    const char **exclude_paths;
    int exclude_dir_count, exclude_path_count;
    const char *prefix;
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
                          const wchar_t *full, int is_directory)
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
    if (w->files) {
        lua_pushstring(L, is_directory ? "directory" : "file");
        lua_setfield(L, -2, "kind");
    }
    if (ku_tag_is_name(tag)) {
        const char *type = ku_fs_link_type(tag, is_directory);
        char *target = ku_fs_link_target(full, is_directory);
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

static char *walk_relative(const char *parent, const char *name)
{
    size_t plen = strlen(parent), nlen = strlen(name);
    if (nlen > SIZE_MAX - plen - 2) {
        return NULL;
    }
    char *result = (char *)malloc(plen + nlen + 2);
    if (result != NULL) {
        memcpy(result, parent, plen);
        if (plen != 0) {
            result[plen++] = '/';
        }
        memcpy(result + plen, name, nlen + 1);
    }
    return result;
}

static int walk_exact(const char *rule, const char *value)
{
    while (*rule && *value && fold((unsigned char)*rule) == fold((unsigned char)*value)) {
        rule++;
        value++;
    }
    return *rule == '\0' && *value == '\0';
}

/* Metadata comes from the same directory batch used to schedule children.
 * No second enumeration, file stat, or content read is needed. */
static void walk_file(walk *w, const walk_item *parent, const ku_child_entry *entry)
{
    lua_State *L = w->L;
    wchar_t *full = ku_wpath_join(parent->path, wcslen(parent->path), entry->wname, entry->wlen);
    char *relative = walk_relative(parent->relative, entry->name);
    char *shown = full != NULL ? ku_wpath_show(full, w->unc) : NULL;
    if (full == NULL || relative == NULL || shown == NULL) {
        walk_error(w, parent->path, ERROR_NOT_ENOUGH_MEMORY);
    } else if ((entry->attributes & FILE_ATTRIBUTE_REPARSE_POINT) && ku_tag_is_name(entry->tag)) {
        walk_link_row(w, shown, entry->tag, (entry->tag & KU_TAG_SURROGATE) != 0, "nofollow", full, 0);
    } else {
        lua_createtable(L, 0, 7);
        lua_pushstring(L, shown);
        lua_setfield(L, -2, "path");
        lua_pushstring(L, relative);
        lua_setfield(L, -2, "relative");
        lua_pushinteger(L, (lua_Integer)entry->size);
        lua_setfield(L, -2, "size");
        lua_pushnumber(L, ku_fs_time_seconds(entry->mtime));
        lua_setfield(L, -2, "mtime");
        lua_pushinteger(L, (lua_Integer)entry->attributes);
        lua_setfield(L, -2, "attrs");
        if (entry->attributes & FILE_ATTRIBUTE_REPARSE_POINT) {
            char hex[16];
            snprintf(hex, sizeof hex, "0x%08lx", (unsigned long)entry->tag);
            lua_pushstring(L, hex);
            lua_setfield(L, -2, "reparse");
        }
        lua_rawseti(L, w->files, ++w->file_count);
    }
    free(shown);
    free(relative);
    free(full);
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
    stack[0].relative = w->files ? _strdup(w->prefix) : NULL;
    if (stack[0].path == NULL || (w->files && stack[0].relative == NULL)) {
        free(stack[0].path);
        free(stack[0].relative);
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
        /* Decide before emitting.  A pruned directory was excluded by name, so
         * it belongs in `skipped`, never in `paths`: listing it there made the
         * obvious walk -- list the files of every path -- read exactly the
         * content the prune was asked to exclude.  The depth cap and a name
         * surrogate still emit into `paths`, because those directories are the
         * frontier the caller asked to stop at rather than names it excluded. */
        int depth_stop = (w->depthcap >= 0 && it.depth >= w->depthcap);
        int prune_stop = it.pruned;

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
        if (depth_stop && !prune_stop) {
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
            BOOL classified = GetFileInformationByHandleEx(h, FileAttributeTagInfo, &info, sizeof info);
            if (!classified && w->files) {
                /* A classification failure cannot establish that descent is
                 * safe. The collector keeps an explicit incomplete result. */
                walk_error(w, it.path, GetLastError());
                action = "failed";
                stop = 1;
            } else if (classified && (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
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
            w->enumerated++;
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
                if (w->files) {
                    for (size_t i = 0; i < kids.count; i++) {
                        if (!(kids.items[i].attributes & FILE_ATTRIBUTE_DIRECTORY)) {
                            walk_file(w, &it, &kids.items[i]);
                        }
                    }
                }
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
                    char *relative = w->files ? walk_relative(it.relative, k->name) : NULL;
                    if (child == NULL || (w->files && relative == NULL)) {
                        free(child);
                        free(relative);
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
                    for (int p = 0; !pruned && p < w->exclude_dir_count; p++) {
                        pruned = walk_exact(w->exclude_dirs[p], k->name);
                    }
                    for (int p = 0; !pruned && p < w->exclude_path_count; p++) {
                        pruned = walk_exact(w->exclude_paths[p], relative);
                    }
                    int reparse = (k->attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
                    stack[n].path = child;
                    stack[n].relative = relative;
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
            walk_link_row(w, shown, it.tag, it.surrogate, action, it.path, 1);
        }
        free(shown);
        free(it.path);
        free(it.relative);
    }
    free(stack);
    return 0;
}

/* Declarative rules are already-normalized exact names/paths. A separate
 * legacy_prune option preserves mutable checker wildcard configuration.
 * Validate the entire shape before owning native resources;
 * raw access prevents metatables from manufacturing unanchored string values. */
static const char *scan_string(lua_State *L, int index, int path, int allow_empty)
{
    size_t length = 0;
    if (lua_type(L, index) != LUA_TSTRING) {
        ku_err_raise(L, "FS", "badvalue", "scan rules and prefix must be strings");
    }
    const char *value = lua_tolstring(L, index, &length);
    if (memchr(value, '\0', length) != NULL ||
        !ku_utf8_valid((const unsigned char *)value, length)) {
        ku_err_raise(L, "FS", "badvalue", "scan rules and prefix must be valid UTF-8 without NUL");
    }
    if (length == 0) {
        if (!allow_empty) {
            ku_err_raise(L, "FS", "badvalue", "scan rules must not be empty");
        }
        return value;
    }
    size_t start = 0;
    for (size_t i = 0; i <= length; i++) {
        unsigned char c = (unsigned char)value[i];
        if (c == '/' || c == '\0') {
            size_t component = i - start;
            if ((c == '/' && !path) || component == 0 ||
                (component == 1 && value[start] == '.') ||
                (component == 2 && value[start] == '.' && value[start + 1] == '.')) {
                ku_err_raise(L, "FS", "badvalue", "scan paths must be normalized relative paths");
            }
            start = i + 1;
        } else if (c < 32 || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' ||
                   c == '<' || c == '>' || c == '|') {
            ku_err_raise(L, "FS", "badvalue", "scan rules require exact normalized directory names");
        }
    }
    return value;
}

static int scan_rules(lua_State *L, int options, const char *field, const char **storage, int limit, int path)
{
    lua_pushstring(L, field);
    lua_rawget(L, options);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    if (lua_type(L, -1) != LUA_TTABLE) {
        return ku_err_raise(L, "FS", "badvalue", "%s must be an array of strings", field);
    }
    size_t count = lua_rawlen(L, -1);
    if (count > (size_t)limit) {
        return ku_err_raise(L, "FS", "badvalue", "at most %d %s rules are allowed", limit, field);
    }
    int array = lua_absindex(L, -1);
    lua_pushnil(L);
    while (lua_next(L, array) != 0) {
        int integer = 0;
        lua_Integer key = lua_tointegerx(L, -2, &integer);
        if (lua_type(L, -2) != LUA_TNUMBER || !integer || key < 1 || (lua_Unsigned)key > count) {
            return ku_err_raise(L, "FS", "badvalue", "%s must be a dense array of strings", field);
        }
        lua_pop(L, 1);
    }
    for (size_t i = 0; i < count; i++) {
        lua_rawgeti(L, array, (lua_Integer)i + 1);
        if (path < 0) {
            /* Compatibility with callers mutating check.PRUNE: these are
             * legacy basename wildcards, never declarative policy rules. */
            size_t length = 0;
            if (lua_type(L, -1) != LUA_TSTRING) {
                return ku_err_raise(L, "FS", "badvalue", "%s patterns must be strings", field);
            }
            const char *pattern = lua_tolstring(L, -1, &length);
            if (memchr(pattern, '\0', length) != NULL ||
                !ku_utf8_valid((const unsigned char *)pattern, length)) {
                return ku_err_raise(L, "FS", "badvalue", "%s patterns must be valid UTF-8 without NUL", field);
            }
            storage[i] = pattern;
        } else {
            storage[i] = scan_string(L, -1, path, 0);
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    return (int)count;
}

static void scan_options(lua_State *L, walk *w, const char **dirs, const char **paths, const char **legacy)
{
    w->prefix = "";
    if (lua_isnoneornil(L, 2)) {
        return;
    }
    if (lua_type(L, 2) != LUA_TTABLE) {
        ku_err_raise(L, "FS", "badvalue", "scan options must be a table");
    }
    lua_pushnil(L);
    while (lua_next(L, 2) != 0) {
        size_t length = 0;
        const char *key = lua_type(L, -2) == LUA_TSTRING ? lua_tolstring(L, -2, &length) : NULL;
        if (key == NULL || memchr(key, '\0', length) != NULL ||
            (strcmp(key, "prefix") != 0 && strcmp(key, "exclude_dirs") != 0 &&
             strcmp(key, "exclude_paths") != 0 && strcmp(key, "legacy_prune") != 0)) {
            ku_err_raise(L, "FS", "usage", "unknown scan option");
        }
        lua_pop(L, 1);
    }
    w->exclude_dir_count = scan_rules(L, 2, "exclude_dirs", dirs, 265, 0);
    w->exclude_path_count = scan_rules(L, 2, "exclude_paths", paths, 256, 1);
    w->prune_count = scan_rules(L, 2, "legacy_prune", legacy, 64, -1);
    w->prune = legacy;
    w->exclude_dirs = dirs;
    w->exclude_paths = paths;
    lua_pushliteral(L, "prefix");
    lua_rawget(L, 2);
    if (!lua_isnil(L, -1)) {
        w->prefix = scan_string(L, -1, 1, 1);
    }
    lua_pop(L, 1);
}

/* fs.dirs and the private collector share the exact same native walker. */
static int walk_collect(lua_State *L, int collect_files)
{
    const char *root_utf8 = ku_check_cstring(L, 1, "FS", "path");
    walk w;
    memset(&w, 0, sizeof w);
    w.L = L;
    w.depthcap = -1;
    const char *prune_storage[64];
    const char *dir_storage[265], *path_storage[256];
    if (collect_files) {
        scan_options(L, &w, dir_storage, path_storage, prune_storage);
    } else if (!lua_isnoneornil(L, 2)) {
        static const char *const options[] = {"depth", "prune", NULL};
        ku_check_options(L, 2, "FS", options);
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
    DWORD root_info_error = ok ? 0 : GetLastError();
    CloseHandle(rh);
    if (!ok && collect_files) {
        ku_wpath_free(&root);
        ku_fs_fail(&fail, root_info_error, "classify", root_utf8);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
    }
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
        BOOL classified = GetFileInformationByHandleEx(rawh, FileAttributeTagInfo, &info, sizeof info);
        DWORD classify_error = classified ? 0 : GetLastError();
        CloseHandle(rawh);
        if (!classified && collect_files) {
            ku_wpath_free(&root);
            ku_fs_fail(&fail, classify_error, "classify", root_utf8);
            return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
        }
        if (classified && (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            root_reparse = 1;
            root_tag = info.ReparseTag;
        }
    } else if (collect_files) {
        DWORD error = GetLastError();
        ku_wpath_free(&root);
        ku_fs_fail(&fail, error, "classify", root_utf8);
        return ku_err_fail(L, fail.domain, fail.code, "%s", fail.message);
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
    if (collect_files) {
        lua_newtable(L);      /* 8: files */
        w.files = 8;
    }
    int status = walk_run(&w, root.text, root_reparse, root_tag);
    char *shown_root = ku_wpath_show(root.text, root.unc);
    if (shown_root == NULL && collect_files && status == 0) {
        walk_error(&w, root.text, ERROR_NOT_ENOUGH_MEMORY);
    }
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
    if (collect_files) {
        lua_pushvalue(L, w.files);
        lua_setfield(L, 3, "files");
        lua_pushinteger(L, w.enumerated);
        lua_setfield(L, 3, "enumerated");
    }
    lua_settop(L, 3);
    return 1;
}

/* fs.dirs(root [, { depth = n, prune = { "pattern", ... } }]) */
int ku_fs_dirs(lua_State *L)
{
    return walk_collect(L, 0);
}

static int scan_collect(lua_State *L)
{
    return walk_collect(L, 1);
}

int ku_open_scan_native(lua_State *L)
{
    static const luaL_Reg functions[] = {{"collect", scan_collect}, {NULL, NULL}};
    luaL_newlib(L, functions);
    return 1;
}
