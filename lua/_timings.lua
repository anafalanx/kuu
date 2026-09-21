-- _timings.lua -- command wall-clock measurements. Values are seconds;
-- callers define inclusive/overlapping boundaries, never sum child durations.
global none
global <const> require, table, pcall, error, ipairs, string, io

local clock = require("sched").clock
local timings = { clock = clock }
function timings.measure(values, key, fn, ...)
  local began = clock()
  local result = table.pack(pcall(fn, ...))
  values[key] = (values[key] or 0) + (clock() - began)
  if not result[1] then error(result[2], 0) end
  return table.unpack(result, 2, result.n)
end

function timings.finish(values, began)
  values.total = clock() - began
  return values
end

function timings.write(verb, values)
  local parts = {}
  for _, key in ipairs { "setup", "scan", "checking", "fixing", "inventory",
    "ledger_tail", "ledger_verification", "ledger", "execution", "total" } do
    if values[key] ~= nil then parts[#parts + 1] = string.format("%s=%.3fs", key, values[key]) end
  end
  io.stderr:write("kuu: timings ", verb, " ", table.concat(parts, " "), "\n")
end

return timings
