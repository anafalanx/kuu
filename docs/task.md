# Tasks

A repository declares its tasks once, in a `tasks.lua` at its root, and runs
them with `kuu run`. There is no second file to keep in step: the task list,
each task's description, its dependencies, and its arguments live in the
declaration, and `kuu list` reads them back from there.

```lua
-- tasks.lua
local task = require "task"
local fs = require "fs"

task.defaults { timeout = "10m" }

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
    return task.exec { ".tools/zig/zig.exe", "build", opts.release and "-Doptimize=ReleaseFast" or "-Doptimize=Debug" }
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
kuu run --dry-run test       the plan, in order, arguments checked, nothing run
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
| `run` | `function(opts)`; `opts` is the parsed arguments, or an empty table; optional when `deps` is non-empty |
| `hidden` | left out of `kuu list`; still runs by name |

A task may group dependencies without doing additional work:

```lua
task "all" { deps = { "build", "test" } }
```

An aggregate follows the same planning, argument validation, failure propagation,
and JSON reporting rules. Shared dependencies still run once. A declaration
with neither a function nor non-empty dependencies is refused.

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

`task.defaults { timeout = "10m" }` gives every `task.exec` a default
child timeout. A duration string uses the same units as `proc`, and a number
is seconds. An explicit `timeout` in the call wins, including zero.
`task.defaults {}` clears the default. Each call replaces the preceding
defaults; only `timeout` is accepted, and a malformed duration or unknown key
raises `TASK badvalue` without changing the preceding setting. Settings are
copied, so later changes to the declaration table do not alter the default.
This bounds each child, not the whole task or its dependency plan; use
`sched.deadline` for a scope containing several waits.

`task.exec` runs a child on kuu's own console, so its output streams through
as it happens; under `--json` it streams to standard error instead. It takes
the same table as `proc.run` (`cwd`, `env`, `timeout`, `maxout`, `limits`)
and returns `true`, or `nil, err` with `TASK exit` and the child's code in
`err.exit`, which `kuu run` then uses as its own exit code. A child that timed
out, was killed, or hit a job limit is `TASK failed`. The caller's argv and
options table is never modified, in either console or JSON mode.
The `limits` table has `memory` (bytes or a size string), `cpu` (seconds or
a duration string), and `processes` (a positive count); see
[proc limits](proc.md). To capture output instead, use
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
child is streamed to standard error as it arrives, whatever `inherit` the
task asked for, with no cap on its size. Only a direct `io.stdout:write`
bypasses this, and then the task itself has broken the contract.

```json
{"ok":true,"result":{"root":"C:/work/app","task":"test",
  "tasks":[{"name":"gen","seconds":0.01,"ok":true},{"name":"build","seconds":3.2,"ok":true},{"name":"test","seconds":0.8,"ok":true}]}}
```

These structural schemas use `?` for an omitted optional field. Arrays are
present even when empty; a field is never replaced with `null` merely because
it is optional.

```typescript
type RunError = { domain: string; code: string; message: string; exit?: number };
type TaskRun = { name: string; seconds: number; ok: boolean };
type RunReport =
  | { ok: true; result: { root: string; task: string; tasks: TaskRun[] } }
  | { ok: false; result: { root?: string; task?: string; tasks: TaskRun[] };
      error: RunError };
type DryRunReport = {
  ok: true;
  result: { root: string; task: string;
    plan: { name: string; desc: string; deps: string[] }[] };
};
```

`root` is absolute. `tasks` lists completed attempts in execution order,
including the failed task; it is empty for a failure before execution.
Failure fields `root`, `task`, and `error.exit` appear only when supplied by
that failure path. The process exits as in the table above even when
`error.exit` is absent. A successful `--dry-run --json` produces
`DryRunReport`; its failure uses the failed `RunReport` shape. A dry run
still loads declarations and validates every task's arguments.

`kuu list --json` uses this schema. It includes hidden tasks, marked with
`hidden: true`; only the human-readable listing omits them.

```typescript
type TaskArgument = {
  name: string; type: "flag" | "string" | "int" | "number" | "duration" | "size";
  help: string; required: boolean; rest: boolean;
  default?: unknown; choices?: unknown[];
};
type ListReport =
  | { ok: true; result: { root: string; default?: string; tasks: {
      name: string; desc: string; deps: string[]; hidden: boolean;
      args: TaskArgument[];
    }[] } }
  | { ok: false; error: { domain: string; code: string; message: string } };
```

The `default` task name is omitted when none is declared. Arguments carry
their declared default and choices, not parsed values; bounds such as
`min` and `max` are not included. `tasks.lua` must keep its top level quiet
for `list --json` because that verb does not redirect declaration output.
Malformed command-line options are rejected with a diagnostic on stderr
before either verb builds a JSON report. `--help` before the task name
prints usage and exits 0; task-specific `--help` is a `CLI usage` failure.

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
| `TASK usage` | no task or default was selected, or a runner option is unknown |
| `TASK unknown`, `TASK cycle` | the dependency graph |
| `CLI usage` | wrong arguments for a task, or `--help` |
| `TASK failed` | a task raised something that is not an `err`, or its child did not exit normally |
| `TASK exit` | a `task.exec` child exited non-zero; `err.exit` is the code |

Errors returned or raised by `proc` while starting a child keep their
original domain and code; [proc](proc.md) lists them. A job limit produces
`TASK failed` with its kind in the message, such as `limit (memory)`.
