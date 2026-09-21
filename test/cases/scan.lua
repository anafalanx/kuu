-- scan.lua -- shared private collector: exact pre-descent scope, metadata,
-- link boundaries and incomplete observations. Public configuration activation
-- deliberately remains a later ledger-migration step.
global none
global <const> require, ipairs, tostring, table, string, pcall, assert, error

return function(T)
  local check, contains = T.check, T.contains
  local fs, json, proc, sched = require "fs", require "json", require "proc", require "sched"
  local scan, policy, native = require "_scan", require "_scan_policy", require "_scan_native"
  local scratch = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "scan-" })
  local function directory(name)
    local path = scratch .. "/" .. name
    assert(fs.mkdir(path))
    return path
  end
  local function write(root, relative, contents)
    local path = root .. "/" .. relative
    assert(fs.mkdir(assert(path:match("^(.*)/[^/]+$"))))
    assert(fs.write(path, contents or "global none\nreturn 1\n"))
    return path
  end
  local function configured(options)
    return assert(policy.decode(json.encode { v = 1, scan = options }, "scan-fixture.json"))
  end
  local minimum = configured { defaults = false }
  local defaults = configured {}
  local function paths(observation)
    local values = {}
    for _, file in ipairs(observation.files) do values[#values + 1] = file.relative end
    return table.concat(values, "\n")
  end
  local function has(observation, relative)
    for _, file in ipairs(observation.files) do if file.relative == relative then return true end end
    return false
  end
  local function file_at(observation, relative)
    for _, file in ipairs(observation.files) do if file.relative == relative then return file end end
  end

  local root = directory("scope")
  for _, relative in ipairs {
    "z.lua", "a.txt", "src/main.lua", "src/VENDOR/hidden.lua", "vendorish/visible.lua",
    "assets/generated/deep/hidden.lua", "assets/generated-more/visible.lua",
    "elsewhere/assets/generated/visible.lua", "nested/.CaChE/hidden.lua", "nested/.VeNv/hidden.lua",
    ".git/hidden.lua", ".kuu/hidden.lua", "vendor.txt", "assets/file-only", "build/hidden.lua",
  } do write(root, relative) end
  local scope = configured { exclude_dirs = json.array { "Vendor" },
    exclude_paths = json.array { "ASSETS\\GENERATED", "assets/file-only", "vendor.txt" } }
  local found = scan.collect(root, scope)
  check("a complete custom observation carries its project and starting roots",
    found.complete and found.root == root and found.start == root and #found.errors == 0,
    json.encode(found))
  check("exact basenames prune nested mixed-ASCII-case directories before descent",
    not has(found, "src/VENDOR/hidden.lua") and not has(found, "nested/.CaChE/hidden.lua")
      and not has(found, "nested/.VeNv/hidden.lua") and has(found, "vendorish/visible.lua"), paths(found))
  check("exact project-relative exclusions preserve suffix and different-parent boundaries",
    not has(found, "assets/generated/deep/hidden.lua") and has(found, "assets/generated-more/visible.lua")
      and has(found, "elsewhere/assets/generated/visible.lua"), paths(found))
  check("directory exclusions never suppress matching ordinary file names",
    has(found, "vendor.txt") and has(found, "assets/file-only"), paths(found))
  check("mandatory private directories remain excluded", not has(found, ".git/hidden.lua")
    and not has(found, ".kuu/hidden.lua"), paths(found))
  check("custom scope counts only retained files and reports exclusions separately",
    found.counts.files == #found.files and found.counts.excluded_dirs == 7
      and found.counts.errors == 0 and found.counts.nofollow_links == 0,
    json.encode(found.counts))
  local ascending = true
  for i = 2, #found.files do if found.files[i - 1].path >= found.files[i].path then ascending = false end end
  check("file records have deterministic bytewise path ordering", ascending, paths(found))
  local payload = file_at(found, "a.txt")
  local expected = assert(fs.stat(root .. "/a.txt"))
  check("enumeration retains size, modification time and attributes without a second listing",
    payload and payload.path == root .. "/a.txt" and payload.size == expected.size
      and payload.mtime == expected.mtime and payload.attrs == expected.attrs, json.encode(payload))

  local off = scan.collect(root, minimum)
  check("disabling optional defaults exposes generated names while retaining mandatory exclusions",
    has(off, "build/hidden.lua") and has(off, "nested/.CaChE/hidden.lua")
      and has(off, "nested/.VeNv/hidden.lua") and not has(off, ".git/hidden.lua")
      and not has(off, ".kuu/hidden.lua"), paths(off))
  local explicit = scan.collect(root, scope, root .. "/assets/generated")
  check("an explicit excluded starting directory overrides its own path rule",
    explicit.complete and has(explicit, "assets/generated/deep/hidden.lua"), paths(explicit))
  write(root, "assets/generated/deep/VENDOR/still-hidden.lua")
  explicit = scan.collect(root, scope, root .. "/assets/generated")
  check("descendant basename policy still applies beneath an explicit start",
    not has(explicit, "assets/generated/deep/VENDOR/still-hidden.lua") and explicit.counts.excluded_dirs == 1,
    paths(explicit))
  local explicit_path_policy = configured { defaults = false,
    exclude_paths = json.array { "assets/generated", "assets/generated/deep" } }
  explicit = scan.collect(root, explicit_path_policy, root .. "/assets/generated")
  check("descendant path rules remain project-relative beneath an explicit start",
    explicit.complete and #explicit.files == 0 and explicit.counts.excluded_dirs == 1, json.encode(explicit))
  local named_root = directory("build")
  write(named_root, "visible.lua")
  write(named_root, "build/hidden.lua")
  local own = scan.collect(named_root, defaults)
  check("a project root's own excluded basename never prunes the project",
    own.complete and has(own, "visible.lua") and not has(own, "build/hidden.lua"), paths(own))

  local unicode = directory("unicode")
  write(unicode, "ÄBC/visible.lua")
  write(unicode, "生成物/hidden.lua")
  local distinct = scan.collect(unicode, configured { defaults = false, exclude_dirs = json.array { "äbc", "生成物" } })
  check("native matching folds ASCII only and matches non-ASCII bytes exactly",
    has(distinct, "ÄBC/visible.lua") and not has(distinct, "生成物/hidden.lua"), paths(distinct))
  local matched = scan.collect(unicode, configured { defaults = false, exclude_dirs = json.array { "Äbc" } })
  check("native matching still folds ASCII letters within a non-ASCII name",
    not has(matched, "ÄBC/visible.lua") and has(matched, "生成物/hidden.lua"), paths(matched))

  local many = directory("many-rules")
  local names, rules = json.array {}, json.array {}
  for i = 1, 256 do
    names[i] = string.format("skip%03d", i)
    rules[i] = string.format("paths/generated%03d", i)
  end
  for _, relative in ipairs { "skip001/hidden.lua", "skip065/hidden.lua", "skip256/hidden.lua",
    "paths/generated001/hidden.lua", "paths/generated065/hidden.lua", "paths/generated256/hidden.lua", "visible.lua" } do
    write(many, relative)
  end
  local maximum = scan.collect(many, configured { exclude_dirs = names, exclude_paths = rules })
  check("all 256 configured rules per list plus defaults survive native option transfer",
    maximum.complete and #maximum.files == 1 and has(maximum, "visible.lua")
      and maximum.counts.excluded_dirs == 6 and maximum.counts.enumerated_dirs == 2, json.encode(maximum.counts))

  -- The Lua adapter must consume native metadata directly. A regression to
  -- per-directory fs.list or per-file stat/read is observable here.
  local original_list, original_dirs, original_read, original_stat = fs.list, fs.dirs, fs.read, fs.stat
  local calls = { list = 0, dirs = 0, read = 0, stat = 0 }
  fs.list = function(...) calls.list = calls.list + 1 return original_list(...) end
  fs.dirs = function(...) calls.dirs = calls.dirs + 1 return original_dirs(...) end
  fs.read = function(...) calls.read = calls.read + 1 return original_read(...) end
  fs.stat = function(...) calls.stat = calls.stat + 1 return original_stat(...) end
  local metadata_ok, metadata = pcall(scan.collect, root, scope)
  fs.list, fs.dirs, fs.read, fs.stat = original_list, original_dirs, original_read, original_stat
  check("collection performs no Lua directory relisting or per-file reads/stats",
    metadata_ok and metadata.complete and calls.list == 0 and calls.dirs == 0 and calls.read == 0 and calls.stat == 0,
    json.encode(calls))

  local compat = directory("compat")
  for _, relative in ipairs { "main.lua", ".cache/present.lua", ".local/present.lua", ".venv/present.lua",
    "__pycache__/present.lua", "build/hidden.lua", "node_modules/hidden.lua", ".git/hidden.lua",
    ".kuu/hidden.lua", ".tools/hidden.lua" } do write(compat, relative) end
  -- The legacy-scope adapter never loads configuration; public consumers now
  -- use configured collection and test their preflight in scan_activation.
  write(compat, "kuu.config.json", "{not yet enabled")
  local check_compat, ledger_compat = scan.compat(compat, "check"), scan.compat(compat, "ledger")
  check("compatible checker traversal preserves old generated-directory visibility",
    check_compat.complete and has(check_compat, ".cache/present.lua") and has(check_compat, ".local/present.lua")
      and has(check_compat, ".venv/present.lua") and has(check_compat, "__pycache__/present.lua")
      and not has(check_compat, "build/hidden.lua") and not has(check_compat, "node_modules/hidden.lua"), paths(check_compat))
  check("compatible ledger traversal preserves its prior effective scope without loading config",
    ledger_compat.complete and has(ledger_compat, ".cache/present.lua") and has(ledger_compat, ".local/present.lua")
      and not has(ledger_compat, "build/hidden.lua") and not has(ledger_compat, "node_modules/hidden.lua")
      and not has(ledger_compat, ".git/hidden.lua") and not has(ledger_compat, ".kuu/hidden.lua")
      and not has(ledger_compat, ".tools/hidden.lua"), paths(ledger_compat))

  -- check.PRUNE remains a mutable public list with fs.dirs wildcard
  -- semantics. Configured rules are exact, but that cannot narrow this
  -- pre-existing API while consumers are in compatibility mode.
  local wildcard_root = directory("legacy-wildcard")
  write(wildcard_root, "artifacts/deep/hidden.lua", "this must not be read as Lua\n")
  write(wildcard_root, "maintained/keep.lua", "global none\nlocal M = { kept = true }\nreturn M\n")
  local checker = require "check"
  local saved_prune, saved_read = checker.PRUNE, fs.read
  local forbidden_reads = 0
  checker.PRUNE = { "artifact*" }
  fs.read = function(path, options)
    if path:sub(1, #(wildcard_root .. "/artifacts/")) == wildcard_root .. "/artifacts/" then
      forbidden_reads = forbidden_reads + 1
    end
    return saved_read(path, options)
  end
  local wildcard_ok, wildcard_tree, wildcard_inventory, wildcard_scan = pcall(function()
    return checker.tree(wildcard_root), checker.modules(wildcard_root),
      scan.compat(wildcard_root, "check", nil, checker.PRUNE)
  end)
  checker.PRUNE, fs.read = saved_prune, saved_read
  check("mutable checker.PRUNE retains wildcard exclusions without reading the excluded subtree",
    wildcard_ok and forbidden_reads == 0 and #wildcard_tree.reports == 1
      and wildcard_tree.reports[1].path == wildcard_root .. "/maintained/keep.lua"
      and #wildcard_tree.reports[1].errors == 0, wildcard_ok and json.encode(wildcard_tree) or tostring(wildcard_tree))
  check("module inventory applies the same legacy wildcard scope",
    wildcard_ok and wildcard_inventory.complete and wildcard_inventory.files == 1
      and #wildcard_inventory.modules == 1 and wildcard_inventory.modules[1].name == "maintained.keep",
    wildcard_ok and json.encode(wildcard_inventory) or tostring(wildcard_tree))
  check("legacy wildcard pruning occurs before descent in the shared collector",
    wildcard_ok and wildcard_scan.complete and wildcard_scan.counts.excluded_dirs == 1
      and wildcard_scan.counts.enumerated_dirs == 2 and #wildcard_scan.files == 1,
    wildcard_ok and json.encode(wildcard_scan.counts) or tostring(wildcard_tree))

  -- Real junctions need no symlink privilege. All targets remain within this
  -- one test's private scratch directory.
  local linked_root, outside = directory("links"), directory("outside")
  write(linked_root, "local.lua")
  write(outside, "external.lua")
  write(outside, "deep/ordinary.lua")
  write(outside, "vendor/hidden.lua")
  local other_start = scan.collect(root, configured { defaults = false,
    exclude_dirs = json.array { "vendor" }, exclude_paths = json.array { "deep" } }, outside)
  check("an explicit start outside the project keeps basename rules without misapplying project-relative paths",
    other_start.complete and has(other_start, "deep/ordinary.lua") and not has(other_start, "vendor/hidden.lua"), paths(other_start))
  local linked = proc.run { "cmd.exe", "/c", "mklink", "/J", (linked_root .. "/junction"):gsub("/", "\\"),
    outside:gsub("/", "\\"), timeout = "10s" }
  check("collector junction fixture is created", linked and linked.code == 0, linked and T.describe(linked))
  if linked and linked.code == 0 then
    local walked = scan.collect(linked_root, minimum)
    check("discovered directory junctions are non-followed and do not make observation incomplete",
      walked.complete and #walked.files == 1 and has(walked, "local.lua")
        and walked.counts.nofollow_links == 1 and walked.counts.enumerated_dirs == 1, json.encode(walked))
    local link_start = scan.collect(linked_root, minimum, linked_root .. "/junction")
    check("an explicitly supplied starting junction admits its target metadata",
      link_start.complete and has(link_start, "junction/external.lua") and has(link_start, "junction/deep/ordinary.lua"), paths(link_start))
    local legacy = scan.compat(linked_root .. "/junction", "ledger")
    check("compatible ledger preserves its legacy reparse-root file omission while retaining ordinary descendants",
      legacy.complete and not has(legacy, "external.lua") and has(legacy, "deep/ordinary.lua"), paths(legacy))
  end

  local helper = fs.absolute(T.root .. "/build/test/scan_fixture.exe")
  check("native sharing-denial fixture is built", fs.exists(helper) == "file", helper)
  if fs.exists(helper) == "file" then
    local hold_number = 0
    local function held(path, callback)
      hold_number = hold_number + 1
      local control = directory("hold-" .. hold_number)
      local child <close> = assert(proc.start { helper, "hold", path, control .. "/ready", control .. "/release", timeout = "25s" })
      local ok, value = pcall(function()
        local started = sched.clock()
        while not fs.exists(control .. "/ready") do
          assert(child:running(), "native hold exited before its barrier")
          assert(sched.clock() - started < 10, "native hold barrier timeout")
          sched.sleep("10ms")
        end
        return callback()
      end)
      assert(fs.write(control .. "/release", "release"))
      local ended = assert(child:wait("5s"))
      check("native sharing-denial fixture releases its handle", ended.status == "exit" and ended.code == 0, T.describe(ended))
      if not ok then error(value) end
      return value
    end
    local denied = directory("denied")
    write(denied, "visible.lua")
    write(denied, "secret/hidden.lua")
    held(denied .. "/secret", function()
      local unpruned = scan.collect(denied, minimum)
      check("an unreadable included branch makes collection incomplete and preserves other files",
        not unpruned.complete and #unpruned.errors > 0 and has(unpruned, "visible.lua")
          and unpruned.errors[1].win32 == 32, json.encode(unpruned))
      local by_name = scan.collect(denied, configured { defaults = false, exclude_dirs = json.array { "SECRET" } })
      local by_path = scan.collect(denied, configured { defaults = false, exclude_paths = json.array { "SECRET" } })
      check("basename exclusion happens before trying to open an unreadable directory",
        by_name.complete and #by_name.errors == 0 and #by_name.files == 1
          and by_name.counts.enumerated_dirs == 1 and by_name.counts.excluded_dirs == 1, json.encode(by_name))
      check("relative-path exclusion happens before trying to open an unreadable directory",
        by_path.complete and #by_path.errors == 0 and #by_path.files == 1
          and by_path.counts.enumerated_dirs == 1 and by_path.counts.excluded_dirs == 1, json.encode(by_path))
    end)
    held(denied .. "/visible.lua", function()
      local observed = scan.collect(denied, minimum)
      check("metadata collection does not open even an exclusively held included file",
        observed.complete and #observed.errors == 0 and has(observed, "visible.lua"), json.encode(observed))
    end)
  end

  local absent = scan.collect(scratch .. "/missing-root", minimum)
  check("an unavailable starting root cannot produce a complete empty observation",
    not absent.complete and #absent.errors > 0, json.encode(absent))
  local original_collect = native.collect
  native.collect = function()
    return { root = root, paths = { root }, files = { { path = root .. "/a.txt", relative = "a.txt", size = 20, mtime = 1, attrs = 32 } },
      links = {}, skipped = {}, errors = { { path = root .. "/partial", reason = "enumeration stopped early", win32 = 5 } },
      dirs = 1, enumerated = 1, pruned = 0, depthlimited = 0 }
  end
  local adapted_ok, adapted = pcall(scan.collect, root, minimum)
  native.collect = original_collect
  check("partial native enumeration preserves surviving files and exposes its exact branch failure",
    adapted_ok and not adapted.complete and #adapted.files == 1 and #adapted.errors == 1
      and adapted.errors[1].path == root .. "/partial" and adapted.errors[1].win32 == 5
      and contains(adapted.errors[1].message, "enumeration stopped early") and adapted.counts.errors == 1,
    adapted_ok and json.encode(adapted) or tostring(adapted))

  native.collect = function()
    return { root = root, paths = { root }, files = {}, links = {},
      errors = { { path = root .. "/unrepresentable", reason = "invalid UTF-16 name", win32 = 1113 } }, skipped = {},
      dirs = 1, enumerated = 1, pruned = 0, depthlimited = 0 }
  end
  local rejected_ok, rejected = pcall(scan.collect, root, minimum)
  native.collect = original_collect
  check("rejected directory-entry names make an observation incomplete",
    rejected_ok and not rejected.complete and #rejected.errors == 1 and rejected.errors[1].win32 == 1113,
    rejected_ok and json.encode(rejected) or tostring(rejected))

  assert(fs.remove(scratch, { recursive = true }))
end
