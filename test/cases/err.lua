-- err.lua -- the one error shape: a domain, a code, a message, and `err.is`.
--
-- The message is as long as it is. A 1024-byte buffer used to cut it, and
-- the part that fell off a long-path failure was the Windows reason at the
-- end -- exactly the part that says why. Both the Lua-side object and the
-- host's own failure text are checked here, since they are built by
-- different code.
global none
global <const> require, tostring, string, pcall

return function(T)
  local check, contains = T.check, T.contains
  local err = require "err"
  local fs = require "fs"

  local e = err.new("SPIKE", "boom", "it went")
  check("an error carries its domain, code and message",
    e.domain == "SPIKE" and e.code == "boom" and e.message == "it went")
  check("tostring reads DOMAIN code: message", tostring(e) == "SPIKE boom: it went")
  check("err.is matches domain and code", err.is(e, "SPIKE", "boom") and not err.is(e, "SPIKE", "bang")
    and not err.is(e, "OTHER", "boom"))
  check("err.is is false for a non-error", not err.is("text", "SPIKE", "boom") and not err.is(nil, "SPIKE", "boom"))

  -- A message far beyond the old cut, made by the host: a path this long
  -- cannot exist, so fs.read refuses it with the whole path in the message.
  local long = T.work .. "/" .. string.rep("p", 1500) .. "/" .. string.rep("q", 1500) .. ".txt"
  local _, why = fs.read(long)
  check("a host-built message keeps its whole text", why ~= nil and #why.message > 3000
    and contains(why.message, string.rep("q", 1500)), why and #why.message or "no error")

  -- And one made in Lua through err.new, which shares the constructor.
  local wide = err.new("SPIKE", "wide", string.rep("x", 5000))
  check("a Lua-built message is exact to the byte", #wide.message == 5000)

  -- The pcall path: a raise carries the same object.  An unknown option is
  -- the mistake that raises, by the law every module is being held to.
  local ok, raised = pcall(fs.write, long, "x", { cwdd = 1 })
  check("a raised error is the same shape", not ok and err.is(raised, "FS", "usage"), tostring(raised))
end
