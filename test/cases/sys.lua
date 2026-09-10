-- sys.lua -- facts about this machine: shape, types, and sanity.
global none
global <const> require, ipairs, tostring, type, string, math, pcall, os, assert

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

  local fs, err, rt = require "fs", require "err", require "rt"
  local unsigned, ue = sys.signature(T.root .. "/build/test/http_fixture.exe")
  check("an unsigned executable has only signed=false", unsigned ~= nil and unsigned.signed == false
    and unsigned.valid == nil and unsigned.signer == nil, tostring(ue))
  local absent, ae = sys.signature(T.work .. "/signature-no-such-file.exe")
  check("a missing signature path is SYS notfound", absent == nil and err.is(ae, "SYS", "notfound"), tostring(ae))
  for _, options in ipairs({ { revocation = "true" }, { timeout = "1s" }, true, { ["revocation\0other"] = true } }) do
    local ok, be = pcall(sys.signature, rt.exe, options)
    check("bad signature options raise SYS badvalue", not ok and err.is(be, "SYS", "badvalue"), tostring(be))
  end
  local ok, be = pcall(sys.signature, rt.exe .. "\0other")
  check("signature refuses NUL in a path", not ok and err.is(be, "SYS", "badvalue"), tostring(be))
  ok, be = pcall(sys.signature, 42)
  check("signature needs a string path", not ok and err.is(be, "SYS", "badvalue"), tostring(be))
  local own, oe = sys.signature(rt.exe)
  check("the running executable can be inspected", own ~= nil, tostring(oe))
  local sched = require "sched"
  local late, deadline_error = sched.deadline(0, function() return sys.signature(rt.exe) end)
  check("an enclosing deadline can abandon signature verification", late == nil
    and err.is(deadline_error, "SCHED", "deadline"), tostring(deadline_error))
  local again, again_error = sys.signature(rt.exe)
  check("verification still works after an abandoned wait", again ~= nil, tostring(again_error))
  if own and own.signed then
    check("the signed release names its owner", own.signer and own.signer:find("Vincent Vercauteren", 1, true) ~= nil, own.signer)
  end
  -- Development builds are unsigned; Explorer supplies an embedded signature
  -- on stock Windows. Never alter it: corrupt only a copy in the test workspace.
  local signed_path, signed = rt.exe, own
  if not signed or not signed.signed then
    signed_path = fs.join(os.getenv("WINDIR") or "C:/Windows", "explorer.exe")
    signed = sys.signature(signed_path)
  end
  if signed and signed.signed and signed.valid then
    check("a valid signature carries certificate identity and a timestamp flag", type(signed.signer) == "string"
      and type(signed.issuer) == "string" and type(signed.thumbprint) == "string" and #signed.thumbprint == 40
      and type(signed.timestamped) == "boolean")
    local bytes = assert(fs.read(signed_path))
    local changed = bytes:sub(1, 64) .. string.char((bytes:byte(65) + 1) % 256) .. bytes:sub(66)
    local copy = T.work .. "/signature-tampered.exe"
    assert(fs.write(copy, changed))
    local invalid, ie = sys.signature(copy)
    check("altered signed content is reported as tampered", invalid ~= nil and invalid.signed == true
      and invalid.valid == false and invalid.reason == "tampered", tostring(ie or (invalid and invalid.reason)))
    assert(fs.remove(copy))
  end
end
