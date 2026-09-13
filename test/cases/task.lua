-- task.lua -- manifest.lua discovery, `kuu run` and `kuu list`: dependency order,
-- arguments, exit codes, the JSON envelopes, and a project-local require.
global none
global <const> require, ipairs, tostring, type, pcall, select

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local fs = require "fs"
  local json = require "json"
  local err = require "err"
  local task = require "task"

  local project = fs.absolute(T.work .. "/project")
  fs.remove(project, { recursive = true })
  fs.mkdir(project .. "/sub/deeper")
  fs.mkdir(project .. "/lib")
  fs.write(project .. "/lib/helper.lua", "return { word = 'helped' }\n")
  fs.write(project .. "/manifest.lua", [[
local task = require "task"
local fs = require "fs"
local helper = require "lib.helper"
local function note(line)
  fs.mkdir("out")
  fs.write("out/order.txt", line .. "\n", { append = true })
end
task "gen" { desc = "generate sources", run = function() note("gen " .. helper.word) end }
task "build" {
  desc = "compile", deps = { "gen" },
  args = { { "--release", type = "flag", help = "optimise" }, { "target", default = "app" } },
  run = function(opts) note("build " .. tostring(opts.release) .. " " .. opts.target) end,
}
task "test" { desc = "run the tests", deps = { "build", "gen" }, run = function() note("test") end }
task "fail" { desc = "returns nil, err", run = function() return nil, require("err").new("TASK", "failed", "boom") end }
task "raise" { desc = "raises a string", run = function() error("kaboom") end }
task "child" { desc = "child exit passthrough", run = function() return task.exec { "cmd.exe", "/c", "echo from-child & exit 7" } end }
task "loop_a" { deps = { "loop_b" } }
task "loop_b" { deps = { "loop_a" } }
task "needs_ghost" { deps = { "ghost" } }
task "secret" { hidden = true, run = function() end }
task "needy" { desc = "needs an argument", args = { { "target", required = true } }, run = function(opts) note("needy " .. opts.target) end }
task "uses_needy" { desc = "depends on needy", deps = { "needy" }, run = function() note("uses") end }
task "talk" { desc = "prints", run = function() print("spoken") io.write("written\n") end }
task "console" { desc = "asks for the console explicitly", run = function() return task.exec { "cmd.exe", "/c", "echo via-console", inherit = true } end }
task "big" { desc = "emits more than maxout", run = function() return task.exec { require("rt").exe, "-e", "io.write(string.rep('x', 200000))", maxout = "64K" } end }
task "all" { desc = "aggregate", deps = { "test", "gen" } }
task "all-fail" { hidden = true, deps = { "child", "gen" } }
task.default "build"
]])

  local function order()
    local text = fs.read(project .. "/out/order.txt", { encoding = "utf-8" })
    return text or ""
  end
  local function reset() fs.remove(project .. "/out", { recursive = true }) end
  -- `kuu run --json` is a stream: every line an event, the last the envelope.
  local function events_of(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = json.decode(line) end
    return lines
  end
  local function envelope_of(text)
    local lines = events_of(text)
    return lines[#lines], lines
  end

  -- list ---------------------------------------------------------------------------------
  local r = T.kuu({ "list" }, { cwd = project .. "/sub/deeper" })
  check("kuu list finds manifest.lua from a subdirectory and shows the tasks", r.code == 0 and contains(r.out, "build") and contains(r.out, "compile")
    and contains(r.out, "[after gen]") and contains(r.out, "tasks in " .. project), T.describe(r))
  check("hidden tasks are not listed", not contains(r.out, "secret"))
  check("the default task is marked", contains(r.out, "*build"))
  r = T.kuu({ "list", "--json" }, { cwd = project })
  local listing = r.code == 0 and json.decode(r.out) or nil
  check("kuu list --json is an envelope with root, default, and tasks", listing and listing.ok == true and listing.result.root == project
    and listing.result.default == "build" and #listing.result.tasks == 17, T.describe(r))
  if listing then
    local build
    for _, t in ipairs(listing.result.tasks) do if t.name == "build" then build = t end end
    check("a listed task carries desc, deps, and its argument spec", build and build.desc == "compile" and build.deps[1] == "gen"
      and build.args[1].name == "--release" and build.args[1].type == "flag" and build.args[2].default == "app", r.out)
  end
  r = T.kuu({ "list" }, { cwd = T.work })
  check("kuu list outside a project exits 2 with TASK noproject", r.code == 2 and contains(r.err, "TASK noproject"), T.describe(r))
  r = T.kuu({ "list", "--bogus" }, { cwd = project })
  check("kuu list refuses unknown options with 2", r.code == 2 and contains(r.err, "CLI usage"), T.describe(r))

  -- run ----------------------------------------------------------------------------------
  reset()
  r = T.kuu({ "run" }, { cwd = project .. "/sub/deeper" })
  check("kuu run alone runs the default task after its dependencies, at the project root", r.code == 0 and order() == "gen helped\nbuild false app\n", T.describe(r) .. order())
  check("timing lines go to stderr", contains(r.err, "kuu: gen ") and contains(r.err, "kuu: build "), r.err)
  reset()
  r = T.kuu({ "run", "test" }, { cwd = project })
  check("dependencies run once each, in dependency order", r.code == 0 and order() == "gen helped\nbuild false app\ntest\n", order())
  reset()
  r = T.kuu({ "run", "build", "--release", "lib" }, { cwd = project })
  check("arguments after the task name reach it through its spec", r.code == 0 and order() == "gen helped\nbuild true lib\n", order())
  reset()
  r = T.kuu({ "run", "build", "--bogus" }, { cwd = project })
  check("a wrong task argument exits 2 with the task's usage, before anything runs", r.code == 2 and contains(r.err, "unknown option '--bogus'")
    and contains(r.err, "usage: kuu run build") and order() == "", T.describe(r) .. order())
  r = T.kuu({ "run", "build", "--help" }, { cwd = project })
  check("--help after the task name prints its usage and exits 2 without running dependencies", r.code == 2 and contains(r.err, "--release") and order() == "", T.describe(r) .. order())
  r = T.kuu({ "run", "--dry-run", "test" }, { cwd = project })
  check("--dry-run prints the plan in order and runs nothing", r.code == 0 and r.out == "1. gen  generate sources\n2. build  compile\n3. test  run the tests\n" and order() == "", T.describe(r))
  r = T.kuu({ "run", "--json", "--dry-run", "test" }, { cwd = project })
  local dry = json.decode(r.out)
  check("--dry-run --json is an envelope with the plan", r.code == 0 and dry and dry.ok == true and dry.result.task == "test" and #dry.result.plan == 3
    and dry.result.plan[2].name == "build" and dry.result.plan[2].deps[1] == "gen", T.describe(r))
  r = T.kuu({ "run", "--dry-run", "build", "--bogus" }, { cwd = project })
  check("--dry-run still checks the arguments", r.code == 2 and contains(r.err, "unknown option '--bogus'"), T.describe(r))
  r = T.kuu({ "run", "uses_needy" }, { cwd = project })
  check("a dependency that needs an argument is refused before anything runs", r.code == 2 and contains(r.err, "missing required argument <target>") and order() == "", T.describe(r) .. order())
  r = T.kuu({ "run", "talk" }, { cwd = project })
  check("without --json a task's print and io.write reach standard output", r.code == 0 and contains(r.out, "spoken") and contains(r.out, "written"), T.describe(r))
  r = T.kuu({ "run", "--json", "talk" }, { cwd = project })
  local spoken = envelope_of(r.out)
  check("under --json a task's print and io.write are redirected to standard error", r.code == 0 and spoken and spoken.ok == true
    and contains(r.err, "spoken") and contains(r.err, "written"), T.describe(r))
  r = T.kuu({ "run", "--json", "console" }, { cwd = project })
  local console = envelope_of(r.out)
  check("under --json a child that asked for the console is relayed to stderr all the same", r.code == 0 and console and console.ok == true
    and contains(r.err, "via-console"), T.describe(r))
  r = T.kuu({ "run", "--json", "big" }, { cwd = project })
  local big = envelope_of(r.out)
  check("under --json a child's output beyond maxout is relayed whole, nothing dropped", r.code == 0 and big and big.ok == true
    and select(2, r.err:gsub("x", "")) == 200000, T.describe(r):sub(1, 400))
  r = T.kuu({ "run", "gen", "extra" }, { cwd = project })
  check("arguments to a task without a spec exit 2", r.code == 2 and contains(r.err, "takes no arguments"), T.describe(r))
  r = T.kuu({ "run", "fail" }, { cwd = project })
  check("nil, err from a task exits 1 with the error", r.code == 1 and contains(r.err, "TASK failed: boom") and contains(r.err, "fail failed after"), T.describe(r))
  r = T.kuu({ "run", "raise" }, { cwd = project })
  check("a raise in a task exits 1 with the message and location", r.code == 1 and contains(r.err, "manifest.lua:") and contains(r.err, "kaboom"), T.describe(r))
  r = T.kuu({ "run", "child" }, { cwd = project })
  check("task.exec streams the child's output and passes its exit code through", r.code == 7 and contains(r.out, "from-child") and contains(r.err, "exited with code 7"), T.describe(r))
  r = T.kuu({ "run", "loop_a" }, { cwd = project })
  check("a dependency cycle exits 2 and names the chain", r.code == 2 and contains(r.err, "TASK cycle") and contains(r.err, "loop_a -> loop_b"), T.describe(r))
  r = T.kuu({ "run", "needs_ghost" }, { cwd = project })
  check("an unknown dependency exits 2 and says who needed it", r.code == 2 and contains(r.err, "no task 'ghost' (needed by needs_ghost)"), T.describe(r))
  r = T.kuu({ "run", "nope" }, { cwd = project })
  check("an unknown task exits 2", r.code == 2 and contains(r.err, "TASK unknown: no task 'nope'"), T.describe(r))
  r = T.kuu({ "run", "--wat" }, { cwd = project })
  check("an unknown run option exits 2", r.code == 2 and contains(r.err, "unknown option '--wat'"), T.describe(r))
  reset()
  r = T.kuu({ "run", "--json", "test" }, { cwd = project })
  local envelope, stream = envelope_of(r.out)
  check("kuu run --json reports each task with its timing in its last line", r.code == 0 and envelope and envelope.ok == true and envelope.result.task == "test"
    and #envelope.result.tasks == 3 and envelope.result.tasks[1].name == "gen" and type(envelope.result.tasks[1].seconds) == "number"
    and r.err == "", T.describe(r))
  check("the lines before it are the run and each task starting and finishing, in order, each versioned",
    #stream == 8 and stream[1].v == 1 and stream[1].event == "run" and stream[1].task == "test" and #stream[1].plan == 3 and stream[1].plan[1] == "gen"
      and stream[2].event == "task" and stream[2].name == "gen" and stream[2].state == "started"
      and stream[3].event == "task" and stream[3].name == "gen" and stream[3].state == "finished" and stream[3].ok == true and type(stream[3].seconds) == "number"
      and stream[6].name == "test" and stream[7].name == "test" and stream[7].state == "finished", r.out)
  r = T.kuu({ "run", "--json", "child" }, { cwd = project })
  envelope, stream = envelope_of(r.out)
  check("under --json standard output is only the stream, the child's output is relayed to stderr, and its code passes through", r.code == 7 and envelope
    and envelope.ok == false and envelope.error.code == "exit" and envelope.error.exit == 7 and contains(r.err, "from-child"), T.describe(r))
  local started, finished, ended
  for _, e in ipairs(stream) do
    if e.event == "child" and e.state == "started" then started = e end
    if e.event == "child" and e.state == "finished" then finished = e end
    if e.event == "task" and e.state == "finished" then ended = e end
  end
  check("a child the task runs through the door is two events, with its pid, its argv, and its exit",
    started ~= nil and started.task == "child" and type(started.pid) == "number" and started.argv[1] == "cmd.exe"
      and finished ~= nil and finished.pid == started.pid and finished.status == "exit" and finished.code == 7 and type(finished.seconds) == "number",
    r.out)
  check("a failed task's finish carries the error before the envelope does",
    ended ~= nil and ended.ok == false and ended.error.code == "exit" and ended.error.exit == 7, r.out)
  r = T.kuu({ "run", "--json", "--dry-run", "test" }, { cwd = project })
  check("--dry-run --json is one envelope, since nothing runs", r.code == 0 and #events_of(r.out) == 1, r.out)

  -- a project without a default, and broken declarations ----------------------------------
  local bare = T.work .. "/project-bare"
  fs.remove(bare, { recursive = true })
  fs.mkdir(bare)
  fs.write(bare .. "/manifest.lua", 'local task = require "task"\ntask "only" { desc = "the one", run = function() end }\n')
  r = T.kuu({ "run" }, { cwd = bare })
  check("kuu run with no default lists the tasks and exits 2", r.code == 2 and contains(r.err, "declares no default") and contains(r.err, "only"), T.describe(r))
  fs.write(bare .. "/manifest.lua", 'local task = require "task"\ntask "x" { desc = 1, run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("a bad attribute in manifest.lua exits 2 with TASK badvalue and the line", r.code == 2 and contains(r.err, "TASK badvalue") and contains(r.err, "desc must be a string"), T.describe(r))
  fs.write(bare .. "/manifest.lua", 'local task = require "task"\ntask "x" { run = function() end }\ntask "x" { run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("declaring a task twice is refused", r.code == 2 and contains(r.err, "declared twice"), T.describe(r))
  fs.write(bare .. "/manifest.lua", 'local task = require "task"\ntask "x" { args = { { "--help" } }, run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("a broken argument spec is refused at declaration", r.code == 2 and contains(r.err, "--help is provided by the parser"), T.describe(r))
  fs.write(bare .. "/manifest.lua", "this is not lua\n")
  r = T.kuu({ "list" }, { cwd = bare })
  check("a syntax error in manifest.lua exits 2 with its location", r.code == 2 and contains(r.err, "manifest.lua:1:"), T.describe(r))

  -- Through 0.9 the file was tasks.lua. 0.10 still finds one where no
  -- manifest.lua is, and says so on stderr every time; a directory holding
  -- both is read from manifest.lua and told nothing.
  local legacy = T.work .. "/project-legacy"
  fs.remove(legacy, { recursive = true })
  fs.mkdir(legacy)
  fs.write(legacy .. "/tasks.lua", 'local task = require "task"\ntask "old" { desc = "still found", run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = legacy })
  check("a project with only tasks.lua is still found, with a warning to rename it",
    r.code == 0 and contains(r.out, "old") and contains(r.err, "rename it to manifest.lua"), T.describe(r))
  r = T.kuu({ "run", "old" }, { cwd = legacy })
  check("kuu run says the same, once, and runs the task", r.code == 0 and contains(r.err, "rename it to manifest.lua") and contains(r.err, "kuu: old "), T.describe(r))
  fs.write(legacy .. "/manifest.lua", 'local task = require "task"\ntask "new" { desc = "the manifest", run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = legacy })
  check("manifest.lua wins over a tasks.lua beside it, silently",
    r.code == 0 and contains(r.out, "new") and not contains(r.out, "old") and not contains(r.err, "rename"), T.describe(r))

  reset()
  r = T.kuu({ "run", "--json", "all" }, { cwd = project })
  local aggregate = envelope_of(r.out)
  check("a dependency-only aggregate succeeds and runs shared dependencies once",
    r.code == 0 and aggregate and aggregate.ok and order() == "gen helped\nbuild false app\ntest\n", T.describe(r))
  reset()
  r = T.kuu({ "run", "all-fail" }, { cwd = project })
  check("an aggregate preserves its child's failure and skips later dependencies", r.code == 7 and order() == "", T.describe(r))
  r = T.kuu({ "run", "--dry-run", "all" }, { cwd = project })
  check("aggregate dry runs include the grouping task without executing it", r.code == 0 and contains(r.out, "4. all") and order() == "", T.describe(r))

  -- the module in-process ------------------------------------------------------------------
  local plan, e = task.plan("nothing")
  check("task.plan on an unknown name is nil, TASK unknown", plan == nil and err.is(e, "TASK", "unknown"))
  local ok, raised = pcall(task, "bad name", { run = function() end })
  check("a task name with a space is refused", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
  ok, raised = pcall(task, "nofunc", {})
  check("a task without run is refused", not ok and contains(raised.message, "needs a run function"), tostring(raised))
  ok, raised = pcall(task.exec, "gcc")
  check("task.exec wants an argv table", not ok and err.is(raised, "TASK", "badvalue"))
  ok, raised = pcall(task, "emptydeps", {deps={}})
  check("empty dependency-only tasks are refused", not ok and err.is(raised, "TASK", "badvalue"))
  ok, raised = pcall(task, "badrun", {deps={"x"}, run=false})
  check("aggregate tasks still reject a non-function run", not ok and err.is(raised, "TASK", "badvalue"))

  -- Default child timeouts are validated once, copied, and overridable.
  local defaults = { timeout = "0s 80ms" }
  task.defaults(defaults)
  defaults.timeout = "5s"
  local slow = { T.exe, "-e", "require('sched').sleep('500ms')" }
  local ran, timed = task.exec(slow)
  check("task.defaults times out a child and does not retain the settings table",
    ran == nil and err.is(timed, "TASK", "failed") and contains(timed.message, "timeout"), tostring(timed))
  check("console execution leaves the caller's argv/options table untouched",
    slow.timeout == nil and slow.inherit == nil and slow.stream == nil and slow[1] == T.exe)
  local explicit = { T.exe, "-e", "require('sched').sleep('140ms')", timeout = "2s", inherit = false }
  ran, timed = task.exec(explicit)
  check("an explicit timeout overrides the default without changing caller options",
    ran == true and explicit.timeout == "2s" and explicit.inherit == false, tostring(timed))
  for _, value in ipairs { "soon", -1, false, {}, 0 / 0 } do
    ok, raised = pcall(task.defaults, { timeout = value })
    check("an invalid default timeout is TASK badvalue: " .. tostring(value),
      not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
  end
  ok, raised = pcall(task.defaults, { timeout = "5s", extra = true })
  check("unknown default options are TASK usage, refused before changing any setting",
    not ok and err.is(raised, "TASK", "usage") and contains(raised.message, "unknown option"), tostring(raised))
  ok, raised = pcall(task("t-unknown-attribute"), { desc = "x", runn = function() end })
  check("an attribute a declaration cannot hold is TASK usage",
    not ok and err.is(raised, "TASK", "usage") and contains(raised.message, "unknown attribute 'runn'"), tostring(raised))

  -- The two names the runner is built from, on their own: which task is the
  -- default, and a task's arguments parsed against its spec, in a process of
  -- their own so this suite's registry stays as it is.
  do
    local r = T.kuu { "-e", [=[
      local task, err = require "task", require "err"
      task "needy" { args = { { "target", required = true }, { "--fast", type = "flag" } }, run = function() end }
      task "plain" { run = function() end }
      local before = task.default_task()
      task.default "plain"
      local opts = assert(task.arguments(task.get("needy"), { "app", "--fast" }))
      local none, e = task.arguments(task.get("needy"), {})
      local none2, e2 = task.arguments(task.get("plain"), { "extra" })
      local none3, e3 = task.arguments(task.get("needy"), { "--help" })
      io.write(tostring(before), " ", task.default_task(), " ", opts.target, " ", tostring(opts.fast), " ",
        tostring(none == nil and err.is(e, "CLI", "usage")), " ",
        tostring(none2 == nil and err.is(e2, "CLI", "usage") and e2.message:find("takes no arguments", 1, true) ~= nil), " ",
        tostring(none3 == nil and err.is(e3, "CLI", "usage") and e3.message:find("usage: kuu run needy", 1, true) ~= nil))
    ]=] }
    check("task.default_task and task.arguments answer for a declared project",
      r.status == "exit" and r.code == 0 and r.out == "nil plain app true true true true", T.describe(r))
  end
  ok, raised = pcall(task.get, 5)
  check("task.get with a non-string is TASK badvalue", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
  ok, raised = pcall(task.plan, nil)
  check("task.plan with nil is TASK badvalue, not an unknown task", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))

  -- Tools: declared beside the tasks, resolved by task.command and task.exec.
  do
    local exe = require("rt").exe
    local decl = task.tool "kuu-self" { exe = exe, args = { ["-e"] = "string", ["--bogus"] = "flag" }, output = "lines",
      emits = { "line" }, timeout = "20s", reach = { read = { "." } } }
    check("a tool declaration is registered with its attributes", decl.name == "kuu-self" and decl.exe == exe
      and decl.args["-e"] == "string" and decl.output == "lines" and decl.emits[1] == "line" and decl.timeout == "20s"
      and decl.reach.read[1] == ".")
    check("task.tools lists it and task.tool_get finds it",
      task.tools()[#task.tools()] == decl and task.tool_get("kuu-self") == decl and task.tool_get("nope") == nil)
    local spec = task.command { tool = "kuu-self", "-e", "io.write('through the door')", cwd = T.work }
    check("task.command puts the declared exe first, keeps the call's options, and applies the declared timeout",
      spec[1] == fs.absolute(exe) and spec[2] == "-e" and spec.cwd == T.work and spec.timeout == "20s" and spec.tool == nil,
      tostring(spec[1]) .. " " .. tostring(spec.timeout))
    local r = require("proc").run(spec)
    check("the resolved table runs through proc.run", r and r.status == "exit" and r.code == 0 and r.out == "through the door",
      r and r.err or "no result")
    local ran, why = task.exec { tool = "kuu-self", "-e", "os.exit(3)", timeout = "5s" }
    check("task.exec through a declaration passes the exit code through", ran == nil and err.is(why, "TASK", "exit") and why.exit == 3, tostring(why))
    -- spelled so that kuu check, which reads this file too, does not judge
    -- the name: a computed name is not a literal
    ok, raised = pcall(task.exec, { tool = "un" .. "declared" })
    check("an undeclared tool is TASK unknown", not ok and err.is(raised, "TASK", "unknown"), tostring(raised))
    ok, raised = pcall(task.tool("bad-attr"), { exe = "x", exee = "y" })
    check("an attribute a tool declaration cannot hold is TASK usage", not ok and err.is(raised, "TASK", "usage"), tostring(raised))
    ok, raised = pcall(task.tool("bad-output"), { exe = "x", output = "xml" })
    check("an output the declaration cannot describe is TASK badvalue", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
    ok, raised = pcall(task.tool("bad-type"), { exe = "x", args = { ["--n"] = "count" } })
    check("an argument type outside the seven is TASK badvalue", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
    ok, raised = pcall(task.tool("kuu-self"), { exe = "x" })
    check("a tool declared twice is refused", not ok and err.is(raised, "TASK", "badvalue") and contains(raised.message, "twice"), tostring(raised))
    local plain = task.tool "plain" { exe = "x" }
    check("a declaration without args or output leaves the arguments undescribed and the output none",
      plain.args == nil and plain.output == "none" and #plain.emits == 0)
    ok, raised = pcall(task.tool("map-emits"), { exe = "x", emits = { rows = "string" } })
    check("emits spelled as a table of names is TASK badvalue, not an empty list", not ok and err.is(raised, "TASK", "badvalue") and contains(raised.message, "array"), tostring(raised))
    ok, raised = pcall(task.tool("map-reach"), { exe = "x", reach = { read = { a = "x" } } })
    check("a reach list spelled as a table is TASK badvalue", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
    ok, raised = pcall(task.tool("bad-exe"), { exe = "tools/kuu.exe " })
    check("an exe the resolver refuses is refused at the declaration, in TASK's words", not ok and err.is(raised, "TASK", "badvalue") and contains(raised.message, "exe"), tostring(raised))
  end
  ran, timed = task.exec(slow)
  check("a rejected defaults declaration preserves the preceding default",
    ran == nil and err.is(timed, "TASK", "failed") and contains(timed.message, "timeout"), tostring(timed))
  task.defaults { timeout = 0.08 }
  ran, timed = task.exec(slow)
  check("a numeric default timeout is seconds",
    ran == nil and err.is(timed, "TASK", "failed") and contains(timed.message, "timeout"), tostring(timed))
  local relay_text = ""
  task.relay = { write = function(_, bytes) relay_text = relay_text .. bytes end }
  local relayed = { T.exe, "-e", "io.write('relayed')", timeout = "2s", inherit = true, stream = false }
  ran, timed = task.exec(relayed)
  task.relay = nil
  check("relay execution preserves caller options while applying the default/override rules",
    ran == true and relay_text == "relayed" and relayed.inherit == true and relayed.stream == false and relayed.timeout == "2s", tostring(timed))
  task.defaults {}
  ran, timed = task.exec { T.exe, "-e", "require('sched').sleep('140ms')" }
  check("an empty defaults table clears the default", ran == true, tostring(timed))
  ok, raised = pcall(task.defaults, "80ms")
  check("defaults requires a table", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
  local proc = require "proc"
  local original_run, received = proc.run
  proc.run = function(spec) received = spec return { status = "limit", limit = "memory", code = 0 } end
  local limits = { memory = "64M", cpu = "1s", processes = 2 }
  local called, result, limited = pcall(task.exec, { T.exe, limits = limits })
  proc.run = original_run
  check("task.exec forwards child limits and refuses a limit result even with code zero",
    called and result == nil and err.is(limited, "TASK", "failed") and contains(limited.message, "limit (memory)")
    and received.limits == limits, tostring(limited))
  fs.write(bare .. "/manifest.lua", 'require("task").defaults { timeout = "soon" }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("bad defaults fail while declaring tasks, before any task runs",
    r.code == 2 and contains(r.err, "TASK badvalue") and contains(r.err, "timeout must be"), T.describe(r))
end
