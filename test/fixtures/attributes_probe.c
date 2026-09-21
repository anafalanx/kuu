/* Independent Windows contract probes for Step 08; no kuu implementation used.
 * gcc -std=c11 -Wall -Wextra -Werror -O2 -municode attributes_probe.c
 *     -ladvapi32 -o attributes_probe.exe
 * Invoke with a new, absolute directory under an owned test workspace.
 * Retains only fixtures it creates; never recursively deletes or changes a parent.
 * Emits NDJSON observations. Privilege-dependent symlinks are explicit skips.
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
#define MUTABLE (FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM | \
                 FILE_ATTRIBUTE_ARCHIVE | FILE_ATTRIBUTE_TEMPORARY | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED)
static unsigned passed, failed, skipped;

static void result(const char *name, int ok, DWORD error, unsigned long long actual,
                   unsigned long long expected) {
    printf("{\"test\":\"%s\",\"ok\":%s,\"win32\":%lu,\"actual\":%llu,\"expected\":%llu}\n",
           name, ok ? "true" : "false", error, actual, expected);
    if (ok) passed++; else failed++;
}
static void skip(const char *name, DWORD error) {
    printf("{\"test\":\"%s\",\"skip\":true,\"win32\":%lu}\n", name, error);
    skipped++;
}
static HANDLE metadata(const wchar_t *path, int follow, DWORD access) {
    return CreateFileW(path, access, SHARE, NULL, OPEN_EXISTING,
                       FILE_FLAG_BACKUP_SEMANTICS | (follow ? 0 : FILE_FLAG_OPEN_REPARSE_POINT), NULL);
}
static int basic(const wchar_t *path, int follow, FILE_BASIC_INFO *out) {
    HANDLE h = metadata(path, follow, FILE_READ_ATTRIBUTES);
    if (h == INVALID_HANDLE_VALUE) return 0;
    BOOL ok = GetFileInformationByHandleEx(h, FileBasicInfo, out, sizeof(*out));
    DWORD error = ok ? 0 : GetLastError();
    CloseHandle(h); SetLastError(error); return ok;
}
/* Deliberately exposes native masks, including zero/NORMAL, to probe the OS. */
static int set_mask(const wchar_t *path, int follow, DWORD mask) {
    HANDLE h = metadata(path, follow, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    if (h == INVALID_HANDLE_VALUE) return 0;
    FILE_BASIC_INFO info = {0}; info.FileAttributes = mask;
    BOOL ok = SetFileInformationByHandle(h, FileBasicInfo, &info, sizeof(info));
    DWORD error = ok ? 0 : GetLastError();
    CloseHandle(h); SetLastError(error); return ok;
}
static void join(wchar_t *out, const wchar_t *root, const wchar_t *name) {
    _snwprintf(out, 32768, L"%ls\\%ls", root, name); out[32767] = 0;
}
static int create_file(const wchar_t *path) {
    HANDLE h = CreateFileW(path, GENERIC_WRITE, SHARE, NULL, CREATE_NEW,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    const char bytes[] = "owned attribute fixture\r\n";
    DWORD written = 0;
    BOOL ok = WriteFile(h, bytes, sizeof(bytes) - 1, &written, NULL);
    DWORD error = ok ? 0 : GetLastError();
    CloseHandle(h); SetLastError(error); return ok && written == sizeof(bytes) - 1;
}
static int contents_intact(const wchar_t *path) {
    HANDLE h = CreateFileW(path, GENERIC_READ, SHARE, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    char bytes[64] = {0}; DWORD length = 0;
    BOOL ok = ReadFile(h, bytes, sizeof(bytes), &length, NULL);
    CloseHandle(h);
    return ok && length == 25 && memcmp(bytes, "owned attribute fixture\r\n", 25) == 0;
}
static int check_mask(const char *name, const wchar_t *path, DWORD mask) {
    /* Independent path-based observation, not the setter's handle readback. */
    WIN32_FILE_ATTRIBUTE_DATA info;
    BOOL ok = GetFileAttributesExW(path, GetFileExInfoStandard, &info);
    DWORD error = ok ? 0 : GetLastError();
    result(name, ok && info.dwFileAttributes == mask, error, ok ? info.dwFileAttributes : 0, mask);
    return ok && info.dwFileAttributes == mask;
}
static int junction(const wchar_t *link, const wchar_t *target) {
    struct {
        DWORD tag; WORD length, reserved;
        WORD substitute_offset, substitute_length, print_offset, print_length;
        wchar_t paths[32768];
    } data;
    size_t n = wcslen(target);
    if (n > 8000 || wcsncmp(target, L"\\\\?\\", 4) != 0) return 0;
    memset(&data, 0, sizeof(data));
    data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    wcscpy(data.paths, L"\\??\\"); wcscat(data.paths, target + 4);
    size_t sub = wcslen(data.paths), display = wcslen(target + 4);
    data.substitute_length = (WORD)(sub * sizeof(wchar_t));
    data.print_offset = (WORD)((sub + 1) * sizeof(wchar_t));
    data.print_length = (WORD)(display * sizeof(wchar_t));
    wcscpy(data.paths + sub + 1, target + 4);
    data.length = (WORD)(8 + (sub + display + 2) * sizeof(wchar_t));
    if (!CreateDirectoryW(link, NULL)) return 0;
    HANDLE h = CreateFileW(link, GENERIC_WRITE, SHARE, NULL, OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD bytes;
    BOOL ok = DeviceIoControl(h, FSCTL_SET_REPARSE_POINT, &data, data.length + 8, NULL, 0, &bytes, NULL);
    DWORD error = ok ? 0 : GetLastError();
    CloseHandle(h); SetLastError(error); return ok;
}
static void link_cases(const wchar_t *link, const wchar_t *target, DWORD base, const char *label) {
    FILE_BASIC_INFO before = {0}, after = {0}, target_before = {0}, target_after = {0};
    char name[128];
    if (!basic(link, 0, &before) || !basic(target, 1, &target_before)) {
        result("link setup metadata", 0, GetLastError(), 0, 1); return;
    }
    BOOL ok = set_mask(link, 0, before.FileAttributes | FILE_ATTRIBUTE_READONLY);
    DWORD error = ok ? 0 : GetLastError();
    BOOL got = basic(link, 0, &after) && basic(target, 1, &target_after);
    snprintf(name, sizeof(name), "%s nofollow changes link only", label);
    result(name, ok && got && (after.FileAttributes & FILE_ATTRIBUTE_READONLY) &&
           (after.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
           target_before.FileAttributes == target_after.FileAttributes,
           error, got ? after.FileAttributes : 0, before.FileAttributes | FILE_ATTRIBUTE_READONLY);
    ok = set_mask(link, 1, base | FILE_ATTRIBUTE_HIDDEN);
    error = ok ? 0 : GetLastError();
    got = basic(link, 0, &after) && basic(target, 1, &target_after);
    snprintf(name, sizeof(name), "%s follow changes target only", label);
    result(name, ok && got && target_after.FileAttributes == (base | FILE_ATTRIBUTE_HIDDEN) &&
           after.FileAttributes == (before.FileAttributes | FILE_ATTRIBUTE_READONLY),
           error, got ? target_after.FileAttributes : 0, base | FILE_ATTRIBUTE_HIDDEN);
    if (base & FILE_ATTRIBUTE_DIRECTORY) {
        DWORD previous_link = after.FileAttributes, previous_target = target_after.FileAttributes;
        ok = set_mask(link, 0, previous_link | FILE_ATTRIBUTE_TEMPORARY);
        error = ok ? 0 : GetLastError();
        got = basic(link, 0, &after) && basic(target, 1, &target_after);
        snprintf(name, sizeof(name), "%s nofollow TEMPORARY rejects without mutation", label);
        result(name, !ok && error == ERROR_INVALID_PARAMETER && got && after.FileAttributes == previous_link &&
               target_after.FileAttributes == previous_target, error, error, ERROR_INVALID_PARAMETER);
    }
    set_mask(link, 0, before.FileAttributes);
    set_mask(target, 1, target_before.FileAttributes);
}
static void symlink_case(const wchar_t *root, const wchar_t *name, const wchar_t *target,
                         DWORD directory, int dangling, const char *label) {
    wchar_t link[32768]; join(link, root, name);
    BOOL ok = CreateSymbolicLinkW(link, target, directory | 2 /* allow unprivileged */);
    DWORD error = ok ? 0 : GetLastError();
    if (!ok && error == ERROR_INVALID_PARAMETER) {
        ok = CreateSymbolicLinkW(link, target, directory); error = ok ? 0 : GetLastError();
    }
    if (!ok && error == ERROR_PRIVILEGE_NOT_HELD) { skip(label, error); return; }
    result(label, ok, error, ok, 1);
    if (!ok) return;
    if (!dangling) { link_cases(link, target, directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_ARCHIVE, label); return; }
    FILE_BASIC_INFO info;
    ok = basic(link, 0, &info);
    result("dangling symlink nofollow readable", ok && (info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT),
           ok ? 0 : GetLastError(), ok ? info.FileAttributes : 0, FILE_ATTRIBUTE_REPARSE_POINT);
    if (ok) {
        ok = set_mask(link, 0, info.FileAttributes | FILE_ATTRIBUTE_HIDDEN);
        result("dangling symlink nofollow writable", ok, ok ? 0 : GetLastError(), ok, 1);
    }
    ok = basic(link, 1, &info); error = ok ? 0 : GetLastError();
    result("dangling symlink follow fails missing", !ok && (error == 2 || error == 3), error, error, 2);
}
static void acl_case(const wchar_t *path, const wchar_t *sddl, const char *label,
                     int expect_read, int expect_write, const wchar_t *alias) {
    PSECURITY_DESCRIPTOR original = NULL, restricted = NULL;
    PACL original_dacl = NULL, dacl = NULL; BOOL present, defaulted;
    DWORD error = GetNamedSecurityInfoW((wchar_t *)path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
                                        NULL, NULL, &original_dacl, NULL, &original);
    if (error || !ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, &restricted, NULL) ||
        !GetSecurityDescriptorDacl(restricted, &present, &dacl, &defaulted)) {
        result("ACL fixture setup", 0, error ? error : GetLastError(), 0, 1);
        if (original) LocalFree(original);
        if (restricted) LocalFree(restricted);
        return;
    }
    error = SetNamedSecurityInfoW((wchar_t *)path, SE_FILE_OBJECT,
                                  DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                                  NULL, NULL, dacl, NULL);
    if (!error) {
        HANDLE h = metadata(path, 0, FILE_READ_ATTRIBUTES);
        DWORD read_error = h == INVALID_HANDLE_VALUE ? GetLastError() : 0;
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
        h = metadata(path, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
        DWORD write_error = h == INVALID_HANDLE_VALUE ? GetLastError() : 0;
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
        result(label, read_error == (expect_read ? 0 : ERROR_ACCESS_DENIED) &&
               write_error == (expect_write ? 0 : ERROR_ACCESS_DENIED), write_error,
               ((unsigned long long)read_error << 32) | write_error,
               ((unsigned long long)(expect_read ? 0 : ERROR_ACCESS_DENIED) << 32) | (expect_write ? 0 : ERROR_ACCESS_DENIED));
        if (alias) {
            h = metadata(alias, 1, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
            DWORD follow_error = h == INVALID_HANDLE_VALUE ? GetLastError() : 0;
            if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
            h = metadata(alias, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
            DWORD nofollow_error = h == INVALID_HANDLE_VALUE ? GetLastError() : 0;
            if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
            result("followed junction write denied while link is accessible", follow_error == ERROR_ACCESS_DENIED && nofollow_error == 0,
                   follow_error, ((unsigned long long)nofollow_error << 32) | follow_error, ERROR_ACCESS_DENIED);
        }
    } else result("ACL fixture apply", 0, error, 0, 1);
    error = SetNamedSecurityInfoW((wchar_t *)path, SE_FILE_OBJECT,
                                  DACL_SECURITY_INFORMATION | UNPROTECTED_DACL_SECURITY_INFORMATION,
                                  NULL, NULL, original_dacl, NULL);
    result("restore owned fixture ACL", error == 0, error, error, 0);
    LocalFree(restricted); LocalFree(original);
}
int wmain(int argc, wchar_t **argv) {
    size_t root_length = argc == 2 ? wcslen(argv[1]) : 0;
    if (argc != 2 || root_length < 3 || root_length > 1000 || argv[1][1] != L':' ||
        (argv[1][2] != L'\\' && argv[1][2] != L'/')) return 2;
    wchar_t root[32768], file[32768], dir[32768], link[32768], missing[32768], nested[32768];
    _snwprintf(root, 32768, L"\\\\?\\%ls", argv[1]);
    for (wchar_t *p = root; *p; p++) if (*p == L'/') *p = L'\\';
    if (!CreateDirectoryW(root, NULL)) { result("create new owned root", 0, GetLastError(), 0, 1); return 1; }
    join(file, root, L"plain.bin"); join(dir, root, L"directory"); join(missing, root, L"missing.bin");
    if (!create_file(file) || !CreateDirectoryW(dir, NULL)) { result("fixture setup", 0, GetLastError(), 0, 1); return 1; }
    const DWORD flags[] = {FILE_ATTRIBUTE_READONLY, FILE_ATTRIBUTE_HIDDEN, FILE_ATTRIBUTE_SYSTEM,
                          FILE_ATTRIBUTE_ARCHIVE, FILE_ATTRIBUTE_TEMPORARY, FILE_ATTRIBUTE_NOT_CONTENT_INDEXED};
    const char *names[] = {"readonly", "hidden", "system", "archive", "temporary", "not_content_indexed"};
    for (unsigned i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) {
        char name[128];
        BOOL ok = set_mask(file, 0, flags[i]);
        snprintf(name, sizeof(name), "file set %s", names[i]); result(name, ok, ok ? 0 : GetLastError(), ok, 1);
        snprintf(name, sizeof(name), "file inspect %s independently", names[i]); check_mask(name, file, flags[i]);
        ok = set_mask(dir, 0, FILE_ATTRIBUTE_DIRECTORY | flags[i]); DWORD error = ok ? 0 : GetLastError();
        snprintf(name, sizeof(name), "directory set %s", names[i]);
        result(name, i == 4 ? (!ok && error == ERROR_INVALID_PARAMETER) : ok, error, error, i == 4 ? 87 : 0);
        if (i != 4) { snprintf(name, sizeof(name), "directory inspect %s independently", names[i]); check_mask(name, dir, FILE_ATTRIBUTE_DIRECTORY | flags[i]); }
    }
    set_mask(file, 0, FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_ARCHIVE);
    BOOL ok = set_mask(file, 0, 0);
    result("zero attribute mask accepted", ok, ok ? 0 : GetLastError(), ok, 1);
    check_mask("zero means unchanged, not clear", file, FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_ARCHIVE);
    ok = set_mask(file, 0, FILE_ATTRIBUTE_NORMAL);
    result("NORMAL clears all mutable file flags", ok, ok ? 0 : GetLastError(), ok, 1);
    check_mask("cleared ordinary file reads NORMAL", file, FILE_ATTRIBUTE_NORMAL);
    set_mask(dir, 0, FILE_ATTRIBUTE_DIRECTORY);
    check_mask("cleared directory preserves DIRECTORY", dir, FILE_ATTRIBUTE_DIRECTORY);

    HANDLE h = metadata(file, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    FILETIME created = {123456789, 30000000}, accessed = {223456789, 30000000}, written = {323456789, 30000000};
    ok = h != INVALID_HANDLE_VALUE && SetFileTime(h, &created, &accessed, &written);
    result("fixed timestamp setup", ok, ok ? 0 : GetLastError(), ok, 1);
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    FILE_BASIC_INFO before = {0}, after = {0};
    ok = basic(file, 0, &before); Sleep(20);
    ok = ok && set_mask(file, 0, FILE_ATTRIBUTE_HIDDEN) && basic(file, 0, &after);
    result("zero time fields preserve creation access write times", ok &&
           before.CreationTime.QuadPart == after.CreationTime.QuadPart &&
           before.LastAccessTime.QuadPart == after.LastAccessTime.QuadPart &&
           before.LastWriteTime.QuadPart == after.LastWriteTime.QuadPart, ok ? 0 : GetLastError(),
           (unsigned long long)after.LastWriteTime.QuadPart, (unsigned long long)before.LastWriteTime.QuadPart);
    printf("{\"observation\":\"native metadata ChangeTime\",\"before\":%lld,\"after\":%lld}\n", before.ChangeTime.QuadPart, after.ChangeTime.QuadPart);
    h = metadata(file, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    FILE_BASIC_INFO pending = {0}; pending.FileAttributes = FILE_ATTRIBUTE_ARCHIVE;
    HANDLE second = metadata(file, 0, FILE_WRITE_ATTRIBUTES);
    written.dwLowDateTime += 10000000;
    ok = h != INVALID_HANDLE_VALUE && second != INVALID_HANDLE_VALUE && SetFileTime(second, NULL, NULL, &written);
    if (second != INVALID_HANDLE_VALUE) CloseHandle(second);
    ok = ok && SetFileInformationByHandle(h, FileBasicInfo, &pending, sizeof(pending));
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    ok = ok && basic(file, 0, &after);
    ULARGE_INTEGER expected; expected.LowPart = written.dwLowDateTime; expected.HighPart = written.dwHighDateTime;
    result("attribute write does not restore stale write time", ok && (unsigned long long)after.LastWriteTime.QuadPart == expected.QuadPart,
           ok ? 0 : GetLastError(), (unsigned long long)after.LastWriteTime.QuadPart, expected.QuadPart);
    result("attribute updates preserve file bytes", contents_intact(file), 0, 0, 0);

    h = CreateFileW(file, GENERIC_READ | GENERIC_WRITE, SHARE, NULL, OPEN_EXISTING, 0, NULL);
    DWORD returned = 0;
    ok = h != INVALID_HANDLE_VALUE && DeviceIoControl(h, FSCTL_SET_SPARSE, NULL, 0, NULL, 0, &returned, NULL);
    DWORD error = ok ? 0 : GetLastError();
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    result("independent sparse-file setup", ok, error, ok, 1);
    ok = ok && basic(file, 0, &before) && set_mask(file, 0, before.FileAttributes | FILE_ATTRIBUTE_HIDDEN);
    error = ok ? 0 : GetLastError();
    DWORD attrs = GetFileAttributesW(file);
    if (attrs == INVALID_FILE_ATTRIBUTES) error = GetLastError();
    result("preserve unrelated sparse flag", ok && attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_SPARSE_FILE) &&
           (attrs & FILE_ATTRIBUTE_HIDDEN), error, attrs, before.FileAttributes | FILE_ATTRIBUTE_HIDDEN);
    ok = set_mask(file, 0, attrs & ~MUTABLE);
    attrs = GetFileAttributesW(file);
    result("clear mutable flags preserves sparse flag", ok && attrs == FILE_ATTRIBUTE_SPARSE_FILE,
           ok ? 0 : GetLastError(), attrs, FILE_ATTRIBUTE_SPARSE_FILE);

    join(link, root, L"junction");
    ok = junction(link, dir); result("create junction", ok, ok ? 0 : GetLastError(), ok, 1);
    if (ok) {
        link_cases(link, dir, FILE_ATTRIBUTE_DIRECTORY, "junction");
        acl_case(dir, L"D:P(D;;0x100;;;WD)(A;;FA;;;WD)", "directory target write-attributes denied", 1, 0, link);
        join(nested, dir, L"ancestor.bin"); create_file(nested);
        wchar_t via[32768]; join(via, link, L"ancestor.bin");
        ok = set_mask(via, 0, FILE_ATTRIBUTE_HIDDEN);
        error = ok ? 0 : GetLastError(); attrs = GetFileAttributesW(nested);
        if (attrs == INVALID_FILE_ATTRIBUTES) error = GetLastError();
        result("nofollow final component still traverses linked ancestor", ok && attrs == FILE_ATTRIBUTE_HIDDEN,
               error, attrs, FILE_ATTRIBUTE_HIDDEN);
    }
    join(nested, root, L"symlink-target.bin"); create_file(nested);
    symlink_case(root, L"file-link", nested, 0, 0, "file symlink");
    symlink_case(root, L"directory-link", dir, SYMBOLIC_LINK_FLAG_DIRECTORY, 0, "directory symlink");
    symlink_case(root, L"dangling-link", missing, 0, 1, "dangling file symlink");
    join(link, root, L"dangling-junction"); join(nested, root, L"removed-target");
    ok = CreateDirectoryW(nested, NULL) && junction(link, nested) && RemoveDirectoryW(nested);
    result("create dangling junction", ok, ok ? 0 : GetLastError(), ok, 1);
    ok = ok && basic(link, 0, &before) && set_mask(link, 0, before.FileAttributes | FILE_ATTRIBUTE_HIDDEN);
    result("dangling junction nofollow read and write succeeds", ok, ok ? 0 : GetLastError(), ok, 1);
    ok = basic(link, 1, &before); error = ok ? 0 : GetLastError();
    result("dangling junction follow fails missing", !ok && (error == 2 || error == 3), error, error, 2);

    join(nested, root, L"acl-denied.bin"); create_file(nested);
    acl_case(nested, L"D:P(D;;0x100;;;WD)(A;;FA;;;WD)", "write denied but read and empty-patch rights available", 1, 0, NULL);
    acl_case(nested, L"D:P(D;;0x180;;;WD)(A;;FA;;;WD)", "parent listing grants otherwise denied child attribute reads", 1, 0, NULL);
    wchar_t private_dir[32768], private_file[32768];
    join(private_dir, root, L"acl-private-parent"); join(private_file, private_dir, L"child.bin");
    ok = CreateDirectoryW(private_dir, NULL) && create_file(private_file);
    PSECURITY_DESCRIPTOR original = NULL, restricted = NULL;
    PACL original_dacl = NULL, dacl = NULL; BOOL present = FALSE, defaulted = FALSE;
    error = ok ? GetNamedSecurityInfoW(private_dir, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
                                      NULL, NULL, &original_dacl, NULL, &original) : GetLastError();
    if (!error && ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(D;;0x1;;;WD)(A;;FA;;;WD)",
            SDDL_REVISION_1, &restricted, NULL) && GetSecurityDescriptorDacl(restricted, &present, &dacl, &defaulted)) {
        error = SetNamedSecurityInfoW(private_dir, SE_FILE_OBJECT,
                                     DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, NULL, NULL, dacl, NULL);
        result("deny listing on owned private parent", error == 0, error, error, 0);
        if (!error) acl_case(private_file, L"D:P(D;;0x180;;;WD)(A;;FA;;;WD)", "read denied with parent listing denied", 0, 0, NULL);
        error = SetNamedSecurityInfoW(private_dir, SE_FILE_OBJECT,
                                     DACL_SECURITY_INFORMATION | UNPROTECTED_DACL_SECURITY_INFORMATION, NULL, NULL, original_dacl, NULL);
        result("restore owned parent ACL", error == 0, error, error, 0);
    } else result("private ACL fixture setup", 0, error ? error : GetLastError(), 0, 1);
    if (original) LocalFree(original);
    if (restricted) LocalFree(restricted);
    h = metadata(missing, 0, FILE_READ_ATTRIBUTES); error = h == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    result("missing object native error", error == 2 || error == 3, error, error, 2);

    h = CreateFileW(nested, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    HANDLE probe = metadata(nested, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    error = probe == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    result("exclusive data handle still permits attribute-only access", h != INVALID_HANDLE_VALUE && probe != INVALID_HANDLE_VALUE, error, error, 0);
    if (probe != INVALID_HANDLE_VALUE) CloseHandle(probe);
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);

    join(nested, root, L"readonly-directory"); CreateDirectoryW(nested, NULL);
    ok = set_mask(nested, 0, FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_READONLY);
    BOOL removed = RemoveDirectoryW(nested); error = removed ? 0 : GetLastError();
    result("readonly directory blocks native removal", ok && !removed && error == ERROR_ACCESS_DENIED, error, error, 5);
    ok = set_mask(nested, 0, FILE_ATTRIBUTE_DIRECTORY) && RemoveDirectoryW(nested);
    result("clear readonly permits native directory removal", ok, ok ? 0 : GetLastError(), ok, 1);

    wchar_t renamed[32768]; join(nested, root, L"identity.bin"); join(renamed, root, L"renamed.bin");
    ok = create_file(nested);
    h = metadata(nested, 0, FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES);
    ok = ok && h != INVALID_HANDLE_VALUE && MoveFileExW(nested, renamed, 0) && create_file(nested);
    FILE_BASIC_INFO identity_patch = {0}; identity_patch.FileAttributes = FILE_ATTRIBUTE_HIDDEN;
    ok = ok && SetFileInformationByHandle(h, FileBasicInfo, &identity_patch, sizeof(identity_patch));
    error = ok ? 0 : GetLastError();
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    DWORD original_attrs = GetFileAttributesW(renamed), replacement_attrs = GetFileAttributesW(nested);
    result("same handle updates renamed object not replacement", ok && original_attrs == FILE_ATTRIBUTE_HIDDEN && replacement_attrs == FILE_ATTRIBUTE_ARCHIVE,
           error, ((unsigned long long)original_attrs << 32) | replacement_attrs,
           ((unsigned long long)FILE_ATTRIBUTE_HIDDEN << 32) | FILE_ATTRIBUTE_ARCHIVE);

    join(nested, root, L"unicode-\x03ba\x03bf\x03c5-\x96ea.bin");
    ok = create_file(nested) && set_mask(nested, 0, FILE_ATTRIBUTE_HIDDEN);
    error = ok ? 0 : GetLastError(); attrs = GetFileAttributesW(nested);
    if (attrs == INVALID_FILE_ATTRIBUTES) error = GetLastError();
    result("Unicode object attributes", ok && attrs == FILE_ATTRIBUTE_HIDDEN, error, attrs, FILE_ATTRIBUTE_HIDDEN);
    wcscpy(nested, root);
    for (unsigned i = 0; i < 5; i++) {
        wcscat(nested, L"\\long-component-abcdefghijklmnopqrstuvwxyz-0123456789");
        if (!CreateDirectoryW(nested, NULL)) { result("long directory setup", 0, GetLastError(), 0, 1); break; }
    }
    wcscat(nested, L"\\long.bin");
    ok = create_file(nested) && set_mask(nested, 0, FILE_ATTRIBUTE_HIDDEN);
    error = ok ? 0 : GetLastError(); attrs = GetFileAttributesW(nested);
    if (attrs == INVALID_FILE_ATTRIBUTES) error = GetLastError();
    result("extended path longer than MAX_PATH", ok && wcslen(nested) > 260 && attrs == FILE_ATTRIBUTE_HIDDEN,
           error, wcslen(nested), 260);
    printf("{\"summary\":true,\"passed\":%u,\"failed\":%u,\"skipped\":%u}\n", passed, failed, skipped);
    return failed ? 1 : 0;
}
