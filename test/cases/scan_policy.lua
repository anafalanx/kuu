-- scan_policy.lua -- declarative scan configuration before traversal integration.
global none
global <const> require, ipairs, tostring, type, string, table, pcall

return function(T)
  local check, contains = T.check, T.contains
  local policy = require "_scan_policy"
  local fs, json, hash, err = require "fs", require "json", require "hash", require "err"
  local source = "fixture-policy.json"
  local function decode(text) return policy.decode(text, source) end
  local function config(scan) return json.encode { v = 1, scan = scan } end
  local function same_list(value, expected)
    return type(value) == "table" and table.concat(value, "\n") == table.concat(expected, "\n")
  end
  local function same_members(value, expected)
    if type(value) ~= "table" then return false end
    local sorted = {}
    for i, item in ipairs(value) do sorted[i] = item end
    table.sort(sorted)
    return same_list(sorted, expected)
  end
  local function refused(name, text)
    local ok, value, problem = pcall(decode, text)
    check(name, ok and value == nil and err.is(problem, "SCAN", "config")
      and contains(tostring(problem), source), tostring(problem or value))
  end

  local defaults = { ".cache", ".local", ".tools", ".venv", "__pycache__", "build", "node_modules" }
  local effective = { ".cache", ".git", ".kuu", ".local", ".tools", ".venv", "__pycache__", "build", "node_modules" }
  local base, why = decode('{"v":1}')
  check("a versioned config can omit scan and retain defaults", base and base.v == 1 and base.defaults == true,
    tostring(why))
  if base then
    check("default policy distinguishes mandatory, optional and effective directories",
      same_list(base.mandatory_dirs, { ".git", ".kuu" }) and same_members(base.default_dirs, defaults)
        and same_list(base.effective_dirs, effective))
    check("default policy has no custom exclusions", same_list(base.exclude_dirs, {}) and same_list(base.exclude_paths, {}))
    check("decode records its supplied source independently of its scope",
      base.source.kind == "file" and base.source.path == source)
    local implicit = policy.decode('{"v":1}')
    check("decode has a useful default source path", implicit and implicit.source.kind == "file"
      and implicit.source.path == "kuu.config.json")
    local canonical = json.decode(base.canonical)
    check("canonical scope identifies version and concrete marked directory/path arrays",
      canonical and canonical.v == 1 and json.is_array(canonical.dirs) and json.is_array(canonical.paths)
        and same_list(canonical.dirs, effective) and #canonical.paths == 0)
    check("fingerprint is the SHA-256 of canonical scope", base.fingerprint == hash.sum("sha256", base.canonical)
      and #base.fingerprint == 64)
    for _, text in ipairs {
      '{"v":1,"scan":{}}',
      '{"scan":{"exclude_paths":[],"exclude_dirs":[],"defaults":true},"v":1}',
      '{"v":1,"scan":{"exclude_dirs":[".GIT",".KUU","BUILD",".tools"]}}',
    } do
      local equivalent = decode(text)
      check("equivalent default scope has the same canonical value and fingerprint",
        equivalent and equivalent.canonical == base.canonical and equivalent.fingerprint == base.fingerprint, text)
    end
  end

  local minimal = decode('{"v":1,"scan":{"defaults":false}}')
  check("disabling defaults retains both mandatory exclusions", minimal and minimal.defaults == false
    and same_list(minimal.default_dirs, {}) and same_list(minimal.effective_dirs, { ".git", ".kuu" }))
  local custom_text = config {
    defaults = false,
    exclude_dirs = json.array { "Vendor", ".GIT", "vendor", "tmp", ".KUU" },
    exclude_paths = json.array { "Assets\\Generated", "assets/generated", "Sub/Cache" },
  }
  local custom = decode(custom_text)
  check("custom directory names normalize, deduplicate and sort", custom
    and same_list(custom.exclude_dirs, { ".git", ".kuu", "tmp", "vendor" })
    and same_list(custom.effective_dirs, { ".git", ".kuu", "tmp", "vendor" }))
  check("custom paths normalize separators and ASCII case, deduplicate and sort", custom
    and same_list(custom.exclude_paths, { "assets/generated", "sub/cache" }))
  local reordered = decode('{"scan":{"exclude_paths":["SUB\\\\CACHE","ASSETS/GENERATED"],'
    .. '"exclude_dirs":["TMP","VENDOR"],"defaults":false},"v":1}')
  check("scope fingerprint ignores input order, duplicates, mandatory repetitions and slash spelling",
    custom and reordered and custom.canonical == reordered.canonical and custom.fingerprint == reordered.fingerprint)
  local from_other_source = policy.decode(custom_text, "other/kuu.config.json")
  check("scope fingerprint excludes config source provenance", custom and from_other_source
    and from_other_source.fingerprint == custom.fingerprint and from_other_source.source.path ~= custom.source.path)
  local other_path = decode(config { defaults = false, exclude_dirs = json.array { "tmp", "vendor" },
    exclude_paths = json.array { "assets/generated", "sub/other" } })
  check("different path exclusions change the fingerprint", custom and other_path and custom.fingerprint ~= other_path.fingerprint)
  local other_dir = decode(config { defaults = false, exclude_dirs = json.array { "tmp", "vendor", "extra" },
    exclude_paths = json.array { "assets/generated", "sub/cache" } })
  check("different directory exclusions change the fingerprint", custom and other_dir and custom.fingerprint ~= other_dir.fingerprint)
  check("turning off optional exclusions changes the fingerprint", base and minimal and base.fingerprint ~= minimal.fingerprint)

  local unicode = decode(config { defaults = false, exclude_dirs = json.array { "ÄBC", "äBC", "Äbc", "生成物" },
    exclude_paths = json.array { "Données/ÄBC", "Données/äbc", "DONNéES/Äbc" } })
  check("directory matching folds ASCII only and preserves distinct non-ASCII spellings", unicode
    and same_list(unicode.exclude_dirs, { "Äbc", "äbc", "生成物" }))
  check("path normalization preserves Unicode while folding every ASCII component", unicode
    and same_list(unicode.exclude_paths, { "données/Äbc", "données/äbc" }))
  local near_reserved = decode(config { defaults = false,
    exclude_dirs = json.array { "console", "com0", "com10", "lpt10", "nulled", " foo", "two words", "a+b", "semi;colon", "literal{braces}" },
    exclude_paths = json.array { "package/@scope", "emoji/😀", ".hidden/ordinary" } })
  check("ordinary names are accepted without treating literals as patterns", near_reserved ~= nil)

  for _, item in ipairs {
    { "empty JSON is refused", "" },
    { "truncated JSON is refused", '{"v":' },
    { "trailing JSON data is refused", '{"v":1} false' },
    { "JSON comments are refused", '{"v":1 /*comment*/}' },
    { "invalid UTF-8 JSON is refused", '{"v":1,"scan":{"exclude_dirs":["\255"]}}' },
    { "a root array is refused", "[]" },
    { "a root null is refused", "null" },
    { "a root scalar is refused", "true" },
    { "the version is required", "{}" },
    { "an unsupported version is refused", '{"v":2}' },
    { "a string version is refused", '{"v":"1"}' },
    { "a null version is refused", '{"v":null}' },
    { "a fractional version is refused", '{"v":1.5}' },
    { "an unknown root key is refused", '{"v":1,"scna":{}}' },
    { "a root duplicate key is refused", '{"v":1,"v":1}' },
    { "escaped duplicate keys are refused", '{"v":1,"\\u0076":1}' },
    { "a scan array is refused", '{"v":1,"scan":[]}' },
    { "a null scan is refused", '{"v":1,"scan":null}' },
    { "a scalar scan is refused", '{"v":1,"scan":true}' },
    { "an unknown scan key is refused", '{"v":1,"scan":{"exclude_dir":[]}}' },
    { "a duplicate scan key is refused", '{"v":1,"scan":{"defaults":true,"defaults":false}}' },
    { "null defaults are refused", '{"v":1,"scan":{"defaults":null}}' },
    { "string defaults are refused", '{"v":1,"scan":{"defaults":"false"}}' },
    { "numeric defaults are refused", '{"v":1,"scan":{"defaults":0}}' },
    { "object defaults are refused", '{"v":1,"scan":{"defaults":{}}}' },
  } do refused(item[1], item[2]) end
  for _, field in ipairs { "exclude_dirs", "exclude_paths" } do
    for _, invalid in ipairs { "{}", "null", "true", '"build"', '[null]', '[1]', '[false]', '[{}]', '[[]]' } do
      refused(field .. " refuses wrong containers and entry types: " .. invalid,
        '{"v":1,"scan":{"' .. field .. '":' .. invalid .. '}}')
    end
  end
  local _, indexed_error = decode('{"v":1,"scan":{"exclude_paths":["valid","../escape"]}}')
  check("an invalid rule identifies the source and array field/index", err.is(indexed_error, "SCAN", "config")
    and contains(tostring(indexed_error), source) and contains(tostring(indexed_error), "scan.exclude_paths[2]"),
    tostring(indexed_error))
  local _, syntax_error = decode('{"v":')
  check("a JSON syntax error preserves the parser's byte location", err.is(syntax_error, "SCAN", "config")
    and contains(tostring(syntax_error), "byte"), tostring(syntax_error))
  for _, name in ipairs {
    "", ".", "..", "a/b", "a\\b", "/absolute", "\\absolute", "C:", "C:relative", "name.", "name ",
    "nul", "CON", "prn", "AUX", "COM1", "com9.tmp", "LPT1.log", "lpt9", "con.txt", "nul.tar.gz",
    "CONIN$", "conout$.tmp", "COM¹", "com².txt", "COM³", "LPT¹", "lpt².log", "LPT³",
    "has*glob", "has?glob", "has[glob", "has]glob", "less<than", "greater>than", "pipe|name", 'quote"name',
    "control\0name", "control\1name", "control\31name", "line\nname", "tab\tname",
  } do
    refused("directory exclusions refuse invalid or ambiguous component " .. json.encode(name),
      config { exclude_dirs = json.array { name } })
  end
  for _, path in ipairs {
    "", ".", "..", "./src", "src/.", "src/../other", "src/./other", "../src", "/src", "src/", "src//child",
    "\\src", "src\\", "src\\\\child", "C:/src", "C:src", "//server/share", "\\\\?\\C:\\src",
    "src/name.", "src/name ", "src./child", "src /child", "src/CON.txt", "aux/child", "src/lpt9.tmp",
    "src/**", "src/file?.lua", "src/[ab]", "src/a:b", "src/a<b", "src/a>b", "src/a|b", 'src/a"b',
    "src/a\0b", "src/a\1b", "src/a\31b",
  } do
    refused("path exclusions refuse unsafe or ambiguous path " .. json.encode(path),
      config { exclude_paths = json.array { path } })
  end

  local entries = json.array {}
  for i = 1, 256 do entries[i] = "item" .. tostring(i) end
  local at_limit = decode(config { defaults = false, exclude_dirs = entries, exclude_paths = entries })
  check("both exclusion arrays accept exactly 256 original entries", at_limit
    and #at_limit.exclude_dirs == 256 and #at_limit.exclude_paths == 256)
  entries[257] = "item257"
  refused("directory exclusions reject more than 256 entries", config { exclude_dirs = entries })
  refused("path exclusions reject more than 256 entries", config { exclude_paths = entries })
  for i = 1, 257 do entries[i] = "duplicate" end
  refused("directory entry limit is enforced before deduplication", config { exclude_dirs = entries })
  refused("path entry limit is enforced before deduplication", config { exclude_paths = entries })
  local limit_text = '{"v":1}' .. string.rep(" ", 1024 * 1024 - #'{"v":1}')
  local at_bytes = decode(limit_text)
  check("decode accepts exactly one MiB of otherwise valid configuration", at_bytes ~= nil)
  refused("decode refuses configuration over one MiB", limit_text .. " ")
  local direct_bom = decode("\239\187\191" .. '{"v":1}')
  check("decode accepts the same single UTF-8 BOM as load", direct_bom and base and direct_bom.fingerprint == base.fingerprint)
  refused("two UTF-8 BOMs are not valid configuration", "\239\187\191\239\187\191" .. '{"v":1}')

  local component_limit = decode(config { defaults = false, exclude_dirs = json.array { string.rep("a", 255) } })
  check("a component may contain exactly 255 UTF-16 units", component_limit ~= nil)
  refused("a directory component over 255 UTF-16 units is refused",
    config { exclude_dirs = json.array { string.rep("a", 256) } })
  refused("an overlong component inside a relative path is refused",
    config { exclude_paths = json.array { "parent/" .. string.rep("a", 256) } })
  local astral_limit = decode(config { exclude_dirs = json.array { string.rep("😀", 127) .. "x" } })
  check("supplementary Unicode characters count as two UTF-16 units", astral_limit ~= nil)
  refused("128 supplementary Unicode characters exceed a component's UTF-16 limit",
    config { exclude_dirs = json.array { string.rep("😀", 128) } })
  local long_path = string.rep(string.rep("a", 255) .. "/", 127) .. string.rep("b", 248)
  check("a relative path may contain exactly 32760 UTF-16 units", #long_path == 32760
    and decode(config { exclude_paths = json.array { long_path } }) ~= nil)
  refused("a relative path over 32760 UTF-16 units is refused",
    config { exclude_paths = json.array { long_path .. "b" } })

  -- Every filesystem fixture is new and owned by this case. No project
  -- manifest is needed to load policy, and no fixture cleanup traverses links.
  local root, create_error = fs.tempdir { dir = fs.absolute(T.work), prefix = "scan-policy-" }
  check("scan-policy fixtures have a private directory", root ~= nil, tostring(create_error))
  if not root then return end
  fs.write(root .. "/manifest.lua", 'global none\nglobal <const> error\nerror("a scan-policy load must never execute this manifest")\n')
  local config_path = fs.join(root, "kuu.config.json")
  local missing, missing_error = policy.load(root)
  check("a missing config uses default policy without executing the manifest", base and missing
    and missing.defaults == true and missing.fingerprint == base.fingerprint, tostring(missing_error))
  check("a missing config reports default provenance and an absolute root", missing and missing.root == fs.absolute(root)
    and missing.source.kind == "default" and missing.source.path == config_path)
  if missing then
    missing.mandatory_dirs[1], missing.default_dirs[1], missing.effective_dirs[1] = "mutated", "mutated", "mutated"
    missing.exclude_dirs[1], missing.exclude_paths[1], missing.source.path = "mutated", "mutated", "mutated"
    local again = policy.load(root)
    check("loads return fresh arrays and source metadata rather than shared mutable defaults", base and again
      and same_list(again.mandatory_dirs, { ".git", ".kuu" }) and same_members(again.default_dirs, defaults)
      and same_list(again.effective_dirs, effective) and #again.exclude_dirs == 0 and #again.exclude_paths == 0
      and again.source.path == config_path and again.fingerprint == base.fingerprint)
  end
  fs.write(config_path, custom_text)
  local loaded, load_error = policy.load(root)
  check("loading a real config normalizes the same policy as decode", custom and loaded and loaded.fingerprint == custom.fingerprint,
    tostring(load_error))
  check("a real config records file provenance at the project root", loaded and loaded.source.kind == "file"
    and loaded.source.path == config_path and loaded.root == fs.absolute(root))
  fs.write(config_path, '{"v":1,"scan":{"defaults":false,"exclude_dirs":["changed"]}}')
  local changed = policy.load(root)
  check("load observes a replaced config instead of caching the old policy", loaded and changed
    and same_list(changed.exclude_dirs, { "changed" }) and changed.fingerprint ~= loaded.fingerprint)
  fs.write(config_path, "\239\187\191" .. '{"v":1}')
  local bom = policy.load(root)
  check("load accepts a UTF-8 BOM through the bounded UTF-8 reader", base and bom and bom.fingerprint == base.fingerprint)
  for _, item in ipairs {
    { "malformed", '{"v":' },
    { "invalid UTF-8", '{"v":1,"scan":{"exclude_dirs":["\255"]}}' },
    { "duplicate UTF-8 BOM", "\239\187\191\239\187\191" .. '{"v":1}' },
    { "oversized", limit_text .. " " },
  } do
    fs.write(config_path, item[2])
    local value, problem = policy.load(root)
    check("an existing " .. item[1] .. " config is an actionable SCAN config error", value == nil
      and err.is(problem, "SCAN", "config") and contains(tostring(problem), config_path), tostring(problem))
  end

  -- Native Windows ACL/share-error timing is unnecessary for the loader's
  -- distinction between absence and an unreadable config: inject that FS
  -- result at its one read, then restore the export even on a raised error.
  local original_read, seen = fs.read, nil
  fs.read = function(path, options)
    if path == config_path then
      seen = options
      return nil, err.new("FS", "access", "injected unreadable config")
    end
    return original_read(path, options)
  end
  local ok, unreadable, access_error = pcall(policy.load, root)
  fs.read = original_read
  check("an unreadable config is not treated as a missing file", ok and unreadable == nil
    and err.is(access_error, "SCAN", "config") and contains(tostring(access_error), "injected unreadable config")
    and contains(tostring(access_error), config_path), tostring(access_error or unreadable))
  check("load bounds its only config read and requests strict UTF-8", seen
    and seen.maxbytes == 1024 * 1024 and seen.encoding == "utf-8")

  local directory_root = fs.tempdir { dir = fs.absolute(T.work), prefix = "scan-policy-dir-" }
  check("a separate fixture for a directory-as-config is created", directory_root ~= nil)
  if directory_root then
    fs.mkdir(directory_root .. "/kuu.config.json")
    local value, problem = policy.load(directory_root)
    check("a directory at the config path is refused instead of treated as absent", value == nil
      and err.is(problem, "SCAN", "config") and contains(tostring(problem), "kuu.config.json"), tostring(problem))
  end
  local no_root, no_root_error = policy.load(root .. "/nonexistent-root")
  check("a nonexistent root does not silently get a default policy", no_root == nil
    and err.is(no_root_error, "SCAN", "config"), tostring(no_root_error))
  fs.write(root .. "/file-root", "not a directory")
  local file_root, file_root_error = policy.load(root .. "/file-root")
  check("a file used as the root does not silently get a default policy", file_root == nil
    and err.is(file_root_error, "SCAN", "config"), tostring(file_root_error))

  fs.read = function(path, options)
    if path == config_path then return nil, err.new("FS", "notfound", "injected missing read for existing config") end
    return original_read(path, options)
  end
  local notfound_ok, exists_value, exists_error = pcall(policy.load, root)
  fs.read = original_read
  check("a notfound read cannot conceal an existing config entry", notfound_ok and exists_value == nil
    and err.is(exists_error, "SCAN", "config"), tostring(exists_error or exists_value))
end
