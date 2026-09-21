# The ledger

The door remembers what passes through it. Every `kuu run` writes one record
per crossing — the run itself, each task, each child a task ran through
`task.exec` — to `.kuu/ledger/<day>.ndjson` under the project root, from
what kuu directly knows about execution. It answers "what ran here, and how
did it end", kept locally for ninety days. A child a task starts with
`proc.run` itself, a `task.command` table included, is the program's own call
and not a crossing.

```text
.kuu/ledger/2026-09-21.ndjson      one record per line, the day in UTC
```

Add `.kuu/` to the project's `.gitignore`, as for [mem](mem.md). The ledger
is the machine's, not the repository's; a summary a project wants to keep
is the project's to commit.

A normal run does not scan the project tree, compare file changes, maintain
a filesystem index or start a watcher. The ledger describes execution, not
which files changed or which process caused an edit. [Checking](check.md)
and [module inventory](capabilities.md) inspect source when requested; their
[scan configuration](scan.md) does not add filesystem tracking to a run.
Programs can still explicitly use [fs.watch](fs.md).

## A record

```json
{"v":2,"kuu":"0.12","root":"C:/work/app","git":{"ref":"refs/heads/main","head":"7c1a…"},
 "kind":"child","name":"report","tool":"report","task":"weekly","pid":4120,
 "argv":["C:/work/app/tools/report/report.exe","--out","build/r.json"],
 "at":1789980000.1,"seconds":3.2,"status":"exit","code":0,"bytes":{"out":8192,"err":0},
 "prev":"5e9d…"}
```

| field | |
|---|---|
| `v` | the record's schema version, 2 for new execution-history records |
| `kuu`, `root`, `git` | which runtime and project; best-effort `git.head` and `git.ref` read once when opening the ledger, before task execution, from `.git` itself without `git.exe`; absent without a readable repository, `ref` alone on a branch not yet born, `head` alone when HEAD is detached. This is repository identity, not a dirty-state report |
| `kind`, `name` | `verb` (`run`), `task` (its name), or `child` (the tool's name, else the program) |
| `task`, `tool` | for a child, the task that ran it and the declaration it ran through, when it did |
| `argv`, `cwd`, `pid` | what ran, from where, as what; `cwd` only for a child whose call gave one, and an absent field is absent, never `null` |
| `at`, `seconds` | when it began, as an instant, and how long it took |
| `status`, `code`, `bytes`, `error` | how it ended: a child's `exit`, `timeout`, `killed`, `limit` or `error`, with its code when available, and the bytes on each stream when kuu relayed them (under `--json`; a child on the console has kuu's own streams and nothing is counted); a task's or the run's `ok` or `failed` with the error |
| `prev` | the SHA-256 of the record line before this one, across days |

The three kinds, as a reader would type them:

```typescript
type LedgerRecord = Common & (
  | { kind: "verb"; name: "run"; task?: string;       // the task that ran: the one named, else the default
      argv: string[];                                  // the arguments after `kuu run`, as typed
      status: "ok" | "failed"; code: number;           // kuu's exit code
      error?: LedgerError }
  | { kind: "task"; name: string;
      status: "ok" | "failed"; error?: LedgerError }
  | { kind: "child"; name: string; task: string; tool?: string;
      argv: string[]; cwd?: string; pid: number;
      status: "exit" | "timeout" | "killed" | "limit" | "error"; code?: number;
      limit?: "memory" | "cpu" | "processes";
      bytes?: { out: number; err: number } });
type Common = { v: 2; kuu: string; root: string;
  git?: { head?: string; ref?: string };
  at: number; seconds: number; prev?: string };
type LedgerError = { domain: string; code: string; message: string; exit?: number };
```

A task's `error` is what its `run` returned or raised, with the domain and
code the project chose. `exit` is optional: an in-task `CLI usage` error
without an explicit exit value leaves it absent and makes kuu exit 2.
The verb carries the same domain, code and message; its own `code` always
states kuu's exit status. A child that timed
out or hit a limit is recorded with that `status` and no `error`: the
failure is the task's, and its message names the child. `prev` is absent
only on the first record ever kept.

Each append uses the canonical project identity and a named [lock](sync.md),
so cooperating runs in the same Windows session, including nested runs and
aliases of one root, append to the same chain. The lock covers history work,
not task execution. Different logon sessions or machines do not share that
coordination guarantee. If the root cannot be canonicalized, recording fails
instead of using an unrelated lock for its spelling.

## Existing history

Readers and chain verification accept both schema versions 1 and 2. New
records use version 2 and omit `delta` and `observation`. An existing
version-1 line is never rewritten to fit the new schema: its original bytes
remain the input to the hash chain. A day file can contain both versions.
Normal ninety-day retention still applies.

Version-1 `delta` and `observation` fields are historical data only. Earlier
releases and development builds gave them different completeness guarantees;
their presence does not establish current file state or attribute an edit to
a particular process. A reader that needs only execution history can ignore
them. An existing `.kuu/ledger/tree.json` is ignored and left untouched;
there is no replacement baseline, migration scan or publication step.

0.12 writes these execution-history records. The record's `v` identifies its
schema independently of the runtime version; see
[Upgrading from 0.11](upgrading-from-0.11.md) for report and history migration.

## History costs

Execution-history work does not grow with the number of project source files.
To append a crossing, kuu finds the newest line by examining the end of the
latest nonempty day file. Recent-history lookup also searches backward for the
requested lines, preserving their original order. These lookups avoid scanning
every earlier line in Lua, but the underlying day files are still read in full;
their I/O and memory cost can grow with history size. No persisted tail cache
is trusted in place of the actual history.

`capabilities` verifies every retained record and hash link. Its
`ledger_verification` timing therefore grows with retained history.
`ledger_tail` measures recent-history retrieval separately; `run` reports
opening and appending history as `ledger`. Corruption and read failures remain
explicit. The [run report](task.md) describes those timings and the per-run
record summary.

The whole reader, and the question it most often answers — which task
failed last, and why:

```lua
global none
global <const> require, ipairs, print, table
local fs, json = require "fs", require "json"
local dir = ".kuu/ledger"
local names = {}
for _, e in ipairs((fs.list(dir) or { entries = {} }).entries) do
  if e.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = e.name end
end
table.sort(names)
local failed
for _, name in ipairs(names) do
  for line in (fs.read(fs.join(dir, name)) or ""):gmatch("[^\n]+") do
    local record = json.decode(line)
    -- the task that failed, not the run that ended on it
    if record and record.kind == "task" and record.status == "failed" then failed = record end
  end
end
if failed then print(failed.kind, failed.name, failed.error.domain, failed.error.code, failed.error.message) end
```

The chain is the point of `prev`. Nothing prevents editing a line — the file
is text, the directory is yours — but an edited line no longer hashes to
what the next record says, and `kuu capabilities` finds it: every time it
reads the ledger it walks the whole chain and says whether it is intact,
at which line it breaks, or why it could not be read completely. Records
older than ninety days are removed as new ones are written; the first record
kept then names a line that is gone, and the walk takes it as the anchor.

Only `kuu run` writes the ledger, and only once its plan is checked and a
task is about to run: `--dry-run`, an unknown task and a wrong argument
write nothing. `kuu list` and `kuu capabilities` run `manifest.lua` to read
its declarations and write no crossing records; `kuu check` runs no project
code. A child the manifest starts at its top level is not a crossing of any
run.

## Reading it

`kuu capabilities` shows the last crossings, oldest first, and in its
descriptor `project.ledger.last` carries `at`, `kind`, `name`, `status` and
`seconds` for each; `records` is how many the ledger holds after successful
verification, `intact` whether each hashes the one before it, with `broken`
naming the file and line where that fails. Invalid JSON or an object without
the record's common fields is a broken record too, and is omitted from `last`.
Both descriptor forms report the broken chain even when no recent record can
be read. An unreadable day file or incomplete directory listing sets `intact`
to false and `unreadable` to the filesystem diagnostic; the unverified
`records` count is omitted. Absence is an empty ledger, but a read failure is
never verified emptiness. `last` is empty when its required day files cannot
be read. The files are plain NDJSON: `fs.read` and `json.decode` one line at a
time is the whole reader. There is no `unaccounted` change count.

A ledger that cannot be opened or written — a read-only tree, a lock held
too long, a record holding text that is not UTF-8 — is said once on
standard error, and the run goes on: the record is the door's, never a
condition on the work. A task's error message that is not UTF-8, which a
child's output in the console code page often is, is recorded and reported
with each such byte as U+FFFD. Failures also appear in the JSON envelope's
`notes`; they preserve the task's outcome. Once ledger opening is attempted,
`result.ledger` reports how many records this run appended and whether all
its attempted records were written, with a structured `error` after an opening
or recording failure. A failed open reports `records:0`, `complete:false` and
the error. A dry run or preflight failure has no ledger summary.

If the preceding record cannot be read, the new record is refused with the
same warning and `notes` behavior. The run continues without starting a new,
unchained history behind the unreadable file.
