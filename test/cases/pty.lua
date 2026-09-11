global none
global <const> require, assert, tostring, ipairs, pcall, load, collectgarbage, tonumber, pairs

return function(T)
  local pty, proc, sched, err, rt = require 'pty', require 'proc', require 'sched', require 'err', require 'rt'
  local p <close> = assert(pty.spawn { 'cmd.exe', '/d', '/q', timeout = '15s' })
  local text, which = p:expect({ '>' }, '3s')
  T.check('pty expects the cmd prompt', text ~= nil and which == 1, tostring(which))
  assert(p:write('echo kuu-console-ready\r'))
  text, which = p:expect({ 'missing', 'kuu%-console%-ready' }, '3s')
  T.check('pty matches Lua patterns and reports their index', text ~= nil and which == 2, tostring(which))
  assert(p:write('set /p name=Enter:\r'))
  assert(p:expect({ 'Enter:' }, '3s'))
  assert(p:write('kuu\r'))
  assert(p:write('echo received:%name%\r'))
  text = p:expect({ 'received:kuu' }, '3s')
  T.check('pty drives cmd console input', text ~= nil, tostring(text))
  local before = sched.clock()
  local value, e = p:expect({ 'never-observed-pattern' }, '20ms')
  T.check('pty timeout leaves child alive', value == nil and err.is(e, 'PTY', 'timeout') and proc.alive(p.pid) and sched.clock() - before < 0.5, tostring(e))
  value, e = sched.deadline('10ms', function() return p:read('1s') end)
  T.check('pty reads obey enclosing deadlines', value == nil and err.is(e, 'SCHED', 'deadline'), tostring(e))
  assert(p:write('echo after-deadline\r'))
  T.check('pty reader is reusable after deadline', p:expect({ 'after%-deadline' }, '3s') ~= nil)
  local waiter = sched.spawn(function() return p:expect({ 'never-observed-pattern' }, '100ms') end)
  sched.sleep('10ms')
  local ok, raised = pcall(p.read, p, 0)
  T.check('pty refuses concurrent readers', not ok and err.is(raised, 'PTY', 'busy'), tostring(raised))
  waiter:join()
  assert(p:write('exit\r'))
  local result = assert(p:wait('3s'))
  T.check('pty wait observes clean exit', result.status == 'exit' and result.code == 0)
  while p:read('1s') do end
  T.check('pty text strips terminal controls', p:text():find('\27', 1, true) == nil)
  value, e = p:expect({ 'never-observed-pattern' }, 0)
  T.check('pty expect reports EOF as closed', value == nil and err.is(e, 'PTY', 'closed'))
  p:close(); p:close()
  ok, raised = pcall(p.text, p)
  T.check('pty close is idempotent and methods reject closed handles', not ok and err.is(raised, 'PTY', 'closed'))

  local fixture = T.root .. '/build/test/pty_fixture.exe'
  local plain = assert(proc.run { fixture })
  T.check('console fixture requires console handles', plain.code == 7)
  local console <close> = assert(pty.spawn { fixture, cols = 120, rows = 30, timeout = '10s' })
  assert(console:expect({ 'Console input:' }, '3s'))
  assert(console:resize(80, 24))
  assert(console:write('caf\195\169\r'))
  local all = ''
  while true do local bytes, why = console:read('3s'); if not bytes then assert(why == nil, tostring(why)); break end; all = all .. bytes end
  T.check('pty supports ReadConsoleW, Unicode and resize', console:text():find('received:caf\195\169', 1, true) ~= nil and console:text():find('size:80,24', 1, true) ~= nil, console:text())
  T.check('pty exposes raw VT bytes', all:find('\27', 1, true) ~= nil)
  T.check('pty console fixture exits without lingering conhost', console:wait('3s').code == 0)
  value, e = console:resize(80, 24)
  T.check('a console whose job has exited refuses resize', value == nil and err.is(e, 'PTY', 'closed'), tostring(e))

  local volume <close> = assert(pty.spawn { fixture, 'volume', maxout = '2M', timeout = '10s' })
  text = volume:expect({ 'VOLUME%-DONE' }, '8s')
  T.check('pty drains output beyond pipe capacity without deadlock', text ~= nil and #volume:text() > 65536, tostring(text and #text))
  assert(volume:wait('3s'))
  local tiny <close> = assert(pty.spawn { fixture, 'volume', maxout = 8, timeout = '5s' })
  value, e = tiny:expect({ 'VOLUME%-DONE' }, '2s')
  T.check('pty transcript cap reports toobig', value == nil and err.is(e, 'PTY', 'toobig'), tostring(e))
  tiny:close()
  local pid
  do
    local child <close> = assert(pty.spawn { 'cmd.exe', '/d', '/q' })
    pid = child.pid
    assert(child:expect({ '>' }, '3s'))
  end
  local due = sched.clock() + 3
  while proc.alive(pid) and sched.clock() < due do sched.sleep('10ms') end
  T.check('pty scope close kills its child', not proc.alive(pid))

  local own_pid = require('sys').info().pid
  local function conhosts()
    local found = {}
    for _, entry in ipairs(proc.list()) do
      if entry.parent == own_pid and entry.name:lower() == 'conhost.exe' then found[entry.pid] = true end
    end
    return found
  end
  local function fresh_hosts(baseline)
    local found = {}
    for host in pairs(conhosts()) do if not baseline[host] then found[#found + 1] = host end end
    return found
  end
  local shutdown_source = [[global none
global <const> require, assert
local pty, rt, sched = require 'pty', require 'rt', require 'sched'
local p = assert(pty.spawn { rt.args[1], rt.args[2], maxout = 8 })
sched.sleep('100ms')
]]
  for _, mode in ipairs { 'input', 'volume' } do
    local finished = T.kuu({ '-e', shutdown_source, fixture, mode }, {timeout='5s'})
    T.check('program shutdown joins console cleanup with pending ' .. mode,
      finished.status == 'exit' and finished.code == 0, T.describe(finished))
  end

  local finalized = T.kuu({ '-e', [[global none
global <const> require, assert, setmetatable
local pty, proc = require 'pty', require 'proc'
local finalizer = setmetatable({}, {__gc=function()
  assert(proc.run { 'cmd.exe', '/d', '/c', 'exit', '0' }.code == 0)
end})
for _ = 1, 8 do
  local p = assert(pty.spawn { 'cmd.exe', '/d', '/q' })
  p:close()
end
]] }, {timeout='5s'})
  T.check('shutdown completes canceled console I/O while Lua finalizers run other children',
    finalized.status == 'exit' and finalized.code == 0, T.describe(finalized))

  finalized = T.kuu({ '-e', [[global none
global <const> require, assert, setmetatable
local pty, proc = require 'pty', require 'proc'
local finalizer = setmetatable({}, {__gc=function()
  assert(proc.run { 'cmd.exe', '/d', '/c', 'exit', '0' }.code == 0)
end})
local console = assert(pty.spawn { 'cmd.exe', '/d', '/c', 'echo', 'final output' })
assert(console:wait('3s').code == 0)
-- Leave the exited console open: its final read can still be pending when
-- its own finalizer runs, before the earlier finalizer pumps the loop.
]] }, {timeout='5s'})
  T.check('an exited console can finalize before another finalizer pumps the loop',
    finalized.status == 'exit' and finalized.code == 0, T.describe(finalized))

  local baseline = conhosts()
  do
    local descendant <close> = assert(pty.spawn { fixture, 'descendant', timeout = '5s' })
    assert(descendant:expect({ 'PARENT%-DONE' }, '3s'))
    value, e = descendant:wait('10ms')
    T.check('console completion waits for a descendant after the first process exits',
      value == nil and err.is(e, 'PTY', 'timeout'), tostring(e))
    assert(descendant:expect({ 'DESCENDANT%-DONE' }, '3s'))
    local tail, failure = descendant:read('3s')
    while tail do tail, failure = descendant:read('3s') end
    T.check('last console descendant produces final output and EOF without explicit close',
      failure == nil and descendant:wait('3s').code == 0, tostring(failure))
  end
  do
    -- Stop consuming well below the producer's output volume. close must
    -- remain bounded even on the OS with synchronous console teardown.
    local unread = assert(pty.spawn { fixture, 'volume', maxout = 8, timeout = '5s' })
    sched.sleep('100ms')
    local started = sched.clock()
    unread:close()
    T.check('closing a console with unread blocked output does not block the loop',
      sched.clock() - started < 0.5)
  end
  do
    local fs = require 'fs'
    local invalid = T.work .. '/invalid-console-program.exe'
    assert(fs.write(invalid, 'not an executable'))
    value, e = pty.spawn { invalid }
    T.check('a failed native console launch returns its launch error',
      value == nil and err.is(e, 'PTY', 'launch'), tostring(e))
  end
  due = sched.clock() + 3
  while #fresh_hosts(baseline) > 0 and sched.clock() < due do sched.sleep('10ms') end
  T.check('natural exit, blocked output and failed launch leave no console host', #fresh_hosts(baseline) == 0)

  local tree_pid, descendant_pid, host_pids
  do
    local child_source = [[global none
global <const> require, assert, print
local proc, rt, sched = require 'proc', require 'rt', require 'sched'
local child <close> = assert(proc.start { rt.exe, '-e', "require('sched').sleep('20s')" })
print('descendant:' .. child.pid)
sched.sleep('20s')
]]
    local tree <close> = assert(pty.spawn { rt.exe, '-e', child_source, timeout = '10s' })
    tree_pid = tree.pid
    local seen = assert(tree:expect({ 'descendant:%d+\n' }, '3s'))
    descendant_pid = tonumber(seen:match('descendant:(%d+)'))
    host_pids = fresh_hosts(baseline)
    T.check('a console subtree has a live supervised descendant and a visible conhost', descendant_pid ~= nil
      and proc.alive(descendant_pid) and #host_pids > 0)
  end
  due = sched.clock() + 3
  while sched.clock() < due do
    local alive = proc.alive(tree_pid) or (descendant_pid and proc.alive(descendant_pid))
    for _, host in ipairs(host_pids) do alive = alive or proc.alive(host) end
    if not alive then break end
    sched.sleep('10ms')
  end
  T.check('scope close kills both the console child and its descendant', not proc.alive(tree_pid)
    and descendant_pid ~= nil and not proc.alive(descendant_pid))
  local lingering = false
  for _, host in ipairs(host_pids) do lingering = lingering or proc.alive(host) end
  T.check('scope close leaves no conhost from its session', not lingering)

  -- Closing immediately exercises client startup racing with job termination.
  baseline = conhosts()
  local rapid = {}
  for i = 1, 8 do
    local early = assert(pty.spawn { 'cmd.exe', '/d', '/q', timeout = '3s' })
    rapid[i] = early.pid
    early:close()
  end
  due = sched.clock() + 3
  local alive
  repeat
    sched.sleep('10ms')
    alive = #fresh_hosts(baseline) > 0
    for _, child_pid in ipairs(rapid) do alive = alive or proc.alive(child_pid) end
  until not alive or sched.clock() >= due
  T.check('rapid close during startup leaves no child or conhost', not alive)

  local closing = assert(pty.spawn { 'cmd.exe', '/d', '/q', timeout = '5s' })
  assert(closing:expect({ '>' }, '3s'))
  local blocked = sched.spawn(function() return closing:expect({ 'never-shown' }, '3s') end)
  sched.sleep('10ms')
  closing:close()
  value, e = blocked:join('2s')
  T.check('closing a console wakes its parked reader with PTY closed', value == nil and err.is(e, 'PTY', 'closed'), tostring(e))

  for _, spec in ipairs { {}, { 'cmd.exe', cols = 0 }, { 'cmd.exe', rows = 2.5 }, { 'cmd.exe', maxout = 0 }, { 'cmd.exe', stdin = '' } } do
    ok, raised = pcall(pty.spawn, spec)
    T.check('pty validates command options', not ok and err.is(raised, 'PTY', 'badvalue'), tostring(raised))
  end
  value, e = pty.spawn { 'kuu-pty-missing-09-2026.exe' }
  T.check('pty missing command returns notfound', value == nil and err.is(e, 'PTY', 'notfound'))

  -- Exercise the real filter across adversarial byte boundaries, independently
  -- of conhost's renderer batching. The native launch is replaced with a stream.
  local loader = assert(load(rt.source('pty.console'), '@pty-console-test', 't'))()
  local chunks = { '\27[3', '1mabc\bD\rX\27]0;ti', 'tle\27', '\\Y\n\195', '\169>' }
  local next_chunk = 0
  local mock = { _spawn = function() return { pid = 1, read = function() next_chunk = next_chunk + 1; return chunks[next_chunk] end, close = function() end } end, _resize = function() return true end }
  loader(mock)
  local filtered <close> = assert(mock.spawn { 'fixture' })
  while filtered:read() do end
  T.check('pty VT filter handles split CSI, OSC, UTF8, CR and backspace', filtered:text() == 'XYD\n\195\169>', filtered:text())
  ok, raised = pcall(filtered.expect, filtered, { '[' }, 0)
  T.check('pty reports malformed patterns as badvalue', not ok and err.is(raised, 'PTY', 'badvalue'), tostring(raised))
  ok, raised = pcall(filtered.expect, filtered, { [1] = 'x', [3] = 'y' }, 0)
  T.check('pty refuses sparse pattern arrays', not ok and err.is(raised, 'PTY', 'badvalue'), tostring(raised))

  local function stream(chunks_for_test)
    local at = 0
    local module = {
      _spawn = function() return { pid = 1, read = function() at = at + 1; return chunks_for_test[at] end,
        close = function() end } end,
      _resize = function() return true end,
    }
    loader(module)
    return assert(module.spawn { 'fixture' })
  end
  for _, rewritten in ipairs { 'xyz>', 'abc>' } do
    local prompt <close> = stream { 'abc>', '\r' .. rewritten }
    assert(prompt:expect({ '>' }, 0))
    value, e = prompt:expect({ '>' }, 0)
    T.check('a rewritten prompt becomes available even when its bytes repeat', value == rewritten and e == 1, tostring(value))
  end
  local empty <close> = stream { 'abc' }
  assert(empty:read())
  local advances = true
  for _ = 1, 4 do
    value, e = empty:expect({ '' }, 0)
    advances = advances and value == '' and e == 1
  end
  value, e = empty:expect({ '' }, 0)
  T.check('empty matches advance through the buffer and then stop', advances and value == nil and err.is(e, 'PTY', 'closed'), tostring(e))
  local deferred_bad <close> = stream { 'abc' }
  ok, raised = pcall(deferred_bad.expect, deferred_bad, { 'a[' }, 0)
  T.check('patterns malformed only on nonempty input still raise PTY badvalue', not ok and err.is(raised, 'PTY', 'badvalue'), tostring(raised))
  -- Cross the transcript bound without depending on OS batching.
  local cap_module = { _spawn = function() return { pid = 1, read = function() return 'xx' end,
    close = function() end } end, _resize = function() return true end }
  loader(cap_module)
  local poison <close> = assert(cap_module.spawn { 'fixture', maxout = 1 })
  value, e = poison:read()
  local first_failure = value == nil and err.is(e, 'PTY', 'toobig')
  value, e = poison:expect({ 'x' }, 0)
  T.check('transcript overflow remains an error on later operations', first_failure and value == nil and err.is(e, 'PTY', 'toobig'), tostring(e))
  local cached_chunks, cached_at = { 'ready', 'overflow' }, 0
  local cached_module = { _spawn = function() return { pid = 1, read = function()
    cached_at = cached_at + 1; return cached_chunks[cached_at]
  end, close = function() end } end, _resize = function() return true end }
  loader(cached_module)
  local cached <close> = assert(cached_module.spawn { 'fixture', maxout = 5 })
  assert(cached:read() == 'ready')
  value, e = cached:read()
  local overflowed = value == nil and err.is(e, 'PTY', 'toobig')
  value, e = cached:expect({ 'ready' }, 0)
  T.check('cached matches cannot hide an earlier transcript overflow', overflowed
    and value == nil and err.is(e, 'PTY', 'toobig'), tostring(e))
  collectgarbage('collect')
end
