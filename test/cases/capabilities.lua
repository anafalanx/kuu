-- capabilities.lua -- `kuu capabilities`: the one command an agent runs in an
-- unfamiliar checkout, so every claim it makes has to be true.
--
-- Two kinds of check here. The descriptor is assembled from things that
-- cannot drift -- the modules' own export tables, the payload's own entries
-- -- and the first group holds it to those sources rather than to a copy of
-- the expected answer. The second group is about what it refuses to say: a
-- module whose exports the text does not bound is counted and not named, and
-- a project that does not load costs the task list and nothing else.
global none
global <const> require, ipairs, pcall, tostring, type, table

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local json = require "json"
  local rt = require "rt"

  local root = fs.canon(T.root).path

  -- The two payload accessors the descriptor is built on. A verb is a file
  -- under lua/cmd and a page is a file under docs; if C and the tree ever
  -- disagree, everything downstream is confidently wrong.
  local function names_in(dir, suffix)
    local names = {}
    for _, entry in ipairs(fs.list(root .. "/" .. dir).entries) do
      if entry.kind == "file" and entry.name:sub(-#suffix) == suffix then
        names[#names + 1] = entry.name:sub(1, -#suffix - 1)
      end
    end
    table.sort(names)
    return table.concat(names, " ")
  end
  check("rt.verbs() is exactly what lua/cmd holds",
    table.concat(rt.verbs(), " ") == names_in("lua/cmd", ".lua"),
    table.concat(rt.verbs(), " ") .. " vs " .. names_in("lua/cmd", ".lua"))
  check("rt.pages() is exactly what docs holds",
    table.concat(rt.pages(), " ") == names_in("docs", ".md"),
    table.concat(rt.pages(), " ") .. " vs " .. names_in("docs", ".md"))

  -- A project with one module of each kind: exports the text bounds, exports
  -- it does not, a package reached through init.lua, and a plain program.
  local work = fs.absolute(T.work .. "/capabilities-project")
  fs.remove(work, { recursive = true })
  fs.mkdir(work .. "/lib")
  fs.mkdir(work .. "/pkg")
  fs.mkdir(work .. "/build")
  fs.write(work .. "/manifest.lua",
    'global none\nglobal <const> require\nlocal task = require "task"\n' ..
    'task "build" { desc = "compile it", run = function() end }\n' ..
    'task "test" { desc = "run the suite", deps = { "build" }, run = function() end }\n' ..
    'task.tool "fmt" { exe = "tools/fmt.exe", output = "lines", args = { ["--check"] = "flag" } }\n' ..
    'task.default "test"\n')
  fs.write(work .. "/lib/util.lua",
    'global none\nlocal M = {}\nM.VERSION = "1"\nfunction M.slug(s) return s end\nreturn M\n')
  fs.write(work .. "/pkg/init.lua",
    'global none\nlocal P = {}\nfunction P.open() end\nreturn P\n')
  fs.write(work .. "/dyn.lua",
    'global none\nlocal D = {}\nlocal key = "x"\nD[key] = 1\nreturn D\n')
  fs.write(work .. "/main.lua", 'global none\nglobal <const> print\nprint("hello")\n')
  fs.write(work .. "/build/skip.lua", "this is not lua\n")

  local r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  check("it exits 0 with a project", r.code == 0, T.describe(r))
  local ok, report = pcall(json.decode, r.out)
  check("and prints one envelope", ok and report ~= nil and report.ok == true,
    ok and r.out:sub(1, 200) or tostring(report))
  if not ok or report == nil or report.result == nil then return end
  local result = report.result
  check("execution history makes no unaccounted filesystem-change claim",
    result.project.ledger and result.project.ledger.unaccounted == nil,
    json.encode(result.project.ledger))

  check("it names this runtime", result.kuu.version == rt.version and result.kuu.lua == rt.lua,
    json.encode(result.kuu.version) .. " " .. json.encode(result.kuu.lua))
  check("the verbs and pages are the ones the runtime carries",
    table.concat(result.kuu.verbs, " ") == table.concat(rt.verbs(), " ")
      and #result.kuu.pages == #rt.pages(), json.encode(result.kuu.verbs))
  check("it says what to read and do next, the conduct page first",
    type(result.next) == "table" and #result.next >= 3 and contains(result.next[1], "kuu docs agent"), json.encode(result.next))
  check("without a kuu-eval.md the project's eval says so, counts nothing and dates nothing",
    result.project.eval ~= nil and result.project.eval.present == false and result.project.eval.entries == 0
      and result.project.eval.last == nil, json.encode(result.project.eval))
  check("capabilities is itself among them",
    contains(table.concat(result.kuu.verbs, " "), "capabilities")
      and contains(table.concat(result.kuu.pages, " "), "capabilities"))

  -- The palette listing is read out of the modules' own tables, so the way to
  -- check it is to index those tables, not to compare against a second list.
  local wrong, described = {}, {}
  for _, module in ipairs(result.modules) do
    described[module.name] = true
    local loaded, value = pcall(require, module.name)
    if not loaded or type(value) ~= "table" then
      wrong[#wrong + 1] = module.name .. ": does not load"
    else
      for _, name in ipairs(module.names) do
        -- rt.program is nil on this route and is still part of rt.
        if value[name] == nil and not (module.name == "rt" and name == "program") then
          wrong[#wrong + 1] = module.name .. "." .. name
        end
      end
    end
  end
  table.sort(wrong)
  check("every name it reports is a name its module exports", #wrong == 0,
    table.concat(wrong, ", "))

  local palette = require "_palette"
  local missing = {}
  for _, name in ipairs(palette.public) do
    if not described[name] then missing[#missing + 1] = name end
  end
  check("every public module is reported", #missing == 0, table.concat(missing, ", "))
  check("and nothing else is", #result.modules == #palette.public,
    #result.modules .. " vs " .. #palette.public)

  local fs_names = {}
  for _, module in ipairs(result.modules) do
    if module.name == "fs" then fs_names = module.names end
  end
  check("a module's own names are all there, not a sample",
    #fs_names > 20 and contains(table.concat(fs_names, " "), "tempfile"),
    table.concat(fs_names, " "))

  -- The closed sets are what `err.is` and a literal comparison are matched
  -- against, so an incomplete set here is worse than none.
  local proc_codes
  for _, domain in ipairs(result.errors) do
    if domain.domain == "PROC" then proc_codes = table.concat(domain.codes, " ") end
  end
  check("the error domains carry their complete code sets",
    proc_codes ~= nil and contains(proc_codes, "notfound"), tostring(proc_codes))
  local sets = {}
  for _, set in ipairs(result.sets) do sets[set.name] = table.concat(set.values, " ") end
  check("and the closed sets carry their values",
    sets.ProcStatus == "exit timeout killed limit", tostring(sets.ProcStatus))

  -- The project half.
  local here = result.project
  check("the project is the directory holding manifest.lua",
    here ~= nil and here.root == fs.canon(work).path, here and here.root or "absent")
  check("the descriptor names the file it found", here ~= nil and here.file == "manifest.lua", here and tostring(here.file) or "absent")
  check("the descriptor lists the tools the manifest declares, with their attributes",
    here ~= nil and #here.tools == 1 and here.tools[1].name == "fmt" and here.tools[1].exe == "tools/fmt.exe"
      and here.tools[1].output == "lines" and here.tools[1].args["--check"] == "flag" and #here.tools[1].emits == 0,
    here and json.encode(here.tools) or "absent")
  if here == nil then return end
  local task_names = {}
  for _, t in ipairs(here.tasks) do task_names[#task_names + 1] = t.name end
  check("its tasks are listed with their descriptions and default",
    table.concat(task_names, " ") == "build test" and here.default == "test"
      and here.tasks[1].desc == "compile it", json.encode(here.tasks))

  local by_name = {}
  for _, module in ipairs(here.modules) do by_name[module.name] = module end
  check("a module's exports are read from its text",
    by_name["lib.util"] ~= nil
      and table.concat(by_name["lib.util"].names, " ") == "VERSION slug"
      and by_name["lib.util"].path == "lib/util.lua",
    json.encode(here.modules))
  check("a package is named by its directory, not by init",
    by_name.pkg ~= nil and table.concat(by_name.pkg.names, " ") == "open",
    json.encode(here.modules))
  check("a module whose exports the text does not bound is not named",
    by_name.dyn == nil, json.encode(here.modules))
  check("nor is a program", by_name.main == nil, json.encode(here.modules))
  check("but every .lua file below the root is counted, and pruned ones are not",
    here.files == 5, tostring(here.files))

  -- A directory link is listed by fs.dirs, but is not permission to inventory
  -- its target. Use sibling fixtures and real junctions at two depths.
  do
    local scratch = fs.tempdir { dir = fs.absolute(T.work), prefix = "capabilities-links-" }
    check("a private directory for capabilities link fixtures is created", scratch ~= nil)
    if scratch then
      local proc = require "proc"
      local dir, target = scratch .. "/project", scratch .. "/outside"
      fs.mkdir(dir .. "/src")
      fs.mkdir(target)
      fs.write(dir .. "/manifest.lua", "global none\n")
      fs.write(dir .. "/src/ordinary.lua", "global none\nlocal M = { ordinary = true }\nreturn M\n")
      local sentinel = "global none\nlocal M = { outside = true }\nreturn M\n"
      fs.write(target .. "/sentinel.lua", sentinel)
      local links_ready = true
      for _, path in ipairs { dir .. "/linked", dir .. "/src/nested" } do
        local made = proc.run { "cmd.exe", "/c", "mklink", "/J", path:gsub("/", "\\"), target:gsub("/", "\\"), timeout = "10s" }
        check("capabilities fixture junction is created: " .. path, made and made.code == 0, made and T.describe(made))
        links_ready = links_ready and made ~= nil and made.code == 0
      end
      if links_ready then
        local described = T.kuu({ "capabilities", "--json" }, { cwd = dir })
        local envelope = json.decode(described.out)
        local project = envelope and envelope.result.project
        check("capabilities counts ordinary files and excludes root and nested junction targets",
          described.code == 0 and project and project.files == 2 and #project.modules == 1
            and project.modules[1].name == "src.ordinary" and project.modules_complete
            and #project.module_errors == 0 and not contains(described.out, "sentinel"), T.describe(described))
        local text = T.kuu({ "capabilities" }, { cwd = dir })
        check("capabilities text does not advertise modules from junction targets",
          text.code == 0 and contains(text.out, "src.ordinary") and not contains(text.out, "sentinel"), T.describe(text))
        check("capabilities leaves the outside Lua sentinel untouched", fs.read(target .. "/sentinel.lua") == sentinel)
      end
      fs.remove(scratch, { recursive = true })
    end
  end

  -- What agents wrote back is counted: one entry per `## YYYY-MM-DD` heading
  -- outside fenced code, whatever the bytes after the date; a file that is
  -- there with no such heading is told apart from no file.
  fs.write(work .. "/kuu-eval.md", "# kuu-eval\n\nprose only\n")
  r = T.kuu({ "capabilities" }, { cwd = work })
  check("a kuu-eval.md with no entry is said to be there and empty",
    contains(r.out, "kuu-eval.md is there but holds no entry headed ## YYYY-MM-DD"), r.out)
  fs.write(work .. "/kuu-eval.md", "# kuu-eval\r\n\r\n## 2026-09-11 \u{2014} kuu 0.9.0 \u{2014} first look\r\n\r\n### Worked\r\n- check named the fix\r\n\r\n"
    .. "```text\r\n## 2026-09-13 \u{2014} pasted output, not an entry\r\n```\r\n\r\n"
    .. "## 2026-09-12 - kuu 0.10.0 - the release task, in cp1252 \x97 not UTF-8\r\n\r\n### Difficult\r\n- `kuu run release` said timeout\r\n"
    .. "### 2026-09-14 not an entry either\r\n")
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local with = json.decode(r.out).result.project.eval
  check("kuu-eval.md's entries are counted outside fenced code, whatever the bytes, and the last one dated",
    with.present == true and with.entries == 2 and with.last == "2026-09-12", json.encode(with))
  r = T.kuu({ "capabilities" }, { cwd = work })
  check("the text form says so, and closes on the conduct page then pitfalls",
    contains(r.out, "kuu-eval.md holds 2 entries, the last dated 2026-09-12")
      and contains(r.out, "Read kuu docs agent first") and contains(r.out, "Then kuu docs pitfalls"), r.out)

  -- What it says when it cannot say much.
  fs.write(work .. "/manifest.lua", 'global none\nglobal <const> error\nerror("nope")\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local broken = json.decode(r.out).result
  check("a manifest.lua that does not load costs the task list and nothing else",
    r.code == 0 and #broken.project.tasks == 0 and broken.project.note ~= nil
      and #broken.project.modules == 2 and #broken.modules > 20,
    T.describe(r))
  fs.write(work .. "/manifest.lua", 'error("bad \\233")\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local invalid = json.decode(r.out)
  check("a non-UTF-8 manifest error preserves the JSON descriptor and module inventory",
    r.code == 0 and invalid and invalid.ok == true and contains(invalid.result.project.note, "bad \u{FFFD}")
      and #invalid.result.modules > 20 and #invalid.result.project.modules == 2, T.describe(r))
  fs.write(work .. "/manifest.lua", 'local task = require "task"\n'
    .. 'task "text" {desc="caf\\233",run=function() end}\n'
    .. 'task.tool "bytes" {exe="x.exe",args={["--\\233"]="flag",["--\\232"]="path",["--�"]="string"}}\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local invalid_keys = json.decode(r.out)
  local tool = invalid_keys and invalid_keys.result.project.tools[1]
  local tool_args = tool and tool.args
  check("JSON discovery repairs descriptions and retains colliding invalid UTF-8 argument names",
    r.code == 0 and invalid_keys and invalid_keys.result.project.tasks[1].desc == "caf\u{FFFD}"
      and tool_args and tool_args["--\u{FFFD}"] == "string" and tool_args["--\u{FFFD} [2]"] == "path" and tool_args["--\u{FFFD} [3]"] == "flag",
    T.describe(r))

  local away = fs.tempdir { prefix = "kuu-capabilities-" }
  if away then
    r = T.kuu({ "capabilities" }, { cwd = away })
    check("outside a project it reports the runtime and says there is no project",
      r.code == 0 and contains(r.out, "no project here") and contains(r.out, "modules"),
      T.describe(r))
    fs.remove(away, { recursive = true })
  end

  -- The text form, which is what an agent reads when it does not ask for JSON.
  r = T.kuu({ "capabilities" }, { cwd = work })
  check("the text form names the runtime, the palette and the project",
    r.code == 0 and contains(r.out, "kuu " .. rt.version)
      and contains(r.out, "require \"NAME\"") and contains(r.out, "lib.util"),
    T.describe(r))
  check("it wraps rather than running off the line",
    (r.out:match("^[^\n]*") or ""):len() < 100 and not contains(r.out, "\t"), r.out)

  r = T.kuu({ "capabilities", "--help" }, { cwd = work })
  check("--help exits 0", r.code == 0 and contains(r.out, "usage: kuu capabilities"), T.describe(r))
  r = T.kuu({ "capabilities", "--nope" }, { cwd = work })
  check("an unknown option exits 2", r.code == 2 and contains(r.err, "CLI usage"), T.describe(r))

  fs.write(work .. "/manifest.lua", 'global none\nglobal <const> require\nlocal scan=require "_scan_native"\n'
    .. 'scan.collect=function(root) return {root=root,paths={},files={},links={},skipped={},enumerated=1,pruned=0,errors={{path=root.."/held",win32=32,reason="sharing violation"}}} end\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local incomplete = json.decode(r.out)
  local inventory = incomplete and incomplete.result.project
  check("capabilities JSON exposes incomplete module enumeration with its filesystem diagnostic",
    r.code == 0 and inventory and not inventory.modules_complete and #inventory.module_errors == 1
      and inventory.module_errors[1].win32 == 32, T.describe(r))
  r = T.kuu({ "capabilities" }, { cwd = work })
  check("capabilities text names the incomplete module inventory",
    r.code == 0 and contains(r.out, "module inventory incomplete") and contains(r.out, "sharing violation"), T.describe(r))

  fs.remove(work, { recursive = true })
end
