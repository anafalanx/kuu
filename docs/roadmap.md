# Roadmap

kuu began on 2026-09-09 as the successor to machteld, the Tcl runtime for
agents, after the owner concluded that estate-wide management had to stop and
that each project should stand alone with its own tools. The name was reused
from an earlier, archived attempt to reimplement Lua 5.5 in Go; the new kuu
embeds PUC Lua instead. This page records the decisions and the milestones.

## Decisions

| decision | choice | why |
|---|---|---|
| language for programs | Lua 5.5.1, vendored, compiled as C | agents write it correctly from a hundred-page manual; coroutines make waiting read as straight-line code; `global none` turns the classic typo into a compile error; errors are `longjmp`, so C, never C++ |
| host language | C, the els method's subset | the host lives on two C boundaries, Win32 and the Lua API, and machteld's process-lifetime and text-boundary code transfers verbatim |
| compiler | gcc 16.1 from MSYS2 UCRT64, copied into `.tools` | the estate's proven recipe; the Zig toolchain was weighed and stays an option |
| build | `tools/build.ps1`, PowerShell 5.1 | kuu cannot build itself before it exists and PowerShell is the one runtime every Windows machine has |
| dependency pinning | none yet, by owner decision | "wing it": the toolchain is whatever `.tools` holds; a lock with URLs and hashes comes when the runtime can hydrate it |
| the gate | `require` | a program obtains capabilities by naming modules; a stray Lua file has no machine authority, and a static check can list what a file asks for |
| the manual | for kuu, not for Lua | one page of what an agent's Lua priors get wrong here; no reference manual, no index |
| process lifetime | the no-orphans law, first thing in the palette | every child has a guardian and none outlives the runtime unless detached on purpose |
| what stays out | `store` (SQLite), publishing, Tk, a wrap verb, any Tcl, PATH lookup, `io.popen`, `os.execute` | tools or hazards, not organs |

## Inventory

| organ | status |
|---|---|
| entry routes: file, stdin, inline; `--version`, `--help` | 0.1.0 |
| selective standard library, hazards removed, text-only `load`, rooted `require`, `rt` | 0.1.0 |
| event loop and `sched` (coroutines parked on I/O completions and timers) | next |
| `proc` (run, start, wait, kill, detach, scope) under Job Objects | next |
| `fs` (read, atomic write, stat, dirs, canon, identity, link, watch) | next |
| `text`, `json`, `hash`, `log`, `cli`, `err` | next |
| `http` via WinHTTP, `toolchain` hydrate/verify/path, `task` and `run`/`list` | after |
| `check` (parse, `global none`, palette arity before running), `docs` verb | after |
| `pty` over ConPTY with `expect`; `re` via PCRE2; worker processes; `serve` | later |
| version resource, signing, release | with the first palette release |

## Milestones

1. **0.1.0, the runner.** Routes, decoding, the state, `rt`, errors and exit
   codes, the entry test suite. Done when `kuu -e 'print(_VERSION)'` and every
   entry test pass from a clean checkout with a populated `.tools`.
2. **0.2, the palette core.** The IOCP loop on the Lua thread, coroutine
   scheduler, `proc`, `fs`, `text`, `json`, `hash`, `log`, `cli`, `err`, with
   hostile fixtures: orphans, timeouts, NUL bytes, invalid UTF-8, a hundred
   children.
3. **0.3, the repository runtime.** `http`, hydrate and verify from a lock,
   tasks, `check`, `docs`. Done when kuu builds itself from its own task file
   and the result matches `tools/build.ps1` byte for byte.
4. **0.4, the agent's console.** `pty`, then a signed release and the first
   other repository bootstrapped by a ten-line PowerShell script that fetches
   `kuu.exe` by hash.
