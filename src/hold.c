#include "hold.h"
#include "lauxlib.h"

#define KU_HOLD_META "kuu.hold"

static int hold_close(lua_State *L)
{
    ku_hold *hold = (ku_hold *)luaL_checkudata(L, 1, KU_HOLD_META);
    void *ptr = hold->ptr;
    hold->ptr = NULL;
    if (ptr != NULL) {
        hold->release(ptr);
    }
    return 0;
}

ku_hold *ku_hold_new(lua_State *L, void (*release)(void *))
{
    ku_hold *hold = (ku_hold *)lua_newuserdatauv(L, sizeof *hold, 0);
    hold->ptr = NULL;
    hold->release = release;
    if (luaL_newmetatable(L, KU_HOLD_META)) {
        lua_pushcfunction(L, hold_close);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, hold_close);
        lua_setfield(L, -2, "__close");
    }
    lua_setmetatable(L, -2);
    return hold;
}
