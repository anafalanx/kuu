/* ports.c -- TCP listeners with their owning processes; see ports.h. */
#include "ports.h"

#include <iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned short host_port(DWORD network_order)
{
    return (unsigned short)(((network_order & 0xff) << 8) | ((network_order >> 8) & 0xff));
}

static void ipv4_text(DWORD address, char *out, size_t cap)
{
    const unsigned char *b = (const unsigned char *)&address;
    snprintf(out, cap, "%u.%u.%u.%u", b[0], b[1], b[2], b[3]);
}

static void ipv6_text(const UCHAR *address, char *out, size_t cap)
{
    /* eight groups, uncompressed; "::" would be prettier and is not needed */
    snprintf(out, cap, "%x:%x:%x:%x:%x:%x:%x:%x", (address[0] << 8) | address[1], (address[2] << 8) | address[3],
             (address[4] << 8) | address[5], (address[6] << 8) | address[7], (address[8] << 8) | address[9],
             (address[10] << 8) | address[11], (address[12] << 8) | address[13], (address[14] << 8) | address[15]);
}

static void *table_for(ULONG family, ULONG *size)
{
    *size = 0;
    if (GetExtendedTcpTable(NULL, size, FALSE, family, TCP_TABLE_OWNER_PID_LISTENER, 0) != ERROR_INSUFFICIENT_BUFFER) {
        return NULL;
    }
    void *table = malloc(*size + 4096);
    if (table == NULL) {
        return NULL;
    }
    *size += 4096;
    if (GetExtendedTcpTable(table, size, FALSE, family, TCP_TABLE_OWNER_PID_LISTENER, 0) != NO_ERROR) {
        free(table);
        return NULL;
    }
    return table;
}

int ku_tcp_listeners(ku_listener **out, size_t *count)
{
    ULONG size4 = 0, size6 = 0;
    MIB_TCPTABLE_OWNER_PID *v4 = (MIB_TCPTABLE_OWNER_PID *)table_for(AF_INET, &size4);
    MIB_TCP6TABLE_OWNER_PID *v6 = (MIB_TCP6TABLE_OWNER_PID *)table_for(AF_INET6, &size6);
    size_t total = (v4 != NULL ? v4->dwNumEntries : 0) + (v6 != NULL ? v6->dwNumEntries : 0);
    ku_listener *list = (ku_listener *)calloc(total > 0 ? total : 1, sizeof *list);
    if (list == NULL) {
        free(v4);
        free(v6);
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return -1;
    }
    size_t n = 0;
    if (v4 != NULL) {
        for (DWORD i = 0; i < v4->dwNumEntries; i++) {
            const MIB_TCPROW_OWNER_PID *row = &v4->table[i];
            list[n].port = host_port(row->dwLocalPort);
            list[n].pid = row->dwOwningPid;
            list[n].ipv6 = 0;
            ipv4_text(row->dwLocalAddr, list[n].address, sizeof list[n].address);
            n++;
        }
    }
    if (v6 != NULL) {
        for (DWORD i = 0; i < v6->dwNumEntries; i++) {
            const MIB_TCP6ROW_OWNER_PID *row = &v6->table[i];
            list[n].port = host_port(row->dwLocalPort);
            list[n].pid = row->dwOwningPid;
            list[n].ipv6 = 1;
            ipv6_text(row->ucLocalAddr, list[n].address, sizeof list[n].address);
            n++;
        }
    }
    free(v4);
    free(v6);
    *out = list;
    *count = n;
    return 0;
}
