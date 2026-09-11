-- csv.lua -- comma-separated values as RFC 4180 has them, and the variants
-- Windows tools write: other separators, CRLF or LF, a leading BOM.
--
--   local csv = require "csv"
--   local rows = csv.decode(text)                       -- { { "a", "b" }, { "1", "2" } }
--   local recs = csv.decode(text, { header = true })    -- { { a = "1", b = "2" } }, recs.columns = { "a", "b" }
--   csv.decode(text, { separator = ";" })               -- Excel in many locales; "\t" for TSV
--   csv.encode(rows)                                    -- CRLF line ends, quotes only where needed
--   csv.encode(recs, { columns = { "a", "b" } })        -- records: a header row, then each record's fields
--   csv.encode(rows, { separator = ";", bom = true })   -- Excel opens it as UTF-8
--
-- Every field decodes as a string; nothing guesses at numbers.  Quoted
-- fields may hold separators, quotes (doubled), and line ends.  Blank lines
-- are skipped.  A quote where none may be is CSV parse with the line.
global none
global <const> require, ipairs, tostring, type, table, error

local err = require "err"

local csv = {}

local function option(opts, name, default)
  if opts == nil or opts[name] == nil then return default end
  return opts[name]
end

local function check_separator(sep)
  if type(sep) ~= "string" or #sep ~= 1 or sep == '"' or sep == "\r" or sep == "\n" then
    error(err.new("CSV", "badvalue", "the separator must be one character other than a quote or a line end"), 3)
  end
  return sep
end

-- csv.decode(text [, { separator = ",", header = false, ragged = false }]) -> rows | nil, err
function csv.decode(text, opts)
  if type(text) ~= "string" then error(err.new("CSV", "badvalue", "decode wants a string"), 2) end
  local sep = check_separator(option(opts, "separator", ","))
  local header = option(opts, "header", false)
  local ragged = option(opts, "ragged", false)
  if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end

  local rows, field = {}, {}
  local quoted = false
  local pos, n, line = 1, #text, 1
  local function finish_field(s) field[#field + 1] = s end
  local function finish_row()
    if #field == 1 and field[1] == "" and not quoted then
      field = {} -- a blank line
      return
    end
    rows[#rows + 1] = field
    field = {}
    quoted = false
  end
  while pos <= n do
    local c = text:sub(pos, pos)
    if c == '"' then
      quoted = true
      -- a quoted field: up to the closing quote, "" is one quote
      local parts, at = {}, pos + 1
      while true do
        local q = text:find('"', at, true)
        if q == nil then
          return nil, err.new("CSV", "parse", "unterminated quoted field starting at line " .. line)
        end
        parts[#parts + 1] = text:sub(at, q - 1)
        if text:sub(q + 1, q + 1) == '"' then
          parts[#parts + 1] = '"'
          at = q + 2
        else
          at = q + 1
          break
        end
      end
      local value = table.concat(parts)
      local _, breaks = value:gsub("\n", "")
      finish_field(value)
      pos = at
      local nxt = text:sub(pos, pos)
      if nxt == sep then
        pos = pos + 1
        if pos > n then finish_field("") end
      elseif nxt == "\r" or nxt == "\n" or nxt == "" then
        if nxt == "\r" and text:sub(pos + 1, pos + 1) == "\n" then pos = pos + 1 end
        pos = pos + 1
        finish_row()
        line = line + 1
      else
        return nil, err.new("CSV", "parse", "text after a closing quote at line " .. line)
      end
      line = line + breaks
    else
      -- a plain field: up to the separator or the line end; no quotes allowed inside
      local stop = text:find("[" .. (sep == "]" and "%]" or sep == "%" and "%%" or sep == "^" and "%^" or sep == "-" and "%-" or sep) .. "\r\n]", pos)
      local value = text:sub(pos, (stop or n + 1) - 1)
      if value:find('"', 1, true) then
        return nil, err.new("CSV", "parse", "a quote inside an unquoted field at line " .. line)
      end
      finish_field(value)
      if stop == nil then
        pos = n + 1
        finish_row()
      else
        local at = text:sub(stop, stop)
        if at == sep then
          pos = stop + 1
          if pos > n then finish_field("") finish_row() end
        else
          if at == "\r" and text:sub(stop + 1, stop + 1) == "\n" then stop = stop + 1 end
          pos = stop + 1
          finish_row()
          line = line + 1
        end
      end
    end
  end
  if #field > 0 then finish_row() end

  if not header then
    if not ragged then
      local width = rows[1] and #rows[1]
      for i, r in ipairs(rows) do
        if #r ~= width then
          return nil, err.new("CSV", "parse", "row " .. i .. " has " .. #r .. " fields, the first row has " .. width)
        end
      end
    end
    return rows
  end
  local columns = rows[1]
  if columns == nil then return nil, err.new("CSV", "parse", "no header row") end
  local records = { columns = columns }
  for i = 2, #rows do
    local r = rows[i]
    if #r ~= #columns and not ragged then
      return nil, err.new("CSV", "parse", "row " .. i .. " has " .. #r .. " fields, the header has " .. #columns)
    end
    local rec = {}
    for k, name in ipairs(columns) do rec[name] = r[k] end
    records[#records + 1] = rec
  end
  return records
end

local function field_text(v, sep)
  local t = type(v)
  local s
  if v == nil then s = ""
  elseif t == "string" then s = v
  elseif t == "number" or t == "boolean" then s = tostring(v)
  else error(err.new("CSV", "badvalue", "a field must be a string, number, boolean, or nil, not " .. t), 3) end
  if s:find('[' .. (sep == "]" and "%]" or sep == "%" and "%%" or sep == "^" and "%^" or sep == "-" and "%-" or sep) .. '"\r\n]') or s:match("^%s") or s:match("%s$") then
    s = '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

-- One empty field is a record; an empty physical line is not.
local function row_text(cells, sep)
  if #cells == 1 and cells[1] == "" then return '""' end
  return table.concat(cells, sep)
end

-- csv.encode(rows [, { separator = ",", columns = nil, header = true, bom = false, newline = "\r\n" }]) -> text
--   rows are arrays of fields, or records when `columns` (or rows.columns) names the fields
function csv.encode(rows, opts)
  if type(rows) ~= "table" then error(err.new("CSV", "badvalue", "encode wants a list of rows"), 2) end
  local sep = check_separator(option(opts, "separator", ","))
  local columns = option(opts, "columns", rows.columns)
  local header = option(opts, "header", true)
  local newline = option(opts, "newline", "\r\n")
  local out = {}
  if columns ~= nil then
    if header then
      local cells = {}
      for i, name in ipairs(columns) do cells[i] = field_text(name, sep) end
      out[#out + 1] = row_text(cells, sep)
    end
    for _, rec in ipairs(rows) do
      local cells = {}
      for i, name in ipairs(columns) do cells[i] = field_text(rec[name], sep) end
      out[#out + 1] = row_text(cells, sep)
    end
  else
    for i, row in ipairs(rows) do
      if type(row) ~= "table" then error(err.new("CSV", "badvalue", "row " .. i .. " is not a table"), 2) end
      local cells = {}
      for k = 1, #row do cells[k] = field_text(row[k], sep) end
      out[#out + 1] = row_text(cells, sep)
    end
  end
  local text = table.concat(out, newline) .. (#out > 0 and newline or "")
  if option(opts, "bom", false) then text = "\239\187\191" .. text end
  return text
end

return csv
