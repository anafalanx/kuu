/* Independent owned Windows fixtures for recursive removal.
 * setup ROOT | inspect ROOT REL | acl ROOT | hold ROOT REL MILLISECONDS
 * ACLs and sharing holds restore/release on .release or within 60 seconds.
 * No command removes a tree or changes paths outside the newly owned root. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>

#define CAP 32768
#define SHARE (FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE)
static wchar_t root[CAP];
static const char payload[] = "owned removal fixture\r\n";

static int fail(const char *operation) {
    printf("{\"operation\":\"%s\",\"win32\":%lu}\n", operation, GetLastError());
    return 1;
}
static int child(wchar_t *out, const wchar_t *relative) {
    if (!relative[0] || relative[0] == L'/' || relative[0] == L'\\' ||
        wcschr(relative, L':') || wcsstr(relative, L"..") || wcslen(relative) > 16000) {
        SetLastError(ERROR_INVALID_NAME); return 0;
    }
    _snwprintf(out, CAP, L"%ls\\%ls", root, relative); out[CAP - 1] = 0;
    for (wchar_t *p = out; *p; p++) if (*p == L'/') *p = L'\\';
    return 1;
}
static HANDLE metadata(const wchar_t *path, DWORD access) {
    return CreateFileW(path, access, SHARE, NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
}
static int directory(const wchar_t *relative) {
    wchar_t path[CAP]; return child(path, relative) && CreateDirectoryW(path, NULL);
}
static int create_file(const wchar_t *relative) {
    wchar_t path[CAP]; if (!child(path, relative)) return 0;
    HANDLE h = CreateFileW(path, GENERIC_WRITE, SHARE, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD written = 0;
    BOOL ok = WriteFile(h, payload, sizeof(payload) - 1, &written, NULL);
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h); SetLastError(error);
    return ok && written == sizeof(payload) - 1;
}
static int add_attributes(const wchar_t *relative, DWORD attributes) {
    wchar_t path[CAP]; if (!child(path, relative)) return 0;
    HANDLE h = metadata(path, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    if (h == INVALID_HANDLE_VALUE) return 0;
    FILE_BASIC_INFO before, after = {0};
    BOOL ok = GetFileInformationByHandleEx(h, FileBasicInfo, &before, sizeof before);
    if (ok) {
        after.FileAttributes = (before.FileAttributes | attributes) & ~(DWORD)FILE_ATTRIBUTE_NORMAL;
        ok = SetFileInformationByHandle(h, FileBasicInfo, &after, sizeof after);
    }
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h); SetLastError(error); return ok;
}
static int junction(const wchar_t *name, const wchar_t *target_name) {
    wchar_t link[CAP], target[CAP];
    if (!child(link, name) || !child(target, target_name)) return 0;
    struct { DWORD tag; WORD length, reserved, sub_offset, sub_length, print_offset, print_length; wchar_t paths[CAP]; } data;
    memset(&data, 0, sizeof data); data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    wcscpy(data.paths, L"\\??\\"); wcscat(data.paths, target + 4);
    size_t sub = wcslen(data.paths), shown = wcslen(target + 4);
    data.sub_length = (WORD)(sub * 2); data.print_offset = (WORD)((sub + 1) * 2);
    data.print_length = (WORD)(shown * 2);
    wcscpy(data.paths + sub + 1, target + 4); data.length = (WORD)(8 + (sub + shown + 2) * 2);
    if (!CreateDirectoryW(link, NULL)) return 0;
    HANDLE h = metadata(link, GENERIC_WRITE);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD bytes;
    BOOL ok = DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, &data, data.length + 8, NULL, 0, &bytes, NULL);
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h); SetLastError(error); return ok;
}
static int setup(void) {
    if (!CreateDirectoryW(root, NULL)) return fail("new root");
    if (!create_file(L".removal-fixture") || !directory(L"tree") ||
        !directory(L"tree/nested") || !directory(L"tree/nested/deep") ||
        !create_file(L"tree/nested/deep/leaf.bin") || !create_file(L"tree/root.bin") ||
        !directory(L"outside") || !create_file(L"outside/sentinel.bin") ||
        !junction(L"tree/outside-link", L"outside") ||
        !junction(L"tree/dangling-link", L"missing-directory") ||
        !junction(L"root-link", L"outside") ||
        !junction(L"dangling-root", L"missing-directory") ||
        !directory(L"empty") || !directory(L"attr-denied") ||
        !directory(L"attr-denied/child") || !create_file(L"attr-denied/child/removed-first.bin") ||
        !directory(L"delete-denied") || !create_file(L"delete-denied/blocked.bin") ||
        !directory(L"hold") || !create_file(L"hold/locked.bin")) return fail("setup");
    const wchar_t *readonly[] = {L"tree", L"tree/nested", L"tree/nested/deep",
        L"tree/nested/deep/leaf.bin", L"tree/root.bin", L"tree/outside-link", L"tree/dangling-link",
        L"root-link", L"dangling-root", L"empty", L"attr-denied/child", L"hold/locked.bin"};
    for (size_t i = 0; i < sizeof readonly / sizeof readonly[0]; i++)
        if (!add_attributes(readonly[i], FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_HIDDEN)) return fail("readonly fixture");
    if (!add_attributes(L"outside", FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_SYSTEM) ||
        !add_attributes(L"outside/sentinel.bin", FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_HIDDEN)) return fail("outside attributes");
    puts("{\"ready\":true}"); return 0;
}
static int owned(void) {
    wchar_t marker[CAP]; if (!child(marker, L".removal-fixture")) return 0;
    HANDLE h = CreateFileW(marker, GENERIC_READ, SHARE, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    char bytes[sizeof payload] = {0}; DWORD got = 0;
    BOOL ok = ReadFile(h, bytes, sizeof bytes, &got, NULL); CloseHandle(h);
    return ok && got == sizeof payload - 1 && memcmp(bytes, payload, got) == 0;
}
static int inspect(const wchar_t *relative) {
    wchar_t path[CAP]; if (!child(path, relative)) return fail("relative");
    HANDLE h = metadata(path, FILE_READ_ATTRIBUTES);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
            puts("{\"exists\":false}"); return 0;
        }
        SetLastError(error); return fail("inspect handle");
    }
    FILE_BASIC_INFO info;
    BOOL ok = GetFileInformationByHandleEx(h, FileBasicInfo, &info, sizeof info);
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h);
    if (!ok) { SetLastError(error); return fail("inspect metadata"); }
    printf("{\"exists\":true,\"attrs\":%lu,\"creation\":\"%016llx\",\"write\":\"%016llx\",\"change\":\"%016llx\"}\n",
        info.FileAttributes, (unsigned long long)info.CreationTime.QuadPart,
        (unsigned long long)info.LastWriteTime.QuadPart, (unsigned long long)info.ChangeTime.QuadPart);
    return 0;
}
static void wait_release(ULONGLONG milliseconds) {
    wchar_t release[CAP]; child(release, L".release"); ULONGLONG start = GetTickCount64();
    while (GetFileAttributesW(release) == INVALID_FILE_ATTRIBUTES && GetTickCount64() - start < milliseconds) Sleep(10);
}
typedef struct { wchar_t path[CAP]; PSECURITY_DESCRIPTOR saved; PACL dacl; SECURITY_DESCRIPTOR_CONTROL control; int changed; } acl_saved;
static int restrict_acl(acl_saved *saved, const wchar_t *relative, const wchar_t *sddl) {
    if (!child(saved->path, relative)) return 0;
    DWORD error = GetNamedSecurityInfoW(saved->path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &saved->dacl, NULL, &saved->saved);
    if (error) { SetLastError(error); return 0; }
    DWORD revision;
    if (!GetSecurityDescriptorControl(saved->saved, &saved->control, &revision)) return 0;
    PSECURITY_DESCRIPTOR restricted = NULL; PACL dacl; BOOL present, defaulted;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, &restricted, NULL)) return 0;
    BOOL ok = GetSecurityDescriptorDacl(restricted, &present, &dacl, &defaulted);
    error = ok ? SetNamedSecurityInfoW(saved->path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
        NULL, NULL, dacl, NULL) : GetLastError();
    LocalFree(restricted); saved->changed = error == 0; SetLastError(error); return error == 0;
}
static int acl(void) {
    acl_saved *saved = calloc(3, sizeof *saved);
    if (!saved) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return fail("ACL memory"); }
    BOOL ok = restrict_acl(&saved[0], L"attr-denied/child", L"D:P(D;;0x100;;;WD)(A;;FA;;;WD)") &&
        restrict_acl(&saved[1], L"delete-denied", L"D:P(D;;0x40;;;WD)(A;;FA;;;WD)") &&
        restrict_acl(&saved[2], L"delete-denied/blocked.bin", L"D:P(D;;0x10000;;;WD)(A;;FA;;;WD)");
    DWORD error = ok ? 0 : GetLastError();
    printf("{\"ready\":%s,\"win32\":%lu}\n", ok ? "true" : "false", error); fflush(stdout);
    if (ok) wait_release(60000);
    BOOL restored = TRUE;
    for (int i = 2; i >= 0; i--) {
        if (saved[i].changed) {
            DWORD protection = saved[i].control & SE_DACL_PROTECTED ? PROTECTED_DACL_SECURITY_INFORMATION : UNPROTECTED_DACL_SECURITY_INFORMATION;
            DWORD restore_error = SetNamedSecurityInfoW(saved[i].path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | protection,
                NULL, NULL, saved[i].dacl, NULL);
            if (restore_error) { restored = FALSE; error = restore_error; }
        }
        if (saved[i].saved) LocalFree(saved[i].saved);
    }
    free(saved); printf("{\"restored\":%s,\"win32\":%lu}\n", restored ? "true" : "false", error);
    return ok && restored ? 0 : 1;
}
static int hold(const wchar_t *relative, const wchar_t *duration) {
    wchar_t path[CAP], *end;
    unsigned long milliseconds = wcstoul(duration, &end, 10);
    if (*end || milliseconds < 10 || milliseconds > 60000 || !child(path, relative)) return 2;
    HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return fail("hold delete sharing");
    puts("{\"ready\":true}"); fflush(stdout); wait_release(milliseconds); CloseHandle(h);
    puts("{\"released\":true}"); return 0;
}
int wmain(int argc, wchar_t **argv) {
    if (argc < 3 || wcslen(argv[2]) < 3 || wcslen(argv[2]) > 1000 || argv[2][1] != L':' ||
        (argv[2][2] != L'/' && argv[2][2] != L'\\')) return 2;
    _snwprintf(root, CAP, L"\\\\?\\%ls", argv[2]);
    for (wchar_t *p = root; *p; p++) if (*p == L'/') *p = L'\\';
    if (argc == 3 && !wcscmp(argv[1], L"setup")) return setup();
    if (!owned()) { SetLastError(ERROR_INVALID_DATA); return fail("owned marker"); }
    if (argc == 4 && !wcscmp(argv[1], L"inspect")) return inspect(argv[3]);
    if (argc == 3 && !wcscmp(argv[1], L"acl")) return acl();
    if (argc == 5 && !wcscmp(argv[1], L"hold")) return hold(argv[3], argv[4]);
    return 2;
}
