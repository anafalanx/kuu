-- net.lua -- the network from here: resolve, probe, listeners, addresses,
-- against the loopback fixture and well-known unroutable addresses.
global none
global <const> require, ipairs, tostring, type, math, pcall, tonumber

return function(T)
  local check, describe = T.check, T.describe
  local net = require "net"
  local proc = require "proc"
  local err = require "err"
  local fs = require "fs"
  local sched = require "sched"

  -- resolve ----------------------------------------------------------------------
  local locals = net.resolve("localhost")
  local has_loopback = false
  for _, a in ipairs(locals or {}) do
    if a.address == "127.0.0.1" or a.address == "::1" then has_loopback = true end
  end
  check("localhost resolves to a loopback address with its family named",
    has_loopback and (locals[1].family == "ipv4" or locals[1].family == "ipv6"), tostring(locals and #locals))
  local literal = net.resolve("192.0.2.7")
  check("an IPv4 literal resolves to itself", literal ~= nil and #literal == 1 and literal[1].address == "192.0.2.7" and literal[1].family == "ipv4",
    tostring(literal and literal[1] and literal[1].address))
  local six = net.resolve("::1")
  check("an IPv6 literal resolves to itself", six ~= nil and #six == 1 and six[1].address == "::1" and six[1].family == "ipv6",
    tostring(six and six[1] and six[1].address))
  local none, e = net.resolve("no-such-host.invalid")
  check("an unknown name is nil, NET resolve", none == nil and err.is(e, "NET", "resolve"), tostring(e))
  local okb, eb = pcall(net.resolve, "")
  check("resolve refuses an empty name", not okb and err.is(eb, "NET", "badvalue"), tostring(eb))
  local okt, et = pcall(net.resolve, "localhost", "soon")
  check("resolve wants a duration for its timeout", not okt and err.is(et, "NET", "badvalue"), tostring(et))

  -- probe and listeners against the fixture --------------------------------------
  local fixture = T.root .. "/build/test/http_fixture.exe"
  if fs.exists(fixture) == "file" then
    local server <close> = proc.start { fixture, (T.fixtures:gsub("/", "\\")), stream = true }
    local port = tonumber((server:read("line", "10s") or ""):match("^PORT (%d+)$"))
    check("the fixture reports its port", port ~= nil)
    if port ~= nil then
      local r = net.probe("127.0.0.1", port, "5s")
      check("probe reaches the fixture and says which address answered and how long it took",
        r ~= nil and r.address == "127.0.0.1" and r.family == "ipv4" and type(r.elapsed) == "number" and r.elapsed >= 0 and r.elapsed < 5,
        tostring(r and r.address or r))
      local named = net.probe("localhost", port)
      check("probe resolves a name first", named ~= nil and (named.address == "127.0.0.1" or named.address == "::1"), tostring(named))
      local mine
      for _, l in ipairs(net.listeners()) do
        if l.port == port and l.pid == server.pid then mine = l end
      end
      check("listeners shows the fixture's port with its address, family, pid, and name",
        mine ~= nil and mine.name:lower() == "http_fixture.exe" and mine.family == "ipv4" and mine.address == "127.0.0.1", mine and describe(mine))
      server:kill()
    end
  else
    check("the http fixture server is built (make fixtures)", false, fixture)
  end

  local refused, e2 = net.probe("127.0.0.1", 1, "3s")
  check("a closed port is nil, NET refused", refused == nil and err.is(e2, "NET", "refused"), tostring(e2))
  local t0 = sched.clock()
  local dark, e3 = net.probe("192.0.2.1", 81, "400ms") -- TEST-NET-1 is never routed
  check("an address that never answers is NET timeout or unreachable, within the timeout",
    dark == nil and (err.is(e3, "NET", "timeout") or err.is(e3, "NET", "unreachable")) and sched.clock() - t0 < 3, tostring(e3))
  local okp, ep = pcall(net.probe, "127.0.0.1", 70000)
  check("probe refuses a bad port", not okp and err.is(ep, "NET", "badvalue"), tostring(ep))
  local okh, eh = pcall(net.probe, 42, 80)
  check("probe wants a host", not okh and err.is(eh, "NET", "badvalue"), tostring(eh))

  -- the loop keeps running while a probe waits
  local ticks = 0
  local ticker = sched.spawn(function()
    for _ = 1, 4 do sched.sleep("50ms"); ticks = ticks + 1 end
  end)
  net.probe("192.0.2.2", 81, "300ms")
  ticker:join("2s")
  check("other tasks run while a probe waits for an answer", ticks == 4, tostring(ticks))

  -- listeners and addresses in general -------------------------------------------
  local listeners = net.listeners()
  local sorted = true
  for i = 2, #listeners do
    if listeners[i - 1].port > listeners[i].port then sorted = false end
  end
  check("listeners is sorted by port, each with a pid", #listeners > 0 and sorted and math.type(listeners[1].pid) == "integer", tostring(#listeners))
  local addresses = net.addresses()
  local loopback4 = false
  for _, a in ipairs(addresses) do
    if a.address == "127.0.0.1" and a.loopback == true and a.family == "ipv4" then loopback4 = true end
  end
  check("addresses includes the IPv4 loopback marked as such; each has adapter, prefix, up",
    loopback4 and type(addresses[1].adapter) == "string" and math.type(addresses[1].prefix) == "integer" and type(addresses[1].up) == "boolean",
    tostring(#addresses))
  do
    local ok, e = pcall(net.resolve, "localhost\0ignored")
    check("resolve refuses a NUL in the name", not ok and err.is(e, "NET", "badvalue"), tostring(e))
    ok, e = pcall(net.probe, "127.0.0.1\0ignored", 80)
    check("probe refuses a NUL in the host", not ok and err.is(e, "NET", "badvalue"), tostring(e))
    local scoped, se = net.resolve("fe80::1%1")
    check("resolving a scoped IPv6 literal preserves its interface",
      scoped and #scoped == 1 and scoped[1].family == "ipv6" and scoped[1].address == "fe80::1%1", tostring(se or (scoped and scoped[1].address)))
    local accepted, result, failure = pcall(net.probe, "fe80::1%1", 1, "100ms")
    check("probe accepts scoped IPv6 and returns a network outcome",
      accepted and (result ~= nil or err.is(failure, "NET", "timeout") or err.is(failure, "NET", "unreachable") or err.is(failure, "NET", "refused")), tostring(failure or result))
  end

end
