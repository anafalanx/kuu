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

  -- streams ------------------------------------------------------------------------------------
  -- an echo child: uppercases each stdin line, reports on stderr, exits when stdin ends
  local echo = { exe, "-e", "for line in io.lines() do io.write('> ', line:upper(), '\\n') io.stdout:flush() io.stderr:write('got ', #line, '\\n') io.stderr:flush() end io.write('bye\\n')" }
  do
    local c <close> = proc.start { exe, echo[2], echo[3], stream = true }
    check("write queues bytes to stdin", c:write("hello\n") == true)
    check("read returns the next line without its ending", c:read("line", "5s") == "> HELLO")
    check("read_err reads the other stream", c:read_err("line", "5s") == "got 5")
    c:write("two\r\n")
    check("CRLF line endings are stripped too", c:read("line", "5s") == "> TWO")
    local none, e = c:read("line", "100ms")
    check("a read with nothing available times out", none == nil and err.is(e, "PROC", "timeout"), tostring(e))
    c:write("abcdef\n")
    check("read n bytes returns at most n", c:read(4, "5s") == "> AB")
    check("read some returns what is buffered", c:read("some", "5s") == "CDEF\n")
    check("close_stdin lets the child finish", c:close_stdin() == true and c:read("all", "5s") == "bye\n")
    check("read at EOF returns nil", c:read("line", "5s") == nil and c:read("some") == nil)
    local r = c:wait("5s")
    check("wait in stream mode reports status with empty out and err", r and r.status == "exit" and r.code == 0 and r.out == "" and r.err == "", r and describe(r))
  end

  do
    local c <close> = proc.start { exe, echo[2], echo[3], stream = true }
    c:write("a\nb\nc\n")
    c:close_stdin()
    local got = {}
    for line in c:lines() do got[#got + 1] = line end
    check("lines() iterates stdout to EOF", table.concat(got, "|") == "> A|> B|> C|bye", table.concat(got, "|"))
    local errs = {}
    for line in c:err_lines() do errs[#errs + 1] = line end
    check("err_lines() iterates stderr to EOF", table.concat(errs, "|") == "got 1|got 1|got 1", table.concat(errs, "|"))
    local none, e = c:write("late\n")
    check("writing after close_stdin is nil, PROC closed", none == nil and err.is(e, "PROC", "closed"), tostring(e))
  end

  -- backpressure: 20 MiB through a 1 MiB window, nothing truncated
  do
    local c <close> = proc.start { exe, "-e", "local chunk = string.rep('y', 1 << 20) for i = 1, 20 do io.write(chunk) end", stream = true, maxout = "1M" }
    c:close_stdin()
    local total = 0
    while true do
      local piece = c:read(1 << 18, "10s")
      if piece == nil then break end
      total = total + #piece
    end
    check("stream mode delivers everything with backpressure, never truncating", total == 20 * 1024 * 1024, tostring(total))
    check("the child finished normally", c:wait("5s").status == "exit")
  end

  do
    local c <close> = proc.start { exe, "-e", "require('sched').sleep('30s')", stream = true }
    local reader = sched.spawn(function() return c:read("line", "10s") end)
    sched.sleep("50ms")
    local ok2, e2b = pcall(c.read, c, "line", "10ms")
    check("a second reader on the same stream is refused as PROC busy", not ok2 and err.is(e2b, "PROC", "busy"), tostring(e2b))
    c:close()
    local r1, r2 = reader:join()
    check("a parked reader wakes with PROC closed when the child is closed", r1 == nil and err.is(r2, "PROC", "closed"), tostring(r2))
  end

  local ok3, e3b = pcall(proc.run, { exe, "-e", "print(1)", stream = true })
  check("run refuses stream mode", not ok3 and err.is(e3b, "PROC", "usage"), tostring(e3b))
  ok3, e3b = pcall(proc.start, { exe, stream = true, stdin = "x" })
  check("stream and stdin cannot be combined", not ok3 and err.is(e3b, "PROC", "usage"), tostring(e3b))
  ok3, e3b = pcall(proc.start, { exe, stream = true, inherit = true })
  check("stream and inherit cannot be combined", not ok3 and err.is(e3b, "PROC", "usage"), tostring(e3b))

  -- inherit: the child shares kuu's console; nothing is captured
  local inherited = proc.run { "cmd.exe", "/c", "exit 5", inherit = true }
  check("inherit runs with kuu's own handles and reports the code", inherited and inherited.status == "exit" and inherited.code == 5 and inherited.out == "", inherited and describe(inherited))

  -- wait_any / wait_all --------------------------------------------------------------------------
  do
    local fast <close> = proc.start { exe, "-e", "require('sched').sleep('100ms') io.write('fast')" }
    local slow <close> = proc.start { exe, "-e", "require('sched').sleep('1500ms') io.write('slow')" }
    local winner, result = proc.wait_any({ slow, fast }, "10s")
    check("wait_any returns the first child to finish with its result", winner == fast and result and result.out == "fast", tostring(result and result.out))
    check("the other child is still running", slow:running() == true)
    local none, e = proc.wait_all({ slow, fast }, "200ms")
    check("wait_all with a short timeout is nil, PROC timeout", none == nil and err.is(e, "PROC", "timeout"), tostring(e))
    local results = proc.wait_all({ slow, fast }, "10s")
    check("wait_all returns results in the order given", results and results[1].out == "slow" and results[2].out == "fast", tostring(results and #results))
    local again, again_result = proc.wait_any({ slow, fast })
    check("wait_any on finished children answers at once", again ~= nil and again_result.status == "exit")
  end
  local ok4, e4b = pcall(proc.wait_any, {})
  check("wait_any refuses an empty list", not ok4 and err.is(e4b, "PROC", "usage"), tostring(e4b))
  -- list, find, tree --------------------------------------------------------------------------
  do
    local sys = require "sys"
    local fs = require "fs"
    local me = sys.info().pid
    local all = proc.list()
    local mine
    for _, p in ipairs(all) do if p.pid == me then mine = p end end
    check("list includes this process and is sorted by pid", mine ~= nil and #all > 1 and all[1].pid < all[#all].pid, tostring(#all))
    check("an entry names the executable and the parent and, for our own process, carries the details",
      mine ~= nil and mine.name:lower() == "kuu.exe" and type(mine.parent) == "number" and type(mine.threads) == "number"
      and type(mine.exe) == "string" and mine.exe:lower():sub(-7) == "kuu.exe"
      and type(mine.cmdline) == "string" and contains(mine.cmdline:lower(), "run.lua")
      and type(mine.started) == "number" and mine.started > 1.7e9 and type(mine.cpu) == "number"
      and type(mine.memory) == "number" and mine.memory > 0 and type(mine.private) == "number" and mine.private > 0,
      mine and describe(mine))
    local by_name = proc.find { name = "KUU" }
    local found = false
    for _, p in ipairs(by_name) do if p.pid == me then found = true end end
    check("find by name ignores case and the extension", found, tostring(#by_name))
    local by_pid = proc.find { pid = me }
    check("find by pid is the one entry", #by_pid == 1 and by_pid[1].pid == me, tostring(#by_pid))
    check("find for something absent is an empty list, not an error", #proc.find { pid = 2147483646 } == 0 and #proc.find { name = "no-such-program-kuu" } == 0)
    local okf, ef = pcall(proc.find, { name = "x", pid = 1 })
    check("find takes exactly one criterion", not okf and err.is(ef, "PROC", "badvalue"), tostring(ef))
    local child <close> = proc.start { exe, "-e", "require('sched').sleep('5s')" }
    local tree = proc.tree(me)
    local has_child = false
    for _, c in ipairs(tree and tree.children or {}) do if c.pid == child.pid then has_child = true end end
    check("tree of this process lists the started child", tree ~= nil and tree.pid == me and has_child, tree and tostring(#tree.children))
    local none, e = proc.tree(2147483646)
    check("tree of an unknown pid is nil, PROC notfound", none == nil and err.is(e, "PROC", "notfound"), tostring(e))
    local fixture = T.root .. "/build/test/http_fixture.exe"
    if fs.exists(fixture) == "file" then
      local server <close> = proc.start { fixture, (T.fixtures:gsub("/", "\\")), stream = true }
      local port = tonumber((server:read("line", "10s") or ""):match("^PORT (%d+)$"))
      local owners = port and proc.find { port = port } or {}
      check("find by port names the listener's process", port ~= nil and #owners == 1 and owners[1].pid == server.pid, tostring(port) .. " " .. tostring(#owners))
      check("find by a closed port is an empty list", #proc.find { port = 1 } == 0)
      server:kill()
    end
  end

end
