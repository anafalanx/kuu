-- lib.lua -- the small test kit: checks, running kuu itself, files.
global none
global <const> require, ipairs, tostring, string, io, error, assert

local rt = require "rt"
local proc = require "proc"

local lib = { passed = 0, failed = 0, exe = rt.exe }

function lib.check(name, condition, detail)
  if condition then
    lib.passed = lib.passed + 1
    io.write("ok   ", name, "\n")
  else
    lib.failed = lib.failed + 1
    io.write("FAIL ", name, "\n")
    if detail ~= nil then
      local text = tostring(detail):gsub("\n", "\n     ")
      io.write("     ", text, "\n")
    end
  end
end

-- Run the kuu under test with `args`; returns the proc.run result.
-- opts: stdin (bytes), cwd, env, timeout (default 60s).
function lib.kuu(args, opts)
  local spec = { lib.exe }
  for _, a in ipairs(args) do spec[#spec + 1] = a end
  spec.timeout = (opts and opts.timeout) or "60s"
  if opts then
    spec.stdin = opts.stdin
    spec.cwd = opts.cwd
    spec.env = opts.env
  end
  local r, e = proc.run(spec)
  if not r then error("cannot run kuu: " .. tostring(e)) end
  return r
end

function lib.describe(r)
  return string.format("status %s code %s\nstdout: %s\nstderr: %s",
    tostring(r.status), tostring(r.code), r.out, r.err)
end

function lib.read_file(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("a")
  f:close()
  return data
end

function lib.write_file(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

function lib.starts(s, prefix) return s:sub(1, #prefix) == prefix end
function lib.contains(s, needle) return s:find(needle, 1, true) ~= nil end

return lib
