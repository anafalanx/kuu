# kuu

A Lua 5.5 runtime for agents on Windows. One static executable runs a Lua
program and, milestone by milestone, gives it correct native control over
processes, files, and the network. Kuu is Finnish for moon, as Lua is
Portuguese for it.

Kuu is the tool an agent holds on a Windows machine instead of
PowerShell: to set up, configure, run, test, script, control, and keep in
check. Programs run as coroutines on one event loop; `proc` gives them
children with decided lifetimes under Windows Job Objects and finds the
processes already running; `fs` tells the truth about paths, identity,
junctions, and long names, and watches directories; `http` fetches over
WinHTTP with a deadline of kuu's own; `net` resolves, probes, and lists
listeners and addresses without blocking; `reg` reads and writes the
registry typed; `env` keeps the live and the persisted environment apart;
`re` brings PCRE2, `time` zones and ISO 8601; `archive` unpacks, `sys` knows
the machine, `mem` remembers between runs, `sync` takes turns; `json`, `csv`,
`ini`, `hash`, `text`, `log`, and `cli` round it out.
A repository declares its tasks once in `tasks.lua` and runs them with
`kuu run`, and fetches its own prerequisites by url and hash with `http` and
`archive`. The manual rides inside the executable: `kuu docs`. kuu runs on
Windows 11 25H2 and later, and the equivalent Windows Server releases, only.

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu run [TASK [arg ...]]  a task from the nearest tasks.lua
kuu list [--json]         those tasks
kuu check [PATH ...]      parse, global declarations, requires, without running
kuu docs [PAGE | search TEXT]   the manual
kuu version | --version | --help
```

```lua
global none
global <const> require, print
local proc, fs, json = require("proc"), require("fs"), require("json")
local r = proc.run { "git", "status", "--short", timeout = "30s" }
if r.status == "exit" and r.code == 0 then
  fs.write("build/status.json", json.encode { lines = r.out })
end
```

The manual starts at [docs/index.md](docs/index.md). Agents should read
[docs/pitfalls.md](docs/pitfalls.md) once; it is the only page about the
language. [docs/powershell.md](docs/powershell.md) maps each PowerShell habit
to the kuu call that replaces it. [docs/roadmap.md](docs/roadmap.md) records the decisions.
[docs/shortcomings.md](docs/shortcomings.md) tracks problems observed during
real repository adoption, with evidence and workarounds.

The local 0.6 development version fixes issues observed during repository
adoption. CLI durations now use seconds throughout; see
[upgrading to 0.6](docs/upgrading-0.6.md) for the API changes from published 0.5.

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
The same make command accepts `analyze` for GCC static analysis and `fuzz`
for deterministic parser checks; [toolchain](docs/toolchain.md#verification)
documents the gates and how to replay a seed.

## Layout

| path | holds |
|---|---|
| `src/` | the host, C23 under the els method's warning set |
| `vendor/lua-5.5.1/` | PUC Lua 5.5.1 as released, compiled as C |
| `lua/` | kuu's own Lua: `log`, `cli`, `task`, `project`, `archive`, `check`, and the verbs under `lua/cmd/` |
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
