-- Service inspection is read-only; mutation errors use a name that cannot exist.
global none
global <const> require, ipairs, type, tostring, pcall, math

return function(T)
  local check = T.check
  local svc, err, sched = require "svc", require "err", require "sched"
  local rows, e = svc.list()
  check("list returns services", type(rows) == "table" and #rows > 0, tostring(e))
  local eventlog, sorted, typed = false, true, true
  for i, row in ipairs(rows or {}) do
    if row.name == "EventLog" then eventlog = true end
    if i > 1 and rows[i - 1].name > row.name then sorted = false end
    typed = typed and type(row.name) == "string" and type(row.display) == "string"
      and type(row.state) == "string" and type(row.start) == "string" and math.type(row.pid) == "integer"
  end
  check("list contains EventLog and is sorted with typed fields", eventlog and sorted and typed)
  local dns, de = svc.status("Dnscache")
  check("Dnscache is running with its pid and configured executable", dns ~= nil and dns.state == "running"
    and dns.pid > 0 and type(dns.exe) == "string" and #dns.exe > 0, tostring(de))
  local status = svc.status("EventLog")
  if status then
    local began = sched.clock()
    local ok, we = svc.wait("EventLog", status.state, 0)
    check("waiting for the current state with zero timeout succeeds at once", ok == true and sched.clock() - began < 1, tostring(we))
    local ticks = 0
    local other = sched.spawn(function() sched.sleep("10ms"); ticks = ticks + 1 end)
    local target = status.state == "running" and "stopped" or "running"
    local late, le = svc.wait("EventLog", target, "60ms")
    other:join()
    check("a wait times out without blocking other tasks", late == nil and err.is(le, "SVC", "timeout") and ticks == 1, tostring(le))
  end
  local missing = "kuu-test-no-such-service-6a573dd0"
  for _, method in ipairs({ "status", "start", "stop", "restart" }) do
    local result, me = svc[method](missing)
    check(method .. " reports SVC notfound for an absent service", result == nil and err.is(me, "SVC", "notfound"), tostring(me))
  end
  for _, name in ipairs({ "", "Dnscache\0ignored", "bad/name", "\255", 42, false }) do
    local ok, be = pcall(svc.status, name)
    check("malformed service names raise SVC badvalue", not ok and err.is(be, "SVC", "badvalue"), tostring(be))
  end
  local ok, be = pcall(svc.wait, "EventLog", "invented", 0)
  check("unknown states raise SVC badvalue", not ok and err.is(be, "SVC", "badvalue"), tostring(be))
  ok, be = pcall(svc.restart, missing, "eventually")
  check("transition timeouts are checked before a service is touched", not ok and err.is(be, "SVC", "badvalue"), tostring(be))
end
