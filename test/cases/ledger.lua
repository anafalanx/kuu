-- ledger.lua -- the door's memory: one record per crossing, chained across
-- days, rotated by age, with the tree delta between runs and the
-- repository's head read from .git without git.
global none
global <const> require, tostring, type, pcall, ipairs, pairs, string, table

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
    'global none', 'global <const> require, error', 'local task = require "task"',
    'task.tool "self" { exe = ' .. exe .. ', output = "lines" }',
    'task "hello" { desc = "a child through a declaration", run = function() return task.exec { tool = "self", "-e", "io.write(\'hi\')" } end }',
    'task "plain" { desc = "a plain child that fails", run = function() return task.exec { ' .. exe .. ', "-e", "os.exit(4)" } end }',
    'task "both" { deps = { "hello" }, run = function() end }',
    'task "bad" { desc = "fails with a message that is not UTF-8", run = function() error("caf\\xe9 broken") end }',
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

  check("the verb's record names the root and no cwd, since no call gave one", (records[7] or {}).root == project and (records[7] or {}).cwd == nil, lines[7])

  -- capabilities shows the last crossings and walks the chain.
  r = T.kuu({ "capabilities", "--json" }, { cwd = project })
  local descriptor = json.decode(r.out)
  local shown = descriptor and descriptor.result.project.ledger
  check("capabilities carries the last crossings, the chain's count and state, and the unaccounted count",
    shown ~= nil and #shown.last == 5 and shown.last[5].kind == "verb" and shown.last[5].status == "failed"
      and shown.records == 7 and shown.intact == true and shown.broken == nil and shown.unaccounted == 0,
    r.out:sub(1, 300))

  -- An edited line no longer hashes to what the next record says.
  local tampered = text:gsub('"status":"ok"', '"status":"okk"', 1)
  fs.write(file, tampered)
  local broken, why = ledger.verify(project)
  check("verify finds an edited record", broken == nil and err.is(why, "LEDGER", "broken"), tostring(why))
  r = T.kuu({ "capabilities", "--json" }, { cwd = project })
  descriptor = json.decode(r.out)
  shown = descriptor and descriptor.result.project.ledger
  check("capabilities finds the edited record and names the line",
    shown ~= nil and shown.intact == false and type(shown.broken) == "string" and contains(shown.broken, day .. ".ndjson:"), r.out:sub(1, 400))
  r = T.kuu({ "capabilities" }, { cwd = project })
  check("and says so in its text", contains(r.out, "ledger") and contains(r.out, "verb run failed") and contains(r.out, "the chain is broken"), r.out)

  -- A run that runs nothing writes nothing: the next real run's delta
  -- still names the edits it ran against.
  local before = fs.read(file)
  r = T.kuu({ "run", "nosuch" }, { cwd = project })
  local after_unknown = fs.read(file)
  r = T.kuu({ "run", "--dry-run" }, { cwd = project })
  check("an unknown task and --dry-run write no record", r.code == 0 and after_unknown == before and fs.read(file) == before, T.describe(r))

  -- The record is never a condition on the run, and what a task says is
  -- recorded as it is: a message that is not UTF-8 is recorded and
  -- reported with U+FFFD, not raised as an encoding error by the door.
  r = T.kuu({ "run", "bad" }, { cwd = project })
  check("a task failing with a message that is not UTF-8 is reported, not crashed on",
    r.code == 1 and contains(r.err, "bad failed after") and contains(r.err, "TASK failed") and not contains(r.err, "traceback")
      and not contains(r.err, "ledger"), T.describe(r))
  local tail = ledger.tail(project, 2)
  check("and its record carries the message with each bad byte replaced",
    #tail == 2 and tail[1].kind == "task" and tail[1].error and contains(tail[1].error.message, "caf\u{FFFD} broken")
      and tail[2].kind == "verb" and contains(tail[2].error.message, "caf\u{FFFD} broken"), json.encode(tail))
  r = T.kuu({ "run", "--json", "bad" }, { cwd = project })
  local stream = {}
  for line in r.out:gmatch("[^\n]+") do stream[#stream + 1] = json.decode(line) end
  local envelope = stream[#stream]
  check("under --json the same run ends on its envelope, the message cleaned the same way",
    r.code == 1 and envelope and envelope.ok == false and contains(envelope.error.message, "caf\u{FFFD} broken")
      and stream[#stream - 1].event == "task" and stream[#stream - 1].state == "finished", r.out)
  text = fs.read(file, { encoding = "utf-8" })
  check("a run against an unchanged tree names no path, and paths is still an array", contains(text, '"paths":[]'), text:sub(-600))

  -- What the tree holds is described, never a reason to stop: a name
  -- Windows would rewrite is one the hasher refuses, and the delta names
  -- it without its hash.
  local proc = require "proc"
  local dotted = "\\\\?\\" .. project:gsub("/", "\\") .. "\\dot."
  proc.run { "cmd.exe", "/c", "echo x> " .. dotted, timeout = "10s" }
  local listed = false
  for _, e in ipairs(fs.list(project).entries) do if e.name == "dot." then listed = true end end
  check("a file named with a trailing dot can be made", listed)
  r = T.kuu({ "run", "hello" }, { cwd = project })
  local first = ledger.tail(project, 3)[1] or {}
  local named
  for _, p in ipairs(first.delta and first.delta.paths or {}) do if p.path == "dot." then named = p end end
  check("the run starts, and the delta names the file without a hash",
    r.code == 0 and named ~= nil and named.change == "added" and named.sha256 == nil, json.encode(first.delta))
  proc.run { "cmd.exe", "/c", "del " .. dotted, timeout = "10s" }

  -- A junction under the root is listed and not entered, as fs.dirs does.
  local outside = fs.absolute(T.work .. "/ledger-outside")
  fs.remove(outside, { recursive = true })
  fs.mkdir(outside .. "/deep")
  fs.write(outside .. "/deep/far.txt", "far")
  fs.write(outside .. "/near.txt", "near")
  proc.run { "cmd.exe", "/c", "mklink /J " .. (project .. "/linked"):gsub("/", "\\") .. " " .. outside:gsub("/", "\\"), timeout = "10s" }
  local book = ledger.open(project)
  local entered = false
  for rel in pairs(book.tree) do if rel:match("^linked/") then entered = true end end
  check("a junction's files are not the root's", fs.exists(project .. "/linked") ~= false and not entered, json.encode(book.delta))
  fs.remove(project .. "/linked", { recursive = true })

  -- A worktree's .git is a file naming the real directory; its refs are
  -- in the common directory it names.
  local wt = fs.absolute(T.work .. "/ledger-worktree")
  fs.remove(wt, { recursive = true })
  fs.mkdir(wt)
  fs.mkdir(project .. "/.git/worktrees/wt")
  fs.write(project .. "/.git/refs/heads/feature", "fedcba9876543210fedcba9876543210fedcba98\n")
  fs.write(project .. "/.git/worktrees/wt/HEAD", "ref: refs/heads/feature\n")
  fs.write(project .. "/.git/worktrees/wt/commondir", "../..\n")
  fs.write(wt .. "/.git", "gitdir: " .. project .. "/.git/worktrees/wt\n")
  fs.write(wt .. "/manifest.lua", 'local task = require "task"\ntask "t" { run = function() end }\n')
  local worktree = ledger.open(wt)
  check("a worktree's head and branch are read through its .git file",
    worktree.git and worktree.git.ref == "refs/heads/feature" and worktree.git.head == "fedcba9876543210fedcba9876543210fedcba98",
    json.encode(worktree.git))

  -- A day of records is read once per run, not once per record, and the
  -- last line is found in one pass: two thousand records of a kilobyte
  -- took twelve seconds per record through a pattern anchored at the end.
  local bulk = {}
  for _ = 1, 2000 do bulk[#bulk + 1] = '{"v":1,"kind":"child","name":"' .. string.rep("x", 960) .. '","status":"exit"}' end
  fs.write(file, table.concat(bulk, "\n") .. "\n", { append = true })
  local began = require("sched").clock()
  r = T.kuu({ "run", "hello" }, { cwd = project })
  local took = require("sched").clock() - began
  local chained = ledger.tail(project, 3)
  check("a run against a day of two thousand records is chained to the last of them, quickly",
    r.code == 0 and took < 10 and #chained == 3 and chained[1].prev == hash.sum("sha256", bulk[#bulk])
      and chained[2].prev ~= nil and chained[3].kind == "verb", string.format("%.1fs %s", took, T.describe(r)))

  -- A root that cannot be listed is an empty tree, not a raised error.
  local opened, nowhere = pcall(ledger.open, T.work .. "/ledger-nowhere")
  check("opening the ledger of a root that is not there raises nothing", opened and nowhere.delta.added == 0, tostring(nowhere))
end
