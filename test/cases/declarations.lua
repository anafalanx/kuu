-- Declaration checking reads source without evaluating the manifest.
global none
global <const> require, assert, ipairs, string

return function(T)
  local fs = require "fs"
  local checker = require "check"
  local json = require "json"
  local check, contains = T.check, T.contains
  local dir = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "declarations-" })
  local prefix = 'global none\nglobal <const> require\nlocal task = require "task"\n'
  local function inspect(body)
    assert(fs.write(dir .. "/manifest.lua", prefix .. body .. "\n"))
    return checker.file(dir .. "/manifest.lua", dir)
  end
  local function clean(label, body)
    local r = inspect(body)
    check(label, #r.errors == 0, json.encode(r.errors))
    return r
  end
  local function one(label, body, kind, needle, line)
    local r = inspect(body)
    local e = r.errors[1]
    check(label, #r.errors == 1 and e.kind == kind and contains(e.message, needle)
      and (line == nil or e.line == line), json.encode(r.errors))
    return r
  end

  for _, body in ipairs {
    'task "g++" { run = function() end }',
    'task("g++", { run = function() end })',
    'task.tool "g++" { exe = "bin/g++.exe" }',
    'task.tool("g++", { exe = "bin/g++.exe" })',
  } do
    one("literal task and tool names use the runtime identifier rule", body, "value", "such as 'cxx'", 4)
  end
  for _, call in ipairs { 'task "build"', 'task("build",' } do
    local body = call .. ' {\n  timeout = "5m",\n  run = function() end,\n}'
      .. (call:find("(", 1, true) and ")" or "")
    local r = one("task timeout beside a run function is located and has child timeout remedies",
      body, "option", "task.exec, task.defaults or task.tool", 5)
    check("task timeout finding keeps its field name", r.errors[1] and r.errors[1].name == "timeout", json.encode(r.errors))
  end
  for _, body in ipairs {
    'local jobs = task; jobs "x" { timeout = 2, run = function() end }',
    'local jobs = task; local more = jobs; more("x", { timeout = 2, run = function() end })',
    'local tool = task.tool; tool "g++" { exe = "x.exe" }',
    'local tool = task.tool; local more = tool; more("g++", { exe = "x.exe" })',
    'local declare = task "x"; declare { timeout = 2, run = function() end }',
    'local declare = task.tool "g++"; local again = declare; again { exe = "x.exe" }',
    'require("task")("x", { timeout = 2, run = function() end })',
    'require("task").tool "g++" { exe = "x.exe" }',
  } do
    local r = inspect(body)
    check("direct, copied and saved curried bindings retain declaration identity", #r.errors == 1, body .. "\n" .. json.encode(r.errors))
  end
  for _, body in ipairs {
    'local task = function() return function() end end; task "g++" { timeout = 2 }',
    'local function f(task) task "g++" { timeout = 2 } end; return f',
    'for task in function() end do task "g++" { timeout = 2 } end',
    'task = function() return function() end end; task "g++" { timeout = 2 }',
    'local function f() task "g++" { timeout = 2 } end; task = function() end; return f',
    'local jobs = task; jobs = function() end; jobs "g++" { timeout = 2 }',
    'local jobs = task; local function f() jobs "g++" { timeout = 2 } end; task = function() end; return f',
    'local tool = task.tool; tool = function() end; tool "g++" { arbitrary = 2 }',
    'local tool = task.tool; task.tool = function() end; tool "g++" { arbitrary = 2 }',
    'local jobs = task; jobs.tool = function() end; task.tool "g++" { arbitrary = 2 }',
    'task["tool"] = function() end; task.tool "g++" { arbitrary = 2 }',
    'local declare = task "x"; declare = function() end; declare { timeout = 2 }',
    'local tool = task["tool"]; tool("x", { exe = "x.exe" })',
  } do clean("shadowed or changed declaration bindings are left unchecked", body) end
  one("a shadowing inner local does not erase an outer declaration binding",
    'do local task = function() end; task "custom" {} end; task "x" { timeout = 2, run = function() end }',
    "option", "timeout")

  local invalid = {
    { 'task "x" { run = 1 }', "run must be a function" },
    { 'task "x" { run = function() end, desc = false }', "desc must be a string" },
    { 'task "x" { run = function() end, hidden = "yes" }', "hidden must be a boolean" },
    { 'task "x" { run = function() end, deps = "a" }', "deps must be an array" },
    { 'task "x" { run = function() end, deps = { "a", 7 } }', "deps must be an array" },
    { 'task "x" { run = function() end, args = false }', "args must be a CLI specification" },
    { 'task "x" { run = function() end, args = { { "--n", type = "integer" } } }', "unknown type" },
    { 'task "x" { desc = "no implementation" }', "needs a run function" },
    { 'task "x" { deps = {} }', "needs a run function" },
    { 'task "x" { run = nil, deps = {} }', "needs a run function" },
    { 'task("x", false)', "needs a declaration table" },
    { 'task.tool("x", 7)', "needs a declaration table" },
    { 'task.tool "x" { exe = "" }', "exe must be a non-empty string" },
    { 'task.tool "x" {}', "exe must be a non-empty string" },
    { 'task.tool "x" { exe = nil }', "exe must be a non-empty string" },
    { 'local p; task.tool "x" { exe = p, output = "binary" }', "output must be" },
    { 'local p; task.tool "x" { exe = p, timeout = "someday" }', "timeout must be a duration" },
    { 'local p; task.tool "x" { exe = p, timeout = -1 }', "timeout must be a duration" },
    { 'local p; task.tool "x" { exe = p, args = { ["--n"] = "integer" } }', "supported argument types" },
    { 'local p; task.tool "x" { exe = p, emits = { "a", false } }', "emits must be an array" },
    { 'local p; task.tool "x" { exe = p, reach = { read = { 1 } } }', "reach.read must be an array" },
    { 'local p; task.tool "x" { exe = p, reach = { admin = {} } }', "reach only accepts" },
  }
  for _, case in ipairs(invalid) do one("independently known declaration values are validated", case[1], "value", case[2]) end

  for _, body in ipairs {
    'local dynamic; task(dynamic, { run = function() end })',
    'local dynamic; task "x" { run = dynamic }',
    'local dynamic; task "x" { deps = dynamic }',
    'local dynamic; task "x" { run = function() end, hidden = dynamic, desc = dynamic, args = dynamic }',
    'local function optional() end; task "x" { run = function() end, timeout = optional(), optional() }',
    'local function optional() end; task.tool "x" { exe = "x.exe", emits = { named = optional() }, reach = { other = optional() }, args = { optional() } }',
    'task "x" { run = function() end, deps = { nil } }',
    'task.tool "x" { exe = "x.exe", emits = { "a", nil }, reach = { read = { nil } } }',
    'local dynamic; task.tool "x" { exe = dynamic, timeout = dynamic, args = dynamic, reach = dynamic }',
    'task "x" { run = 42, run = function() end }',
    'task.tool "x" { exe = false, exe = "x.exe", timeout = "5s" }',
    'local key, value; task "x" { run = 42, [key] = value }',
    'local key, value; task.tool "x" { exe = false, [key] = value }',
    'task "x" { run = function() end, timeout = nil }',
    'task.tool "x" { exe = "x.exe", outputt = nil }',
    'task "x" { deps = { "build" } }',
    'task "x" { run = function() end, args = {} }',
    'task "g++"', -- merely returns a closure; no declaration yet
    'task("g++", nil)',
    'local dynamic; task("g++", dynamic)',
    'local spec; task.tool("x", spec); task.command { tool = "x", "--any" }',
    'local spec; task.tool("g++", spec)',
  } do clean("dynamic, overwritten, absent and deferred values do not gain speculative errors", body) end
  one("a dynamic task name does not hide a visible misplaced timeout",
    'local name; task(name, { run = function() end, timeout = "5m" })', "option", "child timeouts")
  clean("a dynamic tool name can supply the tool in a later call",
    'local name; task.tool(name, { exe = "x.exe" }); task.command { tool = "x", "--arbitrary" }')
  assert(fs.write(dir .. "/consumer.lua", prefix .. 'return task.command { tool = "x", "--arbitrary" }\n'))
  local consumer = checker.file(dir .. "/consumer.lua", dir)
  check("manifest dynamic tool names do not cause false consumer name errors", #consumer.errors == 0, json.encode(consumer.errors))
  inspect('local p; task.tool "x" { exe = p, timeout = "bad" }')
  consumer = checker.file(dir .. "/consumer.lua", dir)
  check("an invalid partial tool declaration does not cascade into an undeclared-tool finding", #consumer.errors == 0, json.encode(consumer.errors))
  for _, name in ipairs { "7", "nil", "false", "{}", "function() end" } do
    one("nonstring tool names have a located value finding", 'task.tool(' .. name .. ', {exe="x.exe"})', "value", "name must start")
    consumer = checker.file(dir .. "/consumer.lua", dir)
    local analysis_error = false
    for _, e in ipairs(consumer.errors) do if e.kind == "analysis" then analysis_error = true end end
    check("an invalid nameless tool declaration cannot crash consumer analysis", not analysis_error, json.encode(consumer.errors))
  end
  local optional = 'local function absent() end; '
    .. 'task "nil-fields" {run=function() end, deps={nil}, timeout=absent(), absent()}; '
    .. 'task.tool "nil-tool" {exe="x.exe", emits={"a",nil}, reach={read={nil}, other=absent()}, args={absent()}}'
  clean("nil-producing declaration fields are accepted statically", optional)
  local optional_runtime = T.kuu({ "-e", prefix .. optional }, { cwd = dir })
  check("nil-producing declaration fields are accepted by runtime too", optional_runtime.code == 0, T.describe(optional_runtime))

  for _, name in ipairs { "x", "cxx", "9", "build.release", "build_debug", "build-fast", "" , "_x", "g++", "a/b", "two words", "é" } do
    for _, kind in ipairs { "task", "task.tool" } do
      local body = kind .. "(" .. string.format("%q", name) .. ", "
        .. (kind == "task" and "{run=function() end}" or '{exe="x.exe"}') .. ")"
      local static = inspect(body)
      local runtime = T.kuu({ "-e", prefix .. body }, { cwd = dir })
      check("literal identifier acceptance matches runtime for " .. kind .. " " .. string.format("%q", name),
        (#static.errors == 0) == (runtime.code == 0), json.encode(static.errors) .. "\n" .. T.describe(runtime))
    end
  end
  local marker = dir .. "/manifest-executed.txt"
  -- Use only declared globals and side effects the loaded checker must not run.
  assert(fs.write(dir .. "/manifest.lua", prefix .. 'local fs = require "fs"\n'
    .. 'fs.write(' .. string.format("%q", marker) .. ', "executed")\n'
    .. 'task "x" { run = function() end, timeout = "5m" }\n'))
  local r = checker.file(dir .. "/manifest.lua", dir)
  check("static declaration checking never executes a manifest's top-level side effects",
    #r.errors == 1 and r.errors[1].kind == "option" and fs.exists(marker) == false, json.encode(r.errors))
end
