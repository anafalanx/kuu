/*
 * state.h -- the Lua state kuu hands a program.
 *
 * One state, one thread, Lua 5.5 compiled as C.  The standard library is
 * opened selectively and the hazards a runtime must own are removed:
 * io.popen, os.execute, os.remove, os.rename, os.tmpname, dofile, loadfile,
 * package.loadlib, the debug library, and binary chunks.  `require` searches
 * package.preload and then the program's own directory (`?.lua`,
 * `?/init.lua`), never the environment; package.path and package.cpath are
 * empty strings to make that visible.  The runtime's own modules arrive
 * through package.preload, so a program gets nothing it did not `require`.
 */
#ifndef KUU_STATE_H
#define KUU_STATE_H

#include "kuu.h"
#include "lua.h"

typedef struct ku_launch {
    const char *exe;          /* UTF-8 absolute path of the running kuu.exe */
    const char *route;        /* "file", "stdin", or "eval" */
    const char *program;      /* file route: the path as given; else NULL */
    const char *root;         /* UTF-8 directory `require` searches */
    int argc;                 /* program arguments, UTF-8 */
    const char *const *argv;
} ku_launch;

/* NULL with `fail` set (domain STATE) when the state cannot be created. */
lua_State *ku_state_new(const ku_launch *launch, ku_fail *fail);

#endif /* KUU_STATE_H */
