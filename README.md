# kuu

A Lua 5.5 runtime for agents on Windows. One static executable runs a Lua
program and, milestone by milestone, gives it correct native control over
processes, files, and the network. Kuu is Finnish for moon, as Lua is
Portuguese for it.

Version 0.1.0 is the runner: it runs programs and nothing else yet.

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu --version | --help
```

The manual starts at [docs/index.md](docs/index.md). Agents should read
[docs/lua-in-kuu.md](docs/lua-in-kuu.md) once; it is the only page about the
language. [docs/roadmap.md](docs/roadmap.md) records the decisions.

## Building

The project stands alone. Its compiler lives in `.tools/`, which is not in
the repository; [docs/toolchain.md](docs/toolchain.md) says what goes there.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File test/entry_test.ps1
```

The build produces `build/kuu.exe`; the tests run it as a child process and
compare bytes.

## Layout

| path | holds |
|---|---|
| `src/` | the host, C23 under the els method's warning set |
| `vendor/lua-5.5.1/` | PUC Lua 5.5.1 as released, compiled as C |
| `lua/` | kuu's own Lua, from the palette milestone on |
| `docs/` | the manual, shipped inside the executable later |
| `test/` | the entry suite and its fixtures |
| `tools/` | the stage-zero build |
| `.tools/` | the compiler, local to this checkout |

## License

Apache License 2.0; see [LICENSE](LICENSE). Lua is MIT-licensed by
Lua.org, PUC-Rio; see `vendor/lua-5.5.1/doc/readme.html`.
