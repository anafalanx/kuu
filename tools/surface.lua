-- surface.lua -- the Win32 surface, so that "small" is a number.
--
--   kuu tools/surface.lua [nm.exe]        (make surface)
--
-- Every function the host objects import by name, read from their undefined
-- symbols with binutils' nm, plus the ones resolved by GetProcAddress at run
-- time, read from src.  Prints the names and the count; docs/roadmap.md
-- records the count, and the number is meant to go down.
global none
global <const> require, ipairs, pairs, print, table, os

local fs, proc, rt = require "fs", require "proc", require "rt"

local nm = rt.args[1] or ".tools/msys2/ucrt64/bin/nm.exe"
local objects = fs.glob("build/obj/host/*.o")
if #objects == 0 then
  print("no host objects under build/obj/host; run make first")
  os.exit(2)
end

local seen = {}
for _, object in ipairs(objects) do
  local r, e = proc.run { nm, "-u", object, timeout = "30s" }
  if not r or r.status ~= "exit" or r.code ~= 0 then
    print("nm failed on " .. object .. ": " .. (r and r.err or e.message))
    os.exit(1)
  end
  for line in r.out:gmatch("[^\r\n]+") do
    local name = line:match("(%S+)%s*$")
    if name then
      name = name:gsub("^__imp_", "")
      -- Windows spells its functions in CamelCase; the C runtime and the
      -- vendored libraries do not.
      if name:match("^[A-Z][%w_]*$") and not name:match("^KU_") and not name:match("^LUA") then
        seen[name] = true
      end
    end
  end
end
local imported = {}
for name in pairs(seen) do imported[#imported + 1] = name end
table.sort(imported)

local resolved = {}
for _, path in ipairs(fs.glob("src/*.c")) do
  local text = fs.read(path)
  for name in text:gmatch('GetProcAddress%([^,]+,%s*"([%w_]+)"') do resolved[#resolved + 1] = name end
  for name in text:gmatch('BIND%([%w_]+,%s*"([%w_]+)"') do resolved[#resolved + 1] = name end
end
table.sort(resolved)

print("imported by name (" .. #imported .. "):")
print("  " .. table.concat(imported, " "))
print("resolved at run time (" .. #resolved .. "):")
print("  " .. table.concat(resolved, " "))
print("surface: " .. (#imported + #resolved))
