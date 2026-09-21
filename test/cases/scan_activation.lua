-- scan_activation.lua -- declarative policy at the public command/API boundary.
global none
global <const> require, ipairs, tostring, pcall, table

return function(T)
  local fs, json = require "fs", require "json"
  local checker, policy = require "check", require "_scan_policy"
  local check, contains = T.check, T.contains
  local work = fs.absolute(T.work .. "/scan-activation")
  fs.remove(work, { recursive = true })
  fs.mkdir(work)
  local config = work .. "/kuu.config.json"
  local manifest = work .. "/manifest.lua"
  local module = "global none\nlocal M = { available = true }\nreturn M\n"
  fs.write(manifest, "global none\n")
  fs.write(work .. "/root.lua", module)
  for _, dir in ipairs { ".git", ".kuu", ".tools", "build", "node_modules", ".cache", ".local", ".venv", "__pycache__" } do
    fs.mkdir(work .. "/" .. dir)
    fs.write(work .. "/" .. dir .. "/hidden.lua", "this is not Lua\n")
  end
  local tree, inventory = checker.tree(work), checker.modules(work)
  check("public checker and inventory activate generated-directory defaults and mandatory metadata exclusions",
    #tree.reports == 2 and inventory.files == 2 and inventory.complete,
    json.encode { tree = tree, inventory = inventory })
  local r = T.kuu({ "check", "--json" }, { cwd = work })
  local parsed = json.decode(r.out)
  check("check CLI activates defaults while keeping root files and the manifest visible",
    r.code == 0 and parsed and #parsed.result.files == 2, T.describe(r))

  fs.write(config, '{"v":1,"scan":{"defaults":false}}')
  tree, inventory = checker.tree(work), checker.modules(work)
  check("defaults:false restores all seven optional directory names while preserving mandatory exclusions",
    #tree.reports == 9 and inventory.files == 9 and inventory.complete,
    json.encode { tree = tree, inventory = inventory })
  r = T.kuu({ "check", "--json", ".git/hidden.lua" }, { cwd = work })
  parsed = json.decode(r.out)
  check("an explicitly named file overrides even a mandatory automatic exclusion",
    r.code == 1 and parsed and #parsed.result.files == 1 and parsed.result.files[1].path == ".git/hidden.lua",
    T.describe(r))

  fs.write(config, '{"v":1,"scan":{"exclude_dirs":["vendor"],"exclude_paths":["nested/generated"]}}')
  fs.mkdir(work .. "/vendor/build")
  fs.write(work .. "/vendor/visible.lua", module)
  fs.write(work .. "/vendor/build/hidden.lua", "not Lua\n")
  fs.mkdir(work .. "/nested/generated")
  fs.write(work .. "/nested/generated/hidden.lua", module)
  fs.write(work .. "/nested/ordinary.lua", module)
  r = T.kuu({ "check", "--json", "vendor" }, { cwd = work })
  parsed = json.decode(r.out)
  check("an explicitly named directory overrides its own exclusion but keeps descendant exclusions",
    r.code == 0 and parsed and #parsed.result.files == 1 and parsed.result.files[1].path == "vendor/visible.lua",
    T.describe(r))
  tree = checker.tree(work)
  local names = {}
  for _, report in ipairs(tree.reports) do names[#names + 1] = fs.relative(report.path, work) end
  check("configured exact paths and basenames are active in direct tree scans",
    #names == 3 and not contains(table.concat(names, " "), "hidden.lua"), table.concat(names, " "))

  -- Scope controls discovery; an explicitly referenced project module keeps
  -- the runtime's ordinary require resolution even when inventory hides it.
  fs.mkdir(work .. "/vendor")
  fs.write(work .. "/vendor/hidden.lua", module)
  fs.write(work .. "/consumer.lua",
    'global none\nglobal <const> require\nlocal M = require "vendor.hidden"\nreturn M.available\n')
  local consumer = checker.file(work .. "/consumer.lua", work)
  inventory = checker.modules(work)
  local hidden = false
  for _, found in ipairs(inventory.modules) do if found.name == "vendor.hidden" then hidden = true end end
  r = T.kuu({ "-e", 'local rt=require "rt"; rt.root("."); assert(require("vendor.hidden").available)' }, { cwd = work })
  check("excluded modules still resolve in static checking and execute through ordinary require",
    #consumer.errors == 0 and #consumer.warnings == 0 and not hidden and r.code == 0,
    json.encode(consumer) .. T.describe(r))

  -- Snapshot once: later writes are for a later operation, never a reread
  -- during the current traversal or an explicit-file inspection.
  local original_read, reads = fs.read, 0
  fs.read = function(path, opts)
    if path == config then reads = reads + 1 end
    return original_read(path, opts)
  end
  local ran, result = pcall(checker.tree, work)
  local tree_reads = reads
  reads = 0
  local ran_modules, found = pcall(checker.modules, work)
  local module_reads = reads
  reads = 0
  local context = policy.load(work)
  local supplied_reads = reads
  reads = 0
  local supplied, supplied_tree = pcall(checker.tree, work, work, context)
  local supplied_modules = checker.modules(work, context)
  local supplied_file = checker.file(work .. "/consumer.lua", work)
  local reused_reads = reads
  fs.read = original_read
  check("each direct automatic scan loads config once, and supplied context/file checks do not reread it",
    ran and ran_modules and supplied and result and found and supplied_tree and supplied_modules and supplied_file
      and tree_reads == 1 and module_reads == 1 and supplied_reads == 1 and reused_reads == 0,
    tostring(tree_reads) .. "/" .. tostring(module_reads) .. "/" .. tostring(supplied_reads) .. "/" .. tostring(reused_reads))
  fs.write(config, "not JSON")
  tree, inventory = checker.tree(work), checker.modules(work)
  check("direct APIs expose malformed config as configuration diagnostics without a fallback inventory",
    tree.config_error and tree.config_error.domain == "SCAN" and #tree.reports == 1
      and tree.reports[1].configuration and tree.reports[1].errors[1].kind == "config"
      and inventory.config_error and not inventory.complete and inventory.files == 0 and #inventory.errors == 1,
    json.encode { tree = tree, inventory = inventory })
  tree = checker.tree(work, work, context)
  check("a supplied valid context survives an invalid config written later",
    tree.config_error == nil and #tree.reports == 4, json.encode(tree))
  consumer = checker.file(work .. "/consumer.lua", work)
  check("explicit check.file remains usable while scan configuration is broken",
    #consumer.errors == 0 and #consumer.warnings == 0, json.encode(consumer))

  local marker = work .. "/manifest-ran.txt"
  fs.write(manifest, 'global none\nglobal <const> require\nrequire("fs").write("manifest-ran.txt", "ran")\n')
  for _, verb in ipairs { "check", "list", "run" } do
    r = T.kuu({ verb, "--json" }, { cwd = work })
    parsed = json.decode(r.out)
    check(verb .. " rejects malformed config before any manifest execution",
      r.code == 2 and parsed and not parsed.ok and parsed.error.domain == "SCAN" and parsed.error.code == "config"
        and fs.exists(marker) == false, T.describe(r))
  end
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  local described = parsed and parsed.result and parsed.result.project
  check("capabilities retains its descriptor but refuses manifest execution and inventory under invalid config",
    r.code == 0 and described and described.config_error and described.config_error.domain == "SCAN"
      and #described.tasks == 0 and not described.modules_complete and described.files == 0
      and #described.module_errors == 1 and fs.exists(marker) == false, T.describe(r))
  r = T.kuu({ "capabilities" }, { cwd = work })
  check("the text descriptor makes configuration failure actionable",
    r.code == 0 and contains(r.out, "SCAN config") and contains(r.out, "kuu.config.json") and fs.exists(marker) == false,
    T.describe(r))
  for _, verb in ipairs { "check", "list", "run", "capabilities" } do
    r = T.kuu({ verb, "--help" }, { cwd = work })
    check(verb .. " help remains available without loading malformed project configuration",
      r.code == 0 and fs.exists(marker) == false, T.describe(r))
  end

  fs.write(config, '{"v":1,"scan":{"exclude_dirs":["vendor"]}}')
  fs.write(manifest, "this is not Lua\n")
  r = T.kuu({ "check", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  check("a broken manifest does not prevent static checker diagnostics with valid config",
    r.code == 1 and parsed and parsed.result.errors == 1, T.describe(r))
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  described = parsed and parsed.result.project
  check("a broken manifest does not prevent a valid configured module inventory",
    r.code == 0 and described and described.note and described.modules_complete and described.files == 5,
    T.describe(r))

  fs.write(manifest, 'global none\nglobal <const> require\nlocal fs = require "fs"\n' ..
    'fs.write("kuu.config.json", "not JSON")\nlocal task = require "task"\ntask "hello" {run=function() end}\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  described = parsed and parsed.result.project
  check("capabilities snapshots policy before a manifest changes configuration",
    r.code == 0 and described and described.config_error == nil and #described.tasks == 1
      and described.modules_complete and described.files == 5, T.describe(r))
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  described = parsed and parsed.result.project
  check("the next invocation sees the manifest's changed configuration",
    r.code == 0 and described and described.config_error and not described.modules_complete, T.describe(r))

  fs.write(config, '{"v":1,"scan":{"exclude_dirs":["vendor"]}}')
  fs.write(manifest, 'global none\nglobal <const> require\nlocal fs=require "fs"\n' ..
    'fs.write("kuu.config.json", "not JSON")\nfs.write("manifest-ran.txt", "ran")\n' ..
    'local task=require "task"\ntask "hello" {run=function() end}\n')
  r = T.kuu({ "run", "--json", "hello" }, { cwd = work })
  parsed = json.decode(r.out:match("([^\n]+)\n?$") or "null")
  check("run validates configuration before the manifest and does not reread it for history",
    r.code == 0 and parsed and parsed.ok and parsed.result.ledger.complete and parsed.result.ledger.records == 2
      and parsed.result.scope == nil and parsed.result.scans == nil and fs.read(marker) == "ran", T.describe(r))
  fs.remove(marker)
  r = T.kuu({ "run", "--json", "hello" }, { cwd = work })
  parsed = json.decode(r.out)
  check("the next run rejects the changed configuration before manifest execution or ledger opening",
    r.code == 2 and parsed and not parsed.ok and parsed.error.domain == "SCAN"
      and parsed.result.ledger == nil and fs.exists(marker) == false, T.describe(r))

  fs.write(config, '{"v":1,"scan":{"exclude_dirs":["vendor"]}}')
  fs.mkdir(work .. "/artifacts-snapshot")
  fs.write(work .. "/artifacts-snapshot/visible.lua", module)
  fs.write(manifest, 'global none\nglobal <const> require\nrequire("check").PRUNE = { "artifact*", "nested*" }\n')
  r = T.kuu({ "capabilities", "--json" }, { cwd = work })
  parsed = json.decode(r.out)
  described = parsed and parsed.result.project
  local kept_snapshot_module = false
  for _, found_module in ipairs(described and described.modules or {}) do
    if found_module.name == "artifacts-snapshot.visible" then kept_snapshot_module = true end
  end
  check("a manifest cannot narrow the captured capabilities scope by mutating check.PRUNE",
    r.code == 0 and described and described.modules_complete and described.files == 6 and kept_snapshot_module,
    T.describe(r))

  -- PRUNE remains an additive compatibility hook, never a way to remove
  -- mandatory rules or override the invocation's normalized config object.
  fs.write(config, '{"v":1,"scan":{"defaults":false,"exclude_dirs":["vendor"]}}')
  fs.mkdir(work .. "/artifacts-compat")
  fs.write(work .. "/artifacts-compat/bad.lua", "not Lua\n")
  context = policy.load(work)
  local old_prune = checker.PRUNE
  checker.PRUNE = { "artifact*" }
  tree = checker.tree(work)
  local direct_inventory = checker.modules(work)
  local captured_tree = checker.tree(work, work, context)
  local captured_inventory = checker.modules(work, context)
  checker.PRUNE = old_prune
  local all = {}
  for _, report in ipairs(tree.reports) do all[#all + 1] = report.path end
  check("direct calls apply intentional PRUNE wildcards while preserving configured rules and the caller's context",
    not contains(table.concat(all, " "), "artifacts-compat") and not contains(table.concat(all, " "), "/vendor/")
      and not contains(table.concat(all, " "), "/.git/") and not contains(table.concat(all, " "), "/.kuu/")
      and context.extra_prune == nil, table.concat(all, " "))
  local captured_paths = {}
  for _, report in ipairs(captured_tree.reports) do captured_paths[#captured_paths + 1] = report.path end
  check("supplied tree and module contexts remain frozen across later PRUNE changes",
    contains(table.concat(captured_paths, " "), "artifacts-compat/bad.lua")
      and captured_inventory.files == direct_inventory.files + 2, table.concat(captured_paths, " "))
  fs.remove(work, { recursive = true })
end
