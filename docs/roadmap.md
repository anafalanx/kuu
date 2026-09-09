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
| dependency pinning | a prescriptive lock for the repositories kuu drives (0.3); kuu's own compiler stays unpinned, by owner decision | `tools/lock.json` names url, hash, size, unpacking, a version check, and the license notice; kuu's `.tools` is populated by hand because kuu does not bootstrap itself |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has no machine authority, and a static check can list what a file asks for |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child is born into a kill-on-close job; only `detach`, and a child's own deliberate breakaway, step outside it |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, any Tcl, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs |

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
| `toolchain` hydrate/verify/path from a prescriptive lock; `kuu hydrate`, `kuu verify` | 0.3 |
| `task`, `tasks.lua`, `kuu run`, `kuu list`, `--json` envelopes on every verb; `fs.chdir`, `rt.root`, `rt.source` | 0.3 |
| `kuu check`: parse, global declarations, `require` resolution, without running; no arity checking, by design | 0.3 |
| `examples/hello`: a lock that pins Zig by hash, a `tasks.lua` that hydrates it and builds one C file with it | 0.3 |
| `pty` over ConPTY with `expect`; a version resource, signing, `get-kuu.cmd`, `kuu init`; the second repository | 0.4 |
| `re` on PCRE2; `worker` processes; `serve`; `check` learns the palette's names | 0.5 |

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
   project end to end. Done 2026-09-09 with `examples/hello`: a lock that
   pins Zig 0.16.0 by hash, and a `tasks.lua` that hydrates it (97 MB, 14 s
   including the hash, the unpack, and `zig version`), compiles one C file
   with it (67 s the first time, while Zig builds its C runtime; 0.2 s
   after), and tests the result. `kuu verify --deep` passes, a second
   `kuu run` costs a stamp check, and editing the lock makes the tool stale
   and re-installs it from the cache.
4. **0.4, the agent's console and the first release.**
   - `pty`: a child on a ConPTY, born in a job like every other child, its
     pipes overlapped on the one port, no threads. `read`, `write`, `resize`,
     `wait`, `kill`, and `expect(patterns, timeout)` against both the raw
     bytes and the plain text a terminal would show. Done when the suite
     drives an interactive prompt and a REPL through it.
   - The release: a version resource so the file's properties say what
     `--version` says; Authenticode signing; `kuu.exe` published with a
     `.sha256` beside it; and `get-kuu.cmd`, ten lines of batch on the
     `curl.exe` and `certutil.exe` every supported Windows ships, that fetch
     a named version by hash into `.tools/kuu/`. Batch, because it is the
     only script that can exist before kuu does; no PowerShell.
   - `kuu init`: writes `tasks.lua`, `tools/lock.json`, the `.gitignore`
     lines, and `get-kuu.cmd` into a repository, so adoption is one command.
   - `kuu run --dry-run`: the plan, in order, without running it.
   - The second repository, the owner's pick, driven by a `tasks.lua` and
     bootstrapped by `get-kuu.cmd`. Done when a fresh clone on a clean
     Windows 11 goes from nothing to a passing `kuu run` with one command.
5. **0.5, text and workers.** `re` on PCRE2 (UTF-8, named groups, `find`,
   `match`, `gmatch`, `gsub`, `split`), because the ledger says Lua patterns
   may prove decisive; `fs.glob`; `worker` processes, Lua in a child kuu with
   JSON messages over pipes on the port, for CPU-bound and isolated work;
   `serve`, a local HTTP listener on the loop for tooling and webhooks;
   `check` learns the palette's exported names, so `fs.exist` is an error
   before a run, still without arity.
6. **1.0.** Criteria for the owner to set. Proposed: three repositories
   driven for a month without a runtime defect, a manual page for every
   module, a signed release cadence, and the Lua-versus-Tcl ledger closed
   with a verdict.

## Open decisions

- **The second repository.** The best fit is one with a build-and-test cycle
  that PowerShell and Tcl scripts drive today.
- **Where releases live.** The repository is private, and `get-kuu.cmd` needs
  an anonymous url: a public repository, a public bucket, or a token in the
  script, which is the one to avoid.
- **Signing.** Which certificate, and whether releases are signed only from
  the owner's machine.
- **kuu's own compiler.** Three honest options: MSYS2 by hand, as now; Zig
  fetched by hash with a `get-zig.cmd` that needs no kuu, so no
  self-reference; or Zig through kuu's own lock, hydrated by the previous
  release, which is self-referential across versions. `examples/hello` shows
  a hash-pinned `zig cc` building C in seconds.

## Backlog

Small things, unscheduled: patches pinned by before-and-after hashes in the
lock, for vendored sources; `kuu hydrate --prune` for downloads no lock names;
a per-tool download `timeout`; cancellation and a streaming body reader in
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

Nothing decisive yet. The coroutine model, the byte strings, and the C API have
been strengths at every step so far.
