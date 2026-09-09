-- check.lua -- `kuu check [--json] [PATH ...]`: parse, global declarations, requires.
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

local function shown(path)
  if path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
  return path
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
  io.write(json.encode { ok = errors == 0, result = { root = root, files = files, errors = errors, warnings = warnings } }, "\n")
else
  io.stderr:write(string.format("kuu: %d files, %d errors, %d warnings\n", #reports, errors, warnings))
end
os.exit(errors > 0 and 1 or 0)
