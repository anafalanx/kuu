# Upgrading to 0.10

This page records the historical 0.10.0 release. [Upgrading to 0.11](upgrading-0.11.md)
describes the current N.N version format, review corrections, and continued
support for the deprecated `tasks.lua` fallback.

0.10.0 is the release after the pre-freeze correction. It adds, and it
corrects one convention: an unknown option is refused everywhere, where
fourteen calls used to ignore it, and three calls now fall on the right side of
the raise-or-return rule. No call moved and nothing was removed. A program
that ran on 0.9.0 runs here unchanged unless it misspelt an option, or
checked `hash.file`'s second value for a malformed path; the two sections at
the end name every call.

It is the front-door release: the declaration file is `manifest.lua`, tools
are declared beside the tasks that call them, the door keeps a ledger, `kuu
run --json` is a stream, and the executable explains itself. Each has a
section below. A build that reports `0.10.0` has all of it, and the guard
advice on this page holds for it.

What it changes is what kuu tells you about code that already runs. `check`
reads an authored description of kuu's own interface and a project's own
modules, so **a project that was green on 0.9.0 can be red on 0.10.0 without a
line of it having changed**. Most findings name a call that does nothing; the
rest name one that raises only when its line is reached. None of them is new
breakage — they were there before, and nothing said so.

One thing here can break a working program rather than only turn a build red:
`kuu check --json` documents its error kinds as a closed set, and that set
grew. If anything of yours reads that report, go to
[`CheckError.kind`](#checkerrorkind-has-three-more-members) first.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, run `kuu check` and read what is new, then run
the project's tasks. **If a program of yours reads `kuu check --json`, give its
`kind` switch a default branch before you upgrade** — that is the one edit this
release makes mandatory.

`kuu check` exits 1 where it exited 0, so a CI step that runs it turns red
before any task does. It takes paths, so the upgrade need not be one commit:
narrow the step to the files that are already clean, widen it as you fix the
rest.

```text
kuu check src lib          # the part that is clean today
kuu check                  # everything below the project root
```

If the project uses anything this page introduces — a `task.tool`
declaration, `task.exec { tool = ... }`, `task.command`, `task.tools`,
`task.tool_get`, `rt.page`, `text.trim`, `rt.verbs`, `rt.pages`,
`check.exports`, `check.modules`, `kuu capabilities`, the events of the
`kuu run --json` stream, the ledger, or `kuu docs` with options — raise its
guard to `rt.version_at_least(0, 10)`; a project that uses none of them may
leave it where it is. A project that uses one of them under an older guard
fails at the call rather than at the guard, which is the failure the guard
exists to prevent.

For earlier releases, read
[upgrading to 0.9](upgrading-0.9.md), [to 0.8](upgrading-0.8.md),
[to 0.7](upgrading-0.7.md), and the [0.6 duration migration](upgrading-0.6.md).

## `tasks.lua` is `manifest.lua`

The file at a project's root that declares its prerequisites and tasks is
`manifest.lua`. It is the same file: `task "build" { ... }` reads as it did,
and the `task.tool "name" { ... }` declarations sit beside the tasks. Only
the name changes, because the file describes more than tasks now.

`kuu run`, `kuu list`, `kuu check` and `kuu capabilities` still find a
`tasks.lua` where no `manifest.lua` is, read it as the manifest, and write
one line to standard error each time saying to rename it; `capabilities
--json` reports which name it found as `project.file`. A directory holding
both is read from `manifest.lua` without a word. The announced plan was to
remove the old name in 0.11; that plan was withdrawn, and 0.11 retains the
deprecated fallback.

```text
git mv tasks.lua manifest.lua
```

## Tools are declared in the manifest

A program a task calls — built by the project or fetched by hash into its
root — is declared beside the tasks, `task.tool "name" { exe = ..., args =
..., output = ... }`, and called with `task.exec { tool = "name", ... }` or
resolved with `task.command`. [Tools](tools.md) is the page. Nothing existing
breaks: `task.exec { "gcc", ... }` runs as it did. It gains one thing, a
`tool` warning from `kuu check`, because nothing describes what it runs;
declaring the tool ends the warning and starts the checking — an argument the
declaration does not name is found without running, and `kuu capabilities`
lists the tool. `CheckWarning.kind` gains `tool` for this, so a reader of
warnings needs the same default branch a reader of errors does.

## The door keeps a ledger

`kuu run` writes one record per crossing — the run, each task, each child a
task ran through `task.exec` — to `.kuu/ledger/<day>.ndjson` under the project root, chained by
hash and kept ninety days, with the tree delta since the previous run on the
first record. Nothing asks for it and nothing depends on it: a ledger that
cannot be written is one line on standard error and the run goes on. Add
`.kuu/` to the repository's `.gitignore` if it is not there already for
`mem`. [The ledger](ledger.md) is the page.

That describes the 0.10 release. 0.12 removes automatic tree
deltas and keeps execution history; existing records remain readable. See the
[0.12 migration note](upgrading-from-0.11.md).

## `kuu run --json` is a stream

Through 0.9 `kuu run --json` printed one JSON object when the run ended.
It prints one per line as the run goes — the run once its plan is checked,
each task as it starts and finishes, each child a task runs through the door
— and the envelope it used to print is the last line, unchanged. A reader
that decoded the whole of standard output as one document breaks: take the
last line for what you had, or read each line for what you did not.
[Tasks](task.md) has the events. `--dry-run --json` and every failure
before the run are still one envelope.

## The executable explains itself

Nothing here moves a call; it is what kuu says to an agent that arrives.
[For the agent](agent.md), `kuu docs agent`, states what is expected of an
agent in a project that runs through kuu, as instructions in the order they
are met, and asks it to report back in the project's `kuu-eval.md`;
`kuu --help`, the `kuu docs` footer and both forms of `kuu capabilities`
point to it, and `capabilities` counts the entries the file holds. `kuu
docs` is a verb like the others: `--help`, `--json`, one `##` section by
heading or anchor, a search over all its words; `rt.page(name)` gives a
program a page's text. Every verb points onward at the moment it matters —
a manifest that declares no task, a misspelt verb, an unknown task, no
project, a first `.kuu/` the repository does not ignore — on standard error
and, for `--json` readers, as `notes` on the `run`, `list`, `check` and
`capabilities` envelopes; and `check` names the version guard of 0.8 where
it stands, before the manifest runs. `kuu run TASK --help`
prints the task's usage and exits 0, as every `--help` does; a `TASK
failed` error carries `status` and `limit` so a task branches on fields.

## `check` reports four mistakes it used to pass

Three of them are silent: the call returns, the branch is never taken, and
nothing says why. The fourth raises, but only when its line is reached.

```text
app.lua:6: "notfund" is not a code in PROC, so this never matches; did you mean "notfound"?
app.lua:7: "flie" is not one of rt.route's values, so this never matches; did you mean "file"?
app.lua:8: rt.version is Major.Minor.Patch and is never compared by text; use rt.version_at_least(...)
app.lua:9: cwdd is not an option of proc.run; did you mean cwd?
```

- **A code its domain does not have.** `err.is(e, "PROC", "notfund")` answers
  false for every error there will ever be, so the handler it guards is dead
  code that looks live.
- **A closed set compared with a literal outside it.** `rt.route == "flie"` is
  never true. The sets are the ones the manual states: `ProcStatus`,
  `FsKind`, `SvcState` and thirteen more.
- **`rt.version` compared by text.** Since 0.9.0 the version has three
  components, so `rt.version == "0.9"` is false against `0.9.0`. Use
  `rt.version_at_least`. This is not hypothetical: a consuming project carries
  two such branches, dead since 0.6, which survived the commit that migrated it
  to `rt.version_at_least` and a review looking for exactly them.
- **An option a call does not take.** `proc.run { cwdd = "x" }` raises
  `PROC usage`, not silently but late: an error path may not reach that line
  until production.

Error **domains** are not checked, only the codes inside a domain kuu owns.
`err.new` is public and a project names its own, so an unfamiliar domain says
nothing about correctness.

All four follow a module indexed where it is required as readily as one
reached through a local binding, so `require("rt").version == "0.5"` is
reported and so is `require("proc").run { cwdd = "x" }`. The two dead branches
above are of that shape, and upgrading is what found them. A computed
`require(name)` is still left alone.

## `check` reads a project's own modules too

`require "tools.project"` used to be checked only for resolving to a file. Its
exports are now read from the module's text, so the calls through it are
checked too:

```text
build.lua:4: p.ensure_dirs is not a name in tools.project; did you mean p.ensure_dir?
```

In a consuming project this is the larger half of the checking; one project
reaches through a single such module 210 times, and nothing verified any of
them. Project code is still never executed. The exports come from what a
module assigns to the table it returns — the `function M.name` and `M.name =`
forms.

The extraction over-approximates on purpose, because a field wrongly included
costs a missed diagnostic while one wrongly excluded is a false positive on
correct code. So a module whose export set cannot be bounded is left unchecked
entirely rather than guessed at: a computed key (`M[name] = ...`), a
metatable, a return that is not a plain local, or a local that was not built
as a table in that file.

To settle whether a `name` finding is real, ask for the same set the checker
used:

```lua
local check = require "check"
local exports = check.exports("tools/project.lua")
for name in pairs(exports or {}) do print(name) end
```

If the name you wrote is absent from that set and the module really does
export it, the extraction has a shape it cannot read, and that is a defect
worth reporting rather than working around: the workaround — making the
module's table unreadable, which any of the four shapes above does — switches
off checking of that module, so every real typo through it goes quiet too. If
`check.exports` returns nil, the module is already unchecked and the finding
came from somewhere else.

## `CheckError.kind` has three more members

This is the one change that can break a program. `kuu check --json` documents
its error kinds as a closed set, and the set grew from three to six:

```typescript
kind: "read" | "syntax" | "name" | "code" | "option" | "value"
```

`code`, `option` and `value` are new; `value` carries both the closed-set
comparison and `rt.version` compared by text. A consumer that switches on
`kind` and has no default branch now falls through on a real finding. Warning
kinds gain `tool`, for the two things [Tools](tools.md) describes; a reader
of warnings needs the same default branch.

With `--fix`, the report gains `fixed` and `unfixed` arrays. They are absent
otherwise, so nothing that does not ask for fixing sees them. See
[check](check.md) for the full schema.

## `kuu check --fix` writes the global declaration

New, and nothing changes for a project that does not run it. It adds the
standard names a chunk uses and removes the ones it does not, then checks the
files again so the report describes what is on disk.

```text
kuu check --fix [--adopt] [PATH ...]
```

**It writes files, and with no PATH it writes every `.lua` file below the
nearest project root.** Name the paths, or run it on a clean tree. It rewrites
only the declaration block: the rest of each file, its line endings included,
is left byte for byte.

Removal is the direction that matters: forgetting to add a name is a loud
load-time error that fixes itself, while forgetting to remove one when its
last use goes is silent forever, so a hand-kept list rots in one direction
only. Its first run over kuu's own tree removed 62 dead names and added none.

It knows nothing about Lua's scoping rules, because the compiler already does,
and **a name is only ever added when this runtime has a global by that name**.
A fixer that declared whatever the compiler complained about would answer
`print(reuslt)` by declaring `reuslt`, turning a caught mistake into a silent
nil; such a file is reported as not fixed, with the reason, and left alone
with its error intact. A file with no global declaration at all is untouched
unless `--adopt` is given.

## `kuu capabilities` says what is here

New, and **provisional**: it sits outside the planned 1.0 freeze until a
project has driven it, so treat its output as useful rather than promised.

```text
kuu capabilities [--json]
```

It exists because the answer was scattered across the manual, `kuu list` and a
project's own Lua, and an agent that assembles it wrongly writes code against a
module that is not there. It reports the verbs, every public module and the
names it exports, the error domains and closed sets, and the project's tasks
and its own modules. It does not report what a task installs under `.tools`,
because kuu keeps no manifest of it.

**It runs `manifest.lua`** to read the tasks, exactly as `kuu run` and `kuu list`
do. The module half is read from text and never executed, but the task half is
project code running. That matters if you point it at a checkout you do not
know. See [capabilities](capabilities.md).

## `text.trim`, and the pattern it replaces

```lua
text.trim(s)            -- without leading or trailing blanks
text.trim(s, "left")    -- or "right", or "both", the default
```

It removes the six bytes Lua's `%s` matches, from one end or both, and returns
the string itself when there is nothing to trim. A Unicode space that is not
one of the six is kept, exactly as `%s` would keep it.

It is here because the obvious spelling is a trap. `$` fixes where a match
must end, but not where the matcher starts looking: only `^` does that. So
`s:gsub("%s+$", "")` is retried from position 1, then 2, then 3, and costs a
scan of the whole string rather than a look at its end. Trimming a 15-byte
line 300,000 times measured 300 ms by that pattern and 13 ms through `trim`;
trimming a 278 KB document 200 times, 3.2 seconds against 26 ms.

Worth grepping your own code for `$")` — the shape is a trap wherever it
appears, not only in a trim. `s:find("%.lua$")` is a scan where
`s:sub(-4) == ".lua"` is a comparison. The result is the same either way; only
the cost differs. [Pitfalls](pitfalls.md) carries the entry.

Inside kuu the same fix took `csv.encode` from 303 ms to 183 on 50,000 rows
and `ini.decode` from 171 ms to 88 on 20,000 keys, with the quoting and
trimming decisions unchanged. `ini.decode` reached 69 once it called `trim`
itself; `csv.encode` still uses its own byte test.

## `rt.verbs` and `rt.pages`

`rt.verbs()` is the verbs kuu carries as programs, sorted; `docs` and
`version` are answered in C before that dispatch and are not in it, so
`kuu --help` remains the complete usage. `rt.pages()` is the manual's page
names, sorted, as `kuu docs PAGE` takes them, without the `.md`.

Also in a program: `check.exports(path)` is the set of names a module exports
(`set[name] == true`), **or nil** when its text does not bound them — the case
the extraction bails on, so test for nil before indexing. `check.modules(root)`
returns `{ root, files, modules }`, where `files` counts every `.lua` file
below the root and `modules` lists only those whose exports were bounded, each
as `{ name, path, exports }` with `exports` a sorted array.

## What `check`'s require listing is not evidence of

Not a change, but newly written down, and it bears on a tool this release
makes more useful. `check` says its require listing is how an agent sees what
a file asks for before running it. For one shape of file it is not.

`_ENV` is an upvalue rather than a global, so it is in scope always and needs
no declaration. Under `global none` with nothing declared, `_ENV.require
"proc"` reaches the whole palette, and `kuu check --json` reports that file
with `"requires":[]`, no errors and no warnings.

The `require` gate holds for a program that does not reach around it. If you
are reading a file's requires as evidence about an unfamiliar program, treat a
`_ENV` reference as disqualifying. See
[observed shortcomings](shortcomings.md).

## An unknown option is refused everywhere

Fourteen calls accepted an option they did not know and went on as if it had
not been given: `fs.dirs`, `fs.glob`, `hash.sum`, `hash.file`,
`text.tobase64`, `time.iso`, `time.make`, `json.encode`, `archive.list` (with
`pack` and `unpack`), `ini.encode`, `csv.encode`, `csv.decode`, `proc.find`,
and `proc.detach` given a `maxout` it never honoured. A misspelt `prune`
walked the whole tree; a misspelt `pretty` printed compact JSON; a misspelt
`month` made January. Each now raises `usage` in its own domain, naming the
key, as `fs.read` and `proc.run` always did. Six more refused the key but
called it `badvalue`: `evt.read`, `sys.signature`, `task.defaults`, the
`limits` table of a `proc` command, `pty.spawn`, and an attribute a `cli`
spec entry or a task declaration cannot hold. Those raise `usage` now, and
`badvalue` keeps its one meaning, a known option with a wrong value.

A program that never misspelt an option sees nothing. One that did has been
running with that option silently dropped, and now stops at the line; the
message names the key.

## The raise-or-return rule, applied

[err](err.md) now states where the line falls: a function whose job is to
validate or convert input returns for input that fails; one that assumes its
input is well formed raises. A sweep of every module against that line found
these on the wrong side of it.

- `hash.file` returned `nil, err` for a path `fs` refuses — drive-relative,
  a device, a trailing dot or space, not UTF-8 — where `fs.read` of the same
  path raises. It raises now, `HASH badvalue` or `HASH encoding`, in the same
  words. A caller that tested the second value for a malformed path must
  wrap the call in `pcall`; a caller that passed well-formed paths sees
  nothing.
- `cli.duration` and `cli.size` returned a bare `nil` for text they could not
  parse. They return `nil, err` with `CLI badvalue` now, so the reason can be
  shown. Nothing that tested the first value changes.
- `fs` took a path holding a NUL byte and used the part before it —
  `fs.exists("a.bin\0zzz")` said the file was there — where `hash` and `sys`
  refused. Every path, name, prefix and encoding `fs` takes raises
  `FS badvalue` for a NUL now.
- `proc.run`, `proc.start` and `proc.detach` returned `nil, err` for a
  command, path or environment entry that is not UTF-8, where every other
  module raises for the same mistake; they raise `PROC encoding` now. An
  environment naming one variable twice (`a` and `A`) is refused as
  `PROC badvalue` before the launch, and a `cwd` spelled in a way Windows
  would silently rewrite — drive-relative, a trailing dot or space — is
  refused as `fs` refuses it. A program not on `PATH`, a working directory
  that is not there, and Windows refusing the launch are still returned.
- `proc.alive` answered `false` and `proc.kill` returned `nil, err` for a pid
  outside the range, where `proc.find` and `proc.tree` raise; all four raise
  `PROC badvalue` now, and 0 is a pid to all four.
- `sys.signature` raised for a directory where `fs` and `hash` return for the
  wrong kind of object; it returns `nil, SYS badvalue`. `fs.read` of a
  directory was `FS access` in Windows' words; it is `nil, FS badvalue`
  saying what it is.
- `http.get` with a `to` whose directory is not there raised `HTTP oserror`,
  with the literal word `to` where the path belonged; it returns
  `nil, HTTP notfound`, or `access`, naming the path, as `fs.write` does.
- Out of memory raises everywhere; `sys`, `evt`, `svc` and `archive`
  returned it from some calls and raised from others.

`re` and `text` stay as they were: a subject that is not UTF-8 raises in
`re`, which assumes text, and returns from `text.decode`, which exists to say
whether bytes are text. The rule explains both.
