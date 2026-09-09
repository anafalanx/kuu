-- verify.lua -- `kuu verify [--deep] [--lock FILE] [--root DIR] [--json]`
global none
global <const> require, ipairs, tostring, string, io, os

local rt = require "rt"
local cli = require "cli"
local json = require "json"
local project = require "project"
local toolchain = require "toolchain"

local spec = {
  { "--deep", type = "flag", help = "re-hash every installed executable and notice" },
  { "--lock", type = "string", help = "the lock file (default: tools/lock.json of the nearest project)" },
  { "--root", type = "string", help = "where tools live (default: .tools of the nearest project)" },
  { "--json", type = "flag", help = "machine-readable report" },
}
local opts, e = cli.parse(rt.args, spec, "kuu verify")
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu verify")) os.exit(0) end

local function finish(ok, e2, report, code)
  if opts.json then
    local envelope = { ok = ok, result = report }
    if not ok then envelope.error = { domain = e2.domain, code = e2.code, message = e2.message } end
    io.write(json.encode(envelope), "\n")
  else
    if report ~= nil then
      for _, t in ipairs(report.tools) do
        io.write(string.format("%-9s %-16s %-12s %s\n", t.status, t.name, tostring(t.version or ""), t.path))
      end
    end
    if not ok then io.stderr:write("kuu: ", tostring(e2), "\n") end
  end
  os.exit(ok and 0 or code)
end

local lock, root = opts.lock, opts.root
if lock == nil or root == nil then
  local project_root, e3 = project.find()
  if project_root ~= nil then
    lock = lock or project.lock_path(project_root)
    root = root or project.tools_root(project_root)
  elseif lock ~= nil then
    root = (lock:match("^(.*)/[^/]+$") or ".") .. "/../.tools"
  else
    finish(false, e3, nil, 2)
  end
end

local report, e4 = toolchain.verify(lock, root, { deep = opts.deep })
if not report then finish(false, e4, e4.report, 1) end
finish(true, nil, report, 0)
