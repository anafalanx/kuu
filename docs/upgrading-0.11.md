# Upgrading to 0.11

0.11 corrects defects found in two reviews of 0.10.0 and makes the first
encounter with the executable more useful. It keeps the same Windows baseline
and Lua version. Most projects need only replace their executable, run
`kuu check`, and run their tasks. Programs that read streams or consume the
capabilities descriptor should read the changes below before replacing it.
Version text has two components again, so programs that parse it must also
read the version migration below.

Verify the replacement's signature and SHA-256 against the release. If a
project depends on a correction described here, use
`rt.version_at_least(0, 11)` for its minimum-version guard. For the earlier
manifest, task-report and checker changes, read
[upgrading to 0.10](upgrading-0.10.md).

## Versions are two numbers

Published versions now have the form `N.N`: two nonnegative integers,
compared numerically. `0.11` follows `0.10`. The numbers identify and order
releases; they do not encode semantic-version compatibility categories.
Read the upgrading notes for contract changes and test the executable a
project adopts. The explicit interface commitments in [stability](stability.md)
continue to apply independently of the numbering choice.

`rt.version` and the executable's displayed version are `"0.11"`.
Windows' numeric file and product versions are `0,11,0,0`; their string values
are `"0.11"`. The extra numeric fields belong to the Windows resource format,
not to the public version.

A guard that parses three components, such as
`rt.version:match("^(%d+)%.(%d+)%.(%d+)$")`, no longer matches. Replace it
with a numeric minimum-version check:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 11),
  "this project requires kuu 0.11 or later; found " .. rt.version)
```

Existing calls with a third argument remain accepted for old guards. They
compare the running release as `(0, 11, 0)`, so a guard for an older
three-component release still works; new guards should use two components.
Historical references to 0.9.0 and 0.10.0 describe those releases as published.

The deprecated `tasks.lua` fallback also remains supported in 0.11, with its
warning and no scheduled removal. `manifest.lua` takes precedence when both
files exist. Renaming the old file is still recommended and requires no
change to its contents; the earlier announced removal in 0.11 does not apply.

## Find an API and use it immediately

The entry help and [agent guide](agent.md) now demonstrate `kuu -e`: all kuu
modules are available to an inline script, without creating a script file or
manifest. Print the result explicitly; use `json.encode` when the result
should be structured. Repeated project operations belong in named tasks.

```text
kuu docs
kuu docs search fs.read
kuu docs fs reading-and-writing
kuu -e "print(assert(require('hash').file('sha256', 'README.md')))"
```

The first command lists the available pages. Search finds matching lines and,
in plain output, gives commands for retrieving their surrounding sections.
An API name need not be a section heading: `fs.read` is documented under
`reading-and-writing`. `kuu docs agent` explains the project workflow.
Page and verb inventories sort their exposed names correctly even when one
name is a prefix of another; the shorter name comes first.

## Streaming reads keep their memory bound

For `proc.start { stream = true, ... }`, `maxout` is the maximum unread
buffer for each output stream. Previously, a whole-output or unfinished-line
read could fill that buffer and wait forever: the child could not write more
until the same reader consumed something. It now returns `nil, PROC toobig`.
No bytes are consumed by the error; drain with numeric reads or `read("some")`,
or start the child with a larger `maxout`.

The boundary is exact. Even output exactly `maxout` bytes long can produce
`toobig` if EOF has not yet been observed. `lines()` and `err_lines()` raise
read errors, including this one, instead of silently ending iteration.
Stream `maxout = 0` is rejected because it cannot make progress. Captured
`proc.run` output still uses `truncated` to report discarded output; check it
before interpreting a captured result as complete.

Numeric reads now return **up to** the requested count once any bytes are
available, as documented. Code needing an exact count must accumulate it
across reads and handle EOF. A waiting reader retains its reservation until
it resumes; a competing reader gets `PROC busy`, and closing the child wakes
the waiting reader with `PROC closed`.

Pending stdin writes now own stable storage, consumed queue space is reused,
and aggregate waiters keep their allocations until cleanup. These correct
invalid buffer lifetimes and memory retention under sustained process activity.
`inherit_stdin = true` also works with streamed output, and JSON task
execution preserves inherited input and EOF. See [proc](proc.md).

Concurrent [filesystem-watch](fs.md) readers receive complete batches in
the order they began waiting. Each batch goes to one reader; callers needing
several observers must distribute it themselves.

## Incomplete inspection is visible

`check` reports unreadable directories and incomplete listings as `read`
findings. Its module inventory follows the runtime's resolution rules,
including Unicode names and modules hidden by bundled names. Consumers of
the provisional capabilities descriptor should handle these additions:

- `check.modules(root)` returns `complete` and `errors` alongside its existing
  fields. Each error has `path`, `message`, and an optional `win32` code.
- `capabilities` exposes these as `project.modules_complete` and
  `project.module_errors`. A partial inventory is useful, but not proof that
  an omitted module is absent.
- `project.ledger.records` is optional: it is present only when verification
  establishes a count. An unreadable history sets `intact = false` and
  `unreadable`; corrupt content is described by `broken`. Missing history
  remains distinguishable from a failed read.

The ledger refuses to append behind an unreadable predecessor. Read, write
and close failures warn and appear in the task report's notes while preserving
the task's outcome. Record shape is checked, and broken history is reported
even when no recent record is readable. See [capabilities](capabilities.md),
[check](check.md), and [ledger](ledger.md).

The global fixer leaves initialized or unsupported declarations unchanged
instead of rewriting their meaning. Checker inference also handles reassigned
tool bindings and escaped or shadowed export tables conservatively; each check
operation reads current tool declarations. Task help works before dependency
argument validation. Dry-run and other JSON reports repair invalid UTF-8
without dropping entries whose repaired keys collide.

## Malformed helper inputs are refused

Several helpers previously accepted input whose meaning could not survive a
round trip, or silently ignored part of it. These cases now fail explicitly:

- Task dependencies and tool lists, archive entry lists, and marked JSON
  containers require the documented contiguous array shapes. Ordered JSON
  objects reject duplicate names.
- CSV header mode and record encoding reject duplicate column names. Array
  mode remains available when repeated header text is intentional.
- INI writers reject unrepresentable keys and section names containing line
  endings. Valid spaces and brackets inside section names are preserved.
- CLI specifications reserve the normalized `help` key, require finite numeric
  bounds, and enforce required rest arguments. Help still waives missing
  required values. Overflowing size text is rejected.

Logging failures return false and increment `dropped`. In JSON mode an
unencodable record is dropped whole, so a consumer never receives a plain-text
fallback in its JSON stream. Text logging preserves values associated with
numeric field keys. See [log](log.md) and the individual helper pages.

## Destinations and builds survive failure

Archive packing stages its output beside the destination and replaces the
previous archive only after success. Packing into the input tree excludes
the exact output and staging file, and filenames beginning with `@` are
literal operands. Such entries may retain a leading `./` in their archived
names. Atomic file writes and HTTP downloads use compact sibling names so
long destination basenames remain usable.

HTTP downloads retain their absolute destination across waits, reject NUL
output paths before opening a file, and clean up construction allocations
and staging files when validation or a Lua accessor raises. Long explicit
executable paths and PATH entries also resolve correctly.

For people building kuu, every payload build now observes added and removed
files. Generation checks input and output failures and replaces the generated
file only when complete; unchanged bytes keep their timestamp, and a failed
generation is retried on the next build. Windows version resources validate
the two published components and fill their unused numeric fields with zero.
The bundled manual has explicit, validated section links,
and the cookbook's NDJSON wrapper rejects truncated captures before parsing.
