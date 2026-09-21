-- Exercise the published editor launch paths only on an owned private desktop/profile.
global none
global <const> require, assert, ipairs, type, setmetatable, pcall

return function(T)
  local fs, proc, json, sched = require "fs", require "proc", require "json", require "sched"
  local env, ledger = require "env", require "_ledger"
  local check = T.check
  local root = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "editor-recipe-" })
  local nested = root .. "/nested work/資料's directory"
  assert(fs.mkdir(nested)); assert(fs.mkdir(root .. "/automation")); assert(fs.mkdir(root .. "/.tools/gui-probe"))
  assert(fs.copy(fs.absolute(T.exe), root .. "/kuu.exe"))
  if env.get("KUU_TEST_ASAN") == "1" then
    for _, name in ipairs { "libclang_rt.asan_dynamic-x86_64.dll", "libc++.dll" } do
      assert(fs.copy(fs.absolute(T.root .. "/.tools/msys2/clang64/bin/" .. name), root .. "/" .. name))
    end
  end
  local helper = root .. "/.tools/gui-probe/gui_probe.exe"
  assert(fs.copy(fs.absolute(T.root .. "/build/test/gui_probe.exe"), helper))
  assert(fs.write(root .. "/.gitignore", "/.kuu/\n/.cache/\n/.tools/\n/.local/\n/build/\n"))
  local shared = assert(fs.read(T.root .. "/docs/project-environment.md")):match("```lua\r?\n(.-)\r?\n```")
  assert(fs.write(root .. "/automation/project_env.lua", shared))
  local manifest = assert(fs.read(T.root .. "/docs/editor.md")):match("```lua\r?\n(.-)\r?\n```")
  assert(manifest, "editor guide must contain its executable manifest")
  assert(fs.write(root .. "/manifest.lua", manifest))
  local lint = T.kuu({ "check", "--json", "manifest.lua", "automation/project_env.lua" }, { cwd = root })
  local checked = json.decode(lint.out)
  check("published editor manifest and shared environment pass static checking", lint.code == 0 and checked
    and checked.result.errors == 0 and checked.result.warnings == 0, T.describe(lint))

  local function last_json(output)
    local last
    for line in output:gmatch("[^\r\n]+") do
      local item = json.decode(line)
      if item and item.profile and item.report then last = item end
    end
    return last
  end
  local function run(task, arguments)
    local command = { root .. "/kuu.exe", "run", task, cwd = nested,
      env = { KUU_EDITOR_RECIPE = "wrong-parent", KUU_EDITOR_CACHE = "wrong-parent-cache" }, timeout = "15s" }
    for _, argument in ipairs(arguments or {}) do command[#command + 1] = argument end
    return assert(proc.run(command))
  end
  local function owned_pid(pid)
    if type(pid) ~= "number" or pid <= 0 then return false end
    local found = proc.find { pid = pid }
    local entry = found and found[1]
    return entry and entry.exe and fs.absolute(entry.exe):lower() == helper:lower()
  end
  local function wait_report(path, seconds)
    local until_time = sched.clock() + seconds
    repeat
      local bytes = fs.read(path)
      if bytes then return json.decode(bytes), bytes end
      sched.sleep("20ms")
    until sched.clock() >= until_time
    return nil, "timed out waiting for atomic report: " .. path
  end
  local function wait_nonce(profile)
    local until_time = sched.clock() + 2
    repeat
      local bytes = fs.read(profile .. "/ready")
      if bytes and #bytes == 33 and bytes:match("^%x+\n$") then return bytes end
      sched.sleep("20ms")
    until sched.clock() >= until_time
  end
  local function verify(label, info, report, detail)
    check(label .. " verifies a window on a private desktop", report and report.ok == true
      and report.private_desktop == true and report.window_ready == true, detail)
    check(label .. " receives the root-derived shared editor settings", report
      and report.recipe == "isolated-v1" and report.cache == root .. "/.cache/editor", detail)
    check(label .. " cleans its owned profile and child", report and report.child_exited == true
      and report.profile_created == true and report.profile_removed == true and report.cleanup_error == 0
      and not fs.exists(info.profile) and not owned_pid(report.child_pid), detail)
  end

  local supervised = run("verify_editor")
  local supervised_info = last_json(supervised.out)
  check("supervised editor verification returns profile and report locations", supervised.code == 0
    and supervised_info and supervised_info.profile and supervised_info.report, T.describe(supervised))
  if supervised_info and supervised_info.report and supervised_info.profile then
    local report, bytes = wait_report(supervised_info.report, 2)
    verify("supervised verification", supervised_info, report, bytes)
  end
  local supervised_rows = assert(ledger.tail(root, 10))
  check("supervised GUI verification retains its actual tool child history", #supervised_rows == 3
    and supervised_rows[1].kind == "child" and supervised_rows[1].tool == "editor_probe"
    and supervised_rows[1].status == "exit" and supervised_rows[1].code == 0
    and supervised_rows[2].kind == "task" and supervised_rows[3].kind == "verb")

  local launched = run("launch_editor", { "--hold" })
  local launch = last_json(launched.out)
  local detached_pid = launch and launch.pid
  local guard <close> = setmetatable({}, { __close = function()
    if owned_pid(detached_pid) then
      pcall(proc.kill, detached_pid)
      local stop = sched.clock() + 2
      while owned_pid(detached_pid) and sched.clock() < stop do sched.sleep("20ms") end
    end
    check("editor cleanup leaves no owned detached verifier process", not owned_pid(detached_pid))
  end })
  check("detached editor task returns without waiting for child readiness", launched.status == "exit" and launched.code == 0
    and launch and detached_pid and launch.profile and launch.report, T.describe(launched))
  if launch and detached_pid and launch.profile and launch.report then
    local nonce = wait_nonce(launch.profile)
    check("detached private GUI survives its completed kuu parent until explicit release", nonce ~= nil
      and owned_pid(detached_pid) and not fs.exists(launch.report), nonce or T.describe(launched))
    if nonce then assert(fs.write(launch.profile .. "/continue", nonce)) end
    local report, bytes = wait_report(launch.report, 5)
    verify("detached verification", launch, report, bytes)
    local stop = sched.clock() + 2
    while owned_pid(detached_pid) and sched.clock() < stop do sched.sleep("20ms") end
    check("detached verifier exits after bounded readiness and cleanup", not owned_pid(detached_pid))
  end
  local rows = assert(ledger.tail(root, 10))
  check("detached GUI launch records its task and run without inventing a child completion", #rows == 5
    and rows[4].kind == "task" and rows[4].name == "launch_editor" and rows[4].status == "ok"
    and rows[5].kind == "verb" and ledger.verify(root) == true)

  local function native(mode, profile, output)
    return assert(proc.run { helper, "verify", profile, output, mode, cwd = nested,
      env = { KUU_EDITOR_RECIPE = "isolated-v1", KUU_EDITOR_CACHE = root .. "/.cache/editor" }, timeout = "10s" })
  end
  for _, mode in ipairs { "no-ready", "early-exit" } do
    local profile, output = root .. "/profile-" .. mode, root .. "/report-" .. mode .. ".json"
    local result = native(mode, profile, output)
    local report, bytes = wait_report(output, 1)
    check(mode .. " fails verification without claiming readiness", result.code ~= 0 and report and report.ok == false
      and report.window_ready == false, bytes or T.describe(result))
    check(mode .. " removes only its owned profile and leaves no owned GUI child", report
      and report.profile_removed == true and report.child_exited == true and report.cleanup_error == 0
      and not fs.exists(profile) and not owned_pid(report.child_pid), bytes)
  end
  for _, scenario in ipairs { "wrong-nonce", "unexpected-entry" } do
    local profile, output = root .. "/profile-" .. scenario, root .. "/report-" .. scenario .. ".json"
    local child <close> = assert(proc.start { helper, "verify", profile, output, "hold-ready", cwd = nested,
      env = { KUU_EDITOR_RECIPE = "isolated-v1", KUU_EDITOR_CACHE = root .. "/.cache/editor" }, timeout = "10s" })
    local nonce = wait_nonce(profile)
    check(scenario .. " reaches the held private GUI before fault injection", nonce ~= nil)
    if nonce then
      if scenario == "unexpected-entry" then
        assert(fs.write(profile .. "/unexpected-user-file", "preserve unexpected contents"))
        assert(fs.write(profile .. "/continue", nonce))
      else
        assert(fs.write(profile .. "/continue", "x" .. nonce:sub(2)))
      end
    end
    local result = assert(child:wait("10s"))
    local report, bytes = wait_report(output, 1)
    check(scenario .. " remains a reported verification failure", result.code ~= 0 and report and report.ok == false, bytes)
    check(scenario .. " leaves no owned GUI process", report and report.child_exited == true and not owned_pid(report.child_pid), bytes)
    if scenario == "unexpected-entry" then
      check("cleanup failure preserves unknown profile entries instead of recursively erasing them", report
        and report.status == "cleanup-failed" and report.cleanup_error ~= 0 and report.profile_removed == false
        and fs.read(profile .. "/unexpected-user-file") == "preserve unexpected contents", bytes)
    else
      check("wrong readiness nonce cannot release the handshake and owned cleanup still finishes", report
        and report.status ~= "ready" and report.window_ready == true and report.profile_removed == true
        and report.cleanup_error == 0 and not fs.exists(profile), bytes)
    end
  end
  local preserved_profile = root .. "/existing-profile"
  assert(fs.mkdir(preserved_profile)); assert(fs.write(preserved_profile .. "/sentinel", "real profile stays untouched"))
  local rejected = native("ready", preserved_profile, root .. "/existing-profile-report.json")
  check("existing profiles are refused without touching their data", rejected.code ~= 0
    and fs.read(preserved_profile .. "/sentinel") == "real profile stays untouched", T.describe(rejected))
  local preserved_report = root .. "/existing-report.json"
  assert(fs.write(preserved_report, "existing report bytes"))
  rejected = native("ready", root .. "/unused-profile", preserved_report)
  check("existing report files are refused without replacement or profile creation", rejected.code ~= 0
    and fs.read(preserved_report) == "existing report bytes" and not fs.exists(root .. "/unused-profile"), T.describe(rejected))
  check("nested editor invocation keeps execution history at project root", fs.exists(root .. "/.kuu/ledger") == "directory"
    and not fs.exists(nested .. "/.kuu"))
end
