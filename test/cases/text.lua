-- text.lua -- strict conversions between UTF-8 and Windows encodings.
global none
global <const> require, tostring, pcall, type

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

  -- base64 and hex ---------------------------------------------------------------------------
  check("tobase64 follows the published vectors", text.tobase64("") == "" and text.tobase64("f") == "Zg==" and text.tobase64("fo") == "Zm8="
    and text.tobase64("foo") == "Zm9v" and text.tobase64("foobar") == "Zm9vYmFy", text.tobase64("foobar"))
  check("the url alphabet swaps the two symbols and drops padding", text.tobase64("\255\254\253") == "//79" and text.tobase64("\255\254\253", { url = true }) == "__79"
    and text.tobase64("f", { url = true }) == "Zg", text.tobase64("f", { url = true }))
  check("frombase64 inverts both alphabets, with or without padding", text.frombase64("Zm9vYmFy") == "foobar" and text.frombase64("Zg==") == "f"
    and text.frombase64("Zg") == "f" and text.frombase64("__79") == "\255\254\253")
  check("frombase64 ignores whitespace, as in PEM", text.frombase64("Zm9v\r\nYmFy\n") == "foobar")
  local none, e = text.frombase64("Zm9v*mFy")
  check("a byte outside the alphabet is TEXT invalid with its position", none == nil and err.is(e, "TEXT", "invalid") and tostring(e):find("at 5", 1, true) ~= nil, tostring(e))
  none, e = text.frombase64("Z")
  check("a lone trailing character is TEXT invalid", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = text.frombase64("Zg==Zg")
  check("data after padding is TEXT invalid", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  local bytes = "\0\1\127\128\255"
  check("tohex is lower case and fromhex accepts either case and whitespace", text.tohex(bytes) == "00017f80ff" and text.fromhex("00017F80FF") == bytes
    and text.fromhex("00 01\n7f 80 ff") == bytes and text.tohex("") == "")
  none, e = text.fromhex("abc")
  check("an odd number of hex digits is TEXT invalid", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
  none, e = text.fromhex("zz")
  check("a non-hex byte is TEXT invalid", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))

  -- case, as Windows maps it
  check("upper and lower map beyond ASCII", text.upper("éà ü straat") == "ÉÀ Ü STRAAT" and text.lower("ÉÀ Ü") == "éà ü" and text.upper("") == "", text.upper("éà ü straat"))
  check("Lua's own upper is ASCII only, which is why these exist", ("é"):upper() == "é")
  none, e = text.upper("\255")
  check("invalid UTF-8 is TEXT invalid", none == nil and err.is(e, "TEXT", "invalid"), tostring(e))
end
