/* program.c -- reading and decoding program text; see program.h. */
#include "program.h"
#include "wintext.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ku_fail_set(ku_fail *fail, const char *domain, const char *code,
                const char *format, ...)
{
    fail->domain = domain;
    fail->code = code;
    va_list args;
    va_start(args, format);
    vsnprintf(fail->message, sizeof fail->message, format, args);
    va_end(args);
    return 1;
}

static int win_fail(ku_fail *fail, const char *code, const char *what,
                    const char *verb, DWORD error)
{
    char *text = ku_win_error_message(error);
    ku_fail_set(fail, "ENTRY", code, "cannot %s %s: %s", verb, what,
                text != NULL ? text : "unknown Windows error");
    free(text);
    return 1;
}

void ku_program_free(ku_program *program)
{
    free(program->owned);
    program->owned = NULL;
    program->text = NULL;
    program->length = 0;
}

int ku_program_from_bytes(unsigned char *bytes, size_t length, const char *what,
                          ku_program *out, ku_fail *fail)
{
    out->owned = bytes;
    out->text = (const char *)bytes;
    out->length = length;

    size_t start = 0;
    if (length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
        start = 3;
    }
    if (!ku_utf8_valid(bytes + start, length - start)) {
        ku_program_free(out);
        return ku_fail_set(fail, "ENTRY", "encoding", "%s is not valid UTF-8", what);
    }
    /* A first line beginning with '#' (a shebang or an editor tag) is not
     * Lua.  Skip to its newline and keep the newline: line 2 stays line 2. */
    if (start < length && bytes[start] == '#') {
        while (start < length && bytes[start] != '\n') {
            start++;
        }
    }
    out->text = (const char *)bytes + start;
    out->length = length - start;
    return 0;
}

int ku_program_read_file(const wchar_t *path, const char *what,
                         ku_program *out, ku_fail *fail)
{
    memset(out, 0, sizeof *out);

    DWORD attributes = GetFileAttributesW(path);
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        return ku_fail_set(fail, "ENTRY", "badvalue", "%s is a directory", what);
    }
    HANDLE handle = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        switch (error) {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
        case ERROR_INVALID_NAME:
        case ERROR_BAD_NETPATH:
        case ERROR_INVALID_DRIVE:
            return ku_fail_set(fail, "ENTRY", "notfound", "cannot find %s", what);
        case ERROR_ACCESS_DENIED:
        case ERROR_SHARING_VIOLATION:
        case ERROR_LOCK_VIOLATION:
            return win_fail(fail, "access", what, "open", error);
        default:
            return win_fail(fail, "oserror", what, "open", error);
        }
    }
    if (GetFileType(handle) != FILE_TYPE_DISK) {
        CloseHandle(handle);
        return ku_fail_set(fail, "ENTRY", "badvalue", "%s is not a regular file", what);
    }
    LARGE_INTEGER size;
    if (!GetFileSizeEx(handle, &size)) {
        DWORD error = GetLastError();
        CloseHandle(handle);
        return win_fail(fail, "oserror", what, "measure", error);
    }
    if (size.QuadPart > (LONGLONG)KU_PROGRAM_MAX) {
        CloseHandle(handle);
        return ku_fail_set(fail, "ENTRY", "toobig", "%s is larger than 16 MiB", what);
    }
    size_t wanted = (size_t)size.QuadPart;
    unsigned char *bytes = (unsigned char *)malloc(wanted > 0 ? wanted : 1);
    if (bytes == NULL) {
        CloseHandle(handle);
        return ku_fail_set(fail, "ENTRY", "oserror", "out of memory reading %s", what);
    }
    size_t got = 0;
    while (got < wanted) {
        DWORD received = 0;
        if (!ReadFile(handle, bytes + got, (DWORD)(wanted - got), &received, NULL)) {
            DWORD error = GetLastError();
            free(bytes);
            CloseHandle(handle);
            return win_fail(fail, "oserror", what, "read", error);
        }
        if (received == 0) {
            break; /* the file shrank under us; take what there is */
        }
        got += received;
    }
    CloseHandle(handle);
    return ku_program_from_bytes(bytes, got, what, out, fail);
}

int ku_program_read_stdin(ku_program *out, ku_fail *fail)
{
    memset(out, 0, sizeof *out);
    const char *what = "the stdin program";

    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    if (handle == INVALID_HANDLE_VALUE || handle == NULL) {
        return ku_fail_set(fail, "ENTRY", "stdin",
                           "no standard input is available for the stdin program");
    }
    size_t capacity = 65536, count = 0;
    unsigned char *bytes = (unsigned char *)malloc(capacity);
    if (bytes == NULL) {
        return ku_fail_set(fail, "ENTRY", "oserror", "out of memory reading %s", what);
    }
    for (;;) {
        if (count == capacity) {
            if (count > KU_PROGRAM_MAX) {
                break;
            }
            size_t next = capacity * 2;
            if (next > KU_PROGRAM_MAX + 1) {
                next = KU_PROGRAM_MAX + 1; /* one byte past the bound proves the overflow */
            }
            unsigned char *grown = (unsigned char *)realloc(bytes, next);
            if (grown == NULL) {
                free(bytes);
                return ku_fail_set(fail, "ENTRY", "oserror", "out of memory reading %s", what);
            }
            bytes = grown;
            capacity = next;
        }
        DWORD received = 0;
        if (!ReadFile(handle, bytes + count, (DWORD)(capacity - count), &received, NULL)) {
            DWORD error = GetLastError();
            if (error == ERROR_BROKEN_PIPE || error == ERROR_HANDLE_EOF) {
                break;
            }
            free(bytes);
            return win_fail(fail, "oserror", what, "read", error);
        }
        if (received == 0) {
            break;
        }
        count += received;
    }
    if (count > KU_PROGRAM_MAX) {
        free(bytes);
        return ku_fail_set(fail, "ENTRY", "toobig", "%s is larger than 16 MiB", what);
    }
    return ku_program_from_bytes(bytes, count, what, out, fail);
}
