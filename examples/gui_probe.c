/* A project-owned GUI verification helper, not a kuu API.
 *
 * gui_probe.exe verify PROFILE REPORT [ready|hold-ready|no-ready|early-exit]
 * PROFILE must be a fresh absolute path under a trusted existing parent.
 * REPORT and REPORT.pending must not exist. REPORT is published only when
 * verification and bounded cleanup have finished. No desktop is switched.
 *
 * Build: gcc -std=c11 -O2 -Wall -Wextra -Werror -municode -static
 *        examples/gui_probe.c -o gui_probe.exe -luser32 -lbcrypt
 */
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <windows.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

enum { READY_MS = 3000, CONTINUE_MS = 3000, STOP_MS = 1000, CHILD_MS = 10000 };
static const wchar_t recipe_value[] = L"isolated-v1";

typedef struct report {
    const char *status;
    DWORD win32, cleanup_error, child_pid;
    int private_desktop, window_ready, child_exited, profile_created, profile_removed;
    wchar_t nonce[33], desktop[64];
    const wchar_t *cache, *recipe;
    ULONGLONG elapsed;
} report;

static wchar_t *join(const wchar_t *base, const wchar_t *tail)
{
    size_t a = wcslen(base), b = wcslen(tail);
    if (a + b > 32000) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *out = calloc(a + b + 2, sizeof *out);
    if (!out) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    memcpy(out, base, a * sizeof *out);
    out[a] = L'\\';
    memcpy(out + a + 1, tail, (b + 1) * sizeof *out);
    return out;
}

static wchar_t *absolute_path(const wchar_t *path)
{
    size_t length = wcslen(path);
    int drive = length >= 3 && ((path[0] >= L'A' && path[0] <= L'Z') ||
        (path[0] >= L'a' && path[0] <= L'z')) && path[1] == L':' &&
        (path[2] == L'/' || path[2] == L'\\');
    int unc = length > 2 && (path[0] == L'\\' || path[0] == L'/') && path[1] == path[0];
    if ((!drive && !unc) || (unc && (path[2] == L'?' || path[2] == L'.'))) {
        SetLastError(ERROR_INVALID_NAME); return NULL;
    }
    DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
    if (!size || size > 32000) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *out = calloc(size, sizeof *out);
    if (!out) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    DWORD got = GetFullPathNameW(path, size, out, NULL);
    if (!got || got >= size) { free(out); return NULL; }
    for (DWORD i = 0; i < got; i++) {
        if (out[i] == L'/') out[i] = L'\\';
        if ((out[i] == L'.' || out[i] == L' ') && (i + 1 == got || out[i + 1] == L'/' || out[i + 1] == L'\\')) {
            free(out); SetLastError(ERROR_INVALID_NAME); return NULL;
        }
    }
    if (out[got - 1] == L'\\') { free(out); SetLastError(ERROR_INVALID_NAME); return NULL; }
    return out;
}

static wchar_t *environment(const wchar_t *name)
{
    DWORD size = GetEnvironmentVariableW(name, NULL, 0);
    if (!size) return NULL;
    wchar_t *value = calloc(size, sizeof *value);
    if (!value) return NULL;
    DWORD got = GetEnvironmentVariableW(name, value, size);
    if (!got || got >= size) { free(value); return NULL; }
    return value;
}

static int nonce_bytes(const wchar_t *nonce, char out[34])
{
    if (wcslen(nonce) != 32) return 0;
    for (int i = 0; i < 32; i++) {
        if (!((nonce[i] >= L'0' && nonce[i] <= L'9') || (nonce[i] >= L'a' && nonce[i] <= L'f'))) return 0;
        out[i] = (char)nonce[i];
    }
    out[32] = '\n'; out[33] = '\0';
    return 1;
}

static int new_nonce(wchar_t nonce[33])
{
    unsigned char bytes[16];
    if (BCryptGenRandom(NULL, bytes, sizeof bytes, BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) {
        SetLastError(ERROR_GEN_FAILURE); return 0;
    }
    static const wchar_t hex[] = L"0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        nonce[i * 2] = hex[bytes[i] >> 4]; nonce[i * 2 + 1] = hex[bytes[i] & 15];
    }
    nonce[32] = L'\0';
    return 1;
}

static int write_bytes(HANDLE file, const char *bytes, size_t size)
{
    if (size > MAXDWORD) { SetLastError(ERROR_FILE_TOO_LARGE); return 0; }
    DWORD written = 0;
    if (!WriteFile(file, bytes, (DWORD)size, &written, NULL)) return 0;
    if (written != size) { SetLastError(ERROR_WRITE_FAULT); return 0; }
    return 1;
}

static int write_nonce(const wchar_t *path, const wchar_t *nonce)
{
    char bytes[34];
    if (!nonce_bytes(nonce, bytes)) { SetLastError(ERROR_INVALID_DATA); return 0; }
    HANDLE file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    int ok = write_bytes(file, bytes, 33);
    DWORD why = ok ? ERROR_SUCCESS : GetLastError();
    CloseHandle(file); SetLastError(why);
    return ok;
}

/* No final-component links or directories, no unbounded input, exact nonce. */
static int matches_nonce(const wchar_t *path, const wchar_t *nonce)
{
    char expected[34], actual[34];
    if (!nonce_bytes(nonce, expected)) { SetLastError(ERROR_INVALID_DATA); return 0; }
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
        OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    FILE_ATTRIBUTE_TAG_INFO attrs;
    DWORD got = 0, why = ERROR_SUCCESS;
    int ok = GetFileInformationByHandleEx(file, FileAttributeTagInfo, &attrs, sizeof attrs) != 0;
    if (!ok) why = GetLastError();
    else if (attrs.FileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) { ok = 0; why = ERROR_INVALID_DATA; }
    else if (!ReadFile(file, actual, sizeof actual, &got, NULL)) { ok = 0; why = GetLastError(); }
    else if (got != 33 || memcmp(actual, expected, 33) != 0) { ok = 0; why = ERROR_INVALID_DATA; }
    CloseHandle(file); SetLastError(why);
    return ok;
}

static int desktop_name(HDESK desktop, wchar_t *name, DWORD count)
{
    DWORD needed = 0;
    return GetUserObjectInformationW(desktop, UOI_NAME, name, count * (DWORD)sizeof *name, &needed) != 0;
}

static int not_input_desktop(HDESK desktop)
{
    BOOL receives_input = TRUE;
    DWORD needed = 0;
    return GetUserObjectInformationW(desktop, UOI_IO, &receives_input, sizeof receives_input, &needed) && !receives_input;
}

static LRESULT CALLBACK editor_window(HWND window, UINT message, WPARAM wp, LPARAM lp)
{
    if (message == WM_CLOSE) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wp, lp);
}

/* Only called with the explicit private desktop set at process creation. */
static int editor(int argc, wchar_t **argv)
{
    if (argc != 9) return 40;
    const wchar_t *profile = argv[2], *nonce = argv[3], *wanted_desktop = argv[4];
    const wchar_t *ready_name = argv[5], *stop_name = argv[6], *cache_expected = argv[7], *mode = argv[8];
    wchar_t actual_desktop[128];
    HDESK current = GetThreadDesktop(GetCurrentThreadId());
    if (!desktop_name(current, actual_desktop, 128) || wcscmp(actual_desktop, wanted_desktop) ||
        wcsncmp(wanted_desktop, L"kuu-gui-", 8) || !not_input_desktop(current)) return 41;
    wchar_t *recipe = environment(L"KUU_EDITOR_RECIPE"), *cache = environment(L"KUU_EDITOR_CACHE");
    int env_ok = recipe && cache && !wcscmp(recipe, recipe_value) && !wcscmp(cache, cache_expected);
    free(recipe); free(cache);
    if (!env_ok) return 42;
    wchar_t *owner = join(profile, L"owner"), *ready_path = join(profile, L"ready");
    if (!owner || !ready_path) { free(owner); free(ready_path); return 43; }
    int owned = matches_nonce(owner, nonce);
    free(owner);
    if (!owned) { free(ready_path); return 44; }
    if (!wcscmp(mode, L"early-exit")) { free(ready_path); return 17; }
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, ready_name);
    HANDLE stop = OpenEventW(SYNCHRONIZE, FALSE, stop_name);
    if (!ready || !stop) {
        if (ready) CloseHandle(ready);
        if (stop) CloseHandle(stop);
        free(ready_path); return 45;
    }
    WNDCLASSW cls = {0};
    cls.lpfnWndProc = editor_window;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.lpszClassName = L"KuuIsolatedRecipeEditor";
    int code = 0;
    HWND window = NULL;
    if (!RegisterClassW(&cls)) { code = 46; goto done; }
    window = CreateWindowExW(0, cls.lpszClassName, L"kuu disposable editor probe",
        WS_OVERLAPPEDWINDOW, 20, 20, 420, 180, NULL, NULL, cls.hInstance, NULL);
    if (!window) { code = 47; goto done; }
    HWND edit = CreateWindowExW(0, L"EDIT", L"Fresh isolated profile; no application data.",
        WS_CHILD | WS_VISIBLE | ES_MULTILINE, 0, 0, 390, 130, window, NULL, cls.hInstance, NULL);
    if (!edit) { code = 48; goto done; }
    ShowWindow(window, SW_SHOWNOACTIVATE);
    UpdateWindow(window);
    if (wcscmp(mode, L"no-ready")) {
        if (!write_nonce(ready_path, nonce) || !SetEvent(ready)) { code = 49; goto done; }
    }
    ULONGLONG until = GetTickCount64() + CHILD_MS;
    for (;;) {
        if (GetTickCount64() >= until) { code = 50; break; }
        DWORD event = MsgWaitForMultipleObjects(1, &stop, FALSE, 100, QS_ALLINPUT);
        if (event == WAIT_OBJECT_0) break;
        if (event == WAIT_FAILED) { code = 51; break; }
        MSG message;
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) { code = 52; goto done; }
            TranslateMessage(&message); DispatchMessageW(&message);
        }
    }
done:
    if (window && IsWindow(window)) DestroyWindow(window);
    CloseHandle(stop); CloseHandle(ready); free(ready_path);
    return code;
}

/* Quote the complete argv for the Windows C runtime, including trailing slashes. */
static wchar_t *command_line(const wchar_t *const *args, size_t count)
{
    size_t capacity = 1;
    for (size_t i = 0; i < count; i++) capacity += wcslen(args[i]) * 2 + 3;
    if (capacity > 32767) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *out = calloc(capacity, sizeof *out);
    if (!out) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    size_t at = 0;
    for (size_t i = 0; i < count; i++) {
        if (i) out[at++] = L' ';
        out[at++] = L'"';
        const wchar_t *p = args[i];
        while (*p) {
            size_t slashes = 0;
            while (*p == L'\\') { slashes++; p++; }
            size_t emit = (*p == L'"' || !*p) ? slashes * 2 : slashes;
            for (size_t j = 0; j < emit; j++) out[at++] = L'\\';
            if (*p == L'"') out[at++] = L'\\';
            if (*p) out[at++] = *p++;
        }
        out[at++] = L'"';
    }
    return out;
}

typedef struct windows_seen { DWORD pid; int parent, edit; } windows_seen;
static BOOL CALLBACK observe_window(HWND window, LPARAM data)
{
    windows_seen *seen = (windows_seen *)data;
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid == seen->pid) {
        seen->parent = 1;
        if (FindWindowExW(window, NULL, L"EDIT", NULL)) seen->edit = 1;
    }
    return TRUE;
}

/* Only known files below the newly created, held profile are ever removed. */
static DWORD remove_known(const wchar_t *profile, const wchar_t *name)
{
    wchar_t *path = join(profile, name);
    if (!path) return GetLastError();
    DWORD attrs = GetFileAttributesW(path), why = ERROR_SUCCESS;
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        why = GetLastError();
        if (why == ERROR_FILE_NOT_FOUND || why == ERROR_PATH_NOT_FOUND) why = ERROR_SUCCESS;
    } else if (attrs & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) why = ERROR_INVALID_DATA;
    else if (!DeleteFileW(path)) why = GetLastError();
    free(path);
    return why;
}

static char *json_string(const wchar_t *wide)
{
    if (!wide) wide = L"";
    int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, NULL, 0, NULL, NULL);
    if (!bytes) return NULL;
    char *utf8 = malloc((size_t)bytes), *json = malloc((size_t)bytes * 6 + 3);
    if (!utf8 || !json) { free(utf8); free(json); return NULL; }
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, utf8, bytes, NULL, NULL)) {
        free(utf8); free(json); return NULL;
    }
    static const char hex[] = "0123456789abcdef";
    size_t at = 0;
    json[at++] = '"';
    for (int i = 0; i + 1 < bytes; i++) {
        unsigned char c = (unsigned char)utf8[i];
        if (c == '"' || c == '\\') { json[at++] = '\\'; json[at++] = (char)c; }
        else if (c < 32) {
            json[at++] = '\\'; json[at++] = 'u'; json[at++] = '0'; json[at++] = '0';
            json[at++] = hex[c >> 4]; json[at++] = hex[c & 15];
        } else json[at++] = (char)c;
    }
    json[at++] = '"'; json[at] = '\0'; free(utf8);
    return json;
}

static int publish_report(HANDLE pending, const wchar_t *pending_path, const wchar_t *path, const report *r)
{
    char *desktop = json_string(r->desktop), *nonce = json_string(r->nonce);
    char *cache = json_string(r->cache), *recipe = json_string(r->recipe);
    int ok = !strcmp(r->status, "ready") && r->window_ready && r->child_exited && r->profile_removed && !r->cleanup_error;
    int written = 0;
    if (desktop && nonce && cache && recipe) {
        size_t size = strlen(desktop) + strlen(nonce) + strlen(cache) + strlen(recipe) + 1024;
        char *bytes = malloc(size);
        if (bytes) {
            int length = snprintf(bytes, size,
                "{\"ok\":%s,\"status\":\"%s\",\"win32\":%lu,\"desktop\":%s,\"private_desktop\":%s,"
                "\"window_ready\":%s,\"child_pid\":%lu,\"child_exited\":%s,\"profile_created\":%s,"
                "\"profile_removed\":%s,\"cleanup_error\":%lu,\"cache\":%s,\"recipe\":%s,\"nonce\":%s,\"elapsed_ms\":%llu}\n",
                ok ? "true" : "false", r->status, (unsigned long)r->win32, desktop,
                r->private_desktop ? "true" : "false", r->window_ready ? "true" : "false",
                (unsigned long)r->child_pid, r->child_exited ? "true" : "false", r->profile_created ? "true" : "false",
                r->profile_removed ? "true" : "false", (unsigned long)r->cleanup_error, cache, recipe, nonce,
                (unsigned long long)r->elapsed);
            if (length >= 0 && (size_t)length < size) written = write_bytes(pending, bytes, (size_t)length) && FlushFileBuffers(pending);
            free(bytes);
        }
    }
    free(desktop); free(nonce); free(cache); free(recipe);
    DWORD why = written ? ERROR_SUCCESS : GetLastError();
    CloseHandle(pending);
    if (written && MoveFileExW(pending_path, path, 0)) return ok ? 0 : 1;
    if (written) why = GetLastError();
    DeleteFileW(pending_path); /* Only this invocation's exclusively created file. */
    fwprintf(stderr, L"gui_probe: cannot publish report (Windows error %lu)\n", (unsigned long)why);
    return 2;
}

static int verify(const wchar_t *profile_arg, const wchar_t *report_arg, const wchar_t *mode)
{
    report r = {0};
    r.status = "setup-failed";
    ULONGLONG began = GetTickCount64();
    wchar_t *profile = absolute_path(profile_arg), *report_path = absolute_path(report_arg);
    wchar_t *pending_path = NULL, *owner = NULL, *ready_path = NULL, *continue_path = NULL, *command = NULL;
    wchar_t *cache = environment(L"KUU_EDITOR_CACHE"), *recipe = environment(L"KUU_EDITOR_RECIPE");
    r.cache = cache; r.recipe = recipe;
    HANDLE pending = INVALID_HANDLE_VALUE, profile_hold = INVALID_HANDLE_VALUE, job = NULL, ready = NULL, stop = NULL;
    HDESK desktop = NULL;
    PROCESS_INFORMATION child = {0};
    int assigned = 0;
    if (!profile || !report_path) goto no_report;
    size_t report_len = wcslen(report_path);
    pending_path = calloc(report_len + 9, sizeof *pending_path);
    if (!pending_path) goto no_report;
    memcpy(pending_path, report_path, report_len * sizeof *pending_path);
    memcpy(pending_path + report_len, L".pending", 9 * sizeof *pending_path);
    DWORD existing = GetFileAttributesW(report_path);
    if (existing != INVALID_FILE_ATTRIBUTES || GetLastError() != ERROR_FILE_NOT_FOUND) {
        SetLastError(existing == INVALID_FILE_ATTRIBUTES ? GetLastError() : ERROR_ALREADY_EXISTS); goto no_report;
    }
    pending = CreateFileW(pending_path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (pending == INVALID_HANDLE_VALUE) goto no_report;
    if (!cache || !recipe || wcscmp(recipe, recipe_value)) { r.status = "environment"; r.win32 = ERROR_INVALID_ENVIRONMENT; goto finish; }
    if (!new_nonce(r.nonce)) { r.win32 = GetLastError(); goto finish; }
    swprintf(r.desktop, 64, L"kuu-gui-%ls", r.nonce);
    if (!CreateDirectoryW(profile, NULL)) { r.status = "profile-refused"; r.win32 = GetLastError(); goto finish; }
    r.profile_created = 1;
    profile_hold = CreateFileW(profile, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (profile_hold == INVALID_HANDLE_VALUE) { r.win32 = GetLastError(); goto finish; }
    owner = join(profile, L"owner"); ready_path = join(profile, L"ready"); continue_path = join(profile, L"continue");
    if (!owner || !ready_path || !continue_path || !write_nonce(owner, r.nonce)) { r.win32 = GetLastError(); goto finish; }
    desktop = CreateDesktopW(r.desktop, NULL, NULL, 0, DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS |
        DESKTOP_WRITEOBJECTS | DESKTOP_ENUMERATE, NULL);
    if (!desktop) { r.win32 = GetLastError(); goto finish; }
    r.private_desktop = not_input_desktop(desktop);
    if (!r.private_desktop) { r.win32 = ERROR_ACCESS_DENIED; goto finish; }
    wchar_t ready_name[96], stop_name[96];
    swprintf(ready_name, 96, L"Local\\kuu-gui-ready-%ls", r.nonce);
    swprintf(stop_name, 96, L"Local\\kuu-gui-stop-%ls", r.nonce);
    ready = CreateEventW(NULL, TRUE, FALSE, ready_name);
    if (!ready || GetLastError() == ERROR_ALREADY_EXISTS) { r.win32 = ready ? ERROR_ALREADY_EXISTS : GetLastError(); goto finish; }
    stop = CreateEventW(NULL, TRUE, FALSE, stop_name);
    if (!stop || GetLastError() == ERROR_ALREADY_EXISTS) { r.win32 = stop ? ERROR_ALREADY_EXISTS : GetLastError(); goto finish; }
    job = CreateJobObjectW(NULL, NULL);
    if (!job) { r.win32 = GetLastError(); goto finish; }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limit = {0};
    limit.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limit, sizeof limit)) { r.win32 = GetLastError(); goto finish; }
    wchar_t exe[32768];
    DWORD exe_length = GetModuleFileNameW(NULL, exe, 32768);
    if (!exe_length || exe_length == 32768) { r.win32 = ERROR_FILENAME_EXCED_RANGE; goto finish; }
    const wchar_t *args[] = { exe, L"editor", profile, r.nonce, r.desktop, ready_name, stop_name, cache, mode };
    command = command_line(args, sizeof args / sizeof args[0]);
    if (!command) { r.win32 = GetLastError(); goto finish; }
    STARTUPINFOW startup = {0};
    startup.cb = sizeof startup; startup.lpDesktop = r.desktop; startup.dwFlags = STARTF_FORCEOFFFEEDBACK;
    if (!CreateProcessW(exe, command, NULL, NULL, FALSE, CREATE_SUSPENDED | CREATE_NO_WINDOW,
        NULL, profile, &startup, &child)) { r.win32 = GetLastError(); goto finish; }
    r.child_pid = child.dwProcessId;
    if (!AssignProcessToJobObject(job, child.hProcess)) { r.win32 = GetLastError(); goto finish; }
    assigned = 1;
    if (ResumeThread(child.hThread) == (DWORD)-1) { r.win32 = GetLastError(); goto finish; }
    HANDLE waits[] = { ready, child.hProcess };
    DWORD got = WaitForMultipleObjects(2, waits, FALSE, READY_MS);
    if (got == WAIT_OBJECT_0) {
        windows_seen seen = { child.dwProcessId, 0, 0 };
        if (!matches_nonce(ready_path, r.nonce) || !EnumDesktopWindows(desktop, observe_window, (LPARAM)&seen) ||
            !seen.parent || !seen.edit || WaitForSingleObject(child.hProcess, 0) != WAIT_TIMEOUT) {
            r.status = "readiness-failed"; r.win32 = ERROR_INVALID_DATA; goto finish;
        }
        r.window_ready = 1; r.status = "ready";
        if (!wcscmp(mode, L"hold-ready")) {
            ULONGLONG until = GetTickCount64() + CONTINUE_MS;
            r.status = "continue-timeout";
            do {
                if (matches_nonce(continue_path, r.nonce)) { r.status = "ready"; break; }
                DWORD why = GetLastError();
                if (why != ERROR_FILE_NOT_FOUND && why != ERROR_PATH_NOT_FOUND && why != ERROR_SHARING_VIOLATION) {
                    r.status = "continue-refused"; r.win32 = why; break;
                }
                if (WaitForSingleObject(child.hProcess, 20) == WAIT_OBJECT_0) { r.status = "early-exit"; break; }
            } while (GetTickCount64() < until);
        }
    } else if (got == WAIT_OBJECT_0 + 1) r.status = "early-exit";
    else if (got == WAIT_TIMEOUT) r.status = "timeout";
    else { r.status = "wait-failed"; r.win32 = GetLastError(); }
finish:
    if (child.hProcess) {
        if (stop) SetEvent(stop);
        DWORD waited = WaitForSingleObject(child.hProcess, STOP_MS);
        if (waited != WAIT_OBJECT_0) {
            BOOL stopped = assigned ? TerminateJobObject(job, 90) : TerminateProcess(child.hProcess, 90);
            if (!stopped && !r.cleanup_error) r.cleanup_error = GetLastError();
            waited = WaitForSingleObject(child.hProcess, STOP_MS);
        }
        r.child_exited = waited == WAIT_OBJECT_0;
        if (!r.child_exited && !r.cleanup_error) r.cleanup_error = ERROR_TIMEOUT;
        CloseHandle(child.hThread); CloseHandle(child.hProcess);
    }
    if (job) CloseHandle(job);
    if (ready) CloseHandle(ready);
    if (stop) CloseHandle(stop);
    if (desktop && !CloseDesktop(desktop) && !r.cleanup_error) r.cleanup_error = GetLastError();
    if (r.profile_created && (!r.child_pid || r.child_exited)) {
        const wchar_t *known[] = { L"ready", L"continue", L"owner" };
        for (size_t i = 0; i < sizeof known / sizeof known[0]; i++) {
            DWORD why = remove_known(profile, known[i]);
            if (why && !r.cleanup_error) r.cleanup_error = why;
        }
        if (profile_hold != INVALID_HANDLE_VALUE) {
            CloseHandle(profile_hold); profile_hold = INVALID_HANDLE_VALUE;
        }
        r.profile_removed = RemoveDirectoryW(profile) != 0;
        if (!r.profile_removed && !r.cleanup_error) r.cleanup_error = GetLastError();
    }
    if (profile_hold != INVALID_HANDLE_VALUE) CloseHandle(profile_hold);
    if (!strcmp(r.status, "ready") && r.cleanup_error) r.status = "cleanup-failed";
    r.elapsed = GetTickCount64() - began;
    int code = publish_report(pending, pending_path, report_path, &r);
    free(profile); free(report_path); free(pending_path); free(owner); free(ready_path); free(continue_path);
    free(command); free(cache); free(recipe);
    return code;
no_report:
    fwprintf(stderr, L"gui_probe: invalid or unavailable fresh report path (Windows error %lu)\n", (unsigned long)GetLastError());
    free(profile); free(report_path); free(pending_path); free(cache); free(recipe);
    return 2;
}

int wmain(int argc, wchar_t **argv)
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (argc >= 2 && !wcscmp(argv[1], L"editor")) return editor(argc, argv);
    if ((argc == 4 || argc == 5) && !wcscmp(argv[1], L"verify")) {
        const wchar_t *mode = argc == 5 ? argv[4] : L"ready";
        if (!wcscmp(mode, L"ready") || !wcscmp(mode, L"hold-ready") ||
            !wcscmp(mode, L"no-ready") || !wcscmp(mode, L"early-exit")) return verify(argv[2], argv[3], mode);
    }
    fwprintf(stderr, L"usage: gui_probe.exe verify PROFILE REPORT [ready|hold-ready|no-ready|early-exit]\n");
    return 2;
}
