/*
 * time.c -- the `time` module: instants, zones, ISO 8601.
 *
 *   time.now()                        -> seconds since the epoch, with milliseconds, UTC
 *   time.ms()                         -> the same as an integer of milliseconds
 *   time.iso([t [, { zone, ms }]])    -> "2026-09-09T14:03:05Z", "…16:03:05.123+02:00"
 *   time.parse(text [, zone])         -> seconds | nil, err   ISO 8601; a text without a zone is read in `zone`, local by default
 *   time.parts(t [, zone])            -> { year, month, day, hour, min, sec, ms, wday, yday, offset, zone, dst }
 *   time.make(parts [, zone])         -> seconds; fields may overflow, as in os.time
 *   time.format(t, fmt [, zone])      -> strftime, with %z and %Z for the zone asked
 *   time.zone()                       -> the machine's zone: { name, key, standard, daylight, offset, dst }
 *   time.duration("1h30m")            -> seconds;  time.human(seconds) -> "1h 30m"
 *
 * An instant is a number of seconds since 1970-01-01T00:00:00Z, fractional,
 * exact to the millisecond, so os.time values are instants too.  A zone is
 * "utc", "local", or a fixed offset such as "+02:00"; the local zone follows
 * the machine's rules for the instant in question, daylight time included.
 * Windows keeps time in FILETIME ticks of 100 ns since 1601; everything here
 * converts once and exactly.
 */
#include "err.h"
#include "state.h"
#include "values.h"
#include "wintext.h"

#include "lauxlib.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TICKS_PER_MS 10000LL
#define EPOCH_TICKS 116444736000000000LL /* 1970-01-01 in FILETIME ticks */
#define MS_PER_DAY 86400000LL

typedef struct ku_zone {
    int local;          /* follow the machine's zone */
    int offset_minutes; /* for a fixed zone */
} ku_zone;

static int64_t now_ms(void)
{
    FILETIME ft;
    GetSystemTimePreciseAsFileTime(&ft);
    int64_t ticks = ((int64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (ticks - EPOCH_TICKS) / TICKS_PER_MS;
}

static int64_t ms_arg(lua_State *L, int idx)
{
    if (lua_isnoneornil(L, idx)) {
        return now_ms();
    }
    lua_Number seconds = luaL_checknumber(L, idx);
    if (!(seconds > -1e12 && seconds < 1e12)) {
        ku_err_raise(L, "TIME", "badvalue", "the instant is out of range");
    }
    return (int64_t)llround(seconds * 1000.0);
}

static void push_seconds(lua_State *L, int64_t ms)
{
    lua_pushnumber(L, (lua_Number)ms / 1000.0);
}

/* "utc" | "Z" | "local" | "+hh:mm" | "-hh:mm" | "+hhmm" | "+hh" */
static ku_zone zone_arg(lua_State *L, int idx, const char *fallback)
{
    ku_zone z = {0, 0};
    const char *text = lua_isnoneornil(L, idx) ? fallback : luaL_checkstring(L, idx);
    if (text == NULL || strcmp(text, "utc") == 0 || strcmp(text, "UTC") == 0 || strcmp(text, "Z") == 0) {
        return z;
    }
    if (strcmp(text, "local") == 0) {
        z.local = 1;
        return z;
    }
    int sign = text[0] == '+' ? 1 : text[0] == '-' ? -1 : 0;
    unsigned hours = 0, minutes = 0;
    int n = 0;
    if (sign != 0 && (sscanf(text + 1, "%2u:%2u%n", &hours, &minutes, &n) == 2 || sscanf(text + 1, "%2u%2u%n", &hours, &minutes, &n) == 2 ||
                      (minutes = 0, sscanf(text + 1, "%2u%n", &hours, &n) == 1)) &&
        text[1 + n] == '\0' && hours <= 14 && minutes < 60) {
        z.offset_minutes = sign * (int)(hours * 60 + minutes);
        return z;
    }
    ku_err_raise(L, "TIME", "badvalue", "a zone is \"utc\", \"local\", or an offset such as \"+02:00\", got '%s'", text);
    return z;
}

/* Days since 1970-01-01 for a proleptic Gregorian date; month and day may
 * lie outside their ranges and are carried, as os.time does. */
static int64_t days_from_civil(int64_t year, int64_t month, int64_t day)
{
    year += (month - 1) / 12;
    month = (month - 1) % 12;
    if (month < 0) {
        month += 12;
        year--;
    }
    month += 1;
    year -= month <= 2;
    int64_t era = (year >= 0 ? year : year - 399) / 400;
    int64_t yoe = year - era * 400;
    int64_t doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void civil_from_days(int64_t days, int *year, int *month, int *day)
{
    days += 719468;
    int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    int64_t doe = days - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t y = yoe + era * 400;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153;
    int64_t d = doy - (153 * mp + 2) / 5 + 1;
    int64_t m = mp + (mp < 10 ? 3 : -9);
    *year = (int)(y + (m <= 2));
    *month = (int)m;
    *day = (int)d;
}

/* The wall-clock fields of an instant in a zone.  Returns the offset in
 * minutes and, for the local zone, whether daylight time was in force. */
typedef struct ku_wall {
    int year, month, day, hour, min, sec, ms, wday, yday;
    int offset_minutes;
    int dst;
} ku_wall;

static void wall_from_ms(lua_State *L, int64_t ms, const ku_zone *zone, ku_wall *w)
{
    int offset = zone->offset_minutes;
    int dst = 0;
    if (zone->local) {
        int64_t ticks = ms * TICKS_PER_MS + EPOCH_TICKS;
        FILETIME ft = {(DWORD)(ticks & 0xffffffff), (DWORD)(ticks >> 32)};
        SYSTEMTIME utc, local;
        if (!FileTimeToSystemTime(&ft, &utc) || !SystemTimeToTzSpecificLocalTime(NULL, &utc, &local)) {
            ku_err_raise(L, "TIME", "badvalue", "the instant is out of the range Windows can convert");
        }
        FILETIME lft;
        SystemTimeToFileTime(&local, &lft);
        int64_t lticks = ((int64_t)lft.dwHighDateTime << 32) | lft.dwLowDateTime;
        offset = (int)((lticks - ticks) / (TICKS_PER_MS * 60000LL));
        DYNAMIC_TIME_ZONE_INFORMATION tz;
        DWORD kind = GetDynamicTimeZoneInformation(&tz);
        if (kind != TIME_ZONE_ID_INVALID) {
            dst = offset != -(int)(tz.Bias + tz.StandardBias);
        }
    }
    int64_t shifted = ms + (int64_t)offset * 60000LL;
    int64_t days = shifted / MS_PER_DAY;
    int64_t rem = shifted % MS_PER_DAY;
    if (rem < 0) {
        rem += MS_PER_DAY;
        days--;
    }
    civil_from_days(days, &w->year, &w->month, &w->day);
    w->hour = (int)(rem / 3600000);
    w->min = (int)(rem / 60000 % 60);
    w->sec = (int)(rem / 1000 % 60);
    w->ms = (int)(rem % 1000);
    int64_t wd = (days % 7 + 11) % 7; /* 1970-01-01 was a Thursday; Sunday = 1 */
    w->wday = (int)wd + 1;
    w->yday = (int)(days - days_from_civil(w->year, 1, 1)) + 1;
    w->offset_minutes = offset;
    w->dst = dst;
}

/* The instant of wall-clock fields read in a zone. */
static int64_t ms_from_wall(lua_State *L, int64_t year, int64_t month, int64_t day, int64_t hour, int64_t min,
                            int64_t sec, int64_t ms, const ku_zone *zone)
{
    int64_t days = days_from_civil(year, month, day);
    int64_t local_ms = days * MS_PER_DAY + hour * 3600000LL + min * 60000LL + sec * 1000LL + ms;
    if (!zone->local) {
        return local_ms - (int64_t)zone->offset_minutes * 60000LL;
    }
    /* normalise the fields through the calendar, then let Windows apply the
     * rules that held on that local date */
    int64_t d = local_ms / MS_PER_DAY, rem = local_ms % MS_PER_DAY;
    if (rem < 0) {
        rem += MS_PER_DAY;
        d--;
    }
    int y, mo, dd;
    civil_from_days(d, &y, &mo, &dd);
    SYSTEMTIME local, utc;
    memset(&local, 0, sizeof local);
    local.wYear = (WORD)y;
    local.wMonth = (WORD)mo;
    local.wDay = (WORD)dd;
    local.wHour = (WORD)(rem / 3600000);
    local.wMinute = (WORD)(rem / 60000 % 60);
    local.wSecond = (WORD)(rem / 1000 % 60);
    local.wMilliseconds = (WORD)(rem % 1000);
    if (!TzSpecificLocalTimeToSystemTime(NULL, &local, &utc)) {
        ku_err_raise(L, "TIME", "badvalue", "the local time is out of the range Windows can convert");
    }
    FILETIME ft;
    SystemTimeToFileTime(&utc, &ft);
    int64_t ticks = ((int64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (ticks - EPOCH_TICKS) / TICKS_PER_MS;
}

static void offset_text(int minutes, char *out, size_t cap, int colon)
{
    unsigned a = minutes < 0 ? (unsigned)-minutes : (unsigned)minutes;
    unsigned hours = a / 60 % 100, mins = a % 60;
    if (colon) {
        snprintf(out, cap, "%c%02u:%02u", minutes < 0 ? '-' : '+', hours, mins);
    } else {
        snprintf(out, cap, "%c%02u%02u", minutes < 0 ? '-' : '+', hours, mins);
    }
}

/* ---- the functions --------------------------------------------------------------------- */

static int l_time_now(lua_State *L)
{
    push_seconds(L, now_ms());
    return 1;
}

static int l_time_ms(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer)now_ms());
    return 1;
}

/* time.iso([t [, { zone = "utc", ms = false }]]) */
static int l_time_iso(lua_State *L)
{
    int64_t ms = ms_arg(L, 1);
    ku_zone zone = {0, 0};
    int with_ms = 0;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "zone");
        zone = zone_arg(L, lua_gettop(L), "utc");
        lua_pop(L, 1);
        lua_getfield(L, 2, "ms");
        with_ms = lua_toboolean(L, -1);
        lua_pop(L, 1);
    } else if (!lua_isnoneornil(L, 2)) {
        return ku_err_raise(L, "TIME", "badvalue", "iso takes an options table: { zone = , ms = }");
    }
    ku_wall w;
    wall_from_ms(L, ms, &zone, &w);
    char suffix[8];
    if (w.offset_minutes == 0 && !zone.local) {
        strcpy(suffix, "Z");
    } else {
        offset_text(w.offset_minutes, suffix, sizeof suffix, 1);
    }
    char text[64];
    if (with_ms) {
        snprintf(text, sizeof text, "%04d-%02d-%02dT%02d:%02d:%02d.%03d%s", w.year, w.month, w.day, w.hour, w.min, w.sec, w.ms, suffix);
    } else {
        snprintf(text, sizeof text, "%04d-%02d-%02dT%02d:%02d:%02d%s", w.year, w.month, w.day, w.hour, w.min, w.sec, suffix);
    }
    lua_pushstring(L, text);
    return 1;
}

/* time.parse(text [, zone]) -> seconds | nil, err.  ISO 8601: a date, or a
 * date and time separated by T or a space, with an optional fraction and an
 * optional Z or offset.  Without a zone in the text, `zone` applies, local
 * by default, because that is what a person meant when they wrote it. */
static int l_time_parse(lua_State *L)
{
    const char *text = luaL_checkstring(L, 1);
    ku_zone fallback = zone_arg(L, 2, "local");
    int year, month, day, hour = 0, min = 0, sec = 0;
    int n = 0;
    if (sscanf(text, "%4d-%2d-%2d%n", &year, &month, &day, &n) != 3 || n != 10) {
        return ku_err_fail(L, "TIME", "badvalue", "not an ISO 8601 date: '%s'", text);
    }
    const char *p = text + n;
    int64_t frac_ms = 0;
    int has_time = 0;
    if (*p == 'T' || *p == 't' || *p == ' ') {
        has_time = 1;
        p++;
        if (sscanf(p, "%2d:%2d%n", &hour, &min, &n) != 2 || n != 5) {
            return ku_err_fail(L, "TIME", "badvalue", "not an ISO 8601 time in '%s'", text);
        }
        p += n;
        if (*p == ':') {
            if (sscanf(p + 1, "%2d%n", &sec, &n) != 1 || n != 2) {
                return ku_err_fail(L, "TIME", "badvalue", "not an ISO 8601 time in '%s'", text);
            }
            p += 1 + n;
            if (*p == '.' || *p == ',') {
                p++;
                int digits = 0;
                int64_t frac = 0;
                while (*p >= '0' && *p <= '9') {
                    if (digits < 3) {
                        frac = frac * 10 + (*p - '0');
                    }
                    digits++;
                    p++;
                }
                if (digits == 0) {
                    return ku_err_fail(L, "TIME", "badvalue", "a fraction needs digits in '%s'", text);
                }
                while (digits < 3) {
                    frac *= 10;
                    digits++;
                }
                frac_ms = frac;
            }
        }
    }
    ku_zone zone = fallback;
    if (*p == 'Z' || *p == 'z') {
        zone.local = 0;
        zone.offset_minutes = 0;
        p++;
    } else if (*p == '+' || *p == '-') {
        lua_pushstring(L, p);
        zone = zone_arg(L, lua_gettop(L), NULL); /* raises on a malformed offset */
        lua_pop(L, 1);
        p += strlen(p);
    }
    if (*p != '\0') {
        return ku_err_fail(L, "TIME", "badvalue", "trailing text after the instant in '%s'", text);
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 24 || min > 59 || sec > 60 ||
        (hour == 24 && (min != 0 || sec != 0 || frac_ms != 0))) {
        return ku_err_fail(L, "TIME", "badvalue", "a field is out of range in '%s'", text);
    }
    /* the day must exist in that month */
    if (days_from_civil(year, month, day) != days_from_civil(year, month, 1) + day - 1 ||
        day > days_from_civil(year, month + 1, 1) - days_from_civil(year, month, 1)) {
        return ku_err_fail(L, "TIME", "badvalue", "no such day in '%s'", text);
    }
    (void)has_time;
    push_seconds(L, ms_from_wall(L, year, month, day, hour, min, sec, frac_ms, &zone));
    return 1;
}

static int l_time_parts(lua_State *L)
{
    int64_t ms = ms_arg(L, 1);
    ku_zone zone = zone_arg(L, 2, "utc");
    ku_wall w;
    wall_from_ms(L, ms, &zone, &w);
    lua_createtable(L, 0, 12);
    lua_pushinteger(L, w.year);
    lua_setfield(L, -2, "year");
    lua_pushinteger(L, w.month);
    lua_setfield(L, -2, "month");
    lua_pushinteger(L, w.day);
    lua_setfield(L, -2, "day");
    lua_pushinteger(L, w.hour);
    lua_setfield(L, -2, "hour");
    lua_pushinteger(L, w.min);
    lua_setfield(L, -2, "min");
    lua_pushinteger(L, w.sec);
    lua_setfield(L, -2, "sec");
    lua_pushinteger(L, w.ms);
    lua_setfield(L, -2, "ms");
    lua_pushinteger(L, w.wday);
    lua_setfield(L, -2, "wday");
    lua_pushinteger(L, w.yday);
    lua_setfield(L, -2, "yday");
    lua_pushinteger(L, w.offset_minutes);
    lua_setfield(L, -2, "offset");
    char zone_text[8];
    if (w.offset_minutes == 0 && !zone.local) {
        strcpy(zone_text, "Z");
    } else {
        offset_text(w.offset_minutes, zone_text, sizeof zone_text, 1);
    }
    lua_pushstring(L, zone_text);
    lua_setfield(L, -2, "zone");
    lua_pushboolean(L, w.dst);
    lua_setfield(L, -2, "dst");
    return 1;
}

static int64_t field(lua_State *L, int idx, const char *name, int64_t fallback, int required)
{
    lua_getfield(L, idx, name);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        if (required) {
            ku_err_raise(L, "TIME", "badvalue", "make needs %s", name);
        }
        return fallback;
    }
    if (!lua_isinteger(L, -1)) {
        ku_err_raise(L, "TIME", "badvalue", "%s must be an integer", name);
    }
    int64_t v = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return v;
}

/* time.make({ year, month, day [, hour, min, sec, ms] } [, zone]) */
static int l_time_make(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    ku_zone zone = zone_arg(L, 2, "utc");
    int64_t year = field(L, 1, "year", 0, 1), month = field(L, 1, "month", 1, 0), day = field(L, 1, "day", 1, 0);
    int64_t hour = field(L, 1, "hour", 0, 0), min = field(L, 1, "min", 0, 0), sec = field(L, 1, "sec", 0, 0);
    int64_t ms = field(L, 1, "ms", 0, 0);
    if (year < -100000 || year > 100000) {
        return ku_err_raise(L, "TIME", "badvalue", "the year is out of range");
    }
    push_seconds(L, ms_from_wall(L, year, month, day, hour, min, sec, ms, &zone));
    return 1;
}

/* time.format(t, fmt [, zone]): strftime on the wall clock of the zone, with
 * %z and %Z filled in for that zone rather than the process's. */
static int l_time_format(lua_State *L)
{
    int64_t ms = ms_arg(L, 1);
    const char *fmt = luaL_checkstring(L, 2);
    ku_zone zone = zone_arg(L, 3, "utc");
    ku_wall w;
    wall_from_ms(L, ms, &zone, &w);
    char offset[8], name[16];
    offset_text(w.offset_minutes, offset, sizeof offset, 0);
    if (w.offset_minutes == 0 && !zone.local) {
        strcpy(name, "UTC");
    } else {
        offset_text(w.offset_minutes, name, sizeof name, 1);
    }
    /* substitute %z and %Z ourselves; the C runtime would answer for the process's zone */
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (const char *p = fmt; *p != '\0'; p++) {
        if (p[0] == '%' && p[1] == 'z') {
            luaL_addstring(&b, offset);
            p++;
        } else if (p[0] == '%' && p[1] == 'Z') {
            luaL_addstring(&b, name);
            p++;
        } else if (p[0] == '%' && p[1] == '%') {
            luaL_addlstring(&b, "%%", 2);
            p++;
        } else {
            luaL_addchar(&b, *p);
        }
    }
    luaL_pushresult(&b);
    const char *prepared = lua_tostring(L, -1);
    struct tm tm;
    memset(&tm, 0, sizeof tm);
    tm.tm_year = w.year - 1900;
    tm.tm_mon = w.month - 1;
    tm.tm_mday = w.day;
    tm.tm_hour = w.hour;
    tm.tm_min = w.min;
    tm.tm_sec = w.sec;
    tm.tm_wday = w.wday - 1;
    tm.tm_yday = w.yday - 1;
    tm.tm_isdst = -1;
    char out[1024];
    /* the format is the caller's by design */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-nonliteral"
    size_t n = strftime(out, sizeof out, prepared, &tm);
#pragma GCC diagnostic pop
    if (n == 0 && *prepared != '\0') {
        return ku_err_raise(L, "TIME", "badvalue", "the format is invalid or its result too long");
    }
    lua_pushlstring(L, out, n);
    return 1;
}

static int l_time_zone(lua_State *L)
{
    DYNAMIC_TIME_ZONE_INFORMATION tz;
    DWORD kind = GetDynamicTimeZoneInformation(&tz);
    if (kind == TIME_ZONE_ID_INVALID) {
        return ku_err_raise(L, "TIME", "oserror", "cannot read the time zone");
    }
    lua_createtable(L, 0, 6);
    char *key = ku_wide_to_utf8(tz.TimeZoneKeyName, -1);
    char *standard = ku_wide_to_utf8(tz.StandardName, -1);
    char *daylight = ku_wide_to_utf8(tz.DaylightName, -1);
    int dst = kind == TIME_ZONE_ID_DAYLIGHT;
    lua_pushstring(L, dst && daylight != NULL ? daylight : (standard != NULL ? standard : ""));
    lua_setfield(L, -2, "name");
    lua_pushstring(L, key != NULL ? key : "");
    lua_setfield(L, -2, "key");
    lua_pushstring(L, standard != NULL ? standard : "");
    lua_setfield(L, -2, "standard");
    lua_pushstring(L, daylight != NULL ? daylight : "");
    lua_setfield(L, -2, "daylight");
    lua_pushinteger(L, -(lua_Integer)(tz.Bias + (dst ? tz.DaylightBias : tz.StandardBias)));
    lua_setfield(L, -2, "offset");
    lua_pushboolean(L, dst);
    lua_setfield(L, -2, "dst");
    free(key);
    free(standard);
    free(daylight);
    return 1;
}

static int l_time_duration(lua_State *L)
{
    int64_t ms = 0;
    if (ku_check_duration(L, 1, &ms) != 0) {
        return ku_err_raise(L, "TIME", "badvalue", "a duration is seconds, or text with units such as \"1h30m\" or \"250ms\"");
    }
    push_seconds(L, ms);
    return 1;
}

/* time.human(seconds) -> "2d 3h", "1h 2m", "1m 5s", "5.2s", "250ms" */
static int l_time_human(lua_State *L)
{
    lua_Number seconds = luaL_checknumber(L, 1);
    const char *sign = seconds < 0 ? "-" : "";
    seconds = fabs(seconds);
    char text[64];
    int64_t whole = (int64_t)seconds;
    if (whole >= 86400) {
        snprintf(text, sizeof text, "%s%lldd %lldh", sign, (long long)(whole / 86400), (long long)(whole % 86400 / 3600));
    } else if (whole >= 3600) {
        snprintf(text, sizeof text, "%s%lldh %lldm", sign, (long long)(whole / 3600), (long long)(whole % 3600 / 60));
    } else if (whole >= 60) {
        snprintf(text, sizeof text, "%s%lldm %llds", sign, (long long)(whole / 60), (long long)(whole % 60));
    } else if (seconds >= 1.0) {
        snprintf(text, sizeof text, "%s%.1fs", sign, seconds);
    } else {
        snprintf(text, sizeof text, "%s%lldms", sign, (long long)llround(seconds * 1000.0));
    }
    lua_pushstring(L, text);
    return 1;
}

int ku_open_time(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"now", l_time_now},       {"ms", l_time_ms},       {"iso", l_time_iso},           {"parse", l_time_parse},
        {"parts", l_time_parts},   {"make", l_time_make},   {"format", l_time_format},     {"zone", l_time_zone},
        {"duration", l_time_duration}, {"human", l_time_human}, {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
