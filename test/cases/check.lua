-- check.lua -- `kuu check`: syntax errors with lines, undeclared globals under a
-- declaration, the warning without one, require resolution, pruning, JSON.
global none
global <const> require, ipairs, tostring, type, string, table

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local json = require "json"
  local checker = require "check"

  local project = fs.absolute(T.work .. "/check-project")
  fs.remove(project, { recursive = true })
  fs.mkdir(project .. "/lib")
  fs.mkdir(project .. "/build")
  fs.mkdir(project .. "/sub")
  fs.write(project .. "/tasks.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask "x" { run = function() end }\n')
  fs.write(project .. "/good.lua", 'global none\nglobal <const> require\nlocal fs = require "fs"\nlocal helper = require("lib.helper")\nreturn helper\n')
  fs.write(project .. "/lib/helper.lua", "return { word = 'helped' }\n")
  fs.write(project .. "/bad.lua", "local x = = 1\n")
  fs.write(project .. "/strict.lua", 'global none\nprint("x")\n')
  fs.write(project .. "/ghost.lua", 'global none\nglobal <const> require\nlocal g = require "nothere"\nlocal h = require "lib.helper"\n')
  fs.write(project .. "/build/skip.lua", "this is not lua\n")

  local r = T.kuu({ "check" }, { cwd = project .. "/sub" })
  check("kuu check finds the project and exits 1 on syntax errors", r.code == 1, T.describe(r))
  check("a syntax error is reported with its file and line", contains(r.out, "bad.lua:1: "), r.out)
  check("an undeclared global under a global declaration is an error with its line", contains(r.out, "strict.lua:2: ") and contains(r.out, "print"), r.out)
  check("a file without a global declaration gets a warning", contains(r.out, "lib/helper.lua: warning: no global declaration"), r.out)
  check("a require that resolves to nothing is a warning with its line", contains(r.out, "ghost.lua:3: warning: require \"nothere\" names no kuu module and no file"), r.out)
  check("kuu modules and project files resolve without a warning", not contains(r.out, "\"fs\"") and not contains(r.out, "\"lib.helper\"") and not contains(r.out, "\"task\""), r.out)
  check("build/ is pruned", not contains(r.out, "skip.lua"), r.out)
  check("the summary counts files, errors, and warnings on stderr", contains(r.err, "kuu: 6 files, 2 errors, 3 warnings"), r.err)

  r = T.kuu({ "check", "good.lua" }, { cwd = project })
  check("a clean file exits 0", r.code == 0 and r.out == "" and contains(r.err, "1 files, 0 errors, 0 warnings"), T.describe(r))
  r = T.kuu({ "check", "lib" }, { cwd = project })
  check("a directory argument is walked, with requires still resolved against the project", r.code == 0 and contains(r.out, "lib/helper.lua: warning"), T.describe(r))
  r = T.kuu({ "check", "nope.lua" }, { cwd = project })
  check("a missing path exits 2", r.code == 2 and contains(r.err, "CHECK notfound"), T.describe(r))

  r = T.kuu({ "check", "--json" }, { cwd = project })
  local envelope = json.decode(r.out)
  check("kuu check --json is an envelope with counts and per-file reports", r.code == 1 and envelope and envelope.ok == false and envelope.result.errors == 2
    and envelope.result.warnings == 3 and #envelope.result.files == 6 and envelope.result.root == project, T.describe(r))
  if envelope then
    local good
    for _, f in ipairs(envelope.result.files) do if f.path == "good.lua" then good = f end end
    check("a file's requires are listed, sorted", good and #good.requires == 2 and good.requires[1] == "fs" and good.requires[2] == "lib.helper"
      and #good.errors == 0 and #good.warnings == 0, r.out)
  end

  -- outside a project the current directory is the root
  local loose = fs.absolute(T.work .. "/check-loose")
  fs.remove(loose, { recursive = true })
  fs.mkdir(loose)
  fs.write(loose .. "/a.lua", 'global none\nglobal <const> require\nlocal b = require "b"\n')
  fs.write(loose .. "/b.lua", "global none\nreturn 1\n")
  r = T.kuu({ "check" }, { cwd = loose })
  check("outside a project, the current directory is checked and is the require root", r.code == 0 and contains(r.err, "2 files, 0 errors, 0 warnings"), T.describe(r))

  -- the module in-process
  local report = checker.file(project .. "/ghost.lua", project)
  check("check.file reports requires and the unresolved one", #report.requires == 2 and report.requires[1] == "lib.helper" and report.requires[2] == "nothere"
    and #report.warnings == 1 and report.warnings[1].line == 3, tostring(report.warnings[1] and report.warnings[1].message))
  report = checker.file(project .. "/missing.lua", project)
  check("check.file on a missing file is one error", #report.errors == 1 and contains(report.errors[1].message, "FS notfound"))
  do
    local manual = fs.read(T.root .. "/docs/adopting.md")
    local example = manual:match("```lua\r?\n(.-)\r?\n```")
    check("the adopting page contains its Lua example", example ~= nil)
    if example then
      local path = fs.absolute(T.work .. "/adopting-example.lua")
      fs.write(path, example)
      local r = T.kuu { "check", path }
      check("the adopting example passes kuu check without running setup",
        r.code == 0 and contains(r.err, "0 errors, 0 warnings"), T.describe(r))
    end
  end

end
