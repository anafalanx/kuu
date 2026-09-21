# kuu

This document is the single place where kuu is explained: what the runtime is
today at 0.12 and what was learned building it and its two predecessors. It
exists because that understanding was scattered across three repositories, a
roadmap, an inheritance register, a shortcomings log and a decision record,
and none of those answer the question *why is it like this* in one reading.

kuu is a runtime for Lua 5.5, and only that. It does not define a language,
and it will not: what it grows are capabilities in the palette, and options on
the calls that are already there.

The [stability statement](docs/stability.md) defines the compatibility posture:
0.x contracts can change with documented migration guidance, and the planned
1.0 freeze names its scope and provisional exceptions explicitly.

This file carries the complete manual as **Part III**, so everything kuu knows
about itself can be read in one sitting without querying the executable.

---

## Where things stand

**kuu 0.12 builds on feedback from real projects.** Normal task execution
records history without observing the source tree. Explicit checking and module
inventory share configurable exclusions; Windows file attributes, stronger
declaration checks, consistent task help and tested project recipes complete
the release. Projects moving from signed 0.11 should read
`kuu docs upgrading-from-0.11` before running their tasks with the new runtime.

It is the front-door release: `manifest.lua` declares a project's tasks and
the tools they call, every crossing is recorded in a ledger under `.kuu/`,
`kuu run --json` is a stream, `check` reads what can be known without
running, `capabilities` says what is here, and the executable explains
itself — a page that states what is expected of an agent and asks it to
report back, a `docs` verb like the others, and every verb pointing onward
at the moment a next step is needed.

Versions use two numeric components from 0.11 onward. The intervening 0.9.0
and 0.10.0 used three; guards that parse the old spelling need review.
`rt.version_at_least` compares releases numerically without parsing text, and
`kuu check` identifies obsolete three-component guards.

**What is open** is design, not work in progress. The 1.0 criteria remain the
owner's to set, automatic project observation is outside the runner, and the
intent is to take the time to get the design right and correct course where
needed.

---

## Start here

Parts I and II explain *why*. **Part III is the complete manual**, every page
inlined, so this one file answers both kinds of question and nothing needs to
be fetched before reading. Coming to kuu cold, read in this order:

1. **For the agent** — `kuu docs agent`: what is expected of you in a project
   that runs through kuu, and how to report back. Two minutes.
   On an upgrade from 0.11, also read `kuu docs upgrading-from-0.11` and keep
   the project's `kuu-eval.md` current with dated evidence and follow-ups.
2. **Pitfalls** — the one page an agent's existing Lua knowledge most needs. It
   is the delta between the Lua you know and this runtime, plus the Windows
   facts kuu refuses to hide. Read it once, before writing anything.
3. **Parts I and II**, for why the runtime is shaped as it is.
4. **The rest of Part III**, as reference, when you need a signature.

If you would rather read everything in one pass than navigate, that is what
this file is for: Part III is the whole manual in a deliberate order, beginning
with the map and Pitfalls and ending with the record of decisions.

The same manual also lives inside the executable, where it always matches the
binary in front of you:

```text
kuu docs                       the page list
kuu docs agent                 what is expected of you here
kuu docs fs                    one page
kuu docs proc errors           one section of a page: its error codes
kuu docs search "junction"     find lines across all pages
kuu --help                     the verbs
```

Running, checking, and driving a project:

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

kuu is the front door of a project. Repeated work runs as tasks through
`kuu.exe`; tasks and their `task.exec` children receive execution records.
Child processes run in jobs with the deadlines and limits the calls specify.
For output capture, `task.command` resolves a declared tool for `proc.run`;
the enclosing task remains recorded, but that child has no separate record.
If something cannot be done from
here, the project builds a tool for it, in any technology, declares it in
`manifest.lua`, and calls it through the door. Editing is yours; running is
the door's.

Building and verifying kuu itself, from the repository root:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8       build build/kuu.exe
.tools\msys2\ucrt64\bin\mingw32-make.exe test      the suite
.tools\msys2\ucrt64\bin\mingw32-make.exe gate      test, asan, analyze, fuzz, soak
```

### Where things are written down

| | |
|---|---|
| `kuu.md` (this file) | why kuu is shaped this way, what was learned, where it is going |
| `README.md` | the short introduction and the build |
| `docs/` — every page, shipped inside the executable | the reference: one page per module, plus the pages below; the count is in the figures |
| `docs/agent.md` | what is expected of an agent in a project that runs through kuu, and the report it writes back in `kuu-eval.md`. Read first |
| `docs/pitfalls.md` | what an agent's Lua priors get wrong here. Read once, second |
| `docs/capabilities.md` | `kuu capabilities`: the verbs, the palette, and this project's tasks and modules, in one command |
| `docs/adopting.md` | how a repository comes to be driven by kuu: `manifest.lua`, prerequisites by URL and hash |
| `docs/powershell.md` | each cmdlet you would reach for, and the kuu call that replaces it |
| `docs/cookbook.md` | fourteen complete programs, extracted and checked by the suite; the last four are shaped by the front door |
| `docs/roadmap.md` | decisions and milestones, with their reasons |
| `docs/inheritance.md` | what kuu carried over from its predecessors, each item sourced |
| `docs/shortcomings.md` | problems found in real use, with evidence and status |
| `docs/stability.md` | the 0.x posture, planned 1.0 freeze and provisional exceptions |
| `docs/upgrading-from-0.11.md` | how an existing 0.11 project adopts 0.12 |
| `docs/upgrading-0.N.md` | what changed in a release and what a project must do |
| `notes/` | dated handoff and validation records; not shipped |

Three habits worth forming early. Verify the runtime and read its agent and
migration guidance first. Once the manifest is ready to execute, `kuu
capabilities` answers what is here in one command — the verbs, every module
and the names it exports, and the project's own tasks and modules — so the
first thing you write is written against what exists. `kuu check` finds
misspelled names, unresolved `require`s and wrong palette names without
running anything; use it before running, not after. And when a result
surprises you, the manual page for that module is usually more specific than a
guess: the palette documents its refusals as carefully as its successes.

---

# Part I — kuu today

## What kuu is

kuu is a Lua 5.5 runtime for agents on Windows. One static executable runs a
Lua program and gives it native control over processes, files, the network,
services and event logs. It is the tool an agent holds on a Windows machine
instead of PowerShell: to set up, configure, run, test, script, control and
keep in check.

The shape is deliberate and worth stating plainly, because every later decision
follows from it:

- **One executable, copied into a repository.** A project carries its own
  `kuu.exe` in its root. Nothing is installed on the machine, nothing is shared
  between projects, nothing is looked up on `PATH`. Two projects may sit on
  different versions indefinitely, and that is a feature rather than debt.
- **PUC Lua 5.5.1, vendored unmodified.** kuu does not fork the language. The
  Lua reference manual holds; kuu's own manual documents only the delta.
- **A C host, never C++.** Lua reports errors with `longjmp`, which unwinds
  past C++ destructors and leaks whatever they were holding. That single fact
  decides the host language and is not revisitable while Lua is the runtime.
- **The gate is `require`.** A program obtains capabilities by naming modules.
  A stray Lua file has only stock Lua's `io` and `os`; processes, the network,
  the registry and everything else sit behind a name it must ask for.
- **Windows only.** Windows 11 23H2 and later, Windows Server 2025 and later.
  Portability was never a goal and its absence is what allows the palette to
  tell the truth about the platform.

<!-- figures -->
By the numbers, 0.12 is 16,690 lines of authored host C, 6,408 lines of kuu's own
Lua, a suite of 12,908 lines, and 9,942 lines of manual in 57 pages that ship
inside the executable. The palette is 27 public modules and 175 functions,
plus methods on handles. The suite's own count is what `make test` prints.
These figures are produced by `tools/bundle_docs.lua` from the executable
and the tree, and the suite holds them.

The verbs, as `kuu --help` prints them:

```text
kuu 0.12 -- a Lua 5.5 runtime for agents on Windows
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
<!-- /figures -->

## The shape of a program

```lua
global none
global <const> require, assert, ipairs, print

local proc, fs, json = require "proc", require "fs", require "json"
local rt = require "rt"

local r = assert(proc.run { rt.exe, "--version", timeout = "5s",
  limits = { memory = "128M", cpu = "2s", processes = 1 } })
assert(r.status == "exit" and r.code == 0, "child failed")
assert(fs.mkdir("build"))
assert(fs.write("build/status.json", json.encode { version = r.out }))
```

Two things in that fragment are load-bearing. `global none` switches the chunk
to declared-only mode, so every free name must be declared and a misspelling
becomes a load-time error rather than a silent `nil`. And every duration and
size carries a unit, because a bare number could never be read as thirty of the
wrong thing.

Entry routes are a program file, a program on standard input, and an inline
script with `-e`. Arguments arrive as `...` and as `rt.args`; there is no `arg`
global. The verbs are `run`, `list`, `check`, `capabilities`, `docs` and `version`.

## The palette, by area

The complete reference ships inside the executable — `kuu docs`, `kuu docs
PAGE`, `kuu docs search TEXT` — and is the authority on every signature. What
follows is the shape, not the reference.

**Processes and lifetime.** `proc` runs children with decided lifetimes. Every
child is born into its own Windows Job Object, marked kill-on-close, before its
first instruction runs; when kuu's handle to that job goes away — because the
program closed the child, dropped it, finished, failed or was killed — the
kernel terminates the whole tree. Waiting never blocks other tasks: `run` and
`wait` park the calling coroutine and the loop resumes it when the child is
complete, where complete means the job is empty *and* both streams have reached
end of file. Job-wide limits on memory, CPU time and active process count are
kernel-enforced. `proc.list`, `proc.find` and `proc.tree` see the machine's
other processes. Only `proc.detach` steps outside the lifetime rule, on
purpose.

**Files, and the truth about Windows.** `fs` is the largest single investment
in the host and the least glamorous. Paths go in as UTF-8 with either
separator and come back absolute with forward slashes; every path is
normalised and given the `\\?\` prefix before Windows sees it, so long paths
simply work. A junction is a name for another directory, and the palette says
so: `exists` reports the name itself and never its target, `stat` follows
unless told not to, `dirs` lists a link and does not enter it, `remove` removes
the link and never its target, `canon` and `same` see through it, and a link
whose target is gone is `dangling`, which is not `notfound`. Identity is
compared, never computed: `volume` and `file` come back as fixed-width hex
tokens. `fs.watch` reports directory changes with the same discipline.

**Text and encodings.** Strings are bytes. `text` converts deliberately
between UTF-8 and the Windows encodings, because a child process emits the OEM
or ANSI code page and guessing is how names get silently renamed. Nothing is
decoded implicitly and nothing becomes U+FFFD.

**Data.** `json` decodes strictly — a duplicate key loses data, so it is
refused — and encodes exactly, with integers surviving 64 bits intact.
`json.object` gives a document a decided key order, which a Lua table cannot.
`csv` handles RFC 4180 and the Windows variants; `ini` reads, writes and edits
in place with last-key-wins semantics.

**Network.** `http` fetches and posts over WinHTTP with a deadline of kuu's
own, because WinHTTP's own receive timers do not fire against a server that
accepts and then stays silent. It can verify a body against a SHA-256 as the
bytes arrive and refuse to place the file on mismatch. `net` resolves, probes
and lists listeners and addresses without blocking.

**The machine.** `sys` knows the host and verifies embedded Authenticode
signatures. `reg` reads and writes the registry typed. `env` keeps the live
environment and the persisted one apart, and broadcasts the change. `svc`
controls services; `evt` reads event logs.

**Between runs and between processes.** `mem` is a small JSON notebook per
project, capped and atomically written. `sync` is a named lock two kuu
processes in one session take turns on, which reports when a previous holder
died mid-way rather than leaving a stale lock file.

**The program's own tools.** `cli` declares arguments once and parses and
describes them from that declaration. `err` is the single error shape. `log`
writes timestamped records that never interrupt the work. `re` is PCRE2,
because Lua patterns are not regular expressions. `time` handles instants,
zones and ISO 8601. `hash` is digests, HMAC and random bytes from Windows' own
CNG. `archive` packs and unpacks through the `tar.exe` Windows ships.
`sched` provides tasks, sleep, a monotonic clock and scoped deadlines. `task`
declares a repository's work in a `manifest.lua` that `kuu run` executes.
`check` inspects code without running it. `rt` describes the launch.

**Provisional.** `pty` drives interactive console programs over ConPTY. It
works, and it is the most fragile thing in the palette; its interpretation of
terminal output may still change. `svc`, `evt` and `sys.signature` were also
marked provisional in 0.9.0 — see *Where 0.9.0 stands* below.

## The contracts that matter

These are the commitments that make the palette predictable. They are worth
more than any individual function, and they are what any successor should
carry forward.

**Expected outcomes are data; mistakes raise.** A missing program, a file that
is not there, a wait that ran out — these come back as `nil, err`. A bad option
name, a missing argument, a duration without a unit — these raise. A timeout is
a result state, not an exception: `proc.run` returns `status = "timeout"` and
does not throw. Branch on `err.is(e, "PROC", "notfound")`, never on message
text.

**Nothing goes missing without a counted cause.** A walk, a watch or a capture
never presents a silent partial result. Unreadable branches produce `errors`
rows with raw Windows codes; intentional exclusions have separate metadata.
Every dropped event raises `dropped`; every
truncated stream sets `truncated`. The counts add up, and a caller can always
tell "nothing was there" from "I could not look".

**Fact and decision are separate keys.** A walk reports what it observed and
what it did about it in different fields — whether a reparse point is a name
surrogate, and separately whether it was descended, pruned, depth-limited or
not followed. A reader can see them disagree.

**Units are never implicit.** Durations are `"250ms"`, `"30s"`, `"1.5m"`,
`"2h"` or a number of seconds; sizes are `"16M"` or a number of bytes. A bare
string without a unit is refused. This rule exists because a cross-module
handoff once turned a 100 ms deadline into a 100 second one.

**Strict text at every boundary.** No U+FFFD, no best-fit, no ANSI by default.
A name that cannot be represented is refused, never renamed.

**Paths are refused by name when Windows would lie.** Drive-relative `C:foo`,
device paths, and components ending in a dot or a space are rejected, because
Windows would quietly change what they mean.

**An atomic write is a temporary file and a rename**, so the destination holds
either the old bytes or all of the new ones, never a torn file. Since 0.9.0 the
rename is retried on transient sharing failures; see below.

**Option names are checked.** `{ cwdd = "x" }` raises rather than running with
the wrong settings.

## How a project adopts kuu

A repository keeps its own pinned `kuu.exe` in its root and writes one
`manifest.lua`. It can download and ignore the signed runtime or commit that
binary; both models keep a reviewed release, SHA-256 and signing identity and
verify the bytes before first execution. Runtime upgrades are the project
owner's decision. The [adoption guide](docs/adopting.md) gives both workflows.
The manifest states the minimum version it needs, lists its prerequisites by URL and
SHA-256, and declares its tasks with their dependencies. `kuu run` executes a
task after its dependencies, `kuu list` reads them back, and `kuu run
--dry-run` shows the plan without running it.

Prerequisites are fetched by the project, into the project. `http.get` with a
`sha256` writes the file only if the bytes hash correctly; `archive.unpack`
extracts it. Nothing is re-hosted, nothing is shared between projects, and a
stranger fetches from the same public sources. This has been exercised to its
limit by a consuming project that pins 27 archives and builds a complete
Tcl/Tk from source before it can compile itself.

## How kuu is built and verified

The build is GNU make and gcc from a pinned MSYS2 UCRT64 toolchain copied into
`.tools/`, with recipes running under `cmd.exe`. **kuu never builds kuu**: the
build is make and gcc, and the tests are Lua run by the built executable.
The build recipes do not require PowerShell.

Verification is layered and all of it runs locally:

- `make test` — the suite; its count is what it prints, and nothing here
  repeats it.
- `make analyze` — GCC's static analyzer over every authored host file, with
  warnings as errors.
- `make fuzz` — deterministic parser fuzzing, 10,000 cases per family across
  durations, dates, paths, CSV, INI, JSON and registry text, plus command
  lines, on fixed seeds.
- `make soak` — repeated full runs watching handle counts and private bytes.
- `make asan` — a separate build under Clang's AddressSanitizer, run inside
  the gate since 0.10.0; before that it was a release check run by hand, and
  its build was found 22 commits stale.
- `make gate` — all five in order: `test`, `asan`, `analyze`, `fuzz`, `soak`.

## Where 0.12 stands

0.12 refines the front door introduced in 0.10.0: repeated work runs through
`kuu.exe`, and the executable explains its current contracts and migration path.

- **`manifest.lua` is the declaration file**; `tasks.lua` remains a deprecated
  fallback with a warning and no scheduled removal. Tools are declared beside the tasks that call
  them — `task.tool "name" { exe, args, output, emits, timeout, reach }` —
  and called through the door with `task.exec { tool = "name", ... }`;
  `check` reads the declarations as literals and holds every literal call
  to them, and `capabilities` lists them.
- **The door keeps a ledger.** One record per crossing under
  `.kuu/ledger/<day>.ndjson`, chained by hash, ninety days, with the repository's
  head read from `.git` itself. Version 0.12 records execution history
  without automatic tree snapshots or filesystem-change claims.
  `capabilities` walks the chain and says whether
  it is intact. The record is never a condition on the run.
- **`kuu run --json` is a stream**: run, task and child events as they
  happen, flushed per line, the envelope last, `notes` for what was also
  said on standard error.
- **The executable explains itself.** `kuu docs agent` states what is
  expected of an agent in a project that runs through kuu, and asks for a
  report back in the project's `kuu-eval.md`; every entry point names it.
  `docs` is a verb like the others — sections, descriptions, search over
  all its words, `--json`, `rt.page` for a program. Each verb points onward
  at the moment it matters: a manifest that declares nothing, a misspelt
  verb, an unknown task, no project, a first `.kuu/` the repository does
  not ignore; and `check` names the version guard of 0.8 where it stands.
- **The laws hold everywhere.** An unknown option is `usage` in every call,
  C and Lua; raise-or-return follows the function's purpose, stated in
  err.md, and a project's own code is told to follow both. The asan build
  is inside the gate, the compiler is pinned, and every figure in this
  generated figures block is produced from the executable and tree.

The earlier 0.10.0 audits with a skeptic per finding — over the tools, over the ledger
and the stream, over the manual's self-explanation — confirmed a hundred
and eighteen findings between them, and every one was fixed with a check
before its batch was gated.

## Where 0.9.0 stands

0.9.0 is a correction release. It changed contracts while changing them was
still cheap, rather than adding capability.

- **Versions gained a patch component.** `rt.version` now reads `0.9.0`. The
  guard published through 0.8 matched `^(%d+)%.(%d+)$`, which does not match
  three components, so every project carrying it would have refused this
  runtime and 0.10.0. From 0.11, versions have two components again.
  `rt.version_at_least(major, minor, patch)`
  replaces the pattern; a project never parses the version text again.
- **`fs.write` retries its rename.** The atomic replace had failed
  intermittently with access-denied since 0.5 and the cause was unisolated.
  It reproduced from a *single* process — 15 failures in 2,000 writes — which
  removed concurrency and kuu's own locking from the account and left the
  environment: a scanner or indexer opens the freshly closed temporary file
  and the rename loses the race. Every failure recovered on an immediate
  retry. The rename is now retried, bounded, only on access-denied and
  sharing-violation, bypassing no permission. 4,000 writes after the change
  failed none, and the soak gate reported zero failed state writes where it
  had reported 21.
- **A pruned directory left `fs.dirs`'s `paths`.** It had been listed there
  while never being entered, so the obvious walk read exactly the content the
  prune excluded. It is now reported in a separate `skipped` array.
- **`json.object`** gives a document a decided key order, so a manifest
  compared byte for byte no longer needs a hand-rolled emitter.
- **`sched.clock`** reads the performance counter rather than the loop's
  millisecond tick, taking its resolution from 1 ms to roughly 500 ns.
- **`svc`, `evt` and `sys.signature` were moved to provisional.** They arrived
  in 0.7 with no project having driven them, and service state machines,
  event-log queries and Authenticode trust are three of the easiest Windows
  surfaces to shape wrongly. Nothing was removed from the executable; only the
  expectation of stability was withheld.

## What kuu measures

Single-threaded, on a 16-processor Windows 11 23H2 host, timed inside the
process:

| | |
|---|---|
| startup, do nothing and exit | 35 ms |
| arithmetic loop, 3M iterations | 16 ms |
| build 200k strings, then join | ~100 ms |
| 200k map inserts then lookups | ~240 ms |
| sha256 of 64 MiB in memory | 34 ms |
| walk 400 files with sizes | 2.9 ms |
| build and encode a 5k-row JSON document | 4.3 ms |
| decode it | 3.3 ms |

And for orchestration, which is what kuu is actually for — supervising eight
concurrent external children costs 633 ms against 533 ms for one. The single
event loop is not a limit on process-bound work.

---

# Part II — what was learned

kuu has two predecessors. Neither is being continued; both are kept as
reference, and what they proved is more valuable than what they contain.

## machteld — Tcl/Tk with C and C++ underneath

machteld is a compact Windows machine-control runtime: Tcl/Tk 9.0.4 plus a
structured palette in C and C++, shipping as one executable. It reached 0.21.

**What it proved, and proved first.** The process-lifetime and text-boundary
work that kuu now carries was machteld's first. Its `canon` returns a
normalised final path with volume and file identity as opaque hex, and its
`links` inventories reparse points *and* reports physical files sharing
storage — which kuu still has no equivalent for. Its `dirs` returns the same
result shape kuu's does, field for field. Its `pty` is contracted rather than
provisional, with each pseudoconsole owning a supervised tree in the host root
job and a narrower job of its own. Its `wrap` turns a program into a
standalone executable with no compiler involved. `pmap` and `pool` give real
parallelism across worker processes. It embeds the complete Tcl 9 and Tk 9
manuals — 469 documents, addressable by stable identifier and section — which
is a better documentation story than kuu's.

**What it cost.** Three things, none of them fixable by more effort:

*No sound static check is possible.* Tcl is homoiconic; any string can become
code. This is not a missing feature, it is the evaluation model. For a large
codebase edited over years, the absence of a checker compounds.

*Quoting and evaluation levels.* A condition passed in braces is an
unevaluated string until something calls `expr` on it in the right scope. A
literal brace inside a `string match` pattern unbalances the word. Both of
these cost real time in a single afternoon of writing ordinary code, and
neither has an analogue in Lua.

*A string-typed substrate.* Plain JSON encoding infers types from values, so a
file named `123` encodes as a number and a version of `"1"` becomes an
integer. machteld's typed JSON mode is the correct answer and gets it exactly
right, at the cost of considerable verbosity at every construction site.

**One defect worth recording.** Its `cli` raises `MACHTELD CLI usage` while its
manual documents `CLI usage`, so a `trap` written from the documentation does
not catch and a bad command line escapes as a stack trace. Found only by
printing the error code. Documentation that disagrees with the runtime is worse
than absent documentation, because it is trusted.

**Why it is not continued.** Its 0.21 contract targets Windows 11 25H2 and
Server 2025 build 26100 or newer and excludes ARM64 — a floor that rose from
Windows 10 1809 across six minor releases. More fundamentally, the unfixable
language properties above are precisely the ones that matter most over a long
life. Tk remains the one thing it has that nothing else does.

## drang — Go, and a language of its own

drang is a small, parallel, Perl-inspired scripting language for text, glue and
orchestration, implemented in Go, Windows-only. It reached 0.12.1.

**What it proved.** Several things, decisively:

*Go reaches Win32 directly.* This matters because the intuition that C has
privileged access and Go does not is simply wrong. `golang.org/x/sys/windows`
resolves DLL exports and calls them through the Go runtime's own mechanism —
498 `syscall.SyscallN` sites, no cgo anywhere. The shipped 0.12.1 binary
records `CGO_ENABLED=0`, and it does Job Objects, kill-on-close, memory and CPU
limits and console work regardless. The complete ConPTY path is reachable,
including `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`. Where C++ is genuinely better
is COM — and kuu is C, never C++, which has none of C++'s COM ergonomics
either.

*Real parallelism is worth having.* `map` to `pmap` is a one-word edit and
measured 6.07× on sixteen CPU-bound jobs, in-process, with no worker startup
cost. A pool built on kuu's own surface reached 2.74× and needed roughly
twenty-five lines of child processes and a hand-rolled JSON protocol.

*The standard library removes vendoring.* drang's entire dependency list is the
Go standard library plus `x/sys/windows`. It vendors nothing.

*Owning the language buys evolution.* `|>` pipelines, errors as values with
`?` propagation and `//` recovery, and — most interesting — `fmt --fix`
shipping real migration rules, so a breaking change arrives with an automated
rewrite rather than a note.

**What it cost.** You own a lexer, a parser, a register VM held byte-for-byte
in lockstep with a tree-walking oracle, a provenance-preserving formatter, lint
and migration rules, and 161 builtins — forever, in addition to whatever the
language is being used to build. And the interpreter does not reach Lua's
speed: roughly 430 ms per million arithmetic iterations against kuu's 5 ms.

**The most important thing it recorded.** drang 0.11's ancestor architecture
embedded a second language. machteld did the same: an out-of-process Lua and
column engine, reached through `macht`. In 0.21 it was **removed by
subtraction** — the engine, its wire, `macht`, Lua, LPeg, lua-cjson and the
column library, with no compatibility command and no migration layer — and the
standing decision recorded afterwards reads: *a second embedded scripting
language is not retained for hypothetical future use*.

What was deleted is the lesson. Not "Lua": a **wire, a column data model and
three vendored libraries**. The compute was cheap; the *integration boundary*
was expensive. Any future combination of languages should be judged on the
size of its boundary, not on the appeal of its parts.

## What kuu learned about itself

**Lua's honest weaknesses**, recorded as they were felt:

- *Files and paths are not in the language.* Roughly 1,700 lines of C for `fs`
  that a language with a filesystem would have had for free.
- *No insertion-ordered table.* A `cli` spec must be an array rather than a
  mapping, `log` must sort its fields, and `json` objects come out in arbitrary
  key order. Felt three times in one day, and again by anyone building a
  manifest compared byte for byte.
- *Lua patterns are not regular expressions.* No alternation, no counted
  repetition, no grouping of a repeated sequence. Closed by vendoring PCRE2 —
  at a cost detailed below.
- *Case folding is ASCII.* Closed by `text.upper` over Windows' own folding.
- *`global none` is opt-in boilerplate.* It is the best thing in the language
  for this use, and it must be typed at the top of every file, along with every
  standard name used.

**What vendoring costs.** An earlier 1.48 MB build was measured by object weight:

```
lua     716K   the language
pcre2   644K   regular expressions
yyjson  300K   JSON
host    632K   kuu's own code
```

In that measurement, only 632 K was kuu. The rest is batteries Lua does not ship, carried as 4.4 MB
of third-party source that must be tracked and audited for as long as kuu
lives. PCRE2 alone is 43% of the binary, 788 lines of binding, and produced two
real defects found by external review — a shared match block that a nested call
clobbered, and a quadratic rescan of an unmatched suffix. Neither class of bug
exists when a regular expression engine comes from the standard library.

kuu is small in absolute terms, and it is small *despite* Lua rather than
because of it.

**Where Lua is not fastest.** Lua wins arithmetic by an order of magnitude and
loses string building and dictionary work to Tcl, by 2.4× and 1.6×
respectively, because it interns every short string. A workload that mints many
distinct short keys pays for that. This is a property of the implementation,
not a defect to be fixed.

## Pitfalls, recorded

These cut across all three runtimes and are the ones most likely to be repeated.

**Shared design without a shared check produces shared defects.** kuu and
machteld converged on a byte-identical `dirs` result shape — and carried the
*identical* undocumented prune trap, which caused the same bug in two
independent programs written the same afternoon. Two implementations of one
design need one conformance suite, or each is only as correct as its author's
memory.

**A gate nobody runs is not a gate.** The soak gate was knowingly unclean
across several releases, reporting 21 failed state writes, and the finding sat
open. It was only closed when someone ran it and treated the failure as a
defect rather than as noise.

**Benchmarks lie in specific, repeatable ways.** Three examples from measuring
these runtimes against each other, each of which produced a wrong answer by an
order of magnitude before it was caught:

- Tcl bytecode-compiles *procedure bodies only*, so the same loop written at
  top level runs about three times slower and measures the harness.
- An encoder handed a typed value whose text it had already produced returned
  in 0.6 ms — a cache hit reported as an encode, making it look ten times
  faster than the alternative rather than three times slower.
- kuu's own `sched.clock` resolved to exactly 1 ms until 0.9.0, so anything
  under about 50 ms could not be measured honestly.

And a fourth, of a different kind: a benchmark of CPU-bound work *inside* a
runtime says nothing about a workload that spawns external processes. The first
measurement said kuu's concurrency was weak; the correct measurement — eight
external children at 18% overhead — said the opposite.

**Measure the thing the program actually does.** A pure arithmetic loop
separated two runtimes by 80×. A realistic manifest diff separated them by
4.3×. A realistic manifest scan reversed the ordering entirely. Any one of
those alone would have produced a confident and wrong conclusion.

**A co-evolved consumer routes around contract mistakes instead of reporting
them.** Every adoption finding on record came from one project that grew up
alongside the runtime. A project meeting the runtime cold finds different, and
more important, things.

**Escaping layers compound silently.** A shell heredoc, a Lua string literal
and a child's own source are three levels of escaping, and a doubled backslash
that survives two of them and not the third produces a syntax error in a
generated program with no obvious origin.

**Isolate before fixing.** The atomic-write defect sat open as "intermittent,
not reproduced" while it was assumed to involve concurrency. Reproducing it
from a *single* process was what removed concurrency, locking and the runtime's
own machinery from the account, leaving only the environment — after which the
fix was obvious and bounded.

---

# Part III — the complete manual

Every page of the manual, inlined. This is the same text `kuu docs`
serves from inside the executable, assembled here so that everything kuu
knows about itself can be read in one pass without querying anything.

It is generated by `tools/bundle_docs.lua` and checked by the suite; edit
the pages under `docs/`, never this part.

---

<a id="kuu-page-index"></a>

<a id="kuu-page-index-kuu"></a>

## kuu

kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
runs a Lua program and gives it native control over processes, files, the
network, services, and event logs. It is built for agents, so the manual is short
and exact: this is how kuu behaves, not how Lua works. Lua 5.5 itself is
assumed; the one page you need about the language here is
[Pitfalls](#kuu-page-pitfalls).

If you are an agent working in a project that runs through kuu, [For the
agent](#kuu-page-agent) says what is expected of you and how to report back. Read
it first, then Pitfalls once.

For a project that previously used signed 0.11, read
[Upgrading from 0.11](#kuu-page-upgrading-from-011) before running project tasks:
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
page, [the conduct expected of an agent](#kuu-page-agent), every module — is
inside the executable. It is the tool an agent holds on a Windows machine
instead of PowerShell; the [From PowerShell](#kuu-page-powershell) page maps one
to the other.

kuu is the front door of a project: run repeated operations as tasks with
`kuu run`, and their children with `task.exec`, to record them in the ledger.
Children run in jobs with the timeouts and limits the calls specify. If
something cannot be done from here, build a [tool](#kuu-page-tools) for it, in any
technology, and call it through the door. Editing is yours; running is the
door's. The
[roadmap](#kuu-page-roadmap) records what is planned and why, and
[inheritance](#kuu-page-inheritance) records what kuu learned from its predecessors.

<a id="kuu-page-index-running-a-program"></a>

### Running a program

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
and `rt.args`. The [agent guide](#kuu-page-agent-try-an-inline-command) has more examples
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
[capabilities](#kuu-page-capabilities) reports them. `rt.page(name)` is the text of
one manual page, or nil for a name that is not one, so a program with no
shell reads the manual the way `kuu docs` does.

<a id="kuu-page-index-modules"></a>

### Modules

A program gets capabilities by naming them: `require` is the gate. A Lua file
that requires nothing has only what stock Lua's `io` and `os` give it: files
by path, the environment, the clock, and exit. Processes, the network,
hashing, and every other organ are behind `require`.

| module | gives |
|---|---|
| [`proc`](#kuu-page-proc) | children with decided lifetimes and resource limits: run, start, wait, kill, detach; the other processes: list, find, tree |
| [`fs`](#kuu-page-fs) | files, directories, attributes, identity, links, walks, watches, with Windows truth |
| [`http`](#kuu-page-http) | fetch and post over WinHTTP, with the machine's proxy and certificates |
| [`sched`](#kuu-page-sched) | tasks, sleep, a monotonic clock, wall time, scoped deadlines |
| [`json`](#kuu-page-json) | strict decoding and exact encoding |
| [`hash`](#kuu-page-hash) | digests, HMAC, random bytes |
| [`text`](#kuu-page-text) | strict conversion between UTF-8 and Windows encodings |
| [`log`](#kuu-page-log) | structured lines that never interrupt the work |
| [`cli`](#kuu-page-cli) | a program's arguments, declared once |
| [`err`](#kuu-page-err) | the one error shape and how to test it |
| [`task`](#kuu-page-task) | a repository's tasks and default child timeout, declared once in `manifest.lua`, run by `kuu run` |
| [`check`](#kuu-page-check) | syntax, global declarations, require resolution, and palette names without running project code |
| [`archive`](#kuu-page-archive) | zip and tar archives through the tar.exe Windows ships |
| [`sys`](#kuu-page-sys) | facts about this machine and process, embedded Authenticode signatures |
| [`svc`](#kuu-page-svc) | inspect, start, stop, restart, and wait for Windows services |
| [`evt`](#kuu-page-evt) | read and filter Windows event logs |
| [`pty`](#kuu-page-pty) | interactive console children and Lua-pattern expect; provisional |
| [`mem`](#kuu-page-mem) | a small memory across runs, one JSON file per project |
| [`sync`](#kuu-page-sync) | one at a time across processes: a named lock |
| [`re`](#kuu-page-re) | regular expressions on PCRE2, with Unicode and named groups |
| [`time`](#kuu-page-time) | instants, zones, ISO 8601, durations |
| [`net`](#kuu-page-net) | the network from here: resolve, probe, listeners, addresses |
| [`csv`](#kuu-page-csv) | comma-separated values, RFC 4180 and the Windows variants |
| [`ini`](#kuu-page-ini) | INI files: read, write, and edit in place |
| [`reg`](#kuu-page-reg) | the registry, typed |
| [`env`](#kuu-page-env) | environment variables, live and persisted |
| `rt` | the launch: version, executable, route, program, arguments, the require root |

`require` searches `package.preload`, where these live, and then the program's
directory: `require("a.b")` tries `a/b.lua`, then `a/b/init.lua`, below the
directory of the program file, or below the current directory for the stdin
and inline routes. Module files follow the same decoding rules as programs.
Environment variables such as `LUA_PATH` are never consulted and C modules are
never loaded; `package.path` and `package.cpath` are empty strings to make that
visible.

<a id="kuu-page-index-output-and-input"></a>

### Output and input

Standard input, output, and error are binary. What a program writes with
`print`, `io.write`, or `io.stderr:write` leaves the process byte for byte, with
no CRLF translation and no re-encoding. Text is UTF-8 by convention, and the
C runtime's file functions (`io.open`) and `os.getenv` take and return UTF-8.
A terminal set to another code page will show UTF-8 bytes wrongly; a pipe will
not.

<a id="kuu-page-index-errors-and-exit-codes"></a>

### Errors and exit codes

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

<a id="kuu-page-index-the-manual-from-inside-the-executable"></a>

### The manual, from inside the executable

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

<a id="kuu-page-index-pages"></a>

### Pages

- [For the agent](#kuu-page-agent): what is expected of an agent in a project that
  runs through kuu, and the report it writes back in `kuu-eval.md`. Read
  first.
- [From PowerShell](#kuu-page-powershell): each cmdlet an agent reaches for, and the
  kuu call that replaces it.
- [Pitfalls](#kuu-page-pitfalls): what differs from the Lua an agent already knows,
  and the Windows facts kuu refuses to hide.
- [Adopting kuu](#kuu-page-adopting): a repository gets its own kuu.exe, a
  manifest.lua, and prerequisites by hash; nothing on the machine.
- [capabilities](#kuu-page-capabilities): what a program can reach from here -- the
  verbs, the palette, and this project's tasks and modules, in one command;
  provisional.
- [Cookbook](#kuu-page-cookbook): fourteen complete programs for common automation
  jobs, the last four shaped by the front door.
- [Bounded publication and cleanup](#kuu-page-cleanup): retry Windows denials within
  a project budget, publish validated staging, and retain both failure causes.
- [Process recipes](#kuu-page-process-recipes): serialize command descriptions,
  classify child outcomes and preserve captured diagnostics.
- [Working directories](#kuu-page-working-directories): preserve the caller's directory
  and exact arguments through a wrapper, a task and a child process.
- [Project environment](#kuu-page-project-environment): share root-derived cache paths
  between command-line tools and newly launched editors.
- [Relocation and health checks](#kuu-page-relocation): move a checkout, rebuild local
  environments, and inspect dependencies without provisioning them.
- [Detached editors and GUI verification](#kuu-page-editor): use fresh profiles and
  a bounded native probe on a private desktop, with explicit readiness checks.
- [Native helper and shortcut](#kuu-page-native-helper): cache a helper by verified
  build inputs and regenerate a local shortcut after moving the project.
- [Reconstruction and publication recovery](#kuu-page-reconstruction): verify cached
  restores and independent backups, and reconcile uncertain upload outcomes.
- [Stability](#kuu-page-stability): the future 1.x contract and minimum-version guards.
- [Upgrading from 0.11](#kuu-page-upgrading-from-011): the migration checklist for
  0.12, execution history, inspection policy and new APIs.
- [Upgrading to 0.11](#kuu-page-upgrading-011): N.N version numbers, corrections and
  behavior changes since 0.10.0, and the shorter route to an inline command.
- [proc](#kuu-page-proc), [fs](#kuu-page-fs), [http](#kuu-page-http), [net](#kuu-page-net),
  [sched](#kuu-page-sched), [json](#kuu-page-json), [csv](#kuu-page-csv), [ini](#kuu-page-ini),
  [re](#kuu-page-re), [time](#kuu-page-time), [hash](#kuu-page-hash), [text](#kuu-page-text),
  [reg](#kuu-page-reg), [env](#kuu-page-env), [sys](#kuu-page-sys), [svc](#kuu-page-svc), [evt](#kuu-page-evt),
  [pty](#kuu-page-pty), [sync](#kuu-page-sync),
  [mem](#kuu-page-mem), [archive](#kuu-page-archive), [log](#kuu-page-log), [cli](#kuu-page-cli),
  [err](#kuu-page-err): the modules.
- [Tasks](#kuu-page-task): `manifest.lua`, `kuu run`, `kuu list`, and the exit codes.
- [Tools](#kuu-page-tools): the programs a project builds or fetches, declared in the
  manifest and called through the door.
- [Confined tools](#kuu-page-confined): what a tool that confines itself must
  provide, and the junction every lexical sandbox has to be told about.
- [The ledger](#kuu-page-ledger): what `kuu run` remembers of every crossing, under
  `.kuu/ledger`, chained and kept ninety days.
- [check](#kuu-page-check): what `kuu check` finds without running a file.
- [Scan configuration](#kuu-page-scan): `kuu.config.json` controls shared project
  inspection for checking and module inventory, with validated exclusions and
  safe traversal.
- [Toolchain](#kuu-page-toolchain): what kuu's own `.tools` holds and where it comes
  from.
- [Upgrading to 0.10](#kuu-page-upgrading-010): no call moves, but `check` reports
  four mistakes it used to pass and reads a project's own modules, so a green
  project can turn red without changing. `check --fix`, `capabilities`, and
  `text.trim`.
- [Upgrading to 0.9](#kuu-page-upgrading-09): the version grows a patch component,
  which breaks the old pattern guard; `rt.version_at_least` replaces it. The atomic
  write retries its rename, and three modules leave the planned freeze.
- [Upgrading to 0.8](#kuu-page-upgrading-08): Windows 11 23H2 support and the JSON
  duplicate-key diagnostic fix, with the same Lua API.
- [Upgrading to 0.7](#kuu-page-upgrading-07): deadlines, child limits, services,
  signatures, event logs, name checking, and provisional pty.
- [Upgrading to 0.6](#kuu-page-upgrading-06): duration units and adoption fixes.
- [Observed shortcomings](#kuu-page-shortcomings): reproductions, fixes, and external limitations.
- [Roadmap](#kuu-page-roadmap): decisions taken and milestones ahead.
- [Inheritance](#kuu-page-inheritance): laws, traps, and contracts carried over from
  machteld, the z estate, and the archived projects.

---

<a id="kuu-page-agent"></a>

<a id="kuu-page-agent-for-the-agent"></a>

## For the agent

What is expected of you in a project that runs through kuu. Everything on
this page is stated elsewhere in the manual as a fact about kuu; here it is
stated once, as an instruction, in the order you meet it. Read it first,
before [Pitfalls](#kuu-page-pitfalls).

<a id="kuu-page-agent-arriving"></a>

### Arriving

First establish that the project's copy matches its reviewed runtime pin,
using the [adoption verification procedure](#kuu-page-adopting-verify-before-first-execution)
before executing a newly downloaded or checked-out binary. The project may
download and ignore its runtime or commit the signed binary; both are supported.
Keep that choice and its approved version, hash and signing identity. Change
them only as part of an owner-authorized runtime upgrade.

If this project previously used signed 0.11, read
`kuu docs upgrading-from-0.11` before running project code with a replacement.
It explains the changes to execution history, inspection, reports and project
instructions; old advice in `AGENTS.md` or README files can describe behavior
this executable no longer has. Follow its ordered upgrade checklist while
keeping the project's own task and approval policies.

Read the project's existing `kuu-eval.md` for earlier experience and unresolved
difficulties. Recheck relevant reports as you work and [report back](#kuu-page-agent-reporting-back)
with new evidence, including when an upgrade changes an earlier result.

Run `kuu capabilities` to discover the runtime and the project's tasks and tools
once its manifest is ready to execute. Like `kuu list`, this loads the manifest
to learn its declarations. `kuu check` without `--fix` is read-only static
inspection. The manual is inside the executable; reading it needs no network,
source checkout or manifest execution. With the verified project copy in the
current directory:

```powershell
.\kuu.exe docs                         # list pages and their descriptions
.\kuu.exe docs fs                      # read a module's page
.\kuu.exe docs search fs.read          # find an API and a command to read its context
.\kuu.exe docs fs reading-and-writing  # retrieve only the relevant section
.\kuu.exe docs fs errors               # look up the module's error codes
```

Sections are named by their heading or anchor, so copy the `Read:` command
from a search result. `kuu docs --json` also works for lists, pages, sections,
and searches. Read `kuu docs pitfalls` once for the Lua and Windows differences;
`kuu docs index` is the full map. When an error surprises you, search for its
code or read the module's `errors` section.

<a id="kuu-page-agent-try-an-inline-command"></a>

### Try an inline command

Use `kuu -e` for immediate queries and small operations. Every kuu module is
available, with no script file or manifest required. Print the answer explicitly;
use `json.encode` for structured results. These examples run from PowerShell:

```powershell
.\kuu.exe -e "print(require('json').encode(require('sys').info()))"
.\kuu.exe -e "print(require('json').encode(assert(require('fs').list('.'))))"
.\kuu.exe -e "print(assert(require('hash').file('sha256', ...)))" README.md
```

The first describes the machine, the second lists the current directory as
JSON, and the third hashes a file; replace `README.md` with the path you need.
Arguments after the script arrive as `...` and `require('rt').args`, which
keeps paths out of the Lua source. `assert` makes a failed operation visible
as an error and a nonzero exit. A returned value alone is not printed.

For a longer experiment, use `kuu FILE` or send Lua on standard input to
`kuu -`. Turn repeated project operations into tasks in `manifest.lua`.
Inline commands and scripts do not write the task ledger; set timeouts on
any children or network operations they start.

<a id="kuu-page-agent-running"></a>

### Running

- **Everything that runs in the project runs through `kuu.exe`.** A
  crossing is a task run by `kuu run`, and each child that task starts
  with `task.exec`; each crossing gets a record in [the ledger](#kuu-page-ledger),
  and each child gets a job, the limits and the timeout it was given. `kuu FILE` and `kuu -e`
  are for trying something once: what they start is in a job with
  whatever `timeout` and `limits` the call gives, and nothing is recorded.
  Anything that will run again is a task in `manifest.lua`.
- **Declare every program a task runs as a tool**, `task.tool "name" { exe
  = ... }`, and call it with `task.exec { tool = "name", ... }`. `check`
  then holds every call written with the literal `tool = "name"` to the
  declaration — a name computed at run time is not judged, so write it in
  the call — and `capabilities` lists the tool. A bare `task.exec {
  "prog.exe" }` is a warning from `check` for that reason. A project
  program started from a shell without `kuu.exe` bypasses that history.
  When a task must capture and inspect output, use `task.command` to resolve
  its declared tool, then `proc.run`. This is supported, but the captured
  child has no individual ledger record or child event; the enclosing task
  and run remain recorded. Prefer `task.exec` when capture is unnecessary,
  including when a tool documents successful nonzero exits. The
  [process recipes](#kuu-page-process-recipes) show both paths and their diagnostics.
- **Bound what you run.** `task.defaults { timeout = "10m" }` in the
  manifest gives every child a timeout it does not set itself; without
  it, and without a `timeout` on the call or the declaration, a child has
  no time bound at all. `sched.deadline` bounds a sequence of waits in
  your own code. [Tasks](#kuu-page-task), [sched](#kuu-page-sched).
- **Run `kuu check` after every edit and before every `kuu run`.** It
  reads without running: syntax, global declarations, requires, palette
  names, option names, error codes, closed sets and version comparisons,
  tool declarations and their calls. Errors fail it and warnings do not;
  a warning is still something to read. [check](#kuu-page-check).
- **If something cannot be done from here, build a tool for it**, in
  whatever technology you write best — fetched by URL and hash into the
  project's own `.tools/`, or built from the project's own source — and
  either way declared with `task.tool` and called through the door. kuu is
  never extended; a project is.

<a id="kuu-page-agent-writing"></a>

### Writing

- **Start every file with `global none`** and declare the standard names
  you use. A misspelled name is then a load-time error, and `check` sees
  it before anything runs.
- **Follow the two laws kuu's own functions follow.** An expected outcome
  is returned as `nil, err`; a caller's mistake is raised; and an option
  name your function does not take is a raised `usage`, never ignored.
  Mint your errors with `err.new("DOMAIN", "code", message)` in an
  uppercase domain of your own — the codes are yours, and `check` does not
  judge them — and return `nil, err` from a task for an expected failure,
  so `kuu run --json` and the ledger carry your domain and code. Branch on
  `err.is`, never on the message. [err](#kuu-page-err).
- **Fetch nothing the manifest does not list by URL and hash**, and
  install nothing on the machine: nothing goes on `PATH`, and nothing is
  shared between repositories. [Adopting](#kuu-page-adopting).
- **`.kuu/` is kuu's** — the notebook and the ledger. It sits in
  `.gitignore` beside `.tools/` and `build/`, and nothing in it is yours to
  edit. Ignore `kuu.exe` only when the project downloads its pinned runtime;
  a project may instead commit that signed binary.

<a id="kuu-page-agent-reporting-back"></a>

### Reporting back

kuu is built for you, and the only way it improves is being told where it
helped and where it stood in the way. When you have worked in a project
through kuu, append an entry to `kuu-eval.md` at the project root — a
UTF-8 file the project commits, since `.kuu/` never travels and kuu sends
nothing — and never rewrite an earlier entry. Create the file if it is missing.
Keep it with the project's maintained source and include its updates in the
project's normal review and commit workflow. One entry per piece of work:

```markdown
## 2026-09-13 — kuu 0.11 — adding the release task

### Worked
- `kuu check` named the misspelt option and the fix before anything ran.

### Difficult
- `kuu run release` printed `kuu: release failed after 1.0s` and then
  `kuu: TASK failed: C:/work/app/.tools/sdk/signtool.exe: timeout`; nothing
  said which timeout, and I found `task.defaults` in kuu docs task.

### Should change
- The timeout message should name the bound and where it was set.
```

Maintain this history across runtime upgrades. Record the version actually
tested; for a development build sharing a released version string, include its
build or SHA-256 in the entry. When revisiting a difficulty, reproduce it where
practical and append a follow-up referring to the earlier entry's date and issue.
Say whether it still occurs, is resolved by the tested change, has a workaround,
or remains unverified; release notes alone do not establish a fix in this project.
Preserve the original report and its evidence; append corrections as follow-ups.
Summarize relevant results from disposable validation copies in the project's
root document, including a failed or deferred upgrade. Identify the test copy,
project revision and Windows version when they affect the conclusion; distinguish
candidate testing from actual adoption. Continue reporting after subsequent work
with kuu. Record observed results and useful requests, without inventing problems
to fill the example's sections.

The heading is `## YYYY-MM-DD — kuu VERSION — what the work was`, on one
line: `## `, the date in that form first, then the rest; a hyphen does as
well as the dash. That is the line `kuu capabilities` counts, and a
heading shaped any other way is not an entry. A difficulty carries the
exact command and its output, so it can be reproduced; without that it is
an opinion, and belongs under *Should change*. An entry may name the
ledger record it is about, by its day file and its `at`. Keep entries
short: kuu counts them, and people read them where the project keeps
them. Run `kuu capabilities` when you have written; its `eval` line shows
the count and the date of the last entry, and nothing fails without it. That count
confirms entry discovery; it does not validate evidence or determine issue status.

<a id="kuu-page-agent-the-short-form"></a>

### The short form

Verify a newly obtained runtime against the project's reviewed pins before
executing it. Coming from signed 0.11, read `kuu docs upgrading-from-0.11`
before running project code with a replacement. Read `agent` for the current
workflow, then use `kuu capabilities` to discover the project; it executes the
manifest. Read pitfalls once. Everything that runs,
runs through the door as a task with declared tools; try things with `kuu -e`
or `kuu FILE`, keep them as tasks. Find APIs with `kuu docs search`, then copy
the command to read their section. Bound every child. `global none` at the top of
every file. `check` after every edit and before every run. Return `nil,
err` for what is expected, raise for a mistake. Nothing on `PATH`, nothing
fetched without a hash, nothing of yours in `.kuu/`. Write `kuu-eval.md`
before you leave.

---

<a id="kuu-page-pitfalls"></a>

<a id="kuu-page-pitfalls-pitfalls"></a>

## Pitfalls

What an agent's priors get wrong here. kuu embeds PUC Lua 5.5.1 unchanged,
compiled as C, so the Lua 5.5 reference manual holds; this page is the delta
between the Lua most agents know and this runtime, plus the Windows facts kuu
refuses to hide. Read it once.

<a id="kuu-page-pitfalls-lua-55-differences-from-54-habits"></a>

### Lua 5.5 differences from 5.4 habits

- **`global` is a contextual keyword.** A statement beginning with `global`
  followed by a name, `none`, `*`, `function`, or an attribute is a global
  declaration. Elsewhere it is an ordinary name (kuu keeps Lua's default
  compatibility setting), so `local global = 1` still works. Avoid the name.
- **In a declared-only scope, every free name must be declared**, `print`
  included. `global none` starts such a scope without declaring any names;
  `global *` permits undeclared globals again. kuu recommends
  starting every file with it and declaring the standard names you use:

  ```lua
  global none
  global <const> print, require, ipairs, pairs, tostring, error, pcall, type
  ```

  A misspelled name is then a load-time error instead of a silent nil. The
  common mistake is switching on strictness and forgetting `print`; the error
  says exactly that.
- **For-loop control variables are read-only.** Assigning to them is a
  compile-time error.
- **Floats print with more digits.** `0.1 + 0.2` prints as
  `0.30000000000000004`, `2^53` as `9007199254740992.0`. Use `string.format`
  for a fixed layout.
- **New in the library:** `table.create(n, m)`, two return values from
  `utf8.offset`.
- **Attributes are how resources are held:** `local f <close> = ...` closes
  the value when the block exits, including by error; `local n <const> = ...`
  refuses reassignment. Every kuu handle supports `<close>`.

<a id="kuu-page-pitfalls-what-kuu-removed-or-changed"></a>

### What kuu removed or changed

- **Absent by design:** `io.popen`, `os.execute`, `os.remove`, `os.rename`,
  `os.tmpname`, `dofile`, `loadfile`, `package.loadlib`, and the `debug`
  library except `traceback` and `getinfo`. Processes belong to
  [`proc`](#kuu-page-proc), files to [`fs`](#kuu-page-fs). `io.open` remains and takes
  UTF-8 paths.
- **`os.getenv` reads the live environment as UTF-8**; stock Lua returns the C
  runtime's startup copy in the ANSI code page.
- **No binary chunks.** `load` always uses mode `"t"`.
- **Arguments** reach the main chunk as `...` and as `require("rt").args`.
  There is no `arg` global.
- **`require`** looks in kuu's own modules first, then in the program's
  directory (`?.lua`, `?/init.lua`). Names are plain dotted names; nothing is
  read from the environment; you cannot shadow a kuu module by accident.
- **The main chunk is a coroutine run by kuu's loop.** Waits park it and
  completions resume it. `coroutine.yield()` with nothing to wait for is an
  error. Your own coroutines work; a palette wait inside one is served in
  place.
- **`os.exit(n)`** ends the process at once. Children die with it either way.

<a id="kuu-page-pitfalls-bytes-text-and-windows"></a>

### Bytes, text, and Windows

- **Strings are bytes.** `#s` counts bytes, `s:sub` cuts bytes, `s:lower`
  folds ASCII only. Use `utf8.len` and `utf8.codes` for characters.
- **Standard streams are binary.** What you write leaves the process byte for
  byte, no CRLF translation. A terminal on another code page shows UTF-8
  wrongly; a pipe does not.
- **Child output is bytes in whatever encoding the child chose.** `cmd.exe`
  writes CRLF and the OEM code page: `text.decode(r.out, "oem")`. Do not
  assume UTF-8 from a program you did not write.
- **`cmd.exe /c` re-parses its argument.** kuu quotes arguments for programs
  that parse the normal way; cmd does not. Give `/c` one plain argument
  without embedded quotes, or write a `.cmd` file and run that.
- **Paths: forward slashes are fine everywhere in kuu**, and come back that
  way. `C:foo` (drive-relative) and components ending in `.` or a space are
  refused by name, because Windows would quietly change what they mean.
- **A junction is a name for another directory.** `fs.exists` reports
  `"link"`, `fs.stat` follows unless told not to, `fs.dirs` lists it and does
  not enter it, `fs.remove` removes the link and never its target,
  `fs.canon` and `fs.same` see through it. A link whose target is gone is
  `FS dangling`, not `notfound`.
- **An atomic write is a temp file and a rename.** A watcher sees exactly
  that, not an `added` of the final name.
- **A watch read returns the first batch.** Changes made over time arrive
  over several reads; loop until you see what you expect, and reconcile from
  a listing when `overflow` or `dropped` appears.

<a id="kuu-page-pitfalls-values-and-results"></a>

### Values and results

- **Expected failures are `nil, err`; mistakes raise.** A missing program, a
  file that is not there, a timed-out wait come back as `nil, err`. A bad
  option name or value, a missing argument, a duration without a unit raise.
  Branch on `err.is(e, "PROC", "notfound")`, never on message text.
- **Timeouts are results.** `proc.run` returns `status = "timeout"`; it does
  not raise. A wait that ran out returns `nil, err` with `timeout`, and the
  thing waited on is still alive.
- **Durations and sizes carry units.** `"30s"`, `"250ms"`, `"16M"`. A number
  is seconds or bytes. A bare string without a unit is refused.
- **Option names are checked.** `{ cwdd = "x" }` raises `usage` instead of
  running with the wrong settings.
- **JSON arrays are marked tables and nulls are `json.null`**, so `#` is
  reliable and `{}` stays an object. Integers round-trip exactly; do not
  pass identifiers through floats.
- **`fs.exists` returns a kind string or `false`**, so `if fs.exists(p) then`
  works and `if fs.exists(p) == "directory" then` is available.

<a id="kuu-page-pitfalls-limits-worth-knowing"></a>

### Limits worth knowing

- Deep recursion fails as a Lua stack overflow around two hundred thousand
  frames, far sooner for C-boundary recursion (`pcall`, metamethods) at two
  hundred levels. Write loops for large inputs.
- Programs and stdin programs are bounded at 16 MiB; `fs.read` at 1 GiB
  unless `maxbytes` says otherwise; `proc.run` output at 64 MiB per stream
  unless `maxout` says otherwise, with `truncated` set when cut.
- **A Lua pattern ending in `$` is not anchored.** `s:find("%s+$")` does not
  look at the end of the string; it tries the match at position 1, then 2,
  then 3, to the end, because only `^` anchors a pattern. Asking whether the
  last byte is blank therefore costs a scan of the whole string, and the
  trailing-whitespace test is usually the most expensive line in a routine
  that has one. Both of kuu's own text encoders had it: one `match("%s$")`
  per field was 65% of `csv.encode`'s time, and `ini`'s `trim` paid a
  `gsub("%s+$", "")` on every key and every value. Compare the byte instead
  -- `s:byte(-1)` against 32, 9, 10, 11, 12, 13 -- or walk in from the end;
  `csv.encode` became 1.7x faster and `ini.decode` 1.9x. The same applies to
  `%.lua$`, `"B$"`, and every other pattern whose only anchor is at the
  right. `^%s+` is fine: it is anchored and tried once.
- Short strings are interned, so minting many distinct ones costs a hash and
  a lookup each. Formatting 200,000 twelve-byte results took 66 ms when every
  result differed and 38 ms when they were all the same, so the interning was
  43% of it; the same loop producing 44-byte results showed no difference at
  all, because a string past the implementation's short limit is allocated
  rather than hashed.
- **`..` in a loop is quadratic, but the constant is small, so measure before
  converting one.** Each step copies the whole string so far. Against a table
  and one `table.concat`, the crossover on short pieces was about ten: at two
  pieces `..` was twice as fast, at five 1.3 times, at ten they tied, and past
  that the table pulled away -- 1.4x at twenty, 2x at forty, 4.8x at eighty.
  A log line with a handful of fields is better off with `..`; a document is
  not. What is never in doubt is the large case: accumulating 200,000 pieces
  with `..` does not finish in reasonable time.

<a id="kuu-page-pitfalls-errors-kuu-itself-prints"></a>

### Errors kuu itself prints

Every classified failure kuu reports has the shape `kuu: DOMAIN code: text`,
and the codes are listed per module page. `kuu docs search CODE` finds the
page. Two other shapes reach standard error and are not failures: `kuu run`'s
progress lines, `kuu: NAME 0.3s` as each task ends, or `kuu: NAME failed
after 0.3s` ahead of the failure's own line, and notices, `kuu: warning:
…`, which `--json` also carries as `notes`. A usage failure is followed by
the usage block it refers to. An uncaught error in a program is `kuu:
message` with the traceback, and a crash in kuu itself is `kuu: crashed:
…`, a defect to report.

---

<a id="kuu-page-capabilities"></a>

<a id="kuu-page-capabilities-capabilities"></a>

## capabilities

`kuu capabilities` says what a program can reach from here: this executable's
verbs, manual and palette, and this project's tasks and its own modules.

```text
kuu capabilities [--json] [--timings]
```

It exists because the answer was scattered. The palette is in the manual, the
tasks are in `kuu list`, and a project's own modules are in its Lua; an agent
arriving in a repository had to assemble those three itself, and an agent that
guesses wrong writes code against a module that is not there. This is the
answer assembled once. Start with [the agent guide](#kuu-page-agent) and, when replacing
signed 0.11, [the migration guide](#kuu-page-upgrading-from-011). Then use capabilities
with the verified runtime once the manifest is ready to execute: it loads the
declarations, while `kuu check` inspects them statically.

It is **provisional**: it arrived in 0.10.0, and its descriptor contract remains
under evaluation through project use and feedback. Consuming agents build on
that shape, so it stays outside the planned 1.0 freeze until a later release
explicitly accepts the contract and its adoption evidence. See
[stability](#kuu-page-stability).

Nothing is reported that kuu cannot know.

- **The palette comes from the modules' own export tables**, so the listing
  cannot drift from the runtime: it is read out of the same tables a program
  would index. Which modules are public is authored in the interface
  description `check` reads, and the suite holds that list to the manual's
  module table in both directions.
- **A project's modules are read from their text and never executed.** The
  extraction is the one [check](#kuu-page-check) uses, so the two agree; it
  over-approximates, and a module whose exports the text does not bound is
  counted rather than named. A program is not a module, and from the text
  alone the two do not differ. Failed directory listings and unreadable
  candidate modules make the inventory explicitly incomplete, with their
  paths and diagnostics; they never become a successful empty inventory.
  Automatic discovery skips directory links the native walker refuses to
  enter and skips file symlinks. Their targets are excluded from the file
  count and module list; intentional exclusions do not make the inventory
  incomplete. Ordinary filter/cloud reparse metadata remains discoverable.
- **Tasks and tools are declared by running `manifest.lua`**, which is project
  code. `kuu run` and `kuu list` already do that, and this does no more. A
  `manifest.lua` that does not load costs the task and tool lists and nothing
  else: the reason is reported and the rest of the descriptor still stands.
  The tools listed are the executed reading; [check](#kuu-page-check) reads the
  same declarations from the text, and the suite holds the two equal.
- **Installed executables are not inferred as tools.** An undeclared executable
  under `.tools` does not become a tool entry merely because it is present.
  Tools declared in the manifest are listed, including paths under `.tools`;
  Lua module discovery separately follows the configured inspection exclusions.
- **What agents wrote back is counted, not read.** `kuu-eval.md` at the root,
  the report [For the agent](#kuu-page-agent) asks for, holds one entry per heading
  shaped `## YYYY-MM-DD — kuu VERSION — what`; the descriptor says whether
  the file is there, how many such headings it holds outside fenced code,
  and the date of the last, and nothing else looks at the file.

Without a `manifest.lua` at or above the current directory there is no project
half. kuu does not walk whatever directory it was started in instead: that is
a different question, and an expensive one to answer by accident.

The root's [`kuu.config.json`](#kuu-page-scan) controls module discovery. Automatic
inventory always excludes `.git` and `.kuu`, and by default excludes `.tools`,
`build`, `node_modules`, `.cache`, `.local`, `.venv`, and `__pycache__`.
These basename defaults can hide maintained source; `defaults:false` restores
visibility of the optional names. Configuration does not change `require`
resolution or what the manifest may execute.

The command loads configuration before running the manifest and retains that
policy for its inventory, even if the manifest changes the configuration file
or the legacy `check.PRUNE` table.
Invalid or unreadable configuration prevents manifest execution and inventory;
the descriptor still reports the runtime, ledger and feedback, with a
`SCAN config` diagnostic and an explicitly incomplete module inventory.

```text
kuu 0.12 (Lua 5.5.1) at C:\work\app\kuu.exe

  verbs      capabilities, check, docs, list, run  kuu VERB --help
  manual     57 pages                              kuu docs PAGE | search TEXT
  modules    27, 184 names                         require "NAME"
  errors     28 domains, codes in --json           err.is(e, DOMAIN, code)

modules
  proc       alive, detach, find, kill, list, run, start, tree, wait_all,
             wait_any
  fs         absolute, basename, canon, chdir, copy, cwd, dirname, dirs,
             exists, ext, glob, join, link, list, mkdir, read, relative,
             remove, rename, same, space, stat, stem, temp, tempdir, tempfile,
             watch, write
  ...

project C:/work/app
  tasks      build, test*, fmt
             * the default. kuu run TASK; kuu list describes them
  tools      report (ndjson), signtool (lines)
             declared in the manifest; task.exec { tool = NAME } runs one
  ledger     child report exit, task weekly ok, verb run ok
             the last crossings, oldest first; .kuu/ledger holds ninety days of them
             312 records, each hashing the one before it; the chain is intact
  eval       kuu-eval.md holds 3 entries, the last dated 2026-09-12
  modules    2 of the 4 .lua files below the root bound their exports
    lib.util      VERSION, slug, titlecase
    tools.report  render, write

Installed executables are listed only when declared as tools; project modules
follow the inspection scope (kuu docs scan).
Everything that runs in a project runs through kuu.exe; if something cannot
be done from here, build a tool for it and call it through the door (kuu docs tools).
Read kuu docs agent first: what is expected of you here, and how to report back.
From signed 0.11: read kuu docs upgrading-from-0.11 before running project tasks.
Then kuu docs pitfalls, once; it is where kuu differs from the Lua you know.
```

Modules are listed in the order the manual's table introduces them, which is
roughly the order they are reached for. The descriptor goes to standard output;
`--timings` optionally adds one timing line on standard error. A project whose manifest loads and
declares no task shows `tasks      none` and, on the line beneath, the shape
of a declaration and the page that has it, since an empty manifest is
seldom meant; one whose tasks are all hidden shows `none` and names the
listing that has them. A `tasks.lua` not yet renamed is said in the project
section and carried as `notes` in the descriptor.

`--json` prints one envelope instead. The structural schema below uses `?` for
an omitted optional field; array fields are present even when empty:

```typescript
type CapabilityReport = {
  ok: true; // this command has no failure of its own
  result: {
    timings: { setup: number; inventory?: number; ledger_tail?: number;
               ledger_verification?: number; total: number }; // wall-clock seconds
    kuu: {
      version: string; // N.N: two natural-number components
      lua: string; // the Lua release, "Lua 5.5.1"
      exe: string; // this executable
      verbs: string[]; // the verbs carried as programs, sorted; see below
      pages: string[]; // kuu docs PAGE, sorted
    };
    modules: {
      name: string; // require "NAME"
      page?: string; // its manual page, omitted when it has none
      names: string[]; // everything it exports, sorted
    }[];
    errors: { domain: string; codes: string[] }[]; // err.is(e, DOMAIN, code)
    sets: { name: string; values: string[] }[]; // the closed sets, in their own order
    next: string[]; // what to read and do next, in order: the conduct page first
    project?: {
      root: string; // absolute path of the directory holding manifest.lua
      file: string; // "manifest.lua", or "tasks.lua" from a project that has not renamed yet
      tasks: { name: string; desc: string }[]; // hidden tasks omitted
      tools: { name: string; exe: string; output: string; args?: { [name: string]: string };
               emits: string[]; timeout?: number | string; reach: { [kind: string]: string[] } }[];
      default?: string; // the task kuu run alone runs
      note?: string; // why the manifest did not load or configuration prevented it; tasks is then empty
      config_error?: { domain: "SCAN"; code: "config"; message: string };
      scope?: ScanScope; // normalized rules/provenance; absent if config is invalid
      scan?: ScanReport; // inventory collection metadata; absent if collection did not run
      notes: string[]; // what the text form says beside the inventory: a tasks.lua read as the manifest
      ledger: { last: { at: number; kind: string; name: string; status: string; seconds: number }[]; // the last five crossings, oldest first
                records?: number; intact: boolean; broken?: string; unreadable?: string }; // count only after successful verification; broken locates corruption, unreadable describes a read failure
      eval: { present: boolean; entries: number; last?: string }; // kuu-eval.md at the root: whether it is there, how many entries, and the last one's date
      modules: { name: string; path: string; names: string[] }[];
      modules_complete: boolean; // false if configuration, enumeration or reading a candidate module failed
      module_errors: { path: string; message: string; win32?: number; domain?: string; code?: string }[];
      files: number; // discovered .lua files below the root, whether or not they are modules
    };
  };
};
```

`project` is omitted when there is no project. `kuu list --json` has each
task's dependencies and arguments; they are not repeated here.

The ledger describes execution history. It does not track filesystem changes
or expose an `unaccounted` change count. Source files are inspected here to
build the requested module inventory, independently of task execution.

`ScanScope` and `ScanReport` are defined on the [scan](#kuu-page-scan) page. Scope
exposes normalized mandatory/default/custom exclusions, their fingerprint and
file/default provenance. The scan reports project/starting roots, collection
seconds, completeness, errors, and counts for collected file metadata,
enumerated directories, excluded directories and non-followed links. Scan file
counts include non-Lua files; `project.files` counts discovered Lua files.
`scan.complete` covers collection, while `modules_complete` additionally
covers candidate-module reads. A later unreadable module can therefore make
`modules_complete` false after a complete scan.

`result.timings` is present in JSON whether or not `--timings` was supplied.
`setup` includes imports, palette/project discovery, configuration and manifest
loading, and ends before measured ledger/inventory work. `inventory` measures
collection and static module extraction together; the scan's `seconds` is
nested within it. `ledger_tail` reads recent records and `ledger_verification`
separately measures checking the retained chain. These are elapsed seconds,
not counts or CPU time. An unavailable phase is omitted: without a project,
there is no inventory or ledger phase; invalid configuration omits inventory
while still allowing the ledger descriptor.

`total` covers command work and report assembly, measured from just after the
timing helper loads to just before final serialization/emission and flushing.
Other command imports and final report preparation are included. External wall
time also includes OS process startup and final output, without a promised
bound on the difference. Phases need not add up to total. `--timings` prints
the same measured phases on stderr and leaves JSON on stdout; `--help` prints
no timing line.

`verbs` lists the verbs kuu carries as programs, which is what it can
enumerate; `docs` is one of them. `version` is answered in C before that
dispatch and is not in the list, and `kuu --help` is the complete usage.
`pages` is how the manual shows up in the report, and the text form has a
line of its own for it.

`errors` is every domain kuu raises and the complete set of codes in it, which
is what `err.is(e, DOMAIN, code)` matches against: a code a domain does not
have makes `err.is` answer false for every error, and the handler it guards is
dead. `sets` is the closed sets a result field or an option is drawn from,
such as `ProcStatus`; a literal outside one never matches either. `check`
reports both mistakes where it can see them, and this is the same description
it reads.

<a id="kuu-page-capabilities-errors"></a>

### Errors

The command has no error code of its own. Invalid command arguments use
`CLI usage` and exit 2; `--help` prints usage and exits 0. Everything else
exits 0, including a project whose `manifest.lua` does not load, because a
descriptor that fails is worse than one that says what it could not find out.
Invalid scan configuration appears as `project.config_error` with `SCAN config`,
also in the text descriptor and `module_errors`; tasks, tools and modules are
empty and `modules_complete` is false. `--help` does not read configuration.

---

<a id="kuu-page-adopting"></a>

<a id="kuu-page-adopting-adopting-kuu-in-a-repository"></a>

## Adopting kuu in a repository

How a repository comes to be driven by kuu: one executable of its own, one
`manifest.lua`, and a list of prerequisites it fetches itself. Nothing is
installed on the machine, nothing is shared between repositories, and
nothing is looked up on `PATH`.

```text
repo/
  manifest.lua          the tasks, and the prerequisites as url and sha256
  kuu.exe            this project's pinned runtime; downloaded or committed
  .tools/            downloads and unpacked tools; git ignores it
  .kuu/              kuu's own: the ledger of every crossing, and mem's notebook; git ignores it
  build/             outputs; git ignores it
  src/               whatever the repository is about
```

The examples require 0.10 or later, since they declare their tools. Read
[upgrading to 0.10](#kuu-page-upgrading-010) when moving from 0.9, and the
earlier upgrading pages from further back. A project that already uses signed
0.11 should start with [Upgrading from 0.11](#kuu-page-upgrading-from-011), including
its checklist for project instructions, inspection and history consumers.

<a id="kuu-page-adopting-1-give-the-repository-its-kuu"></a>

### 1. Give the repository its kuu

Each repository owns a particular `kuu.exe` in its root. Another repository
can own a different version. Choose either distribution model; both are
supported, and neither needs a machine-wide install:

| Model | What the repository keeps | What a fresh checkout does |
|---|---|---|
| Downloaded runtime | A reviewed release version, exact asset URL, SHA-256 and expected signing-certificate identity; `/kuu.exe` is ignored | Obtain that exact signed release, verify it as below, then use the local copy |
| Committed runtime | The same reviewed identity and pins, plus the signed `kuu.exe` bytes in Git; `/kuu.exe` is not ignored | Check out the binary, verify it as below, then use it without a runtime download |

Record the pins in the project's README or a committed runtime record. Select
the asset from a specific [release](https://github.com/anafalanx/kuu/releases),
not a moving latest-release URL. The release's `kuu.exe.sha256` supplies the
checksum to review and pin; a newly fetched sidecar must not silently replace
the project's approved hash. Establish the expected signing identity through
the owner's release review, then pin its certificate thumbprint. A valid
signature from a different publisher does not satisfy that pin.

Ignore generated tools, state and outputs in either model:

```text
/.tools/
/.kuu/
/build/
```

Add `/kuu.exe` only for the downloaded model. In the committed model, keep the
runtime as an ordinary binary asset and review upgrades alongside its pins.
Do not substitute an unreviewed local build for the project's signed release.
A project intentionally adopting a development build records its separate
build provenance and hash; the signed-release verification below does not
claim to accept an unsigned build.

<a id="kuu-page-adopting-verify-before-first-execution"></a>

#### Verify before first execution

Read the project's runtime record before running its executable, including
`--version`, `capabilities` or `docs`. Use an already trusted runtime or platform
tools for verification; the candidate must not establish its own initial
trust. This PowerShell example uses the platform's
[Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash)
and [Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature).
It only inspects the file and does not launch it.

Fill all three pin values from the reviewed project record. The release label
identifies the selected release; SHA-256 identifies the exact approved bytes.
The placeholders deliberately fail until replaced. Run from the repository
root, or change `$kuuCandidatePath` to the staged candidate during an upgrade.

```powershell
$kuuRelease = 'N.N'
$kuuExpectedHash = 'REPLACE_WITH_REVIEWED_64_HEX_SHA256'
$kuuExpectedSigner = 'REPLACE_WITH_REVIEWED_40_HEX_CERTIFICATE_THUMBPRINT'
$kuuCandidatePath = '.\kuu.exe'

if ($kuuRelease -notmatch '^[0-9]+\.[0-9]+$' -or
    $kuuExpectedHash -notmatch '^[0-9A-Fa-f]{64}$' -or
    $kuuExpectedSigner -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'Supply the reviewed release, SHA-256 and signing-certificate pins first.'
}
$kuuCandidate = (Resolve-Path -LiteralPath $kuuCandidatePath -ErrorAction Stop).Path
$kuuActualHash = Get-FileHash -LiteralPath $kuuCandidate -Algorithm SHA256 -ErrorAction Stop
if ($kuuActualHash.Hash -ine $kuuExpectedHash) {
    throw 'kuu.exe does not match the approved SHA-256.'
}
$kuuSignature = Get-AuthenticodeSignature -LiteralPath $kuuCandidate -ErrorAction Stop
if ($kuuSignature.Status -ne 'Valid' -or $null -eq $kuuSignature.SignerCertificate) {
    throw "kuu.exe signature was not accepted: $($kuuSignature.Status)"
}
if ($kuuSignature.SignerCertificate.Thumbprint -ine $kuuExpectedSigner) {
    throw 'kuu.exe was signed with a different certificate than the project approved.'
}
Write-Output "Verified kuu $kuuRelease at $kuuCandidate"
```

Verification must succeed before proceeding; do not regenerate pins from a
mismatching candidate. Keep the candidate under project control between the
check and use. An already trusted kuu can instead compare `hash.file` and
`sys.signature` against the same pins; launching the candidate itself to make
those checks would reverse this order. Once verified, use that project copy
for the commands in the rest of this guide.

The first `kuu run` that creates `.kuu/` under a root that no `.gitignore`
ignores it in — the root's own, or one in a directory above it up to the
repository's — says so once, on standard error and as a note in its
`--json` envelope; nothing else reminds you, and nothing fails over it.

<a id="kuu-page-adopting-2-write-manifestlua"></a>

### 2. Write manifest.lua

`manifest.lua` sits at the repository root. It states the minimum kuu version
it needs, lists the prerequisites, and declares the tasks. [Tasks](#kuu-page-task)
has the full contract; this is the shape:

```lua
global none
global <const> require, ipairs, print, error

local NEED_MAJOR, NEED_MINOR = 0, 10

local rt = require "rt"
local task = require "task"
local http = require "http"
local archive = require "archive"
local fs = require "fs"
local hash = require "hash"
local err = require "err"

if not rt.version_at_least(NEED_MAJOR, NEED_MINOR) then
  error(err.new("PROJECT", "version", "requires kuu 0.10.0 or later, found " .. rt.version .. "; copy a supported kuu.exe into the repository root"))
end
task.defaults { timeout = "10m" }

-- What this repository needs, by url and hash.  Nothing else is looked up anywhere.
local PACKAGES = {
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-make-4.4.1-5-any.pkg.tar.zst",
    sha256 = "871f760657a360279f29b945a7fd7d9655fe46a3e1e06dd783c9e74514aa0b27" },
  -- make imports gettext's libintl, which also needs libiconv.
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-gettext-0.22.4-3-any.pkg.tar.zst",
    sha256 = "adb418766c639868e513ab76a1c4676fc63900a183264e7ffa9c1d21a254c45d" },
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-libiconv-1.19-1-any.pkg.tar.zst",
    sha256 = "9a500f38c2b91808741c62fae746b3e9110b33a1ecf5c30fa0c66dbedddf7e16" },
}
-- The tools this repository calls through the door, declared beside the
-- tasks that call them: where each is and what it emits.  See Tools.
task.tool "make" { exe = ".tools/msys2/ucrt64/bin/mingw32-make.exe", output = "lines", timeout = "30m" }
task.tool "tests" { exe = "build/tests.exe", output = "lines" }

task "prereqs" {
  desc = "fetch the tools by hash into .tools",
  run = function()
    if fs.exists(task.tool_get("make").exe) == "file" then return end
    fs.mkdir(".tools/downloads")
    for _, p in ipairs(PACKAGES) do
      local to = ".tools/downloads/" .. fs.basename(p.url)
      if fs.exists(to) ~= "file" or hash.file("sha256", to) ~= p.sha256 then
        local r, e = http.get(p.url, { to = to, sha256 = p.sha256, timeout = "10m" })
        if not r then return nil, e end
      end
      local ok, e = archive.unpack(to, ".tools/msys2")
      if not ok then return nil, e end
    end
  end,
}

task "build" {
  desc = "build with the fetched make",
  deps = { "prereqs" },
  run = function() return task.exec { tool = "make", "-j8" } end,
}

task "test" {
  desc = "run the tests",
  deps = { "build" },
  run = function() return task.exec { tool = "tests" } end,
}

task "clean" {
  desc = "remove build/",
  run = function()
    local ok, why = fs.remove("build", { recursive = true })
    if ok then return true end
    if err.is(why, "FS", "notfound") then
      local info, absent = fs.stat("build", { follow = false })
      if not info and err.is(absent, "FS", "notfound") then return true end
    end
    return nil, why
  end,
}

task.default "test"
```

Three habits make this work:

- **Prerequisites are a list, not a system.** A url and a sha256 per file.
  `http.get { to, sha256 }` refuses a file whose hash differs and places
  nothing; `archive.unpack` opens tar, zip, and zst archives with the tar
  Windows ships. Hashes come from upstream's checksum files or from a first
  fetch inspected by hand; once written down they pin the file forever.
- **Tools are declared by path**, `.tools/...`, and called by the name the
  declaration gives them; nothing is looked up on `PATH`, which is whatever
  the machine has today, and the repository does not depend on it.
- **A task fails by returning `nil, err`** or by a child's exit code
  through `task.exec`. `kuu run` turns that into an exit code and, with
  `--json`, into a record another program can read.

<a id="kuu-page-adopting-3-run-it"></a>

### 3. Run it

```text
.\kuu.exe run                  the default task, with its dependencies
.\kuu.exe run test             a named task
.\kuu.exe run --dry-run test   the plan: what would run, in order, running nothing
.\kuu.exe run --json test      the run as JSON lines on stdout, the outcome the last of them
.\kuu.exe list                 every task with its description and arguments
.\kuu.exe check                manifest.lua and the repository's Lua, without running anything
```

Exit codes: 0 when the task returned, a child's nonzero code when `task.exec`
failed, 1 for another task failure, and 2 when kuu could not start it.
`kuu check` catches an unknown palette export or an undeclared global and
warns about unresolved modules before anything runs, so run it first after
editing.

Then use `kuu list` to load and validate the manifest's declarations. Keep
provisioning inside task bodies: listing executes top-level Lua and is not a
sandbox or a guarantee that required programs are installed.

<a id="kuu-page-adopting-4-keep-state-take-turns-ask-the-machine"></a>

### 4. Keep state, take turns, ask the machine

Use the [shared project environment](#kuu-page-project-environment) recipe when CLI
tools and newly launched editors need the same project-local cache paths.
It keeps those choices independent of the caller's working directory.

For moved checkouts and renamed source directories, use the
[relocation and doctor recipes](#kuu-page-relocation). Their offline checks distinguish
installed tools, cached dependencies and application outputs, and report missing
dependencies without installing them.

The [editor recipe](#kuu-page-editor) demonstrates detached GUI lifetime and isolated
verification. The [native-helper recipe](#kuu-page-native-helper) builds a small
project tool, verifies its cached bytes and creates an ignored local shortcut.
The [reconstruction guide](#kuu-page-reconstruction) separates cached installation,
upstream availability and independent backup, with verified recovery after
an uncertain upload.

- [`mem`](#kuu-page-mem) is a small notebook per repository in `.kuu/memory.json`:
  the last build's hash, a counter, a note for the next run.
- [`sync`](#kuu-page-sync) is a named lock across processes, for the task that two
  agents must not run at once.
- [`sys`](#kuu-page-sys) says what machine this is; [`env`](#kuu-page-env) sets variables
  for the children a task starts; [`proc`](#kuu-page-proc) runs them with decided
  lifetimes and finds the ones already running; [`net`](#kuu-page-net) tells
  whether the service came up.
- [`svc`](#kuu-page-svc) inspects and controls services; [`evt`](#kuu-page-evt) reads the
  event logs. [`sys.signature`](#kuu-page-sys-syssignature) verifies an embedded
  Authenticode signature before a project runs an installer.
- [`sched.deadline`](#kuu-page-sched-deadlines) bounds a sequence of waits, while
  `task.defaults` and [`proc` limits](#kuu-page-proc-limits) bound the children.
  The [cookbook](#kuu-page-cookbook) has complete programs for these jobs.

<a id="kuu-page-adopting-5-upgrading-kuu"></a>

### 5. Upgrading kuu

The project owner decides when to change its pinned runtime. An agent follows
that reviewed choice instead of fetching the latest release, accepting any
runtime that passes the minimum guard, or rewriting pins to match local bytes.

Read the intervening upgrading notes, obtain the chosen signed candidate at a
separate project-owned path, and apply the [pre-execution verification](#kuu-page-adopting-verify-before-first-execution)
to the proposed new pins. For a project coming from signed 0.11, follow
[Upgrading from 0.11](#kuu-page-upgrading-from-011) before loading project code with
the candidate. Reading `docs` is offline and does not load the manifest;
`check` without `--fix` is read-only static inspection. `capabilities` and
`list` execute the manifest to read its declarations.

Validate the candidate with `check` and the project's tests in an isolated
project copy, using the candidate at its expected runtime path. Review task
side effects and external paths so the copy stays isolated. Stop tasks using
the old runtime before replacing the live copy. Retain the old approved runtime
and a separate pre-upgrade history copy if rollback is required: new runs write
ledger v2, which older executables have not been validated to read or append.
Replacing only the executable after those runs is not an established rollback
procedure. Preserve the old and new histories rather than rewriting ledger lines.

In the downloaded model, review and commit the updated runtime record; in the
committed model, review and commit the executable and that record together.
Include changed project instructions, configuration and helpers in the upgrade
review. A signing-certificate change also requires an explicitly reviewed new
identity.

Maintain the project's root `kuu-eval.md` through the upgrade, using
[the reporting format](#kuu-page-agent-reporting-back). Preserve earlier feedback and
append the tested runtime identity, validation results and follow-ups on old
difficulties, including when adoption fails or is deferred. Carry relevant
findings from an isolated validation copy into that project document.

Raise
`NEED_MAJOR` and `NEED_MINOR` only when the recipes begin to require a newer
feature. Compare the components numerically: 0.10 is newer than 0.9. The
[stability statement](#kuu-page-stability) defines this minimum guard and the future
1.x promise; the [roadmap](#kuu-page-roadmap) lists what changed per version.
Repositories upgrade one at a time; there is no machine-wide state to keep
in step.

<a id="kuu-page-adopting-what-not-to-do"></a>

### What not to do

- Do not put kuu on `PATH`, and do not share one `.tools` between
  repositories. The point is that each repository stands alone.
- Do not commit generated `.tools`, `.kuu`, or `build` contents. Commit
  `kuu.exe` when the project chooses the committed-runtime model.
- Do not add an unpinned bootstrap download. The project's runtime record
  explains how to obtain or check out its chosen bytes and verify them before
  first execution; neither model needs a self-updating runtime.
- Do not fetch a prerequisite without its hash. If upstream publishes none,
  fetch once, hash with `hash.file("sha256", path)`, and write it down.

---

<a id="kuu-page-task"></a>

<a id="kuu-page-task-tasks"></a>

## Tasks

A repository declares its tasks once, in a `manifest.lua` at its root, and runs
them with `kuu run`. There is no second file to keep in step: the task list,
each task's description, its dependencies, and its arguments live in the
declaration, and `kuu list` reads them back from there. The same file
declares the [tools](#kuu-page-tools) the tasks call.

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

The programs a task runs are declared as [tools](#kuu-page-tools) beside the tasks,
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

<a id="kuu-page-task-where-kuu-looks"></a>

### Where kuu looks

`kuu run` and `kuu list` walk up from the current directory to the nearest
directory holding `manifest.lua`, make that directory the current directory, and
point `require` at it. A task's relative paths are therefore relative to the
project root wherever the command was typed, children started by a task begin
there, and `require "lib.helper"` in `manifest.lua` reads `lib/helper.lua` of the
project. Without a `manifest.lua` anywhere above, both verbs exit 2 with
`TASK noproject`, naming [Adopting](#kuu-page-adopting). A manifest that loads and
declares no task is not an empty project by accident: `kuu list`, `kuu run`
and `kuu capabilities` say so and name the declaration's shape and this
page; one whose tasks are all hidden is said to be that, with `kuu list
--json` named. A task the command line names that is not declared is `TASK
unknown` with the nearest declared name suggested, and `kuu list` named; a
`task.default` naming a task the manifest does not declare is the same
code, saying it is the manifest's own mistake.

If a wrapper needs the original caller's directory, capture it before launching
`kuu run` and pass it explicitly. `fs.cwd()` inside the manifest already means
the project root. The [working-directory recipe](#kuu-page-working-directories) keeps
caller, wrapper, project and child directories distinct without shell quoting.

Before executing the manifest, both verbs read and validate the root's
[`kuu.config.json`](#kuu-page-scan). Malformed or unreadable configuration is
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
removal date was withdrawn; see [upgrading to 0.11](#kuu-page-upgrading-011).

<a id="kuu-page-task-declaring"></a>

### Declaring

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
| `args` | a [cli](#kuu-page-cli) spec for the arguments after the task name; checked when declared, so a broken spec fails `kuu list` too |
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
[`kuu check`](#kuu-page-check) diagnoses statically known declaration mistakes without
executing the manifest. `kuu list` separately loads and validates declarations:
it does not run task bodies or provision tools for a well-structured manifest,
but arbitrary top-level Lua can have effects. A successful list is not proof
that every tool is installed or every task can run.

`task.default "name"` names what `kuu run` alone runs; without it, `kuu run`
alone lists the tasks and exits 2.

`manifest.lua` is an ordinary Lua chunk and its top level runs on every `kuu run`
and `kuu list`, so keep work inside `run` functions. A syntax error or a raise
while declaring is reported with its line and exits 2.

<a id="kuu-page-task-running-and-failing"></a>

### Running and failing

A task succeeds by returning nothing. It fails by raising, or by returning
`nil, err` — an error of the project's own domain and code, as [err](#kuu-page-err)
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
[proc limits](#kuu-page-proc). When a tool documents successful nonzero exit codes,
accept only the specified codes from `TASK exit`; a timeout or limit failure
must remain a failure. This retains the child's actual outcome in history.
To capture output instead, pass the declared tool's `task.command` result to
[`proc.run`](#kuu-page-proc), then check status, truncation and exit code. That child
has no individual ledger record; the enclosing task/run still do. The
[process recipes](#kuu-page-process-recipes) demonstrate both forms.

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

<a id="kuu-page-task-json"></a>

### JSON

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
The [ledger](#kuu-page-ledger) page describes the history format and its failure
behavior.

Runs do not collect filesystem snapshots or report `scope`, `scans`,
`ledger.observation` or `ledger.publication`. Source inspection has its own
scope and scan reports under [check](#kuu-page-check) and
[capabilities](#kuu-page-capabilities).

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

<a id="kuu-page-task-the-module-in-a-program"></a>

### The module in a program

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
`task.exec { tool = "name", ... }`, are on their own page: [Tools](#kuu-page-tools).

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
original domain and code; [proc](#kuu-page-proc) lists them. A job limit produces
`TASK failed` with its kind in the message, such as `limit (memory)`.

---

<a id="kuu-page-tools"></a>

<a id="kuu-page-tools-tools"></a>

## Tools

Everything that runs in a project runs through `kuu.exe`: a task, a build, a
test, a fetch, and every program a task calls. If the project needs something
kuu cannot do, it builds a tool for it — in whatever technology suits — or
fetches one by hash into its own root, and calls it through the door. Editing
is yours; running is the door's.

A tool is declared in `manifest.lua`, beside the tasks that call it, in the
same shape a task is:

```lua
local task = require "task"

task.tool "report" {
  exe     = "tools/report/report.exe",          -- relative to the project root
  args    = { ["--out"] = "path", ["--since"] = "string", ["--verbose"] = "flag" },
  output  = "ndjson",                           -- ndjson | json | lines | none
  emits   = { "rows", "path" },                 -- the fields its records carry
  timeout = "5m",                               -- unless the call gives one
  reach   = { read = { "src", "build" }, write = { "build" }, net = {} },
}

task.tool "signtool" {
  exe    = ".tools/sdk/signtool.exe",
  args   = { sign = "flag", ["/sha1"] = "string", ["/tr"] = "string" },
  output = "lines",
}

task "report" {
  desc = "the weekly report",
  run = function() return task.exec { tool = "report", "--out", "build/report.json", "--since", "2026-09-01" } end,
}
```

| attribute | |
|---|---|
| `exe` | the program's path, relative to the project root; the one required attribute |
| `args` | the arguments the tool takes, name = type; the types are `flag`, `string`, `path`, `int`, `number`, `duration`, `size`. Absent, the arguments are not described and `check` does not judge them; `{}` says the tool takes none |
| `output` | what the tool writes on standard output: `ndjson`, `json`, `lines`, or `none` (the default) |
| `emits` | the fields its records carry; descriptive, listed by `capabilities`, verified by nothing |
| `timeout` | the child timeout when the call gives none; the default from `task.defaults` after that |
| `reach` | what the tool touches — `read`, `write` and `net` lists; declared and shown, never enforced, since whether a tool can be confined is its own technology's business. [Confined tools](#kuu-page-confined) says what a tool that confines itself must provide |

An unknown attribute raises `TASK usage`, and `kuu check` reports visible
attribute mistakes without running the declaration. A value of the wrong
shape, an invalid tool name, or a name declared twice raises `TASK badvalue`.
Tool names start with an ASCII letter or digit and continue with letters,
digits, `.`, `_` or `-`. For an executable named `g++`, choose a declaration
name such as `cxx`; `cxx` is not a built-in tool.

<a id="kuu-page-tools-calling-one"></a>

### Calling one

```lua
task.exec { tool = "signtool", "sign", "/sha1", thumb, "/tr", "http://ts.example", "build/app.exe" }
task.exec { tool = "report", "--out", "build/r.json", cwd = "build", timeout = "20m" }

local spec = task.command { tool = "report", "--out", "build/r.json" }   -- the same table, resolved
local r, e = proc.run(spec)                                              -- for the output rather than the console
```

`task.exec { tool = "name", ... }` is `task.exec` as before, with the
declaration filling in what the call leaves out: the declared `exe` goes
first, resolved against the `require` root — the project root under `kuu
run`, `kuu list` and `kuu capabilities`, and a program's own directory when
a program loads the manifest itself — and the declared `timeout` applies
unless the call gives one. An `exe` the resolver refuses — a component ending
in a dot or a space, a device path — is refused at the declaration, as
`TASK badvalue`. Everything else — `cwd`, `env`, `limits`,
`maxout` — is the call's. The child runs on kuu's console, its output
streams through, and a non-zero exit is `TASK exit` with the code, as for any
`task.exec`.

`task.command` does the resolving and stops there: it returns the table
`task.exec` would run, for a program that wants the tool's output rather than
its console — a wrapper module, say, that hands the table to `proc.run` and
decodes what comes back. A tool the manifest does not declare is
`TASK unknown` from either. That `proc.run` is the program's own call: the
child has the job and the timeout like any other, but only `task.exec`
crosses the door, so neither the `kuu run --json` stream nor [the
ledger](#kuu-page-ledger) sees it.

The enclosing task and run are still recorded. Capture is a supported choice
when the task needs output bytes; it is not necessary merely to accept a
documented nonzero exit code. The [process recipes](#kuu-page-process-recipes) show
`TASK exit` classification, capture diagnostics, and serializing a command as
separate `argv`, `cwd` and `env` fields rather than a mixed Lua table.

<a id="kuu-page-tools-what-the-door-does-and-does-not"></a>

### What the door does, and does not

Every tool called this way gets what every child of kuu gets: a job, so its
whole tree dies with kuu; the deadline; the limits it was given; a working
directory; the streams read by kuu and nothing else. That is the whole
contract for a fetched tool — `git`, `signtool`, a compiler — which the door
calls as it is and declares as it is. kuu imposes no format on a tool's
output: the declaration says what shape it produces, and the task reads that
shape.

For a tool the project writes, one shape is recommended, for a measured
reason and not as a rule: NDJSON on standard output, one complete record per
line. A tool killed at its deadline then leaves a readable prefix rather than
a truncated document, and kuu's stream reads already deliver lines with
backpressure, so a task can act on each record as it arrives. Arguments
arrive as argv, or as one JSON object on standard input if the tool prefers;
diagnostics go to standard error; failure is a non-zero exit. Nothing here
is required. A tool that writes YAML, or nothing, is declared with the
output it has.

kuu owns exactly one wire: its own output. Every `--json` verb speaks JSON,
and the ledger and `kuu run --json` speak NDJSON. kuu never reads a tool's
protocol, and no tool needs to know kuu's.

<a id="kuu-page-tools-a-tool-that-reads-like-a-module"></a>

### A tool that reads like a module

A tool that wants to be called like a module is wrapped by an ordinary
project module, which is a thing `check` already reads:

```lua
-- tools/yaml.lua
global none
global <const> require
local task, proc, json = require "task", require "proc", require "json"
local M = {}

function M.decode(path)
  local r, e = proc.run(task.command { tool = "yaml", "--json", path })
  if not r then return nil, e end
  if r.code ~= 0 then return nil, require("err").new("YAML", "failed", r.err) end
  return json.decode(r.out)
end

return M
```

`require "tools.yaml"` then reads like any module, `yaml.decode(path)` is
checked as an export of that module, and the call inside is checked against
the `yaml` declaration. No plugin system is needed, and none exists.

<a id="kuu-page-tools-what-check-and-capabilities-see"></a>

### What `check` and `capabilities` see

`kuu check` reads the manifest as text — nothing runs — and takes each
`task.tool` declaration as the literal it is, holding its attributes to the
set above wherever it stands. Then, in every file, a
`task.exec` or `task.command` written with a literal `tool = "name"` is held
to it: a name the manifest does not declare is an error, with the nearest
declared name suggested; an argument that reads as an option name — `-x`,
`--long`, a Windows switch `/x`, or the name in `--name=value` — and is not
in `args` is an error of the same kind as an option a palette call does not
take. Values are not judged: the argument after an option that takes one, a
negative number, a path, `-` and `--` alone. Nor is anything that is not a
literal — a table in a variable, a name computed at run time. Where the
root holds a manifest, a `task.exec` whose table names no `tool` at all is a
warning: the door still runs it, but nothing describes it. A declaration
with a part the text does not show — a computed key, a value built by an
expression — or a name declared more than once is reported and its calls
are not judged, the way a module whose exports cannot be bounded is left
alone. [check](#kuu-page-check) has the details; `check.tools(root)` is the reading
it uses.

`kuu capabilities` lists the tools from the registry the manifest filled when
it ran — the executed reading — with `exe`, `output`, `args`, `emits`,
`timeout` and `reach`. The suite holds the two readings equal, so the manual
can say the checker and the descriptor agree.

Whatever a task installs under `.tools` and never declares is not seen by
either. Declare it, and it is.

---

<a id="kuu-page-confined"></a>

<a id="kuu-page-confined-confined-tools"></a>

## Confined tools

A tool the project builds can confine itself: refuse by default what it was
not granted, and fail rather than ask. kuu names no technology for that and
recommends none; this page says what such a tool must provide, so that a
project choosing one knows what to look for, and it records the one Windows
fact any of them has to deal with.

A confined tool is still called through the door, declared in the manifest
like any other, with `reach` saying what it was granted. The door records
`reach`; it does not enforce it, because it cannot see inside a process it
did not write. Enforcement is the tool's own, and these are its terms.

<a id="kuu-page-confined-what-a-confined-tool-must-provide"></a>

### What a confined tool must provide

- **Refusal by default.** Nothing is readable, writable, or reachable unless
  granted, and a grant names the thing — a directory, a host — not a class
  of things.
- **Failure, never a prompt.** A tool that stops to ask is a tool that hangs
  under a deadline. Whatever it was not granted, it refuses with an exit code
  and a line on standard error, and runs on or stops, but never waits.
- **No way to spawn.** The door's lifetime law is a job around the tool and
  everything it starts. A tool that can start processes is a second door one
  level down, without the job's guarantees inside; a confined tool has that
  ability turned off, or is declared with it and treated as unconfined.
- **Nothing fetched at run time.** Its dependencies are vendored into the
  repository and pinned, the way the project pins everything it fetches by
  hash. A tool that resolves and downloads on first use is not confined, and
  not reproducible either.
- **Its own file access, not the shell's.** A confined tool opens files
  through its own permission check, which brings the fact below into play.

<a id="kuu-page-confined-the-junction"></a>

### The junction

A lexical path sandbox — an allow list of directories, a deny list, or
both — decides by the spelling of a path. Windows decides by what the path
resolves to, and the two disagree at a junction or a directory symlink:

```text
C:\work\app\build            granted
C:\work\app\build\shared  ->  D:\elsewhere            a junction inside the grant
C:\work\app\build\shared\secrets.txt                  spelled inside, resolves outside
```

Every path under the grant is allowed by its spelling, so the tool reads
`D:\elsewhere\secrets.txt` with the sandbox's blessing, and a deny list does
not help, because the spelling never names `D:\elsewhere`. This was
established on 2026-09-12, against a runtime whose permission model is
lexical, and it is a property of the model, not of the runtime.

So a project grants a directory only after looking at what it contains, and
the door supplies part of the look. `fs.dirs` reports directory reparse
points without entering them; it does not inspect file symlinks:

```lua
local fs = require "fs"
local walk = fs.dirs("build")
for _, link in ipairs(walk.links) do
  -- link.path, link.type ("junction" | "directory symlink"), link.target
  print(link.path, "->", link.target)
end
if #walk.links > 0 then
  return nil, require("err").new("PROJECT", "reach", "build holds a link out of itself; refusing to grant it")
end
```

An empty `walk.links` means the directory walk found no directory reparse
points. It does not establish that the tree is free of links: before granting
it, the project must also list the files in each returned directory and
inspect them with `fs.link`, rejecting file symlinks and any inspection failure.
The walk's own `errors` must also be checked. A directory that legitimately
holds a link is granted with that named, or not at all. The complete preflight
is the project's to run, before the grant, every time:
a junction can be made after the check as easily as before it, which is one
more reason `reach` is a declaration and not a promise.

<a id="kuu-page-confined-what-the-record-says"></a>

### What the record says

The evidence for the figures a confined runtime costs — startup, footprint,
the round trip of a call — was measured once, on one runtime, and lives in
the repository's notes rather than here, because a number for one technology
is not a fact about confinement. The manual names no runtime; a project that
chooses one owns the choice and the measurement.

---

<a id="kuu-page-ledger"></a>

<a id="kuu-page-ledger-the-ledger"></a>

## The ledger

The door remembers what passes through it. Every `kuu run` writes one record
per crossing — the run itself, each task, each child a task ran through
`task.exec` — to `.kuu/ledger/<day>.ndjson` under the project root, from
what kuu directly knows about execution. It answers "what ran here, and how
did it end", kept locally for ninety days. A child a task starts with
`proc.run` itself, a `task.command` table included, is the program's own call
and not a crossing.

```text
.kuu/ledger/2026-09-21.ndjson      one record per line, the day in UTC
```

Add `.kuu/` to the project's `.gitignore`, as for [mem](#kuu-page-mem). The ledger
is the machine's, not the repository's; a summary a project wants to keep
is the project's to commit.

A normal run does not scan the project tree, compare file changes, maintain
a filesystem index or start a watcher. The ledger describes execution, not
which files changed or which process caused an edit. [Checking](#kuu-page-check)
and [module inventory](#kuu-page-capabilities) inspect source when requested; their
[scan configuration](#kuu-page-scan) does not add filesystem tracking to a run.
Programs can still explicitly use [fs.watch](#kuu-page-fs).

<a id="kuu-page-ledger-a-record"></a>

### A record

```json
{"v":2,"kuu":"0.12","root":"C:/work/app","git":{"ref":"refs/heads/main","head":"7c1a…"},
 "kind":"child","name":"report","tool":"report","task":"weekly","pid":4120,
 "argv":["C:/work/app/tools/report/report.exe","--out","build/r.json"],
 "at":1789980000.1,"seconds":3.2,"status":"exit","code":0,"bytes":{"out":8192,"err":0},
 "prev":"5e9d…"}
```

| field | |
|---|---|
| `v` | the record's schema version, 2 for new execution-history records |
| `kuu`, `root`, `git` | which runtime and project; best-effort `git.head` and `git.ref` read once when opening the ledger, before task execution, from `.git` itself without `git.exe`; absent without a readable repository, `ref` alone on a branch not yet born, `head` alone when HEAD is detached. This is repository identity, not a dirty-state report |
| `kind`, `name` | `verb` (`run`), `task` (its name), or `child` (the tool's name, else the program) |
| `task`, `tool` | for a child, the task that ran it and the declaration it ran through, when it did |
| `argv`, `cwd`, `pid` | what ran, from where, as what; `cwd` only for a child whose call gave one, and an absent field is absent, never `null` |
| `at`, `seconds` | when it began, as an instant, and how long it took |
| `status`, `code`, `bytes`, `error` | how it ended: a child's `exit`, `timeout`, `killed`, `limit` or `error`, with its code when available, and the bytes on each stream when kuu relayed them (under `--json`; a child on the console has kuu's own streams and nothing is counted); a task's or the run's `ok` or `failed` with the error |
| `prev` | the SHA-256 of the record line before this one, across days |

The three kinds, as a reader would type them:

```typescript
type LedgerRecord = Common & (
  | { kind: "verb"; name: "run"; task?: string;       // the task that ran: the one named, else the default
      argv: string[];                                  // the arguments after `kuu run`, as typed
      status: "ok" | "failed"; code: number;           // kuu's exit code
      error?: LedgerError }
  | { kind: "task"; name: string;
      status: "ok" | "failed"; error?: LedgerError }
  | { kind: "child"; name: string; task: string; tool?: string;
      argv: string[]; cwd?: string; pid: number;
      status: "exit" | "timeout" | "killed" | "limit" | "error"; code?: number;
      limit?: "memory" | "cpu" | "processes";
      bytes?: { out: number; err: number } });
type Common = { v: 2; kuu: string; root: string;
  git?: { head?: string; ref?: string };
  at: number; seconds: number; prev?: string };
type LedgerError = { domain: string; code: string; message: string; exit?: number };
```

A task's `error` is what its `run` returned or raised, with the domain and
code the project chose. `exit` is optional: an in-task `CLI usage` error
without an explicit exit value leaves it absent and makes kuu exit 2.
The verb carries the same domain, code and message; its own `code` always
states kuu's exit status. A child that timed
out or hit a limit is recorded with that `status` and no `error`: the
failure is the task's, and its message names the child. `prev` is absent
only on the first record ever kept.

Each append uses the canonical project identity and a named [lock](#kuu-page-sync),
so cooperating runs in the same Windows session, including nested runs and
aliases of one root, append to the same chain. The lock covers history work,
not task execution. Different logon sessions or machines do not share that
coordination guarantee. If the root cannot be canonicalized, recording fails
instead of using an unrelated lock for its spelling.

<a id="kuu-page-ledger-existing-history"></a>

### Existing history

Readers and chain verification accept both schema versions 1 and 2. New
records use version 2 and omit `delta` and `observation`. An existing
version-1 line is never rewritten to fit the new schema: its original bytes
remain the input to the hash chain. A day file can contain both versions.
Normal ninety-day retention still applies.

Version-1 `delta` and `observation` fields are historical data only. Earlier
releases and development builds gave them different completeness guarantees;
their presence does not establish current file state or attribute an edit to
a particular process. A reader that needs only execution history can ignore
them. An existing `.kuu/ledger/tree.json` is ignored and left untouched;
there is no replacement baseline, migration scan or publication step.

0.12 writes these execution-history records. The record's `v` identifies its
schema independently of the runtime version; see
[Upgrading from 0.11](#kuu-page-upgrading-from-011) for report and history migration.

<a id="kuu-page-ledger-history-costs"></a>

### History costs

Execution-history work does not grow with the number of project source files.
To append a crossing, kuu finds the newest line by examining the end of the
latest nonempty day file. Recent-history lookup also searches backward for the
requested lines, preserving their original order. These lookups avoid scanning
every earlier line in Lua, but the underlying day files are still read in full;
their I/O and memory cost can grow with history size. No persisted tail cache
is trusted in place of the actual history.

`capabilities` verifies every retained record and hash link. Its
`ledger_verification` timing therefore grows with retained history.
`ledger_tail` measures recent-history retrieval separately; `run` reports
opening and appending history as `ledger`. Corruption and read failures remain
explicit. The [run report](#kuu-page-task) describes those timings and the per-run
record summary.

The whole reader, and the question it most often answers — which task
failed last, and why:

```lua
global none
global <const> require, ipairs, print, table
local fs, json = require "fs", require "json"
local dir = ".kuu/ledger"
local names = {}
for _, e in ipairs((fs.list(dir) or { entries = {} }).entries) do
  if e.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = e.name end
end
table.sort(names)
local failed
for _, name in ipairs(names) do
  for line in (fs.read(fs.join(dir, name)) or ""):gmatch("[^\n]+") do
    local record = json.decode(line)
    -- the task that failed, not the run that ended on it
    if record and record.kind == "task" and record.status == "failed" then failed = record end
  end
end
if failed then print(failed.kind, failed.name, failed.error.domain, failed.error.code, failed.error.message) end
```

The chain is the point of `prev`. Nothing prevents editing a line — the file
is text, the directory is yours — but an edited line no longer hashes to
what the next record says, and `kuu capabilities` finds it: every time it
reads the ledger it walks the whole chain and says whether it is intact,
at which line it breaks, or why it could not be read completely. Records
older than ninety days are removed as new ones are written; the first record
kept then names a line that is gone, and the walk takes it as the anchor.

Only `kuu run` writes the ledger, and only once its plan is checked and a
task is about to run: `--dry-run`, an unknown task and a wrong argument
write nothing. `kuu list` and `kuu capabilities` run `manifest.lua` to read
its declarations and write no crossing records; `kuu check` runs no project
code. A child the manifest starts at its top level is not a crossing of any
run.

<a id="kuu-page-ledger-reading-it"></a>

### Reading it

`kuu capabilities` shows the last crossings, oldest first, and in its
descriptor `project.ledger.last` carries `at`, `kind`, `name`, `status` and
`seconds` for each; `records` is how many the ledger holds after successful
verification, `intact` whether each hashes the one before it, with `broken`
naming the file and line where that fails. Invalid JSON or an object without
the record's common fields is a broken record too, and is omitted from `last`.
Both descriptor forms report the broken chain even when no recent record can
be read. An unreadable day file or incomplete directory listing sets `intact`
to false and `unreadable` to the filesystem diagnostic; the unverified
`records` count is omitted. Absence is an empty ledger, but a read failure is
never verified emptiness. `last` is empty when its required day files cannot
be read. The files are plain NDJSON: `fs.read` and `json.decode` one line at a
time is the whole reader. There is no `unaccounted` change count.

A ledger that cannot be opened or written — a read-only tree, a lock held
too long, a record holding text that is not UTF-8 — is said once on
standard error, and the run goes on: the record is the door's, never a
condition on the work. A task's error message that is not UTF-8, which a
child's output in the console code page often is, is recorded and reported
with each such byte as U+FFFD. Failures also appear in the JSON envelope's
`notes`; they preserve the task's outcome. Once ledger opening is attempted,
`result.ledger` reports how many records this run appended and whether all
its attempted records were written, with a structured `error` after an opening
or recording failure. A failed open reports `records:0`, `complete:false` and
the error. A dry run or preflight failure has no ledger summary.

If the preceding record cannot be read, the new record is refused with the
same warning and `notes` behavior. The run continues without starting a new,
unchained history behind the unreadable file.

---

<a id="kuu-page-check"></a>

<a id="kuu-page-check-check"></a>

## check

`kuu check` says what can be known about Lua files without running them, and
nothing more.

```text
kuu check [--json] [--timings] [--fix [--adopt]] [PATH ...]
```

Without paths it checks every `.lua` file below the nearest project (the
directory holding `manifest.lua`, or a `tasks.lua` not yet renamed, which it
then says on standard error and as `notes` under `--json`), or below the
current directory when there is no project. Automatic discovery always skips
`.git` and `.kuu`; by default it also skips `.tools`, `build`, `node_modules`,
`.cache`, `.local`, `.venv`, and `__pycache__`. Paths may
be files or directories; `require` names always resolve against the project
root.

The root's [`kuu.config.json`](#kuu-page-scan) controls this scope. Its exact directory
names and project-relative paths are excluded before descent; `defaults:false`
restores visibility of the optional defaults. A maintained source directory
called `build` or `.local` therefore needs an override or an explicit check.
The command loads configuration once, including across a `--fix` recheck, and
does not execute the manifest. A broken manifest can still be checked.

Automatic discovery skips directory junctions, directory symlinks and other
name-surrogate directory links the native walker refuses to enter. Discovered
file symlinks are skipped too. Their targets are neither selected for checking
nor rewritten by `--fix`. Ordinary filter/cloud reparse metadata does not by
itself exclude a file or directory.

An explicitly named ordinary file or subdirectory is checked even when an
ancestor is a link or an excluded directory. A starting directory overrides
its own exclusion; descendant exclusions still apply. A CLI argument naming the link itself is rejected with
`CHECK notfound`, as before; name a file or ordinary subdirectory within it
to check that content deliberately. The Lua `check.tree(dir, root)` API follows
its explicitly supplied starting directory, including a linked root, and skips
links discovered beneath it.

These are discovery rules, not filesystem confinement: literal `require`
resolution may still read module text through linked ancestors, and replacing
an ancestor during checking is outside this guarantee.

Four things are checked:

- **It parses.** Each file goes through Lua 5.5's own compiler, text only, the
  way kuu would load it. A syntax error is reported with its line. Under a
  declared-only global scope (for example, after `global none`), the compiler
  also refuses an undeclared global, so the classic typo is an error here.
  `global *` permits undeclared globals, and a declaration inside a block
  does not make the rest of the file declared-only.
  A file that does not compile gets that one error, and the missing-`global`
  warning below if that applies, and nothing else: its requires are not
  listed and no other check is made until it parses, since the text they
  read is not yet a program.
- **It declares its globals.** A file with no `global` statement at all gets a
  warning, because in that file an undeclared global is silently nil at run
  time. [Pitfalls](#kuu-page-pitfalls) says how to start a file.
- **Its requires resolve.** Every literal `require "name"` is listed. A name
  that is neither one of kuu's modules nor a file under the root
  (`name.lua` or `name/init.lua`, dots as directories) is a warning with its
  line. A program with no requires has only stock Lua's `io` and `os`, and
  this listing is how an agent sees what else a file asks for before running
  it.
- **Its palette names exist.** After `local files = require "fs"`, an
  access such as `files.exist(path)` is an error:
  `files.exist is not a name in fs; did you mean files.exists?`
  Aliases, multiple local declarations, and parenthesized or long-string
  require literals work. Both functions and exported data fields count.

Strings and comments contribute no requires or field accesses. The checker
opens kuu's own public modules to read their export tables; it never runs
the checked file. Dynamic indexing such as `files[name]` is left alone.

**A project's own modules are checked too, from their text.** Project code is
never executed, so the exports of `require "tools.project"` are read by
scanning the module for what it assigns to the table it returns -- the
`function M.name` and `M.name =` forms. In a consuming project this is the
larger half of the checking: Time Actual reaches through one such module 210
times.

The extraction over-approximates deliberately. A field wrongly included costs
only a missed diagnostic; one wrongly excluded is a false positive on correct
code, which is far more expensive. So when the export set cannot be bounded
the module is left unchecked entirely rather than guessed at: a computed key
(`M[name] = ...`), a metatable, a return that is not a plain local, or a local
that was not built as a table in that file. Passing or aliasing that table
also puts its exports out of reach, since another reference can add names.
Redeclaring the returned local likewise leaves its exports unchecked.

Name checking follows direct local require bindings and lexical scopes.
Parameters, block locals, and loop variables can shadow an alias. If an
alias is reassigned anywhere, its field accesses are skipped throughout
that binding's scope, including captured uses in functions. This avoids
claiming to know a value that control flow may replace. Simple copied local
bindings are followed where their origin remains known; passing a value through
function arguments or arbitrary function results does not infer its identity.
Shadowing or reassigning `require` likewise stops treating it as
kuu's loader in that scope.

A module indexed where it is required is followed too:
`require("rt").version == "0.5"` reports exactly as it would through a local
binding, and so does `require("proc").run { cwdd = "x" }`. Such an expression
has no binding to shadow or reassign, so nothing can make it uncertain. The
module name must be a literal, as it must be everywhere else here; a computed
`require(name)` says nothing and is left alone.

Four things are checked against kuu's own interface before those expressions
run. A code its domain does not have,
so `err.is` answers false for every error and the handler it guards is dead:
`err.is(e, "PROC", "notfund")`. An option a call does not take:
`proc.run { cwdd = "x" }`, which the runtime raises on, but only if the line
is reached. A closed set compared with a literal outside it, such as
`rt.route == "flie"`, which likewise never matches. And `rt.version` compared
by text: public versions use `N.N`, two natural numbers, and lexical order
would put `"0.11"` before `"0.9"`. Use `rt.version_at_least(0, 11)` for a
minimum version.

Error *domains* are not checked, only the codes within a domain kuu owns.
`err.new` is public and a project names its own domains, so an unfamiliar one
says nothing about correctness.

Beyond these, ordinary calls are not type-checked: argument counts, option
values, and types still belong to runtime validation. Task and tool declarations
add the bounded checks below.

<a id="kuu-page-check-task-and-tool-declarations"></a>

### Task and tool declarations

The checker recognizes both `task "name" { ... }` and `task("name", { ... })`,
and the corresponding `task.tool` forms. Simple local aliases of the module,
tool constructor or saved curried constructor retain their identity until
shadowing or reassignment makes them uncertain. Checked code is never executed.

Literal names must follow the runtime rule: start with an ASCII letter or
digit, then use letters, digits, `.`, `_` or `-`. `g++` is invalid; `cxx` is
an example replacement chosen by a project, not a built-in tool.

Visible declaration keys are checked even when another field is dynamic.
For example, `task "build" { run = function() end, timeout = "5m" }` reports
the misplaced `timeout` at its source line and points to `task.exec`,
`task.defaults` or `task.tool`. A function body does not hide an unknown key.
Independently known field types, array shapes, argument schemas and tool
durations are checked when the literal supplies enough information. Dynamic
values and fields whose final value is uncertain are left to runtime
validation; the checker does not evaluate expressions to guess their values.
A dynamic value may produce nil and omit a field, so it does not establish
that an unknown key is actually present. Computed or repeated keys can also
make the final value uncertain.

Run `kuu check` first, then `kuu list` for manifest-loading validation. Listing
executes top-level Lua and therefore requires a manifest that keeps work in
task bodies. It is not a provisioning check or proof that tools exist.

**The manifest's tools are checked the same way.** Each
`task.tool "name" { ... }` in `manifest.lua` is read as the literal it is —
nothing runs — and every `task.exec` or `task.command` written with a
literal `tool = "name"`, in any file under the root, is held to it: a name
the manifest does not declare is a `name` error with the nearest declared
name suggested when the manifest's tool names are bounded. A dynamic tool
name can provide or replace any declaration, so consumer tool-name and option
checks are then left to runtime. An argument that reads as an option name and is not in
the declaration's `args` is an `option` error, as for a palette call. The
declaration itself is held to `task.tool`'s attributes, in the manifest or
any other file and in either spelling: `outputt` is an `option` error with
`output` suggested, found here rather than when the declaration runs. An
option name is `-x`, `--long`, or a Windows switch `/x` — not `-` or `--`
alone, not a negative number, not a path — and `--name=value` is judged by
its name and supplies its own value. `--` ends option checking; subsequent
arguments are positional. The value an option takes is skipped: after `--out`, declared as a
`path`, the next argument is its value whatever it looks like. Anything not
a literal is not judged, and a declaration without `args` leaves its
arguments undescribed. Under a root that holds a manifest, a `task.exec`
whose table names no `tool` at all is a `tool` warning: the door still runs
it, but nothing describes it; a table the checker cannot see into, or a
`tool` whose value is not a literal, is neither warned about nor judged. A
declaration with a part the text does not show — a computed key, a value an
expression builds — and a name declared more than once are `tool` warnings
too, and their calls are not judged, the way a module whose exports cannot
be bounded is left alone. A manifest that does not parse is one syntax
error, and no call anywhere is judged against it. [Tools](#kuu-page-tools) has the
declaration.

<a id="kuu-page-check-fixing-the-declaration"></a>

### Fixing the declaration

`--fix` writes each file's global declaration: it adds the standard names the
chunk uses and removes the ones it does not, then checks the files again so
the report describes what is now on disk.

It knows nothing about Lua's scoping rules, because the compiler already does.
Under a global declaration the compiler names each undeclared variable in
turn, so the needed set is found by compiling and reading the complaint; and a
declared name is unnecessary when removing it still compiles in declared-only
mode. Removing the final unused name leaves `global none` behind.

The fixer handles plain name lists, optionally with a leading `<const>`, at
the start of the file after its comments. Initialized declarations and other
forms it cannot preserve are reported as not fixed and left byte for byte
unchanged. Initializer expressions are never dropped or executed by fixing.
Leading long comments, including license headers with `--[=[ ... ]=]`
delimiters, are kept outside declarations inserted by `--adopt`.

The direction that matters is removal. Forgetting to add a name is a loud
load-time error and fixes itself; forgetting to remove one when its last use
goes is silent forever, so a hand-kept list rots in one direction only.

**A name is only ever added when this runtime has a global by that name.**
`global none` exists so that a misspelling is a load-time error, and a fixer
that declared whatever the compiler complained about would answer
`print(reuslt)` by declaring `reuslt` -- turning a caught mistake into a silent
nil. Such a file is reported as not fixed, with the reason, and left alone
with its error intact.

A file with no global declaration at all is left alone unless `--adopt` is
given, since switching a chunk to declared-only mode is a larger change than
correcting a list that is already there. Nothing else in the file is touched:
a declaration that merely wraps differently is not rewritten, and the file's
line endings are written back as they were, so correcting two lines of a CRLF
file does not rewrite every line of it.

With no paths it rewrites every `.lua` file below the nearest project root,
which is the same set it checks.

```text
app.lua:
  + tostring, ipairs
  - select, math
typo.lua: not fixed: `reuslt` is not a global this runtime has; it reads like a misspelling, and declaring it would hide one
kuu: 6 files, 1 fixed, 1 errors, 0 warnings
```

```text
bad.lua:1: unexpected symbol near '='
strict.lua:2: variable 'print' is not declared
app.lua:12: "notfund" is not a code in PROC, so this never matches; did you mean "notfound"?
app.lua:19: cwdd is not an option of proc.run; did you mean cwd?
app.lua:24: rt.version is N.N (two natural numbers) and is never compared by text; use rt.version_at_least(...)
lib/helper.lua: warning: no global declaration: an undeclared global is not an error here; start with `global none`
ghost.lua:3: warning: require "nothere" names no kuu module and no file under C:/work/app
kuu: 6 files, 5 errors, 2 warnings
```

Findings go to standard output, one per line, relative to the root; the
summary goes to standard error. Exit 0 when there are no errors (warnings do
not fail a check), 1 when any file has an error, 2 for a usage mistake or a
path that is not there.

`--json` prints one envelope instead. The structural schema below uses
`?` for an omitted optional field; array fields are present even when empty:

```typescript
type CheckReport = {
  ok: boolean; // no file errors and no path-selection error
  error?: { domain: "CHECK"; code: "notfound"; message: string };
  result: {
    root: string; // absolute path
    scope: ScanScope; // normalized configured rules and provenance; see scan
    scans: ScanReport[]; // one per actual directory collection, including --fix rechecks
    complete: boolean; // every collection/source read succeeded; syntax findings do not change this
    timings: CheckTimings;
    notes: string[]; // what was also said on standard error: a tasks.lua read as the manifest
    fixed?: { path: string; added: string[]; removed: string[] }[];   // --fix only
    unfixed?: { path: string; message: string }[];                    // --fix only
    files: {
      path: string; // relative to root when under it, otherwise as reported
      errors: CheckError[];
      warnings: CheckWarning[];
      requires: string[]; // unique, sorted literal module names
      tools: ToolDeclaration[]; // the manifest's declarations the text bounds; empty in every other file
    }[];
    errors: number; // total error count
    warnings: number; // total warning count
  };
};
type CheckTimings = { setup: number; checking?: number; scan?: number; fixing?: number; total: number };
type CheckConfigFailure = {
  ok: false;
  error: { domain: "SCAN"; code: "config"; message: string };
  result: { root: string; complete: false; scans: []; timings: CheckTimings };
};
type CheckError =
  | { kind: "read" | "syntax" | "analysis"; line: number; message: string }
  | { kind: "name" | "code" | "option" | "value"; line: number; message: string;
      module: string; name: string; suggestion?: string };
type CheckWarning = {
  kind: "globals" | "require" | "tool"; line: number; message: string;
};
type ToolDeclaration = {
  name: string; line: number; exe: string; output: string;
  args?: { [name: string]: string }; emits: string[]; timeout?: number | string;
  reach: { [kind: string]: string[] };
};
```

Each error and warning carries `line` (0 when it is about the whole file) and
`message`. The closed set of error kinds is `read` (cannot read the file),
`syntax` (Lua compilation, including undeclared globals), `analysis` (a valid
Lua chunk that the additional static inspection could not process), `name` (an unknown
palette export), `code` (an error code its domain does not have), `option`
(an option a call does not take), and `value` (a closed set compared with a
literal outside it, `rt.version` compared by text or matched to its end by
a three-component pattern included — public versions have two components
from 0.11 onward, so that guard cannot match, and the finding names
[upgrading to 0.11](#kuu-page-upgrading-011). A pattern that reads two components,
or one, is left alone; `rt.version_at_least` is the recommended minimum
version check). A malformed
literal tool declaration is also a `value` finding, with `module` set to
`task.tool` and `name` to the tool's declared name; it is omitted from `tools`
and its calls are not judged. For other `value` findings,
`name` is the literal that was written. Warning kinds
are `globals` (no declaration), `require` (unresolved module), and `tool` (a
tool declaration the text does not bound, or a program run through the door
with no declaration). For `name`,
`code`, `option` and `value`, `module` and `name` identify what was written
and `suggestion` is the nearest real spelling, omitted when none is close.

`fixed` and `unfixed` are present only with `--fix`: the declarations that
were rewritten, and the files that were left alone with the reason.

`ScanScope` and `ScanReport` are defined on the [scan](#kuu-page-scan) page. Scope
includes mandatory/default/custom rules, their fingerprint and whether the
configuration came from a file or defaults. A scan records its actual project
root and starting directory, completeness, counts, errors and collection
seconds. File counts in a scan include all collected metadata entries;
`result.files` contains the Lua files actually checked. Deliberately skipped
directories and non-followed links are separate counts, not read failures.
An explicit-file-only invocation has `scans:[]`. A starting directory outside
the project reports `path_rules_applied:false`: project-relative path rules
do not apply there, while basename rules still do.

Exit 0 or 1 produces this envelope, with no summary on stderr unless timings
were requested. An explicitly named missing path exits 2 with `CHECK notfound`;
JSON preserves any files and scans already collected, sets `complete:false`
and adds the top-level error. If initial path selection fails, `--fix` writes nothing.
Invalid command arguments still print a diagnostic on stderr before a report
is available, even with `--json`. Invalid or unreadable scan configuration also
exits 2, with a `SCAN config` diagnostic and the `CheckConfigFailure` shape
under `--json`.
`--help` prints usage and exits 0 without reading configuration.

`timings` is always present in JSON, in wall-clock seconds. `--timings` adds
one human-readable timing line on stderr, independently of `--json`:

- `setup` covers command imports, argument parsing, project discovery and
  configuration loading.
- `checking` covers path selection, collection, source reads and static
  checking, accumulated across initial and `--fix` rechecks.
- `scan` covers directory collection only, nested within `checking`. It is
  omitted when no directory was collected.
- `fixing` covers the fixer and writes, excluding subsequent rechecking;
  it is omitted when the fixer did not run.
- `total` ends after report assembly, including all rechecks, before final
  JSON serialization or human-report emission and flushing.

Phases overlap; adding them does not produce total. The clock starts after the
timing helper loads, before the other command imports. OS process startup and
final emission can make external wall time larger without a promised bound.
Unavailable phases are omitted. `--help` prints no timing line.

In a program, `require("check").file(path, root)` returns
`{path, errors, warnings, requires, tools}` with an absolute `path` and the
same finding kinds; `tools` holds the manifest's declarations when the file
is the manifest, and is empty otherwise. `check.tree(dir, root)` returns
`{root, reports = {...}, complete, scan}`. Either spelling of `root` — backslashes, a
trailing slash, a relative path — is taken as `fs.absolute` spells it.
An unreadable directory or incomplete listing contributes a `read` finding
at the directory's path, with line 0 and the filesystem diagnostic. The
remaining readable files are still checked, and the command exits 1.
Intentionally skipped links do not produce read errors.
Each public call reads the current manifest; a tree check shares its parsed
declarations only for that operation, including a fresh pass after `--fix`.
`check.tree` and `check.modules` each load scan configuration once per
operation. `check.file` deliberately checks its named file without loading
scan configuration, so it remains usable while that configuration is broken.
A configuration failure makes `check.tree` return a `config_error` and one
synthetic report at `kuu.config.json`, marked `configuration = true`, with a
line-0 `config` finding carrying the error's `domain`, `code`, and message.
Its `complete` is false and `scan` is omitted because collection never ran.

The exported `check.PRUNE` table remains a compatibility hook. Changing it
adds native wildcard exclusions to direct tree/inventory calls that load their
own policy; it cannot remove
mandatory or configured exclusions. Its untouched legacy default does not
override `kuu.config.json`. Prefer the declarative configuration for project
policy; its rules are exact names and paths, never wildcards. Commands retain
their captured context: a manifest cannot change the current capabilities
inventory by mutating `check.PRUNE`.

The extraction above is reachable on its own. `check.exports(path)` is the set
of names a module exports, read from its text, or nil when the text does not
bound them; `check.modules(root)` returns
`{root, files, modules = {{name, path, exports}, ...}, complete, errors, scan}` -- every `.lua` file
below the root that a `require` name could reach and whose exports it could
bound, in name order, with `files` counting all discovered `.lua` files.
Unicode names follow the loader's rules; a literal dot in a filename is not
a directory separator, and a project file hidden by a bundled module is not
advertised. `complete` is false if a listing or candidate file could not be
read; `errors` is an array of `{path, message, win32?}` describing each failure.
Invalid configuration also sets `complete = false`, returns `config_error`,
omits `scan`, and leaves `files` at zero and `modules` empty. Its error entry carries
`domain = "SCAN"` and `code = "config"` as well as the path and message.
Inventory uses the same discovery rules as `check.tree`: discovered links
are excluded from `files` and `modules`, while a deliberately supplied linked
root is followed. Excluding links does not make an inventory incomplete.
The `scan` report describes collection only: its `complete` can be true while
a later candidate-module read makes the outer inventory `complete` false.
[capabilities](#kuu-page-capabilities) reports what it returns. `check.tools(root)`
is the manifest's tool declarations as the checker reads them, in declaration
order, only those the text bounds; `capabilities` lists the same tools from
the registry the manifest filled, and the suite holds the two readings equal.

<a id="kuu-page-check-errors"></a>

### Errors

The command's complete `CHECK` code set is `notfound`, for an explicitly
named path that is neither a file nor a directory. Invalid command arguments
use `CLI usage`. The checking module returns findings rather than `nil, err`;
a file-read or directory-enumeration failure is a `read` finding containing the underlying `FS`
diagnostic. Filesystem argument errors retain their original domain and code.
The configuration loader's complete `SCAN` code set is `config`, for malformed,
unsupported or unreadable `kuu.config.json`; the message identifies the field
or read failure. Exclusions affect discovery, not runtime `require` resolution.

---

<a id="kuu-page-scan"></a>

<a id="kuu-page-scan-scan-configuration"></a>

## Scan configuration

`kuu.config.json` controls project inspection by checking and module
inventory. It is read and validated without executing
`manifest.lua`. `kuu check`, `kuu run`, `kuu list` and `kuu capabilities`
validate it before loading project code; each operation keeps its captured
policy. A missing file selects the defaults below. A normal `kuu run` does
not scan the project tree or track file changes; validating configuration does
not start an inspection.

<a id="kuu-page-scan-configuration-file"></a>

### Configuration file

The file belongs at the project root, next to `manifest.lua`, and is intended
to be tracked with the source. It contains UTF-8 JSON, optionally with a BOM:

```json
{
  "v": 1,
  "scan": {
    "defaults": true,
    "exclude_dirs": ["artifacts"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

`v` is required and must be the number `1`. `scan` is optional; omitting it
is the same as `"scan": {}`. `defaults` is optional and defaults to `true`.
Both rule arrays are optional and default to empty arrays. No other keys
are accepted at either level, and objects and arrays are distinct: use `[]`
for an empty rule list. A missing file selects the default policy; an empty,
malformed or unreadable file is a configuration error in the loader.

The two kinds of rule have different meanings:

| Rule | Meaning | Example |
|---|---|---|
| `exclude_dirs` | An exact directory basename at any depth | `"artifacts"` excludes `artifacts/` and `src/artifacts/` |
| `exclude_paths` | An exact directory subtree relative to the project root | `"vendor/generated"` excludes that subtree, but not `src/vendor/generated/` |

A directory rule excludes the directory and its descendants, not a file
with the same name. These are exact names, not patterns: `"artifact"` does
not match `artifacts/`. No `.gitignore` files are parsed and no `git.exe`
is needed. Being ignored by Git does not itself exclude a path from kuu's
inspection.

<a id="kuu-page-scan-defaults-and-deliberate-overrides"></a>

### Defaults and deliberate overrides

The policy separates mandatory exclusions from optional defaults:

| Kind | Directory basenames, at any depth |
|---|---|
| Mandatory for project scans | `.git`, `.kuu` |
| Optional defaults | `.tools`, `build`, `node_modules`, `.cache`, `.local`, `.venv`, `__pycache__` |

Explicit rules add to these sets. `"defaults": false` disables the entire
optional set, while `.git` and `.kuu` remain mandatory for project scans.
For example, this policy includes maintained source named `build/` or
`.local/`, while still excluding `.tools/`, `node_modules/` and one generated
subtree:

```json
{
  "v": 1,
  "scan": {
    "defaults": false,
    "exclude_dirs": [".tools", "node_modules"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

This matters when a conventional generated-directory name holds maintained
source. There is no negation or include rule; disable the defaults and name
the exclusions that belong to the project.

An explicitly named checker file or starting
directory overrides its own exclusion, including an excluded ancestor.
Descendant directory exclusions still apply. A project's root is always the
starting point; its own basename never prunes the whole project. These
overrides do not change the link-target rules in [check](#kuu-page-check).

Exclusions control inspection only. They do not prevent a task from running,
change `require` resolution or provide a sandbox. A module omitted from an
inventory can still be required or inspected to resolve a literal require.

<a id="kuu-page-scan-normalization-and-validation"></a>

### Normalization and validation

Rules normalize backslashes to `/`, fold ASCII `A`–`Z` to `a`–`z`, then sort
and deduplicate. For example, `"Vendor\\Generated"` and
`"vendor/generated"` in `exclude_paths` become one rule. The match convention
is deliberately ASCII-only, not general Unicode Windows case equivalence:
`"École"` and `"école"` remain different names. Unicode normalization is not
performed either.

The loader rejects:

- Absolute, UNC, drive-relative or stream paths, such as `"C:/build"`,
  `"C:build"`, `"/build"` or `"file:stream"`.
- Leading, trailing or repeated separators, and `.` or `..` components.
  Write `"vendor/generated"`, not `"./vendor/generated/"`.
- Any separator in `exclude_dirs`; use `exclude_paths` for a subtree.
- Wildcard characters `*`, `?`, `[` and `]`. Braces are literal characters,
  so `"{artifacts}"` names that exact directory, not a pattern group.
- Windows-invalid component characters `<`, `>`, `:`, `"`, `|`, U+0000
  through U+001F, and components ending in a dot or space.
- Reserved DOS device names, including `CON`, `PRN`, `AUX`, `NUL`, `COM1`
  through `COM9`, `LPT1` through `LPT9`, `CONIN$` and `CONOUT$`. Extensions
  do not make them valid; `COM` and `LPT` names using superscript `¹`, `²`
  or `³` are also rejected.
- Non-string rules, non-array rule lists, non-boolean `defaults`, unknown
  keys, or a missing or unsupported `v`.

Each original array may contain at most **256 entries, before deduplication**.
The file is bounded to **1 MiB**, including a BOM when present. Each component
may contain at most **255 UTF-16 code units**, and a relative path at most
**32,760 UTF-16 code units**. A character outside the Basic Multilingual Plane
uses two units. These are configuration bounds, not a guarantee that every
accepted spelling names an accessible directory on the current filesystem.

Validation errors carry domain `SCAN`, code `config`, with the configuration
path and field. These are examples of the loader's diagnostic bodies:

```text
C:/work/app/kuu.config.json: scan.exclude_dirs[1]: expected one basename, without path separators
C:/work/app/kuu.config.json: scan.exclude_paths[1]: '.' and '..' components are not allowed
C:/work/app/kuu.config.json: scan.exclude_dirs: at most 256 rules are allowed before deduplication
```

The first can result from `"exclude_dirs": ["vendor/generated"]`; move that
entry to `exclude_paths`. The second can result from
`"exclude_paths": ["../generated"]`; exclusions must stay project-relative.
`kuu check` reports these configuration errors without executing the manifest.
Its JSON form returns `ok:false` and an error with domain `SCAN`, code `config`;
it exits 2, as do `run` and `list` on invalid configuration. `capabilities`
keeps its descriptor available, sets `project.config_error` and skips manifest
execution and module inventory until configuration is fixed. Its module
inventory is explicitly incomplete.

<a id="kuu-page-scan-one-policy-per-operation"></a>

### One policy per operation

An invocation loads configuration once **before executing the manifest** and
retains it for requested inspection, including checker rechecks after `--fix`.
Manifest edits to configuration affect the next
invocation. Direct `check.tree` and `check.modules` calls load once per operation
unless given an internal context. `check.file` explicitly inspects one source
file without loading scan configuration; the check command still preflights
configuration before inspecting its requested files.

Malformed or unreadable configuration is an actionable error before task
execution. Checking remains available when the manifest itself is broken.
Changing scope changes what the next check or inventory inspects. The
[execution ledger](#kuu-page-ledger) has no file baseline or change counts to migrate.

<a id="kuu-page-scan-shared-traversal"></a>

### Shared traversal

Checking and module inventory share a native collector.
It excludes directories before entering them and takes file metadata from the
same enumeration, avoiding a second listing of every directory. The public
`fs.dirs` API is unchanged. The private collector supports both full configured
rule lists, independently of `fs.dirs`' 64-pattern limit.

Both consumers use the configured scope and defaults above. For direct
checker calls that load their own policy, an intentional change to the legacy
`check.PRUNE` list adds wildcard exclusions; it cannot remove mandatory or
configured exclusions. Supplied internal contexts, including command contexts
captured before the manifest, remain fixed across later `PRUNE` mutations.
The untouched legacy list does not override declarative configuration.
Configured exclusions remain exact names and paths, not wildcard patterns.

The collector distinguishes deliberate exclusions, links it does not follow,
and enumeration errors. It retains readable metadata from a partial scan and
marks the inspection incomplete. Checker findings and module-inventory
completeness use those diagnostics.

<a id="kuu-page-scan-scan-reports"></a>

### Scan reports

`check --json` and `capabilities --json` expose the normalized
scope and metadata for scans they actually performed. These additive fields
let a reader distinguish a small project from a deliberately restricted or
incomplete inspection. They do not contain the full file inventory.

```typescript
type ScanScope = {
  v: 1;
  defaults: boolean;
  fingerprint: string;
  source: { kind: "default" | "file"; path: string };
  mandatory_dirs: string[];
  default_dirs: string[];
  exclude_dirs: string[];
  exclude_paths: string[];
  effective_dirs: string[];
  extra_prune?: string[];
};
type ScanReport = {
  root: string;
  start: string;
  scope: ScanScope;
  path_rules_applied: boolean;
  complete: boolean;
  counts: { files: number; enumerated_dirs: number; excluded_dirs: number;
            nofollow_links: number; errors: number };
  errors: { path: string; message: string; win32?: number }[];
  seconds: number;
};
```

Scope arrays are present even when empty. `source.path` identifies the root's
configuration path; `kind:"default"` means it was absent. `default_dirs`
contains the enabled optional defaults, and `effective_dirs` is the sorted,
deduplicated union of mandatory, enabled default and custom basenames.
`fingerprint` identifies the normalized configured rules, so a mere reordering
of rules does not change it. Direct checker calls can additionally report
legacy wildcard rules in `extra_prune`; these are separate from that fingerprint.

`root` is the absolute project root and `start` the absolute directory actually
collected. A deliberate checker start can override its own exclusion. When it
is outside the project, `path_rules_applied:false` says that project-relative
subtree rules were inapplicable; basename exclusions still apply.

`counts.files` counts collected ordinary file metadata, including non-Lua
files. `enumerated_dirs` counts directories whose enumeration was attempted,
including the starting directory when it could be opened. `excluded_dirs` counts encountered directory
entries pruned before entering them, not all descendants beneath those entries.
`nofollow_links` counts encountered links deliberately not followed. Neither
exclusions nor non-followed links make a scan incomplete. `errors` counts
enumeration diagnostics, also listed in the `errors` array.

`complete` describes collection within the reported scope, not the whole
filesystem or a transactional snapshot. Reading a collected Lua file can fail
later: checker and module-inventory completeness also cover those reads, while
the underlying scan can remain complete. Syntax findings alone do not make
inspection incomplete. A partial scan retains readable metadata and its counts.

`seconds` is elapsed collection time at the consumer boundary. For the checker
and inventory it covers the collector call. It is not a CPU-time measurement.

<a id="kuu-page-scan-command-timings"></a>

### Command timings

`kuu check --timings`, `kuu run --timings TASK` and `kuu capabilities --timings`
print one timing line on standard error. Human output stays quiet about these
phases by default. Their JSON reports always include `result.timings`, whether
or not `--timings` was supplied, and JSON remains on standard output.

All values are wall-clock seconds. Each command documents its own phases on
the [check](#kuu-page-check), [task](#kuu-page-task) or [capabilities](#kuu-page-capabilities) page.
Phases may overlap: checking includes collection, and task execution includes
nested child work and its observer records. Do not add phases or child
durations to derive a total.

`total` starts just after the timing helper loads, before other command
imports, and ends after command work and report preparation, including the
last history append for a run. It excludes OS/runtime startup before command entry
and final serialization, emission and flushing. Earlier streamed run events
are part of command work. An external stopwatch can therefore be larger,
without a promised bound on the difference.

Unavailable phases are omitted, not reported as zero. Reportable failures keep
the phases and partial inspections reached before failure. Help and
command-line parser exits retain their existing output conventions and produce
no timing line.

---

<a id="kuu-page-cli"></a>

<a id="kuu-page-cli-cli"></a>

## cli

Declare a program's arguments once; parse and describe them from that.

```lua
local cli = require("cli")
local spec = {
  { "--interval", type = "duration", default = "2s", min = 0.1, help = "refresh interval" },
  { "--format",   type = "string", default = "text", choices = { "text", "json" } },
  { "--all",      type = "flag", help = "show everything" },
  { "dir",        type = "string", default = ".", help = "directory to watch" },
  { "files",      type = "string", rest = true, help = "files to process" },
}
local opts, e = cli.parse(require("rt").args, spec, "watchit")
if not opts then io.stderr:write(tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "watchit")) os.exit(0) end
opts.interval   -- 2 (seconds)
opts.files      -- { "a.lua", "b.lua" }
```

The spec is an array, so positionals take declaration order. A name beginning
with `--` is an option; anything else is positional; a positional with
`rest = true` collects everything left over. Types: `flag`, `string`, `int`,
`number`, `duration` (converted to seconds), `size` (converted to bytes).
Attributes: `type`, `default`, `min`, `max`, `choices`, `help`, `required`,
`rest`. Results are keyed by the name without the leading `--`. The `help`
result key is reserved, so neither an option `--help` nor a positional `help`
may be declared. `min` and `max` must be finite numbers and apply only to
numeric types; duration bounds use seconds and size bounds use bytes.
Combining `rest = true` with `required = true` requires at least one value.
Size conversion rejects overflow instead of returning infinity.

On the command line: `--name value` and `--name=value` both work; a flag is
`--all`, `--all=false`; `--` ends options; `--help` is always accepted and
comes back as `opts.help = true`, waiving missing required values but not
malformed ones.

Parsing never prints and never exits. A wrong command line is `nil, err` with
`CLI usage`, whose message names the problem and ends with the generated usage
text, ready to print. A wrong spec raises immediately: `CLI usage` for an
attribute an entry cannot hold, `CLI badvalue` for an unknown type, a default
that fails its own type, invalid numeric bounds, two entries on one key, the
reserved `help` key redeclared, a flag as a positional, or a positional after
the rest entry. Both `parse` and `usage` validate bounds even when the option
is unused.

```lua
cli.usage(spec, "watchit")   -- the text: usage line, arguments, options with defaults and ranges
cli.duration("1.5s")         -- 1.5; nil, err when it is not a duration
cli.size("16M")              -- 16777216; nil, err when it is not a size
```
Duration arguments and `cli.duration` use the native runtime's grammar,
including sums (`"1h30m"`, `"1m 30s"`) and days (`"2d"`). Results are
seconds; text that is not a duration is `nil, err` with `CLI badvalue`, since
converting what a user typed is what these two are for, where `time.duration`
on a literal in the program raises. Numeric defaults, `min`, `max`,
and `choices` for durations use seconds too. `proc`, `sched`, `http`, `sync`,
and `net` accept these numbers directly, without conversion:

```lua
local opts = assert(cli.parse(require("rt").args, {
  { "--timeout", type = "duration", default = "30s", min = 0.001 },
}))
local r = require("proc").run { "tool.exe", timeout = opts.timeout }
```

This changed in 0.6: 0.5 returned milliseconds. See
[Upgrading to 0.6](#kuu-page-upgrading-06) before reusing an older spec. Rounding and
floating-point precision match `time.duration`; results are numbers of seconds,
not exact integer millisecond counts at arbitrarily large magnitudes.

The complete CLI code set is `usage` (returned for invalid command-line
arguments; raised for an attribute a spec entry cannot hold) and `badvalue`
(raised for an invalid specification; returned by `duration` and `size` for
text they cannot parse).

---

<a id="kuu-page-proc"></a>

<a id="kuu-page-proc-proc"></a>

## proc

Children with decided lifetimes.

```lua
local proc = require("proc")
```

Every child kuu supervises is born into its own Windows Job Object, before its
first instruction runs, and the job is marked to kill on close. When kuu's
handle to the job goes away, because the program closed the child, dropped it,
finished, failed, or was killed itself, every process in that tree is
terminated by the kernel. This is the no-orphans law, and it is Windows'
promise rather than kuu's. Only `proc.detach` steps outside it, on purpose.

Waiting never blocks other tasks: `run` and `wait` park the calling coroutine
and the loop resumes it when the child is complete. Complete means the whole
job is empty and stdout and stderr have reached end of file, so a grandchild
that outlives the child keeps the result open, as it should.

<a id="kuu-page-proc-procrun"></a>

### proc.run

```lua
local r, e = proc.run { "git", "status", "--short",
  cwd = "C:/work/app",           -- default: kuu's own
  env = { GIT_PAGER = "", HOME = false },   -- added or removed on top of kuu's
  timeout = "30s",               -- kill the tree and report status "timeout"
  stdin = bytes,                 -- written to the child, then closed
  maxout = "64M",                -- per stream; the default
}
local r = proc.run("cmd.exe", "/c", "echo hi")   -- plain arguments, no options
```

The array part is the command: the executable and its arguments, each a
string. A bare name such as `git` resolves from `PATH` only, never from the
current directory, and empty `PATH` entries are ignored; a name with a separator
is used as given. Names without an extension try `.exe`, `.com`, `.bat`, `.cmd`
in that order, searching `PATH` entries in their listed order for each extension.
Long paths work both explicitly and through `PATH`. Arguments are quoted for the
child exactly by the rules the child's C runtime parses them with, so what you
pass is what it receives: spaces, quotes, and backslashes need no escaping.

`r` is the result:

| field | meaning |
|---|---|
| `status` | `"exit"`, `"timeout"`, `"killed"`, or `"limit"` |
| `limit` | only for `status = "limit"`: `"memory"`, `"cpu"`, or `"processes"` |
| `code` | the exit code as an integer, untruncated |
| `out`, `err` | stdout and stderr as bytes |
| `pid` | the child's process id |
| `elapsed` | seconds from launch to completion |
| `truncated` | true when a stream exceeded `maxout` and the rest was dropped |

A timeout is a result, not an error: branch on `r.status`. `e` is set only when
the child could not be started, with these codes:

| PROC code | when |
|---|---|
| `notfound` | the program is not on `PATH` or does not exist |
| `launch` | Windows refused to create the process; the message says why |
| `badvalue` | raised: a malformed option value, a `cwd` spelled in a way Windows would rewrite, an environment naming one variable twice; `nil, err` for a `cwd` that is not there |
| `encoding` | raised: a command, path, or environment entry is not valid UTF-8 |
| `usage` | raised: no command, a wrong argument shape, an unknown option — in the command table or in `limits` |
| `oserror` | a job, pipe, or another launch resource could not be created |

For complete task-level examples that preserve stderr, check truncation and
distinguish accepted exits from timeout/limit/launch failures, read the
[process recipes](#kuu-page-process-recipes). A command table mixes argv and options;
serialize its argument sequence as an explicit JSON array inside an object
with separate `argv`, `cwd` and `env` fields.

Unknown option names raise rather than pass silently, so a typo cannot
become a run with the wrong settings.

`run` accepts `cwd`, `env`, `timeout`, `stdin`, `maxout`, `inherit`,
`inherit_stdin`, and `limits`; `start` additionally accepts `stream`. An omitted `timeout` has
no time limit; zero requests an immediate timeout. `inherit` and `stream`
default to false. Environment names are compared ignoring case: duplicates,
empty names, `=`, and NUL are refused, as are NUL bytes in text values.

An `env` table overlays the inherited environment; `false` removes a named
variable. It does not start from an empty environment. For shared root-derived
cache locations and fresh editor processes, see
[the project environment recipe](#kuu-page-project-environment).

<a id="kuu-page-proc-limits"></a>

### Limits

```lua
proc.run { "build.exe", timeout = "10m",
  limits = { memory = "512M", cpu = "30s", processes = 8 } }
```

`limits` applies to `run`, `start`, and `task.exec`. All three bounds are
job-wide, across the child and its descendants: `memory` is committed bytes,
`cpu` is accumulated user-mode CPU time, and `processes` is the number alive
at once, including the initial child. Each optional bound must be positive;
a malformed bound raises `PROC badvalue` and an unknown name `PROC usage`. An empty table
sets no bounds. `detach` accepts neither limits nor `maxout`, since it reads
no output.

Windows refuses allocations and child creation that exceed memory and process
limits; kuu terminates the job when the corresponding notification arrives.
The kernel checks accumulated CPU time periodically and terminates a job
found over its quota; enforcement can overshoot the requested CPU time.
This is [Windows' job-time contract](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information).
The result has
`status = "limit"` and names the bound in `limit`. `timeout` is independently
elapsed wall-clock time; keep it when a child can wait without using CPU.
An intentional breakaway still follows the rules described under `detach`.

<a id="kuu-page-proc-procstart-and-the-child-handle"></a>

### proc.start and the child handle

```lua
local c <close> = proc.start { "server.exe", "--port", "8080", timeout = "10m" }
c.pid                    -- integer
c:running()              -- true until the tree is done
local r, e = c:wait("5s")   -- the same result table as run; nil, PROC timeout if late
c:kill()                 -- terminate the tree now; wait then reports "killed"
c:close()                -- kill if still running, release everything
```

`start` accepts the same table as `run`, plus `stream = true`. Both accept
`inherit = true`. The `timeout` is the child's, counted from launch and
enforced whether or not anyone waits; a `wait` timeout only bounds the wait.
The handle is also closed by `<close>` at the end of its block and by garbage
collection, and either closing kills a tree that still runs. `close` is
idempotent; after it, `pid` is nil and the other methods raise `PROC closed`.
Repeated waits on a finished child return
the same result.

<a id="kuu-page-proc-streams"></a>

### Streams

```lua
local c <close> = proc.start { "tool.exe", stream = true }
c:write("first line\n")          -- queued to the child's stdin; true, or nil, PROC closed | toobig
c:close_stdin()                  -- EOF for the child once the queue has drained
c:read("line", "5s")             -- the next stdout line without its ending; nil at EOF
c:read(4096)                     -- up to that many bytes, once at least one is there
c:read("some")                   -- whatever has arrived, once anything has
c:read("all")                    -- everything to EOF, within the buffer bound below
c:read_err("line")               -- the same for stderr
for line in c:lines() do ... end -- stdout lines to EOF; c:err_lines() likewise
```

In stream mode the program reads the pipes itself, so `wait` reports the exit
with empty `out` and `err`. Reads that must wait park the calling task and
accept a timeout, returning `nil, err` with `PROC timeout` while the data stays
buffered. One task at a time may read a given stream; a second raises
`PROC busy`. In stream mode `maxout` must be positive and becomes the
backpressure point: when that much is unread,
kuu stops reading and the child blocks on its write until the program catches
up, so nothing is ever truncated. A `read("all")` whose buffer fills before
EOF, or a `read("line")` whose buffer fills before its line ending, returns
`nil, PROC toobig` instead of waiting on its own backpressure. This includes
an unterminated final line or output exactly `maxout` bytes long when EOF has
not yet been observed. No bytes are consumed by that error: continue with
`read("some")` or numeric reads to drain the stream, or choose a larger
`maxout` when starting the child. `lines()` and `err_lines()` raise read
errors, including `PROC toobig`, so iteration cannot mistake them for EOF.
Closing the child wakes a parked reader with
`PROC closed`. A child that does not read its stdin is not an error; a child
that never gets its stdin closed may never exit, so `close_stdin` when you are
done.

The stdin queue has its own fixed 64 MiB bound, independent of `maxout`.
`write` returns `nil, PROC toobig` when a write cannot be queued within it.
Pending writes hold their own stable chunk; consumed queue storage is reused
as input progresses, so a continuing backlog does not retain all earlier input.

To capture or stream output while keeping interactive or piped input, set
`inherit_stdin = true`. The child reads kuu's own standard input directly;
there is no input queue to write or close. Missing or closed standard input
is EOF. This works with `run` and `start`, including `stream = true`, and
cannot be combined with `stdin` or `inherit = true`. It is not an option for
`detach` or PTY sessions.

<a id="kuu-page-proc-the-console"></a>

### The console

```lua
proc.run { "vim", "notes.md", inherit = true }
```

With `inherit = true` the child receives kuu's own standard handles: colours,
pagers, prompts, and Ctrl-C reach it as if it had been started from the
terminal, with every supervision guarantee intact. Nothing is captured; `out`
and `err` are empty. It cannot be combined with `stdin` or `stream`.

<a id="kuu-page-proc-waiting-on-several-children"></a>

### Waiting on several children

```lua
local first, result = proc.wait_any({ a, b, c }, "1m")   -- the handle and its result
local results = proc.wait_all({ a, b, c }, "10m")        -- results in the order given
```

Both return `nil, err` with `PROC timeout` when the duration passes; the
children keep running. Children that already finished answer at once.

<a id="kuu-page-proc-procdetach"></a>

### proc.detach

```lua
local pid, e = proc.detach { "updater.exe", "--quiet", cwd = "C:/app" }
```

Starts a process that kuu does not supervise: it gets no console of kuu's, its
own process group, the null device for its standard streams, and it lives on
after kuu exits. Options are `cwd` and `env` only. If kuu itself runs inside a
job that permits breakaway, the process leaves that job; jobs that enclose kuu
and forbid breakaway keep it, which is that environment's policy, not kuu's.

kuu's own child jobs permit breakaway, so a program that kuu runs can itself
detach a process, and only a process that asks to break away leaves; nothing
escapes supervision by accident.

The [editor verification recipe](#kuu-page-editor) shows a detached native supervisor
that owns and bounds its GUI child on a private desktop. Launch success and
application readiness are separate results.

<a id="kuu-page-proc-procalive-and-prockill"></a>

### proc.alive and proc.kill

```lua
proc.alive(pid)        -- true while a process with that id runs
proc.kill(pid)         -- true, or nil, PROC notfound | access | oserror
```

For processes kuu did not start. `kill` terminates one process, not a tree;
use a supervised child when the tree matters.

<a id="kuu-page-proc-proclist-procfind-proctree"></a>

### proc.list, proc.find, proc.tree

```lua
proc.list()                    -- every process on the machine, sorted by pid
proc.find { name = "node" }    -- by executable name, ignoring case and the extension
proc.find { pid = 4120 }       -- one entry, or none
proc.find { port = 8080 }      -- the owners of TCP listeners on that port
proc.tree(pid)                 -- the entry with its `children`, recursively; nil, PROC notfound
```

An entry:

| field | |
|---|---|
| `pid`, `parent`, `name`, `threads` | from the process snapshot; always present |
| `exe` | the full UTF-8 path of the executable, with forward slashes like `fs.absolute` |
| `cmdline` | the command line as the kernel holds it |
| `started` | when the process began, an instant for [`time`](#kuu-page-time) |
| `cpu` | seconds of kernel plus user time so far |
| `memory`, `private` | the working set and the private bytes |

The last six need the process opened for querying and are absent when this
user may not: system processes, another user's, protected ones. `find`
returns a list, empty when nothing matches; looking for something that is
not there is not an error. It takes exactly one of `name`, `pid`, `port` and
raises PROC badvalue otherwise. `tree` answers `nil, PROC notfound` for an
unknown pid. Process ids are reused, so a `parent` may name a process that
exited long ago and whose id now belongs to something unrelated; the field
reports what the snapshot says. `tree` does not follow such a name: a
process is listed as a child only when it began no earlier than the parent
did, which a real child always has and a stranger wearing a dead parent's
id never has. A process whose start time cannot be read — one this user may
not ask about — is listed only under a parent whose start time cannot be
read either, since nothing kuu can open starts a process it cannot; `csrss`
and `wininit` name the boot-time pid 1000 as their parent, and whatever
wears that pid today did not start them.
Tree expansion stops after 64 levels; a deepest entry then has no expanded
children.

<a id="kuu-page-proc-errors"></a>

### Errors

| PROC code | when |
|---|---|
| `notfound` | a command or requested process does not exist |
| `launch` | Windows refused to start the command |
| `access` | `kill` cannot open the process for termination |
| `badvalue` | raised: malformed arguments or option values, a pid outside the range; returned for a working directory that is not there |
| `encoding` | raised: a command, path, environment entry, or process-name filter is not UTF-8 |
| `usage` | raised: an invalid call shape, unknown option, incompatible stream modes, or a read/write without stream mode |
| `timeout` | a child wait, stream read, `wait_any`, or `wait_all` outlasted its wait duration |
| `closed` | raised for a closed handle; returned when stdin is closed or a pending read's handle closes |
| `busy` | raised: another task is already reading that stream |
| `toobig` | stdin could not queue the write within its 64 MiB bound, or an `all`/unfinished-line read filled `maxout` before completion; buffered output remains readable with numeric/`some` reads; line iterators raise this error |
| `oserror` | Windows, snapshot, or allocation failure |

Waiting can also propagate the scheduler's `SCHED` errors, including
`deadline`; see [sched](#kuu-page-sched). Child results with `status = "timeout"`,
`"killed"`, or `"limit"` are result states, not error codes.

<a id="kuu-page-proc-two-things-to-know"></a>

### Two things to know

- **`cmd.exe` parses its own line.** Quoting is done for programs that parse
  their command line the normal way. `cmd.exe /c` re-parses its argument by
  its own rules, so give it one plain argument without embedded quotes, or
  write a `.cmd` file and run that. Batch files are launched through a
  defensively quoted `cmd.exe`, the mitigation for CVE-2024-24576, so an
  argument like `a&b` reaches the script literally.
- **Output is bytes.** Windows programs write in whatever encoding they
  choose; `cmd.exe` writes CRLF line ends and the console code page. Decode
  deliberately.

<a id="kuu-page-proc-tools-that-construct-their-own-commands"></a>

### Tools that construct their own commands

Kuu preserves the argument vector it passes to a child. A child may construct
another command string internally. For example, Windows `windres` uses a shell
for its preprocessor by default and can split checkout paths containing spaces.
Use its `--use-temp-file` mode and relative resource/include paths from a build
directory. Quoting only the original Kuu argument cannot repair that internal
command. Process metadata's `cmdline` stays verbatim; only `exe` is normalized.
Use `fs.canon` identity when different path spellings or aliases must compare equal.

---

<a id="kuu-page-fs"></a>

<a id="kuu-page-fs-fs"></a>

## fs

Files and directories as Windows actually has them.

```lua
local fs = require("fs")
```

Paths in are UTF-8 with either separator. Paths out are absolute, with
forward slashes. Every path is normalised and given the `\\?\` prefix before
Windows sees it, so paths beyond 260 characters simply work. Refused by name,
because Windows would silently make them mean something else: a
drive-relative path such as `C:foo`, a device path, and a component ending in
`.` or a space. Refused path spellings raise `FS badvalue`; invalid UTF-8 raises
`FS encoding`. A path that is not there is `nil, err` with `FS notfound`.

<a id="kuu-page-fs-reading-and-writing"></a>

### Reading and writing

```lua
local bytes = fs.read("build/kuu.exe")                     -- bytes, up to 1 GiB
local text  = fs.read("notes.md", { encoding = "utf-8" })   -- BOM dropped, strictly validated
local old   = fs.read("robocopy.log", { encoding = "cp1252" })
fs.read(path, { maxbytes = "16M" })                        -- nil, FS toobig above that

fs.write("out/result.json", data)                    -- atomic: temp file beside, then rename
fs.write("build/log.txt", line, { append = true })   -- appended in place
fs.write(path, data, { atomic = false })             -- plain overwrite
```

An atomic write leaves either the old bytes or all of the new ones, never a
torn file. It creates `.kuu-<32 random hex digits>.tmp` in the same directory and
renames it over the target, which a watcher sees as an added temporary file
and a rename.

The rename is retried, up to six attempts over a few tens of milliseconds,
when it fails with access denied or a sharing violation. On Windows a scanner
or an indexer routinely opens a file the moment its handle closes, and the
rename of a freshly written temporary loses that race: 15 of 2000
single-process writes failed that way on the owner's machine before the retry,
and none of 4000 after. The retry bypasses no permission — a target that
genuinely cannot be replaced still fails with `FS access`, only later — and it
does not weaken atomicity, because each attempt either replaced the target or
left it alone. A target somebody holds open for longer than that window still
fails, and that is the intended answer rather than a defect.

`rename` and `copy` retry the same way, since 0.10.0, for the same two
errors and the same bound. 0.9.0 gave the retry to the atomic write alone,
and the intermittent failures the suite kept seeing were exactly the two
calls it had not reached.

<a id="kuu-page-fs-facts-about-a-path"></a>

### Facts about a path

```lua
fs.exists(p)   -- "file" | "directory" | "link" | "other" | false; the name itself, never its target
fs.stat(p)     -- follows links: { kind, size, mtime, ctime, atime, attrs, hidden, readonly,
               --   system, reparse, volume, file, links }
fs.stat(p, { follow = false })   -- the link itself: kind "link", reparse "0xa0000003"
fs.canon(p)    -- { path, volume, file, kind, links }: where it really lives and what it is
fs.same(a, b)  -- true when two paths name one object, through any links
fs.link(p)     -- false, or { type = "junction" | "directory symlink" | "file symlink", target, tag }
```

Times are seconds since the Unix epoch, as numbers. `volume` and `file` are
sixteen-character hex tokens: identity is compared, never computed. A junction
or symlink whose target is gone is `nil, err` with `FS dangling`, distinct from
`notfound`, because a resolver may continue past a missing name but must stop
at an existing broken link.

<a id="kuu-page-fs-file-attributes"></a>

### File attributes

`fs.attributes` inspects Windows file attributes; `fs.set_attributes` patches
named flags on an existing file, directory or reparse object. These calls are
available from [0.12](#kuu-page-upgrading-from-011); use `rt.version_at_least(0, 12)`
when a project depends on them. For an existing file:

```lua
local path = "build/output.bin"
local flags = assert(fs.attributes(path))
print(flags.attrs, flags.readonly, flags.hidden)
assert(fs.set_attributes(path, { readonly = false, hidden = true }))

local target = assert(fs.attributes(path, { follow = true }))
assert(fs.set_attributes(path, { archive = false }, { follow = true }))
```

The getter returns a table with all seven fields present:

```typescript
type Attributes = {
  attrs: number; // complete unsigned 32-bit Windows mask, as an integer
  readonly: boolean; hidden: boolean; system: boolean; archive: boolean;
  temporary: boolean; not_content_indexed: boolean;
};
```

It is a detached snapshot: assigning `flags.hidden` changes only the Lua
table. A setter patch accepts the six named booleans; `true` sets a flag,
`false` clears it, and omitted/nil fields preserve the queried value. The raw
`attrs` mask is inspection only. Passing it back as a patch, or naming `normal`,
directory/reparse bits, compression, encryption or sparse allocation, is an
error. Unrelated native bits are preserved, including when all mutable flags
are cleared. The setter returns `true` on success.

Both calls default to **`follow=false` for the final path component**, selecting
the link itself; `{follow=true}` selects its target. `fs.stat` keeps its
existing following default. Linked ancestors may still be traversed, so this
selection does not confine access to a directory. A failed nofollow call never
silently retries against the target.

An empty patch, `fs.set_attributes(path, {})`, opens and reads metadata,
validates the selected object, and makes no write. It does **not** test write
permission. Every nonempty patch requests read/write-attribute access, even
if its values are already set; an unchanged effective mask skips the native
setter after that check. Only attribute access is requested, not permission
to read or write file contents.

`temporary=true` on a directory returns `nil, FS badvalue` before any part of
the patch is written. This also applies to directory links selected without
following. `temporary=false` is allowed on directories. File attributes are
separate from ACL permissions: a directory's readonly flag is not a general
write-permission control, though it can prevent removal. These calls do not
create paths, recurse, change ACLs or create links. Successfully opened
non-disk objects return `nil, FS badvalue`; other provider failures keep their
native error classification.

Paths must actually be UTF-8 strings; numbers are not coerced. A patch must be
a table, and options must be a table or nil. Only stored table entries count:
`__index`, `__pairs` and other metatable behavior do not supply fields.
Unknown, numeric or embedded-NUL keys raise `FS usage`. Every present flag
and `follow` must be a boolean; other values raise `FS badvalue`. Wrong
argument types raise Lua argument errors. Invalid UTF-8 raises `FS encoding`;
empty paths, malformed path spellings and paths containing NUL raise
`FS badvalue`. Validation happens before native handles are acquired.

Environmental failures return `nil, err`. Missing ordinary paths are
`FS notfound`; permission or sharing denial is `FS access`. `FS dangling`
requires a followed open to fail with native file/path-not-found, followed by
a successful nofollow query confirming a name-surrogate link at the final
component. Otherwise the original error is kept, including access denied.
That diagnosis uses separate observations and can race with path replacement.

Each update reads and patches through the same handle, keeping it attached to
the selected object if the path is renamed. It does not atomically merge
concurrent attribute writers: preservation refers to the state read by this
call. File contents are unchanged. This call does not explicitly rewrite
creation, access or write times; the filesystem's metadata change time may
advance.
`fs.stat().ctime` is creation time, not that change time.

<a id="kuu-page-fs-making-and-removing"></a>

### Making and removing

```lua
fs.mkdir("build/out/deep")                  -- parents created; existing is fine
fs.mkdir("build/out", { parents = false })  -- the parent must already exist
fs.remove("build/out/deep/file.txt")
fs.remove("build/out", { recursive = true })
fs.rename(from, to, { replace = true })
fs.copy(from, to, { replace = true })
```

`remove` without `recursive` on a non-empty directory is `FS notempty`. A
recursive remove never follows a junction or symlink: the link is removed as a
link and its target is untouched. Read-only files and directories are removed:
the readonly bit is cleared on the selected object before deletion, and a
failure to clear it is reported. Removal is nontransactional: earlier entries
may already be gone, and a cleared readonly bit can remain clear if deletion
later fails. Attribute clearing does not change a link target. Do not race
removal against path replacement; linked ancestors are not a containment boundary.
Readonly-directory handling here requires 0.12 or later.

For longer, scheduler-friendly retries, use the project's
[bounded publication and cleanup recipe](#kuu-page-cleanup). It retries `FS access`
under one budget per tree operation and preserves primary and cleanup failures.

<a id="kuu-page-fs-listing-and-walking"></a>

### Listing and walking

```lua
local l = fs.list("src")
for _, e in ipairs(l.entries) do print(e.name, e.kind, e.size, e.mtime) end
#l.errors        -- names that could not be represented, listings cut short

local d = fs.dirs("C:/work", { prune = { "node_modules", ".git" } })
d.root           -- as walked
d.paths          -- directory paths, including link/depth frontiers; depth-first, siblings in UTF-8 byte order
d.dirs           -- == #d.paths
d.skipped        -- the directories a prune pattern excluded; never in d.paths
d.links          -- { path, tag, surrogate, action, type, target } per reparse point
d.errors         -- { path, win32, reason } per branch that could not be read
d.pruned, d.depthlimited, d.maxdepth
```

`dirs` lists directories only; junctions and symlinks are listed and not
entered, and their `links` row says so (`action = "nofollow"`). Hidden
directories are included. Nothing is omitted silently: a branch that could not
be read is an `errors` row with the raw Windows code, and the counts add up.
`depth` omitted is unlimited; `depth = 0` is the root alone. Prune patterns
use `*` and `?`, match base names, and ignore case; at most 64 are accepted.

**A pruned directory is not in `paths`.** It was excluded by name, so it is
reported in `skipped` and `pruned` instead, including at the depth limit
(where pruning takes precedence over `depthlimited`).

Directory links remain in `paths`, however. Listing one would follow its
target despite the walk's refusal to enter it. For the unlimited walk above,
also honor the walk's `nofollow` decisions when listing discovered directories:

```lua
local nofollow = {}
for _, link in ipairs(d.links) do
  if link.action == "nofollow" then nofollow[link.path] = true end
end
for _, dir in ipairs(d.paths) do
  if not nofollow[dir] then
    local listing, why = fs.list(dir)
    -- Handle a nil listing and listing.errors before treating it as complete.
    if listing then
      for _, e in ipairs(listing.entries) do
        -- e.kind == "link" identifies file/directory name-surrogate links.
        -- Inspect ordinary entries here.
      end
    end
  end
end
```

Use `action`, rather than rejecting all reparse metadata: filter/cloud
directories can be ordinary content. A linked starting directory is followed
deliberately and reported with `action = "descended"` when successfully read.

Through 0.8 a pruned directory appeared in `paths` and only its descent was
skipped, so that loop listed the files of every excluded directory. Two
independent programs made exactly that mistake. A directory stopped by the
`depth` cap, or a link not followed, does stay in `paths`: those are the
frontier the walk was asked to stop at, not names it was asked to exclude.
See [upgrading to 0.9](#kuu-page-upgrading-09).

<a id="kuu-page-fs-watching"></a>

### Watching

```lua
local w <close> = fs.watch("src", { recursive = true })
local events, e = w:read("30s")       -- nil, FS timeout when nothing changed
for _, ev in ipairs(events) do print(ev.action, ev.path, ev.from) end
w:info()                              -- { directory, recursive, pending, dropped, armed }
```

The options are `recursive` (default true) and `raw` (default false).

Actions are `added`, `removed`, `modified`, `renamed` (with `from`), and
`overflow`. Paths are relative to the watched directory with forward slashes.
A read returns the first batch the system delivered; changes made over time
arrive over several reads. Within a batch, one path gets one event, by
precedence removed, added, renamed, modified, unless `raw = true` asks for
every notification. The watch is armed before `fs.watch` returns. When
`overflow` appears or `dropped` grows, the system could not describe every
change: reconcile from `fs.list` or `fs.dirs`.

Concurrent readers compete for batches in the order they started waiting.
One reader receives each batch; the others remain parked for later changes
or their own timeout. Events are not broadcast. Closing the watch wakes all
waiting readers with `FS closed`.

<a id="kuu-page-fs-paths-as-strings"></a>

### Paths as strings

```lua
fs.join("build", "out\\", "/app.exe")   -- "build/out/app.exe": either separator in, "/" out
fs.join("a", "C:/x", "y")               -- "C:/x/y": a drive or a share starts over
fs.dirname("a/b/c.txt")                 -- "a/b"; "." for a bare name; a root stays a root
fs.basename("a/b/c.txt")                -- "c.txt"
fs.ext("a/b.tar.gz")                    -- ".gz"; "" for ".gitignore"
fs.stem("a/b.tar.gz")                   -- "b.tar"
fs.relative("C:/work/app/src/x.c", "C:/work/app")   -- "src/x.c"; ".." as needed; case ignored
```

None of these touch the disk except `relative`, which makes both paths
absolute first and returns the absolute path when they share no root.

```lua
local paths, errors = fs.glob("src/**/*.c")           -- sorted; relative when the pattern is
fs.glob("C:/work/**", { kind = "directory" })         -- or "file"
```

`*` and `?` match within one name, `?` one character, and case is folded the
way Windows folds file names, so `É*.TXT` finds `é.txt`; `**` as a whole
component matches any number of directories, including none.
Links are matched by name but never entered. Each directory that could not be
listed is one entry of `errors`, with `path` and `message`, and the rest of
the results stand.

<a id="kuu-page-fs-places"></a>

### Places

```lua
fs.cwd()          -- the current directory
fs.chdir(p)       -- change it, for the whole process: every task and every child started afterwards
fs.temp()         -- the temporary directory
fs.absolute(p)    -- the normalised absolute spelling of p
fs.tempfile { dir = "build", prefix = "kuu-", suffix = ".tmp" }   -- a new empty file, uniquely named; every field optional
fs.tempdir { dir = "build", prefix = "kuu-" }                     -- a new empty directory
fs.space("C:/")   -- { total, free, available } in bytes; available is what this user may still use
```

Temporary names are created exclusively, so two callers never receive the
same one. Both default to the temporary directory and to the prefix `kuu-`.
A prefix or suffix with a separator, and a suffix ending in a dot or a space,
which Windows would create and then never name the same way again, are
refused before anything is created.

<a id="kuu-page-fs-errors"></a>

### Errors

| FS code | when |
|---|---|
| `notfound` | the path is not there |
| `dangling` | the path is a link whose target is not there |
| `access` | denied, or the file is in use |
| `exists` | the target exists and `replace` was not given, or `mkdir` met a file |
| `notempty` | `remove` on a non-empty directory without `recursive` |
| `toobig` | `read` above `maxbytes` |
| `encoding` | a name cannot be represented, or a path is not valid UTF-8 |
| `badvalue` | raised for a refused path, a path or name holding NUL, or an option/attribute value; `nil, err` for a wrong kind of object — a directory given to `read`, a file given to `list`, a non-disk attribute handle, or `temporary=true` on a directory |
| `usage` | raised: an unknown option or attribute patch key |
| `timeout` | `watch:read` waited its whole duration |
| `closed` | raised: a closed watch was used |
| `oserror` | anything else, with the Windows message |

`read` with `encoding` keeps conversion failures in the `TEXT` domain, as
documented in [text](#kuu-page-text). A surrounding `sched.deadline` can interrupt
a watch read with `SCHED deadline`; it does not preempt synchronous file I/O.

---

<a id="kuu-page-http"></a>

<a id="kuu-page-http-http"></a>

## http

Fetch and post over HTTP and HTTPS with Windows' own client, WinHTTP: the
machine's proxy settings and certificate store, TLS serviced by Windows
Update, nothing vendored.

```lua
local http = require("http")
local r, e = http.get("https://example.org/tool.zip", { to = ".tools/tool.zip", timeout = "5m" })
local r, e = http.post(url, body, { type = "application/json" })
local r, e = http.request { method = "PUT", url = url, body = bytes, headers = { Authorization = token } }
```

`r` is the response:

| field | meaning |
|---|---|
| `status` | the status code as an integer; a 404 is a result, not an error |
| `headers` | names lowercased, repeats joined with `, ` |
| `rawheaders` | the header block verbatim, for the repeats that must not be joined, such as `Set-Cookie` |
| `body` | the bytes, or `""` when `to` streamed them to a file |
| `bytes` | the body length received |
| `path` | the file written, when `to` was given |

Bodies are bytes until something says otherwise; decode deliberately.
Compressed responses (gzip, deflate) are decompressed transparently.

<a id="kuu-page-http-options"></a>

### Options

| option | default | meaning |
|---|---|---|
| `timeout` | `"30s"` | the whole request, from connect to the last byte; `HTTP timeout` when exceeded; zero is refused because WinHTTP reads it as infinite |
| `maxbody` | `"64M"`, `"8G"` with `to` | the body is refused as `HTTP toobig` beyond this, never truncated |
| `to` | | stream the body into this file; a relative path is resolved when the request starts. Written beside it as a temporary and renamed into place, with the same retry as [`fs.write`](#kuu-page-fs) since 0.10.0, so a failed download leaves the previous file untouched |
| `sha256` | | 64 hex digits the body must hash to, checked as it arrives; otherwise `HTTP mismatch`, and a `to` file is never placed. A non-2xx answer is then `HTTP status`, because specific bytes were asked for |
| `headers` | | a table of name = value; names and values may not contain control characters, and names no colon or space |
| `type` | `application/octet-stream` when there is a body | the `Content-Type`; wins over a `Content-Type` header |
| `redirect` | followed | `"none"` returns the first 3xx with its `location` and makes zero further requests |
| `method` | `GET` | `request` only: GET, POST, PUT, DELETE, HEAD, PATCH |

Redirects from HTTPS down to HTTP are never followed. There is no insecure
option of any kind, because such flags end up left on in something that
matters. URL fragments are client-side and are not sent. Each request runs on
its own worker thread and posts one completion to the loop, so a slow download
stalls no other task and no timer.

Requests are independent of each other: kuu keeps one WinHTTP session for the
process, because a session per request was measured to leak a handle each
time, but cookies are disabled on every request, so nothing set by one answer
is sent with the next. A caller who wants a cookie sends the `Cookie` header.

<a id="kuu-page-http-errors"></a>

### Errors

| HTTP code | when |
|---|---|
| `timeout` | the request did not complete within `timeout` |
| `notfound` | the host name does not resolve, or the directory `to` points into is not there |
| `access` | the download file cannot be created where `to` points |
| `connect` | the host refused or dropped the connection |
| `tls` | the certificate or the secure channel was rejected |
| `toobig` | the body exceeded `maxbody` |
| `mismatch` | the body did not hash to `sha256`; the message carries both digests |
| `status` | a non-2xx answer to a request that gave `sha256` |
| `badvalue` | raised: a malformed url, method, body, content type, header, timeout, size, or redirect value |
| `encoding` | raised: a URL or header is not valid UTF-8 |
| `usage` | raised: an unknown option, or no url |
| `oserror` | anything else, with the Windows message |

A refused download destination path keeps the path helper's `FS` domain
(`badvalue`, `encoding`, or `oserror`) and is raised before the request starts.
A destination containing a NUL byte is rejected as `HTTP badvalue` before any
file is created or request is sent.
An enclosing `sched.deadline` propagates `SCHED deadline` while cancelling the
request, independently of the request's own `HTTP timeout`.

TLS client-certificate errors 12185/12186 and proxy TLS errors 12187/12188 are
`HTTP tls`. Their messages include the Windows error symbol, number, and the
certificate, private-key permission, or proxy setting to inspect. For example,
12185 means the client-certificate context has no associated private key; it
does not by itself prove a network ban. See Microsoft's
[WinHTTP error reference](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages).
An execution sandbox or a different account can change available credentials;
the diagnostic describes the reported failure without bypassing TLS validation.

---

<a id="kuu-page-net"></a>

<a id="kuu-page-net-net"></a>

## net

The network as seen from this machine: what a name resolves to, whether a
port answers, who is listening here, and which addresses this machine has.
Where an agent would reach for `Test-NetConnection`, `Resolve-DnsName`,
`Get-NetTCPConnection`, `netstat -ano`, or `ipconfig`.

```lua
local net = require "net"

net.resolve("example.org")              -- { { address = "93.184.215.14", family = "ipv4" }, ... }
net.probe("localhost", 5432, "2s")      -- { address = "127.0.0.1", family = "ipv4", elapsed = 0.003 }
net.listeners()                         -- { { port = 135, address = "0.0.0.0", family = "ipv4", pid = 1204, name = "svchost.exe" }, ... }
net.addresses()                         -- { { adapter = "Ethernet", address = "192.168.1.20", family = "ipv4", prefix = 24, up = true, ... }, ... }
```

Resolving and probing park the calling task and let the others run; both
take a timeout, five seconds unless given. `listeners` and `addresses` take
synchronous snapshots of Windows' local tables.

<a id="kuu-page-net-netresolve"></a>

### net.resolve

```lua
net.resolve(name [, timeout])   -- { { address, family }, ... } | nil, err
```

Every address the name resolves to, IPv4 and IPv6, in the order the system
returns them. An address literal resolves to itself, so a caller need not
check first. `family` is `"ipv4"` or `"ipv6"`. IPv6 addresses keep their
numeric interface scope, such as `fe80::1%1`, in both `resolve` and
`addresses`; `probe` accepts that same spelling.

Failures: `nil, NET resolve` when the name has no address, `nil, NET timeout`
when nothing answered in time. An empty name, a name with NUL, or a malformed timeout is a
programming error and raises NET badvalue.

<a id="kuu-page-net-netprobe"></a>

### net.probe

```lua
net.probe(host, port [, timeout])   -- { address, family, elapsed } | nil, err
```

Resolves the host, then tries to open a TCP connection to each address in
turn until one accepts; the connection is closed at once. The result says
which address answered and how many seconds the whole probe took. A port
that is closed answers with `nil, NET refused`; one behind a silent
firewall, or an address nobody has, ends in `nil, NET timeout`; no route at
all is `nil, NET unreachable`. The timeout bounds the whole probe, resolution
included.

Windows retries a refused connection before giving up, so `refused` arrives
after about two seconds, even on the loopback interface. Give a probe three
seconds or more when you need refused told apart from silence; a short
timeout is fine when you only care whether the port is up yet.

```lua
-- wait for a service to come up
local deadline = sched.clock() + 30
repeat
  local up = net.probe("127.0.0.1", 8080, "1s")
  if up then break end
  sched.sleep("500ms")
until sched.clock() > deadline
```

<a id="kuu-page-net-netlisteners"></a>

### net.listeners

```lua
net.listeners()   -- { { port, address, family, pid, name }, ... }
```

Every TCP port with a listening socket on this machine, sorted by port, with
the address it is bound to (`0.0.0.0` or `::` for all interfaces), the owning
process id, and that process's executable name where a process by that id
still exists. The same table answers `proc.find { port = }` in
[`proc`](#kuu-page-proc), which gives the owner's full entry. UDP is not listed.

<a id="kuu-page-net-netaddresses"></a>

### net.addresses

```lua
net.addresses()   -- { { adapter, description, address, family, prefix, up, loopback, mac }, ... }
```

One row per unicast address on every adapter, loopback and link-local
included: the adapter's friendly name and description, the address and its
family, the on-link prefix length, whether the adapter is up, whether it is
the loopback interface, and its MAC address when it has one. To find the
machine's own routable IPv4, filter for `up`, not `loopback`, `family ==
"ipv4"`, and an address not starting with `169.254.`.

<a id="kuu-page-net-errors"></a>

### Errors

Domain `NET`.

| code | when |
|---|---|
| `resolve` | the name has no address |
| `refused` | the port is closed: the host answered with a reset |
| `timeout` | nothing answered within the timeout |
| `unreachable` | no route to the address, or the address cannot be used from here |
| `badvalue` | a bad host, port, or timeout (raised) |
| `oserror` | Winsock or the IP helper failed in some other way |

---

<a id="kuu-page-sched"></a>

<a id="kuu-page-sched-sched"></a>

## sched

Tasks and time. The scheduler is the loop that runs every program: one thread,
one Lua state, coroutines that switch only where a palette call waits.

```lua
local sched = require("sched")
```

<a id="kuu-page-sched-tasks"></a>

### Tasks

```lua
local t = sched.spawn(function(a, b) return proc.run { a, b } end, "git", "status")
local r = t:join()           -- the function's results
t:status()                   -- "running", "done", or "failed"
```

`spawn` starts the function as a task and returns at once. Tasks are
coroutines, not threads: exactly one runs at any moment, and a task gives way
only when it waits on something, so plain Lua code never needs locks. A task
keeps running when its handle is dropped; its results wait until joined.

`join` returns what the function returned. If the function raised an error,
`join` raises that same error in the joiner, so a failing task is noticed
where its result was wanted. With a duration, `t:join("30s")` returns
`nil, err` with `SCHED timeout` when the task is still running, and the task
carries on; join again later.

The program ends when its main chunk returns, whatever tasks are still
running; join what you spawn.

<a id="kuu-page-sched-sleep-and-time"></a>

### Sleep and time

```lua
sched.sleep("250ms")   -- park this task; other tasks run
sched.sleep(0)         -- give other tasks a turn
sched.clock()          -- monotonic seconds, for measuring
sched.now()            -- wall-clock Unix seconds; time.now() uses the same Windows clock
```

`sched.clock` reads the performance counter, so its resolution is well under a
microsecond; through 0.8 it resolved to exactly 1 millisecond, which could not
measure anything short honestly. Its epoch is arbitrary and only differences
between two readings mean anything. `sched.now` is wall time and can move
backwards when the machine's clock is set; measure with `clock`, timestamp
with `now`.

Durations everywhere in kuu are a number of seconds or a string with a unit:
`"250ms"`, `"30s"`, `"1.5m"`, `"2h"`. A string without a unit is refused.

<a id="kuu-page-sched-deadlines"></a>

### Deadlines

```lua
local value, e = sched.deadline("30s", function(a)
  sched.sleep("10ms")
  return a
end, 42)
```

`deadline(duration, fn, ...)` returns the function's results unchanged. If
the deadline expires while that coroutine waits on the loop, it unwinds
the function and returns `nil, SCHED deadline`. Other errors pass through.
Nested scopes use the earliest deadline; an outer deadline crosses inner
scopes until it reaches the scope that owns it. A call's shorter timeout
still produces that call's normal timeout result.

This is a bound on waits, not a CPU interrupt. A function that computes
without waiting cannot be interrupted; a completed operation returns at
once. Spawned tasks have their own coroutine and do not inherit the scope.
Children are not killed by a deadline: keep a `proc.start` handle in a
`<close>` variable when the child's lifetime should end with the scope.
`proc.run` retains its internal handle until the child finishes even if
the wait is interrupted; give it its own `timeout` when it needs a firm
wall-clock lifetime. Program exit still closes every supervised job.
HTTP and network operations cancel their outstanding work when abandoned.

<a id="kuu-page-sched-where-waiting-is-not-possible"></a>

### Where waiting is not possible

A palette call parks the running coroutine by yielding. Inside a metamethod,
a `string.gsub` callback, a `table.sort` comparator, or a coroutine the program
created itself, Lua cannot yield to kuu. In those places kuu drives the loop in
place until the wait is over, so the call still returns the right thing, and
other tasks still make progress meanwhile.

<a id="kuu-page-sched-errors"></a>

### Errors

| SCHED code | when |
|---|---|
| `timeout` | `join` with a duration outlasted the task |
| `deadline` | an enclosing deadline expired while its function waited |
| `badvalue` | raised: an invalid duration, or a non-function deadline callback |
| `yield` | a coroutine yielded to kuu with nothing to wait for; the task (or the program) fails |
| `deadlock` | a wait has no possible wakeup; raised by an in-place wait, or terminates a deadlocked program with exit 1 |
| `oserror` | a scheduler allocation or timer could not be created |

These are the complete SCHED codes. `join` and `deadline` also propagate
errors raised by the function they run or observe, preserving the original
error object. Ordinary Lua argument-type errors remain Lua errors; see
[err](#kuu-page-err).

---

<a id="kuu-page-json"></a>

<a id="kuu-page-json-json"></a>

## json

Strict reading, exact writing.

```lua
local json = require("json")
local v, e = json.decode(text)            -- nil, err JSON parse | depth | duplicate
local s = json.encode(v)                  -- raises JSON badvalue | encoding | depth | oserror
local pretty = json.encode(v, { pretty = true })
```

<a id="kuu-page-json-the-mapping"></a>

### The mapping

| JSON | Lua |
|---|---|
| `null` | `json.null`, a sentinel, so a null inside an array keeps its slot |
| `true`, `false` | booleans |
| number | an integer when whole and within 64 bits, else a float |
| string | a string, UTF-8 both ways |
| array | a table marked with `json.array`, elements at 1 to n |
| object | a table with string keys |

Decoded arrays are marked, so an empty array stays `[]` on the way back and
`json.is_array(t)` tells. An unmarked table encodes as an array when its keys
are exactly 1 to n with n above zero, and as an object otherwise: `{}` is an
object, `json.array{}` is `[]`. `json.array(t)` marks an existing table.
Marked arrays must also have exactly the keys 1 to n, with no holes or other
keys; use `json.null` for an explicit null element.

```lua
local doc = json.decode('{"ids": [1, null, 3], "empty": {}}')
#doc.ids == 3            -- the null kept its place
doc.ids[2] == json.null
json.encode { list = json.array {}, none = json.null }   -- '{"list":[],"none":null}'
```

Integers survive exactly; a document carrying 64-bit identifiers round-trips
without loss. Integers beyond 64 bits decode as floats. Integral floats encode
with a decimal point (`2.0`), so the two number kinds do not blur.

<a id="kuu-page-json-a-decided-key-order"></a>

### A decided key order

A Lua table has no key order, so an object built from one encodes in whatever
order the hash gives. That order is stable within a build, but it is not a
promised interface and it cannot be chosen. A document compared byte for byte
— a manifest, a lockfile, a golden fixture, anything signed — needs one, so
`json.object` takes the pairs in the order they are to be written:

```lua
json.encode(json.object {
  { "tool",    "sigil" },
  { "version", "1" },
  { "count",   14 },
  { "files",   json.array { json.object { { "path", "a.txt" }, { "size", 6 } } } },
})
-- {"tool":"sigil","version":"1","count":14,"files":[{"path":"a.txt","size":6}]}

json.object {}      -- encodes as {}
json.is_object(v)   -- true for a marked ordered object
```

It marks the table it is given, exactly as `json.array` does, and nests at any
depth. Each entry must be a two-element `{ key, value }` table whose key is a
string; the outer list and each pair must have no holes or extra keys.
Malformed shapes raise `JSON badvalue`; repeated object keys raise
`JSON duplicate`, matching the decoder's policy. Decoding is
unchanged: a document read back is an ordinary table, because the order is a
property of writing, not of the value.

<a id="kuu-page-json-refusals"></a>

### Refusals

Decoding is strict: a duplicate object key is `JSON duplicate` at any depth,
because last-wins would silently lose data; nesting beyond 512 is `JSON depth`;
a lone surrogate escape, trailing text, or any malformation is `JSON parse` with
the byte offset. Encoding raises for values JSON has no spelling for: NaN and
infinity, functions and userdata other than `json.null`, tables mixing array
and string keys, non-string keys, strings that are not valid UTF-8, and cycles,
which surface as `JSON depth`.

The complete code set is `parse`, `duplicate`, and `depth` for decoding;
`badvalue`, `duplicate`, `encoding`, `depth`, `usage`, and `oserror` for encoding. `usage`
is raised for an unknown option; `oserror` means the encoder could not
allocate its document.

Output is compact by default, with the seven short escapes, lowercase
`\u00xx` for other control characters, and UTF-8 left raw.

---

<a id="kuu-page-csv"></a>

<a id="kuu-page-csv-csv"></a>

## csv

Comma-separated values as RFC 4180 has them, and the variants Windows tools
write: other separators, CRLF or LF line ends, a leading byte order mark.
Where an agent would reach for `Import-Csv`, `Export-Csv`, or `ConvertFrom-Csv`.

```lua
local csv = require "csv"

local rows = csv.decode(text)                          -- { { "a", "b" }, { "1", "2" } }
local recs = csv.decode(text, { header = true })       -- { { a = "1", b = "2" } }, recs.columns = { "a", "b" }
csv.decode(text, { separator = ";" })                  -- Excel in many locales; "\t" for TSV
csv.encode(rows)                                       -- CRLF line ends, quotes only where needed
csv.encode(recs, { columns = { "a", "b" } })           -- records: a header row, then each record's fields
csv.encode(rows, { separator = ";", bom = true })      -- Excel opens it as UTF-8
```

<a id="kuu-page-csv-csvdecode"></a>

### csv.decode

```lua
csv.decode(text [, options])   -- rows | nil, err
```

Every field is a string; nothing guesses at numbers, dates, or booleans.
Quoted fields may hold the separator, quotes (written doubled), and line
ends. CRLF, LF, and CR all end a line; a final line end is not an extra row;
blank lines are skipped; a leading UTF-8 byte order mark is dropped. A
quoted empty field (`""`) is a row, and a row containing just one empty
field is encoded that way so it survives a round trip.

| option | default | |
|---|---|---|
| `separator` | `","` | one byte; `";"` for European Excel, `"\t"` for TSV |
| `header` | `false` | the first row names the columns; the result is records keyed by name, with `columns` alongside |
| `ragged` | `false` | allow rows with a different number of fields than the first row |

Failures are `nil, CSV parse` with the line number: an unterminated quoted
field, a quote inside an unquoted field, text after a closing quote, or a
row whose field count differs from the first row's unless `ragged` allows
it.

<a id="kuu-page-csv-csvencode"></a>

### csv.encode

```lua
csv.encode(rows [, options])   -- text
```

Rows are arrays of fields, or records when `columns` names the fields, in
that order; a decoded records table carries its `columns` and encodes back
as it came. Strings, numbers, booleans, and `nil` (empty) are fields;
anything else raises CSV badvalue. A field is quoted only when it holds the
separator, a quote, a line end, or leading or trailing whitespace.

| option | default | |
|---|---|---|
| `separator` | `","` | |
| `columns` | `rows.columns` | the field names, for records |
| `header` | `true` | write the column names first, for records |
| `newline` | `"\r\n"` | RFC 4180 and Excel; `"\n"` when a Unix tool reads it |
| `bom` | `false` | a leading byte order mark, which Excel needs to read UTF-8 |

<a id="kuu-page-csv-errors"></a>

### Errors

Header mode rejects duplicate column names with `CSV parse`, so one field
cannot silently replace another. Array mode preserves the original cells.
Encoding records likewise requires distinct string column names and raises
`CSV badvalue` for duplicates.

Domain `CSV`: `parse` (returned), `badvalue` (raised), and `usage` (raised for
an unknown option).

---

<a id="kuu-page-ini"></a>

<a id="kuu-page-ini-ini"></a>

## ini

INI files as Windows has them: `[sections]`, `key=value`, comment lines
starting with `;` or `#`. Where an agent would reach for
`Get-IniContent` from a gallery module, or a regular expression it will
regret.

```lua
local ini = require "ini"

local t = ini.decode(text)                  -- { [""] = { top-level keys }, Section = { key = "value" } }
t.Server.port                               -- "8080": always a string
ini.get(t, "server", "PORT")                -- the same, ignoring ASCII letter case
ini.encode(t)                               -- sections and keys sorted; deterministic
ini.encode(t, { newline = "\r\n" })        -- LF by default; CRLF when requested
ini.set(text, "Server", "port", "9090")     -- the text with that one change, the rest untouched
ini.remove(text, "Server", "port")          -- without that key; without the whole section when key is nil
```

Two ways of working, on purpose. `decode` and `encode` read a file into a
table and write a file of your own. `set` and `remove` edit a file that
belongs to something else: comments, order, spacing, and the line ending
style survive, and section and key names match ignoring ASCII letter case.
Non-ASCII bytes are compared exactly. Read the
file with `fs.read`, edit, write it back with `fs.write`.

<a id="kuu-page-ini-rules"></a>

### Rules

- Keys before any section header live under the empty section name, `""`.
- Section names must be strings. `encode` and `set` reject names containing
  CR or LF because they would write additional lines instead of the requested
  section. Spaces and brackets within a section name are preserved.
- Keys and values are trimmed. A value in surrounding double quotes has
  them removed and the inside kept, as the Windows profile functions do;
  encode and set quote a value that would not otherwise survive.
- A line without `=` is a key with an empty value.
- `encode` and `set` reject empty or padded keys, keys containing `=` or a
  line end, and keys beginning with a comment or section marker (`;`, `#`, `[`),
  because those spellings cannot preserve the requested key when read back.
- There are no inline comments: everything after `=` is the value, a `;`
  included, which is what Windows does too.
- Duplicate keys: the last wins. Duplicate sections merge, ignoring case
  and keeping the first spelling of each section and key in the table.
- Values are strings; numbers and booleans given to `encode` or `set` are
  written with `tostring`.

<a id="kuu-page-ini-iniset-and-iniremove"></a>

### ini.set and ini.remove

```lua
ini.set(text, section, key, value)   -- text
ini.remove(text, section [, key])    -- text
```

`set` replaces the last occurrence of an existing key across all matching
sections, keeping the key's own
spelling and the spacing around `=`; adds a missing key after the last
line of its section, before the blank lines that precede the next header;
appends a missing section at the end. `section` `""` means the top level.
`remove` drops every occurrence of the key in matching sections, or every
matching section with its header when `key` is nil. It returns the text
unchanged when there is nothing to remove. Both edits preserve a UTF-8 BOM.
Files using one line-ending style retain it; mixed LF/CRLF input is normalized
to CRLF if any CRLF is present, otherwise LF.

<a id="kuu-page-ini-errors"></a>

### Errors

Domain `INI`, all raised: `badvalue` for an unrepresentable key or section
name, a value that spans lines, or a table that is not sections of keys;
`usage` for an unknown option.

---

<a id="kuu-page-hash"></a>

<a id="kuu-page-hash-hash"></a>

## hash

Digests, HMAC, and random bytes from Windows' own cryptography (CNG). Nothing
is vendored.

```lua
local hash = require("hash")
hash.sum("sha256", bytes)                    -- lowercase hex
hash.sum("sha256", bytes, { raw = true })    -- the digest bytes
hash.file("sha256", "build/kuu.exe")         -- streamed in 64 KiB chunks; nil, err
hash.hmac("sha256", key, bytes)
hash.random(32)                              -- bytes from the system RNG, 1 to 1048576
hash.uuid()                                  -- "5f3a…-…-4…-…", a random version 4 UUID, lower case
hash.algorithms()                            -- { "md5", "sha1", "sha256", "sha384", "sha512" }

local h = hash.start("sha256")
h:update(part1):update(part2)
h:final()                                    -- hex; the hasher is finished
```

`sum` and `file` accept `{ raw = true }` as the third argument, `hmac` as
the fourth, and `h:final` as its options argument. All default to lowercase
hex; raw results are digest bytes.

Strings are bytes, so what you pass is what is hashed, and
`hash.sum("sha256", "abc")` agrees with every other implementation. The list
`hash.algorithms()` returns is the list the binary has; an unknown name raises
`HASH badvalue` and says so.

`hash.file` uses the same normalized Unicode paths as `fs`, including paths
beyond 260 characters, and refuses the same paths the same way: a
drive-relative, device, or trailing-dot/space path, or one that is not
UTF-8, raises as it does in `fs.read`, since 0.10.0; a path containing NUL
raises instead of silently hashing the filename before that byte.

| HASH code | when |
|---|---|
| `badvalue` | raised: unknown algorithm, a count out of range, an oversized key, NUL in a filename, or an ambiguous path |
| `encoding` | raised: `hash.file`'s path is not valid UTF-8 |
| `usage` | raised: an unknown option |
| `notfound`, `access` | `hash.file`: the file cannot be opened or read |
| `oserror` | file I/O failed, or raised when Windows' cryptographic provider failed |
| `closed` | raised: a finished hasher was used again |

---

<a id="kuu-page-text"></a>

<a id="kuu-page-text-text"></a>

## text

Strict conversion between UTF-8 and the encodings Windows programs emit.

```lua
local text = require("text")
text.decode(bytes, "cp1252")      -- UTF-8, or nil, err TEXT invalid
text.encode(str, "utf-16le")      -- bytes, or nil, err TEXT unencodable
text.valid(bytes)                 -- true when the bytes are strict UTF-8
text.encodings()                  -- the accepted names

text.tobase64(bytes)              -- standard alphabet, padded
text.tobase64(bytes, { url = true })   -- the url alphabet, no padding
text.frombase64(s)                -- bytes, or nil, err TEXT invalid; either alphabet, padding optional, whitespace ignored
text.tohex(bytes)                 -- lower case
text.fromhex(s)                   -- bytes, or nil, err TEXT invalid; either case, whitespace ignored

text.upper(s), text.lower(s)      -- Unicode case mapping by Windows' invariant rules, the ones file names fold by;
                                  -- Lua's own string.upper knows ASCII only; nil, err TEXT invalid for bad UTF-8

text.trim(s)                      -- without leading or trailing blanks
text.trim(s, "left")              -- or "right", or "both", the default
```

`trim` removes the six bytes Lua's `%s` matches -- space, tab, newline,
vertical tab, form feed, carriage return -- from one end or both. It trims
bytes, not characters: a Unicode space that is not one of those six is kept,
as `%s` would keep it. A string needing no trimming is returned as itself
rather than copied, and `where` other than `"both"`, `"left"` or `"right"`
raises `TEXT badvalue`.

It is here because writing it as a pattern is a trap. `s:gsub("%s+$", "")`
looks like it inspects the end of the string and does not: only `^` anchors a
Lua pattern, so Lua retries the match at every position and the cost grows
with the whole string rather than with the blanks. Trimming a 15-byte line
300,000 times measured 300 ms by that pattern and 13 ms through `trim`;
trimming a 278 KB document 200 times, 3.2 seconds against 26 ms. See
[Pitfalls](#kuu-page-pitfalls).

Encodings: `utf-8`, `utf-16le`, `utf-16be`, `latin1`, `ansi` (the system code
page), `oem` (the console code page), and `cpNNN` for any Windows code page
number, such as `cp850` for what `cmd.exe` writes on a Western European
system.

Every conversion is strict. Bytes that are not valid in the named encoding are
refused, never replaced by U+FFFD; a character the target code page cannot
represent is refused, never best-fitted to a lookalike. A silently rewritten
name is worse than a reported one. UTF-16 input must have an even number of
bytes and paired surrogates; byte-order marks are not interpreted or produced.

| TEXT code | when |
|---|---|
| `invalid` | the input is not valid in the named encoding, or is not base64 or hex |
| `unencodable` | the string has characters the target encoding lacks |
| `unsupported` | the code page is not available on this system |
| `badvalue` | raised: an unknown encoding name |
| `usage` | raised: an unknown option |
| `toobig` | the input is too long for Windows' case mapping |
| `oserror` | raised: allocation or Windows case mapping failed |

---

<a id="kuu-page-re"></a>

<a id="kuu-page-re-re"></a>

## re

Regular expressions, on PCRE2: the syntax of Perl, PCRE, and every editor,
with alternation, counted repetition, named groups, and Unicode, which Lua
patterns lack. Strings are bytes as everywhere in kuu; positions are Lua's,
one-based and inclusive.

```lua
local re = require("re")
re.find("the year 2026", "\\d+")                    -- 10, 13
re.find("key = value", "(\\w+)\\s*=\\s*(\\w+)")     -- 1, 11, "key", "value"
re.match("x=42", "(\\w)=(\\d+)")                    -- "x", "42"; the whole match when there are no groups
for word in re.gmatch("one two", "\\w+") do end
re.gsub("2026-09-09", "(\\d+)-(\\d+)-(\\d+)", "$3/$2/$1")            -- "09/09/2026", 1
re.gsub("john smith", "(?<first>\\w+) (?<last>\\w+)", "${last}, ${first}")
re.gsub("a b c", "\\w", function(w) return w:upper() end)             -- a function or a table, as string.gsub
re.split("a, b,c", "\\s*,\\s*")                    -- { "a", "b", "c" }
re.exec("Date: 2026-09-09", "(?<year>\\d{4})-(\\d{2})-(\\d{2})")
-- { start = 7, stop = 16, "2026", "09", "09", year = "2026" }; an unset group is false
re.escape("a.b*c")                                  -- "a\\.b\\*c"

local rx = re.compile("(?<key>\\w+)=(?<value>\\d+)", "i")
rx:find(s), rx:match(s), rx:gmatch(s), rx:gsub(s, r), rx:split(s), rx:exec(s)
rx.groups, rx.names                                 -- 2, { key = 1, value = 2 }
```

Every function takes the pattern as a string and optional flags as its last
argument; `find`, `match`, and `exec` take an `init` before the flags, as
`string.find` does. Compiled patterns are cached, so the functions cost no
more than the methods; `compile` is for a pattern used many times or for its
`groups` and `names`.

`gsub` takes an optional replacement count before its flags:
`re.gsub(s, pattern, replacement, n, flags)` or `rx:gsub(s, replacement, n)`.
Omitting `n` replaces every match; zero makes no replacements. For flags
without a count, pass nil in that slot.

| flag | meaning |
|---|---|
| `i` | caseless |
| `m` | `^` and `$` match at every line; a line ends at CR, LF, or CRLF |
| `s` | `.` matches a newline too |
| `x` | whitespace and `#` comments in the pattern are ignored |
| `b` | bytes: no UTF-8, `.` is one byte, any subject is fine |
| `u` | `\d`, `\w`, `\b` and friends know Unicode, not only ASCII |

Patterns and subjects are UTF-8 unless `b`. A subject that is not valid
UTF-8 is refused as `RE invalid`, naming the byte, rather than matched wrongly;
for arbitrary bytes, such as a log with a stray byte, use `b`. `\C` is never
allowed.

In a replacement string, `$1` to `$99` and `${name}` are groups, `$0` the
whole match, and `$$` a dollar; anything else after `$` is refused. An unset
group expands to nothing. A function replacement is called with the
captures, or the whole match when there are none, and a table is looked up by
the first capture, or the whole match; `nil` or `false` keeps the original,
as in `string.gsub`.

An empty match advances by one character, or one CRLF, and never repeats at
the same place, so `gmatch`, `gsub`, and `split` always finish. `split` makes
no piece from an empty match at a boundary, so `re.split("abc", "")` is the
characters, and keeps empty fields between and after separators, so
`re.split("a,,b,", ",")` is `{ "a", "", "b", "" }`.

The engine's own limits stop a catastrophic pattern rather than letting it run
for hours: `RE limit`. No JIT is built in, on purpose; the interpreter handles
a megabyte of `gsub` well under a second.

| RE code | when |
|---|---|
| `badpattern` | raised: the pattern does not compile; the message has PCRE2's words and the offset |
| `badvalue` | raised: an unknown flag, `b` with `u`, a bad `$` in a replacement, a replacement that is not a string |
| `invalid` | raised: the subject is not UTF-8, or `init` is inside a character; flag `b` matches bytes |
| `limit` | raised: the match exceeded the engine's limits |
| `oserror` | raised: allocation failed, or the engine returned another internal error |

---

<a id="kuu-page-time"></a>

<a id="kuu-page-time-time"></a>

## time

Instants, zones, and ISO 8601. An instant is a number of seconds since
1970-01-01T00:00:00Z, fractional and exact to the millisecond, so what
`os.time` returns is an instant too. A zone is `"utc"`, `"local"`, or a fixed
offset such as `"+02:00"`; the local zone follows the machine's rules for the
instant in question, daylight time included.

```lua
local time = require("time")
time.now()                                  -- 1788962585.123
time.ms()                                   -- 1788962585123, an integer
time.iso()                                  -- "2026-09-09T14:03:05Z"
time.iso(t, { zone = "local", ms = true })  -- "2026-09-09T16:03:05.123+02:00"
time.parse("2026-09-09T16:03:05+02:00")     -- 1788962585; nil, err TIME badvalue when it is not a date
time.parse("2026-09-09 14:03", "utc")       -- a text without a zone is read in the zone given, local by default
time.parts(t, "local")
-- { year = 2026, month = 9, day = 9, hour = 16, min = 3, sec = 5, ms = 123,
--   wday = 4, yday = 252, offset = 120, zone = "+02:00", dst = true }
time.make({ year = 2026, month = 9, day = 9, hour = 14 })          -- UTC unless a zone follows
time.make({ year = 2026, month = 13, day = 1 })                     -- fields carry: 2027-01-01
time.make({ year = 2026, mnth = 2 })                                -- raises TIME usage: not a part it has
time.format(t, "%Y-%m-%d %H:%M:%S %z", "local")                     -- strftime; %z and %Z are the zone asked for
time.zone()          -- { name = "Romance Daylight Time", key = "Romance Standard Time", standard, daylight, offset = 120, dst = true }
time.duration("1h30m")   -- 5400; the units ms s m h d, alone or summed, or plain seconds; the same grammar every timeout takes
time.human(93784)        -- "1d 2h"; two units, or "5.2s", or "250ms"
```

`parse` accepts a date, or a date and a time separated by `T` or a space,
seconds optional, a fraction optional, and `Z` or an offset optional. It
checks that the day exists. `wday` counts from Sunday as 1, as `os.date` does.
`os.date` and `os.time` keep working and agree with `time.parts(t, "local")`;
they know only the machine's zone and whole seconds, which is why this module
exists. Named zones other than the machine's own are not supported yet; an
offset says what is meant.

| TIME code | when |
|---|---|
| `badvalue` | `nil, err` from `parse` for a text that is not an instant; raised for a bad zone, a bad duration, a bad format, or an instant out of range |
| `usage` | raised: an unknown option |
| `oserror` | raised: Windows could not report the zone |
Malformed text passed to `time.parse`, including signed date/time fields
or an offset beyond +/-14:00, returns `nil, TIME badvalue`. Invalid
explicit zone arguments remain programming errors and raise.

---

<a id="kuu-page-archive"></a>

<a id="kuu-page-archive-archive"></a>

## archive

Zip and tar archives using Windows' archive components. `pack` and `unpack`
use the system `tar.exe`. `list` uses the Unicode API in its companion
`System32/archiveint.dll`, the libarchive that Windows ships beside `tar.exe`
since Windows 10 1803. It is loaded only from the system directory and every
entry point is checked; it is not a documented Windows API, so on a Windows
without it, or one that changes it, `list` fails with `ARCHIVE oserror`
naming the library while `pack` and `unpack` keep working. No extra
executable or archive library is installed.

```lua
local archive = require("archive")

archive.unpack("build/zig.zip", ".tools/zig", { strip = 1 })   -- true | nil, err
archive.pack("build/out.zip", "build/stage")                   -- everything in the directory
archive.pack("build/src.tar.gz", ".", { "src", "Makefile" })   -- named entries, relative to the directory
archive.list("build/zig.zip")                                  -- { "zig-x86_64-windows-0.16.0/", ... }

archive.unpack(file, dir, { strip = 1, timeout = "10m" })
archive.pack(file, dir, nil, { timeout = "10m" })   -- options are fourth, after entries
archive.list(file, { timeout = "10m" })
```

The format follows the archive's extension: `.zip`, `.tar`, `.tar.gz` or
`.tgz`, `.tar.xz`, `.tar.zst`, `.tar.bz2`. `unpack` creates the directory
when needed and overwrites what is there; `strip` drops that many leading
path components, so an archive whose single top-level directory carries the
version lands where you say. `pack` creates a temporary archive beside the
destination and replaces the existing archive only after packing succeeds.
Invalid arguments, failed packing, and timeouts preserve the previous archive.
When the output lies inside the input directory, that exact output and its
temporary file are excluded from the archive; other files with the same name
at different paths are kept.
Entries must be a dense array of names inside the directory, never absolute
and never climbing out; holes, map keys, and non-table lists raise
`ARCHIVE badvalue` before staging the output. Names beginning with `@` or
`--` are literal filenames, including when entries are discovered by packing
a whole directory. A leading `./` may appear in their archived names.
Windows'
bsdtar refuses archive entries that would climb out of the target directory,
so an unpack stays under the directory you name.

| code | meaning |
|---|---|
| `ARCHIVE notfound` | no archive, or no directory, at that path |
| `ARCHIVE failed` | an invalid archive, unsupported format, or rejected entry; pack/unpack retain tar's diagnostic |
| `ARCHIVE badvalue` | raised: wrong paths, a negative `strip`, an invalid entry array, or entries that leave the directory; returned for an empty directory to pack |
| `ARCHIVE usage` | raised: an unknown option |
| `ARCHIVE timeout` | the archive operation did not finish within `timeout` (default 30m) |
| `ARCHIVE encoding` | an entry has no valid Unicode filename |
| `ARCHIVE toobig` | listing exceeds 64 MiB of names, one million entries, or 64 MiB of encoded output |
| `ARCHIVE oserror` | the required Windows component is unavailable |

Filesystem setup and process launch failures retain their `FS` and `PROC`
domains. Invalid timeout values raise `PROC badvalue`. An enclosing
`sched.deadline` propagates `SCHED deadline` as with other waiting calls.

`list` returns UTF-8 names, including characters outside the system ANSI code
page. Embedded newlines remain part of a name. Directories retain their trailing
slash; backslashes become forward slashes to match Windows extraction semantics.
It does not extract files or parse tar's lossy text listing. The native reader
runs in a supervised copy of this same `kuu.exe`, with its own `timeout`,
without blocking the parent's scheduler. An enclosing `sched.deadline`
interrupts the wait; the worker can continue until it finishes, reaches its
own timeout, or the parent exits, as with `proc.run`. The internal
`_archive` module is an implementation detail, not a supported public API.
ZIP creation explicitly writes UTF-8 headers so names survive packing too.

Fetching a prerequisite is these two capabilities together, and nothing more:

```lua
local http, archive = require("http"), require("archive")
local r, e = http.get("https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip", {
  to = "build/zig.zip",
  sha256 = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e",
})
if not r then return nil, e end                              -- a wrong hash is HTTP mismatch, and no file is left
local ok, e2 = archive.unpack("build/zig.zip", ".tools/zig", { strip = 1 })
```

---

<a id="kuu-page-log"></a>

<a id="kuu-page-log-log"></a>

## log

Say what happened, where someone can read it later.

```lua
local log = require("log")
log.info("built", { target = out, bytes = size })
log.warn("queue at 90%")
log.error("cannot open", { path = p, err = e })
log.debug("retrying", { attempt = n })
```

A line is the local time with milliseconds, the level, the message, and the
fields sorted by key, quoted where a space or quote would make them ambiguous:

```text
2026-09-09T14:03:05.123 INFO  built bytes=307200 target=build/kuu.exe
```

Field values may be strings, numbers, booleans, error objects (rendered as
`DOMAIN code: message`), or tables (rendered as JSON). Each call returns true
when the line was emitted and false when it was filtered or dropped.
Field keys are rendered with `tostring`; text output keeps each original
key's value, including numeric keys. Keys with the same displayed spelling
appear as separate text fields.

<a id="kuu-page-log-configuration"></a>

### Configuration

```lua
log.configure { level = "debug" }            -- debug, info, warn, error, off; default info
log.configure { file = "build/log.txt" }     -- append to a file; false returns to stderr
log.configure { json = true }                -- one JSON object per line: ts, level, msg, then your fields
log.configure { sink = function(line) end }  -- your own destination; false removes it
log.configure()                              -- { level, file, json, sink, dropped }
```

Levels are `debug`, `info`, `warn`, `error`, and `off`, and the default is
`info`. A record below the configured level is filtered, and its call returns
false rather than raising.

Every option is validated before any is applied, so a bad call leaves the
previous configuration intact; a file that cannot be opened raises
`LOG oserror` at configure time rather than being discovered by silently
counting drops. Writing never raises: a sink that fails increments `dropped`,
which `configure()` reports, because a diagnostic must not terminate the work
it describes. An unrenderable message or field is also counted as a drop.
JSON mode always emits JSON; invalid UTF-8 strings, cyclic tables, or other
values that JSON cannot encode cause the entire record to be dropped, with
no line sent to the sink. User fields are top-level JSON properties; the
logger's `ts`, `level`, and `msg` properties take precedence. A custom
sink may report failure by raising, returning `false`, or returning `nil, err`;
returning nothing means success. Failed file writes and flushes count as drops.
The default sink is standard error, resolved at write time, so a
program that never logs opens nothing.

| LOG code | when |
|---|---|
| `badvalue` | raised: a non-table argument, an unknown level, or a `file` or `sink` of the wrong kind |
| `usage` | raised: an unknown option |
| `oserror` | raised: the log file cannot be opened |

---

<a id="kuu-page-err"></a>

<a id="kuu-page-err-err"></a>

## err

The one error shape.

```lua
local err = require("err")
local e = err.new("TASK", "failed", "the build returned 1", { exit = 1 })
tostring(e)                 -- "TASK failed: the build returned 1"
e.domain, e.code, e.message, e.exit
err.is(e)                   -- true: it is one of these
err.is(e, "TASK")           -- true
err.is(e, "TASK", "failed") -- true
```

The optional fourth argument adds fields to the error. Keep `domain`, `code`,
and `message` out of that table: extra fields replace existing fields.

kuu's classified failures use such a table, with a closed set of domains and
codes documented per module. Lua's argument-type checks can still raise a
string error, and errors from user callbacks propagate unchanged. The
convention for classified failures is:

- An expected failure returns `nil, e`: a program that is not installed, a
  child that timed out waiting, a file that is not there.
- A programming mistake raises `e`: a missing command, a duration without a
  unit, an unknown option name.

The line between the two is the function's purpose. A function whose job is
to validate or convert input — `text.decode`, `time.parse`, `csv.decode`,
`cli.duration` — returns for input that fails, because failing input is the
outcome it exists to report. A function that assumes its input is well
formed — `fs.read` given a malformed path, `re.match` given a subject that
is not UTF-8, `time.duration` given a bare number in a string — raises,
because the fix is in the code that called it, not in the data. Every
module follows this since 0.10.0; where two once disagreed on the same kind
of failure, the disagreement is named in [upgrading to 0.10](#kuu-page-upgrading-010).

Branch on `err.is(e, "PROC", "notfound")`, never on the message text.
Messages are for people; domains and codes are for programs.

<a id="kuu-page-err-in-your-own-code"></a>

### In your own code

The same shape and the same law serve a project's own code. Choose an
uppercase domain of your own — `REPORT`, `DEPLOY` — and codes of your own
within it; `err.new` takes any domain, `check` judges codes only in the
domains kuu owns, and an unfamiliar domain says nothing about correctness.
Return `nil, err.new("REPORT", "stale", "inputs older than the report")`
from a function, or from a task's `run`, for the outcome the function
exists to report; raise for a caller's mistake. A task that returns
`nil, err` fails with that domain and code: `kuu run` prints `kuu: REPORT
stale: …`, the `--json` stream and envelope carry them as `error.domain`
and `error.code`, and so does [the ledger](#kuu-page-ledger). A task that returns
`nil, "some text"` instead is wrapped as `TASK failed` with that text as
the message, and a caller can no longer tell it from any other failure.
Of the extra fields, `exit` is the one kuu carries out of the task — into
the stream, the envelope, the ledger, and the process's exit code; any
other, `{ path = p }` say, stays on the Lua value for the task's own callers.

---

<a id="kuu-page-mem"></a>

<a id="kuu-page-mem-mem"></a>

## mem

A small memory across runs: what an agent decided, counted, or saw last time,
kept in one JSON file per project.

```lua
local mem = require("mem")
mem.set("last_build", { at = os.time(), ok = true })   -- any value JSON can hold
mem.get("last_build")                                   -- nil when absent
mem.get("runs", 0)                                      -- with a default
mem.update("runs", function(n) return (n or 0) + 1 end) -- read-modify-write as one step, under the lock
mem.forget("last_build")                                -- so does set(key, nil)
mem.keys()                                              -- sorted
mem.all()                                               -- a copy of everything
mem.path()                                              -- where it lives
mem.open("build/state.json")                            -- somewhere else instead
```

The file is `.kuu/memory.json` under the project root, the nearest
`manifest.lua` upward from the current directory, or under the directory
`require` searches when there is no project. `.kuu/` is kuu's own and is
never committed — it holds [the ledger](#kuu-page-ledger) too; a memory that is
meant to travel with the repository is opened somewhere else with
`mem.open(path)`.

Every `get` reads the file. Every `set` holds a [`sync`](#kuu-page-sync) lock across
processes in the same Windows session, named after the file, while it reads, merges, and
writes atomically, so two kuu processes writing at once take turns and
neither loses the other's keys; a writer that cannot get the lock within ten
seconds gets `SYNC busy`. A value computed from a `get` and then `set` is
still two steps, and two processes counting that way lose increments; `update`
runs the function under the lock, so it is one. The whole file may not exceed 1 MiB: `set` refuses with
`MEM toobig` and the file stands. This is a notebook, never a database; the
database stays out of kuu by decision.

| MEM code | when |
|---|---|
| `toobig` | the memory would exceed 1 MiB; nothing was written |
| `badvalue` | raised for an empty or non-string key or `open` path, or a non-function `update` callback; `nil, err` for a value JSON cannot hold |
| `corrupt` | raised: the file is not a JSON object |
| `unreadable` | raised: the file exists and cannot be read |

Writes can also return the original `FS` error from creating the directory
or writing the file, or `SYNC busy` if the lock times out. Invalid paths and
lock setup failures keep their `FS` or `SYNC` domain. An `update` callback's
error propagates unchanged, releases the lock, and leaves the file intact.

---

<a id="kuu-page-sync"></a>

<a id="kuu-page-sync-sync"></a>

## sync

One at a time, across processes: a named lock that two kuu processes in the
same Windows session, or two tasks in one, take turns on.

```lua
local sync = require("sync")
local lock <close> = assert(sync.lock("deploy", "10s"))   -- waits up to 10 s; released when the block ends
lock:release()                                            -- or explicitly; idempotent

local now, e = sync.try("deploy")                         -- acquire now or nil, SYNC busy
if now and now.abandoned then log.warn("the previous holder died mid-way") end
```

The lock is a named Windows mutex in the `Local` namespace, so it costs
nothing on disk and there is no stale lock file to break: when a holder dies
without releasing, the kernel hands the lock to the next taker and marks it
`abandoned`, which is the moment to check whatever the dead holder was doing.
kuu keeps one handle per name open for as long as the process lives, because
a mutex whose last handle closes is simply gone and the next taker would get
a fresh one that was never abandoned; a process that has tried a name once
therefore always learns of a death. A kuu that exits normally releases its
locks as its state closes, so only a killed holder abandons.
`lock` waits on the loop, so other tasks keep running while it waits, and
gives up with `SYNC busy` after the timeout, 30 seconds by default. A lock
is released by `release`, by the end of a `<close>` block, or when it is
collected; kuu's own bookkeeping holds it weakly, so dropping the last
reference is enough, though only `release` and `<close>` are prompt. It is
exclusive within one kuu as well: a second `try` from the
same process is `busy`, although Windows would have let the same thread in
again. Names are 1 to 200 bytes without backslashes or control characters,
and are the same across every kuu in that session. A different logon session
has its own `Local` namespace and does not share these locks.

`mem` holds one of these while it reads, merges, and writes its file.

| SYNC code | when |
|---|---|
| `busy` | `nil, err`: held elsewhere (`try`), or still held after the timeout (`lock`) |
| `badvalue` | raised: a bad name or timeout |
| `oserror`, `encoding` | raised: the mutex could not be opened, or the name is not UTF-8 |

---

<a id="kuu-page-sys"></a>

<a id="kuu-page-sys-sys"></a>

## sys

Facts about this machine and this process, read fresh on every call.

```lua
local sys = require("sys")
local i = sys.info()
-- i.windows.build      26200            an integer; Windows 11 is 22000 and above
-- i.windows.revision   6584             the update build revision, the fourth number
-- i.windows.version    "10.0.26200"     what the kernel reports, truthfully
-- i.windows.display    "25H2"           the marketing name, from the registry
-- i.windows.server     false            a Windows Server edition
-- i.hostname           "FORGE"
-- i.user               "anafa"
-- i.elevated           false            running with administrator rights
-- i.cpus               16
-- i.arch               "x64"            or "arm64"
-- i.memory.total       68584734720      bytes; i.memory.available likewise
-- i.drives             { { letter = "C:", type = "fixed" }, { letter = "D:", type = "removable" } }
-- i.uptime             84213.5          seconds since boot
-- i.pid                4120
-- i.codepage           1252             the ANSI code page programs without UTF-8 use
-- i.process            { handles = 61, working_set = 9437184, peak_working_set = 9502720, private = 5242880 }
```

`process` is this kuu, in bytes and handles, for a program that keeps an eye
on itself; the soak test watches it across rounds.

Drive types are `fixed`, `removable`, `remote`, `cdrom`, `ramdisk`, or
`unknown`. The version comes from `RtlGetVersion`, which tells the truth
where the older calls lie to programs without a manifest. `elevated` is what a
PowerShell script means by `IsInRole(Administrator)`: this process, now, with
this token. Nothing here is cached and nothing here writes.

<a id="kuu-page-sys-syssignature"></a>

### sys.signature

```lua
local signature, e = sys.signature("installer.exe")
local signature, e = sys.signature("installer.exe", { revocation = true })
```

An unsigned file returns `{ signed = false }`. An embedded signed file returns
`{ signed = true, valid = true, signer, issuer, thumbprint, timestamped }`.
`signer` and `issuer` are the certificate display names, and `thumbprint` is
the leaf certificate's 40-character uppercase SHA-1 identifier. `timestamped`
reports the presence of a countersignature or RFC 3161 timestamp attribute.
It is separate from validity; an invalid timestamp can still be present.

A failed trust check returns `signed = true, valid = false, reason = ...`.
Reasons are `expired`, `untrusted`, `tampered`, `revoked`, `distrusted`,
`revocation` (the revocation check could not complete), `timestamp`, `usage`,
or `invalid` (another trust failure). Certificate identity fields can be absent
if a damaged signature could not be decoded. A trust failure is a result,
not `nil, err`.

Only embedded Authenticode signatures are inspected. Files signed only through
a Windows catalog report `signed = false`; no catalog lookup is performed.
Revocation checks and network certificate retrieval are disabled by default.
`revocation = true` enables chain revocation checking and may use the network.
Verification runs on a worker so the Lua loop keeps running. A surrounding
`sched.deadline` can abandon the wait, but Windows' verification itself cannot
be cancelled; its resources remain owned until it finishes. Shutdown waits
for an outstanding verification to finish before freeing the loop.

`valid` means Windows accepted the signature under the selected trust policy.
Before running an installer, also match its signer or pinned thumbprint to the
identity you expect. Signature inspection opens the file for reading and
prevents writes while checking it; it does not reserve the path after return.

<a id="kuu-page-sys-errors"></a>

### Errors

The complete SYS code set is `notfound` (missing signature path), `access`
(the file cannot be read or is open for writing), `badvalue` (raised for a
malformed path or a `revocation` that is not a boolean; `nil, err` for a
directory, the wrong kind of object, as `fs` returns it), `usage` (raised for
an unknown option), and `oserror` (other Windows or allocation failures).
`sys.info` has no expected error return.

---

<a id="kuu-page-reg"></a>

<a id="kuu-page-reg-reg"></a>

## reg

The registry, typed. Where an agent would reach for `Get-ItemProperty`,
`Set-ItemProperty`, `New-Item HKCU:\...`, or `reg.exe`.

```lua
local reg = require "reg"

reg.get("HKCU\\Software\\Vendor\\App", "Level")      -- 3, "dword"
reg.set("HKCU\\Software\\Vendor\\App", "Level", 4)   -- creates the key path when needed
reg.set(key, "Path", "%ProgramFiles%\\x", "expandstring")
reg.values(key)                                      -- { { name = "Level", type = "dword", value = 4 }, ... }
reg.keys(key)                                        -- { "Sub1", "Sub2" }
reg.delete(key, "Level")                             -- one value
reg.remove(key)                                      -- the key and everything under it
```

A key is written `HKCU\Software\Vendor\App`; either slash works, and so do
the long root names. Roots: `HKLM`, `HKCU`, `HKCR`, `HKU`, `HKCC`. The
value name `nil` or `""` is the key's default value. kuu is a 64-bit
process and sees the 64-bit view.

<a id="kuu-page-reg-types"></a>

### Types

| type | Windows | Lua |
|---|---|---|
| `string` | REG_SZ | a string |
| `expandstring` | REG_EXPAND_SZ | a string, unexpanded; `env.expand` expands it |
| `multistring` | REG_MULTI_SZ | a list of non-empty strings |
| `dword` | REG_DWORD | an integer 0 to 4294967295 |
| `qword` | REG_QWORD | an integer, 64 bits, signed on the way back |
| `binary` | REG_BINARY | a string of bytes |

`get` and `values` return the value and its type name; a type not in the
table reads as bytes named `"unknown"`. `set` without a type stores a
string as `string`, an integer as `dword` when it fits and `qword`
otherwise, and a list as `multistring`; give the type to store an
`expandstring`, a `binary`, or a small `qword`. Floats have no registry
type and raise.

Text values must be valid UTF-16. `get` returns `nil, REG encoding` when
one is malformed; `values` keeps its `name` and `type` and supplies the
original `bytes` instead of `value`. An empty string is still `""`.
Keys, value names, and text passed to `set` cannot contain NUL; binary
values can.

<a id="kuu-page-reg-functions"></a>

### Functions

```lua
reg.get(key, name)                   -- value, type | nil, err
reg.set(key, name, value [, type])   -- true | nil, err
reg.delete(key, name)                -- true | nil, err
reg.values(key)                      -- { { name, type, value }, ... } sorted by name | nil, err
reg.keys(key)                        -- { name, ... } sorted | nil, err
reg.exists(key)                      -- boolean
reg.create(key)                      -- true | nil, err
reg.remove(key)                      -- true | nil, err
```

`remove` deletes a whole tree and refuses a key directly under a root.
Writing under `HKLM` needs an elevated kuu; without it the answer is
`nil, REG access`, not a silent redirect.

<a id="kuu-page-reg-errors"></a>

### Errors

Domain `REG`: `notfound` (no such key or value), `access` (run elevated),
`badvalue` (raised: a bad root, type, value, or embedded NUL), `encoding`
(text cannot be represented as UTF-8), `oserror`.

---

<a id="kuu-page-env"></a>

<a id="kuu-page-env-env"></a>

## env

Environment variables: this process's, and the ones Windows keeps for the
user or the machine. Where an agent would reach for `$env:NAME`,
`[Environment]::SetEnvironmentVariable(name, value, "User")`, or `setx`.

```lua
local env = require "env"

env.get("TEMP")                              -- the live value, UTF-8; os.getenv does the same
env.set("GIT_PAGER", "")                     -- for this process and the children it starts from now on
env.set("GIT_PAGER", nil)                    -- removed
env.all()                                    -- { NAME = value, ... }
env.expand("%LOCALAPPDATA%\\tool")           -- "C:\\Users\\me\\AppData\\Local\\tool"

env.persisted("Path")                        -- the user's stored Path, unexpanded, and its type
env.persist("TOOL_HOME", "%USERPROFILE%\\tool")   -- stored for the user, then the change is broadcast
env.forget("TOOL_HOME")                      -- removed, then the change is broadcast
env.persist("TOOL_HOME", "C:\\tool", "machine")  -- for everyone; needs an elevated kuu
```

<a id="kuu-page-env-the-two-environments"></a>

### The two environments

The **live environment** is this process's copy. `set` changes it for kuu
and for every child kuu starts afterwards; nothing outside notices. A
child's `env` option in [`proc`](#kuu-page-proc) does the same for one child.
`get` and `os.getenv` return `""` for an empty value and `nil` for an
absent variable. Names and text values cannot contain NUL.

The **persisted environment** is the user's stored settings under
`HKCU\Environment` and the machine's under the Session Manager's key.
`persist` and `forget` write there and broadcast `WM_SETTINGCHANGE`, allowing
programs such as Explorer to refresh their environment. This does not rewrite
every running process's copy. A new child normally inherits its parent's live
environment, so a console or editor started by an existing launcher may still
receive the old values. See Microsoft's [environment inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables)
and [change notification](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)
contracts. Kuu keeps its live copy: after `env.persist`, `env.get` still
answers as before. A value holding a
`%` is stored as an expandstring, as Windows does for `Path`; `persisted`
returns it unexpanded with its type, and `env.expand` expands it.

To add a directory to the user's `Path`, read `env.persisted("Path")`,
edit the string, and persist it back; nothing here edits `Path` for you,
because appending blindly is how `Path` fills with duplicates.

For project tools, pass a child `env` overlay instead of persisting machine or
user settings. The [shared project environment](#kuu-page-project-environment) recipe
derives cache paths from the project root and supplies the same overlay to CLI
tools and newly launched editors. An existing editor keeps its launch
environment; launching a client that reuses it does not refresh that copy.

<a id="kuu-page-env-functions"></a>

### Functions

```lua
env.get(name)                       -- value | nil
env.set(name, value)                -- true; value nil or false removes
env.all()                           -- { NAME = value }
env.expand(text)                    -- text with %VAR% references filled in
env.persisted(name [, scope])       -- value, type | nil
env.persist(name, value [, scope])  -- true | nil, err
env.forget(name [, scope])          -- true | nil, err
```

`scope` is `"user"` (the default) or `"machine"`.

<a id="kuu-page-env-errors"></a>

### Errors

Domain `ENV`: `badvalue` (raised: an empty name, a name with `=`, an unknown
scope, or embedded NUL), `notfound` (forgetting what is not there), `access` (the machine
scope without elevation), `oserror`.

---

<a id="kuu-page-svc"></a>

<a id="kuu-page-svc-svc"></a>

## svc

Inspect and control local Windows services through the Service Control Manager.

```lua
local svc = require "svc"
svc.list()                       -- list of { name, display, state, start, pid }
svc.status("Dnscache")           -- those fields plus exe, or nil, err
svc.start("MyService", "30s")    -- true, or nil, err; waits until running
svc.stop("MyService", "30s")     -- true, or nil, err; waits until stopped
svc.restart("MyService", "30s")  -- one timeout for the stop and start together
svc.wait("MyService", "running", "10s")
```

`list` is sorted by service name. It lists Win32 services, including per-user
services, rather than kernel drivers. The `start` field is `auto`, `manual`,
`disabled`, `boot`, or `system`. The `exe` field is the configured binary
command line, including its arguments and original quoting. It is not a path
to pass unchanged to `proc.run`. A stopped service has `pid = 0`.

States are `running`, `stopped`, `start_pending`, `stop_pending`, `paused`,
`pause_pending`, and `continue_pending`. `wait` accepts any of these. A state
already held succeeds immediately, even with a zero timeout. Starting an
already running service, or stopping an already stopped one, also succeeds.
Starting a paused service does not resume it; Windows' transition rules apply.

All timeouts accept seconds or durations such as `"10s"`; the default is 30
seconds. State transitions poll every 100 milliseconds, sleeping on the loop
so other tasks keep running. A timeout bounds how long kuu watches: it does
not undo a start or stop already requested. `restart` shares one timeout across
both transitions. Services are managed by Windows and live beyond kuu's exit.

Service names are the internal names (`Dnscache`), not the display strings.
They must be nonempty UTF-8 without NUL or slash characters. Access checks are
those of the current token. A refused operation returns `nil, SVC access`
naming the service; running elevated may be necessary. `list` also needs
permission to read each listed service's configuration.

<a id="kuu-page-svc-errors"></a>

### Errors

The complete SVC code set is `notfound` (no such service), `access`
(insufficient rights), `timeout` (the target state was not observed in time),
`badvalue` (raised for malformed names, states, or timeouts), and `oserror`
(other Windows failures, including service transition failures).

---

<a id="kuu-page-evt"></a>

<a id="kuu-page-evt-evt"></a>

## evt

Read local Windows event logs. This module never writes or clears a log.

```lua
local evt = require "evt"
local time = require "time"
evt.logs() -- channel names, including Application and System
local events, e = evt.read("System", {
  since = time.now() - 86400,
  level = "error",
  provider = "Service Control Manager",
  limit = 200,
})
```

Every option is optional. `since` is an instant in Unix seconds, as returned
by `time.now`, between 1601 and 9999. `level` is `critical`, `error`,
`warning`, `information`, or `verbose`. Unclassified level-zero events use
`information` and are included in that filter. `provider` matches the exact
publisher name. Names are UTF-8 without NUL; a provider containing both single
and double quote characters is refused because Windows' restricted XPath
cannot express that literal. An unknown option raises `EVT usage`.

`limit` defaults to 1000 and must be an integer from 1 to 100000. Results are
the newest records first. An empty query returns an empty table. Each entry
has these fields:

| field | value |
|---|---|
| `time` | instant in Unix seconds |
| `level` | one of the names above |
| `id` | integer event id |
| `provider` | publisher name |
| `message` | formatted message, or the raw event XML if its publisher resources are missing |
| `record` | integer record number within that channel |
| `computer` | computer name recorded in the event |

The query filters inside Windows and reads in batches. Only the returned
records are rendered. Messages use the machine's available publisher
resources and language; old events can remain readable as XML after their
publisher is uninstalled. This is a bounded snapshot, not a subscription;
choose a small `limit` when polling repeatedly. Channel permissions apply:
reading `Security`, for example, usually requires administrator rights.

<a id="kuu-page-evt-errors"></a>

### Errors

The complete EVT code set is `notfound` (unknown channel), `access`
(insufficient channel rights), `badvalue` (raised for malformed names,
instants, levels, or limits), `usage` (raised for an unknown option), and
`oserror` (other Windows failures).

---

<a id="kuu-page-pty"></a>

<a id="kuu-page-pty-pty----provisional-console-automation"></a>

## pty -- provisional console automation

`pty` drives Windows console programs through ConPTY. It is **provisional**
and outside the planned 1.0 API freeze. Use `proc` for ordinary subprocesses.

`local pty = require "pty"`

```lua
global none
global <const> require, assert
local pty = require "pty"
local p <close> = assert(pty.spawn { "cmd.exe", "/d", "/q", cols = 120, rows = 30 })
assert(p:expect({ ">" }, "5s"))
assert(p:write("echo hello\r"))
local text, which = assert(p:expect({ "hello", "error" }, "5s"))
assert(p:write("exit\r"))
assert(p:wait("5s"))
```

<a id="kuu-page-pty-launch-and-lifetime"></a>

### Launch and lifetime

`pty.spawn { exe, args..., cols = 120, rows = 30, cwd = path, env = table,
timeout = duration, maxout = "64M", limits = table }` returns a console
handle or `nil, err`. Dimensions must be integers from 1 to 32767. The
command, `cwd`, environment overrides/removals, lifetime `timeout`, and
job `limits` follow [proc](#kuu-page-proc). Without a lifetime timeout the child
can run indefinitely. `stdin`, `stream`, `inherit` and unknown options are
refused; input is written through the console handle.

The child is born into a kill-on-close job. `p.pid` identifies that child.
Windows also starts a `conhost.exe` process: it is visible in `proc.tree`
under the hosting kuu process, and exits when the console session ends.
It is a console host, not an extra application launched by the script.
Use `<close>` to terminate the child tree and release the console on all
paths. `p:close()` is idempotent. The host's pipe ends use overlapped I/O;
read, expect, and process waits keep the event loop running. On Windows 11
23H2, each console reserves two isolated native workers before launch: one
closes the console and the other drains abandoned output. The OS close call
can block while writing its final frame. Natural exit starts closing only
after the whole supervised job exits and retains output for the Lua reader
until EOF. Explicit close cancels pending I/O, waits for completion before
transferring the output pipe, and lets the native drainer discard its tail.
Runtime cancellation completes through the event loop; final shutdown uses
separate completion events without running Lua callbacks. Kuu joins both
workers before exiting. Neither worker accesses Lua or the event loop. On
24H2 and later, Kuu uses the OS's release and asynchronous-close APIs directly.

The console lifetime follows its supervised job on 23H2. A client that
deliberately escapes that job must also detach from the console if it needs
to outlive the session.

`p:write(bytes)` queues UTF-8 console input and returns `true` or `nil, err`.
Use `"\r"` for Enter. Input includes control sequences when the console
application expects them. The pending input queue is bounded at 64 MiB.
`p:resize(cols, rows)` changes the console buffer size and returns
`true` or `nil, err`.

`p:wait([timeout])` returns the [proc result](#kuu-page-proc), including `status`,
`code`, `pid`, `elapsed` and optional `limit`. Output is consumed through
`read`/`expect`; the result's `out` and `err` are empty. A wait timeout
returns `nil, PTY timeout` and leaves the child alive. `p:kill()` terminates
the entire child job; `wait` can still observe its result. A scope deadline
interrupts the current wait with `SCHED deadline`; it does not close `p`.

<a id="kuu-page-pty-output-and-matching"></a>

### Output and matching

`p:read([timeout])` returns the next raw byte chunk, including VT sequences.
It returns `nil` at EOF, or `nil, PTY timeout` when nothing arrives in time.
The default read timeout is unlimited. Both stdout and stderr use the same
console stream. Raw chunks may split a UTF-8 character or a VT sequence.

`p:text()` returns the plain text consumed so far by `read` and `expect`.
It does not wait for or drain unread output. The filter retains partial
UTF-8 characters and escape sequences across reads, drops CSI and OSC,
applies carriage return, line feed and backspace, preserves tabs, and ignores other control
bytes. Carriage return makes subsequent characters overwrite the current
line; backspace erases its previous character. This is a text filter with
no cursor addressing, screen model, full-screen editor support, or display
width calculation. Resizing may cause a program to redraw and repeat text.

`p:expect({ pattern, ... } [, timeout])` searches that plain text using
**Lua patterns**, returning `text, index`: all unconsumed text through the
match and the one-based pattern index. The earliest match wins; array order
breaks ties. Matching resumes after the previous match. Rewriting consumed
characters on the current line makes the changed region available again.
An empty match advances the cursor by one byte. Captures are not returned.
The timeout defaults to 30 seconds; zero polls already available output.
Timeout leaves the console alive and the unmatched text available for the
next call. EOF before a match is `nil, PTY closed`. Only one `read` or
`expect` may be active per console; a second raises `PTY busy`.

`maxout` is a positive byte size and bounds both buffered raw output and
the accumulated transcript input. Crossing the transcript cap returns
`nil, PTY toobig` on this and later reads/expect calls. Close the console
or use a larger cap when spawning a new one. Read while a chatty program
runs: waiting for exit without draining a full output buffer can leave that
program blocked on output.

<a id="kuu-page-pty-errors"></a>

### Errors

The closed PTY code set is `usage` (an option the command table does not
take, as `proc` reports it), `badvalue` (invalid command/options/dimensions,
duration, or a rejected Lua pattern), `notfound` (executable), `encoding`
(invalid UTF-8 command/environment), `launch` (process creation), `busy`
(concurrent read or pending input conflict), `closed` (closed handle or EOF
before a match), `timeout` (wait expired), `toobig` (output/input bound),
and `oserror` (native operation or allocation failure). Invalid arguments
raise; operational failures return `nil, err`. An enclosing deadline raises
`SCHED deadline` internally and is caught by its `sched.deadline` scope.

---

<a id="kuu-page-powershell"></a>

<a id="kuu-page-powershell-from-powershell"></a>

## From PowerShell

kuu is the tool an agent holds on a Windows machine instead of PowerShell:
to set up, configure, run, test, script, control, and keep in check. This page
maps what an agent reaches for in PowerShell to the kuu call that does it,
with the differences that matter. Where kuu has nothing yet, it says so.
Process and network waits cooperate with the scheduler; file and machine
inspection calls can be synchronous, as their manual pages describe.

<a id="kuu-page-powershell-processes"></a>

### Processes

| PowerShell | kuu | the difference |
|---|---|---|
| `& tool.exe args`, `Start-Process -Wait` | `proc.run { "tool.exe", "arg" }` | the child and its whole tree die when kuu does, or when `timeout` passes; exit codes are results, not exceptions |
| `$LASTEXITCODE`, `$?` | `r.code`, `r.status` | `"exit"`, `"timeout"`, `"killed"`, or `"limit"`; `r.limit` names an exhausted resource bound |
| `Start-Process` plus Windows Job Object resource limits | `proc.run { ..., limits = { memory = "512M", cpu = "30s", processes = 8 } }` | limits apply to the whole tree; CPU is user-mode time, timeout is elapsed time |
| `tool 2>&1 \| Out-String` | `r.out`, `r.err` | bytes, captured separately; beyond `maxout` the rest is dropped and `r.truncated` says so |
| `Start-Process` without `-Wait` | `proc.start { ... }` then `c:wait()` | one child per handle, closed with it |
| `Start-Process -NoNewWindow` for an interactive tool | `proc.run { ..., inherit = true }` | the child gets kuu's own console |
| an interactive tool that reads console prompts | `pty.spawn { "cmd.exe" }`, `p:expect({ ">" }, "5s")`, `p:write("echo hello\r")` | a private pseudoconsole with supervised lifetime; provisional API, see [pty](#kuu-page-pty) |
| `tool \| ForEach-Object { }` | `for line in c:lines() do` | live, with backpressure, no thread |
| `Start-Job`, `Wait-Job -Any` | `sched.spawn`, `proc.wait_any` | tasks are coroutines, not processes |
| `Start-Process -WindowStyle Hidden` for a daemon | `proc.detach { ... }` | the one child that outlives kuu, on purpose |
| `taskkill /T` | `c:kill()` | the child's whole tree, since every child has its own job |
| `Stop-Process -Id` | `proc.kill(pid)` | that one process, by id |
| `Get-Process`, `netstat -o`, `tasklist` | `proc.list`, `proc.find { name = "tool" }`, `proc.tree` | find also accepts one `pid` or `port`; entries carry exe, command line, start, cpu, memory when this user may ask |
| `Start-Process -Verb RunAs` | deferred | elevation needs a broker; not yet |
| `cmd /c "a \| b"` | `proc.run { "cmd.exe", "/c", "a \| b" }` | explicit; cmd re-parses its argument, see [proc](#kuu-page-proc) |

<a id="kuu-page-powershell-files"></a>

### Files

| PowerShell | kuu | the difference |
|---|---|---|
| `Get-Content -Raw`, `-Encoding` | `fs.read(p)`, `fs.read(p, { encoding = "cp1252" })` | bytes by default; a named encoding is decoded strictly, never repaired |
| `Set-Content`, `Out-File` | `fs.write(p, data)` | atomic: a temporary beside, then a rename; never a torn file |
| `Add-Content` | `fs.write(p, data, { append = true })` | |
| `Test-Path` | `fs.exists(p)` | says what it is: `"file"`, `"directory"`, `"link"`, `"other"`, or `false` |
| `Get-Item`, `Get-ItemProperty` | `fs.stat(p)` | identity too: volume and file ids |
| `(Get-Item p).Attributes`, `attrib.exe` | `fs.attributes(p)`, `fs.set_attributes(p, { readonly = false })` | six named flags from 0.12; omitted flags preserved, final links not followed by default; [contract](#kuu-page-fs-file-attributes) |
| `New-Item -ItemType Directory -Force` | `fs.mkdir(p)` | parents made, existing fine |
| `Remove-Item -Recurse -Force` | `fs.remove(p, { recursive = true })` | never follows a junction or symlink into its target |
| `Move-Item`, `Copy-Item` | `fs.rename(a, b, { replace = true })`, `fs.copy(a, b)` | |
| `Get-ChildItem -Recurse -Filter *.c` | `fs.glob("src/**/*.c")` | sorted, case-insensitive, links matched but never entered |
| `Get-ChildItem -Directory` | `fs.list(dir)`, `fs.dirs(root, { depth, prune })` | the walk tells the truth about junctions and depth |
| `Join-Path`, `Split-Path -Parent`, `Split-Path -Leaf` | `fs.join`, `fs.dirname`, `fs.basename` | `fs.ext`, `fs.stem`, `fs.relative` too |
| `Resolve-Path` | `fs.absolute(p)`, `fs.canon(p)` | `canon` follows links and gives identity |
| `New-TemporaryFile` | `fs.tempfile { dir, prefix, suffix }`, `fs.tempdir { }` | created exclusively |
| `Get-PSDrive`, `Get-Volume` | `fs.space(p)`, `sys.info().drives` | |
| `Get-FileHash` | `hash.file("sha256", p)` | |
| `Register-ObjectEvent` on a FileSystemWatcher | `fs.watch(dir)` then `w:read()` | on the loop, batched as Windows delivers |
| `Set-Location`, `Get-Location` | `fs.chdir(p)`, `fs.cwd()` | process-wide, as in PowerShell |
| `Get-Acl`, `Set-Acl` | deferred | icacls through `proc.run` until a real need |

<a id="kuu-page-powershell-network-and-downloads"></a>

### Network and downloads

| PowerShell | kuu | the difference |
|---|---|---|
| `Invoke-WebRequest -OutFile` | `http.get(url, { to = p })` | streamed through a temporary; the previous file survives a failure |
| `Invoke-WebRequest` then `Get-FileHash` | `http.get(url, { to = p, sha256 = "..." })` | hashed as it arrives; a mismatch leaves no file |
| `Invoke-RestMethod` | `http.get(url)` then `json.decode(r.body)` | status codes are results; no insecure switch exists |
| `Invoke-RestMethod -Method Post -Body` | `http.post(url, body, { type = "application/json" })` | |
| `Expand-Archive`, `tar -xf` | `archive.unpack(file, dir, { strip = 1 })` | zip and the tar family, through the tar.exe Windows ships |
| `Compress-Archive` | `archive.pack(file, dir)` | |
| `Test-NetConnection -Port`, `Resolve-DnsName`, `Get-NetTCPConnection`, `Get-NetIPAddress`, `ipconfig` | `net.probe`, `net.resolve`, `net.listeners`, `net.addresses` | probe reports the address that answered and the elapsed time; connect and DNS waits yield |

<a id="kuu-page-powershell-data-and-text"></a>

### Data and text

| PowerShell | kuu | the difference |
|---|---|---|
| `ConvertFrom-Json`, `ConvertTo-Json` | `json.decode`, `json.encode` | strict, exact integers, duplicate keys refused |
| `[Convert]::ToBase64String`, `FromBase64String` | `text.tobase64`, `text.frombase64` | |
| `[BitConverter]::ToString`, `-replace '-'` | `text.tohex`, `text.fromhex` | |
| `[Text.Encoding]::GetEncoding(1252).GetString` | `text.decode(bytes, "cp1252")` | strict both ways |
| `New-Guid` | `hash.uuid()` | |
| `.ToUpper()`, `.ToLower()` | `text.upper`, `text.lower` | Unicode, by the rules file names fold by; Lua's own are ASCII only |
| `New-Object Threading.Mutex`, `Wait-Handle` | `sync.lock(name, timeout)`, `sync.try(name)` | a named mutex across processes in one Windows session; a dead holder hands it over as `abandoned` |
| `-match`, `$Matches` | `re.match`, `re.exec` | `exec` gives positions, numbered and named groups in one table |
| `-replace` | `re.gsub(s, pattern, "$1")` | `$1`, `${name}`, `$0`, `$$`; a function or table too |
| `-split` | `re.split` | |
| `Select-String` | `re.find` in a loop over `c:lines()` or `fs.read` | |
| `[regex]::Escape` | `re.escape` | |
| `Get-Date`, `Get-Date -Format`, `[DateTime]::Parse`, `ToUniversalTime` | `time.now`, `time.format`, `time.parse`, `time.iso` | instants are seconds since the epoch; zones are `utc`, `local`, or an offset |
| `New-TimeSpan`, `[TimeSpan]::Parse` | `time.duration("1h30m")`, `time.human(seconds)` | |
| `Import-Csv`, `Export-Csv`, `ConvertFrom-Csv` | `csv.decode(text, { header = true })`, `csv.encode` | every field a string; separators, CRLF, and the BOM handled |
| an INI parser or a text replacement script | `ini.decode(text)`, `ini.set(text, section, key, value)` | edits preserve unrelated lines, comments, and line endings |
| `Select-Xml`, `[xml]` | deferred | |
| `Write-Host`, `Write-Verbose` | `print`, `io.stderr:write`, `log` | log writes never raise; invalid configuration does |

<a id="kuu-page-powershell-the-machine"></a>

### The machine

| PowerShell | kuu | the difference |
|---|---|---|
| `[Environment]::OSVersion`, `Get-ComputerInfo` | `sys.info()` | the truthful build, the display name, elevation, cpus, memory, drives, uptime |
| `[Security.Principal.WindowsPrincipal]…IsInRole` | `sys.info().elevated` | |
| `$env:NAME`, `[Environment]::SetEnvironmentVariable(..., 'User')`, `setx` | `env.get`, `env.set`; `env.persist`, `env.forget` with the change broadcast | live and persisted are two different things; see [env](#kuu-page-env) |
| `Get-ItemProperty HKLM:\...`, `Set-ItemProperty`, `New-Item HKCU:\...`, `reg.exe` | `reg.get`, `reg.set`, `reg.values`, `reg.keys`, `reg.remove` | typed: dword, qword, string, expandstring, multistring, binary |
| `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service` | `svc.list`, `svc.status`, `svc.start`, `svc.stop`, `svc.restart` | local services; transitions wait for the requested state; no service creation API |
| `Get-WinEvent`, `Get-WinEvent -ListLog *` | `evt.read`, `evt.logs` | bounded local snapshots with typed fields and filters; no log mutation |
| `Get-AuthenticodeSignature` | `sys.signature(path)` | embedded signatures only, no catalog lookup; trust failures are results, revocation checking is opt-in |
| `Register-ScheduledTask` | `schtasks.exe` through `proc.run` | deferred as a module |
| `New-Object -ComObject WScript.Shell` for shortcuts | no | desktop plumbing, not an agent's tool |
| `Enable-WindowsOptionalFeature`, `New-NetFirewallRule`, `Set-MpPreference` | no | security settings stay with the person |

<a id="kuu-page-powershell-the-script-itself"></a>

### The script itself

| PowerShell | kuu | the difference |
|---|---|---|
| `param()` | `cli.parse(rt.args, spec)` | declared once; `--help` is a value, not an exit |
| `$PSScriptRoot` | `rt.root()` | |
| `Start-Sleep` | `sched.sleep("2s")` | other tasks run meanwhile |
| a shared timeout around several waiting operations | `sched.deadline("30s", fn)` | returns `nil, SCHED deadline` when a wait reaches the bound; does not preempt computing Lua or independently kill children |
| a `.ps1` per job, `Invoke-Build` | `manifest.lua`, `kuu run`, `kuu list` | dependencies once, in order; `--dry-run` shows the plan |
| a wrapper adding `-Timeout` to every command | `task.defaults { timeout = "10m" }` | a default for `task.exec`; each call can override it, including with zero; `task.defaults {}` clears the default |
| `Export-Clixml` for state between runs | `mem.set`, `mem.get`, `mem.update` | a JSON notebook per project, 1 MiB at most; update holds the lock through read, callback, and write |
| `Set-StrictMode -Version Latest` | `global none` at the top of the file | the compiler refuses an undeclared global |
| `try { } catch { }` | `nil, err` for expected failures, `pcall` for mistakes | see [err](#kuu-page-err) |
| `-WhatIf` | `kuu run --dry-run` | loads task declarations and shows dependency order; task bodies do not run |
| `Test-ModuleManifest`, `PSScriptAnalyzer` | `kuu check` | syntax, global declarations, `require` resolution, and misspelt known palette exports; does not check types or argument counts |

---

<a id="kuu-page-cookbook"></a>

<a id="kuu-page-cookbook-cookbook"></a>

## Cookbook

Each block is a complete program. Save it under the indicated filename and
run it with your repository's `kuu.exe`. Inputs are positional arguments;
paths belong to the current directory unless absolute. The first ten
programs require kuu 0.7 or later, and the four after them, which are
shaped by the front door — a manifest, a wrapper module, a reader of the
run stream, a reader of the ledger — require 0.10. [`pty`](#kuu-page-pty) is
provisional.

<a id="kuu-page-cookbook-1-wait-for-a-port-to-open"></a>

### 1. Wait for a port to open

`kuu wait-port.lua HOST PORT [TIMEOUT]` waits up to 30 seconds by default.
The outer deadline includes DNS, connection attempts, and the pauses between
them. A successful probe closes its connection immediately.

```lua
global none
global <const> require, assert, tonumber, print
local rt, net, sched = require "rt", require "net", require "sched"
local host = assert(rt.args[1], "usage: wait-port.lua HOST PORT [TIMEOUT]")
local port = assert(tonumber(rt.args[2]), "PORT must be a number")
local up, e = sched.deadline(rt.args[3] or "30s", function()
  while true do
    local connected = net.probe(host, port, "1s")
    if connected then return connected end
    sched.sleep("100ms")
  end
end)
assert(up, e)
print("ready", up.address, port)
```

<a id="kuu-page-cookbook-2-install-a-tool-by-hash"></a>

### 2. Install a tool by hash

`kuu install-tool.lua URL SHA256 ARCHIVE DEST [STRIP]` downloads a pinned
archive into a project cache and extracts it into a project tool directory.
For example, use `build/tool.zip` and `.tools/tool` for the last two paths.
Get the URL and SHA-256 from the tool's release, then record both in the
project. `STRIP` defaults to zero; use one for a versioned top-level folder.
Extraction overwrites existing destination files.

```lua
global none
global <const> require, assert, tonumber, print
local rt, fs = require "rt", require "fs"
local http, archive = require "http", require "archive"
local url = assert(rt.args[1], "usage: install-tool.lua URL SHA256 ARCHIVE DEST [STRIP]")
local sha256 = assert(rt.args[2], "SHA256 is required")
local cached = assert(rt.args[3], "ARCHIVE is required")
local dest = assert(rt.args[4], "DEST is required")
local strip = assert(tonumber(rt.args[5] or "0"), "STRIP must be a number")
assert(fs.mkdir(fs.dirname(cached)))
local response = assert(http.get(url, {
  to = cached, sha256 = sha256, timeout = "10m", maxbody = "1G",
}))
assert(response.status == 200, "download returned HTTP " .. response.status)
assert(archive.unpack(cached, dest, { strip = strip, timeout = "10m" }))
print("installed", dest)
```

<a id="kuu-page-cookbook-3-tail-a-log-while-a-build-runs"></a>

### 3. Tail a log while a build runs

`kuu tail-build.lua LOG EXECUTABLE [ARG ...]` starts the build and copies new
bytes from its log to stdout until its process tree finishes. The build may
create the log after starting or truncate it; this program handles both.
Use a fresh log for each build. The log and inherited build output should be
UTF-8 if they are to share the terminal.

```lua
global none
global <const> require, assert, io, tostring
local rt, fs, proc, sched = require "rt", require "fs", require "proc", require "sched"
local path = assert(rt.args[1], "usage: tail-build.lua LOG EXECUTABLE [ARG ...]")
local spec = { assert(rt.args[2], "EXECUTABLE is required"), inherit = true, timeout = "10m" }
for i = 3, #rt.args do spec[#spec + 1] = rt.args[i] end
local offset = 0
local function tail()
  if not fs.exists(path) then return end
  local file <close> = assert(io.open(path, "rb"))
  local size = assert(file:seek("end"))
  if size < offset then offset = 0 end
  assert(file:seek("set", offset))
  while offset < size do
    local bytes = file:read(65536)
    if not bytes then break end
    io.write(bytes)
    offset = offset + #bytes
  end
  io.flush()
end
local child <close> = assert(proc.start(spec))
while child:running() do tail(); sched.sleep("100ms") end
tail()
local result = assert(child:wait())
assert(result.status == "exit" and result.code == 0,
  "build ended: " .. result.status .. " / " .. tostring(result.code))
```

<a id="kuu-page-cookbook-4-find-the-process-on-a-port-and-stop-it"></a>

### 4. Find the process on a port and stop it

`kuu stop-port.lua PORT EXPECTED_PID` stops one process. Supply the PID you
intend to stop; the program refuses an empty or ambiguous owner list and an
unexpected owner. The lookup is a snapshot and does not reserve the PID.
For a child your program starts itself, keep its handle and use `child:kill()`
to terminate its whole tree instead.

```lua
global none
global <const> require, assert, tonumber, print
local rt, proc, sched = require "rt", require "proc", require "sched"
local port = assert(tonumber(rt.args[1]), "usage: stop-port.lua PORT EXPECTED_PID")
local expected = assert(tonumber(rt.args[2]), "EXPECTED_PID must be a number")
local owners = assert(proc.find { port = port })
assert(#owners == 1 and owners[1].pid == expected, "port owner changed or is ambiguous")
assert(proc.kill(expected))
local stopped, e = sched.deadline("5s", function()
  while proc.alive(expected) do sched.sleep("50ms") end
  return true
end)
assert(stopped, e)
print("stopped", expected)
```

<a id="kuu-page-cookbook-5-verify-an-installers-signature-before-running-it"></a>

### 5. Verify an installer's signature before running it

`kuu signed-installer.lua FILE EXPECTED_THUMBPRINT [ARG ...]` requires both
a valid embedded signature and the expected signing certificate. Record the
40-character certificate thumbprint independently of the download. Keep
the installer in a directory controlled by the project: verification does
not reserve the path between checking and launching. Catalog-only signatures
report unsigned. Successful installer exit codes other than zero must be
handled according to that installer's documented contract.

```lua
global none
global <const> require, assert, tostring, print
local rt, sys, proc = require "rt", require "sys", require "proc"
local path = assert(rt.args[1], "usage: signed-installer.lua FILE EXPECTED_THUMBPRINT [ARG ...]")
local expected = assert(rt.args[2], "EXPECTED_THUMBPRINT is required"):upper()
assert(#expected == 40 and expected:match("^%x+$"), "expected a 40-character SHA-1 thumbprint")
local signature = assert(sys.signature(path))
assert(signature.signed, "installer has no embedded signature")
assert(signature.valid, "installer signature is invalid: " .. tostring(signature.reason))
assert(signature.thumbprint == expected, "installer has an unexpected signing certificate")
local spec = { path, inherit = true, timeout = "10m" }
for i = 3, #rt.args do spec[#spec + 1] = rt.args[i] end
local result = assert(proc.run(spec))
assert(result.status == "exit" and result.code == 0,
  "installer ended: " .. result.status .. " / " .. tostring(result.code))
print("installed", signature.signer)
```

<a id="kuu-page-cookbook-6-check-a-service-and-start-it"></a>

### 6. Check a service and start it

`kuu start-service.lua NAME` uses the service's internal name, not its display
name. Starting a service may need elevation. A timeout stops waiting; it does
not undo a start request already accepted by Windows.

```lua
global none
global <const> require, assert, print
local rt, svc = require "rt", require "svc"
local name = assert(rt.args[1], "usage: start-service.lua NAME")
local before = assert(svc.status(name))
if before.state ~= "running" then assert(svc.start(name, "30s")) end
local after = assert(svc.status(name))
assert(after.state == "running", "service did not stay running")
print(after.name, after.state, after.pid)
```

<a id="kuu-page-cookbook-7-read-the-last-errors-from-the-event-log"></a>

### 7. Read the last errors from the event log

`kuu event-errors.lua [CHANNEL]` prints up to 20 errors from the last day,
newest first. `System` is the default channel. Each record is one JSON line,
so embedded newlines in event messages do not split records.

```lua
global none
global <const> require, assert, ipairs, print
local rt, evt, time, json = require "rt", require "evt", require "time", require "json"
local events = assert(evt.read(rt.args[1] or "System", {
  since = time.now() - 86400, level = "error", limit = 20,
}))
for _, event in ipairs(events) do print(json.encode(event)) end
```

<a id="kuu-page-cookbook-8-run-a-step-under-a-deadline-with-limits"></a>

### 8. Run a step under a deadline with limits

`kuu bounded-step.lua EXECUTABLE [ARG ...]` gives a step 30 seconds of elapsed
time, 512 MiB of committed memory, 10 seconds of user CPU time, and at most
eight processes including the initial child. The `<close>` handle kills the
tree if the deadline unwinds the block. The deadline bounds waits; it cannot
interrupt Lua code that computes without waiting.

```lua
global none
global <const> require, assert, tostring
local rt, proc, sched = require "rt", require "proc", require "sched"
local spec = { assert(rt.args[1], "usage: bounded-step.lua EXECUTABLE [ARG ...]"),
  inherit = true, limits = { memory = "512M", cpu = "10s", processes = 8 } }
for i = 2, #rt.args do spec[#spec + 1] = rt.args[i] end
local ok, e = sched.deadline("30s", function()
  local child <close> = assert(proc.start(spec))
  local result = assert(child:wait())
  assert(result.status == "exit" and result.code == 0,
    "step ended: " .. result.status .. " / " .. tostring(result.limit or result.code))
  return true
end)
assert(ok, e)
```

<a id="kuu-page-cookbook-9-edit-an-ini-value-in-place"></a>

### 9. Edit an INI value in place

`kuu edit-ini.lua FILE SECTION KEY VALUE` preserves comments, spacing, line
endings, and a UTF-8 BOM. It replaces the effective last occurrence of the
key. The write is atomic; coordinate separately if another process also edits
this file. Use an empty SECTION argument for a key before any section header.

```lua
global none
global <const> require, assert, print
local rt, fs, ini = require "rt", require "fs", require "ini"
local path = assert(rt.args[1], "usage: edit-ini.lua FILE SECTION KEY VALUE")
local section = assert(rt.args[2], "SECTION is required")
local key = assert(rt.args[3], "KEY is required")
local value = assert(rt.args[4], "VALUE is required")
local before = assert(fs.read(path))
assert(fs.write(path, ini.set(before, section, key, value)))
print("updated", path, section, key)
```

<a id="kuu-page-cookbook-10-drive-a-prompt-through-pty"></a>

### 10. Drive a prompt through pty

`kuu prompt.lua` drives `cmd.exe`'s console input, sets a value through
`set /p`, and checks the answer. `expect` consumes through the matched text
and uses Lua patterns. `text()` is the accumulated plain-text view, not a
terminal screen. See the provisional [`pty`](#kuu-page-pty) contract before driving
a different interactive program.

```lua
global none
global <const> require, assert, os, print
local pty = require "pty"
local shell = os.getenv("ComSpec") or "C:/Windows/System32/cmd.exe"
local child <close> = assert(pty.spawn { shell, "/d", "/q", cols = 120, rows = 30 })
assert(child:expect({ ">" }, "5s"))
assert(child:write("set /p name=Enter:\r"))
assert(child:expect({ "Enter:" }, "5s"))
assert(child:write("kuu\r"))
assert(child:write("echo received:%name%\r"))
assert(child:expect({ "received:kuu" }, "5s"))
print(child:text())
assert(child:write("exit\r"))
local result = assert(child:wait("5s"))
assert(result.status == "exit" and result.code == 0, "prompt child failed")
```
<a id="kuu-page-cookbook-11-a-manifest-a-task-with-arguments-a-dependency-and-a-declared-tool"></a>

### 11. A manifest: a task with arguments, a dependency, and a declared tool

`manifest.lua` at the project root. `kuu run report --since 2026-09-01`
runs `gen` first, then the declared tool through the door: the exe resolved
against the root, the declared timeout, a record in the ledger, and every
argument held to the declaration by `kuu check` before anything runs.

```lua
global none
global <const> require, tostring
local task, fs = require "task", require "fs"

task.defaults { timeout = "10m" }

task.tool "report" {
  exe = "tools/report.exe",
  args = { ["--out"] = "path", ["--since"] = "string", ["--verbose"] = "flag" },
  output = "ndjson",
  timeout = "5m",
}

task "gen" {
  desc = "write build/inputs.json",
  run = function()
    fs.mkdir("build")
    return fs.write("build/inputs.json", "[]\n")
  end,
}

task "report" {
  desc = "the report, from build/inputs.json",
  deps = { "gen" },
  args = {
    { "--since", type = "string", default = "2026-01-01", help = "the first day to include" },
    { "--verbose", type = "flag", help = "say what is skipped" },
  },
  run = function(opts)
    local call = { tool = "report", "--out", "build/report.ndjson", "--since", tostring(opts.since) }
    if opts.verbose then call[#call + 1] = "--verbose" end
    return task.exec(call)
  end,
}

task.default "report"
```

<a id="kuu-page-cookbook-12-a-module-that-wraps-a-tool-and-decodes-its-ndjson"></a>

### 12. A module that wraps a tool and decodes its NDJSON

`tools/report.lua` in the project, required as `require "tools.report"`:
the tool is run for its output through `task.command`, so the declared exe
and timeout apply, and each line of standard output is one record. A line
that does not decode is the tool's fault, and says which line. Truncated
capture is refused before parsing, so a valid prefix is never a complete result. This is the
program's own `proc.run`, not a crossing; a task that wants the record
calls `task.exec` instead.

```lua
global none
global <const> require, ipairs
local task, proc, json, err = require "task", require "proc", require "json", require "err"
local M = {}

-- M.rows(since) -> records | nil, err
function M.rows(since)
  local r, e = proc.run(task.command { tool = "report", "--out", "-", "--since", since })
  if not r then return nil, e end
  if r.status ~= "exit" then return nil, err.new("REPORT", "failed", "report: " .. r.status) end
  if r.code ~= 0 then return nil, err.new("REPORT", "exit", "report exited with code " .. r.code, { exit = r.code }) end
  if r.truncated then return nil, err.new("REPORT", "toobig", "report output exceeded the capture limit") end
  local rows, number = {}, 0
  for line in r.out:gmatch("[^\r\n]+") do
    number = number + 1
    local record, bad = json.decode(line)
    if record == nil then return nil, err.new("REPORT", "badvalue", "line " .. number .. " is not JSON: " .. bad.message) end
    rows[#rows + 1] = record
  end
  return rows
end

return M
```

<a id="kuu-page-cookbook-13-read-the-kuu-run---json-stream-as-it-happens"></a>

### 13. Read the `kuu run --json` stream as it happens

`kuu run --json test | kuu watch-run.lua` reads one event per line from
standard input, prints each task as it ends, and exits with the run's own
code when the envelope arrives — the error's `exit` when it has one, else 2
for a usage or a `TASK` failure and 1 for the rest, the rule `kuu run` itself
follows; a child's events name the pid and the program. The envelope is the
last line, so a reader that only wants the outcome keeps the last line it
saw.

```lua
global none
global <const> require, io, os, print, string
local json = require "json"
local last
for line in io.stdin:lines() do
  local record = json.decode(line)
  if record == nil then
    io.stderr:write("not an event: ", line, "\n")
  elseif record.event == "run" then
    print("run " .. record.task .. " in " .. record.root)
  elseif record.event == "task" and record.state == "finished" then
    print(string.format("%s %s %.1fs%s", record.name, record.ok and "ok" or "failed", record.seconds,
      record.error and ("  " .. record.error.domain .. " " .. record.error.code .. ": " .. record.error.message) or ""))
  elseif record.event == "child" and record.state == "finished" then
    print(string.format("  %s pid %d %s%s", record.argv[1], record.pid, record.status,
      record.code and (" " .. record.code) or ""))
  elseif record.ok ~= nil then
    last = record
  end
end
if last == nil then io.stderr:write("no envelope\n") os.exit(1) end
if not last.ok then
  local e = last.error
  io.stderr:write(e.domain, " ", e.code, ": ", e.message, "\n")
  local usage = (e.domain == "CLI" and e.code == "usage") or e.domain == "TASK"
  os.exit(e.exit or (usage and 2 or 1))
end
```

<a id="kuu-page-cookbook-14-what-failed-last-from-the-ledger"></a>

### 14. What failed last, from the ledger

`kuu last-failure.lua [ROOT]` reads `.kuu/ledger/*.ndjson` under the
project root, one JSON record per line, and prints the last task whose
status is `failed` with its error — a child that timed out is recorded with
that status and no error, and the run's own record ends on the task's error,
so the task is the one to name — or says that nothing has failed. The files
are the ledger's own format; nothing but `fs.read` and `json.decode` is
needed to read them.

```lua
global none
global <const> require, ipairs, print, os, io, table
local fs, json, rt = require "fs", require "json", require "rt"
local root = rt.args[1] or "."
local dir = fs.join(root, ".kuu", "ledger")
local listing = fs.list(dir)
if not listing then io.stderr:write("no ledger under ", fs.absolute(root), "; kuu run writes one\n") os.exit(1) end
local names = {}
for _, entry in ipairs(listing.entries) do
  if entry.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = entry.name end
end
table.sort(names)
local failed
for _, name in ipairs(names) do
  for line in (fs.read(fs.join(dir, name)) or ""):gmatch("[^\n]+") do
    local record = json.decode(line)
    if record and record.kind == "task" and record.status == "failed" then failed = record end
  end
end
if failed == nil then print("nothing has failed") os.exit(0) end
print(failed.kind, failed.name, failed.error and (failed.error.domain .. " " .. failed.error.code .. ": " .. failed.error.message) or "")
```

---

<a id="kuu-page-cleanup"></a>

<a id="kuu-page-cleanup-bounded-publication-and-cleanup"></a>

## Bounded publication and cleanup

Project Lua can retry a short-lived Windows denial while publishing a completed
directory or removing owned staging. These recipes require kuu 0.12 for
`fs.attributes` and readonly-directory cleanup. Use `rt.version_at_least(0, 12)`
as the minimum-version guard, alongside the project's approved runtime pins.

`FS access` includes sharing violations, ACL denial and write protection. A
retry cannot distinguish them immediately. Retry only that classified error,
under an explicit time budget; never parse localized error messages. Other
errors return immediately. The budget limits new attempts and scheduled waits,
not the time spent inside one synchronous filesystem call. `fs.rename` already
has a short native retry; its elapsed time counts toward this outer budget.

<a id="kuu-page-cleanup-a-project-module"></a>

### A project module

Save this complete module as `owned_ops.lua` in the project. Its callers must
own the exact staging/removal path and exclude concurrent writers. Pass the
same path on every attempt. Do not use a repository root, a parent directory,
or a user profile as staging. Final-component links are removed themselves;
linked ancestors and concurrent path replacement are not containment barriers.

```lua
global none
global <const> require, assert, type, math, pcall
local fs, err, sched = require "fs", require "err", require "sched"
local M = {}

function M.retry_access(operation, seconds)
  assert(type(seconds) == "number" and seconds >= 0 and seconds < math.huge,
    "retry budget must be finite nonnegative seconds")
  local until_time = sched.clock() + seconds
  local last
  repeat
    local ok, why = operation()
    if ok then return ok end
    if not err.is(why, "FS", "access") then return nil, why end
    last = why
    local remaining = until_time - sched.clock()
    if remaining <= 0 then break end
    sched.sleep(math.min(0.025, remaining))
  until sched.clock() >= until_time
  return nil, last
end

function M.remove_owned(path, seconds)
  return M.retry_access(function()
    local ok, why = fs.remove(path, { recursive = true })
    if ok then return true end
    if err.is(why, "FS", "notfound") then
      -- A missing descendant alone does not prove the root was removed.
      local flags, absent = fs.attributes(path)
      if not flags and err.is(absent, "FS", "notfound") then return true end
    end
    return nil, why
  end, seconds)
end

function M.publish(staging, destination, validate, seconds)
  -- validate returns true or nil,error; raised validation errors survive too.
  local called, valid, primary = pcall(validate, staging)
  if not called then primary, valid = valid, nil end
  if valid then
    valid, primary = M.retry_access(function()
      return fs.rename(staging, destination) -- no replace: destination must be absent
    end, seconds)
  end
  if valid then return true end
  primary = primary or err.new("PROJECT", "invalid", "staging validation failed")
  local removed, cleanup = M.remove_owned(staging, seconds)
  if removed then cleanup = nil end
  return nil, primary, cleanup
end

return M
```

One removal attempt covers the whole tree, so a two-second budget is not
multiplied by the number of files. Removal is nontransactional: earlier entries
may already be gone, and a readonly bit can remain cleared when deletion later
fails. Retrying tolerates that partial progress. There is no blind restoration
of attributes or files after failure.

Publication uses a staging directory beside the destination, on the same
volume, and never replaces an existing destination. Validate before renaming;
readers should use only the published path. A successful rename moves the
completed tree into place, but is not a power-loss durability guarantee.
On failure, publication and cleanup each have their own explicit budget. A
two-second argument can therefore permit up to four seconds of retry waiting,
plus filesystem call time and validation. Raised programming errors from a
filesystem call still propagate; provide valid paths and arguments.

<a id="kuu-page-cleanup-extract-validate-publish"></a>

### Extract, validate, publish

Save as `install-cached.lua`; run `kuu install-cached.lua ARCHIVE DEST SHA256`.
This uses an already cached archive whose expected SHA-256 was pinned by the
project. It creates a new owned staging directory and checks a known package
marker before publication; change `bin/tool.exe` to the package's actual
required file. Hash verification and extraction both happen inside the
validation callback, so either failure still attempts staging cleanup.

```lua
global none
global <const> require, assert, io, tostring
local rt, fs, hash = require "rt", require "fs", require "hash"
local archive, err, ops = require "archive", require "err", require "owned_ops"
local cached = assert(rt.args[1], "ARCHIVE is required")
local destination = assert(rt.args[2], "DEST is required")
local expected = assert(rt.args[3], "SHA256 is required")
assert(fs.mkdir(fs.dirname(destination)))
local staging = assert(fs.tempdir { dir = fs.dirname(destination), prefix = ".stage-" })
local ok, primary, cleanup = ops.publish(staging, destination, function(path)
  local digest, why = hash.file("sha256", cached)
  if not digest then return nil, why end
  if digest ~= expected then return nil, err.new("PROJECT", "hash", "archive hash mismatch") end
  local unpacked, unpack_error = archive.unpack(cached, path, { timeout = "2m" })
  if not unpacked then return nil, unpack_error end
  local info, missing = fs.stat(path .. "/bin/tool.exe", { follow = false })
  if not info then return nil, missing end
  if info.kind ~= "file" then return nil, err.new("PROJECT", "invalid", "bin/tool.exe must be a file") end
  return true
end, 2)
if cleanup then io.stderr:write("staging cleanup also failed: ", tostring(cleanup), "\n") end
assert(ok, primary)
```

The secondary cleanup error is printed before the primary error is raised;
neither failure is replaced by a success message. A task can instead report
the cleanup error and `return nil, primary`, preserving its classified task
failure. Validate the real package's required contents; one marker is only
this example's acceptance criterion. For reconstructing installations and
recovering interrupted publication, keep the pinned archive and explicit
ownership of leftover staging directories. The [reconstruction guide](#kuu-page-reconstruction)
adds receipt and payload verification, staging attribute normalization, independent
backup verification and reconciliation after an uncertain upload.

---

<a id="kuu-page-process-recipes"></a>

<a id="kuu-page-process-recipes-process-descriptions-outcomes-and-diagnostics"></a>

## Process descriptions, outcomes and diagnostics

A process specification mixes numbered arguments with options such as `cwd`
and `env`. It is a Lua call table, not a JSON object. To describe it, copy its
arguments into an explicit `json.array` and put them under `argv`. Keep the
working directory and environment overlay in separate fields. An empty overlay
is `{}`; an empty argument array is `[]`. JSON's strict mapping stays useful.

Use `task.exec` when output can stream through. A program can define nonzero
success codes; accepting a classified `TASK exit` preserves its individual
child record. Use `task.command` with `proc.run` when the task needs captured
bytes. This retains tool resolution, supervision and deadlines, but the capture
call has **no individual child record** in the ledger or `kuu run --json`
events. The enclosing task and run are still recorded. It is a supported
project implementation choice; call the project task through `kuu run`.

<a id="kuu-page-process-recipes-a-project-module"></a>

### A project module

Save as `process_ops.lua`. The extra success-code set is specific to the
program: `{ [3] = true }` below belongs to the sample probe, not every tool.
Zero remains success. A timeout, kill or limit is always failure, even if its
numeric code happens to be in the set. Invalid call arguments still raise;
launch failures return a classified error with the original cause attached.

```lua
global none
global <const> require, ipairs, pairs, tostring
local task, proc, json = require "task", require "proc", require "json"
local fs, err = require "fs", require "err"
local M = {}

local function description(command)
  local argv, env = json.array {}, {}
  for i, argument in ipairs(command) do argv[i] = argument end
  for name, value in pairs(command.env or {}) do env[name] = value end
  return { argv = argv, cwd = fs.absolute(command.cwd or fs.cwd()), env = env }
end

function M.describe(spec)
  return description(task.command(spec))
end

function M.exec_success(spec, extra_success)
  local ok, why = task.exec(spec)
  if ok then return true end
  if err.is(why, "TASK", "exit") and extra_success and extra_success[why.exit] == true then
    return true
  end
  return nil, why
end

local function failure(command, code, message, result, cause)
  local context = description(command)
  -- The full environment overlay is useful in a description, not in an error.
  context.env = nil
  message = message .. "\ncommand: " .. json.encode(context)
  if result then
    if result.err ~= "" then message = message .. "\nstderr:\n" .. result.err end
    if result.truncated then message = message .. "\n[captured output truncated]" end
  end
  local details = { result = result, cause = cause }
  if code == "exit" then details.exit = result.code end
  return nil, err.new("PROJECT", code, message, details)
end

function M.capture(spec, extra_success)
  local command = task.command(spec)
  local result, why = proc.run(command)
  if not result then
    return failure(command, "launch", "could not start child: " .. tostring(why), nil, why)
  end
  if result.status ~= "exit" then
    local reason = result.status .. (result.limit and (" (" .. result.limit .. ")") or "")
    return failure(command, result.status, "child ended: " .. reason, result)
  end
  if result.code ~= 0 and not (extra_success and extra_success[result.code] == true) then
    return failure(command, "exit", "child exited with code " .. result.code, result)
  end
  if result.truncated then
    return failure(command, "truncated", "complete captured output is required", result)
  end
  return result
end

return M
```

`describe` resolves a declared executable and records an absolute cwd. A bare
executable name remains a PATH lookup; this is a description, not a PATH
resolver or a complete replay format. `env` contains only the explicit overlay:
strings set variables and `false` removes them; inherited variables are not
expanded. `timeout`, `limits`, `stdin` and capture settings are intentionally
outside this `{argv, cwd, env}` description. Persist only arguments and
environment values that the project intends to expose in diagnostics.

The module copies the specification and its description rather than changing
the caller's table. `capture` expects ordinary capture options: do not set
`inherit = true`, because inherited output cannot be collected. Use finite
`timeout` and `maxout` values appropriate to the command. `truncated` covers
either stream, so even accepted exits are rejected when complete output was
not retained. The failure's `result` still holds the captured prefixes, status,
code, elapsed time and actual stderr; `cause` retains a launch error. These
extra fields are for Lua callers, not automatic JSON/ledger error fields.

<a id="kuu-page-process-recipes-a-runnable-example"></a>

### A runnable example

Save this small program as `probe.lua` beside the module. It supplies three
ordinary exit outcomes, a slow operation and oversized output without needing
an installed external application.

```lua
global none
global <const> require, io, os, string
local rt, sched = require "rt", require "sched"
local mode = rt.args[1] or "same"
if mode == "same" then
  io.write("unchanged\n")
elseif mode == "changed" then
  io.write("updated\n")
  os.exit(3)
elseif mode == "failed" then
  io.write("partial output\n")
  io.stderr:write("probe could not finish its work\n")
  os.exit(9)
elseif mode == "slow" then
  io.stderr:write("probe began waiting\n")
  io.stderr:flush()
  sched.sleep("10s")
elseif mode == "loud" then
  io.write(string.rep("x", 8192))
else
  io.stderr:write("unknown probe mode\n")
  os.exit(2)
end
```

Save this manifest as `manifest.lua`. `stream changed` demonstrates accepting
code 3 after `task.exec` has recorded the child's actual exit. `capture failed`
reports code 9, its real stderr, argv and cwd. `capture slow` reports timeout;
`capture loud` refuses a truncated success. Place the project's pinned `kuu.exe`
beside the manifest; the sample declares that existing executable as its tool.
Loading the manifest performs no provisioning work.

```lua
global none
global <const> require, io
local task, rt, fs = require "task", require "rt", require "fs"
local ops = require "process_ops"
task.tool "probe" { exe = "kuu.exe", timeout = "5s", output = "lines" }
local arguments = { { "mode", type = "string", default = "changed" } }
local function command(mode)
  return { tool = "probe", fs.join(rt.root(), "probe.lua"), mode,
    cwd = rt.root(), timeout = "500ms", maxout = "1K" }
end
task "stream" {
  desc = "Run the probe and accept its documented changed exit",
  args = arguments,
  run = function(opts) return ops.exec_success(command(opts.mode), { [3] = true }) end,
}
task "capture" {
  desc = "Capture the probe with status and truncation checks",
  args = arguments,
  run = function(opts)
    local result, why = ops.capture(command(opts.mode), { [3] = true })
    if not result then return nil, why end
    io.write(result.out)
    return true
  end,
}
```

Run `kuu run stream changed` or `kuu run capture changed`. For machine output,
`kuu run --json stream changed` keeps the child's code 3 in its child events
and history while the enclosing task succeeds. `kuu run --json capture changed`
has task/run records without a child record. Under `--json`, the capture task's
own `io.write` is redirected to standard error; it is not an individual child
event.

Finally save `describe.lua` and run `kuu describe.lua` to print a JSON process
description without executing the probe. The module performs no provisioning.

```lua
global none
global <const> require, io
local rt, fs, json = require "rt", require "fs", require "json"
require "manifest"
local ops = require "process_ops"
io.write(json.encode(ops.describe {
  tool = "probe", fs.join(rt.root(), "probe.lua"), "changed",
  cwd = rt.root(), env = { PROBE_MODE = "local", PROBE_UNUSED = false },
}), "\n")
```

<a id="kuu-page-process-recipes-reading-failures"></a>

### Reading failures

For streamed operations, branch on `err.is(why, "TASK", "exit")` and
`why.exit` only for ordinary nonzero exits. Other results stay failures:
`TASK failed` carries `why.status` and, for a job limit, `why.limit`; a launch
failure is a `PROC` error. Never accept one by parsing its message or treating
every nonzero code as equivalent.

For captured operations, first test whether a result exists, then `status`,
then the tool's exit policy, then `truncated`, before decoding stdout. A limit
result reports `status = "limit"` with `limit = "memory"`, `"cpu"` or
`"processes"`; its code does not turn it into success. The module exposes this
as `PROJECT limit`, retaining the full result and naming the limit in its
message. Add `limits` to the command when the project needs them. Keep a
wall-clock timeout as well, because a waiting process need not consume CPU.

The message prints stderr itself rather than the result table's address or
stdout mislabeled as stderr. Empty stderr stays empty; stdout is available in
the attached result. A truncation notice means that neither stream should be
treated as a complete diagnostic or document. See [proc](#kuu-page-proc),
[tools](#kuu-page-tools) and [the ledger](#kuu-page-ledger) for the underlying contracts.

---

<a id="kuu-page-working-directories"></a>

<a id="kuu-page-working-directories-working-directories-through-wrappers"></a>

## Working directories through wrappers

Keep the caller's directory explicit when a wrapper enters a project and
launches another program through its manifest.

These are separate places:

| place | meaning in this recipe |
|---|---|
| project root | the directory containing `manifest.lua` and the pinned `kuu.exe` |
| caller cwd | the directory from which the user launched the wrapper |
| wrapper cwd | initially the caller cwd; this wrapper leaves its own cwd alone |
| child cwd | the validated directory explicitly supplied to `task.exec` |
| module root | the base for project `require` calls; `rt.root()` starts at a file program's directory and becomes the project root for `kuu run` |

`kuu run` finds the manifest above its starting directory and enters that
project **before loading the manifest**. Therefore `fs.cwd()` at the top of
`manifest.lua` returns the project root, not the original invocation directory.
Capture the caller cwd in the wrapper first and pass it as an argument. No
invocation-directory API or process-wide `fs.chdir` in the task is needed.

<a id="kuu-page-working-directories-complete-wrapper-and-manifest"></a>

### Complete wrapper and manifest

Use this layout. The runtime can be downloaded or committed according to the
project's pinned-runtime policy in [Adopting kuu](#kuu-page-adopting).

```text
repo/
  kuu.exe
  manifest.lua
  tools/
    from-here.lua
    report.lua
```

Save this as `tools/from-here.lua`. On the file route, kuu sets `rt.root()` to
the script's directory without changing cwd. The wrapper locates its project
from that directory, even when launched from somewhere unrelated. It launches
the project's runtime with the project root as cwd so the intended manifest
is selected. `--cwd` belongs to this task's schema, not to the `kuu run` verb.

```lua
global none
global <const> require, ipairs, io, os, tostring

local fs, rt, proc = require "fs", require "rt", require "proc"
local caller_cwd = fs.cwd()
local project_root = fs.absolute(fs.join(rt.root(), ".."))
local command = {
  fs.join(project_root, "kuu.exe"), "run", "report", "--cwd", caller_cwd, "--",
  cwd = project_root, inherit = true, timeout = "1m",
}
for _, value in ipairs(rt.args) do command[#command + 1] = value end
local result, why = proc.run(command)
if not result then
  io.stderr:write("from-here: ", tostring(why), "\n")
  os.exit(1)
end
if result.status ~= "exit" then
  io.stderr:write("from-here: child status ", result.status, "\n")
  os.exit(1)
end
os.exit(result.code)
```

Save this as `manifest.lua`. Require an absolute directory: resolving a
relative `--cwd` here would resolve it against the project root, after the
original caller context was lost. A directory link is accepted if its target
is a directory. Existence is checked before launch; the actual launch still
reports an error if the directory disappears or becomes inaccessible later.

```lua
global none
global <const> require, ipairs

local task, fs, rt, err = require "task", require "fs", require "rt", require "err"
local project_root = fs.absolute(rt.root())
task.tool "kuu" { exe = "kuu.exe", output = "ndjson", timeout = "20s" }

task "report" {
  desc = "report from the wrapper's original working directory",
  args = {
    { "--cwd", type = "string", required = true, help = "absolute caller directory" },
    { "argv", type = "string", rest = true, help = "arguments for the report program" },
  },
  run = function(opts)
    local cwd = opts.cwd:gsub("\\", "/")
    if not cwd:match("^%a:/") and not cwd:match("^//[^/]+/[^/]+") then
      return nil, err.new("PROJECT", "cwd", "--cwd must be an absolute drive or UNC path")
    end
    local info, why = fs.stat(cwd)
    if not info then return nil, why end
    if info.kind ~= "directory" then
      return nil, err.new("PROJECT", "cwd", "--cwd must name a directory")
    end
    local command = {
      tool = "kuu", fs.join(project_root, "tools/report.lua"), cwd = fs.absolute(cwd),
    }
    for _, value in ipairs(opts.argv) do command[#command + 1] = value end
    return task.exec(command)
  end,
}
```

Save this small diagnostic child as `tools/report.lua`; replace its body with
the real operation when adopting the recipe. Its script path is absolute, so
changing child cwd cannot select a different script. Its `require` root stays
at `tools/`, while relative filesystem operations use the explicit caller cwd.

```lua
global none
global <const> require, io

local fs, rt, json = require "fs", require "rt", require "json"
io.write(json.encode {
  cwd = fs.cwd(), module_root = rt.root(), argv = json.array(rt.args),
}, "\n")
```

Launch the wrapper by its path using the project's runtime, from the project
root, a nested directory, or an unrelated directory. For example, in
PowerShell, `& 'C:\work\my project\kuu.exe' 'C:\work\my project\tools\from-here.lua' 'a file.txt' --help` sends both argument values to
the report program. The wrapper supplies the task parser's first `--`;
later `--`, `--help`, and `--cwd` values are ordinary child arguments. The
file route itself does not consume them as task options.

Use argument arrays at every process boundary. Do not join them into command
text or add quote characters around paths. Empty arguments, embedded double
quotes and trailing backslashes are preserved by kuu's Windows argv encoding;
the initial shell must first deliver the intended values to the wrapper.
Windows filenames cannot contain a double quote: test paths with spaces and
apostrophes, and double quotes inside **argument values** instead.

The wrapper checks process status before forwarding an exit code. An ordinary
nonzero exit passes from the child through `task.exec`, the nested `kuu run`,
and the wrapper. A launch error or timeout is reported as failure, not treated
as a successful exit. See [Process recipes](#kuu-page-process-recipes) for captured
diagnostics and accepted nonzero codes, and [Tasks](#kuu-page-task) for child records
and JSON reporting.

---

<a id="kuu-page-project-environment"></a>

<a id="kuu-page-project-environment-shared-project-environment-and-caches"></a>

## Shared project environment and caches

Keep one environment recipe for CLI tools and newly launched editors. Anchor
its paths to the project root, even when `kuu run` starts in a nested directory.
Under `kuu run`, `rt.root()` is the manifest's directory; it is the module
search root, not the caller's original working directory. See
[working directories](#kuu-page-working-directories) when a child needs that caller's
directory instead.

<a id="kuu-page-project-environment-a-shared-module"></a>

### A shared module

Save as `automation/project_env.lua`. It computes paths but creates nothing at
module load. Tools create their own caches when needed. Ignore `/.cache/`,
`/.venv/` and `/.tools/` in the project's `.gitignore`.

```lua
global none
global <const> require, ipairs
local fs, rt, task, proc = require "fs", require "rt", require "task", require "proc"
local root = fs.absolute(rt.root())
local M = { root = root }

function M.overlay()
  return {
    UV_CACHE_DIR = root .. "/.cache/uv",
    UV_PROJECT_ENVIRONMENT = root .. "/.venv",
    npm_config_cache = root .. "/.cache/npm",
    GOCACHE = root .. "/.cache/go/build",
    GOMODCACHE = root .. "/.cache/go/modules",
    VIRTUAL_ENV = false,
    PYTHONHOME = false,
    PYTHONPATH = false,
  }
end

local function command(tool, arguments)
  local spec = { tool = tool, cwd = root, env = M.overlay() }
  for i, argument in ipairs(arguments) do spec[i] = argument end
  return spec
end

function M.run(tool, arguments)
  return task.exec(command(tool, arguments))
end

function M.launch(tool, arguments)
  local resolved = task.command(command(tool, arguments))
  -- detach accepts only argv, cwd and env, not a tool/default timeout.
  local detached = { cwd = resolved.cwd, env = resolved.env }
  for i, argument in ipairs(resolved) do detached[i] = argument end
  return proc.detach(detached)
end

return M
```

Each call gets a fresh overlay. A string sets a variable, including an empty
string; `false` removes it. Other inherited variables remain. This is a partial
overlay, not a clean or hermetic environment. The explicit Python removals
prevent those inherited activation settings from choosing a different project.
They do not disable every tool's user configuration or interpreter discovery.
Pin and declare the actual executables separately. For subprocesses a tool
launches by bare name, explicitly provide its required project tool directories
in `PATH`; calling the top-level tool by absolute path does not configure its
own subprocess search.

A strict allowlist requires enumerating `env.all()`, marking every unapproved
name `false`, then adding the approved values. Windows names are case
insensitive: compare names consistently and do not supply differently cased
duplicates. Decide which Windows variables and credentials each tool actually
requires before using such an allowlist. This module intentionally does not
implement that broader policy or persist machine/user settings.

The cache variables are documented upstream: [uv's cache directory](https://docs.astral.sh/uv/reference/environment/#uv_cache_dir),
[uv's project environment path](https://docs.astral.sh/uv/concepts/projects/config/#project-environment-path),
[npm's cache configuration and environment settings](https://docs.npmjs.com/cli/v11/using-npm/config/),
and [Go's environment variables](https://pkg.go.dev/cmd/go#hdr-Environment_variables).
`GOCACHE` must be absolute. `GOMODCACHE` contains downloaded modules; it is
separate from Go's build cache. These settings select locations; they do not
prove a cache is complete, portable or sufficient for offline reconstruction.

<a id="kuu-page-project-environment-exercise-both-launch-paths"></a>

### Exercise both launch paths

The following complete example uses kuu itself as an environment probe. It
opens no GUI and needs no installed language tools. Save as `manifest.lua` and
keep the project's verified, pinned `kuu.exe` beside it as described in
[Adopting kuu](#kuu-page-adopting).

```lua
global none
global <const> require, print
local task, json = require "task", require "json"
local project_env = require "automation.project_env"
task.defaults { timeout = "5s" }
task.tool "environment_probe" { exe = "kuu.exe", output = "lines", timeout = "3s" }
local probe = project_env.root .. "/automation/environment_probe.lua"

task "environment" {
  desc = "Report selected environment settings through a supervised child",
  run = function() return project_env.run("environment_probe", { probe, "cli" }) end,
}
task "editor_environment" {
  desc = "Report the same settings through a short detached probe",
  run = function()
    local pid, why = project_env.launch("environment_probe", { probe, "detached" })
    if not pid then return nil, why end
    print(json.encode { pid = pid })
    return true
  end,
}
```

Save as `automation/environment_probe.lua`. It reports only chosen settings;
do not dump `env.all()` into logs, because the inherited environment may hold
tokens and passwords. The sentinel is a test value, not an application secret.

```lua
global none
global <const> require, assert, print
local fs, env, rt, json = require "fs", require "env", require "rt", require "json"
local report = {
  cwd = fs.cwd(),
  uv = env.get("UV_CACHE_DIR"),
  venv = env.get("UV_PROJECT_ENVIRONMENT"),
  npm = env.get("npm_config_cache"),
  go_build = env.get("GOCACHE"),
  go_modules = env.get("GOMODCACHE"),
  virtual_env = env.get("VIRTUAL_ENV") or json.null,
  python_home = env.get("PYTHONHOME") or json.null,
  python_path = env.get("PYTHONPATH") or json.null,
  path_empty = env.get("PATH") == "",
  sentinel = env.get("PROJECT_ENV_SENTINEL") or json.null,
}
local encoded = json.encode(report)
if rt.args[1] == "detached" then
  assert(fs.mkdir(".cache"))
  assert(fs.write(".cache/detached-environment.json", encoded))
else
  print(encoded)
end
```

Run `kuu run environment`, then `kuu run editor_environment`. The latter
prints the launched PID; its short child writes `.cache/detached-environment.json`
before exiting. A detached process has no kuu console and no supervision or
deadline from `task.defaults`. Its launch succeeding is not a readiness check.
There is no individual `task.exec` child record for `M.launch`; the enclosing
task and run are recorded.

For an actual editor, declare its pinned executable as a tool and call
`project_env.launch("editor", { project_env.root })` with that editor's explicit
arguments. Use its documented separate-instance/profile options when it might
forward the request to an existing process. A running editor keeps the
environment from its original launch; changing this module does not update
that process. Close/restart or start an independent instance before checking
its child tools. [Environment lifetime](#kuu-page-env-the-two-environments) explains
the same boundary for consoles and persisted settings. Supervised CLI calls
use `M.run` and retain their task/tool timeout and child records.

The [editor recipe](#kuu-page-editor) demonstrates both paths with a real disposable
GUI on a private desktop, including readiness, failure and cleanup checks.

---

<a id="kuu-page-relocation"></a>

<a id="kuu-page-relocation-relocation-and-an-offline-doctor"></a>

## Relocation and an offline doctor

Derive local paths from the current project root, as in
[the shared environment recipe](#kuu-page-project-environment). After a checkout
moves, the next `kuu run` discovers its new root; a fresh process resolves
declared relative tools there. Already running processes retain their old
working directory, environment and loaded modules. Stop them before moving
the checkout and launch them again afterwards.

<a id="kuu-page-relocation-moving-maintained-source"></a>

### Moving maintained source

For a `scripts/` to `automation/` migration:

1. Move the maintained Lua files and update `require "scripts.health"` to
   `require "automation.health"`, including imports between project modules.
2. Update script arguments, task tool paths, build configuration and tests that
   intentionally name the old directory. `require "a.b"` resolves `a/b.lua` or
   `a/b/init.lua` below the module root; `LUA_PATH` does not override kuu's
   [module lookup](#kuu-page-index-modules).
3. Run static `kuu check`, then `kuu list` to validate declarations. Keep
   provisioning out of top-level Lua: listing executes the manifest.
4. Recreate generated local launchers, editor settings and shortcuts that
   contain absolute paths, executable targets or working directories. Keep
   these local outputs ignored. Their previous paths are not rewritten by kuu.
5. Inspect obsolete ignored environments separately. Checking out a tracked
   rename, or moving tracked files individually, can leave `scripts/.venv`
   behind. A whole-directory filesystem rename can carry ignored children;
   do not assume every kind of move has the same result.

For a whole-checkout move, retain the project's chosen pinned runtime and
verified dependency caches. Recompute environment/cache paths in the new
location, run the local doctor below, then explicitly recreate installations
that retain absolute paths. A cache directory existing does not establish that
it contains everything needed to rebuild offline.

<a id="kuu-page-relocation-python-environments-and-relocation-markers"></a>

### Python environments and relocation markers

Recreate a Python virtual environment at its final new path using the declared
pinned interpreter, then reinstall the locked dependencies and editable local
packages against their current source locations. Do not move a venv and assume
that editing `pyvenv.cfg` repairs launchers, `.pth` files, editable metadata,
native packages or references to its base interpreter. Python documents venvs
as disposable rather than portable. [Python venv documentation](https://docs.python.org/3/library/venv.html).

For a project that uses uv, the configured `UV_PROJECT_ENVIRONMENT` selects
one specific environment; avoid pointing several checkouts at one shared
absolute path. uv installs packaged projects and workspace members as editable
packages during synchronization. After a source move, rebuild that environment
and reinstall from the new layout through the project's explicit installation
task. Keep such synchronization out of `doctor`: it can create or change the
environment. [uv environment location](https://docs.astral.sh/uv/concepts/projects/config/#project-environment-path),
[uv editable installation](https://docs.astral.sh/uv/concepts/projects/sync/#editable-installation).

uv's `--relocatable` adjusts standard entrypoint and activation scripts; it does
not rewrite arbitrary binaries or guarantee that every installed package and
editable source reference survives a move. A project's own `relocatable=true`
receipt, or the ownership marker used below, proves neither current path
validity nor application readiness. [uv relocatable option](https://docs.astral.sh/uv/reference/cli/#uv-venv--relocatable).

<a id="kuu-page-relocation-a-non-repairing-doctor"></a>

### A non-repairing doctor

This example checks a small project's pinned local executable and cached
archive. It does not launch either, access the network, provision dependencies
or compile application packages. Missing generated assets cannot prevent it
from diagnosing dependency state. A project's richer doctor can add bounded,
read-only version/import probes through known installed tools; keep application
builds and installers in separate tasks.

Maintain `dependencies.json` in source control with the independently reviewed
SHA-256 values for `.tools/tool/tool.exe` and `.cache/dependencies/tool.zip`:

```json
{
  "tool_sha256": "REPLACE_WITH_REVIEWED_EXECUTABLE_SHA256",
  "archive_sha256": "REPLACE_WITH_REVIEWED_ARCHIVE_SHA256"
}
```

These placeholders deliberately fail validation. Do not generate expected
digests from whatever files happen to be installed during a doctor run. The
archive digest is a byte-integrity check; it does not prove unpacking or full
offline dependency reconstruction will succeed.

Save as `automation/health.lua`:

```lua
global none
global <const> require, type, tostring
local fs, rt, hash, json, err = require "fs", require "rt", require "hash", require "json", require "err"
local root = fs.absolute(rt.root())
local M = {}

local function valid_digest(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-fA-F]+$") ~= nil
end

local function inspect_file(relative, expected)
  local path = fs.join(root, relative)
  local info, why = fs.stat(path, { follow = false })
  if not info then
    return { path = path, status = err.is(why, "FS", "notfound") and "missing" or "unreadable",
      message = tostring(why) }
  end
  if info.kind ~= "file" or info.reparse then
    return { path = path, status = "unexpected-kind", message = "expected an ordinary file" }
  end
  if not expected then return { path = path, status = "present-unverified" } end
  local digest, failure = hash.file("sha256", path)
  if not digest then return { path = path, status = "unreadable", message = tostring(failure) } end
  return { path = path, status = digest == expected:lower() and "verified" or "mismatch", sha256 = digest }
end

function M.inspect()
  local text, why = fs.read(root .. "/dependencies.json", { maxbytes = "16K" })
  if not text then return nil, why end
  local pins, parse_error = json.decode(text)
  if pins == nil then return nil, parse_error end
  if type(pins) ~= "table" or not valid_digest(pins.tool_sha256) or not valid_digest(pins.archive_sha256) then
    return nil, err.new("PROJECT", "pins", "dependencies.json requires reviewed 64-digit tool_sha256 and archive_sha256 values")
  end
  local report = {
    root = root,
    installed = inspect_file(".tools/tool/tool.exe", pins.tool_sha256),
    cache = inspect_file(".cache/dependencies/tool.zip", pins.archive_sha256),
    application = inspect_file("build/app.exe"),
  }
  if report.application.status == "missing" then report.application.status = "not-built" end
  report.application.ready = false -- this doctor does not establish application readiness
  report.ok = report.installed.status == "verified" and report.cache.status == "verified"
  return report
end

return M
```

The three results mean different things: `installed.status == "verified"` says the expected
executable bytes are present, not that every supporting DLL exists;
`cache.status == "verified"` says this archive matches its pin; an application file remains
`present-unverified` until a separate project-specific readiness check succeeds.
Absent application output is `not-built` and does not fail this dependency
doctor. Access and digest failures remain visible rather than becoming missing
dependencies. Filesystem checks are observations, not a transaction against
concurrent writers or a sandbox for untrusted linked ancestors.

Save as `manifest.lua`. This doctor has **no provisioning dependencies**.
`kuu run doctor` prints the report and fails when either dependency check fails.
Run an explicit install or repair task separately after reading the report.
Normal task/run history is still written under `.kuu`; “non-repairing” does not
mean the entire kuu invocation performs zero writes.

```lua
global none
global <const> require, print
local task, json, err = require "task", require "json", require "err"
local health = require "automation.health"
local remove_obsolete = require "automation.remove_obsolete"

task "doctor" {
  desc = "Check local dependency bytes without installing or building",
  run = function()
    local report, why = health.inspect()
    if not report then return nil, why end
    print(json.encode(report))
    if not report.ok then
      return nil, err.new("PROJECT", "health", "installed=" .. report.installed.status ..
        "; cache=" .. report.cache.status .. "; inspect the report before an explicit repair")
    end
    return true
  end,
}
task "clean_obsolete_environment" {
  desc = "Remove only this project's marked obsolete scripts/.venv",
  run = function() return remove_obsolete() end,
}
```

<a id="kuu-page-relocation-remove-only-the-owned-obsolete-environment"></a>

### Remove only the owned obsolete environment

Save the [bounded cleanup module](#kuu-page-cleanup-a-project-module) as `owned_ops.lua`
at the project root, then save this function as `automation/remove_obsolete.lua`.
It requires the readonly-directory cleanup from 0.12 described on that page;
use `rt.version_at_least(0, 12)` as its minimum-version guard.
The only removal target is the literal `scripts/.venv` below the canonical
project root. It accepts no caller-supplied path. Its owner marker must have
been written by this project's environment-creation task when it created that
directory: `.project-owner` contains exactly `example-project/venv/v1` followed
by a newline. Choose your own project identifier. Never add a marker to an
uninspected directory just to make cleanup accept it.

Use this only during exclusive maintenance: stop processes using or modifying
the old environment. The trusted project root may itself resolve through a
link; below that canonical root, every path component and the marker must be
ordinary, without reparse metadata. These checks are not protection against
concurrent malicious path replacement. Other files under `scripts/`, the
current environment and dependency caches remain outside the removal target.

```lua
global none
global <const> require, ipairs
local fs, rt, err = require "fs", require "rt", require "err"
local owned_ops = require "owned_ops"
local OWNER = "example-project/venv/v1\n"

return function()
  local canonical, why = fs.canon(rt.root())
  if not canonical then return nil, why end
  if canonical.kind ~= "directory" then return nil, err.new("PROJECT", "ownership", "project root is not a directory") end
  local target = canonical.path
  for _, component in ipairs { "scripts", ".venv" } do
    target = fs.join(target, component)
    local info, failure = fs.stat(target, { follow = false })
    if not info then
      if err.is(failure, "FS", "notfound") then return true end
      return nil, failure
    end
    if info.kind ~= "directory" or info.reparse then
      return nil, err.new("PROJECT", "ownership", "refusing linked or non-directory cleanup component: " .. target)
    end
  end
  local marker = target .. "/.project-owner"
  local info, failure = fs.stat(marker, { follow = false })
  if not info then return nil, failure end
  if info.kind ~= "file" or info.reparse or info.size ~= #OWNER then
    return nil, err.new("PROJECT", "ownership", "obsolete environment has no valid ordinary ownership marker")
  end
  local text, read_error = fs.read(marker, { maxbytes = 128 })
  if not text then return nil, read_error end
  if text ~= OWNER then return nil, err.new("PROJECT", "ownership", "obsolete environment belongs to another owner") end
  return owned_ops.remove_owned(target, 0.5)
end
```

Run `kuu run clean_obsolete_environment` only after adopting the new layout.
Already absent cleanup succeeds; an existing unmarked, differently marked or
linked environment fails without removal. Recursive removal can make partial
progress before a failure, including deleting the ownership marker. Keep the
returned error. If the marker still passes validation, rerun this same bounded
cleanup after resolving the cause. If partial removal consumed the marker,
this task safely refuses the remaining directory: inspect and recover it under
explicit project ownership instead of manufacturing a new marker or broadening
the target. The retry loop within one invocation retains the already validated
target, which is another reason exclusive maintenance is required.

---

<a id="kuu-page-editor"></a>

<a id="kuu-page-editor-detached-editors-and-isolated-gui-verification"></a>

## Detached editors and isolated GUI verification

Use the same declared executable and [project environment](#kuu-page-project-environment)
for a bounded CLI operation and a newly launched editor. A PID means launch
succeeded; it does not establish that the editor loaded its workspace, profile
or extensions. Readiness needs a separate signal from the application.

<a id="kuu-page-editor-a-disposable-native-gui-probe"></a>

### A disposable native GUI probe

The source example [gui_probe.c](examples/gui_probe.c) is a small project
helper, not a new kuu API. Build it with the project's pinned Windows compiler
and keep it at `.tools/gui-probe/gui_probe.exe`. In kuu's source checkout,
`make fixtures` builds this exact source with its pinned UCRT64 toolchain into
`build/test/gui_probe.exe`; the tests copy that artifact into disposable projects.
The C source is supplied with the repository; it is not embedded as a Lua module.

The helper's contract is:

```text
gui_probe.exe verify PROFILE REPORT [ready|no-ready|early-exit|hold-ready]
```

PROFILE and REPORT must be absolute paths with existing parents. The profile
must be absent; an existing profile or report is refused without replacement.
The helper creates a private Windows desktop and launches its own small editor
there. The child creates a window with an EDIT control, verifies the desktop
and selected environment, and signals readiness with a fresh nonce. The helper
never switches the interactive desktop. It owns the child through a retained
process handle and a job that terminates children when closed, then removes
only the known files in its newly created profile. Unexpected entries or
cleanup errors remain failures and are reported.

An atomically published REPORT contains `ok`, `status`, `win32`, `desktop`,
`private_desktop`, `window_ready`, `child_pid`, `child_exited`, `profile_created`,
`profile_removed`, `cleanup_error`, selected `cache` and `recipe` values,
`nonce`, and `elapsed_ms`. `ok` includes cleanup success. Read the report and
exit status together on the supervised path; on the detached path, retain the
PID and report location and explicitly wait for the report.

`no-ready` and `early-exit` exercise failure paths. `hold-ready` is a bounded
test handshake: after window creation the supervisor waits up to three seconds
for PROFILE/continue to contain the exact bytes from PROFILE/ready. This lets
an automated caller prove that both the supervisor and GUI survive the kuu
launcher exiting, then release them. It is not an interactive user prompt.

<a id="kuu-page-editor-a-complete-manifest"></a>

### A complete manifest

Save the shared module from [Project environment](#kuu-page-project-environment-a-shared-module)
as `automation/project_env.lua`, keep the project's verified `kuu.exe` at its
root, and save this manifest. Ignore `/.local/` as well as the tool and cache
directories. The helper is the one declared project tool for both launch paths.

```lua
global none
global <const> require, ipairs, print
local task, fs, hash, json, proc = require "task", require "fs", require "hash", require "json", require "proc"
local project_env = require "automation.project_env"
local root = project_env.root
task.defaults { timeout = "12s" }
task.tool "editor_probe" { exe = ".tools/gui-probe/gui_probe.exe", output = "lines", timeout = "12s" }

local function command(mode)
  local directory = root .. "/.local/gui-checks"
  local made, why = fs.mkdir(directory)
  if not made then return nil, why end
  local id = hash.uuid()
  local paths = { profile = directory .. "/profile-" .. id, report = directory .. "/report-" .. id .. ".json" }
  local overlay = project_env.overlay()
  overlay.KUU_EDITOR_RECIPE = "isolated-v1"
  overlay.KUU_EDITOR_CACHE = root .. "/.cache/editor"
  return { tool = "editor_probe", "verify", paths.profile, paths.report, mode,
    cwd = root, env = overlay }, paths
end

task "verify_editor" {
  desc = "Verify a disposable GUI on a private desktop and clean it up",
  run = function()
    local spec, paths = command("ready")
    if not spec then return nil, paths end
    print(json.encode(paths))
    return task.exec(spec)
  end,
}

task "launch_editor" {
  desc = "Detach the same disposable GUI verifier; inspect its completion report",
  args = { { "--hold", type = "flag", help = "bounded test handshake after the kuu launcher exits" } },
  run = function(opts)
    local spec, paths = command(opts.hold and "hold-ready" or "ready")
    if not spec then return nil, paths end
    local resolved = task.command(spec)
    local detached = { cwd = resolved.cwd, env = resolved.env }
    for i, argument in ipairs(resolved) do detached[i] = argument end
    local pid, why = proc.detach(detached)
    if not pid then return nil, why end
    paths.pid = pid
    print(json.encode(paths))
    return true
  end,
}
```

Run `kuu run verify_editor` for the bounded operation; `task.exec` records the
child and reports helper failures. `kuu run launch_editor` returns after
launching; its supervisor has its own internal bounds, and the task timeout
does not govern that detached lifetime. A captured or detached child has no
individual `task.exec` child record; its enclosing task/run still has history.
The `--hold` option is for the automated nonce handshake, not a normal launch.

For a real editor, replace the tool with its pinned project executable and use
its documented profile, workspace and separate-instance arguments. Supply a
fresh disposable profile for verification; an existing editor may accept a
request without starting a new process or adopting the new environment.
Choose an application-specific readiness check instead of treating PID
existence, an open window or a fixed sleep as proof of a usable workspace.

<a id="kuu-page-editor-profiles-and-database-snapshots"></a>

### Profiles and database snapshots

Use generated test settings and fresh profiles. Live cookie databases, locks
and credentials are not ordinary portable configuration files. A copied
profile can combine database files from different moments, or combine a newly
copied database with an old destination WAL. Do not merge snapshots into a
reused destination or delete a WAL merely because it looks stale: SQLite's
[WAL is part of persistent database state](https://www.sqlite.org/wal.html).
For legitimate application backups, use its supported export/backup operation,
or establish a consistent cold snapshot after its writers stop. This recipe
does not import browser profiles or copy live user databases.

<a id="kuu-page-editor-platform-limits"></a>

### Platform limits

The test creates a desktop in the current session and uses ordinary Win32 GUI
controls. It requires permission to create that desktop and launch a process
on it; noninteractive services, restrictive enclosing jobs and session policy
can prevent the operation. It reports failure rather than falling back to the
interactive desktop. See Microsoft's [desktop access rights](https://learn.microsoft.com/en-us/windows/win32/winstation/desktop-security-and-access-rights).

A private desktop keeps this probe's windows off the interactive desktop; it
is not a filesystem, network or security sandbox. These checks establish this
probe's GUI creation, selected environment, lifetime and cleanup. They do not
certify arbitrary editors, GPU rendering, extension loading, login flows or
application-specific profile formats. No application outside the owned test
processes is terminated or modified.

---

<a id="kuu-page-native-helper"></a>

<a id="kuu-page-native-helper-a-cached-native-helper-and-local-shortcuts"></a>

## A cached native helper and local shortcuts

Use a small project helper when an operation needs a Windows interface outside
kuu's palette. The source [shell_link.c](examples/shell_link.c) creates a
Shell Link through `IShellLinkW` and `IPersistFile`; it is supplied with this
repository, not embedded as a Lua module. Copy it into `native/shell_link.c`
in the adopting project. Its interface is:

```text
shell_link.exe create LINK TARGET CWD [ARG ...]
```

All three paths are absolute. TARGET is the executable path alone, CWD is its
working directory, and each following value is a separate child argument.
The helper encodes those arguments using Windows C-runtime quoting, including
empty values, embedded quotes and trailing backslashes. It creates LINK without
replacing an existing file. It prints operation/HRESULT diagnostics to stderr
and fails if creation or publication fails. The APIs are documented by
Microsoft: [Shell Links](https://learn.microsoft.com/en-us/windows/win32/shell/links),
[SetArguments](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishelllinkw-setarguments),
[IPersistFile::Save](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-ipersistfile-save),
and [C argument parsing](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments).

<a id="kuu-page-native-helper-inputs-and-ownership"></a>

### Inputs and ownership

Provision the project's pinned compiler under `.tools/msys2/ucrt64`, following
the complete [UCRT64 package closure](#kuu-page-toolchain-the-ucrt64-pins). No compiler
is installed on the machine. Save the reviewed package list and the expected
installed compiler hash in `toolchain.lock.json`:

```json
{
  "v": 1,
  "compiler_sha256": "REPLACE_WITH_REVIEWED_GCC_EXE_SHA256",
  "packages": [
    { "file": "REPLACE_WITH_EACH_PINNED_PACKAGE_FILENAME", "sha256": "REPLACE_WITH_REVIEWED_PACKAGE_SHA256" }
  ]
}
```

Replace the placeholders with the **whole** reviewed closure, not just gcc's
package. Provisioning must verify those archives before extraction; record the
compiler digest from that verified installation. Do not repair a pin from
unexpected installed bytes. The recipe hashes the complete lockfile and checks
the actual compiler driver against its pin. It does not re-hash every installed
header, library or compiler subprocess on each cache hit; those remain part of
the project's trusted, exclusively maintained toolchain installation.

Save [owned_ops.lua](#kuu-page-cleanup-a-project-module) at the project root. Ignore
`/.tools/`, `/.cache/`, `/.local/`, and `/.kuu/`. The generated helper cache and
`.local/native-helper/shell_link.exe` belong exclusively to this recipe.
`.local/project.lnk` is its one replaceable shortcut. No desktop, Start menu,
user profile or machine-wide path is modified.

This uses the cleanup recipe's APIs from 0.12. Require
`rt.version_at_least(0, 12)` and adopt the project's approved runtime by hash.

<a id="kuu-page-native-helper-build-and-verify-a-cache-entry"></a>

### Build and verify a cache entry

Save as `automation/native_helper.lua`. Its key includes the source bytes, the
actual build-module bytes and flags, the complete toolchain lockfile, and the
verified compiler-driver digest. A recipe edit therefore invalidates the cache
even when the C source stays unchanged. Every reuse checks the receipt and the
cached executable hash. Corruption is an error with the exact cache path; the
recipe never silently executes, deletes or repairs a corrupt cache entry.

```lua
global none
global <const> require, ipairs, type, tostring, table
local fs, rt, task, hash = require "fs", require "rt", require "task", require "hash"
local json, err, ops = require "json", require "err", require "owned_ops"
local root = fs.absolute(rt.root())
local M = {}
local FLAGS = { "-std=c23", "-O2", "-Wall", "-Wextra", "-Werror", "-municode", "-static", "-s" }
local LIBRARIES = { "-lole32", "-luuid" }

local function digest(value)
  return type(value) == "string" and #value == 64 and value:match("^%x+$") ~= nil
end
local function failure(code, message, cause)
  return nil, err.new("PROJECT", code, message .. (cause and (": " .. tostring(cause)) or ""), { cause = cause })
end
local function ordinary(path, kind)
  local info, why = fs.stat(path, { follow = false })
  if not info then return nil, why end
  if info.kind ~= kind or info.reparse then return failure("cache", "expected ordinary " .. kind .. ": " .. path) end
  return info
end
local function inputs()
  local lock, why = fs.read(root .. "/toolchain.lock.json", { maxbytes = "256K" })
  if not lock then return nil, why end
  local pins, parse_error = json.decode(lock)
  if pins == nil then return nil, parse_error end
  if type(pins) ~= "table" or pins.v ~= 1 or not digest(pins.compiler_sha256)
      or type(pins.packages) ~= "table" or not json.is_array(pins.packages) or #pins.packages == 0 then
    return failure("pins", "toolchain.lock.json requires v=1, compiler_sha256 and the complete pinned packages array")
  end
  for _, package in ipairs(pins.packages) do
    if type(package) ~= "table" or type(package.file) ~= "string" or package.file == "" or not digest(package.sha256) then
      return failure("pins", "each toolchain package needs its reviewed filename and SHA-256")
    end
  end
  local compiler = task.command { tool = "cc" }
  local actual, hash_error = hash.file("sha256", compiler[1])
  if not actual then return nil, hash_error end
  if actual ~= pins.compiler_sha256:lower() then return failure("compiler", "installed gcc does not match compiler_sha256") end
  local source, source_error = fs.read(root .. "/native/shell_link.c", { maxbytes = "256K" })
  if not source then return nil, source_error end
  local builder, builder_error = fs.read(root .. "/automation/native_helper.lua", { maxbytes = "256K" })
  if not builder then return nil, builder_error end
  local identity = {
    source_sha256 = hash.sum("sha256", source),
    recipe_sha256 = hash.sum("sha256", builder .. "\0" .. json.encode(json.array(FLAGS)) .. json.encode(json.array(LIBRARIES))),
    toolchain_sha256 = hash.sum("sha256", lock), compiler_sha256 = actual,
  }
  identity.key = hash.sum("sha256", table.concat({ identity.source_sha256, identity.recipe_sha256,
    identity.toolchain_sha256, identity.compiler_sha256 }, ":"))
  identity.source = source
  return identity
end
local function cached(directory, expected)
  local info, why = ordinary(directory, "directory")
  if not info then return failure("cache", "invalid cache directory " .. directory, why) end
  local receipt_info, receipt_error = ordinary(directory .. "/receipt.json", "file")
  if not receipt_info then return failure("cache", "invalid cache receipt at " .. directory, receipt_error) end
  local text, read_error = fs.read(directory .. "/receipt.json", { maxbytes = "16K" })
  if not text then return failure("cache", "cannot read cache receipt at " .. directory, read_error) end
  local receipt = json.decode(text)
  if type(receipt) ~= "table" or receipt.v ~= 1 or not digest(receipt.executable_sha256) then
    return failure("cache", "malformed cache receipt at " .. directory)
  end
  for _, field in ipairs { "key", "source_sha256", "recipe_sha256", "toolchain_sha256", "compiler_sha256" } do
    if receipt[field] ~= expected[field] then return failure("cache", "cache receipt disagrees on " .. field .. " at " .. directory) end
  end
  local file, file_error = ordinary(directory .. "/shell_link.exe", "file")
  if not file then return failure("cache", "invalid cached executable at " .. directory, file_error) end
  local actual, hash_error = hash.file("sha256", directory .. "/shell_link.exe")
  if not actual then return failure("cache", "cannot hash cached executable at " .. directory, hash_error) end
  if actual ~= receipt.executable_sha256 then return failure("cache", "cached executable hash mismatch at " .. directory) end
  return receipt
end
local function finish(stage, ok, primary)
  local removed, cleanup = ops.remove_owned(stage, 0.5)
  if ok then
    if not removed then return nil, cleanup end
    return true
  end
  return nil, primary, not removed and cleanup or nil
end
local function install(cache, receipt)
  local directory = root .. "/.local/native-helper"
  local made, why = fs.mkdir(directory)
  if not made then return nil, why end
  local target = directory .. "/shell_link.exe"
  local existing, absent = fs.stat(target, { follow = false })
  if existing then
    if existing.kind ~= "file" or existing.reparse then return failure("cache", "refusing non-file helper target: " .. target) end
    if hash.file("sha256", target) == receipt.executable_sha256 then return true end
  elseif not err.is(absent, "FS", "notfound") then return nil, absent end
  local stage, stage_error = fs.tempdir { dir = directory, prefix = ".stage-" }
  if not stage then return nil, stage_error end
  local bytes, read_error = fs.read(cache .. "/shell_link.exe", { maxbytes = "16M" })
  if not bytes then return finish(stage, nil, read_error) end
  if hash.sum("sha256", bytes) ~= receipt.executable_sha256 then
    return finish(stage, nil, err.new("PROJECT", "cache", "cache changed before helper installation: " .. cache))
  end
  local written, write_error = fs.write(stage .. "/shell_link.exe", bytes)
  if not written then return finish(stage, nil, write_error) end
  local placed, place_error = fs.rename(stage .. "/shell_link.exe", target, { replace = true })
  return finish(stage, placed, place_error)
end

function M.ensure()
  local expected, why = inputs()
  if not expected then return nil, why end
  local base = root .. "/.cache/native-helper"
  local directory = base .. "/" .. expected.key
  local info, absent = fs.stat(directory, { follow = false })
  local receipt, reused = nil, info ~= nil
  if info then
    receipt, why = cached(directory, expected)
    if not receipt then return nil, why end
  else
    if not err.is(absent, "FS", "notfound") then return nil, absent end
    local made, make_error = fs.mkdir(base)
    if not made then return nil, make_error end
    local stage, stage_error = fs.tempdir { dir = base, prefix = ".stage-" }
    if not stage then return nil, stage_error end
    local published, primary, cleanup = ops.publish(stage, directory, function(path)
      local written, write_error = fs.write(path .. "/shell_link.c", expected.source)
      if not written then return nil, write_error end
      local spec = { tool = "cc", cwd = path, timeout = "1m", env = {
        PATH = root .. "/.tools/msys2/ucrt64/bin", CPATH = false, C_INCLUDE_PATH = false,
        CPLUS_INCLUDE_PATH = false, OBJC_INCLUDE_PATH = false, COMPILER_PATH = false,
        LIBRARY_PATH = false, GCC_EXEC_PREFIX = false,
      } }
      for _, flag in ipairs(FLAGS) do spec[#spec + 1] = flag end
      spec[#spec + 1] = "shell_link.c"
      spec[#spec + 1] = "-o"; spec[#spec + 1] = "shell_link.exe"
      for _, library in ipairs(LIBRARIES) do spec[#spec + 1] = library end
      local built, build_error = task.exec(spec)
      if not built then return nil, build_error end
      local executable_hash, hash_error = hash.file("sha256", path .. "/shell_link.exe")
      if not executable_hash then return nil, hash_error end
      local record = { v = 1, executable_sha256 = executable_hash }
      for _, field in ipairs { "key", "source_sha256", "recipe_sha256", "toolchain_sha256", "compiler_sha256" } do
        record[field] = expected[field]
      end
      local saved, save_error = fs.write(path .. "/receipt.json", json.encode(record))
      if not saved then return nil, save_error end
      return cached(path, expected)
    end, 0.5)
    if not published then
      if not cleanup and err.is(primary, "FS", "exists") then
        receipt, why = cached(directory, expected)
        if not receipt then return nil, why end
        reused = true
      else return nil, primary, cleanup end
    else receipt, why = cached(directory, expected) end
    if not receipt then return nil, why end
  end
  local installed, install_error, cleanup = install(directory, receipt)
  if not installed then return nil, install_error, cleanup end
  return { key = expected.key, cache = directory, reused = reused,
    helper = root .. "/.local/native-helper/shell_link.exe", sha256 = receipt.executable_sha256 }
end

function M.shortcut(arguments)
  local built, why, cleanup = M.ensure()
  if not built then return nil, why, cleanup end
  local destination = root .. "/.local/project.lnk"
  local old, absent = fs.stat(destination, { follow = false })
  if old and (old.kind ~= "file" or old.reparse) then return failure("shortcut", "refusing non-file shortcut target: " .. destination) end
  if not old and not err.is(absent, "FS", "notfound") then return nil, absent end
  local stage, stage_error = fs.tempdir { dir = root .. "/.local", prefix = ".shortcut-stage-" }
  if not stage then return nil, stage_error end
  local spec = { tool = "shell_link", "create", stage .. "/project.lnk", root .. "/kuu.exe", root, cwd = root }
  for _, argument in ipairs(arguments) do spec[#spec + 1] = argument end
  local made, make_error = task.exec(spec)
  if not made then return finish(stage, nil, make_error) end
  local placed, place_error = fs.rename(stage .. "/project.lnk", destination, { replace = true })
  local done, failure_error, cleanup_error = finish(stage, placed, place_error)
  if not done then return nil, failure_error, cleanup_error end
  built.shortcut = destination
  return built
end

return M
```

The cache directory is published only after compilation and its receipt are
complete, using a rename without replacement. A competing publisher's entry
is accepted only after the same validation. The literal declared helper path
is installed atomically from the verified cache; this keeps tool discovery
useful even though cache keys vary. The shortcut is likewise created at a fresh
owned path, then atomically replaces only `.local/project.lnk`. A failed replace
leaves the preceding destination intact. A cleanup failure after successful
publication still fails the task and may leave its new output in place.

Compilation runs inside its staging directory with relative source and output
filenames. This avoids passing a Unicode checkout path through the compiler's
linker filename arguments; kuu supplies the working directory through Windows'
Unicode process API. The declared compiler still resolves from the project root.

The recipe requires exclusive maintenance of sources, toolchain and these
generated paths. It does not sandbox linked ancestors or authenticate receipts
against someone who can rewrite the whole project. Receipts detect changed
bytes relative to the recorded build. Primary and secondary cleanup errors are
returned separately; the manifest below reports both. After a cache error,
inspect that exact entry and deliberately remove/rebuild it if appropriate;
do not delete the entire cache or regenerate its receipt from corrupt bytes.

<a id="kuu-page-native-helper-declare-and-call-the-tools"></a>

### Declare and call the tools

Save as `manifest.lua`, with the verified project runtime at `kuu.exe`. Loading
the module declares no tasks, creates no cache, and runs no compiler; work
begins only inside the requested task.

```lua
global none
global <const> require, print, io, tostring
local task, fs, rt, json = require "task", require "fs", require "rt", require "json"
local helper = require "automation.native_helper"
task.tool "cc" { exe = ".tools/msys2/ucrt64/bin/gcc.exe", output = "lines", timeout = "1m" }
task.tool "shell_link" { exe = ".local/native-helper/shell_link.exe", output = "none", timeout = "10s" }
local function report(value, why, cleanup)
  if cleanup then io.stderr:write("cleanup also failed: ", tostring(cleanup), "\n") end
  if not value then return nil, why end
  print(json.encode(value))
  return true
end
task "build_helper" {
  desc = "Build or verify the pinned native shortcut helper",
  run = function() return report(helper.ensure()) end,
}
task "shortcut" {
  desc = "Regenerate this checkout's owned local shortcut",
  args = { { "argv", type = "string", rest = true, help = "arguments passed to this project's kuu" } },
  run = function(opts)
    local arguments = opts.argv
    if #arguments == 0 then arguments = { "run", "shortcut_probe" } end
    return report(helper.shortcut(arguments))
  end,
}
task "shortcut_probe" {
  desc = "Show where the shortcut ran and the exact arguments it delivered",
  args = { { "argv", type = "string", rest = true } },
  run = function(opts)
    print(json.encode { cwd = fs.cwd(), exe = rt.exe, argv = json.array(opts.argv) })
    return true
  end,
}
```

Run `kuu run build_helper`, then `kuu run shortcut -- run shortcut_probe -- VALUE`.
The resulting link targets this checkout's `kuu.exe`, with its root as cwd.
Argument values are passed as arrays up to the native helper; do not prequote
them or join shell command text. The helper's encoding targets kuu's Windows
C-runtime argv parsing, not a shell or an arbitrary program's custom parser.

After moving the checkout, rerun `kuu run shortcut`. The content cache can be
reused if its identities and hashes still agree, but the link must be rebuilt:
its executable, arguments containing paths, and working directory are local
values. Do not rely on Windows link tracking to choose the intended checkout.
See [relocation](#kuu-page-relocation) for other generated absolute-path artifacts.

The repository tests compile this exact source, read the link through an
independent COM fixture and launch its stored target to inspect actual argv
and cwd. Their disposable project aliases this repository's already pinned
compiler tree through a junction to avoid duplicating its thousands of files;
that alias is a test-harness arrangement, not independent provisioning.

---

<a id="kuu-page-reconstruction"></a>

<a id="kuu-page-reconstruction-reconstructing-tools-and-reconciling-publication"></a>

## Reconstructing tools and reconciling publication

A retained cache, a reachable upstream download and an independent backup are
three different recovery options. Keep reviewed pins in maintained source;
record which archives are necessary for an offline rebuild. A cache directory
alone proves neither completeness nor that upstream URLs will remain available.
This recipe requires 0.12 for the [attribute APIs](#kuu-page-fs-file-attributes) and
readonly-directory removal, with the complete `owned_ops.lua` module from
[cleanup](#kuu-page-cleanup). Use `rt.version_at_least(0, 12)` as its minimum-version guard.

| Recovery source | What must remain available |
|---|---|
| Retained cache | Every required pinned archive, for offline reconstruction. |
| Pinned upstream | Network, URL and access still working; a hash does not preserve availability. |
| Independent backup | A separately retained complete set of verified archives and reviewed pins, with restore testing. |

<a id="kuu-page-reconstruction-restore-an-installation-from-local-bytes"></a>

### Restore an installation from local bytes

Save the following as `restore_cached.lua`. This example package contains
`package.json` with `{schema:1, package, target, recipe}` and `bin/tool.exe`.
The independently reviewed pin adds `archive_sha256` and `tool_sha256`, both
lowercase SHA-256 values. Set `target` to `windows-x86_64` and `recipe` to
`tool-layout-v1`; deliberately revise this recipe before accepting another
layout or platform. An archive's own receipt cannot establish its trust.

Paths and their parents must be project-owned, with writers stopped throughout
the operation. The destination must be absent; publication never replaces an
existing installation. Extraction occurs only after the archive matches its
pin, into a newly created sibling directory. The full tree is inspected before
readonly normalization, rejecting reparse objects and multiply linked files.
These checks close their handles and do not prevent concurrent path replacement.
Use this with reviewed packages, not arbitrary untrusted archives.
Post-extraction checks are not an archive sandbox: review must exclude aliases
outside staging during extraction too. Recursive failure cleanup can clear a
readonly flag shared by hardlinks; rejecting a hardlink during validation does
not undo that risk or establish ownership of its other names.

```lua
global none
global <const> require, type, ipairs
local fs, hash, json = require "fs", require "hash", require "json"
local archive, err, ops = require "archive", require "err", require "owned_ops"
local M = {}
local function refused(code, message) return nil, err.new("PROJECT", code, message) end
local function digest(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end
local function pin_valid(pin)
  return type(pin) == "table" and pin.schema == 1 and type(pin.package) == "string"
    and #pin.package > 0 and pin.target == "windows-x86_64" and pin.recipe == "tool-layout-v1"
    and digest(pin.archive_sha256) and digest(pin.tool_sha256)
end
local function matches(path, expected)
  local actual, why = hash.file("sha256", path)
  if not actual then return nil, why end
  if actual ~= expected then return refused("hash", "pinned bytes differ: " .. path) end
  return true
end

-- Only call for a newly created, exclusively owned staging tree.
function M.normalize_staging(staging)
  local ordinary = {}
  local function inspect(path, depth)
    if depth > 64 or #ordinary >= 100000 then return refused("layout", "staging inspection limit") end
    local info, why = fs.stat(path, { follow = false })
    if not info then return nil, why end
    if (info.attrs & 0x400) ~= 0 or (info.kind ~= "directory" and info.kind ~= "file")
      or (info.kind == "file" and info.links > 1) then
      return refused("layout", "staging requires ordinary unaliased files/directories: " .. path)
    end
    ordinary[#ordinary + 1] = path
    if info.kind == "directory" then
      local listing, listing_error = fs.list(path)
      if not listing then return nil, listing_error end
      if #listing.errors > 0 then return refused("layout", "incomplete staging directory listing") end
      for _, entry in ipairs(listing.entries) do
        local ok, child_error = inspect(path .. "/" .. entry.name, depth + 1)
        if not ok then return nil, child_error end
      end
    end
    return true
  end
  local inspected, why = inspect(staging, 0)
  if not inspected then return nil, why end
  for _, path in ipairs(ordinary) do
    local flags, flag_error = fs.attributes(path) -- nofollow
    if not flags then return nil, flag_error end
    if flags.readonly then
      local ok, update_error = fs.set_attributes(path, { readonly = false })
      if not ok then return nil, update_error end
    end
  end
  return true
end

local function staged(destination, validate)
  local parent = fs.dirname(destination)
  local made, why = fs.mkdir(parent)
  if not made then return nil, why end
  local stage, stage_error = fs.tempdir { dir = parent, prefix = ".reconstruct-" }
  if not stage then return nil, stage_error end
  local ok, primary, cleanup = ops.publish(stage, destination, validate, 0.5)
  return ok, primary, cleanup, stage -- retain the exact owned path if cleanup failed
end

function M.restore(cached, destination, pin)
  if not pin_valid(pin) then return refused("pin", "reviewed compatible package pin required") end
  return staged(destination, function(stage)
    local ok, why = matches(cached, pin.archive_sha256)
    if not ok then return nil, why end
    ok, why = archive.unpack(cached, stage, { timeout = "2m" })
    if not ok then return nil, why end
    ok, why = M.normalize_staging(stage)
    if not ok then return nil, why end
    local bytes, read_error = fs.read(stage .. "/package.json", { maxbytes = "16K" })
    if not bytes then return nil, read_error end
    local receipt, parse_error = json.decode(bytes)
    if receipt == nil then return nil, parse_error end
    if type(receipt) ~= "table" or receipt.schema ~= pin.schema or receipt.package ~= pin.package
      or receipt.target ~= pin.target or receipt.recipe ~= pin.recipe then
      return refused("receipt", "package receipt does not match the reviewed pin")
    end
    local tool, missing = fs.stat(stage .. "/bin/tool.exe", { follow = false })
    if not tool then return nil, missing end
    if tool.kind ~= "file" then return refused("layout", "bin/tool.exe must be a file") end
    return matches(stage .. "/bin/tool.exe", pin.tool_sha256)
  end)
end

function M.backup(cached, destination, pin)
  if not pin_valid(pin) then return refused("pin", "reviewed compatible package pin required") end
  return staged(destination, function(stage)
    local ok, why = matches(cached, pin.archive_sha256)
    if not ok then return nil, why end
    ok, why = fs.copy(cached, stage .. "/package.zip")
    if not ok then return nil, why end
    ok, why = fs.write(stage .. "/pin.json", json.encode(pin))
    if not ok then return nil, why end
    return matches(stage .. "/package.zip", pin.archive_sha256)
  end)
end
return M
```

Save this driver as `reconstruct.lua`. For example, run
`kuu reconstruct.lua restore .cache/tool.zip .tools/tool tool-pin.json` or
`kuu reconstruct.lua backup .cache/tool.zip E:/project-backup/tool tool-pin.json`.
The backup destination must be a new directory on separately retained storage;
the tests use a separate disposable directory, not a simulated disk failure.
Restore from its `package.zip` with the maintained pin, comparing its saved
`pin.json` with the reviewed source. Rehash after any later transfer. Use ZIP
caches with this driver so the backup filename matches its format.
Successful byte reconstruction does not prove
that an application built with the tool is ready or that its runtime works.

```lua
global none
global <const> require, assert, io, tostring, print
local rt, fs, json = require "rt", require "fs", require "json"
local rebuild = require "restore_cached"
assert(#rt.args == 4, "usage: reconstruct.lua restore|backup CACHE DEST PIN")
local mode, cached, destination, pin_path = rt.args[1], rt.args[2], rt.args[3], rt.args[4]
assert(mode == "restore" or mode == "backup", "mode must be restore or backup")
local pin, parse_error = json.decode(assert(fs.read(pin_path, { maxbytes = "16K" })))
assert(pin ~= nil, parse_error)
local ok, primary, cleanup, stage = rebuild[mode](cached, destination, pin)
if cleanup then io.stderr:write("owned staging remains at ", stage, ": ", tostring(cleanup), "\n") end
assert(ok, primary)
print(json.encode { status = "verified", operation = mode, destination = fs.absolute(destination) })
```

Keep the primary error and any secondary cleanup error. Removal can make partial
progress; inspect the exact reported staging path before recovering it. The
recipe clears only readonly, preserving hidden and other flags; it does not
repair ACLs or modify the retained source archive. It does not provision or
download anything. A missing archive requires a separate deliberate decision
to restore a backup or fetch the already pinned upstream bytes.

<a id="kuu-page-reconstruction-an-upload-timed-out-reconcile-before-deciding-what-to-do"></a>

### An upload timed out: reconcile before deciding what to do

Save this module as `publish_asset.lua`. It is an executable project recipe with
an injected remote adapter, not a GitHub client. Its journal, local artifact and
scratch parent belong to one publisher: exclude all concurrent writers and
publishers. Keep the journal after failure; removing or rolling it back removes
the protection against a duplicate attempt. An atomic local write is not a
power-loss durability guarantee or a distributed lock.

The maintained `spec` contains `repository`, numeric `release_id`, `name`,
`size`, `sha256`, `file`, `journal` and `scratch`. Use a stable release ID, not
only a mutable tag. The adapter's three functions return `value` or `nil,error`:

- `lookup(spec)` returns one asset or `false` for confirmed absence. It must
  enumerate all pages for that release, reject duplicates, and never turn a
  failed or incomplete listing into absence. Assets contain `repository`,
  `release_id`, `name`, `id`, `size`, `sha256` and `state="uploaded"`; normalize
  a provider's `sha256:` digest prefix before returning it. A missing provider
  digest is unsupported confirmation; never fill it from the local pin.
- `upload(spec)` attempts once, without internal retries, and returns a result
  or an error. A timeout may mean the server accepted it.
- `download(asset, path)` fetches that exact asset ID into the new owned path,
  with a byte cap of `asset.size` and a finite timeout. It returns true or an error.

Bound each complete adapter call (for example 30 seconds), the number of listing
pages (for example 20), and each page's size. Pages and redirects share the call's
remaining deadline; they do not reset it. An exceeded limit is an error. This
module makes at most two lookups, one upload and one verification download per
invocation; it has no polling, delete, replacement or automatic upload retry.

```lua
global none
global <const> require, type, math, pcall
local fs, hash, json = require "fs", require "hash", require "json"
local err, ops = require "err", require "owned_ops"
local M = {}
local function fail(code, message, context) return nil, err.new("PROJECT", code, message, context) end
local function integer(value) return type(value) == "number" and math.type(value) == "integer" and value > 0 end
local function same(a, b)
  return a.repository == b.repository and a.release_id == b.release_id and a.name == b.name
    and a.size == b.size and a.sha256 == b.sha256
end
function M.reconcile(remote, spec)
  if type(spec) ~= "table" or type(spec.repository) ~= "string" or #spec.repository == 0
    or not integer(spec.release_id) or type(spec.name) ~= "string" or #spec.name == 0
    or not integer(spec.size) or type(spec.sha256) ~= "string" or #spec.sha256 ~= 64
    or not spec.sha256:match("^[0-9a-f]+$") then
    return fail("intent", "complete pinned asset identity required")
  end
  local info, why = fs.stat(spec.file, { follow = false })
  if not info then return nil, why end
  if info.kind ~= "file" or (info.attrs & 0x400) ~= 0 or info.size ~= spec.size then
    return fail("artifact", "local artifact kind or size differs")
  end
  local digest, hash_error = hash.file("sha256", spec.file)
  if not digest then return nil, hash_error end
  if digest ~= spec.sha256 then return fail("artifact", "local artifact digest differs") end
  local state = { schema = 1, repository = spec.repository, release_id = spec.release_id,
    name = spec.name, size = spec.size, sha256 = spec.sha256, attempted = false, confirmed = false }
  local bytes, read_error = fs.read(spec.journal, { maxbytes = "16K" })
  if bytes then
    local saved, parse_error = json.decode(bytes)
    if saved == nil then return nil, parse_error end
    if type(saved) ~= "table" or saved.schema ~= 1 or not same(saved, state)
      or type(saved.attempted) ~= "boolean" or type(saved.confirmed) ~= "boolean"
      or (saved.asset_id ~= nil and not integer(saved.asset_id))
      or (saved.confirmed and saved.asset_id == nil) then
      return fail("intent", "saved publication identity or state differs")
    end
    state = saved
  elseif not err.is(read_error, "FS", "notfound") then return nil, read_error end
  local function save() return fs.write(spec.journal, json.encode(state)) end
  local asset, lookup_error = remote.lookup(spec)
  local upload_error
  if asset == nil then return nil, lookup_error end
  if asset == false then
    if state.attempted or state.confirmed or state.asset_id then
      return fail("pending", "previous attempt is unresolved; retain journal and inspect the release")
    end
    state.attempted = true -- persist BEFORE allowing the only upload attempt
    local saved, save_error = save()
    if not saved then return nil, save_error end
    local called, uploaded, why_upload = pcall(remote.upload, spec)
    if not called then upload_error = uploaded
    elseif not uploaded then upload_error = why_upload end
    asset, lookup_error = remote.lookup(spec)
    if asset == nil or asset == false then
      return fail("pending", "upload outcome unresolved; do not retry or delete",
        { upload_error = upload_error, lookup_error = lookup_error })
    end
  end
  if type(asset) ~= "table" or not same(asset, spec) or asset.state ~= "uploaded" or not integer(asset.id)
    or (state.asset_id ~= nil and state.asset_id ~= asset.id) then
    return fail("conflict", "remote asset identity, state, size or digest differs", { upload_error = upload_error })
  end
  state.asset_id = asset.id
  local saved, save_error = save()
  if not saved then return nil, save_error end
  local stage, stage_error = fs.tempdir { dir = spec.scratch, prefix = ".verify-asset-" }
  if not stage then return nil, stage_error end
  local path = stage .. "/asset.bin"
  local called, ok, primary = pcall(function()
    local downloaded_ok, download_error = remote.download(asset, path)
    if not downloaded_ok then return nil, download_error end
    local downloaded, inspect_error = fs.stat(path, { follow = false })
    if not downloaded then return nil, inspect_error end
    if downloaded.kind ~= "file" or (downloaded.attrs & 0x400) ~= 0 or downloaded.size ~= spec.size then
      return fail("download", "downloaded asset kind or size differs")
    end
    local actual, verify_error = hash.file("sha256", path)
    if not actual then return nil, verify_error end
    if actual ~= spec.sha256 then return fail("download", "downloaded asset digest differs") end
    return true
  end)
  if not called then primary, ok = ok, nil end
  local removed, cleanup = ops.remove_owned(stage, 0.5)
  if removed then cleanup = nil end
  if not ok then return nil, primary, cleanup, stage end
  if cleanup then return nil, err.new("PROJECT", "cleanup", "verified download cleanup failed"), cleanup, stage end
  state.confirmed = true
  saved, save_error = save()
  if not saved then return nil, save_error end
  return { status = "confirmed", asset_id = asset.id, size = spec.size, sha256 = spec.sha256 }
end
return M
```

Retain the primary diagnostic and any cleanup error returned by `reconcile`.
Unresolved post-upload errors also retain `upload_error` and `lookup_error`
when available; inspect those Lua fields when reporting the failure.
An upload's immediate response is deliberately insufficient evidence of success
or failure; a verified remote object resolves even a lost response. Re-running
with the same journal performs inspection and download verification, without
uploading again. A previously confirmed asset is reverified, never deleted.
The journal's `confirmed` flag records a past successful observation; only the
current invocation's return establishes its latest verification result.
If an attempted asset stays absent, investigate before making a new, explicitly
reviewed publication decision. Tests simulate timeout after acceptance, missing
assets, conflicts, corrupt downloads and cleanup failure; they make no live
release or network changes.

GitHub returns asset IDs, state, size and digest. Download endpoints can redirect;
handle that according to the API, preserving normal certificate validation.
A failed upload can leave a `starter` asset; this recipe reports it for review
and does not delete it. Choose a provider-stable filename: GitHub can rename
special characters, which would fail this recipe's exact-name check. See the
[release assets API](https://docs.github.com/en/rest/releases/assets).

For public API failures, distinguish anonymous rate limits from missing assets:
use the documented status and rate-limit headers, authenticated requests where
appropriate, and `Retry-After`/reset timing. A throttled or truncated asset list
cannot prove absence. See [GitHub rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

For `HTTP tls`, preserve the native WinHTTP code. Client-certificate private-key
absence and lack of access to that key require different certificate/account
repairs; neither calls for disabling TLS verification. Inspect the Windows
certificate configuration and the account running the request, using
[WinHTTP errors](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages)
and [WinHTTP SSL guidance](https://learn.microsoft.com/en-us/windows/win32/winhttp/ssl-in-winhttp).

---

<a id="kuu-page-inheritance"></a>

<a id="kuu-page-inheritance-inheritance"></a>

## Inheritance

What kuu carries over from machteld, the z estate, the els method, and the
archived and adjacent projects, harvested on 2026-09-09 from their sources,
retrospectives, and commit histories. Each item is a law kuu keeps, a trap it
must not fall into again, or a contract it copies. The source is named so the
reasoning can be reread. This is the register the roadmap's "learn every
lesson" instruction produces; add to it, never silently edit it.

<a id="kuu-page-inheritance-laws"></a>

### Laws

- **Lua orchestrates; C only for what Lua cannot reach.** Every serious bug in
  the estate's C was a lifetime or bounds bug the script layer structurally
  cannot have. (els method §1)
- **Fail closed; refuse rather than approximate.** A confident wrong artefact
  is worse than a refusal that names what is missing. Whatever subset ships
  is stated exactly, and the rest is refused by name. (els method §11)
- **Nothing goes missing without a counted cause.** A walk, a watch, a
  capture never presents a silent partial result: every omitted branch,
  dropped event, or truncated stream is accounted for in the result.
  (machteld `dirs.c` header; watch `dropped`; `run` `truncated`)
- **Fact and decision are separate keys.** Report what was observed and what
  was done about it as two fields, so a reader can see them disagree.
  (`dirs.c` `surrogate` versus `action`)
- **Strict text at every boundary.** No U+FFFD, no best fit, no ANSI by
  default: a name that cannot be represented is refused, never renamed.
  Windows tools emit the system code page; decode deliberately.
  (`wintext.h`; els method §10 trap 14)
- **Expected outcomes are data.** Timeout, killed, truncated, unknown are
  result states beside the answer, never exceptions and never disguised as
  the answer. Programming mistakes raise. (`proc` result shape; machteld
  research §7, §12)
- **The no-orphans law.** Every child has a decided lifetime and dies with
  the runtime unless detached on purpose; detaching is not a lifetime policy.
  (els method §16; the spac incident of 2026-08-16)
- **An upstream library's vocabulary never becomes the contract.** yyjson,
  SQLite, WinHTTP names stop at the module boundary. (ecosystem policy)
- **The manifest is authored, never inferred.** What kuu advertises about
  itself comes from declarations, not from scanning implementation text.
- **Write the why into the code.** Every load-bearing strangeness carries the
  failure it prevents, so the next reader can tell it from style.
- **Measure honestly.** Register predictions before measuring; a band tighter
  than the noise floor is unfalsifiable; interleave comparisons; a cold file
  cache produced a tenfold wrong number five separate times. (els method §11;
  reken)
- **Verification enumerates from the other side.** A test that iterates your
  own list is blind to what is missing; a 273-of-273 gate hid four missing
  tools for a month.
- **Build the hostile fixture first.** The real junction, dangling link,
  hidden directory, or locked file exposes what self-review never does.

<a id="kuu-page-inheritance-windows-traps-kuus-c-obeys"></a>

### Windows traps kuu's C obeys

Paths and the file system (`fs`):

- Apply `\\?\` only after `GetFullPathNameW`; recognise the prefix before and
  after normalisation, because `//?/C:/x` normalises into a form the UNC test
  misreads. Without the prefix seven directories at 278 to 424 characters
  vanished from a walk with a clean exit.
- Under `\\?\` a doubled separator is a real empty component. `\\?\UNC\` is
  eight characters standing in for two. A drive root keeps its trailing
  backslash: `\\?\C:` is the device.
- A component ending in `.` or a space is silently rewritten by
  normalisation and can name a different directory; refuse it by name.
- `GetFullPathNameW` returns the needed size and writes nothing when the
  buffer is too small; treat `got >= need` as failure.
- Enumerate with `FILE_ID_BOTH_DIR_INFO`; the restart class returns the first
  batch and is not a seek, so the loop is do-while. Grow the buffer on both
  `ERROR_MORE_DATA` and `ERROR_NOT_ENOUGH_MEMORY`; a 64-byte probe returns the
  latter. Names are not NUL-terminated. The reparse tag in `EaSize` is only
  meaningful when the reparse attribute is set.
- Sort siblings yourself, unsigned, in UTF-8: NTFS order is a case-insensitive
  collation disjoint from byte order, and a signed compare puts every
  non-ASCII name before `a`.
- A directory handle needs `FILE_LIST_DIRECTORY` with backup semantics; open
  reparse points raw (`FILE_FLAG_OPEN_REPARSE_POINT`) or a junction hands you
  its target's contents. Reclassify on the handle immediately before descent;
  the handle may veto but never authorise. The root is exempt: you named it,
  you get it.
- The name-surrogate bit is `0x20000000`; DFS and DFSR redirect without it;
  cloud placeholders are content behind a filter. A dangling link is its own
  error, distinct from not found: a resolver may pass a missing component
  but must stop at an existing broken link.
- The reparse payload's offsets are relative to `PathBuffer`, not the struct,
  and the fixed part must be checked per arm before it is read; one wrong
  constant was a heap over-read with a working proof of concept.
- Identity is the volume serial plus the 64-bit file index, compared as
  opaque tokens; `dev` from a portable stat is the drive letter index, and
  existence predicates answer true for a dangling junction.
- `CloseHandle` clobbers `GetLastError`. A double close is a process that
  stops, not an error you catch: null the handle the moment another owner
  takes it.
- Never delete through a junction: removing a tree opens every directory raw
  and removes a link as a link.

Processes (`proc`), inherited and already applied:

- Born-in-job through `PROC_THREAD_ATTRIBUTE_JOB_LIST`; one `LimitFlags`
  write is authoritative, so re-assert kill-on-close whenever a limit is set;
  duplicate each distinct standard handle once and restrict inheritance to
  the list; resolve `cmd.exe` from your own environment, never the child's.
- `cmd.exe` re-parses its `/c` argument; batch files run through a
  defensively quoted `cmd.exe` (CVE-2024-24576). Environment blocks are
  sorted with `CompareStringOrdinal`, case-insensitively.
- Start output drains before feeding stdin, or two full pipes deadlock. A
  child completes when its whole job is empty, not when its process exits.
- ConPTY, for later: a parent with redirected standard handles poisons the
  child unless `STARTF_USESTDHANDLES` is set with explicit nulls; teardown
  must drain the output pipe on a thread while `ClosePseudoConsole` runs.

Watching (`fs.watch`):

- Arm the first `ReadDirectoryChangesW` before returning; until it is issued
  the OS records nothing. Zero bytes returned means overflow: disclose it as
  an event with a count. Validate name length parity and next-entry offsets
  on every record. Cancel, then reap the completion before freeing the
  buffer. Coalesce by precedence removed, added, renamed, modified, from
  observations, never last-wins. A watch is a trigger; on overflow the caller
  reconciles from a fresh scan. (machteld `proc.c`; drenn)

Text, JSON, hashing, HTTP:

- `MultiByteToWideChar` substitutes U+FFFD and reports success without
  `MB_ERR_INVALID_CHARS`; NTFS accepts names with unpaired surrogates and a
  lenient conversion collapses two siblings into one.
- Duplicate object keys are refused, with detection that is pairwise below
  sixteen members and sort-based above, comparing by length and bytes; a
  quadratic scan turned a 16 MiB object into minutes. Depth is capped at 512
  independently of the parser. Build an error message before freeing the
  document it points into. An unpaired surrogate escape is a parse error.
  Never route a 64-bit integer through a double: one study's int64 test
  vectors were silently corrupted that way.
- Digest a file in 64 KiB chunks; algorithms are a table of values so the
  list the binary reports is the list it has.
- Do not write TLS; WinHTTP is serviced by Windows Update. Crack URLs with
  the OS parser. Zero timeout means infinite to WinHTTP, so refuse it. Set
  both the receive and the receive-response timeouts. Keep raw headers
  beside cooked ones because `Set-Cookie` repeats. Redirect `none` means zero
  further requests. No insecure flag of any kind. A short body that looks
  whole is the one answer never given.

Host and build:

- `_CRT_glob = 0`: the mingw runtime otherwise expands a literal `*.lua`.
- Compile Lua as C. Foreign threads allocate with the C runtime, never
  through the interpreter's allocator. A count hook never fires inside a C
  call, so an in-process budget cannot stop a C loop; only a process boundary
  can.
- Stage what version control tracks, place artefacts by atomic rename, link
  with `--no-insert-timestamp` and a fixed source date, and demand a
  byte-identical rebuild before signing. Sign the final executable, not the
  interpreter it came from.

<a id="kuu-page-inheritance-contracts-kuu-copies"></a>

### Contracts kuu copies

- Durations and sizes carry units; a bare number is seconds or bytes, never
  a guess. `0xFFFFFFFF` is `INFINITE`, not a duration.
- Options take one shape, a table; unknown option names raise.
- Handles are opaque, never reconstructed from a pid, closed explicitly or
  by `<close>`, and refuse use after close.
- `dirs` returns `root`, ordered `paths`, counts, `links` decisions, `errors`
  rows with the raw Win32 code and the system's message; `-depth` omitted is
  unlimited and zero is the root alone; prune patterns match base names.
- `canon` returns path, volume, file, kind, links, with `dangling` as its own
  code. `watch` events are relative paths with forward slashes.
- `log`: levels debug, info, warn, error, off; default info; sink resolved at
  write time; a write failure never raises, it counts as dropped; validate
  the whole configuration before committing any of it; an odd trailing field
  renders as `key=?`.
- `cli`: a spec is a table with a closed attribute set; parsing never prints
  or exits; `--help` is a returned value; a wrong spec is `badvalue`, a wrong
  command line is `usage`; validate the spec eagerly; `--help` waives missing
  required values only.
- JSON on the command line uses one envelope: `{ok true result}` or
  `{ok false error {domain code message}}`. Structured output by default
  for agents, human text as the development aid.
- The manual ships inside the executable at the exact version, with list,
  get, and search that never touch the network. Error messages are greppable
  in the manual. Every example in the manual is executed by a test.

<a id="kuu-page-inheritance-task-runners-and-locks-for-03"></a>

### Task runners and locks, for 0.3

- Five task runners in the estate shared no library; the same converter and
  the same discovery block were copied three to five times and drifted.
  Provide once: script root, tool discovery, streaming exec with exit-code
  passthrough, capturing exec, tool preflight, atomic place, task lock, the
  dispatcher.
- The task list must live in one place; two-file declarations drifted in
  every project that had them. Tasks need a description, dependencies run
  once, a declared argument spec, `list`, `--json`, timing, and consistent
  exit codes: child code passed through, 1 for failure, 2 for usage.
- A lock must be prescriptive: URL, file, SHA-256, size, license, and how to
  unpack and verify, plus patches pinned by before-and-after hashes and
  license notices pinned at source and destination. z's ledger described what
  was on disk and could restore nothing; downloads matched by fuzzy filename
  were a regret in waiting.
- Hydrate and verify are one code path with a flag. Download to `.partial`,
  hash, then rename; re-hash cached downloads and heal; unpack into a
  temporary directory and rename whole; write stamps last; the stamp is a
  hash of the inputs, including the hydrating code itself; every write stays
  under the cache root; cross-check a tool's reported version against the
  lock.
- A `z env --json` that shows the final argv and environment without running
  anything was the most useful verb agents had. Bare invocation from a pipe
  gets help, never an interactive shell.

<a id="kuu-page-inheritance-what-the-estates-agents-got-wrong"></a>

### What the estate's agents got wrong

- Under strict globals, declaring any `global` switches the chunk into
  declared-only mode and `print` itself then needs a declaration; the luax
  manual shipped it as trap eight rather than fixing it. kuu documents the
  mode, and recommends `global none` with an explicit standard list.
- Deep recursion on large inputs was the only failure class in one study;
  document limits and the iterative idiom.
- A checker that runs two of three passes is not a gate: three constructs
  typed clean and failed to compile. `check` must run every pass it claims.
- Studies with easy corpora cannot measure a feedback-loop benefit; build the
  discriminating corpus before the instrument.
- Lua's thin string library made string-heavy tasks slower than Python's C
  builtins; `text` and `json` are C for that reason.

---

<a id="kuu-page-roadmap"></a>

<a id="kuu-page-roadmap-roadmap"></a>

## Roadmap

kuu began on 2026-09-09 as the successor to machteld, the Tcl runtime for
agents, after the owner concluded that estate-wide management had to stop and
that each project should stand alone with its own tools. The name was reused
from an earlier, archived attempt to reimplement Lua 5.5 in Go; the new kuu
embeds PUC Lua instead. This page records the decisions and the milestones.

<a id="kuu-page-roadmap-decisions"></a>

### Decisions

| decision | choice | why |
|---|---|---|
| platform | Windows 11 23H2 and later; Windows Server 2025 and later | native Windows APIs; 23H2 console teardown uses isolated close/drain workers and completion-aware pipe ownership |
| language for programs | Lua 5.5.1, vendored, compiled as C | agents write it correctly from a hundred-page manual; coroutines make waiting read as straight-line code; `global none` turns the classic typo into a compile error; errors are `longjmp`, so C, never C++ |
| a language of kuu's own | none, by owner decision on 2026-09-11: no successor language, no compiler, no emission subset | kuu is a runtime for Lua 5.5 and grows capabilities in the palette and options on the calls already there; existing technology is recombined, not syntax invented |
| a mandated runtime | none. No JavaScript, Go, Tcl or other runtime is shipped, fetched by kuu, mandated, or recommended; kuu is never extended, a project is, and `.kuu/` never holds anything that runs | decided 2026-09-13. A design for a downloaded, pinned JavaScript runtime was recorded on 2026-09-12 and set aside the next day; the note stands as the record of what was considered and measured. The problem it answered — the palette grows only through C — is answered by the front door instead: a project builds the tool it needs and calls it through `kuu.exe`, and the manual says what a confined tool must provide without naming what to write it in |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.2.0-3 from MSYS2 UCRT64, unpacked into `.tools` from 18 archives pinned by SHA-256 and retained | the estate's proven recipe; gcc and GNU make are the chosen production build, with Clang only for sanitizer tests. Pinned on 2026-09-13, when the 16.1 tree that built everything before turned out to be a copy of a live install whose packages the mirror no longer served; the record is the table in [toolchain](#kuu-page-toolchain), the check is `certutil`, and no tool in the repository fetches or verifies it |
| build | GNU make from the same `.tools`, recipes under `cmd.exe` | no PowerShell in the repository, and kuu never builds kuu: the build is make and gcc, the tests are Lua run by the built kuu |
| self-hosting | none, by owner decision | kuu is not required to bootstrap or build itself; a person with `.tools` populated runs `make` |
| versions | `N.N`, two nonnegative integers, from 0.11 | the owner chose release numbers without semantic-version compatibility categories; compare components numerically, so 0.11 follows 0.10. `rt.version_at_least` compares them without parsing text. The earlier 0.9.0 and 0.10.0 names remain historical; contract changes and explicit interface commitments live in the upgrading and stability pages |
| dependency pinning | none: a project fetches what it needs by url and hash with `http` and `archive`; kuu's own compiler is obtained by hand from archives pinned by hash and retained, never fetched by kuu | the lock built in 0.3 was removed in 0.4 as formalism; kuu does not bootstrap itself |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has only stock Lua's `io` and `os`, and a static check can list what else a file asks for. It gates a program that does not reach around it: `_ENV` is an upvalue, needs no declaration, and reaches `load` and the whole palette from a file `check` reports with `"requires":[]` and a clean bill ([shortcomings](#kuu-page-shortcomings)) |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child is born into a kill-on-close job; only `detach`, and a child's own deliberate breakaway, step outside it |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, Tcl in the runtime, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs. Any of them may be a project's tool, fetched by hash into its own root and called through the door; none is recommended, and none enters the palette unless it cannot be a tool |
| projects share nothing | every project carries its own `kuu.exe`, copied in by hand, directly in its root since 0.6 (0.4 and 0.5 put it in `.tools`); nothing on `PATH`, no machine changes, no bootstrap scripts | the owner ended estate-wide management; a small executable is copied, not fetched by glue |
| what a project may fetch | upstream downloads only, into its own `.tools`; nothing re-hosted, nothing shared between projects | no commonalities, and a stranger fetches from the same public sources. kuu itself fetches nothing, ever; `.kuu/` holds only kuu's own state, the notebook and the ledger |
| a project's tools | whatever a project builds or fetches into its own root, in any technology, declared in its manifest with the arguments it takes and the shape it emits, and called through the door | there are exactly two kinds of thing a program can reach: the palette, kuu's, described by `_palette` and gated by `require`; and the project's tools, the project's, declared in `manifest.lua`. There is no third kind; a tool that wants to read like a module is wrapped by an ordinary project module |
| the project's declaration file | `manifest.lua` at the root: prerequisites by hash, tasks, and `tool` declarations, in one file; `tasks.lua` remains a deprecated fallback with a warning and no scheduled removal | decided 2026-09-13; one authored file, read two ways from one source — executed by `run`, `list` and `capabilities`, read as literals by `check`, held equal by the suite. The earlier planned removal in 0.11 was withdrawn |
| kuu's own repository | free of kuu: build and release are make, gcc, and cmd recipes; no `manifest.lua` there | self-reference is unwelcome, for release steps too |
| releases | anafalanx/kuu public; GitHub Releases carry `kuu.exe` and its `.sha256`; signed with the owner's existing Certum certificate through the Windows SDK's signtool | the estate already signs this way, and public releases need no credentials to fetch |
| the second project | `C:\dev\kuu-test-project`, local, no remote, tailored to test kuu features | a project built to exercise the runtime, before any existing one is converted |
| what kuu is | the front door of a project: everything that *runs* in a project runs through `kuu.exe` — a task, a build, a test, a tool, a fetch — and gets a job, a deadline, limits, tree-kill on the door's death, a record, and where the door can read it, a check. Writing code is not a crossing; what an agent writes becomes the door's business the moment it first runs, and `check` stands at that threshold | decided 2026-09-13, after the review of 2026-09-12 ([plan](notes/plan-front-door-2026-09-13_001735.md)). The door is the only part that must last fifteen years, so it is Lua on C, small, built with great care, and it stops growing; what a project needs beyond it is a tool the project builds, in any technology, and calls through the door. The earlier row — a power tool in the agent's hand that removes the fumbling, not the knowing — stands as the description of the palette |
| dependencies | no lock: verification is a capability (`http.get` with `sha256`, `fs.unpack`), and the agent writes its own setup | the lock was formalism for a shared-payload world that no longer exists |
| memory across runs | `mem`, a small JSON notebook per project, Lua only, capped at 1 MiB | agents need to remember between runs; the executable stays nimble; SQLite stays out |
| execution history | record tasks, child processes and runs; no automatic filesystem-change tracking | owner decision after large-project acceptance measurements: source-tree snapshots and comparisons made trivial runs scale with maintained file count. Remove that responsibility instead of adding a watcher, journal or index. Checking, module inventory, safe traversal, scan exclusions and explicit `fs.watch` remain useful capabilities |

<a id="kuu-page-roadmap-inventory"></a>

### Inventory

| organ | status |
|---|---|
| entry routes: file, stdin, inline; `--version`, `--help` | 0.1 |
| selective standard library, hazards removed, text-only `load`, rooted `require`, `rt` | 0.1 |
| event loop on one completion port; `sched` (spawn, join, sleep, clock, now) | 0.2 |
| `proc` (run, start, wait, kill, close, detach, alive, kill by pid) under Job Objects, overlapped pipes, no threads | 0.2 |
| `err`, durations and sizes with units, UTF-8 `io.open` and `os.getenv` | 0.2 |
| `fs` (read, atomic write, stat, exists, mkdir, remove, rename, copy, list, dirs, canon, same, link, watch, cwd, temp, absolute) | 0.2 |
| `json` on yyjson, `hash` on CNG, `text`, `log`, `cli` | 0.2 |
| the manual and kuu's own Lua inside the executable; `kuu docs [page | search]` | 0.2 |
| live child streams with backpressure (`read`, `read_err`, `lines`, `write`, `close_stdin`), `inherit = true`, `proc.wait_any`, `proc.wait_all` | 0.2 |
| `http` on WinHTTP: get, post, request, streaming to a file, a wall-clock deadline of kuu's own | 0.3 |
| `toolchain` hydrate/verify/path from a prescriptive lock; `kuu hydrate`, `kuu verify` | 0.3, removed in 0.4 |
| `task`, `tasks.lua`, `kuu run`, `kuu list`, their `--json` reports; `fs.chdir`, `rt.root`, `rt.source` | 0.3 |
| `kuu check`: parse, global declarations, `require` resolution, without running; no arity checking, by design | 0.3 |
| verification as a capability: `http.get { to, sha256 }`, `fs.unpack`, `fs.pack` over the tar.exe Windows ships | 0.4 |
| `fs.glob`, `fs.join`, `fs.dirname`, `fs.basename`, `fs.ext`, `fs.relative`, `fs.tempfile`, `fs.tempdir`, `fs.space` | 0.4 |
| `sys.info`; `hash.uuid`; `text.base64`, `text.hex`, `text.upper`, `text.lower`; `mem`, a small JSON notebook per project; `sync`, a named lock across processes | 0.4 |
| `kuu run --dry-run`; a crash handler so kuu never dies silently; soak and stress tests on demand | 0.4 |
| the from-PowerShell page of the manual: each cmdlet an agent reaches for, and the kuu call | 0.4 onward |
| a version resource, Certum signing, a GitHub Release, by make; `kuu-test-project` under the released kuu | 0.4 |
| `re` on PCRE2; `time`; `debug.traceback` and `debug.getinfo` only; `csv`, `ini`; the adopting page of the manual | 0.5 |
| `reg`; `env`: the live environment and the persisted one, with the change broadcast | 0.5 |
| `proc.list`, `proc.find`, `proc.tree`; `net.probe`, `net.listeners`, `net.resolve`, `net.addresses` | 0.5 |
| `worker` processes; `serve` | deferred to 1.1; prototyped on the 0.9.0 surface, which reached 2.74x on sixteen CPU-bound jobs using only `sched.spawn`/`join` and a streaming `proc` child, so nothing in the freeze has to move for it |
| review fixes, dependency-only tasks, duration units, Unicode archives, TLS diagnostics, process path consistency; analysis and parser fuzz gates | 0.6 |
| job-wide `proc` limits on memory, user CPU time, and active processes; result `status = "limit"` with its kind | 0.7 |
| `sched.deadline` across waits; `task.defaults { timeout = ... }`; `task.exec` leaves the caller's options table untouched | 0.7 |
| `svc` for service state and transitions; `evt` for bounded event-log queries; `sys.signature` for embedded Authenticode trust and identity | 0.7 |
| `check` verifies palette export names through local aliases and lexical scopes, with suggestions and JSON finding kinds | 0.7 |
| `pty` over ConPTY with `expect`, a plain-text view, and supervised child lifetime; provisional, outside the future freeze | 0.7 |
| ten executable cookbook programs; public stability statement and minimum-version guards; complete module map and JSON schemas | 0.7 |
| `make gate`: suite, analysis, expanded parser fuzzing, soak; separate pinned Clang AddressSanitizer build required for release | 0.7 |
| Windows 11 23H2 support with safe console shutdown; JSON duplicate-key diagnostic lifetime fix; unchanged Lua API | 0.8 |
| `Major.Minor.Patch` versions and `rt.version_at_least`, replacing the pattern guard the third component breaks | 0.9.0 |
| `fs.write` retries its rename over the target on transient sharing failures, closing the `FS access` finding open since 0.5 | 0.9.0 |
| `fs.dirs` reports a pruned directory in `skipped` instead of `paths`, so the plain walk reads nothing the prune excluded | 0.9.0 |
| `json.object`, an ordered object beside `json.array`, for documents compared byte for byte | 0.9.0 |
| `sched.clock` on the performance counter: 1 ms resolution becomes about 500 ns | 0.9.0 |
| `svc`, `evt`, `sys.signature` become provisional, outside the planned freeze until a project has driven them | 0.9.0 |
| `check` reads `_palette`, an authored description of kuu's interface: an error code its domain lacks, an option a call does not take, a closed set compared with a non-member, `rt.version` compared by text; through a local binding or a module indexed where it is required | 0.10.0 |
| `check` reads a project's own modules from their text, so its exports are checked too; an export set the text cannot bound goes unchecked rather than guessed. `check.exports`, `check.modules` | 0.10.0 |
| `kuu check --fix [--adopt]`: the global declaration written in both directions, the Lua compiler as the authority, and a refusal to declare a name this runtime lacks | 0.10.0 |
| `kuu capabilities [--json]`: the verbs, the public modules and their names, the error domains and closed sets, and this project's tasks and modules; `rt.verbs`, `rt.pages` | 0.10.0 |
| `text.trim`, native, replacing a helper hand-rolled six times; the unanchored `$` out of every hot path in `lua/` and `tools/`; `check` lexes by byte | 0.10.0 |
| `kuu.md`: what kuu is, what its predecessors taught, and the whole manual inlined by `tools/bundle_docs.lua`, held to `docs/` by the suite | 0.10.0 |
| `manifest.lua` as the declaration file, with a warned `tasks.lua` fallback that remains supported; tools declared beside tasks with `task.tool` and called with `task.exec { tool = }`, read by `check` as literals and held to; the ledger under `.kuu/ledger`, chained, with the tree delta and the repository's head; `kuu run --json` as a stream | 0.10.0 |
| execution-history ledger records v2; removal of automatic tree snapshots and deltas, with immutable v1 history still readable | 0.12; see [migration note](#kuu-page-upgrading-from-011) |
| `fs.attributes` and `fs.set_attributes`; readonly-directory removal; safe shared inspection with declarative exclusions; literal declaration validation and consistent task help | 0.12; see [migration note](#kuu-page-upgrading-from-011) |
| tested project recipes for process outcomes, cwd, shared environments, relocation, private GUI verification, native helpers, verified reconstruction and uncertain publication | 0.12; [manual map](#kuu-page-index-pages) |
| `kuu docs agent`, what is expected of an agent and the `kuu-eval.md` report back, named by every entry point and counted by `capabilities`; `docs` a verb like the others with sections, descriptions, search and `--json`; `rt.page` | 0.10.0 |
| every verb points onward: a manifest that declares nothing, a misspelt verb, an unknown task with the nearest name, no project, a first `.kuu/` not ignored, the 0.8 version guard found by `check`; `notes` on the JSON envelopes; `kuu run TASK --help` exits 0; `TASK failed` carries `status` and `limit` | 0.10.0 |
| deferred: elevated runs, `xml`, ACLs, clipboard, ICMP, scheduled tasks as a module, `kuu run --watch`, credentials and certificates, CI | later, on a real need |
| no-go: `tools.get`, `proc.shell`, YAML, templating, `text.diff`, shortcuts, Windows features, firewall, Defender, power, `kuu init`, bootstrap scripts | decided 2026-09-09 |

The Win32 surface, counted on 2026-09-13 from the host objects' undefined
symbols (`make surface`, which runs `tools/surface.lua`): 180 functions
imported by name; four resolved with `GetProcAddress` at run time —
`NtQueryInformationProcess`, `RtlGetVersion`, `ReleasePseudoConsole`,
`GetAddrInfoExCancel`; and seven entry points of `archiveint.dll`, loaded
from System32 only while `archive.list` runs. 191 names is what "small"
means here, and the number is meant to go down, not up: a module that would
add to it is a tool the project builds, called through the door.

<a id="kuu-page-roadmap-milestones"></a>

### Milestones

The milestones below record each release's behavior. 0.12 follows the
execution-history decision above: the tree-delta behavior introduced in 0.10
is removed, while existing history is preserved.

1. **0.1, the runner.** Routes, decoding, the state, `rt`, errors and exit
   codes, the entry test suite. Done 2026-09-09.
2. **0.2, the palette core.** The loop and scheduler, `proc`, `fs`, `text`,
   `json`, `hash`, `log`, `cli`, `err`, with hostile fixtures: orphans,
   timeouts, NUL bytes, invalid UTF-8, dozens of children, junctions inside,
   outside, looped, and dangling, paths beyond 260 characters. Done
   2026-09-09 with 322 checks. Output callbacks were considered and dropped:
   a task reading a stream is the same thing without a second calling
   convention.
3. **0.3, the repository runtime.** `http`, hydrate and verify from a lock,
   tasks, `check`, `docs`. `http` landed 2026-09-09 with a deadline of kuu's
   own, after measuring that WinHTTP's receive timers never fire against a
   server that accepts and stays silent. The lock and the tasks landed the
   same day: hydrate and verify are one pass, stamps are keyed on the lock
   entry and the hydrating code, `kuu run` passes a child's exit code
   through. `check` parses, wants a global declaration, and resolves every
   `require`; palette arity checking was dropped, because a checker that
   promises more than it runs is not a gate. The suite drives a synthetic
   project end to end. Done 2026-09-09: the finish line was met by a worked
   example that pinned a compiler by hash, hydrated it, built one C file with
   it, and tested the result. It was retired the same day, at the owner's
   request, in favour of `kuu-test-project`.
4. **0.4, the tool in the hand, and the first release.** Decided with the
   owner on 2026-09-09, after the whole feasible surface was laid out and
   given a go, a defer, or a no-go; the inventory above records them.
   - The lock goes. `toolchain`, `tools/lock.json`, `kuu hydrate`, and
     `kuu verify` are removed with their tests; `http.get` learns `sha256`
     for a file it writes, refusing and deleting on a mismatch, and `fs`
     learns `unpack` and `pack` over the tar.exe Windows ships. The manual
     shows the ten lines a project writes to fetch, verify, and unpack a
     prerequisite. The test project found the lock's next demand on its
     first day, MSYS2's `make` needing two sibling packages, and that demand
     is now a loop in a `tasks.lua`, which is what it always was.
   - The small things every setup reaches for: `fs.glob`, path helpers,
     temporary files, free space, `sys.info`, `hash.uuid`, base64 and hex.
   - `mem`: a small JSON notebook per project, so an agent remembers between
     runs. Lua only, atomic writes, 1 MiB at most.
   - `kuu run --dry-run`: the plan, in order, without running it.
   - Like a watch: a structured exception handler so kuu never dies
     silently, and soak and stress tests, run on demand, that the
     thirteen-second suite cannot afford.
   - The from-PowerShell page: each cmdlet an agent reaches for, and the kuu
     call that replaces it. It grows with every milestone and is the product
     statement in one page.
   - The release, by make and cmd recipes in kuu's own repository, which
     stays free of kuu: a version resource from `windres` so the file's
     properties say what `--version` says; Authenticode signing with the
     owner's Certum certificate through the Windows SDK's signtool, verified
     after signing against the pinned leaf certificate and a timestamp, the
     discipline els already has in Tcl; `kuu.exe` and its `.sha256`
     published as a GitHub Release of the public repository. Done when
     `kuu-test-project` runs its tasks end to end under the released
     `kuu.exe` copied into its `.tools` (the root became the place in 0.6).
   - Done 2026-09-09, the same day it was decided. 509 checks. The soak test
     found a handle leak on its first run and a standalone probe traced it
     to WinHTTP itself, one handle per session opened and closed; kuu now
     holds one session per process and a 45 second soak stays flat on
     handles and memory. `kuu.exe` carries its version resource, is signed
     by thumbprint and timestamped, verified, hashed, and published as the
     0.4 release; `kuu-test-project` fetches make and its two runtime
     packages by hash with `http` and `archive`, counts its runs in `mem`,
     and runs its tasks under the released kuu.
5. **0.5, the language, the machine, the network.** `re` on PCRE2, because
   the ledger says Lua patterns may prove decisive; `time` with zones and
   ISO 8601; `debug.traceback` and `debug.getinfo` and nothing else of that
   library; `csv` and `ini`; `reg` with typed values; `env`, the live
   environment and the persisted one with the change broadcast;
   `proc.list`, `proc.find`, `proc.tree`; `net.resolve`, `net.probe`,
   `net.listeners`, `net.addresses`, none of them blocking the loop; the
   manual page on adopting kuu in a repository.
   - Done 2026-09-09. 729 checks. `pty` with `expect` moved to 0.6, to be
     shaped by the first real repository driven with kuu rather than
     guessed at. Found on the way: a refused TCP connect takes two seconds
     on Windows, loopback included, so a probe given less reports timeout
     instead of refused (recorded in net.md); `GetAddrInfoExCancel` is
     missing from the MinGW header and is resolved at run time; a megabyte
     `gsub` took a minute until PCRE2 was told the subject was already
     checked as UTF-8.
6. **0.6, hardening through a real repository.** Time Actual now carries
   `kuu.exe` directly in its root and uses project-owned recipes and tools
   for setup, build, tests, and process control. The twelve 0.5 review fixes
   and the defects observed during that adoption define this release:
   dependency-only tasks, the `version` command, consistent duration units,
   Unicode archive listing and ZIP creation, process path consistency, and
   actionable TLS diagnostics. GCC analysis and deterministic parser fuzzing
   supplement the regression suite. See the [migration notes](#kuu-page-upgrading-06)
   and [observations log](#kuu-page-shortcomings). Released 2026-09-10, after the cold
   setup and recovery run of Time Actual on a second machine.
   - The earlier console/control plan is deferred. `pty`, `svc`, `evt`,
     `worker`, `serve`, and export-aware `check` are not implemented in 0.6.
     Add capabilities when a consuming project demonstrates the need.
   - Clean setup and recovery were then run end to end on a second machine:
     two cold setups, twelve fault-injection and relocation steps, and the
     complete test task from a path with spaces, all passing. One external
     limitation surfaced: Tcl/Tk will not rebuild from a path with spaces.
     Recorded in the observations log.
7. **0.7, the last capabilities before the freeze.** Implemented from the
   2026-09-10 handoff. Children can be bounded by committed memory, user CPU
   time, and process count; their result identifies a breached limit.
   `sched.deadline` bounds a scope's waits and composes with nested deadlines;
   `task.defaults` sets the default timeout of `task.exec`. `svc` controls
   Windows services, `evt` reads bounded event snapshots, and `sys.signature`
   verifies embedded Authenticode trust and certificate identity. The checker
   follows direct local require bindings through lexical scopes and catches
   unknown exports without running project code. `pty` drives console prompts
   through ConPTY and stays provisional.
   - The [cookbook](#kuu-page-cookbook) gives ten complete programs, extracted and
     checked by the suite and exercised with safe fixtures. The
     [stability statement](#kuu-page-stability) names the future 1.x contract and
     replaces exact-version guards with numeric minimums. The module pages,
     PowerShell map, error-code sets, and JSON schemas are documented together;
     [upgrading to 0.7](#kuu-page-upgrading-07) records the changes from 0.6.
   - `make gate` combines the suite, GCC analysis, deterministic fuzzing, and
     soak. The parser corpus now includes CSV, INI decode and edits, JSON,
     and registry key text. `make asan` builds a separate test executable
     with pinned MSYS2 CLANG64 packages and runs the suite under
     AddressSanitizer; it is a required separate release check.
8. **0.8, Windows 11 23H2 compatibility.** Resolve the newer console release
   API only when present; on 23H2, independent close/drain workers preserve
   final output and finish canceled I/O safely. The Lua API is unchanged,
   and `pty` remains provisional. The JSON duplicate-key diagnostic also
   keeps its parser-owned key alive while formatting the error. See
   [upgrading to 0.8](#kuu-page-upgrading-08) and the validation evidence in
   [observed shortcomings](#kuu-page-shortcomings).
9. **0.9.0, the pre-freeze correction release.** The last release in which a
   contract may still be corrected, so it is mostly subtraction and
   correction rather than features: additions stay legal at 1.x, contract
   changes do not. The version grows a patch component and `rt.version_at_least`
   replaces the published pattern guard, which `0.9.0` would otherwise break.
   `svc`, `evt`, and `sys.signature` leave the freeze list until a project
   has driven them. `fs.write` retries its rename, closing the intermittent
   `FS access` failure that had left the suite red: one process reproduced it
   15 times in 2000 writes, every one recovered on an immediate retry, and
   4000 writes after the change failed none. A pruned directory leaves
   `fs.dirs`'s `paths` for a new `skipped`, because listing it there made the
   obvious walk read exactly the content the prune excluded. `json.object`
   gives a document a decided key order, so a manifest no longer needs a
   hand-rolled emitter. `sched.clock` reads the performance counter instead of
   the loop's millisecond tick, taking its resolution from 1 ms to about
   500 ns. The numeric-handoff audit found no boundary where unit agreement
   was only conventional. A pool prototyped on the 0.9.0 surface reached 2.74x
   on sixteen CPU-bound jobs using nothing outside the freeze list, so
   `worker` and `serve` can still wait for 1.1 and are not a freeze blocker.
   Every component of `make gate` passes: the suite five times over, native
   analysis, parser fuzzing, and — for the first time on any host — a soak
   gate with zero failures. See [upgrading to 0.9](#kuu-page-upgrading-09).
   - Released 2026-09-11 at 12:55:48 UTC: the tag names `81f9fd7`, the signed
     executable is 1,563,512 bytes, and the local file, the asset downloaded
     again, and the published sidecar all carry the same SHA-256, with the
     released binary reporting its own Certum identity through
     `sys.signature`. Three gates ran in a row on the release host — `make
     gate`, the required separate `make asan`, and the `make publish` repeat,
     1062 checks each — and the two of them that carry a soak were clean at 25
     and 29 rounds, which with the 23H2 evidence from the other machine puts
     two hosts behind the 1.0 soak criterion rather than one. The release
     note's "three clean soak gates" counts the gates, not the soaks: `make
     asan` runs the suite alone. Time Actual adopted
     it the same day: it guards with `rt.version_at_least(0, 9)`, raising its
     minimum from 0.5 retired the two compatibility branches it carried, its
     CI pins the release and its checksum, and its `test` task passed 2,191
     engine checks with CI green in 1 min 19 s. That is the project that
     co-evolved with the runtime, so it does not answer the cold-adopter
     amendment. Recorded in the
     [release handoff](notes/handoff-2026-09-11_145745.md).
10. **0.10.0, the interface described, and no language.** Released on
   2026-09-13, tagged on the tested commit, signed and verified. The owner
   decided on
   2026-09-11 that there is no successor language, no compiler and no emission
   subset; kuu is a runtime for Lua 5.5, and grows capabilities in the palette
   and options on the calls already there. `kuu.md` lost the part that
   described the direction, with four design notes and the subset checker.
   What the release adds instead is what kuu can say about a program before it
   runs. `lua/_palette.lua` is an authored description of kuu's own interface
   — 27 error domains with their code sets, 16 closed sets, and per-function
   options and results for the modules carrying the most field access — and
   `check` reads it, so a code its domain does not have, an option a call does
   not take, a closed set compared with a literal outside it, and `rt.version`
   compared by text are now errors. Time Actual carries two of the last kind,
   dead since 0.6, which survived the commit that migrated it and a review
   looking for exactly them, and which the first draft of these checks also
   walked past: they index the module where they require it, and only a local
   binding was followed. Both shapes are now, which is what found them.
   Domains themselves stay open, since `err.new` is
   public and projects name their own: the first draft that checked them
   offered `TEXT` for the suite's `TEST`, one edit away, on a correct line.
   The description is authored because scraping was tried, and returned option
   names, result fields and `re`'s flags as error codes and nothing at all for
   six domains. `check.file`'s documented error kinds grow from three to six,
   and `--fix` adds two report fields beside them.
   - A project's own modules are read from their text too, which in a
     consuming project is the larger half: Time Actual reaches through one of
     them 210 times and nothing verified a call. Exports come from what a
     module assigns to the table it returns, 73 of the 75 export sites in the
     corpus, and project code is still never executed. A module whose export
     set the text cannot bound goes unchecked rather than guessed at, because
     a field wrongly included costs a missed diagnostic while one wrongly
     excluded is a false positive on correct code. `kuu check --fix` writes
     the global declaration in both directions, with the Lua compiler as the
     authority and a refusal to declare a name this runtime lacks, so
     `print(reuslt)` keeps its error instead of acquiring a silent nil; its
     first run over this repository removed 62 dead names and added none, a
     forgotten addition failing loudly and a forgotten removal never. `kuu capabilities` reports
     the verbs, the 27 public modules and the 176 names they export, the
     domains and the closed sets, and a project's tasks and modules — and not
     what a task installs under `.tools`, of which kuu keeps no manifest.
   - Strings, where the cost was a pattern. A Lua pattern ending in `$` is not
     anchored, so `s:match("%s$")` is retried at every position: one byte of
     information for a scan of the whole string. That one call was 65% of
     `csv.encode`, which over 50,000 rows went from 303 ms to 183; `ini.decode`
     over 20,000 keys went 171 to 88, and to 69 once `text.trim` existed —
     native, because a byte walk in Lua pays a crossing per byte, at 300 ms by
     pattern, 111 ms in Lua and 13 ms in C over a 15-byte line trimmed 300,000
     times. `check` lexes by byte instead of matching patterns against
     one-character substrings, 448 ms to 327 over `lua`, `tools` and `test`.
     Two measurements went the other way: flattening a build to avoid
     intermediate strings measured 1.03x, so no string builder was written;
     and `log`'s `format_text` on one `table.concat` ran 30% slower and was
     reverted, so [pitfalls](#kuu-page-pitfalls) now carries the crossover, about ten
     short pieces, instead of the rule it was written from.
   - Recorded, not built. `_ENV` is an upvalue, so under `global none` with
     nothing declared it reaches `load` and the whole palette while
     `kuu check --json` reports `"requires":[]` and a clean bill; the `require`
     gate holds only for a program that does not reach around it, and the
     small answer, reporting such a reference from `check`, is unimplemented
     ([observations](#kuu-page-shortcomings)). And a JavaScript capability was
     designed on 2026-09-12 — a downloaded, pinned runtime under a permission
     model, never shipped — and set aside the next day, after a whole-project
     review and a spike, for the front door: kuu stays Lua on C and stops
     growing, and what a project needs beyond the palette is a tool the
     project builds, in any technology, called through `kuu.exe`. The spike
     established one fact that outlives the design and belongs to any lexical
     path sandbox on Windows: a junction inside a granted directory walks out
     of it, and neither an allow list nor a deny list sees it, which is why
     the door will supply a reparse-point preflight. The
     [design note](notes/design-js-capability-2026-09-12_155114.md) stands
     as the record of what was considered and measured; the
     [front-door plan](notes/plan-front-door-2026-09-13_001735.md) is what
     followed; it landed through its fourth phase on 2026-09-13, and 0.10.0
     is the release that carries it.
   - Great care with the C, as the front-door plan's first phase asks.
     `make asan` runs inside `make gate`, and the compiler is pinned by hash.
     Five defects the review of 2026-09-12 confirmed are closed: `fs.rename`
     and `fs.copy` retry the two transient refusals as `fs.write` does, and
     so does `http`'s placement of a download; a program or `require` root
     beyond 260 characters opens at the entry; an error message is as long
     as it is, 1023 bytes no longer; `proc.tree` lists a child only when it
     began no earlier than its parent, which closes the 23H2 chain
     intermittent by removing the one mechanism the evidence admits; and a
     job is let go behind a marker once its association with the port is
     removed, since Windows promises no order between its last two messages.
     Two laws hold in every module: an unknown option raises `usage` —
     eleven calls ignored one and four called it `badvalue` — through one
     helper in C and one in Lua; and the raise-or-return line is stated in
     [err](#kuu-page-err) by the function's purpose, which moved `hash.file`,
     `cli.duration` and `cli.size` and left `re` and `text` where they were.
     The `fs.c` raise-path leak the review named did not reproduce under two
     scans and is recorded as such.
   - The front door, as the plan of 2026-09-13 laid it out, landed through its
     fourth phase the same day. The declaration file is `manifest.lua`, with
     `tasks.lua` still found for this release and warned about. A project's
     tools are declared in it, `task.tool "name" { exe, args, output, emits,
     timeout, reach }`, called with `task.exec { tool = "name", ... }` and
     resolved with `task.command`; `check` reads the declarations from the
     manifest's text and holds every call to them, `capabilities` lists them
     from the registry, and the suite holds the two readings equal —
     [tools](#kuu-page-tools), and [confined tools](#kuu-page-confined) for what a tool
     that confines itself must provide and the junction that walks out of any
     lexical grant. `kuu run --json` is a stream, each event as it happens
     and the envelope last. The door keeps a [ledger](#kuu-page-ledger): one record
     per crossing under `.kuu/ledger`, chained by hash, ninety days, with the
     tree delta since the previous run and the repository's head read from
     `.git` itself. Part I's figures are produced by the bundler and held by
     the suite, and `_palette` describes the options of every option-taking
     call, so "an option the call does not take" holds everywhere. A
     three-lens review with a skeptic per finding ran over the tool change
     and confirmed twenty, all fixed with checks; a second over the ledger,
     the stream and the figures confirmed twenty-two more — a task error
     that is not UTF-8 crashing the run, a file name ending in a dot
     stopping it at the door, a stream held in the pipe until exit, a
     last-line pattern quadratic in the line — fixed the same way. What is
     left of the plan is `kuu watch`, deferred by design until something
     runs unattended.
   - The suite gained four new cases: `_palette` held to the
     runtime, to the manual in both directions and to itself; `capabilities`;
     the fixer's invariant, which keeps every declaration outside
     `test/fixtures` correct so a name that falls out of use fails instead of
     rotting; and `kuu.md` regenerated and compared. `docs/capabilities.md` is
     a new manual page, and
     [upgrading to 0.10](#kuu-page-upgrading-010) the migration: no call moves, but
     a project green on 0.9.0 can be red here without changing, and the
     documented set of `check` error kinds grows from three to six, which is
     the one change that can break a program reading the JSON.
     `capabilities` is provisional and outside the planned freeze until a
     project has driven it, by the rule [stability](#kuu-page-stability) already
     applies to `pty`, `svc`, `evt` and `sys.signature`.
11. **0.11, corrections and the first encounter.** Published versions return
   to two nonnegative integers, compared numerically, without semantic-version
   compatibility categories. Existing three-argument minimum-version guards
   remain accepted, with the running release compared as `(0, 11, 0)`.
   The deprecated `tasks.lua` fallback remains supported without a removal
   date. Two reviews of 0.10.0
   corrected process and HTTP allocation ownership, bounded streaming reads,
   archive replacement, ledger failure reporting, checker inference, helper
   validation, and payload generation. Whole-output and unfinished-line reads
   now return recoverable `PROC toobig` at the unread buffer bound; incomplete
   module inventories and unreadable history are explicit in the descriptor.
   Entry help and the agent guide demonstrate immediate work through `kuu -e`,
   and documentation search points to commands that retrieve the relevant
   section. [Upgrading to 0.11](#kuu-page-upgrading-011) records the version, behavior and
   schema changes. The next evidence comes from agents doing ordinary work in
   prepared projects, with kuu as the execution entry point.
12. **0.12, project adoption and execution history.** Feedback from FlowNet
   led to file-attribute operations, readonly-directory cleanup, shared
   inspection exclusions, stronger literal declaration checks and consistent
   task help. Normal runs keep execution history without automatic tree
   snapshots, deltas, watchers or indexes. New ledger records use v2; existing
   v1 bytes and hash links remain readable. The manual adds tested project
   recipes and names [Upgrading from 0.11](#kuu-page-upgrading-from-011) from its
   entry points, including the checklist for existing project instructions,
   report consumers and ongoing `kuu-eval.md` feedback.
13. **1.0.** Criteria for the owner to set. Proposed: three projects driven
   for a month without a runtime defect, a manual page for every module, a
   signed release cadence, and the Lua-versus-Tcl ledger closed with a
   verdict. Two amendments agreed on 2026-09-11: a **clean soak gate on every
   target host**, since freezing while it is knowingly unclean rests the 1.x
   promise on a signal nobody trusts; and **at least one cold adopter**,
   because every adoption finding on record comes from Time Actual, which
   co-evolved with the runtime and therefore routes around contract mistakes
   instead of reporting them. Between 0.12 and 1.0: the freeze, the month of
   use, and corrections driven by what that use finds.

<a id="kuu-page-roadmap-the-05-review-fixes-implemented"></a>

### The 0.5 review: fixes implemented

The external review of 0.5 (commit 3811edf, 2026-09-09) found the items
below, listed in its priority order. All twelve fixes are implemented with
regression tests and shipped in 0.6. The native defects were
addressed first. The old in-progress stash is not needed.

1. **`re`: a callback that matches with the same pattern clobbers the outer
   match (P1).** One match block per compiled pattern is shared by every
   operation on it, so a `gsub` callback that calls `re.match` with the
   same pattern overwrites the outer offsets; a nil-returning callback then
   copies from bounds that belong to another subject, past the end of its
   own. Fix: one match block per operation, held on the stack as a
   userdata so a raise frees it; the fallback copies bounds taken before
   Lua runs. Tests: nested gsub and match, nested gmatch, a nil-returning
   callback after an inner match of a longer subject, a table replacement
   whose metamethod matches.
2. **`proc.tree`: a deep chain overruns the Lua stack (P1).** The recursion
   pushes two tables per level without growing the stack; a chain of 41
   processes crashed kuu with exit 3. Fix: `luaL_checkstack` per level, and
   the native snapshot owned by the stack (a holder userdata, `hold.c`) so
   an error frees it. Test: a chain of 31 kuu processes from a fixture,
   inspected, then killed through its root.
3. **`re`: an unmatched suffix is rescanned per character (P2).** The retry
   after an empty match was recognised as `options == 0`, which the
   `PCRE2_NO_UTF_CHECK` flag breaks, so `gsub("a" .. ("b"):rep(n), "a", "x")`
   is quadratic. Fix: a separate retry flag. Test: a 400 KB suffix well
   under a second.
4. **`csv`: a quoted empty field is dropped as a blank line (P2).** Fix: a
   blank line is one empty field with no quotes and no separator; a row
   that is one empty field encodes as `""`. Tests: `name\r\n""\r\nbob` gives
   two records; `decode(encode{{""}})` gives one row.
5. **`ini`: editing does not follow last-key-wins (P2).** `set` changed the
   first occurrence, `remove` left the effective value, both stopped at the
   first same-named section; a BOM defeated editing; a value with literal
   surrounding quotes lost them on decode. Fix: `set` changes the last
   occurrence across every same-named section, `remove` drops them all,
   the BOM is kept, such a value is quoted once more. Tests:
   `decode(set(...))` with duplicate keys and sections, removal, a BOM
   file, the `"hello"` round trip.
6. **`reg`, `env`, `net`: a name with an embedded NUL acts on another name
   (P2).** The Win32 calls stop at the NUL. Fix: a shared check that
   refuses a NUL in keys, value names, text values, variable names, and
   host names with badvalue. Tests: each raises.
7. **`reg`: a text value that is not valid UTF-16 reads as `""` (P2).** Fix:
   `get` answers `nil, REG encoding`; `values` carries `bytes` in place of
   `value`. Test: a fixture writes an unpaired surrogate as REG_SZ.
8. **`env`: an empty variable reads as unset (P2).** The second Win32 call
   returns zero characters for an empty value and was taken as failure.
   Fix: tell ERROR_ENVVAR_NOT_FOUND from an empty value, in `env.get` and
   in kuu's `os.getenv`. Test: set `""`, get `""`.
9. **`cli` and `sync`: the duration grammar differs from `time`'s (P2).**
   Fix: `cli.duration` delegates to the C parser, so sums and days work in
   typed arguments and lock timeouts. Tests: `"1h30m"`, `"2d"`,
   `sync.lock(name, "1m30s")`.
10. **`time.parse`: negative fields accepted, a bad offset raises (P2).**
    Fix: fields are digits only; the offset is parsed in place with a
    14:00 bound; every malformed text is `nil, err`. Tests: the three
    negative forms, `+99:00`.
11. **adopting.md: the example does not compile (P2).** `error` is missing
    from its globals. Fix: add it; the suite extracts the page's example
    and runs `kuu check` over it.
12. **`net`: a scoped IPv6 address loses its scope (low confidence).** Fix:
    `%scope` in the text from `resolve` and `addresses`, accepted by
    `probe`. Test: `"fe80::1%1"` resolves to itself.

Hardening gates are implemented: `make analyze` runs GCC's static analyzer
over every authored host C file with warnings as errors; `make fuzz` exercises
durations, paths, dates, and command lines with fixed seeds, arbitrary bytes,
structured mutations, round trips, and supervised child deadlines. The
Windows command-line parser provides an independent quoting check. See
[toolchain](#kuu-page-toolchain) for replay commands. Analysis also made the error
raiser's non-returning contract explicit and led to entry-allocation cleanup.

<a id="kuu-page-roadmap-open-decisions"></a>

### Open decisions

- **1.0 criteria.** The proposal above stands until the owner sets them.
- **The shape of a `tool` declaration.** The plan carries a draft — `exe`,
  `args`, `output`, `emits`, `timeout`, `reach` — to be settled when the
  first project writes one, and `emits` is descriptive until `check` can
  follow a value through `json.decode`, which it does not.
- **Whether the ledger's `reach` is ever enforced by the door**, or only
  declared and shown. Enforcement for every tool is C in the door —
  restricted tokens are moderate, path allow-lists are not — and waits for a
  real need.

<a id="kuu-page-roadmap-backlog"></a>

### Backlog

Small things, unscheduled: cancellation and a streaming body reader in
`http`; `kuu docs` as a searchable single page.

<a id="kuu-page-roadmap-the-lua-versus-tcl-ledger"></a>

### The Lua-versus-Tcl ledger

The owner asked to hear, without softening, where Lua turns out weaker than
Tcl for this job. The ledger so far:

- **Files and paths are not in the language.** Tcl ships `file`, `glob`,
  `open` with encodings, and a virtual file system that handled Unicode paths
  correctly on Windows for twenty years. Lua's `io` goes through the C
  runtime, which meant an ANSI code page until kuu switched the CRT to UTF-8;
  everything else had to be written as `fs`. Real cost: about 1,700 lines of
  C that Tcl had for free. Real gain: `fs` tells the truth about junctions,
  identity, and long paths, which Tcl's portable `file` never did. The same
  gap shows in small ways: `file dirname` and `file join` are string patterns
  written by hand in `project.lua`, and `info script` became `rt.source`.
- **No insertion-ordered table.** Tcl's dict remembers order, so a `cli`
  spec could be a mapping; in Lua a spec must be an array of entries, and
  `pairs` order is undefined, so `log` sorts fields, and a JSON object came
  out in arbitrary key order until 0.9.0 added `json.object` to give one a
  decided order. Minor, but felt three times in one day.
- **Lua patterns are not regular expressions.** No alternation, no counted
  repetition, no grouping of a repeated sequence, no Unicode classes. Tcl's
  `regexp` had all of it, and an agent's first instinct in any language is a
  regex. In kuu's own Lua this shows already: `check` resolves module names
  with two patterns because one cannot say `a|a.b`, and `cli` and `values`
  each parse durations by hand. `re` on PCRE2 landed first in 0.5, about
  five hundred lines over a vendored library that cost 450 KB of executable.
  The gap was the first that looked decisive, and it is closed; what remains
  true is that Tcl had it for free.
- **Case is ASCII in the language.** `string.upper` and `string.lower` know
  the twenty-six letters; Tcl's `string toupper` knew Unicode. A glob that
  had to find `é.txt` under `É*.TXT`, as the file system does, needed
  `text.upper` on Windows' own folding. Small, and now closed, but the kind
  of thing Tcl simply had.
- **No trim in the language, and `$` does not anchor.** Tcl ships `string
  trim`, `trimleft` and `trimright`, and its `regexp` anchors with `$`. Lua
  has neither, so the trim must be written, and the obvious spelling of it is
  a trap: only `^` anchors a Lua pattern, so `gsub("%s+$", "")` is retried at
  every position and costs a scan of the whole string. That one call was 65%
  of `csv.encode`, and over the 278 KB `kuu.md` it took 14.4 ms against
  0.19 ms for walking back from the end. Real cost: the helper was hand-rolled
  six times across the projects driving kuu and three more inside it, every
  copy carrying the trap, until `text.trim` was written in C — 13 ms where the
  pattern took 300, over a 15-byte line trimmed 300,000 times. Now closed, and
  the kind of thing Tcl simply had.
- **`global none` is opt-in boilerplate.** Tcl has no equivalent check at all,
  so this is a Lua advantage in the end, but every file must start with two
  lines to get it, and an agent that forgets them gets stock Lua's silent
  globals. `check` warns about a file without them and `kuu check --fix
  --adopt` writes them and keeps the list correct in both directions, with
  the compiler as the authority, so what is left is that the boilerplate
  exists at all rather than that it must be kept by hand.

Still nothing decisive, though Lua's patterns have now cost twice rather than
once: the alternation gap closed with `re`, and the anchoring gap with
`text.trim`, both of them C that Tcl would not have needed. The coroutine
model, the byte strings, and the C API have been strengths at every step so
far.

<a id="kuu-page-roadmap-06-fixes-from-real-repository-adoption"></a>

### 0.6: fixes from real repository adoption

Time Actual exposed cross-module duration units, lossy archive names, process
path inconsistency, and task/entry friction. 0.6 uses numeric
seconds throughout, supports dependency-only tasks and `kuu version`, returns
Unicode archive inventories, writes UTF-8 ZIP headers, normalizes process
executable paths, and identifies client-key/proxy TLS failures. See
[migration notes](#kuu-page-upgrading-06) and the [observations log](#kuu-page-shortcomings).
The Tcl sandbox issue remains an execution-environment limitation. The windres
workaround belongs to the consuming build recipe and is now documented.

Cold setup testing also found and fixed `hash.file`'s long-path boundary.
The complete suite now passes 838 checks plus native analysis. Time Actual's
new recovery fixture passes 17 checks on 0.5 and 0.6; full cold toolchain and
relocation validation is paused. The [2026-09-10 handoff](notes/handoff-2026-09-10_193511.md) recorded
that pause; the remaining work was completed the same day on the second
machine, recorded in the observations log, and 0.6 was released.

---

<a id="kuu-page-shortcomings"></a>

<a id="kuu-page-shortcomings-shortcomings-observed-in-real-use"></a>

## Shortcomings observed in real use

Findings from adopting Kuu in real repositories. Record the trigger, impact,
workaround, and verification status. A limitation or rough edge is not
necessarily a runtime defect; fixes should follow reproduced evidence.

<a id="kuu-page-shortcomings-time-actual-adoption-—-2026-09-10"></a>

### Time Actual adoption — 2026-09-10

0.6 addresses seven runtime/API findings below. The
Tcl sandbox limitation remains external; the windres recipe issue is resolved
in Time Actual. Original observations and 0.5 workarounds are retained for context.

<a id="kuu-page-shortcomings-kuu-version-executes-a-repositorys-version-file"></a>

#### `kuu version` executes a repository's VERSION file

- **Kind:** command-line diagnostic / discoverability.
- **Observed:** in Time Actual, `kuu.exe version` resolves the case-insensitive
  `VERSION` filename and reports `version:1: unexpected symbol near '0.58'`.
- **Impact:** an intuitive version query produces an unrelated Lua parse error.
- **Workaround:** use `kuu.exe --version`.
- **Status:** Fixed in 0.6. `version` is a reserved verb; `./version` still
  executes a file. Both version forms reject extra arguments.

<a id="kuu-page-shortcomings-dependency-only-tasks-require-an-empty-function"></a>

#### Dependency-only tasks require an empty function

- **Kind:** task declaration friction.
- **Observed:** declaring `test` with `deps` but no `run` passes `kuu check`,
  then `kuu list` fails with `TASK badvalue: task 'test' needs a run function`.
- **Impact:** aggregate tasks need boilerplate, and syntax checking alone
  does not validate declarations.
- **Workaround:** add `run = function() end`; run `kuu list` as well as `check`.
- **Status:** Fixed in 0.6. A task with non-empty dependencies may omit `run`;
  cycles, failure propagation, argument checks, and JSON plans still apply.

<a id="kuu-page-shortcomings-restricted-networking-produces-an-opaque-winhttp-error"></a>

#### Restricted networking produces an opaque WinHTTP error

- **Kind:** error diagnostics / execution environment.
- **Observed:** upstream HTTPS requests inside the agent's restricted sandbox
  returned `HTTP oserror: ... Windows error 12185`. The same requests succeeded
  with network permission, with no runtime or URL change.
- **Impact:** the message gives little guidance about the network/proxy context.
- **Diagnosis:** Windows defines 12185 as a client-certificate context without
  an associated private key. The different execution contexts explain the
  observed success/failure difference; the number alone does not prove a ban.
  See [Microsoft's error reference](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages).
- **Workaround:** use the execution context with the required network and
  certificate access; inspect its credential configuration when necessary.
- **Status:** Diagnostic fixed in 0.6. Errors 12185–12188 are `HTTP tls`, with
  named client-key/proxy causes and actionable context. The hosting restriction itself
  is external.

<a id="kuu-page-shortcomings-cli-durations-cannot-be-passed-directly-to-process-timeouts"></a>

#### CLI durations cannot be passed directly to process timeouts

- **Kind:** cross-module unit mismatch; confirmed during real task execution.
- **Observed:** `cli` parses `--timeout 100ms` as the integer `100` (milliseconds).
  Passing this value directly to `proc.run { timeout = opts.timeout }` sets a
  **100-second** deadline, because numeric process durations are seconds.
  A fixture sleeping for 30 seconds completed instead of timing out at 100 ms;
  an enclosing 10-second deadline subsequently confirmed the mismatch.
- **Impact:** natural composition silently lengthens a deadline by 1,000 times.
  This remains after the duration grammar was unified in the 0.5 review fixes.
- **Workaround:** pass `tostring(opts.timeout) .. "ms"` to the process API.
  Time Actual retains this for 0.5 compatibility and exercises both runtime versions.
- **Status:** Fixed in 0.6. CLI results, bounds, and choices use seconds, matching
  native consumers. This is an intentional API change; see [migration
  notes](#kuu-page-upgrading-06). Time Actual handles both 0.5 and 0.6 explicitly.

<a id="kuu-page-shortcomings-tcl-path-normalization-fails-inside-the-agents-filesystem-sandbox"></a>

#### Tcl path normalization fails inside the agent's filesystem sandbox

- **Kind:** hosting-environment limitation, not established as a Kuu defect.
- **Observed:** the same locally built Tcl 9.0.3 normalized
  `C:/Users/.../HEAD/dev/_timeactual/.tools/twapi` into a path missing
  `HEAD/dev` inside the agent sandbox. TWAPI loading failed, and the packaged
  GUI self-test timed out before producing its report.
- **Control:** outside that sandbox, the same interpreter returned the exact
  path, loaded TWAPI 5.2.0, and the packaged app passed its self-test.
- **Workaround:** execute affected Tcl/GUI tasks in a normal Windows process
  with the agent's required execution permission. Headless engine/task tests
  can still run inside the sandbox.
- **Status:** External limitation remains. Normal Windows execution passes; no Kuu
  runtime defect was demonstrated.

<a id="kuu-page-shortcomings-archivelist-returns-non-utf-8-filenames-on-windows"></a>

#### `archive.list` returns non-UTF-8 filenames on Windows

- **Kind:** encoding defect at an API boundary.
- **Observed:** listing the official Go 1.27.1 Windows ZIP returns two names
  under `go/test/fixedbugs/issue27836.dir/` containing the single byte `0xDE`.
  `utf8.len` rejects both at byte 34; saving the inventory with `json.encode`
  fails with `JSON encoding: a string is not valid UTF-8`.
- **Impact:** extracted files are usable, but archive listings do not compose
  safely with Kuu's UTF-8/JSON/file APIs. A prerequisite task can fail after
  successfully unpacking its tool.
- **Workaround:** if a listing has invalid UTF-8, inventory extracted files
  with `fs.glob` and `fs.relative`, which return native Unicode paths. Time
  Actual initially used this fallback. Its current recovery installer
  inventories extracted files directly with an anchored `fs.list` walk.
- **Status:** Fixed in 0.6. A supervised native reader uses the Unicode API in
  Windows archiveint.dll, without extraction or ANSI-output guessing. Unicode, JSON,
  empty archives, and cancellation have regression coverage.

<a id="kuu-page-shortcomings-downstream-tools-can-reintroduce-shell-quoting-problems"></a>

#### Downstream tools can reintroduce shell quoting problems

- **Kind:** external tool limitation encountered through process orchestration.
- **Observed:** a moved Time Actual checkout named `Time Actual` reached the
  native resource build, then windres failed because its internal preprocessor
  command split the path at the space. Kuu had passed the original argv intact.
- **Workaround:** use windres's `--use-temp-file` mode, run it in `build/`, and
  pass relative resource/include paths. The moved checkout then built and
  passed its tests with the original toolchain directories unavailable.
- **Status:** Resolved in the Time Actual recipe. The internal-command boundary and
  windres workaround are documented in [proc](#kuu-page-proc); no Kuu quoting defect was
  demonstrated.

<a id="kuu-page-shortcomings-process-metadata-and-filesystem-paths-use-different-separators"></a>

#### Process metadata and filesystem paths use different separators

- **Kind:** API composition friction; native Windows paths are both valid.
- **Observed:** `proc.tree` returned executable paths with backslashes, while
  `fs.absolute` returned forward slashes. A case-insensitive string comparison
  missed the expected child and could have hidden survivors in a cleanup test.
- **Workaround:** normalize the process path with `fs.absolute` before comparing
  it with another absolute path. Use canonical file identity when aliases matter.
- **Status:** Fixed in 0.6. Process `exe` paths use forward slashes like
  `fs.absolute`; command lines remain unchanged. Regression coverage checks a real child
  process.

<a id="kuu-page-shortcomings-zip-creation-loses-names-outside-the-system-code-page"></a>

#### ZIP creation loses names outside the system code page

- **Kind:** confirmed encoding defect in the archive wrapper's writer options.
- **Observed:** the Unicode regression packed `漢字.txt` using Windows tar's
  default ZIP settings. The archive contained `??.txt`, which extracted as
  `__.txt`. Tar-family archives preserved the same name.
- **Impact:** a successful ZIP pack could silently rename a source file.
- **Fix:** pass `--options zip:hdrcharset=UTF-8` for ZIP creation.
- **Status:** fixed in 0.6; the regression compares the source name,
  Unicode listing, and extracted file for ZIP and compressed tar formats.

<a id="kuu-page-shortcomings-intermittent-access-denied-while-replacing-files"></a>

#### Intermittent access denied while replacing files

- **Kind:** observed file-access failure; underlying cause not isolated.
- **Observed:** one full Kuu run reported Windows error 5 during an atomic
  `mem.update` write. That stopped one concurrent counter and caused two related
  checks to fail. Later, Time Actual's native `strip.exe` reported permission
  denied replacing a freshly linked executable. The file was not read-only,
  and no running application held that executable when inspected.
- **Control:** the memory case passed alone, then passed five consecutive
  runs; the complete Kuu suite subsequently passed. The exact strip operation
  passed on retry, followed by a successful complete Time Actual build/test.
- **Status:** observed, not reproduced deterministically. Do not attribute it
  to a Kuu locking defect, antivirus, or the filesystem sandbox without more
  evidence. No permission bypass or unconditional retry was added.
- **23H2 follow-up, 2026-09-11:** the compatibility gate completed 38 soak
  rounds in 61 seconds with stable handles, but 21 state writes failed. A
  separate 1,000-write comparison reproduced `FS access`, Windows error 5,
  in both the original 0.6 executable (4 failures) and the compatibility
  build (3 failures). This predates the OS-floor change; its cause remains
  unisolated. The soak gate is not clean on this host.

<a id="kuu-page-shortcomings-entry-routes-leave-startup-allocations-to-process-teardown"></a>

#### Entry routes leave startup allocations to process teardown

- **Kind:** native allocation cleanup found by GCC analysis, not a reported
  long-running workload failure.
- **Observed:** failed UTF-16 argument conversion returned without freeing the
  partially converted argument array. Reviewing that path also found argument,
  launch-path, and chunk-name allocations left to process teardown on other
  entry routes.
- **Status:** fixed locally. The entry dispatcher borrows converted arguments;
  its caller releases them, and file/eval/stdin routes share explicit cleanup.
  GCC analysis and the entry regression cases pass.

<a id="kuu-page-shortcomings-validation-of-06-before-its-release"></a>

### Validation of 0.6 before its release

- Full Kuu suite: **834 checks passed**, including **23 new adoption checks**;
  reconfirmed after native cleanup and hardening-gate work on 2026-09-10.
- `make analyze`: all authored host C files pass GCC `-fanalyzer` with warnings
  as errors. The shared error raiser now declares its non-returning contract,
  allowing GCC to follow Lua error paths correctly without suppressing warnings.
- `make fuzz`: **30,000 cases per family** across command lines, durations,
  dates, and paths (**120,000 randomized cases**), plus fixed boundary cases
  and valid-value/round-trip checks. All three fixed seeds pass. Workers are
  bounded by deadlines; this is not a proof of memory safety.
- Time Actual: build, **2,191 engine checks**, **nine task checks**, and the
  packaged GUI self-test passed with root `kuu.exe` at 0.6.
- All **27 pinned prerequisite archives** listed successfully: **42,849 UTF-8
  names**. The Go archive's two formerly corrupted names matched extracted files.
- The original restricted HTTP request now reports `HTTP tls`, error 12185,
  its symbolic name, and client-certificate context. Native fixtures also cover
  errors 12186–12188 without changing certificate stores or TLS policy.
- Time Actual retains explicit compatibility for published 0.5; its task and
  application checks pass with that binary as well. The installed root runtime
  is restored to 0.6 after compatibility testing.

The intermittent file-access failures above remain recorded despite passing
reruns. These validation results preceded the source checkpoint push; no
release or signing was performed.

<a id="kuu-page-shortcomings-cold-setup-and-recovery-—-2026-09-10"></a>

### Cold setup and recovery — 2026-09-10

<a id="kuu-page-shortcomings-file-hashing-fails-on-paths-that-the-filesystem-api-can-read"></a>

#### File hashing fails on paths that the filesystem API can read

- **Kind:** confirmed native path-boundary inconsistency.
- **Observed:** `fs.read` successfully read a 376-character filename, but
  `hash.file("sha256", path)` returned `HASH notfound`. Content verification
  of a deeply nested installed tool could therefore reject a valid file.
- **Fix:** use the shared normalized Unicode filesystem boundary in
  `hash.file`, including extended-length paths, and reject embedded NUL.
- **Status:** fixed in the source checkpoint. Four regressions cover long
  paths, NUL, ambiguous trailing-dot paths and invalid UTF-8. The complete
  suite passes **838 checks**, and native static analysis passes.
- **Published 0.5 workaround:** Time Actual's installer supplies an explicit
  extended-length Windows path until the fixed 0.6 binary is released.

<a id="kuu-page-shortcomings-installation-presence-stamps-accept-damaged-tools"></a>

#### Installation presence stamps accept damaged tools

- **Kind:** consuming-project recipe defect, not a new Kuu runtime API.
- **Observed:** a tool whose bytes were changed was accepted by the original
  Time Actual presence-only recipe; malformed record data could instead
  raise a Lua indexing error. Individually tracking overlapping archives
  also risks repeated repairs after a later package overwrites an earlier one.
- **Fix:** Time Actual inventories and hashes the final merged destination,
  validates records, stages archive extraction and preserves a recoverable
  old tree until promotion succeeds. Kuu supplies the existing primitives.
- **Status:** **17 recovery fixture checks pass on 0.5 and 0.6**, including
  corruption, interruptions, offline repair, relocation and concurrency.
  Real cold toolchain setup and full recovery/relocation validation were
  paused and remain incomplete. Tcl/Tk's compiled tree still rebuilds in
  place after invalidating its completion record.

See [the dated handoff](notes/handoff-2026-09-10_193511.md) for the exact paused
state, local evidence and remaining work. Earlier full application results
above do not establish completion of the new recovery recipe's validation.

<a id="kuu-page-shortcomings-cold-setup-and-recovery-on-a-second-machine-—-2026-09-10"></a>

### Cold setup and recovery on a second machine — 2026-09-10

Step 2 of the [dated handoff](notes/handoff-2026-09-10_193511.md), run
on the owner's other machine with the 0.6 build at commit 9abab18.

- **Main checkout, empty `.tools`.** `prereqs --all` fetched all 27 pinned
  archives and built Tcl/Tk 9.0.3 shared and static in 22 min 50 s. `env`
  verified gcc 16.2.0, Python 3.14.6, and Tcl 9.0.3. The complete `test`
  task passed in 1 min 41 s: 9 task checks, 17 recovery checks, the build
  (6,428,720 bytes), 2,191 engine checks, and the application self-test at
  `status=ok`.
- **Cold lab, a second clone with an empty `.tools`.** 23 min 18 s to the
  same state. Then twelve fault-injection and relocation steps passed: a
  changed byte in `ar.exe` repaired from the cached archives (0 downloads,
  21 unpacks, 445 s); a deleted Python record rebuilt (8 s); a corrupt cached
  Python archive plus a missing `python.exe` fetched again, verified, and
  repaired (1 download, 11 s); a deleted Tcl/Tk record rebuilt in place
  (662 s); the checkout moved to `cold lab moved` with the original path gone
  and the inherited tool environment replaced by junk paths, after which
  `env` (6 s), reuse (10 s, 0 downloads, 0 unpacks), repair of a damaged tool
  from the cache (0 downloads, 181 s), and the complete `test` task (69 s,
  every check as above) all passed from the moved path.
- **CI.** The checkpoint push's GitHub run succeeded in 7 min 34 s on
  windows-latest with published 0.5; the run for the commit that pins 0.6
  succeeded in 7 min 36 s.

Observations, none of them a kuu defect:

- **Tcl/Tk cannot be rebuilt from a path with spaces.** The thirteenth step
  removed the Tcl/Tk record in the moved checkout and asked for a rebuild.
  Tcl 9.0.3's `win/configure` and Makefile fail with `cd: too many
  arguments` and `No rule to make target '.../cold'` when the source or
  prefix path holds a space. Using the already built Tcl/Tk from such a path
  works, as the moved test run showed. Time Actual's recipe now refuses the
  rebuild with that explanation instead of make's output. An upstream
  build-system limitation.
- **Repair is bundle-granular.** One damaged byte re-extracts and
  re-inventories the whole destination: for the MSYS2 bundle 21 archives and
  some 22,000 files, 3 to 7 minutes here. The design trades repair time for
  one simple, verifiable record per destination.
- **The first verification after a repair is slow.** `env` took 87 s right
  after the MSYS2 repair and 5 to 10 s at every other time: freshly written
  files are read once by the on-access scanner. Hosting, not kuu.
- **`env` printed a stray `1`** after the Python and Tcl versions, `gsub`'s
  count reaching `print`. Fixed in the recipe.

<a id="kuu-page-shortcomings-promoting-07-on-windows-11-23h2-—-2026-09-11"></a>

### Promoting 0.7 on Windows 11 23H2 — 2026-09-11

- **Kind:** a newly supported OS exposed a static-import and console-lifetime
  incompatibility. The owner lowered the Windows 11 floor from 25H2 to 23H2.
- **Observed:** the signed 0.7 release, verified against its sidecar, GitHub
  asset digest and Time Actual's CI pin, exits before `--version` with
  `0xC0000139` (entry point not found) on Windows 11 Enterprise 23H2,
  build 22631.7517. Its Authenticode signature and expected signer match.
- **Cause:** the release statically imports `ReleasePseudoConsole` from
  `kernel32.dll`; a direct export lookup confirms that this host lacks it.
  The other three ConPTY entry points are present. The loader rejects the
  executable before Kuu can report its OS requirement, even for commands
  that do not use `pty`.
- **Local recovery:** restored the original root Kuu 0.6 executable by its
  saved hash. The synced Time Actual source accepts it: eight Lua files
  check without warnings/errors, task declarations load, and the complete
  test plan validates. The verified 0.7 download remains in that project's
  `.tools/downloads/kuu/0.7/` for later promotion.
- **Fix:** resolve `ReleasePseudoConsole` only when exported. On 23H2,
  reserve close/drain workers before creating a console; wait for the whole
  supervised job on natural exit, and transfer abandoned output only after
  canceled I/O completes. Dedicated completion events let final shutdown
  finish without depending on stopped IOCP dispatch. The 24H2+ OS path is
  retained, as is the public Lua API.
- **Regression coverage:** descendant lifetime and final output, blocked
  unread output, native launch failure, console-host cleanup, pending input
  and output at process exit, and canceled I/O while Lua finalizers run other
  children. The complete suite now contains 1,044 checks. Validation runs on
  Windows 11 Enterprise 23H2 build 22631.7517; no newer Windows host was
  available for a fresh run. See the file-access finding above for the
  pre-existing soak failure.
- **Release status:** the compatibility fix is included in
  [0.8](#kuu-page-upgrading-08). The published signed 0.7 asset and its digest are
  unchanged and still cannot start on 23H2. The validation evidence above
  records the earlier development build; its remaining findings stay open.

<a id="kuu-page-shortcomings-json-duplicate-key-error-lifetime-—-2026-09-11"></a>

### JSON duplicate-key error lifetime — 2026-09-11

- **Observed:** the full AddressSanitizer suite on 23H2 found a heap use after
  free in the existing `json.decode` duplicate-key diagnostic. The offending
  key points into the yyjson document, which was freed before formatting it.
- **Fix:** build the error while the document still owns the key, then free
  the document. The existing duplicate-key regression now checks the key in
  the message as well as the error code. Included in 0.8.

<a id="kuu-page-shortcomings-process-tree-chain-check-during-23h2-validation-—-2026-09-11"></a>

### Process-tree chain check during 23H2 validation — 2026-09-11

- **Observed:** one complete run failed the existing 31-process-chain
  assertion that each node has at most one child. The cause is unisolated.
- **Control:** the isolated process suite passed all 82 checks; the final
  complete production suite then passed all 1,044 checks. No change to
  process-tree enumeration was made.
- **Evidence:** [dated validation record](notes/validation-23h2-2026-09-11_094612.md).
- **Status:** closed 2026-09-13, on evidence. The snapshot's parent id is
  the number the parent had when the child started, and Windows hands a dead
  process's id to the next one that needs it. `tree` first learned to list a
  child only when it began no earlier than its parent, keeping a child whose
  start time it could not read; the assertion failed again that day, twice,
  and once the assertion named what it saw, the second and third children of
  chain node 1000 were `csrss.exe` and `wininit.exe` — system processes whose
  recorded parent is the boot-time pid 1000, unreadable to this user, worn
  that afternoon by a `kuu.exe` the chain had just started. A process kuu can
  open never starts one it cannot, so an unreadable child under a readable
  parent is a stranger, and `tree` leaves it out; only a parent that cannot
  be read keeps every child. The proc case holds the rule against whatever
  the machine offers: every readable process whose snapshot children include
  an unreadable one shows it no such child.

<a id="kuu-page-shortcomings-orphaned-io-completion-during-console-shutdown-—-2026-09-11"></a>

### Orphaned I/O completion during console shutdown — 2026-09-11

- **Observed:** the 0.8 release review found that a canceled console read
  could outlive its child state during Lua shutdown. A later finalizer
  running another process could dispatch that queued completion and read
  its freed source before noticing that the request was orphaned.
- **Fix:** overlapped I/O uses a stable completion key; dispatch consults
  the request's source only after checking whether it is orphaned.
- **Regression:** a native fixture cancels real pipe I/O, releases the
  source's memory before dequeue, and dispatches the orphaned completion.
  The console suite also leaves an exited console open through shutdown
  while another Lua finalizer runs a process. Included in 0.8.

<a id="kuu-page-shortcomings-published-08-on-the-23h2-host-—-2026-09-11"></a>

### Published 0.8 on the 23H2 host — 2026-09-11

The final signed 0.8 release starts on build 22631.7517 and passes all
48 console checks, including the additional shutdown/finalizer regression.
The native orphaned-I/O fixture and signature/tamper checks also pass.
The full signed suite reports 1,045 passed and two related failures caused
by the previously observed Windows error 5 during a memory-file replacement.
The isolated memory case then passes all 19 checks; the underlying finding
remains open. Time Actual's task/recovery tests, all 2,191 engine checks,
application build and isolated self-test pass with the promoted release.

See the [dated adoption record](notes/validation-0.8-23h2-2026-09-11_104022.md).

<a id="kuu-page-shortcomings-the-replacement-failure-isolated-and-closed-—-2026-09-11"></a>

### The replacement failure isolated and closed — 2026-09-11

The Windows error 5 seen during atomic replacement since 0.5 is reproduced,
explained, and fixed in 0.9.0.

- **Reproduction.** 2000 atomic writes to one target from a **single**
  process: 15 failed with `FS access`, Windows error 5. One process is enough,
  which removes concurrency, `sync`, and kuu's own locking from the account.
- **Transience.** Every one of the 15 succeeded on an immediate retry, with no
  sleep and no change of permission. Zero hard failures.
- **Cause.** `fs.write` writes `name.kuu-<pid>-<tick>.tmp` and renames it over
  the target. On Windows a scanner or an indexer routinely opens a file the
  moment its handle closes, and `MoveFileExW` on that freshly written
  temporary then loses the race and reports access denied. This is
  environmental and affects any program using write-temp-then-rename; it is
  not specific to `mem`, which merely writes often enough to show it.
- **Fix.** The rename is retried, bounded at six attempts over a few tens of
  milliseconds, and only for access-denied and sharing-violation. No
  permission is bypassed and no retry is unconditional: a target held open
  past the window still fails with `FS access`, which stays the intended
  answer. Atomicity is untouched, because each attempt either replaced the
  target or left it alone.
- **Verification.** 4000 writes after the change failed none. The two
  previously failing `mem` checks pass, and the suite reports **1049 passed,
  0 failed** — green for the first time since the finding was recorded. A
  regression holds a reader open for the whole attempt and asserts the write
  still fails, that it spent the retry window rather than giving up on the
  first rename, and that the target kept its old bytes.

Two intermittent failures seen while establishing the baseline are **not**
covered by this and remain open: `proc.tree handles a 31-process chain`, which
failed once and passed on rerun, and `an unknown host is HTTP notfound`, which
returned `HTTP timeout` when sandbox DNS stalled past ten seconds. Neither is
reproduced; neither should be attributed to a kuu defect without evidence.

<a id="kuu-page-shortcomings-the-soak-gate-is-clean-—-2026-09-11"></a>

### The soak gate is clean — 2026-09-11

The compatibility gate above recorded 38 soak rounds with 21 state writes
failed, and that finding was open. With the bounded rename retry in place the
same gate on the same host (build 22631.7517) reports **34 rounds in 61 s,
handles -3, private +4.3 MB, failures 0**.

Alongside it: the suite passes 1,062 checks with zero failures on five
consecutive runs, native static analysis passes over every authored host file,
and parser fuzzing passes 10,000 cases per family on both fixed seeds. Every
component of `make gate` therefore passes on this host, which is the first
host on which that has been true.

<a id="kuu-page-shortcomings-_env-reaches-every-capability-without-declaring-one-—-2026-09-11"></a>

### `_ENV` reaches every capability without declaring one — 2026-09-11

- **Kind:** a gap in a documented affordance. Not a sandbox escape: kuu has
  no sandbox, and the operator ran the file.
- **Observed:** `_ENV` is an upvalue rather than a global, so it is in scope
  always and needs no declaration. Under `global none` with nothing declared,
  `_ENV.load("return 2 + 3")()` compiles and runs code, and
  `_ENV.require("proc")` reaches the whole palette.
- **Impact:** [`check`](#kuu-page-check) says its require listing "is how an agent sees
  what else a file asks for before running it", and for such a file it does
  not. The file below draws `"requires":[]`, `"errors":0`, `"warnings":0`,
  `"ok":true` from `kuu check --json`, and then starts a child:

  ```lua
  global none
  -- This file declares nothing and requires nothing, by inspection.
  local m = _ENV.require("proc")
  local r = m.run { "cmd.exe", "/c", "echo reached" }
  _ENV.print((r.out:gsub("%s+$", "")))
  ```

  The same reasoning limits the capability gate itself: `require` gates a
  program's capabilities only for a program that does not reach around it.
- **Workaround:** treat a `_ENV` reference as disqualifying when reading a
  file's requires as evidence of what it does. A file that carries no `global`
  declaration at all is already reported by `check` as a warning.
- **Status:** observed and reproduced, no fix attempted. Reporting a `_ENV`
  reference from `check` is the small answer and is not implemented. Recorded so
  that the require listing is not read as a complete account of what a file
  can reach.

---

<a id="kuu-page-stability"></a>

<a id="kuu-page-stability-stability"></a>

## Stability

kuu is still before 1.0. The 0.x releases may change contracts when use in
real repositories shows a mistake. Each such change belongs in that release's
upgrading page, with the old form beside the replacement. Projects carry a
specific `kuu.exe` in their own repository; updating that copy is deliberate.

Published versions from 0.11 have the form `N.N`, two nonnegative integers
compared numerically: 0.11 follows 0.10. The components identify and order
releases; they do not encode semantic-version compatibility categories.
Compatibility follows the explicit promises below and each release's
upgrading notes, not an inference from which number changed.

<a id="kuu-page-stability-the-10-boundary"></a>

### The 1.0 boundary

At 1.0, the documented public interfaces of these modules will be frozen:

`archive`, `check`, `cli`, `csv`, `env`, `err`, `fs`, `hash`, `http`,
`ini`, `json`, `log`, `mem`, `net`, `proc`, `re`, `reg`, `rt`, `sched`,
`sync`, `sys`, `task`, `text`, and `time`.

The same promise covers running a file, stdin, or an inline program; the
`docs`, `run`, `list`, and `check` verbs; their documented options and exit
codes; and their documented JSON reports. It includes the supported Windows
baseline and the documented Lua language version. The freeze is a promise
for the named 1.x release family, not a claim that the current interface can
no longer improve. It is an explicit commitment, independent of the release
numbering convention.

`pty`, `svc`, `evt`, and `sys.signature` are provisional, and so is the
`capabilities` verb with its JSON report. Their APIs may change before or
after 1.0, with an upgrading note, and they are outside the freeze until a
later release explicitly brings them in.

`pty` is provisional for its interpretation of terminal output. The other
three left the freeze list in 0.9.0 for a plainer reason: they arrived in 0.7
and no project has yet driven them in earnest. A service state machine, an
event-log query, and an Authenticode trust decision are three of the easiest
Windows surfaces to shape wrongly, and a wrong shape inside the freeze costs
the whole 1.x line. They are brought in at 1.1 with adoption evidence behind
them. Nothing is removed from the executable; only the promise is withheld.

`capabilities` arrived in 0.10.0 and remains provisional while its descriptor
contract is evaluated through project use and feedback. Consuming agents build
on the fields and their meanings, so the freeze needs adoption evidence for
that contract. A later release must explicitly bring it into the freeze;
current project use alone does not change its provisional status.

Private modules and names starting with `_`, command implementation modules
under `cmd`, internal helper processes, build artifacts, and undocumented
implementation details are also outside the public contract.

<a id="kuu-page-stability-what-1x-may-add"></a>

### What 1.x may add

A 1.x release may add a module, function, verb, optional argument, option,
or result field. An addition must leave the behavior of existing valid
programs unchanged when they do not use it. Consumers should ignore unknown
JSON object fields and read the fields they need. A result's documented
closed set of status values or error codes cannot silently grow: an
existing caller may exhaustively handle that set.

A 1.x release may fix a defect so implementation matches the documented
contract. It may improve diagnostics, performance, and resource use. Exact
error-message wording, incidental timings, and unspecified enumeration
ordering are not stable interfaces; use error domains and codes and the
ordering the manual actually promises.

It may not remove or rename a public entry, change an accepted argument's
meaning, change defaults for existing calls, change duration or size units,
change the type or meaning of an existing result field, change a documented
exit code or error domain/code, or weaken a documented lifetime or atomicity
guarantee. Such a change cannot be made under this promise: it would require
an explicitly announced replacement compatibility policy and a migration
note. Changing a version number alone does not authorize it.

<a id="kuu-page-stability-a-minimum-version-guard"></a>

### A minimum-version guard

A `manifest.lua` should ask for the oldest release whose features it uses,
rather than compare the runtime version for equality. `rt.version_at_least`
compares the release's numeric components, so a project never parses the
version text:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 12),
  "this project requires kuu 0.12 or later; found " .. rt.version)
```

`rt.version_at_least(first [, second])` answers whether the running kuu is
that version or newer. An omitted component is zero; negative or noninteger
components raise `RT badvalue`. It compares numbers, so 0.11
comes after 0.10, and 1.0 after both.

A third argument remains accepted for compatibility with guards written when
releases had three components. The running 0.12 compares as `(0, 12, 0)` for
those calls; no third component appears in its published version. Use two
arguments in new guards.

Version text changed from two components to three at 0.9.0 and returns to two
at 0.11. A three-component pattern no longer matches `rt.version`; replace
it with the call above. [Upgrading to 0.11](#kuu-page-upgrading-011) records that
migration; [upgrading to 0.9](#kuu-page-upgrading-09) records the earlier
change as history.

Place this before declarations that use newer capabilities. The guard tests
the minimum released capability level, while the reviewed executable hash and
the project's tests decide which executable the project adopts. Development
artifacts can share version text with an earlier release; identify those by
build/hash and check feature availability where needed. Run the project's
tests when updating, and read the upgrading notes for every intervening release.
For 0.12's execution-history, inspection and file-attribute changes, read
[Upgrading from 0.11](#kuu-page-upgrading-from-011).

For the changes introduced with this statement, see
[Upgrading to 0.7](#kuu-page-upgrading-07). For a complete `manifest.lua`, see
[Adopting kuu](#kuu-page-adopting).

---

<a id="kuu-page-toolchain"></a>

<a id="kuu-page-toolchain-toolchain"></a>

## Toolchain

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted. This page says exactly what `.tools` holds
so that another machine, or another person, can reproduce it.

Projects kuu drives are the same: each fetches its own prerequisites by url
and hash into its own `.tools`, with [`http`](#kuu-page-http) and
[`archive`](#kuu-page-archive), and carries its own `kuu.exe` directly in the
project root, copied in by hand. Nothing is shared between projects, and there is no lock: the agent
knows what a project needs, and kuu gives it the means.

<a id="kuu-page-toolchain-what-tools-holds"></a>

### What `.tools` holds

```text
.tools/
  msys2/
    ucrt64/        the MSYS2 UCRT64 GCC toolchain, copied as a tree
    clang64/       the separately pinned, test-only AddressSanitizer toolchain
```

Production builds need only the `ucrt64` subtree; the MSYS2 shell, pacman,
and the `usr` tree are not needed. It brings GNU make (`mingw32-make.exe`) as well as gcc. The
compiler runs from any shell as long as `ucrt64\bin` is on `PATH`, because the
compiler proper (`cc1.exe`, under `lib\gcc`) loads `libgmp`, `libisl`,
`libmpfr`, `libmpc`, `zlib`, and `zstd` from that directory and the driver does
not add it for the programs it spawns. Without it every compile exits 1 and
prints nothing. The `Makefile` sets the path itself and runs its recipes under
`cmd.exe`, so `make` behaves the same from PowerShell, cmd, or Git Bash:

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8
```

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe test
```

Each build checks the complete embedded Lua/manual file set, including added
and deleted files. The C generator writes a temporary payload and replaces
the previous output only after successful reads and writes. Identical output
keeps its timestamp, avoiding unnecessary recompilation; a failed generation
is retried on the next build.

Target triple `x86_64-w64-mingw32`; C runtime UCRT, which every supported
Windows carries as `ucrtbase.dll`, so the executable has no redistributable.

<a id="kuu-page-toolchain-the-ucrt64-pins"></a>

#### The UCRT64 pins

The production tree is unpacked from these 18 MSYS2 packages, fetched on
2026-09-13 from the [MSYS2 UCRT64 mirror](https://mirror.msys2.org/mingw/ucrt64/)
and checked against the SHA-256 each
[package page](https://packages.msys2.org/packages/mingw-w64-ucrt-x86_64-gcc)
publishes before extraction. They are gcc's complete runtime closure plus
GNU make; `cc-libs` is a virtual dependency that `gcc-libs` provides. The
same day, the complete gate — suite, `asan`, `analyze`, `fuzz`, `soak` —
passed under this tree before it replaced the previous one.

Until then the tree was a robocopy of a live MSYS2 install carrying gcc
16.1.0-5, recorded by version only: 42,000 files, of which the 6,384 in this
closure are the ones a build touches. That compiler had already left the
mirror, which keeps only current versions, by the time anyone tried to obtain
it again. The archives are retained so that this cannot happen twice.

For each row, the download name is
`mingw-w64-ucrt-x86_64-<package>-<version>-any.pkg.tar.zst`, below the mirror
URL above. Keep the archives under `.tools/downloads/ucrt64`. Download the
exact versions, compare `certutil -hashfile <archive> SHA256` with the table,
then unpack each verified archive with Windows' own tar, which reads zstd —
`C:\Windows\System32\tar.exe -xf <archive> -C .tools\msys2 ucrt64` — taking
only the `ucrt64` member so the package's own metadata files are left out. Do
not run package scripts. The first check is
`.tools\msys2\ucrt64\bin\gcc.exe --version`, which must report
`gcc.exe (Rev3, Built by MSYS2 project) 16.2.0`.

| package | version | SHA-256 |
|---|---|---|
| gcc | 16.2.0-3 | `1cd86e5817f6e0d7310d7cb2bb91f4a55e1256cb4ce580a0c5f2a74e013d144d` |
| gcc-libs | 16.2.0-3 | `5763fabf86fa13a4449ee765006d3446384ed66af7bf827459710eb777e0b11c` |
| binutils | 2.47-3 | `ba98af202fe71e0884bb51daf78ce10bd8a51c69528c700dcf5855e6ece06dd3` |
| crt | 14.0.0.r375.g9c1abbbf5-1 | `09bccbb31c7bdc9090358cac429a78b8bffe5142a98a1e1d54f5b869f3068055` |
| headers | 14.0.0.r375.g9c1abbbf5-1 | `046cc32a88739738e94976486ace1e8e457e6beb6ae866de2f07d2d3eebcabb6` |
| winpthreads | 14.0.0.r375.g9c1abbbf5-1 | `3cdd84d957e4bb8b5a30df548afd82b97a52fedc77974a43debd1d0685ed669c` |
| libwinpthread | 14.0.0.r375.g9c1abbbf5-1 | `61d340fe8eebc77ee821badca246827fe90545e99685e503bdea16a8d25df512` |
| gmp | 6.3.0-2 | `e82a75968a556484a50084578238a84eb60fb93e34986fd6695c537975bd39ea` |
| isl | 0.28-1 | `8594e01a253d5a72646c586cf5a1626c1b1c2be7c30060fe67abd9bebe3fe223` |
| mpc | 1.4.1-1 | `f06556e811c711ce91609484e31d358e4f495811ba29813bf2284a3b236d82ce` |
| mpfr | 4.2.2-3 | `6b70a275d2ec75c70aa50a236c218e6b7ee9a5ab4c6d52cb0b580267b7d200fe` |
| zlib | 1.3.2-2 | `841401182976d2f9e17e5c0ebaac51f2a8014140ea53d67625e91c8fb3c85ea0` |
| zstd | 1.5.7-2 | `dbdb8427280046a2b41697780aa4c52983b708082b0da4755951dc3bea96ca89` |
| windows-default-manifest | 20260815-1 | `b39039f754a600cc0dec49df7d675a59a3cb2b63691d91b4ae60735ee7075eca` |
| make | 4.4.1-5 | `871f760657a360279f29b945a7fd7d9655fe46a3e1e06dd783c9e74514aa0b27` |
| gettext-runtime | 1.0-1 | `ba693dda4ac375af76ce481ff3a6e7481286546cc7dc6d56c7021dae34084157` |
| tzdata | 2026c-1 | `b6af6fd6acb676b9bb0761b75b1d8330b89abd4c8d467fda35cee8925b170db9` |
| libiconv | 1.19-1 | `9a500f38c2b91808741c62fae746b3e9110b33a1ecf5c30fa0c66dbedddf7e16` |

<a id="kuu-page-toolchain-populating-tools"></a>

### Populating `.tools`

From the pinned archives, as above: 18 downloads, 70 MB, verified, unpacked
into `.tools/msys2/ucrt64`. No MSYS2 install and no pacman are involved.

kuu's own compiler is not fetched by kuu, by the owner's decision: kuu does not
build or bootstrap itself, and there is no tool in the repository that fetches
or verifies these archives — the table is the record, `certutil` is the
check. Only verification targets run the built executable.

<a id="kuu-page-toolchain-verification"></a>

### Verification

Run the complete production gate from the checkout root:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8 gate
```

`gate` runs the regression suite, `asan`, `analyze`, `fuzz`, and `soak` in
that order, stopping at the first failure. Recursive makes keep these stages
sequential even with `-j8`: the suite and soak share scratch files. Each
stage is also available separately (`test`, `asan`, `analyze`, `fuzz`,
`soak`). `asan` is inside the gate since 0.10.0; before that it was described
as a required release check and run by hand, and on 2026-09-12 its build was
found 22 commits stale. `SOAK` defaults to
60 seconds; `FUZZ` and `FUZZ_SEED` below are inherited by the gate.

`analyze` compiles all authored `src/*.c` and `examples/*.c` files separately into `build/analyze`
with GCC's `-fanalyzer`, no optimization, and the normal warning-as-error gate.
It does not analyze vendored libraries or claim to prove memory safety.

`fuzz` defaults to 10,000 cases per parser family for each of three fixed
seeds: 1, 12648430, and 3735928559. It checks durations, dates/zones, lexical
paths, Windows command-line quoting, CSV decoding, INI decoding and edits,
JSON decoding, and registry key text. Inputs include arbitrary bytes,
mutated boundary cases, valid Unicode, independently known arithmetic, and
round trips. Native quoting is compared with `CommandLineToArgvW`; batch
quoting also checks newline rejection. CSV fields and exact JSON integers
have round-trip checks; INI edits must return the requested value after
decoding. Registry inputs only go to `reg.exists`: no registry keys or
values are written. Fuzzed strings are never executed as commands or opened
as filesystem paths. Each worker has a five-minute
deadline; any crash, nonzero exit, timeout, or truncated output fails the gate.

For a longer run or a deterministic replay:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe fuzz FUZZ=100000 FUZZ_SEED=12648430
```

Assertion failures print the seed, case, and input bytes in hexadecimal.
A native crash or deadline failure identifies the worker and seed; rerun
that seed, reducing `FUZZ` to narrow the failing prefix if needed. The gates
are bounded regression tools, not coverage-guided fuzzing.

<a id="kuu-page-toolchain-addresssanitizer"></a>

### AddressSanitizer

GCC remains the production compiler. `make asan` builds a separate
`build/kuu-asan.exe` with Clang, `-fsanitize=address`, debug information,
frame pointers, and `-O1`, then runs the full regression suite with that
executable. Every authored and vendored native object is instrumented;
objects and generated payloads stay under `build/asan`. Build helpers and
external test fixtures still use GCC. No kuu is used to build either runtime.

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8 asan
```

This is a test executable, with a dependency on CLANG64's
`libclang_rt.asan_dynamic-x86_64.dll`; it is never signed or released.
The target adds the local `clang64/bin` to its own process environment so
the DLL and `llvm-symbolizer` are found, including by child kuus. No machine
environment variable changes. The two existing printf wrappers are exempt
from Clang's annotation suggestions only; GCC's warning gate is unchanged.
The target sets `KUU_TEST_ASAN=1` for the suite: its deliberate crash probe
must reach ASAN's exception reporter instead of kuu's production handler.
The production suite continues to require kuu's diagnostic and exit code 3.
ASAN detects memory access errors on exercised paths. It does not establish
race freedom, correct Win32 handle ownership, or coverage of unexecuted paths.

<a id="kuu-page-toolchain-the-clang64-pins"></a>

#### The CLANG64 pins

These 17 packages were fetched on 2026-09-10 from the
[MSYS2 CLANG64 mirror](https://mirror.msys2.org/mingw/clang64/) and checked
against SHA-256 values published on their MSYS2 package pages before
extraction. They include Clang's complete runtime dependency closure;
`libc++` provides the `cc-libs` dependency. Only this test toolchain uses them.
The [Clang package metadata](https://packages.msys2.org/packages/mingw-w64-clang-x86_64-clang)
links to each dependency's package page and published checksum.

For each row, the download name is
`mingw-w64-clang-x86_64-<package>-<version>-any.pkg.tar.zst`, below the mirror
URL above. Keep the archives under `.tools/downloads/clang64`. Download the
exact versions, compare `certutil -hashfile <archive> SHA256` with the table,
then unpack each verified archive with
`tar -xf <archive> -C .tools/msys2 clang64`. The package's `clang64/` tree
lands alongside `ucrt64/`; do not mix the two trees or run package scripts.
The first check is `.tools\msys2\clang64\bin\clang.exe --version`, which
must report 22.1.8 and target `x86_64-w64-windows-gnu`.

| package | version | SHA-256 |
|---|---|---|
| clang | 22.1.8-2 | `4eb99c39d1ade53dc55362c7c334265e629b84270dbe474377900330e0b81a5d` |
| clang-libs | 22.1.8-2 | `335106bd756266322d8beb2d55ac650dafa339f470e6932c3490ba242022149a` |
| compiler-rt | 22.1.8-2 | `840675b14938bed10d982529e7312a8e1cfa9503b438ee73a3efe2559440f586` |
| crt | 14.0.0.r353.g6df76fa52-4 | `f34cec18643c421aeb606bddd887514bd69950a6be2c669aec7e5ef0d94e8c89` |
| headers | 14.0.0.r353.g6df76fa52-2 | `e8cbff539567875775a2d8145da0c34c38deaf88766b8336c21040b3e262095d` |
| lld | 22.1.8-2 | `db67211e280929e20c0908f90c48a426281b0b39bc30687ce31af93ad8b7b571` |
| llvm-tools | 22.1.8-2 | `c176f89d38a5a36ceb7461416d7a8aefef4a3cb8642c104dcba9ad274c174e47` |
| winpthreads | 14.0.0.r353.g6df76fa52-2 | `0a8ea5b96e89b0dc7de55e50f7a980593c2559f0ea2ab6c952ea996b373bdec8` |
| llvm-libs | 22.1.8-2 | `63d87b17d6e249cb90c8cf1decaff6a3ad944b8551d5342b8b9b329c01a12318` |
| zlib | 1.3.2-2 | `96d8db2f2bf24c0d4e82b899d50a3497d97536a8bd38ce275401d0f2b9580b5e` |
| zstd | 1.5.7-2 | `2d75c4ddf8f4f7b76fe33e3f1eea16450f9b3aede14285c886462d72f0ffd87d` |
| libwinpthread | 14.0.0.r353.g6df76fa52-2 | `2ff874bf57f71a9192bc39cb0227f87021576ee5f98878f740dd3ef8057fc705` |
| libc++ | 22.1.8-1 | `de0bd1b9d62f81b6ac06ea915af8da3fbd63e6705e1bb62ef3f553d1e5fbe4ef` |
| libffi | 3.8.0-1 | `4d27339b52eabae86a1dff79cf432191ad8dd6acfa653b1179b12490234c66a6` |
| libxml2 | 2.15.4-1 | `61de987a3655c1bc81ea50ee1bdc6ac91836d96e91115ba8afdb82283272f6d8` |
| libunwind | 22.1.8-1 | `1427583ab43306045b06df71e4a31686d5848bddabba628ea1b8068f38dbd5fd` |
| libiconv | 1.19-1 | `26c4ac9f2023eecdfffb291cab40c60585a0cd0f72539ca03c5558f3ecd309ec` |

<a id="kuu-page-toolchain-releasing"></a>

### Releasing

A release is make, cmd recipes, and two plain C tools, never kuu. Every build
already carries a version resource: `tools/versionrc.c` reads the version
from `src/kuu.h` and writes the `.rc`, `windres` compiles it in, so the file's
properties say what `--version` says.

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe release
```

`release` signs `build\kuu.exe` with the owner's Certum certificate through
the Windows SDK's signtool, selected by thumbprint and timestamped by Certum,
then verifies the signature and checks that the leaf was issued to the
expected name, then writes `build\kuu.exe.sha256` with `tools/sha256sum.c`.
Signing needs the owner's SimplySign session, so the owner runs it.
`publish` first runs `gate`, then signs and hashes only after the gate passed
and the tree was checked for uncommitted changes. It creates the GitHub Release named after the
version, with both files attached and notes generated from the commits. The
release is bound to the commit the tree was built from: the tag is created on
`HEAD`, which must already be pushed, and a tree with uncommitted changes is
refused.
`SIGNTOOL`, `SIGN_SHA1`, `SIGN_NAME`, `TIMESTAMP`, and `GH` are make variables
whose defaults fit the owner's machine; `GH` names the gh executable when it
is not on `PATH`.

A project keeps its chosen `kuu.exe` directly in its root, either downloaded
and ignored or committed as a signed binary. In both models it verifies the
exact reviewed SHA-256, accepted signature and expected signing identity before
first execution; see [adoption and runtime verification](#kuu-page-adopting-1-give-the-repository-its-kuu).
The runtime pin identifies the approved bytes, while the minimum-version guard
in `manifest.lua` states the capabilities its recipes require. Upgrades are
deliberate project decisions, not automatic changes to a shared installation.

Before publishing a release:

1. Run `make gate` on the final sources and review every stage's result.
2. Resolve every sanitizer finding from the gate's ASAN stage. `make asan`
   also runs that stage independently when investigating a failure.
3. Commit and push the tested tree. Run `make publish GH=<gh.exe>`; it repeats
   the production gate before signing and publishing that commit.
4. Verify the release tag, signed executable, and SHA-256 sidecar, then run
   the exerciser with a copy of the released executable.

---

<a id="kuu-page-upgrading-from-011"></a>

<a id="kuu-page-upgrading-from-011-upgrading-from-011"></a>

## Upgrading from 0.11

Move a project from signed kuu 0.11 to 0.12 by reviewing its runtime
assumptions, inspection policy and history consumers before running its tasks.
This page describes the changes in 0.12; [Upgrading to 0.11](#kuu-page-upgrading-011)
records that release's changes from 0.10.0.

Keep working task and tool declarations; there is no wholesale manifest rewrite.
The checklist identifies the expectations and consumers that may need changes.

**These changes require kuu 0.12.** Use `rt.version_at_least(0, 12)` when a
project depends on them. That guard establishes a minimum capability level;
the reviewed SHA-256 and signing identity still identify the approved runtime.
No runtime upgrade is performed by reading this page.

<a id="kuu-page-upgrading-from-011-upgrade-in-order"></a>

### Upgrade in order

1. **Verify the chosen candidate.** Follow the project's owner-approved runtime
   choice and [verification procedure](#kuu-page-adopting-verify-before-first-execution).
   Keep the candidate separate from the live executable during evaluation. Match
   its reviewed SHA-256 and signing identity, or the explicitly approved identity
   of a development artifact, before executing it. Keep the project's downloaded
   or committed-runtime model; a newer version alone does not authorize new pins.
2. **Read the candidate's own manual before loading project code.** Run its
   `docs agent` and `docs upgrading-from-0.11` commands. `docs`, including searches
   and sections, reads only the embedded manual: it needs no network or manifest.
   `kuu check` is static inspection without executing project Lua; omit `--fix`
   for a read-only check. `capabilities` and `list` execute the manifest to learn
   its declarations, so review it before using those commands with the candidate.
3. **Review the project's expectations.** Read `AGENTS.md`, README instructions,
   automation helpers and report consumers against [the list below](#kuu-page-upgrading-from-011-project-instructions-and-assumptions).
   Update statements that describe retired behavior and adapt consumers of removed
   fields. Keep the owner's task, verification and approval policies; the embedded
   manual describes what this executable does, not permission to replace them.
   Read the existing `kuu-eval.md` at the project root and identify reported
   difficulties to recheck during candidate validation.
4. **Check which source will be inspected.** Review `kuu.config.json` and the
   [directory exclusions](#kuu-page-upgrading-from-011-explicit-project-inspection). Maintained source under
   an optional default name needs a deliberate policy. A missing configuration
   selects defaults; no new configuration file is required when those are right.
   Run the candidate's `check`, read warnings as well as errors, and correct
   declaration mistakes it now detects before running tasks.
5. **Validate in an isolated project copy.** Put the candidate at that copy's
   expected project runtime path so nested tasks use the same verified bytes.
   Keep its paths, outputs and task side effects isolated from the live project;
   a copied manifest may still refer to external locations. Then inspect
   `capabilities` and `list`, and run the project's relevant tests. Where history
   compatibility matters, include a preserved copy of its old history and check
   the resulting mixed-version chain and report consumers. New runs append v2
   records; the old executable has not been validated against them.
6. **Adopt the verified result together.** Stop tasks using the old runtime before
   replacing it. Review the runtime pins, changed project instructions, configuration
   and helpers together; change minimum-version guards only for features actually
   required. Retain the old approved runtime and a separate pre-upgrade history copy
   if rollback is required. After new runs write live v2 history, replacing only the
   binary is not an established rollback procedure. Preserve both histories; do not
   edit, merge or delete ledger lines to make an older executable accept them.
   Record the adopted identity and validation evidence in the project's upgrade record.
7. **Maintain the project's `kuu-eval.md`.** Append a concise dated entry for the
   upgrade evaluation, including an unsuccessful or deferred adoption, using
   [the reporting format](#kuu-page-agent-reporting-back). Create the file if missing;
   preserve earlier entries. Record the actual runtime tested, commands and
   outcomes, what helped, remaining difficulties and new regressions. Recheck
   earlier issues and reference their dated entries in a new follow-up; call an
   issue resolved only after verifying it with the candidate.
   Bring the relevant results from an isolated test copy back to the project's
   root evaluation document. Continue maintaining it after subsequent work with
   kuu; the upgrade entry does not replace ongoing feedback.

The runtime API remains available to `kuu -e` for immediate queries. Find an API
with `kuu docs search NAME`, then use the printed `Read:` command to retrieve its
section. Full pages and section retrieval also support `--json`.

<a id="kuu-page-upgrading-from-011-project-instructions-and-assumptions"></a>

### Project instructions and assumptions

An agent returning to an established project should check these specific claims,
including copies of old kuu advice in `AGENTS.md` and README files:

| Assumption to review | What to use now |
|---|---|
| A run snapshots the source tree and records which edits it ran against | Runs record execution. Use the project's explicit source-review or version-control workflow when changed files matter. There is no automatic watcher or index. |
| A missing `delta`, `observation` or `project.ledger.unaccounted` means no files changed | These fields are absent by contract. Absence makes no claim about file changes or who caused them. |
| `.kuu/ledger/tree.json` must be refreshed, repaired or migrated | Leave the existing file alone. It is ignored, and there is no replacement baseline. |
| Every ledger record is v1, or report timing includes scan phases | Accept the documented v1/v2 history and current run-report shape below. Stream-event v1 is a separate schema. |
| Git ignore rules determine which Lua files kuu checks | Review `kuu.config.json` and the explicit inspection exclusions below. |
| Calling `proc.run` is always a bypass, even when output must be captured | Resolve a declared tool with `task.command`, then use `proc.run` for capture. This is supported: the enclosing task/run remain recorded, but there is no individual child ledger record or child event. Prefer `task.exec` when capture is unnecessary. |
| `kuu capabilities` or `kuu list` merely reads manifest text | Both execute its declarations. Use `kuu check` for static inspection and `kuu docs` for documentation without loading the manifest. |
| `rt.version_at_least(0, 11)` proves the APIs described here are present | Use `rt.version_at_least(0, 12)` for 0.12 capabilities, and keep the project's reviewed runtime pins. |

For process capture, successful nonzero child exits and actionable failure reports,
read the [process recipes](#kuu-page-process-recipes). File attributes and the checker
changes below may also let the project simplify existing workarounds. Adopt only
the recipes relevant to that project; they are examples, not new mandatory tasks.

Keep a short bootstrap instruction in the project's existing agent instructions
instead of copying the manual. Adapt this text to its approved runtime path:

```text
Use the project's pinned kuu.exe and follow its runtime-verification instructions.
Read that executable's `kuu docs agent` when starting work; use `kuu docs search`
and section retrieval for current APIs. On a runtime upgrade, read the candidate's
embedded migration notes before running project code. When moving from signed
0.11, start with `kuu docs upgrading-from-0.11` in the verified candidate.
`kuu check` without --fix inspects project Lua statically; `kuu capabilities`
and `kuu list` execute the manifest. Follow this project's task and approval
policies. Resolve stale runtime claims against the current embedded manual and
update the affected instructions as part of the authorized upgrade.
Read and maintain `kuu-eval.md` at the project root. Append a dated entry for
each piece of work using `kuu docs agent reporting-back`; create it if missing.
Preserve earlier entries and report retested issues in a new follow-up, with
the runtime identity, commands and outcomes; leave untested issues unverified.
```

<a id="kuu-page-upgrading-from-011-execution-history"></a>

### Execution history

0.12 changes the ledger and run-report contract. These changes are not part of
the signed 0.11 release.

Normal `kuu run` execution no longer takes project-tree snapshots, compares
file changes or publishes a baseline. It does not start a watcher or maintain
a filesystem index. The [ledger](#kuu-page-ledger) retains task, child and run
records, outcomes, timings, arguments and best-effort repository ref/head
metadata. Repository identity does not describe dirty files or attribute
changes to a task. Explicit filesystem operations, including `fs.watch`,
remain available; [checking](#kuu-page-check), [module inventory](#kuu-page-capabilities)
and their [scan exclusions](#kuu-page-scan) remain supported.

Consumers of reports and history should adapt these fields:

- New durable ledger records have `v:2` and omit `delta` and `observation`.
  The new reader and chain verifier accept both versions 1 and 2. Existing
  NDJSON lines keep their original bytes and hash links, subject to normal
  ninety-day retention. Treat old change metadata as historical only.
  Older executables have not been validated against version 2; do not assume
  a downgrade can read or append the new history.
- An existing `.kuu/ledger/tree.json` is ignored and left untouched. No
  migration, cleanup or replacement baseline is required.
- `run --json` no longer emits result `scope` or `scans`, ledger `observation`
  or `publication`, or timing phases `initial_scan` and `final_scan`.
  `result.ledger` instead reports `{records, complete, error?}` once opening
  is attempted: successful appends for this invocation, whether recording
  succeeded, and any opening or recording error. Failures remain nonfatal to
  tasks and appear in `notes`. Preflight failures and dry runs omit the
  summary. See [Tasks](#kuu-page-task) for the complete shape.
- Stream events still have `v:1`; their schema version is separate from
  durable ledger records. Existing task and child durations keep their
  meanings. The `ledger` timing measures opening and append work.
- `capabilities --json` no longer emits `project.ledger.unaccounted`. Kuu
  makes no claim to know which project edits a crossing accounts for.

<a id="kuu-page-upgrading-from-011-explicit-project-inspection"></a>

### Explicit project inspection

Checking and module inventory now use a shared declarative inspection policy
from `kuu.config.json` beside the project's manifest. Its automatic directory
exclusions are:

| Kind | Directory basenames, at any depth |
|---|---|
| Mandatory | `.git`, `.kuu` |
| Optional defaults | `.tools`, `build`, `node_modules`, `.cache`, `.local`, `.venv`, `__pycache__` |

A missing configuration file selects those defaults. If a conventional name
such as `build/` or `.local/` contains maintained source, disable the optional
set and add only the exclusions the project needs:

```json
{
  "v": 1,
  "scan": {
    "defaults": false,
    "exclude_dirs": [".tools", "node_modules"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

`exclude_dirs` matches an exact basename at any depth; `exclude_paths` matches
a project-relative directory subtree. These rules add exclusions, without
negation or include patterns. `defaults:false` leaves `.git` and `.kuu`
mandatory for automatic inspection. An explicitly named checker file or
starting directory overrides its own exclusion; descendant rules still apply.
Git ignore rules do not configure this policy. See [scan configuration](#kuu-page-scan)
for path validation and the reported scope and scan metadata.

`check`, `capabilities`, `run` and `list` validate this file before project code
can execute. Checking still reads the manifest as text. Invalid or unreadable
configuration makes `check`, `run` and `list` exit 2 with `SCAN config`;
`capabilities` reports the error and an incomplete inventory without loading
the manifest. Each invocation retains its captured policy. The configuration
controls inspection only and does not change `require` resolution. Normal
`run` and `list` do not automatically scan the project tree or track changes.

<a id="kuu-page-upgrading-from-011-file-attributes"></a>

### File attributes

`fs.attributes(path, options)` and `fs.set_attributes(path, patch, options)`
add inspection and mutation of six named Windows file attributes. Options
are optional. The getter returns `attrs` plus six booleans; setters preserve
unspecified bits and accept only named boolean flags. Read the
[file-attribute contract](#kuu-page-fs-file-attributes) for examples and errors.

Both calls select the final link itself by default; use `{follow=true}` for
its target. Existing `fs.stat` behavior is unchanged. `{}` validates readable
metadata without testing write permission; every nonempty patch requests
write-attribute access, even when its values already match. Directory
`temporary=true` is rejected without applying any of the patch. Attributes
do not replace ACL permissions or imply recursive cleanup.

These calls require 0.12; use `rt.version_at_least(0, 12)` before declarations
that need them. Signed 0.11 does not provide them.

<a id="kuu-page-upgrading-from-011-cleanup-declarations-and-task-help"></a>

### Cleanup, declarations and task help

0.12 also fixes recursive removal of readonly
directories. Clearing a readonly bit now checks errors and leaves link targets
untouched. Removal remains nontransactional; the [cleanup guide](#kuu-page-cleanup)
provides bounded project-level retries and preserves primary and cleanup errors.

`kuu check` now validates literal task/tool identifiers and independently known
declaration fields, including a misplaced task-level `timeout` beside a run
function. Direct, curried and simple aliased constructors work; dynamic values
stay conservative. See [declaration checking](#kuu-page-check-task-and-tool-declarations).

Task help shows non-empty descriptions above usage with or without an explicit
argument schema. Tasks without a schema accept a lone trailing `--`, while
still rejecting real extra arguments. Rest forwarding and child exit codes are
preserved. [Task help](#kuu-page-task-running-and-failing) explains `run TASK --help`
versus deliberately forwarding `run TASK -- --help`.

The 0.11 executable does not include these corrections.

<a id="kuu-page-upgrading-from-011-adoption-recipes"></a>

### Adoption recipes

The manual now includes tested recipes for [process descriptions and
diagnostics](#kuu-page-process-recipes), [caller working directories](#kuu-page-working-directories),
[shared project environments](#kuu-page-project-environment),
[relocation with non-repairing health checks](#kuu-page-relocation),
[isolated editor launch checks](#kuu-page-editor), [cached native helpers and local
shortcuts](#kuu-page-native-helper), and [cache reconstruction and uncertain publication
recovery](#kuu-page-reconstruction). These use project Lua to express the policy; each
page states any minimum-version requirement.

[Adopting kuu](#kuu-page-adopting) supports both a downloaded, ignored runtime and a
committed signed runtime. Both models pin approved bytes and signing identity;
a minimum-version guard alone does not identify an approved executable.

---

<a id="kuu-page-upgrading-011"></a>

<a id="kuu-page-upgrading-011-upgrading-to-011"></a>

## Upgrading to 0.11

0.11 corrects defects found in two reviews of 0.10.0 and makes the first
encounter with the executable more useful. It keeps the same Windows baseline
and Lua version. Most projects need only replace their executable, run
`kuu check`, and run their tasks. Programs that read streams or consume the
capabilities descriptor should read the changes below before replacing it.
Version text has two components again, so programs that parse it must also
read the version migration below.

Follow the project's owner-approved runtime upgrade and
[pre-execution verification](#kuu-page-adopting-verify-before-first-execution): compare
the chosen replacement with the reviewed SHA-256 and expected signing identity
before running it. This applies whether the project downloads and ignores the
runtime or commits the signed binary. For corrections included in the signed
0.11 release, use `rt.version_at_least(0, 11)` for the minimum-version guard.
Changes in 0.12 have their own [Upgrading from 0.11](#kuu-page-upgrading-from-011)
page; read it when replacing that release. For the earlier
manifest, task-report and checker changes, read
[upgrading to 0.10](#kuu-page-upgrading-010).

<a id="kuu-page-upgrading-011-versions-are-two-numbers"></a>

### Versions are two numbers

Published versions now have the form `N.N`: two nonnegative integers,
compared numerically. `0.11` follows `0.10`. The numbers identify and order
releases; they do not encode semantic-version compatibility categories.
Read the upgrading notes for contract changes and test the executable a
project adopts. The explicit interface commitments in [stability](#kuu-page-stability)
continue to apply independently of the numbering choice.

`rt.version` and the executable's displayed version are `"0.11"`.
Windows' numeric file and product versions are `0,11,0,0`; their string values
are `"0.11"`. The extra numeric fields belong to the Windows resource format,
not to the public version.

A guard that parses three components, such as
`rt.version:match("^(%d+)%.(%d+)%.(%d+)$")`, no longer matches. Replace it
with a numeric minimum-version check:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 11),
  "this project requires kuu 0.11 or later; found " .. rt.version)
```

Existing calls with a third argument remain accepted for old guards. They
compare the running release as `(0, 11, 0)`, so a guard for an older
three-component release still works; new guards should use two components.
Historical references to 0.9.0 and 0.10.0 describe those releases as published.

The deprecated `tasks.lua` fallback also remains supported in 0.11, with its
warning and no scheduled removal. `manifest.lua` takes precedence when both
files exist. Renaming the old file is still recommended and requires no
change to its contents; the earlier announced removal in 0.11 does not apply.

<a id="kuu-page-upgrading-011-find-an-api-and-use-it-immediately"></a>

### Find an API and use it immediately

The entry help and [agent guide](#kuu-page-agent) now demonstrate `kuu -e`: all kuu
modules are available to an inline script, without creating a script file or
manifest. Print the result explicitly; use `json.encode` when the result
should be structured. Repeated project operations belong in named tasks.

```text
kuu docs
kuu docs search fs.read
kuu docs fs reading-and-writing
kuu -e "print(assert(require('hash').file('sha256', 'README.md')))"
```

The first command lists the available pages. Search finds matching lines and,
in plain output, gives commands for retrieving their surrounding sections.
An API name need not be a section heading: `fs.read` is documented under
`reading-and-writing`. `kuu docs agent` explains the project workflow.
Page and verb inventories sort their exposed names correctly even when one
name is a prefix of another; the shorter name comes first.

<a id="kuu-page-upgrading-011-streaming-reads-keep-their-memory-bound"></a>

### Streaming reads keep their memory bound

For `proc.start { stream = true, ... }`, `maxout` is the maximum unread
buffer for each output stream. Previously, a whole-output or unfinished-line
read could fill that buffer and wait forever: the child could not write more
until the same reader consumed something. It now returns `nil, PROC toobig`.
No bytes are consumed by the error; drain with numeric reads or `read("some")`,
or start the child with a larger `maxout`.

The boundary is exact. Even output exactly `maxout` bytes long can produce
`toobig` if EOF has not yet been observed. `lines()` and `err_lines()` raise
read errors, including this one, instead of silently ending iteration.
Stream `maxout = 0` is rejected because it cannot make progress. Captured
`proc.run` output still uses `truncated` to report discarded output; check it
before interpreting a captured result as complete.

Numeric reads now return **up to** the requested count once any bytes are
available, as documented. Code needing an exact count must accumulate it
across reads and handle EOF. A waiting reader retains its reservation until
it resumes; a competing reader gets `PROC busy`, and closing the child wakes
the waiting reader with `PROC closed`.

Pending stdin writes now own stable storage, consumed queue space is reused,
and aggregate waiters keep their allocations until cleanup. These correct
invalid buffer lifetimes and memory retention under sustained process activity.
`inherit_stdin = true` also works with streamed output, and JSON task
execution preserves inherited input and EOF. See [proc](#kuu-page-proc).

Concurrent [filesystem-watch](#kuu-page-fs) readers receive complete batches in
the order they began waiting. Each batch goes to one reader; callers needing
several observers must distribute it themselves.

<a id="kuu-page-upgrading-011-incomplete-inspection-is-visible"></a>

### Incomplete inspection is visible

`check` reports unreadable directories and incomplete listings as `read`
findings. Its module inventory follows the runtime's resolution rules,
including Unicode names and modules hidden by bundled names. Consumers of
the provisional capabilities descriptor should handle these additions:

- `check.modules(root)` returns `complete` and `errors` alongside its existing
  fields. Each error has `path`, `message`, and an optional `win32` code.
- `capabilities` exposes these as `project.modules_complete` and
  `project.module_errors`. A partial inventory is useful, but not proof that
  an omitted module is absent.
- `project.ledger.records` is optional: it is present only when verification
  establishes a count. An unreadable history sets `intact = false` and
  `unreadable`; corrupt content is described by `broken`. Missing history
  remains distinguishable from a failed read.

The ledger refuses to append behind an unreadable predecessor. Read, write
and close failures warn and appear in the task report's notes while preserving
the task's outcome. Record shape is checked, and broken history is reported
even when no recent record is readable. See [capabilities](#kuu-page-capabilities),
[check](#kuu-page-check), and [ledger](#kuu-page-ledger).

The global fixer leaves initialized or unsupported declarations unchanged
instead of rewriting their meaning. Checker inference also handles reassigned
tool bindings and escaped or shadowed export tables conservatively; each check
operation reads current tool declarations. Task help works before dependency
argument validation. Dry-run and other JSON reports repair invalid UTF-8
without dropping entries whose repaired keys collide.

<a id="kuu-page-upgrading-011-malformed-helper-inputs-are-refused"></a>

### Malformed helper inputs are refused

Several helpers previously accepted input whose meaning could not survive a
round trip, or silently ignored part of it. These cases now fail explicitly:

- Task dependencies and tool lists, archive entry lists, and marked JSON
  containers require the documented contiguous array shapes. Ordered JSON
  objects reject duplicate names.
- CSV header mode and record encoding reject duplicate column names. Array
  mode remains available when repeated header text is intentional.
- INI writers reject unrepresentable keys and section names containing line
  endings. Valid spaces and brackets inside section names are preserved.
- CLI specifications reserve the normalized `help` key, require finite numeric
  bounds, and enforce required rest arguments. Help still waives missing
  required values. Overflowing size text is rejected.

Logging failures return false and increment `dropped`. In JSON mode an
unencodable record is dropped whole, so a consumer never receives a plain-text
fallback in its JSON stream. Text logging preserves values associated with
numeric field keys. See [log](#kuu-page-log) and the individual helper pages.

<a id="kuu-page-upgrading-011-destinations-and-builds-survive-failure"></a>

### Destinations and builds survive failure

Archive packing stages its output beside the destination and replaces the
previous archive only after success. Packing into the input tree excludes
the exact output and staging file, and filenames beginning with `@` are
literal operands. Such entries may retain a leading `./` in their archived
names. Atomic file writes and HTTP downloads use compact sibling names so
long destination basenames remain usable.

HTTP downloads retain their absolute destination across waits, reject NUL
output paths before opening a file, and clean up construction allocations
and staging files when validation or a Lua accessor raises. Long explicit
executable paths and PATH entries also resolve correctly.

For people building kuu, every payload build now observes added and removed
files. Generation checks input and output failures and replaces the generated
file only when complete; unchanged bytes keep their timestamp, and a failed
generation is retried on the next build. Windows version resources validate
the two published components and fill their unused numeric fields with zero.
The bundled manual has explicit, validated section links,
and the cookbook's NDJSON wrapper rejects truncated captures before parsing.

---

<a id="kuu-page-upgrading-010"></a>

<a id="kuu-page-upgrading-010-upgrading-to-010"></a>

## Upgrading to 0.10

This page records the historical 0.10.0 release. [Upgrading to 0.11](#kuu-page-upgrading-011)
describes the current N.N version format, review corrections, and continued
support for the deprecated `tasks.lua` fallback.

0.10.0 is the release after the pre-freeze correction. It adds, and it
corrects one convention: an unknown option is refused everywhere, where
fourteen calls used to ignore it, and three calls now fall on the right side of
the raise-or-return rule. No call moved and nothing was removed. A program
that ran on 0.9.0 runs here unchanged unless it misspelt an option, or
checked `hash.file`'s second value for a malformed path; the two sections at
the end name every call.

It is the front-door release: the declaration file is `manifest.lua`, tools
are declared beside the tasks that call them, the door keeps a ledger, `kuu
run --json` is a stream, and the executable explains itself. Each has a
section below. A build that reports `0.10.0` has all of it, and the guard
advice on this page holds for it.

What it changes is what kuu tells you about code that already runs. `check`
reads an authored description of kuu's own interface and a project's own
modules, so **a project that was green on 0.9.0 can be red on 0.10.0 without a
line of it having changed**. Most findings name a call that does nothing; the
rest name one that raises only when its line is reached. None of them is new
breakage — they were there before, and nothing said so.

One thing here can break a working program rather than only turn a build red:
`kuu check --json` documents its error kinds as a closed set, and that set
grew. If anything of yours reads that report, go to
[`CheckError.kind`](#kuu-page-upgrading-010-checkerrorkind-has-three-more-members) first.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, run `kuu check` and read what is new, then run
the project's tasks. **If a program of yours reads `kuu check --json`, give its
`kind` switch a default branch before you upgrade** — that is the one edit this
release makes mandatory.

`kuu check` exits 1 where it exited 0, so a CI step that runs it turns red
before any task does. It takes paths, so the upgrade need not be one commit:
narrow the step to the files that are already clean, widen it as you fix the
rest.

```text
kuu check src lib          # the part that is clean today
kuu check                  # everything below the project root
```

If the project uses anything this page introduces — a `task.tool`
declaration, `task.exec { tool = ... }`, `task.command`, `task.tools`,
`task.tool_get`, `rt.page`, `text.trim`, `rt.verbs`, `rt.pages`,
`check.exports`, `check.modules`, `kuu capabilities`, the events of the
`kuu run --json` stream, the ledger, or `kuu docs` with options — raise its
guard to `rt.version_at_least(0, 10)`; a project that uses none of them may
leave it where it is. A project that uses one of them under an older guard
fails at the call rather than at the guard, which is the failure the guard
exists to prevent.

For earlier releases, read
[upgrading to 0.9](#kuu-page-upgrading-09), [to 0.8](#kuu-page-upgrading-08),
[to 0.7](#kuu-page-upgrading-07), and the [0.6 duration migration](#kuu-page-upgrading-06).

<a id="kuu-page-upgrading-010-taskslua-is-manifestlua"></a>

### `tasks.lua` is `manifest.lua`

The file at a project's root that declares its prerequisites and tasks is
`manifest.lua`. It is the same file: `task "build" { ... }` reads as it did,
and the `task.tool "name" { ... }` declarations sit beside the tasks. Only
the name changes, because the file describes more than tasks now.

`kuu run`, `kuu list`, `kuu check` and `kuu capabilities` still find a
`tasks.lua` where no `manifest.lua` is, read it as the manifest, and write
one line to standard error each time saying to rename it; `capabilities
--json` reports which name it found as `project.file`. A directory holding
both is read from `manifest.lua` without a word. The announced plan was to
remove the old name in 0.11; that plan was withdrawn, and 0.11 retains the
deprecated fallback.

```text
git mv tasks.lua manifest.lua
```

<a id="kuu-page-upgrading-010-tools-are-declared-in-the-manifest"></a>

### Tools are declared in the manifest

A program a task calls — built by the project or fetched by hash into its
root — is declared beside the tasks, `task.tool "name" { exe = ..., args =
..., output = ... }`, and called with `task.exec { tool = "name", ... }` or
resolved with `task.command`. [Tools](#kuu-page-tools) is the page. Nothing existing
breaks: `task.exec { "gcc", ... }` runs as it did. It gains one thing, a
`tool` warning from `kuu check`, because nothing describes what it runs;
declaring the tool ends the warning and starts the checking — an argument the
declaration does not name is found without running, and `kuu capabilities`
lists the tool. `CheckWarning.kind` gains `tool` for this, so a reader of
warnings needs the same default branch a reader of errors does.

<a id="kuu-page-upgrading-010-the-door-keeps-a-ledger"></a>

### The door keeps a ledger

`kuu run` writes one record per crossing — the run, each task, each child a
task ran through `task.exec` — to `.kuu/ledger/<day>.ndjson` under the project root, chained by
hash and kept ninety days, with the tree delta since the previous run on the
first record. Nothing asks for it and nothing depends on it: a ledger that
cannot be written is one line on standard error and the run goes on. Add
`.kuu/` to the repository's `.gitignore` if it is not there already for
`mem`. [The ledger](#kuu-page-ledger) is the page.

That describes the 0.10 release. 0.12 removes automatic tree
deltas and keeps execution history; existing records remain readable. See the
[0.12 migration note](#kuu-page-upgrading-from-011).

<a id="kuu-page-upgrading-010-kuu-run---json-is-a-stream"></a>

### `kuu run --json` is a stream

Through 0.9 `kuu run --json` printed one JSON object when the run ended.
It prints one per line as the run goes — the run once its plan is checked,
each task as it starts and finishes, each child a task runs through the door
— and the envelope it used to print is the last line, unchanged. A reader
that decoded the whole of standard output as one document breaks: take the
last line for what you had, or read each line for what you did not.
[Tasks](#kuu-page-task) has the events. `--dry-run --json` and every failure
before the run are still one envelope.

<a id="kuu-page-upgrading-010-the-executable-explains-itself"></a>

### The executable explains itself

Nothing here moves a call; it is what kuu says to an agent that arrives.
[For the agent](#kuu-page-agent), `kuu docs agent`, states what is expected of an
agent in a project that runs through kuu, as instructions in the order they
are met, and asks it to report back in the project's `kuu-eval.md`;
`kuu --help`, the `kuu docs` footer and both forms of `kuu capabilities`
point to it, and `capabilities` counts the entries the file holds. `kuu
docs` is a verb like the others: `--help`, `--json`, one `##` section by
heading or anchor, a search over all its words; `rt.page(name)` gives a
program a page's text. Every verb points onward at the moment it matters —
a manifest that declares no task, a misspelt verb, an unknown task, no
project, a first `.kuu/` the repository does not ignore — on standard error
and, for `--json` readers, as `notes` on the `run`, `list`, `check` and
`capabilities` envelopes; and `check` names the version guard of 0.8 where
it stands, before the manifest runs. `kuu run TASK --help`
prints the task's usage and exits 0, as every `--help` does; a `TASK
failed` error carries `status` and `limit` so a task branches on fields.

<a id="kuu-page-upgrading-010-check-reports-four-mistakes-it-used-to-pass"></a>

### `check` reports four mistakes it used to pass

Three of them are silent: the call returns, the branch is never taken, and
nothing says why. The fourth raises, but only when its line is reached.

```text
app.lua:6: "notfund" is not a code in PROC, so this never matches; did you mean "notfound"?
app.lua:7: "flie" is not one of rt.route's values, so this never matches; did you mean "file"?
app.lua:8: rt.version is Major.Minor.Patch and is never compared by text; use rt.version_at_least(...)
app.lua:9: cwdd is not an option of proc.run; did you mean cwd?
```

- **A code its domain does not have.** `err.is(e, "PROC", "notfund")` answers
  false for every error there will ever be, so the handler it guards is dead
  code that looks live.
- **A closed set compared with a literal outside it.** `rt.route == "flie"` is
  never true. The sets are the ones the manual states: `ProcStatus`,
  `FsKind`, `SvcState` and thirteen more.
- **`rt.version` compared by text.** Since 0.9.0 the version has three
  components, so `rt.version == "0.9"` is false against `0.9.0`. Use
  `rt.version_at_least`. This is not hypothetical: a consuming project carries
  two such branches, dead since 0.6, which survived the commit that migrated it
  to `rt.version_at_least` and a review looking for exactly them.
- **An option a call does not take.** `proc.run { cwdd = "x" }` raises
  `PROC usage`, not silently but late: an error path may not reach that line
  until production.

Error **domains** are not checked, only the codes inside a domain kuu owns.
`err.new` is public and a project names its own, so an unfamiliar domain says
nothing about correctness.

All four follow a module indexed where it is required as readily as one
reached through a local binding, so `require("rt").version == "0.5"` is
reported and so is `require("proc").run { cwdd = "x" }`. The two dead branches
above are of that shape, and upgrading is what found them. A computed
`require(name)` is still left alone.

<a id="kuu-page-upgrading-010-check-reads-a-projects-own-modules-too"></a>

### `check` reads a project's own modules too

`require "tools.project"` used to be checked only for resolving to a file. Its
exports are now read from the module's text, so the calls through it are
checked too:

```text
build.lua:4: p.ensure_dirs is not a name in tools.project; did you mean p.ensure_dir?
```

In a consuming project this is the larger half of the checking; one project
reaches through a single such module 210 times, and nothing verified any of
them. Project code is still never executed. The exports come from what a
module assigns to the table it returns — the `function M.name` and `M.name =`
forms.

The extraction over-approximates on purpose, because a field wrongly included
costs a missed diagnostic while one wrongly excluded is a false positive on
correct code. So a module whose export set cannot be bounded is left unchecked
entirely rather than guessed at: a computed key (`M[name] = ...`), a
metatable, a return that is not a plain local, or a local that was not built
as a table in that file.

To settle whether a `name` finding is real, ask for the same set the checker
used:

```lua
local check = require "check"
local exports = check.exports("tools/project.lua")
for name in pairs(exports or {}) do print(name) end
```

If the name you wrote is absent from that set and the module really does
export it, the extraction has a shape it cannot read, and that is a defect
worth reporting rather than working around: the workaround — making the
module's table unreadable, which any of the four shapes above does — switches
off checking of that module, so every real typo through it goes quiet too. If
`check.exports` returns nil, the module is already unchecked and the finding
came from somewhere else.

<a id="kuu-page-upgrading-010-checkerrorkind-has-three-more-members"></a>

### `CheckError.kind` has three more members

This is the one change that can break a program. `kuu check --json` documents
its error kinds as a closed set, and the set grew from three to six:

```typescript
kind: "read" | "syntax" | "name" | "code" | "option" | "value"
```

`code`, `option` and `value` are new; `value` carries both the closed-set
comparison and `rt.version` compared by text. A consumer that switches on
`kind` and has no default branch now falls through on a real finding. Warning
kinds gain `tool`, for the two things [Tools](#kuu-page-tools) describes; a reader
of warnings needs the same default branch.

With `--fix`, the report gains `fixed` and `unfixed` arrays. They are absent
otherwise, so nothing that does not ask for fixing sees them. See
[check](#kuu-page-check) for the full schema.

<a id="kuu-page-upgrading-010-kuu-check---fix-writes-the-global-declaration"></a>

### `kuu check --fix` writes the global declaration

New, and nothing changes for a project that does not run it. It adds the
standard names a chunk uses and removes the ones it does not, then checks the
files again so the report describes what is on disk.

```text
kuu check --fix [--adopt] [PATH ...]
```

**It writes files, and with no PATH it writes every `.lua` file below the
nearest project root.** Name the paths, or run it on a clean tree. It rewrites
only the declaration block: the rest of each file, its line endings included,
is left byte for byte.

Removal is the direction that matters: forgetting to add a name is a loud
load-time error that fixes itself, while forgetting to remove one when its
last use goes is silent forever, so a hand-kept list rots in one direction
only. Its first run over kuu's own tree removed 62 dead names and added none.

It knows nothing about Lua's scoping rules, because the compiler already does,
and **a name is only ever added when this runtime has a global by that name**.
A fixer that declared whatever the compiler complained about would answer
`print(reuslt)` by declaring `reuslt`, turning a caught mistake into a silent
nil; such a file is reported as not fixed, with the reason, and left alone
with its error intact. A file with no global declaration at all is untouched
unless `--adopt` is given.

<a id="kuu-page-upgrading-010-kuu-capabilities-says-what-is-here"></a>

### `kuu capabilities` says what is here

New, and **provisional**: it sits outside the planned 1.0 freeze until a
project has driven it, so treat its output as useful rather than promised.

```text
kuu capabilities [--json]
```

It exists because the answer was scattered across the manual, `kuu list` and a
project's own Lua, and an agent that assembles it wrongly writes code against a
module that is not there. It reports the verbs, every public module and the
names it exports, the error domains and closed sets, and the project's tasks
and its own modules. It does not report what a task installs under `.tools`,
because kuu keeps no manifest of it.

**It runs `manifest.lua`** to read the tasks, exactly as `kuu run` and `kuu list`
do. The module half is read from text and never executed, but the task half is
project code running. That matters if you point it at a checkout you do not
know. See [capabilities](#kuu-page-capabilities).

<a id="kuu-page-upgrading-010-texttrim-and-the-pattern-it-replaces"></a>

### `text.trim`, and the pattern it replaces

```lua
text.trim(s)            -- without leading or trailing blanks
text.trim(s, "left")    -- or "right", or "both", the default
```

It removes the six bytes Lua's `%s` matches, from one end or both, and returns
the string itself when there is nothing to trim. A Unicode space that is not
one of the six is kept, exactly as `%s` would keep it.

It is here because the obvious spelling is a trap. `$` fixes where a match
must end, but not where the matcher starts looking: only `^` does that. So
`s:gsub("%s+$", "")` is retried from position 1, then 2, then 3, and costs a
scan of the whole string rather than a look at its end. Trimming a 15-byte
line 300,000 times measured 300 ms by that pattern and 13 ms through `trim`;
trimming a 278 KB document 200 times, 3.2 seconds against 26 ms.

Worth grepping your own code for `$")` — the shape is a trap wherever it
appears, not only in a trim. `s:find("%.lua$")` is a scan where
`s:sub(-4) == ".lua"` is a comparison. The result is the same either way; only
the cost differs. [Pitfalls](#kuu-page-pitfalls) carries the entry.

Inside kuu the same fix took `csv.encode` from 303 ms to 183 on 50,000 rows
and `ini.decode` from 171 ms to 88 on 20,000 keys, with the quoting and
trimming decisions unchanged. `ini.decode` reached 69 once it called `trim`
itself; `csv.encode` still uses its own byte test.

<a id="kuu-page-upgrading-010-rtverbs-and-rtpages"></a>

### `rt.verbs` and `rt.pages`

`rt.verbs()` is the verbs kuu carries as programs, sorted; `docs` and
`version` are answered in C before that dispatch and are not in it, so
`kuu --help` remains the complete usage. `rt.pages()` is the manual's page
names, sorted, as `kuu docs PAGE` takes them, without the `.md`.

Also in a program: `check.exports(path)` is the set of names a module exports
(`set[name] == true`), **or nil** when its text does not bound them — the case
the extraction bails on, so test for nil before indexing. `check.modules(root)`
returns `{ root, files, modules }`, where `files` counts every `.lua` file
below the root and `modules` lists only those whose exports were bounded, each
as `{ name, path, exports }` with `exports` a sorted array.

<a id="kuu-page-upgrading-010-what-checks-require-listing-is-not-evidence-of"></a>

### What `check`'s require listing is not evidence of

Not a change, but newly written down, and it bears on a tool this release
makes more useful. `check` says its require listing is how an agent sees what
a file asks for before running it. For one shape of file it is not.

`_ENV` is an upvalue rather than a global, so it is in scope always and needs
no declaration. Under `global none` with nothing declared, `_ENV.require
"proc"` reaches the whole palette, and `kuu check --json` reports that file
with `"requires":[]`, no errors and no warnings.

The `require` gate holds for a program that does not reach around it. If you
are reading a file's requires as evidence about an unfamiliar program, treat a
`_ENV` reference as disqualifying. See
[observed shortcomings](#kuu-page-shortcomings).

<a id="kuu-page-upgrading-010-an-unknown-option-is-refused-everywhere"></a>

### An unknown option is refused everywhere

Fourteen calls accepted an option they did not know and went on as if it had
not been given: `fs.dirs`, `fs.glob`, `hash.sum`, `hash.file`,
`text.tobase64`, `time.iso`, `time.make`, `json.encode`, `archive.list` (with
`pack` and `unpack`), `ini.encode`, `csv.encode`, `csv.decode`, `proc.find`,
and `proc.detach` given a `maxout` it never honoured. A misspelt `prune`
walked the whole tree; a misspelt `pretty` printed compact JSON; a misspelt
`month` made January. Each now raises `usage` in its own domain, naming the
key, as `fs.read` and `proc.run` always did. Six more refused the key but
called it `badvalue`: `evt.read`, `sys.signature`, `task.defaults`, the
`limits` table of a `proc` command, `pty.spawn`, and an attribute a `cli`
spec entry or a task declaration cannot hold. Those raise `usage` now, and
`badvalue` keeps its one meaning, a known option with a wrong value.

A program that never misspelt an option sees nothing. One that did has been
running with that option silently dropped, and now stops at the line; the
message names the key.

<a id="kuu-page-upgrading-010-the-raise-or-return-rule-applied"></a>

### The raise-or-return rule, applied

[err](#kuu-page-err) now states where the line falls: a function whose job is to
validate or convert input returns for input that fails; one that assumes its
input is well formed raises. A sweep of every module against that line found
these on the wrong side of it.

- `hash.file` returned `nil, err` for a path `fs` refuses — drive-relative,
  a device, a trailing dot or space, not UTF-8 — where `fs.read` of the same
  path raises. It raises now, `HASH badvalue` or `HASH encoding`, in the same
  words. A caller that tested the second value for a malformed path must
  wrap the call in `pcall`; a caller that passed well-formed paths sees
  nothing.
- `cli.duration` and `cli.size` returned a bare `nil` for text they could not
  parse. They return `nil, err` with `CLI badvalue` now, so the reason can be
  shown. Nothing that tested the first value changes.
- `fs` took a path holding a NUL byte and used the part before it —
  `fs.exists("a.bin\0zzz")` said the file was there — where `hash` and `sys`
  refused. Every path, name, prefix and encoding `fs` takes raises
  `FS badvalue` for a NUL now.
- `proc.run`, `proc.start` and `proc.detach` returned `nil, err` for a
  command, path or environment entry that is not UTF-8, where every other
  module raises for the same mistake; they raise `PROC encoding` now. An
  environment naming one variable twice (`a` and `A`) is refused as
  `PROC badvalue` before the launch, and a `cwd` spelled in a way Windows
  would silently rewrite — drive-relative, a trailing dot or space — is
  refused as `fs` refuses it. A program not on `PATH`, a working directory
  that is not there, and Windows refusing the launch are still returned.
- `proc.alive` answered `false` and `proc.kill` returned `nil, err` for a pid
  outside the range, where `proc.find` and `proc.tree` raise; all four raise
  `PROC badvalue` now, and 0 is a pid to all four.
- `sys.signature` raised for a directory where `fs` and `hash` return for the
  wrong kind of object; it returns `nil, SYS badvalue`. `fs.read` of a
  directory was `FS access` in Windows' words; it is `nil, FS badvalue`
  saying what it is.
- `http.get` with a `to` whose directory is not there raised `HTTP oserror`,
  with the literal word `to` where the path belonged; it returns
  `nil, HTTP notfound`, or `access`, naming the path, as `fs.write` does.
- Out of memory raises everywhere; `sys`, `evt`, `svc` and `archive`
  returned it from some calls and raised from others.

`re` and `text` stay as they were: a subject that is not UTF-8 raises in
`re`, which assumes text, and returns from `text.decode`, which exists to say
whether bytes are text. The rule explains both.

---

<a id="kuu-page-upgrading-09"></a>

<a id="kuu-page-upgrading-09-upgrading-to-09"></a>

## Upgrading to 0.9

This page records the historical 0.9.0 release. From 0.11, published versions
use two components again; [upgrading to 0.11](#kuu-page-upgrading-011) describes
the current format and compatible numeric guards.

0.9.0 is the last release before the 1.0 freeze, and it exists to correct
contracts while correcting them is still allowed. It carries one breaking
change every project must act on — the version now has three components — and
one defect fix that removes an intermittent failure from every atomic write.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, **replace the minimum-version guard as described
below**, run `kuu check`, and run the project's tasks. For earlier releases,
read [upgrading to 0.8](#kuu-page-upgrading-08), [to 0.7](#kuu-page-upgrading-07), and the
[0.6 duration migration](#kuu-page-upgrading-06).

<a id="kuu-page-upgrading-09-the-version-is-majorminorpatch"></a>

### The version is Major.Minor.Patch

`rt.version` now reads `0.9.0` rather than `0.9`. A frozen 1.x needs a way to
ship a single correction without claiming new capability, and the component is
far cheaper to add before the freeze than after it.

**This breaks every guard written against the published pattern.** Releases
through 0.8 documented

```lua
local major, minor = rt.version:match("^(%d+)%.(%d+)$")
```

which does not match `0.9.0`. A project carrying it does not merely mis-compare:
`major` is nil, the guard's own assertion fires, and the project refuses this
runtime and every later one, whatever minimum it asks for. The failure is loud
and immediate rather than silent, but it happens before any task runs.

Replace the pattern with `rt.version_at_least`, which compares components and
never asks a project to parse the version text:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 9),
  "this project requires kuu 0.9.0 or later; found " .. rt.version)
```

`rt.version_at_least(major [, minor [, patch]])` answers whether the running
kuu is that version or newer. An omitted component is zero, so
`rt.version_at_least(1)` means 1.0.0. A component that is not a natural number
raises `RT badvalue`. Because it compares numbers, 0.10 correctly follows 0.9
and 1.0 follows both.

A project that must accept both 0.8 and 0.9.0 during a migration can ask for
the function before using it:

```lua
local rt = require "rt"
local recent = rt.version_at_least ~= nil
  and rt.version_at_least(0, 9)
```

`rt` is inside the planned 1.0 freeze, which is why `version_at_least`
arrives now rather than after it.

<a id="kuu-page-upgrading-09-atomic-writes-no-longer-fail-transiently"></a>

### Atomic writes no longer fail transiently

`fs.write` renames a temporary over its target, and that rename failed
intermittently with `FS access`, Windows error 5. On Windows a scanner or an
indexer routinely opens a file the moment its handle closes, and the rename of
a freshly written temporary loses that race. One process is enough to
reproduce it: 15 of 2000 single-process writes failed that way on the owner's
machine, and each one succeeded on an immediate second attempt. The same
defect made `mem.update` fail under concurrency and left the suite red.

The rename is now retried, up to six attempts over a few tens of milliseconds,
and only for access-denied and sharing-violation. After the change, 4000
writes failed none. Nothing else moved:

- No permission is bypassed. A target that genuinely cannot be replaced still
  fails with `FS access`, only later. A target somebody holds open past the
  window still fails, and that remains the intended answer.
- Atomicity is unchanged. Each attempt either replaced the target or left it
  alone, so a reader still sees the old bytes or all of the new ones.
- A caller that measured the timing of a failing write will see it take longer
  to fail. Success timing is unaffected in the common case.

See [fs](#kuu-page-fs) for the contract and
[observed shortcomings](#kuu-page-shortcomings) for the evidence.

<a id="kuu-page-upgrading-09-a-pruned-directory-leaves-fsdirss-paths"></a>

### A pruned directory leaves `fs.dirs`'s `paths`

`fs.dirs` emitted a pruned directory into `paths` and skipped only its
descent. The plain walk — list the files of every path — therefore read exactly
the content the prune was asked to exclude. Two independent programs made that
mistake within an afternoon, which is evidence about the shape rather than
about their authors.

From 0.9.0 a pruned directory is reported in a new `skipped` array and is
never in `paths`. `dirs` still equals `#paths`, and `pruned` still counts
them.

```lua
local d = fs.dirs("C:/work", { prune = { ".*" } })

-- 0.8: d.paths included C:/work/.git, and this read its files
-- 0.9.0: it does not, and this reads what was asked for
for _, dir in ipairs(d.paths) do
  for _, e in ipairs(fs.list(dir).entries) do ... end
end

d.skipped   -- { "C:/work/.git", ... }   new
```

A caller that wants the old list can concatenate `paths` and `skipped`. A
directory stopped by the `depth` cap, or a link not followed, is unaffected
and stays in `paths`: those are the frontier the walk was asked to stop at,
not names it was asked to exclude.

<a id="kuu-page-upgrading-09-jsonobject-gives-an-object-a-decided-key-order"></a>

### `json.object` gives an object a decided key order

New, and nothing changes for code that does not use it. A Lua table has no key
order, so until now no kuu program could emit a canonical document — a
manifest, a lockfile, a golden fixture — without writing its own emitter
around `json.encode`. Every project that needed one wrote a different one, and
the freeze would have made that permanent.

```lua
json.encode(json.object {
  { "tool",    "sigil" },
  { "version", "1" },
  { "count",   14 },
})
-- {"tool":"sigil","version":"1","count":14}
```

It marks a table as `json.array` does, nests at any depth, and `json.object {}`
encodes as `{}`. `json.is_object` tells one apart. Each entry must be a
two-element `{ key, value }` pair with a string key; anything else raises
`JSON badvalue` naming the entry. Decoding is untouched — order is a property
of writing, not of the value — so a document read back is an ordinary table.

<a id="kuu-page-upgrading-09-schedclock-resolves-below-a-microsecond"></a>

### `sched.clock` resolves below a microsecond

It read the event loop's millisecond tick, so the smallest difference two
readings could show was exactly 1 ms and nothing under roughly 50 ms could be
measured honestly. It now reads the performance counter: measured on the
owner's machine, the smallest observable difference fell from 1 ms to about
500 ns.

Its meaning is unchanged — monotonic seconds from an arbitrary epoch, where
only differences mean anything — so this is precision rather than a new
contract. Code that rounded a reading to whole milliseconds will now see
fractions.

<a id="kuu-page-upgrading-09-three-modules-leave-the-planned-freeze"></a>

### Three modules leave the planned freeze

`svc`, `evt`, and `sys.signature` arrived in 0.7 and have no real-project
adoption evidence behind them. Service state machines, event-log queries, and
Authenticode trust are easy surfaces to shape wrongly, and freezing a wrong
shape would cost the whole 1.x line. They join `pty` as provisional, outside
the freeze, and are brought in at 1.1 with evidence behind them.

Nothing is removed from the executable and no call changes. Only the
compatibility promise is withheld; see the
[stability statement](#kuu-page-stability).

---

<a id="kuu-page-upgrading-08"></a>

<a id="kuu-page-upgrading-08-upgrading-to-08"></a>

## Upgrading to 0.8

0.8 lowers the Windows 11 minimum to **23H2** and fixes a memory-lifetime
defect in the JSON duplicate-key diagnostic. Windows Server still requires
2025 or later. The public Lua API is unchanged from 0.7, and `pty` remains
provisional and outside the planned 1.0 freeze.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, run `kuu check`, and run the project's tasks.
Projects using 0.7 features can keep their existing minimum-version guard;
projects deployed to 23H2 should require 0.8 or later. For earlier releases,
also read [upgrading to 0.7](#kuu-page-upgrading-07) and the
[0.6 duration migration](#kuu-page-upgrading-06).

<a id="kuu-page-upgrading-08-windows-11-23h2"></a>

### Windows 11 23H2

The signed 0.7 executable imports `ReleasePseudoConsole`, which 23H2 does
not provide, and fails before any Lua program can run. In 0.8 that function
is resolved only when the host exports it. The original 0.7 release asset
and checksum remain unchanged.

On 23H2, console shutdown uses independent close and output-drain workers.
Natural close waits for the entire supervised job and preserves final
output. Explicit close finishes canceled I/O before handing the pipe to a
native drainer; resize is refused once shutdown can begin. Newer Windows
versions retain their existing release and asynchronous-close path. See
[pty](#kuu-page-pty) for the lifetime contract.

Queued I/O completions also keep a stable dispatch key after their owner is
released, so a Lua finalizer can run another process during shutdown without
accessing freed console state.

<a id="kuu-page-upgrading-08-json-diagnostics"></a>

### JSON diagnostics

`json.decode` now formats a duplicate-key error while the parser still owns
the key's bytes. Previously it freed those bytes first, causing a use after
free while constructing the message. Duplicate keys still return
`nil, err` with domain `JSON` and code `duplicate`.

The [observed shortcomings](#kuu-page-shortcomings) record the compatibility
validation and unresolved intermittent file-access and process-tree checks.
This release does not claim to resolve those separate findings.

---

<a id="kuu-page-upgrading-07"></a>

<a id="kuu-page-upgrading-07-upgrading-to-07"></a>

## Upgrading to 0.7

0.7 adds the last planned capabilities before the 1.0 freeze: child resource
limits, scoped deadlines, default task timeouts, services, event logs,
signature verification, palette-name checking, and provisional console
automation through `pty`.

Copy the new executable into the repository root, read the changes below,
run `kuu check`, and run the project's tasks. Numeric durations remain
seconds, as in 0.6. A project still on 0.5 also needs the
[0.6 duration migration](#kuu-page-upgrading-06).

<a id="kuu-page-upgrading-07-windows-11-23h2-compatibility"></a>

### Windows 11 23H2 compatibility

The published, signed 0.7 executable cannot start on Windows 11 23H2 because
it imports a newer console API. Use [0.8 or later](#kuu-page-upgrading-08) on that
OS. The original 0.7 release asset and its checksum have not been replaced.

<a id="kuu-page-upgrading-07-existing-programs-and-reports"></a>

### Existing programs and reports

| 0.6 form or behavior | 0.7 form or behavior |
|---|---|
| `local fs = require "fs"; fs.exist(path)` passed the checker and failed when called | `kuu check` reports an error and suggests `fs.exists`; correct the export name |
| Require-like text inside comments or strings could be reported by the scan | Requires and palette accesses are found from tokens and lexical bindings; quoted text, comments, shadowed loaders, and project-module fields are excluded |
| Check findings carried `line` and `message` | They also carry `kind`; name errors carry `module`, `name`, and an optional `suggestion` |
| `task.exec(spec)` wrote its console/stream settings into `spec` | The call copies the argv/options table; callers must not depend on those incidental writes |
| A project repeated a `timeout` on each `task.exec` or wrote a wrapper to add one | `task.defaults { timeout = "10m" }` supplies it centrally; an explicit call timeout still wins |
| Recipes often required `rt.version == "0.6"` | Use a numeric minimum version for the features the recipes need; copying a newer release need not change that minimum |

The checker treats a direct local module binding conservatively. It skips a
binding reassigned anywhere and follows lexical shadows instead of guessing
at the value. Dynamic indexing, aliases passed through other variables, and
project-module exports are not inferred. It checks names, not arity or types.
See [check](#kuu-page-check) for the exact report schema and limitations.

`task.defaults` currently accepts only `timeout`. A malformed duration or an
unknown field raises `TASK badvalue` without replacing the preceding default;
an empty table clears it. It bounds each child of `task.exec`, not the entire
task or dependency plan. Numeric values are seconds and zero is a valid
explicit timeout. See [Tasks](#kuu-page-task), including the exact `run --json`,
`run --dry-run --json`, and `list --json` schemas.

The schemas describe the existing output boundaries too: task output under
`run --json` goes to stderr through `print`, `io.write`, and `task.exec`;
direct `io.stdout` writes can still mix with the envelope. `list --json`
requires quiet top-level task declarations. Malformed runner options and
missing paths can fail before a JSON report exists, as documented per verb.

<a id="kuu-page-upgrading-07-new-capabilities"></a>

### New capabilities

- **Child limits.** `proc.run`, `proc.start`, and `task.exec` accept
  `limits = { memory = "512M", cpu = "30s", processes = 8 }`. The bounds
  apply to the child's whole job: committed bytes, user CPU seconds, and
  simultaneously active processes including the first child. When a bound
  is breached, a process result has `status = "limit"` and
  `limit = "memory" | "cpu" | "processes"`. If you opt into limits, handle
  that status as a failure regardless of `code`. `task.exec` returns
  `TASK failed` and names the breached bound. [proc](#kuu-page-proc-limits)
- **Scoped deadlines.** `sched.deadline(duration, fn, ...)` returns the
  function's results unchanged or `nil, SCHED deadline` when its waits
  exhaust the scope. Nested scopes use the earliest deadline. This cannot
  interrupt CPU-only Lua, and spawned tasks do not inherit it. A child is
  not automatically killed by the scope: hold a `proc.start` handle in a
  `<close>` local when its lifetime must end on unwind. [sched](#kuu-page-sched-deadlines)
- **Services.** `svc.list`, `status`, `start`, `stop`, `restart`, and `wait`
  inspect and control the Service Control Manager. State transitions poll
  on the event loop. Access failures are explicit and may require elevation;
  a timeout stops waiting without undoing the request. [svc](#kuu-page-svc)
- **Signatures.** `sys.signature(path [, options])` distinguishes unsigned
  files, accepted embedded Authenticode signatures, and rejected signatures
  with a reason. Match the signer or pinned certificate thumbprint before
  running an installer. Windows catalog-only signatures report unsigned;
  revocation/network retrieval are off unless requested. [sys](#kuu-page-sys-syssignature)
- **Event logs.** `evt.logs` lists channels and `evt.read` returns bounded
  newest-first snapshots filtered by time, level, and provider. A record has
  typed system fields and a rendered message, with raw XML as the fallback.
  It never writes or clears a log. [evt](#kuu-page-evt)
- **Interactive consoles.** `pty.spawn` creates a supervised ConPTY child.
  Its handle offers Lua-pattern `expect`, raw reads, a plain-text view,
  writes, resize, wait, kill, and close. The view is a small VT filter rather
  than a terminal screen model. This module remains provisional and outside
  the future 1.x freeze. [pty](#kuu-page-pty)

The [cookbook](#kuu-page-cookbook) has ten complete programs using these APIs and
the existing palette. Its extracted programs are checked by the suite;
safe fixtures exercise downloads, logs, process control, INI edits, service
decisions, signatures, and console input. The [PowerShell map](#kuu-page-powershell)
includes the new operations.

<a id="kuu-page-upgrading-07-version-guards-and-verification"></a>

### Version guards and verification

Use the numeric minimum-version guard from [Stability](#kuu-page-stability) or the
complete [adoption example](#kuu-page-adopting). A guard tests the capabilities
required; the project still chooses and verifies its executable explicitly.
The stability page names the modules and verbs that will freeze at 1.0,
what a 1.x release may add, and what requires a new major version.

The consistency pass documents complete error-code sets, option contracts,
and JSON schemas. It also clarifies existing boundaries such as the
same-Windows-session scope of named locks and ASCII case matching in INI
keys; those clarifications do not introduce new runtime behavior.

For kuu's own development, `make gate` runs the suite, GCC analysis, parser
fuzzing, and soak. The fuzz corpus now covers CSV, INI decode and edits,
JSON, and registry key text. `make asan` uses a separately pinned MSYS2
CLANG64 toolchain to build and run a test executable with AddressSanitizer.
It is separate from `gate` and required by the release checklist.
[Toolchain](#kuu-page-toolchain) records the packages and commands.

---

<a id="kuu-page-upgrading-06"></a>

<a id="kuu-page-upgrading-06-upgrading-to-06"></a>

## Upgrading to 0.6

0.6 is the release that carries the 0.5 review fixes and the fixes from the
first real repository driven by kuu.
Keep `kuu.exe` directly in the project root and declare the supported runtime
version in `tasks.lua`. The previous 0.5 review fixes are included.

<a id="kuu-page-upgrading-06-duration-migration"></a>

### Duration migration

`cli.duration` and CLI entries with `type="duration"` now return **seconds**,
the same numeric unit accepted by `proc`, `sched`, `http`, `sync`, and `net`.
For example, `100ms` returns `0.1`; `2s` returns `2`.

- Divide old duration `min`, `max`, and numeric `choices` by 1,000.
- Numeric defaults already represented input seconds; keep them unchanged.
- Remove conversions such as `opts.timeout / 1000` before a process call.
- Remove workarounds such as `tostring(opts.timeout) .. "ms"`.
- Multiply a result by 1,000 only when deliberately calling an API that wants
  milliseconds. Native Kuu duration APIs already want seconds.

The string grammar and millisecond rounding remain shared with `time.duration`.
If an unusually large duration must preserve an exact integer millisecond count,
keep the unit-bearing string and pass it directly to the consuming native API.

Time Actual accepts 0.5 and 0.6 with explicit compatibility branches; its CI
pins the 0.6 release.

<a id="kuu-page-upgrading-06-other-changes"></a>

### Other changes

- `kuu version` and `kuu --version` print the same identity and reject extra
  arguments. Use `kuu ./version` to execute a script literally named `version`.
- `task "all" {deps={"build", "test"}}` needs no empty `run` function.
- `proc.list`, `proc.find`, and `proc.tree` return `exe` with forward slashes.
  Command lines remain verbatim; path aliases still require `fs.canon` identity.
- Archive listings preserve Unicode names and embedded newlines. They use the
  Windows archive library in a supervised copy of Kuu, rather than tar's ANSI
  text output. ZIP packing explicitly selects UTF-8 headers too.
- TLS client-key and proxy failures report `HTTP tls` and actionable details.

Windows' Tcl sandbox behavior and tools that construct their own shell commands
remain external boundaries; see [observed shortcomings](#kuu-page-shortcomings).

