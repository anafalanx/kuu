-- check.lua -- `kuu check [--json] [--fix] [PATH ...]`: parse, global
-- declarations, requires, palette names and contracts.
global none
global <const> require, ipairs, pairs, tostring, string, io, os, table

local timing = require "_timings"
local began, times = timing.clock(), {}
local rt = require "rt"
local cli = require "cli"
local fs = require "fs"
local json = require "json"
local clean = require "_jsonsafe"
local project = require "project"
local check = require "check"
local policy = require "_scan_policy"
local scan = require "_scan"

local spec = {
  { "--json", type = "flag", help = "machine-readable report" },
  { "--timings", type = "flag", help = "print measured command phases on stderr" },
  { "--fix", type = "flag", help = "write each file's global declaration: add the standard names it uses, remove the ones it does not" },
  { "--adopt", type = "flag", help = "with --fix, also give a file that has no global declaration one" },
  { "paths", rest = true, help = "files or directories (default: the nearest project, else the current directory)" },
}
local opts, e = cli.parse(rt.args, spec, "kuu check")
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu check")) os.exit(0) end

local root, file = project.find()
root = root or fs.absolute(".")
local context, config_error = policy.load(root)
if not context then
  times.setup = timing.clock() - began
  timing.finish(times, began)
  if opts.json then
    io.write(json.encode(clean { ok = false, error = {
      domain = config_error.domain, code = config_error.code, message = config_error.message,
    }, result = { root = root, complete = false, scans = json.array {}, timings = times } }), "\n")
  else
    io.stderr:write("kuu: ", tostring(config_error), "\n")
  end
  if opts.timings then timing.write("check", times) end
  os.exit(2)
end
-- A tasks.lua not yet renamed is found the way run and list find it, and
-- said the same way: on standard error, and as `notes` on the envelope.
local notes = json.array {}
if file == project.LEGACY then
  notes[#notes + 1] = project.LEGACY_NOTE
  io.stderr:write("kuu: warning: ", project.LEGACY_NOTE, "\n")
end

local scans, complete = json.array {}, true
local scope = scan.describe(context)
times.setup = timing.clock() - began

local function collect_reports()
  local reports = {}
  local function collect_tree(path)
    local result = check.tree(path, root, context)
    for _, report in ipairs(result.reports) do reports[#reports + 1] = report end
    if result.scan then
      scans[#scans + 1] = result.scan
      if result.scan.seconds ~= nil then times.scan = (times.scan or 0) + result.scan.seconds end
    end
    if result.complete == false then complete = false end
  end
  if #opts.paths == 0 then
    collect_tree(root)
  else
    for _, p in ipairs(opts.paths) do
      local kind = fs.exists(p)
      if kind == "directory" then
        collect_tree(p)
      elseif kind == "file" then
        local report = check.file(p, root)
        reports[#reports + 1] = report
        for _, finding in ipairs(report.errors) do if finding.kind == "read" then complete = false end end
      else
        complete = false
        return reports, { domain = "CHECK", code = "notfound", message = "no file or directory '" .. p .. "'" }
      end
    end
  end
  return reports
end
local reports, selection_error = timing.measure(times, "checking", collect_reports)

-- --fix rewrites the declaration and nothing else, then the files are checked
-- again, so the report describes what is now on disk rather than what was. A
-- name is only ever added when the runtime has a global by that name, so a
-- misspelling is refused rather than declared; see _fixglobals.
local fixed, unfixable = {}, {}
if opts.fix and not selection_error then
  local fixing_began = timing.clock()
  local fixer = require "_fixglobals"
  local paths = {}
  for _, r in ipairs(reports) do if not r.enumeration then paths[#paths + 1] = r.path end end
  for _, path in ipairs(paths) do
    local result, why = fixer.fix(path, opts.adopt)
    if not result then
      unfixable[#unfixable + 1] = { path = path, message = tostring(why) }
    elseif result.changed then
      local ok, e2 = fs.write(path, result.text)
      if ok then
        fixed[#fixed + 1] = { path = path, added = result.added, removed = result.removed }
      else
        unfixable[#unfixable + 1] = { path = path, message = tostring(e2) }
      end
    end
  end
  times.fixing = timing.clock() - fixing_began
  if #fixed > 0 then
    reports, selection_error = timing.measure(times, "checking", collect_reports)
  end
end

local function shown(path)
  if path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
  return path
end

-- Assemble the human report before taking total, so final emission is
-- outside the same boundary as JSON serialization and flushing.
local output = {}
local function say(...) output[#output + 1] = table.concat { ... } end
if opts.fix and not opts.json then
  for _, f in ipairs(fixed) do
    say(shown(f.path), ":\n")
    if #f.added > 0 then say("  + ", table.concat(f.added, ", "), "\n") end
    if #f.removed > 0 then say("  - ", table.concat(f.removed, ", "), "\n") end
  end
  for _, u in ipairs(unfixable) do
    say(shown(u.path), ": not fixed: ", u.message, "\n")
  end
end

local errors, warnings = 0, 0
for _, r in ipairs(reports) do
  for _, x in ipairs(r.errors) do
    errors = errors + 1
    if not opts.json then say(string.format("%s:%d: %s\n", shown(r.path), x.line, x.message)) end
  end
  for _, w in ipairs(r.warnings) do
    warnings = warnings + 1
    if not opts.json then
      if w.line > 0 then
        say(string.format("%s:%d: warning: %s\n", shown(r.path), w.line, w.message))
      else
        say(string.format("%s: warning: %s\n", shown(r.path), w.message))
      end
    end
  end
end

if opts.json then
  local files = json.array {}
  for _, r in ipairs(reports) do
    -- The lists inside a declaration are arrays on the wire, empty or not,
    -- as capabilities spells the same declaration.
    local tools = json.array {}
    for _, t in ipairs(r.tools or {}) do
      local reach = {}
      for k, list in pairs(t.reach) do reach[k] = json.array(list) end
      tools[#tools + 1] = { name = t.name, line = t.line, exe = t.exe, args = t.args, output = t.output,
        emits = json.array(t.emits), timeout = t.timeout, reach = reach }
    end
    files[#files + 1] = { path = shown(r.path), errors = json.array(r.errors), warnings = json.array(r.warnings),
      requires = json.array(r.requires), tools = tools }
  end
  local result = { root = root, files = files, errors = errors, warnings = warnings, notes = notes,
    scope = scope, scans = scans, complete = complete, timings = times }
  if opts.fix then
    result.fixed, result.unfixed = json.array {}, json.array {}
    for _, f in ipairs(fixed) do
      result.fixed[#result.fixed + 1] = { path = shown(f.path),
        added = json.array(f.added), removed = json.array(f.removed) }
    end
    for _, u in ipairs(unfixable) do
      result.unfixed[#result.unfixed + 1] = { path = shown(u.path), message = u.message }
    end
  end
  local envelope = { ok = errors == 0 and selection_error == nil, result = result, error = selection_error }
  timing.finish(times, began)
  io.write(json.encode(clean(envelope)), "\n")
else
  local summary
  if opts.fix then
    summary = string.format("kuu: %d files, %d fixed, %d errors, %d warnings\n",
      #reports, #fixed, errors, warnings)
  else
    summary = string.format("kuu: %d files, %d errors, %d warnings\n", #reports, errors, warnings)
  end
  local text = table.concat(output)
  timing.finish(times, began)
  io.write(text)
  if selection_error then io.stderr:write("kuu: CHECK notfound: ", selection_error.message, "\n") end
  io.stderr:write(summary)
end
if opts.timings then timing.write("check", times) end
os.exit(selection_error and 2 or errors > 0 and 1 or 0)
