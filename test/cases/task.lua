-- task.lua -- tasks.lua discovery, `kuu run` and `kuu list`: dependency order,
-- arguments, exit codes, the JSON envelopes, and a project-local require.
global none
global <const> require, ipairs, tostring, tonumber, type, string, table, pcall

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
  fs.write(project .. "/tasks.lua", [[
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
task "loop_a" { deps = { "loop_b" }, run = function() end }
task "loop_b" { deps = { "loop_a" }, run = function() end }
task "needs_ghost" { deps = { "ghost" }, run = function() end }
task "secret" { hidden = true, run = function() end }
task.default "build"
]])

  local function order()
    local text = fs.read(project .. "/out/order.txt", { encoding = "utf-8" })
    return text or ""
  end
  local function reset() fs.remove(project .. "/out", { recursive = true }) end

  -- list ---------------------------------------------------------------------------------
  local r = T.kuu({ "list" }, { cwd = project .. "/sub/deeper" })
  check("kuu list finds tasks.lua from a subdirectory and shows the tasks", r.code == 0 and contains(r.out, "build") and contains(r.out, "compile")
    and contains(r.out, "[after gen]") and contains(r.out, "tasks in " .. project), T.describe(r))
  check("hidden tasks are not listed", not contains(r.out, "secret"))
  check("the default task is marked", contains(r.out, "*build"))
  r = T.kuu({ "list", "--json" }, { cwd = project })
  local listing = r.code == 0 and json.decode(r.out) or nil
  check("kuu list --json is an envelope with root, default, and tasks", listing and listing.ok == true and listing.result.root == project
    and listing.result.default == "build" and #listing.result.tasks == 10, T.describe(r))
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
  r = T.kuu({ "run", "build", "--bogus" }, { cwd = project })
  check("a wrong task argument exits 2 with the task's usage", r.code == 2 and contains(r.err, "unknown option '--bogus'") and contains(r.err, "usage: kuu run build"), T.describe(r))
  r = T.kuu({ "run", "build", "--help" }, { cwd = project })
  check("--help after the task name prints its usage and exits 2", r.code == 2 and contains(r.err, "--release"), T.describe(r))
  r = T.kuu({ "run", "gen", "extra" }, { cwd = project })
  check("arguments to a task without a spec exit 2", r.code == 2 and contains(r.err, "takes no arguments"), T.describe(r))
  r = T.kuu({ "run", "fail" }, { cwd = project })
  check("nil, err from a task exits 1 with the error", r.code == 1 and contains(r.err, "TASK failed: boom") and contains(r.err, "fail failed after"), T.describe(r))
  r = T.kuu({ "run", "raise" }, { cwd = project })
  check("a raise in a task exits 1 with the message and location", r.code == 1 and contains(r.err, "tasks.lua:") and contains(r.err, "kaboom"), T.describe(r))
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
  local envelope = r.code == 0 and json.decode(r.out) or nil
  check("kuu run --json reports each task with its timing", envelope and envelope.ok == true and envelope.result.task == "test"
    and #envelope.result.tasks == 3 and envelope.result.tasks[1].name == "gen" and type(envelope.result.tasks[1].seconds) == "number"
    and r.err == "", T.describe(r))
  r = T.kuu({ "run", "--json", "child" }, { cwd = project })
  envelope = json.decode(r.out:match("{.*}") or "null")
  check("a failing task under --json still exits with the child's code and reports the error", r.code == 7 and envelope
    and envelope.ok == false and envelope.error.code == "exit" and envelope.error.exit == 7, T.describe(r))

  -- a project without a default, and broken declarations ----------------------------------
  local bare = T.work .. "/project-bare"
  fs.remove(bare, { recursive = true })
  fs.mkdir(bare)
  fs.write(bare .. "/tasks.lua", 'local task = require "task"\ntask "only" { desc = "the one", run = function() end }\n')
  r = T.kuu({ "run" }, { cwd = bare })
  check("kuu run with no default lists the tasks and exits 2", r.code == 2 and contains(r.err, "declares no default") and contains(r.err, "only"), T.describe(r))
  fs.write(bare .. "/tasks.lua", 'local task = require "task"\ntask "x" { desc = 1, run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("a bad attribute in tasks.lua exits 2 with TASK badvalue and the line", r.code == 2 and contains(r.err, "TASK badvalue") and contains(r.err, "desc must be a string"), T.describe(r))
  fs.write(bare .. "/tasks.lua", 'local task = require "task"\ntask "x" { run = function() end }\ntask "x" { run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("declaring a task twice is refused", r.code == 2 and contains(r.err, "declared twice"), T.describe(r))
  fs.write(bare .. "/tasks.lua", 'local task = require "task"\ntask "x" { args = { { "--help" } }, run = function() end }\n')
  r = T.kuu({ "list" }, { cwd = bare })
  check("a broken argument spec is refused at declaration", r.code == 2 and contains(r.err, "--help is provided by the parser"), T.describe(r))
  fs.write(bare .. "/tasks.lua", "this is not lua\n")
  r = T.kuu({ "list" }, { cwd = bare })
  check("a syntax error in tasks.lua exits 2 with its location", r.code == 2 and contains(r.err, "tasks.lua:1:"), T.describe(r))

  -- the module in-process ------------------------------------------------------------------
  local plan, e = task.plan("nothing")
  check("task.plan on an unknown name is nil, TASK unknown", plan == nil and err.is(e, "TASK", "unknown"))
  local ok, raised = pcall(task, "bad name", { run = function() end })
  check("a task name with a space is refused", not ok and err.is(raised, "TASK", "badvalue"), tostring(raised))
  ok, raised = pcall(task, "nofunc", {})
  check("a task without run is refused", not ok and contains(raised.message, "needs a run function"), tostring(raised))
  ok, raised = pcall(task.exec, "gcc")
  check("task.exec wants an argv table", not ok and err.is(raised, "TASK", "badvalue"))
end
