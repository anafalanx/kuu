-- mem.lua -- the notebook across runs: round-trips, defaults, keys, another
-- process writing the same file, the size limit, damage, and the default place.
global none
global <const> require, ipairs, tostring, type, string, table, pcall

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local json = require "json"
  local err = require "err"
  local mem = require "mem"

  local work = fs.absolute(T.work .. "/mem")
  fs.remove(work, { recursive = true })
  fs.mkdir(work)
  local path = work .. "/notes/memory.json"
  check("open sets the place and returns it absolute", mem.open(path) == path and mem.path() == path)
  check("an absent key is nil, or the default", mem.get("nothing") == nil and mem.get("nothing", 7) == 7)
  local ok, e = mem.set("build", { at = 1700000000, ok = true, tags = json.array { "a", "b" } })
  check("set creates the directory and the file", ok == true and fs.exists(path) == "file", tostring(e))
  local build = mem.get("build")
  check("a table round-trips, arrays included", build and build.at == 1700000000 and build.ok == true and build.tags[2] == "b" and #build.tags == 2)
  mem.set("count", 3)
  mem.set("name", "moon")
  check("keys come back sorted", table.concat(mem.keys(), ",") == "build,count,name", table.concat(mem.keys(), ","))
  check("all is a copy of everything", mem.all().count == 3 and mem.all() ~= mem.all())
  check("forget removes, and forgetting the absent is fine", mem.forget("count") == true and mem.get("count") == nil and mem.forget("count") == true)
  mem.set("name", nil)
  check("setting nil forgets", mem.get("name") == nil and table.concat(mem.keys(), ",") == "build")

  -- another kuu writing the same file
  local r = T.kuu { "-e", "local m = require('mem'); m.open([[" .. path .. "]]); assert(m.set('from_child', 42))" }
  check("another process can write the same memory", r.code == 0 and mem.get("from_child") == 42, T.describe(r))
  check("and the earlier keys survived its write", mem.get("build").ok == true)

  -- refusals
  local none
  none, e = mem.set("big", string.rep("x", 1024 * 1024))
  check("a memory over 1 MiB is refused as MEM toobig, and the file stands", none == nil and err.is(e, "MEM", "toobig") and mem.get("from_child") == 42, tostring(e))
  none, e = mem.set("fn", function() end)
  check("a value JSON cannot hold is MEM badvalue", none == nil and err.is(e, "MEM", "badvalue"), tostring(e))
  local raised
  ok, raised = pcall(mem.get, 5)
  check("keys must be strings", not ok and err.is(raised, "MEM", "badvalue"))
  fs.write(path, "[1, 2]")
  ok, raised = pcall(mem.get, "build")
  check("a damaged file raises MEM corrupt rather than answering", not ok and err.is(raised, "MEM", "corrupt"), tostring(raised))

  -- the default place: .kuu/memory.json under the project, else under the require root
  local project = work .. "/proj/deep"
  fs.mkdir(project)
  fs.write(work .. "/proj/tasks.lua", "")
  r = T.kuu({ "-e", "io.write(require('mem').path())" }, { cwd = project })
  check("without open, the memory lives under the nearest project", r.code == 0 and r.out == work .. "/proj/.kuu/memory.json", T.describe(r))
  r = T.kuu({ "-e", "io.write(require('mem').path())" }, { cwd = work })
  check("without a project, it lives under the require root", r.code == 0 and r.out == work .. "/.kuu/memory.json", T.describe(r))
end
