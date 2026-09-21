# kuu

A Lua 5.5 runtime for agents on Windows. One static executable runs a Lua
program and gives it native control over processes, files, the network,
services, and event logs. Kuu is Finnish for moon, as Lua is
Portuguese for it.

Kuu is the tool an agent holds on a Windows machine instead of
PowerShell: to set up, configure, run, test, script, control, and keep in
check. Programs run as coroutines on one event loop; `proc` gives them
children with decided lifetimes and resource limits under Windows Job Objects and finds the
processes already running; `fs` tells the truth about paths, identity,
junctions, and long names, and watches directories; `http` fetches over
WinHTTP with a deadline of kuu's own; `net` resolves, probes, and lists
listeners and addresses without blocking; `reg` reads and writes the
registry typed; `env` keeps the live and the persisted environment apart;
`re` brings PCRE2, `time` zones and ISO 8601; `archive` unpacks, `sys` knows
the machine, `mem` remembers between runs, `sync` takes turns; `json`, `csv`,
`ini`, `hash`, `text`, `log`, and `cli` round it out. `svc` controls Windows
services, `evt` reads event logs, `sys.signature` checks installers, and the
provisional `pty` drives interactive console prompts. `sched.deadline`
bounds a sequence of waits, and `check` catches misspelled palette exports.
A repository declares its tasks once in `manifest.lua` and runs them with
`kuu run`, and fetches its own prerequisites by url and hash with `http` and
`archive`. The manual rides inside the executable: `kuu docs`. kuu runs on
Windows 11 23H2 and later, and Windows Server 2025 and later, only.

Version 0.12 focuses the ledger on execution history, adds Windows file
attribute operations, and improves project inspection, declaration checks and
task help. Its manual includes tested recipes for processes, environments,
relocation, native helpers and recovery. Versions retain the two natural-number
components (`N.N`) introduced in 0.11.

A project runs through `kuu.exe`. `manifest.lua` declares the tasks and the tools they
call, every crossing is recorded in a ledger under `.kuu/`, `kuu run --json`
is a stream, and the executable explains itself — `kuu docs agent` states
what is expected of an agent and asks it to report back, `kuu docs` serves
sections and searches, and every verb points onward when a next step is
needed. An unknown option is refused everywhere, and `check` reports what
can be known without running, a project's own modules included. See
[upgrading to 0.10](docs/upgrading-0.10.md).

Normal
task runs no longer scan the project tree or track file changes; source
inspection remains available through checking and module inventory, with
configurable exclusions. Existing 0.11 projects should read
[Upgrading from 0.11](docs/upgrading-from-0.11.md), also available offline as
`kuu docs upgrading-from-0.11`, before running tasks with the replacement.

<!-- usage -->
```text
usage: kuu FILE [arg ...]        run a Lua program file
       kuu - [arg ...]           run a program read from standard input
       kuu -e SCRIPT [arg ...]   run an inline script
       kuu docs [--json] [PAGE [SECTION] | search TEXT ...]   the manual, from inside the executable
       kuu run [--json] [--dry-run] [--timings] [TASK [arg ...]]   a task from the nearest manifest.lua
       kuu list [--json]         those tasks
       kuu check [--json] [--timings] [--fix [--adopt]] [PATH ...]   syntax, globals, requires, palette names, without running
       kuu capabilities [--json] [--timings]   what a program can reach from here, and what to read
       kuu version | --version | --help

Try a query now: all modules are available with -e; no file or manifest is needed.
  kuu -e "print(require('json').encode(require('sys').info()))"
Find an API: kuu docs search fs.read; read its section: kuu docs fs reading-and-writing
kuu docs agent shows how to begin; then pitfalls, once; kuu docs index is the map.
From signed 0.11: read kuu docs upgrading-from-0.11 before running project tasks.
```
<!-- /usage -->

```lua
global none
global <const> require, assert
local proc, fs, json = require("proc"), require("fs"), require("json")
local rt = require "rt"
local r = assert(proc.run { rt.exe, "--version", timeout = "5s",
  limits = { memory = "128M", cpu = "2s", processes = 1 } })
assert(r.status == "exit" and r.code == 0, "child failed")
assert(fs.mkdir("build"))
assert(fs.write("build/status.json", json.encode { version = r.out }))
```

The manual starts at [docs/index.md](docs/index.md). An agent working in a
project reads [docs/agent.md](docs/agent.md) first — what is expected of it,
and how it reports back in the project's `kuu-eval.md` — and
[docs/pitfalls.md](docs/pitfalls.md) once; that is the only page about the
language. [docs/powershell.md](docs/powershell.md) maps each PowerShell habit
to the kuu call that replaces it. [docs/roadmap.md](docs/roadmap.md) records the decisions.
[docs/shortcomings.md](docs/shortcomings.md) tracks problems observed during
real repository adoption, with evidence and workarounds.

The [cookbook](docs/cookbook.md) holds fourteen complete programs, the last
four shaped by the front door, and the [stability statement](docs/stability.md)
the future compatibility promise; the upgrading pages, from
[0.11 to 0.12](docs/upgrading-from-0.11.md) back to [0.6](docs/upgrading-0.6.md), say what
each release changed and what a project must do.

## Building

The project stands alone. Its compiler and GNU make live in `.tools/`, which is
not in the repository; [docs/toolchain.md](docs/toolchain.md) says what goes
there. Nothing in the repository runs kuu to build kuu.

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8
```

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe test
```

The build produces `build/kuu.exe`; the tests are Lua, run by the built kuu,
which spawns itself as a child and compares bytes.
`make gate` combines the suite, Clang's AddressSanitizer build and tests,
GCC analysis, deterministic parser fuzzing, and the soak test. `make asan`
runs the sanitizer stage independently. [Toolchain](docs/toolchain.md#verification)
documents the targets, pinned compiler packages, and replaying a seed.

## Layout

| path | holds |
|---|---|
| `src/` | the host, C23 under the els method's warning set |
| `vendor/lua-5.5.1/` | PUC Lua 5.5.1 as released, compiled as C |
| `lua/` | kuu's Lua modules and native-module helpers, plus the verbs under `lua/cmd/` |
| `docs/` | the manual, shipped inside the executable |
| `notes/` | dated handoff documents between the owner's machines; not shipped |
| `test/` | the Lua test suite: `run.lua`, `cases/`, `fixtures/` |
| `Makefile` | the build |
| `.tools/` | the compiler and make, local to this checkout |

## License

Apache License 2.0; see [LICENSE](LICENSE). Lua is MIT-licensed by
Lua.org, PUC-Rio; see `vendor/lua-5.5.1/doc/readme.html`. yyjson is MIT, in
`vendor/yyjson-0.12.0`. PCRE2 is BSD-3-Clause with the PCRE2 exception; see
`vendor/pcre2-10.48/LICENCE.md` and `vendor/pcre2-10.48/README-kuu.md` for
what was taken and what was configured.
