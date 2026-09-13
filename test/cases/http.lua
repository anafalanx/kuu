-- http.lua -- WinHTTP requests against the loopback fixture server: statuses,
-- headers, bodies, redirects and the zero-request canary, timeouts, limits,
-- streaming to a file, and concurrency on the loop.
global none
global <const> require, ipairs, tostring, tonumber, string, pcall, select, io, assert

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

  do
    -- Catch failures in a separate process so native memory ownership is
    -- measured without allocations from the surrounding HTTP case. Disable
    -- ASAN's freed-memory quarantine in this child for the retention measure.
    local validation = T.kuu({ "-e", [[
local http,sys,err=require'http',require'sys',require'err'
local body=string.rep('x',4*1024*1024)
collectgarbage('collect')
local before=sys.info().process.private
for _=1,20 do
  local ok,e=pcall(http.request,{url='http://127.0.0.1:1/',method='POST',body=body,type={}})
  assert(not ok and err.is(e,'HTTP','badvalue'),tostring(e))
end
collectgarbage('collect')
local growth=sys.info().process.private-before
assert(growth<32*1024*1024,'native body leak: '..growth)
for _,spec in ipairs{{url='http://127.0.0.1:1/',method={}},
  {url='http://127.0.0.1:1/',method='GET\0POST'},
  {url='http://127.0.0.1:1/',type='text/plain\0hidden'}} do
  local ok,e=pcall(http.request,spec)
  assert(not ok and err.is(e,'HTTP','badvalue'),tostring(e))
end
for _=1,20 do
  local ok,e=pcall(http.request,setmetatable({url='http://127.0.0.1:1/',body=body},
    {__index=function(_,key) if key=='headers' then error('header accessor failed') end end}))
  assert(not ok and tostring(e):find('header accessor failed',1,true))
end
collectgarbage('collect')
assert(sys.info().process.private-before<32*1024*1024,'native body leak after accessor failure')
print('validation ownership ok')
]] }, { env = { ASAN_OPTIONS = (require("env").get("ASAN_OPTIONS") or "")
      .. ":quarantine_size_mb=0:thread_local_quarantine_size_kb=0" } })
    check("HTTP validation and accessor errors release native request allocations", validation.code == 0
      and contains(validation.out, "validation ownership ok"), T.describe(validation))
  end

  -- streaming to a file ---------------------------------------------------------------------
  local target = T.work .. "/downloaded.bin"
  do
    local long = files .. "/" .. string.rep("n", 236) .. ".txt"
    check("atomic writing supports a 240-character basename", fs.write(long, "previous") == true
      and fs.read(long) == "previous")
    local fetched, problem = http.get(base .. "/hello", { to = long })
    check("HTTP staging supports the same long basename", fetched and fs.read(long) == "hello", tostring(problem))
    local kept, failure = http.get(base .. "/hello", { to = long, sha256 = string.rep("0", 64) })
    check("a rejected long-name download preserves previous bytes", not kept and err.is(failure, "HTTP", "mismatch")
      and fs.read(long) == "hello", tostring(failure))
    assert(fs.remove(long))
  end
  if fs.exists(target) then fs.remove(target) end
  r = http.get(base .. "/files/blob.bin", { to = target })
  check("to streams the body into the file and returns its path", r and r.status == 200 and r.body == "" and r.bytes == 16384 and r.path == target
    and fs.read(target) == string.rep("\0\1\2\255", 4096), tostring(e))
  local leftovers = 0
  for _, entry in ipairs(fs.list(T.work).entries) do if entry.name:match("^%.kuu%-.*%.tmp$") then leftovers = leftovers + 1 end end
  check("no temporary file remains beside the download", leftovers == 0)
  none, e3 = http.get(base .. "/big?n=200000", { to = target, maxbody = "100K" })
  check("a refused download leaves the previous file untouched", none == nil and err.is(e3, "HTTP", "toobig") and #fs.read(target) == 16384, tostring(e3))
  r = http.get(base .. "/files/missing.bin", { to = target })
  check("a 404 download still writes what the server sent", r and r.status == 404 and fs.read(target) == "no such file")
  ok, e2 = pcall(http.get, base .. "/hello", { to = target .. "\0ignored.txt" })
  check("a NUL in the destination is refused without replacing its prefix",
    not ok and err.is(e2, "HTTP", "badvalue") and fs.read(target) == "no such file", tostring(e2))
  do
    local a, b = fs.absolute(files .. "/cwd-a"), fs.absolute(files .. "/cwd-b")
    fs.mkdir(a)
    fs.mkdir(b)
    fs.write(a .. "/result.txt", "A-original")
    fs.write(b .. "/result.txt", "B-original")
    local cwd = fs.cwd()
    local worked, downloaded, problem = pcall(function()
      fs.chdir(a)
      local fetch = sched.spawn(function() return http.get(base .. "/slow?ms=200", { to = "result.txt" }) end)
      sched.sleep("30ms")
      fs.chdir(b)
      return fetch:join("5s")
    end)
    fs.chdir(cwd)
    check("a relative download stays in its starting directory across a yield",
      worked and downloaded and downloaded.status == 200 and downloaded.path == "result.txt"
      and fs.read(a .. "/result.txt") == "slow" and fs.read(b .. "/result.txt") == "B-original",
      tostring(problem or (not worked and downloaded)))
  end

  -- The rename into place is retried the way fs.write's is (fs.lua has the
  -- account).  A target held open for the whole window still fails, after
  -- the window, keeps its bytes, and leaves no temporary beside it.
  do
    local handle <close> = io.open(target, "rb")
    local began = sched.clock()
    local held, e4 = http.get(base .. "/files/blob.bin", { to = target })
    local elapsed = (sched.clock() - began) * 1000
    check("a download onto a held target fails after the retry window and keeps the old bytes",
      held == nil and err.is(e4, "HTTP", "oserror") and elapsed >= 10 and fs.read(target) == "no such file",
      tostring(e4) .. string.format(" after %.0f ms", elapsed))
    leftovers = 0
    for _, entry in ipairs(fs.list(T.work).entries) do if entry.name:match("^%.kuu%-.*%.tmp$") then leftovers = leftovers + 1 end end
    check("no temporary file remains after a refused placement", leftovers == 0)
  end
  do
    -- The destination's directory not being there is the machine's answer,
    -- returned as fs.write returns it, and it names the path.
    local none3, e5 = http.get(base .. "/hello", { to = T.work .. "/no-such-dir/x.bin" })
    check("a download into a directory that is not there is nil, HTTP notfound, naming the path",
      none3 == nil and err.is(e5, "HTTP", "notfound") and contains(tostring(e5), "no-such-dir"), tostring(e5))
  end

  -- A scope deadline can arrive before the worker publishes its WinHTTP
  -- handle, or during the request. Neither path may replace the old file or
  -- leave its sibling temporary file behind after completion is delivered.
  local deadline_targets = {}
  for i, budget in ipairs({ 0, "10ms", "20ms" }) do
    local deadline_target = files .. "/deadline-kept-" .. i .. ".txt"
    deadline_targets[i] = deadline_target
    fs.write(deadline_target, "previous contents")
    local began = sched.clock()
    local value, problem = sched.deadline(budget, function()
      return http.get(base .. "/slow?ms=250", { to = deadline_target, timeout = "2s" })
    end)
    check("a scope deadline cancels an in-flight download", value == nil and err.is(problem, "SCHED", "deadline")
      and sched.clock() - began < 1, tostring(problem))
  end
  local cleanup_until, partials = sched.clock() + 2, 0
  repeat
    sched.sleep("10ms")
    partials = 0
    for _, entry in ipairs(fs.list(files).entries) do
      if entry.name:match("^%.kuu%-.*%.tmp$") then partials = partials + 1 end
    end
  until partials == 0 or sched.clock() >= cleanup_until
  local preserved = true
  for _, path in ipairs(deadline_targets) do preserved = preserved and fs.read(path) == "previous contents" end
  check("deadline cancellation preserves the destinations and removes temporary files", preserved and partials == 0, tostring(partials))
  r, e = http.get(base .. "/hello")
  check("a request after cancelled downloads still succeeds", r ~= nil and r.body == "hello", tostring(e))

  -- verification -----------------------------------------------------------------------------
  local hello_sha = require("hash").sum("sha256", "hello")
  r, e = http.get(base .. "/hello", { to = files .. "/verified.txt", sha256 = hello_sha:upper() })
  check("a download that hashes as asked lands", r and r.status == 200 and fs.read(files .. "/verified.txt") == "hello", tostring(e))
  r, e = http.get(base .. "/hello", { to = files .. "/wrong.txt", sha256 = string.rep("0", 64) })
  local leftovers = 0
  for _, entry in ipairs(fs.list(files).entries) do if entry.name:sub(1, 9) == "wrong.txt" or entry.name:match("^%.kuu%-.*%.tmp$") then leftovers = leftovers + 1 end end
  check("a download that hashes otherwise is HTTP mismatch, names both digests, and leaves no file", r == nil and err.is(e, "HTTP", "mismatch")
    and contains(e.message, hello_sha) and leftovers == 0, tostring(e))
  r, e = http.get(base .. "/status/404", { to = files .. "/missing.txt", sha256 = hello_sha })
  check("a non-2xx answer to a verified download is HTTP status and leaves no file", r == nil and err.is(e, "HTTP", "status") and not fs.exists(files .. "/missing.txt"), tostring(e))
  r, e = http.get(base .. "/hello", { sha256 = hello_sha })
  check("a body kept in memory is verified the same way", r and r.body == "hello", tostring(e))
  r, e = http.get(base .. "/hello", nil)
  check("an explicit nil options table is the same as none", r and r.status == 200 and r.body == "hello", tostring(e))
  http.get(base .. "/dup") -- sets two cookies
  r = http.get(base .. "/headers")
  check("requests are independent: a cookie set by one is not sent by the next", r and r.status == 200 and not r.body:lower():find("cookie:", 1, true), r and r.body)
  r, e = http.post(base .. "/echo", "x", nil)
  check("and so for post", r and r.status == 200, tostring(e))
  local ok_hex, raised_hex = pcall(http.get, base .. "/hello", { sha256 = "abc" })
  check("a malformed sha256 is refused before any request", not ok_hex and err.is(raised_hex, "HTTP", "badvalue"), tostring(raised_hex))

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
  do
    local result = proc.run {T.root .. "/build/test/http_error_fixture.exe"}
    check("TLS client-key and proxy errors have actionable native diagnostics",
      result and result.code == 0 and contains(result.out, "ERROR_WINHTTP_CLIENT_CERT_NO_PRIVATE_KEY")
      and contains(result.out, "ERROR_WINHTTP_CLIENT_CERT_NO_ACCESS_PRIVATE_KEY")
      and contains(result.out, "ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED_PROXY")
      and contains(result.out, "ERROR_WINHTTP_SECURE_FAILURE_PROXY"), result and result.err)
  end

end
