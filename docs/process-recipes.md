# Process descriptions, outcomes and diagnostics

A process specification mixes numbered arguments with options such as `cwd`
and `env`. It is a Lua call table, not a JSON object. To describe it, copy its
arguments into an explicit `json.array` and put them under `argv`. Keep the
working directory and environment overlay in separate fields. An empty overlay
is `{}`; an empty argument array is `[]`. JSON's strict mapping stays useful.

Use `task.exec` when output can stream through. A program can define nonzero
success codes; accepting a classified `TASK exit` preserves its individual
child record. Use `task.command` with `proc.run` when the task needs captured
bytes. This retains tool resolution, supervision and deadlines, but the capture
call has **no individual child record** in the ledger or `kuu run --json`
events. The enclosing task and run are still recorded. It is a supported
project implementation choice; call the project task through `kuu run`.

## A project module

Save as `process_ops.lua`. The extra success-code set is specific to the
program: `{ [3] = true }` below belongs to the sample probe, not every tool.
Zero remains success. A timeout, kill or limit is always failure, even if its
numeric code happens to be in the set. Invalid call arguments still raise;
launch failures return a classified error with the original cause attached.

```lua
global none
global <const> require, ipairs, pairs, tostring
local task, proc, json = require "task", require "proc", require "json"
local fs, err = require "fs", require "err"
local M = {}

local function description(command)
  local argv, env = json.array {}, {}
  for i, argument in ipairs(command) do argv[i] = argument end
  for name, value in pairs(command.env or {}) do env[name] = value end
  return { argv = argv, cwd = fs.absolute(command.cwd or fs.cwd()), env = env }
end

function M.describe(spec)
  return description(task.command(spec))
end

function M.exec_success(spec, extra_success)
  local ok, why = task.exec(spec)
  if ok then return true end
  if err.is(why, "TASK", "exit") and extra_success and extra_success[why.exit] == true then
    return true
  end
  return nil, why
end

local function failure(command, code, message, result, cause)
  local context = description(command)
  -- The full environment overlay is useful in a description, not in an error.
  context.env = nil
  message = message .. "\ncommand: " .. json.encode(context)
  if result then
    if result.err ~= "" then message = message .. "\nstderr:\n" .. result.err end
    if result.truncated then message = message .. "\n[captured output truncated]" end
  end
  local details = { result = result, cause = cause }
  if code == "exit" then details.exit = result.code end
  return nil, err.new("PROJECT", code, message, details)
end

function M.capture(spec, extra_success)
  local command = task.command(spec)
  local result, why = proc.run(command)
  if not result then
    return failure(command, "launch", "could not start child: " .. tostring(why), nil, why)
  end
  if result.status ~= "exit" then
    local reason = result.status .. (result.limit and (" (" .. result.limit .. ")") or "")
    return failure(command, result.status, "child ended: " .. reason, result)
  end
  if result.code ~= 0 and not (extra_success and extra_success[result.code] == true) then
    return failure(command, "exit", "child exited with code " .. result.code, result)
  end
  if result.truncated then
    return failure(command, "truncated", "complete captured output is required", result)
  end
  return result
end

return M
```

`describe` resolves a declared executable and records an absolute cwd. A bare
executable name remains a PATH lookup; this is a description, not a PATH
resolver or a complete replay format. `env` contains only the explicit overlay:
strings set variables and `false` removes them; inherited variables are not
expanded. `timeout`, `limits`, `stdin` and capture settings are intentionally
outside this `{argv, cwd, env}` description. Persist only arguments and
environment values that the project intends to expose in diagnostics.

The module copies the specification and its description rather than changing
the caller's table. `capture` expects ordinary capture options: do not set
`inherit = true`, because inherited output cannot be collected. Use finite
`timeout` and `maxout` values appropriate to the command. `truncated` covers
either stream, so even accepted exits are rejected when complete output was
not retained. The failure's `result` still holds the captured prefixes, status,
code, elapsed time and actual stderr; `cause` retains a launch error. These
extra fields are for Lua callers, not automatic JSON/ledger error fields.

## A runnable example

Save this small program as `probe.lua` beside the module. It supplies three
ordinary exit outcomes, a slow operation and oversized output without needing
an installed external application.

```lua
global none
global <const> require, io, os, string
local rt, sched = require "rt", require "sched"
local mode = rt.args[1] or "same"
if mode == "same" then
  io.write("unchanged\n")
elseif mode == "changed" then
  io.write("updated\n")
  os.exit(3)
elseif mode == "failed" then
  io.write("partial output\n")
  io.stderr:write("probe could not finish its work\n")
  os.exit(9)
elseif mode == "slow" then
  io.stderr:write("probe began waiting\n")
  io.stderr:flush()
  sched.sleep("10s")
elseif mode == "loud" then
  io.write(string.rep("x", 8192))
else
  io.stderr:write("unknown probe mode\n")
  os.exit(2)
end
```

Save this manifest as `manifest.lua`. `stream changed` demonstrates accepting
code 3 after `task.exec` has recorded the child's actual exit. `capture failed`
reports code 9, its real stderr, argv and cwd. `capture slow` reports timeout;
`capture loud` refuses a truncated success. Place the project's pinned `kuu.exe`
beside the manifest; the sample declares that existing executable as its tool.
Loading the manifest performs no provisioning work.

```lua
global none
global <const> require, io
local task, rt, fs = require "task", require "rt", require "fs"
local ops = require "process_ops"
task.tool "probe" { exe = "kuu.exe", timeout = "5s", output = "lines" }
local arguments = { { "mode", type = "string", default = "changed" } }
local function command(mode)
  return { tool = "probe", fs.join(rt.root(), "probe.lua"), mode,
    cwd = rt.root(), timeout = "500ms", maxout = "1K" }
end
task "stream" {
  desc = "Run the probe and accept its documented changed exit",
  args = arguments,
  run = function(opts) return ops.exec_success(command(opts.mode), { [3] = true }) end,
}
task "capture" {
  desc = "Capture the probe with status and truncation checks",
  args = arguments,
  run = function(opts)
    local result, why = ops.capture(command(opts.mode), { [3] = true })
    if not result then return nil, why end
    io.write(result.out)
    return true
  end,
}
```

Run `kuu run stream changed` or `kuu run capture changed`. For machine output,
`kuu run --json stream changed` keeps the child's code 3 in its child events
and history while the enclosing task succeeds. `kuu run --json capture changed`
has task/run records without a child record. Under `--json`, the capture task's
own `io.write` is redirected to standard error; it is not an individual child
event.

Finally save `describe.lua` and run `kuu describe.lua` to print a JSON process
description without executing the probe. The module performs no provisioning.

```lua
global none
global <const> require, io
local rt, fs, json = require "rt", require "fs", require "json"
require "manifest"
local ops = require "process_ops"
io.write(json.encode(ops.describe {
  tool = "probe", fs.join(rt.root(), "probe.lua"), "changed",
  cwd = rt.root(), env = { PROBE_MODE = "local", PROBE_UNUSED = false },
}), "\n")
```

## Reading failures

For streamed operations, branch on `err.is(why, "TASK", "exit")` and
`why.exit` only for ordinary nonzero exits. Other results stay failures:
`TASK failed` carries `why.status` and, for a job limit, `why.limit`; a launch
failure is a `PROC` error. Never accept one by parsing its message or treating
every nonzero code as equivalent.

For captured operations, first test whether a result exists, then `status`,
then the tool's exit policy, then `truncated`, before decoding stdout. A limit
result reports `status = "limit"` with `limit = "memory"`, `"cpu"` or
`"processes"`; its code does not turn it into success. The module exposes this
as `PROJECT limit`, retaining the full result and naming the limit in its
message. Add `limits` to the command when the project needs them. Keep a
wall-clock timeout as well, because a waiting process need not consume CPU.

The message prints stderr itself rather than the result table's address or
stdout mislabeled as stderr. Empty stderr stays empty; stdout is available in
the attached result. A truncation notice means that neither stream should be
treated as a complete diagnostic or document. See [proc](proc.md),
[tools](tools.md) and [the ledger](ledger.md) for the underlying contracts.
