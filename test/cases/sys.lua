-- sys.lua -- facts about this machine: shape, types, and sanity.
global none
global <const> require, ipairs, tostring, type, string, math

return function(T)
  local check = T.check
  local sys = require "sys"

  local i = sys.info()
  check("windows: a build at or above Windows 11, a dotted version, a display name, a server flag",
    type(i.windows) == "table" and math.type(i.windows.build) == "integer" and i.windows.build >= 22000
    and i.windows.version == ("10.0." .. i.windows.build) and type(i.windows.display) == "string" and i.windows.display:match("^%d%dH%d$") ~= nil
    and type(i.windows.server) == "boolean" and math.type(i.windows.revision) == "integer",
    tostring(i.windows.build) .. " " .. tostring(i.windows.version) .. " " .. tostring(i.windows.display))
  check("hostname and user are non-empty strings", type(i.hostname) == "string" and #i.hostname > 0 and type(i.user) == "string" and #i.user > 0)
  check("elevated is a boolean", type(i.elevated) == "boolean")
  check("cpus is a positive integer and arch is named", math.type(i.cpus) == "integer" and i.cpus >= 1 and (i.arch == "x64" or i.arch == "arm64"), tostring(i.arch))
  check("memory has total above available", type(i.memory) == "table" and i.memory.total > i.memory.available and i.memory.available > 0)
  local has_c = false
  for _, d in ipairs(i.drives) do
    if d.letter == "C:" and d.type == "fixed" then has_c = true end
  end
  check("drives list C: as a fixed drive with letter and type", has_c, tostring(#i.drives))
  check("uptime is seconds, pid is this process, codepage is an integer", type(i.uptime) == "number" and i.uptime > 0
    and math.type(i.pid) == "integer" and i.pid > 0 and math.type(i.codepage) == "integer")
  check("process reports handles and memory of this process", type(i.process) == "table" and i.process.handles > 0
    and i.process.working_set > 0 and i.process.peak_working_set >= i.process.working_set and i.process.private > 0,
    tostring(i.process and i.process.handles))
  local j = sys.info()
  check("each call is a fresh table", j ~= i and j.pid == i.pid)
end
