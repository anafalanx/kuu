# kuu

kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
runs a Lua program and gives it correct native control over processes, and, as
it grows, files and the network. It is built for agents, so the manual is short
and exact: this is how kuu behaves, not how Lua works. Lua 5.5 itself is
assumed; the one page you need about the language here is
[Pitfalls](pitfalls.md).

kuu runs on Windows 11 version 25H2 and later, and on the equivalent Windows
Server releases. Nothing else, on purpose: the process, console, and file
system features it builds on are used without fallbacks.

This is version 0.4: the runner, the scheduler, processes, files, JSON, HTTP,
archives, hashing, text encodings, logging, argument parsing, a repository's
tasks, a memory across runs, and the machine's own facts. It is the tool an
agent holds on a Windows machine instead of PowerShell; the
[From PowerShell](powershell.md) page maps one to the other. The
[roadmap](roadmap.md) records what is planned and why, and
[inheritance](inheritance.md) records what kuu learned from its predecessors.

## Running a program

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu docs [PAGE | search TEXT]   this manual, from inside the executable
kuu run [--json] [--dry-run] [TASK [arg ...]]   a task from the nearest tasks.lua      (see Tasks)
kuu list [--json]         those tasks
kuu check [--json] [PATH ...]   parse, global declarations, requires, without running  (see check)
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
-- 0.4  Lua 5.5.1  file  C:\work\app\.tools\kuu.exe  build.lua  2
```

`rt.route` is `"file"`, `"stdin"`, `"eval"`, or `"cmd"` for a verb such as
`run`. `rt.program` is the path as given for the file route, the verb for the
cmd route, and nil otherwise. `rt.root([dir])` reads or moves the directory
`require` searches after kuu's own modules; `rt.source(name)` is the text of
one of kuu's own Lua modules.

## Modules

A program gets capabilities by naming them: `require` is the gate. A Lua file
that requires nothing has only what stock Lua's `io` and `os` give it: files
by path, the environment, the clock, and exit. Processes, the network,
hashing, and every other organ are behind `require`.

| module | gives |
|---|---|
| [`proc`](proc.md) | children with decided lifetimes: run, start, wait, kill, detach; the other processes: list, find, tree |
| [`fs`](fs.md) | files, directories, identity, links, walks, watches, with Windows truth |
| [`http`](http.md) | fetch and post over WinHTTP, with the machine's proxy and certificates |
| [`sched`](sched.md) | tasks, sleep, a monotonic clock, wall time |
| [`json`](json.md) | strict decoding and exact encoding |
| [`hash`](hash.md) | digests, HMAC, random bytes |
| [`text`](text.md) | strict conversion between UTF-8 and Windows encodings |
| [`log`](log.md) | structured lines that never interrupt the work |
| [`cli`](cli.md) | a program's arguments, declared once |
| [`err`](err.md) | the one error shape and how to test it |
| [`task`](task.md) | a repository's tasks, declared once in `tasks.lua`, run by `kuu run` |
| [`archive`](archive.md) | zip and tar archives through the tar.exe Windows ships |
| [`sys`](sys.md) | facts about this machine and this process |
| [`mem`](mem.md) | a small memory across runs, one JSON file per project |
| [`sync`](sync.md) | one at a time across processes: a named lock |
| [`re`](re.md) | regular expressions on PCRE2, with Unicode and named groups |
| [`time`](time.md) | instants, zones, ISO 8601, durations |
| [`net`](net.md) | the network from here: resolve, probe, listeners, addresses |
| `rt` | the launch: version, executable, route, program, arguments, the require root |

`require` searches `package.preload`, where these live, and then the program's
directory: `require("a.b")` tries `a/b.lua`, then `a/b/init.lua`, below the
directory of the program file, or below the current directory for the stdin
and inline routes. Module files follow the same decoding rules as programs.
Environment variables such as `LUA_PATH` are never consulted and C modules are
never loaded; `package.path` and `package.cpath` are empty strings to make that
visible.

## Output and input

Standard input, output, and error are binary. What a program writes with
`print`, `io.write`, or `io.stderr:write` leaves the process byte for byte, with
no CRLF translation and no re-encoding. Text is UTF-8 by convention, and the
C runtime's file functions (`io.open`) and `os.getenv` take and return UTF-8.
A terminal set to another code page will show UTF-8 bytes wrongly; a pipe will
not.

## Errors and exit codes

An uncaught error prints one line, `kuu: message`, followed by the stack
traceback, on standard error, and exits with code 1. Error objects with a
`__tostring` metamethod are rendered through it; other non-string objects are
named by type. Pending to-be-closed variables (`local x <close> = ...`) are
closed before exit, whether the program finished or failed.

| exit | meaning |
|---|---|
| 0 | the program finished |
| 1 | the program failed: a syntax error, an uncaught error, a stray yield, a deadlock |
| 2 | kuu did not start the program: usage, a missing or unreadable file, invalid UTF-8, or a program over 16 MiB |
| 3 | kuu itself crashed: a structured exception was caught, named with its address on standard error, and is a defect in kuu; `kuu --crash-test` exercises the handler |
| other | the program's own `os.exit(n)` |

Failures kuu detects before the program runs are spelled
`kuu: DOMAIN code: message`. The ENTRY codes are `usage`, `notfound`, `access`,
`badvalue`, `toobig`, `encoding`, `stdin`, and `oserror`.

## Pages

- [From PowerShell](powershell.md): each cmdlet an agent reaches for, and the
  kuu call that replaces it.
- [Pitfalls](pitfalls.md): what differs from the Lua an agent already knows,
  and the Windows facts kuu refuses to hide.
- [proc](proc.md), [fs](fs.md), [http](http.md), [sched](sched.md),
  [json](json.md), [hash](hash.md), [text](text.md), [log](log.md),
  [cli](cli.md), [err](err.md): the modules.
- [Tasks](task.md): `tasks.lua`, `kuu run`, `kuu list`, and the exit codes.
- [check](check.md): what `kuu check` finds without running a file.
- [Toolchain](toolchain.md): what kuu's own `.tools` holds and where it comes
  from.
- [Roadmap](roadmap.md): decisions taken and milestones ahead.
- [Inheritance](inheritance.md): laws, traps, and contracts carried over from
  machteld, the z estate, and the archived projects.
