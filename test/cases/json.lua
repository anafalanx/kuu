-- json.lua -- the mapping, strictness, round trips, and the JSONTestSuite corpus.
global none
global <const> require, ipairs, pairs, tostring, type, string, io, pcall, table, math, next, print

return function(T)
  local check, contains = T.check, T.contains
  local json = require "json"
  local err = require "err"
  local proc = require "proc"

  -- the mapping ------------------------------------------------------------------
  local v = json.decode('{"a": 1, "b": 2.5, "c": "x", "d": true, "e": null, "f": [1, null, 3], "g": {}}')
  check("objects decode to tables", type(v) == "table" and v.a == 1 and v.b == 2.5 and v.c == "x" and v.d == true)
  check("integers stay integers, reals stay floats", math.type(v.a) == "integer" and math.type(v.b) == "float")
  check("null decodes to json.null", v.e == json.null and tostring(json.null) == "null")
  check("arrays are marked and keep null slots", json.is_array(v.f) and #v.f == 3 and v.f[2] == json.null)
  check("an empty object is an unmarked empty table", type(v.g) == "table" and next(v.g) == nil and not json.is_array(v.g))

  check("big integers within 64 bits are exact", json.decode("9223372036854775807") == math.maxinteger)
  check("integers beyond 64 bits become floats", math.type(json.decode("18446744073709551616")) == "float")
  check("negative and exponent forms parse", json.decode("-12") == -12 and json.decode("1e3") == 1000.0)
  check("strings unescape, surrogate pairs included", json.decode('"a\\u00e9b\\n\\ud83d\\ude00"') == "aéb\n😀")

  -- encoding -----------------------------------------------------------------------
  local back0 = json.decode(json.encode({ a = 1, b = 2.5, c = "x", d = false }))
  check("encode writes compact JSON with stable types", back0.a == 1 and back0.b == 2.5 and back0.c == "x" and back0.d == false)
  check("encode escapes controls and quotes, leaves UTF-8 raw", json.encode("a\"b\\c\n\1é") == '"a\\"b\\\\c\\n\\u0001é"')
  check("a sequence encodes as an array", json.encode({ 1, 2, 3 }) == "[1,2,3]")
  check("an empty table encodes as an object", json.encode({}) == "{}")
  check("json.array{} encodes as an empty array", json.encode(json.array {}) == "[]")
  check("json.null encodes as null", json.encode({ x = json.null }) == '{"x":null}')
  check("integral floats keep a decimal point", json.encode(2.0) == "2.0")
  check("pretty output has newlines and two-space indents", contains(json.encode({ a = { 1 } }, { pretty = true }), '{\n  "a": [\n    1\n  ]\n}'))

  local ok, e = pcall(json.encode, { [1] = "a", x = "b" })
  check("a table with mixed keys is refused", not ok and err.is(e, "JSON", "badvalue"), tostring(e))
  ok, e = pcall(json.encode, 0 / 0)
  check("NaN is refused", not ok and err.is(e, "JSON", "badvalue"), tostring(e))
  ok, e = pcall(json.encode, "\255")
  check("an invalid UTF-8 string is refused", not ok and err.is(e, "JSON", "encoding"), tostring(e))
  ok, e = pcall(json.encode, print)
  check("a function is refused", not ok and err.is(e, "JSON", "badvalue"), tostring(e))
  local cycle = {}
  cycle.self = cycle
  ok, e = pcall(json.encode, cycle)
  check("a cyclic table is refused as too deep", not ok and err.is(e, "JSON", "depth"), tostring(e))

  local round = { name = "kuu", list = json.array { 1, json.null, "three" }, nested = { deep = { x = true } }, empty = json.array {} }
  local back = json.decode(json.encode(round))
  check("a document round-trips", back.name == "kuu" and #back.list == 3 and back.list[2] == json.null and back.list[3] == "three"
    and back.nested.deep.x == true and json.is_array(back.empty) and #back.empty == 0)

  -- strictness -----------------------------------------------------------------------
  local none, e2 = json.decode('{"a": 1, "a": 2}')
  check("duplicate keys are refused", none == nil and err.is(e2, "JSON", "duplicate") and contains(tostring(e2), "object key 'a' appears twice"), tostring(e2))
  none, e2 = json.decode("[1, 2,")
  check("a parse error names the byte", none == nil and err.is(e2, "JSON", "parse") and contains(tostring(e2), "byte"), tostring(e2))
  none, e2 = json.decode(string.rep("[", 600) .. string.rep("]", 600))
  check("nesting beyond 512 is refused", none == nil and err.is(e2, "JSON", "depth"), tostring(e2))
  check("nesting at 500 is fine", json.decode(string.rep("[", 500) .. string.rep("]", 500)) ~= nil)
  none, e2 = json.decode('"\\ud800"')
  check("a lone surrogate escape is a parse error", none == nil and err.is(e2, "JSON", "parse"), tostring(e2))
  none, e2 = json.decode("[1] x")
  check("trailing garbage is a parse error", none == nil and err.is(e2, "JSON", "parse"), tostring(e2))

  -- the corpus -----------------------------------------------------------------------
  local listing = proc.run { "cmd.exe", "/c", "dir", "/b", (T.fixtures .. "/jsontestsuite"):gsub("/", "\\") }
  local files = {}
  for name in listing.out:gmatch("[^\r\n]+") do
    if name:match("%.json$") then files[#files + 1] = name end
  end
  -- The suite calls duplicate keys valid (RFC 8259 only says keys SHOULD be
  -- unique); kuu refuses them on purpose, so these two y_ files must fail with
  -- JSON duplicate and nothing else.
  local refused_on_purpose = {
    ["y_object_duplicated_key.json"] = "duplicate",
    ["y_object_duplicated_key_and_value.json"] = "duplicate",
  }
  local accepted_y, rejected_n, wrong = 0, 0, {}
  for _, name in ipairs(files) do
    local data = T.read_file(T.fixtures .. "/jsontestsuite/" .. name)
    local value, e3 = json.decode(data)
    local kind = name:sub(1, 1)
    if refused_on_purpose[name] then
      if value == nil and err.is(e3, "JSON", refused_on_purpose[name]) then accepted_y = accepted_y + 1 else wrong[#wrong + 1] = name .. ": " .. tostring(e3) end
    elseif kind == "y" then
      if value ~= nil or e3 == nil then accepted_y = accepted_y + 1 else wrong[#wrong + 1] = name .. ": " .. tostring(e3) end
    elseif kind == "n" then
      if value == nil and e3 ~= nil then rejected_n = rejected_n + 1 else wrong[#wrong + 1] = name .. ": accepted" end
    end
  end
  check("JSONTestSuite: every y_ document is accepted (two duplicates refused by design)", accepted_y == 95, table.concat(wrong, "\n"))
  check("JSONTestSuite: every n_ document is rejected", rejected_n == 188, table.concat(wrong, "\n"))
  check("the corpus was actually read", #files == 318, tostring(#files))
end
