-- project.lua -- where a repository's tasks.lua lives, and how the verbs
-- enter the project.
--
--   local project = require "project"
--   local root = project.find()          -- the nearest directory upward holding tasks.lua
--   project.enter(root)                  -- chdir there and point `require` at it
--   project.load_tasks(root)             -- run tasks.lua, which fills the task registry
global none
global <const> require, tostring, pcall, load

local fs = require "fs"
local err = require "err"
local rt = require "rt"

local project = {}

project.TASKS_FILE = "tasks.lua"

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

-- project.find([start]) -> root | nil, err (TASK noproject)
function project.find(start)
  local dir = fs.absolute(start or fs.cwd())
  for _ = 1, 128 do
    if fs.exists(join(dir, project.TASKS_FILE)) == "file" then return dir end
    local up = parent(dir)
    if up == nil then break end
    dir = up
  end
  return nil, err.new("TASK", "noproject", "no " .. project.TASKS_FILE .. " here or in any directory above")
end

function project.enter(root)
  local ok, e = fs.chdir(root)
  if not ok then return nil, e end
  rt.root(root)
  return true
end

-- Runs tasks.lua so it declares its tasks.  A syntax error or a raise while
-- declaring is TASK badvalue with the location in the message.
function project.load_tasks(root)
  local path = join(root, project.TASKS_FILE)
  local text, e = fs.read(path, { encoding = "utf-8" })
  if not text then return nil, e end
  if text:sub(1, 1) == "#" then text = text:gsub("^[^\n]*", "", 1) end
  local chunk, load_error = load(text, "@" .. project.TASKS_FILE, "t")
  if chunk == nil then return nil, err.new("TASK", "badvalue", tostring(load_error)) end
  local ok, raised = pcall(chunk)
  if not ok then
    if err.is(raised) then return nil, raised end
    return nil, err.new("TASK", "badvalue", tostring(raised))
  end
  return true
end

return project
