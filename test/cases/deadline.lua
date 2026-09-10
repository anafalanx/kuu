-- Deadlines compose around loop waits and preserve ownership.
global none
global <const> require, pcall, error, tostring, assert, table, coroutine, collectgarbage, string, tonumber

return function(T)
  local sched, err, proc, fs = require 'sched', require 'err', require 'proc', require 'fs'
  local started = sched.clock()
  local ok, e = sched.deadline('20ms', function() sched.sleep('1s'); return true end)
  T.check('deadline interrupts sleep with its named error', ok == nil and err.is(e, 'SCHED', 'deadline') and sched.clock() - started < 0.5, tostring(e))
  T.check('returned deadline error carries no private token', e._token == nil)
  local results = table.pack(sched.deadline('1s', function(a, b) return a, nil, b, nil end, 7, 'value'))
  T.check('unexpired deadline preserves arguments, nils, and result count', results.n == 4 and results[1] == 7 and results[2] == nil and results[3] == 'value' and results[4] == nil)
  local marker = err.new('TEST', 'marker', 'same object')
  local caught, raised = pcall(sched.deadline, '1s', function() error(marker) end)
  T.check('a function error passes through unchanged', not caught and raised == marker)
  ok, e = sched.deadline('1s', function()
    local value, problem = sched.deadline('10ms', function() sched.sleep('100ms') end)
    T.check('shorter inner deadline returns to its own scope', value == nil and err.is(problem, 'SCHED', 'deadline'))
    sched.sleep('10ms')
    return 'outer survived'
  end)
  T.check('outer scope survives an inner deadline', ok == 'outer survived', tostring(e))
  local after_inner = false
  ok, e = sched.deadline('10ms', function()
    sched.deadline('1s', function() sched.sleep('100ms') end)
    after_inner = true
  end)
  T.check('shorter outer deadline crosses inner scope', ok == nil and err.is(e, 'SCHED', 'deadline') and not after_inner, tostring(e))
  local independent = sched.spawn(function() sched.sleep('40ms'); return 'independent' end)
  ok, e = sched.deadline('5ms', function() return independent:join() end)
  T.check('deadline abandons a join without canceling its task', ok == nil and err.is(e, 'SCHED', 'deadline') and independent:join() == 'independent')
  local c <close> = assert(proc.start { T.exe, '-e', "require('sched').sleep('120ms'); print('ready')", stream = true, timeout = '2s' })
  ok, e = sched.deadline('10ms', function() return c:read('line') end)
  T.check('deadline removes a parked stream reader', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  T.check('the child and its unread bytes survive deadline', c:running() and c:read('line', '1s') == 'ready')
  c:wait('1s')
  ok, e = sched.deadline('10ms', function()
    return proc.run { T.exe, '-e', "require('sched').sleep('200ms')", timeout = '300ms' }
  end)
  T.check('deadline surrounds proc.run', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  local retained_marker = fs.absolute(fs.join(T.work, 'deadline-run-retained.txt'))
  if fs.exists(retained_marker) then assert(fs.remove(retained_marker)) end
  local retained_script = string.format([[global none
global <const> require, assert, tostring
local pid = require('sys').info().pid
require('sched').sleep('150ms')
assert(require('fs').write(%q, tostring(pid)))
]], retained_marker)
  ok, e = sched.deadline('10ms', function()
    return proc.run { T.exe, '-e', retained_script, timeout = '3s' }
  end)
  T.check('a run can leave a deadline before its child finishes', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  collectgarbage('collect')
  collectgarbage('collect')
  local until_marker = sched.clock() + 2
  while not fs.exists(retained_marker) and sched.clock() < until_marker do sched.sleep('10ms') end
  local retained_pid = tonumber(fs.read(retained_marker) or '')
  T.check('an abandoned run keeps its child alive through garbage collection', retained_pid ~= nil)
  if retained_pid then
    local until_exit = sched.clock() + 2
    while proc.alive(retained_pid) and sched.clock() < until_exit do sched.sleep('10ms') end
    T.check('the retained child exits normally afterwards', not proc.alive(retained_pid))
    assert(fs.remove(retained_marker))
  end
  local group <close> = assert(proc.start { T.exe, '-e', "require('sched').sleep('80ms')", timeout = '2s' })
  ok, e = sched.deadline('5ms', function() return proc.wait_all {group} end)
  T.check('deadline unlinks aggregate process waits', ok == nil and err.is(e, 'SCHED', 'deadline') and group:wait('1s').status == 'exit')
  local short <close> = assert(proc.start { T.exe, '-e', "require('sched').sleep('100ms')", timeout = '2s' })
  ok, e = sched.deadline('1s', function() return short:wait('5ms') end)
  T.check('a shorter call timeout keeps its own domain', ok == nil and err.is(e, 'PROC', 'timeout'), tostring(e))
  short:wait('1s')
  ok, e = sched.deadline('10ms', function()
    return ('x'):gsub('x', function() sched.sleep('100ms'); return '' end)
  end)
  T.check('deadline works through an in-place callback wait', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  local wrapped = coroutine.wrap(function()
    return sched.deadline('5ms', function() sched.sleep('100ms') end)
  end)
  ok, e = wrapped()
  T.check('deadline works in a user-created coroutine', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  local dir = fs.join(T.work, 'deadline-watch')
  assert(fs.mkdir(dir))
  local watch <close> = assert(fs.watch(dir))
  ok, e = sched.deadline('5ms', function() return watch:read() end)
  T.check('deadline unlinks a filesystem watch wait', ok == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  assert(fs.write(fs.join(dir, 'after.txt'), 'after'))
  T.check('watch remains usable after deadline', watch:read('1s') ~= nil)
  local finished = false
  ok = sched.deadline(0, function() finished = true; return 'no wait' end)
  T.check('deadline does not interrupt computation without a wait', finished and ok == 'no wait')
  caught, raised = pcall(sched.deadline, 'bad', function() end)
  T.check('invalid deadline duration is SCHED badvalue', not caught and err.is(raised, 'SCHED', 'badvalue'))
  caught, raised = pcall(sched.deadline, '1s', false)
  T.check('invalid deadline function is SCHED badvalue', not caught and err.is(raised, 'SCHED', 'badvalue'))
  sched.sleep('20ms')
  T.check('scope restoration leaves later waits unrestricted', true)
end
