-- archive.lua -- zip and tar archives, through the tar.exe every supported Windows ships.
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
global <const> require, ipairs, tostring, type, string, table, math, os, error

local fs = require "fs"
local proc = require "proc"
local err = require "err"

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
  local args = { "-a", "-cf", windows_path(file), "-C", windows_path(dir) }
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
  local r, e = run_tar({ "-tf", windows_path(file) }, options.timeout)
  if not r then return nil, e end
  local entries = {}
  for line in r.out:gmatch("[^\r\n]+") do entries[#entries + 1] = line end
  return entries
end

return archive
