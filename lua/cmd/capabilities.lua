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
-- does not bound is counted and not named. Installed executables that a task
-- never declares are not inferred; project modules follow inspection scope.
global none
global <const> require, ipairs, pairs, pcall, tostring, type, table, string, io, os

local timing = require "_timings"
local began, times = timing.clock(), {}
local rt = require "rt"
local cli = require "cli"
local fs = require "fs"
local json = require "json"
local clean = require "_jsonsafe"
local project = require "project"
local task = require "task"
local check = require "check"
local policy = require "_scan_policy"
local scan = require "_scan"

-- What to read and do next, in order, said the same way in both forms:
-- the descriptor is an agent's project-discovery command, so it carries
-- the conduct as well as the inventory.
local NEXT = {
  "kuu docs agent: what is expected of an agent here, and how to report back; read it first",
  "kuu docs upgrading-from-0.11: migrating a project from signed 0.11; read before running project tasks",
  "kuu docs pitfalls: where kuu differs from the Lua you know; read it once",
  "kuu docs index: the map of the manual; kuu docs PAGE prints a page, kuu docs search TEXT finds lines",
  "if something cannot be done from here, build a tool for it and call it through the door: kuu docs tools",
}

local spec = {
  { "--json", type = "flag", help = "machine-readable descriptor" },
  { "--timings", type = "flag", help = "print measured command phases on stderr" },
}
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

-- Absent when there is no manifest.lua at or above here. Without a project there
-- is no root to read modules under, and walking whatever directory kuu
-- happens to have been started in is not the same question.
local here = nil
local root, file = project.find()
if root then
  here = { root = root, file = file, tasks = json.array {}, tools = json.array {}, modules = json.array {}, files = 0,
           notes = json.array {} }
  -- What the text form says beside the inventory is carried here too.
  if file == project.LEGACY then here.notes[#here.notes + 1] = project.LEGACY_NOTE end

  -- Tasks are declared by running manifest.lua, which is project code; `kuu
  -- list` and `kuu run` already do that. A failure costs the task list and
  -- nothing else, so it is reported here rather than raised.
  local loaded, why = false, nil
  local context, config_error = policy.load(root)
  if not context then
    here.config_error = { domain = config_error.domain, code = config_error.code, message = config_error.message }
    why = config_error
  else
    here.scope = scan.describe(context)
    local entered, e2 = project.enter(root)
    if not entered then why = e2 else
      loaded, why = project.load_tasks(root)
    end
  end
  if loaded then
    for _, t in ipairs(task.all()) do
      if not t.hidden then
        here.tasks[#here.tasks + 1] = { name = t.name, desc = t.desc }
      end
    end
    here.default = task.default_task()
    -- The tools the manifest declares, from the registry the declaration
    -- filled: the executed reading, which the suite holds equal to the one
    -- check takes from the text.
    for _, t in ipairs(task.tools()) do
      local reach = {}
      for k, list in pairs(t.reach) do reach[k] = json.array(list) end
      here.tools[#here.tools + 1] = { name = t.name, exe = t.exe, args = t.args, output = t.output,
        emits = json.array(t.emits), timeout = t.timeout, reach = reach }
    end
  else
    here.note = config_error and ("project scan configuration is invalid: " .. tostring(why))
      or (file .. " did not load: " .. tostring(why))
  end

  -- The door's memory: the last crossings, the chain held to itself --
  -- every record hashes the line before it, and this is where an edited
  -- line is found. No workspace-change counts are inferred from history.
  local ledger = require "_ledger"
  times.setup = timing.clock() - began
  here.ledger = { last = json.array {}, records = 0, intact = true }
  local recent, tail_error = timing.measure(times, "ledger_tail", ledger.tail, root, 5)
  for _, record in ipairs(recent or {}) do
    here.ledger.last[#here.ledger.last + 1] = { at = record.at, kind = record.kind, name = record.name,
      status = record.status, seconds = record.seconds }
  end
  local sound, detail = timing.measure(times, "ledger_verification", ledger.verify, root)
  if sound then here.ledger.records = detail
  else
    here.ledger.intact, here.ledger.records = false, nil
    if detail.domain == "LEDGER" then here.ledger.broken = detail.message
    else here.ledger.unreadable = tostring(detail) end
  end
  if tail_error then
    here.ledger.intact, here.ledger.unreadable = false, tostring(tail_error)
  end

  -- What agents wrote back: kuu-eval.md at the root, one `## DATE ...`
  -- heading per entry, appended and never rewritten (kuu docs agent).
  -- Counted, not read: the door shows that someone has written.
  -- The shape counted is `## YYYY-MM-DD ...` at the start of a line
  -- outside fenced code, since a difficulty pastes output that may hold
  -- such a line; the bytes are read as they are, so one byte that is not
  -- UTF-8 does not erase the count.
  here.eval = { present = false, entries = 0 }
  local written = fs.read(fs.join(root, "kuu-eval.md"))
  if written then
    here.eval.present = true
    local fenced = false
    for line in (written .. "\n"):gmatch("([^\n]*)\n") do
      if line:match("^```") then fenced = not fenced
      elseif not fenced then
        local date = line:match("^## (%d%d%d%d%-%d%d%-%d%d)")
        if date then
          here.eval.entries = here.eval.entries + 1
          here.eval.last = date
        end
      end
    end
  end

  local found
  if context then found = timing.measure(times, "inventory", check.modules, root, context)
  else found = { root = root, files = 0, modules = {}, complete = false,
    errors = { { path = fs.join(root, policy.FILE), message = tostring(config_error),
      domain = config_error.domain, code = config_error.code } } }
  end
  here.files = found.files
  here.scan = found.scan
  here.modules_complete, here.module_errors = found.complete, json.array(found.errors)
  for _, module in ipairs(found.modules) do
    here.modules[#here.modules + 1] = { name = module.name,
      path = module.path:sub(#found.root + 2), names = json.array(module.exports) }
  end
end
if times.setup == nil then times.setup = timing.clock() - began end

-- ---- saying it -----------------------------------------------------------

if opts.json then
  local envelope = {
    ok = true,
    result = {
      kuu = { version = rt.version, lua = rt.lua, exe = rt.exe,
        verbs = json.array(rt.verbs()), pages = json.array(pages) },
      next = json.array(NEXT),
      modules = modules,
      errors = domains,
      sets = sets,
      project = here,
      timings = times,
    },
  }
  timing.finish(times, began)
  io.write(json.encode(clean(envelope)), "\n")
  if opts.timings then timing.write("capabilities", times) end
  os.exit(0)
end

-- Buffer the human descriptor so total ends at completed report assembly,
-- before final output/flush, just as it does before JSON serialization.
local output, human_io = {}, io
local io = { write = function(...) output[#output + 1] = table.concat { ... } end }
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
  io.write(string.format("  %-" .. (LABEL - 2) .. "s%-38s%s\n", label, value, hint))
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
  io.write("\nno project here: kuu found no manifest.lua in this directory or above,\n",
    "so there are no tasks to run and no root to read project modules under.\n")
else
  io.write("\nproject ", here.root, "\n")
  if here.file == project.LEGACY then
    io.write("  ", project.LEGACY_NOTE, "\n")
  end
  if here.note then
    io.write("  ", here.note, "\n")
  else
    local names = {}
    for _, t in ipairs(here.tasks) do
      names[#names + 1] = t.name == here.default and (t.name .. "*") or t.name
    end
    listing(LABEL, 2, "tasks", names)
    if #task.all() == 0 then
      io.write(string.rep(" ", LABEL), here.file, " declares no task; declare one with task \"name\" { ... } (kuu docs task)\n")
    elseif #names == 0 then
      io.write(string.rep(" ", LABEL), here.file, " declares only hidden tasks; kuu list --json shows them\n")
    else
      io.write(string.rep(" ", LABEL),
        here.default and "* the default. kuu run TASK; kuu list describes them\n"
          or "kuu run TASK; kuu list describes them\n")
    end
  end
  if #here.tools > 0 then
    local names = {}
    for _, t in ipairs(here.tools) do names[#names + 1] = t.name .. " (" .. t.output .. ")" end
    listing(LABEL, 2, "tools", names)
    io.write(string.rep(" ", LABEL), "declared in the manifest; task.exec { tool = NAME } runs one\n")
  end
  if #here.ledger.last > 0 then
    local shown = {}
    for _, c in ipairs(here.ledger.last) do
      shown[#shown + 1] = string.format("%s %s %s", c.kind, c.name, tostring(c.status))
    end
    listing(LABEL, 2, "ledger", shown)
    io.write(string.rep(" ", LABEL), "the last crossings, oldest first; .kuu/ledger holds ninety days of them\n")
    if here.ledger.intact then
      io.write(string.rep(" ", LABEL), string.format("%d records, each hashing the one before it; the chain is intact\n", here.ledger.records))
    end
  elseif here.ledger.intact then
    io.write(string.format("  %-" .. (LABEL - 2) .. "snothing has crossed the door yet; kuu run writes .kuu/ledger\n", "ledger"))
  else
    io.write(string.format("  %-" .. (LABEL - 2) .. "sno readable recent crossings\n", "ledger"))
  end
  if not here.ledger.intact then
    if here.ledger.unreadable then
      io.write(string.rep(" ", LABEL), "the ledger could not be completely read: ", here.ledger.unreadable, "\n")
    end
    if here.ledger.broken then
      io.write(string.rep(" ", LABEL), "the chain is broken: ", here.ledger.broken, "\n")
    end
  end
  if here.eval.entries > 0 then
    io.write(string.format("  %-" .. (LABEL - 2) .. "skuu-eval.md holds %d entr%s, the last dated %s\n", "eval",
      here.eval.entries, here.eval.entries == 1 and "y" or "ies", here.eval.last))
  elseif here.eval.present then
    io.write(string.format("  %-" .. (LABEL - 2) .. "skuu-eval.md is there but holds no entry headed ## YYYY-MM-DD; kuu docs agent shows the form\n", "eval"))
  else
    io.write(string.format("  %-" .. (LABEL - 2) .. "sno kuu-eval.md yet; kuu docs agent says what to write there\n", "eval"))
  end
  io.write(string.format("  %-" .. (LABEL - 2) .. "s%d of the %d .lua files below the root bound their exports\n",
    "modules", #here.modules, here.files))
  local column = column_for(here.modules, 4, LABEL)
  for _, module in ipairs(here.modules) do listing(column, 4, module.name, module.names) end
  if not here.modules_complete then
    io.write("    module inventory incomplete:\n")
    for _, e in ipairs(here.module_errors) do io.write("      ", e.path, ": ", e.message, "\n") end
  end
end

io.write("\nInstalled executables are listed only when declared as tools; project modules\n",
  "follow the inspection scope (kuu docs scan).\n",
  "Everything that runs in a project runs through kuu.exe; if something cannot\n",
  "be done from here, build a tool for it and call it through the door (kuu docs tools).\n",
  "Read kuu docs agent first: what is expected of you here, and how to report back.\n",
  "From signed 0.11: read kuu docs upgrading-from-0.11 before running project tasks.\n",
  "Then kuu docs pitfalls, once; it is where kuu differs from the Lua you know.\n")
local text = table.concat(output)
timing.finish(times, began)
human_io.write(text)
if opts.timings then timing.write("capabilities", times) end
