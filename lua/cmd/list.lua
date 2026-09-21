-- list.lua -- `kuu list [--json]`: the tasks of the nearest manifest.lua.
global none
global <const> require, ipairs, tostring, string, io, os, table

local rt = require "rt"
local cli = require "cli"
local project = require "project"
local task = require "task"
local json = require "json"
local clean = require "_jsonsafe"
local policy = require "_scan_policy"

local spec = { { "--json", type = "flag", help = "machine-readable listing" } }
local opts, e = cli.parse(rt.args, spec, "kuu list")
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu list")) os.exit(0) end

local function fail(e2)
  if opts.json then
    io.write(json.encode(clean { ok = false, error = { domain = e2.domain, code = e2.code, message = e2.message } }), "\n")
  else
    io.stderr:write("kuu: ", tostring(e2), "\n")
  end
  os.exit(2)
end

local root, found = project.find()
if not root then fail(found) end
local file = found
local context, config_error = policy.load(root)
if not context then fail(config_error) end
local entered, e4 = project.enter(root)
if not entered then fail(e4) end
local loaded, e5 = project.load_tasks(root)
if not loaded then fail(e5) end
-- What is said on standard error is also on the envelope as `notes`.
local notes = json.array {}
if e5 then notes[#notes + 1] = e5 io.stderr:write("kuu: warning: ", e5, "\n") end -- a tasks.lua read as the manifest

local tasks = json.array {}
for _, t in ipairs(task.all()) do
  local args = json.array {}
  for _, a in ipairs(t.args or {}) do
    args[#args + 1] = { name = a[1], type = a.type or "string", help = a.help or "", default = a.default,
      required = a.required == true, rest = a.rest == true, choices = a.choices }
  end
  tasks[#tasks + 1] = { name = t.name, desc = t.desc, deps = json.array(t.deps), args = args, hidden = t.hidden }
end

if opts.json then
  io.write(json.encode(clean { ok = true, result = { root = root, default = task.default_task(), tasks = tasks, notes = notes } }), "\n")
else
  io.write("tasks in ", root, ":\n")
  local shown = 0
  for _, t in ipairs(tasks) do
    if not t.hidden then
      local after = #t.deps > 0 and ("  [after " .. table.concat(t.deps, ", ") .. "]") or ""
      local star = t.name == task.default_task() and "*" or " "
      io.write(string.format(" %s%-20s %s%s\n", star, t.name, t.desc, after))
      shown = shown + 1
    end
  end
  if task.default_task() ~= nil then io.write("* the default: kuu run alone runs it\n") end
  -- A manifest that loaded and declared nothing is not an empty project by
  -- accident: the shape of a declaration is the next thing to know.  One
  -- whose tasks are all hidden declared them; the listing that shows them
  -- is named instead.
  if #tasks == 0 then
    io.write("  ", file, " declares no task; declare one with task \"name\" { ... } (kuu docs task)\n")
  elseif shown == 0 then
    io.write("  ", file, " declares only hidden tasks; kuu list --json shows them\n")
  end
end
