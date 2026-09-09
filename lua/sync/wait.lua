-- sync/wait.lua -- the waiting half of sync: lock(name, timeout) on top of
-- try(name), sleeping on the loop so other tasks keep running.  Installed
-- into the sync table when the module opens.
global none
global <const> require, tostring, type, math, error

return function(sync)
  local sched = require "sched"
  local err = require "err"
  local cli = require "cli"

  -- sync.lock(name [, timeout]) -> lock | nil, err (SYNC busy after the timeout, default 30s)
  --   local lock <close> = assert(sync.lock("deploy", "10s"))
  function sync.lock(name, timeout)
    local ms = 30000
    if timeout ~= nil then
      ms = cli.duration(timeout)
      if ms == nil then error(err.new("SYNC", "badvalue", "the timeout must be a duration such as \"10s\""), 2) end
    end
    local deadline = sched.clock() + ms / 1000
    local pause = 1
    while true do
      local lock, e = sync.try(name)
      if lock then return lock end
      if not err.is(e, "SYNC", "busy") then return nil, e end
      if sched.clock() >= deadline then
        return nil, err.new("SYNC", "busy", "'" .. tostring(name) .. "' stayed held for " .. tostring(timeout or "30s"))
      end
      sched.sleep(pause .. "ms")
      pause = math.min(pause * 2, 50)
    end
  end
end
