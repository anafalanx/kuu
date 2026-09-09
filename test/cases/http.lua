-- http.lua -- WinHTTP requests against the loopback fixture server: statuses,
-- headers, bodies, redirects and the zero-request canary, timeouts, limits,
-- streaming to a file, and concurrency on the loop.
global none
global <const> require, ipairs, tostring, tonumber, type, string, pcall, table, select

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local http = require "http"
  local proc = require "proc"
  local fs = require "fs"
  local sched = require "sched"
  local err = require "err"

  local fixture = T.root .. "/build/test/http_fixture.exe"
  if fs.exists(fixture) ~= "file" then
    check("the http fixture server is built (make fixtures)", false, fixture)
    return
  end
  local files = T.work .. "/http-files"
  fs.mkdir(files)
  fs.write(files .. "/blob.bin", string.rep("\0\1\2\255", 4096))
  local server <close> = proc.start { fixture, (files:gsub("/", "\\")), stream = true }
  local first = server:read("line", "10s")
  local port = tonumber((first or ""):match("^PORT (%d+)$"))
  check("the fixture reports its port", port ~= nil, tostring(first))
  if port == nil then return end
  local base = "http://127.0.0.1:" .. port

  -- basics ----------------------------------------------------------------------------
  local r, e = http.get(base .. "/hello")
  check("get returns status, headers, body, bytes", r and r.status == 200 and r.body == "hello" and r.bytes == 5
    and r.headers["content-type"] == "text/plain" and contains(r.rawheaders, "HTTP/1.1 200"), tostring(e))
  r = http.get(base .. "/status/404")
  check("a 404 is a result, not an error", r and r.status == 404 and r.body == "status body")
  r = http.get(base .. "/status/500")
  check("a 500 is a result too", r and r.status == 500)
  r = http.get(base .. "/big?n=" .. (3 * 1024 * 1024))
  check("a 3 MiB body arrives whole", r and r.bytes == 3 * 1024 * 1024 and #r.body == r.bytes)
  r = http.get(base .. "/dup")
  check("repeated headers are joined and the raw block keeps both",
    r and r.headers["set-cookie"] == "a=1, b=2" and r.headers["x-kuu"] == "yes" and select(2, r.rawheaders:gsub("Set%-Cookie", "")) == 2, r and r.headers["set-cookie"])
  r = http.get(base .. "/gzip")
  check("gzip bodies are decompressed transparently", r and r.body == "hello gzip", r and r.body)

  -- post -----------------------------------------------------------------------------
  local payload = "{\"a\":1}\0raw\255"
  r = http.post(base .. "/echo", payload, { type = "application/json" })
  check("post sends the body as bytes with the given type", r and starts(r.body, "POST application/json " .. #payload .. "\n") and r.body:sub(-#payload) == payload, r and r.body)
  r = http.post(base .. "/echo", "x")
  check("post defaults to application/octet-stream", r and starts(r.body, "POST application/octet-stream 1\n"), r and r.body)
  r = http.request { method = "PUT", url = base .. "/echo", body = "put-body", headers = { ["X-Test"] = "1", ["Content-Type"] = "text/x" } }
  check("request sends other methods and caller headers", r and starts(r.body, "PUT text/x 8\n"), r and r.body)
  r = http.get(base .. "/headers", { headers = { ["X-Agent-Note"] = "hi there" } })
  check("request headers reach the server and the agent is kuu", r and contains(r.body, "X-Agent-Note: hi there") and contains(r.body, "User-Agent: kuu/"), r and r.body)

  -- redirects and the canary ------------------------------------------------------------
  r = http.get(base .. "/redirect")
  check("redirects are followed by default", r and r.status == 200 and r.body == "hello", r and tostring(r.status))
  local before = tonumber(http.get(base .. "/hits?path=/hello").body)
  r = http.get(base .. "/redirect-abs", { redirect = "none" })
  local after = tonumber(http.get(base .. "/hits?path=/hello").body)
  check("redirect = none returns the 3xx and makes zero further requests",
    r and r.status == 302 and r.headers["location"] == base .. "/hello" and after == before, tostring(r and r.status) .. " hits " .. tostring(before) .. "->" .. tostring(after))
  local ok, e2 = pcall(http.get, base .. "/hello", { redirect = "follow" })
  check("redirect takes exactly none", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))

  -- failures --------------------------------------------------------------------------------
  local none, e3 = http.get(base .. "/slow?ms=1500", { timeout = "300ms" })
  check("a slow server is HTTP timeout", none == nil and err.is(e3, "HTTP", "timeout"), tostring(e3))
  none, e3 = http.get(base .. "/big?n=" .. (2 * 1024 * 1024), { maxbody = "1M" })
  check("a body over maxbody is refused as HTTP toobig, never truncated", none == nil and err.is(e3, "HTTP", "toobig"), tostring(e3))
  none, e3 = http.get("http://127.0.0.1:1/hello", { timeout = "5s" })
  check("a closed port is HTTP connect", none == nil and err.is(e3, "HTTP", "connect"), tostring(e3))
  none, e3 = http.get("http://no-such-host.invalid/x", { timeout = "10s" })
  check("an unknown host is HTTP notfound", none == nil and err.is(e3, "HTTP", "notfound"), tostring(e3))
  ok, e2 = pcall(http.get, "ftp://example.com/x")
  check("a non-http scheme is refused", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))
  ok, e2 = pcall(http.get, base .. "/hello\r\nX: y")
  check("a url with control characters is refused", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))
  ok, e2 = pcall(http.get, base .. "/hello", { headers = { ["Bad:Name"] = "x" } })
  check("a header name with a colon is refused", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))
  ok, e2 = pcall(http.get, base .. "/hello", { headers = { X = "line\r\nInjected: yes" } })
  check("a header value with a newline is refused", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))
  ok, e2 = pcall(http.get, base .. "/hello", { timeout = "0s" })
  check("a zero timeout is refused because WinHTTP reads it as infinite", not ok and err.is(e2, "HTTP", "badvalue"), tostring(e2))
  ok, e2 = pcall(http.get, base .. "/hello", { insecure = true })
  check("an unknown option is refused", not ok and err.is(e2, "HTTP", "usage"), tostring(e2))

  -- streaming to a file ---------------------------------------------------------------------
  local target = T.work .. "/downloaded.bin"
  if fs.exists(target) then fs.remove(target) end
  r = http.get(base .. "/files/blob.bin", { to = target })
  check("to streams the body into the file and returns its path", r and r.status == 200 and r.body == "" and r.bytes == 16384 and r.path == target
    and fs.read(target) == string.rep("\0\1\2\255", 4096), tostring(e))
  local leftovers = 0
  for _, entry in ipairs(fs.list(T.work).entries) do if entry.name:find("downloaded.bin.kuu-", 1, true) then leftovers = leftovers + 1 end end
  check("no temporary file remains beside the download", leftovers == 0)
  none, e3 = http.get(base .. "/big?n=200000", { to = target, maxbody = "100K" })
  check("a refused download leaves the previous file untouched", none == nil and err.is(e3, "HTTP", "toobig") and #fs.read(target) == 16384, tostring(e3))
  r = http.get(base .. "/files/missing.bin", { to = target })
  check("a 404 download still writes what the server sent", r and r.status == 404 and fs.read(target) == "no such file")

  -- concurrency on the loop -----------------------------------------------------------------
  local t0 = sched.clock()
  local tasks = {}
  for i = 1, 5 do
    tasks[i] = sched.spawn(function() return http.get(base .. "/slow?ms=300") end)
  end
  local ticks = 0
  local ticker = sched.spawn(function() for _ = 1, 5 do sched.sleep("40ms") ticks = ticks + 1 end end)
  local all_ok = true
  for i = 1, 5 do local rr = tasks[i]:join(); if not rr or rr.body ~= "slow" then all_ok = false end end
  ticker:join()
  local elapsed = sched.clock() - t0
  check("five slow requests overlap while timers keep firing", all_ok and ticks == 5 and elapsed < 1.4, string.format("%.2fs ticks %d", elapsed, ticks))

  http.get(base .. "/quit")
  local exit = server:wait("5s")
  check("the fixture exits on /quit", exit and exit.status == "exit", exit and exit.status)
end
