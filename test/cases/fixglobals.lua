-- fixglobals.lua -- `kuu check --fix` writes a file's global declaration for
-- it, in both directions, by asking the Lua compiler what the chunk needs
-- rather than by knowing Lua's scoping rules itself.
--
-- The measurement that motivated it: declarations are 1.8% of the repository's
-- Lua, and the first run over it removed 62 dead names and added none, because
-- forgetting to add a name is a loud error while forgetting to remove one is
-- silent forever. The
-- last check here is the one that matters most -- it holds the tree at zero,
-- so the list cannot rot again.
global none
global <const> require, ipairs, pcall, table

return function(T)
  local check = T.check
  local fs = require "fs"
  local proc = require "proc"
  local json = require "json"
  local rt = require "rt"

  local root = fs.canon(T.root).path

  -- Build the argv explicitly: in `{a, b, ..., k = v}` the vararg is not the
  -- last field, so Lua expands it to a single value and every argument after
  -- the first is silently dropped.
  local function run(...)
    local argv = { rt.exe, "check" }
    for _, a in ipairs { ... } do argv[#argv + 1] = a end
    argv.timeout = "120s"
    argv.cwd = root
    return proc.run(argv)
  end

  local function report(...)
    local r = run("--json", ...)
    if not r or r.code > 1 then return nil, r and (r.out .. r.err) or "no result" end
    local ok, v = pcall(json.decode, r.out)
    if not ok then return nil, r.out end
    return v.result
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

  -- Adds what the chunk uses and removes what it does not, in one pass. The
  -- removal direction is the one nothing else catches.
  local both = write("both.lua",
    'global none\nglobal <const> print, select, math\nlocal x = tostring(1)\nprint(x, ipairs({}))\n')
  local r = report("--fix", both)
  check("it adds the names a chunk uses and removes the ones it does not",
    r ~= nil and #r.fixed == 1
      and table.concat(r.fixed[1].added, ",") == "tostring,ipairs"
      and table.concat(r.fixed[1].removed, ",") == "select,math",
    r and json.encode(r.fixed) or "no report")
  check("and the file then checks clean", (report(both) or {}).errors == 0)

  -- The safety property. `global none` exists so a misspelling is a load-time
  -- error; a fixer that declared every name the compiler named would answer
  -- `print(reuslt)` by declaring `reuslt`, converting a caught mistake into a
  -- silent nil. It must refuse, and leave the error standing.
  local typo = write("typo.lua",
    'global none\nglobal <const> print\nlocal result = 1\nprint(reuslt)\n')
  local t = report("--fix", typo)
  check("it refuses a misspelling rather than declaring it",
    t ~= nil and #t.fixed == 0 and #t.unfixed == 1
      and t.unfixed[1].message:find("misspelling", 1, true) ~= nil,
    t and json.encode(t) or "no report")
  check("and leaves the file alone, error intact",
    (fs.read(typo) or ""):find("<const> print\n", 1, true) ~= nil
      and (report(typo) or {}).errors == 1)

  -- A file in stock Lua's mode is left alone unless --adopt is given, because
  -- switching a chunk to declared-only mode is a bigger change than fixing a
  -- list that is already there.
  local stock = write("stock.lua", 'return 1 + 1\n')
  check("a stock-mode file is untouched without --adopt",
    #((report("--fix", stock) or {}).fixed or {}) == 0
      and (fs.read(stock) or "") == "return 1 + 1\n")
  check("and adopted with it",
    #((report("--fix", "--adopt", stock) or {}).fixed or {}) == 1
      and (fs.read(stock) or ""):find("global none", 1, true) == 1)

  -- It has to read back what it writes: a long declaration wraps, and a
  -- wrapped one is a `global` line followed by a continuation. Running twice
  -- is what exposes the difference.
  local long = write("long.lua",
    'global none\nprint(tostring(1), ipairs({}), pairs({}), type(1), select("#"), math.floor(1), table.concat({}), string.rep("x", 1), tonumber("1"), pcall(print), error, assert)\n')
  check("a long declaration is written", #((report("--fix", long) or {}).fixed or {}) == 1)
  check("and it wrapped", (fs.read(long) or ""):find("\n%s+[a-z]") ~= nil)
  check("running again changes nothing: it reads back what it writes",
    #((report("--fix", long) or {}).fixed or {}) == 0)

  -- It writes the declaration and nothing else, and a file's line endings are
  -- part of "nothing else". Rewriting every line of a CRLF file to correct two
  -- of them turns a two-line fix into a whole-file diff, which on Windows is
  -- most of the files it will ever be pointed at.
  local crlf = write("crlf.lua",
    "global none\r\nglobal <const> print, select\r\nlocal x = 1\r\nprint(x)\r\n")
  check("a CRLF file is fixed without its endings being rewritten",
    #((report("--fix", crlf) or {}).fixed or {}) == 1
      and (fs.read(crlf) or ""):find("print(x)\r\n", 1, true) ~= nil
      and (fs.read(crlf) or ""):find("\n\n", 1, true) == nil,
    fs.read(crlf))
  local lf = write("lf.lua",
    "global none\nglobal <const> print, select\nlocal x = 1\nprint(x)\n")
  check("and an LF file keeps its own",
    #((report("--fix", lf) or {}).fixed or {}) == 1
      and (fs.read(lf) or ""):find("\r", 1, true) == nil,
    fs.read(lf))

  fs.remove(dir, { recursive = true })

  -- The invariant. Every declaration in the tree is already correct, so a
  -- name that falls out of use fails the suite instead of rotting quietly.
  -- test/fixtures is excluded: those files are minimal or carry a deliberate
  -- typo, which is their job.
  local tree = report("--fix", "lua", "tools", "test/cases",
    "test/lib.lua", "test/run.lua", "test/soak.lua")
  check("the tree's declarations are correct -- run kuu check --fix",
    tree ~= nil and #tree.fixed == 0,
    tree and json.encode(tree.fixed) or "no report")
end
