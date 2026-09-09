# kuu

A Lua 5.5 runtime for agents on Windows. One static executable runs a Lua
program and, milestone by milestone, gives it correct native control over
processes, files, and the network. Kuu is Finnish for moon, as Lua is
Portuguese for it.

Version 0.2 is the palette core: programs run as coroutines on one event loop;
`proc` gives them children with decided lifetimes under Windows Job Objects;
`fs` tells the truth about paths, identity, junctions, and long names, and
watches directories; `json`, `hash`, `text`, `log`, and `cli` round it out.
The manual rides inside the executable: `kuu docs`. kuu runs on Windows 11
25H2 and later, and the equivalent Windows Server releases, only.

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu docs [PAGE | search TEXT]   the manual
kuu --version | --help
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
language. [docs/roadmap.md](docs/roadmap.md) records the decisions.

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

## Layout

| path | holds |
|---|---|
| `src/` | the host, C23 under the els method's warning set |
| `vendor/lua-5.5.1/` | PUC Lua 5.5.1 as released, compiled as C |
| `lua/` | kuu's own Lua, from the palette milestone on |
| `docs/` | the manual, shipped inside the executable later |
| `test/` | the Lua test suite: `run.lua`, `cases/`, `fixtures/` |
| `Makefile` | the build |
| `.tools/` | the compiler and make, local to this checkout |

## License

Apache License 2.0; see [LICENSE](LICENSE). Lua is MIT-licensed by
Lua.org, PUC-Rio; see `vendor/lua-5.5.1/doc/readme.html`.
