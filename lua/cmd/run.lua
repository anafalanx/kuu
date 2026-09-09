-- run.lua -- `kuu run [--json] [TASK [arg ...]]`: a task from the nearest tasks.lua.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, io, os, select

local rt = require "rt"
local project = require "project"
local task = require "task"
local sched = require "sched"
local json = require "json"
local err = require "err"

local USAGE = "usage: kuu run [--json] [TASK [arg ...]]\n  runs TASK, or the default task, after its dependencies; kuu list shows them\n"

local want_json = false
local i = 1
while rt.args[i] ~= nil and rt.args[i]:sub(1, 2) == "--" do
  local a = rt.args[i]
  i = i + 1
  if a == "--json" then want_json = true
  elseif a == "--help" then io.write(USAGE) os.exit(0)
  elseif a == "--" then break
  else io.stderr:write("kuu: TASK usage: unknown option '", a, "'\n", USAGE) os.exit(2) end
end
local name = rt.args[i]
local args = {}
for k = i + 1, #rt.args do args[#args + 1] = rt.args[k] end

local ran = json.array {}

local function exit_code_for(e)
  if type(e.exit) == "number" then return e.exit end
  if err.is(e, "CLI", "usage") or err.is(e, "TASK") then return 2 end
  return 1
end

local function finish(ok, e, extra)
  if want_json then
    local envelope = { ok = ok, result = { tasks = ran } }
    if extra ~= nil then for k, v in pairs(extra) do envelope.result[k] = v end end
    if not ok then envelope.error = { domain = e.domain, code = e.code, message = e.message, exit = e.exit } end
    io.write(json.encode(envelope), "\n")
  elseif not ok then
    io.stderr:write("kuu: ", tostring(e), "\n")
  end
  os.exit(ok and 0 or exit_code_for(e))
end

local root, e = project.find()
if not root then finish(false, e) end
local entered, e2 = project.enter(root)
if not entered then finish(false, e2) end
local loaded, e3 = project.load_tasks(root)
if not loaded then finish(false, e3) end

if name == nil then
  name = task.default_task()
  if name == nil then
    local lines = { "no task named and tasks.lua declares no default; the tasks in " .. root .. ":" }
    for _, t in ipairs(task.all()) do
      if not t.hidden then lines[#lines + 1] = string.format("  %-20s %s", t.name, t.desc) end
    end
    finish(false, err.new("TASK", "usage", table.concat(lines, "\n")), { root = root })
  end
end

local plan, e4 = task.plan(name)
if not plan then finish(false, e4, { root = root }) end
for _, entry in ipairs(plan) do
  local started = sched.clock()
  local ok, e5 = task.execute(entry, entry.name == name and args or {}, "kuu run " .. entry.name)
  local elapsed = sched.clock() - started
  ran[#ran + 1] = { name = entry.name, seconds = elapsed, ok = ok == true }
  if not ok then
    if not want_json then
      io.stderr:write(string.format("kuu: %s failed after %.1fs\n", entry.name, elapsed))
    end
    -- a failed task's own error is not a usage mistake of the runner: only
    -- argument errors exit 2, a child's code passes through, the rest is 1
    if not (type(e5.exit) == "number" or err.is(e5, "CLI", "usage")) then e5.exit = 1 end
    finish(false, e5, { root = root, task = name })
  end
  if not want_json then io.stderr:write(string.format("kuu: %s %.1fs\n", entry.name, elapsed)) end
end
finish(true, nil, { root = root, task = name })
