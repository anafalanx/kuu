/*
 * fspath.h -- how a path crosses into Win32 and back, for the fs module.
 *
 * Inbound, a UTF-8 path becomes an absolute, `\\?\`-prefixed UTF-16 path:
 * GetFullPathNameW first (the prefix turns off every normalisation the object
 * manager would do, so prefixing an unnormalised path is the standard route to
 * ERROR_INVALID_NAME), then the prefix.  The prefix is what makes paths beyond
 * 260 characters work; neither the longPathAware manifest nor the policy helps
 * a path you did not prefix.  Outbound, the prefix comes off and separators
 * become forward slashes; a UNC root's eight-character prefix stands in for
 * two.  Refused by name: drive-relative roots (hidden per-drive state), device
 * paths, and components ending in '.' or a space, which normalisation would
 * silently rewrite into a different name.  All of this was measured in
 * machteld's dirs.c and is inherited, not redesigned.
 */
#ifndef KUU_FSPATH_H
#define KUU_FSPATH_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stddef.h>

#include "kuu.h"

typedef struct ku_wpath {
    wchar_t *text; /* \\?\-prefixed, malloc'd */
    size_t length;
    int unc;       /* the prefix is \\?\UNC\ */
} ku_wpath;

/* UTF-8 -> prefixed absolute path.  On failure fills `fail` (domain FS,
 * codes badvalue | encoding) and returns non-zero. */
int ku_wpath_make(const char *utf8, ku_wpath *out, ku_fail *fail);
void ku_wpath_free(ku_wpath *path);

/* Parent + separator + name (nlen units), prefixed; malloc'd; NULL on oom.
 * Adds the separator only when the parent lacks one: under \\?\ a doubled
 * separator is a real empty component and fails with ERROR_INVALID_NAME. */
wchar_t *ku_wpath_join(const wchar_t *parent, size_t plen, const wchar_t *name, size_t nlen);

/* Prefixed UTF-16 -> UTF-8 with forward slashes and the prefix removed.
 * malloc'd; NULL when the name is not representable or on oom. */
char *ku_wpath_show(const wchar_t *prefixed, int unc);

/* A Win32 error into an FS failure about `what` (a UTF-8 path or a noun).
 * Codes: notfound, access, exists, notempty, badvalue, oserror. Returns 1. */
int ku_fs_fail(ku_fail *fail, DWORD error, const char *verb, const char *what);
const char *ku_fs_code(DWORD error);

#endif /* KUU_FSPATH_H */
