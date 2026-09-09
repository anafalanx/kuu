/*
 * http.c -- the `http` module on WinHTTP: fetch and post, correctly, with the
 * machine's proxy and certificate store and nothing vendored.
 *
 *   local r, e = http.get("https://host/x.zip", { to = ".tools/x.zip", timeout = "5m" })
 *   local r, e = http.post(url, body, { type = "application/json" })
 *   local r, e = http.request { method = "PUT", url = url, body = bytes, headers = {...} }
 *   -- r = { status = 200, headers = { ["content-type"] = "..." }, rawheaders = "...",
 *   --       body = bytes (or "" when `to` was given), bytes = n, path = to }
 *   -- e: HTTP badvalue | notfound | connect | timeout | tls | toobig | oserror; usage raised
 *
 * Each request runs WinHTTP's synchronous API on its own worker thread, which
 * touches nothing of Lua and, when done, posts one packet to the loop.  So a
 * slow download stalls no timer and no other task.  Defaults: 30 s per WinHTTP
 * phase, 64 MiB of body in memory (8 GiB when streaming to a file), redirects
 * followed except from HTTPS down to HTTP, transparent gzip and deflate.
 * There is no insecure option of any kind: such flags are eventually left on
 * in something that matters.  HTTP status codes are results, never errors.
 */
#include "err.h"
#include "fspath.h"
#include "loop.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#include <winhttp.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KU_HTTP_DEFAULT_TIMEOUT_MS 30000
#define KU_HTTP_DEFAULT_MAXBODY ((size_t)64 * 1024 * 1024)
#define KU_HTTP_DEFAULT_MAXFILE ((size_t)8 * 1024 * 1024 * 1024)
#define KU_HTTP_CHUNK 65536

typedef struct http_request {
    ku_source src;
    ku_loop *loop;
    ku_waiter *waiter;
    HANDLE thread;
    /* The deadline is kuu's own: a loop timer that closes the request handle
     * from the loop thread, which cancels the worker's blocking call.  WinHTTP's
     * own receive timers were measured not to fire against a server that has
     * accepted but not answered, so they are set but not relied upon. */
    ku_timer deadline;
    volatile PVOID cancel_handle; /* the live request handle, or NULL */
    volatile LONG timed_out;
    /* inputs, owned here, read by the worker */
    wchar_t *method, *host, *path, *headers, *url;
    INTERNET_PORT port;
    int secure;
    unsigned char *body;
    size_t body_len;
    DWORD timeout_ms;
    size_t maxbody;
    int redirect_none;
    HANDLE file;        /* streaming target, or NULL */
    wchar_t *temp_path; /* the file's temporary name */
    char *to_utf8;      /* the final path, for the result */
    /* outputs, written by the worker, read after the packet */
    int failed;
    const char *code;
    char message[512];
    DWORD status;
    char *rawheaders;
    unsigned char *data;
    size_t data_len, data_cap;
    size_t total;
    /* `sha256` given: the body is hashed as it arrives and must match */
    int want_hash;
    unsigned char expected[32];
    HINTERNET session; /* the process-wide session; the worker never closes it */
} http_request;

/* One WinHTTP session for the whole process, as WinHTTP intends.  A session
 * per request was measured to leave roughly one handle behind per request,
 * inside WinHTTP, never reclaimed; one shared session stays flat.  Made on
 * the loop thread at first use; workers only open connections under it. */
static HINTERNET shared_session;

static HINTERNET session_get(void)
{
    if (shared_session == NULL) {
        shared_session = WinHttpOpen(L"kuu/" KUU_VERSION_W, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                                     WINHTTP_NO_PROXY_BYPASS, 0);
        if (shared_session != NULL) {
            DWORD protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
            WinHttpSetOption(shared_session, WINHTTP_OPTION_SECURE_PROTOCOLS, &protocols, sizeof protocols);
        }
    }
    return shared_session;
}

/* ---- the worker ------------------------------------------------------------------ */

static void worker_fail(http_request *q, const char *code, const char *what, DWORD error)
{
    q->failed = 1;
    if (q->timed_out) {
        q->code = "timeout";
        snprintf(q->message, sizeof q->message, "the request did not complete within %lu ms",
                 (unsigned long)q->timeout_ms);
        return;
    }
    q->code = code;
    char *text = ku_win_error_message(error);
    snprintf(q->message, sizeof q->message, "%s: %s (error %lu)", what, text != NULL ? text : "", (unsigned long)error);
    free(text);
}

/* Take the request handle away from whoever else might close it. */
static HINTERNET take_request(http_request *q)
{
    return (HINTERNET)InterlockedExchangePointer(&q->cancel_handle, NULL);
}

static const char *code_for(DWORD error)
{
    switch (error) {
    case ERROR_WINHTTP_TIMEOUT:
        return "timeout";
    case ERROR_WINHTTP_NAME_NOT_RESOLVED:
        return "notfound";
    case ERROR_WINHTTP_CANNOT_CONNECT:
    case ERROR_WINHTTP_CONNECTION_ERROR:
        return "connect";
    case ERROR_WINHTTP_SECURE_FAILURE:
    case ERROR_WINHTTP_SECURE_CERT_CN_INVALID:
    case ERROR_WINHTTP_SECURE_CERT_DATE_INVALID:
    case ERROR_WINHTTP_SECURE_INVALID_CA:
    case ERROR_WINHTTP_SECURE_INVALID_CERT:
    case ERROR_WINHTTP_SECURE_CERT_REV_FAILED:
    case ERROR_WINHTTP_SECURE_CERT_REVOKED:
    case ERROR_WINHTTP_SECURE_CERT_WRONG_USAGE:
    case ERROR_WINHTTP_SECURE_CHANNEL_ERROR:
    case ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED:
        return "tls";
    case ERROR_WINHTTP_INVALID_URL:
    case ERROR_WINHTTP_UNRECOGNIZED_SCHEME:
        return "badvalue";
    default:
        return "oserror";
    }
}

static int append_data(http_request *q, const unsigned char *bytes, DWORD n)
{
    if (q->file != NULL) {
        DWORD done = 0;
        while (done < n) {
            DWORD written = 0;
            if (!WriteFile(q->file, bytes + done, n - done, &written, NULL)) {
                worker_fail(q, "oserror", "cannot write the download", GetLastError());
                return -1;
            }
            done += written;
        }
        return 0;
    }
    if (q->data_len + n > q->data_cap) {
        size_t cap = q->data_cap ? q->data_cap : 65536;
        while (cap < q->data_len + n) {
            cap *= 2;
        }
        unsigned char *grown = (unsigned char *)realloc(q->data, cap);
        if (grown == NULL) {
            q->failed = 1;
            q->code = "oserror";
            snprintf(q->message, sizeof q->message, "out of memory receiving the body");
            return -1;
        }
        q->data = grown;
        q->data_cap = cap;
    }
    memcpy(q->data + q->data_len, bytes, n);
    q->data_len += n;
    return 0;
}

static int parse_hex(const char *text, size_t length, unsigned char *out, size_t out_len)
{
    if (length != out_len * 2) {
        return -1;
    }
    for (size_t i = 0; i < out_len; i++) {
        unsigned value = 0;
        for (int k = 0; k < 2; k++) {
            char c = text[i * 2 + k];
            unsigned digit;
            if (c >= '0' && c <= '9') {
                digit = (unsigned)(c - '0');
            } else if (c >= 'a' && c <= 'f') {
                digit = (unsigned)(c - 'a' + 10);
            } else if (c >= 'A' && c <= 'F') {
                digit = (unsigned)(c - 'A' + 10);
            } else {
                return -1;
            }
            value = value * 16 + digit;
        }
        out[i] = (unsigned char)value;
    }
    return 0;
}

static void hex_of(const unsigned char *bytes, size_t n, char *out)
{
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[i * 2] = digits[bytes[i] >> 4];
        out[i * 2 + 1] = digits[bytes[i] & 15];
    }
    out[n * 2] = '\0';
}

static DWORD WINAPI http_worker(LPVOID arg)
{
    http_request *q = (http_request *)arg;
    HINTERNET session = NULL, connection = NULL, request = NULL;
    unsigned char *chunk = NULL;
    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;

    session = q->session; /* the process-wide session; not ours to close */
    DWORD response_timeout = q->timeout_ms;
    connection = WinHttpConnect(session, q->host, q->port, 0);
    if (connection == NULL) {
        worker_fail(q, code_for(GetLastError()), "cannot connect", GetLastError());
        goto done;
    }
    request = WinHttpOpenRequest(connection, q->method, q->path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 q->secure ? WINHTTP_FLAG_SECURE : 0);
    if (request == NULL) {
        worker_fail(q, code_for(GetLastError()), "cannot open the request", GetLastError());
        goto done;
    }
    /* Every phase gets the timeout, on the request since the session is
     * shared; the response-header wait has its own setting below that
     * WinHttpSetTimeouts does not cover. */
    int t = (int)q->timeout_ms;
    WinHttpSetTimeouts(request, t, t, t, t);
    /* Requests are independent: the shared session must not carry cookies
     * from one to the next.  A caller who wants a cookie sends the header. */
    DWORD no_cookies = WINHTTP_DISABLE_COOKIES;
    WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &no_cookies, sizeof no_cookies);
    /* Publish the handle so the loop's deadline can cancel us; if the deadline
     * already passed, it is our job to notice. */
    InterlockedExchangePointer(&q->cancel_handle, request);
    if (q->timed_out) {
        worker_fail(q, "timeout", "", 0);
        goto done;
    }
    /* Redirects: followed, but never from HTTPS down to HTTP; or not at all. */
    DWORD policy = q->redirect_none ? WINHTTP_OPTION_REDIRECT_POLICY_NEVER
                                    : WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP;
    WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &policy, sizeof policy);
    DWORD decompression = WINHTTP_DECOMPRESSION_FLAG_ALL;
    WinHttpSetOption(request, WINHTTP_OPTION_DECOMPRESSION, &decompression, sizeof decompression);
    WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_RESPONSE_TIMEOUT, &response_timeout, sizeof response_timeout);

    if (!WinHttpSendRequest(request, q->headers != NULL ? q->headers : WINHTTP_NO_ADDITIONAL_HEADERS,
                            q->headers != NULL ? (DWORD)-1 : 0, q->body_len > 0 ? q->body : WINHTTP_NO_REQUEST_DATA,
                            (DWORD)q->body_len, (DWORD)q->body_len, 0)) {
        worker_fail(q, code_for(GetLastError()), "the request failed", GetLastError());
        goto done;
    }
    if (!WinHttpReceiveResponse(request, NULL)) {
        worker_fail(q, code_for(GetLastError()), "no response", GetLastError());
        goto done;
    }
    DWORD status = 0, size = sizeof status;
    if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                             &status, &size, WINHTTP_NO_HEADER_INDEX)) {
        worker_fail(q, "oserror", "cannot read the status", GetLastError());
        goto done;
    }
    q->status = status;
    if (q->want_hash && (status < 200 || status >= 300)) {
        /* Specific bytes were asked for; anything but success is a failure. */
        q->failed = 1;
        q->code = "status";
        snprintf(q->message, sizeof q->message, "the server answered %lu to a request for a verified body",
                 (unsigned long)status);
        goto done;
    }
    DWORD raw_size = 0;
    WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, NULL, &raw_size,
                        WINHTTP_NO_HEADER_INDEX);
    if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && raw_size > 0) {
        wchar_t *raw = (wchar_t *)malloc(raw_size + sizeof(wchar_t));
        if (raw != NULL) {
            if (WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, raw, &raw_size,
                                    WINHTTP_NO_HEADER_INDEX)) {
                q->rawheaders = ku_wide_to_utf8(raw, (int)(raw_size / sizeof(wchar_t)));
            }
            free(raw);
        }
    }
    chunk = (unsigned char *)malloc(KU_HTTP_CHUNK);
    if (chunk == NULL) {
        q->failed = 1;
        q->code = "oserror";
        snprintf(q->message, sizeof q->message, "out of memory");
        goto done;
    }
    if (q->want_hash) {
        if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) != 0 ||
            BCryptCreateHash(alg, &hash, NULL, 0, NULL, 0, 0) != 0) {
            worker_fail(q, "oserror", "cannot start the SHA-256 check", 0);
            goto done;
        }
    }
    for (;;) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request, &available)) {
            worker_fail(q, code_for(GetLastError()), "the body stopped", GetLastError());
            goto done;
        }
        if (available == 0) {
            break; /* the whole body has arrived */
        }
        DWORD want = available > KU_HTTP_CHUNK ? KU_HTTP_CHUNK : available;
        DWORD got = 0;
        if (!WinHttpReadData(request, chunk, want, &got)) {
            worker_fail(q, code_for(GetLastError()), "the body stopped", GetLastError());
            goto done;
        }
        if (got == 0) {
            break;
        }
        if (q->total + got > q->maxbody) {
            /* Refused, not truncated: a short body that looks whole is the
             * one answer never given. */
            q->failed = 1;
            q->code = "toobig";
            snprintf(q->message, sizeof q->message, "the body exceeds the %llu byte limit",
                     (unsigned long long)q->maxbody);
            goto done;
        }
        q->total += got;
        if (append_data(q, chunk, got) != 0) {
            goto done;
        }
        if (hash != NULL && BCryptHashData(hash, chunk, got, 0) != 0) {
            worker_fail(q, "oserror", "the SHA-256 check failed", 0);
            goto done;
        }
    }
    if (hash != NULL) {
        unsigned char digest[32];
        if (BCryptFinishHash(hash, digest, sizeof digest, 0) != 0) {
            worker_fail(q, "oserror", "the SHA-256 check failed", 0);
            goto done;
        }
        if (memcmp(digest, q->expected, sizeof digest) != 0) {
            char have[65], want[65];
            hex_of(digest, sizeof digest, have);
            hex_of(q->expected, sizeof q->expected, want);
            q->failed = 1;
            q->code = "mismatch";
            snprintf(q->message, sizeof q->message, "the body hashes to %s, expected %s", have, want);
            goto done;
        }
    }
    if (q->file != NULL && !FlushFileBuffers(q->file)) {
        worker_fail(q, "oserror", "cannot flush the download", GetLastError());
    }

done:
    free(chunk);
    if (hash != NULL) {
        BCryptDestroyHash(hash);
    }
    if (alg != NULL) {
        BCryptCloseAlgorithmProvider(alg, 0);
    }
    if (q->file != NULL) {
        CloseHandle(q->file);
        q->file = NULL;
    }
    if (request != NULL) {
        HINTERNET mine = take_request(q); /* NULL when the deadline closed it */
        if (mine != NULL) {
            WinHttpCloseHandle(mine);
        }
    }
    if (connection != NULL) {
        WinHttpCloseHandle(connection);
    }
    ku_loop_post(q->loop, &q->src, q, 0);
    return 0;
}

/* ---- the loop side -------------------------------------------------------------- */

static void request_free(http_request *q)
{
    if (q->thread != NULL) {
        CloseHandle(q->thread);
    }
    free(q->method);
    free(q->host);
    free(q->path);
    free(q->headers);
    free(q->url);
    free(q->body);
    free(q->temp_path);
    free(q->to_utf8);
    free(q->rawheaders);
    free(q->data);
    free(q);
}

/* The deadline fired on the loop thread: cancel the worker's blocking call. */
static void http_deadline(ku_timer *timer)
{
    http_request *q = (http_request *)timer->owner;
    InterlockedExchange(&q->timed_out, 1);
    HINTERNET h = take_request(q);
    if (h != NULL) {
        WinHttpCloseHandle(h);
    }
}

static void http_on_posted(ku_source *src, void *value, DWORD bytes)
{
    (void)value;
    (void)bytes;
    http_request *q = (http_request *)src->owner;
    ku_loop_received(q->loop);
    ku_timer_cancel(q->loop, &q->deadline);
    ku_waiter *w = q->waiter;
    q->waiter = NULL;
    if (w != NULL) {
        w->data = q;
        ku_wake(w);
    } else {
        request_free(q); /* nobody is waiting any more */
    }
}

/* Cooked headers: lowercase names, repeats joined with ", " as RFC 9110
 * allows; the raw block stays beside them because Set-Cookie repeats. */
static void push_headers(lua_State *L, const char *raw)
{
    lua_newtable(L);
    if (raw == NULL) {
        return;
    }
    const char *line = strstr(raw, "\r\n"); /* skip the status line */
    line = line != NULL ? line + 2 : raw;
    while (*line != '\0') {
        const char *end = strstr(line, "\r\n");
        size_t length = end != NULL ? (size_t)(end - line) : strlen(line);
        const char *colon = memchr(line, ':', length);
        if (colon != NULL && colon != line) {
            size_t name_length = (size_t)(colon - line);
            char *name = (char *)malloc(name_length + 1);
            if (name != NULL) {
                for (size_t i = 0; i < name_length; i++) {
                    char c = line[i];
                    name[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
                }
                name[name_length] = '\0';
                const char *value = colon + 1;
                size_t value_length = length - name_length - 1;
                while (value_length > 0 && (*value == ' ' || *value == '\t')) {
                    value++;
                    value_length--;
                }
                lua_getfield(L, -1, name);
                if (lua_isnil(L, -1)) {
                    lua_pop(L, 1);
                    lua_pushlstring(L, value, value_length);
                } else {
                    lua_pushliteral(L, ", ");
                    lua_pushlstring(L, value, value_length);
                    lua_concat(L, 3);
                }
                lua_setfield(L, -2, name);
                free(name);
            }
        }
        if (end == NULL) {
            break;
        }
        line = end + 2;
    }
}

static int request_push(lua_State *L, ku_waiter *w)
{
    http_request *q = (http_request *)w->data;
    if (q->failed) {
        if (q->temp_path != NULL) {
            DeleteFileW(q->temp_path); /* no partial download is left behind */
        }
        int n = ku_err_fail(L, "HTTP", q->code, "%s", q->message);
        request_free(q);
        return n;
    }
    if (q->temp_path != NULL) {
        ku_wpath final;
        ku_fail fail;
        if (ku_wpath_make(q->to_utf8, &final, &fail) != 0 ||
            !MoveFileExW(q->temp_path, final.text, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            DWORD error = GetLastError();
            DeleteFileW(q->temp_path);
            ku_wpath_free(&final);
            char *text = ku_win_error_message(error);
            int n = ku_err_fail(L, "HTTP", "oserror", "cannot place the download at '%s': %s", q->to_utf8,
                                text != NULL ? text : "");
            free(text);
            request_free(q);
            return n;
        }
        ku_wpath_free(&final);
    }
    lua_createtable(L, 0, 6);
    lua_pushinteger(L, (lua_Integer)q->status);
    lua_setfield(L, -2, "status");
    push_headers(L, q->rawheaders);
    lua_setfield(L, -2, "headers");
    lua_pushstring(L, q->rawheaders != NULL ? q->rawheaders : "");
    lua_setfield(L, -2, "rawheaders");
    lua_pushlstring(L, (const char *)(q->data != NULL ? q->data : (const unsigned char *)""), q->data_len);
    lua_setfield(L, -2, "body");
    lua_pushinteger(L, (lua_Integer)q->total);
    lua_setfield(L, -2, "bytes");
    if (q->to_utf8 != NULL) {
        lua_pushstring(L, q->to_utf8);
        lua_setfield(L, -2, "path");
    }
    request_free(q);
    return 1;
}

/* ---- building a request from Lua ------------------------------------------------- */

static int has_control(const char *s, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c < 0x20 || c == 0x7f) {
            return 1;
        }
    }
    return 0;
}

static wchar_t *wide_or_raise(lua_State *L, const char *utf8, const char *what)
{
    wchar_t *w = ku_utf8_to_wide(utf8);
    if (w == NULL) {
        ku_err_raise(L, "HTTP", "encoding", "%s is not valid UTF-8", what);
    }
    return w;
}

/* The request table: method, url, body, headers, type, timeout, maxbody,
 * redirect, to.  Raises HTTP usage | badvalue for mistakes. */
static int build_request(lua_State *L, int idx)
{
    static const char *const known[] = {"method", "url", "body", "headers", "type", "timeout", "maxbody", "redirect",
                                        "to", "sha256", NULL};
    luaL_checktype(L, idx, LUA_TTABLE);
    lua_pushnil(L);
    while (lua_next(L, idx) != 0) {
        lua_pop(L, 1);
        const char *key = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : "?";
        int ok = 0;
        for (int i = 0; known[i] != NULL; i++) {
            if (strcmp(key, known[i]) == 0) {
                ok = 1;
            }
        }
        if (!ok) {
            return ku_err_raise(L, "HTTP", "usage", "unknown option '%s'", key);
        }
    }
    http_request *q = (http_request *)calloc(1, sizeof *q);
    if (q == NULL) {
        return ku_err_raise(L, "HTTP", "oserror", "out of memory");
    }
    q->loop = ku_loop_of(L);
    q->src.kind = KU_SRC_POSTED;
    q->src.owner = q;
    q->src.on_posted = http_on_posted;
    q->timeout_ms = KU_HTTP_DEFAULT_TIMEOUT_MS;

    lua_getfield(L, idx, "method");
    const char *method = luaL_optstring(L, -1, "GET");
    if (strcmp(method, "GET") != 0 && strcmp(method, "POST") != 0 && strcmp(method, "PUT") != 0 &&
        strcmp(method, "DELETE") != 0 && strcmp(method, "HEAD") != 0 && strcmp(method, "PATCH") != 0) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "badvalue", "method must be GET, POST, PUT, DELETE, HEAD, or PATCH");
    }
    q->method = ku_utf8_to_wide(method);
    lua_pop(L, 1);

    lua_getfield(L, idx, "url");
    if (lua_type(L, -1) != LUA_TSTRING) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "usage", "a url is required");
    }
    size_t url_length = 0;
    const char *url = lua_tolstring(L, -1, &url_length);
    if (strlen(url) != url_length || has_control(url, url_length) || memchr(url, ' ', url_length) != NULL) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "badvalue", "the url contains a space, a control character, or NUL");
    }
    q->url = wide_or_raise(L, url, "the url");
    lua_pop(L, 1);
    /* The OS parser cracks the URL: a URL splitter is a security boundary, and
     * the host is what the certificate is checked against. */
    URL_COMPONENTS parts;
    memset(&parts, 0, sizeof parts);
    parts.dwStructSize = sizeof parts;
    parts.dwSchemeLength = (DWORD)-1;
    parts.dwHostNameLength = (DWORD)-1;
    parts.dwUrlPathLength = (DWORD)-1;
    parts.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(q->url, 0, 0, &parts)) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "badvalue", "'%s' is not a valid http or https url", url);
    }
    if (parts.nScheme != INTERNET_SCHEME_HTTP && parts.nScheme != INTERNET_SCHEME_HTTPS) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "badvalue", "only http and https urls are supported");
    }
    if (parts.dwHostNameLength == 0) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "badvalue", "the url has no host");
    }
    q->secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
    q->port = parts.nPort;
    q->host = (wchar_t *)malloc(((size_t)parts.dwHostNameLength + 1) * sizeof(wchar_t));
    if (q->host != NULL) {
        memcpy(q->host, parts.lpszHostName, parts.dwHostNameLength * sizeof(wchar_t));
        q->host[parts.dwHostNameLength] = L'\0';
    }
    /* Path plus query; a fragment is client-side and never sent. */
    size_t path_units = parts.dwUrlPathLength;
    const wchar_t *extra = parts.lpszExtraInfo;
    size_t extra_units = 0;
    if (extra != NULL) {
        for (size_t i = 0; i < parts.dwExtraInfoLength && extra[i] != L'#'; i++) {
            extra_units++;
        }
    }
    q->path = (wchar_t *)malloc((path_units + extra_units + 2) * sizeof(wchar_t));
    if (q->host == NULL || q->path == NULL || q->method == NULL) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "oserror", "out of memory");
    }
    if (path_units == 0) {
        q->path[0] = L'/';
        path_units = 1;
    } else {
        memcpy(q->path, parts.lpszUrlPath, path_units * sizeof(wchar_t));
    }
    memcpy(q->path + path_units, extra, extra_units * sizeof(wchar_t));
    q->path[path_units + extra_units] = L'\0';

    lua_getfield(L, idx, "body");
    if (!lua_isnil(L, -1)) {
        if (lua_type(L, -1) != LUA_TSTRING) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "body must be a string of bytes");
        }
        size_t n = 0;
        const char *b = lua_tolstring(L, -1, &n);
        if (n > 0xffffffffu) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "the body is larger than WinHTTP can send at once");
        }
        q->body = (unsigned char *)malloc(n > 0 ? n : 1);
        if (q->body == NULL) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "oserror", "out of memory");
        }
        memcpy(q->body, b, n);
        q->body_len = n;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "timeout");
    if (!lua_isnil(L, -1)) {
        int64_t ms = 0;
        if (ku_check_duration(L, -1, &ms) != 0 || ms <= 0 || ms > 0x7fffffff) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue",
                                "timeout must be a positive duration such as \"30s\" (WinHTTP reads zero as infinite)");
        }
        q->timeout_ms = (DWORD)ms;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "redirect");
    if (!lua_isnil(L, -1)) {
        const char *policy = lua_tostring(L, -1);
        if (policy == NULL || strcmp(policy, "none") != 0) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "redirect takes exactly \"none\"");
        }
        q->redirect_none = 1;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "to");
    int to_file = !lua_isnil(L, -1);
    if (to_file) {
        if (lua_type(L, -1) != LUA_TSTRING) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "to must be a path");
        }
        q->to_utf8 = _strdup(lua_tostring(L, -1));
    }
    lua_pop(L, 1);
    q->maxbody = to_file ? KU_HTTP_DEFAULT_MAXFILE : KU_HTTP_DEFAULT_MAXBODY;
    lua_getfield(L, idx, "maxbody");
    if (!lua_isnil(L, -1)) {
        int64_t bytes = 0;
        if (ku_check_bytes(L, -1, &bytes) != 0 || bytes <= 0) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "maxbody must be a positive size such as \"64M\"");
        }
        q->maxbody = (size_t)bytes;
    }
    lua_pop(L, 1);
    lua_getfield(L, idx, "sha256");
    if (!lua_isnil(L, -1)) {
        size_t hex_length = 0;
        const char *hex = lua_type(L, -1) == LUA_TSTRING ? lua_tolstring(L, -1, &hex_length) : NULL;
        if (hex == NULL || parse_hex(hex, hex_length, q->expected, sizeof q->expected) != 0) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "sha256 must be 64 hex digits");
        }
        q->want_hash = 1;
    }
    lua_pop(L, 1);

    /* Headers: a table of name = value, plus `type` for Content-Type.  An
     * explicit `type` beats a caller-supplied Content-Type header; otherwise
     * the caller's header stands; otherwise a body is application/octet-stream. */
    char *block = NULL;
    size_t block_len = 0;
    lua_getfield(L, idx, "type");
    const char *content_type = lua_isnil(L, -1) ? NULL : luaL_checkstring(L, -1);
    int caller_typed = 0;
    lua_getfield(L, idx, "headers");
    if (lua_type(L, -1) == LUA_TTABLE) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_type(L, -2) == LUA_TSTRING && _stricmp(lua_tostring(L, -2), "Content-Type") == 0) {
                caller_typed = 1;
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    if (content_type == NULL && q->body != NULL && !caller_typed) {
        content_type = "application/octet-stream";
    }
    lua_getfield(L, idx, "headers");
    if (!lua_isnil(L, -1)) {
        if (lua_type(L, -1) != LUA_TTABLE) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "headers must be a table of name = value");
        }
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_type(L, -2) != LUA_TSTRING || (lua_type(L, -1) != LUA_TSTRING && lua_type(L, -1) != LUA_TNUMBER)) {
                free(block);
                request_free(q);
                return ku_err_raise(L, "HTTP", "badvalue", "header names and values must be strings");
            }
            size_t nl = 0, vl = 0;
            const char *name = lua_tolstring(L, -2, &nl);
            const char *value = lua_tolstring(L, -1, &vl);
            if (nl == 0 || strlen(name) != nl || strlen(value) != vl || has_control(name, nl) || has_control(value, vl) ||
                memchr(name, ':', nl) != NULL || memchr(name, ' ', nl) != NULL) {
                free(block);
                request_free(q);
                return ku_err_raise(L, "HTTP", "badvalue", "header '%s' has an invalid name or value", name);
            }
            if (content_type != NULL && _stricmp(name, "Content-Type") == 0) {
                lua_pop(L, 1);
                continue; /* `type` wins */
            }
            size_t add = nl + 2 + vl + 2;
            char *grown = (char *)realloc(block, block_len + add + 1);
            if (grown == NULL) {
                free(block);
                request_free(q);
                return ku_err_raise(L, "HTTP", "oserror", "out of memory");
            }
            block = grown;
            memcpy(block + block_len, name, nl);
            memcpy(block + block_len + nl, ": ", 2);
            memcpy(block + block_len + nl + 2, value, vl);
            memcpy(block + block_len + nl + 2 + vl, "\r\n", 2);
            block_len += add;
            block[block_len] = '\0';
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 2);
    if (content_type != NULL) {
        if (has_control(content_type, strlen(content_type))) {
            free(block);
            request_free(q);
            return ku_err_raise(L, "HTTP", "badvalue", "type has an invalid value");
        }
        size_t add = 14 + strlen(content_type) + 2;
        char *grown = (char *)realloc(block, block_len + add + 1);
        if (grown == NULL) {
            free(block);
            request_free(q);
            return ku_err_raise(L, "HTTP", "oserror", "out of memory");
        }
        block = grown;
        snprintf(block + block_len, add + 1, "Content-Type: %s\r\n", content_type);
        block_len += add;
    }
    if (block != NULL) {
        q->headers = ku_utf8_to_wide(block);
        free(block);
        if (q->headers == NULL) {
            request_free(q);
            return ku_err_raise(L, "HTTP", "encoding", "a header is not valid UTF-8");
        }
    }

    if (to_file) {
        /* Stream into a sibling temporary file; the completion renames it. */
        ku_wpath target;
        ku_fail fail;
        if (ku_wpath_make(q->to_utf8, &target, &fail) != 0) {
            request_free(q);
            return ku_err_raise(L, fail.domain, fail.code, "%s", fail.message);
        }
        wchar_t suffix[48];
        _snwprintf(suffix, sizeof suffix / sizeof suffix[0], L".kuu-%lu-%llu.tmp", (unsigned long)GetCurrentProcessId(),
                   (unsigned long long)GetTickCount64());
        q->temp_path = (wchar_t *)malloc((target.length + wcslen(suffix) + 1) * sizeof(wchar_t));
        if (q->temp_path == NULL) {
            ku_wpath_free(&target);
            request_free(q);
            return ku_err_raise(L, "HTTP", "oserror", "out of memory");
        }
        wcscpy(q->temp_path, target.text);
        wcscat(q->temp_path, suffix);
        ku_wpath_free(&target);
        q->file = CreateFileW(q->temp_path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
        if (q->file == INVALID_HANDLE_VALUE) {
            DWORD error = GetLastError();
            q->file = NULL;
            request_free(q);
            char *text = ku_win_error_message(error);
            ku_err_push(L, "HTTP", "oserror", "cannot create the download file beside '%s': %s", "to",
                        text != NULL ? text : "");
            free(text);
            return lua_error(L);
        }
    }

    q->session = session_get();
    if (q->session == NULL) {
        DWORD error = GetLastError();
        request_free(q);
        return ku_err_raise(L, "HTTP", "oserror", "cannot open a WinHTTP session (error %lu)", (unsigned long)error);
    }
    ku_waiter *w = ku_waiter_new(q->loop, q, request_push);
    if (w == NULL) {
        request_free(q);
        return ku_err_raise(L, "HTTP", "oserror", "out of memory");
    }
    q->waiter = w;
    ku_timer_init(&q->deadline, http_deadline, q);
    ku_loop_expect(q->loop);
    q->thread = CreateThread(NULL, 0, http_worker, q, 0, NULL);
    if (q->thread == NULL) {
        ku_loop_received(q->loop);
        free(w);
        request_free(q);
        return ku_err_raise(L, "HTTP", "oserror", "cannot start the request thread");
    }
    ku_timer_arm(q->loop, &q->deadline, q->timeout_ms);
    return ku_wait(L, w, -1);
}

/* http.request{ method=, url=, ... } */
static int l_http_request(lua_State *L)
{
    return build_request(L, 1);
}

/* http.get(url [, options]) */
static int l_http_get(lua_State *L)
{
    luaL_checkstring(L, 1);
    lua_settop(L, 2); /* an absent options table and an explicit nil are the same thing */
    if (lua_isnil(L, 2)) {
        lua_pop(L, 1);
        lua_newtable(L);
    } else {
        luaL_checktype(L, 2, LUA_TTABLE);
    }
    lua_pushvalue(L, 1);
    lua_setfield(L, 2, "url");
    lua_pushliteral(L, "GET");
    lua_setfield(L, 2, "method");
    return build_request(L, 2);
}

/* http.post(url, body [, options]) */
static int l_http_post(lua_State *L)
{
    luaL_checkstring(L, 1);
    luaL_checkstring(L, 2);
    lua_settop(L, 3);
    if (lua_isnil(L, 3)) {
        lua_pop(L, 1);
        lua_newtable(L);
    } else {
        luaL_checktype(L, 3, LUA_TTABLE);
    }
    lua_pushvalue(L, 1);
    lua_setfield(L, 3, "url");
    lua_pushvalue(L, 2);
    lua_setfield(L, 3, "body");
    lua_pushliteral(L, "POST");
    lua_setfield(L, 3, "method");
    return build_request(L, 3);
}

int ku_open_http(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"get", l_http_get},
        {"post", l_http_post},
        {"request", l_http_request},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
