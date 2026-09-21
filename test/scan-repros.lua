-- Step 01 known-defect reproductions; intentionally separate from test/run.lua.
-- Usage (from any cwd): kuu test/scan-repros.lua --exe PATH --out PATH
-- Optional: --fixture PATH supplies a prebuilt scan_fixture.exe. Otherwise
-- the checked-in native helper is compiled with the repo-local GCC.
-- Results and all disposable fixtures are retained under build/scan-repros-UUID.
-- Exit 0 means the harness completed, not that the observed defects are fixed.
-- Exit 2 means a harness/setup failure; unsupported OS probes are unconfirmed.
-- No project/runtime source is modified, and no fixture is recursively deleted.
global none
global <const> require, assert, error, pcall, pairs, ipairs, type, tostring, io, os

local fs, rt, proc = require "fs", require "rt", require "proc"
local json, hash, sys = require "json", require "hash", require "sys"
local sched, time, err = require "sched", require "time", require "err"
local ledger = require "_ledger"
local has_native_scan, native_scan = pcall(require, "_scan_native")
local versioned_tree = ledger.TREE_VERSION == 1
local script = fs.absolute(rt.program)
local repo = fs.absolute(assert(script:match("^(.*)/test/[^/]+$"), "keep this script under test/"))
local args, opts = rt.args, {}
local i = 1
while i <= #args do
  local key = args[i]
  assert(key == "--exe" or key == "--out" or key == "--fixture" or key == "--worker"
    or key == "--root" or key == "--control", "unknown argument: " .. key)
  assert(args[i + 1], "missing value for " .. key)
  assert(opts[key] == nil, "duplicate option: " .. key)
  opts[key] = args[i + 1]
  i = i + 2
end

local function command(argv)
  argv.timeout, argv.maxout = argv.timeout or "30s", "4M"
  local r, why = proc.run(argv)
  assert(r, tostring(why))
  assert(r.status == "exit" and not r.truncated, "child did not finish cleanly: " .. json.encode(r))
  return r
end
local function checked(argv)
  local r = command(argv)
  assert(r.code == 0, "child failed: " .. json.encode(r))
  return r
end
local function wait_file(path, child)
  local began = sched.clock()
  while not fs.exists(path) do
    if child and not child:running() then error("child exited before barrier: " .. json.encode(assert(child:wait()))) end
    assert(sched.clock() - began < 15, "barrier timed out: " .. path)
    sched.sleep("10ms")
  end
end
local function tree_path(root) return root .. "/.kuu/ledger/tree.json" end
local function read_tree(root) return assert(json.decode(assert(fs.read(tree_path(root))))) end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function write(path, value) assert(fs.write(path, value)) end
local function encode(path, value) write(path, json.encode(value) .. "\n") end
local function text_error(value) return value and tostring(value) or nil end
local function tree_files(state)
  if not versioned_tree then return state end
  assert(type(state) == "table" and state.kind == "kuu.tree" and state.v == 1
    and type(state.generation) == "number" and state.generation > 0 and state.generation % 1 == 0
    and state.complete == true and type(state.scope) == "table"
    and type(state.scope.fingerprint) == "string" and #state.scope.fingerprint == 64
    and type(state.files) == "table" and not json.is_array(state.files), "expected a complete versioned tree envelope")
  return state.files
end
local function honest_delta(book, status)
  local delta = book and book.delta
  return type(delta) == "table" and delta.complete == false and delta.status == status
    and delta.added == nil and delta.changed == nil and delta.removed == nil
    and type(delta.paths) == "table" and #delta.paths == 0
end
local function baseline_status(book, status)
  local observation = book and book.observation
  return type(observation) == "table" and type(observation.baseline) == "table"
    and observation.baseline.status == status
end
local function outcome_status(book, outcome, status)
  return type(outcome) == "table" and outcome.status == status
    and type(book.publication) == "table" and book.publication.status == status
end
local function classify(prerequisite, defect, acceptance)
  if not prerequisite then return "unconfirmed" end
  if defect then return "reproduced" end
  return acceptance and "not_reproduced" or "unconfirmed"
end

-- The delay changes scheduling only. Old builds pause before the real write;
-- versioned builds pause after the final real scan, before the publication
-- lock, so another process can publish without an artificial lock deadlock.
-- This does not measure naturally occurring race frequency.
if opts["--worker"] then
  local root, control = fs.absolute(assert(opts["--root"])), fs.absolute(assert(opts["--control"]))
  assert(root:find(repo .. "/build/scan-repros-", 1, true) == 1, "worker root is not owned")
  local owned = assert(root:match("^(.*)/[^/]+$"))
  assert(control:sub(1, #owned + 1) == owned .. "/", "worker controls are not owned")
  local book = ledger.open(root)
  if opts["--worker"] == "publisher-a" then
    if versioned_tree then
      assert(has_native_scan, "versioned ledger requires a native scan barrier")
      local original, paused = native_scan.collect, false
      native_scan.collect = function(path, options)
        local collected, why = original(path, options)
        if not paused and collected and fs.absolute(path) == root then
          paused = true
          local files = {}
          for _, file in ipairs(collected.files) do files[file.relative] = { size = file.size, mtime = file.mtime } end
          encode(control .. "/a-candidate.json", { files = files, initial = book.observation,
            barrier = "after final native scan, before publication lock", errors = collected.errors })
          write(control .. "/ready", "ready")
          wait_file(control .. "/release")
        end
        return collected, why
      end
    else
      local original = fs.write
      fs.write = function(path, bytes, options)
        if fs.absolute(path) == tree_path(root) then
          assert(original(control .. "/a-candidate.json", bytes))
          assert(original(control .. "/ready", "ready"))
          wait_file(control .. "/release")
        end
        return original(path, bytes, options)
      end
    end
  else
    assert(opts["--worker"] == "publisher-b", "unknown worker")
  end
  local ok, why = ledger.close(book)
  encode(control .. "/" .. opts["--worker"] .. ".json", { ok = ok == true,
    error = not ok and text_error(why) or nil, outcome = ok and why or nil,
    publication = book.publication, observation = book.observation, delta = book.delta })
  return
end

-- Re-execution makes the binary under observation unambiguous even when the
-- driver was initially launched through another kuu build.
if opts["--exe"] then
  local argv = { fs.absolute(opts["--exe"]), script }
  for _, key in ipairs { "--out", "--fixture" } do
    if opts[key] then argv[#argv + 1], argv[#argv + 2] = key, fs.absolute(opts[key]) end
  end
  argv.timeout = "5m"
  local r = command(argv)
  io.write(r.out)
  io.stderr:write(r.err)
  os.exit(r.code)
end

if ledger.VERSION >= 2 then
  io.stderr:write("scan-repros: historical snapshot reproduction requires a snapshot-era executable (--exe PATH).\n",
    "Current acceptance: kuu test/run.lua ledger_execution execution_acceptance scan_native check.\n")
  os.exit(2)
end

local work = repo .. "/build/scan-repros-" .. hash.uuid()
assert(not fs.exists(work), "fixture directory already exists")
assert(fs.mkdir(work))
local report = {
  v = 1, at = time.iso(), fixture_root = work,
  runtime = { exe = rt.exe, version = rt.version, sha256 = assert(hash.file("sha256", rt.exe)),
    signature = assert(sys.signature(rt.exe)), tree_version = ledger.TREE_VERSION },
  host = sys.info(), observations = json.array {}, harness_errors = json.array {},
  interpretation = "reproduced denotes a known defect observation; exit 0 denotes harness completion only",
}
local output = fs.absolute(opts["--out"] or (work .. "/results.json"))
local began = sched.clock()
local helper
local function setup()
  if opts["--fixture"] then helper = fs.absolute(opts["--fixture"])
  else
    helper = work .. "/scan_fixture.exe"
    local compiler = repo .. "/.tools/msys2/ucrt64/bin/gcc.exe"
    local built = checked { compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-municode", "-static", "-static-libgcc",
      "-o", helper, repo .. "/test/fixtures/scan_fixture.c", timeout = "60s",
      env = { PATH = repo .. "/.tools/msys2/ucrt64/bin;" .. (os.getenv("PATH") or "") } }
    report.helper_build = { compiler = compiler, elapsed = built.elapsed, out = built.out, err = built.err }
  end
  report.helper = { path = helper, sha256 = assert(hash.file("sha256", helper)),
    source_sha256 = assert(hash.file("sha256", repo .. "/test/fixtures/scan_fixture.c")) }
end
local function project(name, files)
  local root = work .. "/" .. name
  assert(fs.mkdir(root))
  for rel, text in pairs(files or { ["kept.txt"] = "this source still exists\n" }) do
    local path = root .. "/" .. rel
    local parent = assert(path:match("^(.*)/[^/]+$"))
    assert(fs.mkdir(parent))
    write(path, text)
  end
  return root
end
local function seed(root)
  local book = ledger.open(root)
  local closed, outcome = ledger.close(book)
  assert(closed, tostring(outcome))
  local state = read_tree(root)
  tree_files(state)
  if versioned_tree then
    assert(outcome_status(book, outcome, "published"), "seed was not positively published")
    local verified = ledger.open(root)
    assert(baseline_status(verified, "valid") and verified.delta.complete == true
      and verified.delta.added == 0 and verified.delta.changed == 0 and verified.delta.removed == 0,
      "seed did not establish a trustworthy unchanged baseline")
  end
  return state
end
local function observe(id, method, callback)
  local ok, value = pcall(callback)
  if not ok then
    report.harness_errors[#report.harness_errors + 1] = { id = id, error = tostring(value) }
    value = { status = "unconfirmed", evidence = { harness_error = tostring(value) } }
  end
  value.id, value.method = id, method
  assert(value.status == "reproduced" or value.status == "not_reproduced" or value.status == "unconfirmed")
  report.observations[#report.observations + 1] = value
  io.write(id, ": ", value.status, "\n")
  encode(work .. "/results.json", report)
end
local function with_hold(path, label, callback)
  local control = work .. "/hold-" .. label
  assert(fs.mkdir(control))
  local child <close> = assert(proc.start { helper, "hold", path, control .. "/ready", control .. "/release", timeout = "25s" })
  wait_file(control .. "/ready", child)
  local ok, value = pcall(callback)
  write(control .. "/release", "release")
  local ended = assert(child:wait("5s"))
  assert(ended.status == "exit" and ended.code == 0, json.encode(ended))
  if not ok then error(value) end
  return value
end

local setup_ok, setup_error = pcall(setup)
if not setup_ok then
  report.harness_errors[#report.harness_errors + 1] = { id = "setup", error = tostring(setup_error) }
else
  observe("junction-check-fix", "OS reproduction: a real junction to an owned sibling target; unmodified CLI check and check --fix", function()
    local root = project("junction-project", { ["manifest.lua"] = "global none\n" })
    local outside = project("junction-outside", { ["external.lua"] = "global none\nprint('outside')\n" })
    local before = assert(fs.read(outside .. "/external.lua"))
    local made = command { helper, "junction", root .. "/linked", outside }
    if made.code ~= 0 then return { status = "unconfirmed", evidence = { junction_creation = made } } end
    local link = assert(fs.link(root .. "/linked"))
    assert(link.type == "junction", "native fixture did not make a junction")
    local checked_result = command { rt.exe, "check", "--json", cwd = root }
    local fixed = command { rt.exe, "check", "--fix", cwd = root }
    local after = assert(fs.read(outside .. "/external.lua"))
    local envelope = json.decode(checked_result.out)
    local listed = checked_result.out:find("external.lua", 1, true) ~= nil
    local safely_checked = checked_result.code == 0 and fixed.code == 0 and envelope and envelope.ok
      and #envelope.result.files == 1 and not listed and after == before
    return { status = classify(true, after ~= before or listed, safely_checked), evidence = {
      project = root, outside = outside, junction = link, before = before, after = after,
      check = checked_result, fix = fixed, outside_listed = listed,
      outside_modified = after ~= before, successful_safe_check = safely_checked == true } }
  end)

  observe("unreadable-branch", "OS reproduction: exclusive directory handle, real fs.dirs/fs.list and ledger snapshots", function()
    local root = project("unreadable-branch", { ["src/kept.txt"] = "retained source", ["visible.txt"] = "visible" })
    local before = seed(root)
    local before_bytes = assert(fs.read(tree_path(root)))
    assert(tree_files(before)["src/kept.txt"], "seed lacks held-branch source")
    local result = with_hold(root .. "/src", "branch", function()
      local walk, walk_error = fs.dirs(root, { prune = ledger.PRUNE })
      local listing, listing_error = fs.list(root .. "/src")
      local book = ledger.open(root)
      local closed, close_error = ledger.close(book)
      local after = read_tree(root)
      local after_bytes = assert(fs.read(tree_path(root)))
      local denied = listing == nil or walk == nil or #walk.errors > 0
      local false_removed = type(book.delta.removed) == "number" and book.delta.removed > 0
      local preserved = before_bytes == after_bytes and tree_files(after)["src/kept.txt"] ~= nil
      local honest = versioned_tree and honest_delta(book, "incomplete") and baseline_status(book, "valid")
        and book.observation.scan.complete == false and #book.observation.scan.errors > 0
        and closed == true and outcome_status(book, close_error, "incomplete") and preserved
      local defect = versioned_tree and (false_removed or not preserved)
        or (not versioned_tree and false_removed and tree_files(after)["src/kept.txt"] == nil)
      return { status = classify(denied, defect, versioned_tree and honest or (not versioned_tree and not defect)),
        evidence = { directory_denial_observed = denied, walk = walk, walk_error = text_error(walk_error),
          listing = listing, listing_error = text_error(listing_error), delta = book.delta,
          observation = book.observation, publication = book.publication, before = before, published = after,
          baseline_bytes_preserved = preserved, honest_incomplete_observation = honest == true,
          close_ok = closed == true, close_outcome = closed and close_error or nil,
          close_error = not closed and text_error(close_error) or nil } }
    end)
    result.evidence.source_still_present = assert(fs.read(root .. "/src/kept.txt")) == "retained source"
    return result
  end)

  observe("partial-listing", "Fault injection: real enumeration with one entry removed and an explicit enumeration error", function()
    local root = project("partial-listing", { ["src/alpha.txt"] = "alpha", ["src/beta.txt"] = "beta" })
    local before = seed(root)
    local before_bytes = assert(fs.read(tree_path(root)))
    assert(tree_files(before)["src/beta.txt"], "seed lacks source targeted by injection")
    local target, key = has_native_scan and native_scan or fs, has_native_scan and "collect" or "list"
    local original, injected = target[key], false
    target[key] = function(path, options)
      local listing, why = original(path, options)
      if listing and has_native_scan and path == root then
        local entries = {}
        for _, entry in ipairs(listing.files) do if entry.relative ~= "src/beta.txt" then entries[#entries + 1] = entry end end
        listing.files = entries
        listing.errors[#listing.errors + 1] = { path = root .. "/src", win32 = 32, reason = "injected mid-enumeration failure" }
        injected = true
      elseif listing and not has_native_scan and path == root .. "/src" then
        local entries = {}
        for _, entry in ipairs(listing.entries) do if entry.name ~= "beta.txt" then entries[#entries + 1] = entry end end
        listing.entries, listing.errors = entries, { "injected mid-enumeration failure" }
        injected = true
      end
      return listing, why
    end
    local ok, book, closed, close_error = pcall(function()
      local b = ledger.open(root)
      local c, e = ledger.close(b)
      return b, c, e
    end)
    target[key] = original
    assert(ok, tostring(book))
    local after = read_tree(root)
    local preserved = before_bytes == assert(fs.read(tree_path(root))) and tree_files(after)["src/beta.txt"] ~= nil
    local false_removed = type(book.delta.removed) == "number" and book.delta.removed > 0
    local honest = versioned_tree and honest_delta(book, "incomplete") and baseline_status(book, "valid")
      and book.observation.scan.complete == false and #book.observation.scan.errors > 0
      and closed == true and outcome_status(book, close_error, "incomplete") and preserved
    local defect = versioned_tree and (false_removed or not preserved)
      or (not versioned_tree and false_removed and tree_files(after)["src/beta.txt"] == nil)
    return { status = classify(injected, defect, versioned_tree and honest or (not versioned_tree and not defect)),
      evidence = { before = before, delta = book.delta, published = after, close_ok = closed == true,
        injection_observed = injected, boundary = has_native_scan and "_scan_native.collect" or "fs.list", scan = book.scan,
        observation = book.observation, publication = book.publication, baseline_bytes_preserved = preserved,
        honest_incomplete_observation = honest == true, close_outcome = closed and close_error or nil,
        close_error = not closed and text_error(close_error) or nil,
        source_still_present = assert(fs.read(root .. "/src/beta.txt")) == "beta" } }
  end)

  observe("unreadable-tree-state", "OS reproduction: tree.json held with an exclusive native file handle", function()
    local root = project("unreadable-state")
    local before = seed(root)
    local before_bytes = assert(fs.read(tree_path(root)))
    local result = with_hold(tree_path(root), "state", function()
      local text, why = fs.read(tree_path(root))
      local ok, book = pcall(ledger.open, root)
      local denied = text == nil and err.is(why, "FS", "access")
      local closed, outcome
      if versioned_tree and ok then closed, outcome = ledger.close(book) end
      local exact_empty = ok and book.delta.added == count(tree_files(before))
      local honest = versioned_tree and ok and honest_delta(book, "unreadable") and baseline_status(book, "unreadable")
        and closed == true and outcome_status(book, outcome, "unreadable")
      return { status = classify(denied, exact_empty, versioned_tree and honest or (not versioned_tree and not exact_empty)),
        evidence = { read_denied = denied, read_error = text_error(why), before = before,
          opened = ok, delta = ok and book.delta or nil, observation = ok and book.observation or nil,
          publication = ok and book.publication or nil, close_ok = closed == true, close_outcome = closed and outcome or nil,
          close_error = not closed and text_error(outcome) or nil, honest_unreadable_state = honest == true,
          open_error = not ok and tostring(book) or nil } }
    end)
    result.evidence.baseline_bytes_preserved = assert(fs.read(tree_path(root))) == before_bytes
    if versioned_tree and not result.evidence.baseline_bytes_preserved then result.status = "reproduced" end
    return result
  end)

  observe("malformed-tree-records", "Real tree.json corruption: syntactically valid JSON with invalid per-file records", function()
    local root = project("malformed-records")
    local before = seed(root)
    local function corrupt_record(value)
      if not versioned_tree then return '{"kept.txt":' .. value .. '}\n' end
      local state = assert(json.decode(json.encode(before)))
      state.files["kept.txt"] = json.decode(value)
      return json.encode(state) .. "\n"
    end
    local cases, raised, accepted = json.array {}, false, true
    for _, value in ipairs { 'false', '17', '[]', '{}', '{"size":"not-a-number","mtime":false}' } do
      local corrupt_bytes = corrupt_record(value)
      write(tree_path(root), corrupt_bytes)
      local ok, book = pcall(ledger.open, root)
      raised = raised or not ok
      local unchanged = assert(fs.read(tree_path(root))) == corrupt_bytes
      local honest = versioned_tree and ok and honest_delta(book, "invalid")
        and baseline_status(book, "invalid") and book.observation.scan.complete == true and unchanged
      local closed, outcome, repaired
      if versioned_tree and ok then
        closed, outcome = ledger.close(book)
        local decoded, state = pcall(read_tree, root)
        local valid, files = false, nil
        if decoded then valid, files = pcall(tree_files, state) end
        repaired = closed == true and outcome_status(book, outcome, "published") and valid
          and type(files["kept.txt"]) == "table" and files["kept.txt"].size == assert(fs.stat(root .. "/kept.txt")).size
      end
      accepted = accepted and honest and repaired
      cases[#cases + 1] = { record_json = value, opened = ok, error = not ok and tostring(book) or nil,
        delta = ok and book.delta or nil, observation = ok and book.observation or nil,
        state_unchanged_by_open = unchanged, honest_invalid_state = honest == true,
        complete_rebaseline_published = repaired == true, close_ok = closed == true,
        close_outcome = closed and outcome or nil, close_error = not closed and text_error(outcome) or nil }
    end
    write(root .. "/manifest.lua", 'local task,fs=require "task",require "fs"\ntask "noop" {run=function() assert(fs.write("worked.txt","ran")) end}\n')
    write(tree_path(root), corrupt_record('false'))
    local public = command { rt.exe, "run", "--json", "noop", cwd = root }
    local ran = fs.read(root .. "/worked.txt") == "ran"
    local recorded, records = false, nil
    if versioned_tree then
      records = assert(ledger.tail(root, 100))
      local task_record, honest_record = false, false
      for _, record in ipairs(records) do
        if record.kind == "task" and record.name == "noop" then task_record = true end
        if record.delta and honest_delta({ delta = record.delta }, "invalid") then honest_record = true end
      end
      recorded = task_record and honest_record and ledger.verify(root) == true
      accepted = accepted and public.code == 0 and ran and recorded
    end
    return { status = classify(true, raised, versioned_tree and accepted or (not versioned_tree and not raised)), evidence = { cases = cases,
      public_run = public, public_task_still_executed = fs.read(root .. "/worked.txt") == "ran",
      public_crossings_recorded_with_honest_delta = recorded, public_records = records,
      public_run_qualification = versioned_tree and "task must execute and append verified crossings carrying an explicitly non-exact invalid-baseline delta"
        or "run catches the ledger.open exception, warns, and continues without recording crossings",
      criterion = versioned_tree and "every invalid record is diagnosed without an exception or false exact delta, followed by an explicit complete rebaseline"
        or "at least one malformed per-file record escapes ledger.open as an indexing exception" } }
  end)

  observe("malformed-tree-json", "Real tree.json corruption: truncated JSON and scalar top-level values", function()
    local root = project("malformed-json")
    local before = seed(root)
    local cases, empty, accepted = json.array {}, false, true
    for _, value in ipairs { '{"kept.txt":', 'false', '42', '[]' } do
      local corrupt_bytes = value .. "\n"
      write(tree_path(root), corrupt_bytes)
      local ok, book = pcall(ledger.open, root)
      local reset = ok and book.delta.added == count(tree_files(before))
      empty = empty or reset
      local unchanged = assert(fs.read(tree_path(root))) == corrupt_bytes
      local honest = versioned_tree and ok and honest_delta(book, "invalid") and baseline_status(book, "invalid")
        and book.observation.scan.complete == true and unchanged
      local closed, outcome, repaired
      if versioned_tree and ok then
        closed, outcome = ledger.close(book)
        local decoded, state = pcall(read_tree, root)
        local valid, files = false, nil
        if decoded then valid, files = pcall(tree_files, state) end
        repaired = closed == true and outcome_status(book, outcome, "published") and valid
          and type(files["kept.txt"]) == "table" and files["kept.txt"].size == assert(fs.stat(root .. "/kept.txt")).size
      end
      accepted = accepted and honest and repaired
      cases[#cases + 1] = { state_json = value, opened = ok, treated_as_empty = reset,
        error = not ok and tostring(book) or nil, delta = ok and book.delta or nil,
        observation = ok and book.observation or nil, state_unchanged_by_open = unchanged,
        honest_invalid_state = honest == true, complete_rebaseline_published = repaired == true,
        close_ok = closed == true, close_outcome = closed and outcome or nil,
        close_error = not closed and text_error(outcome) or nil }
    end
    return { status = classify(true, empty, versioned_tree and accepted or (not versioned_tree and not empty)), evidence = { before = before, cases = cases,
      criterion = "malformed state silently produces exact additions as though no predecessor existed" } }
  end)

  observe("stale-overlapping-publication", versioned_tree
    and "Deterministic instrumented two-process interleave: pause A after its final native scan, outside the publication lock; let B publish, then release A"
    or "Deterministic instrumented two-process interleave: pause A immediately before fs.write, let B scan/publish, release A; real snapshots and atomic writes", function()
    local root = project("overlapping")
    local seeded = seed(root)
    local control = project("overlap-control", {})
    local a <close> = assert(proc.start { rt.exe, script, "--worker", "publisher-a", "--root", root,
      "--control", control, timeout = "25s" })
    wait_file(control .. "/ready", a)
    local old_candidate = assert(json.decode(assert(fs.read(control .. "/a-candidate.json"))))
    local candidate_files = versioned_tree and old_candidate.files or old_candidate
    assert(candidate_files["kept.txt"] ~= nil and candidate_files["later.txt"] == nil,
      "A candidate lacks the seed or unexpectedly contains the future file")
    if versioned_tree then
      assert(old_candidate.initial.baseline.generation == seeded.generation and #old_candidate.errors == 0,
        "A did not collect from the seeded generation with a complete final scan")
    end
    write(root .. "/later.txt", "created after A's scan, before B's scan")
    local b = checked { rt.exe, script, "--worker", "publisher-b", "--root", root, "--control", control }
    local newer = read_tree(root)
    local newer_bytes = assert(fs.read(tree_path(root)))
    assert(tree_files(newer)["later.txt"] ~= nil, "B did not publish the later snapshot")
    local b_result = assert(json.decode(assert(fs.read(control .. "/publisher-b.json"))))
    if versioned_tree then
      assert(newer.generation > seeded.generation and b_result.ok
        and b_result.publication.status == "published", "B did not advance the generation")
    end
    write(control .. "/release", "release")
    local ended = assert(a:wait("5s"))
    assert(ended.status == "exit" and ended.code == 0, json.encode(ended))
    local final = read_tree(root)
    local final_bytes = assert(fs.read(tree_path(root)))
    local a_result = assert(json.decode(assert(fs.read(control .. "/publisher-a.json"))))
    local lost = tree_files(final)["later.txt"] == nil and a_result.ok
    local newer_preserved = final_bytes == newer_bytes
    local rejected = versioned_tree and a_result.ok and outcome_status(a_result, a_result.outcome, "stale")
      and newer_preserved and final.generation == newer.generation
    return { status = classify(true, lost or (versioned_tree and not newer_preserved),
      versioned_tree and rejected or (not versioned_tree and not lost)),
      evidence = { earlier_candidate = old_candidate, newer_publication = newer, final_publication = final,
        seed_generation = versioned_tree and seeded.generation or nil,
        newer_publication_bytes = newer_bytes, final_publication_bytes = final_bytes,
        newer_publication_bytes_preserved = newer_preserved, stale_candidate_explicitly_rejected = rejected == true,
        publisher_a = a_result, publisher_b = b, publisher_b_outcome = b_result,
        source_still_present = fs.exists(root .. "/later.txt") == "file",
        natural_race_frequency = "not measured; barrier controls scheduling without altering snapshot contents" } }
  end)
end

report.seconds = sched.clock() - began
report.complete = #report.harness_errors == 0
encode(work .. "/results.json", report)
if output ~= work .. "/results.json" then encode(output, report) end
io.write("results: ", output, "\nfixtures: ", work, "\n")
if not report.complete then os.exit(2) end
