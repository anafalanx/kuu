-- Exercise the real Makefile payload rules in an isolated miniature tree.
global none
global <const> require, assert, tostring, ipairs

return function(T)
  local fs, proc = require "fs", require "proc"
  local root = assert(fs.absolute(T.root))
  local dir = assert(fs.absolute(T.work .. "/embed-regression"))
  local make = root .. "/.tools/msys2/ucrt64/bin/mingw32-make.exe"
  local embed = root .. "/build/embed.exe"
  assert(fs.mkdir(dir .. "/lua"))
  assert(fs.write(dir .. "/lua/a.lua", "return {a=1}\n"))
  assert(fs.write(dir .. "/lua/z.lua", "return {z=1}\n"))
  local function generate()
    return assert(proc.run { make, "-f", root .. "/Makefile", "-o", embed,
      "payload.c", "EMBED=" .. embed, "PAYLOAD_C=payload.c", "PAYLOAD_DIRS=lua",
      "BUILD=stage", "VERSION=0.11", cwd=dir, timeout="20s" })
  end
  local first = generate()
  T.check("the real payload rule builds an isolated file set", first.code == 0, T.describe(first))
  if first.code ~= 0 then return end
  local path = dir .. "/payload.c"
  local before = assert(fs.read(path))
  local mtime = assert(fs.stat(path)).mtime
  local same = generate()
  T.check("unchanged payload bytes preserve the generated timestamp", same.code == 0
    and fs.stat(path).mtime == mtime and fs.read(path) == before, T.describe(same))
  assert(fs.remove(dir .. "/lua/z.lua"))
  local removed = generate()
  T.check("deleting a source removes it from an incremental payload", removed.code == 0
    and not fs.read(path):find('"lua/z.lua"', 1, true), T.describe(removed))
  assert(fs.write(dir .. "/lua/z.lua", "return {z=2}\n"))
  local added = generate()
  T.check("adding a source restores it to the payload", added.code == 0
    and fs.read(path):find('"lua/z.lua"', 1, true), T.describe(added))
  before = assert(fs.read(path))
  assert(fs.write(dir .. "/lua/a.lua", "return {a=2}\n"))
  do
    local lock <close> = assert(proc.start { root .. "/build/test/lock_fixture.exe", "lua/z.lua",
      cwd=dir, stream=true, timeout="20s" })
    assert(lock:read("line", "5s") == "LOCKED")
    local failed = generate()
    T.check("failed payload generation preserves the last complete output", failed.code ~= 0
      and fs.read(path) == before, T.describe(failed))
    assert(lock:write("\n"))
    lock:close_stdin()
    assert(lock:wait("5s").code == 0)
  end
  local retried = generate()
  T.check("retry regenerates a payload after its input becomes readable", retried.code == 0
    and fs.read(path) ~= before and fs.read(path):find("const ku_payload_entry", 1, true), T.describe(retried))
  local temporaries = 0
  for _, entry in ipairs(assert(fs.list(dir)).entries) do
    if entry.name:find("payload.c.tmp-", 1, true) then temporaries = temporaries + 1 end
  end
  T.check("payload generation leaves no staging files", temporaries == 0, tostring(temporaries))
end
