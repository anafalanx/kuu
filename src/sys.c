/*
 * sys.c -- the `sys` module: facts about this machine and this process.
 *
 *   sys.info() -> {
 *     windows  = { build, revision, version, display, server },
 *     hostname, user, elevated, cpus, arch,
 *     memory   = { total, available },
 *     drives   = { { letter, type }, ... },
 *     uptime, pid, codepage,
 *     process  = { handles, working_set, peak_working_set, private },
 *   }
 *
 * The first thing an agent asks a machine.  Everything is read fresh on each
 * call; nothing is cached and nothing is written.  The Windows version comes
 * from RtlGetVersion, which tells the truth where GetVersionEx lies to
 * unmanifested programs; the marketing name ("25H2") lives only in the
 * registry and is read from there.
 */
#include "err.h"
#include "state.h"
#include "signature.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define PSAPI_VERSION 2
#include <psapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef LONG(WINAPI *rtl_get_version_fn)(PRTL_OSVERSIONINFOW);

static void set_utf8_field(lua_State *L, const char *field, const wchar_t *wide)
{
    char *utf8 = ku_wide_to_utf8(wide, -1);
    if (utf8 != NULL) {
        lua_pushstring(L, utf8);
        lua_setfield(L, -2, field);
        free(utf8);
    }
}

static void push_windows(lua_State *L)
{
    lua_createtable(L, 0, 5);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    rtl_get_version_fn get_version =
        ntdll != NULL ? (rtl_get_version_fn)(void (*)(void))GetProcAddress(ntdll, "RtlGetVersion") : NULL;
    RTL_OSVERSIONINFOEXW info;
    memset(&info, 0, sizeof info);
    info.dwOSVersionInfoSize = sizeof info;
    if (get_version != NULL && get_version((PRTL_OSVERSIONINFOW)&info) == 0) {
        lua_pushinteger(L, (lua_Integer)info.dwBuildNumber);
        lua_setfield(L, -2, "build");
        char version[64];
        snprintf(version, sizeof version, "%lu.%lu.%lu", (unsigned long)info.dwMajorVersion,
                 (unsigned long)info.dwMinorVersion, (unsigned long)info.dwBuildNumber);
        lua_pushstring(L, version);
        lua_setfield(L, -2, "version");
        lua_pushboolean(L, info.wProductType != VER_NT_WORKSTATION);
        lua_setfield(L, -2, "server");
    }
    static const wchar_t key[] = L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
    wchar_t display[64];
    DWORD size = sizeof display;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, L"DisplayVersion", RRF_RT_REG_SZ, NULL, display, &size) == ERROR_SUCCESS) {
        set_utf8_field(L, "display", display);
    }
    DWORD revision = 0;
    size = sizeof revision;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, L"UBR", RRF_RT_REG_DWORD, NULL, &revision, &size) == ERROR_SUCCESS) {
        lua_pushinteger(L, (lua_Integer)revision);
        lua_setfield(L, -2, "revision");
    }
}

static int process_elevated(void)
{
    HANDLE token = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        return 0;
    }
    TOKEN_ELEVATION elevation;
    DWORD size = 0;
    int elevated = GetTokenInformation(token, TokenElevation, &elevation, sizeof elevation, &size) &&
                   elevation.TokenIsElevated != 0;
    CloseHandle(token);
    return elevated;
}

static const char *drive_type_name(UINT type)
{
    switch (type) {
    case DRIVE_FIXED:
        return "fixed";
    case DRIVE_REMOVABLE:
        return "removable";
    case DRIVE_REMOTE:
        return "remote";
    case DRIVE_CDROM:
        return "cdrom";
    case DRIVE_RAMDISK:
        return "ramdisk";
    default:
        return "unknown";
    }
}

static void push_drives(lua_State *L)
{
    lua_newtable(L);
    wchar_t buffer[512];
    DWORD n = GetLogicalDriveStringsW((DWORD)(sizeof buffer / sizeof buffer[0]) - 1, buffer);
    if (n == 0 || n >= sizeof buffer / sizeof buffer[0]) {
        return;
    }
    int index = 1;
    for (const wchar_t *root = buffer; *root != L'\0'; root += wcslen(root) + 1) {
        lua_createtable(L, 0, 2);
        char letter[3] = {(char)root[0], ':', '\0'};
        lua_pushstring(L, letter);
        lua_setfield(L, -2, "letter");
        lua_pushstring(L, drive_type_name(GetDriveTypeW(root)));
        lua_setfield(L, -2, "type");
        lua_rawseti(L, -2, index++);
    }
}

static int l_sys_info(lua_State *L)
{
    lua_createtable(L, 0, 12);
    push_windows(L);
    lua_setfield(L, -2, "windows");

    wchar_t name[256];
    DWORD size = sizeof name / sizeof name[0];
    if (GetComputerNameExW(ComputerNameDnsHostname, name, &size)) {
        set_utf8_field(L, "hostname", name);
    }
    size = sizeof name / sizeof name[0];
    if (GetUserNameW(name, &size)) {
        set_utf8_field(L, "user", name);
    }
    lua_pushboolean(L, process_elevated());
    lua_setfield(L, -2, "elevated");

    lua_pushinteger(L, (lua_Integer)GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));
    lua_setfield(L, -2, "cpus");
    SYSTEM_INFO system;
    GetNativeSystemInfo(&system);
    const char *arch = system.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64   ? "x64"
                       : system.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM64 ? "arm64"
                                                                                       : "other";
    lua_pushstring(L, arch);
    lua_setfield(L, -2, "arch");

    MEMORYSTATUSEX memory;
    memory.dwLength = sizeof memory;
    if (GlobalMemoryStatusEx(&memory)) {
        lua_createtable(L, 0, 2);
        lua_pushinteger(L, (lua_Integer)memory.ullTotalPhys);
        lua_setfield(L, -2, "total");
        lua_pushinteger(L, (lua_Integer)memory.ullAvailPhys);
        lua_setfield(L, -2, "available");
        lua_setfield(L, -2, "memory");
    }
    push_drives(L);
    lua_setfield(L, -2, "drives");

    lua_pushnumber(L, (lua_Number)GetTickCount64() / 1000.0);
    lua_setfield(L, -2, "uptime");
    lua_pushinteger(L, (lua_Integer)GetCurrentProcessId());
    lua_setfield(L, -2, "pid");
    lua_pushinteger(L, (lua_Integer)GetACP());
    lua_setfield(L, -2, "codepage");

    /* this process, for keeping an eye on itself: a soak test watches these */
    lua_createtable(L, 0, 4);
    DWORD handles = 0;
    if (GetProcessHandleCount(GetCurrentProcess(), &handles)) {
        lua_pushinteger(L, (lua_Integer)handles);
        lua_setfield(L, -2, "handles");
    }
    PROCESS_MEMORY_COUNTERS_EX counters;
    memset(&counters, 0, sizeof counters);
    counters.cb = sizeof counters;
    if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&counters, sizeof counters)) {
        lua_pushinteger(L, (lua_Integer)counters.WorkingSetSize);
        lua_setfield(L, -2, "working_set");
        lua_pushinteger(L, (lua_Integer)counters.PeakWorkingSetSize);
        lua_setfield(L, -2, "peak_working_set");
        lua_pushinteger(L, (lua_Integer)counters.PrivateUsage);
        lua_setfield(L, -2, "private");
    }
    lua_setfield(L, -2, "process");
    return 1;
}

int ku_open_sys(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"info", l_sys_info},
        {"signature", ku_sys_signature},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
