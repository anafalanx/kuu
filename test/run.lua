-- run.lua -- the test driver: kuu test/run.lua [case ...]
--
-- Runs the case modules under test/cases with the kuu that runs this file,
-- so the build under test is the one exercised.  Scratch files go under
-- build/test-work.
global none
global <const> require, ipairs, io, os, tostring, string

local rt = require "rt"
local proc = require "proc"
local lib = require "lib"

local program_dir = (rt.program or "test/run.lua"):match("^(.*)[/\\][^/\\]*$") or "."
lib.root = program_dir .. "/.."
lib.fixtures = program_dir .. "/fixtures"
lib.work = lib.root .. "/build/test-work"

local made = proc.run { "cmd.exe", "/c", "if not exist " .. lib.work:gsub("/", "\\") ..
  " mkdir " .. lib.work:gsub("/", "\\") }
if not made or made.code ~= 0 then
  io.stderr:write("cannot create the work directory ", lib.work, "\n")
  os.exit(2)
end

local cases = { "entry", "sched", "proc", "limits", "json", "hash", "text", "re", "time", "fs", "paths", "sys", "sync", "mem", "log", "cli", "http", "net", "csv", "ini", "reg", "env", "task", "archive", "check" }
if #rt.args > 0 then cases = rt.args end

local started = require("sched").clock()
for _, name in ipairs(cases) do
  io.write("== ", name, "\n")
  local case = require("cases." .. name)
  case(lib)
end
io.write(string.format("\n%d ok, %d failed in %.1f s\n", lib.passed, lib.failed,
  require("sched").clock() - started))
if lib.failed > 0 then os.exit(1) end
