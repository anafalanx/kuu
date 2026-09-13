-- archive.lua -- pack, list, and unpack through Windows' tar.exe: zip and the
-- tar family, strip, replacement, and the refusals.
global none
global <const> require, ipairs, pairs, tostring, string, table, pcall

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local err = require "err"
  do
    -- An option the call does not read is refused, before the archive is looked for.
    local a = require "archive"
    for _, call in ipairs({ { "list", a.list, "nothing.zip" }, { "unpack", a.unpack, "nothing.zip", "nowhere" }, { "pack", a.pack, "nothing.zip", "nowhere", nil } }) do
      local ok, raised
      if call[1] == "pack" then ok, raised = pcall(call[2], call[3], call[4], call[5], { timeoutt = "1s" })
      elseif call[1] == "unpack" then ok, raised = pcall(call[2], call[3], call[4], { timeoutt = "1s" })
      else ok, raised = pcall(call[2], call[3], { timeoutt = "1s" }) end
      check(call[1] .. " refuses an unknown option as ARCHIVE usage", not ok and err.is(raised, "ARCHIVE", "usage") and contains(tostring(raised), "timeoutt"), tostring(raised))
    end
  end
  local archive = require "archive"

  local work = fs.absolute(T.work .. "/archive")
  fs.remove(work, { recursive = true })
  fs.mkdir(work .. "/src/tool-1.0/sub")
  fs.write(work .. "/src/tool-1.0/a.txt", "alpha\n")
  fs.write(work .. "/src/tool-1.0/sub/b.txt", "beta\n")
  fs.write(work .. "/src/loose.txt", "loose\n")

  local ok, e = archive.pack(work .. "/out/tool.zip", work .. "/src", { "tool-1.0" })
  check("pack writes a zip of the named entries, creating the parent", ok == true and fs.exists(work .. "/out/tool.zip") == "file", tostring(e))
  do
    local target = work .. "/out/tool.zip"
    local previous = fs.read(target)
    local accepted, failure = pcall(archive.pack, target, work .. "/src", { "tool-1.0" }, { timeout = "nonsense" })
    check("invalid pack options preserve the existing archive", not accepted and err.is(failure, "PROC", "badvalue")
      and fs.read(target) == previous, tostring(failure))
    local packed, problem = archive.pack(target, work .. "/src", { "missing-entry" })
    check("a failed tar invocation preserves the existing archive", packed == nil and err.is(problem, "ARCHIVE", "failed")
      and fs.read(target) == previous, tostring(problem))
    packed, problem = archive.pack(target, work .. "/src", { "tool-1.0" }, { timeout = "0ms" })
    check("a timed out pack preserves the existing archive", packed == nil and err.is(problem, "ARCHIVE", "timeout")
      and fs.read(target) == previous, tostring(problem))
    check("failed packing removes its temporary archive", #fs.glob(work .. "/out/.kuu-*") == 0)
    fs.write(work .. "/src/replacement.txt", "replacement")
    packed, problem = archive.pack(target, work .. "/src", { "replacement.txt" })
    local replaced = packed and archive.list(target)
    check("successful packing promotes the complete replacement", replaced and #replaced == 1
      and replaced[1] == "replacement.txt", tostring(problem))
    archive.pack(target, work .. "/src", { "tool-1.0" })
  end
  do
    -- Keeping the old archive intact also keeps it visible to traversal.
    -- Exclude that exact output and the temporary, including through an
    -- ancestor entry, without hiding unrelated files with the same name.
    local dir = work .. "/self"
    fs.mkdir(dir .. "/sub/out[1]")
    fs.mkdir(dir .. "/out[1]")
    fs.mkdir(dir .. "/out1")
    fs.write(dir .. "/source.txt", "source")
    fs.write(dir .. "/out1/archive$.zip", "unrelated glob lookalike")
    fs.write(dir .. "/sub/out[1]/archive$.zip", "unrelated same suffix")
    local target = dir .. "/out[1]/archive$.zip"
    local function listed()
      local paths = archive.list(target)
      local names = {}
      for _, path in ipairs(paths or {}) do names[path:gsub("^%./", "")] = true end
      for path in pairs(names) do
        if path:find(".kuu-", 1, true) then return nil end
      end
      return names
    end
    local first, first_error = archive.pack(target, dir)
    local second, second_error = archive.pack(target, dir, { "." })
    local names = second and listed()
    check("packing beneath the input tree excludes both archives and preserves unrelated matching names",
      first and names and names["source.txt"] and names["out1/archive$.zip"]
        and names["sub/out[1]/archive$.zip"] and not names["out[1]/archive$.zip"],
      tostring(first_error or second_error))
    fs.write(dir .. "/out[1]/source.txt", "nested source")
    local nested, nested_error = archive.pack(target, dir, { "out[1]" })
    names = nested and listed()
    check("an explicit ancestor still excludes its previous output and temporary",
      names and names["out[1]/source.txt"] and not names["out[1]/archive$.zip"], tostring(nested_error))
    local long_target = work .. "/out/" .. string.rep("a", 234) .. ".zip"
    local long, long_error = archive.pack(long_target, work .. "/src", { "tool-1.0" })
    check("a valid long output basename fits because only its format suffix is copied to the temporary",
      long and fs.exists(long_target) == "file", tostring(long_error))
  end
  local entries = archive.list(work .. "/out/tool.zip")
  check("list shows the entries", entries and #entries >= 3 and table.concat(entries, " "):find("tool-1.0/sub/b.txt", 1, true) ~= nil, entries and table.concat(entries, " "))
  ok, e = archive.unpack(work .. "/out/tool.zip", work .. "/one")
  check("unpack recreates the tree", ok == true and fs.read(work .. "/one/tool-1.0/sub/b.txt") == "beta\n", tostring(e))
  ok, e = archive.unpack(work .. "/out/tool.zip", work .. "/two", { strip = 1 })
  check("strip drops leading components", ok == true and fs.read(work .. "/two/a.txt") == "alpha\n" and fs.read(work .. "/two/sub/b.txt") == "beta\n", tostring(e))
  fs.write(work .. "/two/a.txt", "stale")
  ok, e = archive.unpack(work .. "/out/tool.zip", work .. "/two", { strip = 1 })
  check("unpacking again overwrites", ok == true and fs.read(work .. "/two/a.txt") == "alpha\n", tostring(e))

  for _, ext in ipairs { "tar.gz", "tgz", "tar.xz", "tar.zst", "tar" } do
    local file = work .. "/out/all." .. ext
    ok, e = archive.pack(file, work .. "/src")
    local listed = ok and archive.list(file) or nil
    ok, e = ok and archive.unpack(file, work .. "/from-" .. ext) or ok, e
    check("the " .. ext .. " format round-trips a whole directory", ok == true and listed and #listed >= 4
      and fs.read(work .. "/from-" .. ext .. "/loose.txt") == "loose\n" and fs.read(work .. "/from-" .. ext .. "/tool-1.0/a.txt") == "alpha\n", tostring(e))
  end

  fs.write(work .. "/src/--help", "an entry, not an option\n")
  ok, e = archive.pack(work .. "/out/dash.zip", work .. "/src", { "--help" })
  local dash = ok and archive.list(work .. "/out/dash.zip") or nil
  check("an entry named like an option is packed as an entry", ok == true and dash and dash[1] == "--help", tostring(e))
  ok, e = archive.unpack(work .. "/out/dash.zip", work .. "/dash")
  check("and unpacks", ok == true and fs.read(work .. "/dash/--help") == "an entry, not an option\n", tostring(e))

  do
    local source = work .. "/at-src"
    fs.mkdir(source .. "/@folder")
    fs.write(source .. "/@notes.txt", "literal file")
    fs.write(source .. "/@folder/inside.txt", "literal folder")
    for _, ext in ipairs { "zip", "tar" } do
      for _, mode in ipairs { "explicit", "all" } do
        local target = work .. "/out/at-" .. mode .. "." .. ext
        local unpacked = work .. "/at-" .. mode .. "-" .. ext
        local packed, pe = archive.pack(target, source, mode == "explicit" and { "@notes.txt", "@folder" } or nil)
        local extracted, ue = packed and archive.unpack(target, unpacked)
        local names = packed and archive.list(target)
        local listed = {}
        for _, name in ipairs(names or {}) do listed[name:gsub("^%./", "")] = true end
        check("@ names are literal files and folders in " .. mode .. " " .. ext .. " packing",
          extracted and listed["@notes.txt"] and listed["@folder/inside.txt"]
          and fs.read(unpacked .. "/@notes.txt") == "literal file"
          and fs.read(unpacked .. "/@folder/inside.txt") == "literal folder", tostring(pe or ue))
      end
    end
    local target = source .. "/@out.zip"
    archive.pack(target, source)
    local packed, pe = archive.pack(target, source)
    local clean = packed
    for _, name in ipairs(packed and archive.list(target) or {}) do
      if name:gsub("^%./", "") == "@out.zip" or name:find(".kuu-", 1, true) then clean = false end
    end
    check("literal @ operands still exclude the old destination and its temporary", clean, tostring(pe))
  end

  do
    local target = work .. "/out/tool.zip"
    local previous = fs.read(target)
    for _, entries in ipairs {
      { [1] = "loose.txt", [3] = "replacement.txt" }, { "loose.txt", extra = "replacement.txt" },
      { [0] = "loose.txt" }, { [1.5] = "loose.txt" }, false, "loose.txt",
    } do
      local accepted, failure = pcall(archive.pack, target, work .. "/src", entries)
      check("a malformed archive entry list is refused without replacing its destination",
        not accepted and err.is(failure, "ARCHIVE", "badvalue") and fs.read(target) == previous, tostring(failure))
    end
    local parent = work .. "/not-staged"
    local accepted, failure = pcall(archive.pack, parent .. "/out.zip", work .. "/src", { [1] = "loose.txt", [3] = "replacement.txt" })
    check("entry-list validation happens before creating the destination directory",
      not accepted and err.is(failure, "ARCHIVE", "badvalue") and not fs.exists(parent), tostring(failure))
  end

  local none
  none, e = archive.unpack(work .. "/out/absent.zip", work .. "/three")
  check("unpacking a missing archive is ARCHIVE notfound", none == nil and err.is(e, "ARCHIVE", "notfound"), tostring(e))
  fs.write(work .. "/out/not-an-archive.zip", "this is text")
  none, e = archive.unpack(work .. "/out/not-an-archive.zip", work .. "/three")
  check("unpacking a file that is not an archive is ARCHIVE failed with tar's words", none == nil and err.is(e, "ARCHIVE", "failed") and #e.message > 0, tostring(e))
  none, e = archive.list(work .. "/out/not-an-archive.zip")
  check("listing it fails the same way", none == nil and err.is(e, "ARCHIVE", "failed"), tostring(e))
  none, e = archive.pack(work .. "/out/empty.zip", work .. "/nowhere")
  check("packing a missing directory is ARCHIVE notfound", none == nil and err.is(e, "ARCHIVE", "notfound"), tostring(e))
  fs.mkdir(work .. "/empty")
  none, e = archive.pack(work .. "/out/empty.zip", work .. "/empty")
  check("packing an empty directory is refused", none == nil and err.is(e, "ARCHIVE", "badvalue"), tostring(e))
  local raised
  ok, raised = pcall(archive.pack, work .. "/out/x.zip", work .. "/src", { "../escape" })
  check("entries that leave the directory are refused", not ok and err.is(raised, "ARCHIVE", "badvalue"), tostring(raised))
  ok, raised = pcall(archive.unpack, work .. "/out/tool.zip", work .. "/four", { strip = -1 })
  check("a negative strip is refused", not ok and err.is(raised, "ARCHIVE", "badvalue"), tostring(raised))
  ok, raised = pcall(archive.unpack, 5, work .. "/four")
  check("wrong argument types raise", not ok and err.is(raised, "ARCHIVE", "badvalue"), tostring(raised))
  do
    -- An independent, stored ZIP fixture: empty files need CRC32=0. UTF-8 is
    -- declared in bit 11; the central directory and local headers agree.
    local function zip(names)
      local local_records, central, offset = {}, {}, 0
      for _,name in ipairs(names) do
        local head = string.pack("<I4I2I2I2I2I2I4I4I4I2I2", 0x04034b50,20,0x800,0,0,0,0,0,0,#name,0) .. name
        local_records[#local_records+1] = head
        central[#central+1] = string.pack("<I4I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4", 0x02014b50,20,20,0x800,0,0,0,0,0,0,#name,0,0,0,0,0,offset) .. name
        offset = offset + #head
      end
      local directory = table.concat(central)
      return table.concat(local_records) .. directory .. string.pack("<I4I2I2I2I2I4I4I2", 0x06054b50,0,0,#names,#names,#directory,offset,0)
    end
    local names = {"Þfoo.txt", "café.txt", "漢字.txt", "😀.txt", "Ã©.txt", "line\nbreak.txt", "folder/"}
    local file = work .. "/out/Unicode 漢字.zip"
    fs.write(file, zip(names))
    local got, problem = archive.list(file)
    check("archive.list preserves every Unicode name and embedded newline",
      got and table.concat(got, "|") == table.concat(names, "|"), tostring(problem))
    local json = require "json"
    local encoded = got and json.encode(got)
    check("archive names compose with JSON without an encoding fallback", encoded and #json.decode(encoded) == #names)
    fs.write(work .. "/out/empty.zip", zip({}))
    local empty = archive.list(work .. "/out/empty.zip")
    check("an empty archive returns an empty list", empty and #empty == 0)
    local timed, te = archive.list(file, {timeout="0ms"})
    check("archive listing retains its supervised timeout", timed == nil and err.is(te, "ARCHIVE", "timeout"), tostring(te))
    fs.mkdir(work .. "/unicode-src")
    fs.write(work .. "/unicode-src/漢字.txt", "unicode")
    for _,ext in ipairs {"zip", "tar.gz", "tar.xz", "tar.zst"} do
      local output = work .. "/out/unicode." .. ext
      local packed, pe = archive.pack(output, work .. "/unicode-src")
      local listed, le = archive.list(output)
      local unpacked, ue = archive.unpack(output, work .. "/unicode-" .. ext)
      check("Unicode listing and extraction agree for " .. ext,
        packed and listed and listed[1] == "漢字.txt" and unpacked
        and fs.read(work .. "/unicode-" .. ext .. "/漢字.txt") == "unicode", tostring(pe or le or ue))
    end
  end

end
