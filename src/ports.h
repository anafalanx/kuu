/*
 * ports.h -- who listens on which TCP port, from the machine's own tables.
 *
 * Shared by proc.find { port = } and, later, net.listeners.  The Windows
 * IP helper answers with the owning process id per listening socket, for
 * IPv4 and IPv6 alike.
 */
#ifndef KUU_PORTS_H
#define KUU_PORTS_H

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>

#include <stddef.h>

typedef struct ku_listener {
    unsigned short port;
    DWORD pid;
    int ipv6;
    char address[64]; /* the bound address, textual */
} ku_listener;

/* Every TCP listener on the machine; malloc'd, the caller frees.  Returns 0,
 * or -1 with GetLastError set. */
int ku_tcp_listeners(ku_listener **out, size_t *count);

#endif /* KUU_PORTS_H */
