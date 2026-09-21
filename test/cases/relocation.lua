-- Execute the published doctor and exact obsolete-environment cleanup after moves.
global none
global <const> require, assert, ipairs, string

return function(T)
  local fs, proc, json, hash = require "fs", require "proc", require "json", require "hash"
  local archive, env = require "archive", require "env"
  local check = T.check
  local base = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "relocation-" })
  local project = base .. "/Old checkout's space"
  local owner = "example-project/venv/v1\n"
  assert(fs.mkdir(project .. "/scripts/.venv/nested"))
  assert(fs.mkdir(project .. "/.tools/tool")); assert(fs.mkdir(project .. "/.cache/dependencies"))
  assert(fs.mkdir(project .. "/.venv"))
  assert(fs.copy(fs.absolute(T.exe), project .. "/kuu.exe"))
  assert(fs.copy(fs.absolute(T.exe), project .. "/.tools/tool/tool.exe"))
  if env.get("KUU_TEST_ASAN") == "1" then
    for _, name in ipairs { "libclang_rt.asan_dynamic-x86_64.dll", "libc++.dll" } do
      assert(fs.copy(fs.absolute(T.root .. "/.tools/msys2/clang64/bin/" .. name), project .. "/" .. name))
    end
  end
  assert(fs.write(project .. "/.gitignore", "/.kuu/\n/.cache/\n/.tools/\n/.venv/\n/scripts/.venv/\n/build/\n"))
  assert(fs.write(project .. "/scripts/.venv/.project-owner", owner))
  assert(fs.write(project .. "/scripts/.venv/nested/old-library", "obsolete environment"))
  assert(fs.write(project .. "/scripts/retained-notes.txt", "keep source-neighbor"))
  assert(fs.write(project .. "/.venv/current-library", "keep current environment"))
  local archive_path = project .. "/.cache/dependencies/tool.zip"
  assert(archive.pack(archive_path, project .. "/.tools/tool"))
  local pins = { tool_sha256 = assert(hash.file("sha256", project .. "/.tools/tool/tool.exe")),
    archive_sha256 = assert(hash.file("sha256", archive_path)) }
  assert(fs.write(project .. "/dependencies.json", json.encode(pins)))
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/relocation.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = source
  end
  check("relocation guide contains doctor module, manifest and owned cleanup", #blocks == 3)
  if #blocks ~= 3 then return end
  local cleanup = assert(fs.read(T.root .. "/docs/cleanup.md")):match("```lua\r?\n(.-)\r?\n```")
  assert(fs.write(project .. "/owned_ops.lua", cleanup))
  assert(fs.write(project .. "/scripts/health.lua", blocks[1]))
  assert(fs.write(project .. "/scripts/remove_obsolete.lua", blocks[3]))
  local old_manifest = blocks[2]:gsub('"automation%.', '"scripts.')
  assert(fs.write(project .. "/manifest.lua", old_manifest))

  local function run(name, extra)
    local command = { project .. "/kuu.exe", "run", name }
    for _, argument in ipairs(extra or {}) do command[#command + 1] = argument end
    command.cwd, command.timeout = project, "15s"
    return assert(proc.run(command))
  end
  local function doctor()
    local result = run("doctor")
    return result, json.decode(result.out)
  end
  local function intact()
    return hash.file("sha256", project .. "/.tools/tool/tool.exe") == pins.tool_sha256
      and hash.file("sha256", project .. "/.cache/dependencies/tool.zip") == pins.archive_sha256
  end
  local result, report = doctor()
  check("old-layout doctor verifies installed and cached dependency bytes offline", result.code == 0
    and report and report.installed.status == "verified" and report.cache.status == "verified", T.describe(result))
  check("doctor runs without generated application assets", report and report.application.status == "not-built"
    and report.application.ready == false and not fs.exists(project .. "/build"), result.out)

  -- Model a tracked-file rename: ignored old .venv and unrelated notes stay behind.
  assert(fs.mkdir(project .. "/automation"))
  assert(fs.rename(project .. "/scripts/health.lua", project .. "/automation/health.lua"))
  assert(fs.rename(project .. "/scripts/remove_obsolete.lua", project .. "/automation/remove_obsolete.lua"))
  result = run("doctor")
  check("a stale require is diagnosed after the maintained source move", result.code ~= 0
    and T.contains(result.err, "scripts.health"), T.describe(result))
  check("source moves leave ignored old environment available for explicit cleanup",
    fs.read(project .. "/scripts/.venv/nested/old-library") == "obsolete environment")
  assert(fs.write(project .. "/manifest.lua", blocks[2]))
  result, report = doctor()
  check("updating module references restores the published doctor after source rename", result.code == 0
    and report and report.root == project and intact(), T.describe(result))
  local lint = T.kuu({ "check", "--json", "manifest.lua", "automation/health.lua", "automation/remove_obsolete.lua", "owned_ops.lua" },
    { cwd = project })
  local checked = json.decode(lint.out)
  check("all published relocation and cleanup blocks pass static checking", lint.code == 0 and checked
    and checked.result.errors == 0 and checked.result.warnings == 0, T.describe(lint))

  local previous = project
  project = base .. "/Moved checkout 資料's space"
  assert(fs.rename(previous, project))
  result, report = doctor() -- deliberately run the moved checkout's own executable
  check("whole checkout relocation runs its own pinned runtime at the new root", result.code == 0 and report
    and report.root == project and not fs.exists(previous), T.describe(result))
  check("relocated doctor derives installed and cache paths from its new root", report
    and report.installed.path == project .. "/.tools/tool/tool.exe"
    and report.cache.path == project .. "/.cache/dependencies/tool.zip"
    and report.application.path == project .. "/build/app.exe" and intact(), result.out)
  check("source and checkout moves preserve obsolete and current environments until explicit cleanup",
    fs.read(project .. "/scripts/.venv/nested/old-library") == "obsolete environment"
    and fs.read(project .. "/.venv/current-library") == "keep current environment")

  local tool = project .. "/.tools/tool/tool.exe"
  local cache = project .. "/.cache/dependencies/tool.zip"
  local manifest = assert(fs.read(project .. "/manifest.lua"))
  -- An accidental deps={"prereqs"} would leave evidence and fail this fixture.
  assert(fs.write(project .. "/manifest.lua", manifest .. [[
task "prereqs" { run = function()
  require("fs").write("provisioning-was-called", "unexpected")
  return nil, err.new("PROJECT", "unexpected", "doctor must not provision")
end }
]]))
  for _, entry in ipairs { { "installed", tool }, { "cache", cache } } do
    local label, path = entry[1], entry[2]
    assert(fs.rename(path, path .. ".held"))
    result, report = doctor()
    check("missing " .. label .. " is an actionable doctor failure without repair", result.code == 1
      and report and report[label].status == "missing" and T.contains(result.err, "PROJECT health")
      and not fs.exists(path) and not fs.exists(project .. "/provisioning-was-called"), T.describe(result))
    check("missing " .. label .. " does not suppress the other dependency diagnosis", report
      and report[label == "installed" and "cache" or "installed"].status == "verified", result.out)
    assert(fs.rename(path .. ".held", path))
    local bytes = assert(fs.read(path))
    assert(fs.write(path, "corrupt fixture bytes"))
    result, report = doctor()
    check("corrupt " .. label .. " fails its reviewed digest without replacement", result.code == 1
      and report and report[label].status == "mismatch" and fs.read(path) == "corrupt fixture bytes"
      and not fs.exists(project .. "/provisioning-was-called"), T.describe(result))
    assert(fs.write(path, bytes))
  end
  assert(fs.write(project .. "/manifest.lua", manifest))
  assert(fs.write(project .. "/dependencies.json", '{"tool_sha256":"placeholder","archive_sha256":"placeholder"}'))
  result = run("doctor")
  check("doctor rejects placeholder pins instead of blessing currently installed bytes", result.code == 1
    and T.contains(result.err, "PROJECT pins") and intact(), T.describe(result))
  for _, invalid in ipairs { "false", "null", "42", '"scalar"', "[]" } do
    assert(fs.write(project .. "/dependencies.json", invalid))
    result = run("doctor")
    check("doctor rejects invalid pin document " .. invalid, result.code == 1
      and T.contains(result.err, "PROJECT pins") and intact(), T.describe(result))
  end
  assert(fs.write(project .. "/dependencies.json", json.encode(pins)))
  assert(fs.mkdir(project .. "/build")); assert(fs.write(project .. "/build/app.exe", "unverified output"))
  result, report = doctor()
  check("an application file is reported separately and never mistaken for readiness", result.code == 0 and report
    and report.application.status == "present-unverified" and report.application.ready == false
    and fs.read(project .. "/build/app.exe") == "unverified output", T.describe(result))

  local obsolete = project .. "/scripts/.venv"
  local marker = obsolete .. "/.project-owner"
  assert(fs.rename(marker, marker .. ".held"))
  result = run("clean_obsolete_environment")
  check("cleanup refuses an existing environment without its ownership marker", result.code ~= 0
    and fs.exists(obsolete) == "directory" and fs.exists(marker .. ".held") == "file", T.describe(result))
  assert(fs.rename(marker .. ".held", marker))
  assert(fs.write(marker, (owner:gsub("example", "another"))))
  result = run("clean_obsolete_environment")
  check("cleanup refuses a same-size marker belonging to another project", result.code == 1
    and T.contains(result.err, "PROJECT ownership") and fs.exists(obsolete) == "directory", T.describe(result))
  assert(fs.write(marker, string.rep("x", 4096)))
  result = run("clean_obsolete_environment")
  check("cleanup rejects oversized ownership metadata before reading unbounded content", result.code == 1
    and T.contains(result.err, "PROJECT ownership") and fs.exists(obsolete) == "directory", T.describe(result))
  assert(fs.write(marker, owner))
  result = run("clean_obsolete_environment", { project .. "/.venv" })
  check("cleanup accepts no caller-supplied replacement target", result.code == 2 and fs.exists(obsolete) == "directory"
    and fs.read(project .. "/.venv/current-library") == "keep current environment", T.describe(result))

  local native_root = base .. "/native-junctions"
  local native = assert(proc.run { fs.absolute(T.root .. "/build/test/attributes_fixture.exe"), "setup", native_root, timeout = "10s" })
  check("native junction fixture is available for cleanup containment checks", native.code == 0, T.describe(native))
  if native.code == 0 then
    local link = native_root .. "/junction"
    local sentinel = assert(fs.read(native_root .. "/target/child.bin"))
    for _, relative in ipairs { "scripts", "scripts/.venv", "scripts/.venv/.project-owner" } do
      local path = project .. "/" .. relative
      assert(fs.rename(path, path .. ".held"))
      assert(fs.rename(link, path))
      result = run("clean_obsolete_environment")
      check("cleanup refuses reparse metadata at " .. relative, result.code == 1
        and T.contains(result.err, "PROJECT ownership") and fs.exists(path) == "link"
        and fs.read(native_root .. "/target/child.bin") == sentinel, T.describe(result))
      assert(fs.rename(path, link))
      assert(fs.rename(path .. ".held", path))
    end
    assert(fs.rename(link, obsolete .. "/outside-link"))
    assert(fs.set_attributes(obsolete, { readonly = true }))
    assert(fs.set_attributes(obsolete .. "/nested", { readonly = true }))
    result = run("clean_obsolete_environment")
    check("explicit cleanup removes the exact owned readonly obsolete environment", result.code == 0
      and not fs.exists(obsolete), T.describe(result))
    check("owned cleanup leaves junction target bytes untouched", fs.read(native_root .. "/target/child.bin") == sentinel)
  end
  check("cleanup preserves neighboring source notes, current environment and both dependencies",
    fs.read(project .. "/scripts/retained-notes.txt") == "keep source-neighbor"
    and fs.read(project .. "/.venv/current-library") == "keep current environment" and intact())
  result = run("clean_obsolete_environment")
  check("already absent obsolete environment is successful bounded cleanup", result.code == 0 and not fs.exists(obsolete), T.describe(result))
end
