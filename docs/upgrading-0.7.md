# Upgrading to 0.7

0.7 adds the last planned capabilities before the 1.0 freeze: child resource
limits, scoped deadlines, default task timeouts, services, event logs,
signature verification, palette-name checking, and provisional console
automation through `pty`.

Copy the new executable into the repository root, read the changes below,
run `kuu check`, and run the project's tasks. Numeric durations remain
seconds, as in 0.6. A project still on 0.5 also needs the
[0.6 duration migration](upgrading-0.6.md).

## Windows 11 23H2 compatibility in the development tree

The source now supports Windows 11 23H2. `ReleasePseudoConsole` is resolved
only when the host exports it; 23H2 uses isolated close/drain workers,
preserves final output after the entire supervised job exits, and waits for
canceled I/O before transferring pipe ownership. The Lua API is unchanged.
The published, signed 0.7 asset predates this change and still cannot start
on 23H2. Use a build containing the compatibility change; the existing
release asset and its checksum have not been replaced.

## Existing programs and reports

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
See [check](check.md) for the exact report schema and limitations.

`task.defaults` currently accepts only `timeout`. A malformed duration or an
unknown field raises `TASK badvalue` without replacing the preceding default;
an empty table clears it. It bounds each child of `task.exec`, not the entire
task or dependency plan. Numeric values are seconds and zero is a valid
explicit timeout. See [Tasks](task.md), including the exact `run --json`,
`run --dry-run --json`, and `list --json` schemas.

The schemas describe the existing output boundaries too: task output under
`run --json` goes to stderr through `print`, `io.write`, and `task.exec`;
direct `io.stdout` writes can still mix with the envelope. `list --json`
requires quiet top-level task declarations. Malformed runner options and
missing paths can fail before a JSON report exists, as documented per verb.

## New capabilities

- **Child limits.** `proc.run`, `proc.start`, and `task.exec` accept
  `limits = { memory = "512M", cpu = "30s", processes = 8 }`. The bounds
  apply to the child's whole job: committed bytes, user CPU seconds, and
  simultaneously active processes including the first child. When a bound
  is breached, a process result has `status = "limit"` and
  `limit = "memory" | "cpu" | "processes"`. If you opt into limits, handle
  that status as a failure regardless of `code`. `task.exec` returns
  `TASK failed` and names the breached bound. [proc](proc.md#limits)
- **Scoped deadlines.** `sched.deadline(duration, fn, ...)` returns the
  function's results unchanged or `nil, SCHED deadline` when its waits
  exhaust the scope. Nested scopes use the earliest deadline. This cannot
  interrupt CPU-only Lua, and spawned tasks do not inherit it. A child is
  not automatically killed by the scope: hold a `proc.start` handle in a
  `<close>` local when its lifetime must end on unwind. [sched](sched.md#deadlines)
- **Services.** `svc.list`, `status`, `start`, `stop`, `restart`, and `wait`
  inspect and control the Service Control Manager. State transitions poll
  on the event loop. Access failures are explicit and may require elevation;
  a timeout stops waiting without undoing the request. [svc](svc.md)
- **Signatures.** `sys.signature(path [, options])` distinguishes unsigned
  files, accepted embedded Authenticode signatures, and rejected signatures
  with a reason. Match the signer or pinned certificate thumbprint before
  running an installer. Windows catalog-only signatures report unsigned;
  revocation/network retrieval are off unless requested. [sys](sys.md#syssignature)
- **Event logs.** `evt.logs` lists channels and `evt.read` returns bounded
  newest-first snapshots filtered by time, level, and provider. A record has
  typed system fields and a rendered message, with raw XML as the fallback.
  It never writes or clears a log. [evt](evt.md)
- **Interactive consoles.** `pty.spawn` creates a supervised ConPTY child.
  Its handle offers Lua-pattern `expect`, raw reads, a plain-text view,
  writes, resize, wait, kill, and close. The view is a small VT filter rather
  than a terminal screen model. This module remains provisional and outside
  the future 1.x freeze. [pty](pty.md)

The [cookbook](cookbook.md) has ten complete programs using these APIs and
the existing palette. Its extracted programs are checked by the suite;
safe fixtures exercise downloads, logs, process control, INI edits, service
decisions, signatures, and console input. The [PowerShell map](powershell.md)
includes the new operations.

## Version guards and verification

Use the numeric minimum-version guard from [Stability](stability.md) or the
complete [adoption example](adopting.md). A guard tests the capabilities
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
[Toolchain](toolchain.md) records the packages and commands.
