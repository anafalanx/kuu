-- mem.lua -- a small memory across runs: one JSON file per project.
--
--   local mem = require "mem"
--   mem.set("last_build", { at = os.time(), ok = true })   -- any value JSON can hold
--   mem.get("last_build")                                   -- nil when absent
--   mem.get("runs", 0)                                      -- with a default
--   mem.forget("last_build")
--   mem.keys()                                              -- sorted
--   mem.all()                                               -- a copy of everything
--   mem.path()                                              -- where it lives
--   mem.open("build/state.json")                            -- somewhere else instead
--
-- The file is .kuu/memory.json under the project root, the nearest tasks.lua
-- upward from the current directory, or under the directory `require`
-- searches when there is no project.  Every read goes to the file and every
-- set reads, merges, and writes it atomically, so two kuu processes take
-- turns rather than overwrite each other.  The whole file may not exceed
-- 1 MiB: this is a notebook, never a database.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, error, pcall

local fs = require "fs"
local json = require "json"
local err = require "err"
local rt = require "rt"
local project = require "project"

local mem = {}

mem.LIMIT = 1024 * 1024

local location

local function default_path()
  local root = project.find() or rt.root()
  return fs.join(root, ".kuu", "memory.json")
end

-- mem.open(path) -> the absolute path now in use
function mem.open(path)
  if type(path) ~= "string" or path == "" then error(err.new("MEM", "badvalue", "open needs a path"), 2) end
  location = fs.absolute(path)
  return location
end

function mem.path()
  if location == nil then location = fs.absolute(default_path()) end
  return location
end

local function load()
  local path = mem.path()
  if not fs.exists(path) then return {} end
  local text, e = fs.read(path, { encoding = "utf-8", maxbytes = tostring(mem.LIMIT) .. "B" })
  if not text then error(err.new("MEM", "unreadable", "cannot read " .. path .. ": " .. tostring(e))) end
  local data, e2 = json.decode(text)
  if type(data) ~= "table" or json.is_array(data) then
    error(err.new("MEM", "corrupt", path .. " is not a JSON object" .. (e2 and (": " .. tostring(e2)) or "")))
  end
  return data
end

local function store(data)
  local path = mem.path()
  local ok, text = pcall(json.encode, data, { pretty = true })
  if not ok then return nil, err.new("MEM", "badvalue", "the value cannot be kept as JSON: " .. tostring(text)) end
  text = text .. "\n"
  if #text > mem.LIMIT then
    return nil, err.new("MEM", "toobig", string.format("the memory would be %d bytes, the limit is %d", #text, mem.LIMIT))
  end
  local made, e = fs.mkdir(fs.dirname(path))
  if not made then return nil, e end
  return fs.write(path, text)
end

local function check_key(key)
  if type(key) ~= "string" or key == "" then error(err.new("MEM", "badvalue", "keys are non-empty strings"), 3) end
end

-- mem.get(key [, default]) -> the value, or default (nil) when absent
function mem.get(key, default)
  check_key(key)
  local value = load()[key]
  if value == nil then return default end
  return value
end

-- mem.set(key, value) -> true | nil, err.  A nil value forgets the key.
function mem.set(key, value)
  check_key(key)
  local data = load()
  data[key] = value
  return store(data)
end

-- mem.forget(key) -> true | nil, err
function mem.forget(key)
  check_key(key)
  local data = load()
  if data[key] == nil then return true end
  data[key] = nil
  return store(data)
end

function mem.keys()
  local keys = {}
  for k in pairs(load()) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function mem.all()
  return load()
end

return mem
