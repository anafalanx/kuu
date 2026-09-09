-- soak.lua -- kuu under volume, on demand:  build\kuu.exe test\soak.lua [seconds]
--
-- Rounds of tasks, children, streams, requests, files, timers, and memory
-- writes, repeated until the time is up, with the process's own handle count
-- and private bytes measured after every round.  The suite proves behaviour
-- in thirteen seconds; this proves that nothing leaks or slows over minutes.
-- Exit 1 when any operation fails or when handles or memory keep growing.
global none
global <const> require, ipairs, io, os, tostring, tonumber, string, math, table, select

local rt = require "rt"
local proc = require "proc"
local sched = require "sched"
local fs = require "fs"
local http = require "http"
local sys = require "sys"
local mem = require "mem"

local seconds = tonumber(rt.args[1]) or 60
local only = rt.args[2] -- a comma-separated list of phases, to hunt a leak
local program_dir = (rt.program or "test/soak.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = fs.absolute(program_dir .. "/..")
local work = root .. "/build/soak-work"
fs.remove(work, { recursive = true })
fs.mkdir(work)
mem.open(work .. "/memory.json")

local failures = 0
local function must(ok, what)
  if not ok then
    failures = failures + 1
    io.write("FAIL ", what, "\n")
  end
end

local fixture = root .. "/build/test/http_fixture.exe"
local server, base
if fs.exists(fixture) == "file" then
  server = proc.start { fixture, (work:gsub("/", "\\")), stream = true }
  local port = tonumber((server:read("line", "10s") or ""):match("^PORT (%d+)$"))
  if port then base = "http://127.0.0.1:" .. port end
end
if base == nil then io.write("note: no http fixture; the request phase is skipped (make fixtures)\n") end

local phases = {}

phases.tasks = function()
  local handles = {}
  for i = 1, 500 do
    handles[i] = sched.spawn(function(n) sched.sleep(tostring(n % 5) .. "ms") return n end, i)
  end
  local sum = 0
  for i = 1, 500 do sum = sum + select(1, handles[i]:join()) end
  must(sum == 500 * 501 / 2, "500 tasks join with their values")
end

phases.children = function()
  local runs = {}
  for i = 1, 40 do
    runs[i] = sched.spawn(function() return proc.run { "cmd.exe", "/c", "echo x", timeout = "30s" } end)
  end
  for i = 1, 40 do
    local r = runs[i]:join()
    must(r and r.status == "exit" and r.code == 0 and r.out == "x\r\n", "child " .. i .. " ran and was captured")
  end
end

phases.streams = function()
  local readers = {}
  for i = 1, 10 do
    readers[i] = sched.spawn(function()
      local c <close> = proc.start { "cmd.exe", "/c", "for /L %i in (1,1,50) do @echo line %i", stream = true, timeout = "30s" }
      local count = 0
      for _ in c:lines() do count = count + 1 end
      local r = c:wait("10s")
      return count, r and r.code
    end)
  end
  for i = 1, 10 do
    local count, code = readers[i]:join()
    must(count == 50 and code == 0, "stream " .. i .. " delivered 50 lines")
  end
end

phases.requests = function()
  if base == nil then return end
  local gets = {}
  for i = 1, 40 do
    gets[i] = sched.spawn(function() return http.get(base .. "/hello", { timeout = "30s" }) end)
  end
  for i = 1, 40 do
    local r = gets[i]:join()
    must(r and r.status == 200 and r.body == "hello", "request " .. i)
  end
  local r = http.get(base .. "/big?n=" .. (2 * 1024 * 1024), { to = work .. "/big.bin", timeout = "60s" })
  must(r and r.status == 200 and fs.stat(work .. "/big.bin").size == 2 * 1024 * 1024, "a 2 MiB download lands whole")
end

phases.files = function()
  for i = 1, 200 do
    local p = work .. "/f" .. (i % 20) .. ".txt"
    must(fs.write(p, string.rep("x", i)) == true, "write " .. i)
    must(#fs.read(p) == i, "read " .. i)
  end
  local hits = fs.glob(work .. "/f*.txt")
  must(#hits == 20, "glob finds the twenty files")
  for i = 0, 19 do fs.remove(work .. "/f" .. i .. ".txt") end
end

phases.timers = function()
  local sleepers = {}
  for i = 1, 200 do
    sleepers[i] = sched.spawn(function() sched.sleep(tostring(i % 10) .. "ms") return true end)
  end
  for i = 1, 200 do must(sleepers[i]:join() == true, "timer " .. i) end
end

phases.memory = function()
  for i = 1, 50 do must(mem.set("k" .. (i % 10), { i = i }) == true, "mem set " .. i) end
  must(mem.get("k9").i == 49, "mem reads back the last write")
end

local order = { "tasks", "children", "streams", "requests", "files", "timers", "memory" }
if only ~= nil then
  order = {}
  for name in only:gmatch("[^,]+") do
    if phases[name] == nil then io.write("no phase '", name, "'\n") os.exit(2) end
    order[#order + 1] = name
  end
end
local started = sched.clock()
local at_start = sys.info().process
local first -- measured after the first round: WinHTTP and the allocator warm up once
local round = 0
io.write(string.format("soak for %d s: handles %d, private %.1f MB at start\n", seconds, at_start.handles, at_start.private / 1048576))
while sched.clock() - started < seconds do
  round = round + 1
  local round_started = sched.clock()
  for _, name in ipairs(order) do phases[name]() end
  local now = sys.info().process
  if first == nil then first = now end
  io.write(string.format("round %d: %.1fs, handles %d, private %.1f MB, failures %d\n", round,
    sched.clock() - round_started, now.handles, now.private / 1048576, failures))
end
local last = sys.info().process
first = first or last
local handle_growth = last.handles - first.handles
local private_growth = (last.private - first.private) / 1048576
io.write(string.format("\n%d rounds in %.0f s; handles %+d, private %+.1f MB, failures %d\n", round,
  sched.clock() - started, handle_growth, private_growth, failures))
if server then http.get(base .. "/quit") server:wait("5s") end
if failures > 0 or handle_growth > 50 or private_growth > 32 then
  io.write("soak: NOT like a watch\n")
  os.exit(1)
end
io.write("soak: like a watch\n")
