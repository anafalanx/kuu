-- Public parser contracts, arbitrary bytes, and independently known values.
global none
global <const> require, assert, tonumber, tostring, type, pcall, xpcall, string, table, math, io, os, ipairs, utf8

local rt, time, cli, fs, err = require "rt", require "time", require "cli", require "fs", require "err"
local cases, seed = tonumber(rt.args[1]), tonumber(rt.args[2])
assert(cases and math.type(cases) == "integer" and cases > 0 and cases <= 1000000)
assert(seed and math.type(seed) == "integer" and seed > 0 and seed <= 0xffffffff)
local state = seed
local function pick(limit)
  state = (state * 1664525 + 1013904223) & 0xffffffff
  return (state >> 8) % limit
end

local iteration, family, input = 0, "", ""
local function context(kind, value) family, input = kind, value; return value end
local function bytes(n)
  local out = {}
  for i = 1, n do out[i] = string.char(pick(256)) end
  return table.concat(out)
end
local function mutate(corpus)
  local s = corpus[pick(#corpus) + 1]
  local pos, mode = pick(#s + 1), pick(5)
  if mode == 0 then return s:sub(1, pos) end
  if mode == 1 then return s:sub(1, pos) .. bytes(1 + pick(8)) .. s:sub(pos + 1) end
  if mode == 2 then return s:sub(1, pos) .. s:sub(pos + 2) end
  if mode == 3 then return bytes(pick(257)) end
  return s .. string.rep(string.char(pick(256)), pick(4097))
end

local durations = { "", "0", "1h30m", "250ms", "0.0005s", "2d 3h", "9e9s", "-1", "nan", "inf", "1\0s", "9000000000001s", "0x10", "1.2.3s" }
local dates = { "", "2026-09-10", "2000-02-29T12:34:56.789Z", "2024-12-31T24:00:00+14:00", "0000-01-01", "9999-12-31", "2026-09-10T", "2026-09-10T01:02:03-02:30", "2026-09-10\0ignored" }
local paths = { "", ".", "..", "C:", "C:/", "C:/a/../b", "//server/share/a", "\\\\?\\C:\\x", "\\\\?\\", "\\\\.\\", "a. ", "漢字/é.txt", "a\0b" }

local function duration(s)
  context("duration", s)
  local ok, value = pcall(time.duration, s)
  local parsed = cli.duration(s)
  if ok then
    assert(type(value) == "number" and value >= 0 and value <= 9e12 and value == value)
    assert(parsed == value, "CLI/time duration disagreement")
  else
    assert(err.is(value, "TIME", "badvalue"), tostring(value))
    assert(parsed == nil, "CLI accepted a rejected duration")
  end
end
local function date(s)
  context("date", s)
  local ok, value, e = pcall(time.parse, s, "utc")
  assert(ok, "date parser raised: " .. tostring(value))
  assert(value == nil and err.is(e, "TIME", "badvalue") or type(value) == "number" and value == value)
end
local function path(s)
  context("path", s)
  local ok, value = pcall(fs.absolute, s)
  if ok then
    assert(type(value) == "string" and utf8.len(value) ~= nil and not value:find("\0", 1, true))
  else
    assert(err.is(value, "FS"), tostring(value))
  end
end

local ok, failure = xpcall(function()
  for _, s in ipairs(durations) do duration(s) end
  for _, s in ipairs(dates) do date(s) end
  for _, s in ipairs(paths) do path(s) end
  for i = 1, cases do
    iteration = i
    duration(mutate(durations))
    date(mutate(dates))
    path(mutate(paths))

    -- Known arithmetic checks acceptance as well as rejection.
    local hours, minutes, ms = pick(1000), pick(60), pick(60000)
    local s = context("duration arithmetic", string.format("%dh %dm %dms", hours, minutes, ms))
    local expected = hours * 3600 + minutes * 60 + ms / 1000
    assert(math.abs(time.duration(s) - expected) < 0.000001)

    -- Generate real instants, then check ISO milliseconds and numeric zones.
    local instant = (946684800000 + pick(1000000000) * 1000 + pick(1000)) / 1000
    local iso = context("ISO round trip", time.iso(instant, { ms = true }))
    assert(time.parse(iso, "utc") == instant)
    local offset = pick(841)
    local zone = context("zone", string.format("%s%02d:%02d", pick(2) == 0 and "+" or "-", offset // 60, offset % 60))
    iso = context("zoned ISO round trip", time.iso(instant, { zone = zone, ms = true }))
    assert(time.parse(iso) == instant)

    -- Lexical only: fuzzing never opens or writes a fuzzed path.
    s = context("path normalization", string.format("fuzz/漢字-%d/../é-%d.txt", pick(10000), pick(10000)))
    local absolute = fs.absolute(s)
    assert(fs.absolute(absolute) == absolute)
    assert(fs.absolute(absolute:gsub("/", "\\")) == absolute)
  end
end, tostring)
if not ok then
  io.stderr:write(string.format("parser fuzz failed: seed=%d case=%d family=%s\ninput hex=%s\n%s\n",
    seed, iteration, family, (input:gsub(".", function(c) return string.format("%02x", c:byte()) end)), failure))
  os.exit(1)
end
io.write(string.format("duration/date/path fuzz: %d cases each, seed %d passed\n", cases, seed))
