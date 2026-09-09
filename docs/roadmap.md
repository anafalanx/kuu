# Roadmap

kuu began on 2026-09-09 as the successor to machteld, the Tcl runtime for
agents, after the owner concluded that estate-wide management had to stop and
that each project should stand alone with its own tools. The name was reused
from an earlier, archived attempt to reimplement Lua 5.5 in Go; the new kuu
embeds PUC Lua instead. This page records the decisions and the milestones.

## Decisions

| decision | choice | why |
|---|---|---|
| platform | Windows 11 25H2 and later, and the equivalent Windows Server releases; nothing else | the strength comes from using the modern process, console, and file APIs without fallbacks |
| language for programs | Lua 5.5.1, vendored, compiled as C | agents write it correctly from a hundred-page manual; coroutines make waiting read as straight-line code; `global none` turns the classic typo into a compile error; errors are `longjmp`, so C, never C++ |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.1 from MSYS2 UCRT64, copied into `.tools` | the estate's proven recipe; the Zig toolchain was weighed and stays an option |
| build | GNU make from the same `.tools`, recipes under `cmd.exe` | no PowerShell in the repository, and kuu never builds kuu: the build is make and gcc, the tests are Lua run by the built kuu |
| self-hosting | none, by owner decision | kuu is not required to bootstrap or build itself; a person with `.tools` populated runs `make` |
| versions | `Major.Minor`, both natural numbers | 0.1, 0.2, ...; no patch component |
| dependency pinning | none: a project fetches what it needs by url and hash with `http` and `archive`; kuu's own compiler is copied by hand | the lock built in 0.3 was removed in 0.4 as formalism; kuu does not bootstrap itself |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has only stock Lua's `io` and `os`, and a static check can list what else a file asks for |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child is born into a kill-on-close job; only `detach`, and a child's own deliberate breakaway, step outside it |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, any Tcl, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs |
| projects share nothing | every project carries its own `kuu.exe` in its own `.tools`, copied in by hand; nothing on `PATH`, no machine changes, no bootstrap scripts | the owner ended estate-wide management; a small executable is copied, not fetched by glue |
| what a project may fetch | upstream downloads only, into its own `.tools`; nothing re-hosted, nothing shared between projects | no commonalities, and a stranger fetches from the same public sources |
| kuu's own repository | free of kuu: build and release are make, gcc, and cmd recipes; no `tasks.lua` there | self-reference is unwelcome, for release steps too |
| releases | anafalanx/kuu public; GitHub Releases carry `kuu.exe` and its `.sha256`; signed with the owner's existing Certum certificate through the Windows SDK's signtool | the estate already signs this way, and public releases need no credentials to fetch |
| the second project | `C:\dev\kuu-test-project`, local, no remote, tailored to test kuu features | a project built to exercise the runtime, before any existing one is converted |
| what kuu is | a Windows-only power tool in the agent's hand: set up, configure, run, test, script, control, keep in check; every feature replaces a PowerShell fumble | the agent knows its prerequisites; kuu removes the fumbling, not the knowing |
| dependencies | no lock: verification is a capability (`http.get` with `sha256`, `fs.unpack`), and the agent writes its own setup | the lock was formalism for a shared-payload world that no longer exists |
| memory across runs | `mem`, a small JSON notebook per project, Lua only, capped at 1 MiB | agents need to remember between runs; the executable stays nimble; SQLite stays out |

## Inventory

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
| `task`, `tasks.lua`, `kuu run`, `kuu list`, `--json` envelopes on every verb; `fs.chdir`, `rt.root`, `rt.source` | 0.3 |
| `kuu check`: parse, global declarations, `require` resolution, without running; no arity checking, by design | 0.3 |
| verification as a capability: `http.get { to, sha256 }`, `fs.unpack`, `fs.pack` over the tar.exe Windows ships | 0.4 |
| `fs.glob`, `fs.join`, `fs.dirname`, `fs.basename`, `fs.ext`, `fs.relative`, `fs.tempfile`, `fs.tempdir`, `fs.space` | 0.4 |
| `sys.info`; `hash.uuid`; `text.base64`, `text.hex`; `mem`, a small JSON notebook per project | 0.4 |
| `kuu run --dry-run`; a crash handler so kuu never dies silently; soak and stress tests on demand | 0.4 |
| the from-PowerShell page of the manual: each cmdlet an agent reaches for, and the kuu call | 0.4 onward |
| a version resource, Certum signing, a GitHub Release, by make; `kuu-test-project` under the released kuu | 0.4 |
| `pty` over ConPTY with `expect`; VT processing and size on kuu's own console | 0.5 |
| `re` on PCRE2; `time`; `debug.traceback` and `debug.getinfo` only; `csv`, `ini` | 0.5 |
| `reg`; persistent environment variables with the change broadcast | 0.5 |
| `proc.list`, `proc.find`, `proc.tree`; `net.probe`, `net.listeners`, `net.resolve`, `net.addresses`; `sync.lock` | 0.5 |
| `svc` via the Service Control Manager; `evt`, the event logs; `worker` processes; `serve`; `check` learns the palette's names | 0.6 |
| deferred: elevated runs, `xml`, ACLs, clipboard, ICMP, scheduled tasks as a module, `kuu run --watch`, credentials and certificates, CI | later, on a real need |
| no-go: `tools.get`, `proc.shell`, YAML, templating, `text.diff`, shortcuts, Windows features, firewall, Defender, power, `kuu init`, bootstrap scripts | decided 2026-09-09 |

## Milestones

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
     `kuu.exe` copied into its `.tools`.
   - Done 2026-09-09, the same day it was decided. 509 checks. The soak test
     found a handle leak on its first run and a standalone probe traced it
     to WinHTTP itself, one handle per session opened and closed; kuu now
     holds one session per process and a 45 second soak stays flat on
     handles and memory. `kuu.exe` carries its version resource, is signed
     by thumbprint and timestamped, verified, hashed, and published as the
     0.4 release; `kuu-test-project` fetches make and its two runtime
     packages by hash with `http` and `archive`, counts its runs in `mem`,
     and runs its tasks under the released kuu.
5. **0.5, the console, the language, the machine.** `pty`: a child on a
   ConPTY, born in a job like every other child, its pipes overlapped on the
   one port, no threads; `read`, `write`, `resize`, `wait`, `kill`, and
   `expect(patterns, timeout)` against both the raw bytes and the plain text
   a terminal would show; done when the suite drives an interactive prompt
   and a REPL through it. `re` on PCRE2, because the ledger says Lua
   patterns may prove decisive; `time` with zones and ISO 8601;
   `debug.traceback` and `debug.getinfo` and nothing else of that library;
   `csv` and `ini`. `reg` with typed values and persistent environment
   variables with the change broadcast, reads and writes. `proc.list`,
   `proc.find`, `proc.tree`; `net.probe`, `net.listeners`, `net.resolve`,
   `net.addresses`; `sync.lock`, a named mutex across processes.
6. **0.6, control and keeping in check.** `svc` via the Service Control
   Manager: query, start, stop, create, delete; `evt`, the event logs read
   with filters; `worker` processes, Lua in a child kuu with JSON messages
   over pipes on the port; `serve`, a local HTTP listener on the loop;
   `check` learns the palette's exported names, so `fs.exist` is an error
   before a run, still without arity.
7. **1.0.** Criteria for the owner to set. Proposed: three projects driven
   for a month without a runtime defect, a manual page for every module, a
   signed release cadence, and the Lua-versus-Tcl ledger closed with a
   verdict.

## Open decisions

- **1.0 criteria.** The proposal above stands until the owner sets them.

## Backlog

Small things, unscheduled: cancellation and a streaming body reader in
`http`; `kuu docs` as a searchable single page.

## The Lua-versus-Tcl ledger

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
  each parse durations by hand. `re` on PCRE2 is planned for 0.5; until it
  lands, string-heavy work is where an agent will most often fall back to C or
  to a clumsy loop. This is the first entry that may prove decisive rather
  than minor.
- **`global none` is opt-in boilerplate.** Tcl has no equivalent check at all,
  so this is a Lua advantage in the end, but every file must start with two
  lines to get it, and an agent that forgets them gets stock Lua's silent
  globals.

Nothing decisive yet, though the pattern entry is the one to watch. The
coroutine model, the byte strings, and the C API have been strengths at every
step so far.
