-- Each parent announces readiness only after its whole subtree exists.
global none
global <const> require, assert, tonumber, tostring, io
local rt, proc, sched = require "rt", require "proc", require "sched"
local depth = assert(tonumber(rt.args[1]))
if depth > 1 then
  local child <close> = assert(proc.start {
    rt.exe, rt.program, tostring(depth - 1), stream = true, timeout = "30s",
  })
  assert(child:read("line", "20s") == "ready")
  io.write("ready\n")
  io.flush()
  child:wait()
else
  io.write("ready\n")
  io.flush()
  sched.sleep("30s")
end
