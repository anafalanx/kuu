# For the agent

What is expected of you in a project that runs through kuu. Everything on
this page is stated elsewhere in the manual as a fact about kuu; here it is
stated once, as an instruction, in the order you meet it. Read it first,
before [Pitfalls](pitfalls.md).

## Arriving

Run `kuu capabilities` to discover the runtime and the project's tasks and
tools. The manual is inside the executable; no network or source checkout
is needed. With the project's copy in the current directory:

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
  with `task.exec`; each gets a job, the limits and the timeout it was
  given, and a record in [the ledger](ledger.md). `kuu FILE` and `kuu -e`
  are for trying something once: what they start is in a job with
  whatever `timeout` and `limits` the call gives, and nothing is recorded.
  Anything that will run again is a task in `manifest.lua`.
- **Declare every program a task runs as a tool**, `task.tool "name" { exe
  = ... }`, and call it with `task.exec { tool = "name", ... }`. `check`
  then holds every call written with the literal `tool = "name"` to the
  declaration — a name computed at run time is not judged, so write it in
  the call — and `capabilities` lists the tool. A bare `task.exec {
  "prog.exe" }` is a warning from `check` for that reason. A project
  program started from a shell without `kuu.exe`, or with `proc.run` where
  `task.exec { tool = ... }` was possible, is a bypass: it runs, and the
  door does not see it. [Tools](tools.md).
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
  `.gitignore` beside `kuu.exe`, `.tools/` and `build/`, and nothing in it
  is yours to edit.

## Reporting back

kuu is built for you, and the only way it improves is being told where it
helped and where it stood in the way. When you have worked in a project
through kuu, append an entry to `kuu-eval.md` at the project root — a
UTF-8 file the project commits, since `.kuu/` never travels and kuu sends
nothing — and never rewrite an earlier entry. One entry per piece of work:

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

The heading is `## YYYY-MM-DD — kuu VERSION — what the work was`, on one
line: `## `, the date in that form first, then the rest; a hyphen does as
well as the dash. That is the line `kuu capabilities` counts, and a
heading shaped any other way is not an entry. A difficulty carries the
exact command and its output, so it can be reproduced; without that it is
an opinion, and belongs under *Should change*. An entry may name the
ledger record it is about, by its day file and its `at`. Keep entries
short: kuu counts them, and people read them where the project keeps
them. Run `kuu capabilities` when you have written; its `eval` line shows
the count and the date of the last entry, and nothing fails without it.

## The short form

Run `kuu capabilities` first. Read pitfalls once. Everything that runs,
runs through the door as a task with declared tools; try things with `kuu -e`
or `kuu FILE`, keep them as tasks. Find APIs with `kuu docs search`, then copy
the command to read their section. Bound every child. `global none` at the top of
every file. `check` after every edit and before every run. Return `nil,
err` for what is expected, raise for a mistake. Nothing on `PATH`, nothing
fetched without a hash, nothing of yours in `.kuu/`. Write `kuu-eval.md`
before you leave.
