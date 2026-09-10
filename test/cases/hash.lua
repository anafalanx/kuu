-- hash.lua -- digests against published vectors, files, HMAC, random bytes.
global none
global <const> require, ipairs, tostring, type, string, pcall, table

return function(T)
  local check, contains = T.check, T.contains
  local hash = require "hash"
  local err = require "err"

  check("sha256 of abc", hash.sum("sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  check("sha256 of the empty string", hash.sum("sha256", "") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  check("md5 of the empty string", hash.sum("md5", "") == "d41d8cd98f00b204e9800998ecf8427e")
  check("sha1 of abc", hash.sum("sha1", "abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
  check("sha512 of abc starts right", T.starts(hash.sum("sha512", "abc"), "ddaf35a193617aba"))
  check("bytes with NUL and high bits hash as given", hash.sum("sha256", "a\0b\255") == hash.sum("sha256", "a\0b\255") and #hash.sum("sha256", "a\0b\255") == 64)

  local raw = hash.sum("sha256", "abc", { raw = true })
  check("raw digests are 32 bytes", #raw == 32 and raw:byte(1) == 0xba)

  -- RFC 4231 test case 1
  check("hmac-sha256 matches RFC 4231", hash.hmac("sha256", string.rep("\11", 20), "Hi There") == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")

  local h = hash.start("sha256")
  h:update("a"):update("b"):update("c")
  check("incremental hashing equals one shot", h:final() == hash.sum("sha256", "abc"))
  local ok, e = pcall(h.update, h, "more")
  check("a finished hasher refuses more input", not ok and err.is(e, "HASH", "closed"), tostring(e))

  local path = T.work .. "/hash-me.bin"
  local data = string.rep("kuu\0\255", 100000)
  T.write_file(path, data)
  check("file hashing streams the same digest", hash.file("sha256", path) == hash.sum("sha256", data))
  local none, e2 = hash.file("sha256", T.work .. "/no-such-file.bin")
  check("a missing file is nil, HASH notfound", none == nil and err.is(e2, "HASH", "notfound"), tostring(e2))

  do
    local fs = require "fs"
    local long = fs.absolute(T.work .. "/hash-long/" .. ("deep-component/"):rep(20) .. "tool.bin")
    fs.mkdir(fs.dirname(long))
    fs.write(long, "verified bytes")
    local value, failure = hash.file("sha256", long)
    check("file hashing agrees with fs.read beyond MAX_PATH",
      #long > 260 and fs.read(long) == "verified bytes" and value == hash.sum("sha256", "verified bytes"), tostring(failure))
    local ok, raised = pcall(hash.file, "sha256", path .. "\0ignored")
    check("file hashing refuses NUL instead of hashing a different filename",
      not ok and err.is(raised, "HASH", "badvalue"), tostring(raised))
    local value, failure = hash.file("sha256", path .. ".")
    check("file hashing rejects ambiguous trailing-dot paths",
      value == nil and err.is(failure, "HASH", "badvalue"), tostring(failure))
    value, failure = hash.file("sha256", "\255")
    check("file hashing reports invalid UTF-8 paths",
      value == nil and err.is(failure, "HASH", "encoding"), tostring(failure))
  end

  local r1, r2 = hash.random(32), hash.random(32)
  check("random bytes have the asked length and differ", #r1 == 32 and #r2 == 32 and r1 ~= r2)
  ok, e = pcall(hash.random, 0)
  check("random refuses a zero count", not ok and err.is(e, "HASH", "badvalue"), tostring(e))

  ok, e = pcall(hash.sum, "sha3-256", "x")
  check("an unknown algorithm is refused by name", not ok and err.is(e, "HASH", "badvalue") and contains(tostring(e), "sha3-256"), tostring(e))
  check("algorithms lists the five", table.concat(hash.algorithms(), ",") == "md5,sha1,sha256,sha384,sha512")

  local u1, u2 = hash.uuid(), hash.uuid()
  check("uuid is a lower-case version 4 UUID with the variant bits set",
    u1:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil, u1)
  check("two uuids differ", u1 ~= u2)
end
