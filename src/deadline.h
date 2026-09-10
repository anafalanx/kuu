#ifndef KUU_DEADLINE_H
#define KUU_DEADLINE_H
#include "lua.h"
#include <stdint.h>

/* Add the private scope primitives to the sched table on top of the stack. */
void ku_deadline_open(lua_State *L);
/* Push the effective deadline's token and set its absolute monotonic time.
 * Returns 0 without pushing when this coroutine has no deadline. */
int ku_deadline_current(lua_State *L, int64_t *due_ms);
#endif
