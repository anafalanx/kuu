# Cookbook

Each block is a complete program. Save it under the indicated filename and
run it with your repository's `kuu.exe`. Inputs are positional arguments;
paths belong to the current directory unless absolute. The first ten
programs require kuu 0.7 or later, and the four after them, which are
shaped by the front door — a manifest, a wrapper module, a reader of the
run stream, a reader of the ledger — require 0.10. [`pty`](pty.md) is
provisional.

## 1. Wait for a port to open

`kuu wait-port.lua HOST PORT [TIMEOUT]` waits up to 30 seconds by default.
The outer deadline includes DNS, connection attempts, and the pauses between
them. A successful probe closes its connection immediately.

```lua
global none
global <const> require, assert, tonumber, print
local rt, net, sched = require "rt", require "net", require "sched"
local host = assert(rt.args[1], "usage: wait-port.lua HOST PORT [TIMEOUT]")
local port = assert(tonumber(rt.args[2]), "PORT must be a number")
local up, e = sched.deadline(rt.args[3] or "30s", function()
  while true do
    local connected = net.probe(host, port, "1s")
    if connected then return connected end
    sched.sleep("100ms")
  end
end)
assert(up, e)
print("ready", up.address, port)
```

## 2. Install a tool by hash

`kuu install-tool.lua URL SHA256 ARCHIVE DEST [STRIP]` downloads a pinned
archive into a project cache and extracts it into a project tool directory.
For example, use `build/tool.zip` and `.tools/tool` for the last two paths.
Get the URL and SHA-256 from the tool's release, then record both in the
project. `STRIP` defaults to zero; use one for a versioned top-level folder.
Extraction overwrites existing destination files.

```lua
global none
global <const> require, assert, tonumber, print
local rt, fs = require "rt", require "fs"
local http, archive = require "http", require "archive"
local url = assert(rt.args[1], "usage: install-tool.lua URL SHA256 ARCHIVE DEST [STRIP]")
local sha256 = assert(rt.args[2], "SHA256 is required")
local cached = assert(rt.args[3], "ARCHIVE is required")
local dest = assert(rt.args[4], "DEST is required")
local strip = assert(tonumber(rt.args[5] or "0"), "STRIP must be a number")
assert(fs.mkdir(fs.dirname(cached)))
local response = assert(http.get(url, {
  to = cached, sha256 = sha256, timeout = "10m", maxbody = "1G",
}))
assert(response.status == 200, "download returned HTTP " .. response.status)
assert(archive.unpack(cached, dest, { strip = strip, timeout = "10m" }))
print("installed", dest)
```

## 3. Tail a log while a build runs

`kuu tail-build.lua LOG EXECUTABLE [ARG ...]` starts the build and copies new
bytes from its log to stdout until its process tree finishes. The build may
create the log after starting or truncate it; this program handles both.
Use a fresh log for each build. The log and inherited build output should be
UTF-8 if they are to share the terminal.

```lua
global none
global <const> require, assert, io, tostring
local rt, fs, proc, sched = require "rt", require "fs", require "proc", require "sched"
local path = assert(rt.args[1], "usage: tail-build.lua LOG EXECUTABLE [ARG ...]")
local spec = { assert(rt.args[2], "EXECUTABLE is required"), inherit = true, timeout = "10m" }
for i = 3, #rt.args do spec[#spec + 1] = rt.args[i] end
local offset = 0
local function tail()
  if not fs.exists(path) then return end
  local file <close> = assert(io.open(path, "rb"))
  local size = assert(file:seek("end"))
  if size < offset then offset = 0 end
  assert(file:seek("set", offset))
  while offset < size do
    local bytes = file:read(65536)
    if not bytes then break end
    io.write(bytes)
    offset = offset + #bytes
  end
  io.flush()
end
local child <close> = assert(proc.start(spec))
while child:running() do tail(); sched.sleep("100ms") end
tail()
local result = assert(child:wait())
assert(result.status == "exit" and result.code == 0,
  "build ended: " .. result.status .. " / " .. tostring(result.code))
```

## 4. Find the process on a port and stop it

`kuu stop-port.lua PORT EXPECTED_PID` stops one process. Supply the PID you
intend to stop; the program refuses an empty or ambiguous owner list and an
unexpected owner. The lookup is a snapshot and does not reserve the PID.
For a child your program starts itself, keep its handle and use `child:kill()`
to terminate its whole tree instead.

```lua
global none
global <const> require, assert, tonumber, print
local rt, proc, sched = require "rt", require "proc", require "sched"
local port = assert(tonumber(rt.args[1]), "usage: stop-port.lua PORT EXPECTED_PID")
local expected = assert(tonumber(rt.args[2]), "EXPECTED_PID must be a number")
local owners = assert(proc.find { port = port })
assert(#owners == 1 and owners[1].pid == expected, "port owner changed or is ambiguous")
assert(proc.kill(expected))
local stopped, e = sched.deadline("5s", function()
  while proc.alive(expected) do sched.sleep("50ms") end
  return true
end)
assert(stopped, e)
print("stopped", expected)
```

## 5. Verify an installer's signature before running it

`kuu signed-installer.lua FILE EXPECTED_THUMBPRINT [ARG ...]` requires both
a valid embedded signature and the expected signing certificate. Record the
40-character certificate thumbprint independently of the download. Keep
the installer in a directory controlled by the project: verification does
not reserve the path between checking and launching. Catalog-only signatures
report unsigned. Successful installer exit codes other than zero must be
handled according to that installer's documented contract.

```lua
global none
global <const> require, assert, tostring, print
local rt, sys, proc = require "rt", require "sys", require "proc"
local path = assert(rt.args[1], "usage: signed-installer.lua FILE EXPECTED_THUMBPRINT [ARG ...]")
local expected = assert(rt.args[2], "EXPECTED_THUMBPRINT is required"):upper()
assert(#expected == 40 and expected:match("^%x+$"), "expected a 40-character SHA-1 thumbprint")
local signature = assert(sys.signature(path))
assert(signature.signed, "installer has no embedded signature")
assert(signature.valid, "installer signature is invalid: " .. tostring(signature.reason))
assert(signature.thumbprint == expected, "installer has an unexpected signing certificate")
local spec = { path, inherit = true, timeout = "10m" }
for i = 3, #rt.args do spec[#spec + 1] = rt.args[i] end
local result = assert(proc.run(spec))
assert(result.status == "exit" and result.code == 0,
  "installer ended: " .. result.status .. " / " .. tostring(result.code))
print("installed", signature.signer)
```

## 6. Check a service and start it

`kuu start-service.lua NAME` uses the service's internal name, not its display
name. Starting a service may need elevation. A timeout stops waiting; it does
not undo a start request already accepted by Windows.

```lua
global none
global <const> require, assert, print
local rt, svc = require "rt", require "svc"
local name = assert(rt.args[1], "usage: start-service.lua NAME")
local before = assert(svc.status(name))
if before.state ~= "running" then assert(svc.start(name, "30s")) end
local after = assert(svc.status(name))
assert(after.state == "running", "service did not stay running")
print(after.name, after.state, after.pid)
```

## 7. Read the last errors from the event log

`kuu event-errors.lua [CHANNEL]` prints up to 20 errors from the last day,
newest first. `System` is the default channel. Each record is one JSON line,
so embedded newlines in event messages do not split records.

```lua
global none
global <const> require, assert, ipairs, print
local rt, evt, time, json = require "rt", require "evt", require "time", require "json"
local events = assert(evt.read(rt.args[1] or "System", {
  since = time.now() - 86400, level = "error", limit = 20,
}))
for _, event in ipairs(events) do print(json.encode(event)) end
```

## 8. Run a step under a deadline with limits

`kuu bounded-step.lua EXECUTABLE [ARG ...]` gives a step 30 seconds of elapsed
time, 512 MiB of committed memory, 10 seconds of user CPU time, and at most
eight processes including the initial child. The `<close>` handle kills the
tree if the deadline unwinds the block. The deadline bounds waits; it cannot
interrupt Lua code that computes without waiting.

```lua
global none
global <const> require, assert, tostring
local rt, proc, sched = require "rt", require "proc", require "sched"
local spec = { assert(rt.args[1], "usage: bounded-step.lua EXECUTABLE [ARG ...]"),
  inherit = true, limits = { memory = "512M", cpu = "10s", processes = 8 } }
for i = 2, #rt.args do spec[#spec + 1] = rt.args[i] end
local ok, e = sched.deadline("30s", function()
  local child <close> = assert(proc.start(spec))
  local result = assert(child:wait())
  assert(result.status == "exit" and result.code == 0,
    "step ended: " .. result.status .. " / " .. tostring(result.limit or result.code))
  return true
end)
assert(ok, e)
```

## 9. Edit an INI value in place

`kuu edit-ini.lua FILE SECTION KEY VALUE` preserves comments, spacing, line
endings, and a UTF-8 BOM. It replaces the effective last occurrence of the
key. The write is atomic; coordinate separately if another process also edits
this file. Use an empty SECTION argument for a key before any section header.

```lua
global none
global <const> require, assert, print
local rt, fs, ini = require "rt", require "fs", require "ini"
local path = assert(rt.args[1], "usage: edit-ini.lua FILE SECTION KEY VALUE")
local section = assert(rt.args[2], "SECTION is required")
local key = assert(rt.args[3], "KEY is required")
local value = assert(rt.args[4], "VALUE is required")
local before = assert(fs.read(path))
assert(fs.write(path, ini.set(before, section, key, value)))
print("updated", path, section, key)
```

## 10. Drive a prompt through pty

`kuu prompt.lua` drives `cmd.exe`'s console input, sets a value through
`set /p`, and checks the answer. `expect` consumes through the matched text
and uses Lua patterns. `text()` is the accumulated plain-text view, not a
terminal screen. See the provisional [`pty`](pty.md) contract before driving
a different interactive program.

```lua
global none
global <const> require, assert, os, print
local pty = require "pty"
local shell = os.getenv("ComSpec") or "C:/Windows/System32/cmd.exe"
local child <close> = assert(pty.spawn { shell, "/d", "/q", cols = 120, rows = 30 })
assert(child:expect({ ">" }, "5s"))
assert(child:write("set /p name=Enter:\r"))
assert(child:expect({ "Enter:" }, "5s"))
assert(child:write("kuu\r"))
assert(child:write("echo received:%name%\r"))
assert(child:expect({ "received:kuu" }, "5s"))
print(child:text())
assert(child:write("exit\r"))
local result = assert(child:wait("5s"))
assert(result.status == "exit" and result.code == 0, "prompt child failed")
```
## 11. A manifest: a task with arguments, a dependency, and a declared tool

`manifest.lua` at the project root. `kuu run report --since 2026-09-01`
runs `gen` first, then the declared tool through the door: the exe resolved
against the root, the declared timeout, a record in the ledger, and every
argument held to the declaration by `kuu check` before anything runs.

```lua
global none
global <const> require, tostring
local task, fs = require "task", require "fs"

task.defaults { timeout = "10m" }

task.tool "report" {
  exe = "tools/report.exe",
  args = { ["--out"] = "path", ["--since"] = "string", ["--verbose"] = "flag" },
  output = "ndjson",
  timeout = "5m",
}

task "gen" {
  desc = "write build/inputs.json",
  run = function()
    fs.mkdir("build")
    return fs.write("build/inputs.json", "[]\n")
  end,
}

task "report" {
  desc = "the report, from build/inputs.json",
  deps = { "gen" },
  args = {
    { "--since", type = "string", default = "2026-01-01", help = "the first day to include" },
    { "--verbose", type = "flag", help = "say what is skipped" },
  },
  run = function(opts)
    local call = { tool = "report", "--out", "build/report.ndjson", "--since", tostring(opts.since) }
    if opts.verbose then call[#call + 1] = "--verbose" end
    return task.exec(call)
  end,
}

task.default "report"
```

## 12. A module that wraps a tool and decodes its NDJSON

`tools/report.lua` in the project, required as `require "tools.report"`:
the tool is run for its output through `task.command`, so the declared exe
and timeout apply, and each line of standard output is one record. A line
that does not decode is the tool's fault, and says which line. Truncated
capture is refused before parsing, so a valid prefix is never a complete result. This is the
program's own `proc.run`, not a crossing; a task that wants the record
calls `task.exec` instead.

```lua
global none
global <const> require, ipairs
local task, proc, json, err = require "task", require "proc", require "json", require "err"
local M = {}

-- M.rows(since) -> records | nil, err
function M.rows(since)
  local r, e = proc.run(task.command { tool = "report", "--out", "-", "--since", since })
  if not r then return nil, e end
  if r.status ~= "exit" then return nil, err.new("REPORT", "failed", "report: " .. r.status) end
  if r.code ~= 0 then return nil, err.new("REPORT", "exit", "report exited with code " .. r.code, { exit = r.code }) end
  if r.truncated then return nil, err.new("REPORT", "toobig", "report output exceeded the capture limit") end
  local rows, number = {}, 0
  for line in r.out:gmatch("[^\r\n]+") do
    number = number + 1
    local record, bad = json.decode(line)
    if record == nil then return nil, err.new("REPORT", "badvalue", "line " .. number .. " is not JSON: " .. bad.message) end
    rows[#rows + 1] = record
  end
  return rows
end

return M
```

## 13. Read the `kuu run --json` stream as it happens

`kuu run --json test | kuu watch-run.lua` reads one event per line from
standard input, prints each task as it ends, and exits with the run's own
code when the envelope arrives — the error's `exit` when it has one, else 2
for a usage or a `TASK` failure and 1 for the rest, the rule `kuu run` itself
follows; a child's events name the pid and the program. The envelope is the
last line, so a reader that only wants the outcome keeps the last line it
saw.

```lua
global none
global <const> require, io, os, print, string
local json = require "json"
local last
for line in io.stdin:lines() do
  local record = json.decode(line)
  if record == nil then
    io.stderr:write("not an event: ", line, "\n")
  elseif record.event == "run" then
    print("run " .. record.task .. " in " .. record.root)
  elseif record.event == "task" and record.state == "finished" then
    print(string.format("%s %s %.1fs%s", record.name, record.ok and "ok" or "failed", record.seconds,
      record.error and ("  " .. record.error.domain .. " " .. record.error.code .. ": " .. record.error.message) or ""))
  elseif record.event == "child" and record.state == "finished" then
    print(string.format("  %s pid %d %s%s", record.argv[1], record.pid, record.status,
      record.code and (" " .. record.code) or ""))
  elseif record.ok ~= nil then
    last = record
  end
end
if last == nil then io.stderr:write("no envelope\n") os.exit(1) end
if not last.ok then
  local e = last.error
  io.stderr:write(e.domain, " ", e.code, ": ", e.message, "\n")
  local usage = (e.domain == "CLI" and e.code == "usage") or e.domain == "TASK"
  os.exit(e.exit or (usage and 2 or 1))
end
```

## 14. What failed last, from the ledger

`kuu last-failure.lua [ROOT]` reads `.kuu/ledger/*.ndjson` under the
project root, one JSON record per line, and prints the last task whose
status is `failed` with its error — a child that timed out is recorded with
that status and no error, and the run's own record ends on the task's error,
so the task is the one to name — or says that nothing has failed. The files
are the ledger's own format; nothing but `fs.read` and `json.decode` is
needed to read them.

```lua
global none
global <const> require, ipairs, print, os, io, table
local fs, json, rt = require "fs", require "json", require "rt"
local root = rt.args[1] or "."
local dir = fs.join(root, ".kuu", "ledger")
local listing = fs.list(dir)
if not listing then io.stderr:write("no ledger under ", fs.absolute(root), "; kuu run writes one\n") os.exit(1) end
local names = {}
for _, entry in ipairs(listing.entries) do
  if entry.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = entry.name end
end
table.sort(names)
local failed
for _, name in ipairs(names) do
  for line in (fs.read(fs.join(dir, name)) or ""):gmatch("[^\n]+") do
    local record = json.decode(line)
    if record and record.kind == "task" and record.status == "failed" then failed = record end
  end
end
if failed == nil then print("nothing has failed") os.exit(0) end
print(failed.kind, failed.name, failed.error and (failed.error.domain .. " " .. failed.error.code .. ": " .. failed.error.message) or "")
```
