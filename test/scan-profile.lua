-- Diagnostic worker for scan-bench.lua; not part of the regression runner.
-- Run from a disposable fixture with the executable being measured:
--   kuu test/scan-profile.lua --out ABSOLUTE.json run --json child
-- Also accepts check and capabilities. The embedded command and modules are
-- the measured executable's own copies. No source algorithm is substituted.
global none
global <const> require, assert, ipairs, pairs, type, tostring, tonumber, table,
               string, os, io, load, pcall, error, coroutine, package

local rt, fs, sched, json, hash = require "rt", require "fs", require "sched", require "json", require "hash"
local clock = sched.clock
local worker_started = clock()
local original_write, original_encode, original_exit = fs.write, json.encode, os.exit
local input = rt.args
assert(input[1] == "--out" and input[2] and input[3],
  "usage: scan-profile.lua --out ABSOLUTE.json run|check|capabilities [ARG ...]")
local output = assert(fs.absolute(input[2]))
local verb = input[3]
assert(verb == "run" or verb == "check" or verb == "capabilities", "unsupported profiled verb: " .. verb)
local argv = json.array {}
for i = 4, #input do argv[#argv + 1] = input[i] end
local source = assert(rt.source("cmd." .. verb), "executable has no embedded cmd." .. verb)
local metadata = {
  schema = "kuu.scan-profile.v1",
  executable = rt.exe,
  version = rt.version,
  executable_sha256 = assert(hash.file("sha256", rt.exe)),
  command_source_sha256 = hash.sum("sha256", source),
  cwd = assert(fs.cwd()),
  command = verb,
  args = argv,
  method = "wrapped exports; unchanged embedded command and module algorithms",
  timing = "inclusive wall seconds; self subtracts directly nested wrappers on the same coroutine; rows must not be summed as disjoint phases",
  boundaries = "command_seconds excludes worker setup/module preloading and profile emission; process startup and child internals require separate external measurements",
  counters = "call/result counts, not unique paths; byte counts cover fs.read/fs.write and hash.sum strings; hash.file bytes are unavailable without extra I/O",
  limitations = json.array {
    "wrapping and counters perturb execution; use separate uninstrumented processes for benchmark latency",
    "preloading modules removes their normal first-require cost from command_seconds",
    "Historical ledger.open includes delta construction; execution-only ledger.open reads bounded project/Git context without tree scans. Snapshot children occur only on historical builds.",
    "native_scan.collect reuses traversal metadata in one pass; fs.dirs/fs.list remain separately measured for older builds and non-scan callers",
    "hash.file is measured separately; execution-only history does not hash workspace files. Historical ledgers may hash their configured number of changed paths.",
    "timed waits include scheduling and child elapsed time; separately scheduled coroutine rows have their own async root",
    "nested kuu processes are uninstrumented and keep the selected rt.exe; only their parent's elapsed wait is observed",
    "this worker does not inject read failures, fix bugs, suppress results, or instrument the native implementation"
  },
}

-- Exports are mutable, shared through package.loaded. Preloading ensures every
-- unchanged command receives exactly the tables whose functions are wrapped.
local project, ledger, check, task = require "project", require "_ledger", require "check", require "task"
assert(package.loaded.project == project and package.loaded._ledger == ledger)
local rows, stacks = {}, {}
local command_started, command_finished, emitted

local function stack_for()
  local thread = coroutine.running()
  local stack = stacks[thread]
  if not stack then stack = {} stacks[thread] = stack end
  return stack
end

local function begin(name)
  local stack = stack_for()
  local parent = stack[#stack]
  local path = (parent and (parent.path .. "/") or "async/") .. name
  local row = rows[path]
  if not row then
    row = { path = path, name = name, calls = 0, raised = 0, nil_results = 0,
            seconds = 0, self_seconds = 0, counts = {} }
    rows[path] = row
  end
  row.calls = row.calls + 1
  local frame = { path = path, row = row, parent = parent, children = 0, started = clock() }
  stack[#stack + 1] = frame
  return frame, stack
end

local function finish(frame, stack, ended)
  local elapsed = ended - frame.started
  frame.row.seconds = frame.row.seconds + elapsed
  frame.row.self_seconds = frame.row.self_seconds + elapsed - frame.children
  if frame.parent then frame.parent.children = frame.parent.children + elapsed end
  stack[#stack] = nil
end

local function add(row, name, count)
  if count then row.counts[name] = (row.counts[name] or 0) + count end
end

local function count_result(name, row, args, result)
  local value = result[2] -- pcall's first result is its success flag
  if name == "fs.dirs" and type(value) == "table" then
    add(row, "returned_paths", #(value.paths or {}))
    add(row, "walk_errors", #(value.errors or {}))
    add(row, "links", #(value.links or {}))
    add(row, "pruned", value.pruned)
    add(row, "depthlimited", value.depthlimited)
  elseif name == "fs.list" and type(value) == "table" then
    add(row, "entries", #(value.entries or {}))
    add(row, "listing_errors", #(value.errors or {}))
    for _, entry in ipairs(value.entries or {}) do
      if entry.kind == "file" then
        add(row, "file_entries", 1)
        add(row, "listed_file_bytes", entry.size)
      elseif entry.kind == "directory" then add(row, "directory_entries", 1) end
    end
  elseif name == "native_scan.collect" and type(value) == "table" then
    add(row, "returned_paths", #value.paths)
    add(row, "file_entries", #value.files)
    add(row, "enumerated_dirs", value.enumerated)
    add(row, "walk_errors", #value.errors)
    add(row, "links", #value.links)
    add(row, "pruned", value.pruned)
  elseif (name == "scan.collect" or name == "scan.compat") and type(value) == "table" then
    add(row, "file_entries", value.counts.files)
    add(row, "enumerated_dirs", value.counts.enumerated_dirs)
    add(row, "pruned", value.counts.excluded_dirs)
    add(row, "walk_errors", value.counts.errors)
  elseif name == "fs.read" and type(value) == "string" then
    add(row, "bytes_read", #value)
  elseif name == "fs.write" and value and type(args[2]) == "string" then
    add(row, "bytes_written", #args[2])
  elseif name == "hash.file" and value then
    add(row, "files_hashed", 1)
  elseif name == "hash.sum" and type(args[2]) == "string" then
    add(row, "bytes_hashed", #args[2])
  elseif name == "json.encode" and type(value) == "string" then
    add(row, "encoded_bytes", #value)
  elseif name == "json.decode" and type(args[1]) == "string" then
    add(row, "input_bytes", #args[1])
  elseif name == "check.modules" and type(value) == "table" then
    add(row, "lua_files", value.files)
    add(row, "modules", #(value.modules or {}))
    add(row, "inventory_errors", #(value.errors or {}))
  elseif name == "ledger.verify" and value and type(result[3]) == "number" then
    add(row, "records_verified", result[3])
  end
end

local function wrap(module, key, name)
  local original = assert(module[key], "missing measured export: " .. name)
  assert(type(original) == "function", "not a function: " .. name)
  module[key] = function(...)
    local frame, stack = begin(name)
    local args = table.pack(...)
    local result = table.pack(pcall(original, ...))
    local ended = clock()
    if not result[1] then frame.row.raised = frame.row.raised + 1
    elseif result[2] == nil then frame.row.nil_results = frame.row.nil_results + 1 end
    finish(frame, stack, ended)
    if result[1] then count_result(name, frame.row, args, result) end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
  end
end

for _, key in ipairs { "dirs", "list", "read", "write", "stat", "exists", "canon", "mkdir" } do wrap(fs, key, "fs." .. key) end
for _, key in ipairs { "file", "sum" } do wrap(hash, key, "hash." .. key) end
for _, key in ipairs { "encode", "decode" } do wrap(json, key, "json." .. key) end
for _, key in ipairs { "find", "enter", "load_tasks" } do wrap(project, key, "project." .. key) end
for _, key in ipairs { "open", "record", "close", "tail", "verify" } do
  if ledger[key] then wrap(ledger, key, "ledger." .. key) end
end
for _, key in ipairs { "tree", "file", "modules" } do wrap(check, key, "check." .. key) end
for _, key in ipairs { "plan", "arguments", "execute", "exec" } do wrap(task, key, "task." .. key) end
local has_native_scan, native_scan = pcall(require, "_scan_native")
if has_native_scan then
  wrap(native_scan, "collect", "native_scan.collect")
  local scan = require "_scan"
  for _, key in ipairs { "collect", "compat" } do wrap(scan, key, "scan." .. key) end
end

local function emit(code, failure)
  if emitted then return end
  emitted = true
  command_finished = clock()
  -- os.exit may run while wrappers (e.g. the manifest) remain on the stack.
  -- Their elapsed intervals are still useful, explicitly marked as unwound.
  for _, stack in pairs(stacks) do
    while #stack > 0 do
      local frame = stack[#stack]
      add(frame.row, "exit_unwinds", 1)
      finish(frame, stack, command_finished)
    end
  end
  local ordered = json.array {}
  for _, row in pairs(rows) do ordered[#ordered + 1] = row end
  table.sort(ordered, function(a, b) return a.path < b.path end)
  metadata.phases = ordered
  metadata.command_seconds = command_finished - command_started
  metadata.setup_seconds = command_started - worker_started
  metadata.exit_code = code
  metadata.failure = failure
  local ok, why = original_write(output, original_encode(metadata) .. "\n")
  if not ok then io.stderr:write("scan-profile: cannot write profile: ", tostring(why), "\n") original_exit(70) end
end

-- Match the verb route's visible context; rt.exe is deliberately untouched.
rt.args, rt.route, rt.program = argv, "cmd", verb
rt.root(metadata.cwd)
local chunk = assert(load(source, "=kuu/lua/cmd/" .. verb .. ".lua", "t"))
os.exit = function(code, close)
  local normalized = code == nil and 0 or code == true and 0 or code == false and 1 or tonumber(code)
  emit(normalized or 1)
  return original_exit(code, close)
end
command_started = clock()
local frame, stack = begin("command." .. verb)
local ok, failure = pcall(chunk, table.unpack(argv))
finish(frame, stack, clock())
if not ok then
  emit(1, tostring(failure))
  error(failure, 0)
end
emit(0)
