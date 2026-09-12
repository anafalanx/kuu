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
| a language of kuu's own | none, by owner decision on 2026-09-11: no successor language, no compiler, no emission subset | kuu is a runtime for Lua 5.5 and grows capabilities in the palette and options on the calls already there; existing technology is recombined, not syntax invented |
| a JavaScript runtime | Deno, pinned to the kuu release that uses it, downloaded by the consumer on request into the project's own `.kuu/`, never shipped | designed 2026-09-12 and not built. The palette was reachable only through C, so every capability meant vendoring, rebuilding and releasing; an explicit permission model is what keeps a capability gate over a general escape hatch, and pinning is what makes the youngest of the candidates acceptable |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.1 from MSYS2 UCRT64, copied into `.tools` | the estate's proven recipe; gcc and GNU make are the chosen production build, with Clang only for sanitizer tests |
| build | GNU make from the same `.tools`, recipes under `cmd.exe` | no PowerShell in the repository, and kuu never builds kuu: the build is make and gcc, the tests are Lua run by the built kuu |
| self-hosting | none, by owner decision | kuu is not required to bootstrap or build itself; a person with `.tools` populated runs `make` |
| versions | `Major.Minor.Patch`, all natural numbers, since 0.9.0 | 0.1 through 0.8 had no patch component; a frozen 1.x needs a way to ship one correction without claiming new capability, and the component is cheaper to add before the freeze than after it. `rt.version_at_least` compares them so no project parses the text |
| dependency pinning | none: a project fetches what it needs by url and hash with `http` and `archive`; kuu's own compiler is copied by hand | the lock built in 0.3 was removed in 0.4 as formalism; kuu does not bootstrap itself |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has only stock Lua's `io` and `os`, and a static check can list what else a file asks for. It gates a program that does not reach around it: `_ENV` is an upvalue, needs no declaration, and reaches `load` and the whole palette from a file `check` reports with `"requires":[]` and a clean bill ([shortcomings](shortcomings.md)) |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child is born into a kill-on-close job; only `detach`, and a child's own deliberate breakaway, step outside it |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, Tcl in the runtime, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs. Tcl reached as a fetched helper behind a capability is a different question and is open: the JavaScript design keeps Tcl with twapi as the right answer for Windows API reach specifically, and says a capability module may yet use it |
| projects share nothing | every project carries its own `kuu.exe`, copied in by hand, directly in its root since 0.6 (0.4 and 0.5 put it in `.tools`); nothing on `PATH`, no machine changes, no bootstrap scripts | the owner ended estate-wide management; a small executable is copied, not fetched by glue |
| what a project may fetch | upstream downloads only, into its own `.tools`; nothing re-hosted, nothing shared between projects | no commonalities, and a stranger fetches from the same public sources. The JavaScript runtime is the one thing kuu itself would fetch, into `.kuu/` beside the project's own tools, on request and never shared |
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
| `check` reads `_palette`, an authored description of kuu's interface: an error code its domain lacks, an option a call does not take, a closed set compared with a non-member, `rt.version` compared by text | 0.10.0 |
| `check` reads a project's own modules from their text, so its exports are checked too; an export set the text cannot bound goes unchecked rather than guessed. `check.exports`, `check.modules` | 0.10.0 |
| `kuu check --fix [--adopt]`: the global declaration written in both directions, the Lua compiler as the authority, and a refusal to declare a name this runtime lacks | 0.10.0 |
| `kuu capabilities [--json]`: the verbs, the public modules and their names, the error domains and closed sets, and this project's tasks and modules; `rt.verbs`, `rt.pages` | 0.10.0 |
| `text.trim`, native, replacing a helper hand-rolled six times; the unanchored `$` out of every hot path in `lua/` and `tools/`; `check` lexes by byte | 0.10.0 |
| `kuu.md`: what kuu is, what its predecessors taught, and the whole manual inlined by `tools/bundle_docs.lua`, held to `docs/` by the suite | 0.10.0 |
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
8. **0.8, Windows 11 23H2 compatibility.** Resolve the newer console release
   API only when present; on 23H2, independent close/drain workers preserve
   final output and finish canceled I/O safely. The Lua API is unchanged,
   and `pty` remains provisional. The JSON duplicate-key diagnostic also
   keeps its parser-owned key alive while formatting the error. See
   [upgrading to 0.8](upgrading-0.8.md) and the validation evidence in
   [observed shortcomings](shortcomings.md).
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
   gate with zero failures. See [upgrading to 0.9](upgrading-0.9.md).
   - Released 2026-09-11 at 12:55:48 UTC: the tag names `81f9fd7`, the signed
     executable is 1,563,512 bytes, and the local file, the asset downloaded
     again, and the published sidecar all carry the same SHA-256, with the
     released binary reporting its own Certum identity through
     `sys.signature`. Three clean soak gates ran in a row on the release host
     — `make gate`, the required separate `make asan`, and the `make publish`
     repeat — which with the 23H2 evidence from the other machine puts two
     hosts behind the 1.0 soak criterion rather than one. Time Actual adopted
     it the same day: it guards with `rt.version_at_least(0, 9)`, raising its
     minimum from 0.5 retired the two compatibility branches it carried, its
     CI pins the release and its checksum, and its `test` task passed 2,191
     engine checks with CI green in 1 min 19 s. That is the project that
     co-evolved with the runtime, so it does not answer the cold-adopter
     amendment. Recorded in the
     [release handoff](../notes/handoff-2026-09-11_145745.md).
10. **0.10.0, the interface described, and no language.** On main and
   unreleased: the executable still reports `0.9.0`. The owner decided on
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
   looking for exactly them. Domains themselves stay open, since `err.new` is
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
     reverted, so [pitfalls](pitfalls.md) now carries the crossover, about ten
     short pieces, instead of the rule it was written from.
   - Recorded, not built. `_ENV` is an upvalue, so under `global none` with
     nothing declared it reaches `load` and the whole palette while
     `kuu check --json` reports `"requires":[]` and a clean bill; the `require`
     gate holds only for a program that does not reach around it, and the
     small answer, reporting such a reference from `check`, is unimplemented
     ([observations](shortcomings.md)). And a JavaScript capability is
     designed, on Deno: about 24 MB, downloaded by the consumer on request,
     pinned to the kuu release that uses it, never shipped, never fetched in a
     non-interactive run, unpacked into the project's own `.kuu/`. It won on
     the one property Tcl with twapi and a compiled Go helper per capability
     both lack, an explicit permission model, which is what keeps a capability
     gate over a general escape hatch; it is also the youngest of the three,
     2.0 having broken compatibility in 2024 under a company rather than a
     foundation, and pinning is what makes that acceptable, since churn
     upstream cannot reach a project that never re-pins. PowerShell through a
     bridge was rejected on four counts, one a measured 68 MB idle working set
     per bridge against kuu's 1.6 MB. Replaceability comes from the internal
     boundary, one module owning the runtime and every engine-specific call
     going through one shim, not from where the engine is named. See
     [the JavaScript capability design](../notes/design-js-capability-2026-09-12_155114.md).
   - The suite is at 1140 checks, with four new cases: `_palette` held to the
     runtime, to the manual in both directions and to itself; `capabilities`;
     the fixer's invariant, which keeps every declaration outside
     `test/fixtures` correct so a name that falls out of use fails instead of
     rotting; and `kuu.md` regenerated and compared. `docs/capabilities.md` is
     the manual's forty-first page. Outstanding: there is no upgrading page for
     this release, and [stability](stability.md) still names four verbs, so
     nothing yet says whether `capabilities` is inside the 1.0 freeze.
11. **1.0.** Criteria for the owner to set. Proposed: three projects driven
   for a month without a runtime defect, a manual page for every module, a
   signed release cadence, and the Lua-versus-Tcl ledger closed with a
   verdict. Two amendments agreed on 2026-09-11: a **clean soak gate on every
   target host**, since freezing while it is knowingly unclean rests the 1.x
   promise on a signal nobody trusts; and **at least one cold adopter**,
   because every adoption finding on record comes from Time Actual, which
   co-evolved with the runtime and therefore routes around contract mistakes
   instead of reporting them. Between 0.9.0 and 1.0: the freeze, the month of
   use, and corrections driven by what that use finds.

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
- **The JavaScript runtime, five questions the design leaves open.** Consent
  is per project, so a fresh clone of the eighth prompts again — correct, or
  maddening by the third time? What removes a superseded pinned version under
  `.kuu/`? How is the unpacked runtime verified cheaply on every run, when
  hashing it is too slow? What does `check` report for a file using the
  capability when the runtime is absent? And is the general escape hatch a
  public module or reached through a capability — which decides whether
  `require` stays a meaningful gate for it, or the permission flags carry it
  alone.

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
