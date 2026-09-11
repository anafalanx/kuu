-- sched.lua -- tasks, sleep, join, timeouts, the non-yieldable fallback,
-- stray yields, and deadlock detection.
global none
global <const> require, ipairs, tostring, string, pcall, coroutine, select, table, error

return function(T)
  local check, kuu, describe, contains = T.check, T.kuu, T.describe, T.contains
  local sched = require "sched"
  local err = require "err"

  local orphan_fixture = require("env").get("KUU_TEST_ASAN") == "1"
    and "loop_orphan_asan.exe" or "loop_orphan_fixture.exe"
  local orphaned = require("proc").run {
    T.root .. "/build/test/" .. orphan_fixture, timeout = "10s"
  }
  check("orphaned I/O dispatch never reads its released source",
    orphaned.status == "exit" and orphaned.code == 0, describe(orphaned))

  -- sleep ----------------------------------------------------------------------
  local t0 = sched.clock()
  sched.sleep("100ms")
  local slept = sched.clock() - t0
  check("sleep waits about as long as asked", slept >= 0.09 and slept < 1.0, tostring(slept))

  t0 = sched.clock()
  sched.sleep(0.05)
  slept = sched.clock() - t0
  check("a number duration is seconds", slept >= 0.04 and slept < 1.0, tostring(slept))

  local ok, e = pcall(sched.sleep, "soon")
  check("a duration without a unit is refused", not ok and err.is(e, "SCHED", "badvalue"), tostring(e))

  -- spawn and join -------------------------------------------------------------
  local order = {}
  local a = sched.spawn(function(x) sched.sleep("60ms"); order[#order + 1] = "a"; return x, x * 2 end, 21)
  local b = sched.spawn(function() sched.sleep("10ms"); order[#order + 1] = "b"; return "b-done" end)
  local ra1, ra2 = a:join()
  local rb = b:join()
  check("join returns the task's results", ra1 == 21 and ra2 == 42 and rb == "b-done", tostring(ra1) .. " " .. tostring(ra2) .. " " .. tostring(rb))
  check("tasks interleave by their waits", order[1] == "b" and order[2] == "a", table.concat(order, ","))
  check("finished tasks report done", a:status() == "done" and b:status() == "done")

  local again1, again2 = a:join()
  check("joining twice returns the same results", again1 == 21 and again2 == 42)

  local failing = sched.spawn(function() sched.sleep("5ms"); error(err.new("TEST", "boom", "task failed")) end)
  ok, e = pcall(failing.join, failing)
  check("join re-raises the task's error", not ok and err.is(e, "TEST", "boom"), tostring(e))
  check("a failed task reports failed", failing:status() == "failed")

  local slow = sched.spawn(function() sched.sleep("300ms"); return "slow" end)
  local r, e2 = slow:join("30ms")
  check("join with a timeout returns nil, SCHED timeout", r == nil and err.is(e2, "SCHED", "timeout"), tostring(e2))
  check("the task keeps running after a join timeout", slow:status() == "running")
  check("a later join gets the result", slow:join() == "slow")

  local side = {}
  sched.spawn(function() sched.sleep("20ms"); side.ran = true end)
  sched.sleep("80ms")
  check("a task whose handle was dropped still runs", side.ran == true)

  local nested_result
  local outer = sched.spawn(function()
    local inner = sched.spawn(function() return "inner" end)
    nested_result = inner:join()
    return "outer"
  end)
  check("tasks can spawn and join tasks", outer:join() == "outer" and nested_result == "inner")

  local ticks = {}
  local t1 = sched.spawn(function() for i = 1, 3 do ticks[#ticks + 1] = "x" .. i; sched.sleep(0) end end)
  local t2 = sched.spawn(function() for i = 1, 3 do ticks[#ticks + 1] = "y" .. i; sched.sleep(0) end end)
  t1:join(); t2:join()
  check("sleep(0) lets other tasks run", table.concat(ticks, ",") == "x1,y1,x2,y2,x3,y3", table.concat(ticks, ","))

  local stray = sched.spawn(function() coroutine.yield() end)
  ok, e = pcall(stray.join, stray)
  check("a stray yield inside a task fails the task with SCHED yield", not ok and err.is(e, "SCHED", "yield"), tostring(e))

  -- the non-yieldable fallback ---------------------------------------------------
  local replaced = ("a"):gsub("a", function() sched.sleep("20ms"); return "b" end)
  check("waiting inside a non-yieldable callback works by pumping in place", replaced == "b", replaced)

  local wrapped = coroutine.wrap(function() sched.sleep("10ms"); return "from-coroutine" end)()
  check("waiting inside a program's own coroutine works", wrapped == "from-coroutine", tostring(wrapped))

  local background = {}
  sched.spawn(function() sched.sleep("5ms"); background.ran = true end)
  ;("a"):gsub("a", function() sched.sleep("50ms"); return "" end)
  check("other tasks progress while a non-yieldable wait pumps", background.ran == true)

  -- deadlock and the program boundary --------------------------------------------
  local rr = kuu { "-e", "local s = require('sched'); local t; t = s.spawn(function() s.sleep(0); return t:join() end); t:join()" }
  check("a wait nothing can satisfy is reported as SCHED deadlock", rr.code == 1 and contains(rr.err, "SCHED deadlock"), describe(rr))

  -- a join on itself from inside a gsub callback cannot yield, so the wait pumps
  -- in place, finds nothing, and raises; the waiter must leave the task's list
  -- before it is freed, or the task's own finish would wake freed memory
  rr = kuu { "-e", "local s = require('sched'); local t; t = s.spawn(function() local ok, e = pcall(function() return (('x'):gsub('x', function() return t:join() end)) end); return ok, tostring(e) end); print(t:join()); local u = s.spawn(function() s.sleep('5ms'); return 'later' end); print(u:join())" }
  check("a caught in-place deadlock leaves no dangling waiter behind", rr.code == 0 and rr.out == "false\tSCHED deadlock: nothing can wake this wait\nlater\n", describe(rr))

  rr = kuu { "-e", "local s = require('sched'); s.spawn(function() s.sleep('10s') end); print('main done')" }
  check("the program ends when the main chunk returns, whatever tasks remain", rr.code == 0 and rr.out == "main done\n" and rr.elapsed < 5, describe(rr))

  rr = kuu { "-e", "local s = require('sched'); local t = s.spawn(function() error('inside') end); local ok, e = pcall(t.join, t); print(ok, e)" }
  check("task errors carry their location", rr.code == 0 and contains(rr.out, "false\t(command line):1: inside"), describe(rr))
end
