# For the agent

What is expected of you in a project that runs through kuu. Everything on
this page is stated elsewhere in the manual as a fact about kuu; here it is
stated once, as an instruction, in the order you meet it. Read it first,
before [Pitfalls](pitfalls.md).

## Arriving

First establish that the project's copy matches its reviewed runtime pin,
using the [adoption verification procedure](adopting.md#verify-before-first-execution)
before executing a newly downloaded or checked-out binary. The project may
download and ignore its runtime or commit the signed binary; both are supported.
Keep that choice and its approved version, hash and signing identity. Change
them only as part of an owner-authorized runtime upgrade.

If this project previously used signed 0.11, read
`kuu docs upgrading-from-0.11` before running project code with a replacement.
It explains the changes to execution history, inspection, reports and project
instructions; old advice in `AGENTS.md` or README files can describe behavior
this executable no longer has. Follow its ordered upgrade checklist while
keeping the project's own task and approval policies.

Read the project's existing `kuu-eval.md` for earlier experience and unresolved
difficulties. Recheck relevant reports as you work and [report back](#reporting-back)
with new evidence, including when an upgrade changes an earlier result.

Run `kuu capabilities` to discover the runtime and the project's tasks and tools
once its manifest is ready to execute. Like `kuu list`, this loads the manifest
to learn its declarations. `kuu check` without `--fix` is read-only static
inspection. The manual is inside the executable; reading it needs no network,
source checkout or manifest execution. With the verified project copy in the
current directory:

```powershell
.\kuu.exe docs                         # list pages and their descriptions
.\kuu.exe docs fs                      # read a module's page
.\kuu.exe docs search fs.read          # find an API and a command to read its context
.\kuu.exe docs fs reading-and-writing  # retrieve only the relevant section
.\kuu.exe docs fs errors               # look up the module's error codes
```

Sections are named by their heading or anchor, so copy the `Read:` command
from a search result. `kuu docs --json` also works for lists, pages, sections,
and searches. Read `kuu docs pitfalls` once for the Lua and Windows differences;
`kuu docs index` is the full map. When an error surprises you, search for its
code or read the module's `errors` section.

## Try an inline command

Use `kuu -e` for immediate queries and small operations. Every kuu module is
available, with no script file or manifest required. Print the answer explicitly;
use `json.encode` for structured results. These examples run from PowerShell:

```powershell
.\kuu.exe -e "print(require('json').encode(require('sys').info()))"
.\kuu.exe -e "print(require('json').encode(assert(require('fs').list('.'))))"
.\kuu.exe -e "print(assert(require('hash').file('sha256', ...)))" README.md
```

The first describes the machine, the second lists the current directory as
JSON, and the third hashes a file; replace `README.md` with the path you need.
Arguments after the script arrive as `...` and `require('rt').args`, which
keeps paths out of the Lua source. `assert` makes a failed operation visible
as an error and a nonzero exit. A returned value alone is not printed.

For a longer experiment, use `kuu FILE` or send Lua on standard input to
`kuu -`. Turn repeated project operations into tasks in `manifest.lua`.
Inline commands and scripts do not write the task ledger; set timeouts on
any children or network operations they start.

## Running

- **Everything that runs in the project runs through `kuu.exe`.** A
  crossing is a task run by `kuu run`, and each child that task starts
  with `task.exec`; each crossing gets a record in [the ledger](ledger.md),
  and each child gets a job, the limits and the timeout it was given. `kuu FILE` and `kuu -e`
  are for trying something once: what they start is in a job with
  whatever `timeout` and `limits` the call gives, and nothing is recorded.
  Anything that will run again is a task in `manifest.lua`.
- **Declare every program a task runs as a tool**, `task.tool "name" { exe
  = ... }`, and call it with `task.exec { tool = "name", ... }`. `check`
  then holds every call written with the literal `tool = "name"` to the
  declaration — a name computed at run time is not judged, so write it in
  the call — and `capabilities` lists the tool. A bare `task.exec {
  "prog.exe" }` is a warning from `check` for that reason. A project
  program started from a shell without `kuu.exe` bypasses that history.
  When a task must capture and inspect output, use `task.command` to resolve
  its declared tool, then `proc.run`. This is supported, but the captured
  child has no individual ledger record or child event; the enclosing task
  and run remain recorded. Prefer `task.exec` when capture is unnecessary,
  including when a tool documents successful nonzero exits. The
  [process recipes](process-recipes.md) show both paths and their diagnostics.
- **Bound what you run.** `task.defaults { timeout = "10m" }` in the
  manifest gives every child a timeout it does not set itself; without
  it, and without a `timeout` on the call or the declaration, a child has
  no time bound at all. `sched.deadline` bounds a sequence of waits in
  your own code. [Tasks](task.md), [sched](sched.md).
- **Run `kuu check` after every edit and before every `kuu run`.** It
  reads without running: syntax, global declarations, requires, palette
  names, option names, error codes, closed sets and version comparisons,
  tool declarations and their calls. Errors fail it and warnings do not;
  a warning is still something to read. [check](check.md).
- **If something cannot be done from here, build a tool for it**, in
  whatever technology you write best — fetched by URL and hash into the
  project's own `.tools/`, or built from the project's own source — and
  either way declared with `task.tool` and called through the door. kuu is
  never extended; a project is.

## Writing

- **Start every file with `global none`** and declare the standard names
  you use. A misspelled name is then a load-time error, and `check` sees
  it before anything runs.
- **Follow the two laws kuu's own functions follow.** An expected outcome
  is returned as `nil, err`; a caller's mistake is raised; and an option
  name your function does not take is a raised `usage`, never ignored.
  Mint your errors with `err.new("DOMAIN", "code", message)` in an
  uppercase domain of your own — the codes are yours, and `check` does not
  judge them — and return `nil, err` from a task for an expected failure,
  so `kuu run --json` and the ledger carry your domain and code. Branch on
  `err.is`, never on the message. [err](err.md).
- **Fetch nothing the manifest does not list by URL and hash**, and
  install nothing on the machine: nothing goes on `PATH`, and nothing is
  shared between repositories. [Adopting](adopting.md).
- **`.kuu/` is kuu's** — the notebook and the ledger. It sits in
  `.gitignore` beside `.tools/` and `build/`, and nothing in it is yours to
  edit. Ignore `kuu.exe` only when the project downloads its pinned runtime;
  a project may instead commit that signed binary.

## Reporting back

kuu is built for you, and the only way it improves is being told where it
helped and where it stood in the way. When you have worked in a project
through kuu, append an entry to `kuu-eval.md` at the project root — a
UTF-8 file the project commits, since `.kuu/` never travels and kuu sends
nothing — and never rewrite an earlier entry. Create the file if it is missing.
Keep it with the project's maintained source and include its updates in the
project's normal review and commit workflow. One entry per piece of work:

```markdown
## 2026-09-13 — kuu 0.11 — adding the release task

### Worked
- `kuu check` named the misspelt option and the fix before anything ran.

### Difficult
- `kuu run release` printed `kuu: release failed after 1.0s` and then
  `kuu: TASK failed: C:/work/app/.tools/sdk/signtool.exe: timeout`; nothing
  said which timeout, and I found `task.defaults` in kuu docs task.

### Should change
- The timeout message should name the bound and where it was set.
```

Maintain this history across runtime upgrades. Record the version actually
tested; for a development build sharing a released version string, include its
build or SHA-256 in the entry. When revisiting a difficulty, reproduce it where
practical and append a follow-up referring to the earlier entry's date and issue.
Say whether it still occurs, is resolved by the tested change, has a workaround,
or remains unverified; release notes alone do not establish a fix in this project.
Preserve the original report and its evidence; append corrections as follow-ups.
Summarize relevant results from disposable validation copies in the project's
root document, including a failed or deferred upgrade. Identify the test copy,
project revision and Windows version when they affect the conclusion; distinguish
candidate testing from actual adoption. Continue reporting after subsequent work
with kuu. Record observed results and useful requests, without inventing problems
to fill the example's sections.

The heading is `## YYYY-MM-DD — kuu VERSION — what the work was`, on one
line: `## `, the date in that form first, then the rest; a hyphen does as
well as the dash. That is the line `kuu capabilities` counts, and a
heading shaped any other way is not an entry. A difficulty carries the
exact command and its output, so it can be reproduced; without that it is
an opinion, and belongs under *Should change*. An entry may name the
ledger record it is about, by its day file and its `at`. Keep entries
short: kuu counts them, and people read them where the project keeps
them. Run `kuu capabilities` when you have written; its `eval` line shows
the count and the date of the last entry, and nothing fails without it. That count
confirms entry discovery; it does not validate evidence or determine issue status.

## The short form

Verify a newly obtained runtime against the project's reviewed pins before
executing it. Coming from signed 0.11, read `kuu docs upgrading-from-0.11`
before running project code with a replacement. Read `agent` for the current
workflow, then use `kuu capabilities` to discover the project; it executes the
manifest. Read pitfalls once. Everything that runs,
runs through the door as a task with declared tools; try things with `kuu -e`
or `kuu FILE`, keep them as tasks. Find APIs with `kuu docs search`, then copy
the command to read their section. Bound every child. `global none` at the top of
every file. `check` after every edit and before every run. Return `nil,
err` for what is expected, raise for a mistake. Nothing on `PATH`, nothing
fetched without a hash, nothing of yours in `.kuu/`. Write `kuu-eval.md`
before you leave.
