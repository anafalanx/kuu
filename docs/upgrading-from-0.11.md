# Upgrading from 0.11

Move a project from signed kuu 0.11 to 0.12 by reviewing its runtime
assumptions, inspection policy and history consumers before running its tasks.
This page describes the changes in 0.12; [Upgrading to 0.11](upgrading-0.11.md)
records that release's changes from 0.10.0.

Keep working task and tool declarations; there is no wholesale manifest rewrite.
The checklist identifies the expectations and consumers that may need changes.

**These changes require kuu 0.12.** Use `rt.version_at_least(0, 12)` when a
project depends on them. That guard establishes a minimum capability level;
the reviewed SHA-256 and signing identity still identify the approved runtime.
No runtime upgrade is performed by reading this page.

## Upgrade in order

1. **Verify the chosen candidate.** Follow the project's owner-approved runtime
   choice and [verification procedure](adopting.md#verify-before-first-execution).
   Keep the candidate separate from the live executable during evaluation. Match
   its reviewed SHA-256 and signing identity, or the explicitly approved identity
   of a development artifact, before executing it. Keep the project's downloaded
   or committed-runtime model; a newer version alone does not authorize new pins.
2. **Read the candidate's own manual before loading project code.** Run its
   `docs agent` and `docs upgrading-from-0.11` commands. `docs`, including searches
   and sections, reads only the embedded manual: it needs no network or manifest.
   `kuu check` is static inspection without executing project Lua; omit `--fix`
   for a read-only check. `capabilities` and `list` execute the manifest to learn
   its declarations, so review it before using those commands with the candidate.
3. **Review the project's expectations.** Read `AGENTS.md`, README instructions,
   automation helpers and report consumers against [the list below](#project-instructions-and-assumptions).
   Update statements that describe retired behavior and adapt consumers of removed
   fields. Keep the owner's task, verification and approval policies; the embedded
   manual describes what this executable does, not permission to replace them.
   Read the existing `kuu-eval.md` at the project root and identify reported
   difficulties to recheck during candidate validation.
4. **Check which source will be inspected.** Review `kuu.config.json` and the
   [directory exclusions](#explicit-project-inspection). Maintained source under
   an optional default name needs a deliberate policy. A missing configuration
   selects defaults; no new configuration file is required when those are right.
   Run the candidate's `check`, read warnings as well as errors, and correct
   declaration mistakes it now detects before running tasks.
5. **Validate in an isolated project copy.** Put the candidate at that copy's
   expected project runtime path so nested tasks use the same verified bytes.
   Keep its paths, outputs and task side effects isolated from the live project;
   a copied manifest may still refer to external locations. Then inspect
   `capabilities` and `list`, and run the project's relevant tests. Where history
   compatibility matters, include a preserved copy of its old history and check
   the resulting mixed-version chain and report consumers. New runs append v2
   records; the old executable has not been validated against them.
6. **Adopt the verified result together.** Stop tasks using the old runtime before
   replacing it. Review the runtime pins, changed project instructions, configuration
   and helpers together; change minimum-version guards only for features actually
   required. Retain the old approved runtime and a separate pre-upgrade history copy
   if rollback is required. After new runs write live v2 history, replacing only the
   binary is not an established rollback procedure. Preserve both histories; do not
   edit, merge or delete ledger lines to make an older executable accept them.
   Record the adopted identity and validation evidence in the project's upgrade record.
7. **Maintain the project's `kuu-eval.md`.** Append a concise dated entry for the
   upgrade evaluation, including an unsuccessful or deferred adoption, using
   [the reporting format](agent.md#reporting-back). Create the file if missing;
   preserve earlier entries. Record the actual runtime tested, commands and
   outcomes, what helped, remaining difficulties and new regressions. Recheck
   earlier issues and reference their dated entries in a new follow-up; call an
   issue resolved only after verifying it with the candidate.
   Bring the relevant results from an isolated test copy back to the project's
   root evaluation document. Continue maintaining it after subsequent work with
   kuu; the upgrade entry does not replace ongoing feedback.

The runtime API remains available to `kuu -e` for immediate queries. Find an API
with `kuu docs search NAME`, then use the printed `Read:` command to retrieve its
section. Full pages and section retrieval also support `--json`.

## Project instructions and assumptions

An agent returning to an established project should check these specific claims,
including copies of old kuu advice in `AGENTS.md` and README files:

| Assumption to review | What to use now |
|---|---|
| A run snapshots the source tree and records which edits it ran against | Runs record execution. Use the project's explicit source-review or version-control workflow when changed files matter. There is no automatic watcher or index. |
| A missing `delta`, `observation` or `project.ledger.unaccounted` means no files changed | These fields are absent by contract. Absence makes no claim about file changes or who caused them. |
| `.kuu/ledger/tree.json` must be refreshed, repaired or migrated | Leave the existing file alone. It is ignored, and there is no replacement baseline. |
| Every ledger record is v1, or report timing includes scan phases | Accept the documented v1/v2 history and current run-report shape below. Stream-event v1 is a separate schema. |
| Git ignore rules determine which Lua files kuu checks | Review `kuu.config.json` and the explicit inspection exclusions below. |
| Calling `proc.run` is always a bypass, even when output must be captured | Resolve a declared tool with `task.command`, then use `proc.run` for capture. This is supported: the enclosing task/run remain recorded, but there is no individual child ledger record or child event. Prefer `task.exec` when capture is unnecessary. |
| `kuu capabilities` or `kuu list` merely reads manifest text | Both execute its declarations. Use `kuu check` for static inspection and `kuu docs` for documentation without loading the manifest. |
| `rt.version_at_least(0, 11)` proves the APIs described here are present | Use `rt.version_at_least(0, 12)` for 0.12 capabilities, and keep the project's reviewed runtime pins. |

For process capture, successful nonzero child exits and actionable failure reports,
read the [process recipes](process-recipes.md). File attributes and the checker
changes below may also let the project simplify existing workarounds. Adopt only
the recipes relevant to that project; they are examples, not new mandatory tasks.

Keep a short bootstrap instruction in the project's existing agent instructions
instead of copying the manual. Adapt this text to its approved runtime path:

```text
Use the project's pinned kuu.exe and follow its runtime-verification instructions.
Read that executable's `kuu docs agent` when starting work; use `kuu docs search`
and section retrieval for current APIs. On a runtime upgrade, read the candidate's
embedded migration notes before running project code. When moving from signed
0.11, start with `kuu docs upgrading-from-0.11` in the verified candidate.
`kuu check` without --fix inspects project Lua statically; `kuu capabilities`
and `kuu list` execute the manifest. Follow this project's task and approval
policies. Resolve stale runtime claims against the current embedded manual and
update the affected instructions as part of the authorized upgrade.
Read and maintain `kuu-eval.md` at the project root. Append a dated entry for
each piece of work using `kuu docs agent reporting-back`; create it if missing.
Preserve earlier entries and report retested issues in a new follow-up, with
the runtime identity, commands and outcomes; leave untested issues unverified.
```

## Execution history

0.12 changes the ledger and run-report contract. These changes are not part of
the signed 0.11 release.

Normal `kuu run` execution no longer takes project-tree snapshots, compares
file changes or publishes a baseline. It does not start a watcher or maintain
a filesystem index. The [ledger](ledger.md) retains task, child and run
records, outcomes, timings, arguments and best-effort repository ref/head
metadata. Repository identity does not describe dirty files or attribute
changes to a task. Explicit filesystem operations, including `fs.watch`,
remain available; [checking](check.md), [module inventory](capabilities.md)
and their [scan exclusions](scan.md) remain supported.

Consumers of reports and history should adapt these fields:

- New durable ledger records have `v:2` and omit `delta` and `observation`.
  The new reader and chain verifier accept both versions 1 and 2. Existing
  NDJSON lines keep their original bytes and hash links, subject to normal
  ninety-day retention. Treat old change metadata as historical only.
  Older executables have not been validated against version 2; do not assume
  a downgrade can read or append the new history.
- An existing `.kuu/ledger/tree.json` is ignored and left untouched. No
  migration, cleanup or replacement baseline is required.
- `run --json` no longer emits result `scope` or `scans`, ledger `observation`
  or `publication`, or timing phases `initial_scan` and `final_scan`.
  `result.ledger` instead reports `{records, complete, error?}` once opening
  is attempted: successful appends for this invocation, whether recording
  succeeded, and any opening or recording error. Failures remain nonfatal to
  tasks and appear in `notes`. Preflight failures and dry runs omit the
  summary. See [Tasks](task.md) for the complete shape.
- Stream events still have `v:1`; their schema version is separate from
  durable ledger records. Existing task and child durations keep their
  meanings. The `ledger` timing measures opening and append work.
- `capabilities --json` no longer emits `project.ledger.unaccounted`. Kuu
  makes no claim to know which project edits a crossing accounts for.

## Explicit project inspection

Checking and module inventory now use a shared declarative inspection policy
from `kuu.config.json` beside the project's manifest. Its automatic directory
exclusions are:

| Kind | Directory basenames, at any depth |
|---|---|
| Mandatory | `.git`, `.kuu` |
| Optional defaults | `.tools`, `build`, `node_modules`, `.cache`, `.local`, `.venv`, `__pycache__` |

A missing configuration file selects those defaults. If a conventional name
such as `build/` or `.local/` contains maintained source, disable the optional
set and add only the exclusions the project needs:

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

`exclude_dirs` matches an exact basename at any depth; `exclude_paths` matches
a project-relative directory subtree. These rules add exclusions, without
negation or include patterns. `defaults:false` leaves `.git` and `.kuu`
mandatory for automatic inspection. An explicitly named checker file or
starting directory overrides its own exclusion; descendant rules still apply.
Git ignore rules do not configure this policy. See [scan configuration](scan.md)
for path validation and the reported scope and scan metadata.

`check`, `capabilities`, `run` and `list` validate this file before project code
can execute. Checking still reads the manifest as text. Invalid or unreadable
configuration makes `check`, `run` and `list` exit 2 with `SCAN config`;
`capabilities` reports the error and an incomplete inventory without loading
the manifest. Each invocation retains its captured policy. The configuration
controls inspection only and does not change `require` resolution. Normal
`run` and `list` do not automatically scan the project tree or track changes.

## File attributes

`fs.attributes(path, options)` and `fs.set_attributes(path, patch, options)`
add inspection and mutation of six named Windows file attributes. Options
are optional. The getter returns `attrs` plus six booleans; setters preserve
unspecified bits and accept only named boolean flags. Read the
[file-attribute contract](fs.md#file-attributes) for examples and errors.

Both calls select the final link itself by default; use `{follow=true}` for
its target. Existing `fs.stat` behavior is unchanged. `{}` validates readable
metadata without testing write permission; every nonempty patch requests
write-attribute access, even when its values already match. Directory
`temporary=true` is rejected without applying any of the patch. Attributes
do not replace ACL permissions or imply recursive cleanup.

These calls require 0.12; use `rt.version_at_least(0, 12)` before declarations
that need them. Signed 0.11 does not provide them.

## Cleanup, declarations and task help

0.12 also fixes recursive removal of readonly
directories. Clearing a readonly bit now checks errors and leaves link targets
untouched. Removal remains nontransactional; the [cleanup guide](cleanup.md)
provides bounded project-level retries and preserves primary and cleanup errors.

`kuu check` now validates literal task/tool identifiers and independently known
declaration fields, including a misplaced task-level `timeout` beside a run
function. Direct, curried and simple aliased constructors work; dynamic values
stay conservative. See [declaration checking](check.md#task-and-tool-declarations).

Task help shows non-empty descriptions above usage with or without an explicit
argument schema. Tasks without a schema accept a lone trailing `--`, while
still rejecting real extra arguments. Rest forwarding and child exit codes are
preserved. [Task help](task.md#running-and-failing) explains `run TASK --help`
versus deliberately forwarding `run TASK -- --help`.

The 0.11 executable does not include these corrections.

## Adoption recipes

The manual now includes tested recipes for [process descriptions and
diagnostics](process-recipes.md), [caller working directories](working-directories.md),
[shared project environments](project-environment.md),
[relocation with non-repairing health checks](relocation.md),
[isolated editor launch checks](editor.md), [cached native helpers and local
shortcuts](native-helper.md), and [cache reconstruction and uncertain publication
recovery](reconstruction.md). These use project Lua to express the policy; each
page states any minimum-version requirement.

[Adopting kuu](adopting.md) supports both a downloaded, ignored runtime and a
committed signed runtime. Both models pin approved bytes and signing identity;
a minimum-version guard alone does not identify an approved executable.
