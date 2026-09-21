# Tools

Everything that runs in a project runs through `kuu.exe`: a task, a build, a
test, a fetch, and every program a task calls. If the project needs something
kuu cannot do, it builds a tool for it — in whatever technology suits — or
fetches one by hash into its own root, and calls it through the door. Editing
is yours; running is the door's.

A tool is declared in `manifest.lua`, beside the tasks that call it, in the
same shape a task is:

```lua
local task = require "task"

task.tool "report" {
  exe     = "tools/report/report.exe",          -- relative to the project root
  args    = { ["--out"] = "path", ["--since"] = "string", ["--verbose"] = "flag" },
  output  = "ndjson",                           -- ndjson | json | lines | none
  emits   = { "rows", "path" },                 -- the fields its records carry
  timeout = "5m",                               -- unless the call gives one
  reach   = { read = { "src", "build" }, write = { "build" }, net = {} },
}

task.tool "signtool" {
  exe    = ".tools/sdk/signtool.exe",
  args   = { sign = "flag", ["/sha1"] = "string", ["/tr"] = "string" },
  output = "lines",
}

task "report" {
  desc = "the weekly report",
  run = function() return task.exec { tool = "report", "--out", "build/report.json", "--since", "2026-09-01" } end,
}
```

| attribute | |
|---|---|
| `exe` | the program's path, relative to the project root; the one required attribute |
| `args` | the arguments the tool takes, name = type; the types are `flag`, `string`, `path`, `int`, `number`, `duration`, `size`. Absent, the arguments are not described and `check` does not judge them; `{}` says the tool takes none |
| `output` | what the tool writes on standard output: `ndjson`, `json`, `lines`, or `none` (the default) |
| `emits` | the fields its records carry; descriptive, listed by `capabilities`, verified by nothing |
| `timeout` | the child timeout when the call gives none; the default from `task.defaults` after that |
| `reach` | what the tool touches — `read`, `write` and `net` lists; declared and shown, never enforced, since whether a tool can be confined is its own technology's business. [Confined tools](confined.md) says what a tool that confines itself must provide |

An unknown attribute raises `TASK usage`, and `kuu check` reports visible
attribute mistakes without running the declaration. A value of the wrong
shape, an invalid tool name, or a name declared twice raises `TASK badvalue`.
Tool names start with an ASCII letter or digit and continue with letters,
digits, `.`, `_` or `-`. For an executable named `g++`, choose a declaration
name such as `cxx`; `cxx` is not a built-in tool.

## Calling one

```lua
task.exec { tool = "signtool", "sign", "/sha1", thumb, "/tr", "http://ts.example", "build/app.exe" }
task.exec { tool = "report", "--out", "build/r.json", cwd = "build", timeout = "20m" }

local spec = task.command { tool = "report", "--out", "build/r.json" }   -- the same table, resolved
local r, e = proc.run(spec)                                              -- for the output rather than the console
```

`task.exec { tool = "name", ... }` is `task.exec` as before, with the
declaration filling in what the call leaves out: the declared `exe` goes
first, resolved against the `require` root — the project root under `kuu
run`, `kuu list` and `kuu capabilities`, and a program's own directory when
a program loads the manifest itself — and the declared `timeout` applies
unless the call gives one. An `exe` the resolver refuses — a component ending
in a dot or a space, a device path — is refused at the declaration, as
`TASK badvalue`. Everything else — `cwd`, `env`, `limits`,
`maxout` — is the call's. The child runs on kuu's console, its output
streams through, and a non-zero exit is `TASK exit` with the code, as for any
`task.exec`.

`task.command` does the resolving and stops there: it returns the table
`task.exec` would run, for a program that wants the tool's output rather than
its console — a wrapper module, say, that hands the table to `proc.run` and
decodes what comes back. A tool the manifest does not declare is
`TASK unknown` from either. That `proc.run` is the program's own call: the
child has the job and the timeout like any other, but only `task.exec`
crosses the door, so neither the `kuu run --json` stream nor [the
ledger](ledger.md) sees it.

The enclosing task and run are still recorded. Capture is a supported choice
when the task needs output bytes; it is not necessary merely to accept a
documented nonzero exit code. The [process recipes](process-recipes.md) show
`TASK exit` classification, capture diagnostics, and serializing a command as
separate `argv`, `cwd` and `env` fields rather than a mixed Lua table.

## What the door does, and does not

Every tool called this way gets what every child of kuu gets: a job, so its
whole tree dies with kuu; the deadline; the limits it was given; a working
directory; the streams read by kuu and nothing else. That is the whole
contract for a fetched tool — `git`, `signtool`, a compiler — which the door
calls as it is and declares as it is. kuu imposes no format on a tool's
output: the declaration says what shape it produces, and the task reads that
shape.

For a tool the project writes, one shape is recommended, for a measured
reason and not as a rule: NDJSON on standard output, one complete record per
line. A tool killed at its deadline then leaves a readable prefix rather than
a truncated document, and kuu's stream reads already deliver lines with
backpressure, so a task can act on each record as it arrives. Arguments
arrive as argv, or as one JSON object on standard input if the tool prefers;
diagnostics go to standard error; failure is a non-zero exit. Nothing here
is required. A tool that writes YAML, or nothing, is declared with the
output it has.

kuu owns exactly one wire: its own output. Every `--json` verb speaks JSON,
and the ledger and `kuu run --json` speak NDJSON. kuu never reads a tool's
protocol, and no tool needs to know kuu's.

## A tool that reads like a module

A tool that wants to be called like a module is wrapped by an ordinary
project module, which is a thing `check` already reads:

```lua
-- tools/yaml.lua
global none
global <const> require
local task, proc, json = require "task", require "proc", require "json"
local M = {}

function M.decode(path)
  local r, e = proc.run(task.command { tool = "yaml", "--json", path })
  if not r then return nil, e end
  if r.code ~= 0 then return nil, require("err").new("YAML", "failed", r.err) end
  return json.decode(r.out)
end

return M
```

`require "tools.yaml"` then reads like any module, `yaml.decode(path)` is
checked as an export of that module, and the call inside is checked against
the `yaml` declaration. No plugin system is needed, and none exists.

## What `check` and `capabilities` see

`kuu check` reads the manifest as text — nothing runs — and takes each
`task.tool` declaration as the literal it is, holding its attributes to the
set above wherever it stands. Then, in every file, a
`task.exec` or `task.command` written with a literal `tool = "name"` is held
to it: a name the manifest does not declare is an error, with the nearest
declared name suggested; an argument that reads as an option name — `-x`,
`--long`, a Windows switch `/x`, or the name in `--name=value` — and is not
in `args` is an error of the same kind as an option a palette call does not
take. Values are not judged: the argument after an option that takes one, a
negative number, a path, `-` and `--` alone. Nor is anything that is not a
literal — a table in a variable, a name computed at run time. Where the
root holds a manifest, a `task.exec` whose table names no `tool` at all is a
warning: the door still runs it, but nothing describes it. A declaration
with a part the text does not show — a computed key, a value built by an
expression — or a name declared more than once is reported and its calls
are not judged, the way a module whose exports cannot be bounded is left
alone. [check](check.md) has the details; `check.tools(root)` is the reading
it uses.

`kuu capabilities` lists the tools from the registry the manifest filled when
it ran — the executed reading — with `exe`, `output`, `args`, `emits`,
`timeout` and `reach`. The suite holds the two readings equal, so the manual
can say the checker and the descriptor agree.

Whatever a task installs under `.tools` and never declares is not seen by
either. Declare it, and it is.
