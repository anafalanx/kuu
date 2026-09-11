-- sync.lua -- one at a time across processes: try, lock with a timeout,
-- release, the <close> idiom, a holder in another process, abandonment.
global none
global <const> require, tostring, string, assert, pcall, collectgarbage,
               select

return function(T)
  local check, contains = T.check, T.contains
  local sync = require "sync"
  local sched = require "sched"
  local proc = require "proc"
  local err = require "err"
  local name = "kuu-test-" .. require("hash").uuid()

  local a, e = sync.try(name)
  check("try acquires a free lock, not abandoned", a ~= nil and a.abandoned == false, tostring(e))
  local none
  none, e = sync.try(name)
  check("a second try on a held lock is SYNC busy", none == nil and err.is(e, "SYNC", "busy"), tostring(e))
  local t0 = sched.clock()
  none, e = sync.lock(name, "80ms")
  check("lock waits and gives up after the timeout", none == nil and err.is(e, "SYNC", "busy") and sched.clock() - t0 >= 0.07, tostring(e))
  check("release is idempotent and says so", a:release() == true and a:release() == true and tostring(a) == "kuu.lock (released)")
  local b = sync.try(name)
  check("after release the lock is free again", b ~= nil)
  b:release()

  do
    local c <close> = assert(sync.try(name))
    local inner = sync.try(name)
    check("a lock in a to-be-closed variable is held inside its block", inner == nil and tostring(c) == "kuu.lock (held)")
  end
  local d = sync.try(name)
  check("and released when the block ends", d ~= nil)
  d:release()

  -- a lock dropped without release is released when it is collected
  ;(function() local dropped = assert(sync.try(name)) end)()
  local still_held = sync.try(name) == nil
  collectgarbage()
  collectgarbage()
  local collected = sync.try(name)
  check("a dropped lock is held until collected, and released by collection", still_held and collected ~= nil,
    tostring(still_held) .. " " .. tostring(select(2, sync.try(name))))
  if collected then collected:release() end

  -- another task holds it for a while; lock waits on the loop, other tasks run
  local holder = sched.spawn(function()
    local l <close> = assert(sync.try(name))
    sched.sleep("120ms")
    return "done"
  end)
  sched.sleep("1ms") -- let the holder run and take it
  local ticks = 0
  local ticker = sched.spawn(function() for _ = 1, 4 do sched.sleep("20ms") ticks = ticks + 1 end end)
  t0 = sched.clock()
  local f = sync.lock(name, "5s")
  local waited = sched.clock() - t0
  check("lock acquires once the holder lets go, after waiting on the loop", f ~= nil and waited >= 0.1 and holder:join() == "done", string.format("%.3f", waited))
  ticker:join()
  check("other tasks ran while lock waited", ticks == 4, tostring(ticks))
  f:release()

  -- another process holds it and is killed holding it: the kernel hands it over abandoned
  -- (a kuu that exits normally releases its locks as the state closes)
  local child <close> = proc.start { T.exe, "-e", "local s = require('sync'); local l = s.try('" .. name .. "'); io.write(l and 'held' or 'busy', '\\n'); io.flush(); require('sched').sleep('30s')", stream = true }
  local line = child:read("line", "5s")
  check("the child took the lock", line == "held", tostring(line))
  none, e = sync.try(name)
  check("while the child holds it, try is busy here", none == nil and err.is(e, "SYNC", "busy"), tostring(e))
  child:kill()
  child:wait("5s")
  local g = sync.try(name)
  check("after the child was killed holding it, try succeeds and says abandoned", g ~= nil and g.abandoned == true, tostring(g))
  g:release()
  local polite <close> = proc.start { T.exe, "-e", "local s = require('sync'); local l = assert(s.try('" .. name .. "')); io.write('held\\n'); io.flush()", stream = true }
  polite:read("line", "5s")
  polite:wait("5s")
  local h = sync.try(name)
  check("a kuu that exits normally releases its lock, so the next taker sees nothing abandoned", h ~= nil and h.abandoned == false, tostring(h))
  h:release()

  local ok, raised = pcall(sync.try, "with\\backslash")
  check("a name with a backslash is refused", not ok and err.is(raised, "SYNC", "badvalue"))
  ok, raised = pcall(sync.try, "")
  check("an empty name is refused", not ok and err.is(raised, "SYNC", "badvalue"))
  ok, raised = pcall(sync.lock, name, "soon")
  check("a bad timeout is refused", not ok and err.is(raised, "SYNC", "badvalue"))
  do
    local lock, e = sync.lock(name .. "-compound", "1m30s")
    check("lock timeouts accept the native compound duration grammar", lock ~= nil, tostring(e))
    if lock then lock:release() end
  end

end
