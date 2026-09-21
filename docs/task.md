# Tasks

A repository declares its tasks once, in a `manifest.lua` at its root, and runs
them with `kuu run`. There is no second file to keep in step: the task list,
each task's description, its dependencies, and its arguments live in the
declaration, and `kuu list` reads them back from there. The same file
declares the [tools](tools.md) the tasks call.

```lua
-- manifest.lua
global none
global <const> require
local task = require "task"
local fs = require "fs"

task.defaults { timeout = "10m" }

task.tool "zig" { exe = ".tools/zig/zig.exe", args = { build = "flag", ["-Doptimize"] = "string" } }
task.tool "app" { exe = "build/app.exe", args = { ["--self-test"] = "flag" } }

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
    return task.exec { tool = "zig", "build", opts.release and "-Doptimize=ReleaseFast" or "-Doptimize=Debug" }
  end,
}

task "test" {
  desc = "run the suite",
  deps = { "build" },
  run = function() return task.exec { tool = "app", "--self-test" } end,
}

task.default "build"
```

The programs a task runs are declared as [tools](tools.md) beside the tasks,
and called by name: `check` then holds each call to its declaration, and
`capabilities` lists them. A `task.exec` of a bare program still runs, and
`check` warns that nothing describes it.

```text
kuu run                      the default task, after its dependencies
kuu run test                 test, after build, after gen; each runs once
kuu run build --release      arguments after the task name go to that task
kuu run --json test          the same, as JSON lines on stdout: each event as it happens, the outcome last
kuu run --dry-run test       the plan, in order, arguments checked, nothing run
kuu run --timings test       include phase timings on standard error
kuu list [--json]            the tasks, their descriptions, dependencies, and arguments
```

## Where kuu looks

`kuu run` and `kuu list` walk up from the current directory to the nearest
directory holding `manifest.lua`, make that directory the current directory, and
point `require` at it. A task's relative paths are therefore relative to the
project root wherever the command was typed, children started by a task begin
there, and `require "lib.helper"` in `manifest.lua` reads `lib/helper.lua` of the
project. Without a `manifest.lua` anywhere above, both verbs exit 2 with
`TASK noproject`, naming [Adopting](adopting.md). A manifest that loads and
declares no task is not an empty project by accident: `kuu list`, `kuu run`
and `kuu capabilities` say so and name the declaration's shape and this
page; one whose tasks are all hidden is said to be that, with `kuu list
--json` named. A task the command line names that is not declared is `TASK
unknown` with the nearest declared name suggested, and `kuu list` named; a
`task.default` naming a task the manifest does not declare is the same
code, saying it is the manifest's own mistake.

If a wrapper needs the original caller's directory, capture it before launching
`kuu run` and pass it explicitly. `fs.cwd()` inside the manifest already means
the project root. The [working-directory recipe](working-directories.md) keeps
caller, wrapper, project and child directories distinct without shell quoting.

Before executing the manifest, both verbs read and validate the root's
[`kuu.config.json`](scan.md). Malformed or unreadable configuration is
`SCAN config` and exits 2 before project code runs. An absent file selects the
documented defaults. The configuration controls checking and module inventory;
it does not change task execution or `require` resolution. A normal run does
not scan the project tree or track file changes. The verb's own `--help`
remains available without loading project configuration.

Through 0.9 the file was `tasks.lua`. kuu still finds a `tasks.lua` where no
`manifest.lua` is, reads it as the manifest, and says so on standard error
each time; a directory holding both is read from `manifest.lua` and told
nothing. This fallback is deprecated but remains supported in 0.12, with no
scheduled removal. Rename the file — nothing inside it changes. The earlier
removal date was withdrawn; see [upgrading to 0.11](upgrading-0.11.md).

## Declaring

`task "name" { ... }` takes a name starting with an ASCII letter or digit,
followed by letters, digits, `.`, `_` or `-`, and a table with these attributes.
`task("name", { ... })` is the direct spelling. Tool names follow the same
rule: `g++` is invalid; `cxx` is one possible project-chosen replacement,
not a built-in tool. Anything else is refused at declaration, as is declaring
a name twice.

| attribute | meaning |
|---|---|
| `desc` | description for `kuu list`, and above task usage when requesting help |
| `deps` | a contiguous array of task-name strings to run first, each once, in dependency order; sparse arrays and keyed tables are `TASK badvalue`; a cycle is `TASK cycle` naming the chain, an unknown name is `TASK unknown` saying who needed it |
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

`timeout` is not a task attribute. Set a child timeout on `task.exec`, a
default with `task.defaults`, or a tool timeout on `task.tool`. These limit
child processes; they do not limit the duration of arbitrary Lua task code.
[`kuu check`](check.md) diagnoses statically known declaration mistakes without
executing the manifest. `kuu list` separately loads and validates declarations:
it does not run task bodies or provision tools for a well-structured manifest,
but arbitrary top-level Lua can have effects. A successful list is not proof
that every tool is installed or every task can run.

`task.default "name"` names what `kuu run` alone runs; without it, `kuu run`
alone lists the tasks and exits 2.

`manifest.lua` is an ordinary Lua chunk and its top level runs on every `kuu run`
and `kuu list`, so keep work inside `run` functions. A syntax error or a raise
while declaring is reported with its line and exits 2.

## Running and failing

A task succeeds by returning nothing. It fails by raising, or by returning
`nil, err` — an error of the project's own domain and code, as [err](err.md)
says; a second value that is a string instead is wrapped as `TASK failed`
with that text as the message. The runner prints one line per task on standard error when it
finishes, `kuu: build 1.2s`, and on failure names the task and the error.
Dependencies that already ran are not run again, and nothing after a failed
task runs. Every argument is checked before anything runs: the named task's
against its spec, and each dependency's spec against no arguments. So a
wrong argument, or a dependency that requires an argument, exits 2 with
nothing started. `kuu run TASK --help` prints a non-empty task description
above its usage on standard output and exits 0, including when `args` is
omitted or explicitly `{}`. The selected task's arguments are handled first,
so a dependency that requires an argument does not prevent requesting help.
Task help runs no task/dependency bodies or their children and creates no
ledger records. Loading the manifest's top level still happens, so keep work
inside task bodies.

A task without an `args` schema accepts no arguments or a lone trailing `--`,
just like `args = {}`; real extra arguments are still rejected. Schemas with
rest/forwarded arguments keep ordinary CLI parsing: the first `--` ends option
parsing, and a later `--` is an argument whose value must be preserved.
`kuu run TASK -- --help` asks the task to receive a literal `--help` argument
after CLI option parsing ends. This only works when its schema accepts that
argument and its run function forwards it. It is different from task help:
dependencies and the run function execute, and a child may run and return a
nonzero exit. Task help does not promise a helper program's own help output.

```lua
run = function(opts)
  return task.exec { tool = "gcc", "-O2", "main.c", "-o", "build/app.exe", timeout = "5m" }
end
```

`task.defaults { timeout = "10m" }` gives every `task.exec` a default
child timeout. Without it, and without a `timeout` on the call or on the
tool's declaration, a child has no time bound at all: the job, the limits
and the record are unconditional, the deadline is the manifest's to set. A
duration string uses the same units as `proc`, and a number
is seconds. An explicit `timeout` in the call wins, including zero.
`task.defaults {}` clears the default. Each call replaces the preceding
defaults; only `timeout` is accepted. A malformed duration raises `TASK
badvalue` and an unknown key `TASK usage`, either without changing the
preceding setting. Settings are
copied, so later changes to the declaration table do not alter the default.
This bounds each child, not the whole task or its dependency plan; use
`sched.deadline` for a scope containing several waits.

`task.exec` runs a child on kuu's own console, so its output streams through
as it happens; under `--json` it streams to standard error instead. Both
modes give the child kuu's own standard input, including piped input and
EOF. It takes
the same table as `proc.run` (`cwd`, `env`, `timeout`, `maxout`, `limits`)
and returns `true`, or `nil, err` with `TASK exit` and the child's code in
`err.exit`, which `kuu run` then uses as its own exit code. A child that timed
out, was killed, or hit a job limit is `TASK failed`, with the result's
`status` on the error and, for a limit, which one as `limit`, so a task
branches on `e.status == "timeout"` or `e.limit == "memory"` and never on
the message; the child event of the `--json` stream carries `limit` the
same way. The caller's argv and
options table is never modified, in either console or JSON mode.
The `limits` table has `memory` (bytes or a size string), `cpu` (seconds or
a duration string), and `processes` (a positive count); see
[proc limits](proc.md). When a tool documents successful nonzero exit codes,
accept only the specified codes from `TASK exit`; a timeout or limit failure
must remain a failure. This retains the child's actual outcome in history.
To capture output instead, pass the declared tool's `task.command` result to
[`proc.run`](proc.md), then check status, truncation and exit code. That child
has no individual ledger record; the enclosing task/run still do. The
[process recipes](process-recipes.md) demonstrate both forms.

| exit | meaning |
|---|---|
| 0 | every task returned |
| the child's code | a `task.exec` child exited non-zero |
| 1 | a task raised or returned `nil, err`, without an explicit numeric `err.exit` or `CLI usage` classification |
| 2 | no `manifest.lua`, a broken `manifest.lua`, invalid scan configuration, an unknown task or dependency, a cycle, or wrong arguments; also an in-task `CLI usage` error without an explicit numeric `err.exit` |

An explicit numeric `err.exit` takes precedence. Error objects in events and
reports may omit `exit`; the process exit status and the verb ledger record's
`code` remain authoritative. For example, a task that returns `nil` and a
`CLI usage` error without `exit` produces that error unchanged and exits 2.

## JSON

`kuu run --json` (the flag before the task name) prints a stream on standard
output, one JSON object per line as things happen, and nothing else there
— `--help` excepted, which prints usage as text and no envelope, before or
after the task name, as every `--help` does:
`print` and `io.write` from tasks are redirected to standard error, and the
output of a `task.exec` child is streamed to standard error as it arrives,
whatever `inherit` the task asked for, with no cap on its size. Only a direct
`io.stdout:write` bypasses this, and then the task itself has broken the
contract.

JSON reports replace invalid UTF-8 bytes in messages and descriptions with
U+FFFD, including errors raised while loading the manifest. `list --json`
and `capabilities --json` use the same conversion. Invalid bytes in map keys
are repaired too; if names then coincide, numbered suffixes preserve every
entry in the report.

The lines are events — the run once its plan is checked, each task as it
starts and finishes, each child a task runs through the door — and the last
line is the envelope, which is what the whole output was through 0.9. A
reader that takes the last line sees what it always saw; one that reads
each line sees the run as it goes, which is what a harness watching a long
task needs.

This example is abridged; the complete final-report schema follows it.

```json
{"v":1,"event":"run","root":"C:/work/app","task":"test","plan":["gen","build","test"]}
{"v":1,"event":"task","name":"gen","state":"started"}
{"v":1,"event":"task","name":"gen","state":"finished","ok":true,"seconds":0.01}
{"v":1,"event":"task","name":"build","state":"started"}
{"v":1,"event":"child","task":"build","state":"started","pid":4120,"argv":["C:/work/app/.tools/zig/zig.exe","build"]}
{"v":1,"event":"child","task":"build","state":"finished","pid":4120,"argv":["C:/work/app/.tools/zig/zig.exe","build"],"status":"exit","code":0,"seconds":3.1,"bytes":{"out":8192,"err":0}}
{"v":1,"event":"task","name":"build","state":"finished","ok":true,"seconds":3.2}
{"v":1,"event":"task","name":"test","state":"started"}
{"v":1,"event":"task","name":"test","state":"finished","ok":true,"seconds":0.8}
{"ok":true,"result":{"root":"C:/work/app","task":"test",
  "tasks":[{"name":"gen","seconds":0.01,"ok":true},{"name":"build","seconds":3.2,"ok":true},{"name":"test","seconds":0.8,"ok":true}]}}
```

Every event carries `v`, the stream's schema version, 1; the envelope
carries none and is told apart by `ok`. A failure before the run — no
project, a wrong argument — is the envelope alone. `--dry-run --json` is
one envelope, since nothing runs.

```typescript
type RunEvent =
  | { v: 1; event: "run"; root: string; task: string; plan: string[] }
  | { v: 1; event: "task"; name: string; state: "started" }
  | { v: 1; event: "task"; name: string; state: "finished"; ok: boolean; seconds: number;
      error?: RunError }
  | { v: 1; event: "child"; task: string; state: "started"; pid: number; argv: string[]; tool?: string }
  | { v: 1; event: "child"; task: string; state: "finished"; pid: number; argv: string[]; tool?: string;
      status: "exit" | "timeout" | "killed" | "limit" | "error"; code?: number;
      limit?: "memory" | "cpu" | "processes"; seconds: number;
      bytes: { out: number; err: number } };
```

These structural schemas use `?` for an omitted optional field. Arrays are
present even when empty; a field is never replaced with `null` merely because
it is optional.

```typescript
type RunError = { domain: string; code: string; message: string; exit?: number };
type TaskRun = { name: string; seconds: number; ok: boolean };
type LedgerRun = {
  records: number;
  complete: boolean;
  error?: { message: string; domain?: string; code?: string };
};
type RunTimings = { setup: number; ledger?: number; execution?: number; total: number };
type RunReport =
  | { ok: true; result: { root: string; task: string; tasks: TaskRun[]; notes: string[];
                         timings: RunTimings; ledger?: LedgerRun } }
  | { ok: false; result: { root?: string; task?: string; tasks: TaskRun[]; notes: string[];
                          timings: RunTimings; ledger?: LedgerRun };
      error: RunError };
type DryRunReport = {
  ok: true;
  result: { root: string; task: string;
    plan: { name: string; desc: string; deps: string[] }[]; notes: string[];
    timings: RunTimings };
};
```

`root` is absolute. `tasks` lists completed attempts in execution order,
including the failed task; it is empty for a failure before execution.
`notes` carries what the verb also said on standard error beside the work,
for a reader that sees only the envelope: a `tasks.lua` read as the
manifest, a `.kuu/` created under a root whose `.gitignore` does not list
it. It is empty when there was nothing to say.
Failure fields `root`, `task`, and `error.exit` appear only when supplied by
that failure path. The process exits as in the table above even when
`error.exit` is absent. A successful `--dry-run --json` produces
`DryRunReport`; its failure uses the failed `RunReport` shape. A dry run
still loads declarations and validates every task's arguments.

When ledger opening is attempted, `result.ledger.records` counts records
successfully appended by this invocation; `complete` says whether all attempted crossing
records were written. An opening or recording failure sets it to false and
adds `error`; a failed open has zero records.
Classified errors carry `domain` and `code`; an ordinary Lua exception has
only `message`. Problems also appear in `notes` and leave the task's exit
status unchanged. A preflight failure or dry run has no `result.ledger`.
The [ledger](ledger.md) page describes the history format and its failure
behavior.

Runs do not collect filesystem snapshots or report `scope`, `scans`,
`ledger.observation` or `ledger.publication`. Source inspection has its own
scope and scan reports under [check](check.md) and
[capabilities](capabilities.md).

`result.timings` is always present in these JSON envelopes. `--timings`, before
the task name, also prints one timing line on stderr. After the task name it is
an argument for that task, like other runner options. Values are wall-clock
seconds:

| Phase | Included work |
|---|---|
| `setup` | Command imports, project/configuration discovery, manifest execution, dependency planning and argument validation, before opening the ledger |
| `ledger` | Measured ledger opening and record append work: repository metadata, predecessor reads, hashes, locks, history writes and retention |
| `execution` | The sum of existing task-attempt durations, including nested child work and child observer records |
| `total` | Command work and report preparation through the last history append or its failure |

Phases are diagnostic measurements, not a partition: `ledger` can overlap
`execution` when recording children. Never add child durations to execution
again. Existing task/child `seconds` fields and the ledger's verb duration keep
their previous meanings. The verb duration is captured before appending its
own history record; `total` includes that append and report preparation.

The clock begins just after loading the timing helper, before other command
imports; total ends before final JSON serialization or human-report emission
and flushing. OS/runtime startup and final output can make an external
stopwatch larger without a promised bound. Unavailable phases are omitted,
including on failures. A dry run reports setup and total, with no ledger or
execution phase. Help and runner-option parser exits retain their
existing output conventions and produce no timing line.

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
    }[]; notes: string[] } }
  | { ok: false; error: { domain: string; code: string; message: string } };
```

The `default` task name is omitted when none is declared. Arguments carry
their declared default and choices, not parsed values; bounds such as
`min` and `max` are not included. `manifest.lua` must keep its top level quiet
for `list --json` because that verb does not redirect declaration output.
Malformed command-line options are rejected with a diagnostic on stderr
before either verb builds a JSON report. `--help` before the task name
prints the verb's usage and exits 0, and after it the task's, the same way.

## The module in a program

The same module drives the verbs and is open to programs that build on them.
The registry is the module, so a program that loads a `manifest.lua` with `load`
after `require "task"` sees its declarations.

```lua
local task = require "task"
task.all()                 -- the declared tasks, in declaration order
task.get("build")          -- one entry: name, desc, deps, args, run, hidden
task.default_task()        -- the default's name, or nil
task.plan("test")             -- the entries to run, in order | nil, err
task.arguments(entry, args)   -- the arguments parsed against its spec: opts | nil, err
task.execute(entry, opts)     -- run it with parsed arguments: true | nil, err
task.tools()                  -- the declared tools, in declaration order
task.tool_get("report")       -- one: name, exe, args, output, emits, timeout, reach
task.command { tool = "report", "--out", p }   -- the table task.exec would run, resolved
```

The tools a manifest declares with `task.tool "name" { ... }`, and
`task.exec { tool = "name", ... }`, are on their own page: [Tools](tools.md).

| code | meaning |
|---|---|
| `TASK noproject` | no `manifest.lua` here or above; the message names `kuu docs adopting` |
| `TASK badvalue` | a bad declaration, or `manifest.lua` failed to load |
| `TASK usage` | no task or default was selected — the message says when the manifest declares no task at all — a runner option is unknown, or a declaration holds an attribute or option that is not known |
| `TASK unknown`, `TASK cycle` | the dependency graph; `unknown` for the task the command named suggests the nearest declared one and names `kuu list`, and is also a tool the manifest does not declare |
| `CLI usage` | wrong arguments for a task |
| `SCAN config` | malformed or unreadable root `kuu.config.json`; the message identifies the configuration field or read failure, before manifest execution |
| `TASK failed` | a task raised something that is not an `err`, returned `nil` with a string instead of an `err`, or its child did not exit normally — `status` and `limit` on the error say how |
| `TASK exit` | a `task.exec` child exited non-zero; `err.exit` is the code |

Errors returned or raised by `proc` while starting a child keep their
original domain and code; [proc](proc.md) lists them. A job limit produces
`TASK failed` with its kind in the message, such as `limit (memory)`.
