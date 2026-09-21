-- Compile the documented cache recipe, inspect shortcuts independently and run their stored argv.
global none
global <const> require, assert, ipairs, string

return function(T)
  local fs, proc, json, hash = require "fs", require "proc", require "json", require "hash"
  local env, ledger = require "env", require "_ledger"
  local check = T.check
  local scratch = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "native-helper-" })
  local root = scratch .. "/fresh work/資料's project"
  assert(fs.mkdir(root .. "/automation")); assert(fs.mkdir(root .. "/native")); assert(fs.mkdir(root .. "/.tools/msys2"))
  assert(fs.copy(fs.absolute(T.exe), root .. "/kuu.exe"))
  if env.get("KUU_TEST_ASAN") == "1" then
    for _, name in ipairs { "libclang_rt.asan_dynamic-x86_64.dll", "libc++.dll" } do
      assert(fs.copy(fs.absolute(T.root .. "/.tools/msys2/clang64/bin/" .. name), root .. "/" .. name))
    end
  end
  assert(fs.write(root .. "/.gitignore", "/.kuu/\n/.tools/\n/.local/\n/.cache/\n"))
  local reader = fs.absolute(T.root .. "/build/test/shell_link_reader.exe")
  local alias = assert(proc.run { reader, "junction", root .. "/.tools/msys2/ucrt64",
    fs.absolute(T.root .. "/.tools/msys2/ucrt64"), timeout = "10s" })
  check("native-helper fixture aliases only the repository's pinned compiler tree", alias.status == "exit" and alias.code == 0,
    T.describe(alias))
  if alias.code ~= 0 then return end
  local source = assert(fs.read(T.root .. "/examples/shell_link.c"))
  assert(fs.write(root .. "/native/shell_link.c", source))
  local blocks = {}
  for block in assert(fs.read(T.root .. "/docs/native-helper.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = block
  end
  check("native-helper guide provides a complete cache module and manifest", #blocks == 2)
  if #blocks ~= 2 then return end
  assert(fs.write(root .. "/automation/native_helper.lua", blocks[1]))
  assert(fs.write(root .. "/manifest.lua", blocks[2]))
  local owned_ops = assert(fs.read(T.root .. "/docs/cleanup.md")):match("```lua\r?\n(.-)\r?\n```")
  assert(fs.write(root .. "/owned_ops.lua", assert(owned_ops)))
  local pins = { v = 1, compiler_sha256 = assert(hash.file("sha256", root .. "/.tools/msys2/ucrt64/bin/gcc.exe")),
    packages = json.array {} }
  local toolchain = assert(fs.read(T.root .. "/docs/toolchain.md")):match("### The UCRT64 pins(.-)## Populating")
  assert(toolchain, "the reviewed toolchain table must be available")
  for name, version, digest in toolchain:gmatch("| ([^|]+) | ([^|]+) | `(%x+)` |") do
    pins.packages[#pins.packages + 1] = { file = "mingw-w64-ucrt-x86_64-" .. name .. "-" .. version .. "-any.pkg.tar.zst",
      sha256 = digest }
  end
  check("fixture compiler identity includes all 18 reviewed UCRT64 package pins", #pins.packages == 18)
  local original_pins = json.encode(pins)
  assert(fs.write(root .. "/toolchain.lock.json", original_pins))
  local lint = T.kuu({ "check", "--json", "." }, { cwd = root })
  local checked = json.decode(lint.out)
  check("native-helper recipe checks with literal compiler and helper declarations", lint.code == 0 and checked
    and checked.result.errors == 0 and checked.result.warnings == 0, T.describe(lint))
  local listed = T.kuu({ "list" }, { cwd = root })
  check("loading the helper manifest creates no cache or installed helper", listed.code == 0
    and not fs.exists(root .. "/.cache") and not fs.exists(root .. "/.local"), T.describe(listed))

  local function run(name, arguments)
    local command = { root .. "/kuu.exe", "run", name, cwd = root, env = { PATH = "" }, timeout = "90s" }
    for _, argument in ipairs(arguments or {}) do command[#command + 1] = argument end
    local result = assert(proc.run(command))
    local report
    for line in result.out:gmatch("[^\r\n]+") do
      local value = json.decode(line)
      if value and value.key then report = value end
    end
    return result, report
  end
  local function compiler_runs()
    local count = 0
    for _, row in ipairs(assert(ledger.tail(root, 100))) do
      if row.kind == "child" and row.tool == "cc" then count = count + 1 end
    end
    return count
  end
  local function stages()
    local count = 0
    for _, relative in ipairs { ".cache/native-helper", ".local/native-helper", ".local" } do
      local listing = fs.list(root .. "/" .. relative)
      if listing then
        for _, entry in ipairs(listing.entries) do
          if entry.name:match("^%.stage%-") or entry.name:match("^%.shortcut%-stage%-") then count = count + 1 end
        end
      end
    end
    return count
  end

  local first_result, first = run("build_helper")
  check("first use compiles and publishes a verified helper with empty inherited PATH", first_result.status == "exit"
    and first_result.code == 0 and first and first.reused == false, T.describe(first_result))
  if not first then return end
  local receipt_path = first.cache .. "/receipt.json"
  local receipt_bytes = assert(fs.read(receipt_path))
  local receipt = assert(json.decode(receipt_bytes))
  check("cache receipt binds key, compiler, source, recipe and executable bytes", receipt.v == 1
    and receipt.key == first.key and receipt.source_sha256 == hash.sum("sha256", source)
    and receipt.compiler_sha256 == pins.compiler_sha256 and receipt.toolchain_sha256 == hash.sum("sha256", original_pins)
    and receipt.executable_sha256 == hash.file("sha256", first.cache .. "/shell_link.exe")
    and receipt.executable_sha256 == hash.file("sha256", first.helper))
  check("fresh publication leaves no staging directory", stages() == 0)
  local count = compiler_runs()
  local reused_result, reused = run("build_helper")
  check("cache reuse verifies the same artifact without invoking the compiler again", reused_result.code == 0
    and reused and reused.key == first.key and reused.reused == true and compiler_runs() == count,
    T.describe(reused_result))

  local cache_bytes = assert(fs.read(first.cache .. "/shell_link.exe"))
  local installed_hash = assert(hash.file("sha256", first.helper))
  assert(fs.write(first.cache .. "/shell_link.exe", cache_bytes .. "corrupt"))
  local corrupt = run("build_helper")
  check("corrupt cached helper is refused before compilation or installing altered bytes", corrupt.code ~= 0
    and T.contains(corrupt.err, "cached executable hash mismatch") and T.contains(corrupt.err, first.key)
    and compiler_runs() == count and hash.file("sha256", first.helper) == installed_hash, T.describe(corrupt))
  assert(fs.write(first.cache .. "/shell_link.exe", cache_bytes))
  for _, malformed in ipairs { "false", "{not-json", '{"v":1,"executable_sha256":"wrong"}' } do
    assert(fs.write(receipt_path, malformed))
    local rejected = run("build_helper")
    check("malformed cache receipt fails closed: " .. malformed, rejected.code ~= 0
      and T.contains(rejected.err, "PROJECT cache") and compiler_runs() == count, T.describe(rejected))
  end
  receipt.source_sha256 = string.rep("0", 64)
  assert(fs.write(receipt_path, json.encode(receipt)))
  local disagrees = run("build_helper")
  check("a plausible receipt with the wrong input identity is rejected", disagrees.code ~= 0
    and T.contains(disagrees.err, "disagrees on source_sha256"), T.describe(disagrees))
  assert(fs.write(receipt_path, receipt_bytes))

  local old_hash = pins.compiler_sha256
  pins.compiler_sha256 = string.rep("0", 64)
  assert(fs.write(root .. "/toolchain.lock.json", json.encode(pins)))
  local bad_compiler = run("build_helper")
  check("installed compiler bytes must match their reviewed pin even on reuse", bad_compiler.code ~= 0
    and T.contains(bad_compiler.err, "PROJECT compiler") and compiler_runs() == count, T.describe(bad_compiler))
  pins.compiler_sha256 = old_hash
  assert(fs.write(root .. "/toolchain.lock.json", original_pins))
  assert(fs.write(root .. "/native/shell_link.c", source .. "\nconst char input_change[] = \"source identity changed\";\n"))
  local changed_result, changed = run("build_helper")
  check("changed native source selects a new content cache key", changed_result.code == 0
    and changed and changed.key ~= first.key and changed.reused == false and compiler_runs() == count + 1,
    T.describe(changed_result))
  assert(fs.write(root .. "/native/shell_link.c", source))
  assert(fs.write(root .. "/automation/native_helper.lua", blocks[1] .. "\n-- reviewed build recipe revision\n"))
  local recipe_result, recipe_changed = run("build_helper")
  check("actual build-module changes invalidate cache with unchanged source", recipe_result.code == 0
    and recipe_changed and recipe_changed.key ~= first.key and recipe_changed.reused == false,
    T.describe(recipe_result))
  assert(fs.write(root .. "/automation/native_helper.lua", blocks[1]))
  pins.review = "a separately reviewed toolchain identity"
  assert(fs.write(root .. "/toolchain.lock.json", json.encode(pins)))
  local identity_result, identity_changed = run("build_helper")
  check("whole toolchain-lock identity changes select a distinct cache key", identity_result.code == 0
    and identity_changed and identity_changed.key ~= first.key and identity_changed.reused == false,
    T.describe(identity_result))
  assert(fs.write(root .. "/toolchain.lock.json", original_pins))
  local restored_result, restored = run("build_helper")
  assert(restored_result.code == 0 and restored)
  local previous_cache_count = #assert(fs.list(root .. "/.cache/native-helper")).entries
  assert(fs.write(root .. "/native/shell_link.c", source .. "\n#error intentionally rejected native fixture\n"))
  local failed = run("build_helper")
  check("failed compilation preserves the prior helper and publishes no cache entry", failed.code ~= 0
    and T.contains(failed.err, "intentionally rejected native fixture")
    and hash.file("sha256", restored.helper) == restored.sha256 and stages() == 0
    and #assert(fs.list(root .. "/.cache/native-helper")).entries == previous_cache_count, T.describe(failed))
  assert(fs.write(root .. "/native/shell_link.c", source))

  -- An owned read handle without delete sharing prevents the atomic replacement.
  do
    local locker = fs.absolute(T.root .. "/build/test/lock_fixture.exe")
    local held <close> = assert(proc.start { locker, "shell_link.exe", cwd = fs.dirname(restored.helper),
      stream = true, timeout = "30s" })
    assert(held:read("line", "5s") == "LOCKED")
    assert(fs.write(root .. "/native/shell_link.c", source .. "\nconst char locked_change[] = \"owned replacement refused\";\n"))
    local blocked = run("build_helper")
    assert(held:write("x\n")); held:close_stdin()
    local released = assert(held:wait("5s"))
    assert(released.status == "exit" and released.code == 0)
    check("sharing denial preserves the previous installed helper and primary error", blocked.code ~= 0
      and T.contains(blocked.err, "FS access") and hash.file("sha256", restored.helper) == restored.sha256
      and stages() == 0, T.describe(blocked))
  end
  assert(fs.write(root .. "/native/shell_link.c", source))

  local arguments = { "", "a value", "an'argument", "資料", 'embedded"quote', "trailing\\", 'slashes\\\\"quote', "--", "--help" }
  local command = { "--", "run", "shortcut_probe", "--" }
  for _, value in ipairs(arguments) do command[#command + 1] = value end
  local link_result, linked = run("shortcut", command)
  check("shortcut publication succeeds with exact unquoted argument values", link_result.code == 0
    and linked and linked.shortcut == root .. "/.local/project.lnk" and stages() == 0, T.describe(link_result))
  if not linked then return end
  local function inspect_and_launch(label)
    local inspected = assert(proc.run { reader, "inspect", root .. "/.local/project.lnk", timeout = "10s" })
    local properties = json.decode(inspected.out)
    check(label .. " targets the current project runtime and working directory", inspected.code == 0 and properties
      and fs.absolute(properties.target) == root .. "/kuu.exe" and fs.absolute(properties.cwd) == root, T.describe(inspected))
    local exact = properties and properties.argv and #properties.argv == #arguments + 3
    if exact then
      exact = properties.argv[1] == "run" and properties.argv[2] == "shortcut_probe" and properties.argv[3] == "--"
      for i, value in ipairs(arguments) do exact = exact and properties.argv[i + 3] == value end
    end
    check(label .. " stores every argument including empties, quotes and trailing slashes", exact, T.describe(inspected))
    local launched = assert(proc.run { reader, "launch", root .. "/.local/project.lnk", timeout = "15s" })
    local observed = json.decode(launched.out)
    local same = observed and observed.argv and #observed.argv == #arguments
    if same then for i, value in ipairs(arguments) do same = same and observed.argv[i] == value end end
    check(label .. " launches stored target with actual exact argv and cwd", launched.status == "exit" and launched.code == 0
      and same and observed.cwd == root and fs.absolute(observed.exe) == root .. "/kuu.exe", T.describe(launched))
  end
  inspect_and_launch("fresh shortcut")
  local previous_link = assert(fs.read(linked.shortcut))
  local moved = scratch .. "/relocated 資料's project"
  assert(root:sub(1, #scratch + 1) == scratch .. "/" and moved:sub(1, #scratch + 1) == scratch .. "/")
  assert(fs.rename(root, moved))
  root = moved
  check("moving the owned checkout does not itself regenerate shortcut bytes", fs.read(root .. "/.local/project.lnk") == previous_link)
  count = compiler_runs()
  local relocated_result, relocated = run("shortcut", command)
  check("relocation reuses verified helper bytes and regenerates the owned shortcut", relocated_result.code == 0
    and relocated and relocated.key == first.key and relocated.reused == true and compiler_runs() == count
    and fs.read(root .. "/.local/project.lnk") ~= previous_link, T.describe(relocated_result))
  inspect_and_launch("relocated shortcut")
  check("all native-helper publications leave no owned staging residue", stages() == 0)
end
