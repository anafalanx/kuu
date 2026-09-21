/* Independent test oracle: reads the persisted Shell Link through COM instead
 * of trusting the writer's success. No ShellExecute, Resolve or GUI launch.
 * inspect LINK | launch LINK | junction LINK TARGET
 * launch is used only with the test's own known console probe; it owns a
 * kill-on-close job and a 10-second deadline. junction creates an absent local
 * fixture link; its existing target and trusted parent are never modified.
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <windows.h>
#include <winioctl.h>
#include <objbase.h>
#include <shobjidl.h>
#include <propsys.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static const PROPERTYKEY arguments_key = {
    {0x436f2667, 0x14e2, 0x4feb, {0xb3, 0x0a, 0x14, 0x6c, 0x53, 0xb5, 0xb6, 0x74}}, 100
};

static int failure(const char *operation, HRESULT hr, DWORD why)
{
    fprintf(stderr, "shell_link_reader: %s (HRESULT 0x%08lx, Windows error %lu)\n",
        operation, (unsigned long)hr, (unsigned long)why);
    return 1;
}

static wchar_t *full_path(const wchar_t *path)
{
    size_t length = wcslen(path);
    int drive = length >= 3 && ((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z')) &&
        path[1] == L':' && (path[2] == L'\\' || path[2] == L'/');
    int unc = length > 2 && (path[0] == L'\\' || path[0] == L'/') && path[1] == path[0];
    if ((!drive && !unc) || (unc && (path[2] == L'.' || path[2] == L'?'))) { SetLastError(ERROR_INVALID_NAME); return NULL; }
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    if (!size || size > 32000) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *result = calloc(size, sizeof *result);
    if (!result) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    DWORD got = GetFullPathNameW(path, size, result, NULL);
    if (!got || got >= size) { free(result); return NULL; }
    for (DWORD i = 0; i < got; i++) if (result[i] == L'/') result[i] = L'\\';
    return result;
}

static char *encode_string(const wchar_t *wide)
{
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, NULL, 0, NULL, NULL);
    if (!count) return NULL;
    char *utf8 = malloc((size_t)count), *out = malloc((size_t)count * 6 + 3);
    if (!utf8 || !out) { free(utf8); free(out); return NULL; }
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, utf8, count, NULL, NULL)) {
        free(utf8); free(out); return NULL;
    }
    static const char hex[] = "0123456789abcdef";
    size_t at = 0;
    out[at++] = '"';
    for (int i = 0; i + 1 < count; i++) {
        unsigned char c = (unsigned char)utf8[i];
        if (c == '"' || c == '\\') { out[at++] = '\\'; out[at++] = (char)c; }
        else if (c < 32) {
            out[at++] = '\\'; out[at++] = 'u'; out[at++] = '0'; out[at++] = '0';
            out[at++] = hex[c >> 4]; out[at++] = hex[c & 15];
        } else out[at++] = (char)c;
    }
    out[at++] = '"'; out[at] = '\0'; free(utf8);
    return out;
}

static int inspect(const wchar_t *target, const wchar_t *cwd, const wchar_t *arguments)
{
    size_t capacity = wcslen(arguments) + 10;
    wchar_t *command = calloc(capacity, sizeof *command);
    if (!command) return failure("allocate command", E_OUTOFMEMORY, 0);
    swprintf(command, capacity, L"probe %ls", arguments);
    int count = 0;
    wchar_t **decoded = CommandLineToArgvW(command, &count);
    free(command);
    if (!decoded) return failure("CommandLineToArgvW", S_OK, GetLastError());
    char *target_json = encode_string(target), *cwd_json = encode_string(cwd), *args_json = encode_string(arguments);
    int ok = target_json && cwd_json && args_json;
    if (ok) {
        printf("{\"target\":%s,\"cwd\":%s,\"arguments\":%s,\"argv\":[", target_json, cwd_json, args_json);
        for (int i = 1; i < count; i++) {
            char *value = encode_string(decoded[i]);
            if (!value) { ok = 0; break; }
            printf("%s%s", i == 1 ? "" : ",", value); free(value);
        }
        if (ok) fputs("]}\n", stdout);
    }
    free(target_json); free(cwd_json); free(args_json); LocalFree(decoded);
    if (!ok) return failure("JSON encoding", E_OUTOFMEMORY, 0);
    return fflush(stdout) == 0 ? 0 : 1;
}

static int launch(const wchar_t *target, const wchar_t *cwd, const wchar_t *arguments)
{
    size_t capacity = wcslen(target) + wcslen(arguments) + 5;
    if (capacity > 32767 || wcschr(target, L'"')) return failure("command length or target", E_INVALIDARG, 0);
    wchar_t *command = calloc(capacity, sizeof *command);
    if (!command) return failure("allocate command", E_OUTOFMEMORY, 0);
    swprintf(command, capacity, L"\"%ls\" %ls", target, arguments);
    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (!job) { free(command); return failure("CreateJobObjectW", S_OK, GetLastError()); }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof limits)) {
        DWORD why = GetLastError(); CloseHandle(job); free(command); return failure("SetInformationJobObject", S_OK, why);
    }
    STARTUPINFOW startup = {0};
    startup.cb = sizeof startup; startup.dwFlags = STARTF_USESTDHANDLES | STARTF_FORCEOFFFEEDBACK;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION child = {0};
    if (!CreateProcessW(target, command, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW,
        NULL, cwd, &startup, &child)) {
        DWORD why = GetLastError(); CloseHandle(job); free(command); return failure("CreateProcessW", S_OK, why);
    }
    free(command);
    int assigned = AssignProcessToJobObject(job, child.hProcess) != 0;
    DWORD why = assigned ? 0 : GetLastError();
    int resumed = assigned && ResumeThread(child.hThread) != (DWORD)-1;
    if (assigned && !resumed) why = GetLastError();
    DWORD waited = resumed ? WaitForSingleObject(child.hProcess, 10000) : WAIT_FAILED;
    DWORD code = 1;
    if (waited == WAIT_OBJECT_0) {
        if (!GetExitCodeProcess(child.hProcess, &code)) why = GetLastError();
    } else {
        if (resumed) why = waited == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError();
        if (assigned) TerminateJobObject(job, 124); else TerminateProcess(child.hProcess, 124);
        WaitForSingleObject(child.hProcess, 1000);
    }
    CloseHandle(child.hThread); CloseHandle(child.hProcess); CloseHandle(job);
    if (why) return failure("owned child launch/wait", S_OK, why);
    return (int)code;
}

static int read_link(const wchar_t *link, int execute)
{
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) return failure("CoInitializeEx", hr, 0);
    IShellLinkW *shell = NULL;
    IPersistFile *persist = NULL;
    IPropertyStore *properties = NULL;
    PROPVARIANT value;
    memset(&value, 0, sizeof value);
    wchar_t *path = full_path(link), *target = NULL, *cwd = NULL;
    DWORD path_error = path ? 0 : GetLastError();
    const wchar_t *arguments = L"";
    const char *operation = "allocate absolute paths";
    int code = 1;
    if (!path) { hr = HRESULT_FROM_WIN32(path_error ? path_error : ERROR_INVALID_NAME); goto done; }
    target = calloc(32768, sizeof *target); cwd = calloc(32768, sizeof *cwd);
    if (!target || !cwd) { hr = E_OUTOFMEMORY; goto done; }
    operation = "CoCreateInstance";
    hr = CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, (void **)&shell);
    if (hr != S_OK) goto done;
    operation = "QueryInterface IPersistFile";
    hr = IShellLinkW_QueryInterface(shell, &IID_IPersistFile, (void **)&persist);
    if (hr != S_OK) goto done;
    operation = "IPersistFile::Load";
    hr = IPersistFile_Load(persist, path, STGM_READ);
    if (hr != S_OK) goto done;
    operation = "GetPath";
    hr = IShellLinkW_GetPath(shell, target, 32768, NULL, SLGP_RAWPATH);
    if (hr != S_OK || !target[0]) { if (hr == S_OK) hr = E_INVALIDARG; goto done; }
    operation = "GetWorkingDirectory";
    hr = IShellLinkW_GetWorkingDirectory(shell, cwd, 32768);
    if (hr != S_OK || !cwd[0]) { if (hr == S_OK) hr = E_INVALIDARG; goto done; }
    operation = "QueryInterface IPropertyStore";
    hr = IShellLinkW_QueryInterface(shell, &IID_IPropertyStore, (void **)&properties);
    if (hr != S_OK) goto done;
    operation = "PKEY_Link_Arguments";
    hr = IPropertyStore_GetValue(properties, &arguments_key, &value);
    if (hr != S_OK) goto done;
    if (value.vt == VT_LPWSTR && value.pwszVal) arguments = value.pwszVal;
    else if (value.vt == VT_BSTR && value.bstrVal) arguments = value.bstrVal;
    else if (value.vt != VT_EMPTY && value.vt != VT_NULL) { hr = E_INVALIDARG; goto done; }
    code = execute ? launch(target, cwd, arguments) : inspect(target, cwd, arguments);
done:
    if (hr != S_OK) code = failure(operation, hr, 0);
    PropVariantClear(&value);
    if (properties) IPropertyStore_Release(properties);
    if (persist) IPersistFile_Release(persist);
    if (shell) IShellLinkW_Release(shell);
    free(path); free(target); free(cwd); CoUninitialize();
    return code;
}

static int junction(const wchar_t *link_arg, const wchar_t *target_arg)
{
    wchar_t *link = full_path(link_arg), *target = full_path(target_arg);
    DWORD why = 0;
    int made = 0, ok = 0;
    HANDLE directory = INVALID_HANDLE_VALUE;
    if (!link || !target) { why = GetLastError(); goto done; }
    /* Fixture junctions deliberately support drive-local directories only. */
    if (target[0] == L'\\' || link[0] == L'\\' || wcslen(target) > 3900) { why = ERROR_INVALID_NAME; goto done; }
    DWORD attrs = GetFileAttributesW(target);
    if (attrs == INVALID_FILE_ATTRIBUTES) { why = GetLastError(); goto done; }
    if (!(attrs & FILE_ATTRIBUTE_DIRECTORY)) { why = ERROR_DIRECTORY; goto done; }
    if (!CreateDirectoryW(link, NULL)) { why = GetLastError(); goto done; }
    made = 1;
    directory = CreateFileW(link, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (directory == INVALID_HANDLE_VALUE) { why = GetLastError(); goto done; }
    struct {
        DWORD tag;
        WORD length, reserved, substitute_offset, substitute_length, print_offset, print_length;
        wchar_t paths[8000];
    } data;
    memset(&data, 0, sizeof data);
    data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    swprintf(data.paths, 8000, L"\\??\\%ls", target);
    size_t substitute = wcslen(data.paths), shown = wcslen(target);
    data.substitute_length = (WORD)(substitute * sizeof(wchar_t));
    data.print_offset = (WORD)((substitute + 1) * sizeof(wchar_t));
    data.print_length = (WORD)(shown * sizeof(wchar_t));
    memcpy(data.paths + substitute + 1, target, (shown + 1) * sizeof(wchar_t));
    data.length = (WORD)(8 + (substitute + shown + 2) * sizeof(wchar_t));
    DWORD bytes = 0;
    ok = DeviceIoControl(directory, FSCTL_SET_REPARSE_POINT, &data, (DWORD)data.length + 8,
        NULL, 0, &bytes, NULL) != 0;
    if (!ok) why = GetLastError();
done:
    if (directory != INVALID_HANDLE_VALUE) CloseHandle(directory);
    if (made && !ok && !RemoveDirectoryW(link)) {
        fprintf(stderr, "shell_link_reader: owned empty junction cleanup failed (Windows error %lu)\n", (unsigned long)GetLastError());
    }
    free(link); free(target);
    return ok ? 0 : failure("new fixture junction", S_OK, why);
}

static int hardlink(const wchar_t *link_arg, const wchar_t *target_arg)
{
    wchar_t *link = full_path(link_arg), *target = NULL;
    DWORD why = link ? 0 : GetLastError();
    if (link) { target = full_path(target_arg); if (!target) why = GetLastError(); }
    int ok = link && target && CreateHardLinkW(link, target, NULL);
    if (link && target && !ok) why = GetLastError();
    free(link); free(target);
    return ok ? 0 : failure("new fixture hardlink", S_OK, why);
}

int wmain(int argc, wchar_t **argv)
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (argc == 3 && !wcscmp(argv[1], L"inspect")) return read_link(argv[2], 0);
    if (argc == 3 && !wcscmp(argv[1], L"launch")) return read_link(argv[2], 1);
    if (argc == 4 && !wcscmp(argv[1], L"junction")) return junction(argv[2], argv[3]);
    if (argc == 4 && !wcscmp(argv[1], L"hardlink")) return hardlink(argv[2], argv[3]);
    fputs("usage: shell_link_reader.exe inspect LINK | launch LINK | junction LINK TARGET | hardlink LINK TARGET\n", stderr);
    return 2;
}
