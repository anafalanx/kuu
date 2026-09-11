-- fixglobals.lua -- tools/fixglobals.lua writes a file's global declaration
-- for it, in both directions, by asking the Lua compiler what the chunk needs
-- rather than by knowing Lua's scoping rules itself.
--
-- The measurement that motivated it: declarations are 1.8% of the corpus's
-- lines, but 54 of 559 declared names were dead, because forgetting to add a
-- name is a loud error while forgetting to remove one is silent forever. The
-- last check here is the one that matters most -- it holds the tree at zero,
-- so the list cannot rot again.
global none
global <const> require, ipairs

return function(T)
  local check = T.check
  local fs = require "fs"
  local proc = require "proc"
  local rt = require "rt"

  local root = fs.canon(T.root).path
  local tool = root .. "/tools/fixglobals.lua"
  check("the tool is present", fs.exists(tool) == "file", tool)

  -- Build the argv explicitly: in `{a, b, ..., k = v}` the vararg is not the
  -- last field, so Lua expands it to a single value and every argument after
  -- the first is silently dropped.
  local function run(...)
    local argv = { rt.exe, tool }
    for _, a in ipairs { ... } do argv[#argv + 1] = a end
    argv.timeout = "120s"
    return proc.run(argv)
  end

  local dir = fs.tempdir { prefix = "kuu-fixglobals-" }
  if not dir then
    check("a temporary directory for the fixtures", false, "fs.tempdir failed")
    return
  end

  local function write(name, text)
    local path = dir .. "/" .. name
    fs.write(path, text)
    return path
  end

  -- Adds what the chunk uses.
  local needs = write("needs.lua",
    'global none\nlocal x = tostring(1)\nprint(x, ipairs({}))\n')
  local added = run(needs)
  check("it adds the standard names a chunk uses",
    added ~= nil and added.code == 1 and added.out:find("+", 1, true) ~= nil
      and added.out:find("tostring", 1, true) ~= nil,
    added and added.out or "no result")

  -- Removes what the chunk does not use. This is the direction nothing
  -- catches today, and the one the corpus got wrong 54 times.
  local dead = write("dead.lua",
    'global none\nglobal <const> print, ipairs, select, math\nprint(1)\n')
  local removed = run(dead)
  check("it removes declarations the chunk does not use",
    removed ~= nil and removed.code == 1
      and removed.out:find("select", 1, true) ~= nil
      and removed.out:find("math", 1, true) ~= nil,
    removed and removed.out or "no result")

  -- The safety property. `global none` exists so a misspelling is a load-time
  -- error; a fixer that declared every name the compiler named would answer
  -- `print(reuslt)` by declaring `reuslt`, converting a caught mistake into a
  -- silent nil. It must refuse instead.
  local typo = write("typo.lua",
    'global none\nglobal <const> print\nlocal result = 1\nprint(reuslt)\n')
  local refused = run(typo)
  check("it refuses a misspelling rather than declaring it",
    refused ~= nil and refused.code == 1
      and refused.out:find("misspelling", 1, true) ~= nil,
    refused and refused.out or "no result")
  local after = fs.read(typo) or ""
  check("and leaves such a file alone",
    after:find("reuslt", 1, true) ~= nil and not after:find("<const> print, reuslt", 1, true),
    after)

  -- It has to read back what it writes: a long declaration is wrapped, and a
  -- wrapped one is a `global` line followed by a continuation. Running twice
  -- is what exposes the difference.
  local long = write("long.lua",
    'global none\nprint(tostring(1), ipairs({}), pairs({}), type(1), select("#"), math.floor(1), table.concat({}), string.rep("x", 1), tonumber("1"), pcall(print), error, assert)\n')
  local once = run("--write", long)
  check("a long declaration is written", once ~= nil and once.code == 1,
    once and once.out or "no result")
  local wrapped = fs.read(long) or ""
  check("and it wrapped", wrapped:find("\n%s+[a-z]") ~= nil, wrapped:sub(1, 200))
  local twice = run(long)
  check("running again changes nothing: it reads back what it writes",
    twice ~= nil and twice.code == 0,
    twice and twice.out or "no result")

  fs.remove(dir, { recursive = true })

  -- The invariant. Every declaration in the tree is already correct, so a
  -- name that falls out of use fails the suite instead of rotting quietly.
  -- test/fixtures is deliberately excluded: those files are minimal or carry
  -- a deliberate typo, which is their job.
  local tree = run(root .. "/lua", root .. "/tools", root .. "/test/cases",
    root .. "/test/lib.lua", root .. "/test/run.lua", root .. "/test/soak.lua")
  check("the tree's declarations are correct -- run tools/fixglobals.lua --write",
    tree ~= nil and tree.code == 0,
    tree and (tree.out .. tree.err) or "no result")
end
