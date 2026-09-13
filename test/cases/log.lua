-- log.lua -- the logger: format, levels, sinks, never raising.
global none
global <const> require, tostring, type, pcall, error, select, io, ipairs

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local log = require "log"
  local err = require "err"
  local json = require "json"

  local lines = {}
  local settings = log.configure { sink = function(line) lines[#lines + 1] = line end, level = "debug" }
  check("configure returns the settings", settings.level == "debug" and settings.sink == true and settings.dropped == 0)

  check("info returns true when emitted", log.info("built", { target = "out/x.exe", bytes = 307200, ok = true }) == true)
  check("the line has a timestamp, level, message, sorted quoted fields",
    #lines == 1 and lines[1]:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d%d%d INFO  built bytes=307200 ok=true target=out/x%.exe$") ~= nil, lines[1])
  log.warn("spaces here", { note = 'has "quotes" and spaces', empty = "" })
  check("values with spaces or quotes are quoted and escaped", contains(lines[2], 'WARN  spaces here empty="" note="has \\"quotes\\" and spaces"'), lines[2])
  log.error("failed", { e = err.new("PROC", "notfound", "no git") })
  check("error objects render through tostring", contains(lines[3], 'ERROR failed e="PROC notfound: no git"'), lines[3])
  log.debug("nested", { t = { a = 1 } })
  check("table fields render as JSON, quoted like any value with quotes", contains(lines[4], 'DEBUG nested t="{\\"a\\":1}"'), lines[4])
  log.info("odd", "not a table")
  check("a non-table second argument becomes value=", contains(lines[5], "odd value=\"not a table\""), lines[5])

  log.configure { level = "warn" }
  check("below the level is filtered and returns false", log.info("quiet") == false and #lines == 5)
  check("at the level passes", log.warn("loud") == true and #lines == 6)
  log.configure { level = "off" }
  check("off silences everything", log.error("nothing") == false and #lines == 6)

  local failing = 0
  log.configure { level = "info", sink = function() failing = failing + 1; error("sink broke") end }
  check("a failing sink never raises and counts dropped", log.info("x") == false and log.configure().dropped == 1 and failing == 1)

  local path = T.work .. "/log-test.txt"
  local fs = require "fs"
  if fs.exists(path) then fs.remove(path) end
  log.configure { sink = false, file = path }
  log.info("to file", { n = 1 })
  log.info("again")
  log.configure { file = false }
  local content = fs.read(path)
  check("a file sink appends lines", content and select(2, content:gsub("\n", "")) == 2 and contains(content, "INFO  to file n=1") and contains(content, "again"), tostring(content))

  local captured = {}
  log.configure { sink = function(line) captured[#captured + 1] = line end, json = true }
  log.info("as json", { count = 2, name = "kuu", flag = false })
  local record = json.decode(captured[1])
  check("json mode writes one object per line", record and record.level == "info" and record.msg == "as json" and record.count == 2
    and record.name == "kuu" and record.flag == false and type(record.ts) == "string", captured[1])
  do
    local cyclic = {}; cyclic.self = cyclic
    for index, input in ipairs {
      { "bad\255", {} }, { "invalid field", { value = "bad\255" } }, { "cyclic field", { value = cyclic } },
    } do
      local before, count = log.configure().dropped, #captured
      local safe, emitted = pcall(log.info, input[1], input[2])
      check("an unencodable JSON record is dropped without emitting plain text: case " .. index,
        safe and emitted == false and #captured == count and log.configure().dropped == before + 1)
    end
    check("a dropped JSON record leaves the selected format usable", log.info("after failure", { count = 3 }) == true
      and json.decode(captured[#captured]).count == 3)
    log.configure { json = false }
    log.info("numeric keys", { [1] = "alpha", ["1"] = "beta", [2] = "two words" })
    check("text fields keep the values of numeric and string keys with the same spelling",
      contains(captured[#captured], 'numeric keys 1=alpha 1=beta 2="two words"'), captured[#captured])
    local before, count = log.configure().dropped, #captured
    local safe, emitted = pcall(log.info, "cyclic text field", { value = cyclic })
    check("a failed text-field render also drops the complete record without raising",
      safe and emitted == false and #captured == count and log.configure().dropped == before + 1)
  end
  log.configure { json = false, sink = false }

  local ok, e = pcall(log.configure, { level = "loud" })
  check("an unknown level is refused", not ok and err.is(e, "LOG", "badvalue"), tostring(e))
  ok, e = pcall(log.configure, { colour = true })
  check("an unknown option is refused", not ok and err.is(e, "LOG", "usage"), tostring(e))
  ok, e = pcall(log.configure, "loud")
  check("a non-table is LOG badvalue, a wrong value rather than a wrong option", not ok and err.is(e, "LOG", "badvalue"), tostring(e))
  ok, e = pcall(log.configure, { file = T.work .. "/no-such-dir/x.log", level = "debug" })
  check("a file that cannot be opened is refused and nothing changes", not ok and err.is(e, "LOG", "oserror") and log.configure().level == "info", tostring(e))
  do
    local cyclic = {}; cyclic.self = cyclic
    local before = log.configure().dropped
    local safe, emitted = pcall(log.info, cyclic)
    check("a cyclic message never raises and counts its drop", safe and emitted == false and log.configure().dropped == before + 1)
    local original = io.stderr
    io.stderr = { write = function() return nil, "simulated write failure", 28 end }
    before = log.configure().dropped
    safe, emitted = pcall(log.info, "cannot write")
    io.stderr = original
    check("a returned I/O failure counts as a dropped log record", safe and emitted == false and log.configure().dropped == before + 1)
    log.configure { sink = function() return nil, "sink failed" end }
    check("a sink may return a failure instead of raising", log.info("x") == false)
    log.configure { sink = false }
    local open = io.open
    io.open = function()
      return { write = function(self) return self end,
        flush = function() return nil, "simulated flush failure" end, close = function() return true end }
    end
    local configured, problem = pcall(log.configure, { file = path })
    io.open = open
    before = log.configure().dropped
    safe, emitted = pcall(log.info, "cannot flush")
    log.configure { file = false }
    check("a returned flush failure counts as a dropped log record", configured and safe and emitted == false
      and log.configure().dropped == before + 1, tostring(problem))
  end
end
