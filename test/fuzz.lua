-- Each seed runs in supervised children: a crash or hang fails the gate.
-- Native command-line quoting plus duration/date/path/CSV/INI/JSON/registry
-- parsers: registry fuzzing only checks key existence, never writes values.
-- Reproduce with make fuzz FUZZ=<cases> FUZZ_SEED=<seed>.
global none
global <const> require, tonumber, tostring, assert, math, ipairs, io, os

local rt, proc, fs = require "rt", require "proc", require "fs"
local cases = tonumber(rt.args[1] or "10000")
assert(cases and math.type(cases) == "integer" and cases > 0 and cases <= 1000000, "FUZZ must be 1..1000000")
local seeds = { 1, 12648430, 3735928559 }
if rt.args[2] then
  local seed = tonumber(rt.args[2])
  assert(seed and math.type(seed) == "integer" and seed > 0 and seed <= 0xffffffff, "FUZZ_SEED must be 1..4294967295")
  seeds = { seed }
end
local root = fs.absolute(fs.dirname(rt.program) .. "/..")
for _, seed in ipairs(seeds) do
  local commands = {
    { root .. "/build/test/parser_fuzz.exe", tostring(cases), tostring(seed) },
    { rt.exe, root .. "/test/fixtures/parser_fuzz.lua", tostring(cases), tostring(seed) },
  }
  for _, command in ipairs(commands) do
    io.write("fuzz: ", command[1], " cases=", cases, " seed=", seed, "\n")
    io.flush()
    command.timeout, command.maxout = "5m", "1M"
    local r, e = proc.run(command)
    if not r then io.stderr:write(tostring(e), "\n"); os.exit(1) end
    io.write(r.out)
    io.stderr:write(r.err)
    if r.status ~= "exit" or r.code ~= 0 or r.truncated then
      io.stderr:write("fuzz failed: status=", r.status, " code=", tostring(r.code), " seed=", seed, "\n")
      os.exit(1)
    end
  end
end
io.write("parser fuzzing passed\n")
