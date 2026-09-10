# time

Instants, zones, and ISO 8601. An instant is a number of seconds since
1970-01-01T00:00:00Z, fractional and exact to the millisecond, so what
`os.time` returns is an instant too. A zone is `"utc"`, `"local"`, or a fixed
offset such as `"+02:00"`; the local zone follows the machine's rules for the
instant in question, daylight time included.

```lua
local time = require("time")
time.now()                                  -- 1788962585.123
time.ms()                                   -- 1788962585123, an integer
time.iso()                                  -- "2026-09-09T14:03:05Z"
time.iso(t, { zone = "local", ms = true })  -- "2026-09-09T16:03:05.123+02:00"
time.parse("2026-09-09T16:03:05+02:00")     -- 1788962585; nil, err TIME badvalue when it is not a date
time.parse("2026-09-09 14:03", "utc")       -- a text without a zone is read in the zone given, local by default
time.parts(t, "local")
-- { year = 2026, month = 9, day = 9, hour = 16, min = 3, sec = 5, ms = 123,
--   wday = 4, yday = 252, offset = 120, zone = "+02:00", dst = true }
time.make({ year = 2026, month = 9, day = 9, hour = 14 })          -- UTC unless a zone follows
time.make({ year = 2026, month = 13, day = 1 })                     -- fields carry: 2027-01-01
time.format(t, "%Y-%m-%d %H:%M:%S %z", "local")                     -- strftime; %z and %Z are the zone asked for
time.zone()          -- { name = "Romance Daylight Time", key = "Romance Standard Time", standard, daylight, offset = 120, dst = true }
time.duration("1h30m")   -- 5400; the units ms s m h d, alone or summed, or plain seconds; the same grammar every timeout takes
time.human(93784)        -- "1d 2h"; two units, or "5.2s", or "250ms"
```

`parse` accepts a date, or a date and a time separated by `T` or a space,
seconds optional, a fraction optional, and `Z` or an offset optional. It
checks that the day exists. `wday` counts from Sunday as 1, as `os.date` does.
`os.date` and `os.time` keep working and agree with `time.parts(t, "local")`;
they know only the machine's zone and whole seconds, which is why this module
exists. Named zones other than the machine's own are not supported yet; an
offset says what is meant.

| TIME code | when |
|---|---|
| `badvalue` | `nil, err` from `parse` for a text that is not an instant; raised for a bad zone, a bad duration, a bad format, or an instant out of range |
| `oserror` | raised: Windows could not report the zone |
Malformed text passed to `time.parse`, including signed date/time fields
or an offset beyond +/-14:00, returns `nil, TIME badvalue`. Invalid
explicit zone arguments remain programming errors and raise.
