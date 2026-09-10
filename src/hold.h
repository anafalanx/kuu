/* hold.h -- native allocations owned by the Lua stack, even across a raise. */
#ifndef KUU_HOLD_H
#define KUU_HOLD_H

#include "lua.h"

typedef struct ku_hold {
    void *ptr;
    void (*release)(void *);
} ku_hold;

/* Push an empty holder before allocating.  Assign ptr once ownership passes
 * to it.  Use lua_toclose on its stack slot for a call-local resource, or
 * retain it as an upvalue for an iterator.  __gc also releases abandoned holds. */
ku_hold *ku_hold_new(lua_State *L, void (*release)(void *));

#endif /* KUU_HOLD_H */
