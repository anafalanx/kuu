-- Job-wide limits: real children, bounded by a separate wall-clock timeout.
global none
global <const> require, ipairs, pcall, tostring, assert

return function(T)
  local proc, err, fs = require 'proc', require 'err', require 'fs'
  local fixture = fs.join(T.root, 'build/test/limits_fixture.exe')
  for _, kind in ipairs { 'memory', 'cpu' } do
    local limits = kind == 'memory' and { memory = '64M' } or { cpu = '1s' }
    local r = proc.run { fixture, kind, limits = limits, timeout = '8s' }
    T.check(kind .. ' limit is a named outcome', r and r.status == 'limit' and r.limit == kind,
      r and (r.status .. ' ' .. tostring(r.limit) .. ' ' .. r.err))
    T.check(kind .. ' limited child has no survivor', r and not proc.alive(r.pid))
  end
  local batch = fs.join(T.work, 'limit-processes.cmd')
  assert(fs.write(batch, '@echo off\r\nstart /b cmd.exe /c ping -n 10 127.0.0.1 > nul\r\nstart /b cmd.exe /c ping -n 10 127.0.0.1 > nul\r\nping -n 10 127.0.0.1 > nul\r\n'))
  local r = proc.run { batch, limits = { processes = 2 }, timeout = '8s' }
  T.check('process count breach terminates the job', r and r.status == 'limit' and r.limit == 'processes',
    r and (r.status .. ' ' .. tostring(r.limit) .. ' ' .. r.err))
  T.check('process limited child has no survivor', r and not proc.alive(r.pid))
  local c <close> = proc.start { T.exe, '-e', 'print("within")', limits = { memory = '128M', cpu = '2s', processes = 1 } }
  r = c:wait('5s')
  T.check('start and wait keep an ordinary result below the limits', r and r.status == 'exit' and r.code == 0 and r.limit == nil)
  for _, limits in ipairs { false, {memory=0}, {memory=-1}, {cpu=0}, {cpu='bad'}, {processes=0}, {processes=1.5}, {unknown=1}, {['cpu\0junk']='1s'}, {[true]=1}, {[1]=1} } do
    local ok, e = pcall(proc.run, { T.exe, '-e', '', limits = limits })
    T.check('invalid child limit is PROC badvalue', not ok and err.is(e, 'PROC', 'badvalue'), tostring(e))
  end
  local ok, e = pcall(proc.detach, { T.exe, '-e', '', limits = {} })
  T.check('detach refuses limits', not ok and err.is(e, 'PROC', 'usage'), tostring(e))
  ok, e = pcall(proc.run, { T.exe, '-e', '', ['limits\0junk'] = {} })
  T.check('NUL option suffixes cannot name another option', not ok and err.is(e, 'PROC', 'badvalue'), tostring(e))
end
