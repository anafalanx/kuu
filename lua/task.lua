-- task.lua -- a repository's tasks, declared once in its manifest.lua.
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
-- registry is the module itself, so manifest.lua and the runner share it.
global none
global <const> require, ipairs, pairs, tostring, type, error, setmetatable,
               pcall, table

local err = require "err"
local nearest = require "_nearest"
local proc = require "proc"
local sched = require "sched"
local fs = require "fs"
local rt = require "rt"

local registry = { order = {}, byname = {}, default_name = nil, tools = { order = {}, byname = {} } }
local default_timeout

local ATTRIBUTES = { desc = true, deps = true, args = true, run = true, hidden = true }
local TOOL_ATTRIBUTES = { exe = true, args = true, output = true, emits = true, timeout = true, reach = true }
local OUTPUTS = { ndjson = true, json = true, lines = true, none = true }
local ARG_TYPES = { flag = true, string = true, path = true, int = true, number = true, duration = true, size = true }
local REACH = { read = true, write = true, net = true }

local function bad(message)
  error(err.new("TASK", "badvalue", message), 3)
end

local function unknown(message)
  error(err.new("TASK", "usage", message), 3)
end

local function declare(name, spec)
  if type(name) ~= "string" or not name:match("^[%w][%w%._%-]*$") then
    bad("a task name must be a plain word, got " .. tostring(name))
  end
  local where = "task '" .. name .. "'"
  if type(spec) ~= "table" then bad(where .. " needs a task specification table") end
  for k in pairs(spec) do
    if not ATTRIBUTES[k] then unknown(where .. ": unknown attribute '" .. tostring(k) .. "'") end
  end
  if spec.run ~= nil and type(spec.run) ~= "function" then bad(where .. ": run must be a function") end
  if spec.desc ~= nil and type(spec.desc) ~= "string" then bad(where .. ": desc must be a string") end
  if spec.deps ~= nil then
    if type(spec.deps) ~= "table" then bad(where .. ": deps must be an array of task names") end
    for _, dep in ipairs(spec.deps) do
      if type(dep) ~= "string" then bad(where .. ": deps must be task names") end
    end
  end
  if spec.run == nil and (spec.deps == nil or #spec.deps == 0) then
    bad(where .. " needs a run function or non-empty deps")
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

-- A tool the project built or fetched into its own root, declared beside the
-- tasks that call it: where it is, the arguments it takes, the shape it
-- emits.  The declaration is read by `check` from the manifest's text and
-- by `capabilities` from this registry, and resolved by task.exec { tool =
-- "name" }.  It gates nothing at run time; `reach` is recorded, not
-- enforced, since whether a tool can be confined is the tool's own
-- technology's business.
local function declare_tool(name, spec)
  if type(name) ~= "string" or not name:match("^[%w][%w%._%-]*$") then
    bad("a tool name must be a plain word, got " .. tostring(name))
  end
  local where = "tool '" .. name .. "'"
  if type(spec) ~= "table" then bad(where .. " needs a declaration table") end
  for k in pairs(spec) do
    if not TOOL_ATTRIBUTES[k] then unknown(where .. ": unknown attribute '" .. tostring(k) .. "'") end
  end
  if type(spec.exe) ~= "string" or spec.exe == "" then
    bad(where .. ": exe must be the program's path, relative to the project root")
  end
  -- Refused now, in the declaration's own domain, rather than at the call
  -- from fs: a path the resolver will not take is a mistake in the manifest.
  local resolvable, why = pcall(fs.absolute, fs.join(rt.root(), spec.exe))
  if not resolvable then bad(where .. ": exe " .. (err.is(why) and why.message or tostring(why))) end
  local function list_of(value, what)
    if type(value) ~= "table" then bad(where .. ": " .. what .. " must be an array of strings") end
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    if count ~= #value then bad(where .. ": " .. what .. " must be an array, not a table of names") end
    local out = {}
    for i, item in ipairs(value) do
      if type(item) ~= "string" then bad(where .. ": " .. what .. " must be strings") end
      out[i] = item
    end
    return out
  end
  -- `args` absent: the arguments are not described and check does not judge
  -- them; `args = {}`: the tool takes none.
  local args = spec.args ~= nil and {} or nil
  if spec.args ~= nil then
    if type(spec.args) ~= "table" then bad(where .. ": args must be a table of argument name = type") end
    for arg, kind in pairs(spec.args) do
      if type(arg) ~= "string" then bad(where .. ": argument names must be strings") end
      if not ARG_TYPES[kind] then
        bad(where .. ": argument '" .. arg .. "' has type " .. tostring(kind) .. "; the types are flag, string, path, int, number, duration, size")
      end
      args[arg] = kind
    end
  end
  local output = spec.output == nil and "none" or spec.output
  if not OUTPUTS[output] then bad(where .. ": output is ndjson, json, lines, or none, not " .. tostring(spec.output)) end
  local emits = spec.emits ~= nil and list_of(spec.emits, "emits") or {}
  if spec.timeout ~= nil and require("cli").duration(spec.timeout) == nil then
    bad(where .. ": timeout must be a duration such as 5m, or seconds")
  end
  local reach = {}
  if spec.reach ~= nil then
    if type(spec.reach) ~= "table" then bad(where .. ": reach must be a table of read, write and net lists") end
    for k, list in pairs(spec.reach) do
      if not REACH[k] then unknown(where .. ": reach: unknown option '" .. tostring(k) .. "'") end
      reach[k] = list_of(list, "reach." .. tostring(k))
    end
  end
  if registry.tools.byname[name] ~= nil then bad(where .. " is declared twice") end
  local entry = { name = name, exe = spec.exe, args = args, output = output, emits = emits,
                  timeout = spec.timeout, reach = reach }
  registry.tools.byname[name] = entry
  registry.tools.order[#registry.tools.order + 1] = entry
  return entry
end

local task = setmetatable({}, {
  __call = function(_, name, spec)
    if spec ~= nil then return declare(name, spec) end
    return function(spec2) return declare(name, spec2) end -- task "name" { ... }
  end,
})

-- task.tool "name" { exe = , args = , output = , emits = , timeout = , reach = }
function task.tool(name, spec)
  if spec ~= nil then return declare_tool(name, spec) end
  return function(spec2) return declare_tool(name, spec2) end
end
function task.tools() return registry.tools.order end
function task.tool_get(name)
  if type(name) ~= "string" then bad("a tool name must be a string, got " .. type(name)) end
  return registry.tools.byname[name]
end

function task.default(name)
  if type(name) ~= "string" then bad("the default must be a task name") end
  registry.default_name = name
end

-- task.defaults { timeout = "10m" }: replace the defaults for task.exec.
-- Validate the whole declaration before changing it; {} clears the default.
function task.defaults(options)
  if type(options) ~= "table" then bad("defaults needs a table") end
  for name in pairs(options) do
    if name ~= "timeout" then unknown("defaults: unknown option '" .. tostring(name) .. "'") end
  end
  local timeout = options.timeout
  if timeout ~= nil and require("cli").duration(timeout) == nil then
    bad("defaults: timeout must be a duration such as 10m, or seconds")
  end
  default_timeout = timeout
end

function task.get(name)
  if type(name) ~= "string" then bad("a task name must be a string, got " .. type(name)) end
  return registry.byname[name]
end
function task.all() return registry.order end
function task.default_task() return registry.default_name end

-- task.plan(name) -> the tasks to run, in order, each once | nil, err (TASK unknown | cycle)
function task.plan(name)
  if type(name) ~= "string" then bad("a task name must be a string, got " .. type(name)) end
  local order, state = {}, {}
  local function visit(n, chain)
    local entry = registry.byname[n]
    if entry == nil then
      if chain ~= "" then
        return nil, err.new("TASK", "unknown", "no task '" .. tostring(n) .. "' (needed by " .. chain .. ")")
      end
      -- The name the command line gave: the nearest declared one is
      -- offered, and the list is named, so the next step is on the line.
      local suggestion = nearest(tostring(n), registry.byname)
      local hint = suggestion and ("; did you mean '" .. suggestion .. "'? kuu list shows the tasks") or "; kuu list shows the tasks"
      return nil, err.new("TASK", "unknown", "no task '" .. tostring(n) .. "'" .. hint)
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
  local cli = require "cli"
  if entry.args == nil then
    -- A task with no arguments still answers --help, with the usage that says so.
    if #args == 1 and args[1] == "--help" then
      return nil, err.new("CLI", "usage", cli.usage({}, program_name), { help = true })
    end
    if #args > 0 then return nil, err.new("CLI", "usage", "task '" .. entry.name .. "' takes no arguments") end
    return {}
  end
  local parsed, e = cli.parse(args, entry.args, program_name)
  if not parsed then return nil, e end
  -- --help is not a mistake: the usage comes back as the message, with
  -- `help` set, so the runner prints it and exits 0 like every other --help.
  if parsed.help then return nil, err.new("CLI", "usage", cli.usage(entry.args, program_name), { help = true }) end
  return parsed
end

-- task.execute(entry [, opts]) -> true | nil, err
-- Calls run with parsed arguments and normalises the outcome.  Dependencies
-- are the caller's business (see task.plan).
function task.execute(entry, opts)
  if entry.run == nil then return true end -- dependency-only aggregate
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

-- task.relay: nil, or a file such as io.stderr.  When set, task.exec runs its
-- child with piped streams and copies whatever arrives to the relay as it
-- arrives, whatever `inherit` the caller asked for.  `kuu run --json` sets it
-- so standard output carries only the envelope.
task.relay = nil

-- task.observer: nil, or a function given one record per crossing the door
-- sees -- a child started, a child finished -- with `event`, `state`, `pid`,
-- `argv`, `tool` and `cwd`, and for a finish `status`, `code`, `seconds`,
-- `started` (the clock at launch) and, on the relay path, `bytes`.  `kuu
-- run` sets it: the relay path reports both events, the console path the
-- finish only, since a child on kuu's own console starts and ends in one
-- call.  A child a task runs through proc.run itself is the program's own
-- and is not observed.
task.observer = nil

local function observe(record)
  if task.observer ~= nil then task.observer(record) end
end

-- Two small tasks pump the child's streams to the relay while the child runs,
-- so nothing waits for it to finish and nothing is capped: maxout is only the
-- point at which the child is held back until the relay has caught up.
local function relay_exec(spec, relay, tool)
  spec.inherit = nil
  spec.stream = true
  local began = sched.clock()
  local c <close>, e = proc.start(spec)
  if not c then return nil, e end
  local argv = {}
  for i, item in ipairs(spec) do argv[i] = item end
  observe { event = "child", state = "started", pid = c.pid, argv = argv, tool = tool, cwd = spec.cwd }
  local bytes = { out = 0, err = 0 }
  local function pump(read, which)
    while true do
      local chunk = read(c, "some")
      if chunk == nil then return end
      bytes[which] = bytes[which] + #chunk
      relay:write(chunk)
    end
  end
  local out_pump = sched.spawn(function() pump(c.read, "out") end)
  local err_pump = sched.spawn(function() pump(c.read_err, "err") end)
  local r, e2 = c:wait()
  out_pump:join()
  err_pump:join()
  observe { event = "child", state = "finished", pid = c.pid, argv = argv, tool = tool, cwd = spec.cwd,
            status = r and r.status or "error", code = r and r.code or nil, limit = r and r.limit or nil,
            seconds = sched.clock() - began, bytes = bytes, started = began }
  return r, e2
end

-- task.command { tool = "name", "--out", path, ... } -> a proc table
-- The door's spelling of a tool call: the declared exe first, resolved
-- against the project root, the declared timeout unless the call gives one,
-- and the default timeout after that.  What task.exec runs is this; a
-- program that wants the output rather than the console gives the table to
-- proc.run or proc.start.  A table without `tool` comes back copied, with
-- the default timeout applied.  A tool the manifest does not declare is
-- TASK unknown.
function task.command(spec)
  if type(spec) ~= "table" then error(err.new("TASK", "badvalue", "task.command needs a table"), 2) end
  local copied = {}
  for name, value in pairs(spec) do copied[name] = value end
  if copied.tool ~= nil then
    if type(copied.tool) ~= "string" then error(err.new("TASK", "badvalue", "tool must be a tool's name"), 2) end
    local decl = registry.tools.byname[copied.tool]
    if decl == nil then
      error(err.new("TASK", "unknown", "no tool '" .. copied.tool .. "' is declared in the manifest"), 2)
    end
    table.insert(copied, 1, fs.absolute(fs.join(rt.root(), decl.exe)))
    if copied.timeout == nil then copied.timeout = decl.timeout end
    copied.tool = nil
  end
  if copied.timeout == nil then copied.timeout = default_timeout end
  return copied
end

-- task.exec { "gcc", ..., cwd = , env = , timeout = } -> true | nil, err
-- task.exec { tool = "name", ... }: the same, through a declaration
-- Runs a child on kuu's own console, so its output streams through.  A
-- non-zero exit is TASK exit with `exit` set to the code, which `kuu run`
-- passes through as its own exit code.
function task.exec(spec)
  if type(spec) ~= "table" or (spec.tool == nil and type(spec[1]) ~= "string") then
    error(err.new("TASK", "badvalue", "task.exec needs an argv table, or a tool"), 2)
  end
  -- Both console and relay setup change options. Own those changes instead
  -- of changing the caller's reusable table, and let its timeout win.
  local tool = spec.tool
  spec = task.command(spec)
  local r, e
  if task.relay ~= nil then
    r, e = relay_exec(spec, task.relay, tool)
  else
    -- On the console the child has kuu's own streams, so there is nothing to
    -- count; the crossing is still observed when it ends.
    spec.inherit = true
    local began = sched.clock()
    r, e = proc.run(spec)
    if r then
      local argv = {}
      for i, item in ipairs(spec) do argv[i] = item end
      observe { event = "child", state = "finished", pid = r.pid, argv = argv, tool = tool, cwd = spec.cwd,
                status = r.status, code = r.code, limit = r.limit, seconds = sched.clock() - began, started = began }
    end
  end
  if not r then return nil, e end
  if r.status ~= "exit" then
    -- The result state rides on the error as fields, so a task branches on
    -- e.status and e.limit, never on the message.
    local reason = r.status .. (r.limit and (" (" .. r.limit .. ")") or "")
    return nil, err.new("TASK", "failed", spec[1] .. ": " .. reason, { status = r.status, limit = r.limit })
  end
  if r.code ~= 0 then
    return nil, err.new("TASK", "exit", spec[1] .. " exited with code " .. r.code, { exit = r.code })
  end
  return true
end

return task
