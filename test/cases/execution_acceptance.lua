-- execution_acceptance.lua -- task history is independent of project tree
-- state; processes entering one project through aliases share an append lock.
global none
global <const> require, assert, ipairs, tostring, type, table, pcall, error, io

return function(T)
  local check = T.check
  local fs, json, proc, sync = require "fs", require "json", require "proc", require "sync"
  local ledger, err, sched = require "_ledger", require "err", require "sched"
  local scratch = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "execution-acceptance-" })
  local function write(root, relative, contents)
    local path = root .. "/" .. relative
    assert(fs.mkdir(assert(path:match("^(.*)/[^/]+$"))))
    assert(fs.write(path, contents))
    return path
  end
  local function final_envelope(text)
    local result
    for line in text:gmatch("[^\r\n]+") do result = assert(json.decode(line)) end
    return assert(result)
  end
  local function execution_only(result, count)
    local body = result.result
    return body and body.scope == nil and body.scans == nil
      and body.timings.initial_scan == nil and body.timings.final_scan == nil
      and body.ledger and body.ledger.complete and body.ledger.records == count
      and body.ledger.observation == nil and body.ledger.publication == nil
      and body.ledger.error == nil and #body.notes == 0
  end
  local function record_shape(record)
    return record.v == 2 and record.observation == nil and record.delta == nil
      and type(record.at) == "number" and type(record.seconds) == "number"
  end
  local function project(name, tree_bytes)
    local root = scratch .. "/" .. name
    assert(fs.mkdir(root))
    write(root, ".gitignore", "/.kuu/\n")
    if tree_bytes then write(root, ".kuu/ledger/tree.json", tree_bytes) end
    write(root, "src/maintained.txt", "before the run\n")
    -- Guard after manifest loading, before the runner opens the ledger.
    -- A caught collection failure must still fail the history assertions;
    -- changing the fixture's files is intentional task work.
    write(root, "manifest.lua", table.concat({
      'global none', 'global <const> require, assert, ipairs, error',
      'local fs,task,rt=require "fs",require "task",require "rt"',
      'local function forbid() error("automatic project observation is forbidden") end',
      'require("_scan").collect=forbid', 'require("_scan_native").collect=forbid',
      'fs.dirs=forbid',
      'for _,name in ipairs {"read","write","stat","exists","remove"} do',
      '  local original=fs[name]',
      '  fs[name]=function(path,...)',
      '    if path:gsub("\\\\","/"):match("/%.kuu/ledger/tree%.json$") then error("obsolete tree state was touched") end',
      '    return original(path,...)',
      '  end',
      'end',
      'local list=fs.list',
      'fs.list=function(path,...)',
      '  if not path:gsub("\\\\","/"):match("/%.kuu/ledger$") then error("unexpected project enumeration") end',
      '  return list(path,...)',
      'end',
      'task "mutate" {run=function() assert(fs.write("src/maintained.txt","task changed this\\n")) end}',
      'task "fail" {run=function() return task.exec {rt.exe,"-e","os.exit(7)"} end}',
      'task "inner" {run=function() assert(fs.write("src/nested.txt","nested work\\n")) end}',
      'task "nested" {run=function() return task.exec {rt.exe,"run","--json","inner"} end}',
    }, "\n") .. "\n")
    return root
  end

  local old_scope = assert(require("_scan_policy").decode('{"v":1,"scan":{"defaults":false}}'))
  local legacy = json.encode {
    kind = "kuu.tree", v = 1, generation = 9, complete = true,
    scope = { v = 1, dirs = old_scope.effective_dirs, paths = old_scope.exclude_paths,
      fingerprint = old_scope.fingerprint },
    files = { ["src/maintained.txt"] = { size = 15, mtime = 1 } },
  }
  for _, fixture in ipairs { { name = "legacy-state", bytes = legacy },
      { name = "malformed-state", bytes = "{obsolete, broken tree bytes\n" } } do
    local root = project(fixture.name, fixture.bytes)
    local ran = T.kuu({ "run", "--json", "mutate" }, { cwd = root })
    local run_doc = final_envelope(ran.out)
    local records = assert(ledger.tail(root, 20))
    check(fixture.name .. ": a successful task records execution without collecting or touching old tree state",
      ran.code == 0 and run_doc.ok and execution_only(run_doc, 2)
        and fs.read(root .. "/src/maintained.txt") == "task changed this\n"
        and fs.read(root .. "/.kuu/ledger/tree.json") == fixture.bytes
        and #records == 2 and records[1].kind == "task" and records[1].name == "mutate"
        and records[1].status == "ok" and records[2].kind == "verb" and records[2].code == 0,
      T.describe(ran))

    local failed = T.kuu({ "run", "--json", "fail" }, { cwd = root })
    local failed_doc = final_envelope(failed.out)
    records = assert(ledger.tail(root, 20))
    check(fixture.name .. ": failed child, task and verb are recorded independently of obsolete state",
      failed.code == 7 and not failed_doc.ok and execution_only(failed_doc, 3)
        and fs.read(root .. "/.kuu/ledger/tree.json") == fixture.bytes
        and #records == 5 and records[3].kind == "child" and records[3].code == 7
        and records[4].kind == "task" and records[4].status == "failed"
        and records[5].kind == "verb" and records[5].status == "failed" and records[5].code == 7,
      T.describe(failed))

    local nested = T.kuu({ "run", "--json", "nested" }, { cwd = root })
    local nested_doc = final_envelope(nested.out)
    records = assert(ledger.tail(root, 20))
    check(fixture.name .. ": nested runs append their own records to one intact history",
      nested.code == 0 and nested_doc.ok and execution_only(nested_doc, 3)
        and fs.read(root .. "/.kuu/ledger/tree.json") == fixture.bytes
        and fs.read(root .. "/src/nested.txt") == "nested work\n"
        and #records == 10 and records[6].kind == "task" and records[6].name == "inner"
        and records[7].kind == "verb" and records[8].kind == "child" and records[8].task == "nested"
        and records[9].kind == "task" and records[9].name == "nested" and records[10].kind == "verb",
      T.describe(nested))
    local clean_records = true
    for _, record in ipairs(records) do clean_records = clean_records and record_shape(record) end
    local intact, count = ledger.verify(root)
    check(fixture.name .. ": all new records use the execution schema and preserve the hash chain",
      clean_records and intact == true and count == 10, json.encode(records))
  end

  local fresh = project("fresh")
  local ran = T.kuu({ "run", "--json", "mutate" }, { cwd = fresh })
  check("a new project receives history without creating a snapshot",
    ran.code == 0 and execution_only(final_envelope(ran.out), 2)
      and fs.exists(fresh .. "/.kuu/ledger/tree.json") == false, T.describe(ran))

  local unreadable = project("unreadable-state", legacy)
  local helper = fs.absolute(T.root .. "/build/test/scan_fixture.exe")
  check("execution tests have the Windows sharing-denial fixture", fs.exists(helper) == "file", helper)
  if fs.exists(helper) == "file" then
    local control = scratch .. "/hold-control"
    assert(fs.mkdir(control))
    local child <close> = assert(proc.start { helper, "hold", unreadable .. "/.kuu/ledger/tree.json",
      control .. "/ready", control .. "/release", timeout = "25s" })
    local tested, failure = pcall(function()
      local began = sched.clock()
      while not fs.exists(control .. "/ready") do
        assert(child:running(), "state hold exited before readiness")
        assert(sched.clock() - began < 10, "state hold barrier timeout")
        sched.sleep("10ms")
      end
      local bytes, why = fs.read(unreadable .. "/.kuu/ledger/tree.json")
      check("the old snapshot is actually unreadable while the fixture holds it",
        bytes == nil and err.is(why, "FS", "access"), tostring(why))
      local held_run = T.kuu({ "run", "--json", "mutate" }, { cwd = unreadable })
      check("an unreadable old snapshot does not disable execution history or create a warning",
        held_run.code == 0 and execution_only(final_envelope(held_run.out), 2)
          and ledger.verify(unreadable) == true, T.describe(held_run))
    end)
    assert(fs.write(control .. "/release", "release"))
    local ended = assert(child:wait("5s"))
    check("the held snapshot is released with its original bytes intact",
      ended.status == "exit" and ended.code == 0 and fs.read(unreadable .. "/.kuu/ledger/tree.json") == legacy,
      T.describe(ended))
    if not tested then error(failure) end
  end

  local real_root, alias = scratch .. "/real-project", scratch .. "/project-alias"
  assert(fs.mkdir(real_root))
  local created, creation_error = proc.run { "cmd.exe", "/c", "mklink", "/J",
    alias:gsub("/", "\\"), real_root:gsub("/", "\\"), timeout = "10s" }
  if not created or created.code ~= 0 then
    io.write("skip canonical ledger alias fixture: junction creation unavailable: ",
      created and T.describe(created) or tostring(creation_error), "\n")
  else
    check("the owned junction names the same canonical project",
      assert(fs.canon(real_root)).path == assert(fs.canon(alias)).path)
    -- Capture the real name requested by an append; do not duplicate the
    -- ledger's private lock-name hashing in the test.
    local original_lock, lock_names = sync.lock, {}
    sync.lock = function(name, timeout)
      lock_names[#lock_names + 1] = name
      return original_lock(name, timeout)
    end
    local seeded, seed_error = pcall(function()
      local book = ledger.open(real_root)
      assert(ledger.record(book, { kind = "task", name = "seed", status = "ok", at = 1, seconds = 0 }))
    end)
    sync.lock = original_lock
    if not seeded then error(seed_error) end
    local lock_name = assert(lock_names[1], "ledger append never requested a lock")
    check("a successful append acquires one ledger lock", #lock_names == 1, table.concat(lock_names, "\n"))
    local worker = write(scratch, "alias-worker.lua", [=[
global none
global <const> require, assert, io
local rt,json,sync,ledger=require "rt",require "json",require "sync",require "_ledger"
local original=sync.lock
local function event(value) io.write(json.encode(value),"\n"); io.flush() end
sync.lock=function(name,timeout)
  event {event="lock",name=name}
  return original(name,timeout)
end
event {event="ready"}
local book=ledger.open(assert(rt.args[1]))
event {event="opened"}
assert(ledger.record(book,{kind="task",name="alias",status="ok",at=2,seconds=0}))
event {event="appended",written=book.written}
]=])
    local held <close> = assert(sync.lock(lock_name, "2s"))
    local child <close> = assert(proc.start { T.exe, worker, alias, stream = true, timeout = "15s" })
    local ready = assert(json.decode(assert(child:read("line", "5s"))))
    local opened = assert(json.decode(assert(child:read("line", "5s"))))
    local attempted = assert(json.decode(assert(child:read("line", "5s"))))
    check("opening through an alias needs no baseline lock; appending reaches the shared held lock",
      ready.event == "ready" and opened.event == "opened" and attempted.event == "lock"
        and attempted.name == lock_name, json.encode(attempted))
    local early, why = child:read("line", "100ms")
    check("a real-root append lock blocks an alias append until release",
      early == nil and err.is(why, "PROC", "timeout") and child:running(), tostring(early or why))
    assert(held:release())
    local remainder = assert(child:read("all", "5s"))
    local ended = assert(child:wait("5s"))
    local appended = assert(json.decode(remainder))
    local records = assert(ledger.tail(real_root, 5))
    local intact, count = ledger.verify(real_root)
    check("the alias resumes into the same intact append chain without creating tree state",
      ended.status == "exit" and ended.code == 0 and appended.event == "appended" and appended.written == 1
        and intact == true and count == 2 and records[1].name == "seed" and records[2].name == "alias"
        and json.encode(records) == json.encode(assert(ledger.tail(alias, 5)))
        and fs.exists(real_root .. "/.kuu/ledger/tree.json") == false, remainder .. T.describe(ended))
  end
  assert(fs.remove(scratch, { recursive = true }))
end
