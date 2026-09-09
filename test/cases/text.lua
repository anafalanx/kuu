-- text.lua -- strict conversions between UTF-8 and Windows encodings.
global none
global <const> require, tostring, pcall, string, type

return function(T)
  local check = T.check
  local text = require "text"
  local err = require "err"

  check("cp1252 decodes to UTF-8", text.decode("caf\233", "cp1252") == "café")
  check("UTF-8 encodes to cp1252", text.encode("café", "cp1252") == "caf\233")
  check("utf-16le round-trips", text.decode(text.encode("héllo €", "utf-16le"), "utf-16le") == "héllo €")
  check("utf-16be differs from le and round-trips", text.encode("A", "utf-16be") == "\0A" and text.decode("\0A", "utf-16be") == "A")
  check("latin1 is an alias for 28591", text.decode("\233", "latin1") == "é")
  check("utf-8 decode validates only", text.decode("ok", "utf-8") == "ok")

  local none, e = text.decode("\255\254x", "utf-8")
  check("invalid UTF-8 is refused, not repaired", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = text.decode("\0\216", "utf-16le")
  check("a lone UTF-16 surrogate is refused", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = text.decode("abc", "utf-16le")
  check("an odd byte count is not UTF-16", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = text.encode("😀", "cp1252")
  check("a character outside the code page is unencodable, never best-fit", none == nil and err.is(e, "TEXT", "unencodable"), tostring(e))
  none, e = text.encode("\255", "cp1252")
  check("encode refuses invalid UTF-8 input", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))

  local ok, e2 = pcall(text.decode, "x", "klingon")
  check("an unknown encoding name is raised", not ok and err.is(e2, "TEXT", "badvalue"), tostring(e2))
  check("cpNNN names work", text.decode("\130", "cp850") == "é")
  check("ansi and oem resolve", type(text.decode("abc", "ansi")) == "string" and type(text.decode("abc", "oem")) == "string")
  check("valid reports strict UTF-8", text.valid("héllo") == true and text.valid("\255") == false and text.valid("") == true)
end
