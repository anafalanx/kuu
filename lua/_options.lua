-- _options.lua -- the one check every option-taking call in the palette
-- makes, on the Lua side: an options table may hold only the keys the call
-- reads, and any other key raises `<DOMAIN> usage` naming it, exactly as the
-- C modules do through ku_check_options.  A misspelt option is refused
-- instead of being ignored, and refused the same way everywhere.
--
--   local check_options = require "_options"
--   options = check_options(options, { strip = true, timeout = true }, "ARCHIVE")
--
-- nil stands for no options and comes back as an empty table, so the caller
-- reads fields without a guard.  A value that is not a table is `badvalue`.
global none
global <const> require, pairs, tostring, type, error

local err = require "err"

return function(options, allowed, domain)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(err.new(domain, "badvalue", "options must be a table, not " .. type(options)), 3)
  end
  for key in pairs(options) do
    if not allowed[key] then
      error(err.new(domain, "usage", "unknown option '" .. tostring(key) .. "'"), 3)
    end
  end
  return options
end
