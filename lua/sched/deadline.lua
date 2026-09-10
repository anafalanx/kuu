-- The scope token belongs to this coroutine, including across a yield.
global none
global <const> pcall, table, error, type, require

local err = require 'err'

return function(sched)
  local enter, leave = sched._deadline_enter, sched._deadline_leave
  sched._deadline_enter, sched._deadline_leave = nil, nil
  function sched.deadline(duration, fn, ...)
    if type(fn) ~= 'function' then
      error(err.new('SCHED', 'badvalue', 'deadline needs a function'), 2)
    end
    local scope <close> = enter(duration)
    local results = table.pack(pcall(fn, ...))
    leave(scope)
    if results[1] then return table.unpack(results, 2, results.n) end
    local raised = results[2]
    if type(raised) == 'table' and raised.domain == 'SCHED' and raised.code == 'deadline' and raised._token == scope then
      raised._token = nil
      return nil, raised
    end
    error(raised, 0)
  end
end
