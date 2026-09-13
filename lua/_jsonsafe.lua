-- _jsonsafe.lua -- strings in the door's reports are UTF-8 even when an
-- error or a description came from bytes in a Windows console code page.
-- Replace each invalid byte with U+FFFD, keeping the report's table shape
-- (including marked JSON arrays) intact.
global none
global <const> type, pairs, ipairs, utf8, table

local function utf8ify(s)
  local parts, from = {}, 1
  while true do
    local n, bad = utf8.len(s, from)
    if n then parts[#parts + 1] = s:sub(from) break end
    parts[#parts + 1] = s:sub(from, bad - 1) .. "\u{FFFD}"
    from = bad + 1
  end
  return table.concat(parts)
end

local function clean(value, seen)
  if type(value) == "string" then return utf8ify(value) end
  if type(value) == "table" then
    seen = seen or {}
    if seen[value] then return value end
    seen[value] = true
    local renamed = {}
    for k, v in pairs(value) do
      value[k] = clean(v, seen)
      if type(k) == "string" and utf8.len(k) == nil then renamed[#renamed + 1] = k end
    end
    -- Do not add keys during pairs traversal. Different byte spellings can
    -- repair to the same text; retain every entry with a numbered suffix
    -- rather than overwriting an existing name in the report.
    table.sort(renamed)
    for _, old in ipairs(renamed) do
      local name, suffix = utf8ify(old), 1
      local key = name
      while value[key] ~= nil do
        suffix = suffix + 1
        key = name .. " [" .. suffix .. "]"
      end
      value[key], value[old] = value[old], nil
    end
  end
  return value
end

return clean
