-- check.lua -- `kuu check`: syntax errors with lines, undeclared globals under a
-- declaration, the warning without one, require resolution, pruning, JSON.
global none
global <const> require, ipairs, pairs, tostring, type, table, pcall

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
  fs.write(project .. "/manifest.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask "x" { run = function() end }\n')
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
  check("check.file on a missing file is one error and still has a tools array",
    #report.errors == 1 and contains(report.errors[1].message, "FS notfound") and type(report.tools) == "table" and #report.tools == 0)
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
  do
    local varargs = inspect('global none\nglobal <const> require\nlocal fs = require "fs"\n'
      .. 'local function first(... values) return values[1] end\n'
      .. 'local function shadow(prefix, ... fs) return fs[1].anything(prefix) end\n'
      .. 'local function loader(... require) return require[1].anything end\n'
      .. 'return first(7), shadow, loader, fs.exists\n')
    check("Lua 5.5 named varargs parse and shadow module bindings",
      #varargs.errors == 0 and #varargs.warnings == 0 and #varargs.requires == 1,
      json.encode(varargs.errors))
    r = T.kuu { "check", "--json", names_dir .. "/names.lua" }
    local named_varargs = json.decode(r.out)
    check("a named-vararg file has a complete successful JSON check report",
      r.code == 0 and named_varargs and named_varargs.ok, T.describe(r))
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
    report = inspect(head .. 'if rt.version < "0.9" or "0.11" >= rt.version then print(1) end\n')
    check("two-component versions still reject lexicographic ordering in either direction",
      #report.errors == 2 and report.errors[1].kind == "value" and report.errors[2].kind == "value"
        and contains(first(report), "rt.version_at_least"), first(report))

    report = inspect(head .. 'if rt.route == "flie" then print(1) end\n')
    check("a closed set compared with a literal outside it is an error",
      #report.errors == 1 and report.errors[1].kind == "value"
        and report.errors[1].suggestion == "file", first(report))

    report = inspect(head .. 'if rt.route == "file" then print(1) end\n')
    check("a literal inside it is not", #report.errors == 0, first(report))
    report = inspect(head .. 'if rt.route < "z" then print(1) end\n')
    check("ordinary enum ordering does not become a closed-set equality finding",
      #report.errors == 0, first(report))
    report = inspect(head .. 'local a, b, c = rt.version:match("^(%d+)%.(%d+)(%d+)$")\nprint(a, b, c)\n')
    check("three numeric captures are not mistaken for three version components",
      #report.errors == 0, first(report))

    -- Indexed where it is required. A consuming project carried two dead
    -- `require('rt').version == '0.5'` branches that every check above walked
    -- past, because each followed the local binding and this shape has none.
    local bare = 'global none\nglobal <const> require, print\n'
    report = inspect(bare .. 'if require("rt").version == "0.5" then print(1) end\n')
    check("a module indexed where it is required is checked too",
      #report.errors == 1 and report.errors[1].kind == "value"
        and contains(report.errors[1].message, 'require("rt").version is N.N (two natural numbers)'),
      first(report))

    report = inspect(bare .. 'print(require("fs").exist("x"))\n')
    check("and its names are",
      #report.errors == 1 and report.errors[1].kind == "name"
        and report.errors[1].module == "fs" and report.errors[1].suggestion == "exists",
      first(report))

    report = inspect(bare .. 'print(require("proc").run { "git", cwdd = "x" })\n')
    check("and its options are",
      #report.errors == 1 and report.errors[1].kind == "option"
        and report.errors[1].suggestion == "cwd", first(report))

    report = inspect(bare .. 'if require("err").is(nil, "PROC", "notfund") then print(1) end\n')
    check("and its codes are",
      #report.errors == 1 and report.errors[1].kind == "code"
        and report.errors[1].suggestion == "notfound", first(report))

    report = inspect(bare .. 'print(require("fs").exists("x"), require("rt").version_at_least(0, 9))\n')
    check("a correct one through that shape is still not an error",
      #report.errors == 0, first(report))

    -- The name it is required by is the only thing that shape can be read
    -- from, so a computed one says nothing and is left alone.
    report = inspect(bare .. 'local n = "fs"\nprint(require(n).exist("x"))\n')
    check("a computed module name through it is left alone",
      #report.errors == 0, first(report))

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
      put("manifest.lua", 'global none\nlocal task = require "task"\ntask "x" { run = function() end }\n')
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

      -- The extraction on its own, as capabilities reports it: the same set
      -- the checker uses, or nil where the text does not bound it.
      local set = checker.exports(dir .. "/tools/consts.lua")
      check("check.exports reads a module's names from its text",
        set ~= nil and set.VERSION and set.LIMIT and set.paths and set.go and not set.nothing, tostring(set))
      check("check.exports is nil for a module behind a metatable", checker.exports(dir .. "/tools/opaque.lua") == nil)
      check("check.exports is nil for a module that returns what it did not build", checker.exports(dir .. "/tools/borrowed.lua") == nil)
      check("check.exports is nil for a path that is not there", checker.exports(dir .. "/tools/absent.lua") == nil)

      put("tools/constcomputed.lua",
        'global none\nlocal k = "a"\nlocal M = { [k] = 1, real = 2 }\nreturn M\n')
      put("constdyn.lua",
        'global none\nglobal <const> require\nlocal c = require "tools.constcomputed"\nreturn c.anything\n')
      r = T.kuu({ "check", "constdyn.lua" }, { cwd = dir })
      check("a computed key in the constructor bails like any other",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      -- A metatable on the module's own objects is not a metatable on the
      -- module. The token alone used to put the whole module out of reach,
      -- which the generated corpus found: every module that builds a class
      -- went unchecked.
      put("tools/classy.lua",
        'global none\nglobal <const> setmetatable\nlocal M = {}\nlocal Thing = {}\nThing.__index = Thing\nfunction M.new() return setmetatable({}, Thing) end\nfunction M.count() return 0 end\nreturn M\n')
      put("classy.lua",
        'global none\nglobal <const> require, print\nlocal c = require "tools.classy"\nprint(c.new(), c.coutn())\n')
      r = T.kuu({ "check", "classy.lua" }, { cwd = dir })
      check("a module that builds its own objects with setmetatable is still bounded",
        r.code == 1 and contains(r.out, "did you mean c.count"), T.describe(r))
      put("tools/aliased.lua",
        'global none\nglobal <const> setmetatable\nlocal M = {}\nfunction M.known() end\nlocal T = M\nsetmetatable(T, { __index = function() return 1 end })\nreturn M\n')
      put("aliased.lua",
        'global none\nglobal <const> require\nlocal m = require "tools.aliased"\nreturn m.anything()\n')
      r = T.kuu({ "check", "aliased.lua" }, { cwd = dir })
      check("but a module that lets its table escape near setmetatable is not guessed at",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))
      put("tools/mutated.lua",
        'global none\nlocal M = { first = 1 }\nlocal alias = M\nalias.second = 2\nreturn M\n')
      put("mutated.lua", 'global none\nglobal <const> require\nlocal m = require "tools.mutated"\nreturn m.second\n')
      r = T.kuu({ "check", "mutated.lua" }, { cwd = dir })
      check("an ordinary escaped alias puts the export set out of reach too",
        checker.exports(dir .. "/tools/mutated.lua") == nil and r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      -- Only the first field after an alias names a module export. Reaching
      -- further asks a value the module returned, which its export set cannot
      -- answer -- and recording it against the module crashed the report.
      put("nested.lua",
        'global none\nglobal <const> require, print\nlocal c = require "tools.consts"\nprint(c.paths.build, c.paths.build.deeper)\n')
      r = T.kuu({ "check", "nested.lua" }, { cwd = dir })
      check("a second field is not checked against the module, and does not crash",
        r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      -- Tools: the manifest's declarations read as literals, and every call
      -- through the door, in any file, held to them.
      put("manifest.lua", table.concat({
        'global none', 'global <const> require', 'local task, rt = require "task", require "rt"',
        'task.tool "report" {', '  exe = "tools/report.exe",',
        '  args = { ["--out"] = "path", ["--since"] = "string", quiet = "flag" },',
        '  output = "ndjson", emits = { "rows" }, timeout = "5m",', '}',
        'task.tool("plain", { exe = "tools/plain.exe" })',
        'local later = "x"', 'task.tool "dyn" { exe = later }',
        'task "ok" { run = function() return task.exec { tool = "report", "--out", "build/r.json", "quiet" } end }',
        'task "typo" { run = function() return task.exec { tool = "report", "--sinc", "yesterday" } end }',
        'task "nosuch" { run = function() return task.exec { tool = "reprot" } end }',
        'task "bare" { run = function() return task.exec { "cmd.exe", "/c", "dir" } end }',
        'task "free" { run = function() return task.exec { tool = "plain", "--anything" } end }',
        -- values are not options: a path, a negative number, --name=value, and the value an option takes
        'task "values" { run = function() return task.exec { tool = "report", "--out", "/tmp/r.json", "--since", "-1", "--out=x", "quiet", "-" } end }',
        -- a table the checker cannot see into, and a tool it cannot name, are not judged
        'local spec = { tool = "report" }',
        'task "var" { run = function() return task.exec(spec) end }',
        'local which = "report"',
        'task "named" { run = function() return task.exec { tool = which, "--nope" } end }',
        -- declared once per arm: the text cannot tell which one runs
        'if rt.route == "file" then task.tool "dup" { exe = "a.exe" } else task.tool "dup" { exe = "b.exe" } end',
        'task "dupcall" { run = function() return task.exec { tool = "dup", "--x" } end }',
      }, "\n") .. "\n")
      put("tools/wrap.lua", 'global none\nglobal <const> require\nlocal task = require "task"\nlocal M = {}\n'
        .. 'function M.go() return task.command { tool = "report", "--outt", "x" } end\nreturn M\n')
      r = T.kuu({ "check", "--json" }, { cwd = dir })
      local report = json.decode(r.out)
      local by = {}
      for _, f in ipairs(report and report.result.files or {}) do by[f.path:gsub("\\", "/")] = f end
      local m, w = by["manifest.lua"], by["tools/wrap.lua"]
      local function first(f, kind)
        for _, e in ipairs(f and f.errors or {}) do if e.kind == kind then return e end end
        return nil
      end
      check("the manifest's bounded declarations are reported with their attributes",
        m ~= nil and #m.tools == 2 and m.tools[1].name == "report" and m.tools[1].args["--out"] == "path"
          and m.tools[1].output == "ndjson" and m.tools[1].emits[1] == "rows" and m.tools[2].name == "plain" and m.tools[2].args == nil,
        r.out:sub(1, 400))
      local typo = first(m, "option")
      check("a misspelt argument is an option finding with the nearest name",
        typo ~= nil and typo.name == "--sinc" and typo.suggestion == "--since" and typo.module == "report", json.encode(m and m.errors))
      local missing = first(m, "name")
      check("an undeclared tool is a name finding with the nearest declared",
        missing ~= nil and missing.name == "reprot" and missing.suggestion == "report" and missing.module == "manifest", json.encode(m and m.errors))
      local twice, all_tool = false, m ~= nil and #m.warnings == 3
      for _, w in ipairs(m and m.warnings or {}) do
        all_tool = all_tool and w.kind == "tool"
        if w.message:find("more than once", 1, true) then twice = true end
      end
      check("a declaration the text does not bound, a call with no declaration, and a name declared twice are tool warnings",
        all_tool and twice, json.encode(m and m.warnings))
      check("values, a table the checker cannot see into, a tool it cannot name, and a tool declared twice are not judged, so the manifest has exactly two errors",
        m ~= nil and #m.errors == 2, json.encode(m and m.errors))
      check("a project module's call is held to the manifest's declaration",
        w ~= nil and #w.errors == 1 and w.errors[1].kind == "option" and w.errors[1].suggestion == "--out", json.encode(w and w.errors))

      -- The two readings of one declaration: what check took from the text
      -- and what capabilities took from the registry the manifest filled.
      local function equal(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
      end
      local scanned = checker.tools(dir)
      r = T.kuu({ "capabilities", "--json" }, { cwd = dir })
      local descriptor = json.decode(r.out)
      local executed = {}
      for _, x in ipairs(descriptor and descriptor.result.project.tools or {}) do executed[x.name] = x end
      local same = #scanned == 2 and executed.report ~= nil and executed.plain ~= nil and executed.dyn ~= nil and executed.dup ~= nil
      for _, s in ipairs(scanned) do
        local x = executed[s.name]
        same = same and x ~= nil and x.exe == s.exe and x.output == s.output and x.timeout == s.timeout
          and equal(x.emits, s.emits) and equal(x.args, s.args) and equal(x.reach, s.reach)
      end
      check("check's reading of a declaration equals the registry's, attribute for attribute", same,
        json.encode(scanned) .. " vs " .. json.encode(executed))
      -- On the wire, too: an empty list is an array in both.
      r = T.kuu({ "check", "--json" }, { cwd = dir })
      check("check --json spells a declaration's empty lists as arrays, as capabilities does",
        contains(r.out, '"emits":[]') and not contains(r.out, '"emits":{}'), r.out:sub(1, 400))
      do
        put("tool-arguments.lua", 'global none\nglobal <const> require\nlocal task = require "task"\n'
          .. 'task.command { tool = "report", "--out=value", "--sinc" }\n'
          .. 'task.command { tool = "report", "--", "--file-name" }\n')
        r = T.kuu({ "check", "--json", "tool-arguments.lua" }, { cwd = dir })
        local arguments = json.decode(r.out)
        local findings = arguments and arguments.result.files[1].errors or {}
        check("inline option values consume no following token and -- ends option checking",
          r.code == 1 and #findings == 1 and findings[1].kind == "option" and findings[1].name == "--sinc", r.out)
      end
      -- The description now names the options of every option-taking call,
      -- so a misspelt one is found in any module, and a declaration's
      -- attribute is held to task.tool's set.
      put("described.lua", table.concat({
        'global none', 'global <const> require',
        'local hash, time, csv, task = require "hash", require "time", require "csv", require "task"',
        'local a = hash.sum("sha256", "x", { raww = true })',
        'local b = time.make { year = 2026, mnth = 2 }',
        'local c = csv.decode("a,b", { separater = ";" })',
        'task.tool "described" { exe = "x.exe", outputt = "lines" }',
        'return a, b, c',
      }, "\n") .. "\n")
      r = T.kuu({ "check", "--json", "described.lua" }, { cwd = dir })
      local described = json.decode(r.out)
      local found = {}
      for _, e in ipairs(described and described.result.files[1].errors or {}) do found[#found + 1] = e.kind .. ":" .. e.name .. ">" .. tostring(e.suggestion) end
      table.sort(found)
      check("an option a described call does not take is found in hash, time and csv alike, and a declaration's attribute in any file",
        table.concat(found, " ") == "option:mnth>month option:outputt>output option:raww>raw option:separater>separator",
        table.concat(found, " "))
      put("manifest.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask.tool "declared" { exe = "x.exe", outputt = "lines" }\ntask.tool("direct", { exe = "y.exe", outputt = "lines" })\n')
      r = T.kuu({ "check", "--json", "manifest.lua" }, { cwd = dir })
      local declared = json.decode(r.out)
      local attributes = {}
      for _, e in ipairs(declared and declared.result.files[1].errors or {}) do
        attributes[#attributes + 1] = e.kind .. ":" .. e.name .. ">" .. tostring(e.suggestion) .. "@" .. e.line
      end
      table.sort(attributes)
      check("an attribute a tool declaration cannot hold is one option finding per declaration, in either spelling, with the nearest attribute",
        table.concat(attributes, " ") == "option:outputt>output@4 option:outputt>output@5", r.out:sub(1, 400))
      -- the same, in a file that is not the manifest, and an option
      -- task.exec does not take, since it neither feeds nor streams
      put("elsewhere.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask.tool "x2" { exe = "a.exe", outputt = "lines" }\n'
        .. 'task.tool("y2", { exe = "b.exe", outputt = "lines" })\ntask.exec { "cmd.exe", "/c", "dir", stdin = "", stream = true }\n')
      r = T.kuu({ "check", "--json", "elsewhere.lua" }, { cwd = dir })
      local elsewhere = json.decode(r.out)
      local names = {}
      for _, e in ipairs(elsewhere and elsewhere.result.files[1].errors or {}) do names[#names + 1] = e.kind .. ":" .. e.name .. "@" .. e.line end
      table.sort(names)
      check("outside the manifest both spellings are judged alike, and task.exec's stdin and stream are found",
        table.concat(names, " ") == "option:outputt@4 option:outputt@5 option:stdin@6 option:stream@6", table.concat(names, " "))

      -- The root however it is spelled: the manifest is recognised as itself
      -- under backslashes, a trailing slash, and a `..`, where a text compare
      -- once recursed until the stack ran out.
      local spellings = { dir:gsub("/", "\\"), dir .. "/", dir .. "/tools/.." }
      local every_way = true
      for _, spelling in ipairs(spellings) do
        local ok2, result = pcall(checker.file, dir .. "/tools/wrap.lua", spelling)
        every_way = every_way and ok2 and #result.errors == 1
      end
      check("a root spelled any way finds the manifest, and never recurses", every_way)
      -- Public versions return to two components in 0.11. Those guards
      -- pass; requiring three components is diagnosed before the manifest
      -- runs, naming the numeric comparison and the migration page.
      put("guard.lua", 'global none\nglobal <const> require, tonumber, string\nlocal rt = require "rt"\nlocal major, minor = rt.version:match("^(%d+)%.(%d+)$")\n'
        .. 'local again = string.match(rt.version, "^(%d+)%.(%d+)$")\n'
        .. 'local a, b, c = rt.version:match("^(%d+)%.(%d+)%.(%d+)$")\nlocal legacy = string.match(rt.version, "^(%d+)%.(%d+)%.(%d+)$")\n'
        .. 'local first = rt.version:match("^(%d+)")\nlocal spelled = rt.version:gsub("%.", "_")\n'
        .. 'return tonumber(major), tonumber(minor), again, a, b, c, legacy, first, spelled\n')
      r = T.kuu({ "check", "--json", "guard.lua" }, { cwd = dir })
      local guard = json.decode(r.out)
      local found_guard = {}
      for _, e in ipairs(guard and guard.result.files[1].errors or {}) do found_guard[#found_guard + 1] = e.kind .. "@" .. e.line .. ":" .. tostring(e.name) end
      check("three-component guards name version_at_least and upgrading-0.11 in both spellings, while two-component and partial patterns pass",
        r.code == 1 and table.concat(found_guard, " ") == "value@6:^(%d+)%.(%d+)%.(%d+)$ value@7:^(%d+)%.(%d+)%.(%d+)$"
          and contains(guard.result.files[1].errors[1].message, "N.N (two natural numbers)")
          and contains(guard.result.files[1].errors[1].message, "three components")
          and contains(guard.result.files[1].errors[1].message, "rt.version_at_least") and contains(guard.result.files[1].errors[1].message, "kuu docs upgrading-0.11"),
        table.concat(found_guard, " ") .. " " .. r.out:sub(1, 300))

      put("guard.lua", 'global none\nglobal <const> require, string\nlocal rt = require "rt"\n'
        .. 'local a, b = rt.version:match("^(%d+)%.(%d+)$")\nlocal c, d = string.match(rt.version, "^(%d+)%.(%d+)$")\n'
        .. 'return a, b, c, d, rt.version_at_least(0, 11)\n')
      r = T.kuu({ "check", "--json", "guard.lua" }, { cwd = dir })
      guard = json.decode(r.out)
      check("a two-component version guard and the recommended numeric check pass without findings",
        r.code == 0 and guard and guard.ok and #guard.result.files[1].errors == 0
          and #guard.result.files[1].warnings == 0, T.describe(r))

      -- A number or a boolean where a literal may stand is not a string, and
      -- nothing downstream may take it for one.
      put("literals.lua", 'global none\nglobal <const> require\nlocal rt = require "rt"\nlocal m = require(42)\nif rt.route == 1 or rt.route == true then return m end\n')
      r = T.kuu({ "check", "literals.lua" }, { cwd = dir })
      check("a number or boolean in a literal's place is passed over, not crashed on", r.code == 0 and contains(r.err, "0 errors"), T.describe(r))

      do
        for _, fields in ipairs {
          'emits = "rows"', 'emits = { "rows", named = "lost" }',
          'reach = "all"', 'reach = { read = "files" }',
          'args = "--all"', 'output = false',
        } do
          put("manifest.lua", 'global none\nglobal <const> require\nlocal task = require "task"\n'
            .. 'task.tool "bad" { exe = "bad.exe", ' .. fields .. ' }\n')
          r = T.kuu({ "check", "--json", "manifest.lua" }, { cwd = dir })
          local decoded, malformed = pcall(json.decode, r.out)
          local file = decoded and malformed and malformed.result.files[1]
          check("malformed literal tool fields produce findings in a valid JSON envelope",
            r.code == 1 and file and #file.errors == 1 and file.errors[1].kind == "value" and #file.tools == 0,
            fields .. ": " .. r.out .. r.err)
        end
        put("manifest.lua", 'global none\nglobal <const> require\nlocal task = require "task"\n'
          .. 'task.tool "bytes" { exe = "bad\\233.exe", args = { ["--bad\\233"] = "flag" } }\n')
        r = T.kuu({ "check", "--json", "manifest.lua" }, { cwd = dir })
        local decoded, bytes = pcall(json.decode, r.out)
        check("non-UTF-8 source literals cannot break the check JSON envelope",
          decoded and bytes and bytes.result and #bytes.result.files == 1 and r.code == 0, T.describe(r))
      end

      -- A manifest that does not parse declares nothing anyone can read, and
      -- no call is judged against it.
      put("manifest.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask.tool "report" { exe = "x.exe"\n')
      r = T.kuu({ "check", "--json" }, { cwd = dir })
      local broken = json.decode(r.out)
      local wrap_errors, manifest_errors
      for _, f in ipairs(broken and broken.result.files or {}) do
        local path = f.path:gsub("\\", "/")
        if path == "tools/wrap.lua" then wrap_errors = f.errors elseif path == "manifest.lua" then manifest_errors = f.errors end
      end
      check("a manifest that does not parse is one syntax error, not one 'not declared' per call site",
        manifest_errors ~= nil and #manifest_errors == 1 and manifest_errors[1].kind == "syntax"
          and wrap_errors ~= nil and #wrap_errors == 0, r.out:sub(1, 400))

      fs.remove(dir, { recursive = true })
    end
  end

  do
    local dir = fs.absolute(T.work .. "/check-review-fixes")
    fs.remove(dir, { recursive = true })
    fs.mkdir(dir)
    local manifest = 'global none\nglobal <const> require\nlocal task = require "task"\n'
      .. 'task.tool "sample" { exe="sample.exe", args={ ["--good"]="flag" } }\n'
    fs.write(dir .. "/manifest.lua", (manifest:gsub("global <const> require\n", "")))
    fs.write(dir .. "/consumer.lua", 'global none\nglobal <const> require\nlocal task=require "task"\nreturn task.exec {tool="sample", "--bad"}\n')
    local before = checker.file(dir .. "/consumer.lua", dir)
    fs.write(dir .. "/manifest.lua", manifest)
    local after = checker.file(dir .. "/consumer.lua", dir)
    check("independent check.file calls refresh edited manifest declarations",
      #before.errors == 0 and #after.errors == 1 and after.errors[1].name == "--bad", json.encode(after.errors))
    fs.write(dir .. "/manifest.lua", (manifest:gsub("global <const> require\n", "")))
    local fixed = T.kuu({ "check", "--json", "--fix" }, { cwd = dir })
    local fixed_report = json.decode(fixed.out)
    local again = T.kuu({ "check", "--json" }, { cwd = dir })
    local current = json.decode(again.out)
    check("check --fix uses repaired manifest declarations in its final report",
      fixed.code == 1 and again.code == 1 and fixed_report and current
        and fixed_report.result.errors == 1 and current.result.errors == 1 and #fixed_report.result.fixed == 1,
      T.describe(fixed))

    for _, source in ipairs {
      'task={tool=function() return function(x) return x end end}; return task.tool "custom" {arbitrary=true}',
      'task={tool=function(_, x) return x end}; return task.tool("custom", {arbitrary=true})',
      'local function later() return task.tool "custom" {arbitrary=true} end; task={tool=function() return function(x) return x end end}; return later',
    } do
      fs.write(dir .. "/alias.lua", 'global none\nglobal <const> require\nlocal task=require "task"\n' .. source .. '\n')
      local alias = checker.file(dir .. "/alias.lua", dir)
      check("reassigned task bindings do not create direct, curried or captured tool declarations",
        #alias.errors == 0 and #alias.tools == 0, json.encode(alias.errors))
    end
    fs.write(dir .. "/factory.lua", 'global none\nlocal M={first=1}\nlocal M={second=2}\nreturn M\n')
    fs.write(dir .. "/consumer.lua", 'global none\nglobal <const> require\nlocal M=require "factory"\nreturn M.second\n')
    local shadowed = checker.file(dir .. "/consumer.lua", dir)
    check("a redeclared export-table local is conservatively left unchecked",
      checker.exports(dir .. "/factory.lua") == nil and #shadowed.errors == 0, json.encode(shadowed.errors))

    fs.write(dir .. "/café.lua", 'global none\nlocal M={available=true}\nreturn M\n')
    fs.write(dir .. "/dotted.name.lua", 'global none\nlocal M={unreachable=true}\nreturn M\n')
    fs.write(dir .. "/consumer.lua", 'global none\nglobal <const> require\nlocal M=require "café"\nreturn M.available\n')
    local unicode = checker.file(dir .. "/consumer.lua", dir)
    local modules = checker.modules(dir)
    local unicode_found, dotted_found = false, false
    for _, module in ipairs(modules.modules) do
      if module.name == "café" then unicode_found = true end
      if module.name == "dotted.name" then dotted_found = true end
    end
    local loaded = T.kuu({ "-e", 'local rt=require "rt"; rt.root("."); assert(require("café").available)' }, { cwd = dir })
    check("module discovery and checking follow runtime Unicode and dotted-path rules",
      #unicode.errors == 0 and #unicode.warnings == 0 and unicode_found and not dotted_found and modules.complete and loaded.code == 0,
      json.encode(modules) .. T.describe(loaded))

    local original_dirs, original_list, original_read = fs.dirs, fs.list, fs.read
    fs.dirs = function() return { paths = {}, errors = { { path = dir .. "/hidden", win32 = 32, reason = "sharing violation" } } } end
    local walked, tree, inventory = pcall(function() return checker.tree(dir), checker.modules(dir) end)
    fs.dirs = original_dirs
    check("unreadable subtrees produce read findings and incomplete module inventories",
      walked and #tree.reports == 1 and tree.reports[1].errors[1].kind == "read"
        and tree.reports[1].errors[1].win32 == 32 and not inventory.complete and #inventory.errors == 1,
      tostring(tree))
    fs.dirs = function() return { paths = { dir }, errors = {} } end
    fs.list = function() return { entries = {}, errors = { "the listing stopped early" } } end
    local listed, partial, partial_modules = pcall(function() return checker.tree(dir), checker.modules(dir) end)
    fs.dirs, fs.list = original_dirs, original_list
    check("partial directory listings cannot become successful empty check results",
      listed and #partial.reports == 1 and contains(partial.reports[1].errors[1].message, "stopped early")
        and not partial_modules.complete and #partial_modules.errors == 1, tostring(partial))
    fs.read = function(path, opts)
      if path == dir .. "/café.lua" then return nil, require("err").new("FS", "access", "module held open") end
      return original_read(path, opts)
    end
    local read, unreadable = pcall(checker.modules, dir)
    fs.read = original_read
    check("an unreadable candidate module marks its inventory incomplete",
      read and not unreadable.complete and #unreadable.errors == 1
        and unreadable.errors[1].path == dir .. "/café.lua", tostring(unreadable))
    fs.remove(dir, { recursive = true })
  end
end
