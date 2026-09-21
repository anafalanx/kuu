-- Execute the published cleanup module, including real Windows sharing holds.
global none
global <const> require, assert, ipairs, load, tostring, table, error

return function(T)
  local fs, err, sched = require "fs", require "err", require "sched"
  local proc, hash, json = require "proc", require "hash", require "json"
  local check = T.check
  local root = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "cleanup-recipe-" })
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/cleanup.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = source
  end
  check("cleanup guide contains a module and a complete extraction program", #blocks == 2)
  if #blocks ~= 2 then return end
  for i, name in ipairs { "owned_ops.lua", "install-cached.lua" } do assert(fs.write(root .. "/" .. name, blocks[i])) end
  local lint = T.kuu({ "check", "--json", "owned_ops.lua", "install-cached.lua" }, { cwd = root })
  local report = json.decode(lint.out)
  check("both published cleanup blocks pass static checking", lint.code == 0 and report
    and report.result.errors == 0 and report.result.warnings == 0, T.describe(lint))
  local ops = assert(load(blocks[1], "@owned_ops.lua", "t"))()

  -- Deterministic time/control evidence complements real sharing failures below.
  local real_clock, real_sleep = sched.clock, sched.sleep
  local now, sleeps, attempts = 0, {}, 0
  local denied = err.new("FS", "access", "opaque native diagnostic")
  sched.clock = function() return now end
  sched.sleep = function(seconds) sleeps[#sleeps + 1] = seconds; now = now + seconds end
  local ok, why = ops.retry_access(function() attempts = attempts + 1; return nil, denied end, 0.06)
  sched.clock, sched.sleep = real_clock, real_sleep
  check("retry uses one total deadline and returns the original access error",
    ok == nil and why == denied and attempts == 3 and #sleeps == 3 and now == 0.06)
  attempts = 0
  local exists = err.new("FS", "exists", "not a sharing failure")
  ok, why = ops.retry_access(function() attempts = attempts + 1; return nil, exists end, 2)
  check("unrelated errors are not retried", ok == nil and why == exists and attempts == 1)
  attempts = 0
  ok, why = ops.retry_access(function() attempts = attempts + 1; return nil, denied end, 0)
  check("zero retry budget still makes exactly one attempt", ok == nil and why == denied and attempts == 1)
  check("already absent owned cleanup succeeds", ops.remove_owned(root .. "/absent", 0.1) == true)

  local original_remove = fs.remove
  local missing_child = err.new("FS", "notfound", "descendant disappeared")
  fs.remove = function() return nil, missing_child end
  ok, why = ops.remove_owned(root, 0.1)
  fs.remove = original_remove
  check("a missing descendant cannot falsely report a surviving root removed", ok == nil and why == missing_child)

  local locker = fs.absolute(T.root .. "/build/test/lock_fixture.exe")
  local function held(path)
    local child = assert(proc.start { locker, path, stream = true, timeout = "10s" })
    assert(child:read("line", "5s") == "LOCKED")
    return child
  end
  local function release(child)
    assert(child:write("x\n")); child:close_stdin()
    local result = assert(child:wait("5s"))
    assert(result.status == "exit" and result.code == 0)
  end
  local stage, destination = root .. "/transient-stage", root .. "/published"
  assert(fs.mkdir(stage)); assert(fs.write(stage .. "/marker", "complete"))
  do
    local child <close> = held(stage)
    local rel = sched.spawn(function() sched.sleep("150ms"); release(child) end)
    ok, why = ops.publish(stage, destination, function(path) return fs.read(path .. "/marker") == "complete" end, 2)
    rel:join()
    check("publication retries a real temporary sharing denial without replacing data", ok == true
      and fs.exists(stage) == false and fs.read(destination .. "/marker") == "complete", tostring(why))
  end
  do
    local path = root .. "/temporary-removal"
    assert(fs.mkdir(path)); assert(fs.write(path .. "/locked", "held"))
    local child <close> = held(path .. "/locked")
    local rel = sched.spawn(function() sched.sleep("100ms"); release(child) end)
    ok, why = ops.remove_owned(path, 2)
    rel:join()
    check("whole-tree cleanup yields and succeeds after a real sharing hold releases", ok == true and not fs.exists(path), tostring(why))
  end
  do
    local path = root .. "/persistent-removal"
    assert(fs.mkdir(path)); assert(fs.write(path .. "/locked", "held"))
    local child <close> = held(path .. "/locked")
    local began = sched.clock()
    ok, why = ops.remove_owned(path, 0.12)
    local elapsed = sched.clock() - began
    check("persistent sharing denial stops within the cleanup retry budget", ok == nil and err.is(why, "FS", "access")
      and elapsed >= 0.10 and elapsed < 3 and fs.exists(path) == "directory", tostring(why) .. " elapsed=" .. elapsed)
    release(child)
    check("a later cleanup tolerates partial previous progress", ops.remove_owned(path, 0.2) == true)
  end
  do
    local path = root .. "/invalid-stage"
    assert(fs.mkdir(path)); assert(fs.write(path .. "/locked", "held"))
    local child <close> = held(path .. "/locked")
    local primary = err.new("PROJECT", "invalid", "package validation failed")
    local cleanup
    ok, why, cleanup = ops.publish(path, root .. "/never-published", function() return nil, primary end, 0.08)
    check("failed validation and failed cleanup both survive without publishing", ok == nil and why == primary
      and err.is(cleanup, "FS", "access") and not fs.exists(root .. "/never-published"))
    release(child)
    check("invalid staging remains an exact owned cleanup target", ops.remove_owned(path, 0.2) == true)
    assert(fs.mkdir(path))
    ok, why, cleanup = ops.publish(path, destination, function() error(primary) end, 0.2)
    check("raised validation failure survives successful cleanup", ok == nil and why == primary
      and cleanup == nil and not fs.exists(path))
    assert(fs.mkdir(path))
    ok, why, cleanup = ops.publish(path, destination, function() return true end, 2)
    check("existing destination is preserved and unsuccessful staging is removed", ok == nil and err.is(why, "FS", "exists")
      and cleanup == nil and not fs.exists(path) and fs.read(destination .. "/marker") == "complete", tostring(why))
  end

  -- Execute the second, unchanged program against a local tar; no downloads.
  local payload = root .. "/payload"
  assert(fs.mkdir(payload .. "/bin")); assert(fs.write(payload .. "/bin/tool.exe", "fixture bytes"))
  local tar = root .. "/cached.tar"
  local packed = assert(proc.run { "tar.exe", "-cf", tar, "-C", payload, ".", timeout = "10s" })
  check("local archive fixture is created", packed.status == "exit" and packed.code == 0, T.describe(packed))
  if packed.code ~= 0 then return end
  local digest = assert(hash.file("sha256", tar))
  local installed = T.kuu({ "install-cached.lua", tar, root .. "/installed", digest }, { cwd = root })
  check("published extraction program validates and publishes the local package", installed.code == 0
    and fs.read(root .. "/installed/bin/tool.exe") == "fixture bytes", T.describe(installed))
  local rejected = T.kuu({ "install-cached.lua", tar, root .. "/bad-hash", "wrong" }, { cwd = root })
  local listing = assert(fs.list(root))
  local leftovers = {}
  for _, entry in ipairs(listing.entries) do if entry.name:match("^%.stage%-") then leftovers[#leftovers + 1] = entry.name end end
  check("hash failure retains primary diagnostic and cleans only its staging", rejected.code ~= 0
    and T.contains(rejected.err, "PROJECT hash") and not fs.exists(root .. "/bad-hash") and #leftovers == 0
    and fs.read(root .. "/installed/bin/tool.exe") == "fixture bytes", T.describe(rejected) .. table.concat(leftovers, ","))

  local adopting = assert(fs.read(T.root .. "/docs/adopting.md"))
  local clean_source = assert(adopting:match('(task "clean" %b{})'))
  local clean
  local simulated = {
    remove = function() return nil, denied end,
    stat = function() return nil, missing_child end,
  }
  assert(load("global none\nreturn function(task, fs, err)\n" .. clean_source .. "\nend", "@adopting-clean", "t"))()(
    function(_) return function(spec) clean = spec.run end end, simulated, err)
  ok, why = clean()
  check("adoption clean task preserves real removal failure", ok == nil and why == denied)
  simulated.remove = function() return nil, missing_child end
  check("adoption clean task tolerates a confirmed absent build root", clean() == true)
  simulated.stat = function() return { kind = "directory" } end
  ok, why = clean()
  check("adoption clean task never confuses a missing child with successful cleanup", ok == nil and why == missing_child)
end
