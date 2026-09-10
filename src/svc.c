/* svc.c -- local Service Control Manager operations; waits live in Lua. */
#include "err.h"
#include "hold.h"
#include "state.h"
#include "values.h"
#include "wintext.h"
#include "lauxlib.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

typedef struct service_scope {
    SC_HANDLE manager, service;
    wchar_t *name;
    void *services, *config;
    char *text;
} service_scope;

static void scope_free(void *ptr)
{
    service_scope *s = ptr;
    if (s->service) CloseServiceHandle(s->service);
    if (s->manager) CloseServiceHandle(s->manager);
    free(s->name); free(s->services); free(s->config); free(s->text); free(s);
}

static service_scope *scope_new(lua_State *L)
{
    ku_hold *hold = ku_hold_new(L, scope_free);
    lua_toclose(L, -1);
    service_scope *s = calloc(1, sizeof *s);
    if (!s) ku_err_raise(L, "SVC", "oserror", "out of memory");
    hold->ptr = s;
    return s;
}

static int fail(lua_State *L, DWORD code, const char *name)
{
    const char *kind = code == ERROR_SERVICE_DOES_NOT_EXIST ? "notfound" :
                       code == ERROR_ACCESS_DENIED ? "access" : "oserror";
    return ku_err_fail(L, "SVC", kind, "service '%s': Windows error %lu%s", name,
                       (unsigned long)code, code == ERROR_ACCESS_DENIED ? "; administrator rights may be required" : "");
}

static const char *check_name(lua_State *L)
{
    if (lua_type(L, 1) != LUA_TSTRING) ku_err_raise(L, "SVC", "badvalue", "service name must be a string");
    const char *name = ku_check_cstring(L, 1, "SVC", "service name");
    if (!*name || strpbrk(name, "/\\") || !ku_utf8_valid((const unsigned char *)name, strlen(name)))
        ku_err_raise(L, "SVC", "badvalue", "a service name must be nonempty UTF-8 without slashes");
    return name;
}

static const char *state_name(DWORD state)
{
    switch (state) {
    case SERVICE_RUNNING: return "running";
    case SERVICE_STOPPED: return "stopped";
    case SERVICE_START_PENDING: return "start_pending";
    case SERVICE_STOP_PENDING: return "stop_pending";
    case SERVICE_PAUSED: return "paused";
    case SERVICE_PAUSE_PENDING: return "pause_pending";
    case SERVICE_CONTINUE_PENDING: return "continue_pending";
    default: return "stopped";
    }
}

static const char *start_name(DWORD start)
{
    switch (start) {
    case SERVICE_AUTO_START: return "auto";
    case SERVICE_DEMAND_START: return "manual";
    case SERVICE_DISABLED: return "disabled";
    case SERVICE_BOOT_START: return "boot";
    case SERVICE_SYSTEM_START: return "system";
    default: return "manual";
    }
}

static void wide_field(lua_State *L, service_scope *s, const char *key, const wchar_t *value)
{
    free(s->text);
    s->text = ku_wide_to_utf8(value, -1);
    if (!s->text) ku_err_raise(L, "SVC", "oserror", "cannot convert service text to UTF-8");
    lua_pushstring(L, s->text);
    lua_setfield(L, -2, key);
}

static DWORD open_service(service_scope *s, const wchar_t *name, DWORD access)
{
    if (s->service) { CloseServiceHandle(s->service); s->service = NULL; }
    s->service = OpenServiceW(s->manager, name, access);
    return s->service ? ERROR_SUCCESS : GetLastError();
}

static DWORD query_config(service_scope *s)
{
    DWORD needed = 0;
    QueryServiceConfigW(s->service, NULL, 0, &needed);
    DWORD error = GetLastError();
    if (error != ERROR_INSUFFICIENT_BUFFER) return error;
    void *next = realloc(s->config, needed);
    if (!next) return ERROR_OUTOFMEMORY;
    s->config = next;
    return QueryServiceConfigW(s->service, s->config, needed, &needed) ? ERROR_SUCCESS : GetLastError();
}

static void push_status(lua_State *L, service_scope *s, const wchar_t *name,
                        const SERVICE_STATUS_PROCESS *status, int full)
{
    const QUERY_SERVICE_CONFIGW *config = s->config;
    lua_createtable(L, 0, full ? 6 : 5);
    wide_field(L, s, "name", name);
    wide_field(L, s, "display", config->lpDisplayName);
    lua_pushstring(L, state_name(status->dwCurrentState)); lua_setfield(L, -2, "state");
    lua_pushstring(L, start_name(config->dwStartType)); lua_setfield(L, -2, "start");
    lua_pushinteger(L, status->dwProcessId); lua_setfield(L, -2, "pid");
    if (full) wide_field(L, s, "exe", config->lpBinaryPathName);
}

static int l_status(lua_State *L)
{
    const char *name = check_name(L);
    service_scope *s = scope_new(L);
    s->name = ku_utf8_to_wide(name);
    if (!s->name) return fail(L, ERROR_OUTOFMEMORY, name);
    s->manager = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!s->manager) return fail(L, GetLastError(), name);
    DWORD error = open_service(s, s->name, SERVICE_QUERY_STATUS | SERVICE_QUERY_CONFIG);
    if (error) return fail(L, error, name);
    SERVICE_STATUS_PROCESS status;
    DWORD needed = 0;
    if (!QueryServiceStatusEx(s->service, SC_STATUS_PROCESS_INFO, (BYTE *)&status, sizeof status, &needed))
        return fail(L, GetLastError(), name);
    error = query_config(s);
    if (error) return fail(L, error, name);
    push_status(L, s, s->name, &status, 1);
    return 1;
}

static int compare_services(const void *a, const void *b)
{
    const ENUM_SERVICE_STATUS_PROCESSW *x = a, *y = b;
    return wcscmp(x->lpServiceName, y->lpServiceName);
}

static int l_list(lua_State *L)
{
    service_scope *s = scope_new(L);
    s->manager = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
    if (!s->manager) return fail(L, GetLastError(), "list");
    DWORD capacity = 256 * 1024, resume = 0, needed = 0, count = 0;
    s->services = malloc(capacity);
    if (!s->services) return fail(L, ERROR_OUTOFMEMORY, "list");
    lua_newtable(L);
    lua_Integer index = 0;
    /* SCM caps a buffer at 256 KiB; enumerate all pages before sorting in Lua. */
    do {
        BOOL ok = EnumServicesStatusExW(s->manager, SC_ENUM_PROCESS_INFO, SERVICE_WIN32,
                      SERVICE_STATE_ALL, s->services, capacity, &needed, &count, &resume, NULL);
        DWORD error = ok ? ERROR_SUCCESS : GetLastError();
        if (error && error != ERROR_MORE_DATA) return fail(L, error, "list");
        ENUM_SERVICE_STATUS_PROCESSW *rows = s->services;
        qsort(rows, count, sizeof *rows, compare_services);
        for (DWORD i = 0; i < count; ++i) {
            error = open_service(s, rows[i].lpServiceName, SERVICE_QUERY_CONFIG);
            if (error == ERROR_SERVICE_DOES_NOT_EXIST) continue; /* removed since snapshot */
            if (error) return fail(L, error, "list");
            error = query_config(s);
            if (error) return fail(L, error, "list");
            push_status(L, s, rows[i].lpServiceName, &rows[i].ServiceStatusProcess, 0);
            lua_rawseti(L, -2, ++index);
        }
        if (ok) break;
        if (!count) return fail(L, ERROR_INSUFFICIENT_BUFFER, "list");
    } while (resume != 0);
    return 1;
}

static int change(lua_State *L, int start)
{
    const char *name = check_name(L);
    service_scope *s = scope_new(L);
    s->name = ku_utf8_to_wide(name);
    if (!s->name) return fail(L, ERROR_OUTOFMEMORY, name);
    s->manager = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!s->manager) return fail(L, GetLastError(), name);
    DWORD error = open_service(s, s->name, start ? SERVICE_START : SERVICE_STOP);
    if (error) return fail(L, error, name);
    SERVICE_STATUS status;
    BOOL ok = start ? StartServiceW(s->service, 0, NULL) : ControlService(s->service, SERVICE_CONTROL_STOP, &status);
    error = ok ? ERROR_SUCCESS : GetLastError();
    if (error && error != (start ? ERROR_SERVICE_ALREADY_RUNNING : ERROR_SERVICE_NOT_ACTIVE))
        return fail(L, error, name);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_start(lua_State *L) { return change(L, 1); }
static int l_stop(lua_State *L) { return change(L, 0); }

int ku_open_svc(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"list", l_list}, {"status", l_status}, {"start", l_start}, {"stop", l_stop}, {NULL, NULL}
    };
    luaL_newlib(L, functions);
    return 1;
}
