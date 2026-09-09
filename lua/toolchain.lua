-- toolchain.lua -- hydrate and verify a repository's tools from a prescriptive lock.
--
--   tools/lock.json
--   {
--     "schema": 1,
--     "tools": {
--       "zig": { "version": "0.16.0",
--                "url": "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip",
--                "sha256": "3f2b...", "bytes": 88811520, "kind": "zip", "strip": 1,
--                "bin": "zig.exe", "check": ["version"], "expect": "0.16.0",
--                "license": "MIT", "notice": "LICENSE", "noticeSha256": "9a1c..." }
--     }
--   }
--
--   local toolchain = require "toolchain"
--   local report = toolchain.hydrate("tools/lock.json", ".tools")      -- every tool present and stamped
--   local report = toolchain.verify("tools/lock.json", ".tools", { deep = true })
--   local zig    = toolchain.path("tools/lock.json", "zig", ".tools")   -- an absolute path; never PATH
--
-- The lock says where every tool's bytes come from and what they hash to.
-- Hydrate and verify are one pass with a flag: each tool is classified as ok,
-- missing, stale (the lock or the hydrating code changed), or corrupt (deep:
-- the executable or notice no longer hashes as stamped), and hydrate repairs
-- whatever is not ok.  A repair downloads to `.partial`, hashes, renames into
-- the download cache; unpacks into a temporary directory; checks the
-- executable, the notice, and the tool's own reported version; removes the old
-- stamp; swaps the directory in; and writes the stamp last.  So an interrupted
-- run leaves no half-installed tool, a damaged download heals on the next run,
-- and nothing is ever written outside the tools root.  Archives are unpacked
-- by the tar.exe every supported Windows ships (zip, tar.gz, tar.xz, tar.zst).
global none
global <const> require, ipairs, pairs, tostring, type, string, table, math, os, error, select

local fs = require "fs"
local hash = require "hash"
local http = require "http"
local json = require "json"
local proc = require "proc"
local err = require "err"
local rt = require "rt"

local toolchain = {}

toolchain.FORMAT = 2 -- the layout under the tools root; bumping it re-hydrates everything

local KINDS = { zip = true, tar = true, exe = true }
local KEYS = { version = true, url = true, sha256 = true, bytes = true, kind = true, strip = true, bin = true,
  check = true, expect = true, license = true, notice = true, noticeSha256 = true }

local function fail(code, message, extra)
  return nil, err.new("TOOLCHAIN", code, message, extra)
end

local function is_hex64(s)
  return type(s) == "string" and #s == 64 and s:match("^%x+$") ~= nil
end

-- A relative path that stays inside a tool's directory.
local function is_inside(rel)
  return type(rel) == "string" and rel ~= "" and not rel:find("..", 1, true)
    and not rel:match("^[/\\]") and not rel:match("^%a:") and not rel:match("[%z\r\n]")
end

local function url_name(url)
  return (url:gsub("[?#].*$", "")):match("([^/]+)$")
end

-- toolchain.read(path) -> lock | nil, err.  A lock with one thing wrong is refused whole.
function toolchain.read(path)
  local text, e = fs.read(path, { encoding = "utf-8" })
  if not text then return fail("nolock", "cannot read the lock '" .. path .. "': " .. tostring(e)) end
  local lock, e2 = json.decode(text)
  if lock == nil then return fail("badlock", "'" .. path .. "' is not valid JSON: " .. tostring(e2)) end
  if type(lock) ~= "table" or json.is_array(lock) or lock.schema ~= 1 or type(lock.tools) ~= "table" or json.is_array(lock.tools) then
    return fail("badlock", "'" .. path .. "' must be an object with \"schema\": 1 and a \"tools\" object")
  end
  for k in pairs(lock) do
    if k ~= "schema" and k ~= "tools" then return fail("badlock", "'" .. path .. "': unknown top-level key '" .. tostring(k) .. "'") end
  end
  local names, folded = {}, {}
  for name, entry in pairs(lock.tools) do
    local where = "tool '" .. tostring(name) .. "'"
    if type(name) ~= "string" or not name:match("^%w[%w%._%-]*$") then
      return fail("badlock", where .. ": the name must be a plain word starting with a letter or digit")
    end
    -- names become directories and files, and Windows cannot tell Foo from foo
    local lowered = name:lower()
    if folded[lowered] ~= nil then
      return fail("badlock", string.format("tools '%s' and '%s' differ only in case, which the file system cannot tell apart", folded[lowered], name))
    end
    folded[lowered] = name
    if type(entry) ~= "table" or json.is_array(entry) then return fail("badlock", where .. " must be an object") end
    for k in pairs(entry) do
      if not KEYS[k] then return fail("badlock", where .. ": unknown key '" .. tostring(k) .. "'") end
    end
    if type(entry.url) ~= "string" or not entry.url:match("^https?://") then
      return fail("badlock", where .. ": url must start with http:// or https://")
    end
    if not is_hex64(entry.sha256) then return fail("badlock", where .. ": sha256 must be 64 hex digits") end
    entry.sha256 = entry.sha256:lower()
    if entry.bytes ~= nil and (math.type(entry.bytes) ~= "integer" or entry.bytes < 0) then
      return fail("badlock", where .. ": bytes must be a non-negative integer")
    end
    local kind = entry.kind
    if kind == nil then
      local lower = (entry.url:gsub("[?#].*$", "")):lower()
      if lower:match("%.zip$") then kind = "zip"
      elseif lower:match("%.tar%.%w+$") or lower:match("%.tgz$") or lower:match("%.tar$") then kind = "tar"
      elseif lower:match("%.exe$") then kind = "exe" end
    end
    if not KINDS[kind] then
      return fail("badlock", where .. ": kind must be zip, tar, or exe, and the url does not tell")
    end
    entry.kind = kind
    if entry.strip ~= nil and (kind == "exe" or math.type(entry.strip) ~= "integer" or entry.strip < 0) then
      return fail("badlock", where .. ": strip must be a non-negative integer, for archives only")
    end
    if entry.bin == nil then
      entry.bin = (kind == "exe" and url_name(entry.url)) or (name .. ".exe")
    end
    if not is_inside(entry.bin) then return fail("badlock", where .. ": bin must be a relative path inside the tool") end
    if entry.version ~= nil and type(entry.version) ~= "string" then return fail("badlock", where .. ": version must be a string") end
    if entry.check ~= nil then
      if type(entry.check) ~= "table" then return fail("badlock", where .. ": check must be an array of arguments") end
      for _, a in ipairs(entry.check) do
        if type(a) ~= "string" then return fail("badlock", where .. ": check must be an array of strings") end
      end
      if entry.expect == nil and entry.version == nil then return fail("badlock", where .. ": check needs expect or version") end
    end
    if entry.expect ~= nil and (type(entry.expect) ~= "string" or entry.check == nil) then
      return fail("badlock", where .. ": expect is a string that goes with check")
    end
    if entry.license ~= nil and type(entry.license) ~= "string" then return fail("badlock", where .. ": license must be a string") end
    if entry.notice ~= nil and not is_inside(entry.notice) then
      return fail("badlock", where .. ": notice must be a relative path inside the tool")
    end
    if entry.noticeSha256 ~= nil then
      if entry.notice == nil then return fail("badlock", where .. ": noticeSha256 needs notice") end
      if not is_hex64(entry.noticeSha256) then return fail("badlock", where .. ": noticeSha256 must be 64 hex digits") end
      entry.noticeSha256 = entry.noticeSha256:lower()
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return { path = path, tools = lock.tools, names = names }
end

-- The stamp key: a hash over the lock entry, the layout format, and the code
-- that hydrates.  Any of them changing makes every stamped tool stale.
local function literal(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local out = {}
    for i, x in ipairs(v) do out[i] = literal(x) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  return tostring(v)
end

local function key_of(entry)
  local keys = {}
  for k in pairs(entry) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = { "kuu toolchain format " .. toolchain.FORMAT }
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. literal(entry[k]) end
  parts[#parts + 1] = rt.source("toolchain") or "?"
  return hash.sum("sha256", table.concat(parts, "\n"))
end

-- Everything kuu owns under the root lives in dot-directories, and a tool name
-- may not start with a dot, so no tool can collide with a stamp, a download,
-- or a temporary directory, whatever it is called.
local function places(root, name, entry)
  local dir = root .. "/" .. name
  return {
    dir = dir,
    bin = dir .. "/" .. entry.bin,
    notice = entry.notice and (dir .. "/" .. entry.notice) or nil,
    stamps = root .. "/.stamps",
    stamp = root .. "/.stamps/" .. name .. ".json",
    temp = root .. "/.partial/" .. name,
    cache = root .. "/.downloads",
  }
end

local function read_stamp(path)
  local text = fs.read(path, { encoding = "utf-8" })
  if not text then return nil end
  local stamp = json.decode(text)
  if type(stamp) ~= "table" then return nil end
  return stamp
end

local function status_of(p, entry, key, deep)
  local stamp = read_stamp(p.stamp)
  if stamp == nil or fs.exists(p.bin) ~= "file" then return "missing" end
  if stamp.key ~= key then return "stale" end
  if deep then
    if hash.file("sha256", p.bin) ~= stamp.binSha256 then return "corrupt" end
    if p.notice and (fs.exists(p.notice) ~= "file"
        or (stamp.noticeSha256 ~= nil and hash.file("sha256", p.notice) ~= stamp.noticeSha256)) then
      return "corrupt"
    end
  end
  return "ok"
end

local function tar_exe()
  local system_root = os.getenv("SystemRoot") or "C:\\Windows"
  local exe = system_root:gsub("\\", "/") .. "/System32/tar.exe"
  if fs.exists(exe) ~= "file" then
    return fail("oserror", "Windows' own tar.exe is not at " .. exe)
  end
  return exe
end

-- The archive or executable the lock names, in the download cache with the
-- right hash.  A cached file is re-hashed every time; a wrong one is replaced.
local function fetch(p, name, entry, options, progress)
  local made, e = fs.mkdir(p.cache)
  if not made then return nil, e end
  local base = url_name(entry.url) or ""
  local ext = base:match("(%.tar%.%w+)$") or base:match("(%.%w+)$") or ""
  local file = p.cache .. "/" .. name .. "-" .. entry.sha256:sub(1, 16) .. ext
  if fs.exists(file) == "file" then
    if hash.file("sha256", file) == entry.sha256 then
      local size = fs.stat(file)
      if entry.bytes ~= nil and size ~= nil and size.size ~= entry.bytes then
        return fail("mismatch", string.format("tool '%s': the archive is %d bytes, the lock says %d; the lock disagrees with itself", name, size.size, entry.bytes))
      end
      progress("cached", name, file)
      return file
    end
    fs.remove(file)
  end
  local partial = file .. ".partial"
  fs.remove(partial)
  progress("download", name, entry.url)
  local request = { to = partial, timeout = options.timeout or "30m" }
  if entry.bytes ~= nil then request.maxbody = tostring(entry.bytes) .. "B" end
  local r, e2 = http.get(entry.url, request)
  if not r then
    fs.remove(partial)
    return fail("download", string.format("tool '%s': %s", name, tostring(e2)))
  end
  if r.status ~= 200 then
    fs.remove(partial)
    return fail("download", string.format("tool '%s': %s answered %d", name, entry.url, r.status))
  end
  if entry.bytes ~= nil and r.bytes ~= entry.bytes then
    fs.remove(partial)
    return fail("mismatch", string.format("tool '%s': the download is %d bytes, the lock says %d", name, r.bytes, entry.bytes))
  end
  local have = hash.file("sha256", partial)
  if have ~= entry.sha256 then
    fs.remove(partial)
    return fail("mismatch", string.format("tool '%s': the download hashes to %s, the lock says %s", name, tostring(have), entry.sha256))
  end
  local moved, e3 = fs.rename(partial, file, { replace = true })
  if not moved then
    fs.remove(partial)
    return nil, e3
  end
  return file
end

local function unpack(p, name, entry, archive, progress)
  progress("unpack", name, archive)
  fs.remove(p.temp, { recursive = true })
  local made, e = fs.mkdir(p.temp)
  if not made then return nil, e end
  if entry.kind == "exe" then
    local target = p.temp .. "/" .. entry.bin
    local dir = target:match("^(.*)/[^/]+$")
    if dir ~= nil then
      local ok, e2 = fs.mkdir(dir)
      if not ok then return nil, e2 end
    end
    return fs.copy(archive, target)
  end
  local tar, e3 = tar_exe()
  if not tar then return nil, e3 end
  local argv = { tar, "-xf", (archive:gsub("/", "\\")), "-C", (p.temp:gsub("/", "\\")) }
  if entry.strip ~= nil and entry.strip > 0 then
    argv[#argv + 1] = "--strip-components"
    argv[#argv + 1] = tostring(entry.strip)
  end
  argv.timeout = "30m"
  local r, e4 = proc.run(argv)
  if not r then return nil, e4 end
  if r.status ~= "exit" or r.code ~= 0 then
    return fail("unpack", string.format("tool '%s': tar %s %s: %s", name, r.status, tostring(r.code), (r.err:gsub("%s+$", ""))))
  end
  return true
end

local function first_line(s)
  return (s:match("^[^\r\n]*"))
end

-- Fetch, unpack, check, swap in, stamp.  Every failure removes the temporary
-- directory.  A failure before the swap leaves any old install and its stamp
-- in place, so the tool reads as stale; a failure after the old stamp went
-- reads as missing.  Neither is ever ok.
local function install(p, name, entry, key, options, progress)
  local archive, e = fetch(p, name, entry, options, progress)
  if not archive then return nil, e end
  local function abandon(...)
    fs.remove(p.temp, { recursive = true })
    return ...
  end
  local unpacked, e2 = unpack(p, name, entry, archive, progress)
  if not unpacked then return abandon(nil, e2) end
  local temp_bin = p.temp .. "/" .. entry.bin
  if fs.exists(temp_bin) ~= "file" then
    return abandon(fail("unpack", string.format("tool '%s': the archive holds no '%s'; check bin and strip", name, entry.bin)))
  end
  local notice_sha
  if entry.notice ~= nil then
    local temp_notice = p.temp .. "/" .. entry.notice
    if fs.exists(temp_notice) ~= "file" then
      return abandon(fail("notice", string.format("tool '%s': the archive carries no '%s'", name, entry.notice)))
    end
    notice_sha = hash.file("sha256", temp_notice)
    if entry.noticeSha256 ~= nil and notice_sha ~= entry.noticeSha256 then
      return abandon(fail("mismatch", string.format("tool '%s': '%s' hashes to %s, the lock says %s",
        name, entry.notice, tostring(notice_sha), entry.noticeSha256)))
    end
  end
  if entry.check ~= nil then
    progress("check", name, temp_bin)
    local argv = { temp_bin }
    for _, a in ipairs(entry.check) do argv[#argv + 1] = a end
    argv.timeout = "2m"
    local expect = entry.expect or entry.version
    local r, e3 = proc.run(argv)
    if not r then
      return abandon(fail("check", string.format("tool '%s': cannot run '%s %s': %s", name, entry.bin, table.concat(entry.check, " "), tostring(e3))))
    end
    local output = r.out .. r.err
    if r.status ~= "exit" or not output:find(expect, 1, true) then
      return abandon(fail("mismatch", string.format("tool '%s': '%s %s' did not report '%s' (%s %s: %s)",
        name, entry.bin, table.concat(entry.check, " "), expect, r.status, tostring(r.code), first_line(output))))
    end
  end
  -- From here the old install goes: its stamp first, so a failure below reads
  -- as missing rather than ok.
  fs.remove(p.stamp)
  if fs.exists(p.dir) then
    local removed, e4 = fs.remove(p.dir, { recursive = true })
    if not removed then
      return abandon(fail("replace", string.format("tool '%s': cannot remove the old install, a file may be in use: %s", name, tostring(e4))))
    end
  end
  local renamed, e5 = fs.rename(p.temp, p.dir)
  if not renamed then return abandon(nil, e5) end
  local stamp = {
    schema = 1, name = name, version = entry.version, url = entry.url, sha256 = entry.sha256,
    bin = entry.bin, binSha256 = hash.file("sha256", p.bin), notice = entry.notice, noticeSha256 = notice_sha,
    key = key, kuu = rt.version, hydrated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  local made_stamps, e6 = fs.mkdir(p.stamps)
  if not made_stamps then return nil, e6 end
  local written, e7 = fs.write(p.stamp, json.encode(stamp, { pretty = true }) .. "\n")
  if not written then return nil, e7 end
  return true
end

-- The one pass.  options: fix, deep, progress(step, name, detail), timeout.
local function reconcile(lock_path, root, options)
  local progress = options.progress or function() end
  local lock, e = toolchain.read(lock_path)
  if not lock then return nil, e end
  root = fs.absolute(root)
  local report = { root = root, lock = fs.absolute(lock_path), ok = true, tools = json.array {} }
  if options.fix then
    local made, e2 = fs.mkdir(root)
    if not made then return nil, e2 end
  end
  for _, name in ipairs(lock.names) do
    local entry = lock.tools[name]
    local p = places(root, name, entry)
    local key = key_of(entry)
    local status = status_of(p, entry, key, options.deep)
    local item = { name = name, version = entry.version, license = entry.license, status = status, path = p.bin }
    report.tools[#report.tools + 1] = item
    if status == "ok" then
      item.action = "current"
    elseif options.fix then
      progress(status, name, p.dir)
      local ok, e3 = install(p, name, entry, key, options, progress)
      if not ok then
        item.status = "failed"
        item.error = e3
        report.ok = false
        return nil, e3, report
      end
      item.action = status == "missing" and "hydrated" or "replaced"
      item.status = "ok"
    else
      report.ok = false
    end
  end
  return report
end

-- toolchain.hydrate(lock_path, root [, { deep = bool, progress = fn, timeout = "30m" }])
--   -> report | nil, err, partial report
-- report = { root, lock, ok = true, tools = { { name, version, license, status = "ok",
--   action = "current" | "hydrated" | "replaced", path } ... } }
function toolchain.hydrate(lock_path, root, options)
  options = options or {}
  return reconcile(lock_path, root, { fix = true, deep = options.deep, progress = options.progress, timeout = options.timeout })
end

-- toolchain.verify(lock_path, root [, { deep = bool }]) -> report | nil, err
-- The err is TOOLCHAIN unverified with the report attached as `report`, each
-- tool's status one of ok, missing, stale, corrupt.
function toolchain.verify(lock_path, root, options)
  options = options or {}
  local report, e = reconcile(lock_path, root, { fix = false, deep = options.deep })
  if not report then return nil, e end
  if not report.ok then
    local problems = {}
    for _, t in ipairs(report.tools) do
      if t.status ~= "ok" then problems[#problems + 1] = t.name .. " is " .. t.status end
    end
    return fail("unverified", table.concat(problems, ", ") .. "; kuu hydrate repairs this", { report = report })
  end
  return report
end

-- toolchain.path(lock_path, name, root) -> the tool's executable, absolute | nil, err
-- Raises TOOLCHAIN unknown for a name the lock lacks; a tool that is not ok is
-- nil, err with its status as the code.
function toolchain.path(lock_path, name, root)
  local lock, e = toolchain.read(lock_path)
  if not lock then return nil, e end
  local entry = lock.tools[name]
  if entry == nil then
    error(err.new("TOOLCHAIN", "unknown", "the lock has no tool '" .. tostring(name) .. "'"))
  end
  local p = places(fs.absolute(root), name, entry)
  local status = status_of(p, entry, key_of(entry), false)
  if status ~= "ok" then
    return fail(status, "tool '" .. name .. "' is " .. status .. "; kuu hydrate repairs this")
  end
  return p.bin
end

return toolchain
