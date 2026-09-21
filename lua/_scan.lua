-- _scan.lua -- one private inspection path for checking and inventory.
-- Policy is captured by each operation before project code runs.
global none
global <const> require, ipairs, tostring, table, error

local fs, native = require "fs", require "_scan_native"
local json, clock = require "json", require("sched").clock
local scan = {}

local legacy_dirs = {
  check = { ".git", ".tools", "build", "node_modules" },
  ledger = { ".git", ".tools", "build", "node_modules", ".kuu" },
}

local function order_error(a, b)
  if a.path ~= b.path then return a.path < b.path end
  return a.message < b.message
end

local function collect(root, scope, start, legacy_ledger)
  local began = clock()
  root = fs.absolute(root)
  start = fs.absolute(start or root)
  local prefix = fs.relative(start, root):gsub("\\", "/")
  if prefix == "." then prefix = "" end
  local outside = prefix == ".." or prefix:sub(1, 3) == "../"
    or prefix:find(":", 1, true) ~= nil or prefix:sub(1, 1) == "/"
  local options = {
    exclude_dirs = scope.effective_dirs, exclude_paths = outside and {} or scope.exclude_paths,
    prefix = outside and "" or prefix,
  }
  if scope.legacy_prune then
    -- check.PRUNE has always been a mutable exported table of native prune
    -- patterns. Preserve those overrides without giving configured rules
    -- wildcard semantics.
    options.exclude_dirs, options.legacy_prune = {}, scope.legacy_prune
  elseif scope.extra_prune then
    -- A deliberate legacy checker override can further restrict configured
    -- observation, but cannot remove its mandatory or exact exclusions.
    options.legacy_prune = scope.extra_prune
  end
  local walked, why = native.collect(start, options)
  local observed = {
    root = root, start = start, scope = scope, files = {}, errors = {}, paths = {}, links = {}, skipped = {},
    counts = { files = 0, enumerated_dirs = 0, excluded_dirs = 0, nofollow_links = 0, errors = 0 },
    complete = false, path_rules_applied = not outside,
  }
  if not walked then
    observed.errors[1] = { path = start, message = tostring(why) }
  else
    observed.start = walked.root
    observed.paths, observed.links, observed.skipped = walked.paths, walked.links, walked.skipped
    observed.counts.enumerated_dirs, observed.counts.excluded_dirs = walked.enumerated, walked.pruned
    local omitted_parents = {}
    for _, link in ipairs(walked.links) do
      if link.action == "nofollow" then observed.counts.nofollow_links = observed.counts.nofollow_links + 1 end
      -- The old ledger skipped listings for every reparse directory, even
      -- an explicitly followed root or ordinary filter. Retain that scope
      -- for the retained legacy-scope benchmark adapter only.
      if legacy_ledger and link.kind ~= "file" then omitted_parents[link.path] = true end
    end
    for _, file in ipairs(walked.files) do
      local parent = file.path:match("^(.*)/[^/]+$")
      if parent and parent:match("^%a:$") then parent = parent .. "/" end
      if not omitted_parents[parent] then observed.files[#observed.files + 1] = file end
    end
    for _, e in ipairs(walked.errors) do
      local message = e.message or ("FS oserror: " .. e.reason .. " (win32 " .. tostring(e.win32) .. ")")
      observed.errors[#observed.errors + 1] = { path = e.path, message = message, win32 = e.win32 }
    end
  end
  table.sort(observed.files, function(a, b) return a.path < b.path end)
  table.sort(observed.errors, order_error)
  observed.counts.files, observed.counts.errors = #observed.files, #observed.errors
  observed.complete = #observed.errors == 0
  observed.seconds = clock() - began
  return observed
end

-- Scope is an already-normalized _scan_policy result; never load config or
-- execute a manifest here. The start is deliberate, so its own exclusion and
-- those of ancestors are overridden; descendant rules still apply.
function scan.collect(root, scope, start)
  return collect(root, scope, start, false)
end

-- Retained compatibility adapter for old-scope tests and benchmarks. Public
-- consumers now use configured collection.
function scan.compat(root, kind, start, prune)
  if not legacy_dirs[kind] then error("unknown compatibility scan: " .. tostring(kind), 2) end
  local names = {}
  for i, name in ipairs(prune or legacy_dirs[kind]) do names[i] = name end
  return collect(root, { kind = "legacy-" .. kind, effective_dirs = names, exclude_paths = {}, legacy_prune = names }, start, kind == "ledger")
end

-- The public checker retains one read finding per incomplete directory,
-- while the shared result keeps every enumeration diagnostic.
function scan.lua_files(observed)
  local paths, errors, failed = {}, {}, {}
  for _, file in ipairs(observed.files) do
    if file.path:sub(-4) == ".lua" then paths[#paths + 1] = file.path end
  end
  for _, e in ipairs(observed.errors) do
    if not failed[e.path] then errors[#errors + 1], failed[e.path] = e, true end
  end
  return paths, errors
end

local function array(values)
  local result = json.array {}
  for _, value in ipairs(values or {}) do result[#result + 1] = value end
  return result
end

-- No canonical JSON string or full native path/link lists on the wire. The
-- fingerprint identifies exact configured rules; legacy extra patterns, if
-- present for a direct API call, are disclosed separately.
function scan.describe(scope)
  local source = scope.source
  return { v = scope.v or 1, defaults = scope.defaults, fingerprint = scope.fingerprint,
    source = source and { kind = source.kind, path = source.path } or nil,
    mandatory_dirs = array(scope.mandatory_dirs), default_dirs = array(scope.default_dirs),
    exclude_dirs = array(scope.exclude_dirs), exclude_paths = array(scope.exclude_paths),
    effective_dirs = array(scope.effective_dirs),
    extra_prune = scope.extra_prune and array(scope.extra_prune) or nil }
end

function scan.report(observed)
  return { root = observed.root, start = observed.start, path_rules_applied = observed.path_rules_applied,
    scope = scan.describe(observed.scope), complete = observed.complete, counts = observed.counts,
    errors = array(observed.errors), seconds = observed.seconds }
end

return scan
