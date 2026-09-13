-- project.lua -- where a repository's manifest.lua lives, and how the verbs
-- enter the project.
--
--   local project = require "project"
--   local root, file = project.find()    -- the nearest directory upward holding manifest.lua, and the file's name
--   project.enter(root)                  -- chdir there and point `require` at it
--   project.load_tasks(root)             -- run the manifest, which fills the task registry
global none
global <const> require, ipairs, tostring, pcall, load

local fs = require "fs"
local err = require "err"
local rt = require "rt"

local project = {}

-- The declaration file.  Through 0.9 it was tasks.lua; 0.10 still finds one
-- where no manifest.lua is, reads it as the manifest, and says so, so a
-- project renames when it upgrades and not before.  0.11 looks for the old
-- name no longer.
project.MANIFEST = "manifest.lua"
project.LEGACY = "tasks.lua"
project.LEGACY_NOTE = "tasks.lua is read as the manifest for this release; rename it to manifest.lua, nothing inside it changes"

local function join(dir, name)
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

local function parent(dir)
  if dir:match("^%a:/$") or dir:match("^//[^/]+/[^/]+/?$") then return nil end -- a drive or share root
  local up = dir:match("^(.*)/[^/]+$")
  if up == nil then return nil end
  if up:match("^%a:$") then return up .. "/" end
  return up
end

-- The declaration file in `dir`, or nil: manifest.lua, else tasks.lua.
local function declaration_in(dir)
  for _, name in ipairs { project.MANIFEST, project.LEGACY } do
    if fs.exists(join(dir, name)) == "file" then return name end
  end
  return nil
end

-- project.find([start]) -> root, file | nil, err (TASK noproject)
function project.find(start)
  local dir = fs.absolute(start or fs.cwd())
  for _ = 1, 128 do
    local name = declaration_in(dir)
    if name then return dir, name end
    local up = parent(dir)
    if up == nil then break end
    dir = up
  end
  return nil, err.new("TASK", "noproject", "no " .. project.MANIFEST .. " here or in any directory above")
end

function project.enter(root)
  local ok, e = fs.chdir(root)
  if not ok then return nil, e end
  rt.root(root)
  return true
end

-- Runs the manifest so it declares its tasks.  A syntax error or a raise
-- while declaring is TASK badvalue with the location in the message.
-- project.load_tasks(root) -> true [, note] | nil, err; `note` is the
-- sentence to show when the file read was tasks.lua.
function project.load_tasks(root)
  local name = declaration_in(root)
  if name == nil then return nil, err.new("TASK", "noproject", "no " .. project.MANIFEST .. " in " .. root) end
  local path = join(root, name)
  local text, e = fs.read(path, { encoding = "utf-8" })
  if not text then return nil, e end
  if text:sub(1, 1) == "#" then text = text:gsub("^[^\n]*", "", 1) end
  local chunk, load_error = load(text, "@" .. name, "t")
  if chunk == nil then return nil, err.new("TASK", "badvalue", tostring(load_error)) end
  local ok, raised = pcall(chunk)
  if not ok then
    if err.is(raised) then return nil, raised end
    return nil, err.new("TASK", "badvalue", tostring(raised))
  end
  if name == project.LEGACY then return true, project.LEGACY_NOTE end
  return true
end

return project
