-- cookbook.lua -- the manual's ten complete programs: check every extracted
-- block and exercise them with owned processes/files or simulated service state.
global none
global <const> require, assert, ipairs, tonumber, tostring, string

return function(T)
  local check, contains = T.check, T.contains
  local fs, proc = require "fs", require "proc"
  local archive, hash, json = require "archive", require "hash", require "json"
  local root = fs.absolute(T.work .. "/cookbook")
  assert(fs.mkdir(root))
  local names = { "wait-port", "install-tool", "tail-build", "stop-port", "signed-installer",
    "start-service", "event-errors", "bounded-step", "edit-ini", "prompt" }
  local paths, count = {}, 0
  for source in assert(fs.read(T.root .. "/docs/cookbook.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    count = count + 1
    local path = root .. "/" .. (names[count] or tostring(count)) .. ".lua"
    assert(fs.write(path, source))
    paths[count] = path
    local r = T.kuu { "check", "--json", path }
    local report = json.decode(r.out)
    check("cookbook " .. (names[count] or tostring(count)) .. " passes kuu check",
      r.code == 0 and report and report.result.errors == 0 and report.result.warnings == 0, T.describe(r))
  end
  check("cookbook contains exactly ten complete Lua programs", count == #names, count)
  if count ~= #names then return end
  local function run(index, args)
    local command = { paths[index] }
    for _, value in ipairs(args or {}) do command[#command + 1] = value end
    return T.kuu(command, { timeout = "20s" })
  end

  local files = root .. "/files"
  assert(fs.mkdir(files .. "/payload"))
  assert(fs.write(files .. "/payload/tool.txt", "pinned cookbook tool\n"))
  assert(archive.pack(files .. "/tool.zip", files .. "/payload"))
  local fixture = fs.absolute(T.root .. "/build/test/http_fixture.exe")
  local server <close> = assert(proc.start { fixture, (files:gsub("/", "\\")), stream = true })
  local first = server:read("line", "10s")
  local port = tonumber((first or ""):match("^PORT (%d+)$"))
  check("cookbook fixture owns a loopback port", port ~= nil, first)
  if not port then return end
  local base = "http://127.0.0.1:" .. port
  local r = run(1, { "127.0.0.1", tostring(port), "2s" })
  check("wait-port observes the owned listener", r.code == 0 and contains(r.out, "ready"), T.describe(r))

  local digest = assert(hash.file("sha256", files .. "/tool.zip"))
  r = run(2, { base .. "/files/tool.zip", digest, root .. "/cache/tool.zip", root .. "/installed" })
  check("install-tool downloads by hash and extracts into the project", r.code == 0
    and fs.read(root .. "/installed/tool.txt") == "pinned cookbook tool\n", T.describe(r))
  r = run(2, { base .. "/files/tool.zip", string.rep("0", 64), root .. "/cache/bad.zip", root .. "/bad-install" })
  check("install-tool refuses a wrong hash before extraction", r.code == 1 and contains(r.err, "HTTP mismatch")
    and not fs.exists(root .. "/cache/bad.zip") and not fs.exists(root .. "/bad-install"), T.describe(r))

  local log = root .. "/build.log"
  assert(fs.write(log, ""))
  local build = root .. "/build.lua"
  assert(fs.write(build, [[global none
global <const> require, assert
local rt, fs, sched = require "rt", require "fs", require "sched"
assert(fs.write(rt.args[1], "first build line\n"))
sched.sleep("200ms")
assert(fs.write(rt.args[1], "last build line\n", { append = true }))
]]))
  r = run(3, { log, T.exe, build, log })
  check("tail-build streams a growing log and finishes with the child", r.code == 0
    and contains(r.out, "first build line\nlast build line\n"), T.describe(r))
  r = run(3, { log, T.exe, "-e", "os.exit(7)" })
  check("tail-build propagates a failed build", r.code == 1 and contains(r.err, "build ended: exit / 7"), T.describe(r))

  r = run(4, { tostring(port), "0" })
  check("stop-port refuses an unexpected owner without stopping it", r.code == 1
    and contains(r.err, "port owner changed") and server:running(), T.describe(r))
  r = run(4, { tostring(port), tostring(server.pid) })
  check("stop-port stops the explicitly selected fixture process", r.code == 0
    and contains(r.out, "stopped") and not proc.alive(server.pid), T.describe(r))
  r = run(1, { "127.0.0.1", tostring(port), "50ms" })
  check("wait-port returns the outer deadline when a listener never opens", r.code == 1
    and contains(r.err, "SCHED deadline"), T.describe(r))

  r = run(5, { fixture, string.rep("0", 40) })
  check("signed-installer refuses the unsigned fixture without launching it", r.code == 1
    and contains(r.err, "installer has no embedded signature") and not contains(r.out, "PORT"), T.describe(r))

  -- Run the unmodified program against an isolated SCM substitute. Exercise
  -- both branches without starting or stopping any machine service.
  local service_driver = root .. "/service-driver.lua"
  assert(fs.write(service_driver, [[global none
global <const> require, assert, package, load
local rt, fs = require "rt", require "fs"
local path, state = rt.args[1], rt.args[2]
local initial, starts = state, 0
package.loaded.svc = {
  status = function(name)
    assert(name == "CookbookFixture")
    return { name = name, state = state, pid = state == "running" and 42 or 0 }
  end,
  start = function(name, timeout)
    assert(name == "CookbookFixture" and timeout == "30s")
    starts = starts + 1
    state = "running"
    return true
  end,
}
rt.args = { "CookbookFixture" }
assert(load(assert(fs.read(path)), "@" .. path, "t"))()
assert(starts == (initial == "running" and 0 or 1))
]]))
  for _, state in ipairs { "running", "stopped" } do
    r = T.kuu { service_driver, paths[6], state }
    check("start-service handles a " .. state .. " service with simulated state", r.code == 0
      and contains(r.out, "CookbookFixture\trunning\t42"), T.describe(r))
  end

  r = run(7, { "System" })
  local valid_lines = true
  for line in r.out:gmatch("[^\n]+") do
    local event = json.decode(line)
    if not event or event.level ~= "error" then valid_lines = false end
  end
  check("event-errors reads the System log as JSON lines", r.code == 0 and valid_lines, T.describe(r))
  r = run(8, { T.exe, "-e", "print('bounded step ran')" })
  check("bounded-step completes a child under its deadline and limits", r.code == 0
    and contains(r.out, "bounded step ran"), T.describe(r))
  r = run(8, { T.exe, "-e", "os.exit(6)" })
  check("bounded-step propagates the child's failure", r.code == 1
    and contains(r.err, "step ended: exit / 6"), T.describe(r))

  local ini_path = root .. "/settings.ini"
  assert(fs.write(ini_path, "\239\187\191; keep this\r\n[Server]\r\nport = 80\r\nPORT = 81\r\n"))
  r = run(9, { ini_path, "server", "port", "9090" })
  check("edit-ini preserves BOM, comments and effective duplicate-key behavior", r.code == 0
    and fs.read(ini_path) == "\239\187\191; keep this\r\n[Server]\r\nport = 80\r\nPORT = 9090\r\n", T.describe(r))
  r = run(10)
  check("prompt drives console input and observes the answer", r.code == 0
    and contains(r.out, "received:kuu"), T.describe(r))

  local stability = assert(fs.read(T.root .. "/docs/stability.md"))
  local guard = stability:match("```lua\r?\n(.-)\r?\n```")
  check("stability documents a complete minimum-version guard", guard ~= nil)
  if guard then
    local guard_path = root .. "/version-guard.lua"
    assert(fs.write(guard_path, guard))
    local checked = T.kuu { "check", guard_path }
    check("minimum-version guard passes kuu check", checked.code == 0
      and contains(checked.err, "0 errors, 0 warnings"), T.describe(checked))
    r = T.kuu { guard_path }
    check("the documented guard accepts the runtime that ships it", r.code == 0, T.describe(r))

    -- The guard no longer reads rt.version, so the comparison itself is what
    -- needs exercising: a faked version field cannot stand in for it.
    local probe = root .. "/at-least.lua"
    assert(fs.write(probe, [[global none
global <const> require, print, tostring, ipairs, table
local rt = require "rt"
local out = {}
for _, want in ipairs { {0}, {0, 9}, {0, 9, 0}, {0, 9, 1}, {0, 10}, {1}, {1, 0} } do
  out[#out + 1] = tostring(rt.version_at_least(table.unpack(want)))
end
print(table.concat(out, ","))
]]))
    r = T.kuu { probe }
    check("version_at_least compares components numerically, so 0.10 follows 0.9",
      r.code == 0 and r.out == "true,true,true,false,false,false,false\n", T.describe(r))

    local bad = T.kuu { "-e", 'global none global <const> require require("rt").version_at_least("0.9")' }
    check("a version component that is not a number raises RT badvalue",
      bad.code == 1 and contains(bad.err, "RT badvalue"), T.describe(bad))
  end
end
