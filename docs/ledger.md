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
| `kuu`, `root`, `git` | which runtime, which project, and where the repository stood: `git.head` and `git.ref` are read from `.git` itself, no `git.exe` assumed; absent without a repository |
| `kind`, `name` | `verb` (`run`), `task` (its name), or `child` (the tool's name, else the program) |
| `task`, `tool` | for a child, the task that ran it and the declaration it ran through, when it did |
| `argv`, `cwd`, `pid` | what ran, from where, as what; `cwd` only for a child whose call gave one, and an absent field is absent, never `null` |
| `at`, `seconds` | when it began, as an instant, and how long it took |
| `status`, `code`, `bytes`, `error` | how it ended: a child's `exit`, `timeout`, `killed` or `limit` with its code, and the bytes on each stream when kuu relayed them (under `--json`; a child on the console has kuu's own streams and nothing is counted); a task's or the run's `ok` or `failed` with the error |
| `delta` | on the first record of a run only: what changed under the root since the previous run, by size and mtime, skipping `.git`, `.tools`, `build`, `node_modules` and `.kuu`, and not entering a junction or symlink, as [`fs.dirs`](fs.md) does not; the counts are complete, and up to forty paths are named, each with the content hash of what is there now when it can be read — a file another process holds open, or a name Windows would rewrite, is named without its `sha256`. That says which edits this run ran against. An edit with no crossing after it is work in progress, not a bypass |
| `prev` | the SHA-256 of the record line before this one, across days |

The chain is the point of `prev`. Nothing prevents editing a line — the file
is text, the directory is yours — but an edited line no longer hashes to
what the next record says, and `kuu capabilities` finds it: every time it
reads the ledger it walks the whole chain and says whether it is intact,
or at which line it breaks. Records older than ninety days are removed as
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
`seconds` for each; `records` is how many the ledger holds, `intact` whether
each hashes the one before it, with `broken` naming the file and line where
that fails; and `unaccounted` is the count of changes under the root that
no crossing accounts for — zero until something watches the root, which
nothing does yet. The files are plain NDJSON: `fs.read` and `json.decode`
one line at a time is the whole reader.

A ledger that cannot be opened or written — a read-only tree, a lock held
too long, a record holding text that is not UTF-8 — is said once on
standard error, and the run goes on: the record is the door's, never a
condition on the work. A task's error message that is not UTF-8, which a
child's output in the console code page often is, is recorded and reported
with each such byte as U+FFFD.
