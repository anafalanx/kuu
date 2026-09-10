/* values.c -- durations and byte sizes; see values.h. */
#include "values.h"
#include "err.h"
#include "lauxlib.h"

#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Parse a non-negative decimal number with an optional fraction.  Returns the
 * unit suffix start, or NULL when the text does not begin with a number. */
static const char *parse_number(const char *text, double *value)
{
    const char *p = text;
    if (*p < '0' || *p > '9') {
        return NULL;
    }
    errno = 0;
    char *end = NULL;
    double v = strtod(p, &end);
    if (end == p || errno != 0 || !(v >= 0.0) || isinf(v)) {
        return NULL;
    }
    /* strtod accepts exponents and hex; a unit string is decimal digits and
     * one '.' only, so re-scan to make sure nothing exotic slipped in. */
    int dots = 0;
    for (const char *q = p; q < end; q++) {
        if (*q == '.') {
            dots++;
        } else if (*q < '0' || *q > '9') {
            return NULL;
        }
    }
    if (dots > 1) {
        return NULL;
    }
    *value = v;
    return end;
}

/* "30s", "250ms", "1.5h", "2d", and sums of those with or without spaces:
 * "1h30m", "1h 30m 5s".  Units: ms, s, m, h, d. */
int ku_parse_duration_ms(const char *text, int64_t *ms)
{
    double total = 0.0;
    int parts = 0;
    const char *p = text;
    for (;;) {
        while (*p == ' ') {
            p++;
        }
        if (*p == '\0') {
            break;
        }
        double value = 0.0;
        const char *unit = parse_number(p, &value);
        if (unit == NULL) {
            return -1;
        }
        double scale;
        if (unit[0] == 'm' && unit[1] == 's') {
            scale = 1.0;
            p = unit + 2;
        } else if (unit[0] == 's') {
            scale = 1000.0;
            p = unit + 1;
        } else if (unit[0] == 'm') {
            scale = 60000.0;
            p = unit + 1;
        } else if (unit[0] == 'h') {
            scale = 3600000.0;
            p = unit + 1;
        } else if (unit[0] == 'd') {
            scale = 86400000.0;
            p = unit + 1;
        } else {
            return -1;
        }
        total += value * scale;
        parts++;
        if (total > 9.0e15) {
            return -1;
        }
    }
    if (parts == 0) {
        return -1;
    }
    *ms = (int64_t)(total + 0.5);
    return 0;
}

int ku_parse_bytes(const char *text, int64_t *bytes)
{
    double value = 0.0;
    const char *unit = parse_number(text, &value);
    if (unit == NULL) {
        return -1;
    }
    double scale = 1.0;
    if (*unit == 'K' || *unit == 'k') {
        scale = 1024.0;
        unit++;
    } else if (*unit == 'M' || *unit == 'm') {
        scale = 1024.0 * 1024.0;
        unit++;
    } else if (*unit == 'G' || *unit == 'g') {
        scale = 1024.0 * 1024.0 * 1024.0;
        unit++;
    }
    if (*unit == 'B' || *unit == 'b') {
        unit++;
    }
    if (*unit != '\0') {
        return -1;
    }
    double total = value * scale;
    if (total > 9.0e15) {
        return -1;
    }
    *bytes = (int64_t)(total + 0.5);
    return 0;
}

int ku_check_duration(lua_State *L, int idx, int64_t *ms)
{
    if (lua_type(L, idx) == LUA_TNUMBER) {
        double seconds = lua_tonumber(L, idx);
        if (!(seconds >= 0.0) || seconds > 9.0e12) {
            return -1;
        }
        *ms = (int64_t)(seconds * 1000.0 + 0.5);
        return 0;
    }
    if (lua_type(L, idx) == LUA_TSTRING) {
        size_t length = 0;
        const char *text = lua_tolstring(L, idx, &length);
        return memchr(text, '\0', length) == NULL ? ku_parse_duration_ms(text, ms) : -1;
    }
    return -1;
}

int ku_check_bytes(lua_State *L, int idx, int64_t *bytes)
{
    if (lua_type(L, idx) == LUA_TNUMBER) {
        int is_integer = 0;
        lua_Integer n = lua_tointegerx(L, idx, &is_integer);
        if (!is_integer || n < 0) {
            return -1;
        }
        *bytes = (int64_t)n;
        return 0;
    }
    if (lua_type(L, idx) == LUA_TSTRING) {
        size_t length = 0;
        const char *text = lua_tolstring(L, idx, &length);
        return memchr(text, '\0', length) == NULL ? ku_parse_bytes(text, bytes) : -1;
    }
    return -1;
}

const char *ku_check_cstring(lua_State *L, int idx, const char *domain, const char *what)
{
    size_t length = 0;
    const char *text = luaL_checklstring(L, idx, &length);
    if (memchr(text, '\0', length) != NULL) {
        ku_err_raise(L, domain, "badvalue", "the %s cannot contain NUL", what);
    }
    return text;
}
