-- paths.lua -- the string half of fs: join, dirname, basename, ext, stem,
-- relative, and glob; then temporary names and free space.
global none
global <const> require, ipairs, tostring, type, string, table, pcall

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local err = require "err"

  -- strings ----------------------------------------------------------------------------------
  check("join joins with slashes, either separator in, and drops a leading one", fs.join("a", "b\\", "/c", "d.txt") == "a/b/c/d.txt", fs.join("a", "b\\", "/c", "d.txt"))
  check("a piece with a drive starts over", fs.join("a", "C:/x", "y") == "C:/x/y", fs.join("a", "C:/x", "y"))
  check("a bare drive gets its slash", fs.join("C:", "x") == "C:/x", fs.join("C:", "x"))
  check("a share starts over and keeps its root", fs.join("a", "//srv/share", "p") == "//srv/share/p", fs.join("a", "//srv/share", "p"))
  check("empty pieces vanish", fs.join("", "x", "") == "x")
  check("dirname of a nested path", fs.dirname("a/b/c.txt") == "a/b" and fs.dirname("a\\b\\c.txt") == "a/b")
  check("dirname of a bare name is .", fs.dirname("c.txt") == ".")
  check("dirname stops at a drive root", fs.dirname("C:/x") == "C:/" and fs.dirname("C:/") == "C:/")
  check("dirname stops at a share root", fs.dirname("//srv/share/x/y") == "//srv/share/x" and fs.dirname("//srv/share/x") == "//srv/share/")
  check("basename takes the last component, ignoring a trailing slash", fs.basename("a/b/c.txt") == "c.txt" and fs.basename("a/b/") == "b" and fs.basename("C:/") == "")
  check("ext is the last suffix, none for a dot-prefixed name", fs.ext("a/b.tar.gz") == ".gz" and fs.ext(".gitignore") == "" and fs.ext("noext") == "")
  check("stem is the basename without ext", fs.stem("a/b.tar.gz") == "b.tar" and fs.stem(".gitignore") == ".gitignore" and fs.stem("noext") == "noext")
  local ok, raised = pcall(fs.join, "a", 5)
  check("join refuses non-strings", not ok and err.is(raised, "FS", "badvalue"))

  local work = fs.absolute(T.work .. "/paths")
  fs.remove(work, { recursive = true })
  fs.mkdir(work .. "/x/y/z")
  check("relative descends", fs.relative(work .. "/x/y/z.txt", work .. "/x") == "y/z.txt", fs.relative(work .. "/x/y/z.txt", work .. "/x"))
  check("relative climbs", fs.relative(work .. "/x", work .. "/x/y/z") == "../..", fs.relative(work .. "/x", work .. "/x/y/z"))
  check("relative to itself is .", fs.relative(work, work) == ".")
  check("relative ignores case, as the file system does", fs.relative(work:upper() .. "/x/y", work:lower()) == "x/y", fs.relative(work:upper() .. "/x/y", work:lower()))
  check("paths on different roots stay absolute", fs.relative("//nowhere/share/f", work) == "//nowhere/share/f", fs.relative("//nowhere/share/f", work))
  check("relative defaults to the current directory", fs.relative(fs.cwd() .. "/q") == "q")

  -- glob ---------------------------------------------------------------------------------------
  local g = work .. "/g"
  fs.mkdir(g .. "/src/sub")
  fs.mkdir(g .. "/build")
  for _, f in ipairs { "src/a.c", "src/b.c", "src/sub/c.c", "src/sub/d.h", "README.md", "build/x.c" } do fs.write(g .. "/" .. f, f) end
  local function names(list) local out = {} for _, p in ipairs(list) do out[#out + 1] = fs.relative(p, g) end return table.concat(out, " ") end
  local hits, errors = fs.glob(g .. "/src/*.c")
  check("* matches within a name and results are sorted", names(hits) == "src/a.c src/b.c" and #errors == 0, names(hits))
  hits = fs.glob(g .. "/**/*.c")
  check("** matches any number of directories, including none", names(hits) == "build/x.c src/a.c src/b.c src/sub/c.c", names(hits))
  hits = fs.glob(g .. "/src/sub/?.h")
  check("? matches one character", names(hits) == "src/sub/d.h", names(hits))
  hits = fs.glob(g .. "/**", { kind = "directory" })
  check("kind = directory keeps directories only", names(hits) == "build src src/sub", names(hits))
  hits = fs.glob(g .. "/**", { kind = "file" })
  check("kind = file keeps files only", #hits == 6, names(hits))
  hits = fs.glob(g .. "/SRC/*.C")
  check("matching ignores case, as the file system does", #hits == 2, names(hits))
  fs.write(g .. "/é.txt", "e")
  hits = fs.glob(g .. "/?.txt")
  check("? matches one character, not one byte", names(hits) == "é.txt", names(hits))
  hits = fs.glob(g .. "/É*.TXT")
  check("case folding is Unicode, as the file system folds", names(hits) == "é.txt", names(hits))
  hits = fs.glob(g .. "/nowhere/*.c")
  check("a pattern below a missing directory matches nothing, without error", #hits == 0)
  local rel = fs.glob(T.work .. "/paths/g/src/*.c")
  check("a relative pattern gives relative results", #rel == 2 and rel[1] == T.work .. "/paths/g/src/a.c", rel[1])
  ok, raised = pcall(fs.glob, g .. "/**", { kind = "socket" })
  check("an unknown kind is refused", not ok and err.is(raised, "FS", "badvalue"))
  ok, raised = pcall(fs.glob, "")
  check("an empty pattern is refused", not ok and err.is(raised, "FS", "badvalue"))

  -- temporary names ------------------------------------------------------------------------------
  local t1 = fs.tempfile()
  local t2 = fs.tempfile()
  check("tempfile creates an empty file in the temporary directory", fs.exists(t1) == "file" and fs.read(t1) == "" and fs.dirname(t1) == fs.temp(), t1)
  check("two temporary files differ", t1 ~= t2)
  fs.remove(t1)
  fs.remove(t2)
  local t3 = fs.tempfile { dir = work, prefix = "t-", suffix = ".bin" }
  check("dir, prefix, and suffix are honoured", fs.dirname(t3) == work and fs.basename(t3):match("^t%-%x+%.bin$") ~= nil, t3)
  local d1 = fs.tempdir { dir = work }
  check("tempdir creates a directory", fs.exists(d1) == "directory" and fs.dirname(d1) == work and fs.basename(d1):match("^kuu%-%x+$") ~= nil, d1)
  ok, raised = pcall(fs.tempfile, { prefix = "a/b" })
  check("a prefix with a separator is refused", not ok and err.is(raised, "FS", "badvalue"))
  ok, raised = pcall(fs.tempfile, { dir = work, suffix = "." })
  check("a suffix ending in a dot is refused before anything is created", not ok and err.is(raised, "FS", "badvalue"), tostring(raised))
  ok, raised = pcall(fs.tempfile, { dir = work, suffix = "x " })
  check("a suffix ending in a space is refused", not ok and err.is(raised, "FS", "badvalue"), tostring(raised))
  local none, e = fs.tempfile { dir = work .. "/nowhere" }
  check("a missing directory is nil, FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))

  -- free space -------------------------------------------------------------------------------------
  local s = fs.space(work)
  check("space reports total, free, and available bytes", s and s.total > 0 and s.free <= s.total and s.available <= s.free, s and (s.total .. " " .. s.free .. " " .. s.available))
  none, e = fs.space(work .. "/nowhere")
  check("space at a missing path is nil, FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))
end
