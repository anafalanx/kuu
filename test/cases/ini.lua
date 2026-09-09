-- ini.lua -- Windows INI: decode, encode, and edits that leave the rest alone.
global none
global <const> require, tostring, type, string, pcall, table

return function(T)
  local check = T.check
  local ini = require "ini"
  local err = require "err"

  local text = table.concat({
    "; a comment", "top=1", "", "[Server]", "Host = example.org", "port=8080", "# another",
    "Quoted = \"  spaced ; not a comment \"", "flag", "", "[Paths]", "root=C:\\data", "",
  }, "\r\n")
  local t = ini.decode(text)
  check("top-level keys land under the empty section", t[""].top == "1")
  check("sections hold trimmed keys and values", t.Server.Host == "example.org" and t.Server.port == "8080")
  check("surrounding quotes are removed, the inside kept", t.Server.Quoted == "  spaced ; not a comment ")
  check("a line without = is a key with an empty value", t.Server.flag == "")
  check("backslashes are plain characters", t.Paths.root == "C:\\data")
  check("get ignores case", ini.get(t, "server", "HOST") == "example.org" and ini.get(t, "nothing", "x") == nil)

  local out = ini.encode { [""] = { z = "1", a = "2" }, Two = { k = "v" }, One = { n = 3, b = true, s = " lead" } }
  check("encode is sorted and deterministic, top-level first, values quoted when they would not survive",
    out == "a=2\nz=1\n\n[One]\nb=true\nn=3\ns=\" lead\"\n\n[Two]\nk=v\n", out)
  check("encode and decode round-trip", ini.decode(out).One.s == " lead" and ini.decode(out)[""].z == "1")
  local okb, eb = pcall(ini.encode, { S = { ["a=b"] = "1" } })
  check("a key with = is INI badvalue", not okb and err.is(eb, "INI", "badvalue"), tostring(eb))

  local edited = ini.set(text, "server", "PORT", "9090")
  check("set replaces a value in place, keeping the key's spelling, the comments, and the rest",
    edited:find("\r\nport=9090\r\n", 1, true) ~= nil and edited:find("Host = example.org", 1, true) ~= nil and edited:find("; a comment", 1, true) == 1, edited)
  local added = ini.set(text, "Server", "new", "yes")
  check("set adds a missing key at the end of its section, before the blank line", added:find("flag\r\nnew=yes\r\n\r\n[Paths]", 1, true) ~= nil, added)
  local fresh = ini.set(text, "Extra", "k", "v")
  check("set appends a missing section", fresh:sub(-#"\r\n[Extra]\r\nk=v\r\n") == "\r\n[Extra]\r\nk=v\r\n", fresh)
  local top = ini.set(text, "", "top", "2")
  check("set edits a top-level key", top:find("^; a comment\r\ntop=2\r\n") ~= nil, top)
  local lf = ini.set("[A]\nx=1\n", "A", "y", "2")
  check("set keeps LF line ends", lf == "[A]\nx=1\ny=2\n", lf)
  check("set on empty text writes the section", ini.set("", "A", "x", "1") == "[A]\nx=1\n")
  check("set quotes a value that would not survive a round trip", ini.set("", "A", "x", " lead") == "[A]\nx=\" lead\"\n")
  local removed = ini.remove(text, "Server", "host")
  check("remove drops one key ignoring case", removed:find("Host", 1, true) == nil and removed:find("port=8080", 1, true) ~= nil, removed)
  local gone = ini.remove(text, "Server")
  check("remove drops a whole section, header included",
    gone:find("[Server]", 1, true) == nil and gone:find("port", 1, true) == nil and gone:find("[Paths]", 1, true) ~= nil, gone)
  check("remove of something absent returns the text unchanged", ini.remove(text, "Nope", "x") == text and ini.remove(text, "Server", "nope") == text)
  local okq, eq = pcall(ini.set, text, "S", "k", "a\nb")
  check("a value spanning lines is INI badvalue", not okq and err.is(eq, "INI", "badvalue"), tostring(eq))
end
