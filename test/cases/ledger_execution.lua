-- ledger_execution.lua -- execution history does not survey project files.
-- Legacy observation bytes remain historical data, never active tree state.
global none
global <const> require, assert, ipairs, pcall, error, tostring, table

return function(T)
  local check = T.check
  local fs, json, hash, time = require "fs", require "json", require "hash", require "time"
  local ledger, err = require "_ledger", require "err"
  local scan, policy, native = require "_scan", require "_scan_policy", require "_scan_native"
  local scratch = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "ledger-execution-" })
  local today = time.iso():sub(1, 10)
  local function project(name)
    local root = scratch .. "/" .. name
    assert(fs.mkdir(root .. "/.kuu/ledger"))
    return root
  end
  local function crossing(name)
    return { kind = "task", name = name, status = "ok", at = 1, seconds = 0 }
  end
  local function append(book, name) assert(ledger.record(book, crossing(name))) end
  local function rows(root)
    local lines = {}
    for line in assert(fs.read(root .. "/.kuu/ledger/" .. today .. ".ndjson")):gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
    return lines
  end

  local root = project("no-observation")
  assert(fs.mkdir(root .. "/src"))
  assert(fs.mkdir(root .. "/.git/refs/heads"))
  assert(fs.write(root .. "/src/secret.txt", "source contents are not execution history"))
  assert(fs.write(root .. "/kuu.config.json", "malformed scan configuration is irrelevant to the ledger"))
  assert(fs.write(root .. "/.git/HEAD", "ref: refs/heads/main\n"))
  assert(fs.write(root .. "/.git/refs/heads/main", "0123456789012345678901234567890123456789\n"))
  local old_trees = {
    '{"source.txt":{"size":1,"mtime":1}}',
    '{"kind":"kuu.tree","v":999,"future":"leave untouched"}',
    '{malformed old tree',
  }
  for index, old_tree in ipairs(old_trees) do
    assert(fs.write(root .. "/.kuu/ledger/tree.json", old_tree))
    local calls, originals = {}, {}
    local function prohibited(operation, path)
      calls[#calls + 1] = operation .. ": " .. tostring(path)
      error("unexpected project observation: " .. calls[#calls], 0)
    end
    for _, name in ipairs { "read", "write", "stat", "remove" } do
      local original = fs[name]
      originals[name] = original
      fs[name] = function(path, ...)
        if path == root .. "/.kuu/ledger/tree.json" or path == root .. "/kuu.config.json"
            or path == root .. "/src" or path:sub(1, #root + 5) == root .. "/src/" then
          return prohibited(name, path)
        end
        return original(path, ...)
      end
    end
    originals.list, originals.dirs, originals.hash_file = fs.list, fs.dirs, hash.file
    originals.scan, originals.policy, originals.native = scan.collect, policy.load, native.collect
    fs.list = function(path, ...)
      if path ~= root .. "/.kuu/ledger" then return prohibited("list", path) end
      return originals.list(path, ...)
    end
    fs.dirs = function(path) return prohibited("dirs", path) end
    hash.file = function(_, path) return prohibited("hash.file", path) end
    scan.collect = function(path) return prohibited("scan.collect", path) end
    policy.load = function(path) return prohibited("policy.load", path) end
    native.collect = function(path) return prohibited("native.collect", path) end
    local ran, book, recent, intact, count = pcall(function()
      local opened = ledger.open(root)
      append(opened, "without-observation-" .. index)
      local last = assert(ledger.tail(root, 1))
      local valid, amount = ledger.verify(root)
      return opened, last, valid, amount
    end)
    for _, name in ipairs { "read", "write", "stat", "remove", "list", "dirs" } do fs[name] = originals[name] end
    hash.file, scan.collect, policy.load, native.collect = originals.hash_file, originals.scan, originals.policy, originals.native
    check("ledger open, append and readers never access project scans, config or old tree: " .. index,
      ran and #calls == 0 and intact and count == index, ran and table.concat(calls, "\n") or tostring(book))
    check("legacy, future and malformed tree bytes are all preserved: " .. index,
      fs.read(root .. "/.kuu/ledger/tree.json") == old_tree)
    check("execution-only books and records carry no observation state: " .. index,
      ran and book.written == 1 and book.tree == nil and book.scope == nil and book.delta == nil
        and book.scan == nil and book.observation == nil and book.publication == nil and ledger.close == nil
        and #recent == 1 and recent[1].v == 2 and recent[1].delta == nil and recent[1].observation == nil,
      ran and json.encode(recent) or tostring(book))
    check("best-effort Git context remains in an execution-only record: " .. index,
      ran and recent[1] and recent[1].git and recent[1].git.ref == "refs/heads/main"
        and recent[1].git.head == "0123456789012345678901234567890123456789",
      ran and json.encode(recent) or tostring(book))
  end

  local original_read = fs.read
  for _, raises in ipairs { false, true } do
    fs.read = function(path, ...)
      if path == root .. "/.git/HEAD" then
        local why = err.new("FS", "access", "Git metadata is unavailable")
        if raises then error(why, 0) end
        return nil, why
      end
      return original_read(path, ...)
    end
    local opened, book = pcall(ledger.open, root)
    fs.read = original_read
    check("Git metadata failure does not prevent opening execution history: " .. tostring(raises),
      opened and book.git == nil and book.root == root, tostring(book))
  end
  local before_directory = scratch .. "/open-only"
  assert(fs.mkdir(before_directory))
  local empty = ledger.open(before_directory)
  check("opening history alone creates no state or history directory",
    empty.written == 0 and fs.exists(before_directory .. "/.kuu") == false)

  -- Keep exact legacy bytes, including whitespace and retired fields.
  local legacy = project("legacy-v1")
  local yesterday = time.iso(time.now() - 86400):sub(1, 10)
  local old_line = '{ "v":1, "kuu":"0.11", "root":"legacy", "kind":"verb", "name":"run",'
    .. ' "status":"ok", "at":1, "seconds":0, "delta":{"added":1,"paths":[{"path":"old.txt"}]},'
    .. ' "observation":{"baseline":{"status":"valid"}} }'
  local old_path = legacy .. "/.kuu/ledger/" .. yesterday .. ".ndjson"
  assert(fs.write(old_path, old_line .. "\n"))
  local newer = ledger.open(legacy)
  append(newer, "new-one")
  append(newer, "new-two")
  local newer_lines = rows(legacy)
  local combined = assert(ledger.tail(legacy, 3))
  local valid, amount = ledger.verify(legacy)
  check("v2 appends chain from exact v1 bytes across days without rewriting history",
    valid and amount == 3 and fs.read(old_path) == old_line .. "\n"
      and combined[2].prev == hash.sum("sha256", old_line)
      and combined[3].prev == hash.sum("sha256", newer_lines[1]), json.encode(combined))
  check("mixed history preserves retired fields only on historical v1 records",
    #combined == 3 and combined[1].v == 1 and combined[1].delta.paths[1].path == "old.txt"
      and combined[1].observation.baseline.status == "valid"
      and combined[2].v == 2 and combined[2].delta == nil and combined[2].observation == nil
      and combined[3].v == 2 and combined[3].delta == nil and combined[3].observation == nil,
    json.encode(combined))

  local stale = crossing("stale-private-caller")
  stale.v, stale.delta, stale.observation = 1, { added = 7 }, { baseline = { status = "valid" } }
  assert(ledger.record(newer, stale))
  local sanitized = assert(ledger.tail(legacy, 1))[1]
  check("retired private caller fields cannot restore observations or downgrade newly written history",
    sanitized.v == 2 and sanitized.delta == nil and sanitized.observation == nil
      and stale.v == 1 and stale.delta.added == 7 and stale.observation.baseline.status == "valid"
      and ledger.verify(legacy) == true, json.encode(sanitized))

  local unsupported = project("unknown-version")
  for _, version in ipairs { 0, 3, 999, "2" } do
    local record = crossing("unknown")
    record.v, record.kuu, record.root = version, "0.11", unsupported
    local text = json.encode(record) .. "\n"
    local path = unsupported .. "/.kuu/ledger/" .. today .. ".ndjson"
    assert(fs.write(path, text))
    local verified, why = ledger.verify(unsupported)
    local recent = assert(ledger.tail(unsupported, 5))
    check("readers reject unknown schema versions without rewriting them: " .. tostring(version),
      verified == nil and err.is(why, "LEDGER", "broken") and #recent == 0 and fs.read(path) == text, tostring(why))
  end

  -- Two independently opened books can interleave. The first book must
  -- discard its cached predecessor after another book has appended.
  local interleaved = project("interleaved-books")
  local outer, inner = ledger.open(interleaved), ledger.open(interleaved)
  append(outer, "outer-before")
  append(inner, "inner-one")
  append(inner, "inner-two")
  append(outer, "outer-after")
  append(inner, "inner-after")
  local interleaved_lines = rows(interleaved)
  local recent = assert(ledger.tail(interleaved, 5))
  local sound, records = ledger.verify(interleaved)
  local ordered = #recent == 5
  for index, name in ipairs { "outer-before", "inner-one", "inner-two", "outer-after", "inner-after" } do
    ordered = ordered and recent[index].name == name
    if index > 1 then ordered = ordered and recent[index].prev == hash.sum("sha256", interleaved_lines[index - 1]) end
  end
  check("interleaved books refresh their predecessor without breaking nested execution order",
    sound and records == 5 and ordered and outer.written == 2 and inner.written == 3, json.encode(recent))

  assert(fs.remove(scratch, { recursive = true }))
end
