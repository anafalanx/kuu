-- fs.lua -- files, directories, identity, links, walks, and watches, against
-- hostile fixtures built first: junctions inside, outside, looped, dangling;
-- hidden and read-only entries; a path beyond 260 characters; Unicode names.
global none
global <const> require, ipairs, pairs, tostring, type, string, table, pcall, math, select, io

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local fs = require "fs"
  local proc = require "proc"
  local err = require "err"
  local sched = require "sched"

  local root = T.work .. "/fs"
  if fs.exists(root) then fs.remove(root, { recursive = true }) end
  check("fixture root created", fs.mkdir(root) == true)
  local function win(p) return (p:gsub("/", "\\")) end
  local function cmd(...) local r = proc.run { "cmd.exe", "/c", ... }; return r and r.code == 0, r end

  -- read / write ---------------------------------------------------------------------
  local bytes = "line\0nul\255\254 héllo " .. string.rep("z", 5000)
  check("write returns true", fs.write(root .. "/a.bin", bytes) == true)
  check("read returns the exact bytes", fs.read(root .. "/a.bin") == bytes)
  check("atomic write replaces the whole content", fs.write(root .. "/a.bin", "short") and fs.read(root .. "/a.bin") == "short")
  check("append adds to the end", fs.write(root .. "/a.bin", "+tail", { append = true }) and fs.read(root .. "/a.bin") == "short+tail")
  check("no temporary file is left beside an atomic write", #fs.list(root).entries == 1, table.concat((function()
    local names = {} for _, e in ipairs(fs.list(root).entries) do names[#names + 1] = e.name end return names end)(), ","))

  -- The replace is retried, because a scanner opening a freshly closed
  -- temporary makes it fail transiently: 15 of 2000 writes on the owner's host
  -- before the retry, none of 4000 after.  A reader held open for the whole
  -- attempt stands in for that holder deterministically: the write must still
  -- fail, so no permission is bypassed, and it must have spent the retry
  -- window rather than giving up on the first rename.
  do
    local held = root .. "/held.bin"
    check("a file to hold is written", fs.write(held, "before", { atomic = false }) == true)
    local handle = io.open(held, "rb")
    local began = sched.clock()
    local wrote, why = fs.write(held, "after")
    local elapsed = (sched.clock() - began) * 1000
    handle:close()
    check("a target held open still fails, with no permission bypassed",
      wrote == nil and err.is(why, "FS", "access"), tostring(why))
    check("the replace was retried rather than abandoned at once",
      elapsed >= 10, string.format("%.0f ms", elapsed))
    check("the held target kept its old bytes", fs.read(held) == "before")
  end
  fs.write(root .. "/text.txt", "\239\187\191caf\195\169\r\nx")
  check("read with encoding utf-8 drops the BOM and validates", fs.read(root .. "/text.txt", { encoding = "utf-8" }) == "café\r\nx")
  fs.write(root .. "/cp.txt", "caf\233")
  check("read with encoding cp1252 decodes", fs.read(root .. "/cp.txt", { encoding = "cp1252" }) == "café")
  local none, e = fs.read(root .. "/cp.txt", { encoding = "utf-8" })
  check("read with a wrong encoding refuses", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = fs.read(root .. "/missing.txt")
  check("reading a missing file is nil, FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))
  none, e = fs.read(root)
  check("reading a directory is refused", none == nil and err.is(e, "FS"), tostring(e))
  none, e = fs.read(root .. "/a.bin", { maxbytes = 3 })
  check("maxbytes refuses a larger file as FS toobig", none == nil and err.is(e, "FS", "toobig"), tostring(e))
  local ok, e2 = pcall(fs.read, root .. "/a.bin", { maxbytez = 3 })
  check("an unknown option is a raised usage error", not ok and err.is(e2, "FS", "usage"), tostring(e2))
  ok, e2 = pcall(fs.write, root .. "/x", "d", { append = true, atomic = true })
  check("append with atomic is refused", not ok and err.is(e2, "FS", "usage"), tostring(e2))

  -- stat / exists -----------------------------------------------------------------------
  local st = fs.stat(root .. "/a.bin")
  check("stat describes a file", st and st.kind == "file" and st.size == 10 and type(st.mtime) == "number" and st.mtime > 1.6e9
    and type(st.attrs) == "number" and st.readonly == false and #st.volume == 16 and #st.file == 16 and st.links == 1, tostring(e))
  check("stat describes a directory", fs.stat(root).kind == "directory")
  check("exists reports kinds", fs.exists(root) == "directory" and fs.exists(root .. "/a.bin") == "file" and fs.exists(root .. "/none") == false)
  none, e = fs.stat(root .. "/none")
  check("stat of a missing path is nil, FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))

  -- mkdir / list --------------------------------------------------------------------------
  check("mkdir creates parents", fs.mkdir(root .. "/deep/er/est") == true and fs.exists(root .. "/deep/er/est") == "directory")
  check("mkdir is idempotent on a directory", fs.mkdir(root .. "/deep") == true)
  none, e = fs.mkdir(root .. "/a.bin")
  check("mkdir over a file is FS exists", none == nil and err.is(e, "FS", "exists"), tostring(e))
  fs.mkdir(root .. "/order")
  for _, name in ipairs { "b1", "aa", "AB", "Zz", "_z", "é", "日本語", "quote'n[brace]", "with space" } do
    fs.write(root .. "/order/" .. name, name)
  end
  local names = {}
  for _, entry in ipairs(fs.list(root .. "/order").entries) do names[#names + 1] = entry.name end
  check("list is in unsigned UTF-8 byte order", table.concat(names, ",") == "AB,Zz,_z,aa,b1,quote'n[brace],with space,é,日本語", table.concat(names, ","))
  local listing = fs.list(root)
  check("list entries carry kind, size, mtime", listing.entries[1].kind ~= nil and type(listing.entries[1].size) == "number" and #listing.errors == 0)
  none, e = fs.list(root .. "/a.bin")
  check("listing a file is refused", none == nil and err.is(e, "FS", "badvalue"), tostring(e))
  none, e = fs.list(root .. "/nowhere")
  check("listing a missing directory is FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))

  -- hidden and read-only ----------------------------------------------------------------
  fs.mkdir(root .. "/hidden")
  local hid = cmd("attrib", "+h", win(root .. "/hidden"))
  check("hidden fixture made", hid)
  check("stat sees the hidden attribute", fs.stat(root .. "/hidden").hidden == true)
  fs.write(root .. "/ro.txt", "ro")
  cmd("attrib", "+r", win(root .. "/ro.txt"))
  check("stat sees read-only", fs.stat(root .. "/ro.txt").readonly == true)
  check("remove clears read-only and deletes", fs.remove(root .. "/ro.txt") == true and fs.exists(root .. "/ro.txt") == false)

  -- junctions ----------------------------------------------------------------------------
  fs.mkdir(root .. "/target/inner")
  fs.write(root .. "/target/inner/leaf.txt", "leaf")
  local j1 = cmd("mklink", "/J", win(root .. "/jlink"), win(root .. "/target"))
  local j2 = cmd("mklink", "/J", win(root .. "/target/outside"), win(T.fixtures))
  local j3 = cmd("mklink", "/J", win(root .. "/target/loop"), win(root))
  fs.mkdir(root .. "/gone")
  local j4 = cmd("mklink", "/J", win(root .. "/dangling"), win(root .. "/gone"))
  fs.remove(root .. "/gone")
  check("junction fixtures made", j1 and j2 and j3 and j4)
  if j1 and j2 and j3 and j4 then
    check("exists names a link as a link", fs.exists(root .. "/jlink") == "link")
    check("stat follows by default", fs.stat(root .. "/jlink").kind == "directory")
    check("stat with follow = false sees the link", fs.stat(root .. "/jlink", { follow = false }).kind == "link")
    local link = fs.link(root .. "/jlink")
    check("link reports type and target", link and link.type == "junction" and link.target:lower():gsub("/", "\\") == fs.absolute(root .. "/target"):lower():gsub("/", "\\"), link and (link.type .. " " .. tostring(link.target)))
    check("link on a plain directory is false", fs.link(root .. "/target") == false)
    check("same sees through the junction", fs.same(root .. "/jlink", root .. "/target") == true)
    check("same distinguishes different objects", fs.same(root .. "/target", root .. "/order") == false)
    local c = fs.canon(root .. "/jlink/inner/leaf.txt")
    check("canon resolves the link in the path", c and c.kind == "file" and c.path:lower() == fs.absolute(root .. "/target/inner/leaf.txt"):lower(), c and c.path)
    none, e = fs.stat(root .. "/dangling")
    check("stat of a dangling junction is FS dangling", none == nil and err.is(e, "FS", "dangling"), tostring(e))
    none, e = fs.canon(root .. "/dangling")
    check("canon of a dangling junction is FS dangling", none == nil and err.is(e, "FS", "dangling"), tostring(e))
    check("exists reports the dangling link itself", fs.exists(root .. "/dangling") == "link")

    -- the walk
    local d = fs.dirs(root .. "/target")
    local set = {}
    for _, p in ipairs(d.paths) do set[p:lower()] = true end
    local shown_target = fs.absolute(root .. "/target"):lower()
    check("dirs lists the root first with forward slashes", d.root:lower() == shown_target and d.paths[1]:lower() == shown_target, d.root)
    check("dirs counts equal the path list", d.dirs == #d.paths and d.maxdepth == 1, d.dirs .. " " .. #d.paths)
    check("junctions are listed but not entered", set[shown_target .. "/outside"] and set[shown_target .. "/loop"]
      and not set[(shown_target .. "/outside/sub"):lower()] and not set[shown_target .. "/loop/target"], table.concat(d.paths, "\n"))
    local nofollow, junction_typed = 0, 0
    for _, row in ipairs(d.links) do
      if row.action == "nofollow" then nofollow = nofollow + 1 end
      if row.type == "junction" and row.target then junction_typed = junction_typed + 1 end
    end
    check("each junction has a links row with nofollow, type, target", nofollow == 2 and junction_typed == 2, tostring(#d.links))
    check("the walk has no error rows", #d.errors == 0, tostring(d.errors[1] and d.errors[1].reason))

    local whole = fs.dirs(root)
    check("a junction root is descended and disclosed", fs.dirs(root .. "/jlink").dirs == 4)
    check("hidden directories are listed", (function() for _, p in ipairs(whole.paths) do if p:lower():match("/hidden$") then return true end end return false end)())
    check("the dangling junction is listed with a links row", (function()
      for _, row in ipairs(whole.links) do if row.path:lower():match("/dangling$") and row.action == "nofollow" then return true end end return false end)(), tostring(#whole.links))
    local depth0 = fs.dirs(root, { depth = 0 })
    check("depth 0 lists the root alone", depth0.dirs == 1 and depth0.depthlimited == 1)
    local pruned = fs.dirs(root, { prune = { "ORDER", "hid*" } })
    local function names_one(list, suffix)
      for _, p in ipairs(list) do if p:lower():match(suffix) then return true end end
      return false
    end
    check("prune matches base names case-insensitively", pruned.pruned == 2, tostring(pruned.pruned))
    -- A pruned directory is excluded by name, so it is reported in skipped and
    -- never in paths: listing it there made the obvious walk read exactly the
    -- content the prune excluded.  Changed in 0.9.0.
    check("a pruned directory is not in paths", not names_one(pruned.paths, "/order$"),
      table.concat(pruned.paths, ","))
    check("a pruned directory is reported in skipped",
      #pruned.skipped == 2 and names_one(pruned.skipped, "/order$"),
      table.concat(pruned.skipped, ","))
    check("dirs still counts exactly the paths", pruned.dirs == #pruned.paths,
      tostring(pruned.dirs) .. " vs " .. tostring(#pruned.paths))
    check("a walk with nothing pruned has an empty skipped",
      #fs.dirs(root).skipped == 0)
    -- The depth cap is a frontier the caller asked to stop at, not a name it
    -- excluded, so those directories stay in paths.
    check("a depth-limited directory stays in paths",
      depth0.dirs == 1 and #depth0.paths == 1 and #depth0.skipped == 0)
    ok, e2 = pcall(fs.dirs, root, { depth = -1 })
    check("a negative depth is refused", not ok and err.is(e2, "FS", "badvalue"), tostring(e2))
    none, e = fs.dirs(root .. "/a.bin")
    check("a file root is refused", none == nil and err.is(e, "FS", "badvalue"), tostring(e))
    none, e = fs.dirs(root .. "/nowhere")
    check("a missing root is FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))

    -- removal never follows a junction
    fs.mkdir(root .. "/victim/sub")
    fs.write(root .. "/victim/sub/f.txt", "f")
    cmd("mklink", "/J", win(root .. "/victim/link-to-target"), win(root .. "/target"))
    check("recursive remove deletes the tree", fs.remove(root .. "/victim", { recursive = true }) == true and fs.exists(root .. "/victim") == false)
    check("the junction's target survived the removal", fs.exists(root .. "/target/inner/leaf.txt") == "file")
    check("removing a junction removes the link only", fs.remove(root .. "/jlink") == true and fs.exists(root .. "/target/inner/leaf.txt") == "file")
  end

  -- remove / rename / copy ---------------------------------------------------------------
  none, e = fs.remove(root .. "/deep")
  check("removing a non-empty directory without recursive is FS notempty", none == nil and err.is(e, "FS", "notempty"), tostring(e))
  check("recursive remove of a plain tree", fs.remove(root .. "/deep", { recursive = true }) == true and fs.exists(root .. "/deep") == false)
  none, e = fs.remove(root .. "/deep")
  check("removing a missing path is FS notfound", none == nil and err.is(e, "FS", "notfound"), tostring(e))
  fs.write(root .. "/r1.txt", "one")
  check("rename moves a file", fs.rename(root .. "/r1.txt", root .. "/r2.txt") == true and fs.read(root .. "/r2.txt") == "one")
  fs.write(root .. "/r3.txt", "three")
  none, e = fs.rename(root .. "/r2.txt", root .. "/r3.txt")
  check("rename onto an existing file is refused without replace", none == nil and err.is(e, "FS", "exists"), tostring(e))
  check("rename with replace overwrites", fs.rename(root .. "/r2.txt", root .. "/r3.txt", { replace = true }) == true and fs.read(root .. "/r3.txt") == "one")
  check("copy duplicates", fs.copy(root .. "/r3.txt", root .. "/c.txt") == true and fs.read(root .. "/c.txt") == "one")
  none, e = fs.copy(root .. "/r3.txt", root .. "/c.txt")
  check("copy onto an existing file is refused without replace", none == nil and err.is(e, "FS", "exists"), tostring(e))

  -- paths ------------------------------------------------------------------------------------
  local abs = fs.absolute("test/../build/./x.txt")
  check("absolute normalises with forward slashes", abs:match("^%a:/") and abs:match("/build/x%.txt$") and not abs:find("..", 1, true), abs)
  ok, e2 = pcall(fs.absolute, "C:foo")
  check("a drive-relative path is refused by name", not ok and err.is(e2, "FS", "badvalue"), tostring(e2))
  ok, e2 = pcall(fs.absolute, root .. "/trailing./x")
  check("a component ending in a dot is refused by name", not ok and err.is(e2, "FS", "badvalue"), tostring(e2))
  ok, e2 = pcall(fs.absolute, root .. "/trailing /x")
  check("a component ending in a space is refused by name", not ok and err.is(e2, "FS", "badvalue"), tostring(e2))
  check("cwd and temp are absolute", fs.cwd():match("^%a:/") ~= nil and fs.temp():match("^%a:/") ~= nil, fs.cwd() .. " " .. fs.temp())
  check("absolute of a UNC-style path keeps two leading slashes", fs.absolute("//server/share/x") == "//server/share/x", fs.absolute("//server/share/x"))

  -- beyond 260 characters ----------------------------------------------------------------------
  -- components are capped at 255 units; the PATH limit of 260 is what \\?\ lifts
  local long = root .. "/long/" .. string.rep("abcdefghij", 20) .. "/" .. string.rep("k", 120) .. "/deeper"
  local made_long, e_long = fs.mkdir(long)
  check("a path beyond 260 characters can be created", #long > 260 and made_long == true, tostring(#long) .. " " .. tostring(e_long))
  check("a file can be written and read there", fs.write(long .. "/f.txt", "far") and fs.read(long .. "/f.txt") == "far")
  check("dirs walks past 260 characters", fs.dirs(root .. "/long").dirs == 4, tostring(fs.dirs(root .. "/long").dirs))
  check("recursive remove past 260 characters", fs.remove(root .. "/long", { recursive = true }) == true)

  -- watch ------------------------------------------------------------------------------------
  -- A read returns the first batch the OS delivered, so a sequence of changes
  -- arrives over several reads; collect until the expected path shows up.
  local function collect(w, wanted, seconds)
    local seen, all = {}, {}
    local deadline = sched.clock() + (seconds or 5)
    while sched.clock() < deadline do
      local events = w:read("200ms")
      for _, ev in ipairs(events or {}) do
        seen[ev.path] = ev
        all[#all + 1] = ev
      end
      if wanted ~= nil and seen[wanted] then break end
    end
    return seen, all
  end
  fs.mkdir(root .. "/watched/sub")
  do
    local w <close> = fs.watch(root .. "/watched")
    local info = w:info()
    check("watch is armed on return", info.armed == true and info.pending == 0 and info.dropped == 0 and info.recursive == true)
    none, e = w:read("100ms")
    check("read with a timeout and no changes is FS timeout", none == nil and err.is(e, "FS", "timeout"), tostring(e))
    fs.write(root .. "/watched/sub/new.txt", "hello", { atomic = false })
    local seen = collect(w, "sub/new.txt")
    check("a new file arrives as added with a relative forward-slash path", seen["sub/new.txt"] and seen["sub/new.txt"].action == "added", tostring(seen["sub/new.txt"] and seen["sub/new.txt"].action))
    fs.rename(root .. "/watched/sub/new.txt", root .. "/watched/sub/moved.txt")
    seen = collect(w, "sub/moved.txt")
    local renamed = seen["sub/moved.txt"]
    check("a rename pairs into one event with from", renamed and renamed.action == "renamed" and renamed.from == "sub/new.txt", tostring(renamed and (renamed.action .. " from " .. tostring(renamed.from))))
    fs.remove(root .. "/watched/sub/moved.txt")
    seen = collect(w, "sub/moved.txt")
    check("a removal arrives as removed", seen["sub/moved.txt"] and seen["sub/moved.txt"].action == "removed")
    fs.write(root .. "/watched/sub/atomic.txt", "x")
    seen = collect(w, "sub/atomic.txt")
    check("an atomic write appears as a rename from its temporary file",
      seen["sub/atomic.txt"] and seen["sub/atomic.txt"].action == "renamed" and contains(tostring(seen["sub/atomic.txt"].from), ".kuu-"),
      tostring(seen["sub/atomic.txt"] and seen["sub/atomic.txt"].from))
  end
  local raw <close> = fs.watch(root .. "/watched", { raw = true, recursive = false })
  fs.write(root .. "/watched/top.txt", "a", { atomic = false })
  fs.write(root .. "/watched/top.txt", "bb", { atomic = false })
  local _, raw_all = collect(raw, nil, 1)
  check("raw mode returns every OS event uncoalesced", #raw_all >= 2, tostring(#raw_all))
  raw:close()
  ok, e2 = pcall(raw.read, raw, "10ms")
  check("a closed watch refuses reads", not ok and err.is(e2, "FS", "closed"), tostring(e2))
  none, e = fs.watch(root .. "/nowhere")
  check("watching a missing directory fails by name", none == nil and err.is(e, "FS", "notfound"), tostring(e))

  -- a reader parked on a watch that is closed elsewhere wakes with FS closed
  local w2 = fs.watch(root .. "/watched")
  local reader = sched.spawn(function() return w2:read("5s") end)
  sched.sleep("50ms")
  w2:close()
  local r1, r2 = reader:join()
  check("a parked reader wakes when the watch is closed", r1 == nil and err.is(r2, "FS", "closed"), tostring(r2))
end
