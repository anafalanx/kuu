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
  fs.write(work .. "/tasks.lua",
    'global none\nglobal <const> require\nlocal task = require "task"\n' ..
    'task "build" { desc = "compile it", run = function() end }\n' ..
    'task "test" { desc = "run the suite", deps = { "build" }, run = function() end }\n' ..
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

  check("it names this runtime", result.kuu.version == rt.version and result.kuu.lua == rt.lua,
    json.encode(result.kuu.version) .. " " .. json.encode(result.kuu.lua))
  check("the verbs and pages are the ones the runtime carries",
    table.concat(result.kuu.verbs, " ") == table.concat(rt.verbs(), " ")
      and #result.kuu.pages == #rt.pages(), json.encode(result.kuu.verbs))
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
  check("the project is the directory holding tasks.lua",
    here ~= nil and here.root == fs.canon(work).path, here and here.root or "absent")
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

  -- What it says when it cannot say much.
  fs.write(work .. "/tasks.lua", 'global none\nglobal <const> error\nerror("nope")\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  local broken = json.decode(r.out).result
  check("a tasks.lua that does not load costs the task list and nothing else",
    r.code == 0 and #broken.project.tasks == 0 and broken.project.note ~= nil
      and #broken.project.modules == 2 and #broken.modules > 20,
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

  fs.remove(work, { recursive = true })
end
