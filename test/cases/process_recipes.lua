-- Exercise the published process modules and their actual child-history boundary.
global none
global <const> require, assert, ipairs, load, tostring, pcall

return function(T)
  local fs, json, err = require "fs", require "json", require "err"
  local proc, task, ledger = require "proc", require "task", require "_ledger"
  local check = T.check
  local root = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "process-recipes-" })
  assert(fs.copy(T.exe, root .. "/kuu.exe"))
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/process-recipes.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = source
  end
  check("process guide contains four complete executable blocks", #blocks == 4)
  if #blocks ~= 4 then return end
  for i, name in ipairs { "process_ops.lua", "probe.lua", "manifest.lua", "describe.lua" } do
    assert(fs.write(root .. "/" .. name, blocks[i]))
  end
  local lint = T.kuu({ "check", "--json", "." }, { cwd = root })
  local checked = json.decode(lint.out)
  check("all published process recipe blocks pass static checking", lint.code == 0 and checked
    and checked.result.errors == 0 and checked.result.warnings == 0, T.describe(lint))
  local ops = assert(load(blocks[1], "@process_ops.lua", "t"))()

  local description = T.kuu({ "describe.lua" }, { cwd = root })
  local described = json.decode(description.out)
  check("process description resolves the declared tool and preserves a JSON argv array", description.code == 0
    and described and json.is_array(described.argv) and #described.argv == 3
    and described.argv[1] == fs.join(root, "kuu.exe")
    and described.argv[2] == fs.join(root, "probe.lua") and described.argv[3] == "changed"
    and described.cwd == root and described.env.PROBE_MODE == "local" and described.env.PROBE_UNUSED == false,
    T.describe(description))
  check("describing a command does not execute tasks or write a ledger", fs.exists(root .. "/.kuu/ledger") == false)
  local spec = { T.exe, "space quote\" argument", cwd = root, env = { VALUE = "kept", REMOVED = false } }
  local desc = ops.describe(spec)
  local encoded = json.encode(desc)
  desc.argv[2], desc.env.VALUE = "changed", "changed"
  check("description copies argv and environment without mixing JSON shapes", T.contains(encoded, '"argv":[')
    and spec[2] == 'space quote" argument' and spec.env.VALUE == "kept" and desc.cwd == root)
  local empty = ops.describe { T.exe }
  check("unspecified environment is an object and cwd is the actual absolute cwd",
    T.contains(json.encode(empty), '"env":{}') and empty.cwd == fs.absolute(fs.cwd()))
  local mixed, invalid = pcall(json.encode, spec)
  check("mixed process tables still fail strict JSON encoding", not mixed and err.is(invalid, "JSON", "badvalue"), tostring(invalid))

  local function command(mode)
    return { T.exe, root .. "/probe.lua", mode, cwd = root, timeout = "5s", maxout = "1K" }
  end
  local result, why = ops.capture(command("same"), { [3] = true })
  check("captured zero exit retains exact output", result and result.status == "exit" and result.code == 0
    and result.out == "unchanged\n" and result.err == "", tostring(why))
  result, why = ops.capture(command("changed"), { [3] = true })
  check("captured documented nonzero success retains its original code", result and result.code == 3
    and result.out == "updated\n", tostring(why))
  result, why = ops.capture(command("changed"))
  check("a nonzero exit requires an explicit success policy", result == nil and err.is(why, "PROJECT", "exit")
    and why.exit == 3 and why.result.code == 3, tostring(why))
  local failed = command("failed")
  failed.env = { RECIPE_SECRET = "not-for-errors" }
  result, why = ops.capture(failed, { [3] = true })
  check("failure preserves actual stderr, output, code, argv and cwd", result == nil and err.is(why, "PROJECT", "exit")
    and why.exit == 9 and why.result.out == "partial output\n"
    and why.result.err == "probe could not finish its work\n"
    and T.contains(why.message, "stderr:\nprobe could not finish its work\n")
    and T.contains(why.message, '"argv":[') and T.contains(why.message, json.encode(root))
    and not T.contains(why.message, "not-for-errors") and not T.contains(why.message, "partial output"), tostring(why))
  result, why = ops.capture(command("loud"))
  check("a truncated zero exit is refused while retaining the captured prefix", result == nil
    and err.is(why, "PROJECT", "truncated") and why.result.code == 0 and why.result.truncated
    and #why.result.out == 1024 and T.contains(why.message, "[captured output truncated]"), tostring(why))
  local slow = command("slow")
  slow.timeout = "500ms"
  result, why = ops.capture(slow, { [0] = true, [1] = true })
  check("real timeout is failure and retains stderr produced before the deadline", result == nil
    and err.is(why, "PROJECT", "timeout") and why.result.status == "timeout"
    and why.result.err == "probe began waiting\n", tostring(why))
  local missing = { root .. "/missing-program.exe", cwd = root }
  result, why = ops.capture(missing)
  check("launch failure preserves its classified cause and command context", result == nil
    and err.is(why, "PROJECT", "launch") and err.is(why.cause, "PROC", "notfound")
    and why.result == nil and T.contains(why.message, "missing-program.exe"), tostring(why))
  result, why = ops.capture { fs.absolute(T.root .. "/build/test/limits_fixture.exe"), "memory",
    cwd = root, timeout = "8s", limits = { memory = "64M" } }
  check("real job limit remains failure with its named bound and captured diagnostics", result == nil
    and err.is(why, "PROJECT", "limit") and why.result.status == "limit" and why.result.limit == "memory"
    and T.contains(why.message, "limit (memory)"), tostring(why))

  -- Control fixtures prove branch ordering independently of OS-specific exit codes.
  local real_run = proc.run
  for _, status in ipairs { "timeout", "killed", "limit" } do
    local synthetic = { status = status, limit = status == "limit" and "memory" or nil,
      code = 3, out = "", err = "diagnostic prefix", truncated = true }
    proc.run = function() return synthetic end
    local called, value, failure = pcall(ops.capture, command("same"), { [3] = true })
    proc.run = real_run
    check("status precedes accepted code and truncation for " .. status, called and value == nil
      and err.is(failure, "PROJECT", status) and failure.result == synthetic
      and T.contains(failure.message, "diagnostic prefix")
      and T.contains(failure.message, "[captured output truncated]"), tostring(failure))
  end
  local real_exec = task.exec
  local launch_error = err.new("PROC", "launch", "fixture launch failure")
  local timeout_error = err.new("TASK", "failed", "fixture timeout", { status = "timeout", exit = 3 })
  for _, failure in ipairs { launch_error, timeout_error } do
    task.exec = function() return nil, failure end
    local called, value, retained = pcall(ops.exec_success, command("same"), { [3] = true })
    task.exec = real_exec
    check("stream classifier preserves non-exit errors by identity: " .. failure.code,
      called and value == nil and retained == failure, tostring(retained))
  end

  local streamed = T.kuu({ "run", "--json", "stream", "changed" }, { cwd = root })
  local rows = assert(ledger.tail(root, 10))
  local child, enclosing = 0, 0
  for _, row in ipairs(rows) do
    if row.kind == "child" then
      child = child + 1
      check("accepted streamed child history keeps actual code, tool and task", row.status == "exit"
        and row.code == 3 and row.tool == "probe" and row.task == "stream", json.encode(row))
    elseif row.status == "ok" then enclosing = enclosing + 1 end
  end
  check("streamed nonzero success leaves one child and successful task/run history", streamed.code == 0
    and child == 1 and enclosing == 2 and #rows == 3 and ledger.verify(root) == true, T.describe(streamed))
  local child_events = 0
  for line in streamed.out:gmatch("[^\r\n]+") do
    local event = json.decode(line)
    if event and event.event == "child" then child_events = child_events + 1 end
  end
  check("streamed accepted child remains visible in JSON child events", child_events > 0, T.describe(streamed))

  local captured = T.kuu({ "run", "--json", "capture", "changed" }, { cwd = root })
  rows = assert(ledger.tail(root, 10))
  local capture_children, capture_tasks, capture_events = 0, 0, 0
  for _, row in ipairs(rows) do
    if row.kind == "child" and row.task == "capture" then capture_children = capture_children + 1 end
    if row.kind == "task" and row.name == "capture" and row.status == "ok" then capture_tasks = capture_tasks + 1 end
  end
  for line in captured.out:gmatch("[^\r\n]+") do
    local event = json.decode(line)
    if event and event.event == "child" then capture_events = capture_events + 1 end
  end
  check("capture records its enclosing task/run but no individual child or child event", captured.code == 0
    and #rows == 5 and capture_tasks == 1 and capture_children == 0 and capture_events == 0
    and ledger.verify(root) == true, T.describe(captured))
  local rejected = T.kuu({ "run", "capture", "failed" }, { cwd = root })
  check("published task propagates real stderr and the failing child's code", rejected.code == 9
    and T.contains(rejected.err, "PROJECT exit") and T.contains(rejected.err, "probe could not finish its work"),
    T.describe(rejected))
  local timed = T.kuu({ "run", "stream", "slow" }, { cwd = root })
  rows = assert(ledger.tail(root, 3))
  check("streamed timeout remains failed with its child history intact", timed.code ~= 0 and #rows == 3
    and rows[1].kind == "child" and rows[1].status == "timeout"
    and rows[2].kind == "task" and rows[2].status == "failed" and rows[3].status == "failed", T.describe(timed))
end
