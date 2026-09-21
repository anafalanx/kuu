/* Project-owned Unicode Shell Link writer. No shortcut is opened or executed.
 * create LINK TARGET CWD ARG... : save three separate COM properties, quote
 * only the argument field for a Windows CRT child, then publish without replace.
 * All three paths are absolute; LINK must end in .lnk and must not exist.
 * Parent directories belong to the caller and must not be concurrently moved.
 * gcc -std=c23 -O2 -Wall -Wextra -Werror -Wpedantic -Wformat=2 -municode
 *     -static examples/shell_link.c -o shell_link.exe -lole32 -luuid
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <windows.h>
#include <objbase.h>
#include <shobjidl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static wchar_t *absolute(const wchar_t *path)
{
    size_t n = wcslen(path);
    int drive = n >= 3 && ((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z')) &&
        path[1] == L':' && (path[2] == L'/' || path[2] == L'\\');
    int unc = n > 2 && (path[0] == L'/' || path[0] == L'\\') && path[1] == path[0];
    if ((!drive && !unc) || (unc && (path[2] == L'?' || path[2] == L'.'))) {
        SetLastError(ERROR_INVALID_NAME); return NULL;
    }
    DWORD count = GetFullPathNameW(path, 0, NULL, NULL);
    if (!count || count > 32000) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *result = calloc(count, sizeof *result);
    if (!result) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    DWORD got = GetFullPathNameW(path, count, result, NULL);
    if (!got || got >= count) { free(result); return NULL; }
    for (DWORD i = 0; i < got; i++) {
        if (result[i] == L'/') result[i] = L'\\';
        if ((result[i] == L'.' || result[i] == L' ') &&
            (i + 1 == got || result[i + 1] == L'/' || result[i + 1] == L'\\')) {
            free(result); SetLastError(ERROR_INVALID_NAME); return NULL;
        }
    }
    return result;
}

/* The target is not part of IShellLink::SetArguments. Every ARG, including an
 * empty one, is quoted independently using the Windows CRT backslash rules. */
static wchar_t *arguments(int argc, wchar_t **argv)
{
    size_t capacity = 1;
    for (int i = 0; i < argc; i++) {
        size_t length = wcslen(argv[i]);
        if (length > 32767 || capacity > 131071 - (length * 2 + 3)) {
            SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL;
        }
        capacity += length * 2 + 3;
    }
    wchar_t *result = calloc(capacity, sizeof *result);
    if (!result) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    size_t at = 0;
    for (int i = 0; i < argc; i++) {
        if (i) result[at++] = L' ';
        result[at++] = L'"';
        const wchar_t *p = argv[i];
        while (*p) {
            size_t slash = 0;
            while (*p == L'\\') { slash++; p++; }
            size_t emitted = !*p || *p == L'"' ? slash * 2 : slash;
            for (size_t j = 0; j < emitted; j++) result[at++] = L'\\';
            if (*p == L'"') result[at++] = L'\\';
            if (*p) result[at++] = *p++;
        }
        result[at++] = L'"';
    }
    if (at + 1 > 32767) { free(result); SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    return result;
}

static wchar_t *reserve_sibling(const wchar_t *link)
{
    const wchar_t *slash = wcsrchr(link, L'\\');
    if (!slash) { SetLastError(ERROR_INVALID_NAME); return NULL; }
    size_t prefix = (size_t)(slash - link + 1);
    wchar_t *temp = calloc(prefix + 80, sizeof *temp);
    if (!temp) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    GUID id;
    wchar_t uuid[40];
    if (CoCreateGuid(&id) != S_OK || !StringFromGUID2(&id, uuid, 40)) {
        free(temp); SetLastError(ERROR_GEN_FAILURE); return NULL;
    }
    memcpy(temp, link, prefix * sizeof *temp);
    swprintf(temp + prefix, 80, L".kuu-shortcut-%ls.lnk", uuid);
    HANDLE owned = CreateFileW(temp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (owned == INVALID_HANDLE_VALUE) { free(temp); return NULL; }
    CloseHandle(owned);
    return temp;
}

static int create(int argc, wchar_t **argv)
{
    const char *operation = "absolute paths";
    HRESULT hr = S_OK;
    DWORD win32 = 0, cleanup_error = 0;
    wchar_t *link = NULL, *target = NULL, *cwd = NULL;
    wchar_t *args = NULL, *temporary = NULL;
    IShellLinkW *shell = NULL;
    IPersistFile *persist = NULL;
    int initialized = 0, published = 0;
    link = absolute(argv[2]);
    if (!link) { win32 = GetLastError(); goto done; }
    target = absolute(argv[3]);
    if (!target) { win32 = GetLastError(); goto done; }
    cwd = absolute(argv[4]);
    if (!cwd) { win32 = GetLastError(); goto done; }
    size_t link_len = wcslen(link);
    if (link_len < 4 || _wcsicmp(link + link_len - 4, L".lnk")) { win32 = ERROR_INVALID_NAME; goto done; }
    operation = "new shortcut";
    DWORD attrs = GetFileAttributesW(link);
    if (attrs != INVALID_FILE_ATTRIBUTES) { win32 = ERROR_ALREADY_EXISTS; goto done; }
    win32 = GetLastError();
    if (win32 != ERROR_FILE_NOT_FOUND) goto done;
    win32 = 0;
    operation = "target";
    attrs = GetFileAttributesW(target);
    if (attrs == INVALID_FILE_ATTRIBUTES) { win32 = GetLastError(); goto done; }
    if (attrs & FILE_ATTRIBUTE_DIRECTORY) { win32 = ERROR_DIRECTORY; goto done; }
    operation = "working directory";
    attrs = GetFileAttributesW(cwd);
    if (attrs == INVALID_FILE_ATTRIBUTES) { win32 = GetLastError(); goto done; }
    if (!(attrs & FILE_ATTRIBUTE_DIRECTORY)) { win32 = ERROR_DIRECTORY; goto done; }
    operation = "argument encoding";
    args = arguments(argc - 5, argv + 5);
    if (!args) { win32 = GetLastError(); goto done; }
    /* Include the quoted executable and separator in the CreateProcess limit. */
    if (wcslen(target) + wcslen(args) + 4 > 32767) { win32 = ERROR_FILENAME_EXCED_RANGE; goto done; }
    operation = "CoInitializeEx";
    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) goto done;
    initialized = 1;
    operation = "CoCreateInstance";
    hr = CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, (void **)&shell);
    if (hr != S_OK) goto done;
    operation = "SetPath";
    hr = IShellLinkW_SetPath(shell, target);
    if (hr != S_OK) goto done;
    operation = "SetWorkingDirectory";
    hr = IShellLinkW_SetWorkingDirectory(shell, cwd);
    if (hr != S_OK) goto done;
    operation = "SetArguments";
    hr = IShellLinkW_SetArguments(shell, args);
    if (hr != S_OK) goto done;
    operation = "QueryInterface IPersistFile";
    hr = IShellLinkW_QueryInterface(shell, &IID_IPersistFile, (void **)&persist);
    if (hr != S_OK) goto done;
    operation = "reserve private staging file";
    temporary = reserve_sibling(link);
    if (!temporary) { win32 = GetLastError(); goto done; }
    operation = "IPersistFile::Save";
    hr = IPersistFile_Save(persist, temporary, FALSE);
    /* S_FALSE is not a successful save, although FAILED(S_FALSE) is false. */
    if (hr != S_OK) goto done;
    IPersistFile_Release(persist); persist = NULL;
    IShellLinkW_Release(shell); shell = NULL;
    operation = "publish new shortcut";
    for (int attempt = 0; attempt < 6; attempt++) {
        if (MoveFileExW(temporary, link, 0)) { published = 1; win32 = 0; break; }
        win32 = GetLastError();
        if ((win32 != ERROR_ACCESS_DENIED && win32 != ERROR_SHARING_VIOLATION) || attempt == 5) break;
        Sleep(10);
    }
done:
    if (persist) IPersistFile_Release(persist);
    if (shell) IShellLinkW_Release(shell);
    if (initialized) CoUninitialize();
    if (temporary && !published && !DeleteFileW(temporary)) cleanup_error = GetLastError();
    if (!published) fprintf(stderr, "shell_link: %s failed (HRESULT 0x%08lx, Windows error %lu; cleanup error %lu)\n",
        operation, (unsigned long)hr, (unsigned long)win32, (unsigned long)cleanup_error);
    free(link); free(target); free(cwd); free(args); free(temporary);
    return published ? 0 : 1;
}

int wmain(int argc, wchar_t **argv)
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (argc >= 5 && !wcscmp(argv[1], L"create")) return create(argc, argv);
    fputs("usage: shell_link.exe create LINK TARGET CWD [ARG ...]\n", stderr);
    return 2;
}
