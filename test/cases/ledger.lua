-- ledger.lua -- the door's memory: one record per crossing, chained across
-- days, rotated by age, with the tree delta between runs and the
-- repository's head read from .git without git.
global none
global <const> require, tostring, type, string, table

return function(T)
  local check, contains = T.check, T.contains
  local fs, json, hash, err, rt, time = require "fs", require "json", require "hash", require "err", require "rt", require "time"
  local ledger = require "_ledger"

  local project = fs.absolute(T.work .. "/ledger-project")
  fs.remove(project, { recursive = true })
  fs.mkdir(project .. "/.git/refs/heads")
  fs.write(project .. "/.git/HEAD", "ref: refs/heads/main\n")
  fs.write(project .. "/.git/refs/heads/main", "0123456789abcdef0123456789abcdef01234567\n")
  local exe = string.format("%q", rt.exe)
  fs.write(project .. "/manifest.lua", table.concat({
    'global none', 'global <const> require', 'local task = require "task"',
    'task.tool "self" { exe = ' .. exe .. ', output = "lines" }',
    'task "hello" { desc = "a child through a declaration", run = function() return task.exec { tool = "self", "-e", "io.write(\'hi\')" } end }',
    'task "plain" { desc = "a plain child that fails", run = function() return task.exec { ' .. exe .. ', "-e", "os.exit(4)" } end }',
    'task "both" { deps = { "hello" }, run = function() end }',
    'task.default "both"',
  }, "\n") .. "\n")
  -- a day long gone, to be rotated away; its last line anchors the chain
  fs.mkdir(project .. "/.kuu/ledger")
  local old_line = '{"v":1,"kind":"verb","name":"run","status":"ok"}'
  fs.write(project .. "/.kuu/ledger/2020-01-01.ndjson", old_line .. "\n")

  local r = T.kuu({ "run" }, { cwd = project })
  check("the run succeeds and says nothing about the ledger", r.code == 0 and not contains(r.err, "ledger"), T.describe(r))
  local day = time.iso():sub(1, 10)
  local file = project .. "/.kuu/ledger/" .. day .. ".ndjson"
  local text = fs.read(file, { encoding = "utf-8" })
  check("the run wrote today's file, and the old day is gone",
    text ~= nil and #text > 0 and fs.exists(project .. "/.kuu/ledger/2020-01-01.ndjson") == false, tostring(file))
  local records, lines = {}, {}
  for line in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = line records[#records + 1] = json.decode(line) end
  check("one record per crossing: the child, its task, the aggregate, the verb, in that order",
    #records == 4 and records[1].kind == "child" and records[1].name == "self" and records[1].tool == "self" and records[1].task == "hello"
      and records[2].kind == "task" and records[2].name == "hello" and records[2].status == "ok"
      and records[3].kind == "task" and records[3].name == "both" and records[4].kind == "verb" and records[4].name == "run"
      and records[4].status == "ok" and records[4].code == 0, text)
  local child = records[1] or {}
  check("a child's record says what ran, as what, and how it ended, from what kuu observed",
    child.v == 1 and child.kuu == rt.version and child.root == project and type(child.pid) == "number"
      and child.argv and child.argv[1] == fs.absolute(rt.exe) and child.argv[2] == "-e" and child.status == "exit" and child.code == 0
      and child.bytes == nil and type(child.at) == "number" and type(child.seconds) == "number",
    lines[1])
  check("the repository's head is read from .git, no git assumed",
    child.git and child.git.ref == "refs/heads/main" and child.git.head == "0123456789abcdef0123456789abcdef01234567", lines[1])
  check("the first record of a run carries the delta since the previous run, and the others do not",
    child.delta and child.delta.added >= 1 and child.delta.removed == 0 and records[2].delta == nil and records[4].delta == nil,
    json.encode(child.delta))
  check("the chain starts from the line that was last, and each record hashes the one before it",
    child.prev == hash.sum("sha256", old_line) and records[2].prev == hash.sum("sha256", lines[1])
      and records[4].prev == hash.sum("sha256", lines[3]), lines[2])

  -- An edit between runs is what the next run's delta says it ran against.
  fs.mkdir(project .. "/src")
  fs.write(project .. "/src/new.lua", "return 1\n")
  r = T.kuu({ "run", "--json", "plain" }, { cwd = project })
  check("a failing run exits with the child's code", r.code == 4, T.describe(r))
  text = fs.read(file, { encoding = "utf-8" })
  records, lines = {}, {}
  for line in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = line records[#records + 1] = json.decode(line) end
  local second = records[5] or {}
  check("the second run's first record names the file added in between, with its content hash",
    #records == 7 and second.delta and second.delta.added == 1 and second.delta.changed == 0
      and second.delta.paths[1].path == "src/new.lua" and second.delta.paths[1].change == "added"
      and second.delta.paths[1].sha256 == hash.sum("sha256", "return 1\n"), json.encode(second.delta))
  check("a failed child, task and run are recorded as they ended, with the bytes kuu relayed under --json",
    second.status == "exit" and second.code == 4 and second.bytes and second.bytes.out == 0 and second.bytes.err == 0
      and records[6].kind == "task" and records[6].status == "failed"
      and records[6].error and records[6].error.code == "exit" and records[7].kind == "verb" and records[7].status == "failed"
      and records[7].code == 4, lines[7])
  local sound, count = ledger.verify(project)
  check("verify walks the chain and counts the records", sound == true and count == 7, tostring(count))
  local last = ledger.tail(project, 2)
  check("tail gives the last records, oldest first", #last == 2 and last[1].kind == "task" and last[2].kind == "verb")

  -- An edited line no longer hashes to what the next record says.
  local tampered = text:gsub('"status":"ok"', '"status":"okk"', 1)
  fs.write(file, tampered)
  local broken, why = ledger.verify(project)
  check("verify finds an edited record", broken == nil and err.is(why, "LEDGER", "broken"), tostring(why))

  -- capabilities shows the last crossings.
  r = T.kuu({ "capabilities", "--json" }, { cwd = project })
  local descriptor = json.decode(r.out)
  local shown = descriptor and descriptor.result.project.ledger
  check("capabilities carries the last crossings and the unaccounted count",
    shown ~= nil and #shown.last == 5 and shown.last[5].kind == "verb" and shown.last[5].status == "failed" and shown.unaccounted == 0,
    r.out:sub(1, 300))
  r = T.kuu({ "capabilities" }, { cwd = project })
  check("and says so in its text", contains(r.out, "ledger") and contains(r.out, "verb run failed"), r.out)
end
