/*
 * procinfo.h -- the other processes: proc.list, proc.find, proc.tree.
 *
 * Registered into the `proc` table by proc.c; implemented in procinfo.c on
 * the Toolhelp snapshot, the process query APIs, and the TCP tables.
 */
#ifndef KUU_PROCINFO_H
#define KUU_PROCINFO_H

#include "lua.h"

int ku_proc_list(lua_State *L);
int ku_proc_find(lua_State *L);
int ku_proc_tree(lua_State *L);

#endif /* KUU_PROCINFO_H */
