# Upgrading to 0.10

0.10.0 is the release after the pre-freeze correction, and it adds rather than
corrects: no call moved, no result changed shape, and nothing was removed. A
program that ran on 0.9.0 runs here unchanged.

It is not yet released. It is held until the front-door work recorded in the
[roadmap](roadmap.md) has landed — the declaration file becomes
`manifest.lua`, tools are declared beside tasks, and the door keeps a ledger
— and this page will grow to describe that. What follows is what has landed
so far.

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

If the project calls `text.trim`, `rt.verbs`, `rt.pages`, `check.exports`,
`check.modules`, or `kuu capabilities`, raise its guard to
`rt.version_at_least(0, 10)`; otherwise leave it where it is. A project that
uses one of them under an older guard fails at the call rather than at the
guard, which is the failure the guard exists to prevent.

For earlier releases, read
[upgrading to 0.9](upgrading-0.9.md), [to 0.8](upgrading-0.8.md),
[to 0.7](upgrading-0.7.md), and the [0.6 duration migration](upgrading-0.6.md).

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
kinds are unchanged: `globals` and `require`.

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

**It runs `tasks.lua`** to read the tasks, exactly as `kuu run` and `kuu list`
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
