/* launch.c -- born-in-job process launch; see launch.h. */
#include "launch.h"
#include "cmdline.h"
#include "wintext.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef PROC_THREAD_ATTRIBUTE_JOB_LIST
#define PROC_THREAD_ATTRIBUTE_JOB_LIST 0x0002000D
#endif

static int path_is_absolute(const char *p)
{
    if (p == NULL || p[0] == '\0') {
        return 0;
    }
    if ((p[0] == '\\' || p[0] == '/') && (p[1] == '\\' || p[1] == '/')) {
        return 1; /* UNC */
    }
    int drive = (p[0] >= 'A' && p[0] <= 'Z') || (p[0] >= 'a' && p[0] <= 'z');
    return drive && p[1] == ':' && (p[2] == '\\' || p[2] == '/');
}

static int has_extension(const char *program)
{
    const char *base = program;
    for (const char *c = program; *c; c++) {
        if (*c == '/' || *c == '\\') {
            base = c + 1;
        }
    }
    return strchr(base, '.') != NULL;
}

int ku_resolve_exe(const char *program, char **exe)
{
    *exe = NULL;
    wchar_t *wide = ku_utf8_to_wide(program);
    if (wide == NULL) {
        return 2;
    }
    /* A bare name (no separator) resolves from PATH only, never from the
     * current directory, so a cwd-local "git.exe" cannot hijack a bare name.
     * A name with a separator is searched as given.  Names without an
     * extension try the executable extensions; the bare name itself is never
     * matched, because it could be a non-executable file. */
    int bare = wcschr(wide, L'\\') == NULL && wcschr(wide, L'/') == NULL;
    wchar_t *path_env = NULL;
    if (bare) {
        DWORD need = GetEnvironmentVariableW(L"PATH", NULL, 0);
        if (need == 0) {
            free(wide);
            return 1;
        }
        path_env = (wchar_t *)malloc((size_t)need * sizeof(wchar_t));
        if (path_env == NULL || GetEnvironmentVariableW(L"PATH", path_env, need) == 0) {
            free(path_env);
            free(wide);
            return 1;
        }
    }
    const wchar_t *extensions[4];
    int count = 0;
    if (has_extension(program)) {
        extensions[count++] = NULL;
    } else {
        extensions[count++] = L".exe";
        extensions[count++] = L".com";
        extensions[count++] = L".bat";
        extensions[count++] = L".cmd";
    }
    wchar_t found[MAX_PATH * 2];
    int status = 1;
    for (int i = 0; i < count; i++) {
        wchar_t *file_part = NULL;
        DWORD n = SearchPathW(bare ? path_env : NULL, wide, extensions[i],
                              (DWORD)(sizeof found / sizeof found[0]), found, &file_part);
        if (n > 0 && n < sizeof found / sizeof found[0]) {
            DWORD attributes = GetFileAttributesW(found);
            if (attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
                *exe = ku_wide_to_utf8(found, -1);
                status = *exe != NULL ? 0 : 2;
                break;
            }
        }
    }
    free(path_env);
    free(wide);
    return status;
}

HANDLE ku_job_new(ku_fail *fail)
{
    HANDLE job = CreateJobObjectW(NULL, NULL); /* non-inheritable: no child can pin it */
    if (job == NULL) {
        ku_fail_set(fail, "PROC", "oserror", "cannot create a job object (error %lu)",
                    (unsigned long)GetLastError());
        return NULL;
    }
    /* KILL_ON_JOB_CLOSE is the no-orphans law.  BREAKAWAY_OK lets a process in
     * the tree leave on purpose, by asking for CREATE_BREAKAWAY_FROM_JOB the way
     * kuu's own detach does; nothing leaves by accident (that would be
     * SILENT_BREAKAWAY_OK, which is not set).  Without it a program run by kuu
     * could never detach anything, and its run would not complete until the
     * would-be daemon exited. */
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
    ZeroMemory(&limits, sizeof limits);
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof limits)) {
        ku_fail_set(fail, "PROC", "oserror", "cannot configure the job object (error %lu)",
                    (unsigned long)GetLastError());
        CloseHandle(job);
        return NULL;
    }
    return job;
}

int ku_job_limits(HANDLE job, const ku_limits *limits, ku_fail *fail)
{
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
    ZeroMemory(&info, sizeof info);
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (limits->memory != 0) {
        info.BasicLimitInformation.LimitFlags |= JOB_OBJECT_LIMIT_JOB_MEMORY;
        info.JobMemoryLimit = (SIZE_T)limits->memory;
    }
    if (limits->cpu_ms != 0) {
        info.BasicLimitInformation.LimitFlags |= JOB_OBJECT_LIMIT_JOB_TIME;
        info.BasicLimitInformation.PerJobUserTimeLimit.QuadPart = limits->cpu_ms * 10000;
    }
    if (limits->processes != 0) {
        info.BasicLimitInformation.LimitFlags |= JOB_OBJECT_LIMIT_ACTIVE_PROCESS;
        info.BasicLimitInformation.ActiveProcessLimit = limits->processes;
    }
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof info)) {
        return ku_fail_set(fail, "PROC", "oserror", "cannot apply child limits (error %lu)",
                           (unsigned long)GetLastError());
    }
    return 0;
}

HANDLE ku_open_nul(int write)
{
    HANDLE h = CreateFileW(L"NUL", write ? GENERIC_READ | GENERIC_WRITE : GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    return h == INVALID_HANDLE_VALUE ? NULL : h;
}

/* ---- environment block -------------------------------------------------------- */

typedef struct env_item {
    const wchar_t *text; /* NAME=VALUE */
    size_t length;
    size_t name_length;
    wchar_t *owned;
} env_item;

static size_t env_name_length(const wchar_t *entry)
{
    /* Entries starting with '=' (drive-current-directory state) have their
     * name after the leading '='. */
    const wchar_t *p = entry;
    if (*p == L'=') {
        p++;
    }
    while (*p != L'\0' && *p != L'=') {
        p++;
    }
    return (size_t)(p - entry);
}

static int env_compare(const void *a, const void *b)
{
    const env_item *x = (const env_item *)a;
    const env_item *y = (const env_item *)b;
    int r = CompareStringOrdinal(x->text, (int)x->name_length, y->text, (int)y->name_length, TRUE);
    if (r == CSTR_LESS_THAN) {
        return -1;
    }
    if (r == CSTR_GREATER_THAN) {
        return 1;
    }
    return 0;
}

static int env_same_name(const wchar_t *a, size_t la, const wchar_t *b, size_t lb)
{
    return CompareStringOrdinal(a, (int)la, b, (int)lb, TRUE) == CSTR_EQUAL;
}

int ku_env_block(int count, const char *const *keys, const char *const *values,
                 wchar_t **block, ku_fail *fail)
{
    *block = NULL;
    wchar_t **wkeys = (wchar_t **)calloc((size_t)(count > 0 ? count : 1), sizeof *wkeys);
    if (wkeys == NULL) {
        return ku_fail_set(fail, "PROC", "oserror", "out of memory");
    }
    int rc = 0;
    for (int i = 0; i < count && rc == 0; i++) {
        if (keys[i][0] == '\0' || strchr(keys[i], '=') != NULL) {
            rc = ku_fail_set(fail, "PROC", "badvalue",
                             "environment names must be non-empty and contain no '='");
            break;
        }
        wkeys[i] = ku_utf8_to_wide(keys[i]);
        if (wkeys[i] == NULL) {
            rc = ku_fail_set(fail, "PROC", "encoding", "environment name '%s' is not valid UTF-8", keys[i]);
            break;
        }
        for (int k = 0; k < i; k++) {
            if (env_same_name(wkeys[k], wcslen(wkeys[k]), wkeys[i], wcslen(wkeys[i]))) {
                rc = ku_fail_set(fail, "PROC", "badvalue", "duplicate environment name '%s'", keys[i]);
                break;
            }
        }
    }

    LPWCH inherited = NULL;
    env_item *items = NULL;
    size_t nitems = 0;
    if (rc == 0) {
        inherited = GetEnvironmentStringsW();
        if (inherited == NULL) {
            rc = ku_fail_set(fail, "PROC", "oserror", "cannot read the environment");
        }
    }
    if (rc == 0) {
        size_t inherited_count = 0;
        for (const wchar_t *e = inherited; *e; e += wcslen(e) + 1) {
            inherited_count++;
        }
        items = (env_item *)calloc(inherited_count + (size_t)count + 1, sizeof *items);
        if (items == NULL) {
            rc = ku_fail_set(fail, "PROC", "oserror", "out of memory");
        }
    }
    /* Inherited entries, minus the ones the caller overrides or removes. */
    for (const wchar_t *e = inherited; rc == 0 && *e; e += wcslen(e) + 1) {
        size_t length = wcslen(e);
        size_t name_length = env_name_length(e);
        int replaced = 0;
        for (int i = 0; i < count; i++) {
            if (env_same_name(e, name_length, wkeys[i], wcslen(wkeys[i]))) {
                replaced = 1;
                break;
            }
        }
        if (!replaced) {
            items[nitems].text = e;
            items[nitems].length = length;
            items[nitems].name_length = name_length;
            nitems++;
        }
    }
    /* The caller's entries, as NAME=VALUE. */
    for (int i = 0; i < count && rc == 0; i++) {
        if (values[i] == NULL) {
            continue; /* removed */
        }
        wchar_t *wvalue = ku_utf8_to_wide(values[i]);
        if (wvalue == NULL) {
            rc = ku_fail_set(fail, "PROC", "encoding", "the value of '%s' is not valid UTF-8", keys[i]);
            break;
        }
        size_t lk = wcslen(wkeys[i]), lv = wcslen(wvalue);
        wchar_t *entry = (wchar_t *)malloc((lk + 1 + lv + 1) * sizeof(wchar_t));
        if (entry == NULL) {
            free(wvalue);
            rc = ku_fail_set(fail, "PROC", "oserror", "out of memory");
            break;
        }
        memcpy(entry, wkeys[i], lk * sizeof(wchar_t));
        entry[lk] = L'=';
        memcpy(entry + lk + 1, wvalue, lv * sizeof(wchar_t));
        entry[lk + 1 + lv] = L'\0';
        free(wvalue);
        items[nitems].text = entry;
        items[nitems].owned = entry;
        items[nitems].length = lk + 1 + lv;
        items[nitems].name_length = lk;
        nitems++;
    }
    if (rc == 0) {
        /* CreateProcess requires the block sorted by name, case-insensitively. */
        qsort(items, nitems, sizeof *items, env_compare);
        size_t total = 1;
        for (size_t i = 0; i < nitems; i++) {
            total += items[i].length + 1;
        }
        wchar_t *out = (wchar_t *)malloc(total * sizeof(wchar_t));
        if (out == NULL) {
            rc = ku_fail_set(fail, "PROC", "oserror", "out of memory");
        } else {
            size_t pos = 0;
            for (size_t i = 0; i < nitems; i++) {
                memcpy(out + pos, items[i].text, items[i].length * sizeof(wchar_t));
                pos += items[i].length;
                out[pos++] = L'\0';
            }
            out[pos] = L'\0';
            *block = out;
        }
    }
    for (size_t i = 0; i < nitems; i++) {
        free(items[i].owned);
    }
    free(items);
    if (inherited != NULL) {
        FreeEnvironmentStringsW(inherited);
    }
    for (int i = 0; i < count; i++) {
        free(wkeys[i]);
    }
    free(wkeys);
    return rc;
}

/* ---- the launch ----------------------------------------------------------------- */

/* cmd.exe from kuu's own environment or the system directory, never from a
 * child's custom environment, which could point ComSpec anywhere. */
static char *comspec_path(void)
{
    wchar_t buffer[1024];
    DWORD n = GetEnvironmentVariableW(L"ComSpec", buffer, (DWORD)(sizeof buffer / sizeof buffer[0]));
    if (n > 0 && n < sizeof buffer / sizeof buffer[0]) {
        char *utf8 = ku_wide_to_utf8(buffer, -1);
        if (utf8 != NULL && path_is_absolute(utf8)) {
            return utf8;
        }
        free(utf8);
    }
    wchar_t system_dir[MAX_PATH];
    UINT m = GetSystemDirectoryW(system_dir, MAX_PATH);
    if (m > 0 && m < MAX_PATH) {
        wchar_t full[MAX_PATH + 16];
        wcscpy(full, system_dir);
        wcscat(full, L"\\cmd.exe");
        return ku_wide_to_utf8(full, -1);
    }
    return NULL;
}

/* Does the job kuu itself runs in, if any, let children break away? */
static int breakaway_permitted(void)
{
    BOOL in_job = FALSE;
    if (!IsProcessInJob(GetCurrentProcess(), NULL, &in_job) || !in_job) {
        return 0; /* no job to break away from: the flag would be an error */
    }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
    ZeroMemory(&info, sizeof info);
    if (!QueryInformationJobObject(NULL, JobObjectExtendedLimitInformation, &info, sizeof info, NULL)) {
        return 0;
    }
    return (info.BasicLimitInformation.LimitFlags &
            (JOB_OBJECT_LIMIT_BREAKAWAY_OK | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK)) != 0;
}

static int launch_fail(ku_fail *fail, const char *what)
{
    char *text = ku_win_error_message(GetLastError());
    ku_fail_set(fail, "PROC", "launch", "%s: %s", what, text != NULL ? text : "unknown error");
    free(text);
    return 1;
}

static int launch_common(const char *exe, int argc, const char *const *argv, const char *cwd,
                         HANDLE job, const ku_stdio *io, HPCON console, const wchar_t *env,
                         DWORD *pid, HANDLE *process, ku_fail *fail)
{
    if (exe == NULL || exe[0] == '\0' || argc <= 0 || argv == NULL) {
        return ku_fail_set(fail, "PROC", "usage", "a command is required");
    }
    if (console == NULL && (io == NULL || io->in == NULL || io->out == NULL || io->err == NULL)) {
        return ku_fail_set(fail, "PROC", "oserror", "the child's standard handles are incomplete");
    }
    int rc = 1;
    char *cmdline = NULL, *comspec = NULL;
    wchar_t *wapp = NULL, *wcmd = NULL, *wcwd = NULL;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    int attributes_ready = 0;
    HANDLE duplicates[3] = {NULL, NULL, NULL};
    HANDLE inherit[3];
    int ninherit = 0;

    const char *app = exe;
    if (ku_is_batch_target(exe)) {
        comspec = comspec_path();
        if (comspec == NULL) {
            ku_fail_set(fail, "PROC", "launch", "cannot locate cmd.exe to run a batch file");
            goto done;
        }
        const char *problem = NULL;
        if (ku_make_batch_cmdline(exe, argc - 1, argv + 1, &cmdline, &problem) != 0) {
            ku_fail_set(fail, "PROC", "badvalue", "%s", problem);
            goto done;
        }
        app = comspec;
    } else {
        cmdline = ku_make_cmdline(argc, argv);
        if (cmdline == NULL) {
            ku_fail_set(fail, "PROC", "oserror", "out of memory");
            goto done;
        }
    }
    wapp = ku_utf8_to_wide(app);
    wcmd = ku_utf8_to_wide(cmdline); /* CreateProcessW may modify it: our own copy */
    if (wapp == NULL || wcmd == NULL) {
        ku_fail_set(fail, "PROC", "encoding", "the command line is not valid UTF-8");
        goto done;
    }
    if (cwd != NULL && cwd[0] != '\0') {
        wcwd = ku_utf8_to_wide(cwd);
        if (wcwd == NULL) {
            ku_fail_set(fail, "PROC", "encoding", "the working directory is not valid UTF-8");
            goto done;
        }
    }

    /* Private inheritable duplicates of each distinct stdio handle; the
     * caller's handles are never mutated and only the duplicates can be
     * inherited. */
    HANDLE self = GetCurrentProcess();
    HANDLE originals[3] = {NULL, NULL, NULL};
    if (io != NULL) {
        originals[0] = io->in;
        originals[1] = io->out;
        originals[2] = io->err;
    }
    for (int i = 0; console == NULL && i < 3; i++) {
        int prior = -1;
        for (int k = 0; k < i; k++) {
            if (originals[k] == originals[i]) {
                prior = k;
                break;
            }
        }
        if (prior >= 0) {
            duplicates[i] = duplicates[prior];
            continue;
        }
        if (!DuplicateHandle(self, originals[i], self, &duplicates[i], 0, TRUE, DUPLICATE_SAME_ACCESS)) {
            launch_fail(fail, "cannot duplicate a standard handle");
            goto done;
        }
        inherit[ninherit++] = duplicates[i];
    }

    SIZE_T size = 0;
    DWORD attribute_count = job != NULL ? 2 : 1;
    InitializeProcThreadAttributeList(NULL, attribute_count, 0, &size);
    if (size == 0) {
        launch_fail(fail, "cannot size the attribute list");
        goto done;
    }
    attributes = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(size);
    if (attributes == NULL || !InitializeProcThreadAttributeList(attributes, attribute_count, 0, &size)) {
        launch_fail(fail, "cannot initialise the attribute list");
        goto done;
    }
    attributes_ready = 1;
    HANDLE jobs[1] = {job};
    if (job != NULL &&
        !UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_JOB_LIST, jobs, sizeof jobs, NULL, NULL)) {
        launch_fail(fail, "cannot attach the job to the launch");
        goto done;
    }
    if (console != NULL) {
        if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console,
                                       sizeof console, NULL, NULL)) {
            launch_fail(fail, "cannot attach the pseudoconsole");
            goto done;
        }
    } else if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherit,
                                   (SIZE_T)ninherit * sizeof(HANDLE), NULL, NULL)) {
        launch_fail(fail, "cannot restrict handle inheritance");
        goto done;
    }

    STARTUPINFOEXW startup;
    ZeroMemory(&startup, sizeof startup);
    startup.StartupInfo.cb = sizeof startup;
    /* Explicitly discard redirected parent stdio for a pseudoconsole.
     * Otherwise Windows can attach the child to ConPTY but still give it
     * the parent's redirected handles for normal reads and writes. */
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = console == NULL ? duplicates[0] : INVALID_HANDLE_VALUE;
    startup.StartupInfo.hStdOutput = console == NULL ? duplicates[1] : INVALID_HANDLE_VALUE;
    startup.StartupInfo.hStdError = console == NULL ? duplicates[2] : INVALID_HANDLE_VALUE;
    startup.lpAttributeList = attributes;

    PROCESS_INFORMATION info;
    ZeroMemory(&info, sizeof info);
    DWORD flags = EXTENDED_STARTUPINFO_PRESENT;
    if (job == NULL) {
        /* The detach path: no console of ours, its own process group so a
         * Ctrl-C at our console does not reach it, and out of our own job when
         * the job we sit in permits breakaway.  Jobs that enclose kuu itself
         * (a terminal's, a harness's) are that environment's policy, not
         * orphans of kuu, so their presence is not a failure. */
        flags |= DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
        if (breakaway_permitted()) {
            flags |= CREATE_BREAKAWAY_FROM_JOB;
        }
    }
    if (env != NULL) {
        flags |= CREATE_UNICODE_ENVIRONMENT;
    }
    if (!CreateProcessW(wapp, wcmd, NULL, NULL, console == NULL, flags, (LPVOID)env, wcwd,
                        &startup.StartupInfo, &info)) {
        DWORD error = GetLastError();
        char *text = ku_win_error_message(error);
        if (cwd != NULL && error == ERROR_DIRECTORY) {
            ku_fail_set(fail, "PROC", "badvalue", "the working directory '%s' does not exist", cwd);
        } else {
            ku_fail_set(fail, "PROC", "launch", "cannot start '%s': %s", exe,
                        text != NULL ? text : "unknown error");
        }
        free(text);
        goto done;
    }
    CloseHandle(info.hThread);
    *pid = info.dwProcessId;
    *process = info.hProcess;
    rc = 0;

done:
    if (attributes_ready) {
        DeleteProcThreadAttributeList(attributes);
    }
    free(attributes);
    for (int i = 0; i < ninherit; i++) {
        CloseHandle(inherit[i]); /* the child holds its own inherited copies now */
    }
    free(wapp);
    free(wcmd);
    free(wcwd);
    free(cmdline);
    free(comspec);
    return rc;
}

int ku_launch(const char *exe, int argc, const char *const *argv, const char *cwd,
              HANDLE job, const ku_stdio *io, const wchar_t *env,
              DWORD *pid, HANDLE *process, ku_fail *fail)
{
    return launch_common(exe, argc, argv, cwd, job, io, NULL, env, pid, process, fail);
}

int ku_launch_console(const char *exe, int argc, const char *const *argv, const char *cwd,
                      HANDLE job, HPCON console, const wchar_t *env,
                      DWORD *pid, HANDLE *process, ku_fail *fail)
{
    return launch_common(exe, argc, argv, cwd, job, NULL, console, env, pid, process, fail);
}
