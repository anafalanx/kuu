/* Independent Windows fixture for fs.attributes/set_attributes integration.
 * Every command is limited to a root created here and marked as owned.
 * setup ROOT | inspect ROOT REL [follow] | set ROOT REL MASK | acl ROOT
 * acl restores original descriptors when ROOT/.release appears or after 60s.
 * It never removes a tree, changes an external parent, or uses kuu APIs.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>

#define SHARE (FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE)
#define CAP 32768
static wchar_t root[CAP];
static const char payload[] = "independent fixture\r\n\0binary\xff";

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
static HANDLE metadata(const wchar_t *path, int follow, DWORD access) {
    return CreateFileW(path, access, SHARE, NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | (follow ? 0 : FILE_FLAG_OPEN_REPARSE_POINT), NULL);
}
static int create_file(const wchar_t *relative) {
    wchar_t path[CAP]; if (!child(path, relative)) return 0;
    HANDLE h = CreateFileW(path, GENERIC_WRITE, SHARE, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD written;
    BOOL ok = WriteFile(h, payload, sizeof(payload) - 1, &written, NULL);
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h); SetLastError(error);
    return ok && written == sizeof(payload) - 1;
}
static int directory(const wchar_t *relative) {
    wchar_t path[CAP]; return child(path, relative) && CreateDirectoryW(path, NULL);
}
static int junction(const wchar_t *name, const wchar_t *target_name) {
    wchar_t link[CAP], target[CAP];
    if (!child(link, name) || !child(target, target_name)) return 0;
    struct { DWORD tag; WORD length, reserved, sub_offset, sub_length, print_offset, print_length; wchar_t paths[CAP]; } data;
    memset(&data, 0, sizeof(data)); data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    wcscpy(data.paths, L"\\??\\"); wcscat(data.paths, target + 4);
    size_t sub = wcslen(data.paths), shown = wcslen(target + 4);
    data.sub_length = (WORD)(sub * 2); data.print_offset = (WORD)((sub + 1) * 2);
    data.print_length = (WORD)(shown * 2);
    wcscpy(data.paths + sub + 1, target + 4); data.length = (WORD)(8 + (sub + shown + 2) * 2);
    if (!CreateDirectoryW(link, NULL)) return 0;
    HANDLE h = metadata(link, 0, GENERIC_WRITE);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD bytes; BOOL ok = DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, &data, data.length + 8, NULL, 0, &bytes, NULL);
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h); SetLastError(error); return ok;
}
static DWORD symlink(const wchar_t *name, const wchar_t *target_name, DWORD flags) {
    wchar_t link[CAP], target[CAP];
    if (!child(link, name) || !child(target, target_name)) return GetLastError();
    if (CreateSymbolicLinkW(link, target, flags | 2)) return 0;
    DWORD error = GetLastError();
    if (error == ERROR_INVALID_PARAMETER) {
        if (CreateSymbolicLinkW(link, target, flags)) return 0;
        error = GetLastError();
    }
    return error;
}
static int setup(void) {
    if (!CreateDirectoryW(root, NULL)) return fail("new root");
    if (!create_file(L".attributes-fixture") || !create_file(L"plain.bin") ||
        !create_file(L"times.bin") || !create_file(L"sparse.bin") || !create_file(L"write-denied.bin") ||
        !create_file(L"link-target.bin") || !create_file(L"unicode-\x03ba\x03bf\x03c5-\x96ea.bin") ||
        !directory(L"directory") || !directory(L"target") || !create_file(L"target/child.bin") ||
        !directory(L"private") || !create_file(L"private/child.bin") ||
        !junction(L"junction", L"target") || !junction(L"dangling-junction", L"missing-directory")) return fail("setup");
    wchar_t path[CAP]; child(path, L"times.bin");
    HANDLE h = metadata(path, 0, FILE_WRITE_ATTRIBUTES);
    FILETIME created = {123456789, 30000000}, accessed = {223456789, 30000000}, written = {323456789, 30000000};
    BOOL ok = h != INVALID_HANDLE_VALUE && SetFileTime(h, &created, &accessed, &written);
    DWORD error = ok ? 0 : GetLastError(); if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    if (!ok) { SetLastError(error); return fail("fixed times"); }
    child(path, L"sparse.bin"); h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, SHARE, NULL, OPEN_EXISTING, 0, NULL);
    DWORD bytes; ok = h != INVALID_HANDLE_VALUE && DeviceIoControl(h, FSCTL_SET_SPARSE, NULL, 0, NULL, 0, &bytes, NULL);
    error = ok ? 0 : GetLastError(); if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    if (!ok) { SetLastError(error); return fail("sparse"); }
    wchar_t relative[4096] = L"";
    for (int i = 0; i < 5; i++) {
        if (i) wcscat(relative, L"/");
        wcscat(relative, L"long-component-abcdefghijklmnopqrstuvwxyz-0123456789");
        if (!directory(relative)) return fail("long directory");
    }
    wcscat(relative, L"/long.bin"); if (!create_file(relative)) return fail("long file");
    DWORD file_link = symlink(L"file-link", L"link-target.bin", 0);
    DWORD dir_link = symlink(L"directory-link", L"target", SYMBOLIC_LINK_FLAG_DIRECTORY);
    DWORD dangling = symlink(L"dangling-link", L"missing.bin", 0);
    printf("{\"ready\":true,\"file_symlink\":%lu,\"directory_symlink\":%lu,\"dangling_symlink\":%lu}\n", file_link, dir_link, dangling);
    return 0;
}
static int owned(void) {
    wchar_t marker[CAP]; if (!child(marker, L".attributes-fixture")) return 0;
    HANDLE h = CreateFileW(marker, GENERIC_READ, SHARE, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    char bytes[sizeof(payload)] = {0}; DWORD got = 0;
    BOOL ok = ReadFile(h, bytes, sizeof(bytes), &got, NULL); CloseHandle(h);
    return ok && got == sizeof(payload) - 1 && memcmp(bytes, payload, got) == 0;
}
static int inspect(const wchar_t *relative, int follow) {
    wchar_t path[CAP]; if (!child(path, relative)) return fail("relative");
    WIN32_FILE_ATTRIBUTE_DATA data;
    if (!GetFileAttributesExW(path, GetFileExInfoStandard, &data)) return fail("inspect path");
    HANDLE h = metadata(path, follow, FILE_READ_ATTRIBUTES);
    if (h == INVALID_HANDLE_VALUE) return fail("inspect handle");
    FILE_BASIC_INFO info; BOOL ok = GetFileInformationByHandleEx(h, FileBasicInfo, &info, sizeof(info));
    DWORD error = ok ? 0 : GetLastError(); CloseHandle(h);
    if (!ok) { SetLastError(error); return fail("inspect basic"); }
    printf("{\"attrs\":%lu,\"selected\":%lu,\"creation\":\"%016llx\",\"access\":\"%016llx\",\"write\":\"%016llx\",\"change\":\"%016llx\"}\n",
        data.dwFileAttributes, info.FileAttributes, (unsigned long long)info.CreationTime.QuadPart,
        (unsigned long long)info.LastAccessTime.QuadPart, (unsigned long long)info.LastWriteTime.QuadPart,
        (unsigned long long)info.ChangeTime.QuadPart);
    return 0;
}
static int set(const wchar_t *relative, const wchar_t *text) {
    wchar_t path[CAP], *end; unsigned long mask = wcstoul(text, &end, 10);
    if (*end || !child(path, relative)) return 2;
    if (!SetFileAttributesW(path, mask)) return fail("set attributes independently");
    puts("{\"set\":true}"); return 0;
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
    acl_saved *saved = calloc(4, sizeof(*saved));
    if (!saved) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return fail("ACL memory"); }
    BOOL ok = restrict_acl(&saved[0], L"write-denied.bin", L"D:P(D;;0x101;;;WD)(A;;FA;;;WD)") &&
        restrict_acl(&saved[1], L"private", L"D:P(D;;0x1;;;WD)(A;;FA;;;WD)") &&
        restrict_acl(&saved[2], L"private/child.bin", L"D:P(D;;0x180;;;WD)(A;;FA;;;WD)") &&
        restrict_acl(&saved[3], L"target", L"D:P(D;;0x100;;;WD)(A;;FA;;;WD)");
    DWORD error = ok ? 0 : GetLastError();
    printf("{\"ready\":%s,\"win32\":%lu}\n", ok ? "true" : "false", error); fflush(stdout);
    if (ok) {
        wchar_t release[CAP]; child(release, L".release"); ULONGLONG start = GetTickCount64();
        while (GetFileAttributesW(release) == INVALID_FILE_ATTRIBUTES && GetTickCount64() - start < 60000) Sleep(10);
    }
    BOOL restored = TRUE;
    for (int i = 3; i >= 0; i--) {
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
int wmain(int argc, wchar_t **argv) {
    if (argc < 3 || wcslen(argv[2]) < 3 || wcslen(argv[2]) > 1000 || argv[2][1] != L':' ||
        (argv[2][2] != L'/' && argv[2][2] != L'\\')) return 2;
    _snwprintf(root, CAP, L"\\\\?\\%ls", argv[2]);
    for (wchar_t *p = root; *p; p++) if (*p == L'/') *p = L'\\';
    if (argc == 3 && !wcscmp(argv[1], L"setup")) return setup();
    if (!owned()) { SetLastError(ERROR_INVALID_DATA); return fail("owned marker"); }
    if ((argc == 4 || argc == 5) && !wcscmp(argv[1], L"inspect")) return inspect(argv[3], argc == 5 && !wcscmp(argv[4], L"follow"));
    if (argc == 5 && !wcscmp(argv[1], L"set")) return set(argv[3], argv[4]);
    if (argc == 3 && !wcscmp(argv[1], L"acl")) return acl();
    return 2;
}
