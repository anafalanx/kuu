-- ini.lua -- INI files as Windows has them: [sections], key=value, and
-- comment lines starting with ; or #.
--
--   local ini = require "ini"
--   local t = ini.decode(text)                -- { [""] = { top-level keys }, Section = { key = "value" } }
--   t.Section.key                             -- always a string; nothing guesses at numbers
--   ini.encode(t)                             -- sections and keys in sorted order, deterministic
--   ini.set(text, "Section", "key", "value")  -- the text with that one change, everything else untouched
--   ini.remove(text, "Section", "key")        -- without that key; without the whole section when key is nil
--   ini.get(t, "section", "KEY")              -- lookup ignoring case, as Windows does
--
-- decode and encode are for reading a file and writing one of your own.
-- set and remove are for editing a file that belongs to something else:
-- comments, order, spacing, and the line ending style survive, and section
-- and key names match ignoring case.  A line without = is a key with an
-- empty value.  Surrounding double quotes around a value are removed, as
-- the Windows profile functions do.  Inline comments are not a thing:
-- Windows keeps everything after = including a ; and so does this.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, error

local err = require "err"

local ini = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function unquote(v)
  if #v >= 2 and v:sub(1, 1) == '"' and v:sub(-1) == '"' then return v:sub(2, -2) end
  return v
end

local function lines_of(text)
  local newline = text:find("\r\n", 1, true) and "\r\n" or "\n"
  local list = {}
  local body = text
  if body:sub(-#newline) == newline then body = body:sub(1, -#newline - 1) end
  if body == "" then return list, newline, text ~= "" end
  for line in (body .. "\n"):gmatch("(.-)\r?\n") do list[#list + 1] = line end
  return list, newline, text:sub(-#newline) == newline
end

local function section_of(line)
  return trim(line):match("^%[(.-)%]$")
end

local function is_comment(line)
  local first = trim(line):sub(1, 1)
  return first == ";" or first == "#" or first == ""
end

-- ini.decode(text) -> sections
function ini.decode(text)
  if type(text) ~= "string" then error(err.new("INI", "badvalue", "decode wants a string"), 2) end
  if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
  local result = { [""] = {} }
  local current = result[""]
  local lines = lines_of(text)
  for _, line in ipairs(lines) do
    local name = section_of(line)
    if name ~= nil then
      current = result[name] or {}
      result[name] = current
    elseif not is_comment(line) then
      local key, value = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
      if key == nil then
        key, value = trim(line), ""
      end
      if key ~= "" then current[key] = unquote(value) end
    end
  end
  return result
end

local function value_text(v)
  local t = type(v)
  local s
  if t == "string" then s = v
  elseif t == "number" or t == "boolean" then s = tostring(v)
  else error(err.new("INI", "badvalue", "a value must be a string, number, or boolean, not " .. t), 3) end
  if s:find("[\r\n]") then error(err.new("INI", "badvalue", "a value cannot span lines"), 3) end
  if s ~= trim(s) or s:sub(1, 1) == ";" or s:sub(1, 1) == "#" then s = '"' .. s .. '"' end
  return s
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    if type(k) ~= "string" then error(err.new("INI", "badvalue", "keys and section names must be strings"), 3) end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- ini.encode(sections [, { newline = "\n" }]) -> text
function ini.encode(sections, opts)
  if type(sections) ~= "table" then error(err.new("INI", "badvalue", "encode wants a table of sections"), 2) end
  local newline = opts and opts.newline or "\n"
  local out = {}
  local names = sorted_keys(sections)
  for _, name in ipairs(names) do
    local body = sections[name]
    if type(body) ~= "table" then error(err.new("INI", "badvalue", "section '" .. name .. "' is not a table"), 2) end
    if name ~= "" then
      if #out > 0 then out[#out + 1] = "" end
      out[#out + 1] = "[" .. name .. "]"
    end
    for _, key in ipairs(sorted_keys(body)) do
      if key:find("[=\r\n]") or key:find("^%s*[%[;#]") then error(err.new("INI", "badvalue", "'" .. key .. "' cannot be a key"), 2) end
      out[#out + 1] = key .. "=" .. value_text(body[key])
    end
  end
  return #out > 0 and table.concat(out, newline) .. newline or ""
end

-- ini.get(sections, section, key) -> value | nil, ignoring case in both names
function ini.get(sections, section, key)
  local body
  for name, b in pairs(sections) do
    if type(name) == "string" and name:lower() == (section or ""):lower() then body = b break end
  end
  if body == nil or key == nil then return body end
  for k, v in pairs(body) do
    if type(k) == "string" and k:lower() == key:lower() then return v end
  end
  return nil
end

-- the line range [first, last] of a section, or nil; the header line index, or 0 for the top level
local function locate(lines, section)
  local wanted = (section or ""):lower()
  local header, first, last
  if wanted == "" then
    header, first = 0, 1
  end
  for i, line in ipairs(lines) do
    local name = section_of(line)
    if name ~= nil then
      if first ~= nil then last = i - 1 break end
      if name:lower() == wanted then header, first = i, i + 1 end
    end
  end
  if first == nil then return nil end
  return header, first, last or #lines
end

local function key_line(lines, first, last, key)
  for i = first, last do
    local line = lines[i]
    if not is_comment(line) and section_of(line) == nil then
      local k = line:match("^%s*(.-)%s*=") or trim(line)
      if k:lower() == key:lower() then return i end
    end
  end
  return nil
end

-- ini.set(text, section, key, value) -> text
function ini.set(text, section, key, value)
  if type(text) ~= "string" then error(err.new("INI", "badvalue", "set wants the file's text"), 2) end
  if type(key) ~= "string" or key == "" or key:find("[=\r\n]") then error(err.new("INI", "badvalue", "a key must be a non-empty string without ="), 2) end
  local rendered = value_text(value)
  local lines, newline, had_final = lines_of(text)
  local header, first, last = locate(lines, section)
  if header == nil then
    -- a new section at the end
    if #lines > 0 and trim(lines[#lines]) ~= "" then lines[#lines + 1] = "" end
    lines[#lines + 1] = "[" .. section .. "]"
    lines[#lines + 1] = key .. "=" .. rendered
    had_final = true
  else
    local at = key_line(lines, first, last, key)
    if at ~= nil then
      local prefix, name, sep = lines[at]:match("^(%s*)(.-)(%s*=%s*)")
      if prefix == nil then prefix, name, sep = lines[at]:match("^(%s*)(.-)%s*$"), nil, "=" end
      lines[at] = prefix .. (name or key) .. sep .. rendered
    else
      -- after the section's last non-blank line, so blank lines before the next header stay where they are
      local insert = last
      while insert >= first and trim(lines[insert]) == "" do insert = insert - 1 end
      table.insert(lines, insert + 1, key .. "=" .. rendered)
    end
  end
  return table.concat(lines, newline) .. ((had_final or text == "") and newline or "")
end

-- ini.remove(text, section [, key]) -> text
function ini.remove(text, section, key)
  if type(text) ~= "string" then error(err.new("INI", "badvalue", "remove wants the file's text"), 2) end
  local lines, newline, had_final = lines_of(text)
  local header, first, last = locate(lines, section)
  if header == nil then return text end
  if key == nil then
    if header == 0 then
      for _ = first, last do table.remove(lines, first) end
    else
      -- the header, its lines, and one blank line before the next section
      local stop = last
      for _ = header, stop do table.remove(lines, header) end
      while lines[header] ~= nil and trim(lines[header]) == "" and header > 1 and trim(lines[header - 1]) == "" do table.remove(lines, header) end
    end
  else
    local at = key_line(lines, first, last, key)
    if at == nil then return text end
    table.remove(lines, at)
  end
  if #lines == 0 then return "" end
  return table.concat(lines, newline) .. (had_final and newline or "")
end

return ini
