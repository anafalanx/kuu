-- reg.lua -- the registry, typed, under a key of our own in HKCU.
global none
global <const> require, ipairs, tostring, tonumber, type, string, pcall,
               select, table, pairs

return function(T)
  local check = T.check
  local reg = require "reg"
  local err = require "err"
  local sys = require "sys"
  local hash = require "hash"

  local base = "HKCU\\Software\\kuu-test-suite\\" .. hash.uuid()
  check("a fresh key does not exist", reg.exists(base) == false)
  check("create makes the key path", reg.create(base .. "/sub") == true and reg.exists(base) and reg.exists(base .. "\\sub"))
  check("set stores strings, integers, and lists with their natural types",
    reg.set(base, "s", "text") and reg.set(base, "d", 42) and reg.set(base, "q", 1 << 40) and reg.set(base, "m", { "a", "b" }))
  local v, t = reg.get(base, "s")
  check("get returns a string as string", v == "text" and t == "string")
  v, t = reg.get(base, "d")
  check("a small integer is a dword", v == 42 and t == "dword")
  v, t = reg.get(base, "q")
  check("a large integer is a qword", v == 1 << 40 and t == "qword")
  v, t = reg.get(base, "m")
  check("a list is a multistring", type(v) == "table" and #v == 2 and v[2] == "b" and t == "multistring")
  check("explicit types: expandstring, binary, qword, dword",
    reg.set(base, "e", "%SystemRoot%\\x", "expandstring") and reg.set(base, "b", "\0\1\255", "binary")
    and reg.set(base, "q2", 7, "qword") and reg.set(base, "d2", 4294967295, "dword"))
  v, t = reg.get(base, "e")
  check("an expandstring comes back unexpanded with its type", v == "%SystemRoot%\\x" and t == "expandstring")
  v, t = reg.get(base, "b")
  check("binary is bytes", v == "\0\1\255" and t == "binary")
  v, t = reg.get(base, "q2")
  check("a small qword stays a qword", v == 7 and t == "qword")
  v, t = reg.get(base, "d2")
  check("the largest dword", v == 4294967295 and t == "dword")
  check("the default value is name nil or empty", reg.set(base, nil, "dflt") and reg.get(base, "") == "dflt" and reg.get(base, nil) == "dflt")
  check("unicode names and values survive", reg.set(base, "naïve", "café") and reg.get(base, "naïve") == "café")
  local values = reg.values(base)
  local names = {}
  for i, entry in ipairs(values) do names[i] = entry.name end
  check("values lists every value sorted by name with type and value",
    #values == 10 and names[1] == "" and names[2] == "b" and names[#names] == "s" and values[3].type == "dword" and values[3].value == 42,
    table.concat(names, ","))
  local keys = reg.keys(base)
  check("keys lists the subkeys", #keys == 1 and keys[1] == "sub", tostring(#keys))
  check("delete removes one value", reg.delete(base, "s") == true and reg.get(base, "s") == nil)
  local none, e = reg.get(base, "s")
  check("a missing value is nil, REG notfound", none == nil and err.is(e, "REG", "notfound"), tostring(e))
  none, e = reg.get("HKCU\\Software\\kuu-no-such-key-" .. hash.uuid(), "x")
  check("a missing key is nil, REG notfound", none == nil and err.is(e, "REG", "notfound"), tostring(e))
  none, e = reg.delete(base, "s")
  check("deleting a missing value is nil, REG notfound", none == nil and err.is(e, "REG", "notfound"))
  check("a negative integer is a qword, not an error", reg.set(base, "neg", -1) and reg.get(base, "neg") == -1 and select(2, reg.get(base, "neg")) == "qword")
  local okb, eb = pcall(reg.set, base, "x", 1.5)
  check("a float is REG badvalue", not okb and err.is(eb, "REG", "badvalue"), tostring(eb))
  okb, eb = pcall(reg.get, "HKXX\\foo", "x")
  check("an unknown root is REG badvalue", not okb and err.is(eb, "REG", "badvalue"), tostring(eb))
  okb, eb = pcall(reg.set, base, "x", "v", "weird")
  check("an unknown type is REG badvalue", not okb and err.is(eb, "REG", "badvalue"), tostring(eb))
  okb, eb = pcall(reg.remove, "HKCU\\Software")
  check("remove refuses a key right under a root", not okb and err.is(eb, "REG", "badvalue"), tostring(eb))
  if not sys.info().elevated then
    none, e = reg.set("HKLM\\SOFTWARE\\kuu-test-suite", "x", "1")
    check("writing under HKLM without elevation is nil, REG access", none == nil and err.is(e, "REG", "access"), tostring(e))
  end
  local build = reg.get("HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", "CurrentBuild")
  check("reading a system key agrees with sys.info", tonumber(build) == sys.info().windows.build, tostring(build))

  do
    local calls = {
      function() return reg.get(base .. "\0ignored", "s") end,
      function() return reg.set(base .. "\0ignored", "s", "changed") end,
      function() return reg.create(base .. "\0ignored") end,
      function() return reg.exists(base .. "\0ignored") end,
      function() return reg.keys(base .. "\0ignored") end,
      function() return reg.values(base .. "\0ignored") end,
      function() return reg.remove(base .. "\0ignored") end,
      function() return reg.get(base, "s\0ignored") end,
      function() return reg.set(base, "s\0ignored", "changed") end,
      function() return reg.delete(base, "s\0ignored") end,
      function() return reg.set(base, "nul", "before\0after") end,
      function() return reg.set(base, "nul", "before\0after", "expandstring") end,
      function() return reg.set(base, "nul", { "before\0after" }) end,
    }
    for i, call in ipairs(calls) do
      local ok, e = pcall(call)
      check("registry native text refuses NUL, case " .. i, not ok and err.is(e, "REG", "badvalue"), tostring(e))
    end
    check("refused NUL arguments leave the real key intact", reg.exists(base) and reg.get(base, "d") == 42)
    check("an empty registry string is still an empty string", reg.set(base, "empty", "") and reg.get(base, "empty") == "")
    local proc = require "proc"
    local r = proc.run { T.root .. "/build/test/reg_fixture.exe", base:sub(6) }
    check("the fixture writes malformed registry text", r and r.code == 0, r and T.describe(r))
    local expected = {
      bad_string = { "string", string.pack("<I2I2", 0xd800, 0) },
      bad_expand = { "expandstring", string.pack("<I2I2", 0xdc00, 0) },
      bad_multi = { "multistring", string.pack("<I2I2I2I2I2", 97, 0, 0xd800, 0, 0) },
      odd_string = { "string", "A" },
    }
    local entries = {}
    for _, entry in ipairs(reg.values(base)) do entries[entry.name] = entry end
    for name, want in pairs(expected) do
      local value, e = reg.get(base, name)
      check("get refuses malformed UTF-16: " .. name, value == nil and err.is(e, "REG", "encoding"), tostring(e))
      local entry = entries[name]
      check("values preserves malformed bytes and the type: " .. name,
        entry and entry.type == want[1] and entry.value == nil and entry.bytes == want[2])
    end
  end
  check("remove deletes the tree", reg.remove(base) == true and reg.exists(base) == false and reg.exists(base .. "\\sub") == false)
  reg.remove("HKCU\\Software\\kuu-test-suite")
end
