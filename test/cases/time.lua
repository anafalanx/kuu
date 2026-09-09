-- time.lua -- instants, zones, ISO 8601: now, iso, parse, parts, make,
-- format, zone, duration, human, and the refusals.
global none
global <const> require, tostring, type, string, math, os, pcall

return function(T)
  local check, contains = T.check, T.contains
  local time = require "time"
  local err = require "err"

  local now = time.now()
  check("now is seconds since the epoch, close to os.time, with a fraction", type(now) == "number" and math.abs(now - os.time()) < 2 and math.type(time.ms()) == "integer" and math.abs(time.ms() / 1000 - now) < 2)

  -- a known instant: 2026-09-09 14:03:05.123 UTC
  local t = time.make({ year = 2026, month = 9, day = 9, hour = 14, min = 3, sec = 5, ms = 123 })
  check("make builds an instant in UTC by default", math.abs(t - 1788962585.123) < 0.0005, tostring(t))
  check("iso renders UTC with Z, to the second", time.iso(t) == "2026-09-09T14:03:05Z", time.iso(t))
  check("iso renders milliseconds on request", time.iso(t, { ms = true }) == "2026-09-09T14:03:05.123Z")
  check("iso renders a fixed offset zone", time.iso(t, { zone = "+02:00" }) == "2026-09-09T16:03:05+02:00" and time.iso(t, { zone = "-05:30" }) == "2026-09-09T08:33:05-05:30", time.iso(t, { zone = "-05:30" }))
  check("parse reads back what iso wrote, with and without ms and in any zone", time.parse("2026-09-09T14:03:05Z") == math.floor(t)
    and math.abs(time.parse("2026-09-09T14:03:05.123Z") - t) < 0.0005 and time.parse("2026-09-09T16:03:05+02:00") == math.floor(t)
    and time.parse("2026-09-09T08:33:05-05:30") == math.floor(t) and time.parse("2026-09-09 14:03:05Z") == math.floor(t))
  check("a date alone is midnight in the zone given", time.parse("2026-09-09", "utc") == 1788912000)
  check("a text without a zone is read in the zone given, local by default", time.parse("2026-09-09T14:03:05", "utc") == math.floor(t)
    and time.parse("2026-09-09T14:03:05") == time.make({ year = 2026, month = 9, day = 9, hour = 14, min = 3, sec = 5 }, "local"))
  local p = time.parts(t)
  check("parts in UTC", p.year == 2026 and p.month == 9 and p.day == 9 and p.hour == 14 and p.min == 3 and p.sec == 5 and p.ms == 123
    and p.wday == 4 and p.yday == 252 and p.offset == 0 and p.zone == "Z" and p.dst == false, time.iso(t))
  p = time.parts(t, "+02:00")
  check("parts in a fixed zone shift the clock and say the zone", p.hour == 16 and p.offset == 120 and p.zone == "+02:00")
  local lp = time.parts(t, "local")
  local od = os.date("*t", math.floor(t))
  check("parts in the local zone agree with os.date", lp.year == od.year and lp.month == od.month and lp.day == od.day and lp.hour == od.hour and lp.min == od.min and lp.wday == od.wday,
    time.iso(t, { zone = "local" }) .. " vs " .. os.date("%Y-%m-%dT%H:%M", math.floor(t)))
  check("make round-trips parts in the local zone", time.make(lp, "local") == math.floor(t) + (lp.ms / 1000), tostring(time.make(lp, "local")))
  check("make carries overflowing fields, as os.time does", time.iso(time.make({ year = 2026, month = 13, day = 1 })) == "2027-01-01T00:00:00Z"
    and time.iso(time.make({ year = 2026, month = 3, day = 0 })) == "2026-02-28T00:00:00Z" and time.iso(time.make({ year = 2026, month = 1, day = 1, hour = 25 })) == "2026-01-02T01:00:00Z")
  check("format is strftime with the zone asked for", time.format(t, "%Y-%m-%d %H:%M:%S %z", "+02:00") == "2026-09-09 16:03:05 +0200"
    and time.format(t, "%H:%M %Z") == "14:03 UTC" and time.format(t, "%A %d %B") == "Wednesday 09 September", time.format(t, "%Y-%m-%d %H:%M:%S %z", "+02:00"))
  local z = time.zone()
  check("zone describes the machine's zone", type(z.name) == "string" and #z.name > 0 and type(z.key) == "string" and math.type(z.offset) == "integer"
    and z.offset >= -14 * 60 and z.offset <= 14 * 60 and type(z.dst) == "boolean", z.name .. " " .. tostring(z.offset))
  check("the local offset now agrees with parts", time.parts(now, "local").offset == z.offset)
  check("duration reads the runtime's units, sums of them, and plain seconds", time.duration("1h30m") == 5400 and time.duration("1h 30m 5s") == 5405
    and time.duration("250ms") == 0.25 and time.duration("2d") == 172800 and time.duration("1.5h") == 5400 and time.duration(7) == 7)
  check("human picks two units", time.human(93784) == "1d 2h" and time.human(3725) == "1h 2m" and time.human(65) == "1m 5s" and time.human(5.25) == "5.2s"
    and time.human(0.25) == "250ms" and time.human(-90) == "-1m 30s", time.human(93784))

  local none, e = time.parse("2026-02-30")
  check("a day that does not exist is TIME badvalue", none == nil and err.is(e, "TIME", "badvalue"), tostring(e))
  none, e = time.parse("2026-13-01T00:00:00Z")
  check("a month out of range is TIME badvalue", none == nil and err.is(e, "TIME", "badvalue"))
  none, e = time.parse("yesterday")
  check("prose is TIME badvalue", none == nil and err.is(e, "TIME", "badvalue"))
  none, e = time.parse("2026-09-09T14:03:05Zjunk")
  check("trailing text is TIME badvalue", none == nil and err.is(e, "TIME", "badvalue"))
  local ok, raised = pcall(time.iso, t, { zone = "Mars/Olympus" })
  check("an unknown zone raises TIME badvalue", not ok and err.is(raised, "TIME", "badvalue"), tostring(raised))
  ok, raised = pcall(time.make, { month = 1 })
  check("make needs a year", not ok and err.is(raised, "TIME", "badvalue"))
  ok, raised = pcall(time.duration, "soon")
  check("a bad duration raises TIME badvalue", not ok and err.is(raised, "TIME", "badvalue"))
end
