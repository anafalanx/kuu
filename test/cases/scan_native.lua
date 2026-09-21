-- scan_native.lua -- private collector input boundaries and metadata parity.
-- Uses the checked-in fixture sources read-only; no scratch state or mocks.
global none
global <const> require, ipairs, tostring, pcall, setmetatable, error

return function(T)
  local check = T.check
  local native, fs, err = require "_scan_native", require "fs", require "err"
  local root = fs.absolute(T.fixtures)
  local function refuses(label, options, code)
    local ok, value = pcall(native.collect, root, options)
    check("native scanner refuses " .. label, not ok and err.is(value, "FS", code or "badvalue"), tostring(value))
  end

  for _, case in ipairs {
    { "boolean options", false }, { "numeric options", 1 }, { "string options", "x" },
    { "unknown option", { unexpected = true }, "usage" },
    { "numeric option key", { [1] = true }, "usage" },
    { "NUL option key", { ["prefix\0bad"] = "x" }, "usage" },
    { "boolean directory rules", { exclude_dirs = false } },
    { "string directory rules", { exclude_dirs = "x" } },
    { "numeric path rules", { exclude_paths = 42 } },
    { "holes in directory rules", { exclude_dirs = { [1] = "x", [3] = "z" } } },
    { "hash keys in directory rules", { exclude_dirs = { x = "x" } } },
    { "boolean directory rule", { exclude_dirs = { true } } },
    { "numeric path rule", { exclude_paths = { 5 } } },
    { "empty directory rule", { exclude_dirs = { "" } } },
    { "NUL directory rule", { exclude_dirs = { "a\0b" } } },
    { "invalid UTF-8 rule", { exclude_dirs = { "\255" } } },
    { "slash in basename", { exclude_dirs = { "a/b" } } },
    { "backslash in basename", { exclude_dirs = { "a\\b" } } },
    { "dot basename", { exclude_dirs = { "." } } },
    { "parent basename", { exclude_dirs = { ".." } } },
    { "star in exact rule", { exclude_dirs = { "*" } } },
    { "question mark in exact rule", { exclude_dirs = { "?" } } },
    { "rooted path rule", { exclude_paths = { "/absolute" } } },
    { "drive-relative path rule", { exclude_paths = { "C:relative" } } },
    { "repeated path separator", { exclude_paths = { "a//b" } } },
    { "parent path component", { exclude_paths = { "a/../b" } } },
    { "trailing path separator", { exclude_paths = { "a/" } } },
    { "boolean legacy prune", { legacy_prune = false } },
    { "holes in legacy prune", { legacy_prune = { [1] = "x", [3] = "z" } } },
    { "hash keys in legacy prune", { legacy_prune = { x = "x" } } },
    { "NUL legacy pattern", { legacy_prune = { "a\0b" } } },
    { "invalid UTF-8 legacy pattern", { legacy_prune = { "\255" } } },
  } do refuses(case[1], case[2], case[3]) end

  for i, prefix in ipairs {
    "/x", "../x", "x/../y", "x//y", "x/", "C:foo", "C:/foo",
    "\\x", "x\\y", ":", "x\0y", "\255", "*",
  } do refuses("invalid prefix #" .. i, { prefix = prefix }) end

  local names, paths = {}, {}
  for i = 1, 265 do names[i] = "excluded" .. i end
  for i = 1, 256 do paths[i] = "nested/excluded" .. i end
  local result, why = native.collect(root, { exclude_dirs = names, exclude_paths = paths, prefix = "subtree" })
  check("native scanner accepts all 265 effective names and 256 path rules",
    result and #result.errors == 0 and result.enumerated >= 1 and #result.files > 0, tostring(why))
  check("native file names retain a supplied project-relative prefix",
    result and result.files[1] and result.files[1].relative:sub(1, 8) == "subtree/")
  names[266], paths[257] = "overflow", "overflow"
  refuses("266 effective directory rules", { exclude_dirs = names })
  refuses("257 path rules", { exclude_paths = paths })

  local legacy = {}
  for i = 1, 64 do legacy[i] = "absent*" end
  local compatible = native.collect(root, { legacy_prune = legacy })
  check("native compatibility rules retain the old 64-pattern limit", compatible and #compatible.errors == 0)
  legacy[65] = "overflow*"
  refuses("65 legacy patterns", { legacy_prune = legacy })

  local metacalls = 0
  local function no_index()
    metacalls = metacalls + 1
    error("unexpected scanner metatable read")
  end
  local options = setmetatable({}, { __index = no_index })
  local ok, raw = pcall(native.collect, root, options)
  check("native options use anchored raw fields without invoking __index", ok and raw and metacalls == 0, tostring(raw))
  local rules = setmetatable({ "absent" }, { __index = no_index })
  ok, raw = pcall(native.collect, root, { exclude_dirs = rules })
  check("native rule arrays use anchored raw entries", ok and raw and metacalls == 0, tostring(raw))

  local called, invalid = pcall(native.collect, root .. "\0junk")
  check("native scanner refuses a NUL root", not called and err.is(invalid, "FS", "badvalue"), tostring(invalid))
  local file, file_error = native.collect(root .. "/scan_fixture.c")
  check("native scanner distinguishes a file root", file == nil and err.is(file_error, "FS", "badvalue"), tostring(file_error))
  local missing, missing_error = native.collect(root .. "/does-not-exist-scan-native-test")
  check("native scanner preserves an absent root error", missing == nil and err.is(missing_error, "FS", "notfound"), tostring(missing_error))

  local baseline, base_error = native.collect(root)
  local public, public_error = fs.dirs(root)
  check("private and public walkers enumerate the same unrestricted directories",
    baseline and public and baseline.dirs == public.dirs and #baseline.paths == #public.paths,
    tostring(base_error or public_error))
  local metadata = baseline ~= nil and #baseline.files > 0
  for _, file_record in ipairs(baseline and baseline.files or {}) do
    local info = fs.stat(file_record.path)
    metadata = metadata and info ~= nil and file_record.size == info.size
      and file_record.mtime == info.mtime and file_record.attrs == info.attrs
  end
  check("enumerated fixture-file metadata agrees with independent fs.stat reads", metadata)

  local test_root = fs.absolute(T.root .. "/test")
  local patterns = { "c*", "f*" }
  local exact_walk = native.collect(test_root, { legacy_prune = patterns })
  local wildcard_walk = fs.dirs(test_root, { prune = patterns })
  local same = exact_walk and wildcard_walk and exact_walk.pruned == wildcard_walk.pruned
    and exact_walk.dirs == wildcard_walk.dirs and #exact_walk.paths == #wildcard_walk.paths
  for i, path in ipairs(exact_walk and exact_walk.paths or {}) do
    same = same and path == wildcard_walk.paths[i]
  end
  check("private compatibility pruning matches fs.dirs wildcard traversal", same)
end
