/*
 * net.c -- the `net` module: the network as seen from this machine.
 *
 *   net.resolve(name [, timeout])          -> { { address, family }, ... } | nil, err
 *   net.probe(address, port [, timeout])   -> true | nil, err          (the C half)
 *   net.listeners()                        -> { { port, address, family, pid, name }, ... }
 *   net.addresses()                        -> { { adapter, description, address, family,
 *                                                 prefix, up, loopback, mac }, ... }
 *
 * The Lua half (lua/net/probe.lua) wraps probe so that a host name is
 * resolved first and every address is tried in turn; it returns where the
 * connection succeeded and how long it took.
 *
 * Nothing here blocks the loop.  A resolution runs through GetAddrInfoExW
 * with a completion routine, which posts to the port from its system thread
 * (the one thing a foreign thread may do); a probe is a ConnectEx on an
 * overlapped socket attached to the port.  Both park the calling coroutine
 * on a waiter with a timeout; other tasks keep running.  A timed-out request
 * is cancelled and its memory freed when the cancellation completes, never
 * before, so the kernel never writes into freed memory.
 *
 * Errors are NET: resolve (no address for the name), refused, timeout,
 * unreachable, badvalue, oserror.
 */
#include "err.h"
#include "loop.h"
#include "ports.h"
#include "procinfo.h"
#include "state.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <iphlpapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KU_NET_DEFAULT_TIMEOUT_MS 5000

/* GetAddrInfoExCancel is in ws2_32 since Windows 8 but not in this toolchain's header. */
typedef INT(WSAAPI *cancel_fn)(LPHANDLE);
static cancel_fn resolve_cancel;

static const char *family_name(int family)
{
    return family == AF_INET6 ? "ipv6" : "ipv4";
}

/* The textual form of a socket address, or NULL for a family we do not speak. */
static const char *address_text(const struct sockaddr *sa, char *out, size_t cap)
{
    if (sa->sa_family == AF_INET) {
        return inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, out, cap);
    }
    if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)sa;
        if (inet_ntop(AF_INET6, &in6->sin6_addr, out, cap) == NULL) {
            return NULL;
        }
        if (in6->sin6_scope_id != 0) {
            size_t used = strlen(out);
            int n = snprintf(out + used, cap - used, "%%%lu", (unsigned long)in6->sin6_scope_id);
            if (n < 0 || (size_t)n >= cap - used) {
                return NULL;
            }
        }
        return out;
    }
    return NULL;
}

/* nil, NET <code> for a Winsock or Win32 error from connecting */
static int fail_connect(lua_State *L, DWORD error)
{
    switch (error) {
    case WSAECONNREFUSED:
    case ERROR_CONNECTION_REFUSED:
        return ku_err_fail(L, "NET", "refused", "connection refused");
    case WSAETIMEDOUT:
    case ERROR_SEM_TIMEOUT:
        return ku_err_fail(L, "NET", "timeout", "no answer within the timeout");
    case WSAEHOSTUNREACH:
    case WSAENETUNREACH:
    case WSAEADDRNOTAVAIL:
    case ERROR_HOST_UNREACHABLE:
    case ERROR_NETWORK_UNREACHABLE:
        return ku_err_fail(L, "NET", "unreachable", "no route to the address");
    default: {
        char *text = ku_win_error_message(error);
        int n = ku_err_fail(L, "NET", "oserror", "cannot connect: %s (error %lu)", text != NULL ? text : "",
                            (unsigned long)error);
        free(text);
        return n;
    }
    }
}

static void optional_timeout(lua_State *L, int idx, int64_t *ms, const char *what)
{
    *ms = KU_NET_DEFAULT_TIMEOUT_MS;
    if (!lua_isnoneornil(L, idx) && ku_check_duration(L, idx, ms) != 0) {
        ku_err_raise(L, "NET", "badvalue", "the %s timeout must be a duration such as \"2s\"", what);
    }
}

/* ---- resolve --------------------------------------------------------------------- */

typedef struct resolve_request {
    OVERLAPPED ov; /* first: the completion routine receives its address */
    ku_source src;
    ku_loop *loop;
    ku_waiter *waiter;
    HANDLE cancel;
    ADDRINFOEXW *result;
    volatile LONG error;
    char *name;
    wchar_t *wide;
} resolve_request;

static void resolve_free(resolve_request *r)
{
    if (r->result != NULL) {
        FreeAddrInfoExW(r->result);
    }
    free(r->name);
    free(r->wide);
    free(r);
}

/* On a system thread: record the outcome and hand it to the loop. */
static void CALLBACK resolve_done(DWORD error, DWORD bytes, LPWSAOVERLAPPED ov)
{
    resolve_request *r = (resolve_request *)ov;
    InterlockedExchange(&r->error, (LONG)error);
    ku_loop_post(r->loop, &r->src, r, bytes);
}

static int push_addresses(lua_State *L, resolve_request *r)
{
    DWORD error = (DWORD)r->error;
    if (error != 0) {
        if (error == WSAHOST_NOT_FOUND || error == WSANO_DATA || error == WSATRY_AGAIN || error == WSANO_RECOVERY) {
            return ku_err_fail(L, "NET", "resolve", "no address for '%s'", r->name);
        }
        if (error == WSA_E_CANCELLED) {
            return ku_err_fail(L, "NET", "timeout", "resolving '%s' timed out", r->name);
        }
        char *text = ku_win_error_message(error);
        int n = ku_err_fail(L, "NET", "oserror", "cannot resolve '%s': %s (error %lu)", r->name,
                            text != NULL ? text : "", (unsigned long)error);
        free(text);
        return n;
    }
    lua_newtable(L);
    lua_Integer n = 0;
    for (const ADDRINFOEXW *a = r->result; a != NULL; a = a->ai_next) {
        char text[64];
        if (a->ai_addr == NULL || address_text(a->ai_addr, text, sizeof text) == NULL) {
            continue;
        }
        lua_createtable(L, 0, 2);
        lua_pushstring(L, text);
        lua_setfield(L, -2, "address");
        lua_pushstring(L, family_name(a->ai_family));
        lua_setfield(L, -2, "family");
        lua_rawseti(L, -2, ++n);
    }
    if (n == 0) {
        lua_pop(L, 1);
        return ku_err_fail(L, "NET", "resolve", "no address for '%s'", r->name);
    }
    return 1;
}

static int resolve_push(lua_State *L, ku_waiter *w)
{
    if (w->timed_out) {
        return ku_err_fail(L, "NET", "timeout", "resolving timed out");
    }
    resolve_request *r = (resolve_request *)w->data;
    int n = push_addresses(L, r);
    resolve_free(r);
    return n;
}

/* The loop thread: the completion routine's packet. */
static void resolve_posted(ku_source *src, void *value, DWORD bytes)
{
    (void)value;
    (void)bytes;
    resolve_request *r = (resolve_request *)src->owner;
    ku_loop_received(r->loop);
    ku_waiter *w = r->waiter;
    r->waiter = NULL;
    if (w != NULL) {
        w->data = r;
        ku_wake(w);
    } else {
        resolve_free(r); /* the waiter timed out; the cancellation has completed */
    }
}

/* The waiter's timeout: cancel; the completion frees the request. */
static void resolve_timeout(ku_waiter *w)
{
    resolve_request *r = (resolve_request *)w->owner;
    r->waiter = NULL;
    if (resolve_cancel != NULL) {
        resolve_cancel(&r->cancel);
    }
}

/* net.resolve(name [, timeout]) */
static int l_net_resolve(lua_State *L)
{
    const char *name = ku_check_cstring(L, 1, "NET", "host name");
    int64_t timeout_ms = 0;
    optional_timeout(L, 2, &timeout_ms, "resolve");
    if (name[0] == '\0') {
        return ku_err_raise(L, "NET", "badvalue", "resolve needs a host name or address");
    }
    resolve_request *r = (resolve_request *)calloc(1, sizeof *r);
    if (r == NULL) {
        return ku_err_raise(L, "NET", "oserror", "out of memory");
    }
    r->loop = ku_loop_of(L);
    r->src.kind = KU_SRC_POSTED;
    r->src.owner = r;
    r->src.on_posted = resolve_posted;
    r->name = _strdup(name);
    r->wide = ku_utf8_to_wide(name);
    if (r->name == NULL || r->wide == NULL) {
        resolve_free(r);
        return ku_err_raise(L, "NET", "badvalue", "the name is not valid UTF-8");
    }
    ADDRINFOEXW hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    ku_loop_expect(r->loop);
    int ret = GetAddrInfoExW(r->wide, NULL, NS_ALL, NULL, &hints, &r->result, NULL, &r->ov, resolve_done, &r->cancel);
    if (ret != WSA_IO_PENDING) {
        /* finished on the spot: no completion routine will run */
        ku_loop_received(r->loop);
        r->error = ret == NO_ERROR ? 0 : (LONG)(ret == SOCKET_ERROR ? WSAGetLastError() : ret);
        int n = push_addresses(L, r);
        resolve_free(r);
        return n;
    }
    ku_waiter *w = ku_waiter_new(r->loop, r, resolve_push);
    if (w == NULL) {
        r->waiter = NULL; /* the completion will free the request */
        if (resolve_cancel != NULL) {
            resolve_cancel(&r->cancel);
        }
        return ku_err_raise(L, "NET", "oserror", "out of memory");
    }
    w->on_timeout = resolve_timeout;
    r->waiter = w;
    return ku_wait(L, w, timeout_ms);
}

/* ---- probe: one literal address -------------------------------------------------- */

typedef struct probe_request {
    ku_source src;
    ku_loop *loop;
    ku_waiter *waiter;
    ku_io *io;
    SOCKET s;
} probe_request;

static LPFN_CONNECTEX connect_ex(SOCKET s)
{
    static LPFN_CONNECTEX fn;
    if (fn == NULL) {
        GUID guid = WSAID_CONNECTEX;
        LPFN_CONNECTEX found = NULL;
        DWORD bytes = 0;
        if (WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER, &guid, sizeof guid, &found, sizeof found, &bytes, NULL,
                     NULL) == 0) {
            fn = found;
        }
    }
    return fn;
}

static void probe_finish(probe_request *q)
{
    if (q->s != INVALID_SOCKET) {
        closesocket(q->s);
    }
    free(q);
}

/* The loop thread: the connection completed, failed, or was cancelled. */
static void probe_on_io(ku_source *src, ku_io *io, DWORD bytes, DWORD error)
{
    (void)bytes;
    probe_request *q = (probe_request *)src->owner;
    DWORD outcome = 0;
    if (error != 0) {
        DWORD transferred = 0, flags = 0;
        outcome = error;
        if (!WSAGetOverlappedResult(q->s, &io->ov, &transferred, FALSE, &flags)) {
            DWORD wsa = (DWORD)WSAGetLastError();
            if (wsa != 0) {
                outcome = wsa;
            }
        }
    }
    ku_io_free(io);
    q->io = NULL;
    ku_waiter *w = q->waiter;
    q->waiter = NULL;
    probe_finish(q);
    if (w != NULL) {
        w->data = (void *)(uintptr_t)outcome;
        ku_wake(w);
    }
}

/* The waiter's timeout: cancel the connect; the completion frees the request. */
static void probe_timeout(ku_waiter *w)
{
    probe_request *q = (probe_request *)w->owner;
    q->waiter = NULL;
    CancelIoEx((HANDLE)q->s, &q->io->ov);
}

static int probe_push(lua_State *L, ku_waiter *w)
{
    if (w->timed_out) {
        return ku_err_fail(L, "NET", "timeout", "no answer within the timeout");
    }
    DWORD outcome = (DWORD)(uintptr_t)w->data;
    if (outcome == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return fail_connect(L, outcome);
}

/* inet_pton parses the address only.  A numeric scope identifies the
 * interface for link-local IPv6 and must reach ConnectEx unchanged. */
static int parse_ipv6(const char *text, struct sockaddr_in6 *in6)
{
    const char *percent = strchr(text, '%');
    char address[INET6_ADDRSTRLEN];
    if (percent == NULL) {
        return inet_pton(AF_INET6, text, &in6->sin6_addr) == 1;
    }
    size_t n = (size_t)(percent - text);
    if (n == 0 || n >= sizeof address || percent[1] == '\0') {
        return 0;
    }
    memcpy(address, text, n);
    address[n] = '\0';
    uint64_t scope = 0;
    for (const char *p = percent + 1; *p != '\0'; p++) {
        if (*p < '0' || *p > '9') {
            return 0;
        }
        scope = scope * 10 + (unsigned)(*p - '0');
        if (scope > UINT32_MAX) {
            return 0;
        }
    }
    if (inet_pton(AF_INET6, address, &in6->sin6_addr) != 1) {
        return 0;
    }
    in6->sin6_scope_id = (ULONG)scope;
    return 1;
}

/* net.probe(address, port [, timeout]) -- the C half; lua/net/probe.lua resolves names */
static int l_net_probe(lua_State *L)
{
    const char *address = ku_check_cstring(L, 1, "NET", "address");
    lua_Integer port = luaL_checkinteger(L, 2);
    if (port < 1 || port > 65535) {
        return ku_err_raise(L, "NET", "badvalue", "the port must be 1 to 65535");
    }
    int64_t timeout_ms = 0;
    optional_timeout(L, 3, &timeout_ms, "probe");
    struct sockaddr_storage target, local;
    memset(&target, 0, sizeof target);
    memset(&local, 0, sizeof local);
    int length = 0;
    struct sockaddr_in *in4 = (struct sockaddr_in *)&target;
    struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)&target;
    if (inet_pton(AF_INET, address, &in4->sin_addr) == 1) {
        in4->sin_family = AF_INET;
        in4->sin_port = htons((unsigned short)port);
        ((struct sockaddr_in *)&local)->sin_family = AF_INET;
        length = sizeof *in4;
    } else if (parse_ipv6(address, in6)) {
        in6->sin6_family = AF_INET6;
        in6->sin6_port = htons((unsigned short)port);
        ((struct sockaddr_in6 *)&local)->sin6_family = AF_INET6;
        length = sizeof *in6;
    } else {
        return ku_err_raise(L, "NET", "badvalue", "'%s' is not an IP address", address);
    }
    probe_request *q = (probe_request *)calloc(1, sizeof *q);
    if (q == NULL) {
        return ku_err_raise(L, "NET", "oserror", "out of memory");
    }
    q->loop = ku_loop_of(L);
    q->src.kind = KU_SRC_IO;
    q->src.owner = q;
    q->src.on_io = probe_on_io;
    q->s = WSASocketW(target.ss_family, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    if (q->s == INVALID_SOCKET) {
        DWORD error = (DWORD)WSAGetLastError();
        probe_finish(q);
        return fail_connect(L, error);
    }
    LPFN_CONNECTEX connect = connect_ex(q->s);
    if (connect == NULL || bind(q->s, (const struct sockaddr *)&local, length) != 0 ||
        ku_loop_attach(q->loop, (HANDLE)q->s, &q->src) != 0) {
        DWORD error = (DWORD)WSAGetLastError();
        probe_finish(q);
        return fail_connect(L, error != 0 ? error : ERROR_GEN_FAILURE);
    }
    q->io = ku_io_new(q->loop, &q->src, (HANDLE)q->s, 0);
    if (q->io == NULL) {
        probe_finish(q);
        return ku_err_raise(L, "NET", "oserror", "out of memory");
    }
    if (!connect(q->s, (const struct sockaddr *)&target, length, NULL, 0, NULL, &q->io->ov)) {
        DWORD error = (DWORD)WSAGetLastError();
        if (error != WSA_IO_PENDING) {
            ku_io_free(q->io);
            probe_finish(q);
            return fail_connect(L, error);
        }
    }
    ku_io_posted(q->io);
    ku_waiter *w = ku_waiter_new(q->loop, q, probe_push);
    if (w == NULL) {
        CancelIoEx((HANDLE)q->s, &q->io->ov); /* the completion frees the request */
        return ku_err_raise(L, "NET", "oserror", "out of memory");
    }
    w->on_timeout = probe_timeout;
    q->waiter = w;
    return ku_wait(L, w, timeout_ms);
}

/* ---- listeners ------------------------------------------------------------------- */

static int compare_listener(const void *a, const void *b)
{
    const ku_listener *x = (const ku_listener *)a, *y = (const ku_listener *)b;
    if (x->port != y->port) {
        return x->port < y->port ? -1 : 1;
    }
    if (x->ipv6 != y->ipv6) {
        return x->ipv6 < y->ipv6 ? -1 : 1;
    }
    return strcmp(x->address, y->address);
}

/* net.listeners() */
static int l_net_listeners(lua_State *L)
{
    ku_listener *list = NULL;
    size_t count = 0;
    if (ku_tcp_listeners(&list, &count) != 0) {
        return ku_err_raise(L, "NET", "oserror", "cannot read the TCP tables");
    }
    qsort(list, count, sizeof *list, compare_listener);
    size_t process_count = 0;
    ku_pentry *processes = ku_proc_snapshot(&process_count); /* NULL: names stay absent */
    lua_createtable(L, (int)count, 0);
    for (size_t i = 0; i < count; i++) {
        lua_createtable(L, 0, 5);
        lua_pushinteger(L, list[i].port);
        lua_setfield(L, -2, "port");
        lua_pushstring(L, list[i].address);
        lua_setfield(L, -2, "address");
        lua_pushstring(L, list[i].ipv6 ? "ipv6" : "ipv4");
        lua_setfield(L, -2, "family");
        lua_pushinteger(L, (lua_Integer)list[i].pid);
        lua_setfield(L, -2, "pid");
        const ku_pentry *p = processes != NULL ? ku_proc_lookup(processes, process_count, list[i].pid) : NULL;
        if (p != NULL) {
            char *name = ku_wide_to_utf8(p->name, -1);
            if (name != NULL) {
                lua_pushstring(L, name);
                lua_setfield(L, -2, "name");
                free(name);
            }
        }
        lua_rawseti(L, -2, (lua_Integer)i + 1);
    }
    free(processes);
    free(list);
    return 1;
}

/* ---- addresses ------------------------------------------------------------------- */

/* net.addresses() */
static int l_net_addresses(lua_State *L)
{
    ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
    ULONG size = 16384;
    IP_ADAPTER_ADDRESSES *adapters = NULL;
    for (int attempt = 0;; attempt++) {
        adapters = (IP_ADAPTER_ADDRESSES *)malloc(size);
        if (adapters == NULL) {
            return ku_err_raise(L, "NET", "oserror", "out of memory");
        }
        ULONG ret = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, adapters, &size);
        if (ret == NO_ERROR) {
            break;
        }
        free(adapters);
        adapters = NULL;
        if (ret != ERROR_BUFFER_OVERFLOW || attempt == 3) {
            char *text = ku_win_error_message(ret);
            int n = ku_err_raise(L, "NET", "oserror", "cannot list the adapters: %s", text != NULL ? text : "");
            free(text);
            return n;
        }
        /* `size` now says how much; go round */
    }
    lua_newtable(L);
    lua_Integer n = 0;
    for (const IP_ADAPTER_ADDRESSES *a = adapters; a != NULL; a = a->Next) {
        char *friendly = ku_wide_to_utf8(a->FriendlyName, -1);
        char *description = ku_wide_to_utf8(a->Description, -1);
        char mac[32] = "";
        if (a->PhysicalAddressLength == 6) {
            snprintf(mac, sizeof mac, "%02x:%02x:%02x:%02x:%02x:%02x", a->PhysicalAddress[0], a->PhysicalAddress[1],
                     a->PhysicalAddress[2], a->PhysicalAddress[3], a->PhysicalAddress[4], a->PhysicalAddress[5]);
        }
        for (const IP_ADAPTER_UNICAST_ADDRESS *u = a->FirstUnicastAddress; u != NULL; u = u->Next) {
            char text[64];
            if (u->Address.lpSockaddr == NULL || address_text(u->Address.lpSockaddr, text, sizeof text) == NULL) {
                continue;
            }
            lua_createtable(L, 0, 8);
            lua_pushstring(L, friendly != NULL ? friendly : "");
            lua_setfield(L, -2, "adapter");
            lua_pushstring(L, description != NULL ? description : "");
            lua_setfield(L, -2, "description");
            lua_pushstring(L, text);
            lua_setfield(L, -2, "address");
            lua_pushstring(L, family_name(u->Address.lpSockaddr->sa_family));
            lua_setfield(L, -2, "family");
            lua_pushinteger(L, u->OnLinkPrefixLength);
            lua_setfield(L, -2, "prefix");
            lua_pushboolean(L, a->OperStatus == IfOperStatusUp);
            lua_setfield(L, -2, "up");
            lua_pushboolean(L, a->IfType == IF_TYPE_SOFTWARE_LOOPBACK);
            lua_setfield(L, -2, "loopback");
            if (mac[0] != '\0') {
                lua_pushstring(L, mac);
                lua_setfield(L, -2, "mac");
            }
            lua_rawseti(L, -2, ++n);
        }
        free(friendly);
        free(description);
    }
    free(adapters);
    return 1;
}

int ku_open_net(lua_State *L)
{
    static int started;
    if (!started) {
        WSADATA data;
        int ret = WSAStartup(MAKEWORD(2, 2), &data);
        if (ret != 0) {
            return ku_err_raise(L, "NET", "oserror", "Winsock does not start (error %d)", ret);
        }
        started = 1;
        HMODULE ws2 = GetModuleHandleW(L"ws2_32.dll");
        if (ws2 != NULL) {
            resolve_cancel = (cancel_fn)(void (*)(void))GetProcAddress(ws2, "GetAddrInfoExCancel");
        }
    }
    static const luaL_Reg functions[] = {
        {"resolve", l_net_resolve},
        {"probe", l_net_probe},
        {"listeners", l_net_listeners},
        {"addresses", l_net_addresses},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
