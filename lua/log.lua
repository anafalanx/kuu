-- log.lua -- say what happened, where someone can read it later.
--
--   local log = require "log"
--   log.info("built", { target = out, bytes = size })
--   log.warn("queue at 90%")
--   log.error("cannot open", { path = p, err = e })
--   log.debug("retrying", { attempt = n })
--   log.configure { level = "debug", file = "build/log.txt" }
--   log.configure { json = true }            -- one JSON object per line
--   log.configure { sink = function(line) ... end }
--   log.configure()                          -- the settings, and what was dropped
--
-- A line is: local time with milliseconds, the level, the message, then
-- key=value fields sorted by key, quoted when they need it.  Writing never
-- raises: a sink that fails increments `dropped`, because a diagnostic must
-- not terminate the work it describes.  The default sink is standard error,
-- resolved at write time.  Everything is validated before any of it is
-- applied, so a bad option leaves the previous configuration intact.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, io, os,
               pcall, math, error

local err = require "err"
local sched = require "sched"

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, off = 5 }
local NAMES = { "debug", "info", "warn", "error" }

local state = {
  level = LEVELS.info,
  level_name = "info",
  file = nil,        -- path, when a file sink is open
  handle = nil,      -- the open file
  sink = nil,        -- a function(line), when configured
  json = false,
  dropped = 0,
}

local log = {}

local function quote(v)
  if v == "" then return '""' end
  if v:find("[%s\"]") then
    return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
  end
  return v
end

local function render_value(v)
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "nil" then return "nil" end
  if t == "table" then
    if err.is(v) then return tostring(v) end
    local ok, json = pcall(require, "json")
    if ok then
      local encoded = json.encode(v)
      if encoded then return encoded end
    end
  end
  return tostring(v)
end

local function timestamp(now)
  local whole = math.floor(now)
  local ms = math.floor((now - whole) * 1000 + 0.5)
  if ms >= 1000 then whole, ms = whole + 1, 0 end
  return os.date("%Y-%m-%dT%H:%M:%S", whole) .. string.format(".%03d", ms)
end

local function sorted_keys(fields)
  local keys = {}
  for k in pairs(fields) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function format_text(level, message, fields, now)
  local parts = { timestamp(now), string.format("%-5s", level:upper()), message }
  local line = table.concat(parts, " ")
  if fields ~= nil then
    for _, k in ipairs(sorted_keys(fields)) do
      line = line .. " " .. k .. "=" .. quote(render_value(fields[k]))
    end
  end
  return line
end

local function format_json(level, message, fields, now)
  local json = require "json"
  local record = { ts = timestamp(now), level = level, msg = message }
  if fields ~= nil then
    for k, v in pairs(fields) do
      local key = tostring(k)
      if record[key] == nil then
        local vt = type(v)
        if vt == "string" or vt == "number" or vt == "boolean" then
          record[key] = v
        elseif vt == "table" and not err.is(v) then
          record[key] = v
        else
          record[key] = render_value(v)
        end
      end
    end
  end
  local ok, encoded = pcall(json.encode, record)
  if ok then return encoded end
  -- an unencodable field: fall back to text inside the JSON record
  return json.encode { ts = record.ts, level = level, msg = message, fields = format_text(level, "", fields, now) }
end

local function emit(line)
  if state.sink ~= nil then
    local ok = pcall(state.sink, line)
    return ok
  end
  local handle = state.handle
  if handle ~= nil then
    local ok = pcall(function() handle:write(line, "\n"); handle:flush() end)
    return ok
  end
  local ok = pcall(function() io.stderr:write(line, "\n") end)
  return ok
end

local function write(level, message, fields)
  if LEVELS[level] < state.level then return false end
  if type(message) ~= "string" then message = render_value(message) end
  if fields ~= nil and type(fields) ~= "table" then
    fields = { value = fields }
  end
  local now = sched.now()
  local line
  local ok, produced = pcall(state.json and format_json or format_text, level, message, fields, now)
  if ok then line = produced else line = format_text(level, message, nil, now) .. " fields=?" end
  if emit(line) then return true end
  state.dropped = state.dropped + 1
  return false
end

for _, name in ipairs(NAMES) do
  log[name] = function(message, fields) return write(name, message, fields) end
end

-- log.configure([options]) -> the settings
function log.configure(options)
  if options == nil then
    return {
      level = state.level_name,
      file = state.file,
      json = state.json,
      sink = state.sink ~= nil,
      dropped = state.dropped,
    }
  end
  if type(options) ~= "table" then
    error(err.new("LOG", "usage", "configure takes a table of options"))
  end
  -- validate everything first
  local staged = {}
  for k, v in pairs(options) do
    if k == "level" then
      if LEVELS[v] == nil then
        error(err.new("LOG", "badvalue", "unknown level '" .. tostring(v) .. "'; use debug, info, warn, error, or off"))
      end
      staged.level = v
    elseif k == "file" then
      if v ~= false and type(v) ~= "string" then
        error(err.new("LOG", "badvalue", "file must be a path or false"))
      end
      staged.file = v
    elseif k == "json" then
      staged.json = v and true or false
    elseif k == "sink" then
      if v ~= false and type(v) ~= "function" then
        error(err.new("LOG", "badvalue", "sink must be a function or false"))
      end
      staged.sink = v
    else
      error(err.new("LOG", "usage", "unknown option '" .. tostring(k) .. "'"))
    end
  end
  local new_handle
  if type(staged.file) == "string" then
    local handle, open_error = io.open(staged.file, "ab")
    if handle == nil then
      error(err.new("LOG", "oserror", "cannot open '" .. staged.file .. "' for appending: " .. tostring(open_error)))
    end
    new_handle = handle
  end
  -- then commit
  if staged.level ~= nil then
    state.level = LEVELS[staged.level]
    state.level_name = staged.level
  end
  if staged.json ~= nil then state.json = staged.json end
  if staged.sink ~= nil then
    state.sink = staged.sink or nil
  end
  if staged.file ~= nil then
    if state.handle ~= nil then pcall(function() state.handle:close() end) end
    if staged.file == false then
      state.handle, state.file = nil, nil
    else
      state.handle, state.file = new_handle, staged.file
    end
  end
  return log.configure()
end

return log
