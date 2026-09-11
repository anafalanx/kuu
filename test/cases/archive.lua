-- archive.lua -- pack, list, and unpack through Windows' tar.exe: zip and the
-- tar family, strip, replacement, and the refusals.
global none
global <const> require, ipairs, tostring, string, table, pcall

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local err = require "err"
  local archive = require "archive"

  local work = fs.absolute(T.work .. "/archive")
  fs.remove(work, { recursive = true })
  fs.mkdir(work .. "/src/tool-1.0/sub")
  fs.write(work .. "/src/tool-1.0/a.txt", "alpha\n")
  fs.write(work .. "/src/tool-1.0/sub/b.txt", "beta\n")
  fs.write(work .. "/src/loose.txt", "loose\n")

  local ok, e = archive.pack(work .. "/out/tool.zip", work .. "/src", { "tool-1.0" })
  check("pack writes a zip of the named entries, creating the parent", ok == true and fs.exists(work .. "/out/tool.zip") == "file", tostring(e))
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
