/* Owned scan fixtures for reproductions and ordinary collector tests.
 * gcc -std=c11 -Wall -Wextra -Werror -O2 -municode -o scan_fixture.exe scan_fixture.c
 * junction LINK TARGET | hold PATH READY RELEASE
 * hold denies all sharing for at most 30 seconds; READY appears after open.
 * The Lua driver owns every supplied path. This helper never removes files.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>

static int failure(const char *operation) {
    printf("{\"operation\":\"%s\",\"win32\":%lu}\n", operation, GetLastError());
    return 1;
}

static int marker(const wchar_t *path) {
    HANDLE h = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                          CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return failure("ready");
    CloseHandle(h);
    return 0;
}

static int hold(const wchar_t *path, const wchar_t *ready, const wchar_t *release) {
    HANDLE h = CreateFileW(path, GENERIC_READ, 0, NULL, OPEN_EXISTING,
                          FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (h == INVALID_HANDLE_VALUE) return failure("hold");
    if (marker(ready)) { CloseHandle(h); return 1; }
    ULONGLONG start = GetTickCount64();
    while (GetFileAttributesW(release) == INVALID_FILE_ATTRIBUTES) {
        if (GetTickCount64() - start > 30000) {
            CloseHandle(h);
            SetLastError(ERROR_TIMEOUT);
            return failure("release");
        }
        Sleep(10);
    }
    CloseHandle(h);
    puts("{\"released\":true}");
    return 0;
}

static int junction(const wchar_t *link, const wchar_t *target) {
    struct mount_data {
        DWORD tag;
        WORD length, reserved;
        WORD substitute_offset, substitute_length, print_offset, print_length;
        wchar_t paths[32768];
    } data;
    size_t length = wcslen(target);
    if (length < 3 || length > 8000 || target[1] != L':') {
        SetLastError(ERROR_INVALID_NAME);
        return failure("target");
    }
    memset(&data, 0, sizeof(data));
    data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    wcscpy(data.paths, L"\\??\\");
    wcscat(data.paths, target);
    data.substitute_length = (WORD)((length + 4) * sizeof(wchar_t));
    data.print_offset = (WORD)((length + 5) * sizeof(wchar_t));
    data.print_length = (WORD)(length * sizeof(wchar_t));
    wcscpy(data.paths + length + 5, target);
    data.length = (WORD)(8 + (length * 2 + 6) * sizeof(wchar_t));
    if (!CreateDirectoryW(link, NULL)) return failure("mkdir");
    HANDLE h = CreateFileW(link, GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
                          FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return failure("junction-open");
    DWORD bytes;
    BOOL ok = DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, &data,
                             data.length + 8, NULL, 0, &bytes, NULL);
    DWORD error = GetLastError();
    CloseHandle(h);
    if (!ok) { SetLastError(error); return failure("junction-set"); }
    puts("{\"junction\":true}");
    return 0;
}

int wmain(int argc, wchar_t **argv) {
    /* Windows accepts forward slashes in most APIs, but junction targets
     * are native paths and require backslashes. Arguments are owned copies. */
    for (int i = 2; i < argc; ++i)
        for (wchar_t *p = argv[i]; *p; ++p) if (*p == L'/') *p = L'\\';
    if (argc == 4 && wcscmp(argv[1], L"junction") == 0)
        return junction(argv[2], argv[3]);
    if (argc == 5 && wcscmp(argv[1], L"hold") == 0)
        return hold(argv[2], argv[3], argv[4]);
    fputs("usage: scan_fixture junction LINK TARGET | hold PATH READY RELEASE\n", stderr);
    return 2;
}
