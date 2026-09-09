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
| dependency pinning | none yet, by owner decision | "wing it": the toolchain is whatever `.tools` holds; a lock with URLs and hashes comes when the runtime can hydrate it |
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
| live child streams (`child:read`, `child:write`), `proc.wait_any`, output callbacks, inherited console | 0.2 remaining |
| `http` via WinHTTP, `toolchain` hydrate/verify/path, `task` and `run`/`list` | 0.3 |
| `check` (parse, `global none`, palette arity before running), `--json` envelopes | 0.3 |
| `pty` over ConPTY with `expect`; `re` via PCRE2; worker processes; `serve` | later |
| version resource, signing, release | with the first palette release |

## Milestones

1. **0.1, the runner.** Routes, decoding, the state, `rt`, errors and exit
   codes, the entry test suite. Done 2026-09-09.
2. **0.2, the palette core.** The loop and scheduler, `proc`, `fs`, `text`,
   `json`, `hash`, `log`, `cli`, `err`, with hostile fixtures: orphans,
   timeouts, NUL bytes, invalid UTF-8, dozens of children, junctions inside,
   outside, looped, and dangling, paths beyond 260 characters. Landed
   2026-09-09 with about 300 checks; live child streams remain.
3. **0.3, the repository runtime.** `http`, hydrate and verify from a lock,
   tasks, `check`, `docs`. Done when another repository is driven end to end
   by a `tasks.lua`.
4. **0.4, the agent's console.** `pty`, then a signed release and the first
   other repository bootstrapped by a ten-line script that fetches `kuu.exe`
   by hash.

## The Lua-versus-Tcl ledger

The owner asked to hear, without softening, where Lua turns out weaker than
Tcl for this job. The ledger so far:

- **Files and paths are not in the language.** Tcl ships `file`, `glob`,
  `open` with encodings, and a virtual file system that handled Unicode paths
  correctly on Windows for twenty years. Lua's `io` goes through the C
  runtime, which meant an ANSI code page until kuu switched the CRT to UTF-8;
  everything else had to be written as `fs`. Real cost: about 1,700 lines of
  C that Tcl had for free. Real gain: `fs` tells the truth about junctions,
  identity, and long paths, which Tcl's portable `file` never did.
- **No insertion-ordered table.** Tcl's dict remembers order, so a `cli`
  spec could be a mapping; in Lua a spec must be an array of entries, and
  `pairs` order is undefined, so `log` sorts fields and `json` objects come
  out in arbitrary key order. Minor, but felt three times in one day.
- **`global none` is opt-in boilerplate.** Tcl has no equivalent check at all,
  so this is a Lua advantage in the end, but every file must start with two
  lines to get it, and an agent that forgets them gets stock Lua's silent
  globals.

Nothing decisive yet. The coroutine model, the byte strings, and the C API have
been strengths at every step so far.
