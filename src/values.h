/*
 * values.h -- option values that carry units: durations and byte sizes.
 *
 * A duration is a number of seconds (fractions allowed) or a string with a
 * unit: "250ms", "30s", "1.5m", "2h".  A byte size is a number of bytes or a
 * string with a binary unit: "64K", "16M", "2G", optionally followed by "B".
 * Bare strings without a unit are refused so that "30" can never be read as
 * thirty of the wrong thing.  Both parsers return 0 on success and -1 when the
 * text is not a value of that kind.
 */
#ifndef KUU_VALUES_H
#define KUU_VALUES_H

#include <stdint.h>

#include "lua.h"

int ku_parse_duration_ms(const char *text, int64_t *ms);
int ku_parse_bytes(const char *text, int64_t *bytes);

/* Read a duration or size from a Lua value at `idx`.  Returns 0 on success,
 * -1 when the value is not acceptable (nothing is raised; the caller decides
 * how to report it).  A number is seconds for durations and bytes for sizes. */
int ku_check_duration(lua_State *L, int idx, int64_t *ms);
int ku_check_bytes(lua_State *L, int idx, int64_t *bytes);

/* A Lua string passed to a NUL-terminated native API must not name a prefix
 * of what the caller supplied.  This check allocates no native memory. */
const char *ku_check_cstring(lua_State *L, int idx, const char *domain, const char *what);

/* An options table at `idx` -- none or nil is fine -- may hold only the keys
 * in `allowed`, a NULL-terminated list; any other key raises `<domain> usage`
 * naming it, and a value that is not a table raises Lua's own type error.
 * Every option-taking call in the palette goes through this, so a misspelt
 * option is refused the same way everywhere instead of being ignored. */
void ku_check_options(lua_State *L, int idx, const char *domain, const char *const *allowed);

#endif /* KUU_VALUES_H */
