-- Run the published shared environment through supervised and detached children.
global none
global <const> require, assert, ipairs, load, setmetatable, pcall, tostring

return function(T)
  local fs, proc, json = require "fs", require "proc", require "json"
  local env, sched = require "env", require "sched"
  local check = T.check
  local project = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "project-environment-" })
  local nested = project .. "/nested work/資料's folder"
  assert(fs.mkdir(nested)); assert(fs.mkdir(project .. "/automation"))
  assert(fs.copy(fs.absolute(T.exe), project .. "/kuu.exe"))
  if env.get("KUU_TEST_ASAN") == "1" then
    -- Keep PATH genuinely empty: ASAN's two non-system DLLs travel with this owned copy.
    for _, name in ipairs { "libclang_rt.asan_dynamic-x86_64.dll", "libc++.dll" } do
      assert(fs.copy(fs.absolute(T.root .. "/.tools/msys2/clang64/bin/" .. name), project .. "/" .. name))
    end
  end
  assert(fs.write(project .. "/.gitignore", "/.kuu/\n/.cache/\n/.tools/\n/.venv/\n"))
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/project-environment.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = source
  end
  check("environment guide contains a complete module, manifest and probe", #blocks == 3)
  if #blocks ~= 3 then return end
  for index, name in ipairs { "automation/project_env.lua", "manifest.lua", "automation/environment_probe.lua" } do
    assert(fs.write(project .. "/" .. name, blocks[index]))
  end
  local lint = T.kuu({ "check", "--json", "." }, { cwd = project })
  local report = json.decode(lint.out)
  check("published environment blocks pass static checking", lint.code == 0 and report
    and report.result.errors == 0 and report.result.warnings == 0, T.describe(lint))
  local listed = T.kuu({ "list" }, { cwd = project })
  check("loading the environment manifest declares both launch tasks", listed.code == 0
    and T.contains(listed.out, "editor_environment") and T.contains(listed.out, "environment"), T.describe(listed))
  check("loading and checking the environment recipe provisions nothing", not fs.exists(project .. "/.cache")
    and not fs.exists(project .. "/.tools") and not fs.exists(project .. "/.venv"))

  local inherited = { PATH = "", UV_CACHE_DIR = "wrong-uv", UV_PROJECT_ENVIRONMENT = "wrong-venv",
    npm_config_cache = "wrong-npm", GOCACHE = "wrong-build", GOMODCACHE = "wrong-modules",
    VIRTUAL_ENV = "unrelated-venv", PYTHONHOME = "unrelated-python", PYTHONPATH = "unrelated-libraries",
    PROJECT_ENV_SENTINEL = "chosen-test-value", PROJECT_ENV_SECRET = "must-not-be-printed" }
  local function run(name, cwd)
    return assert(proc.run { project .. "/kuu.exe", "run", name,
      cwd = cwd, env = inherited, timeout = "10s" })
  end
  local function verify(label, record, output)
    check(label .. " uses the project root regardless of caller cwd", record and record.cwd == project, output)
    check(label .. " places each cache under the project root", record and record.uv == project .. "/.cache/uv"
      and record.npm == project .. "/.cache/npm" and record.go_build == project .. "/.cache/go/build"
      and record.go_modules == project .. "/.cache/go/modules" and record.venv == project .. "/.venv", output)
    check(label .. " explicitly removes inherited Python activation values", record
      and record.virtual_env == json.null and record.python_home == json.null and record.python_path == json.null, output)
    check(label .. " works with genuinely empty PATH and preserves unrelated inherited values", record
      and record.path_empty == true and record.sentinel == "chosen-test-value", output)
    check(label .. " logs only selected settings", not T.contains(output, "must-not-be-printed")
      and not T.contains(output, "PROJECT_ENV_SECRET"), output)
  end
  for index, cwd in ipairs { project, nested } do
    local result = run("environment", cwd)
    check("supervised environment probe succeeds from directory " .. index, result.status == "exit" and result.code == 0,
      T.describe(result))
    verify("supervised probe " .. index, json.decode(result.out), result.out)
  end

  local detached = run("editor_environment", nested)
  local started = json.decode(detached.out)
  local pid = started and started.pid
  local function owned_process()
    if not pid then return false end
    local found = proc.find { pid = pid }
    local entry = found and found[1]
    return entry ~= nil and entry.exe ~= nil
      and fs.absolute(entry.exe):lower() == (project .. "/kuu.exe"):lower()
  end
  local guard <close> = setmetatable({}, { __close = function()
    -- A reused PID alone is never authority to stop a process.
    if owned_process() then
      pcall(proc.kill, pid)
      local stop = sched.clock() + 2
      while owned_process() and sched.clock() < stop do sched.sleep("20ms") end
    end
    check("detached cleanup leaves no process from the owned executable", not owned_process())
  end })
  check("detached environment probe starts with tool/default timeouts filtered out", detached.status == "exit"
    and detached.code == 0 and pid ~= nil, T.describe(detached))
  if pid then
    local stop = sched.clock() + 5
    while proc.alive(pid) and sched.clock() < stop do sched.sleep("20ms") end
    check("owned detached probe exits within its fixture budget", not proc.alive(pid), tostring(pid))
    local bytes, why = fs.read(project .. "/.cache/detached-environment.json")
    check("detached probe creates its selected report at the root cache", bytes ~= nil, tostring(why))
    verify("detached probe", bytes and json.decode(bytes), bytes or tostring(why))
  end
  check("nested invocation creates no duplicate cache or execution history", not fs.exists(nested .. "/.cache")
    and not fs.exists(nested .. "/.kuu") and fs.exists(project .. "/.kuu/ledger") == "directory")

  local module = assert(load(blocks[1], "@project_env.lua", "t"))()
  local first, second = module.overlay(), module.overlay()
  first.UV_CACHE_DIR = "changed"
  check("every launch receives its own environment overlay", first ~= second and second.UV_CACHE_DIR ~= "changed")
end
