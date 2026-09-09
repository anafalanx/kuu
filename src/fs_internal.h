/*
 * fs_internal.h -- shared pieces of the fs module (fs.c, fs_dirs.c, fs_watch.c).
 */
#ifndef KUU_FS_INTERNAL_H
#define KUU_FS_INTERNAL_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>

#include <stddef.h>

#include "fspath.h"
#include "kuu.h"
#include "lua.h"

/* A reparse tag with this bit set is a name for something else (junction,
 * symlink, mount point).  Everything else is content behind a filter.  DFS and
 * DFSR are namespace redirections that do not set the bit. */
#define KU_TAG_SURROGATE 0x20000000u
#define KU_TAG_DFS 0x8000000Au
#define KU_TAG_DFSR 0x80000012u
#define KU_TAG_MOUNT_POINT 0xa0000003u

static inline int ku_tag_is_name(DWORD tag)
{
    return (tag & KU_TAG_SURROGATE) != 0 || tag == KU_TAG_DFS || tag == KU_TAG_DFSR;
}

/* One child found by enumeration.  `wname` is the UTF-16 name for building
 * paths; `name` is UTF-8 for sorting and reporting, NULL when the name is not
 * representable (counted by the caller). */
typedef struct ku_child_entry {
    wchar_t *wname;
    size_t wlen;
    char *name;
    DWORD attributes;
    DWORD tag;       /* meaningful only when attributes has REPARSE_POINT */
    LONGLONG size;
    LONGLONG mtime;  /* FILETIME as a 64-bit count */
    LONGLONG ctime;
    LONGLONG atime;
} ku_child_entry;

typedef struct ku_children {
    ku_child_entry *items;
    size_t count;
    size_t unrepresentable; /* names refused by the strict conversion */
    size_t lost;            /* entries dropped for lack of memory */
    int overrun;            /* the kernel's record chain left the buffer */
    DWORD error;            /* a non-terminal enumeration failure */
} ku_children;

/* Open a directory for listing.  `follow` == 0 opens a reparse point itself
 * (its own attributes, not its target's). */
HANDLE ku_fs_open_dir(const wchar_t *path, int follow);

/* Enumerate one directory into a sorted child array (UTF-8 byte order,
 * unsigned).  `.` and `..` are skipped.  Returns 0 on success; -1 when the
 * first call failed (children->error holds the code). */
int ku_fs_enumerate(HANDLE dir, ku_children *children);
void ku_fs_children_free(ku_children *children);

/* Where a name surrogate points: malloc'd UTF-8, or NULL. */
char *ku_fs_link_target(const wchar_t *path, int is_directory);
const char *ku_fs_link_type(DWORD tag, int is_directory);

/* Case-insensitive wildcard match ('*' and '?') on UTF-8 bytes. */
int ku_fs_wildcard(const char *pattern, const char *name);

/* FILETIME-as-64-bit -> seconds since the Unix epoch. */
double ku_fs_time_seconds(LONGLONG filetime);

/* The module's functions implemented in the other files. */
int ku_fs_dirs(lua_State *L);
int ku_fs_watch(lua_State *L);
void ku_fs_watch_meta(lua_State *L);

#endif /* KUU_FS_INTERNAL_H */
