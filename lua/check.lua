-- check.lua -- what kuu can tell about Lua files before running them.
--
--   local check = require "check"
--   local r = check.file("tasks.lua", root)     -- { path, errors, warnings, requires }
--   local t = check.tree(dir, root)             -- every *.lua below dir: { root, reports }
--
-- For each file: it is parsed by Lua 5.5's own compiler, text only, so a
-- syntax error, and under a global declaration an undeclared global, is found
-- with its line; a file with no global declaration at all gets a warning,
-- because there the classic typo is silent; and every literal `require` is
-- listed and resolved against kuu's modules and the root, so a name that
-- resolves to nothing is a warning before any run gets there.  That is the
-- whole claim: nothing is executed and no call is type-checked.
global none
global <const> require, ipairs, pairs, tostring, tonumber, type, string, table, load, package, select

local fs = require "fs"
local rt = require "rt"

local check = {}

check.PRUNE = { ".git", ".tools", "build", "node_modules" }

local function resolves(root, name)
  if package.preload[name] ~= nil or rt.source(name) ~= nil then return true end
  if not name:match("^[%w_%-]+$") and not name:match("^[%w_%-]+%.[%w_%.%-]+$") then return false end
  local rel = name:gsub("%.", "/")
  return fs.exists(root .. "/" .. rel .. ".lua") == "file" or fs.exists(root .. "/" .. rel .. "/init.lua") == "file"
end

local function line_of(text, position)
  local _, newlines = text:sub(1, position - 1):gsub("\n", "")
  return newlines + 1
end

-- check.file(path [, root]) -> { path, errors = { {line, message} }, warnings = { {line, message} }, requires = { names } }
function check.file(path, root)
  root = root or fs.absolute(".")
  local report = { path = fs.absolute(path), errors = {}, warnings = {}, requires = {} }
  local text, e = fs.read(path, { encoding = "utf-8" })
  if not text then
    report.errors[1] = { line = 0, message = tostring(e) }
    return report
  end
  if text:sub(1, 1) == "#" then text = text:gsub("^[^\n]*", "", 1) end
  local chunk, load_error = load(text, "@" .. path, "t")
  if chunk == nil then
    local line, message = tostring(load_error):match("^.-:(%d+):%s*(.*)$")
    report.errors[#report.errors + 1] = { line = tonumber(line) or 0, message = message or tostring(load_error) }
  end
  local declares = false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*global[%s<]") then
      declares = true
      break
    end
  end
  if not declares then
    report.warnings[#report.warnings + 1] = { line = 0, message = "no global declaration: an undeclared global is not an error here; start with `global none`" }
  end
  local seen = {}
  for position, quote, name in text:gmatch("()require%s*%(?%s*([\"'])([^\"'\n]*)%2") do
    if not seen[name] then
      seen[name] = true
      report.requires[#report.requires + 1] = name
      if not resolves(root, name) then
        report.warnings[#report.warnings + 1] = { line = line_of(text, position),
          message = "require \"" .. name .. "\" names no kuu module and no file under " .. root }
      end
    end
  end
  table.sort(report.requires)
  return report
end

-- check.tree(dir [, root]) -> { root, reports }: every *.lua below dir, in
-- path order, skipping check.PRUNE directories; requires resolve against root.
function check.tree(dir, root)
  dir = fs.absolute(dir)
  root = root or dir
  local reports = {}
  local skip = {}
  for _, name in ipairs(check.PRUNE) do skip[name:lower()] = true end
  -- the walker lists a pruned directory and only refuses to enter it; its
  -- own files are skipped here, the root's never
  local walk = fs.dirs(dir, { prune = check.PRUNE })
  for _, sub in ipairs(walk.paths) do
    local listing = (sub == dir or not skip[(sub:match("([^/]+)$") or ""):lower()]) and fs.list(sub) or nil
    if listing then
      for _, entry in ipairs(listing.entries) do
        if entry.kind == "file" and entry.name:match("%.lua$") then
          reports[#reports + 1] = check.file(sub .. "/" .. entry.name, root)
        end
      end
    end
  end
  table.sort(reports, function(a, b) return a.path < b.path end)
  return { root = root, reports = reports }
end

return check
