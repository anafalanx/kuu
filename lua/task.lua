-- task.lua -- a repository's tasks, declared once in its tasks.lua.
--
--   local task = require "task"
--   task "build" {
--     desc = "compile and stage build/app.exe",
--     deps = { "gen" },                                              -- run first, each once
--     args = { { "--release", type = "flag", help = "optimise" } },  -- a cli spec
--     run = function(opts)
--       return task.exec { "gcc", "-O2", "main.c", "-o", "build/app.exe" }
--     end,
--   }
--   task.default "build"
--
-- `kuu run NAME [args]` runs NAME after its dependencies in dependency order;
-- `kuu list` shows them.  A task fails by raising or by returning nil, err.
-- The runner exits with the child's code when `task.exec` failed, 2 for a
-- usage mistake, 1 for any other failure, 0 when every task returned.  The
-- registry is the module itself, so tasks.lua and the runner share it.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, error, setmetatable, pcall, select

local err = require "err"
local proc = require "proc"

local registry = { order = {}, byname = {}, default_name = nil }

local ATTRIBUTES = { desc = true, deps = true, args = true, run = true, hidden = true }

local function bad(message)
  error(err.new("TASK", "badvalue", message), 3)
end

local function declare(name, spec)
  if type(name) ~= "string" or not name:match("^[%w][%w%._%-]*$") then
    bad("a task name must be a plain word, got " .. tostring(name))
  end
  local where = "task '" .. name .. "'"
  if type(spec) ~= "table" then bad(where .. " needs a table with a run function") end
  for k in pairs(spec) do
    if not ATTRIBUTES[k] then bad(where .. ": unknown attribute '" .. tostring(k) .. "'") end
  end
  if type(spec.run) ~= "function" then bad(where .. " needs a run function") end
  if spec.desc ~= nil and type(spec.desc) ~= "string" then bad(where .. ": desc must be a string") end
  if spec.deps ~= nil then
    if type(spec.deps) ~= "table" then bad(where .. ": deps must be an array of task names") end
    for _, dep in ipairs(spec.deps) do
      if type(dep) ~= "string" then bad(where .. ": deps must be task names") end
    end
  end
  if spec.hidden ~= nil and type(spec.hidden) ~= "boolean" then bad(where .. ": hidden must be a boolean") end
  if spec.args ~= nil then
    -- normalise the cli spec now, so a broken declaration cannot lie dormant
    local ok, e = pcall(require("cli").usage, spec.args, name)
    if not ok then bad(where .. ": " .. (err.is(e) and e.message or tostring(e))) end
  end
  if registry.byname[name] ~= nil then bad(where .. " is declared twice") end
  local entry = {
    name = name,
    desc = spec.desc or "",
    deps = spec.deps or {},
    args = spec.args,
    run = spec.run,
    hidden = spec.hidden == true,
  }
  registry.byname[name] = entry
  registry.order[#registry.order + 1] = entry
  return entry
end

local task = setmetatable({}, {
  __call = function(_, name, spec)
    if spec ~= nil then return declare(name, spec) end
    return function(spec2) return declare(name, spec2) end -- task "name" { ... }
  end,
})

function task.default(name)
  if type(name) ~= "string" then bad("the default must be a task name") end
  registry.default_name = name
end

function task.get(name) return registry.byname[name] end
function task.all() return registry.order end
function task.default_task() return registry.default_name end

-- task.plan(name) -> the tasks to run, in order, each once | nil, err (TASK unknown | cycle)
function task.plan(name)
  local order, state = {}, {}
  local function visit(n, chain)
    local entry = registry.byname[n]
    if entry == nil then
      local needed = chain ~= "" and (" (needed by " .. chain .. ")") or ""
      return nil, err.new("TASK", "unknown", "no task '" .. tostring(n) .. "'" .. needed)
    end
    if state[n] == "done" then return true end
    if state[n] == "active" then
      return nil, err.new("TASK", "cycle", "task '" .. n .. "' depends on itself through " .. chain)
    end
    state[n] = "active"
    for _, dep in ipairs(entry.deps) do
      local ok, e = visit(dep, chain == "" and n or (chain .. " -> " .. n))
      if not ok then return nil, e end
    end
    state[n] = "done"
    order[#order + 1] = entry
    return true
  end
  local ok, e = visit(name, "")
  if not ok then return nil, e end
  return order
end

-- task.arguments(entry [, args [, program_name]]) -> opts | nil, err
-- The task's arguments parsed against its spec; `--help` and every mistake
-- are CLI usage.  A task without a spec accepts no arguments.  The runner
-- calls this for every task in a plan before anything runs.
function task.arguments(entry, args, program_name)
  args = args or {}
  program_name = program_name or ("kuu run " .. entry.name)
  if entry.args == nil then
    if #args > 0 then return nil, err.new("CLI", "usage", "task '" .. entry.name .. "' takes no arguments") end
    return {}
  end
  local cli = require "cli"
  local parsed, e = cli.parse(args, entry.args, program_name)
  if not parsed then return nil, e end
  if parsed.help then return nil, err.new("CLI", "usage", cli.usage(entry.args, program_name)) end
  return parsed
end

-- task.execute(entry [, opts]) -> true | nil, err
-- Calls run with parsed arguments and normalises the outcome.  Dependencies
-- are the caller's business (see task.plan).
function task.execute(entry, opts)
  local ok, result, e = pcall(entry.run, opts or {})
  if not ok then
    if err.is(result) then return nil, result end
    return nil, err.new("TASK", "failed", tostring(result))
  end
  if result == nil and e ~= nil then
    if err.is(e) then return nil, e end
    return nil, err.new("TASK", "failed", tostring(e))
  end
  return true
end

-- task.relay: nil, or a file such as io.stderr.  When set, task.exec captures
-- its child's output and writes it there when the child finishes, instead of
-- letting the child write to kuu's own console.  `kuu run --json` sets it so
-- standard output carries only the envelope.
task.relay = nil

-- task.exec { "gcc", ..., cwd = , env = , timeout = } -> true | nil, err
-- Runs a child on kuu's own console, so its output streams through.  A
-- non-zero exit is TASK exit with `exit` set to the code, which `kuu run`
-- passes through as its own exit code.
function task.exec(spec)
  if type(spec) ~= "table" or type(spec[1]) ~= "string" then
    error(err.new("TASK", "badvalue", "task.exec needs an argv table"), 2)
  end
  local r, e
  if task.relay ~= nil then
    r, e = proc.run(spec)
    if r ~= nil then
      task.relay:write(r.out)
      task.relay:write(r.err)
    end
  else
    spec.inherit = true
    r, e = proc.run(spec)
  end
  if not r then return nil, e end
  if r.status ~= "exit" then
    return nil, err.new("TASK", "failed", spec[1] .. ": " .. r.status)
  end
  if r.code ~= 0 then
    return nil, err.new("TASK", "exit", spec[1] .. " exited with code " .. r.code, { exit = r.code })
  end
  return true
end

return task
