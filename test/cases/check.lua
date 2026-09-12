-- check.lua -- `kuu check`: syntax errors with lines, undeclared globals under a
-- declaration, the warning without one, require resolution, pruning, JSON.
global none
global <const> require, ipairs, tostring

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
  -- Palette names are checked through lexical bindings, never through text
  -- in strings/comments or by executing the project being inspected.
  local names_dir = fs.absolute(T.work .. "/check-names")
  fs.mkdir(names_dir .. "/lib")
  fs.write(names_dir .. "/lib/private.lua", "error('the checker executed a project module')\n")
  local function inspect(source)
    local path = names_dir .. "/names.lua"
    fs.write(path, source)
    return checker.file(path, names_dir)
  end
  report = inspect('global none\nglobal <const> require\nlocal files = require "fs"\nfiles.exist("x")\n')
  check("a misspelt export on a local alias is a name error with its source line and suggestion",
    #report.errors == 1 and report.errors[1].kind == "name" and report.errors[1].line == 4
    and report.errors[1].module == "fs" and report.errors[1].name == "exist" and report.errors[1].suggestion == "exists"
    and contains(report.errors[1].message, "files.exist is not a name in fs; did you mean files.exists?"),
    report.errors[1] and report.errors[1].message)
  r = T.kuu { "check", "--json", names_dir .. "/names.lua" }
  local named = json.decode(r.out)
  check("check --json carries the name error and exits 1", r.code == 1 and named and not named.ok
    and named.result.files[1].errors[1].kind == "name" and named.result.files[1].errors[1].suggestion == "exists", T.describe(r))
  report = inspect([=[
global none
global <const> require
local files <const>, json = require("f\x73"), require [==[json]==]
files.exists("x")
json.encode({})
local rt, task = require "rt", require "task"
local optional = rt.program
task.relay = nil
local method = "exist"
files[method]("x")
local private = require "lib.private"
private.anything()
local command = require "cmd.run"
command.anything()
]=])
  check("known exports, literal escapes, multiple bindings, optional fields and dynamic/project access are accepted",
    #report.errors == 0 and #report.warnings == 0 and #report.requires == 6,
    report.errors[1] and report.errors[1].message)
  report = inspect([==[
global none
global <const> require
local fs = require "fs"
-- fs.exist(); require "commented"
--[=[ fs.exist(); require "long-comment" ]=]
local short = "fs.exist(); require \"quoted\""
local long = [=[fs.exist(); require "long-string"]=]
fs.exists("x")
]==])
  check("strings and both comment forms contribute no accesses or requires",
    #report.errors == 0 and #report.warnings == 0 and #report.requires == 1 and report.requires[1] == "fs")
  report = inspect([=[
global none
global <const> require, pairs
local fs = require "fs"
do local fs = {}; fs.exist() end
local function parameter(fs) fs.exist() end
local function outer()
  local fs = {}
  fs.exist()
end
for fs in pairs({}) do fs.exist() end
for fs = 1, 2 do local x = fs.whatever end
if true then local fs = {} fs.exist() else local fs = {} fs.exist() end
repeat local fs = {} fs.exist() until fs.done
fs.exist("x")
]=])
  check("block, function-parameter and loop shadows do not hide a later real error",
    #report.errors == 1 and report.errors[1].line == 14 and report.errors[1].name == "exist",
    report.errors[1] and report.errors[1].message)
  report = inspect([=[
global none
global <const> require
local fs = require "fs"
local function captured() fs.custom() end
if true then fs = {} end
fs.custom()
local require = function() return {} end
local other = require "not-a-module"
other.custom()
]=])
  check("reassignment including captured bindings and a shadowed require is conservatively skipped",
    #report.errors == 0 and #report.warnings == 0 and #report.requires == 1 and report.requires[1] == "fs")
  report = inspect('local global = require "fs"\nglobal.exists(".")\n')
  check("the contextual word global can still be a local alias without declaring globals",
    #report.errors == 0 and #report.warnings == 1 and report.warnings[1].kind == "globals")
  report = inspect('--[=[global none]=]\nlocal text = "global none"\n')
  check("a global declaration inside a comment or string does not suppress its warning",
    #report.errors == 0 and #report.warnings == 1 and report.warnings[1].kind == "globals")
  report = inspect('global none\nglobal <const> require\nlocal fs = require "fs"\nfs.zzzzzzzz()\n')
  check("unrelated export names do not get a misleading suggestion",
    #report.errors == 1 and report.errors[1].suggestion == nil)
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


  -- The palette description. Each of these runs without complaint today: the
  -- call is well formed, and the branch it guards is simply never taken.
  do
    local head = 'global none\nglobal <const> require, print\n'
      .. 'local err = require "err"\nlocal proc = require "proc"\nlocal rt = require "rt"\n'
    local function first(r) return r.errors[1] and r.errors[1].message end

    report = inspect(head .. 'if err.is(nil, "PROC", "notfund") then print(1) end\n')
    check("a code its domain does not have is an error, with the nearest real one",
      #report.errors == 1 and report.errors[1].kind == "code"
        and report.errors[1].suggestion == "notfound", first(report))

    report = inspect(head .. 'if err.is(nil, "PROC", "notfound") then print(1) end\n')
    check("a code its domain does have is not", #report.errors == 0, first(report))

    -- err.new is public, so a project names its own domains and an unfamiliar
    -- one says nothing. TEST is one edit from kuu's TEXT, so a suggestion
    -- here would have been confidently wrong.
    report = inspect(head .. 'if err.is(nil, "TEST", "boom") then print(1) end\n')
    check("a domain kuu does not own is left alone", #report.errors == 0, first(report))

    report = inspect(head .. 'local r = proc.run { "git", cwdd = "x" }\nprint(r)\n')
    check("an option the call does not take is an error",
      #report.errors == 1 and report.errors[1].kind == "option"
        and report.errors[1].suggestion == "cwd", first(report))

    report = inspect(head .. 'local r = proc.run { "git", cwd = "x", timeout = "30s" }\nprint(r)\n')
    check("the options it does take are not", #report.errors == 0, first(report))

    report = inspect(head .. 'if rt.version == "0.9" then print(1) end\n')
    check("the version compared by text is an error",
      #report.errors == 1 and report.errors[1].kind == "value", first(report))

    report = inspect(head .. 'if rt.route == "flie" then print(1) end\n')
    check("a closed set compared with a literal outside it is an error",
      #report.errors == 1 and report.errors[1].kind == "value"
        and report.errors[1].suggestion == "file", first(report))

    report = inspect(head .. 'if rt.route == "file" then print(1) end\n')
    check("a literal inside it is not", #report.errors == 0, first(report))

    -- A reassigned binding is uncertain, and its findings are dropped like
    -- every other finding on one.
    report = inspect(head .. 'proc = nil\nlocal r = proc.run { cwdd = "x" }\nprint(r)\n')
    check("a reassigned module binding reports nothing", #report.errors == 0, first(report))
  end


  -- A project's own modules, read from their text and never run. This is the
  -- larger half of the checking in a consuming project: Time Actual reaches
  -- through one such module 210 times.
  do
    local dir = fs.tempdir { prefix = "kuu-project-" }
    if not dir then
      check("a temporary project for the module fixtures", false, "fs.tempdir failed")
    else
      local function put(rel, text)
        local path = dir .. "/" .. rel
        fs.mkdir(fs.dirname(path))
        fs.write(path, text)
        return path
      end
      put("tasks.lua", 'global none\nlocal task = require "task"\ntask "x" { run = function() end }\n')
      put("tools/project.lua",
        'global none\nlocal M = {}\nfunction M.setup() end\nfunction M.capture(argv) return argv end\nM.root = "."\nreturn M\n')

      put("good.lua", 'global none\nglobal <const> require, print\nlocal p = require "tools.project"\np.setup()\nprint(p.root, p.capture({}))\n')
      local r = T.kuu({ "check", "good.lua" }, { cwd = dir })
      check("a correct project-module access passes",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      put("bad.lua", 'global none\nglobal <const> require, print\nlocal p = require "tools.project"\nprint(p.captur({}))\n')
      r = T.kuu({ "check", "bad.lua" }, { cwd = dir })
      check("a misspelled one is an error, with the nearest real name",
        r.code == 1 and contains(r.out, "p.captur is not a name in tools.project")
          and contains(r.out, "did you mean p.capture"), T.describe(r))

      -- Over-approximate, and bail when the set cannot be bounded. A field
      -- wrongly included costs a missed diagnostic; one wrongly excluded is a
      -- false positive on correct code, which is far worse.
      put("tools/opaque.lua",
        'global none\nglobal <const> setmetatable\nlocal M = {}\nfunction M.known() end\nreturn setmetatable(M, { __index = function() return function() end end })\n')
      put("dyn.lua", 'global none\nglobal <const> require\nlocal o = require "tools.opaque"\nreturn o.anything_at_all()\n')
      r = T.kuu({ "check", "dyn.lua" }, { cwd = dir })
      check("a module behind a metatable is left unchecked, not guessed at",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      put("tools/computed.lua",
        'global none\nglobal <const> ipairs\nlocal M = {}\nfor _, n in ipairs { "a", "b" } do M[n] = function() end end\nreturn M\n')
      put("comp.lua", 'global none\nglobal <const> require\nlocal c = require "tools.computed"\nreturn c.whatever()\n')
      r = T.kuu({ "check", "comp.lua" }, { cwd = dir })
      check("so is one whose keys are computed",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      put("tools/borrowed.lua", 'global none\nglobal <const> require\nlocal M = require "fs"\nreturn M\n')
      put("bor.lua", 'global none\nglobal <const> require\nlocal b = require "tools.borrowed"\nreturn b.anything()\n')
      r = T.kuu({ "check", "bor.lua" }, { cwd = dir })
      check("and one that returns a table it did not build",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      -- A module that opens with a table of constants is an ordinary shape,
      -- and its constructor's keys are exports. Missing them reported every
      -- correct use of one as a typo, which is the false positive this
      -- extraction exists to avoid.
      put("tools/consts.lua",
        'global none\nlocal M = {\n  VERSION = "1",\n  LIMIT = 10,\n  paths = { build = "b" },\n}\nfunction M.go() end\nreturn M\n')
      put("consts.lua",
        'global none\nglobal <const> require, print\nlocal c = require "tools.consts"\nprint(c.VERSION, c.LIMIT, c.paths, c.go)\n')
      r = T.kuu({ "check", "consts.lua" }, { cwd = dir })
      check("a constructor's own keys are exports, not typos",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      put("constbad.lua",
        'global none\nglobal <const> require, print\nlocal c = require "tools.consts"\nprint(c.LIMITT)\n')
      r = T.kuu({ "check", "constbad.lua" }, { cwd = dir })
      check("and a misspelling of one is still caught",
        r.code == 1 and contains(r.out, "did you mean c.LIMIT"), T.describe(r))

      put("tools/constcomputed.lua",
        'global none\nlocal k = "a"\nlocal M = { [k] = 1, real = 2 }\nreturn M\n')
      put("constdyn.lua",
        'global none\nglobal <const> require\nlocal c = require "tools.constcomputed"\nreturn c.anything\n')
      r = T.kuu({ "check", "constdyn.lua" }, { cwd = dir })
      check("a computed key in the constructor bails like any other",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      -- Only the first field after an alias names a module export. Reaching
      -- further asks a value the module returned, which its export set cannot
      -- answer -- and recording it against the module crashed the report.
      put("nested.lua",
        'global none\nglobal <const> require, print\nlocal c = require "tools.consts"\nprint(c.paths.build, c.paths.build.deeper)\n')
      r = T.kuu({ "check", "nested.lua" }, { cwd = dir })
      check("a second field is not checked against the module, and does not crash",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      fs.remove(dir, { recursive = true })
    end
  end

end
