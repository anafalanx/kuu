-- _fixglobals.lua -- write a file's global declaration for it, in both
-- directions.  Private: `kuu check --fix` is the public face.
--
-- `global none` and its list of standard names costs little in lines and a
-- lot in attention: across the repository's own Lua, 54 of 559 declared names
-- were dead, because forgetting to add a name is a loud load-time error while
-- forgetting to remove one is silent forever.  The list rots in one direction
-- only.
--
-- This fixes both directions, and knows nothing about Lua's scoping rules,
-- because the Lua compiler already does.  Under a global declaration the
-- compiler names each undeclared variable in turn, so the needed set is found
-- by compiling and reading the complaint; and a declared name is unnecessary
-- exactly when removing it still compiles.  The compiler is the authority on
-- what a chunk needs, as it is for the rest of `check`.
global <const> require, ipairs, pairs, load, tostring, table, string, _G

local fs = require "fs"
local trim = require("text").trim

local WIDTH = 79

-- A name is only ever added if the runtime actually has a global by that
-- name. This is the whole safety of the tool. `global none` exists so that a
-- misspelling is a load-time error, and a fixer that declared every name the
-- compiler complained about would answer `print(reuslt)` by declaring
-- `reuslt` -- turning a caught mistake into a silent nil, which is precisely
-- the failure the declaration was adopted to prevent. So the set comes from
-- the runtime itself and cannot drift from it.
local STANDARD = {}
for name in pairs(_G) do STANDARD[name] = true end

-- The contiguous run of top-level `global` statements, and the names it
-- declares in the order it declares them.  Order is preserved so that fixing
-- a file does not reshuffle a list somebody arranged.
local function declaration(lines)
  -- The block sits at the top, after any leading comments, which is where the
  -- manual tells you to put it and where every file in the corpus does. Only
  -- looking there is also what keeps a `global` at the start of a line inside
  -- an embedded fixture string from being mistaken for one of the file's own.
  local at = 1
  while lines[at] and (lines[at]:match("^%s*%-%-") or lines[at]:match("^%s*$")) do
    at = at + 1
  end
  if not (lines[at] and (lines[at]:match("^global%s") or lines[at] == "global")) then
    return nil, nil
  end

  local first, last = at, at
  local order, const, mutable, none = {}, {}, {}, false
  local attribute = true
  local i = first
  while lines[i] do
    local line = lines[i]
    local starts = line:match("^global%s") or line == "global"
    -- A declaration wraps when its line ends in a comma, and this tool wraps
    -- long ones itself, so it has to read back what it writes.
    local continues = i > first and trim(lines[i - 1], "right"):byte(-1) == 0x2C
    if not (starts or continues) then break end
    last = i

    local rest
    if starts then
      if line:match("^global%s+none%s*$") then
        none = true
        rest = nil
      else
        local list = line:match("^global%s+<const>%s+(.*)$")
        attribute = list ~= nil
        rest = list or line:match("^global%s+(.*)$")
      end
    else
      rest = line
    end
    for name in (rest or ""):gmatch("[A-Za-z_][A-Za-z0-9_]*") do
      order[#order + 1] = name
      if attribute then const[name] = true else mutable[name] = true end
    end
    i = i + 1
  end

  return { first = first, last = last, order = order, const = const,
           mutable = mutable, none = none }
end

-- Render a declaration block, wrapping a long list rather than running past
-- the width the rest of the source keeps to.
local function render(order, const, none)
  local out = {}
  if none then out[#out + 1] = "global none" end
  for _, attribute in ipairs { true, false } do
    local names = {}
    for _, name in ipairs(order) do
      if (const[name] and true or false) == attribute then names[#names + 1] = name end
    end
    if #names > 0 then
      local head = attribute and "global <const> " or "global "
      local line = head
      for i, name in ipairs(names) do
        local piece = name .. (i < #names and "," or "")
        if #line + #piece + 1 > WIDTH and line ~= head then
          out[#out + 1] = trim(line, "right")
          line = string.rep(" ", #head) .. piece .. " "
        else
          line = line .. piece .. " "
        end
      end
      out[#out + 1] = trim(line, "right")
    end
  end
  return out
end

local function assemble(lines, block, replacement)
  local out = {}
  for i = 1, block.first - 1 do out[#out + 1] = lines[i] end
  for _, line in ipairs(replacement) do out[#out + 1] = line end
  for i = block.last + 1, #lines do out[#out + 1] = lines[i] end
  return table.concat(out, "\n")
end

-- Ask the compiler what the chunk needs.  Each pass adds the one name it
-- names, or demotes a name it refuses to let the chunk assign to.
local function solve(lines, block)
  local order, const = {}, {}
  for _, name in ipairs(block.order) do
    order[#order + 1] = name
    const[name] = block.const[name] ~= nil
  end
  local seen = {}
  for _, name in ipairs(order) do seen[name] = true end

  for _ = 1, 300 do
    local source = assemble(lines, block, render(order, const, block.none))
    local chunk, e = load(source, "@fix", "t")
    if chunk then return order, const end
    local missing = e and e:match("variable '([A-Za-z_][A-Za-z0-9_]*)'[^\n]-not declared")
    local assigned = e and e:match("attempt to assign to const variable '([A-Za-z_][A-Za-z0-9_]*)'")
    if missing and not STANDARD[missing] then
      return nil, "`" .. missing .. "` is not a global this runtime has; it reads like a misspelling, and declaring it would hide one"
    elseif missing and not seen[missing] then
      order[#order + 1] = missing
      const[missing] = true
      seen[missing] = true
    elseif assigned and const[assigned] then
      const[assigned] = false
    else
      return nil, e or "the file does not compile"
    end
  end
  return nil, "the declaration did not settle"
end

-- A declared name is unnecessary exactly when the chunk still compiles
-- without it.  This is the direction nothing catches today.
local function prune(lines, block, order, const)
  local kept = {}
  for _, name in ipairs(order) do kept[name] = true end
  for _, name in ipairs(order) do
    kept[name] = nil
    local trial = {}
    for _, other in ipairs(order) do if kept[other] then trial[#trial + 1] = other end end
    local source = assemble(lines, block, render(trial, const, block.none))
    if not load(source, "@fix", "t") then kept[name] = true end
  end
  local final = {}
  for _, name in ipairs(order) do if kept[name] then final[#final + 1] = name end end
  return final
end

local function split(text)
  local lines = {}
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

local function fix(path, adopt)
  local adopted = false
  local text, e = fs.read(path)
  if not text then return nil, tostring(e) end
  local lines = split(text)

  local block, why = declaration(lines)
  if why then return nil, why end
  if not block then
    if not adopt then return { skipped = "no global declaration" } end
    adopted = true
    -- Adopting a stock-mode file: put the declaration after any leading
    -- comments, which is where every file in the corpus keeps it.
    local at = 1
    while lines[at] and (lines[at]:match("^%s*%-%-") or lines[at]:match("^%s*$")) do at = at + 1 end
    table.insert(lines, at, "global none")
    block = { first = at, last = at, order = {}, const = {}, mutable = {}, none = true }
  end

  local order, const = solve(lines, block)
  if not order then return nil, const end
  order = prune(lines, block, order, const)

  local before = {}
  for i = block.first, block.last do before[#before + 1] = lines[i] end
  local after = render(order, const, block.none)

  local added, removed = {}, {}
  local had = {}
  for _, name in ipairs(block.order) do had[name] = true end
  local has = {}
  for _, name in ipairs(order) do has[name] = true end
  for _, name in ipairs(order) do if not had[name] then added[#added + 1] = name end end
  for _, name in ipairs(block.order) do if not has[name] then removed[#removed + 1] = name end end

  -- Changed means the names changed, never merely that they would be laid
  -- out differently. Reflowing a declaration nobody asked about is diff noise
  -- against the one thing this tool is for.
  local reattributed = false
  for _, name in ipairs(order) do
    if had[name] and (block.const[name] ~= nil) ~= (const[name] and true or false) then
      reattributed = true
    end
  end

  return { path = path, before = before, after = after, added = added,
           removed = removed, text = assemble(lines, block, after) .. "\n",
           changed = adopted or #added > 0 or #removed > 0 or reattributed }
end


return { fix = fix }
