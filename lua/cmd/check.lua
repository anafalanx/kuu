-- check.lua -- `kuu check [--json] [--fix] [PATH ...]`: parse, global
-- declarations, requires, palette names and contracts.
global none
global <const> require, ipairs, tostring, string, io, os, table

local rt = require "rt"
local cli = require "cli"
local fs = require "fs"
local json = require "json"
local project = require "project"
local check = require "check"

local spec = {
  { "--json", type = "flag", help = "machine-readable report" },
  { "--fix", type = "flag", help = "write each file's global declaration: add the standard names it uses, remove the ones it does not" },
  { "--adopt", type = "flag", help = "with --fix, also give a file that has no global declaration one" },
  { "paths", rest = true, help = "files or directories (default: the nearest project, else the current directory)" },
}
local opts, e = cli.parse(rt.args, spec, "kuu check")
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu check")) os.exit(0) end

local root = project.find() or fs.absolute(".")

local reports = {}
if #opts.paths == 0 then
  reports = check.tree(root, root).reports
else
  for _, p in ipairs(opts.paths) do
    local kind = fs.exists(p)
    if kind == "directory" then
      for _, r in ipairs(check.tree(p, root).reports) do reports[#reports + 1] = r end
    elseif kind == "file" then
      reports[#reports + 1] = check.file(p, root)
    else
      io.stderr:write("kuu: CHECK notfound: no file or directory '", p, "'\n")
      os.exit(2)
    end
  end
end

-- --fix rewrites the declaration and nothing else, then the files are checked
-- again, so the report describes what is now on disk rather than what was. A
-- name is only ever added when the runtime has a global by that name, so a
-- misspelling is refused rather than declared; see _fixglobals.
local fixed, unfixable = {}, {}
if opts.fix then
  local fixer = require "_fixglobals"
  local paths = {}
  for _, r in ipairs(reports) do paths[#paths + 1] = r.path end
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
  if #fixed > 0 then
    reports = {}
    for _, path in ipairs(paths) do reports[#reports + 1] = check.file(path, root) end
  end
end

local function shown(path)
  if path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
  return path
end

if opts.fix and not opts.json then
  for _, f in ipairs(fixed) do
    io.write(shown(f.path), ":\n")
    if #f.added > 0 then io.write("  + ", table.concat(f.added, ", "), "\n") end
    if #f.removed > 0 then io.write("  - ", table.concat(f.removed, ", "), "\n") end
  end
  for _, u in ipairs(unfixable) do
    io.write(shown(u.path), ": not fixed: ", u.message, "\n")
  end
end

local errors, warnings = 0, 0
for _, r in ipairs(reports) do
  for _, x in ipairs(r.errors) do
    errors = errors + 1
    if not opts.json then io.write(string.format("%s:%d: %s\n", shown(r.path), x.line, x.message)) end
  end
  for _, w in ipairs(r.warnings) do
    warnings = warnings + 1
    if not opts.json then
      if w.line > 0 then
        io.write(string.format("%s:%d: warning: %s\n", shown(r.path), w.line, w.message))
      else
        io.write(string.format("%s: warning: %s\n", shown(r.path), w.message))
      end
    end
  end
end

if opts.json then
  local files = json.array {}
  for _, r in ipairs(reports) do
    files[#files + 1] = { path = shown(r.path), errors = json.array(r.errors), warnings = json.array(r.warnings), requires = json.array(r.requires) }
  end
  local result = { root = root, files = files, errors = errors, warnings = warnings }
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
  io.write(json.encode { ok = errors == 0, result = result }, "\n")
else
  if opts.fix then
    io.stderr:write(string.format("kuu: %d files, %d fixed, %d errors, %d warnings\n",
      #reports, #fixed, errors, warnings))
  else
    io.stderr:write(string.format("kuu: %d files, %d errors, %d warnings\n", #reports, errors, warnings))
  end
end
os.exit(errors > 0 and 1 or 0)
