/*
 * procinfo.c -- the other processes on this machine.
 *
 *   proc.list()                  -> { entry, ... } sorted by pid
 *   proc.find { name = "node.exe" | pid = 4120 | port = 8080 }  -> { entry, ... }
 *   proc.tree(pid)               -> the entry with `children`, recursively | nil, err
 *
 * An entry: { pid, parent, name, threads, exe, cmdline, started, cpu,
 * memory, private }.  The last six come from opening the process with
 * limited query rights and are absent for a process this user may not ask
 * about; `started` is an instant, `cpu` seconds of kernel and user time,
 * `memory` the working set and `private` the private bytes.  The command
 * line comes from the kernel's own copy, not from reading the process's
 * memory.  `find` by name matches the executable name ignoring case, with
 * or without its extension; by port, the owners of TCP listeners on it.
 */
#include "procinfo.h"

#include "err.h"
#include "ports.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <winternl.h>
#define PSAPI_VERSION 2
#include <psapi.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define EPOCH_TICKS 116444736000000000LL

typedef LONG(NTAPI *nt_query_fn)(HANDLE, int, PVOID, ULONG, PULONG);
#define PROCESS_COMMAND_LINE_INFORMATION 60

typedef struct ku_pentry {
    DWORD pid, parent, threads;
    wchar_t name[MAX_PATH];
} ku_pentry;

static int compare_pid(const void *a, const void *b)
{
    DWORD x = ((const ku_pentry *)a)->pid, y = ((const ku_pentry *)b)->pid;
    return x < y ? -1 : x > y ? 1 : 0;
}

/* The snapshot as a sorted array; NULL with GetLastError set. */
static ku_pentry *snapshot(size_t *count)
{
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        return NULL;
    }
    size_t capacity = 256, n = 0;
    ku_pentry *list = (ku_pentry *)malloc(capacity * sizeof *list);
    PROCESSENTRY32W e;
    e.dwSize = sizeof e;
    if (list != NULL && Process32FirstW(snap, &e)) {
        do {
            if (n == capacity) {
                capacity *= 2;
                ku_pentry *grown = (ku_pentry *)realloc(list, capacity * sizeof *list);
                if (grown == NULL) {
                    free(list);
                    list = NULL;
                    break;
                }
                list = grown;
            }
            list[n].pid = e.th32ProcessID;
            list[n].parent = e.th32ParentProcessID;
            list[n].threads = e.cntThreads;
            wcsncpy(list[n].name, e.szExeFile, MAX_PATH - 1);
            list[n].name[MAX_PATH - 1] = L'\0';
            n++;
        } while (Process32NextW(snap, &e));
    }
    DWORD error = GetLastError();
    CloseHandle(snap);
    if (list == NULL) {
        SetLastError(error == 0 ? ERROR_NOT_ENOUGH_MEMORY : error);
        return NULL;
    }
    qsort(list, n, sizeof *list, compare_pid);
    *count = n;
    return list;
}

static void set_wide(lua_State *L, const char *field, const wchar_t *wide, int length)
{
    char *utf8 = ku_wide_to_utf8(wide, length);
    if (utf8 != NULL) {
        lua_pushstring(L, utf8);
        lua_setfield(L, -2, field);
        free(utf8);
    }
}

/* The details that need the process opened; silently absent when it cannot be. */
static void add_details(lua_State *L, DWORD pid)
{
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h == NULL) {
        return;
    }
    wchar_t path[4096];
    DWORD length = sizeof path / sizeof path[0];
    if (QueryFullProcessImageNameW(h, 0, path, &length)) {
        set_wide(L, "exe", path, (int)length);
    }
    FILETIME created, exited, kernel, user;
    if (GetProcessTimes(h, &created, &exited, &kernel, &user)) {
        int64_t ticks = ((int64_t)created.dwHighDateTime << 32) | created.dwLowDateTime;
        if (ticks > EPOCH_TICKS) {
            lua_pushnumber(L, (lua_Number)(ticks - EPOCH_TICKS) / 1e7);
            lua_setfield(L, -2, "started");
        }
        int64_t k = ((int64_t)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime;
        int64_t u = ((int64_t)user.dwHighDateTime << 32) | user.dwLowDateTime;
        lua_pushnumber(L, (lua_Number)(k + u) / 1e7);
        lua_setfield(L, -2, "cpu");
    }
    PROCESS_MEMORY_COUNTERS_EX counters;
    memset(&counters, 0, sizeof counters);
    counters.cb = sizeof counters;
    if (GetProcessMemoryInfo(h, (PROCESS_MEMORY_COUNTERS *)&counters, sizeof counters)) {
        lua_pushinteger(L, (lua_Integer)counters.WorkingSetSize);
        lua_setfield(L, -2, "memory");
        lua_pushinteger(L, (lua_Integer)counters.PrivateUsage);
        lua_setfield(L, -2, "private");
    }
    /* the command line, from the kernel's copy */
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    nt_query_fn query = ntdll != NULL ? (nt_query_fn)(void (*)(void))GetProcAddress(ntdll, "NtQueryInformationProcess") : NULL;
    if (query != NULL) {
        ULONG needed = 0;
        LONG status = query(h, PROCESS_COMMAND_LINE_INFORMATION, NULL, 0, &needed);
        if (needed > 0 && needed < 1024 * 1024) {
            void *buffer = malloc(needed);
            if (buffer != NULL) {
                status = query(h, PROCESS_COMMAND_LINE_INFORMATION, buffer, needed, &needed);
                if (status == 0) {
                    const UNICODE_STRING *us = (const UNICODE_STRING *)buffer;
                    if (us->Buffer != NULL) {
                        set_wide(L, "cmdline", us->Buffer, us->Length / (int)sizeof(wchar_t));
                    }
                }
                free(buffer);
            }
        }
    }
    CloseHandle(h);
}

static void push_entry(lua_State *L, const ku_pentry *e, int details)
{
    lua_createtable(L, 0, 10);
    lua_pushinteger(L, (lua_Integer)e->pid);
    lua_setfield(L, -2, "pid");
    lua_pushinteger(L, (lua_Integer)e->parent);
    lua_setfield(L, -2, "parent");
    lua_pushinteger(L, (lua_Integer)e->threads);
    lua_setfield(L, -2, "threads");
    set_wide(L, "name", e->name, -1);
    if (details) {
        add_details(L, e->pid);
    }
}

static int fail_snapshot(lua_State *L)
{
    char *text = ku_win_error_message(GetLastError());
    int n = ku_err_raise(L, "PROC", "oserror", "cannot list the processes: %s", text != NULL ? text : "");
    free(text);
    return n;
}

int ku_proc_list(lua_State *L)
{
    size_t count = 0;
    ku_pentry *list = snapshot(&count);
    if (list == NULL) {
        return fail_snapshot(L);
    }
    lua_createtable(L, (int)count, 0);
    for (size_t i = 0; i < count; i++) {
        push_entry(L, &list[i], 1);
        lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    free(list);
    return 1;
}

/* case-insensitive, with or without the extension */
static int name_matches(const wchar_t *exe_name, const wchar_t *wanted)
{
    if (_wcsicmp(exe_name, wanted) == 0) {
        return 1;
    }
    size_t n = wcslen(exe_name);
    if (n > 4 && _wcsicmp(exe_name + n - 4, L".exe") == 0 && wcslen(wanted) == n - 4 && _wcsnicmp(exe_name, wanted, n - 4) == 0) {
        return 1;
    }
    return 0;
}

int ku_proc_find(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_getfield(L, 1, "name");
    lua_getfield(L, 1, "pid");
    lua_getfield(L, 1, "port");
    int has_name = !lua_isnil(L, -3), has_pid = !lua_isnil(L, -2), has_port = !lua_isnil(L, -1);
    if (has_name + has_pid + has_port != 1) {
        return ku_err_raise(L, "PROC", "badvalue", "find takes exactly one of name, pid, or port");
    }
    wchar_t *wanted = NULL;
    DWORD pid = 0;
    unsigned short port = 0;
    if (has_name) {
        wanted = ku_utf8_to_wide(luaL_checkstring(L, -3));
        if (wanted == NULL) {
            return ku_err_raise(L, "PROC", "encoding", "the name is not valid UTF-8");
        }
    } else if (has_pid) {
        lua_Integer v = luaL_checkinteger(L, -2);
        if (v < 0 || v > 0xffffffffLL) {
            return ku_err_raise(L, "PROC", "badvalue", "pid out of range");
        }
        pid = (DWORD)v;
    } else {
        lua_Integer v = luaL_checkinteger(L, -1);
        if (v < 1 || v > 65535) {
            return ku_err_raise(L, "PROC", "badvalue", "port must be 1 to 65535");
        }
        port = (unsigned short)v;
    }
    lua_pop(L, 3);
    size_t count = 0;
    ku_pentry *list = snapshot(&count);
    if (list == NULL) {
        free(wanted);
        return fail_snapshot(L);
    }
    ku_listener *listeners = NULL;
    size_t listener_count = 0;
    if (has_port && ku_tcp_listeners(&listeners, &listener_count) != 0) {
        free(list);
        return ku_err_raise(L, "PROC", "oserror", "cannot read the TCP tables");
    }
    lua_newtable(L);
    lua_Integer found = 0;
    for (size_t i = 0; i < count; i++) {
        int match = 0;
        if (has_name) {
            match = name_matches(list[i].name, wanted);
        } else if (has_pid) {
            match = list[i].pid == pid;
        } else {
            for (size_t k = 0; k < listener_count; k++) {
                if (listeners[k].port == port && listeners[k].pid == list[i].pid) {
                    match = 1;
                    break;
                }
            }
        }
        if (match) {
            push_entry(L, &list[i], 1);
            lua_rawseti(L, -2, ++found);
        }
    }
    free(listeners);
    free(list);
    free(wanted);
    return 1;
}

static void push_tree(lua_State *L, const ku_pentry *list, size_t count, size_t index, int depth)
{
    push_entry(L, &list[index], 1);
    lua_newtable(L);
    lua_Integer children = 0;
    if (depth < 64) {
        for (size_t i = 0; i < count; i++) {
            if (list[i].parent == list[index].pid && list[i].pid != list[index].pid && i != index) {
                push_tree(L, list, count, i, depth + 1);
                lua_rawseti(L, -2, ++children);
            }
        }
    }
    lua_setfield(L, -2, "children");
}

int ku_proc_tree(lua_State *L)
{
    lua_Integer v = luaL_checkinteger(L, 1);
    if (v < 0 || v > 0xffffffffLL) {
        return ku_err_raise(L, "PROC", "badvalue", "pid out of range");
    }
    size_t count = 0;
    ku_pentry *list = snapshot(&count);
    if (list == NULL) {
        return fail_snapshot(L);
    }
    for (size_t i = 0; i < count; i++) {
        if (list[i].pid == (DWORD)v) {
            push_tree(L, list, count, i, 0);
            free(list);
            return 1;
        }
    }
    free(list);
    return ku_err_fail(L, "PROC", "notfound", "no process %lld", (long long)v);
}
