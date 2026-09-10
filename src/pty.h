#ifndef KUU_PTY_H
#define KUU_PTY_H
#include "lua.h"

/* The pseudoconsole uses proc's existing job, pipes, and child ownership. */
int ku_proc_pty_spawn(lua_State *L);
int ku_proc_pty_resize(lua_State *L);
#endif
