/*
 * http_fixture.c -- a loopback HTTP server the suite drives.
 *
 * Usage: http_fixture.exe [FILESDIR]
 *
 * Listens on 127.0.0.1 at an ephemeral port and prints "PORT <n>" on stdout.
 * Serves canned routes, counts hits per path, and exits on GET /quit.  Never
 * reaches the network: no DNS, no TLS, one connection at a time.
 *
 *   GET  /hello                 200 "hello"
 *   GET  /status/NNN            NNN with a small body
 *   GET  /big?n=N               N bytes of 'x'
 *   GET  /slow?ms=N             sleeps N ms, then 200 "slow"
 *   GET  /redirect              302 -> /hello (relative Location)
 *   GET  /redirect-abs          302 -> http://127.0.0.1:PORT/hello
 *   GET  /headers               200, the request headers as the body
 *   GET  /dup                   200 with two Set-Cookie headers
 *   GET  /hits?path=P           200, the number of requests P received
 *   GET  /files/NAME            200, the file FILESDIR/NAME (or 404)
 *   GET  /gzip                  200, "hello gzip" compressed with gzip
 *   POST /echo                  200, "METHOD TYPE LEN\n" then the body
 *   GET  /quit                  200 "bye", then the server exits
 */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct hit {
    char path[256];
    int count;
} hit;

static hit hits[64];
static int hit_count;
static const char *files_dir;
static int port;

static CRITICAL_SECTION lock; /* connections are served on threads */
static volatile LONG quitting;
static SOCKET listener_socket;

static void record_hit(const char *path)
{
    EnterCriticalSection(&lock);
    for (int i = 0; i < hit_count; i++) {
        if (strcmp(hits[i].path, path) == 0) {
            hits[i].count++;
            LeaveCriticalSection(&lock);
            return;
        }
    }
    if (hit_count < 64) {
        snprintf(hits[hit_count].path, sizeof hits[hit_count].path, "%.255s", path);
        hits[hit_count].count = 1;
        hit_count++;
    }
    LeaveCriticalSection(&lock);
}

static int hits_for(const char *path)
{
    int count = 0;
    EnterCriticalSection(&lock);
    for (int i = 0; i < hit_count; i++) {
        if (strcmp(hits[i].path, path) == 0) {
            count = hits[i].count;
            break;
        }
    }
    LeaveCriticalSection(&lock);
    return count;
}

static void send_all(SOCKET s, const char *data, size_t n)
{
    while (n > 0) {
        int sent = send(s, data, (int)(n > 65536 ? 65536 : n), 0);
        if (sent <= 0) {
            return;
        }
        data += sent;
        n -= (size_t)sent;
    }
}

static void respond(SOCKET s, int status, const char *reason, const char *extra_headers, const char *body, size_t body_len)
{
    char head[1024];
    int n = snprintf(head, sizeof head,
                     "HTTP/1.1 %d %s\r\nContent-Length: %zu\r\nConnection: close\r\nContent-Type: text/plain\r\n%s\r\n",
                     status, reason, body_len, extra_headers != NULL ? extra_headers : "");
    send_all(s, head, (size_t)n);
    if (body_len > 0) {
        send_all(s, body, body_len);
    }
}

static const char *query_value(const char *query, const char *name, char *out, size_t cap)
{
    out[0] = '\0';
    if (query == NULL) {
        return out;
    }
    size_t nl = strlen(name);
    const char *p = query;
    while (*p) {
        if (strncmp(p, name, nl) == 0 && p[nl] == '=') {
            const char *v = p + nl + 1;
            size_t i = 0;
            while (*v && *v != '&' && i + 1 < cap) {
                out[i++] = *v++;
            }
            out[i] = '\0';
            return out;
        }
        const char *amp = strchr(p, '&');
        if (amp == NULL) {
            break;
        }
        p = amp + 1;
    }
    return out;
}

/* A gzip member holding "hello gzip" (stored block), computed once. */
static const unsigned char GZIP_HELLO[] = {
    0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, /* header */
    0x01, 0x0a, 0x00, 0xf5, 0xff,                               /* stored block: final, len 10 */
    'h', 'e', 'l', 'l', 'o', ' ', 'g', 'z', 'i', 'p',
    0x8c, 0x4d, 0x05, 0x4a, /* crc32 of "hello gzip" (little endian) */
    0x0a, 0x00, 0x00, 0x00, /* size */
};

static int handle(SOCKET s)
{
    char request[65536];
    int total = 0;
    char *body_start = NULL;
    while (total < (int)sizeof request - 1) {
        int got = recv(s, request + total, (int)sizeof request - 1 - total, 0);
        if (got <= 0) {
            break;
        }
        total += got;
        request[total] = '\0';
        body_start = strstr(request, "\r\n\r\n");
        if (body_start != NULL) {
            body_start += 4;
            /* read a declared body completely */
            const char *cl = strstr(request, "Content-Length: ");
            if (cl == NULL) {
                cl = strstr(request, "content-length: ");
            }
            long declared = cl != NULL ? strtol(cl + 16, NULL, 10) : 0;
            while (total - (body_start - request) < declared && total < (int)sizeof request - 1) {
                got = recv(s, request + total, (int)sizeof request - 1 - total, 0);
                if (got <= 0) {
                    break;
                }
                total += got;
                request[total] = '\0';
            }
            break;
        }
    }
    if (body_start == NULL) {
        return 0;
    }
    char method[16] = "", target[1024] = "";
    sscanf(request, "%15s %1023s", method, target);
    char *query = strchr(target, '?');
    if (query != NULL) {
        *query++ = '\0';
    }
    record_hit(target);
    char value[512];

    if (strcmp(target, "/hello") == 0) {
        respond(s, 200, "OK", NULL, "hello", 5);
    } else if (strncmp(target, "/status/", 8) == 0) {
        int status = atoi(target + 8);
        respond(s, status, "Status", NULL, "status body", 11);
    } else if (strcmp(target, "/big") == 0) {
        long n = atol(query_value(query, "n", value, sizeof value));
        char *body = (char *)malloc((size_t)n + 1);
        memset(body, 'x', (size_t)n);
        respond(s, 200, "OK", NULL, body, (size_t)n);
        free(body);
    } else if (strcmp(target, "/slow") == 0) {
        Sleep((DWORD)atol(query_value(query, "ms", value, sizeof value)));
        respond(s, 200, "OK", NULL, "slow", 4);
    } else if (strcmp(target, "/redirect") == 0) {
        respond(s, 302, "Found", "Location: /hello\r\n", "", 0);
    } else if (strcmp(target, "/redirect-abs") == 0) {
        char location[128];
        snprintf(location, sizeof location, "Location: http://127.0.0.1:%d/hello\r\n", port);
        respond(s, 302, "Found", location, "", 0);
    } else if (strcmp(target, "/headers") == 0) {
        const char *first = strstr(request, "\r\n");
        size_t n = (size_t)(body_start - (first + 2));
        respond(s, 200, "OK", NULL, first + 2, n);
    } else if (strcmp(target, "/dup") == 0) {
        respond(s, 200, "OK", "Set-Cookie: a=1\r\nSet-Cookie: b=2\r\nX-Kuu: yes\r\n", "dup", 3);
    } else if (strcmp(target, "/hits") == 0) {
        char count[32];
        snprintf(count, sizeof count, "%d", hits_for(query_value(query, "path", value, sizeof value)));
        respond(s, 200, "OK", NULL, count, strlen(count));
    } else if (strcmp(target, "/gzip") == 0) {
        respond(s, 200, "OK", "Content-Encoding: gzip\r\n", (const char *)GZIP_HELLO, sizeof GZIP_HELLO);
    } else if (strncmp(target, "/files/", 7) == 0 && files_dir != NULL && strstr(target, "..") == NULL) {
        char path[1200];
        snprintf(path, sizeof path, "%s\\%s", files_dir, target + 7);
        FILE *f = fopen(path, "rb");
        if (f == NULL) {
            respond(s, 404, "Not Found", NULL, "no such file", 12);
        } else {
            fseek(f, 0, SEEK_END);
            long size = ftell(f);
            fseek(f, 0, SEEK_SET);
            char *body = (char *)malloc((size_t)size + 1);
            size_t read = fread(body, 1, (size_t)size, f);
            fclose(f);
            respond(s, 200, "OK", "Content-Type: application/octet-stream\r\n", body, read);
            free(body);
        }
    } else if (strcmp(target, "/echo") == 0) {
        const char *ct = strstr(request, "Content-Type: ");
        char type[128] = "-";
        if (ct != NULL) {
            sscanf(ct + 14, "%127[^\r]", type);
        }
        size_t body_len = (size_t)(total - (body_start - request));
        char *body = (char *)malloc(body_len + 256);
        int head = snprintf(body, 256, "%s %s %zu\n", method, type, body_len);
        memcpy(body + head, body_start, body_len);
        respond(s, 200, "OK", NULL, body, (size_t)head + body_len);
        free(body);
    } else if (strcmp(target, "/quit") == 0) {
        respond(s, 200, "OK", NULL, "bye", 3);
        return 1;
    } else {
        respond(s, 404, "Not Found", NULL, "no such route", 13);
    }
    return 0;
}

/* One connection per thread, so slow routes overlap the way a real server's do. */
static DWORD WINAPI serve(LPVOID arg)
{
    SOCKET s = (SOCKET)(ULONG_PTR)arg;
    int quit = handle(s);
    shutdown(s, SD_SEND);
    closesocket(s);
    if (quit) {
        InterlockedExchange(&quitting, 1);
        closesocket(listener_socket); /* unblocks accept */
    }
    return 0;
}

int main(int argc, char **argv)
{
    files_dir = argc > 1 ? argv[1] : NULL;
    InitializeCriticalSection(&lock);
    WSADATA data;
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
        fprintf(stderr, "WSAStartup failed\n");
        return 1;
    }
    SOCKET listener = socket(AF_INET, SOCK_STREAM, 0);
    listener_socket = listener;
    struct sockaddr_in address;
    memset(&address, 0, sizeof address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(listener, (struct sockaddr *)&address, sizeof address) != 0 || listen(listener, 16) != 0) {
        fprintf(stderr, "cannot listen on the loopback interface\n");
        return 1;
    }
    int length = sizeof address;
    getsockname(listener, (struct sockaddr *)&address, &length);
    port = ntohs(address.sin_port);
    printf("PORT %d\n", port);
    fflush(stdout);
    for (;;) {
        SOCKET s = accept(listener, NULL, NULL);
        if (s == INVALID_SOCKET) {
            break; /* the listener was closed by /quit */
        }
        HANDLE thread = CreateThread(NULL, 0, serve, (LPVOID)(ULONG_PTR)s, 0, NULL);
        if (thread == NULL) {
            closesocket(s);
            continue;
        }
        CloseHandle(thread);
    }
    Sleep(50); /* let the /quit responder finish its send */
    WSACleanup();
    return 0;
}
