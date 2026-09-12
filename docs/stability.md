# Stability

kuu is still before 1.0. The 0.x releases may change contracts when use in
real repositories shows a mistake. Each such change belongs in that release's
upgrading page, with the old form beside the replacement. Projects carry a
specific `kuu.exe` in their own repository; updating that copy is deliberate.

## The 1.0 boundary

At 1.0, the documented public interfaces of these modules will be frozen:

`archive`, `check`, `cli`, `csv`, `env`, `err`, `fs`, `hash`, `http`,
`ini`, `json`, `log`, `mem`, `net`, `proc`, `re`, `reg`, `rt`, `sched`,
`sync`, `sys`, `task`, `text`, and `time`.

The same promise covers running a file, stdin, or an inline program; the
`docs`, `run`, `list`, and `check` verbs; their documented options and exit
codes; and their documented JSON reports. It includes the supported Windows
baseline and the documented Lua language version. The freeze is a promise
for 1.x, not a claim that the 0.9.0 interface can no longer improve.

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

`capabilities` is outside for the same reason, one release later: it arrived
in 0.10.0 and nothing has driven it yet. What it reports is kuu describing
itself, so the shape of that description is exactly what a consuming agent
would build on, and a descriptor is cheaper to widen after adoption evidence
than to narrow inside the freeze.

Private modules and names starting with `_`, command implementation modules
under `cmd`, internal helper processes, build artifacts, and undocumented
implementation details are also outside the public contract.

## What 1.x may add

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

## A minimum-version guard

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
[Upgrading to 0.9](upgrading-0.9.md).

Place this before declarations that use newer capabilities. The guard tests
the minimum capability level, while the checked-in release hash and the
project's tests decide which executable the project adopts. Run those tests
when updating, and read the upgrading notes for every intervening 0.x
release or a future major release.

For the changes introduced with this statement, see
[Upgrading to 0.7](upgrading-0.7.md). For a complete `tasks.lua`, see
[Adopting kuu](adopting.md).
