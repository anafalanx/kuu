-- reporting.lua -- command-visible scan scope, completeness and elapsed
-- phases. Controlled delays test boundaries, not process-start benchmarks.
global none
global <const> require, assert, ipairs, pairs, type, table, math, pcall,
               error

return function(T)
  local check, contains = T.check, T.contains
  local fs, json, ledger = require "fs", require "json", require "_ledger"
  local proc, sched = require "proc", require "sched"
  local scratch = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "reporting-" })
  local function write(root, relative, contents)
    local path = root .. "/" .. relative
    assert(fs.mkdir(assert(path:match("^(.*)/[^/]+$"))))
    assert(fs.write(path, contents))
  end
  local function project(name, manifest)
    local root = scratch .. "/" .. name
    assert(fs.mkdir(root))
    write(root, ".gitignore", ".kuu/\n")
    write(root, "manifest.lua", manifest or 'global none\nglobal <const> require\nlocal task=require "task"\ntask "ok" {run=function() end}\ntask.default "ok"\n')
    return root
  end
  local function decoded_lines(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
      local value = json.decode(line)
      if not value then return nil end
      lines[#lines + 1] = value
    end
    return lines
  end
  local function envelope(result)
    local lines = decoded_lines(result.out)
    return lines and lines[#lines], lines
  end
  local function seconds(value)
    return type(value) == "number" and value >= 0 and value < math.huge
  end
  local function at_least(value, minimum)
    return seconds(value) and value >= minimum
  end
  local function near(a, b)
    return seconds(a) and seconds(b) and math.abs(a - b) < 0.000001
  end
  local function timing_shape(value)
    if type(value) ~= "table" or not seconds(value.setup) or not seconds(value.total) then return false end
    for _, measured in pairs(value) do if not seconds(measured) then return false end end
    return true
  end
  local function scan_shape(value)
    return type(value) == "table" and type(value.root) == "string" and type(value.start) == "string"
      and type(value.scope) == "table" and type(value.scope.fingerprint) == "string"
      and type(value.complete) == "boolean" and seconds(value.seconds) and type(value.counts) == "table"
      and type(value.counts.files) == "number" and type(value.counts.enumerated_dirs) == "number"
      and type(value.counts.excluded_dirs) == "number" and type(value.counts.nofollow_links) == "number"
      and type(value.counts.errors) == "number" and json.is_array(value.errors)
  end
  local function array_has(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
  end

  local basic = project("basic")
  write(basic, "src/module.lua", 'global none\nlocal M={answer=42}\nreturn M\n')
  write(basic, "README.md", "non-Lua source\n")
  write(basic, ".cache/hidden.lua", "this intentionally is not Lua\n")
  for _, command in ipairs { "run", "check", "capabilities" } do
    local result = T.kuu({ command, "--json" }, { cwd = basic })
    local doc, lines = envelope(result)
    check(command .. " JSON adds numeric timings without changing the existing envelope",
      result.code == 0 and doc and doc.ok == true and doc.result and timing_shape(doc.result.timings)
        and lines ~= nil, T.describe(result))
    check(command .. " keeps timing commentary quiet unless requested",
      not contains(result.err, "timings"), result.err)
    local timed = T.kuu({ command, "--json", "--timings" }, { cwd = basic })
    local timed_doc, timed_lines = envelope(timed)
    check(command .. " --timings writes human timing information to stderr and preserves JSON stdout",
      timed.code == 0 and timed_doc and timed_doc.ok and timed_lines ~= nil
        and timing_shape(timed_doc.result.timings) and contains(timed.err, "timings"), T.describe(timed))
    local human = T.kuu({ command, "--timings" }, { cwd = basic })
    check(command .. " human output supports the same opt-in timing flag",
      human.code == 0 and contains(human.err, "timings"), T.describe(human))
    local help = T.kuu({ command, "--help" }, { cwd = basic })
    check(command .. " help discovers the timing option", help.code == 0 and contains(help.out, "--timings"), T.describe(help))
  end

  local checked = T.kuu({ "check", "--json" }, { cwd = basic })
  local check_doc = assert(envelope(checked))
  local check_result, check_scan = check_doc.result, check_doc.result.scans[1]
  check("check exposes effective defaults and their default provenance",
    check_result.scope.source.kind == "default" and check_result.scope.defaults == true
      and array_has(check_result.scope.effective_dirs, ".cache")
      and array_has(check_result.scope.mandatory_dirs, ".git"), json.encode(check_result.scope))
  check("check reports native file counts separately from checked Lua files",
    check_result.complete == true and #check_result.scans == 1 and scan_shape(check_scan)
      and check_scan.complete and check_scan.root == basic and check_scan.start == basic
      and check_scan.counts.files == 4 and #check_result.files == 2 and check_scan.counts.excluded_dirs == 2,
    json.encode(check_result))
  check("check scan time is the observation time and checking is its containing phase",
    seconds(check_result.timings.scan) and seconds(check_result.timings.checking)
      and near(check_result.timings.scan, check_scan.seconds)
      and check_result.timings.checking >= check_result.timings.scan,
    json.encode(check_result.timings))
  local explicit = T.kuu({ "check", "--json", "src/module.lua" }, { cwd = basic })
  local explicit_doc = assert(envelope(explicit))
  check("an explicit file check does not invent a directory scan or scan duration",
    explicit.code == 0 and explicit_doc.result.complete and #explicit_doc.result.scans == 0
      and explicit_doc.result.timings.scan == nil and seconds(explicit_doc.result.timings.checking), explicit.out)
  local missing_after_scan = T.kuu({ "check", "--json", "src", "missing-dir" }, { cwd = basic })
  local missing_doc = assert(envelope(missing_after_scan))
  check("a missing later checker argument preserves reports, completed scans and elapsed work",
    missing_after_scan.code == 2 and not missing_doc.ok and missing_doc.error
      and #missing_doc.result.files == 1 and #missing_doc.result.scans == 1
      and missing_doc.result.files[1].path == "src/module.lua" and scan_shape(missing_doc.result.scans[1])
      and timing_shape(missing_doc.result.timings) and seconds(missing_doc.result.timings.scan), missing_after_scan.out)

  local configured = project("configured")
  write(configured, "kuu.config.json", '{"v":1,"scan":{"defaults":false,"exclude_dirs":["generated"]}}')
  write(configured, "generated/hidden.lua", "must stay unobserved\n")
  write(configured, ".cache/kept.lua", "global none\nreturn {visible=true}\n")
  local configured_run = T.kuu({ "run", "--json" }, { cwd = configured })
  local configured_doc = assert(envelope(configured_run))
  check("run validates configured projects without claiming a filesystem observation",
    configured_run.code == 0 and configured_doc.result.scope == nil and configured_doc.result.scans == nil
      and configured_doc.result.timings.initial_scan == nil and configured_doc.result.timings.final_scan == nil,
    configured_run.out)
  check("run reports recorded execution history alongside compatible task fields",
    configured_doc.result.ledger.complete and configured_doc.result.ledger.records == 2
      and configured_doc.result.ledger.error == nil and configured_doc.result.ledger.observation == nil
      and configured_doc.result.ledger.publication == nil
      and configured_doc.result.tasks[1].name == "ok" and configured_doc.result.tasks[1].ok == true
      and seconds(configured_doc.result.tasks[1].seconds), configured_run.out)

  local capabilities = T.kuu({ "capabilities", "--json" }, { cwd = configured })
  local capabilities_doc = assert(envelope(capabilities))
  local described = capabilities_doc.result.project
  check("capabilities retains inventory fields beside normalized scope and native counts",
    capabilities.code == 0 and described.scope.source.kind == "file" and scan_shape(described.scan)
      and described.scan.complete and described.modules_complete and described.files == 2
      and described.scan.counts.files == 4 and described.scan.counts.excluded_dirs == 2
      and json.is_array(described.modules) and #capabilities_doc.result.modules > 20, capabilities.out)
  check("capabilities measures inventory, ledger tail and ledger verification separately",
    timing_shape(capabilities_doc.result.timings) and seconds(capabilities_doc.result.timings.inventory)
      and seconds(capabilities_doc.result.timings.ledger_tail)
      and seconds(capabilities_doc.result.timings.ledger_verification), json.encode(capabilities_doc.result.timings))
  write(configured, "kuu.config.json", '{"v":1,"scan":{"defaults":false,"exclude_dirs":["generated"],"exclude_paths":["nested"]}}')
  local outside_start = scratch .. "/outside-start"
  write(outside_start, "nested/visible.lua", "global none\nreturn {}\n")
  write(outside_start, "generated/hidden.lua", "invalid source that must be excluded\n")
  local outside = T.kuu({ "check", "--json", outside_start }, { cwd = configured })
  local outside_doc = assert(envelope(outside))
  check("an explicit outside starting directory reports that project-relative path rules do not apply",
    outside.code == 0 and #outside_doc.result.scans == 1 and #outside_doc.result.files == 1
      and outside_doc.result.scans[1].root == configured and outside_doc.result.scans[1].start == outside_start
      and outside_doc.result.scans[1].path_rules_applied == false
      and outside_doc.result.scans[1].counts.excluded_dirs == 1, outside.out)

  local unreadable = project("unreadable-module", table.concat({
    'global none', 'global <const> require',
    'local task,fs,err,native,sched,ledger=require "task",require "fs",require "err",require "_scan_native",require "sched",require "_ledger"',
    'local read=fs.read',
    'fs.read=function(path,opts) if path:match("/unreadable%.lua$") then return nil,err.new("FS","access","injected module read failure") end return read(path,opts) end',
    'local collect,tail,verify=native.collect,ledger.tail,ledger.verify',
    'native.collect=function(root,opts) sched.sleep("100ms"); return collect(root,opts) end',
    'ledger.tail=function(root,n) sched.sleep("80ms"); return tail(root,n) end',
    'ledger.verify=function(root) sched.sleep("120ms"); return verify(root) end',
    'task "ok" {run=function() end}',
  }, "\n") .. "\n")
  write(unreadable, "unreadable.lua", "global none\nreturn {visible=true}\n")
  local unreadable_result = T.kuu({ "capabilities", "--json" }, { cwd = unreadable })
  local unreadable_doc = assert(envelope(unreadable_result))
  check("capabilities distinguishes complete metadata traversal from failed module source reading",
    unreadable_result.code == 0 and unreadable_doc.result.project.scan.complete
      and unreadable_doc.result.project.scan.counts.errors == 0
      and not unreadable_doc.result.project.modules_complete and #unreadable_doc.result.project.module_errors == 1
      and timing_shape(unreadable_doc.result.timings), unreadable_result.out)
  check("capabilities assigns delayed inventory, tail and verification work to their own phases",
    at_least(unreadable_doc.result.timings.inventory, 0.07) and at_least(unreadable_doc.result.project.scan.seconds, 0.07)
      and at_least(unreadable_doc.result.timings.ledger_tail, 0.05)
      and at_least(unreadable_doc.result.timings.ledger_verification, 0.09), json.encode(unreadable_doc.result.timings))

  local fix_root = project("fix")
  write(fix_root, "fixme.lua", 'global none\nprint("fixed")\n')
  local fixed = T.kuu({ "check", "--json", "--fix" }, { cwd = fix_root })
  local fixed_doc = assert(envelope(fixed))
  local fix_scan_total = 0
  for _, report in ipairs(fixed_doc.result.scans) do fix_scan_total = fix_scan_total + (seconds(report.seconds) and report.seconds or 0) end
  check("check --fix reports the original collection and its actual recheck",
    fixed.code == 0 and #fixed_doc.result.fixed == 1 and #fixed_doc.result.scans == 2
      and scan_shape(fixed_doc.result.scans[1]) and scan_shape(fixed_doc.result.scans[2])
      and seconds(fixed_doc.result.timings.fixing)
      and near(fixed_doc.result.timings.scan, fix_scan_total), fixed.out)
  write(fix_root, "broken.lua", "this is not valid Lua\n")
  local broken = T.kuu({ "check", "--json" }, { cwd = fix_root })
  local broken_doc = assert(envelope(broken))
  check("a syntax failure preserves complete observation and numeric phase reporting",
    broken.code == 1 and not broken_doc.ok and broken_doc.result.complete
      and broken_doc.result.errors > 0 and timing_shape(broken_doc.result.timings), broken.out)

  -- Manifest waiting is setup; child waiting is already in task duration
  -- and must not be added again. Opening and appending are the ledger work.
  local slow = project("phase-boundaries", table.concat({
    'global none', 'global <const> require,error',
    'local task,sched,native,ledger=require "task",require "sched",require "_scan_native",require "_ledger"',
    'sched.sleep("90ms")',
    'native.collect=function() error("run must not collect the project tree") end',
    'local open,record=ledger.open,ledger.record',
    'ledger.open=function(root) sched.sleep("110ms"); return open(root) end',
    'ledger.record=function(book,fields) sched.sleep(fields.kind=="verb" and "120ms" or "30ms"); return record(book,fields) end',
    'task "dependency" {run=function() sched.sleep("80ms") end}',
    'task "work" {deps={"dependency"},run=function() return task.exec {require("rt").exe,"-e",[[require("sched").sleep("120ms")]]} end}',
    'task.default "work"',
  }, "\n") .. "\n")
  local slow_run = T.kuu({ "run", "--json" }, { cwd = slow })
  local slow_doc = assert(envelope(slow_run))
  local phase = slow_doc.result.timings
  check("run timing reports manifest setup without initial or final scan phases",
    slow_run.code == 0 and at_least(phase.setup, 0.06) and phase.initial_scan == nil and phase.final_scan == nil
      and slow_doc.result.scope == nil and slow_doc.result.scans == nil, T.describe(slow_run))
  local task_seconds = 0
  for _, task in ipairs(slow_doc.result.tasks) do task_seconds = task_seconds + (seconds(task.seconds) and task.seconds or 0) end
  check("execution timing sums existing task durations once without adding child durations again",
    #slow_doc.result.tasks == 2 and at_least(phase.execution, 0.15)
      and near(phase.execution, task_seconds), T.describe(slow_run))
  check("ledger timing includes opening and delayed appends and remains a separate diagnostic phase",
    at_least(phase.ledger, 0.26) and seconds(phase.execution) and seconds(phase.total)
      and phase.total >= phase.ledger and phase.total >= phase.execution, T.describe(slow_run))
  local records = assert(ledger.tail(slow, 10))
  local child, verb
  for _, record in ipairs(records) do
    if record.kind == "child" then child = record elseif record.kind == "verb" then verb = record end
  end
  check("total includes the final append while verb and child duration boundaries remain intact",
    #records == 4 and child and at_least(child.seconds, 0.09) and verb and seconds(verb.seconds)
      and seconds(phase.total) and phase.total - verb.seconds >= 0.10
      and slow_doc.result.ledger.complete and slow_doc.result.ledger.records == 4
      and records[1].observation == nil and records[1].delta == nil,
    json.encode { phases = phase, records = records })

  local dry = T.kuu({ "run", "--json", "--dry-run" }, { cwd = basic })
  local dry_doc = assert(envelope(dry))
  check("dry-run reports only phases performed and preserves its plan schema",
    dry.code == 0 and timing_shape(dry_doc.result.timings) and #dry_doc.result.plan == 1
      and dry_doc.result.scope == nil and dry_doc.result.scans == nil and dry_doc.result.ledger == nil
      and dry_doc.result.timings.initial_scan == nil and dry_doc.result.timings.final_scan == nil
      and dry_doc.result.timings.execution == nil and dry_doc.result.timings.ledger == nil, dry.out)
  local fail_root = project("failed-task", 'global none\nglobal <const> require,error\nlocal task=require "task"\ntask "fail" {run=function() error("expected failure") end}\ntask.default "fail"\n')
  local failed = T.kuu({ "run", "--json" }, { cwd = fail_root })
  local failed_doc = assert(envelope(failed))
  check("a failed task retains timings, execution history and the existing error and task fields",
    failed.code == 1 and not failed_doc.ok and failed_doc.error and failed_doc.result.tasks[1].ok == false
      and timing_shape(failed_doc.result.timings) and seconds(failed_doc.result.timings.execution)
      and failed_doc.result.scans == nil and failed_doc.result.ledger.complete
      and failed_doc.result.ledger.records == 2, failed.out)
  local record_failed = project("failed-record", table.concat({
    'global none', 'global <const> require',
    'local task,ledger,err,sched=require "task",require "_ledger",require "err",require "sched"',
    'ledger.record=function() sched.sleep("80ms"); return nil,err.new("FS","access","injected record failure") end',
    'task "ok" {run=function() end}', 'task.default "ok"',
  }, "\n") .. "\n")
  local record_failure = T.kuu({ "run", "--json" }, { cwd = record_failed })
  local record_doc = assert(envelope(record_failure))
  check("a record failure reports incomplete history and time already spent on the ledger",
    record_failure.code == 0 and record_doc.ok and record_doc.result.scans == nil
      and record_doc.result.timings.initial_scan == nil and record_doc.result.timings.final_scan == nil
      and at_least(record_doc.result.timings.ledger, 0.06)
      and not record_doc.result.ledger.complete and record_doc.result.ledger.records == 0
      and record_doc.result.ledger.error ~= nil, record_failure.out)

  for _, mode in ipairs { "return", "raise" } do
    local open_failed = project("failed-open-" .. mode, table.concat({
      'global none', 'global <const> require,assert,error',
      'local task,ledger,err,fs=require "task",require "_ledger",require "err",require "fs"',
      'local mode=' .. json.encode(mode),
      'ledger.open=function()',
      '  if mode=="raise" then error("injected raw open failure",0) end',
      '  return nil,err.new("FS","access","injected classified open failure")',
      'end',
      'task "ok" {run=function() assert(fs.write("worked.txt","yes")) end}',
      'task.default "ok"',
    }, "\n") .. "\n")
    local opened = T.kuu({ "run", "--json" }, { cwd = open_failed })
    local opened_doc = assert(envelope(opened))
    local summary = opened_doc.result.ledger
    local _, warnings = opened.err:gsub("kuu: warning:", "")
    check("a ledger open " .. mode .. " failure preserves task success and reports zero recorded crossings once",
      opened.code == 0 and opened_doc.ok and #opened_doc.result.tasks == 1 and opened_doc.result.tasks[1].ok
        and fs.read(open_failed .. "/worked.txt") == "yes"
        and summary and summary.complete == false and summary.records == 0
        and type(summary.error) == "table" and type(summary.error.message) == "string"
        and #opened_doc.result.notes == 1 and warnings == 1
        and contains(opened_doc.result.notes[1], "the ledger was not opened")
        and seconds(opened_doc.result.timings.ledger) and #assert(ledger.tail(open_failed, 10)) == 0,
      T.describe(opened))
    check("a ledger open " .. mode .. " failure keeps its actual diagnostic shape",
      summary and summary.error and (mode == "return"
        and summary.error.domain == "FS" and summary.error.code == "access"
        and summary.error.message == "injected classified open failure"
        or mode == "raise" and summary.error.domain == nil and summary.error.code == nil
        and summary.error.message == "injected raw open failure"), opened.out)
  end

  for _, outcome in ipairs { "ok", "failed" } do
    local partial_root = project("partial-record-" .. outcome, table.concat({
      'global none', 'global <const> require,assert,error,tostring',
      'local task,ledger,err,fs=require "task",require "_ledger",require "err",require "fs"',
      'local outcome=' .. json.encode(outcome),
      'local original,calls=ledger.record,0',
      'ledger.record=function(book,fields)',
      '  calls=calls+1; assert(fs.write("record-attempts.txt",tostring(calls)))',
      '  if calls==2 then return nil,err.new("FS","access","injected second append failure") end',
      '  return original(book,fields)',
      'end',
      'task "prepared" {run=function() end}',
      'task "work" {deps={"prepared"},run=function()',
      '  assert(fs.write("worked.txt","yes"))',
      '  if outcome=="failed" then error("original task failure",0) end',
      'end}', 'task.default "work"',
    }, "\n") .. "\n")
    local partial_run = T.kuu({ "run", "--json" }, { cwd = partial_root })
    local partial_doc = assert(envelope(partial_run))
    local summary = partial_doc.result.ledger
    local _, warnings = partial_run.err:gsub("kuu: warning:", "")
    local successful = outcome == "ok"
    check("a partial append failure preserves the " .. outcome .. " task outcome and warns only once",
      partial_run.code == (successful and 0 or 1) and partial_doc.ok == successful
        and #partial_doc.result.tasks == 2 and partial_doc.result.tasks[1].ok
        and partial_doc.result.tasks[2].ok == successful
        and (successful or partial_doc.error and contains(partial_doc.error.message, "original task failure"))
        and fs.read(partial_root .. "/worked.txt") == "yes"
        and fs.read(partial_root .. "/record-attempts.txt") == "2"
        and #partial_doc.result.notes == 1 and warnings == 1
        and contains(partial_doc.result.notes[1], "injected second append failure"), T.describe(partial_run))
    local kept = assert(ledger.tail(partial_root, 10))
    local intact, count = ledger.verify(partial_root)
    check("a partial append failure counts only the successfully stored crossing for a " .. outcome .. " task",
      summary and summary.complete == false and summary.records == 1 and summary.error
        and summary.error.domain == "FS" and summary.error.code == "access"
        and summary.error.message == "injected second append failure"
        and #kept == 1 and kept[1].kind == "task" and kept[1].name == "prepared"
        and intact == true and count == 1, partial_run.out)
  end

  local argument_root = project("task-argument", table.concat({
    'global none', 'global <const> require,tostring',
    'local task,fs=require "task",require "fs"',
    'task "argument" {args={{"--timings",type="flag"}},run=function(opts) fs.write("forwarded.txt",tostring(opts.timings)) end}',
  }, "\n") .. "\n")
  local forwarded = T.kuu({ "run", "--json", "argument", "--timings" }, { cwd = argument_root })
  check("--timings after the task name remains the task's argument",
    forwarded.code == 0 and fs.read(argument_root .. "/forwarded.txt") == "true"
      and not contains(forwarded.err, "kuu: timings"), T.describe(forwarded))
  local task_help = T.kuu({ "run", "--json", "--timings", "argument", "--help" }, { cwd = argument_root })
  check("task help remains plain stdout without runner timing commentary",
    task_help.code == 0 and contains(task_help.out, "usage: kuu run argument")
      and not contains(task_help.err, "timings") and decoded_lines(task_help.out) == nil, T.describe(task_help))

  local bad_config = project("bad-config")
  write(bad_config, "kuu.config.json", "{broken")
  for _, command in ipairs { "run", "check", "capabilities" } do
    local result = T.kuu({ command, "--json" }, { cwd = bad_config })
    local doc = assert(envelope(result))
    local phases = doc.result and doc.result.timings
    local scope = command == "capabilities" and doc.result.project.scope or doc.result.scope
    check(command .. " configuration failures report elapsed setup without pretending to scan",
      timing_shape(phases) and scope == nil and phases.initial_scan == nil and phases.final_scan == nil
        and phases.scan == nil and phases.inventory == nil and phases.execution == nil,
      T.describe(result))
  end

  local partial = project("partial")
  write(partial, "branch/hidden.lua", 'global none\nreturn {hidden=true}\n')
  local helper = fs.absolute(T.root .. "/build/test/scan_fixture.exe")
  check("reporting tests have the real Windows sharing-denial fixture", fs.exists(helper) == "file", helper)
  if fs.exists(helper) == "file" then
    local control = scratch .. "/hold-control"
    assert(fs.mkdir(control))
    local child_handle <close> = assert(proc.start { helper, "hold", partial .. "/branch", control .. "/ready", control .. "/release", timeout = "25s" })
    local held_ok, held_error = pcall(function()
      local started = sched.clock()
      while not fs.exists(control .. "/ready") do
        assert(child_handle:running(), "native hold exited before readiness")
        assert(sched.clock() - started < 10, "native hold barrier timeout")
        sched.sleep("10ms")
      end
      for _, command in ipairs { "run", "check", "capabilities" } do
        local result = T.kuu({ command, "--json" }, { cwd = partial })
        local doc = assert(envelope(result))
        if command == "run" then
          check("a locked unrelated source directory does not affect task execution or ledger completeness",
            result.code == 0 and doc.ok and doc.result.ledger.complete and doc.result.ledger.records == 2
              and doc.result.scans == nil and doc.result.timings.initial_scan == nil
              and doc.result.timings.final_scan == nil and #doc.result.notes == 0, result.out)
        else
          local report = command == "check" and doc.result.scans[1] or doc.result.project.scan
          check(command .. " exposes incomplete scan counts, native errors and elapsed observation time",
            timing_shape(doc.result.timings) and scan_shape(report) and not report.complete
              and report.counts.errors > 0 and #report.errors > 0 and report.errors[1].win32 == 32,
            T.describe(result))
          if command == "check" then
            check("check marks incomplete observation on its aggregate report",
              result.code == 1 and not doc.result.complete, result.out)
          else
            check("capabilities keeps incomplete inventory distinct from palette availability",
              result.code == 0 and not doc.result.project.modules_complete and #doc.result.modules > 20, result.out)
          end
        end
      end
    end)
    assert(fs.write(control .. "/release", "release"))
    local ended = assert(child_handle:wait("5s"))
    check("reporting sharing-denial fixture releases its handle", ended.status == "exit" and ended.code == 0, T.describe(ended))
    if not held_ok then error(held_error) end
  end

  local away = assert(fs.tempdir { prefix = "kuu-reporting-away-" })
  local away_result = T.kuu({ "capabilities", "--json" }, { cwd = away })
  local away_doc = assert(envelope(away_result))
  check("capabilities outside a project omits phases that need a project",
    away_result.code == 0 and away_doc.result.project == nil and timing_shape(away_doc.result.timings)
      and away_doc.result.timings.inventory == nil and away_doc.result.timings.ledger_tail == nil
      and away_doc.result.timings.ledger_verification == nil, away_result.out)
  assert(fs.remove(away, { recursive = true }))
  assert(fs.remove(scratch, { recursive = true }))
end
