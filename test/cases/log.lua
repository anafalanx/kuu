-- log.lua -- the logger: format, levels, sinks, never raising.
global none
global <const> require, tostring, type, pcall, error, select

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
  log.configure { json = false, sink = false }

  local ok, e = pcall(log.configure, { level = "loud" })
  check("an unknown level is refused", not ok and err.is(e, "LOG", "badvalue"), tostring(e))
  ok, e = pcall(log.configure, { colour = true })
  check("an unknown option is refused", not ok and err.is(e, "LOG", "usage"), tostring(e))
  ok, e = pcall(log.configure, { file = T.work .. "/no-such-dir/x.log", level = "debug" })
  check("a file that cannot be opened is refused and nothing changes", not ok and err.is(e, "LOG", "oserror") and log.configure().level == "info", tostring(e))
end
