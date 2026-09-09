/*
 * procinfo.h -- the other processes: proc.list, proc.find, proc.tree, and
 * the process snapshot they share with net.listeners.
 *
 * Registered into the `proc` table by proc.c; implemented in procinfo.c on
 * the Toolhelp snapshot, the process query APIs, and the TCP tables.
 */
#ifndef KUU_PROCINFO_H
#define KUU_PROCINFO_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stddef.h>

#include "lua.h"

typedef struct ku_pentry {
    DWORD pid, parent, threads;
    wchar_t name[MAX_PATH];
} ku_pentry;

/* Every process, sorted by pid; malloc'd, the caller frees.  NULL with
 * GetLastError set when the snapshot cannot be taken. */
ku_pentry *ku_proc_snapshot(size_t *count);

/* The entry for `pid` in a snapshot, or NULL. */
const ku_pentry *ku_proc_lookup(const ku_pentry *list, size_t count, DWORD pid);

int ku_proc_list(lua_State *L);
int ku_proc_find(lua_State *L);
int ku_proc_tree(lua_State *L);

#endif /* KUU_PROCINFO_H */
