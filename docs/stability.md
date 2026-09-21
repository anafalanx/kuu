# Stability

kuu is still before 1.0. The 0.x releases may change contracts when use in
real repositories shows a mistake. Each such change belongs in that release's
upgrading page, with the old form beside the replacement. Projects carry a
specific `kuu.exe` in their own repository; updating that copy is deliberate.

Published versions from 0.11 have the form `N.N`, two nonnegative integers
compared numerically: 0.11 follows 0.10. The components identify and order
releases; they do not encode semantic-version compatibility categories.
Compatibility follows the explicit promises below and each release's
upgrading notes, not an inference from which number changed.

## The 1.0 boundary

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
guarantee. Such a change cannot be made under this promise: it would require
an explicitly announced replacement compatibility policy and a migration
note. Changing a version number alone does not authorize it.

## A minimum-version guard

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
it with the call above. [Upgrading to 0.11](upgrading-0.11.md) records that
migration; [upgrading to 0.9](upgrading-0.9.md) records the earlier
change as history.

Place this before declarations that use newer capabilities. The guard tests
the minimum released capability level, while the reviewed executable hash and
the project's tests decide which executable the project adopts. Development
artifacts can share version text with an earlier release; identify those by
build/hash and check feature availability where needed. Run the project's
tests when updating, and read the upgrading notes for every intervening release.
For 0.12's execution-history, inspection and file-attribute changes, read
[Upgrading from 0.11](upgrading-from-0.11.md).

For the changes introduced with this statement, see
[Upgrading to 0.7](upgrading-0.7.md). For a complete `manifest.lua`, see
[Adopting kuu](adopting.md).
