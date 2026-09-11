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
A repository declares its tasks once in `tasks.lua` and runs them with
`kuu run`, and fetches its own prerequisites by url and hash with `http` and
`archive`. The manual rides inside the executable: `kuu docs`. kuu runs on
Windows 11 23H2 and later, and Windows Server 2025 and later, only.

Version 0.9.0 is the last release before the 1.0 freeze, and corrects contracts
while correcting them is still allowed. The version grows a patch component,
which breaks the minimum-version guard published through 0.8: replace it with
`rt.at_least`. `fs.write` now retries its rename, closing an intermittent
`FS access` failure. `svc`, `evt`, and `sys.signature` leave the planned freeze
list until a project has driven them. See
[upgrading to 0.9](docs/upgrading-0.9.md).

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu run [--json] [--dry-run] [TASK [arg ...]]  a task from the nearest tasks.lua
kuu list [--json]         those tasks
kuu check [--json] [PATH ...]  syntax, globals, requires, palette names, without running
kuu docs [PAGE | search TEXT]   the manual
kuu version | --version | --help
```

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

The manual starts at [docs/index.md](docs/index.md). Agents should read
[docs/pitfalls.md](docs/pitfalls.md) once; it is the only page about the
language. [docs/powershell.md](docs/powershell.md) maps each PowerShell habit
to the kuu call that replaces it. [docs/roadmap.md](docs/roadmap.md) records the decisions.
[docs/shortcomings.md](docs/shortcomings.md) tracks problems observed during
real repository adoption, with evidence and workarounds.

Version 0.7 introduced the capabilities before the planned 1.0 freeze. See
[upgrading to 0.7](docs/upgrading-0.7.md) for those changes since 0.6, the
[cookbook](docs/cookbook.md) for ten complete programs, and the
[stability statement](docs/stability.md) for the future compatibility promise.

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
`make gate` combines the suite, GCC analysis, deterministic parser fuzzing,
and the soak test. `make asan` builds and tests with Clang's AddressSanitizer;
it is a separate release check. [Toolchain](docs/toolchain.md#verification)
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
