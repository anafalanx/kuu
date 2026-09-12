# A JavaScript capability for kuu

> Superseded on 2026-09-13 by
> [the front-door plan](plan-front-door-2026-09-13_001735.md). Nothing below
> is built or will be built as written: kuu mandates no runtime and is never
> extended; a project builds the tools it needs and calls them through the
> door. This note stands as the record of what was considered and measured,
> and a spike on 2026-09-12 confirmed its confinement model works and found
> that a junction inside a granted directory escapes it.

kuu gains the ability to run JavaScript and TypeScript, so that capability can
be added to a project without writing C and without depending on anything
installed on the machine. The runtime is Deno, pinned to a version by the kuu
release that uses it, downloaded by the consumer on request, and never
shipped.

This note records the decision, the measurements behind it, what was
considered and rejected, and the four choices that shape the implementation.
Nothing here is built yet.

## The problem it solves

kuu's palette is C. Adding a capability means writing C, vendoring a library,
rebuilding and releasing — and vendoring is already 43% of the binary in PCRE2
alone, with 4.4 MB of third-party source to track for as long as kuu lives.
Lua's own library ecosystem is thin and mostly needs C compilation anyway,
which `package.cpath` being empty deliberately forecloses.

So there was no way to extend kuu that did not go through C. That is the gap
this closes.

## Why a downloaded runtime rather than the alternatives

**PowerShell, reached through a bridge.** Rejected after adversarial review,
on four counts. It grants everything in one `require`, which breaks the rule
that a program obtains capabilities by naming modules, and silently reverses
the "no" already recorded in `docs/powershell.md` for firewall, Defender and
Windows features. Its errors collapse to one code, so callers would have to
branch on message text — the thing `err.is` exists to prevent. A long-lived
`powershell.exe -Command -` fed from a pipe by a non-Microsoft binary is a
textbook EDR pattern, and no mitigation was found. And a measured idle
PowerShell holds **68,046,848 bytes** of working set, 43 times kuu's entire
binary, per bridge.

It also depends on something preinstalled, which the runtime should not.

**Tcl plus twapi.** Genuinely strong and not dismissed: ~6 MB total
(`tclsh90s.exe` at 3,688,314 bytes, the twapi zip at 2,200,419), thirty years
stable, already fetched and built by Time Actual, and it reaches COM, WMI,
ACLs and services — the exact gap list. It remains the right answer for
Windows API reach specifically, and a capability module may yet use it.

It was not chosen for the general slot because the ecosystem beyond Windows
APIs is small, and because the point of the general slot is breadth.

**A compiled Go helper per capability.** Sound, and still available: a small
static binary speaking NDJSON over stdio, which kuu already does internally
for `archive.list`. Rejected as the *general* answer because it needs a Go
toolchain fetched and a build step per capability, with the reproducibility
burden that implies, where an interpreted runtime needs neither: the helper
source is the artifact.

**Deno.** A single executable, no package manager, no install tree, no PATH
entry. TypeScript with no build step. A large standard library plus npm
reach. And — the property that decided it over the others — **an explicit
permission model**, which is what lets kuu keep a capability gate over a
general escape hatch.

Its download is about **24 MB** for Windows x86_64; current releases are 2.9.x.

## The risk, stated plainly

Deno is the youngest candidate, 2.0 broke compatibility in 2024, and it is
stewarded by a company rather than a foundation. It is MIT and public, so it
survives corporate failure, but surviving and being maintained are not the
same thing.

**Pinning is what makes this acceptable.** A kuu release names one Deno
version. That pair can be frozen together indefinitely; churn upstream cannot
reach a project that never re-pins. The consumer is never asked to track Deno,
only to have the one version their kuu release names.

## The four decisions

**1. Non-interactive runs never download.** CI and any other unattended
context refuses to fetch, and must be pre-seeded — from a retained zip or a
restored `.kuu/`. A build can therefore never break because an upstream URL
moved, which is the property a fifteen-year project needs. It costs one
explicit step in every CI configuration, and that step is the point.

**2. Everything lives in the project.** `.kuu/deno/<version>/` unpacked, and
the fetched archive retained in `.kuu/` beside it. No shared cache, no
per-machine state, nothing outside the checkout. Ten projects means ten
copies, which is the price of the rule that projects share nothing and stand
alone. `.kuu/` already exists and is already git-ignored; its description in
`docs/adopting.md` broadens from "kuu's notebook (mem)" to kuu's own state for
this repository.

**3. Both a curated layer and a general one.** Capability modules —
`require "wmi"`, say — are thin Lua wrappers over scripts authored and tested
here, so every call site stays checkable by `check` through `_palette`. Beside
them, a general way to hand kuu a TypeScript script and get structured data
back, which is the affordance an agent can count on. Deno's permission flags,
not `require`, are the real boundary for the general path.

**4. Nothing is fetched implicitly.** A setup command the consumer runs, which
confirms interactively and refuses when not attended. Combined with decision
one this gives a single clear rule: **kuu never downloads anything unless
explicitly told to, in any context.** `--version`, `check`, `docs` and any task
not touching JavaScript work on a machine that has fetched nothing.

## Mandatory, and what that means

The runtime is mandatory in the sense that an agent may assume it is
obtainable and that kuu knows how to obtain it. It is not mandatory in the
sense that kuu is inert without it: the prompt and the setup command are the
mechanism, and the core palette is untouched.

An optional tier would have been safer and was argued for. It was rejected for
a reason that holds: a conditional affordance is one an agent must check every
time, and a wrong assumption fails silently where a missing capability fails
loudly. A standard beats a description only when it is universal.

## Deno is named in exactly two places

To a consumer, this is a kuu capability. The documentation describes what kuu
can do, not what runs underneath.

The exception is consent: you cannot ask permission to download an unnamed
24 MB archive. So the runtime is named at the setup prompt, and in the bill of
materials kuu emits for archival. Nowhere else — not in module names, not in
the manual's capability pages, not in error messages a program can see.

## The internal boundary

The point of the boundary is that the engine can be replaced by the kuu
developer without rewriting the capabilities. Two rules do most of that work.

**One module owns the runtime.** Discovery, spawn, protocol framing,
permission flags, the pinned version, URL and hash — all in one place, in the
shape `_archive` and `_palette` already have.

**The JavaScript is written against Web and ECMAScript standards, and every
engine-specific call goes through a single shim.** `fetch`, `TextEncoder`,
`URL`, `structuredClone` port to Node or Bun unchanged; `Deno.readTextFile`,
`Deno.Command`, `Deno.permissions` do not. If the shim is the only file that
names the engine, swapping engines is rewriting one file. If engine calls are
scattered through the capability scripts, it is rewriting all of them. That
distinction costs nothing now and is the entire difference later.

## The freeze consequence

At 1.0 kuu's public contract would include *requires a JavaScript runtime it
can download*. That is a dependency inside the freeze.

Which makes **the retained archive a first-class archival artifact**, not a
cache. A fifteen-year project must keep it deliberately. kuu should therefore
emit what to archive, machine-readably — pinned version, URL, sha256 — so a
project can retain it on purpose rather than discover in 2035 that nobody did.
z has `bom` for exactly this thought.

Availability, not integrity, is the binding constraint over that horizon. A
hash proves what you got; it does not make it obtainable. Time Actual's 27
pinned URLs all resolve today, checked on 2026-09-12, and `repo.msys2.org`
will eventually rotate some of them out. Retention is the answer — z keeps
241 MB of downloads, Time Actual 246 MB — and a preflight that HEADs every
pinned URL turns the cliff into a slope by reporting rot before a cold setup
needs it.

## Open questions

- **Consent scope.** `.kuu/` is per project, so a fresh clone of the eighth
  project prompts again. Correct, or maddening by the third time?
- **Upgrade.** A kuu release that re-pins should not clobber a working
  install; `.kuu/deno/<version>/` allows coexistence, but the removal policy
  for superseded versions is unwritten.
- **Verification cost.** Hashing the unpacked runtime on every run is too
  slow. Hash at setup, record it, check cheaply afterwards, and keep a deep
  verify as its own command.
- **What `check` reports** for a file using the capability when the runtime is
  absent. It should be a finding before running, which is the palette-name
  machinery extended.
- **Whether the general escape hatch is a public module or reached through a
  capability**, and what its default permission set is. The answer decides
  whether `require` remains a meaningful gate for the general path or whether
  the flags carry it alone.
