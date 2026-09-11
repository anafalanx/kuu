-- archive.lua -- pack/unpack through Windows tar; list through its Unicode archive library.
--
--   local archive = require "archive"
--   archive.unpack("build/zig.zip", ".tools/zig", { strip = 1 })    -- true | nil, err
--   archive.pack("build/out.zip", "build/stage")                    -- the directory's contents
--   archive.pack("build/src.tar.gz", ".", { "src", "Makefile" })    -- named entries, relative to the directory
--   archive.list("build/zig.zip")                                   -- { "zig-x86_64-windows-0.16.0/", ... } | nil, err
--
-- The format follows the archive's extension: .zip, .tar, .tar.gz or .tgz,
-- .tar.xz, .tar.zst, .tar.bz2.  Windows' bsdtar refuses entries that would
-- climb out of the target directory.  Nothing else is assumed on the machine.
global none
global <const> require, ipairs, tostring, type, math, os, error

local fs = require "fs"
local proc = require "proc"
local err = require "err"
local rt, json = require "rt", require "json"

-- Read Unicode names in a supervised copy of this same executable. Windows
-- tar's text listing has already replaced names outside its ANSI code page.
-- The native reader is private and synchronous; isolating it preserves the
-- caller's scheduler, deadline, and process-tree cleanup on corrupt inputs.
local list_worker = [[
local entries, e = require("_archive")(...)
local json = require "json"
if entries then
  io.write(json.encode { ok = true, entries = json.array(entries) })
else
  io.write(json.encode { ok = false, code = e.code, message = e.message })
  os.exit(1)
end
]]

local archive = {}

local function tar_exe()
  local root = (os.getenv("SystemRoot") or "C:\\Windows"):gsub("\\", "/")
  local exe = root .. "/System32/tar.exe"
  if fs.exists(exe) ~= "file" then
    return nil, err.new("ARCHIVE", "oserror", "Windows' tar.exe is not at " .. exe)
  end
  return exe
end

local function windows_path(path)
  return (fs.absolute(path):gsub("/", "\\"))
end

local function run_tar(args, timeout)
  local tar, e = tar_exe()
  if not tar then return nil, e end
  local argv = { tar }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  argv.timeout = timeout or "30m"
  local r, e2 = proc.run(argv)
  if not r then return nil, e2 end
  if r.status ~= "exit" then return nil, err.new("ARCHIVE", r.status, "tar did not finish: " .. r.status) end
  if r.code ~= 0 then
    local said = r.err:gsub("%s+$", ""):gsub("^tar%.exe: ", ""):gsub("\r?\ntar%.exe: ", "; ")
    return nil, err.new("ARCHIVE", "failed", said ~= "" and said or ("tar exited " .. r.code))
  end
  return r
end

local function check_strip(strip)
  if strip ~= nil and (math.type(strip) ~= "integer" or strip < 0) then
    error(err.new("ARCHIVE", "badvalue", "strip must be a non-negative integer"), 3)
  end
end

-- archive.unpack(file, dir [, { strip = n, timeout = "30m" }]) -> true | nil, err
-- The directory is created if needed; existing files are overwritten.
function archive.unpack(file, dir, options)
  options = options or {}
  if type(file) ~= "string" or type(dir) ~= "string" then
    error(err.new("ARCHIVE", "badvalue", "unpack needs an archive path and a directory"), 2)
  end
  check_strip(options.strip)
  if fs.exists(file) ~= "file" then return nil, err.new("ARCHIVE", "notfound", "no archive at '" .. file .. "'") end
  local made, e = fs.mkdir(dir)
  if not made then return nil, e end
  local args = { "-xf", windows_path(file), "-C", windows_path(dir) }
  if options.strip ~= nil and options.strip > 0 then
    args[#args + 1] = "--strip-components"
    args[#args + 1] = tostring(options.strip)
  end
  local r, e2 = run_tar(args, options.timeout)
  if not r then return nil, e2 end
  return true
end

-- archive.pack(file, dir [, entries [, { timeout = "30m" }]]) -> true | nil, err
-- Packs the named entries of `dir`, or everything in it, into `file`, whose
-- extension chooses the format.  An existing archive is replaced.
function archive.pack(file, dir, entries, options)
  options = options or {}
  if type(file) ~= "string" or type(dir) ~= "string" then
    error(err.new("ARCHIVE", "badvalue", "pack needs an archive path and a directory"), 2)
  end
  if fs.exists(dir) ~= "directory" then return nil, err.new("ARCHIVE", "notfound", "no directory at '" .. dir .. "'") end
  if entries == nil then
    local listing, e = fs.list(dir)
    if not listing then return nil, e end
    entries = {}
    for _, entry in ipairs(listing.entries) do entries[#entries + 1] = entry.name end
    if #entries == 0 then return nil, err.new("ARCHIVE", "badvalue", "'" .. dir .. "' is empty; nothing to pack") end
  end
  for _, name in ipairs(entries) do
    if type(name) ~= "string" or name == "" or name:match("^[/\\]") or name:match("^%a:") or name:find("..", 1, true) then
      error(err.new("ARCHIVE", "badvalue", "entries must be relative names inside the directory, got " .. tostring(name)), 2)
    end
  end
  local parent = fs.absolute(file):match("^(.*)/[^/]+$")
  if parent ~= nil then
    local made, e = fs.mkdir(parent)
    if not made then return nil, e end
  end
  fs.remove(file)
  -- "--" keeps an entry named like an option, "--help" say, an entry
  local args = { "-a", "-cf", windows_path(file), "-C", windows_path(dir) }
  if file:lower():match("%.zip$") then
    -- Windows tar defaults ZIP headers to ANSI and silently loses names.
    args[#args + 1] = "--options"
    args[#args + 1] = "zip:hdrcharset=UTF-8"
  end
  args[#args + 1] = "--"
  for _, name in ipairs(entries) do args[#args + 1] = name end
  local r, e2 = run_tar(args, options.timeout)
  if not r then return nil, e2 end
  return true
end

-- archive.list(file [, { timeout = "30m" }]) -> { entry, ... } | nil, err
function archive.list(file, options)
  options = options or {}
  if type(file) ~= "string" then error(err.new("ARCHIVE", "badvalue", "list needs an archive path"), 2) end
  if fs.exists(file) ~= "file" then return nil, err.new("ARCHIVE", "notfound", "no archive at '" .. file .. "'") end
  local r, e = proc.run { rt.exe, "-e", list_worker, fs.absolute(file),
    timeout = options.timeout or "30m", maxout = "64M" }
  if not r then return nil, e end
  if r.status ~= "exit" then return nil, err.new("ARCHIVE", r.status, "archive listing did not finish: " .. r.status) end
  if r.truncated then return nil, err.new("ARCHIVE", "toobig", "archive listing exceeds 64 MiB") end
  local record = json.decode(r.out)
  if not record then return nil, err.new("ARCHIVE", "failed", "archive reader failed: " .. r.err) end
  if not record.ok then return nil, err.new("ARCHIVE", record.code, record.message) end
  if r.code ~= 0 then return nil, err.new("ARCHIVE", "failed", "archive reader exited " .. r.code) end
  return record.entries
end

return archive
