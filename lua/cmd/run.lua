-- run.lua -- `kuu run [--json] [TASK [arg ...]]`: a task from the nearest manifest.lua.
global none
global <const> require, ipairs, pairs, tostring, type, pcall, string, table, io, os,
               rawset, _G

local rt = require "rt"
local project = require "project"
local task = require "task"
local sched = require "sched"
local json = require "json"
local err = require "err"
local fs = require "fs"
local clean = require "_jsonsafe"

-- What the run says on standard error beside the work -- a tasks.lua read
-- as the manifest, a .kuu/ the repository does not ignore -- is also
-- carried on the envelope as `notes`, for a reader that sees only --json.
local notes = json.array {}
local function note(text)
  notes[#notes + 1] = text
  io.stderr:write("kuu: warning: ", text, "\n")
end

local USAGE = "usage: kuu run [--json] [--dry-run] [TASK [arg ...]]\n  runs TASK, or the default task, after its dependencies; kuu list shows them\n  --dry-run shows the plan, in order, and runs nothing\n"

local want_json, dry_run = false, false
local i = 1
while rt.args[i] ~= nil and rt.args[i]:sub(1, 2) == "--" do
  local a = rt.args[i]
  i = i + 1
  if a == "--json" then want_json = true
  elseif a == "--dry-run" then dry_run = true
  elseif a == "--help" then io.write(USAGE) os.exit(0)
  elseif a == "--" then break
  else io.stderr:write("kuu: TASK usage: unknown option '", a, "'\n", USAGE) os.exit(2) end
end
local name = rt.args[i]
local args = {}
for k = i + 1, #rt.args do args[#args + 1] = rt.args[k] end

if want_json then
  -- Standard output carries the envelope and nothing else: what tasks print
  -- goes to standard error, and so does the output of task.exec children.
  io.output(io.stderr)
  rawset(_G, "print", function(...)
    local parts = table.pack(...)
    for k = 1, parts.n do parts[k] = tostring(parts[k]) end
    io.stderr:write(table.concat(parts, "\t"), "\n")
  end)
  task.relay = io.stderr
end

-- Under --json, standard output is a stream: one JSON object per line as
-- things happen -- the run, each task, each child -- and the envelope as
-- the last line, which is what the whole output used to be.  A reader that
-- takes the last line sees what it always saw; one that watches sees the
-- run as it goes, which needs each line pushed through a pipe as it is
-- written: the C runtime would otherwise hold them all until exit.
local ran = json.array {}
local current = nil
local function emit(record)
  if not want_json then return end
  record.v = 1
  io.stdout:write(json.encode(clean(record)), "\n")
  io.stdout:flush()
end

-- The door remembers what passes through it: the run, each task, each
-- child, written to .kuu/ledger under the root as it happens.  A ledger
-- that cannot be opened or written is said once on standard error and the
-- run goes on; the record is the door's, never a condition on the work.
local ledger = require "_ledger"
local book = nil
local run_began = sched.clock()
local run_at = require("time").now()
-- Whether git ignores .kuu/ under the root: a .gitignore at the root or in
-- any directory above it up to the repository's, with a line naming .kuu
-- the ways git reads them -- `.kuu`, `/.kuu/`, `**/.kuu`, `.kuu/*`, any
-- case, trailing blanks dropped, a leading one kept as git keeps it.
local function lists_kuu(text)
  text = text:gsub("^\239\187\191", "")
  for line in text:gmatch("[^\r\n]+") do
    local rule = line:gsub("%s+$", ""):lower()
    if rule:match("^/?%.kuu/?%*?$") or rule:match("^%*%*/%.kuu/?%*?$") then return true end
  end
  return false
end

local function ignored(root)
  local dir = root
  for _ = 1, 64 do
    if lists_kuu(fs.read(fs.join(dir, ".gitignore")) or "") then return true end
    if fs.exists(fs.join(dir, ".git")) then return false end
    local up = fs.dirname(dir)
    if up == nil or up == dir then return false end
    dir = up
  end
  return false
end

local function crossing(fields)
  if book == nil then return end
  local called, ok, e = pcall(ledger.record, book, clean(fields))
  if not called or not ok then
    note("the ledger was not written: " .. tostring(called and e or ok))
    book = nil
    return
  end
  -- The first crossing creates .kuu/ under the root; the one thing to do
  -- about that is said once, the first time, when the repository does not
  -- yet ignore it.
  if book.written == 1 and book.fresh and not ignored(book.root) then
    note(".kuu/ was created under " .. book.root .. " and no .gitignore up to the repository's lists it; add /.kuu/, it is the machine's (kuu docs adopting)")
  end
end
-- Installed once the plan is checked and something is about to run: a
-- child the manifest starts at its top level is not a crossing of this
-- run, and a run that runs nothing -- --dry-run, an unknown task, a wrong
-- argument -- writes nothing, so the next real run's delta still names
-- the edits it ran against.
local function open_the_door(root)
  local fresh = fs.exists(fs.join(root, ".kuu")) == false
  local opened, result = pcall(ledger.open, root)
  if opened then book = result book.fresh = fresh
  else io.stderr:write("kuu: warning: the ledger was not opened: ", tostring(result), "\n") end
  task.observer = function(record)
    record.task = current
    if record.argv then record.argv = json.array(record.argv) end
    if record.state == "finished" then
      crossing { kind = "child", name = record.tool or record.argv[1], task = current, tool = record.tool,
        argv = record.argv, cwd = record.cwd, pid = record.pid, at = run_at + (record.started - run_began),
        seconds = record.seconds, status = record.status, code = record.code, limit = record.limit, bytes = record.bytes }
    end
    record.started, record.cwd = nil, nil
    emit(record)
  end
end

local function exit_code_for(e)
  if type(e.exit) == "number" then return e.exit end
  if err.is(e, "CLI", "usage") or err.is(e, "TASK") then return 2 end
  return 1
end

local function finish(ok, e, extra)
  if book ~= nil then
    local argv = json.array {}
    for _, a in ipairs(rt.args) do argv[#argv + 1] = a end
    crossing { kind = "verb", name = "run", task = extra and extra.task or nil, argv = argv,
      at = run_at, seconds = sched.clock() - run_began, status = ok and "ok" or "failed",
      code = ok and 0 or exit_code_for(e),
      error = (not ok) and { domain = e.domain, code = e.code, message = e.message } or nil }
    -- A failed final record disables the ledger, just as an earlier one
    -- does. Keep the previous tree so the next run still sees those edits.
    if book ~= nil then
      local called, closed, e7 = pcall(ledger.close, book)
      if not called or not closed then note("the ledger's tree was not written: " .. tostring(called and e7 or closed)) end
    end
  end
  if want_json then
    local envelope = { ok = ok, result = { tasks = ran, notes = notes } }
    if extra ~= nil then for k, v in pairs(extra) do envelope.result[k] = v end end
    if not ok then envelope.error = { domain = e.domain, code = e.code, message = e.message, exit = e.exit } end
    io.stdout:write(json.encode(clean(envelope)), "\n")
    io.stdout:flush()
  elseif not ok then
    io.stderr:write("kuu: ", tostring(e), "\n")
  end
  os.exit(ok and 0 or exit_code_for(e))
end

local root, found = project.find()
if not root then finish(false, found) end
local file = found
local entered, e2 = project.enter(root)
if not entered then finish(false, e2) end
local loaded, e3 = project.load_tasks(root)
if not loaded then finish(false, e3) end
if e3 then note(e3) end -- a tasks.lua read as the manifest

local defaulted = false
if name == nil then
  name = task.default_task()
  defaulted = name ~= nil
  if name == nil then
    local lines
    local visible = {}
    for _, t in ipairs(task.all()) do
      if not t.hidden then visible[#visible + 1] = string.format("  %-20s %s", t.name, t.desc) end
    end
    if #task.all() == 0 then
      -- A manifest that loaded and declared nothing is told apart from
      -- one with no default: the next step is the declaration's shape.
      lines = { "no task named and " .. file .. " declares none; declare one with task \"name\" { ... } (kuu docs task)" }
    elseif #visible == 0 then
      lines = { "no task named and " .. file .. " declares no default; its tasks are hidden, and kuu list --json shows them" }
    else
      lines = { "no task named and " .. file .. " declares no default; the tasks in " .. root .. ":" }
      for _, line in ipairs(visible) do lines[#lines + 1] = line end
    end
    finish(false, err.new("TASK", "usage", table.concat(lines, "\n")), { root = root })
  end
end

local plan, e4 = task.plan(name)
if not plan and defaulted and err.is(e4, "TASK", "unknown") then
  -- The name came from the manifest's own task.default, not the command
  -- line: the mistake is in the file, and the message says so.
  local declared = {}
  for _, t in ipairs(task.all()) do declared[t.name] = true end
  local suggestion = require("_nearest")(name, declared)
  e4 = err.new("TASK", "unknown", file .. " names '" .. name .. "' as its default and declares no such task"
    .. (suggestion and ("; did you mean '" .. suggestion .. "'?") or ""))
end
if not plan then finish(false, e4, { root = root }) end

-- Check the selected task first, so its help remains available even when a
-- dependency requires arguments. Every dependency is still validated before
-- any task runs.
local opts_for = {}
for _, entry in ipairs(plan) do
  if entry.name == name then
    local opts, e5 = task.arguments(entry, args, "kuu run " .. entry.name)
    if not opts and e5.help then io.stdout:write(e5.message) os.exit(0) end
    if not opts then finish(false, e5, { root = root, task = name }) end
    opts_for[entry.name] = opts
  end
end
for _, entry in ipairs(plan) do
  if entry.name ~= name then
    local opts, e5 = task.arguments(entry, {}, "kuu run " .. entry.name)
    if not opts then finish(false, e5, { root = root, task = name }) end
    opts_for[entry.name] = opts
  end
end

if dry_run then
  -- the plan, checked as above, and nothing run
  if want_json then
    local steps = json.array {}
    for _, entry in ipairs(plan) do
      steps[#steps + 1] = { name = entry.name, desc = entry.desc, deps = json.array(entry.deps) }
    end
    io.stdout:write(json.encode(clean { ok = true, result = { root = root, task = name, plan = steps, notes = notes } }), "\n")
  else
    for k, entry in ipairs(plan) do
      io.stdout:write(string.format("%d. %s%s\n", k, entry.name, entry.desc ~= "" and ("  " .. entry.desc) or ""))
    end
  end
  os.exit(0)
end

open_the_door(root)
local names = json.array {}
for _, entry in ipairs(plan) do names[#names + 1] = entry.name end
emit { event = "run", root = root, task = name, plan = names }

for _, entry in ipairs(plan) do
  current = entry.name
  emit { event = "task", name = entry.name, state = "started" }
  local started = sched.clock()
  local ok, e6 = task.execute(entry, opts_for[entry.name])
  local elapsed = sched.clock() - started
  ran[#ran + 1] = { name = entry.name, seconds = elapsed, ok = ok == true }
  if not ok then
    if not want_json then
      io.stderr:write(string.format("kuu: %s failed after %.1fs\n", entry.name, elapsed))
    end
    -- a failed task's own error is not a usage mistake of the runner: only
    -- argument errors exit 2, a child's code passes through, the rest is 1
    if not (type(e6.exit) == "number" or err.is(e6, "CLI", "usage")) then e6.exit = 1 end
    emit { event = "task", name = entry.name, state = "finished", ok = false, seconds = elapsed,
      error = { domain = e6.domain, code = e6.code, message = e6.message, exit = e6.exit } }
    crossing { kind = "task", name = entry.name, at = run_at + (started - run_began), seconds = elapsed,
      status = "failed", error = { domain = e6.domain, code = e6.code, message = e6.message, exit = e6.exit } }
    finish(false, e6, { root = root, task = name })
  end
  emit { event = "task", name = entry.name, state = "finished", ok = true, seconds = elapsed }
  crossing { kind = "task", name = entry.name, at = run_at + (started - run_began), seconds = elapsed, status = "ok" }
  if not want_json then io.stderr:write(string.format("kuu: %s %.1fs\n", entry.name, elapsed)) end
end
finish(true, nil, { root = root, task = name })
