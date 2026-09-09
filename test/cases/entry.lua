-- entry.lua -- routes, arguments, decoding, the removed hazards, require,
-- error reporting, and exit codes, by running kuu as a child.
global none
global <const> require, ipairs, tostring, string, io, pcall

return function(T)
  local check, kuu, describe = T.check, T.kuu, T.describe
  local starts, contains = T.starts, T.contains
  local hello = T.fixtures .. "/hello.lua"

  -- identity and usage ------------------------------------------------------
  local r = kuu { "--version" }
  check("version line", r.code == 0 and r.out == "kuu 0.3 (Lua 5.5.1)\n", describe(r))

  r = kuu { "--help" }
  check("help exits 0 on stdout", r.code == 0 and contains(r.out, "usage: kuu FILE") and r.err == "", describe(r))

  r = kuu {}
  check("no arguments is a usage error", r.code == 2 and contains(r.err, "usage:") and r.out == "", describe(r))

  r = kuu { "--bogus" }
  check("unknown option is refused", r.code == 2 and contains(r.err, "ENTRY usage: unknown option '--bogus'"), describe(r))

  r = kuu { "-e" }
  check("-e without a script is a usage error", r.code == 2 and contains(r.err, "-e needs a script"), describe(r))

  -- inline route -------------------------------------------------------------
  r = kuu { "-e", "print(_VERSION)" }
  check("inline script runs Lua 5.5", r.code == 0 and r.out == "Lua 5.5\n", describe(r))

  r = kuu { "-e", "print(select('#', ...), ...)", "a", "b c" }
  check("inline arguments arrive as ...", r.out == "2\ta\tb c\n", describe(r))

  r = kuu { "-e", "local rt = require('rt'); print(rt.version, rt.lua, rt.route, #rt.args, rt.args[2], rt.program, rt.exe ~= nil)", "x", "y" }
  check("rt module describes the launch", r.out == "0.3\tLua 5.5.1\teval\t2\ty\tnil\ttrue\n", describe(r))

  local accented = "héllo wörld €"
  r = kuu { "-e", "io.write(...)", accented }
  check("arguments are UTF-8 bytes, output is exact bytes", r.out == accented, describe(r))

  r = kuu { "-e", 'io.write("a\\nb\\n")' }
  check("stdout has no CRLF translation", r.out == "a\nb\n", describe(r))

  r = kuu { "-e", "error('boom')" }
  check("uncaught error: message, traceback, exit 1",
    r.code == 1 and starts(r.err, "kuu: (command line):1: boom\nstack traceback:") and r.out == "", describe(r))

  r = kuu { "-e", "error({code = 1})" }
  check("table error object without __tostring is named",
    r.code == 1 and starts(r.err, "kuu: (error object is a table value)"), describe(r))

  r = kuu { "-e", "error(setmetatable({}, {__tostring = function() return 'PROC timeout: gone' end}))" }
  check("error object with __tostring is rendered", r.code == 1 and starts(r.err, "kuu: PROC timeout: gone"), describe(r))

  r = kuu { "-e", "x = = 1" }
  check("syntax error exits 1 with the location", r.code == 1 and starts(r.err, "kuu: (command line):1:"), describe(r))

  r = kuu { "-e", "coroutine.yield()" }
  check("top-level yield is refused", r.code == 1 and contains(r.err, "SCHED yield"), describe(r))

  r = kuu { "-e", "print(coroutine.isyieldable())" }
  check("the main chunk runs as a coroutine", r.out == "true\n", describe(r))

  -- hazards removed, loading rules --------------------------------------------
  r = kuu { "-e", "print(io.popen, os.execute, os.remove, os.rename, os.tmpname, dofile, loadfile, package.loadlib, debug)" }
  check("hazardous functions are absent", r.out == string.rep("nil\t", 8) .. "nil\n", describe(r))

  r = kuu { "-e", "print(type(os.getenv), type(os.time), type(os.exit), type(io.read), type(io.stderr), type(utf8.char), type(coroutine.wrap), type(string.pack), type(math.tointeger), type(table.create))" }
  check("the intended standard library is present",
    r.out == string.rep("function\t", 3) .. "function\tuserdata\t" .. string.rep("function\t", 4) .. "function\n", describe(r))

  r = kuu { "-e", "print(package.path == '', package.cpath == '', #package.searchers)" }
  check("require has no environment paths and two searchers", r.out == "true\ttrue\t2\n", describe(r))

  r = kuu { "-e", "print(load(string.dump(function() end)))" }
  check("load refuses binary chunks", r.code == 0 and contains(r.out, "binary chunk"), describe(r))

  r = kuu { "-e", "print(load('return 1 + 1', 'x', 'b'))" }
  check("load ignores a requested binary mode", starts(r.out, "function"), describe(r))

  r = kuu { "-e", "print(load('return ...', 'x', 't', nil)('env-nil'))" }
  check("load keeps an explicit nil env distinct from absent", r.out == "env-nil\n", describe(r))

  r = kuu { "-e", "for _, m in ipairs{'rt', 'err', 'sched', 'proc'} do assert(type(require(m)) == 'table', m) end print('modules')" }
  check("kuu's modules load through require", r.out == "modules\n", describe(r))

  -- file route ----------------------------------------------------------------
  r = kuu { hello, "one", "two" }
  check("program file runs with arguments", r.code == 0 and r.out == "hello\tone\ttwo\n", describe(r))

  r = kuu { T.fixtures .. "/needs_mod.lua" }
  check("require finds neighbours by name and by init.lua", r.code == 0 and r.out == "mod says hi\tsub.pkg\tfile\ttrue\n", describe(r))

  r = kuu { "-e", "require('nope')" }
  check("missing module names the paths tried",
    r.code == 1 and contains(r.err, "module 'nope' not found") and contains(r.err, "nope.lua'") and contains(r.err, "nope/init.lua'"), describe(r))

  r = kuu { "-e", "require('../escape')" }
  check("require refuses names that are not plain dotted names", r.code == 1 and contains(r.err, "not a plain dotted name"), describe(r))

  r = kuu { T.fixtures .. "/shebang.lua" }
  check("shebang line is skipped and line numbers hold",
    r.code == 1 and r.out == "shebang ok\n" and contains(r.err, "shebang.lua:3: line three"), describe(r))

  r = kuu { T.fixtures .. "/exit7.lua" }
  check("os.exit sets the exit code", r.code == 7 and r.out == "leaving\n", describe(r))

  r = kuu { T.fixtures .. "/closing.lua" }
  check("pending <close> variables are closed after an error",
    r.code == 1 and contains(r.err, "closed with: ") and contains(r.err, "failing on purpose"), describe(r))

  r = kuu { T.fixtures .. "/global_none.lua" }
  check("Lua 5.5 global declarations work", r.code == 0 and r.out == "declared\tfile\n", describe(r))

  r = kuu { T.fixtures .. "/global_typo.lua" }
  check("under global none a misspelled name is a load error", r.code == 1 and contains(r.err, "reuslt"), describe(r))

  r = kuu { T.fixtures .. "/does_not_exist.lua" }
  check("missing program file is ENTRY notfound", r.code == 2 and starts(r.err, "kuu: ENTRY notfound: cannot find program file '"), describe(r))

  r = kuu { T.fixtures }
  check("a directory is refused as a program", r.code == 2 and contains(r.err, "ENTRY badvalue") and contains(r.err, "is a directory"), describe(r))

  local unicode_dir = T.work .. "/hé llo"
  -- cmd.exe parses its own line: keep the path a separate argument, no quotes
  -- inside the /c text.  An existing directory makes mkdir exit 1; both are fine.
  local made = require("proc").run { "cmd.exe", "/c", "mkdir", (unicode_dir:gsub("/", "\\")) }
  local probe = io.open(unicode_dir .. "/probe.txt", "wb")
  check("a directory with a non-ASCII name can be made and opened", made ~= nil and probe ~= nil, made and describe(made))
  if probe then probe:close() end
  T.write_file(unicode_dir .. "/mod.lua", T.read_file(T.fixtures .. "/mod.lua"))
  T.write_file(unicode_dir .. "/main.lua", "print(require('mod').hi, ...)\n")
  r = kuu { unicode_dir .. "/main.lua", "z" }
  check("program and modules under a non-ASCII path", r.code == 0 and r.out == "mod says hi\tz\n", describe(r))

  r = kuu({ "main.lua", "rel" }, { cwd = unicode_dir })
  check("relative program path resolves require from its directory", r.code == 0 and r.out == "mod says hi\trel\n", describe(r))

  -- stdin route ---------------------------------------------------------------
  r = kuu({ "-", "from-stdin" }, { stdin = T.read_file(hello) })
  check("stdin program runs with arguments", r.code == 0 and r.out == "hello\tfrom-stdin\n", describe(r))

  r = kuu({ "-", "a" }, { stdin = "\239\187\191print('bom ok')\r\nprint(select('#', ...))\r\n" })
  check("BOM and CRLF are accepted", r.code == 0 and r.out == "bom ok\n1\n", describe(r))

  r = kuu({ "-" }, { stdin = "print('x')\n\255" })
  check("invalid UTF-8 on stdin is ENTRY encoding", r.code == 2 and r.err == "kuu: ENTRY encoding: the stdin program is not valid UTF-8\n", describe(r))

  local bad = T.work .. "/bad_utf8.lua"
  T.write_file(bad, "print('x')\n\255")
  r = kuu { bad }
  check("invalid UTF-8 in a file is ENTRY encoding", r.code == 2 and contains(r.err, "ENTRY encoding: program file '") and contains(r.err, "is not valid UTF-8"), describe(r))

  local big = T.work .. "/too_big.lua"
  do
    local f = io.open(big, "wb")
    local chunk = string.rep(" ", 1024 * 1024)
    for _ = 1, 17 do f:write(chunk) end
    f:close()
  end
  r = kuu({ "-" }, { stdin = T.read_file(big) })
  check("stdin program over 16 MiB is refused", r.code == 2 and contains(r.err, "ENTRY toobig") and contains(r.err, "larger than 16 MiB"), describe(r))

  r = kuu { big }
  check("program file over 16 MiB is refused", r.code == 2 and contains(r.err, "ENTRY toobig"), describe(r))

  local empty = T.work .. "/empty.lua"
  T.write_file(empty, "")
  r = kuu { empty }
  check("an empty program runs and exits 0", r.code == 0 and r.out == "" and r.err == "", describe(r))

  r = kuu({ hello, "with-stdin" }, { stdin = "ignored input" })
  check("stdin given to the file route is left alone", r.code == 0 and r.out == "hello\twith-stdin\n", describe(r))
end
