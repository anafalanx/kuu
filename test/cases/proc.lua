-- proc.lua -- children: run, start, wait, kill, close, detach, stdin, output
-- bounds, environment, working directory, quoting, and the no-orphans law.
global none
global <const> require, ipairs, tostring, tonumber, type, string, io, pcall, table, error

return function(T)
  local check, kuu, describe, contains, starts = T.check, T.kuu, T.describe, T.contains, T.starts
  local proc = require "proc"
  local sched = require "sched"
  local err = require "err"
  local exe = T.exe

  local function wait_until(predicate, seconds)
    local deadline = sched.clock() + (seconds or 5)
    while sched.clock() < deadline do
      if predicate() then return true end
      sched.sleep("25ms")
    end
    return predicate()
  end

  -- run --------------------------------------------------------------------------
  local r = proc.run { "cmd.exe", "/c", "echo hello" }
  check("run captures stdout and the exit code", r and r.status == "exit" and r.code == 0 and r.out == "hello\r\n", r and describe(r))
  check("run reports pid, elapsed, truncated",
    r and type(r.pid) == "number" and r.pid > 0 and type(r.elapsed) == "number" and r.elapsed >= 0 and r.truncated == false and r.err == "")

  r = proc.run { "cmd.exe", "/c", "exit 3" }
  check("exit codes come through", r and r.status == "exit" and r.code == 3, r and describe(r))

  r = proc.run("cmd.exe", "/c", "echo", "positional")
  check("the positional form works", r and r.out == "positional\r\n", r and describe(r))

  r = kuu { "-e", "io.stderr:write('to-err') io.write('to-out')" }
  check("stdout and stderr are captured apart", r.out == "to-out" and r.err == "to-err", describe(r))

  r = kuu { "-e", "io.write(...)", "héllo wörld €", "a\"quoted\" arg", "back\\slash\\", "" }
  check("arguments round-trip through Windows quoting", r.out == "héllo wörld €a\"quoted\" argback\\slash\\", describe(r))

  local none, e = proc.run { "kuu-no-such-program-anywhere" }
  check("a missing program is nil, PROC notfound", none == nil and err.is(e, "PROC", "notfound"), tostring(e))

  local ok, e2 = pcall(proc.run, {})
  check("an empty command is a raised usage error", not ok and err.is(e2, "PROC", "usage"), tostring(e2))

  ok, e2 = pcall(proc.run, { "cmd.exe", cwdd = "x" })
  check("an unknown option is a raised usage error", not ok and err.is(e2, "PROC", "usage") and contains(tostring(e2), "cwdd"), tostring(e2))

  ok, e2 = pcall(proc.run, { "cmd.exe", timeout = "soon" })
  check("a bad duration is a raised badvalue", not ok and err.is(e2, "PROC", "badvalue"), tostring(e2))

  ok, e2 = pcall(proc.run, { "cmd.exe", "a\0b" })
  check("a NUL byte in an argument is refused", not ok and err.is(e2, "PROC", "badvalue"), tostring(e2))

  -- stdin ------------------------------------------------------------------------
  local bytes = "line\n\0nul\255\254 " .. "héllo" .. string.rep("z", 1000)
  r = kuu({ "-e", "io.write(io.read('a'))" }, { stdin = bytes })
  check("stdin bytes reach the child exactly", r.out == bytes, describe(r))

  local large = string.rep("0123456789abcdef", 5 * 1024 * 1024 // 16)
  r = kuu({ "-e", "local d = io.read('a'); io.write(#d, ' ', d:sub(1, 16), ' ', d:sub(-16))" }, { stdin = large })
  check("a 5 MiB stdin is delivered while output is read", r.out == #large .. " 0123456789abcdef 0123456789abcdef", describe(r))

  r = kuu({ "-e", "io.write('never read stdin')" }, { stdin = string.rep("x", 1024 * 1024) })
  check("a child that never reads stdin still completes", r.status == "exit" and r.out == "never read stdin", describe(r))

  -- output bounds ------------------------------------------------------------------
  r = kuu { "-e", "local c = string.rep('x', 1 << 20); for i = 1, 20 do io.write(c) end" }
  check("20 MiB of output is captured in full", r.status == "exit" and #r.out == 20 * 1024 * 1024 and r.truncated == false, tostring(#r.out))

  r = proc.run { exe, "-e", "local c = string.rep('x', 1 << 20); for i = 1, 4 do io.write(c) end", maxout = "1M" }
  check("maxout caps the capture and flags truncation", r and #r.out == 1024 * 1024 and r.truncated == true and r.status == "exit", r and tostring(#r.out))

  -- timeout, kill, the tree --------------------------------------------------------
  r = proc.run { exe, "-e", "require('sched').sleep('30s')", timeout = "300ms" }
  check("a timeout kills the child and says so", r and r.status == "timeout" and r.elapsed < 10, r and describe(r))

  local pidfile = T.work .. "/grandchild.pid"
  T.write_file(pidfile, "")
  local parent = proc.start { exe, "-e", string.format([[
    local proc, sched = require('proc'), require('sched')
    local g = proc.start { require('rt').exe, '-e', "require('sched').sleep('60s')" }
    local f = io.open(%q, 'wb'); f:write(tostring(g.pid)); f:close()
    sched.sleep('60s')
  ]], pidfile) }
  check("start returns a running child with a pid", parent.pid > 0 and parent:running(), tostring(parent))
  local grandchild
  wait_until(function()
    local text = T.read_file(pidfile)
    grandchild = tonumber(text)
    return grandchild ~= nil
  end, 10)
  check("the grandchild started", grandchild ~= nil and proc.alive(grandchild), tostring(grandchild))
  local none2, e3 = parent:wait("100ms")
  check("wait with a timeout returns nil, PROC timeout", none2 == nil and err.is(e3, "PROC", "timeout"), tostring(e3))
  parent:kill()
  r = parent:wait()
  check("kill ends the child with status killed", r and r.status == "killed", r and describe(r))
  check("killing the child killed the grandchild", wait_until(function() return not proc.alive(grandchild) end, 5))
  check("a finished child is not running", parent:running() == false)
  parent:close()
  ok, e2 = pcall(parent.wait, parent)
  check("using a closed child raises PROC closed", not ok and err.is(e2, "PROC", "closed"), tostring(e2))

  r = kuu { "-e", "local c = require('proc').start { require('rt').exe, '-e', \"require('sched').sleep('60s')\" }; io.write(c.pid)" }
  local orphan = tonumber(r.out)
  check("a child started and abandoned by an exiting program dies with it",
    orphan ~= nil and wait_until(function() return not proc.alive(orphan) end, 5), describe(r))

  local closed_pid
  do
    local c <close> = proc.start { exe, "-e", "require('sched').sleep('60s')" }
    closed_pid = c.pid
  end
  check("a <close> child is killed when its block ends", wait_until(function() return not proc.alive(closed_pid) end, 5))

  -- environment and working directory ------------------------------------------------
  r = kuu({ "-e", "io.write(tostring(os.getenv('KUU_TEST_VAR')))" }, { env = { KUU_TEST_VAR = "value ünïcode" } })
  check("env adds a variable", r.out == "value ünïcode", describe(r))

  r = kuu({ "-e", [[local p = require('proc'); local rr = p.run { require('rt').exe, '-e', "io.write(tostring(os.getenv('KUU_TEST_VAR')))", env = { KUU_TEST_VAR = false } }; io.write(rr.out)]] },
    { env = { KUU_TEST_VAR = "set" } })
  check("env = false removes a variable", r.out == "nil", describe(r))

  r = kuu({ "-e", "io.write(tostring(os.getenv('PATH') ~= nil))" }, { env = { KUU_OTHER = "1" } })
  check("the rest of the environment is inherited", r.out == "true", describe(r))

  ok, e2 = pcall(proc.run, { "cmd.exe", env = { ["BAD=NAME"] = "x" } })
  check("an environment name with '=' is refused", not ok and err.is(e2, "PROC", "badvalue"), tostring(e2))

  r = kuu({ "-e", "io.write(tostring(io.open('hello.lua') ~= nil))" }, { cwd = T.fixtures })
  check("cwd sets the child's working directory", r.out == "true", describe(r))

  none, e = proc.run { "cmd.exe", "/c", "cd", cwd = T.work .. "/no-such-directory" }
  check("a missing cwd is nil, PROC error", none == nil and err.is(e, "PROC"), tostring(e))

  -- batch files -----------------------------------------------------------------------
  r = proc.run { T.fixtures .. "/echo_arg.cmd", "a&b" }
  check("a batch argument with & is passed literally", r and r.status == "exit" and contains(r.out, "a&b") and not contains(r.out, "not recognized"), r and describe(r))

  r = proc.run { T.fixtures .. "/echo_arg.cmd", "%PATH%" }
  check("a batch argument with % is not expanded", r and contains(r.out, "%PATH%"), r and describe(r))

  -- concurrency -------------------------------------------------------------------------
  local tasks = {}
  local started = sched.clock()
  for i = 1, 40 do
    tasks[i] = sched.spawn(function() return kuu { "-e", "io.write(...)", "child-" .. i } end)
  end
  local all_good = true
  for i = 1, 40 do
    local rr = tasks[i]:join()
    if rr.out ~= "child-" .. i or rr.code ~= 0 then all_good = false end
  end
  check("40 concurrent children all report correctly", all_good, tostring(sched.clock() - started) .. "s")

  -- detach, alive, kill ------------------------------------------------------------------
  local pid, e4 = proc.detach { exe, "-e", "require('sched').sleep('30s')" }
  check("detach returns a pid", pid ~= nil and pid > 0, tostring(e4))
  check("the detached process is alive", pid ~= nil and proc.alive(pid))
  local killed = pid and proc.kill(pid)
  check("proc.kill terminates by pid", killed == true and wait_until(function() return not proc.alive(pid) end, 5))

  r = kuu { "-e", "io.write(require('proc').detach { require('rt').exe, '-e', \"require('sched').sleep('30s')\" })" }
  local survivor = tonumber(r.out)
  check("a detached process outlives the program that started it", survivor ~= nil and proc.alive(survivor), describe(r))
  if survivor then proc.kill(survivor) end

  check("alive is false for an impossible pid", proc.alive(999999999) == false)
  local nk, e5 = proc.kill(999999999)
  check("kill of a missing pid is nil, PROC notfound", nk == nil and err.is(e5, "PROC", "notfound"), tostring(e5))

  -- waiting where yielding is impossible ----------------------------------------------------
  local via_gsub = ("x"):gsub("x", function() return proc.run { "cmd.exe", "/c", "echo inner" }.out end)
  check("run works inside a non-yieldable callback", via_gsub == "inner\r\n", via_gsub)
end
