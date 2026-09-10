-- Service transitions poll on the coroutine loop, sharing one timeout per call.
global none
global <const> require, error, type, math, table

return function(svc)
  local sched, err, cli = require "sched", require "err", require "cli"
  local start, stop, list = svc.start, svc.stop, svc.list
  local states = { running = true, stopped = true, start_pending = true, stop_pending = true,
    paused = true, pause_pending = true, continue_pending = true }

  local function duration(timeout)
    local seconds = timeout == nil and 30 or cli.duration(timeout)
    if seconds == nil then error(err.new("SVC", "badvalue", "timeout must be a duration"), 3) end
    return seconds
  end

  local function wait_until(name, state, deadline)
    while true do
      local status, e = svc.status(name)
      if not status then return nil, e end
      if status.state == state then return true end
      local remaining = deadline - sched.clock()
      if remaining <= 0 then return nil, err.new("SVC", "timeout", "service '" .. name .. "' did not reach " .. state) end
      sched.sleep(math.min(0.1, remaining))
    end
  end

  function svc.list()
    local rows, e = list()
    if not rows then return nil, e end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
  end

  function svc.wait(name, state, timeout)
    if type(state) ~= "string" or not states[state] then
      error(err.new("SVC", "badvalue", "unknown service state"), 2)
    end
    return wait_until(name, state, sched.clock() + duration(timeout))
  end

  local function transition(name, state, deadline)
    local status, e = svc.status(name)
    if not status then return nil, e end
    if status.state == state then return true end
    local pending = state == "running" and "start_pending" or "stop_pending"
    if status.state ~= pending then
      local ok
      if state == "running" then ok, e = start(name) else ok, e = stop(name) end
      if not ok then return nil, e end
    end
    return wait_until(name, state, deadline)
  end

  function svc.start(name, timeout)
    return transition(name, "running", sched.clock() + duration(timeout))
  end
  function svc.stop(name, timeout)
    return transition(name, "stopped", sched.clock() + duration(timeout))
  end
  function svc.restart(name, timeout)
    local deadline = sched.clock() + duration(timeout)
    local ok, e = transition(name, "stopped", deadline)
    if not ok then return nil, e end
    return transition(name, "running", deadline)
  end
end
