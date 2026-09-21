-- Attribute API integration: Windows creates and independently inspects fixtures.
-- A bounded helper owns ACL changes and restores every descriptor before exit.
global none
global <const> require, assert, ipairs, pairs, tostring, type, pcall, setmetatable, error, io, string

return function(T)
  local fs, proc, json, err = require "fs", require "proc", require "json", require "err"
  local check = T.check
  check("attribute APIs are exported", type(fs.attributes) == "function" and type(fs.set_attributes) == "function")
  if type(fs.attributes) ~= "function" or type(fs.set_attributes) ~= "function" then return end
  local helper = fs.absolute(T.root .. "/build/test/attributes_fixture.exe")
  check("independent attribute fixture exists", fs.exists(helper) == "file", helper)
  if fs.exists(helper) ~= "file" then return end
  local root = fs.absolute(T.work .. "/attributes-" .. require("hash").uuid())
  local function native(command, ...)
    local args = { helper, command, root, ... }
    args.timeout = "10s"
    local result, why = proc.run(args)
    assert(result and result.code == 0, result and T.describe(result) or tostring(why))
    return assert(json.decode(result.out))
  end
  local setup = native("setup")
  check("native fixture setup succeeds", setup.ready == true)
  local function path(relative) return root .. "/" .. relative end
  local function inspect(relative, follow) return native("inspect", relative, follow and "follow" or "nofollow") end
  local function reset(relative, mask) return native("set", relative, tostring(mask)) end
  local flags = {
    { "readonly", 1 }, { "hidden", 2 }, { "system", 4 }, { "archive", 32 },
    { "temporary", 256 }, { "not_content_indexed", 8192 },
  }
  local function shape(got, mask)
    if type(got) ~= "table" or got.attrs ~= mask then return false end
    local count = 0
    for _ in pairs(got) do count = count + 1 end
    if count ~= 7 then return false end
    for _, flag in ipairs(flags) do
      if got[flag[1]] ~= ((mask & flag[2]) ~= 0) then return false end
    end
    return true
  end
  local function environmental(label, code, fn)
    local called, value, why = pcall(fn)
    check(label, called and value == nil and err.is(why, "FS", code), tostring(called and why or value))
  end
  local function raised(label, code, fn)
    local called, why = pcall(fn)
    check(label, not called and (code and err.is(why, "FS", code) or not code and type(why) == "string"), tostring(why))
  end

  for _, flag in ipairs(flags) do
    local name, bit = flag[1], flag[2]
    reset("plain.bin", bit)
    local got = fs.attributes(path("plain.bin"))
    check("getter decodes independently set " .. name, shape(got, bit))
    check("setter clears " .. name .. " and normalizes final bit", fs.set_attributes(path("plain.bin"), { [name] = false }) == true
      and inspect("plain.bin").attrs == 128)
    local baseline = name == "hidden" and 4 or 2
    reset("plain.bin", baseline)
    check("setter patches " .. name .. " while preserving another bit", fs.set_attributes(path("plain.bin"), { [name] = true }) == true
      and inspect("plain.bin").attrs == (baseline | bit))
    if name ~= "temporary" then
      reset("directory", 16 | bit)
      check("getter decodes directory " .. name, shape(fs.attributes(path("directory")), 16 | bit))
      check("setter clears directory " .. name .. " and preserves DIRECTORY", fs.set_attributes(path("directory"), { [name] = false }) == true
        and inspect("directory").attrs == 16)
    end
  end
  local all, none = {}, {}
  for _, flag in ipairs(flags) do all[flag[1]], none[flag[1]] = true, false end
  check("all six file flags can be enabled together", fs.set_attributes(path("plain.bin"), all) == true
    and inspect("plain.bin").attrs == 8487)
  check("clearing every mutable file flag yields NORMAL", fs.set_attributes(path("plain.bin"), none) == true
    and inspect("plain.bin").attrs == 128)
  local detached = assert(fs.attributes(path("plain.bin")))
  detached.attrs, detached.hidden = 2, true
  check("getter result is a detached snapshot", inspect("plain.bin").attrs == 128)
  reset("directory", 16 | 2)
  environmental("mixed directory patch rejects TEMPORARY before clearing hidden", "badvalue", function()
    return fs.set_attributes(path("directory"), { hidden = false, temporary = true })
  end)
  check("rejected directory patch leaves all bits unchanged", inspect("directory").attrs == (16 | 2))
  check("temporary=false is valid on a directory", fs.set_attributes(path("directory"), { temporary = false }) == true
    and inspect("directory").attrs == (16 | 2))
  local sparse_before = inspect("sparse.bin").attrs
  check("independent fixture actually carries SPARSE", (sparse_before & 512) ~= 0)
  check("getter preserves raw bits outside named flags", shape(fs.attributes(path("sparse.bin")), sparse_before))
  check("patch preserves independently established SPARSE", fs.set_attributes(path("sparse.bin"), { hidden = true }) == true
    and inspect("sparse.bin").attrs == (sparse_before | 2))
  check("clearing mutable flags keeps SPARSE", fs.set_attributes(path("sparse.bin"), none) == true
    and inspect("sparse.bin").attrs == 512)
  check("getter separates unnamed raw bits from false named flags", shape(fs.attributes(path("sparse.bin")), 512))

  local before = inspect("times.bin")
  check("attribute write succeeds with fixed native timestamps", fs.set_attributes(path("times.bin"), { hidden = true }) == true)
  local after = inspect("times.bin")
  check("attribute write preserves independently observed creation access write times",
    before.creation == after.creation and before.access == after.access and before.write == after.write)
  local unchanged = after
  check("empty patch validates without changing native metadata times", fs.set_attributes(path("times.bin"), {}) == true
    and inspect("times.bin").change == unchanged.change)
  check("already satisfied patch skips native write", fs.set_attributes(path("times.bin"), { hidden = true }) == true
    and inspect("times.bin").change == unchanged.change)
  check("attribute updates preserve independently created bytes", fs.read(path("times.bin")) == "independent fixture\r\n\0binary\255")
  local long_relative = string.rep("long-component-abcdefghijklmnopqrstuvwxyz-0123456789/", 5) .. "long.bin"
  for _, relative in ipairs { "unicode-κου-雪.bin", long_relative } do
    check("getter handles " .. relative, shape(fs.attributes(path(relative)), 32))
    check("setter handles " .. relative, fs.set_attributes(path(relative), { hidden = true }) == true
      and inspect(relative).attrs == 34)
  end
  check("long fixture really exceeds MAX_PATH", #path(long_relative) > 260)

  for _, case in ipairs {
    { "numeric getter path", function() return fs.attributes(4) end },
    { "boolean getter path", function() return fs.attributes(false) end },
    { "missing getter path", function() return fs.attributes() end },
    { "numeric setter path", function() return fs.set_attributes(4, {}) end },
    { "missing patch", function() return fs.set_attributes(path("plain.bin")) end },
    { "nil patch", function() return fs.set_attributes(path("plain.bin"), nil) end },
    { "boolean patch", function() return fs.set_attributes(path("plain.bin"), false) end },
    { "numeric patch", function() return fs.set_attributes(path("plain.bin"), 4) end },
    { "getter options type", function() return fs.attributes(path("plain.bin"), false) end },
    { "setter options type", function() return fs.set_attributes(path("plain.bin"), {}, "x") end },
  } do raised(case[1] .. " is an argument error", nil, case[2]) end
  for _, case in ipairs {
    { "raw attrs mutation", { attrs = 0 } }, { "unknown flag", { compressed = true } },
    { "normal mutation", { normal = true } }, { "numeric patch key", { [1] = true } },
    { "NUL patch key", { ["hidden\0suffix"] = true } },
  } do raised(case[1] .. " is FS usage", "usage", function() return fs.set_attributes(path("plain.bin"), case[2]) end) end
  for _, options in ipairs { { unexpected = true }, { [1] = true }, { ["follow\0suffix"] = true } } do
    raised("getter rejects unknown or non-exact option keys", "usage", function() return fs.attributes(path("plain.bin"), options) end)
    raised("setter rejects unknown or non-exact option keys", "usage", function() return fs.set_attributes(path("plain.bin"), {}, options) end)
  end
  for _, value in ipairs { 0, 1, "false", {} } do
    raised("getter follow is strictly boolean", "badvalue", function() return fs.attributes(path("plain.bin"), { follow = value }) end)
    raised("setter follow is strictly boolean", "badvalue", function() return fs.set_attributes(path("plain.bin"), {}, { follow = value }) end)
    for _, flag in ipairs(flags) do
      raised("patch " .. flag[1] .. " is strictly boolean", "badvalue", function()
        return fs.set_attributes(path("plain.bin"), { [flag[1]] = value })
      end)
    end
  end
  for _, bad in ipairs { "", path("plain.bin") .. "\0bad", "C:relative", path("bad.") } do
    raised("getter refuses malformed path", "badvalue", function() return fs.attributes(bad) end)
    raised("setter refuses malformed path", "badvalue", function() return fs.set_attributes(bad, {}) end)
  end
  raised("getter preserves invalid UTF-8 encoding error", "encoding", function() return fs.attributes(path("bad-\255")) end)
  raised("setter preserves invalid UTF-8 encoding error", "encoding", function() return fs.set_attributes(path("bad-\255"), {}) end)
  local callbacks = 0
  local function forbidden() callbacks = callbacks + 1; error("attribute parser consulted metatable") end
  local inherited_options = setmetatable({}, { __index = { follow = true }, __pairs = forbidden })
  local inherited_patch = setmetatable({}, { __index = { hidden = true }, __pairs = forbidden })
  check("inherited patch flags are absent", fs.set_attributes(path("plain.bin"), inherited_patch) == true
    and inspect("plain.bin").attrs == 128)
  local raw_options = setmetatable({}, { __index = forbidden, __pairs = forbidden })
  local raw_patch = setmetatable({ hidden = true }, { __index = forbidden, __pairs = forbidden })
  check("parsers read raw fields without metatable callbacks", fs.set_attributes(path("plain.bin"), raw_patch, raw_options) == true
    and shape(fs.attributes(path("plain.bin"), raw_options), 2) and callbacks == 0)
  check("nil options are accepted", shape(fs.attributes(path("plain.bin"), nil), 2)
    and fs.set_attributes(path("plain.bin"), {}, nil) == true)
  check("nil fields count as omitted", fs.set_attributes(path("plain.bin"), { hidden = nil }, { follow = nil }) == true
    and inspect("plain.bin").attrs == 2)
  raised("invalid mixed patch raises before any mutation", "badvalue", function()
    return fs.set_attributes(path("plain.bin"), { hidden = false, archive = 1 })
  end)
  check("invalid mixed patch left bytes and flags alone", inspect("plain.bin").attrs == 2
    and fs.read(path("plain.bin")) == "independent fixture\r\n\0binary\255")
  environmental("getter reports missing object", "notfound", function() return fs.attributes(path("missing.bin")) end)
  environmental("followed missing ordinary path remains notfound", "notfound", function()
    return fs.attributes(path("missing.bin"), { follow = true })
  end)
  environmental("followed setter does not invent a dangling link", "notfound", function()
    return fs.set_attributes(path("missing.bin"), { hidden = true }, { follow = true })
  end)
  environmental("empty setter reports missing object", "notfound", function() return fs.set_attributes(path("missing.bin"), {}) end)
  environmental("nonempty setter does not create missing object", "notfound", function() return fs.set_attributes(path("missing.bin"), { hidden = true }) end)
  environmental("getter reports missing ancestor", "notfound", function() return fs.attributes(path("missing-parent/file")) end)
  check("failed setter did not create anything", fs.exists(path("missing.bin")) == false)

  local function links(relative, target, directory)
    local own_before, target_before = inspect(relative), inspect(target)
    check(relative .. " getter defaults to final link", shape(fs.attributes(path(relative)), own_before.attrs)
      and (own_before.attrs & 1024) ~= 0)
    check(relative .. " inherited follow is ignored", shape(fs.attributes(path(relative), inherited_options), own_before.attrs))
    check(relative .. " default setter changes link only", fs.set_attributes(path(relative), { hidden = true }) == true
      and inspect(relative).selected == (own_before.selected | 2) and inspect(target).attrs == target_before.attrs)
    local selected = inspect(relative).selected
    check(relative .. " explicit following reads target", shape(fs.attributes(path(relative), { follow = true }), target_before.attrs))
    check(relative .. " explicit following changes target only", fs.set_attributes(path(relative), { system = true }, { follow = true }) == true
      and inspect(target).attrs == (target_before.attrs | 4) and inspect(relative).selected == selected)
    if directory then
      environmental(relative .. " nofollow directory TEMPORARY rejects whole patch", "badvalue", function()
        return fs.set_attributes(path(relative), { hidden = false, temporary = true })
      end)
      check(relative .. " rejected patch leaves link and target unchanged", inspect(relative).selected == selected
        and inspect(target).attrs == (target_before.attrs | 4))
    end
  end
  links("junction", "target", true)
  check("nofollow final component traverses linked ancestor", fs.set_attributes(path("junction/child.bin"), { hidden = true }) == true
    and inspect("target/child.bin").attrs == 34)
  local function dangling(relative)
    local own = inspect(relative)
    check(relative .. " nofollow getter sees existing broken link", shape(fs.attributes(path(relative)), own.attrs))
    check(relative .. " nofollow setter changes existing broken link", fs.set_attributes(path(relative), { hidden = true }) == true
      and inspect(relative).selected == (own.selected | 2))
    environmental(relative .. " followed getter is dangling", "dangling", function() return fs.attributes(path(relative), { follow = true }) end)
    environmental(relative .. " followed setter is dangling", "dangling", function() return fs.set_attributes(path(relative), { archive = true }, { follow = true }) end)
  end
  dangling("dangling-junction")
  for _, case in ipairs {
    { "file-link", "link-target.bin", false, setup.file_symlink },
    { "directory-link", "target", true, setup.directory_symlink },
    { "dangling-link", nil, false, setup.dangling_symlink },
  } do
    if case[4] == 0 then
      if case[2] then links(case[1], case[2], case[3]) else dangling(case[1]) end
    elseif case[4] == 1314 then
      io.write("skip ", case[1], ": native symbolic-link creation denied (Windows 1314)\n")
    else check(case[1] .. " fixture creation", false, "Windows " .. tostring(case[4])) end
  end

  do
    local holder = assert(proc.start { helper, "acl", root, stream = true, timeout = "65s" })
    local active = true
    local function release()
      if not active then return end
      assert(fs.write(path(".release"), "release", { atomic = false }))
      local result = assert(holder:wait("5s"))
      active = false
      assert(result.code == 0, "native ACL restoration failed: " .. tostring(result.code))
    end
    local guard <close> = setmetatable({}, { __close = release })
    local ready = assert(json.decode(assert(holder:read("line", "5s"))))
    assert(ready.ready, "native ACL setup failed: " .. tostring(ready.win32))
    check("ACL fixture holds expected attribute restrictions", ready.ready == true)
    check("getter needs no data-read permission", fs.attributes(path("write-denied.bin")) ~= nil)
    environmental("ACL fixture actually denies file-data reading", "access", function() return fs.read(path("write-denied.bin")) end)
    check("empty patch succeeds without write-attributes permission", fs.set_attributes(path("write-denied.bin"), {}) == true)
    environmental("nonempty patch requires write-attributes permission", "access", function()
      return fs.set_attributes(path("write-denied.bin"), { hidden = true })
    end)
    environmental("already-satisfied nonempty patch still requires write-attributes permission", "access", function()
      return fs.set_attributes(path("write-denied.bin"), { archive = true })
    end)
    environmental("getter reports real read-attributes denial", "access", function() return fs.attributes(path("private/child.bin")) end)
    environmental("empty setter reports read-attributes denial", "access", function() return fs.set_attributes(path("private/child.bin"), {}) end)
    check("nofollow link access remains available while target denies writing", fs.set_attributes(path("junction"), { archive = true }) == true)
    environmental("followed target access denied is never dangling", "access", function()
      return fs.set_attributes(path("junction"), { archive = true }, { follow = true })
    end)
    check("followed empty patch needs only target read attributes", fs.set_attributes(path("junction"), {}, { follow = true }) == true)
    release()
    check("native ACL descriptors restored before fixture exit", fs.attributes(path("private/child.bin")) ~= nil
      and fs.set_attributes(path("write-denied.bin"), { hidden = true }) == true)
  end
end
