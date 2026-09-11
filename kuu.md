# kuu

This document is the single place where kuu is explained: what the runtime is
today at 0.9.0 and what was learned building it and its two predecessors. It
exists because that understanding was scattered across three repositories, a
roadmap, an inheritance register, a shortcomings log and a decision record,
and none of those answer the question *why is it like this* in one reading.

kuu is a runtime for Lua 5.5, and only that. It does not define a language,
and it will not: what it grows are capabilities in the palette, and options on
the calls that are already there.

Nothing here is a promise about compatibility. The compatibility posture is
still being designed and is deliberately left open; where 0.9.0 changed
something, the change is described, not ratified.

This file carries the complete manual as **Part III**, so everything kuu knows
about itself can be read in one sitting without querying the executable.

---

## Where things stand

**kuu 0.9.0 is released.** Tagged on the tested commit, signed, published, and
verified: the gate, the sanitizer gate and the publish gate all green, three
clean soaks, and the downloaded asset, its sidecar and the local signed file in
agreement with the released binary reporting its own certificate identity. A
consuming project adopted it the same day with its checks passing.

The version break landed as predicted. A project carrying the guard published
through 0.8 — `rt.version:match("^(%d+)%.(%d+)$")` — refuses 0.9.0 and every
later release, because that pattern does not match three components. Migrating
to `rt.version_at_least` is the fix, and it is the one thing an existing
project must do.

**What is open** is design, not work in progress. The 1.0 criteria remain the
owner's to set. There is no half-finished work to pick up, and the intent is to
take the time to get the design right and correct course where needed.

---

## Start here

Parts I and II explain *why*. **Part III is the complete manual**, every page
inlined, so this one file answers both kinds of question and nothing needs to
be fetched before reading. Coming to kuu cold, read in this order:

1. **Pitfalls** — Part III's first module page, and the one an agent's existing
   Lua knowledge most needs. It is the delta between the Lua you know and this
   runtime, plus the Windows facts kuu refuses to hide. Read it once, before
   writing anything.
2. **Parts I and II**, for why the runtime is shaped as it is.
3. **The rest of Part III**, as reference, when you need a signature.

If you would rather read everything in one pass than navigate, that is what
this file is for: Part III is the whole manual in a deliberate order, beginning
with the map and Pitfalls and ending with the record of decisions.

The same manual also lives inside the executable, where it always matches the
binary in front of you:

```text
kuu docs                       the page list
kuu docs fs                    one page
kuu docs search "junction"     find lines across all pages
kuu --help                     the verbs
```

Running, checking, and driving a project:

```text
kuu FILE [arg ...]             run a program
kuu -e SCRIPT [arg ...]        run an inline script
kuu check [--json] PATH ...    syntax, globals, requires, palette names
kuu run [--dry-run] [TASK]     a task from the nearest tasks.lua
kuu list                       those tasks
```

Building and verifying kuu itself, from the repository root:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8       build build/kuu.exe
.tools\msys2\ucrt64\bin\mingw32-make.exe test      the suite
.tools\msys2\ucrt64\bin\mingw32-make.exe gate      test, analyze, fuzz, soak
```

### Where things are written down

| | |
|---|---|
| `kuu.md` (this file) | why kuu is shaped this way, what was learned, where it is going |
| `README.md` | the short introduction and the build |
| `docs/` — 40 pages, shipped inside the executable | the reference: one page per module, plus the pages below |
| `docs/pitfalls.md` | what an agent's Lua priors get wrong here. Read once, first |
| `docs/adopting.md` | how a repository comes to be driven by kuu: `tasks.lua`, prerequisites by URL and hash |
| `docs/powershell.md` | each cmdlet you would reach for, and the kuu call that replaces it |
| `docs/cookbook.md` | ten complete programs, extracted and checked by the suite |
| `docs/roadmap.md` | decisions and milestones, with their reasons |
| `docs/inheritance.md` | what kuu carried over from its predecessors, each item sourced |
| `docs/shortcomings.md` | problems found in real use, with evidence and status |
| `docs/stability.md` | the compatibility posture — still under design |
| `docs/upgrading-0.N.md` | what changed in a release and what a project must do |
| `notes/` | dated handoff and validation records; not shipped |

Two habits worth forming early. `kuu check` finds misspelled names, unresolved
`require`s and wrong palette names without running anything — use it before
running, not after. And when a result surprises you, the manual page for that
module is usually more specific than a guess: the palette documents its
refusals as carefully as its successes.

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

By the numbers, 0.9.0 is 16,461 lines of authored host C, 2,724 lines of kuu's
own Lua, a suite of 1,062 checks in 4,320 lines, and 4,692 lines of manual that
ships inside the executable. The palette is 26 modules and 98 registered
functions, plus methods on handles.

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
global. The verbs are `run`, `list`, `check`, `docs` and `version`.

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
declares a repository's work in a `tasks.lua` that `kuu run` executes.
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
never presents a silent partial result. Every omitted branch is an `errors` row
with the raw Windows code; every dropped event raises `dropped`; every
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

A repository copies `kuu.exe` into its root and writes one `tasks.lua`. That
file states the minimum version it needs, lists its prerequisites by URL and
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
There is no PowerShell anywhere in the repository.

Verification is layered and all of it runs locally:

- `make test` — the suite, 1,062 checks.
- `make analyze` — GCC's static analyzer over every authored host file, with
  warnings as errors.
- `make fuzz` — deterministic parser fuzzing, 10,000 cases per family across
  durations, dates, paths, CSV, INI, JSON and registry text, plus command
  lines, on fixed seeds.
- `make soak` — repeated full runs watching handle counts and private bytes.
- `make asan` — a separate build under Clang's AddressSanitizer, a required
  release check.
- `make gate` — the first four in order.

## Where 0.9.0 stands

0.9.0 is a correction release. It changed contracts while changing them was
still cheap, rather than adding capability.

- **Versions gained a patch component.** `rt.version` now reads `0.9.0`. The
  guard published through 0.8 matched `^(%d+)%.(%d+)$`, which does not match
  three components, so every project carrying it would have refused this
  runtime and every later one. `rt.version_at_least(major, minor, patch)`
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

**What vendoring costs.** kuu's 1.48 MB executable is, by object weight:

```
lua     716K   the language
pcre2   644K   regular expressions
yyjson  300K   JSON
host    632K   kuu's own code
```

Only 632 K is kuu. The rest is batteries Lua does not ship, carried as 4.4 MB
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

## kuu

kuu is a Lua 5.5 runtime for agents on Windows: one static executable that
runs a Lua program and gives it native control over processes, files, the
network, services, and event logs. It is built for agents, so the manual is short
and exact: this is how kuu behaves, not how Lua works. Lua 5.5 itself is
assumed; the one page you need about the language here is
[Pitfalls](#pitfalls).

kuu runs on Windows 11 version 23H2 and later, and Windows Server 2025 and
later. The runtime uses native Windows process, console and filesystem APIs.
Console shutdown adapts to the older 23H2 lifetime contract; the Lua API is
the same on every supported version.

This is version 0.9.0: the runner, the scheduler with scoped deadlines,
processes with resource limits (its own children and the others on the machine), files, JSON, CSV, INI, HTTP, archives,
hashing, text encodings, regular expressions, time, logging, argument
parsing, a repository's tasks, a memory across runs, the machine's own facts,
the registry, the environment, services, event logs, signature verification,
and the network as seen from here. The provisional `pty` drives interactive
console programs; `check` verifies names exported by the palette. It is the
tool an agent holds on a Windows machine instead of PowerShell; the
[From PowerShell](#powershell) page maps one to the other. The
[roadmap](#roadmap) records what is planned and why, and
[inheritance](#inheritance) records what kuu learned from its predecessors.

### Running a program

```text
kuu FILE [arg ...]        run a Lua program file
kuu - [arg ...]           run a program read from standard input
kuu -e SCRIPT [arg ...]   run an inline script
kuu docs [PAGE | search TEXT]   this manual, from inside the executable
kuu run [--json] [--dry-run] [TASK [arg ...]]   a task from the nearest tasks.lua      (see Tasks)
kuu list [--json]         those tasks
kuu check [--json] [PATH ...]   syntax, globals, requires, palette names, without running  (see check)
kuu version | --version | --help
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
-- 0.9.0  Lua 5.5.1  file  C:\work\app\kuu.exe  build.lua  2
rt.version_at_least(0, 9)   -- true: this runtime is 0.9.0 or newer
```

`rt.route` is `"file"`, `"stdin"`, `"eval"`, or `"cmd"` for a verb such as
`run`. `rt.program` is the path as given for the file route, the verb for the
cmd route, and nil otherwise. `rt.root([dir])` reads or moves the directory
`require` searches after kuu's own modules; `rt.source(name)` is the text of
one of kuu's own Lua modules.

### Modules

A program gets capabilities by naming them: `require` is the gate. A Lua file
that requires nothing has only what stock Lua's `io` and `os` give it: files
by path, the environment, the clock, and exit. Processes, the network,
hashing, and every other organ are behind `require`.

| module | gives |
|---|---|
| [`proc`](#proc) | children with decided lifetimes and resource limits: run, start, wait, kill, detach; the other processes: list, find, tree |
| [`fs`](#fs) | files, directories, identity, links, walks, watches, with Windows truth |
| [`http`](#http) | fetch and post over WinHTTP, with the machine's proxy and certificates |
| [`sched`](#sched) | tasks, sleep, a monotonic clock, wall time, scoped deadlines |
| [`json`](#json) | strict decoding and exact encoding |
| [`hash`](#hash) | digests, HMAC, random bytes |
| [`text`](#text) | strict conversion between UTF-8 and Windows encodings |
| [`log`](#log) | structured lines that never interrupt the work |
| [`cli`](#cli) | a program's arguments, declared once |
| [`err`](#err) | the one error shape and how to test it |
| [`task`](#task) | a repository's tasks and default child timeout, declared once in `tasks.lua`, run by `kuu run` |
| [`check`](#check) | syntax, global declarations, require resolution, and palette names without running project code |
| [`archive`](#archive) | zip and tar archives through the tar.exe Windows ships |
| [`sys`](#sys) | facts about this machine and process, embedded Authenticode signatures |
| [`svc`](#svc) | inspect, start, stop, restart, and wait for Windows services |
| [`evt`](#evt) | read and filter Windows event logs |
| [`pty`](#pty) | interactive console children and Lua-pattern expect; provisional |
| [`mem`](#mem) | a small memory across runs, one JSON file per project |
| [`sync`](#sync) | one at a time across processes: a named lock |
| [`re`](#re) | regular expressions on PCRE2, with Unicode and named groups |
| [`time`](#time) | instants, zones, ISO 8601, durations |
| [`net`](#net) | the network from here: resolve, probe, listeners, addresses |
| [`csv`](#csv) | comma-separated values, RFC 4180 and the Windows variants |
| [`ini`](#ini) | INI files: read, write, and edit in place |
| [`reg`](#reg) | the registry, typed |
| [`env`](#env) | environment variables, live and persisted |
| `rt` | the launch: version, executable, route, program, arguments, the require root |

`require` searches `package.preload`, where these live, and then the program's
directory: `require("a.b")` tries `a/b.lua`, then `a/b/init.lua`, below the
directory of the program file, or below the current directory for the stdin
and inline routes. Module files follow the same decoding rules as programs.
Environment variables such as `LUA_PATH` are never consulted and C modules are
never loaded; `package.path` and `package.cpath` are empty strings to make that
visible.

### Output and input

Standard input, output, and error are binary. What a program writes with
`print`, `io.write`, or `io.stderr:write` leaves the process byte for byte, with
no CRLF translation and no re-encoding. Text is UTF-8 by convention, and the
C runtime's file functions (`io.open`) and `os.getenv` take and return UTF-8.
A terminal set to another code page will show UTF-8 bytes wrongly; a pipe will
not.

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
`badvalue`, `toobig`, `encoding`, `stdin`, and `oserror`.

### Pages

- [From PowerShell](#powershell): each cmdlet an agent reaches for, and the
  kuu call that replaces it.
- [Pitfalls](#pitfalls): what differs from the Lua an agent already knows,
  and the Windows facts kuu refuses to hide.
- [Adopting kuu](#adopting): a repository gets its own kuu.exe, a
  tasks.lua, and prerequisites by hash; nothing on the machine.
- [Cookbook](#cookbook): ten complete programs for common automation jobs.
- [Stability](#stability): the future 1.x contract and minimum-version guards.
- [proc](#proc), [fs](#fs), [http](#http), [net](#net),
  [sched](#sched), [json](#json), [csv](#csv), [ini](#ini),
  [re](#re), [time](#time), [hash](#hash), [text](#text),
  [reg](#reg), [env](#env), [sys](#sys), [svc](#svc), [evt](#evt),
  [pty](#pty), [sync](#sync),
  [mem](#mem), [archive](#archive), [log](#log), [cli](#cli),
  [err](#err): the modules.
- [Tasks](#task): `tasks.lua`, `kuu run`, `kuu list`, and the exit codes.
- [check](#check): what `kuu check` finds without running a file.
- [Toolchain](#toolchain): what kuu's own `.tools` holds and where it comes
  from.
- [Upgrading to 0.9](#upgrading-09): the version grows a patch component,
  which breaks the old pattern guard; `rt.version_at_least` replaces it. The atomic
  write retries its rename, and three modules leave the planned freeze.
- [Upgrading to 0.8](#upgrading-08): Windows 11 23H2 support and the JSON
  duplicate-key diagnostic fix, with the same Lua API.
- [Upgrading to 0.7](#upgrading-07): deadlines, child limits, services,
  signatures, event logs, name checking, and provisional pty.
- [Upgrading to 0.6](#upgrading-06): duration units and adoption fixes.
- [Observed shortcomings](#shortcomings): reproductions, fixes, and external limitations.
- [Roadmap](#roadmap): decisions taken and milestones ahead.
- [Inheritance](#inheritance): laws, traps, and contracts carried over from
  machteld, the z estate, and the archived projects.

---

## Pitfalls

What an agent's priors get wrong here. kuu embeds PUC Lua 5.5.1 unchanged,
compiled as C, so the Lua 5.5 reference manual holds; this page is the delta
between the Lua most agents know and this runtime, plus the Windows facts kuu
refuses to hide. Read it once.

### Lua 5.5 differences from 5.4 habits

- **`global` is a contextual keyword.** A statement beginning with `global`
  followed by a name, `none`, `*`, `function`, or an attribute is a global
  declaration. Elsewhere it is an ordinary name (kuu keeps Lua's default
  compatibility setting), so `local global = 1` still works. Avoid the name.
- **Any global declaration switches the chunk to declared-only mode**, and
  then every free name must be declared, `print` included. `global none` is
  the declaration that adds nothing and exists only to switch. kuu recommends
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

### What kuu removed or changed

- **Absent by design:** `io.popen`, `os.execute`, `os.remove`, `os.rename`,
  `os.tmpname`, `dofile`, `loadfile`, `package.loadlib`, and the `debug`
  library except `traceback` and `getinfo`. Processes belong to
  [`proc`](#proc), files to [`fs`](#fs). `io.open` remains and takes
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

### Errors kuu itself prints

Every message kuu produces has the shape `DOMAIN code: text`, and the codes
are listed per module page. `kuu docs search CODE` finds the page.

---

## Adopting kuu in a repository

How a repository comes to be driven by kuu: one executable of its own, one
`tasks.lua`, and a list of prerequisites it fetches itself. Nothing is
installed on the machine, nothing is shared between repositories, and
nothing is looked up on `PATH`.

```text
repo/
  tasks.lua          the tasks, and the prerequisites as url and sha256
  kuu.exe            this project's own runtime; git ignores it
  .tools/            downloads and unpacked tools; git ignores it
  .kuu/              kuu's notebook for this repository (mem); git ignores it
  build/             outputs; git ignores it
  src/               whatever the repository is about
```

The examples require 0.7 or later. Read [upgrading to 0.7](#upgrading-07)
when moving from 0.6; a repository still on 0.5 also needs the
[duration migration](#upgrading-06).

### 1. Give the repository its kuu

Copy `kuu.exe` directly into the repository root. It comes from a
[release](https://github.com/anafalanx/kuu/releases), signed, with a
`kuu.exe.sha256` beside it, or from a build. That copy is the only kuu this
repository knows; another repository has its own, possibly another
version. There is no installer and no bootstrap script, because copying a
small file needs neither.

Add to `.gitignore`:

```text
/kuu.exe
/.tools/
/.kuu/
/build/
```

### 2. Write tasks.lua

`tasks.lua` sits at the repository root. It states the minimum kuu version
it needs, lists the prerequisites, and declares the tasks. [Tasks](#task)
has the full contract; this is the shape:

```lua
global none
global <const> require, ipairs, print, error

local NEED_MAJOR, NEED_MINOR = 0, 9

local rt = require "rt"
local task = require "task"
local http = require "http"
local archive = require "archive"
local fs = require "fs"
local hash = require "hash"
local err = require "err"

if not rt.version_at_least(NEED_MAJOR, NEED_MINOR) then
  error(err.new("PROJECT", "version", "requires kuu 0.9.0 or later, found " .. rt.version .. "; copy a supported kuu.exe into the repository root"))
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
local MAKE = ".tools/msys2/ucrt64/bin/mingw32-make.exe"

task "prereqs" {
  desc = "fetch the tools by hash into .tools",
  run = function()
    if fs.exists(MAKE) == "file" then return end
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
  run = function() return task.exec { MAKE, "-j8" } end,
}

task "test" {
  desc = "run the tests",
  deps = { "build" },
  run = function() return task.exec { "build/tests.exe" } end,
}

task "clean" {
  desc = "remove build/",
  run = function() fs.remove("build", { recursive = true }) end,
}

task.default "test"
```

Three habits make this work:

- **Prerequisites are a list, not a system.** A url and a sha256 per file.
  `http.get { to, sha256 }` refuses a file whose hash differs and places
  nothing; `archive.unpack` opens tar, zip, and zst archives with the tar
  Windows ships. Hashes come from upstream's checksum files or from a first
  fetch inspected by hand; once written down they pin the file forever.
- **Tools are called by path**, `.tools/...`, never by name. `PATH` is
  whatever the machine has today; the repository does not depend on it.
- **A task fails by returning `nil, err`** or by a child's exit code
  through `task.exec`. `kuu run` turns that into an exit code and, with
  `--json`, into a record another program can read.

### 3. Run it

```text
.\kuu.exe run                  the default task, with its dependencies
.\kuu.exe run test             a named task
.\kuu.exe run --dry-run test   the plan: what would run, in order, running nothing
.\kuu.exe run --json test      the outcome as one JSON object on stdout
.\kuu.exe list                 every task with its description and arguments
.\kuu.exe check                tasks.lua and the repository's Lua, without running anything
```

Exit codes: 0 when the task returned, a child's nonzero code when `task.exec`
failed, 1 for another task failure, and 2 when kuu could not start it.
`kuu check` catches an unknown palette export or an undeclared global and
warns about unresolved modules before anything runs, so run it first after
editing.

### 4. Keep state, take turns, ask the machine

- [`mem`](#mem) is a small notebook per repository in `.kuu/memory.json`:
  the last build's hash, a counter, a note for the next run.
- [`sync`](#sync) is a named lock across processes, for the task that two
  agents must not run at once.
- [`sys`](#sys) says what machine this is; [`env`](#env) sets variables
  for the children a task starts; [`proc`](#proc) runs them with decided
  lifetimes and finds the ones already running; [`net`](#net) tells
  whether the service came up.
- [`svc`](#svc) inspects and controls services; [`evt`](#evt) reads the
  event logs. [`sys.signature`](#sys) verifies an embedded
  Authenticode signature before a project runs an installer.
- [`sched.deadline`](#sched) bounds a sequence of waits, while
  `task.defaults` and [`proc` limits](#proc) bound the children.
  The [cookbook](#cookbook) has complete programs for these jobs.

### 5. Upgrading kuu

Copy the new `kuu.exe` over the old one in the repository root, read the
intervening upgrading notes, run `check`, and run the tasks. Raise
`NEED_MAJOR` and `NEED_MINOR` only when the recipes begin to require a newer
feature. Compare the components numerically: 0.10 is newer than 0.9. The
[stability statement](#stability) defines this minimum guard and the future
1.x promise; the [roadmap](#roadmap) lists what changed per version.
Repositories upgrade one at a time; there is no machine-wide state to keep
in step.

### What not to do

- Do not put kuu on `PATH`, and do not share one `.tools` between
  repositories. The point is that each repository stands alone.
- Do not commit `kuu.exe`, `.tools`, `.kuu`, or `build`.
- Do not write a bootstrap script to fetch kuu. A repository's README says
  "copy kuu.exe into the repository root" and that is the whole procedure.
- Do not fetch a prerequisite without its hash. If upstream publishes none,
  fetch once, hash with `hash.file("sha256", path)`, and write it down.

---

## Tasks

A repository declares its tasks once, in a `tasks.lua` at its root, and runs
them with `kuu run`. There is no second file to keep in step: the task list,
each task's description, its dependencies, and its arguments live in the
declaration, and `kuu list` reads them back from there.

```lua
-- tasks.lua
local task = require "task"
local fs = require "fs"

task.defaults { timeout = "10m" }

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
    return task.exec { ".tools/zig/zig.exe", "build", opts.release and "-Doptimize=ReleaseFast" or "-Doptimize=Debug" }
  end,
}

task "test" {
  desc = "run the suite",
  deps = { "build" },
  run = function() return task.exec { "build/app.exe", "--self-test" } end,
}

task.default "build"
```

```text
kuu run                      the default task, after its dependencies
kuu run test                 test, after build, after gen; each runs once
kuu run build --release      arguments after the task name go to that task
kuu run --json test          the same, with one JSON object on stdout at the end
kuu run --dry-run test       the plan, in order, arguments checked, nothing run
kuu list [--json]            the tasks, their descriptions, dependencies, and arguments
```

### Where kuu looks

`kuu run` and `kuu list` walk up from the current directory to the nearest
directory holding `tasks.lua`, make that directory the current directory, and
point `require` at it. A task's relative paths are therefore relative to the
project root wherever the command was typed, children started by a task begin
there, and `require "lib.helper"` in `tasks.lua` reads `lib/helper.lua` of the
project. Without a `tasks.lua` anywhere above, both verbs exit 2 with
`TASK noproject`.

### Declaring

`task "name" { ... }` takes a plain word (letters, digits, `.`, `_`, `-`) and
a table with these attributes; anything else is refused at declaration, as is
declaring a name twice.

| attribute | meaning |
|---|---|
| `desc` | one line for `kuu list` |
| `deps` | names to run first, each once, in dependency order; a cycle is `TASK cycle` naming the chain, an unknown name is `TASK unknown` saying who needed it |
| `args` | a [cli](#cli) spec for the arguments after the task name; checked when declared, so a broken spec fails `kuu list` too |
| `run` | `function(opts)`; `opts` is the parsed arguments, or an empty table; optional when `deps` is non-empty |
| `hidden` | left out of `kuu list`; still runs by name |

A task may group dependencies without doing additional work:

```lua
task "all" { deps = { "build", "test" } }
```

An aggregate follows the same planning, argument validation, failure propagation,
and JSON reporting rules. Shared dependencies still run once. A declaration
with neither a function nor non-empty dependencies is refused.

`task.default "name"` names what `kuu run` alone runs; without it, `kuu run`
alone lists the tasks and exits 2.

`tasks.lua` is an ordinary Lua chunk and its top level runs on every `kuu run`
and `kuu list`, so keep work inside `run` functions. A syntax error or a raise
while declaring is reported with its line and exits 2.

### Running and failing

A task succeeds by returning nothing. It fails by raising, or by returning
`nil, err`. The runner prints one line per task on standard error when it
finishes, `kuu: build 1.2s`, and on failure names the task and the error.
Dependencies that already ran are not run again, and nothing after a failed
task runs. Every argument is checked before anything runs: the named task's
against its spec, and each dependency's spec against no arguments. So
`--help`, a wrong argument, or a dependency that requires an argument exits 2
with nothing started.

```lua
run = function(opts)
  return task.exec { "gcc", "-O2", "main.c", "-o", "build/app.exe", timeout = "5m" }
end
```

`task.defaults { timeout = "10m" }` gives every `task.exec` a default
child timeout. A duration string uses the same units as `proc`, and a number
is seconds. An explicit `timeout` in the call wins, including zero.
`task.defaults {}` clears the default. Each call replaces the preceding
defaults; only `timeout` is accepted, and a malformed duration or unknown key
raises `TASK badvalue` without changing the preceding setting. Settings are
copied, so later changes to the declaration table do not alter the default.
This bounds each child, not the whole task or its dependency plan; use
`sched.deadline` for a scope containing several waits.

`task.exec` runs a child on kuu's own console, so its output streams through
as it happens; under `--json` it streams to standard error instead. It takes
the same table as `proc.run` (`cwd`, `env`, `timeout`, `maxout`, `limits`)
and returns `true`, or `nil, err` with `TASK exit` and the child's code in
`err.exit`, which `kuu run` then uses as its own exit code. A child that timed
out, was killed, or hit a job limit is `TASK failed`. The caller's argv and
options table is never modified, in either console or JSON mode.
The `limits` table has `memory` (bytes or a size string), `cpu` (seconds or
a duration string), and `processes` (a positive count); see
[proc limits](#proc). To capture output instead, use
[proc.run](#proc) directly and decide for yourself.

| exit | meaning |
|---|---|
| 0 | every task returned |
| the child's code | a `task.exec` child exited non-zero |
| 1 | a task raised or returned `nil, err` |
| 2 | no `tasks.lua`, a broken `tasks.lua`, an unknown task or dependency, a cycle, or wrong arguments |

### JSON

`kuu run --json` (the flag before the task name) prints one JSON object on
standard output when it ends, and nothing else there: `print` and `io.write`
from tasks are redirected to standard error, and the output of a `task.exec`
child is streamed to standard error as it arrives, whatever `inherit` the
task asked for, with no cap on its size. Only a direct `io.stdout:write`
bypasses this, and then the task itself has broken the contract.

```json
{"ok":true,"result":{"root":"C:/work/app","task":"test",
  "tasks":[{"name":"gen","seconds":0.01,"ok":true},{"name":"build","seconds":3.2,"ok":true},{"name":"test","seconds":0.8,"ok":true}]}}
```

These structural schemas use `?` for an omitted optional field. Arrays are
present even when empty; a field is never replaced with `null` merely because
it is optional.

```typescript
type RunError = { domain: string; code: string; message: string; exit?: number };
type TaskRun = { name: string; seconds: number; ok: boolean };
type RunReport =
  | { ok: true; result: { root: string; task: string; tasks: TaskRun[] } }
  | { ok: false; result: { root?: string; task?: string; tasks: TaskRun[] };
      error: RunError };
type DryRunReport = {
  ok: true;
  result: { root: string; task: string;
    plan: { name: string; desc: string; deps: string[] }[] };
};
```

`root` is absolute. `tasks` lists completed attempts in execution order,
including the failed task; it is empty for a failure before execution.
Failure fields `root`, `task`, and `error.exit` appear only when supplied by
that failure path. The process exits as in the table above even when
`error.exit` is absent. A successful `--dry-run --json` produces
`DryRunReport`; its failure uses the failed `RunReport` shape. A dry run
still loads declarations and validates every task's arguments.

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
    }[] } }
  | { ok: false; error: { domain: string; code: string; message: string } };
```

The `default` task name is omitted when none is declared. Arguments carry
their declared default and choices, not parsed values; bounds such as
`min` and `max` are not included. `tasks.lua` must keep its top level quiet
for `list --json` because that verb does not redirect declaration output.
Malformed command-line options are rejected with a diagnostic on stderr
before either verb builds a JSON report. `--help` before the task name
prints usage and exits 0; task-specific `--help` is a `CLI usage` failure.

### The module in a program

The same module drives the verbs and is open to programs that build on them.
The registry is the module, so a program that loads a `tasks.lua` with `load`
after `require "task"` sees its declarations.

```lua
local task = require "task"
task.all()                 -- the declared tasks, in declaration order
task.get("build")          -- one entry: name, desc, deps, args, run, hidden
task.default_task()        -- the default's name, or nil
task.plan("test")             -- the entries to run, in order | nil, err
task.arguments(entry, args)   -- the arguments parsed against its spec: opts | nil, err
task.execute(entry, opts)     -- run it with parsed arguments: true | nil, err
```

| code | meaning |
|---|---|
| `TASK noproject` | no `tasks.lua` here or above |
| `TASK badvalue` | a bad declaration, or `tasks.lua` failed to load |
| `TASK usage` | no task or default was selected, or a runner option is unknown |
| `TASK unknown`, `TASK cycle` | the dependency graph |
| `CLI usage` | wrong arguments for a task, or `--help` |
| `TASK failed` | a task raised something that is not an `err`, or its child did not exit normally |
| `TASK exit` | a `task.exec` child exited non-zero; `err.exit` is the code |

Errors returned or raised by `proc` while starting a child keep their
original domain and code; [proc](#proc) lists them. A job limit produces
`TASK failed` with its kind in the message, such as `limit (memory)`.

---

## check

`kuu check` says what can be known about Lua files without running them, and
nothing more.

```text
kuu check [--json] [PATH ...]
```

Without paths it checks every `.lua` file below the nearest project (the
directory holding `tasks.lua`), or below the current directory when there is
no project, skipping `.git`, `.tools`, `build`, and `node_modules`. Paths may
be files or directories; `require` names always resolve against the project
root.

Four things are checked:

- **It parses.** Each file goes through Lua 5.5's own compiler, text only, the
  way kuu would load it. A syntax error is reported with its line. Under a
  global declaration (`global none`, or any `global` statement), the compiler
  also refuses an undeclared global, so the classic typo is an error here.
- **It declares its globals.** A file with no `global` statement at all gets a
  warning, because in that file an undeclared global is silently nil at run
  time. [Pitfalls](#pitfalls) says how to start a file.
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
the checked file or loads a project module. A project module's fields and
dynamic indexing such as `files[name]` are left alone.

Name checking follows direct local require bindings and lexical scopes.
Parameters, block locals, and loop variables can shadow an alias. If an
alias is reassigned anywhere, its field accesses are skipped throughout
that binding's scope, including captured uses in functions. This avoids
claiming to know a value that control flow may replace. Aliases passed
through another variable, function arguments, or a function result are not
inferred. Shadowing or reassigning `require` likewise stops treating it as
kuu's loader in that scope.

Four things are checked against kuu's own interface, and all four are
mistakes that run without complaint today. A code its domain does not have,
so `err.is` answers false for every error and the handler it guards is dead:
`err.is(e, "PROC", "notfund")`. An option a call does not take:
`proc.run { cwdd = "x" }`, which the runtime raises on, but only if the line
is reached. A closed set compared with a literal outside it, such as
`rt.route == "flie"`, which likewise never matches. And `rt.version` compared
by text, which no project should do since the version grew a third component;
use `rt.version_at_least`.

Error *domains* are not checked, only the codes within a domain kuu owns.
`err.new` is public and a project names its own domains, so an unfamiliar one
says nothing about correctness.

Beyond these, no call is type-checked: argument counts, option values, and
types still belong to runtime validation.

```text
bad.lua:1: unexpected symbol near '='
strict.lua:2: variable 'print' is not declared
app.lua:12: "notfund" is not a code in PROC, so this never matches; did you mean "notfound"?
app.lua:19: cwdd is not an option of proc.run; did you mean cwd?
app.lua:24: rt.version is Major.Minor.Patch and is never compared by text; use rt.version_at_least(...)
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
  ok: boolean; // true exactly when result.errors is zero
  result: {
    root: string; // absolute path
    files: {
      path: string; // relative to root when under it, otherwise as reported
      errors: CheckError[];
      warnings: CheckWarning[];
      requires: string[]; // unique, sorted literal module names
    }[];
    errors: number; // total error count
    warnings: number; // total warning count
  };
};
type CheckError =
  | { kind: "read" | "syntax"; line: number; message: string }
  | { kind: "name" | "code" | "option" | "value"; line: number; message: string;
      module: string; name: string; suggestion?: string };
type CheckWarning = {
  kind: "globals" | "require"; line: number; message: string;
};
```

Each error and warning carries `line` (0 when it is about the whole file) and
`message`. The closed set of error kinds is `read` (cannot read the file),
`syntax` (Lua compilation, including undeclared globals), `name` (an unknown
palette export), `code` (an error code its domain does not have), `option`
(an option a call does not take), and `value` (a closed set compared with a
literal outside it, `rt.version` compared by text included). Warning kinds
are `globals` (no declaration) and `require` (unresolved module). For `name`,
`code`, `option` and `value`, `module` and `name` identify what was written
and `suggestion` is the nearest real spelling, omitted when none is close.

Exit 0 or 1 produces this envelope, with no summary on stderr. Invalid
command arguments or an explicitly named path that does not exist exit 2
before a report is available and print a diagnostic on stderr, even with
`--json`; `--help` prints usage and exits 0.

In a program, `require("check").file(path, root)` returns
`{path, errors, warnings, requires}` with an absolute `path` and the same
finding kinds. `check.tree(dir, root)` returns `{root, reports = {...}}`.

### Errors

The command's complete `CHECK` code set is `notfound`, for an explicitly
named path that is neither a file nor a directory. Invalid command arguments
use `CLI usage`. The checking module returns findings rather than `nil, err`;
a file-read failure is a `read` finding containing the underlying `FS`
diagnostic. Filesystem argument errors retain their original domain and code.

---

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
`rest`. Results are keyed by the name without dashes.

On the command line: `--name value` and `--name=value` both work; a flag is
`--all`, `--all=false`; `--` ends options; `--help` is always accepted and
comes back as `opts.help = true`, waiving missing required values but not
malformed ones.

Parsing never prints and never exits. A wrong command line is `nil, err` with
`CLI usage`, whose message names the problem and ends with the generated usage
text, ready to print. A wrong spec raises `CLI badvalue` immediately: an
unknown attribute or type, a default that fails its own type, two entries on
one key, `--help` redeclared, a flag as a positional, or a positional after the
rest entry.

```lua
cli.usage(spec, "watchit")   -- the text: usage line, arguments, options with defaults and ranges
cli.duration("1.5s")         -- 1.5; nil when it is not a duration
cli.size("16M")              -- 16777216
```
Duration arguments and `cli.duration` use the native runtime's grammar,
including sums (`"1h30m"`, `"1m 30s"`) and days (`"2d"`). Results are
seconds; an invalid duration returns nil. Numeric defaults, `min`, `max`,
and `choices` for durations use seconds too. `proc`, `sched`, `http`, `sync`,
and `net` accept these numbers directly, without conversion:

```lua
local opts = assert(cli.parse(require("rt").args, {
  { "--timeout", type = "duration", default = "30s", min = 0.001 },
}))
local r = require("proc").run { "tool.exe", timeout = opts.timeout }
```

This changed in 0.6: 0.5 returned milliseconds. See
[Upgrading to 0.6](#upgrading-06) before reusing an older spec. Rounding and
floating-point precision match `time.duration`; results are numbers of seconds,
not exact integer millisecond counts at arbitrarily large magnitudes.

The complete CLI code set is `usage` (returned for invalid command-line
arguments) and `badvalue` (raised for an invalid specification). `duration`
and `size` return nil for text they cannot parse.

---

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
current directory; a name with a separator is used as given; names without an
extension try `.exe`, `.com`, `.bat`, `.cmd`. Arguments are quoted for the
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
| `badvalue` | a bad option value (`nil, err` for `cwd` that does not exist; raised for a malformed value) |
| `encoding` | a name is not valid UTF-8 |
| `usage` | raised: no command, a wrong argument shape, an unknown option |
| `oserror` | a job, pipe, or another launch resource could not be created |

Unknown option names raise rather than pass silently, so a typo cannot
become a run with the wrong settings.

`run` accepts `cwd`, `env`, `timeout`, `stdin`, `maxout`, `inherit`, and
`limits`; `start` additionally accepts `stream`. An omitted `timeout` has
no time limit; zero requests an immediate timeout. `inherit` and `stream`
default to false. Environment names are compared ignoring case: duplicates,
empty names, `=`, and NUL are refused, as are NUL bytes in text values.

### Limits

```lua
proc.run { "build.exe", timeout = "10m",
  limits = { memory = "512M", cpu = "30s", processes = 8 } }
```

`limits` applies to `run`, `start`, and `task.exec`. All three bounds are
job-wide, across the child and its descendants: `memory` is committed bytes,
`cpu` is accumulated user-mode CPU time, and `processes` is the number alive
at once, including the initial child. Each optional bound must be positive;
unknown names and malformed bounds raise `PROC badvalue`. An empty table
sets no bounds. `detach` does not accept limits.

Windows refuses allocations and child creation that exceed memory and process
limits; kuu terminates the job when the corresponding notification arrives.
The kernel terminates a job that exhausts its CPU time. The result has
`status = "limit"` and names the bound in `limit`. `timeout` is independently
elapsed wall-clock time; keep it when a child can wait without using CPU.
An intentional breakaway still follows the rules described under `detach`.

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

### Streams

```lua
local c <close> = proc.start { "tool.exe", stream = true }
c:write("first line\n")          -- queued to the child's stdin; true, or nil, PROC closed | toobig
c:close_stdin()                  -- EOF for the child once the queue has drained
c:read("line", "5s")             -- the next stdout line without its ending; nil at EOF
c:read(4096)                     -- up to that many bytes, once at least one is there
c:read("some")                   -- whatever has arrived, once anything has
c:read("all")                    -- everything to EOF
c:read_err("line")               -- the same for stderr
for line in c:lines() do ... end -- stdout lines to EOF; c:err_lines() likewise
```

In stream mode the program reads the pipes itself, so `wait` reports the exit
with empty `out` and `err`. Reads that must wait park the calling task and
accept a timeout, returning `nil, err` with `PROC timeout` while the data stays
buffered. One task at a time may read a given stream; a second raises
`PROC busy`. `maxout` becomes the backpressure point: when that much is unread,
kuu stops reading and the child blocks on its write until the program catches
up, so nothing is ever truncated. Closing the child wakes a parked reader with
`PROC closed`. A child that does not read its stdin is not an error; a child
that never gets its stdin closed may never exit, so `close_stdin` when you are
done.

The stdin queue has its own fixed 64 MiB bound, independent of `maxout`.
`write` returns `nil, PROC toobig` when a write cannot be queued within it.

### The console

```lua
proc.run { "vim", "notes.md", inherit = true }
```

With `inherit = true` the child receives kuu's own standard handles: colours,
pagers, prompts, and Ctrl-C reach it as if it had been started from the
terminal, with every supervision guarantee intact. Nothing is captured; `out`
and `err` are empty. It cannot be combined with `stdin` or `stream`.

### Waiting on several children

```lua
local first, result = proc.wait_any({ a, b, c }, "1m")   -- the handle and its result
local results = proc.wait_all({ a, b, c }, "10m")        -- results in the order given
```

Both return `nil, err` with `PROC timeout` when the duration passes; the
children keep running. Children that already finished answer at once.

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

### proc.alive and proc.kill

```lua
proc.alive(pid)        -- true while a process with that id runs
proc.kill(pid)         -- true, or nil, PROC notfound | access | oserror
```

For processes kuu did not start. `kill` terminates one process, not a tree;
use a supervised child when the tree matters.

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
| `started` | when the process began, an instant for [`time`](#time) |
| `cpu` | seconds of kernel plus user time so far |
| `memory`, `private` | the working set and the private bytes |

The last six need the process opened for querying and are absent when this
user may not: system processes, another user's, protected ones. `find`
returns a list, empty when nothing matches; looking for something that is
not there is not an error. It takes exactly one of `name`, `pid`, `port` and
raises PROC badvalue otherwise. `tree` answers `nil, PROC notfound` for an
unknown pid. Process ids are reused, so a `parent` may name a process that
exited long ago and whose id now belongs to something unrelated.
Tree expansion stops after 64 levels; a deepest entry then has no expanded
children.

### Complete error codes

| PROC code | when |
|---|---|
| `notfound` | a command or requested process does not exist |
| `launch` | Windows refused to start the command |
| `access` | `kill` cannot open the process for termination |
| `badvalue` | malformed arguments or option values; usually raised, but returned for a refused working directory or invalid `kill` pid |
| `encoding` | a command, path, environment entry, or process-name filter is not UTF-8 |
| `usage` | raised: an invalid call shape, unknown option, incompatible stream modes, or a read/write without stream mode |
| `timeout` | a child wait, stream read, `wait_any`, or `wait_all` outlasted its wait duration |
| `closed` | raised for a closed handle; returned when stdin is closed or a pending read's handle closes |
| `busy` | raised: another task is already reading that stream |
| `toobig` | stdin could not queue the write within its 64 MiB bound |
| `oserror` | Windows, snapshot, or allocation failure |

Waiting can also propagate the scheduler's `SCHED` errors, including
`deadline`; see [sched](#sched). Child results with `status = "timeout"`,
`"killed"`, or `"limit"` are result states, not error codes.

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

### Tools that construct their own commands

Kuu preserves the argument vector it passes to a child. A child may construct
another command string internally. For example, Windows `windres` uses a shell
for its preprocessor by default and can split checkout paths containing spaces.
Use its `--use-temp-file` mode and relative resource/include paths from a build
directory. Quoting only the original Kuu argument cannot repair that internal
command. Process metadata's `cmdline` stays verbatim; only `exe` is normalized.
Use `fs.canon` identity when different path spellings or aliases must compare equal.

---

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
`.` or a space. Refusals of the path itself raise `FS badvalue`; a path that is
not there is `nil, err` with `FS notfound`.

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
torn file. It creates `name.kuu-<pid>-<tick>.tmp` in the same directory and
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
link and its target is untouched. Read-only files are removed.

### Listing and walking

```lua
local l = fs.list("src")
for _, e in ipairs(l.entries) do print(e.name, e.kind, e.size, e.mtime) end
#l.errors        -- names that could not be represented, listings cut short

local d = fs.dirs("C:/work", { depth = 3, prune = { "node_modules", ".git" } })
d.root           -- as walked
d.paths          -- every directory entered, depth-first, siblings in UTF-8 byte order
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
reported in `skipped` and `pruned` instead, and the plain walk below reads
nothing the prune was asked to exclude:

```lua
for _, dir in ipairs(d.paths) do
  for _, e in ipairs(fs.list(dir).entries) do ... end
end
```

Through 0.8 a pruned directory appeared in `paths` and only its descent was
skipped, so that loop listed the files of every excluded directory. Two
independent programs made exactly that mistake. A directory stopped by the
`depth` cap, or a link not followed, does stay in `paths`: those are the
frontier the walk was asked to stop at, not names it was asked to exclude.
See [upgrading to 0.9](#upgrading-09).

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

### Errors

| FS code | when |
|---|---|
| `notfound` | the path is not there |
| `dangling` | the path is a link whose target is not there |
| `access` | denied, or the file is in use |
| `exists` | the target exists and `replace` was not given, or `mkdir` met a file |
| `notempty` | `remove` on a non-empty directory without `recursive` |
| `toobig` | `read` above `maxbytes` |
| `encoding` | a name cannot be represented |
| `badvalue` | raised for a refused path or option value; `nil, err` for a wrong kind of object |
| `usage` | raised: an unknown option |
| `timeout` | `watch:read` waited its whole duration |
| `closed` | raised: a closed watch was used |
| `oserror` | anything else, with the Windows message |

`read` with `encoding` keeps conversion failures in the `TEXT` domain, as
documented in [text](#text). A surrounding `sched.deadline` can interrupt
a watch read with `SCHED deadline`; it does not preempt synchronous file I/O.

---

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

### Options

| option | default | meaning |
|---|---|---|
| `timeout` | `"30s"` | the whole request, from connect to the last byte; `HTTP timeout` when exceeded; zero is refused because WinHTTP reads it as infinite |
| `maxbody` | `"64M"`, `"8G"` with `to` | the body is refused as `HTTP toobig` beyond this, never truncated |
| `to` | | stream the body into this file; written beside it as a temporary and renamed into place, so a failed download leaves the previous file untouched |
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

### Errors

| HTTP code | when |
|---|---|
| `timeout` | the request did not complete within `timeout` |
| `notfound` | the host name does not resolve |
| `connect` | the host refused or dropped the connection |
| `tls` | the certificate or the secure channel was rejected |
| `toobig` | the body exceeded `maxbody` |
| `mismatch` | the body did not hash to `sha256`; the message carries both digests |
| `status` | a non-2xx answer to a request that gave `sha256` |
| `badvalue` | raised: a malformed url, header, timeout, size, or redirect value |
| `encoding` | raised: a URL or header is not valid UTF-8 |
| `usage` | raised: an unknown option, or no url |
| `oserror` | anything else, with the Windows message |

A refused download destination path keeps the path helper's `FS` domain
(`badvalue`, `encoding`, or `oserror`) and is raised before the request starts.
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

### net.listeners

```lua
net.listeners()   -- { { port, address, family, pid, name }, ... }
```

Every TCP port with a listening socket on this machine, sorted by port, with
the address it is bound to (`0.0.0.0` or `::` for all interfaces), the owning
process id, and that process's executable name where a process by that id
still exists. The same table answers `proc.find { port = }` in
[`proc`](#proc), which gives the owner's full entry. UDP is not listed.

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

## sched

Tasks and time. The scheduler is the loop that runs every program: one thread,
one Lua state, coroutines that switch only where a palette call waits.

```lua
local sched = require("sched")
```

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

### Where waiting is not possible

A palette call parks the running coroutine by yielding. Inside a metamethod,
a `string.gsub` callback, a `table.sort` comparator, or a coroutine the program
created itself, Lua cannot yield to kuu. In those places kuu drives the loop in
place until the wait is over, so the call still returns the right thing, and
other tasks still make progress meanwhile.

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
[err](#err).

---

## json

Strict reading, exact writing.

```lua
local json = require("json")
local v, e = json.decode(text)            -- nil, err JSON parse | depth | duplicate
local s = json.encode(v)                  -- raises JSON badvalue | encoding | depth | oserror
local pretty = json.encode(v, { pretty = true })
```

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

```lua
local doc = json.decode('{"ids": [1, null, 3], "empty": {}}')
#doc.ids == 3            -- the null kept its place
doc.ids[2] == json.null
json.encode { list = json.array {}, none = json.null }   -- '{"list":[],"none":null}'
```

Integers survive exactly; a document carrying 64-bit identifiers round-trips
without loss. Integers beyond 64 bits decode as floats. Integral floats encode
with a decimal point (`2.0`), so the two number kinds do not blur.

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
string; anything else raises `JSON badvalue` naming the entry. Decoding is
unchanged: a document read back is an ordinary table, because the order is a
property of writing, not of the value.

### Refusals

Decoding is strict: a duplicate object key is `JSON duplicate` at any depth,
because last-wins would silently lose data; nesting beyond 512 is `JSON depth`;
a lone surrogate escape, trailing text, or any malformation is `JSON parse` with
the byte offset. Encoding raises for values JSON has no spelling for: NaN and
infinity, functions and userdata other than `json.null`, tables mixing array
and string keys, non-string keys, strings that are not valid UTF-8, and cycles,
which surface as `JSON depth`.

The complete code set is `parse`, `duplicate`, and `depth` for decoding;
`badvalue`, `encoding`, `depth`, and `oserror` for encoding. `oserror` means
the encoder could not allocate its document.

Output is compact by default, with the seven short escapes, lowercase
`\u00xx` for other control characters, and UTF-8 left raw.

---

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

### Errors

Domain `CSV`: `parse` (returned) and `badvalue` (raised).

---

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

### Rules

- Keys before any section header live under the empty section name, `""`.
- Keys and values are trimmed. A value in surrounding double quotes has
  them removed and the inside kept, as the Windows profile functions do;
  encode and set quote a value that would not otherwise survive.
- A line without `=` is a key with an empty value.
- There are no inline comments: everything after `=` is the value, a `;`
  included, which is what Windows does too.
- Duplicate keys: the last wins. Duplicate sections merge, ignoring case
  and keeping the first spelling of each section and key in the table.
- Values are strings; numbers and booleans given to `encode` or `set` are
  written with `tostring`.

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

### Errors

Domain `INI`, all raised: `badvalue` for a key holding `=`, a value that
spans lines, or a table that is not sections of keys.

---

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
beyond 260 characters. Ambiguous drive-relative, device, or trailing-dot/space
paths are refused; a path containing NUL raises instead of silently hashing
the filename before that byte.

| HASH code | when |
|---|---|
| `badvalue` | raised: unknown algorithm, a count out of range, an oversized key, or NUL in a filename; returned for an ambiguous path |
| `encoding` | `hash.file`: the path is not valid UTF-8 |
| `notfound`, `access` | `hash.file`: the file cannot be opened or read |
| `oserror` | file I/O failed, or raised when Windows' cryptographic provider failed |
| `closed` | raised: a finished hasher was used again |

---

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
300,000 times measured 300 ms by that pattern, 13 ms through `trim`; on a
278 KB document the pattern took 3.2 seconds against 26 ms. See
[Pitfalls](#pitfalls).

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
| `toobig` | the input is too long for Windows' case mapping |
| `oserror` | raised: allocation or Windows case mapping failed |

---

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
| `oserror` | raised: Windows could not report the zone |
Malformed text passed to `time.parse`, including signed date/time fields
or an offset beyond +/-14:00, returns `nil, TIME badvalue`. Invalid
explicit zone arguments remain programming errors and raise.

---

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
version lands where you say. `pack` replaces an existing archive; entries are
names inside the directory, never absolute and never climbing out. Windows'
bsdtar refuses archive entries that would climb out of the target directory,
so an unpack stays under the directory you name.

| code | meaning |
|---|---|
| `ARCHIVE notfound` | no archive, or no directory, at that path |
| `ARCHIVE failed` | an invalid archive, unsupported format, or rejected entry; pack/unpack retain tar's diagnostic |
| `ARCHIVE badvalue` | raised: wrong paths, a negative `strip`, or entries that leave the directory; returned for an empty directory to pack |
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

### Configuration

```lua
log.configure { level = "debug" }            -- debug, info, warn, error, off; default info
log.configure { file = "build/log.txt" }     -- append to a file; false returns to stderr
log.configure { json = true }                -- one JSON object per line: ts, level, msg, fields
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
it describes. The default sink is standard error, resolved at write time, so a
program that never logs opens nothing.

| LOG code | when |
|---|---|
| `badvalue` | raised: an unknown level, or a `file` or `sink` of the wrong kind |
| `usage` | raised: an unknown option, or a non-table argument |
| `oserror` | raised: the log file cannot be opened |

---

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

Branch on `err.is(e, "PROC", "notfound")`, never on the message text.
Messages are for people; domains and codes are for programs.

---

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
`tasks.lua` upward from the current directory, or under the directory
`require` searches when there is no project. Add `.kuu/` to the project's
`.gitignore` unless the memory is meant to travel with the repository.

Every `get` reads the file. Every `set` holds a [`sync`](#sync) lock across
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

### Errors

The complete SYS code set is `notfound` (missing signature path), `access`
(the file cannot be read or is open for writing), `badvalue` (raised for a
malformed path, a directory, or signature options), and `oserror` (other
Windows or allocation failures). `sys.info` has no expected error return.

---

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

### Errors

Domain `REG`: `notfound` (no such key or value), `access` (run elevated),
`badvalue` (raised: a bad root, type, value, or embedded NUL), `encoding`
(text cannot be represented as UTF-8), `oserror`.

---

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

### The two environments

The **live environment** is this process's copy. `set` changes it for kuu
and for every child kuu starts afterwards; nothing outside notices. A
child's `env` option in [`proc`](#proc) does the same for one child.
`get` and `os.getenv` return `""` for an empty value and `nil` for an
absent variable. Names and text values cannot contain NUL.

The **persisted environment** is what Windows hands to new processes: the
user's, under `HKCU\Environment`, and the machine's, under the Session
Manager's key. `persist` and `forget` write there and broadcast
`WM_SETTINGCHANGE`, so Explorer and every console opened afterwards see the
change. Processes already running, kuu itself included, keep their copy:
after `env.persist`, `env.get` still answers as before. A value holding a
`%` is stored as an expandstring, as Windows does for `Path`; `persisted`
returns it unexpanded with its type, and `env.expand` expands it.

To add a directory to the user's `Path`, read `env.persisted("Path")`,
edit the string, and persist it back; nothing here edits `Path` for you,
because appending blindly is how `Path` fills with duplicates.

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

### Errors

Domain `ENV`: `badvalue` (raised: an empty name, a name with `=`, an unknown
scope, or embedded NUL), `notfound` (forgetting what is not there), `access` (the machine
scope without elevation), `oserror`.

---

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

### Errors

The complete SVC code set is `notfound` (no such service), `access`
(insufficient rights), `timeout` (the target state was not observed in time),
`badvalue` (raised for malformed names, states, or timeouts), and `oserror`
(other Windows failures, including service transition failures).

---

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
cannot express that literal. Unknown options raise `EVT badvalue`.

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

### Errors

The complete EVT code set is `notfound` (unknown channel), `access`
(insufficient channel rights), `badvalue` (raised for malformed names,
options, instants, levels, or limits), and `oserror` (other Windows failures).

---

## pty -- provisional console automation

`local pty = require "pty"`

`pty` drives Windows console programs through ConPTY. It is **provisional**
and outside the planned 1.0 API freeze. Use `proc` for ordinary subprocesses.

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

### Launch and lifetime

`pty.spawn { exe, args..., cols = 120, rows = 30, cwd = path, env = table,
timeout = duration, maxout = "64M", limits = table }` returns a console
handle or `nil, err`. Dimensions must be integers from 1 to 32767. The
command, `cwd`, environment overrides/removals, lifetime `timeout`, and
job `limits` follow [proc](#proc). Without a lifetime timeout the child
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

`p:wait([timeout])` returns the [proc result](#proc), including `status`,
`code`, `pid`, `elapsed` and optional `limit`. Output is consumed through
`read`/`expect`; the result's `out` and `err` are empty. A wait timeout
returns `nil, PTY timeout` and leaves the child alive. `p:kill()` terminates
the entire child job; `wait` can still observe its result. A scope deadline
interrupts the current wait with `SCHED deadline`; it does not close `p`.

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

### Errors

The closed PTY code set is `badvalue` (invalid command/options/dimensions,
duration, or a rejected Lua pattern), `notfound` (executable), `encoding`
(invalid UTF-8 command/environment), `launch` (process creation), `busy`
(concurrent read or pending input conflict), `closed` (closed handle or EOF
before a match), `timeout` (wait expired), `toobig` (output/input bound),
and `oserror` (native operation or allocation failure). Invalid arguments
raise; operational failures return `nil, err`. An enclosing deadline raises
`SCHED deadline` internally and is caught by its `sched.deadline` scope.

---

## From PowerShell

kuu is the tool an agent holds on a Windows machine instead of PowerShell:
to set up, configure, run, test, script, control, and keep in check. This page
maps what an agent reaches for in PowerShell to the kuu call that does it,
with the differences that matter. Where kuu has nothing yet, it says so.
Process and network waits cooperate with the scheduler; file and machine
inspection calls can be synchronous, as their manual pages describe.

### Processes

| PowerShell | kuu | the difference |
|---|---|---|
| `& tool.exe args`, `Start-Process -Wait` | `proc.run { "tool.exe", "arg" }` | the child and its whole tree die when kuu does, or when `timeout` passes; exit codes are results, not exceptions |
| `$LASTEXITCODE`, `$?` | `r.code`, `r.status` | `"exit"`, `"timeout"`, `"killed"`, or `"limit"`; `r.limit` names an exhausted resource bound |
| `Start-Process` plus Windows Job Object resource limits | `proc.run { ..., limits = { memory = "512M", cpu = "30s", processes = 8 } }` | limits apply to the whole tree; CPU is user-mode time, timeout is elapsed time |
| `tool 2>&1 \| Out-String` | `r.out`, `r.err` | bytes, captured separately; beyond `maxout` the rest is dropped and `r.truncated` says so |
| `Start-Process` without `-Wait` | `proc.start { ... }` then `c:wait()` | one child per handle, closed with it |
| `Start-Process -NoNewWindow` for an interactive tool | `proc.run { ..., inherit = true }` | the child gets kuu's own console |
| an interactive tool that reads console prompts | `pty.spawn { "cmd.exe" }`, `p:expect({ ">" }, "5s")`, `p:write("echo hello\r")` | a private pseudoconsole with supervised lifetime; provisional API, see [pty](#pty) |
| `tool \| ForEach-Object { }` | `for line in c:lines() do` | live, with backpressure, no thread |
| `Start-Job`, `Wait-Job -Any` | `sched.spawn`, `proc.wait_any` | tasks are coroutines, not processes |
| `Start-Process -WindowStyle Hidden` for a daemon | `proc.detach { ... }` | the one child that outlives kuu, on purpose |
| `taskkill /T` | `c:kill()` | the child's whole tree, since every child has its own job |
| `Stop-Process -Id` | `proc.kill(pid)` | that one process, by id |
| `Get-Process`, `netstat -o`, `tasklist` | `proc.list`, `proc.find { name = "tool" }`, `proc.tree` | find also accepts one `pid` or `port`; entries carry exe, command line, start, cpu, memory when this user may ask |
| `Start-Process -Verb RunAs` | deferred | elevation needs a broker; not yet |
| `cmd /c "a \| b"` | `proc.run { "cmd.exe", "/c", "a \| b" }` | explicit; cmd re-parses its argument, see [proc](#proc) |

### Files

| PowerShell | kuu | the difference |
|---|---|---|
| `Get-Content -Raw`, `-Encoding` | `fs.read(p)`, `fs.read(p, { encoding = "cp1252" })` | bytes by default; a named encoding is decoded strictly, never repaired |
| `Set-Content`, `Out-File` | `fs.write(p, data)` | atomic: a temporary beside, then a rename; never a torn file |
| `Add-Content` | `fs.write(p, data, { append = true })` | |
| `Test-Path` | `fs.exists(p)` | says what it is: `"file"`, `"directory"`, `"link"`, `"other"`, or `false` |
| `Get-Item`, `Get-ItemProperty` | `fs.stat(p)` | identity too: volume and file ids |
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

### The machine

| PowerShell | kuu | the difference |
|---|---|---|
| `[Environment]::OSVersion`, `Get-ComputerInfo` | `sys.info()` | the truthful build, the display name, elevation, cpus, memory, drives, uptime |
| `[Security.Principal.WindowsPrincipal]…IsInRole` | `sys.info().elevated` | |
| `$env:NAME`, `[Environment]::SetEnvironmentVariable(..., 'User')`, `setx` | `env.get`, `env.set`; `env.persist`, `env.forget` with the change broadcast | live and persisted are two different things; see [env](#env) |
| `Get-ItemProperty HKLM:\...`, `Set-ItemProperty`, `New-Item HKCU:\...`, `reg.exe` | `reg.get`, `reg.set`, `reg.values`, `reg.keys`, `reg.remove` | typed: dword, qword, string, expandstring, multistring, binary |
| `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service` | `svc.list`, `svc.status`, `svc.start`, `svc.stop`, `svc.restart` | local services; transitions wait for the requested state; no service creation API |
| `Get-WinEvent`, `Get-WinEvent -ListLog *` | `evt.read`, `evt.logs` | bounded local snapshots with typed fields and filters; no log mutation |
| `Get-AuthenticodeSignature` | `sys.signature(path)` | embedded signatures only, no catalog lookup; trust failures are results, revocation checking is opt-in |
| `Register-ScheduledTask` | `schtasks.exe` through `proc.run` | deferred as a module |
| `New-Object -ComObject WScript.Shell` for shortcuts | no | desktop plumbing, not an agent's tool |
| `Enable-WindowsOptionalFeature`, `New-NetFirewallRule`, `Set-MpPreference` | no | security settings stay with the person |

### The script itself

| PowerShell | kuu | the difference |
|---|---|---|
| `param()` | `cli.parse(rt.args, spec)` | declared once; `--help` is a value, not an exit |
| `$PSScriptRoot` | `rt.root()` | |
| `Start-Sleep` | `sched.sleep("2s")` | other tasks run meanwhile |
| a shared timeout around several waiting operations | `sched.deadline("30s", fn)` | returns `nil, SCHED deadline` when a wait reaches the bound; does not preempt computing Lua or independently kill children |
| a `.ps1` per job, `Invoke-Build` | `tasks.lua`, `kuu run`, `kuu list` | dependencies once, in order; `--dry-run` shows the plan |
| a wrapper adding `-Timeout` to every command | `task.defaults { timeout = "10m" }` | a default for `task.exec`; each call can override it, including with zero; `task.defaults {}` clears the default |
| `Export-Clixml` for state between runs | `mem.set`, `mem.get`, `mem.update` | a JSON notebook per project, 1 MiB at most; update holds the lock through read, callback, and write |
| `Set-StrictMode -Version Latest` | `global none` at the top of the file | the compiler refuses an undeclared global |
| `try { } catch { }` | `nil, err` for expected failures, `pcall` for mistakes | see [err](#err) |
| `-WhatIf` | `kuu run --dry-run` | loads task declarations and shows dependency order; task bodies do not run |
| `Test-ModuleManifest`, `PSScriptAnalyzer` | `kuu check` | syntax, global declarations, `require` resolution, and misspelt known palette exports; does not check types or argument counts |

---

## Cookbook

Each block is a complete program. Save it under the indicated filename and
run it with your repository's `kuu.exe`. Inputs are positional arguments;
paths belong to the current directory unless absolute. The programs require
kuu 0.7 or later. [`pty`](#pty) is provisional.

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

### 10. Drive a prompt through pty

`kuu prompt.lua` drives `cmd.exe`'s console input, sets a value through
`set /p`, and checks the answer. `expect` consumes through the matched text
and uses Lua patterns. `text()` is the accumulated plain-text view, not a
terminal screen. See the provisional [`pty`](#pty) contract before driving
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

---

## Inheritance

What kuu carries over from machteld, the z estate, the els method, and the
archived and adjacent projects, harvested on 2026-09-09 from their sources,
retrospectives, and commit histories. Each item is a law kuu keeps, a trap it
must not fall into again, or a contract it copies. The source is named so the
reasoning can be reread. This is the register the roadmap's "learn every
lesson" instruction produces; add to it, never silently edit it.

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

## Roadmap

kuu began on 2026-09-09 as the successor to machteld, the Tcl runtime for
agents, after the owner concluded that estate-wide management had to stop and
that each project should stand alone with its own tools. The name was reused
from an earlier, archived attempt to reimplement Lua 5.5 in Go; the new kuu
embeds PUC Lua instead. This page records the decisions and the milestones.

### Decisions

| decision | choice | why |
|---|---|---|
| platform | Windows 11 23H2 and later; Windows Server 2025 and later | native Windows APIs; 23H2 console teardown uses isolated close/drain workers and completion-aware pipe ownership |
| language for programs | Lua 5.5.1, vendored, compiled as C | agents write it correctly from a hundred-page manual; coroutines make waiting read as straight-line code; `global none` turns the classic typo into a compile error; errors are `longjmp`, so C, never C++ |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.1 from MSYS2 UCRT64, copied into `.tools` | the estate's proven recipe; gcc and GNU make are the chosen production build, with Clang only for sanitizer tests |
| build | GNU make from the same `.tools`, recipes under `cmd.exe` | no PowerShell in the repository, and kuu never builds kuu: the build is make and gcc, the tests are Lua run by the built kuu |
| self-hosting | none, by owner decision | kuu is not required to bootstrap or build itself; a person with `.tools` populated runs `make` |
| versions | `Major.Minor.Patch`, all natural numbers, since 0.9.0 | 0.1 through 0.8 had no patch component; a frozen 1.x needs a way to ship one correction without claiming new capability, and the component is cheaper to add before the freeze than after it. `rt.version_at_least` compares them so no project parses the text |
| dependency pinning | none: a project fetches what it needs by url and hash with `http` and `archive`; kuu's own compiler is copied by hand | the lock built in 0.3 was removed in 0.4 as formalism; kuu does not bootstrap itself |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has only stock Lua's `io` and `os`, and a static check can list what else a file asks for |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child is born into a kill-on-close job; only `detach`, and a child's own deliberate breakaway, step outside it |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, any Tcl, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs |
| projects share nothing | every project carries its own `kuu.exe`, copied in by hand, directly in its root since 0.6 (0.4 and 0.5 put it in `.tools`); nothing on `PATH`, no machine changes, no bootstrap scripts | the owner ended estate-wide management; a small executable is copied, not fetched by glue |
| what a project may fetch | upstream downloads only, into its own `.tools`; nothing re-hosted, nothing shared between projects | no commonalities, and a stranger fetches from the same public sources |
| kuu's own repository | free of kuu: build and release are make, gcc, and cmd recipes; no `tasks.lua` there | self-reference is unwelcome, for release steps too |
| releases | anafalanx/kuu public; GitHub Releases carry `kuu.exe` and its `.sha256`; signed with the owner's existing Certum certificate through the Windows SDK's signtool | the estate already signs this way, and public releases need no credentials to fetch |
| the second project | `C:\dev\kuu-test-project`, local, no remote, tailored to test kuu features | a project built to exercise the runtime, before any existing one is converted |
| what kuu is | a Windows-only power tool in the agent's hand: set up, configure, run, test, script, control, keep in check; every feature replaces a PowerShell fumble | the agent knows its prerequisites; kuu removes the fumbling, not the knowing |
| dependencies | no lock: verification is a capability (`http.get` with `sha256`, `fs.unpack`), and the agent writes its own setup | the lock was formalism for a shared-payload world that no longer exists |
| memory across runs | `mem`, a small JSON notebook per project, Lua only, capped at 1 MiB | agents need to remember between runs; the executable stays nimble; SQLite stays out |

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
| deferred: elevated runs, `xml`, ACLs, clipboard, ICMP, scheduled tasks as a module, `kuu run --watch`, credentials and certificates, CI | later, on a real need |
| no-go: `tools.get`, `proc.shell`, YAML, templating, `text.diff`, shortcuts, Windows features, firewall, Defender, power, `kuu init`, bootstrap scripts | decided 2026-09-09 |

### Milestones

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
   supplement the regression suite. See the [migration notes](#upgrading-06)
   and [observations log](#shortcomings). Released 2026-09-10, after the cold
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
   - The [cookbook](#cookbook) gives ten complete programs, extracted and
     checked by the suite and exercised with safe fixtures. The
     [stability statement](#stability) names the future 1.x contract and
     replaces exact-version guards with numeric minimums. The module pages,
     PowerShell map, error-code sets, and JSON schemas are documented together;
     [upgrading to 0.7](#upgrading-07) records the changes from 0.6.
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
   [upgrading to 0.8](#upgrading-08) and the validation evidence in
   [observed shortcomings](#shortcomings).
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
   gate with zero failures. See [upgrading to 0.9](#upgrading-09).
10. **1.0.** Criteria for the owner to set. Proposed: three projects driven
   for a month without a runtime defect, a manual page for every module, a
   signed release cadence, and the Lua-versus-Tcl ledger closed with a
   verdict. Two amendments agreed on 2026-09-11: a **clean soak gate on every
   target host**, since freezing while it is knowingly unclean rests the 1.x
   promise on a signal nobody trusts; and **at least one cold adopter**,
   because every adoption finding on record comes from Time Actual, which
   co-evolved with the runtime and therefore routes around contract mistakes
   instead of reporting them. Between 0.9.0 and 1.0: the freeze, the month of
   use, and corrections driven by what that use finds.

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
[toolchain](#toolchain) for replay commands. Analysis also made the error
raiser's non-returning contract explicit and led to entry-allocation cleanup.

### Open decisions

- **1.0 criteria.** The proposal above stands until the owner sets them.

### Backlog

Small things, unscheduled: cancellation and a streaming body reader in
`http`; `kuu docs` as a searchable single page.

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
  `pairs` order is undefined, so `log` sorts fields and `json` objects come
  out in arbitrary key order. Minor, but felt three times in one day.
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
- **`global none` is opt-in boilerplate.** Tcl has no equivalent check at all,
  so this is a Lua advantage in the end, but every file must start with two
  lines to get it, and an agent that forgets them gets stock Lua's silent
  globals.

Nothing decisive: the pattern entry, the one to watch, closed with `re`. The
coroutine model, the byte strings, and the C API have been strengths at every
step so far.

### 0.6: fixes from real repository adoption

Time Actual exposed cross-module duration units, lossy archive names, process
path inconsistency, and task/entry friction. 0.6 uses numeric
seconds throughout, supports dependency-only tasks and `kuu version`, returns
Unicode archive inventories, writes UTF-8 ZIP headers, normalizes process
executable paths, and identifies client-key/proxy TLS failures. See
[migration notes](#upgrading-06) and the [observations log](#shortcomings).
The Tcl sandbox issue remains an execution-environment limitation. The windres
workaround belongs to the consuming build recipe and is now documented.

Cold setup testing also found and fixed `hash.file`'s long-path boundary.
The complete suite now passes 838 checks plus native analysis. Time Actual's
new recovery fixture passes 17 checks on 0.5 and 0.6; full cold toolchain and
relocation validation is paused. The [2026-09-10 handoff](notes/handoff-2026-09-10_193511.md) recorded
that pause; the remaining work was completed the same day on the second
machine, recorded in the observations log, and 0.6 was released.

---

## Shortcomings observed in real use

Findings from adopting Kuu in real repositories. Record the trigger, impact,
workaround, and verification status. A limitation or rough edge is not
necessarily a runtime defect; fixes should follow reproduced evidence.

### Time Actual adoption — 2026-09-10

0.6 addresses seven runtime/API findings below. The
Tcl sandbox limitation remains external; the windres recipe issue is resolved
in Time Actual. Original observations and 0.5 workarounds are retained for context.

#### `kuu version` executes a repository's VERSION file

- **Kind:** command-line diagnostic / discoverability.
- **Observed:** in Time Actual, `kuu.exe version` resolves the case-insensitive
  `VERSION` filename and reports `version:1: unexpected symbol near '0.58'`.
- **Impact:** an intuitive version query produces an unrelated Lua parse error.
- **Workaround:** use `kuu.exe --version`.
- **Status:** Fixed in 0.6. `version` is a reserved verb; `./version` still
  executes a file. Both version forms reject extra arguments.

#### Dependency-only tasks require an empty function

- **Kind:** task declaration friction.
- **Observed:** declaring `test` with `deps` but no `run` passes `kuu check`,
  then `kuu list` fails with `TASK badvalue: task 'test' needs a run function`.
- **Impact:** aggregate tasks need boilerplate, and syntax checking alone
  does not validate declarations.
- **Workaround:** add `run = function() end`; run `kuu list` as well as `check`.
- **Status:** Fixed in 0.6. A task with non-empty dependencies may omit `run`;
  cycles, failure propagation, argument checks, and JSON plans still apply.

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
  notes](#upgrading-06). Time Actual handles both 0.5 and 0.6 explicitly.

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

#### Downstream tools can reintroduce shell quoting problems

- **Kind:** external tool limitation encountered through process orchestration.
- **Observed:** a moved Time Actual checkout named `Time Actual` reached the
  native resource build, then windres failed because its internal preprocessor
  command split the path at the space. Kuu had passed the original argv intact.
- **Workaround:** use windres's `--use-temp-file` mode, run it in `build/`, and
  pass relative resource/include paths. The moved checkout then built and
  passed its tests with the original toolchain directories unavailable.
- **Status:** Resolved in the Time Actual recipe. The internal-command boundary and
  windres workaround are documented in [proc](#proc); no Kuu quoting defect was
  demonstrated.

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

#### ZIP creation loses names outside the system code page

- **Kind:** confirmed encoding defect in the archive wrapper's writer options.
- **Observed:** the Unicode regression packed `漢字.txt` using Windows tar's
  default ZIP settings. The archive contained `??.txt`, which extracted as
  `__.txt`. Tar-family archives preserved the same name.
- **Impact:** a successful ZIP pack could silently rename a source file.
- **Fix:** pass `--options zip:hdrcharset=UTF-8` for ZIP creation.
- **Status:** fixed in 0.6; the regression compares the source name,
  Unicode listing, and extracted file for ZIP and compressed tar formats.

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

### Cold setup and recovery — 2026-09-10

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
  [0.8](#upgrading-08). The published signed 0.7 asset and its digest are
  unchanged and still cannot start on 23H2. The validation evidence above
  records the earlier development build; its remaining findings stay open.

### JSON duplicate-key error lifetime — 2026-09-11

- **Observed:** the full AddressSanitizer suite on 23H2 found a heap use after
  free in the existing `json.decode` duplicate-key diagnostic. The offending
  key points into the yyjson document, which was freed before formatting it.
- **Fix:** build the error while the document still owns the key, then free
  the document. The existing duplicate-key regression now checks the key in
  the message as well as the error code. Included in 0.8.

### Process-tree chain check during 23H2 validation — 2026-09-11

- **Observed:** one complete run failed the existing 31-process-chain
  assertion that each node has at most one child. The cause is unisolated.
- **Control:** the isolated process suite passed all 82 checks; the final
  complete production suite then passed all 1,044 checks. No change to
  process-tree enumeration was made.
- **Evidence:** [dated validation record](notes/validation-23h2-2026-09-11_094612.md).

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

### `_ENV` reaches every capability without declaring one — 2026-09-11

- **Kind:** a gap in a documented affordance. Not a sandbox escape: kuu has
  no sandbox, and the operator ran the file.
- **Observed:** `_ENV` is an upvalue rather than a global, so it is in scope
  always and needs no declaration. Under `global none` with nothing declared,
  `_ENV.load("return 2 + 3")()` compiles and runs code, and
  `_ENV.require("proc")` reaches the whole palette.
- **Impact:** [`check`](#check) says its require listing "is how an agent sees
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

## Stability

kuu is still before 1.0. The 0.x releases may change contracts when use in
real repositories shows a mistake. Each such change belongs in that release's
upgrading page, with the old form beside the replacement. Projects carry a
specific `kuu.exe` in their own repository; updating that copy is deliberate.

### The 1.0 boundary

At 1.0, the documented public interfaces of these modules will be frozen:

`archive`, `check`, `cli`, `csv`, `env`, `err`, `fs`, `hash`, `http`,
`ini`, `json`, `log`, `mem`, `net`, `proc`, `re`, `reg`, `rt`, `sched`,
`sync`, `sys`, `task`, `text`, and `time`.

The same promise covers running a file, stdin, or an inline program; the
`docs`, `run`, `list`, and `check` verbs; their documented options and exit
codes; and their documented JSON reports. It includes the supported Windows
baseline and the documented Lua language version. The freeze is a promise
for 1.x, not a claim that the 0.9.0 interface can no longer improve.

`pty`, `svc`, `evt`, and `sys.signature` are provisional. Their APIs may
change before or after 1.0, with an upgrading note, and they are outside the
freeze until a later release explicitly brings them in.

`pty` is provisional for its interpretation of terminal output. The other
three left the freeze list in 0.9.0 for a plainer reason: they arrived in 0.7
and no project has yet driven them in earnest. A service state machine, an
event-log query, and an Authenticode trust decision are three of the easiest
Windows surfaces to shape wrongly, and a wrong shape inside the freeze costs
the whole 1.x line. They are brought in at 1.1 with adoption evidence behind
them. Nothing is removed from the executable; only the promise is withheld.

Private modules and names starting with `_`, command implementation modules
under `cmd`, internal helper processes, build artifacts, and undocumented
implementation details are also outside the public contract.

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
guarantee. Such changes require a new major version and a migration note.

### A minimum-version guard

A `tasks.lua` should ask for the oldest release whose features it uses,
rather than compare the runtime version for equality. Since 0.9.0 a version
has three natural-number components, Major.Minor.Patch, and
`rt.version_at_least` compares them, so a project never parses the version
text:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 9),
  "this project requires kuu 0.9.0 or later; found " .. rt.version)
```

`rt.version_at_least(major [, minor [, patch]])` answers whether the running
kuu is that version or newer. An omitted component is zero, and a component
that is not a natural number raises `RT badvalue`. It compares numbers, so
0.10 comes after 0.9, and 1.0 after both.

A guard written before 0.9.0 matched the version text with
`rt.version:match("^(%d+)%.(%d+)$")`. That pattern does not match `0.9.0`, so
such a guard refuses every release from 0.9.0 onward whatever minimum it asks
for. Replace it with the call above; see
[Upgrading to 0.9](#upgrading-09).

Place this before declarations that use newer capabilities. The guard tests
the minimum capability level, while the checked-in release hash and the
project's tests decide which executable the project adopts. Run those tests
when updating, and read the upgrading notes for every intervening 0.x
release or a future major release.

For the changes introduced with this statement, see
[Upgrading to 0.7](#upgrading-07). For a complete `tasks.lua`, see
[Adopting kuu](#adopting).

---

## Toolchain

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted. This page says exactly what `.tools` holds
so that another machine, or another person, can reproduce it.

Projects kuu drives are the same: each fetches its own prerequisites by url
and hash into its own `.tools`, with [`http`](#http) and
[`archive`](#archive), and carries its own `kuu.exe` directly in the
project root, copied in by hand. Nothing is shared between projects, and there is no lock: the agent
knows what a project needs, and kuu gives it the means.

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

The tree in use on 2026-09-09, by MSYS2 package:

| package | version |
|---|---|
| mingw-w64-ucrt-x86_64-gcc | 16.1.0-5 (reports "gcc version 16.1.0 (Rev5, Built by MSYS2 project)") |
| mingw-w64-ucrt-x86_64-binutils | 2.46-3 |
| mingw-w64-ucrt-x86_64-crt | 14.0.0.r47.g0636d42e1-1 |
| mingw-w64-ucrt-x86_64-headers | 14.0.0.r47.g0636d42e1-1 (the headers identify as mingw-w64 15.0) |
| mingw-w64-ucrt-x86_64-winpthreads | 14.0.0.r47.g0636d42e1-1 |

Target triple `x86_64-w64-mingw32`; C runtime UCRT, which every supported
Windows carries as `ucrtbase.dll`, so the executable has no redistributable.

### Populating `.tools`

From an existing MSYS2 installation with the packages above:

```bash
robocopy "C:\msys64\ucrt64" ".tools\msys2\ucrt64" /E /MT:16 /R:1 /W:1 /NFL /NDL /NJH /NP
```

Robocopy exits 1 when it copied files; that is success. From nothing: install
MSYS2, run `pacman -S mingw-w64-ucrt-x86_64-gcc` (binutils, crt, headers, and
winpthreads come with it), then copy as above. About 1.1 GB, 42,000 files.

kuu's own compiler is not fetched by kuu, by the owner's decision: kuu does not
build or bootstrap itself. Only verification targets run the built executable.
The versions above are a record.

### Verification

Run the complete production gate from the checkout root:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8 gate
```

`gate` runs the regression suite, `analyze`, `fuzz`, and `soak` in that order,
stopping at the first failure. Recursive makes keep these stages sequential
even with `-j8`: the suite and soak share scratch files. Each stage is also
available separately (`test`, `analyze`, `fuzz`, `soak`). `SOAK` defaults to
60 seconds; `FUZZ` and `FUZZ_SEED` below are inherited by the gate.

`analyze` compiles all authored `src/*.c` files separately into `build/analyze`
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

A project takes a release by copying `kuu.exe` directly into its root, after
checking the download against the sidecar, and states the version it expects
at the top of its `tasks.lua`.

Before publishing a release:

1. Run `make gate` on the final sources and review every stage's result.
2. Run `make asan` on those same sources and resolve every sanitizer finding.
   It is a separate required release check, not part of the everyday gate.
3. Commit and push the tested tree. Run `make publish GH=<gh.exe>`; it repeats
   the production gate before signing and publishing that commit.
4. Verify the release tag, signed executable, and SHA-256 sidecar, then run
   the exerciser with a copy of the released executable.

---

## Upgrading to 0.9

0.9.0 is the last release before the 1.0 freeze, and it exists to correct
contracts while correcting them is still allowed. It carries one breaking
change every project must act on — the version now has three components — and
one defect fix that removes an intermittent failure from every atomic write.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, **replace the minimum-version guard as described
below**, run `kuu check`, and run the project's tasks. For earlier releases,
read [upgrading to 0.8](#upgrading-08), [to 0.7](#upgrading-07), and the
[0.6 duration migration](#upgrading-06).

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

See [fs](#fs) for the contract and
[observed shortcomings](#shortcomings) for the evidence.

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

### Three modules leave the planned freeze

`svc`, `evt`, and `sys.signature` arrived in 0.7 and have no real-project
adoption evidence behind them. Service state machines, event-log queries, and
Authenticode trust are easy surfaces to shape wrongly, and freezing a wrong
shape would cost the whole 1.x line. They join `pty` as provisional, outside
the freeze, and are brought in at 1.1 with evidence behind them.

Nothing is removed from the executable and no call changes. Only the
compatibility promise is withheld; see the
[stability statement](#stability).

---

## Upgrading to 0.8

0.8 lowers the Windows 11 minimum to **23H2** and fixes a memory-lifetime
defect in the JSON duplicate-key diagnostic. Windows Server still requires
2025 or later. The public Lua API is unchanged from 0.7, and `pty` remains
provisional and outside the planned 1.0 freeze.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, run `kuu check`, and run the project's tasks.
Projects using 0.7 features can keep their existing minimum-version guard;
projects deployed to 23H2 should require 0.8 or later. For earlier releases,
also read [upgrading to 0.7](#upgrading-07) and the
[0.6 duration migration](#upgrading-06).

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
[pty](#pty) for the lifetime contract.

Queued I/O completions also keep a stable dispatch key after their owner is
released, so a Lua finalizer can run another process during shutdown without
accessing freed console state.

### JSON diagnostics

`json.decode` now formats a duplicate-key error while the parser still owns
the key's bytes. Previously it freed those bytes first, causing a use after
free while constructing the message. Duplicate keys still return
`nil, err` with domain `JSON` and code `duplicate`.

The [observed shortcomings](#shortcomings) record the compatibility
validation and unresolved intermittent file-access and process-tree checks.
This release does not claim to resolve those separate findings.

---

## Upgrading to 0.7

0.7 adds the last planned capabilities before the 1.0 freeze: child resource
limits, scoped deadlines, default task timeouts, services, event logs,
signature verification, palette-name checking, and provisional console
automation through `pty`.

Copy the new executable into the repository root, read the changes below,
run `kuu check`, and run the project's tasks. Numeric durations remain
seconds, as in 0.6. A project still on 0.5 also needs the
[0.6 duration migration](#upgrading-06).

### Windows 11 23H2 compatibility

The published, signed 0.7 executable cannot start on Windows 11 23H2 because
it imports a newer console API. Use [0.8 or later](#upgrading-08) on that
OS. The original 0.7 release asset and its checksum have not been replaced.

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
See [check](#check) for the exact report schema and limitations.

`task.defaults` currently accepts only `timeout`. A malformed duration or an
unknown field raises `TASK badvalue` without replacing the preceding default;
an empty table clears it. It bounds each child of `task.exec`, not the entire
task or dependency plan. Numeric values are seconds and zero is a valid
explicit timeout. See [Tasks](#task), including the exact `run --json`,
`run --dry-run --json`, and `list --json` schemas.

The schemas describe the existing output boundaries too: task output under
`run --json` goes to stderr through `print`, `io.write`, and `task.exec`;
direct `io.stdout` writes can still mix with the envelope. `list --json`
requires quiet top-level task declarations. Malformed runner options and
missing paths can fail before a JSON report exists, as documented per verb.

### New capabilities

- **Child limits.** `proc.run`, `proc.start`, and `task.exec` accept
  `limits = { memory = "512M", cpu = "30s", processes = 8 }`. The bounds
  apply to the child's whole job: committed bytes, user CPU seconds, and
  simultaneously active processes including the first child. When a bound
  is breached, a process result has `status = "limit"` and
  `limit = "memory" | "cpu" | "processes"`. If you opt into limits, handle
  that status as a failure regardless of `code`. `task.exec` returns
  `TASK failed` and names the breached bound. [proc](#proc)
- **Scoped deadlines.** `sched.deadline(duration, fn, ...)` returns the
  function's results unchanged or `nil, SCHED deadline` when its waits
  exhaust the scope. Nested scopes use the earliest deadline. This cannot
  interrupt CPU-only Lua, and spawned tasks do not inherit it. A child is
  not automatically killed by the scope: hold a `proc.start` handle in a
  `<close>` local when its lifetime must end on unwind. [sched](#sched)
- **Services.** `svc.list`, `status`, `start`, `stop`, `restart`, and `wait`
  inspect and control the Service Control Manager. State transitions poll
  on the event loop. Access failures are explicit and may require elevation;
  a timeout stops waiting without undoing the request. [svc](#svc)
- **Signatures.** `sys.signature(path [, options])` distinguishes unsigned
  files, accepted embedded Authenticode signatures, and rejected signatures
  with a reason. Match the signer or pinned certificate thumbprint before
  running an installer. Windows catalog-only signatures report unsigned;
  revocation/network retrieval are off unless requested. [sys](#sys)
- **Event logs.** `evt.logs` lists channels and `evt.read` returns bounded
  newest-first snapshots filtered by time, level, and provider. A record has
  typed system fields and a rendered message, with raw XML as the fallback.
  It never writes or clears a log. [evt](#evt)
- **Interactive consoles.** `pty.spawn` creates a supervised ConPTY child.
  Its handle offers Lua-pattern `expect`, raw reads, a plain-text view,
  writes, resize, wait, kill, and close. The view is a small VT filter rather
  than a terminal screen model. This module remains provisional and outside
  the future 1.x freeze. [pty](#pty)

The [cookbook](#cookbook) has ten complete programs using these APIs and
the existing palette. Its extracted programs are checked by the suite;
safe fixtures exercise downloads, logs, process control, INI edits, service
decisions, signatures, and console input. The [PowerShell map](#powershell)
includes the new operations.

### Version guards and verification

Use the numeric minimum-version guard from [Stability](#stability) or the
complete [adoption example](#adopting). A guard tests the capabilities
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
[Toolchain](#toolchain) records the packages and commands.

---

## Upgrading to 0.6

0.6 is the release that carries the 0.5 review fixes and the fixes from the
first real repository driven by kuu.
Keep `kuu.exe` directly in the project root and declare the supported runtime
version in `tasks.lua`. The previous 0.5 review fixes are included.

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
remain external boundaries; see [observed shortcomings](#shortcomings).

