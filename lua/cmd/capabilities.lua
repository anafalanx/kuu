-- capabilities.lua -- `kuu capabilities [--json]`: what a program can reach
-- from here, in one place.
--
-- An agent arriving in a repository has to work out what this kuu can do and
-- what this project already has, and the ways of finding out are scattered:
-- the manual for the palette, `kuu list` for the tasks, reading the project's
-- own Lua for its modules. This is that answer, assembled once.
--
-- It reports only what kuu can know. The palette comes from the modules' own
-- export tables, so it cannot drift from the runtime; the project's modules
-- are read from their text and never executed, so one whose exports the text
-- does not bound is counted and not named. What a task installs under .tools
-- is not reported at all: kuu keeps no manifest of it, and a guess would be
-- worse than the silence.
global none
global <const> require, ipairs, pairs, pcall, tostring, type, table, string, io, os

local rt = require "rt"
local cli = require "cli"
local json = require "json"
local project = require "project"
local task = require "task"
local check = require "check"

local spec = { { "--json", type = "flag", help = "machine-readable descriptor" } }
local opts, e = cli.parse(rt.args, spec, "kuu capabilities")
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu capabilities")) os.exit(0) end

-- The authored description of the palette's interface. Absent only if the
-- payload were built without it, in which case there is no public list to
-- report and the descriptor says so rather than inventing one.
local ok_palette, palette = pcall(require, "_palette")
if not ok_palette or type(palette) ~= "table" then palette = nil end

-- ---- what this executable is ---------------------------------------------

local pages = rt.pages()
local has_page = {}
for _, page in ipairs(pages) do has_page[page] = true end

-- The names a module exports, from its own table, plus any the description
-- says may be absent: `rt.program` is nil on three of the four routes and is
-- part of the interface on all four.
local function names_of(name)
  local ok, module = pcall(require, name)
  if not ok or type(module) ~= "table" then return nil end
  local seen = {}
  for key in pairs(module) do if type(key) == "string" then seen[key] = true end end
  local described = palette and palette.modules[name]
  if described then for key in pairs(described) do seen[key] = true end end
  local names = json.array {}
  for key in pairs(seen) do names[#names + 1] = key end
  table.sort(names)
  return names
end

local modules, name_count = json.array {}, 0
for _, name in ipairs(palette and palette.public or {}) do
  local names = names_of(name)
  if names then
    name_count = name_count + #names
    modules[#modules + 1] = { name = name, page = has_page[name] and name or nil, names = names }
  end
end

local domains = json.array {}
for domain, codes in pairs(palette and palette.errors or {}) do
  local sorted = json.array {}
  for _, code in ipairs(codes) do sorted[#sorted + 1] = code end
  table.sort(sorted)
  domains[#domains + 1] = { domain = domain, codes = sorted }
end
table.sort(domains, function(a, b) return a.domain < b.domain end)

local sets = json.array {}
for set, values in pairs(palette and palette.enums or {}) do
  sets[#sets + 1] = { name = set, values = json.array(values) }
end
table.sort(sets, function(a, b) return a.name < b.name end)

-- ---- what this project is ------------------------------------------------

-- Absent when there is no tasks.lua at or above here. Without a project there
-- is no root to read modules under, and walking whatever directory kuu
-- happens to have been started in is not the same question.
local here = nil
local root = project.find()
if root then
  here = { root = root, tasks = json.array {}, modules = json.array {}, files = 0 }

  -- Tasks are declared by running tasks.lua, which is project code; `kuu
  -- list` and `kuu run` already do that. A failure costs the task list and
  -- nothing else, so it is reported here rather than raised.
  local loaded, why = false, nil
  local entered, e2 = project.enter(root)
  if not entered then why = e2 else
    loaded, why = project.load_tasks(root)
  end
  if loaded then
    for _, t in ipairs(task.all()) do
      if not t.hidden then
        here.tasks[#here.tasks + 1] = { name = t.name, desc = t.desc }
      end
    end
    here.default = task.default_task()
  else
    here.note = "tasks.lua did not load: " .. tostring(why)
  end

  local found = check.modules(root)
  here.files = found.files
  for _, module in ipairs(found.modules) do
    here.modules[#here.modules + 1] = { name = module.name,
      path = module.path:sub(#found.root + 2), names = json.array(module.exports) }
  end
end

-- ---- saying it -----------------------------------------------------------

if opts.json then
  io.write(json.encode {
    ok = true,
    result = {
      kuu = { version = rt.version, lua = rt.lua, exe = rt.exe,
        verbs = json.array(rt.verbs()), pages = json.array(pages) },
      modules = modules,
      errors = domains,
      sets = sets,
      project = here,
    },
  }, "\n")
  os.exit(0)
end

local WIDTH, LABEL = 78, 13

-- A list that wraps under its first item rather than under its label, so a
-- long one stays readable and still lines up.
local function wrap(items, room)
  local lines, line = {}, nil
  for i, item in ipairs(items) do
    local piece = i < #items and (item .. ",") or item
    if line == nil then line = piece
    elseif #line + 1 + #piece <= room then line = line .. " " .. piece
    else lines[#lines + 1] = line; line = piece end
  end
  lines[#lines + 1] = line or "none"
  return lines
end

-- The name column is as wide as the widest name in its own group: a project
-- names its modules, and `tools.report` must not shove the list it heads.
local function column_for(entries, indent, least)
  local widest = 0
  for _, entry in ipairs(entries) do
    if #entry.name > widest then widest = #entry.name end
  end
  local column = indent + widest + 2
  return column < least and least or column
end

local function listing(column, indent, label, items)
  local head = string.rep(" ", indent) .. label
  head = head .. string.rep(" ", column - #head > 0 and column - #head or 1)
  local lines = wrap(items, WIDTH - #head)
  io.write(head, lines[1], "\n")
  for i = 2, #lines do io.write(string.rep(" ", #head), lines[i], "\n") end
end

local function fact(label, value, hint)
  io.write(string.format("  %-" .. (LABEL - 2) .. "s%-34s%s\n", label, value, hint))
end

io.write("kuu ", rt.version, " (", rt.lua, ") at ", rt.exe, "\n\n")
fact("verbs", table.concat(rt.verbs(), ", "), "kuu VERB --help")
fact("manual", #pages .. " pages", "kuu docs PAGE | search TEXT")
fact("modules", #modules .. ", " .. name_count .. " names", 'require "NAME"')
if #domains > 0 then
  fact("errors", #domains .. " domains, codes in --json", "err.is(e, DOMAIN, code)")
end

if #modules > 0 then
  io.write("\nmodules\n")
  local column = column_for(modules, 2, LABEL)
  for _, module in ipairs(modules) do listing(column, 2, module.name, module.names) end
end

if here == nil then
  io.write("\nno project here: kuu found no tasks.lua in this directory or above,\n",
    "so there are no tasks to run and no root to read project modules under.\n")
else
  io.write("\nproject ", here.root, "\n")
  if here.note then
    io.write("  ", here.note, "\n")
  else
    local names = {}
    for _, t in ipairs(here.tasks) do
      names[#names + 1] = t.name == here.default and (t.name .. "*") or t.name
    end
    listing(LABEL, 2, "tasks", names)
    io.write(string.rep(" ", LABEL),
      here.default and "* the default. kuu run TASK; kuu list describes them\n"
        or "kuu run TASK; kuu list describes them\n")
  end
  io.write(string.format("  %-" .. (LABEL - 2) .. "s%d of the %d .lua files below the root bound their exports\n",
    "modules", #here.modules, here.files))
  local column = column_for(here.modules, 4, LABEL)
  for _, module in ipairs(here.modules) do listing(column, 4, module.name, module.names) end
end

io.write("\nWhatever a task installs under .tools is not listed: kuu keeps no manifest\n",
  "of it, and a guess would be worse than the silence.\n",
  "Read kuu docs pitfalls first; it is where kuu differs from the Lua you know.\n")
