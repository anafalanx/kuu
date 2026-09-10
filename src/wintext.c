/* wintext.c -- strict UTF-8 <-> UTF-16 conversion; see wintext.h. */
#include "wintext.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

wchar_t *ku_utf8_to_wide(const char *utf8)
{
    if (utf8 == NULL) {
        return NULL;
    }
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
    if (n <= 0) {
        return NULL;
    }
    wchar_t *wide = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (wide == NULL) {
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, wide, n) <= 0) {
        free(wide);
        return NULL;
    }
    return wide;
}

char *ku_wide_to_utf8(const wchar_t *wide, int count)
{
    if (wide == NULL) {
        return NULL;
    }
    int need = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, count,
                                   NULL, 0, NULL, NULL);
    if (need <= 0) {
        return NULL;
    }
    /* With count == -1 the size includes the terminator; with an explicit
     * count it does not.  One extra byte and an explicit terminator make the
     * result a C string either way. */
    char *utf8 = (char *)malloc((size_t)need + 1);
    if (utf8 == NULL) {
        return NULL;
    }
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, count,
                            utf8, need, NULL, NULL) <= 0) {
        free(utf8);
        return NULL;
    }
    utf8[need] = '\0';
    return utf8;
}

int ku_utf8_valid(const unsigned char *bytes, size_t length)
{
    if (length == 0) {
        return 1;
    }
    if (bytes == NULL || length > (size_t)INT_MAX) {
        return 0;
    }
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                               (const char *)bytes, (int)length, NULL, 0) > 0;
}

char *ku_win_error_message(unsigned long error)
{
    wchar_t *wide = NULL;
    DWORD n = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                             FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)error,
                             MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                             (LPWSTR)&wide, 0, NULL);
    char *text = NULL;
    if (n > 0 && wide != NULL) {
        while (n > 0 && (wide[n - 1] == L'\r' || wide[n - 1] == L'\n' ||
                         wide[n - 1] == L' ' || wide[n - 1] == L'.')) {
            n--;
        }
        if (n > 0) {
            text = ku_wide_to_utf8(wide, (int)n);
        }
    }
    if (wide != NULL) {
        LocalFree(wide);
    }
    if (text == NULL) {
        text = (char *)malloc(48);
        if (text != NULL) {
            snprintf(text, 48, "Windows error %lu", error);
        }
    }
    return text;
}

char *ku_getenv_utf8(const wchar_t *name)
{
    for (;;) {
        SetLastError(ERROR_SUCCESS);
        DWORD need = GetEnvironmentVariableW(name, NULL, 0);
        if (need == 0) {
            return GetLastError() == ERROR_SUCCESS ? _strdup("") : NULL;
        }
        wchar_t *value = (wchar_t *)malloc((size_t)need * sizeof(wchar_t));
        if (value == NULL) {
            return NULL;
        }
        SetLastError(ERROR_SUCCESS);
        DWORD got = GetEnvironmentVariableW(name, value, need);
        DWORD error = GetLastError();
        if (got >= need) {
            free(value); /* the value grew between the two calls */
            continue;
        }
        char *utf8 = got == 0 ? (error == ERROR_SUCCESS ? _strdup("") : NULL)
                             : ku_wide_to_utf8(value, (int)got);
        free(value);
        return utf8;
    }
}
