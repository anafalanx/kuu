-- _scan_policy.lua -- declarative observation scope, loaded before project
-- code runs and retained for one operation. No manifest execution or cache.
global none
global <const> require, ipairs, pairs, type, tostring, table, string, utf8

local fs, json, err, hash = require "fs", require "json", require "err", require "hash"

local policy = {}
policy.FILE = "kuu.config.json"
policy.MAX_RULES = 256 -- each original array, before deduplication
policy.MAX_BYTES = 1048576

local mandatory = { ".git", ".kuu" }
local defaults = { ".cache", ".local", ".tools", ".venv", "__pycache__", "build", "node_modules" }
local top_keys = { v = true, scan = true }
local scan_keys = { defaults = true, exclude_dirs = true, exclude_paths = true }
local ascii_lower = {}
for code = 65, 90 do ascii_lower[string.char(code)] = string.char(code + 32) end

local function failure(source, field, message)
  return nil, err.new("SCAN", "config", source .. ": " .. field .. ": " .. message)
end

-- Match the native walker's ASCII convention, without locale-dependent
-- string.lower or a claim to implement Windows Unicode case equivalence.
local function fold(value)
  return (value:gsub("[A-Z]", ascii_lower))
end

local function object(value, allowed, source, field)
  if type(value) ~= "table" or json.is_array(value) then
    return failure(source, field, "expected a JSON object")
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    if not allowed[key] then return failure(source, field, "unknown key '" .. key .. "'") end
  end
  return true
end

local function units(value)
  -- JSON has already validated UTF-8. Count in native loops; a Lua callback
  -- per character adds noticeable cost near the configuration byte limit.
  local count = utf8.len(value)
  if count == #value then return count end -- all ASCII
  local _, supplementary = value:gsub("[\240-\244]", "") -- four-byte lead bytes
  return count + supplementary
end

local function component(value)
  if value == "" then return "empty directory components are not allowed" end
  if value == "." or value == ".." then return "'.' and '..' components are not allowed" end
  if value:find('[%z\1-\31<>:"|]') then return "invalid character in a directory component" end
  if value:find("[*?%[%]]") then return "wildcards are not supported; use an exact directory name" end
  if value:find("[ .]$") then return "a directory component must not end in a dot or space" end
  if units(value) > 255 then return "a directory component exceeds 255 UTF-16 code units" end
  -- Device names remain reserved when followed by an extension. The space
  -- trim also rejects an ambiguous device stem such as 'CON .txt'.
  local stem = (value:match("^[^.]+") or value):gsub(" +$", "")
  if #stem > 7 then return end -- every reserved stem below is shorter
  stem = fold(stem)
  if stem == "con" or stem == "prn" or stem == "aux" or stem == "nul"
      or stem == "conin$" or stem == "conout$" or stem:match("^com[1-9]$") or stem:match("^lpt[1-9]$") then
    return "reserved DOS device name in a directory component"
  end
  local port, digit = stem:sub(1, 3), stem:sub(4)
  if (port == "com" or port == "lpt") and (digit == "¹" or digit == "²" or digit == "³") then
    return "reserved DOS device name in a directory component"
  end
end

local function normalize_rule(value, is_path, source, field)
  if type(value) ~= "string" then return failure(source, field, "expected a string") end
  -- JSON decoding has already established valid UTF-8. Do not use fs.absolute
  -- here: it would erase traversal components before they can be rejected.
  value = value:gsub("\\", "/")
  if not is_path and value:find("/", 1, true) then
    return failure(source, field, "expected one basename, without path separators")
  end
  if is_path and (value:sub(1, 1) == "/" or value:find(":", 1, true)) then
    return failure(source, field, "expected a project-relative path, without a drive, root or stream")
  end
  if value == "" or value:sub(-1) == "/" or value:find("//", 1, true) then
    return failure(source, field, "empty directory components are not allowed")
  end
  if units(value) > 32760 then return failure(source, field, "relative path exceeds 32760 UTF-16 code units") end
  for part in value:gmatch("[^/]+") do
    local why = component(part)
    if why then return failure(source, field, why) end
  end
  return fold(value)
end

local function rules(value, is_path, source, field, limit)
  limit = limit or policy.MAX_RULES
  if value == nil then return json.array {} end
  if type(value) ~= "table" or not json.is_array(value) then
    return failure(source, field, "expected a JSON array of strings")
  end
  if #value > limit then
    return failure(source, field, "at most " .. limit .. " rules are allowed before deduplication")
  end
  local result, seen = json.array {}, {}
  for i, raw in ipairs(value) do
    local name, why = normalize_rule(raw, is_path, source, field .. "[" .. i .. "]")
    if not name then return nil, why end
    if not seen[name] then result[#result + 1], seen[name] = name, true end
  end
  table.sort(result)
  return result
end

local function copy(values)
  local result = json.array {}
  for _, value in ipairs(values) do result[#result + 1] = value end
  return result
end

local function normalize(config, source, kind)
  local ok, why = object(config, top_keys, source, "configuration")
  if not ok then return nil, why end
  if config.v ~= 1 then return failure(source, "v", "expected configuration version 1") end
  local scan = config.scan
  if scan == nil then scan = {} end
  ok, why = object(scan, scan_keys, source, "scan")
  if not ok then return nil, why end
  local enabled = scan.defaults
  if enabled == nil then enabled = true end
  if type(enabled) ~= "boolean" then return failure(source, "scan.defaults", "expected a boolean") end
  local dirs, dir_error = rules(scan.exclude_dirs, false, source, "scan.exclude_dirs")
  if not dirs then return nil, dir_error end
  local paths, path_error = rules(scan.exclude_paths, true, source, "scan.exclude_paths")
  if not paths then return nil, path_error end
  local base = enabled and copy(defaults) or json.array {}
  local effective, seen = json.array {}, {}
  for _, list in ipairs { mandatory, base, dirs } do
    for _, name in ipairs(list) do
      if not seen[name] then effective[#effective + 1], seen[name] = name, true end
    end
  end
  table.sort(effective)
  -- Fingerprint only the normalized scope, independent of root, provenance,
  -- order, repeated entries or spelling. This describes scope, not tree state.
  local canonical = json.encode(json.object {
    { "v", 1 }, { "dirs", effective }, { "paths", paths },
  })
  return {
    v = 1, defaults = enabled, exclude_dirs = dirs, exclude_paths = paths,
    mandatory_dirs = copy(mandatory), default_dirs = base, effective_dirs = effective,
    canonical = canonical, fingerprint = hash.sum("sha256", canonical),
    source = { kind = kind, path = source },
  }
end

-- decode(text [, source]) -> fresh normalized policy | nil, SCAN config.
-- This entry point validates fixture text without reading any project code.
function policy.decode(text, source)
  source = source or policy.FILE
  if type(text) ~= "string" then return failure(source, "configuration", "expected UTF-8 JSON text") end
  if #text > policy.MAX_BYTES then return failure(source, "configuration", "file exceeds 1048576 bytes (1 MiB)") end
  if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
  local config, why = json.decode(text)
  if config == nil then return failure(source, "configuration", tostring(why)) end
  return normalize(config, source, "file")
end

-- load(root) -> fresh policy (including absolute root) | nil, SCAN config.
-- An invocation can retain this result before running a manifest. No cache:
-- later operations get the current file, while the existing result stays put.
function policy.load(root)
  root = fs.absolute(root)
  local source = fs.join(root, policy.FILE)
  local text, why = fs.read(source, { encoding = "utf-8", maxbytes = policy.MAX_BYTES })
  local result, config_error
  if text == nil then
    if err.is(why, "FS", "notfound") then
      -- Only true absence means defaults. A dangling config link or a
      -- nonexistent/unreadable project root must not hide a broken setup.
      local kind = fs.exists(source)
      local parent = kind == false and fs.stat(root) or nil
      if parent and parent.kind == "directory" then
        result = normalize({ v = 1 }, source, "default")
      end
    end
    if result == nil then return failure(source, "configuration", "cannot read configuration: " .. tostring(why)) end
  else
    -- The UTF-8 reader already removed one leading BOM. Do not let decode
    -- remove a second one and accept bytes its direct entry point refuses.
    if text:sub(1, 3) == "\239\187\191" then
      return failure(source, "configuration", "multiple leading UTF-8 BOMs are not allowed")
    end
    result, config_error = policy.decode(text, source)
    if not result then return nil, config_error end
  end
  result.root = root
  return result
end

return policy
