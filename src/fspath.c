/* fspath.c -- paths across the Win32 boundary; see fspath.h. */
#include "fspath.h"
#include "wintext.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static int is_alpha(char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

int ku_wpath_make(const char *utf8, ku_wpath *out, ku_fail *fail)
{
    out->text = NULL;
    out->length = 0;
    out->unc = 0;
    if (utf8 == NULL || utf8[0] == '\0') {
        return ku_fail_set(fail, "FS", "badvalue", "the path must not be empty");
    }
    if (is_alpha(utf8[0]) && utf8[1] == ':' && utf8[2] != '\\' && utf8[2] != '/') {
        return ku_fail_set(fail, "FS", "badvalue",
                           "'%s' is drive-relative and resolves against hidden per-drive state; write %c:/...",
                           utf8, utf8[0]);
    }
    if ((utf8[0] == '\\' && utf8[1] == '\\' && utf8[2] == '.' && utf8[3] == '\\') ||
        (utf8[0] == '/' && utf8[1] == '/' && utf8[2] == '.' && utf8[3] == '/')) {
        return ku_fail_set(fail, "FS", "badvalue", "'%s' is a device path, not a file system path", utf8);
    }
    wchar_t *raw = ku_utf8_to_wide(utf8);
    if (raw == NULL) {
        return ku_fail_set(fail, "FS", "encoding", "the path is not valid UTF-8");
    }
    int already = raw[0] == L'\\' && raw[1] == L'\\' && raw[2] == L'?' && raw[3] == L'\\';
    wchar_t *full = NULL;
    if (already) {
        full = raw; /* the caller spelled the prefix: taken verbatim */
    } else {
        /* A component ending in '.' or a space is rewritten by normalisation,
         * silently, and the result can be a different name.  `.` and `..` are
         * the two components where the dots are the whole meaning. */
        for (const wchar_t *c = raw, *segment = raw;; c++) {
            if (*c == L'\\' || *c == L'/' || *c == L'\0') {
                size_t length = (size_t)(c - segment);
                int dotted = (length == 1 && segment[0] == L'.') ||
                             (length == 2 && segment[0] == L'.' && segment[1] == L'.');
                if (length > 0 && !dotted && (c[-1] == L'.' || c[-1] == L' ')) {
                    free(raw);
                    return ku_fail_set(fail, "FS", "badvalue",
                                       "a component of '%s' ends in '.' or a space, which Windows would silently "
                                       "rewrite; spell the path \\\\?\\... to reach that exact name",
                                       utf8);
                }
                if (*c == L'\0') {
                    break;
                }
                segment = c + 1;
            }
        }
        DWORD need = GetFullPathNameW(raw, 0, NULL, NULL);
        if (need == 0) {
            free(raw);
            return ku_fail_set(fail, "FS", "badvalue", "'%s' is not a usable path", utf8);
        }
        full = (wchar_t *)malloc((size_t)need * sizeof(wchar_t));
        if (full == NULL) {
            free(raw);
            return ku_fail_set(fail, "FS", "oserror", "out of memory");
        }
        /* A too-small buffer returns the required size and writes nothing;
         * reachable if the current directory grows between the two calls. */
        DWORD got = GetFullPathNameW(raw, need, full, NULL);
        free(raw);
        if (got == 0 || got >= need) {
            free(full);
            return ku_fail_set(fail, "FS", "badvalue", "'%s' is not a usable path", utf8);
        }
        already = full[0] == L'\\' && full[1] == L'\\' && full[2] == L'?' && full[3] == L'\\';
    }
    /* Trailing separators come off, except on a drive root: \\?\C: is the
     * volume device and \\?\C:\ is its root directory. */
    size_t length = wcslen(full);
    while (length > 1 && full[length - 1] == L'\\') {
        int drive_root = (length == 3 && full[1] == L':') || (already && length == 7 && full[5] == L':');
        if (drive_root) {
            break;
        }
        full[--length] = L'\0';
    }
    wchar_t *prefixed;
    if (already) {
        prefixed = full;
        out->unc = _wcsnicmp(full, L"\\\\?\\UNC\\", 8) == 0;
    } else if (full[0] == L'\\' && full[1] == L'\\') {
        /* \\server\share\x -> \\?\UNC\server\share\x */
        prefixed = (wchar_t *)malloc((length + 8) * sizeof(wchar_t));
        if (prefixed == NULL) {
            free(full);
            return ku_fail_set(fail, "FS", "oserror", "out of memory");
        }
        wcscpy(prefixed, L"\\\\?\\UNC");
        wcscat(prefixed, full + 1);
        free(full);
        out->unc = 1;
    } else {
        prefixed = (wchar_t *)malloc((length + 5) * sizeof(wchar_t));
        if (prefixed == NULL) {
            free(full);
            return ku_fail_set(fail, "FS", "oserror", "out of memory");
        }
        wcscpy(prefixed, L"\\\\?\\");
        wcscat(prefixed, full);
        free(full);
    }
    out->text = prefixed;
    out->length = wcslen(prefixed);
    return 0;
}

void ku_wpath_free(ku_wpath *path)
{
    free(path->text);
    path->text = NULL;
    path->length = 0;
}

wchar_t *ku_wpath_join(const wchar_t *parent, size_t plen, const wchar_t *name, size_t nlen)
{
    int separator = plen > 0 && parent[plen - 1] != L'\\';
    wchar_t *out = (wchar_t *)malloc((plen + (size_t)separator + nlen + 1) * sizeof(wchar_t));
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, parent, plen * sizeof(wchar_t));
    if (separator) {
        out[plen] = L'\\';
    }
    memcpy(out + plen + separator, name, nlen * sizeof(wchar_t));
    out[plen + separator + nlen] = L'\0';
    return out;
}

char *ku_wpath_show(const wchar_t *prefixed, int unc)
{
    size_t skip = 0;
    if (wcsncmp(prefixed, L"\\\\?\\", 4) == 0) {
        skip = unc || _wcsnicmp(prefixed, L"\\\\?\\UNC\\", 8) == 0 ? 8 : 4;
        unc = skip == 8;
    }
    char *tail = ku_wide_to_utf8(prefixed + skip, -1);
    if (tail == NULL) {
        return NULL;
    }
    char *out = tail;
    if (unc) {
        size_t n = strlen(tail);
        out = (char *)malloc(n + 3);
        if (out == NULL) {
            free(tail);
            return NULL;
        }
        out[0] = '/';
        out[1] = '/';
        memcpy(out + 2, tail, n + 1);
        free(tail);
    }
    for (char *c = out; *c; c++) {
        if (*c == '\\') {
            *c = '/';
        }
    }
    return out;
}

const char *ku_fs_code(DWORD error)
{
    switch (error) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_DRIVE:
    case ERROR_BAD_NETPATH:
    case ERROR_BAD_NET_NAME:
        return "notfound";
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION:
    case ERROR_WRITE_PROTECT:
        return "access";
    case ERROR_FILE_EXISTS:
    case ERROR_ALREADY_EXISTS:
        return "exists";
    case ERROR_DIR_NOT_EMPTY:
        return "notempty";
    case ERROR_INVALID_NAME:
    case ERROR_BAD_PATHNAME:
    case ERROR_FILENAME_EXCED_RANGE:
    case ERROR_DIRECTORY:
    case ERROR_INVALID_PARAMETER:
        return "badvalue";
    default:
        return "oserror";
    }
}

int ku_fs_fail(ku_fail *fail, DWORD error, const char *verb, const char *what)
{
    char *text = ku_win_error_message(error);
    ku_fail_set(fail, "FS", ku_fs_code(error), "cannot %s '%s': %s (Windows error %lu)", verb, what,
                text != NULL ? text : "unknown error", (unsigned long)error);
    free(text);
    return 1;
}
