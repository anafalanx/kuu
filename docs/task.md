# Tasks

A repository declares its tasks once, in a `tasks.lua` at its root, and runs
them with `kuu run`. There is no second file to keep in step: the task list,
each task's description, its dependencies, and its arguments live in the
declaration, and `kuu list` reads them back from there.

```lua
-- tasks.lua
local task = require "task"
local fs = require "fs"

task "gen" {
  desc = "write build/version.h",
  run = function()
    fs.mkdir("build")
    fs.write("build/version.h", '#define VERSION "0.3"\n')
  end,
}

task "build" {
  desc = "compile build/app.exe",
  deps = { "gen" },
  args = { { "--release", type = "flag", help = "optimise" } },
  run = function(opts)
    local zig = assert(require("toolchain").path("tools/lock.json", "zig", ".tools"))
    return task.exec { zig, "build", opts.release and "-Doptimize=ReleaseFast" or "-Doptimize=Debug" }
  end,
}

task "test" {
  desc = "run the suite",
  deps = { "build" },
  run = function() return task.exec { "build/app.exe", "--self-test" } end,
}

task.default "build"
```

```text
kuu run                      the default task, after its dependencies
kuu run test                 test, after build, after gen; each runs once
kuu run build --release      arguments after the task name go to that task
kuu run --json test          the same, with one JSON object on stdout at the end
kuu list [--json]            the tasks, their descriptions, dependencies, and arguments
```

## Where kuu looks

`kuu run` and `kuu list` walk up from the current directory to the nearest
directory holding `tasks.lua`, make that directory the current directory, and
point `require` at it. A task's relative paths are therefore relative to the
project root wherever the command was typed, children started by a task begin
there, and `require "lib.helper"` in `tasks.lua` reads `lib/helper.lua` of the
project. Without a `tasks.lua` anywhere above, both verbs exit 2 with
`TASK noproject`.

## Declaring

`task "name" { ... }` takes a plain word (letters, digits, `.`, `_`, `-`) and
a table with these attributes; anything else is refused at declaration, as is
declaring a name twice.

| attribute | meaning |
|---|---|
| `desc` | one line for `kuu list` |
| `deps` | names to run first, each once, in dependency order; a cycle is `TASK cycle` naming the chain, an unknown name is `TASK unknown` saying who needed it |
| `args` | a [cli](cli.md) spec for the arguments after the task name; checked when declared, so a broken spec fails `kuu list` too |
| `run` | `function(opts)`; `opts` is the parsed arguments, or an empty table |
| `hidden` | left out of `kuu list`; still runs by name |

`task.default "name"` names what `kuu run` alone runs; without it, `kuu run`
alone lists the tasks and exits 2.

`tasks.lua` is an ordinary Lua chunk and its top level runs on every `kuu run`
and `kuu list`, so keep work inside `run` functions. A syntax error or a raise
while declaring is reported with its line and exits 2.

## Running and failing

A task succeeds by returning nothing. It fails by raising, or by returning
`nil, err`. The runner prints one line per task on standard error when it
finishes, `kuu: build 1.2s`, and on failure names the task and the error.
Dependencies that already ran are not run again, and nothing after a failed
task runs. Every argument is checked before anything runs: the named task's
against its spec, and each dependency's spec against no arguments. So
`--help`, a wrong argument, or a dependency that requires an argument exits 2
with nothing started.

```lua
run = function(opts)
  return task.exec { "gcc", "-O2", "main.c", "-o", "build/app.exe", timeout = "5m" }
end
```

`task.exec` runs a child on kuu's own console, so its output streams through
as it happens. It takes the same table as `proc.run` (`cwd`, `env`, `timeout`)
and returns `true`, or `nil, err` with `TASK exit` and the child's code in
`err.exit`, which `kuu run` then uses as its own exit code. A child that timed
out or was killed is `TASK failed`. To capture output instead, use
[proc.run](proc.md) directly and decide for yourself.

| exit | meaning |
|---|---|
| 0 | every task returned |
| the child's code | a `task.exec` child exited non-zero |
| 1 | a task raised or returned `nil, err` |
| 2 | no `tasks.lua`, a broken `tasks.lua`, an unknown task or dependency, a cycle, or wrong arguments |

## JSON

`kuu run --json` (the flag before the task name) prints one JSON object on
standard output when it ends, and nothing else there: `print` and `io.write`
from tasks are redirected to standard error, and the output of a `task.exec`
child is captured and relayed to standard error when the child finishes.
Only a direct `io.stdout:write` bypasses this, and then the task itself has
broken the contract.

```json
{"ok":true,"result":{"root":"C:/work/app","task":"test",
  "tasks":[{"name":"gen","seconds":0.01,"ok":true},{"name":"build","seconds":3.2,"ok":true},{"name":"test","seconds":0.8,"ok":true}]}}
```

On failure `ok` is false, `error` carries `domain`, `code`, `message`, and
`exit`, and the process exits as in the table above. `kuu list --json` gives
`{"ok":true,"result":{"root","default","tasks":[...]}}`, each task with `name`,
`desc`, `deps`, `hidden`, and `args` as declared (`name`, `type`, `help`,
`default`, `required`, `rest`, `choices`).

## The module in a program

The same module drives the verbs and is open to programs that build on them.
The registry is the module, so a program that loads a `tasks.lua` with `load`
after `require "task"` sees its declarations.

```lua
local task = require "task"
task.all()                 -- the declared tasks, in declaration order
task.get("build")          -- one entry: name, desc, deps, args, run, hidden
task.default_task()        -- the default's name, or nil
task.plan("test")             -- the entries to run, in order | nil, err
task.arguments(entry, args)   -- the arguments parsed against its spec: opts | nil, err
task.execute(entry, opts)     -- run it with parsed arguments: true | nil, err
```

| code | meaning |
|---|---|
| `TASK noproject` | no `tasks.lua` here or above |
| `TASK badvalue` | a bad declaration, or `tasks.lua` failed to load |
| `TASK unknown`, `TASK cycle` | the dependency graph |
| `CLI usage` | wrong arguments for a task, or `--help` |
| `TASK failed` | a task raised something that is not an `err`, or its child did not exit normally |
| `TASK exit` | a `task.exec` child exited non-zero; `err.exit` is the code |
