# check

`kuu check` says what can be known about Lua files without running them, and
nothing more.

```text
kuu check [--json] [PATH ...]
```

Without paths it checks every `.lua` file below the nearest project (the
directory holding `tasks.lua`), or below the current directory when there is
no project, skipping `.git`, `.tools`, `build`, and `node_modules`. Paths may
be files or directories; `require` names always resolve against the project
root.

Three things are checked, and only these:

- **It parses.** Each file goes through Lua 5.5's own compiler, text only, the
  way kuu would load it. A syntax error is reported with its line. Under a
  global declaration (`global none`, or any `global` statement), the compiler
  also refuses an undeclared global, so the classic typo is an error here.
- **It declares its globals.** A file with no `global` statement at all gets a
  warning, because in that file an undeclared global is silently nil at run
  time. [Pitfalls](pitfalls.md) says how to start a file.
- **Its requires resolve.** Every literal `require "name"` is listed. A name
  that is neither one of kuu's modules nor a file under the root
  (`name.lua` or `name/init.lua`, dots as directories) is a warning with its
  line. A program with no requires has only stock Lua's `io` and `os`, and
  this listing is how an agent sees what else a file asks for before running
  it.

Nothing is executed, and no call is type-checked: a wrong argument count to a
palette function still surfaces as a raise at run time, by design, rather
than as a half-checked promise here.

```text
bad.lua:1: unexpected symbol near '='
strict.lua:2: variable 'print' is not declared
lib/helper.lua: warning: no global declaration: an undeclared global is not an error here; start with `global none`
ghost.lua:3: warning: require "nothere" names no kuu module and no file under C:/work/app
kuu: 6 files, 2 errors, 2 warnings
```

Findings go to standard output, one per line, relative to the root; the
summary goes to standard error. Exit 0 when there are no errors (warnings do
not fail a check), 1 when any file has an error, 2 for a usage mistake or a
path that is not there.

`--json` prints one envelope instead:

```json
{"ok":false,"result":{"root":"C:/work/app","errors":2,"warnings":2,
  "files":[{"path":"good.lua","errors":[],"warnings":[],"requires":["fs","lib.helper"]}, ...]}}
```

Each error and warning carries `line` (0 when it is about the whole file) and
`message`. In a program, `require("check").file(path, root)` returns one such
report and `check.tree(dir, root)` returns them for a directory.
