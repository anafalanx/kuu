/*
 * err.h -- the one error shape.
 *
 * Every failure kuu reports to a program is a table { domain, code, message,
 * ... } with the metatable "kuu.err", whose __tostring renders
 * "DOMAIN code: message".  Expected failures come back as `nil, err`;
 * programming mistakes (bad arguments) are raised with the same value.  The
 * domains and codes are closed sets documented per module.
 */
#ifndef KUU_ERR_H
#define KUU_ERR_H

#include "lua.h"

/* Push an error table.  `format` and the arguments build the message. */
void ku_err_push(lua_State *L, const char *domain, const char *code,
                 const char *format, ...);

/* Push nil and an error table; returns 2 for `return ku_err_fail(...)`. */
int ku_err_fail(lua_State *L, const char *domain, const char *code,
                const char *format, ...);

/* Raise an error table; never returns. */
[[noreturn]] int ku_err_raise(lua_State *L, const char *domain, const char *code,
                 const char *format, ...);

/* Open the `err` module (package.preload loader). */
int ku_open_err(lua_State *L);

#endif /* KUU_ERR_H */
