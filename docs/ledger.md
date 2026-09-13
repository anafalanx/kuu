# The ledger

The door remembers what passes through it. Every `kuu run` writes one record
per crossing — the run itself, each task, each child a task ran through
`task.exec` — to `.kuu/ledger/<day>.ndjson` under the project root, from
what kuu observed and never from what a tool reported. It is the answer to
"what ran here, against which edits, and how did it end", kept locally for
ninety days. A child a task starts with `proc.run` itself, a `task.command`
table included, is the program's own call and not a crossing.

```text
.kuu/ledger/2026-09-13.ndjson      one record per line, the day in UTC
.kuu/ledger/tree.json              the tree as the last run left it
```

Add `.kuu/` to the project's `.gitignore`, as for [mem](mem.md). The ledger
is the machine's, not the repository's; a summary a project wants to keep
is the project's to commit.

## A record

```json
{"v":1,"kuu":"0.10.0","root":"C:/work/app","git":{"ref":"refs/heads/main","head":"7c1a…"},
 "kind":"child","name":"report","tool":"report","task":"weekly","pid":4120,
 "argv":["C:/work/app/tools/report/report.exe","--out","build/r.json"],
 "at":1789300000.1,"seconds":3.2,"status":"exit","code":0,"bytes":{"out":8192,"err":0},
 "delta":{"added":0,"changed":2,"removed":0,"paths":[{"path":"src/report.lua","change":"changed","sha256":"…"}]},
 "prev":"5e9d…"}
```

| field | |
|---|---|
| `v` | the record's schema version, 1 |
| `kuu`, `root`, `git` | which runtime, which project, and where the repository stood: `git.head` and `git.ref` are read from `.git` itself, no `git.exe` assumed; absent without a repository, `ref` alone on a branch not yet born, `head` alone when HEAD is detached |
| `kind`, `name` | `verb` (`run`), `task` (its name), or `child` (the tool's name, else the program) |
| `task`, `tool` | for a child, the task that ran it and the declaration it ran through, when it did |
| `argv`, `cwd`, `pid` | what ran, from where, as what; `cwd` only for a child whose call gave one, and an absent field is absent, never `null` |
| `at`, `seconds` | when it began, as an instant, and how long it took |
| `status`, `code`, `bytes`, `error` | how it ended: a child's `exit`, `timeout`, `killed` or `limit` with its code, and the bytes on each stream when kuu relayed them (under `--json`; a child on the console has kuu's own streams and nothing is counted); a task's or the run's `ok` or `failed` with the error |
| `delta` | on the first record of a run only: what changed under the root since the previous run, by size and mtime, skipping `.git`, `.tools`, `build`, `node_modules` and `.kuu`, and not entering a junction or symlink, as [`fs.dirs`](fs.md) does not; the counts are complete, and up to forty paths are named, each with the content hash of what is there now when it can be read — a file another process holds open, or a name Windows would rewrite, is named without its `sha256`. That says which edits this run ran against. An edit with no crossing after it is work in progress, not a bypass |
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
type Common = { v: 1; kuu: string; root: string;
  git?: { head?: string; ref?: string };              // a detached HEAD has only head; a branch not yet born has only ref
  at: number; seconds: number; delta?: Delta; prev?: string };
type LedgerError = { domain: string; code: string; message: string; exit?: number };
type Delta = { added: number; changed: number; removed: number;
  paths: { path: string; change: "added" | "changed" | "removed"; sha256?: string }[] };
```

A task's `error` is what its `run` returned or raised, with the domain and
code the project chose, and `exit` set; the verb's carries the same domain,
code and message, the exit being the verb's own `code`. A child that timed
out or hit a limit is recorded with that `status` and no `error`: the
failure is the task's, and its message names the child. `delta` sits on
the first record the run writes, whichever kind that is — the first child,
else the first task — and `prev` is absent only on the first record ever
kept.

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
at which line it breaks, or why it could not be read completely. Records older than ninety days are removed as
new ones are written; the first record kept then names a line that is gone,
and the walk takes it as the anchor.

Only `kuu run` writes the ledger, and only once its plan is checked and a
task is about to run: `--dry-run`, an unknown task and a wrong argument
write nothing, so the next real run's delta still names the edits it ran
against. `kuu list` and `kuu capabilities` run `manifest.lua` to read its
declarations and write nothing; `kuu check` runs nothing at all. A child
the manifest starts at its top level is not a crossing of any run.

## Reading it

`kuu capabilities` shows the last crossings, oldest first, and in its
descriptor `project.ledger.last` carries `at`, `kind`, `name`, `status` and
`seconds` for each; `records` is how many the ledger holds after successful verification, `intact` whether
each hashes the one before it, with `broken` naming the file and line where
that fails. Invalid JSON or an object without the record's common fields
is a broken record too, and is omitted from `last`. Both descriptor forms
report the broken chain even when no recent record can be read.
An unreadable day file or incomplete directory listing sets `intact` to false
and `unreadable` to the filesystem diagnostic; the unverified `records` count
is omitted. Absence is an empty ledger, but a read failure is never verified
emptiness. `last` is empty when its required day files cannot be read.
`unaccounted` is the count of changes under the root that
no crossing accounts for — zero until something watches the root, which
nothing does yet. The files are plain NDJSON: `fs.read` and `json.decode`
one line at a time is the whole reader.

A ledger that cannot be opened or written — a read-only tree, a lock held
too long, a record holding text that is not UTF-8 — is said once on
standard error, and the run goes on: the record is the door's, never a
condition on the work. A task's error message that is not UTF-8, which a
child's output in the console code page often is, is recorded and reported
with each such byte as U+FFFD. Failed record and final-tree writes also
appear in the JSON envelope's `notes`; they preserve the task's outcome.
After a failed record, the previous tree snapshot is retained so the next
run can still account for those edits.
If the preceding record cannot be read, the new record is refused with the
same warning and `notes` behavior. The run continues without starting a new,
unchained history behind the unreadable file.
