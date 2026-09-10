-- Public parser contracts, arbitrary bytes, and independently known values.
global none
global <const> require, assert, tonumber, tostring, type, pcall, xpcall, string, table, math, io, os, ipairs, pairs, utf8

local rt, time, cli, fs, err = require "rt", require "time", require "cli", require "fs", require "err"
local csv, ini, json, reg = require "csv", require "ini", require "json", require "reg"
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
local csv_texts = { "", '""', "a,b\r\n1,2\r\n", '"a,b","c""d"\n', '"unfinished', 'a"b,c', '"a"tail,b',
  "a,b\n1\n", "\239\187\191name,value\r\né,漢字\r\n", "a\0b,c", '"line\r\nbreak",x', "a,b," }
local ini_texts = { "", "key=value\n", "[Server]\r\nport = 80\r\n", "[kuu_fuzz]\nvalue=old\n[KUU_FUZZ]\nVALUE=new\n",
  "; comment\n# comment\n", '[x]\nkey=" quoted "\n', "\239\187\191[x]\nkey=漢字\n", "[unfinished", "[x]\na\0b=c", "bare-key\n" }
local json_texts = { "", "null", "false", "0", "-9223372036854775808", "9223372036854775807", "1e9999", "[]", "{}",
  '{"a":1,"a":2}', '["\\ud800"]', '["\\ud83d\\ude00"]', '{"nul":"\\u0000","é":"漢字"}', "true\0false",
  "[1,]", "{", string.rep("[", 513) .. "0" .. string.rep("]", 513) }
local registry_keys = { "", "HKCU", "hkey_current_user", "HKXX\\bad", "HKCU\\Software\\kuu-parser-fuzz-no-such-key",
  "HKCU/Software/kuu-parser-fuzz-no-such-key/漢字", "HKCU\0ignored", "HKCU\\Software\\bad\0suffix", "HKCU\\\255", "\\HKCU", "HKCU\\" }

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

local function csv_decode(s)
  context("csv.decode", s)
  local ok, rows, e = pcall(csv.decode, s, { ragged = true })
  assert(ok, "CSV parser raised: " .. tostring(rows))
  if rows == nil then assert(err.is(e, "CSV", "parse"), tostring(e)); return end
  assert(type(rows) == "table")
  for _, row in ipairs(rows) do
    assert(type(row) == "table")
    for _, cell in ipairs(row) do assert(type(cell) == "string") end
  end
  local encoded = csv.encode(rows)
  local back = assert(csv.decode(encoded, { ragged = true }))
  assert(#back == #rows, "CSV row count changed on round trip")
  for i, row in ipairs(rows) do
    assert(#back[i] == #row, "CSV field count changed on round trip")
    for j, cell in ipairs(row) do assert(back[i][j] == cell, "CSV bytes changed on round trip") end
  end
end

local function ini_decode(s)
  context("ini.decode", s)
  local ok, sections = pcall(ini.decode, s)
  assert(ok and type(sections) == "table", "INI parser failed: " .. tostring(sections))
  for section, values in pairs(sections) do
    assert(type(section) == "string" and type(values) == "table")
    for key, value in pairs(values) do assert(type(key) == "string" and type(value) == "string") end
  end
end

local function ini_set(s, value)
  context("ini.set", s .. "\0VALUE\0" .. value)
  local ok, updated = pcall(ini.set, s, "kuu_fuzz", "value", value)
  if value:find("[\r\n]") then
    assert(not ok and err.is(updated, "INI", "badvalue"), "INI accepted a multiline value")
  else
    assert(ok and type(updated) == "string", tostring(updated))
    assert(ini.get(ini.decode(updated), "kuu_fuzz", "value") == value, "INI edit did not preserve the requested value")
  end
end

local function json_decode(s)
  context("json.decode", s)
  local ok, value, e = pcall(json.decode, s)
  assert(ok, "JSON parser raised: " .. tostring(value))
  if value == nil then
    assert(err.is(e, "JSON", "parse") or err.is(e, "JSON", "depth") or err.is(e, "JSON", "duplicate"), tostring(e))
  end
end

local function registry_key(s)
  context("registry key", s)
  -- Existence only: no fuzzed value is read and no registry key is ever written.
  local ok, exists = pcall(reg.exists, s)
  if s:find("\0", 1, true) or utf8.len(s) == nil then
    assert(not ok and err.is(exists, "REG", "badvalue"), "REG accepted NUL or invalid UTF-8")
  elseif ok then
    assert(type(exists) == "boolean")
  else
    assert(err.is(exists, "REG", "badvalue"), tostring(exists))
  end
end

local ok, failure = xpcall(function()
  for _, s in ipairs(durations) do duration(s) end
  for _, s in ipairs(dates) do date(s) end
  for _, s in ipairs(paths) do path(s) end
  for _, s in ipairs(csv_texts) do csv_decode(s) end
  for _, s in ipairs(ini_texts) do ini_decode(s); ini_set(s, "replacement") end
  for _, s in ipairs(json_texts) do json_decode(s) end
  for _, s in ipairs(registry_keys) do registry_key(s) end
  for i = 1, cases do
    iteration = i
    duration(mutate(durations))
    date(mutate(dates))
    path(mutate(paths))
    csv_decode(mutate(csv_texts))
    local ini_input = mutate(ini_texts)
    ini_decode(ini_input)
    ini_set(ini_input, bytes(pick(65)))
    json_decode(mutate(json_texts))
    registry_key(mutate(registry_keys))

    -- Known values cover acceptance as well as malformed input rejection.
    local field = bytes(pick(129))
    context("CSV generated round trip", field)
    local records = assert(csv.decode(csv.encode({ { field, "é,漢字" }, { "", '"quoted"' } })))
    assert(records[1][1] == field and records[1][2] == "é,漢字" and records[2][1] == "" and records[2][2] == '"quoted"')
    local integer = (pick(0x1000000) << 32) | pick(0x1000000)
    local json_source = context("JSON exact integer round trip", json.encode({ integer = integer, values = json.array { json.null, false, "é\0漢字" } }))
    local decoded = assert(json.decode(json_source))
    assert(decoded.integer == integer and math.type(decoded.integer) == "integer")
    assert(json.is_array(decoded.values) and decoded.values[1] == json.null and decoded.values[2] == false and decoded.values[3] == "é\0漢字")

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
io.write(string.format("duration/date/path/csv/ini/json/registry fuzz: %d cases each, seed %d passed\n", cases, seed))
