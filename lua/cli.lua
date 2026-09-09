-- cli.lua -- declare a program's arguments once.
--
--   local cli = require "cli"
--   local spec = {
--     { "--interval", type = "duration", default = "2s", help = "refresh interval" },
--     { "--format",   type = "string", default = "text", choices = { "text", "json" } },
--     { "--all",      type = "flag", help = "show everything" },
--     { "dir",        type = "string", default = ".", help = "directory to watch" },
--     { "files",      type = "string", rest = true, help = "files to process" },
--   }
--   local opts, e = cli.parse(rt.args, spec)     -- opts.interval (ms), opts.format, opts.all, opts.dir, opts.files
--   if not opts then io.stderr:write(tostring(e), "\n"); os.exit(2) end
--   if opts.help then io.write(cli.usage(spec, "watchit")); return end
--
-- The spec is an array, so positionals take declaration order.  A name
-- starting with `--` is an option; anything else is positional.  Types are
-- flag, string, int, number, duration (to milliseconds), and size (to bytes).
-- Parsing never prints and never exits: `--help` comes back as `opts.help`,
-- and a wrong command line is `nil, err` with CLI usage whose message ends
-- with the generated usage text.  A wrong spec raises CLI badvalue at once,
-- so a broken declaration cannot lie dormant until an option is used.
global none
global <const> require, ipairs, pairs, tostring, tonumber, type, string, table, math, error, select

local err = require "err"

local cli = {}

local ATTRIBUTES = { type = true, default = true, min = true, max = true, choices = true, help = true, required = true, rest = true }
local TYPES = { flag = true, string = true, int = true, number = true, duration = true, size = true }

local function bad(message)
  error(err.new("CLI", "badvalue", message))
end

-- Durations and sizes, the same grammar as the runtime's options.
local function parse_duration(text)
  if type(text) == "number" then
    if text < 0 then return nil end
    return math.floor(text * 1000 + 0.5)
  end
  local number, unit = tostring(text):match("^(%d+%.?%d*)(%a+)$")
  if number == nil then return nil end
  local scale = ({ ms = 1, s = 1000, m = 60000, h = 3600000 })[unit]
  if scale == nil then return nil end
  return math.floor(tonumber(number) * scale + 0.5)
end

local function parse_size(text)
  if type(text) == "number" then
    if text < 0 or math.type(text) ~= "integer" then return nil end
    return text
  end
  local number, unit = tostring(text):match("^(%d+%.?%d*)(%a*)$")
  if number == nil then return nil end
  unit = unit:upper():gsub("B$", "")
  local scale = ({ [""] = 1, K = 1024, M = 1024 * 1024, G = 1024 * 1024 * 1024 })[unit]
  if scale == nil then return nil end
  return math.floor(tonumber(number) * scale + 0.5)
end

cli.duration = parse_duration
cli.size = parse_size

-- Convert and check one value against an entry.  Returns value | nil, message.
local function convert(entry, raw)
  local t = entry.type
  local value
  if t == "flag" then
    if raw == true or raw == false then value = raw
    elseif raw == "true" or raw == "1" or raw == "yes" or raw == "on" then value = true
    elseif raw == "false" or raw == "0" or raw == "no" or raw == "off" then value = false
    else return nil, entry.name .. " needs a boolean, got '" .. tostring(raw) .. "'" end
  elseif t == "string" then
    value = tostring(raw)
  elseif t == "int" then
    value = math.tointeger(tonumber(raw))
    if value == nil then return nil, entry.name .. " needs a whole number, got '" .. tostring(raw) .. "'" end
  elseif t == "number" then
    value = tonumber(raw)
    if value == nil then return nil, entry.name .. " needs a number, got '" .. tostring(raw) .. "'" end
  elseif t == "duration" then
    value = parse_duration(raw)
    if value == nil then return nil, entry.name .. " needs a duration such as 30s or 250ms, got '" .. tostring(raw) .. "'" end
  elseif t == "size" then
    value = parse_size(raw)
    if value == nil then return nil, entry.name .. " needs a size such as 16M, got '" .. tostring(raw) .. "'" end
  end
  if entry.min ~= nil and value < entry.min then
    return nil, entry.name .. " must be at least " .. tostring(entry.min) .. ", got " .. tostring(value)
  end
  if entry.max ~= nil and value > entry.max then
    return nil, entry.name .. " must be at most " .. tostring(entry.max) .. ", got " .. tostring(value)
  end
  if entry.choices ~= nil then
    local found = false
    for _, choice in ipairs(entry.choices) do if choice == value then found = true break end end
    if not found then
      return nil, entry.name .. " must be one of " .. table.concat(entry.choices, ", ") .. ", got '" .. tostring(raw) .. "'"
    end
  end
  return value
end

-- Normalise and check a spec: returns { entries = ordered list, options = by name, positionals = ordered }.
local function normalise(spec)
  if type(spec) ~= "table" then bad("the spec must be an array of entries") end
  local norm = { entries = {}, options = {}, positionals = {}, keys = {} }
  for i, raw in ipairs(spec) do
    if type(raw) ~= "table" or type(raw[1]) ~= "string" then
      bad("entry " .. i .. " must be a table whose first element is the name")
    end
    local entry = { name = raw[1] }
    for k, v in pairs(raw) do
      if k ~= 1 then
        if not ATTRIBUTES[k] then bad("unknown attribute '" .. tostring(k) .. "' for '" .. entry.name .. "'") end
        entry[k] = v
      end
    end
    entry.type = entry.type or "string"
    if not TYPES[entry.type] then bad("unknown type '" .. tostring(entry.type) .. "' for '" .. entry.name .. "'") end
    entry.is_option = entry.name:sub(1, 2) == "--"
    if entry.name == "--help" then bad("--help is provided by the parser") end
    if entry.name == "--" or entry.name == "" then bad("'" .. entry.name .. "' is not a name") end
    entry.key = entry.is_option and entry.name:sub(3) or entry.name
    if norm.keys[entry.key] then bad("'" .. entry.name .. "' collides with another entry on the key '" .. entry.key .. "'") end
    norm.keys[entry.key] = true
    if not entry.is_option and entry.type == "flag" then bad("'" .. entry.name .. "' is positional and cannot be a flag") end
    if entry.rest and entry.is_option then bad("'" .. entry.name .. "' is an option and cannot take the rest") end
    if entry.rest and entry.type == "flag" then bad("a rest entry cannot be a flag") end
    if (entry.min ~= nil or entry.max ~= nil) and entry.type ~= "int" and entry.type ~= "number"
        and entry.type ~= "duration" and entry.type ~= "size" then
      bad("min and max for '" .. entry.name .. "' need a numeric type")
    end
    if entry.min ~= nil and entry.max ~= nil and entry.min > entry.max then bad("min exceeds max for '" .. entry.name .. "'") end
    if entry.choices ~= nil then
      if type(entry.choices) ~= "table" or #entry.choices == 0 then bad("choices for '" .. entry.name .. "' must be a non-empty array") end
      if entry.type == "flag" then bad("'" .. entry.name .. "' is a flag and cannot declare choices") end
    end
    if entry.default ~= nil then
      local value, message = convert(entry, entry.default)
      if value == nil then bad("the default for '" .. entry.name .. "' fails its own type: " .. message) end
      entry.default_value = value
    end
    if entry.required ~= nil and type(entry.required) ~= "boolean" then bad("required for '" .. entry.name .. "' must be a boolean") end
    norm.entries[#norm.entries + 1] = entry
    if entry.is_option then
      norm.options[entry.name] = entry
    else
      if norm.rest_entry then bad("'" .. entry.name .. "' cannot follow the rest entry '" .. norm.rest_entry.name .. "'") end
      norm.positionals[#norm.positionals + 1] = entry
      if entry.rest then norm.rest_entry = entry end
    end
  end
  return norm
end

local function help_text(entry)
  local text = entry.help or ""
  local extra = {}
  if entry.choices then extra[#extra + 1] = "one of " .. table.concat(entry.choices, ", ") end
  if entry.min ~= nil and entry.max ~= nil then extra[#extra + 1] = tostring(entry.min) .. " to " .. tostring(entry.max)
  elseif entry.min ~= nil then extra[#extra + 1] = "at least " .. tostring(entry.min)
  elseif entry.max ~= nil then extra[#extra + 1] = "at most " .. tostring(entry.max) end
  if entry.default ~= nil and entry.default ~= "" and entry.default ~= false then extra[#extra + 1] = "default " .. tostring(entry.default) end
  if entry.required then extra[#extra + 1] = "required" end
  if #extra > 0 then text = text .. " (" .. table.concat(extra, "; ") .. ")" end
  return (text:gsub("^%s+", ""))
end

local function usage_of(norm, name)
  local line = "usage: " .. name
  local has_options = false
  for _, entry in ipairs(norm.entries) do if entry.is_option then has_options = true end end
  if has_options then line = line .. " [options]" end
  for _, entry in ipairs(norm.positionals) do
    local shown = entry.rest and (entry.name .. " ...") or entry.name
    line = line .. (entry.required and (" <" .. shown .. ">") or (" [" .. shown .. "]"))
  end
  local out = { line }
  if #norm.positionals > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "arguments:"
    for _, entry in ipairs(norm.positionals) do
      out[#out + 1] = string.format("  %-22s %s", entry.name, help_text(entry))
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "options:"
  for _, entry in ipairs(norm.entries) do
    if entry.is_option then
      local label = entry.name
      if entry.type ~= "flag" then label = label .. " <" .. entry.type .. ">" end
      out[#out + 1] = string.format("  %-22s %s", label, help_text(entry))
    end
  end
  out[#out + 1] = string.format("  %-22s %s", "--help", "show this message")
  return table.concat(out, "\n") .. "\n"
end

-- cli.usage(spec [, name]) -> text
function cli.usage(spec, name)
  return usage_of(normalise(spec), name or "program")
end

-- cli.parse(args, spec [, name]) -> opts | nil, err
function cli.parse(args, spec, name)
  local norm = normalise(spec)
  name = name or "program"
  if type(args) ~= "table" then bad("args must be an array of strings") end
  local function usage(message)
    return nil, err.new("CLI", "usage", message .. "\n\n" .. usage_of(norm, name))
  end
  local opts = { help = false }
  local supplied = {}
  for _, entry in ipairs(norm.entries) do
    if entry.default ~= nil then
      opts[entry.key] = entry.default_value
    elseif entry.type == "flag" then
      opts[entry.key] = false
    elseif entry.rest then
      opts[entry.key] = {}
    end
  end
  local rest = {}
  local options_done = false
  local i = 1
  while i <= #args do
    local a = args[i]
    if options_done or a:sub(1, 2) ~= "--" then
      rest[#rest + 1] = a
    elseif a == "--" then
      options_done = true
    elseif a == "--help" then
      opts.help = true
    else
      local option_name, inline = a:match("^([^=]+)=(.*)$")
      option_name = option_name or a
      local entry = norm.options[option_name]
      if entry == nil then return usage("unknown option '" .. option_name .. "'") end
      local raw
      if entry.type == "flag" then
        if inline ~= nil then raw = inline else raw = true end
      elseif inline ~= nil then
        raw = inline
      else
        local next_value = args[i + 1]
        if next_value == nil or (next_value:sub(1, 2) == "--" and next_value ~= "--") then
          return usage(entry.name .. " needs a value")
        end
        raw = next_value
        i = i + 1
      end
      local value, message = convert(entry, raw)
      if value == nil then return usage(message) end
      opts[entry.key] = value
      supplied[entry.key] = true
    end
    i = i + 1
  end
  local index = 1
  for _, entry in ipairs(norm.positionals) do
    if entry.rest then
      local collected = {}
      while index <= #rest do
        local value, message = convert(entry, rest[index])
        if value == nil then return usage(message) end
        collected[#collected + 1] = value
        index = index + 1
      end
      opts[entry.key] = collected
      supplied[entry.key] = #collected > 0
    elseif index <= #rest then
      local value, message = convert(entry, rest[index])
      if value == nil then return usage(message) end
      opts[entry.key] = value
      supplied[entry.key] = true
      index = index + 1
    elseif entry.required and not opts.help then
      return usage("missing required argument <" .. entry.name .. ">")
    end
  end
  if index <= #rest then
    return usage("unexpected argument '" .. rest[index] .. "'")
  end
  if opts.help then return opts end
  for _, entry in ipairs(norm.entries) do
    if entry.is_option and entry.required and not supplied[entry.key] and entry.default == nil then
      return usage("missing required option " .. entry.name)
    end
  end
  return opts
end

return cli
