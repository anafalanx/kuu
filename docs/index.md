# kuu

kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
runs a Lua program and, as it grows, gives that program correct native control
over processes, files, and the network. It is built for agents, so the manual is
short and exact: this is how kuu behaves, not how Lua works. Lua 5.5 itself is
assumed; the one page you need about the language here is
[Lua in kuu](lua-in-kuu.md).

This is version 0.1.0, the first milestone: the runtime runs programs and
nothing else yet. The [roadmap](roadmap.md) records what is planned and why.

## Running a program

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu --version | --help
```

A program file is UTF-8, optionally with a BOM, with any line ending. The bytes
must be valid UTF-8; kuu refuses an invalid file rather than repairing it. A
first line beginning with `#` is skipped, so shebang lines and editor tags are
allowed and line numbers in error messages stay right. Programs are bounded at
16 MiB.

Arguments after the program reach the main chunk as `...` and as the `args`
array of the `rt` module. There is no `arg` global.

```lua
local rt = require("rt")
print(rt.version, rt.lua, rt.route, rt.exe, rt.program, #rt.args)
-- 0.1.0  Lua 5.5.1  file  C:\tools\kuu.exe  build.lua  2
```

`rt.route` is `"file"`, `"stdin"`, or `"eval"`. `rt.program` is the path as
given for the file route and nil otherwise.

## Output and input

Standard input, output, and error are binary. What a program writes with
`print`, `io.write`, or `io.stderr:write` leaves the process byte for byte, with
no CRLF translation and no re-encoding. Text is UTF-8 by convention; a terminal
set to another code page will show UTF-8 bytes wrongly, a pipe will not.

## Errors and exit codes

An uncaught error prints one line, `kuu: message`, followed by the stack
traceback, on standard error, and exits with code 1. Error objects with a
`__tostring` metamethod are rendered through it; other non-string objects are
named by type. Pending to-be-closed variables (`local x <close> = ...`) are
closed before exit, whether the program finished or failed.

| exit | meaning |
|---|---|
| 0 | the program finished |
| 1 | the program failed: a syntax error, an uncaught error, or a yield with nothing to wait for |
| 2 | kuu did not start the program: usage, a missing or unreadable file, invalid UTF-8, or a program over 16 MiB |
| other | the program's own `os.exit(n)` |

Failures kuu detects before the program runs are spelled
`kuu: DOMAIN code: message`. The ENTRY codes are `usage`, `notfound`, `access`,
`badvalue`, `toobig`, `encoding`, `stdin`, and `oserror`.

## Modules

`require` searches `package.preload` first, where kuu's own modules live, and
then the program's directory: `require("a.b")` tries `a/b.lua`, then
`a/b/init.lua`, below the directory of the program file, or below the current
directory for the stdin and inline routes. Module files follow the same
decoding rules as programs. Environment variables such as `LUA_PATH` are never
consulted and C modules are never loaded; `package.path` and `package.cpath`
are empty strings to make that visible.

## Pages

- [Lua in kuu](lua-in-kuu.md): what differs from the Lua an agent already knows.
- [Roadmap](roadmap.md): decisions taken and milestones ahead.
- [Toolchain](toolchain.md): what `.tools` holds and where it comes from.
