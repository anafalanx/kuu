/* evt.c -- bounded, read-only queries of the local Windows event channels. */
#include "err.h"
#include "hold.h"
#include "state.h"
#include "values.h"
#include "wintext.h"
#include "lauxlib.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winevt.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct event_scope {
    EVT_HANDLE query, context, metadata, events[16];
    wchar_t *channel, *provider, *xpath, *wide;
    void *values;
    char *text;
} event_scope;

static void scope_free(void *ptr)
{
    event_scope *s = ptr;
    for (size_t i = 0; i < 16; ++i) if (s->events[i]) EvtClose(s->events[i]);
    if (s->metadata) EvtClose(s->metadata);
    if (s->context) EvtClose(s->context);
    if (s->query) EvtClose(s->query);
    free(s->channel); free(s->provider); free(s->xpath); free(s->wide);
    free(s->values); free(s->text); free(s);
}

static event_scope *scope_new(lua_State *L)
{
    ku_hold *hold = ku_hold_new(L, scope_free);
    lua_toclose(L, -1);
    event_scope *s = calloc(1, sizeof *s);
    if (!s) ku_err_raise(L, "EVT", "oserror", "out of memory");
    hold->ptr = s;
    return s;
}

static int fail(lua_State *L, DWORD code, const char *what)
{
    const char *kind = code == ERROR_EVT_CHANNEL_NOT_FOUND || code == ERROR_FILE_NOT_FOUND ? "notfound" :
                       code == ERROR_ACCESS_DENIED ? "access" : "oserror";
    return ku_err_fail(L, "EVT", kind, "%s: Windows error %lu", what, (unsigned long)code);
}

static const char *check_text(lua_State *L, int index, const char *what)
{
    if (lua_type(L, index) != LUA_TSTRING) ku_err_raise(L, "EVT", "badvalue", "%s must be a string", what);
    const char *text = ku_check_cstring(L, index, "EVT", what);
    if (!*text || !ku_utf8_valid((const unsigned char *)text, strlen(text)))
        ku_err_raise(L, "EVT", "badvalue", "%s must be nonempty UTF-8", what);
    return text;
}

static const char *level_name(unsigned int level)
{
    static const char *const names[] = { "information", "critical", "error", "warning", "information", "verbose" };
    return level <= 5 ? names[level] : "information";
}

static int level_number(lua_State *L, int index)
{
    if (lua_type(L, index) != LUA_TSTRING) ku_err_raise(L, "EVT", "badvalue", "level must be a string");
    const char *name = ku_check_cstring(L, index, "EVT", "level");
    for (int i = 1; i <= 5; ++i) if (!strcmp(name, level_name((unsigned int)i))) return i;
    ku_err_raise(L, "EVT", "badvalue", "level must be critical, error, warning, information, or verbose");
}

static void push_wide(lua_State *L, event_scope *s, const wchar_t *wide)
{
    if (!wide || !*wide) { lua_pushliteral(L, ""); return; }
    free(s->text);
    s->text = ku_wide_to_utf8(wide, -1);
    if (!s->text) ku_err_raise(L, "EVT", "oserror", "cannot convert event text to UTF-8");
    lua_pushstring(L, s->text);
}

static int l_logs(lua_State *L)
{
    event_scope *s = scope_new(L);
    s->query = EvtOpenChannelEnum(NULL, 0);
    if (!s->query) return fail(L, GetLastError(), "enumerate channels");
    lua_newtable(L);
    lua_Integer count = 0;
    for (;;) {
        DWORD needed = 0;
        EvtNextChannelPath(s->query, 0, NULL, &needed);
        DWORD error = GetLastError();
        if (error == ERROR_NO_MORE_ITEMS) return 1;
        if (error != ERROR_INSUFFICIENT_BUFFER) return fail(L, error, "enumerate channels");
        void *next = realloc(s->wide, (size_t)needed * sizeof(wchar_t));
        if (!next) return fail(L, ERROR_OUTOFMEMORY, "enumerate channels");
        s->wide = next;
        if (!EvtNextChannelPath(s->query, needed, s->wide, &needed)) return fail(L, GetLastError(), "enumerate channels");
        push_wide(L, s, s->wide);
        lua_rawseti(L, -2, ++count);
    }
}

static DWORD render_values(event_scope *s, EVT_HANDLE event)
{
    DWORD needed = 0, count = 0;
    EvtRender(s->context, event, EvtRenderEventValues, 0, NULL, &needed, &count);
    DWORD error = GetLastError();
    if (error != ERROR_INSUFFICIENT_BUFFER) return error;
    void *next = realloc(s->values, needed);
    if (!next) return ERROR_OUTOFMEMORY;
    s->values = next;
    if (!EvtRender(s->context, event, EvtRenderEventValues, needed, s->values, &needed, &count)) return GetLastError();
    return count >= EvtSystemPropertyIdEND ? ERROR_SUCCESS : ERROR_INVALID_DATA;
}

static DWORD render_xml(event_scope *s, EVT_HANDLE event)
{
    DWORD needed = 0, count = 0;
    EvtRender(NULL, event, EvtRenderEventXml, 0, NULL, &needed, &count);
    DWORD error = GetLastError();
    if (error != ERROR_INSUFFICIENT_BUFFER) return error;
    void *next = realloc(s->wide, needed);
    if (!next) return ERROR_OUTOFMEMORY;
    s->wide = next;
    return EvtRender(NULL, event, EvtRenderEventXml, needed, s->wide, &needed, &count) ? ERROR_SUCCESS : GetLastError();
}

static DWORD render_message(event_scope *s, EVT_HANDLE event, const wchar_t *provider)
{
    if (s->metadata) { EvtClose(s->metadata); s->metadata = NULL; }
    if (provider) s->metadata = EvtOpenPublisherMetadata(NULL, provider, NULL, 0, 0);
    if (s->metadata) {
        DWORD needed = 0;
        EvtFormatMessage(s->metadata, event, 0, 0, NULL, EvtFormatMessageEvent, 0, NULL, &needed);
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && needed) {
            void *next = realloc(s->wide, (size_t)needed * sizeof(wchar_t));
            if (!next) return ERROR_OUTOFMEMORY;
            s->wide = next;
            if (EvtFormatMessage(s->metadata, event, 0, 0, NULL, EvtFormatMessageEvent, needed, s->wide, &needed))
                return ERROR_SUCCESS;
        }
    }
    /* Uninstalled/missing publisher resources are ordinary for old events. */
    return render_xml(s, event);
}

static const wchar_t *variant_string(const EVT_VARIANT *v)
{
    return v->Type == EvtVarTypeString ? v->StringVal : NULL;
}

static int l_read(lua_State *L)
{
    const char *channel = check_text(L, 1, "channel");
    const char *provider = NULL;
    int level = -1, limit = 1000, has_since = 0;
    double since = 0;
    if (!lua_isnoneornil(L, 2)) {
        if (!lua_istable(L, 2)) ku_err_raise(L, "EVT", "badvalue", "options must be a table");
        lua_pushnil(L);
        while (lua_next(L, 2)) {
            const char *key = lua_type(L, -2) == LUA_TSTRING ? lua_tostring(L, -2) : "";
            if (lua_type(L, -2) == LUA_TSTRING) ku_check_cstring(L, -2, "EVT", "option name");
            if (!strcmp(key, "since")) {
                if (lua_type(L, -1) != LUA_TNUMBER) ku_err_raise(L, "EVT", "badvalue", "since must be an instant");
                since = lua_tonumber(L, -1);
                if (!isfinite(since) || since < -11644473600.0 || since >= 253402300800.0)
                    ku_err_raise(L, "EVT", "badvalue", "since must be an instant from 1601 through 9999");
                has_since = 1;
            } else if (!strcmp(key, "level")) {
                level = level_number(L, -1);
            } else if (!strcmp(key, "provider")) {
                provider = check_text(L, -1, "provider");
                if (strchr(provider, '\'') && strchr(provider, '"'))
                    ku_err_raise(L, "EVT", "badvalue", "provider must not contain both quote characters");
            } else if (!strcmp(key, "limit")) {
                if (!lua_isinteger(L, -1) || lua_tointeger(L, -1) < 1 || lua_tointeger(L, -1) > 100000)
                    ku_err_raise(L, "EVT", "badvalue", "limit must be an integer from 1 to 100000");
                limit = (int)lua_tointeger(L, -1);
            } else ku_err_raise(L, "EVT", "badvalue", "unknown option '%s'", key);
            lua_pop(L, 1);
        }
    }
    event_scope *s = scope_new(L);
    s->channel = ku_utf8_to_wide(channel);
    if (provider) s->provider = ku_utf8_to_wide(provider);
    if (!s->channel || (provider && !s->provider)) return fail(L, ERROR_OUTOFMEMORY, channel);
    size_t capacity = (s->provider ? wcslen(s->provider) : 0) + 512;
    s->xpath = calloc(capacity, sizeof(wchar_t));
    if (!s->xpath) return fail(L, ERROR_OUTOFMEMORY, channel);
    wcscpy(s->xpath, L"*[System[");
    int terms = 0;
    if (has_since) {
        ULARGE_INTEGER value;
        value.QuadPart = (uint64_t)ceill(((long double)since + 11644473600.0L) * 10000000.0L);
        FILETIME ft = { value.LowPart, value.HighPart };
        SYSTEMTIME st;
        if (!FileTimeToSystemTime(&ft, &st)) return fail(L, GetLastError(), channel);
        wchar_t condition[128];
        swprintf(condition, 128, L"TimeCreated[@SystemTime >= '%04u-%02u-%02uT%02u:%02u:%02u.%07luZ']",
                 (unsigned)st.wYear, (unsigned)st.wMonth, (unsigned)st.wDay, (unsigned)st.wHour,
                 (unsigned)st.wMinute, (unsigned)st.wSecond, (unsigned long)(value.QuadPart % 10000000));
        wcscat(s->xpath, condition);
        ++terms;
    }
    if (level >= 0) {
        if (terms++) wcscat(s->xpath, L" and ");
        wchar_t condition[32];
        if (level == 4) wcscpy(condition, L"(Level=0 or Level=4)");
        else swprintf(condition, 32, L"Level=%d", level);
        wcscat(s->xpath, condition);
    }
    if (s->provider) {
        if (terms++) wcscat(s->xpath, L" and ");
        const wchar_t *quote = wcschr(s->provider, L'\'') ? L"\"" : L"'";
        wcscat(s->xpath, L"Provider[@Name="); wcscat(s->xpath, quote);
        wcscat(s->xpath, s->provider); wcscat(s->xpath, quote); wcscat(s->xpath, L"]");
    }
    if (terms) wcscat(s->xpath, L"]]");
    else wcscpy(s->xpath, L"*");
    s->query = EvtQuery(NULL, s->channel, s->xpath, EvtQueryChannelPath | EvtQueryReverseDirection);
    if (!s->query) return fail(L, GetLastError(), channel);
    s->context = EvtCreateRenderContext(0, NULL, EvtRenderContextSystem);
    if (!s->context) return fail(L, GetLastError(), channel);
    lua_newtable(L);
    int total = 0;
    while (total < limit) {
        DWORD count = 0, want = (DWORD)(limit - total < 16 ? limit - total : 16);
        if (!EvtNext(s->query, want, s->events, INFINITE, 0, &count)) {
            DWORD error = GetLastError();
            if (error == ERROR_NO_MORE_ITEMS) break;
            return fail(L, error, channel);
        }
        for (DWORD i = 0; i < count; ++i) {
            DWORD error = render_values(s, s->events[i]);
            if (error) return fail(L, error, channel);
            const EVT_VARIANT *v = s->values;
            const wchar_t *event_provider = variant_string(&v[EvtSystemProviderName]);
            lua_createtable(L, 0, 7);
            lua_pushnumber(L, v[EvtSystemTimeCreated].Type == EvtVarTypeFileTime ?
                              (double)v[EvtSystemTimeCreated].FileTimeVal / 10000000.0 - 11644473600.0 : 0);
            lua_setfield(L, -2, "time");
            lua_pushstring(L, level_name(v[EvtSystemLevel].Type == EvtVarTypeByte ? v[EvtSystemLevel].ByteVal : 0));
            lua_setfield(L, -2, "level");
            lua_pushinteger(L, v[EvtSystemEventID].Type == EvtVarTypeUInt16 ? v[EvtSystemEventID].UInt16Val : 0);
            lua_setfield(L, -2, "id");
            push_wide(L, s, event_provider); lua_setfield(L, -2, "provider");
            lua_pushinteger(L, v[EvtSystemEventRecordId].Type == EvtVarTypeUInt64 ? (lua_Integer)v[EvtSystemEventRecordId].UInt64Val : 0);
            lua_setfield(L, -2, "record");
            push_wide(L, s, variant_string(&v[EvtSystemComputer])); lua_setfield(L, -2, "computer");
            error = render_message(s, s->events[i], event_provider);
            if (error) return fail(L, error, channel);
            push_wide(L, s, s->wide); lua_setfield(L, -2, "message");
            lua_rawseti(L, -2, ++total);
            EvtClose(s->events[i]); s->events[i] = NULL;
        }
    }
    return 1;
}

int ku_open_evt(lua_State *L)
{
    static const luaL_Reg functions[] = { {"logs", l_logs}, {"read", l_read}, {NULL, NULL} };
    luaL_newlib(L, functions);
    return 1;
}
