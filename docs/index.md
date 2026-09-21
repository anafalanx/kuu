# kuu

kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
runs a Lua program and gives it native control over processes, files, the
network, services, and event logs. It is built for agents, so the manual is short
and exact: this is how kuu behaves, not how Lua works. Lua 5.5 itself is
assumed; the one page you need about the language here is
[Pitfalls](pitfalls.md).

If you are an agent working in a project that runs through kuu, [For the
agent](agent.md) says what is expected of you and how to report back. Read
it first, then Pitfalls once.

For a project that previously used signed 0.11, read
[Upgrading from 0.11](upgrading-from-0.11.md) before running project tasks:
`kuu docs upgrading-from-0.11`. It explains the execution-history contract,
inspection defaults and the project instructions that need review.

kuu runs on Windows 11 version 23H2 and later, and Windows Server 2025 and
later. The runtime uses native Windows process, console and filesystem APIs.
Console shutdown adapts to the older 23H2 lifetime contract; the Lua API is
the same on every supported version.

This is version 0.12: the runner, the scheduler with scoped deadlines,
processes with resource limits (its own children and the others on the machine), files, JSON, CSV, INI, HTTP, archives,
hashing, text encodings, regular expressions, time, logging, argument
parsing, a repository's tasks and the tools they call, declared once in
`manifest.lua`, a ledger of every crossing, a memory across runs, the
machine's own facts, the registry, the environment, services, event logs,
signature verification, and the network as seen from here. The provisional
`pty` drives interactive console programs; `check` reads what can be known
without running; `capabilities` says what is here, and the manual — this
page, [the conduct expected of an agent](agent.md), every module — is
inside the executable. It is the tool an agent holds on a Windows machine
instead of PowerShell; the [From PowerShell](powershell.md) page maps one
to the other.

kuu is the front door of a project: run repeated operations as tasks with
`kuu run`, and their children with `task.exec`, to record them in the ledger.
Children run in jobs with the timeouts and limits the calls specify. If
something cannot be done from here, build a [tool](tools.md) for it, in any
technology, and call it through the door. Editing is yours; running is the
door's. The
[roadmap](roadmap.md) records what is planned and why, and
[inheritance](inheritance.md) records what kuu learned from its predecessors.

## Running a program

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

`kuu -e` gives an immediate query the same modules as a program file, without
requiring a manifest. For example, from PowerShell:

```powershell
.\kuu.exe -e "print(require('json').encode(require('sys').info()))"
```

This prints the machine's facts as JSON. Use `print` to emit results; encode
tables with `json.encode`. Arguments after the script are available as `...`
and `rt.args`. The [agent guide](agent.md#try-an-inline-command) has more examples
and the commands to find an API's documentation. Repeated work becomes a task.

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
-- 0.12  Lua 5.5.1  file  C:\work\app\kuu.exe  build.lua  2
rt.version_at_least(0, 12)  -- true: this runtime is 0.12 or newer
```

`rt.route` is `"file"`, `"stdin"`, `"eval"`, or `"cmd"` for a verb such as
`run`. `rt.program` is the path as given for the file route, the verb for the
cmd route, and nil otherwise. `rt.root([dir])` reads or moves the directory
`require` searches after kuu's own modules; `rt.source(name)` is the text of
one of kuu's own Lua modules. `rt.verbs()` and `rt.pages()` are the verbs this
executable answers to and the manual's pages, both sorted; they are carried in
the executable where nothing else can see them, and
[capabilities](capabilities.md) reports them. `rt.page(name)` is the text of
one manual page, or nil for a name that is not one, so a program with no
shell reads the manual the way `kuu docs` does.

## Modules

A program gets capabilities by naming them: `require` is the gate. A Lua file
that requires nothing has only what stock Lua's `io` and `os` give it: files
by path, the environment, the clock, and exit. Processes, the network,
hashing, and every other organ are behind `require`.

| module | gives |
|---|---|
| [`proc`](proc.md) | children with decided lifetimes and resource limits: run, start, wait, kill, detach; the other processes: list, find, tree |
| [`fs`](fs.md) | files, directories, attributes, identity, links, walks, watches, with Windows truth |
| [`http`](http.md) | fetch and post over WinHTTP, with the machine's proxy and certificates |
| [`sched`](sched.md) | tasks, sleep, a monotonic clock, wall time, scoped deadlines |
| [`json`](json.md) | strict decoding and exact encoding |
| [`hash`](hash.md) | digests, HMAC, random bytes |
| [`text`](text.md) | strict conversion between UTF-8 and Windows encodings |
| [`log`](log.md) | structured lines that never interrupt the work |
| [`cli`](cli.md) | a program's arguments, declared once |
| [`err`](err.md) | the one error shape and how to test it |
| [`task`](task.md) | a repository's tasks and default child timeout, declared once in `manifest.lua`, run by `kuu run` |
| [`check`](check.md) | syntax, global declarations, require resolution, and palette names without running project code |
| [`archive`](archive.md) | zip and tar archives through the tar.exe Windows ships |
| [`sys`](sys.md) | facts about this machine and process, embedded Authenticode signatures |
| [`svc`](svc.md) | inspect, start, stop, restart, and wait for Windows services |
| [`evt`](evt.md) | read and filter Windows event logs |
| [`pty`](pty.md) | interactive console children and Lua-pattern expect; provisional |
| [`mem`](mem.md) | a small memory across runs, one JSON file per project |
| [`sync`](sync.md) | one at a time across processes: a named lock |
| [`re`](re.md) | regular expressions on PCRE2, with Unicode and named groups |
| [`time`](time.md) | instants, zones, ISO 8601, durations |
| [`net`](net.md) | the network from here: resolve, probe, listeners, addresses |
| [`csv`](csv.md) | comma-separated values, RFC 4180 and the Windows variants |
| [`ini`](ini.md) | INI files: read, write, and edit in place |
| [`reg`](reg.md) | the registry, typed |
| [`env`](env.md) | environment variables, live and persisted |
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
`badvalue`, `toobig`, `encoding`, `stdin`, and `oserror`. A first argument
that is neither a verb nor an existing file — a verb misspelt, most often —
is `ENTRY notfound` naming both and where the verbs are listed; a name with
a dot or a separator in it is looked for as a file only.

## The manual, from inside the executable

```text
kuu docs                      the pages, each with its first sentence, and where to start
kuu docs PAGE                 one page, the text of docs/PAGE.md
kuu docs PAGE SECTION         one ## section of it, by its heading or its anchor; PAGE#anchor is the same
kuu docs search TEXT ...      every line mentioning the words, joined by spaces, matched literally, ignoring case
kuu docs --json ...           the same three, as one envelope
```

`kuu docs` is a verb like the others: `--help` prints its usage, an unknown
option or a surplus word is `CLI usage`, exit 2, a page that is not there is
`ENTRY notfound`, exit 2, pointing at the list, and a section that is not
there is the same, naming the sections there are. A section is named by its
heading, whole or as a prefix, ignoring case, or by its anchor — GitHub's
spelling, the one the manual's own links use: lower case, punctuation
dropped, spaces to dashes — and `kuu docs sched deadlines` and `kuu docs
sched#deadlines` print the same. A heading inside a fenced code block is
text, not a section. Every module page heads its code set `## Errors`, so
`kuu docs MODULE errors` is the code table of any module. Search hits are
`page:line: text`, one per line, grouped with a `Read: kuu docs PAGE SECTION`
command for their surrounding section (or `Read: kuu docs PAGE` for a page's
introduction). The JSON search shape is unchanged. A search that finds nothing says so and
exits 0, and one given no text, or only blank text, is `ENTRY usage`.

```typescript
type DocsList = { ok: true; result: { version: string;
  pages: { name: string; description: string; lines: number }[] } }; // description: the page's first sentence
type DocsPage = { ok: true; result: { name: string; lines: number; text: string;
  sections: { heading: string; anchor: string; line: number }[] } };
type DocsSection = { ok: true; result: { name: string; heading: string; anchor: string; line: number; text: string } };
type DocsSearch = { ok: true; result: { text: string;
  hits: { page: string; line: number; heading?: string; text: string }[] } }; // heading: the nearest one above the hit
```

## Pages

- [For the agent](agent.md): what is expected of an agent in a project that
  runs through kuu, and the report it writes back in `kuu-eval.md`. Read
  first.
- [From PowerShell](powershell.md): each cmdlet an agent reaches for, and the
  kuu call that replaces it.
- [Pitfalls](pitfalls.md): what differs from the Lua an agent already knows,
  and the Windows facts kuu refuses to hide.
- [Adopting kuu](adopting.md): a repository gets its own kuu.exe, a
  manifest.lua, and prerequisites by hash; nothing on the machine.
- [capabilities](capabilities.md): what a program can reach from here -- the
  verbs, the palette, and this project's tasks and modules, in one command;
  provisional.
- [Cookbook](cookbook.md): fourteen complete programs for common automation
  jobs, the last four shaped by the front door.
- [Bounded publication and cleanup](cleanup.md): retry Windows denials within
  a project budget, publish validated staging, and retain both failure causes.
- [Process recipes](process-recipes.md): serialize command descriptions,
  classify child outcomes and preserve captured diagnostics.
- [Working directories](working-directories.md): preserve the caller's directory
  and exact arguments through a wrapper, a task and a child process.
- [Project environment](project-environment.md): share root-derived cache paths
  between command-line tools and newly launched editors.
- [Relocation and health checks](relocation.md): move a checkout, rebuild local
  environments, and inspect dependencies without provisioning them.
- [Detached editors and GUI verification](editor.md): use fresh profiles and
  a bounded native probe on a private desktop, with explicit readiness checks.
- [Native helper and shortcut](native-helper.md): cache a helper by verified
  build inputs and regenerate a local shortcut after moving the project.
- [Reconstruction and publication recovery](reconstruction.md): verify cached
  restores and independent backups, and reconcile uncertain upload outcomes.
- [Stability](stability.md): the future 1.x contract and minimum-version guards.
- [Upgrading from 0.11](upgrading-from-0.11.md): the migration checklist for
  0.12, execution history, inspection policy and new APIs.
- [Upgrading to 0.11](upgrading-0.11.md): N.N version numbers, corrections and
  behavior changes since 0.10.0, and the shorter route to an inline command.
- [proc](proc.md), [fs](fs.md), [http](http.md), [net](net.md),
  [sched](sched.md), [json](json.md), [csv](csv.md), [ini](ini.md),
  [re](re.md), [time](time.md), [hash](hash.md), [text](text.md),
  [reg](reg.md), [env](env.md), [sys](sys.md), [svc](svc.md), [evt](evt.md),
  [pty](pty.md), [sync](sync.md),
  [mem](mem.md), [archive](archive.md), [log](log.md), [cli](cli.md),
  [err](err.md): the modules.
- [Tasks](task.md): `manifest.lua`, `kuu run`, `kuu list`, and the exit codes.
- [Tools](tools.md): the programs a project builds or fetches, declared in the
  manifest and called through the door.
- [Confined tools](confined.md): what a tool that confines itself must
  provide, and the junction every lexical sandbox has to be told about.
- [The ledger](ledger.md): what `kuu run` remembers of every crossing, under
  `.kuu/ledger`, chained and kept ninety days.
- [check](check.md): what `kuu check` finds without running a file.
- [Scan configuration](scan.md): `kuu.config.json` controls shared project
  inspection for checking and module inventory, with validated exclusions and
  safe traversal.
- [Toolchain](toolchain.md): what kuu's own `.tools` holds and where it comes
  from.
- [Upgrading to 0.10](upgrading-0.10.md): no call moves, but `check` reports
  four mistakes it used to pass and reads a project's own modules, so a green
  project can turn red without changing. `check --fix`, `capabilities`, and
  `text.trim`.
- [Upgrading to 0.9](upgrading-0.9.md): the version grows a patch component,
  which breaks the old pattern guard; `rt.version_at_least` replaces it. The atomic
  write retries its rename, and three modules leave the planned freeze.
- [Upgrading to 0.8](upgrading-0.8.md): Windows 11 23H2 support and the JSON
  duplicate-key diagnostic fix, with the same Lua API.
- [Upgrading to 0.7](upgrading-0.7.md): deadlines, child limits, services,
  signatures, event logs, name checking, and provisional pty.
- [Upgrading to 0.6](upgrading-0.6.md): duration units and adoption fixes.
- [Observed shortcomings](shortcomings.md): reproductions, fixes, and external limitations.
- [Roadmap](roadmap.md): decisions taken and milestones ahead.
- [Inheritance](inheritance.md): laws, traps, and contracts carried over from
  machteld, the z estate, and the archived projects.
