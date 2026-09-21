# Scan configuration

`kuu.config.json` controls project inspection by checking and module
inventory. It is read and validated without executing
`manifest.lua`. `kuu check`, `kuu run`, `kuu list` and `kuu capabilities`
validate it before loading project code; each operation keeps its captured
policy. A missing file selects the defaults below. A normal `kuu run` does
not scan the project tree or track file changes; validating configuration does
not start an inspection.

## Configuration file

The file belongs at the project root, next to `manifest.lua`, and is intended
to be tracked with the source. It contains UTF-8 JSON, optionally with a BOM:

```json
{
  "v": 1,
  "scan": {
    "defaults": true,
    "exclude_dirs": ["artifacts"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

`v` is required and must be the number `1`. `scan` is optional; omitting it
is the same as `"scan": {}`. `defaults` is optional and defaults to `true`.
Both rule arrays are optional and default to empty arrays. No other keys
are accepted at either level, and objects and arrays are distinct: use `[]`
for an empty rule list. A missing file selects the default policy; an empty,
malformed or unreadable file is a configuration error in the loader.

The two kinds of rule have different meanings:

| Rule | Meaning | Example |
|---|---|---|
| `exclude_dirs` | An exact directory basename at any depth | `"artifacts"` excludes `artifacts/` and `src/artifacts/` |
| `exclude_paths` | An exact directory subtree relative to the project root | `"vendor/generated"` excludes that subtree, but not `src/vendor/generated/` |

A directory rule excludes the directory and its descendants, not a file
with the same name. These are exact names, not patterns: `"artifact"` does
not match `artifacts/`. No `.gitignore` files are parsed and no `git.exe`
is needed. Being ignored by Git does not itself exclude a path from kuu's
inspection.

## Defaults and deliberate overrides

The policy separates mandatory exclusions from optional defaults:

| Kind | Directory basenames, at any depth |
|---|---|
| Mandatory for project scans | `.git`, `.kuu` |
| Optional defaults | `.tools`, `build`, `node_modules`, `.cache`, `.local`, `.venv`, `__pycache__` |

Explicit rules add to these sets. `"defaults": false` disables the entire
optional set, while `.git` and `.kuu` remain mandatory for project scans.
For example, this policy includes maintained source named `build/` or
`.local/`, while still excluding `.tools/`, `node_modules/` and one generated
subtree:

```json
{
  "v": 1,
  "scan": {
    "defaults": false,
    "exclude_dirs": [".tools", "node_modules"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

This matters when a conventional generated-directory name holds maintained
source. There is no negation or include rule; disable the defaults and name
the exclusions that belong to the project.

An explicitly named checker file or starting
directory overrides its own exclusion, including an excluded ancestor.
Descendant directory exclusions still apply. A project's root is always the
starting point; its own basename never prunes the whole project. These
overrides do not change the link-target rules in [check](check.md).

Exclusions control inspection only. They do not prevent a task from running,
change `require` resolution or provide a sandbox. A module omitted from an
inventory can still be required or inspected to resolve a literal require.

## Normalization and validation

Rules normalize backslashes to `/`, fold ASCII `A`–`Z` to `a`–`z`, then sort
and deduplicate. For example, `"Vendor\\Generated"` and
`"vendor/generated"` in `exclude_paths` become one rule. The match convention
is deliberately ASCII-only, not general Unicode Windows case equivalence:
`"École"` and `"école"` remain different names. Unicode normalization is not
performed either.

The loader rejects:

- Absolute, UNC, drive-relative or stream paths, such as `"C:/build"`,
  `"C:build"`, `"/build"` or `"file:stream"`.
- Leading, trailing or repeated separators, and `.` or `..` components.
  Write `"vendor/generated"`, not `"./vendor/generated/"`.
- Any separator in `exclude_dirs`; use `exclude_paths` for a subtree.
- Wildcard characters `*`, `?`, `[` and `]`. Braces are literal characters,
  so `"{artifacts}"` names that exact directory, not a pattern group.
- Windows-invalid component characters `<`, `>`, `:`, `"`, `|`, U+0000
  through U+001F, and components ending in a dot or space.
- Reserved DOS device names, including `CON`, `PRN`, `AUX`, `NUL`, `COM1`
  through `COM9`, `LPT1` through `LPT9`, `CONIN$` and `CONOUT$`. Extensions
  do not make them valid; `COM` and `LPT` names using superscript `¹`, `²`
  or `³` are also rejected.
- Non-string rules, non-array rule lists, non-boolean `defaults`, unknown
  keys, or a missing or unsupported `v`.

Each original array may contain at most **256 entries, before deduplication**.
The file is bounded to **1 MiB**, including a BOM when present. Each component
may contain at most **255 UTF-16 code units**, and a relative path at most
**32,760 UTF-16 code units**. A character outside the Basic Multilingual Plane
uses two units. These are configuration bounds, not a guarantee that every
accepted spelling names an accessible directory on the current filesystem.

Validation errors carry domain `SCAN`, code `config`, with the configuration
path and field. These are examples of the loader's diagnostic bodies:

```text
C:/work/app/kuu.config.json: scan.exclude_dirs[1]: expected one basename, without path separators
C:/work/app/kuu.config.json: scan.exclude_paths[1]: '.' and '..' components are not allowed
C:/work/app/kuu.config.json: scan.exclude_dirs: at most 256 rules are allowed before deduplication
```

The first can result from `"exclude_dirs": ["vendor/generated"]`; move that
entry to `exclude_paths`. The second can result from
`"exclude_paths": ["../generated"]`; exclusions must stay project-relative.
`kuu check` reports these configuration errors without executing the manifest.
Its JSON form returns `ok:false` and an error with domain `SCAN`, code `config`;
it exits 2, as do `run` and `list` on invalid configuration. `capabilities`
keeps its descriptor available, sets `project.config_error` and skips manifest
execution and module inventory until configuration is fixed. Its module
inventory is explicitly incomplete.

## One policy per operation

An invocation loads configuration once **before executing the manifest** and
retains it for requested inspection, including checker rechecks after `--fix`.
Manifest edits to configuration affect the next
invocation. Direct `check.tree` and `check.modules` calls load once per operation
unless given an internal context. `check.file` explicitly inspects one source
file without loading scan configuration; the check command still preflights
configuration before inspecting its requested files.

Malformed or unreadable configuration is an actionable error before task
execution. Checking remains available when the manifest itself is broken.
Changing scope changes what the next check or inventory inspects. The
[execution ledger](ledger.md) has no file baseline or change counts to migrate.

## Shared traversal

Checking and module inventory share a native collector.
It excludes directories before entering them and takes file metadata from the
same enumeration, avoiding a second listing of every directory. The public
`fs.dirs` API is unchanged. The private collector supports both full configured
rule lists, independently of `fs.dirs`' 64-pattern limit.

Both consumers use the configured scope and defaults above. For direct
checker calls that load their own policy, an intentional change to the legacy
`check.PRUNE` list adds wildcard exclusions; it cannot remove mandatory or
configured exclusions. Supplied internal contexts, including command contexts
captured before the manifest, remain fixed across later `PRUNE` mutations.
The untouched legacy list does not override declarative configuration.
Configured exclusions remain exact names and paths, not wildcard patterns.

The collector distinguishes deliberate exclusions, links it does not follow,
and enumeration errors. It retains readable metadata from a partial scan and
marks the inspection incomplete. Checker findings and module-inventory
completeness use those diagnostics.

## Scan reports

`check --json` and `capabilities --json` expose the normalized
scope and metadata for scans they actually performed. These additive fields
let a reader distinguish a small project from a deliberately restricted or
incomplete inspection. They do not contain the full file inventory.

```typescript
type ScanScope = {
  v: 1;
  defaults: boolean;
  fingerprint: string;
  source: { kind: "default" | "file"; path: string };
  mandatory_dirs: string[];
  default_dirs: string[];
  exclude_dirs: string[];
  exclude_paths: string[];
  effective_dirs: string[];
  extra_prune?: string[];
};
type ScanReport = {
  root: string;
  start: string;
  scope: ScanScope;
  path_rules_applied: boolean;
  complete: boolean;
  counts: { files: number; enumerated_dirs: number; excluded_dirs: number;
            nofollow_links: number; errors: number };
  errors: { path: string; message: string; win32?: number }[];
  seconds: number;
};
```

Scope arrays are present even when empty. `source.path` identifies the root's
configuration path; `kind:"default"` means it was absent. `default_dirs`
contains the enabled optional defaults, and `effective_dirs` is the sorted,
deduplicated union of mandatory, enabled default and custom basenames.
`fingerprint` identifies the normalized configured rules, so a mere reordering
of rules does not change it. Direct checker calls can additionally report
legacy wildcard rules in `extra_prune`; these are separate from that fingerprint.

`root` is the absolute project root and `start` the absolute directory actually
collected. A deliberate checker start can override its own exclusion. When it
is outside the project, `path_rules_applied:false` says that project-relative
subtree rules were inapplicable; basename exclusions still apply.

`counts.files` counts collected ordinary file metadata, including non-Lua
files. `enumerated_dirs` counts directories whose enumeration was attempted,
including the starting directory when it could be opened. `excluded_dirs` counts encountered directory
entries pruned before entering them, not all descendants beneath those entries.
`nofollow_links` counts encountered links deliberately not followed. Neither
exclusions nor non-followed links make a scan incomplete. `errors` counts
enumeration diagnostics, also listed in the `errors` array.

`complete` describes collection within the reported scope, not the whole
filesystem or a transactional snapshot. Reading a collected Lua file can fail
later: checker and module-inventory completeness also cover those reads, while
the underlying scan can remain complete. Syntax findings alone do not make
inspection incomplete. A partial scan retains readable metadata and its counts.

`seconds` is elapsed collection time at the consumer boundary. For the checker
and inventory it covers the collector call. It is not a CPU-time measurement.

## Command timings

`kuu check --timings`, `kuu run --timings TASK` and `kuu capabilities --timings`
print one timing line on standard error. Human output stays quiet about these
phases by default. Their JSON reports always include `result.timings`, whether
or not `--timings` was supplied, and JSON remains on standard output.

All values are wall-clock seconds. Each command documents its own phases on
the [check](check.md), [task](task.md) or [capabilities](capabilities.md) page.
Phases may overlap: checking includes collection, and task execution includes
nested child work and its observer records. Do not add phases or child
durations to derive a total.

`total` starts just after the timing helper loads, before other command
imports, and ends after command work and report preparation, including the
last history append for a run. It excludes OS/runtime startup before command entry
and final serialization, emission and flushing. Earlier streamed run events
are part of command work. An external stopwatch can therefore be larger,
without a promised bound on the difference.

Unavailable phases are omitted, not reported as zero. Reportable failures keep
the phases and partial inspections reached before failure. Help and
command-line parser exits retain their existing output conventions and produce
no timing line.
