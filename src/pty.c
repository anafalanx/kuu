/* The native half of pty: job-supervised console children and resizing. */
#include "pty.h"
#include "state.h"
#include "lauxlib.h"

int ku_open_pty(lua_State *L)
{
    ku_open_proc(L); /* initialize the shared child metatable */
    lua_pop(L, 1);
    static const luaL_Reg functions[] = {
        {"_spawn", ku_proc_pty_spawn}, {"_resize", ku_proc_pty_resize}, {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
