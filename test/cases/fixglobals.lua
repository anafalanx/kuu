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
global <const> require, ipairs, pcall, table, load

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

  -- Compilation is not a preservation proof: dropping a global's assignment
  -- leaves valid Lua whose values and effects have changed. Unsupported
  -- declarations must be refused byte for byte, even with --adopt.
  local initialized_text = "global none\nglobal counter, unused = 1, 2\nreturn counter + 1\n"
  local initialized = write("initialized.lua", initialized_text)
  local before_value = load(initialized_text, "@before", "t", {})()
  local init = report("--fix", "--adopt", initialized)
  local after_text = fs.read(initialized)
  check("initialized declarations are refused without losing their assignments",
    init ~= nil and #init.fixed == 0 and #init.unfixed == 1 and after_text == initialized_text
      and load(after_text, "@after", "t", {})() == before_value and before_value == 2,
    init and json.encode(init) or "no report")
  local continued_text = "global none\nglobal counter, unused\n-- the assignment continues\n= 1, 2\nreturn counter + 1\n"
  local continued = write("continued.lua", continued_text)
  local continuation = report("--fix", continued)
  check("an initializer after a newline and comments is refused as well",
    continuation ~= nil and #continuation.fixed == 0 and #continuation.unfixed == 1
      and fs.read(continued) == continued_text)
  local comma_text = "global none\nglobal counter, unused\n, extra = 1, 2, 3\nreturn counter + 1\n"
  local comma = write("comma-continuation.lua", comma_text)
  local comma_report = report("--fix", comma)
  check("a comma on the next line cannot hide an initializer from the fixer",
    comma_report ~= nil and #comma_report.fixed == 0 and #comma_report.unfixed == 1 and fs.read(comma) == comma_text)
  local wildcard_text = "global *\nreturn 1\n"
  local wildcard = write("wildcard.lua", wildcard_text)
  local refused = report("--fix", wildcard)
  check("unsupported declaration forms are refused rather than normalized away",
    refused ~= nil and #refused.fixed == 0 and #refused.unfixed == 1 and fs.read(wildcard) == wildcard_text)

  local sole_text = 'global <const> print\nprint("hello")\n'
  local sole = write("sole.lua", sole_text)
  local kept = report("--fix", sole)
  check("removing the last declaration cannot make a used global look unused",
    kept ~= nil and #kept.fixed == 0 and kept.warnings == 0 and fs.read(sole) == sole_text)
  local empty = write("empty.lua", "global <const> print\nreturn 2\n")
  local pruned = report("--fix", empty)
  check("pruning the last unused name preserves declared-only globals",
    pruned ~= nil and #pruned.fixed == 1 and pruned.warnings == 0
      and fs.read(empty) == "global none\nreturn 2\n"
      and load((fs.read(empty):gsub("return 2", "return missing")), "@strict", "t") == nil)

  for _, prefix in ipairs {
    "--[[\nA license with ordinary text\nglobal fake\n]]\n",
    "--[==[\nA license containing ]] and ]=]\n]==]\n-- one more comment\n\n",
    "--[[license]] ",
  } do
    local commented = write("commented.lua", prefix .. 'return tostring(7)\n')
    local adopted = report("--fix", "--adopt", commented)
    local fixed_text = fs.read(commented)
    check("adoption puts declarations after complete long comments",
      adopted ~= nil and #adopted.fixed == 1 and adopted.errors == 0 and adopted.warnings == 0
        and fixed_text:sub(1, #prefix) == prefix,
      adopted and json.encode(adopted) or "no report")
    check("the adopted long-comment file is stable on the next pass",
      #((report("--fix", commented) or {}).fixed or {}) == 0)
  end
  local header = "--[=[\nLicense\n]=]\n"
  local declared = write("declared-header.lua", header .. "global <const> print, tostring\nreturn tostring(1)\n")
  check("an existing declaration after a long comment is found and pruned",
    #((report("--fix", declared) or {}).fixed or {}) == 1
      and fs.read(declared) == header .. "global <const> tostring\nreturn tostring(1)\n")

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
