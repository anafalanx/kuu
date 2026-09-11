# Roadmap

kuu began on 2026-09-09 as the successor to machteld, the Tcl runtime for
agents, after the owner concluded that estate-wide management had to stop and
that each project should stand alone with its own tools. The name was reused
from an earlier, archived attempt to reimplement Lua 5.5 in Go; the new kuu
embeds PUC Lua instead. This page records the decisions and the milestones.

## Decisions

| decision | choice | why |
|---|---|---|
| platform | Windows 11 23H2 and later; Windows Server 2025 and later | native Windows APIs; 23H2 console teardown uses isolated close/drain workers and completion-aware pipe ownership |
| language for programs | Lua 5.5.1, vendored, compiled as C | agents write it correctly from a hundred-page manual; coroutines make waiting read as straight-line code; `global none` turns the classic typo into a compile error; errors are `longjmp`, so C, never C++ |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.1 from MSYS2 UCRT64, copied into `.tools` | the estate's proven recipe; gcc and GNU make are the chosen production build, with Clang only for sanitizer tests |
| build | GNU make from the same `.tools`, recipes under `cmd.exe` | no PowerShell in the repository, and kuu never builds kuu: the build is make and gcc, the tests are Lua run by the built kuu |
| self-hosting | none, by owner decision | kuu is not required to bootstrap or build itself; a person with `.tools` populated runs `make` |
| versions | `Major.Minor`, both natural numbers | 0.1, 0.2, ...; no patch component |
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
| `worker` processes; `serve` | deferred, on a real project need |
| review fixes, dependency-only tasks, duration units, Unicode archives, TLS diagnostics, process path consistency; analysis and parser fuzz gates | 0.6 |
| job-wide `proc` limits on memory, user CPU time, and active processes; result `status = "limit"` with its kind | 0.7 |
| `sched.deadline` across waits; `task.defaults { timeout = ... }`; `task.exec` leaves the caller's options table untouched | 0.7 |
| `svc` for service state and transitions; `evt` for bounded event-log queries; `sys.signature` for embedded Authenticode trust and identity | 0.7 |
| `check` verifies palette export names through local aliases and lexical scopes, with suggestions and JSON finding kinds | 0.7 |
| `pty` over ConPTY with `expect`, a plain-text view, and supervised child lifetime; provisional, outside the future freeze | 0.7 |
| ten executable cookbook programs; public stability statement and minimum-version guards; complete module map and JSON schemas | 0.7 |
| `make gate`: suite, analysis, expanded parser fuzzing, soak; separate pinned Clang AddressSanitizer build required for release | 0.7 |
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
   supplement the regression suite. See the [migration notes](upgrading-0.6.md)
   and [observations log](shortcomings.md). Released 2026-09-10, after the cold
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
   - The [cookbook](cookbook.md) gives ten complete programs, extracted and
     checked by the suite and exercised with safe fixtures. The
     [stability statement](stability.md) names the future 1.x contract and
     replaces exact-version guards with numeric minimums. The module pages,
     PowerShell map, error-code sets, and JSON schemas are documented together;
     [upgrading to 0.7](upgrading-0.7.md) records the changes from 0.6.
   - `make gate` combines the suite, GCC analysis, deterministic fuzzing, and
     soak. The parser corpus now includes CSV, INI decode and edits, JSON,
     and registry key text. `make asan` builds a separate test executable
     with pinned MSYS2 CLANG64 packages and runs the suite under
     AddressSanitizer; it is a required separate release check.
8. **1.0.** Criteria for the owner to set. Proposed: three projects driven
   for a month without a runtime defect, a manual page for every module, a
   signed release cadence, and the Lua-versus-Tcl ledger closed with a
   verdict. Between 0.7 and 1.0: the freeze, the month of use, and 0.8 with
   only what that month finds.

## The 0.5 review: fixes implemented

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
[toolchain](toolchain.md) for replay commands. Analysis also made the error
raiser's non-returning contract explicit and led to entry-allocation cleanup.

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

## 0.6: fixes from real repository adoption

Time Actual exposed cross-module duration units, lossy archive names, process
path inconsistency, and task/entry friction. 0.6 uses numeric
seconds throughout, supports dependency-only tasks and `kuu version`, returns
Unicode archive inventories, writes UTF-8 ZIP headers, normalizes process
executable paths, and identifies client-key/proxy TLS failures. See
[migration notes](upgrading-0.6.md) and the [observations log](shortcomings.md).
The Tcl sandbox issue remains an execution-environment limitation. The windres
workaround belongs to the consuming build recipe and is now documented.

Cold setup testing also found and fixed `hash.file`'s long-path boundary.
The complete suite now passes 838 checks plus native analysis. Time Actual's
new recovery fixture passes 17 checks on 0.5 and 0.6; full cold toolchain and
relocation validation is paused. The [2026-09-10 handoff](../notes/handoff-2026-09-10_193511.md) recorded
that pause; the remaining work was completed the same day on the second
machine, recorded in the observations log, and 0.6 was released.
