# check

`kuu check` says what can be known about Lua files without running them, and
nothing more.

```text
kuu check [--json] [--fix [--adopt]] [PATH ...]
```

Without paths it checks every `.lua` file below the nearest project (the
directory holding `tasks.lua`), or below the current directory when there is
no project, skipping `.git`, `.tools`, `build`, and `node_modules`. Paths may
be files or directories; `require` names always resolve against the project
root.

Four things are checked:

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
- **Its palette names exist.** After `local files = require "fs"`, an
  access such as `files.exist(path)` is an error:
  `files.exist is not a name in fs; did you mean files.exists?`
  Aliases, multiple local declarations, and parenthesized or long-string
  require literals work. Both functions and exported data fields count.

Strings and comments contribute no requires or field accesses. The checker
opens kuu's own public modules to read their export tables; it never runs
the checked file. Dynamic indexing such as `files[name]` is left alone.

**A project's own modules are checked too, from their text.** Project code is
never executed, so the exports of `require "tools.project"` are read by
scanning the module for what it assigns to the table it returns -- the
`function M.name` and `M.name =` forms. In a consuming project this is the
larger half of the checking: Time Actual reaches through one such module 210
times.

The extraction over-approximates deliberately. A field wrongly included costs
only a missed diagnostic; one wrongly excluded is a false positive on correct
code, which is far more expensive. So when the export set cannot be bounded
the module is left unchecked entirely rather than guessed at: a computed key
(`M[name] = ...`), a metatable, a return that is not a plain local, or a local
that was not built as a table in that file.

Name checking follows direct local require bindings and lexical scopes.
Parameters, block locals, and loop variables can shadow an alias. If an
alias is reassigned anywhere, its field accesses are skipped throughout
that binding's scope, including captured uses in functions. This avoids
claiming to know a value that control flow may replace. Aliases passed
through another variable, function arguments, or a function result are not
inferred. Shadowing or reassigning `require` likewise stops treating it as
kuu's loader in that scope.

A module indexed where it is required is followed too:
`require("rt").version == "0.5"` reports exactly as it would through a local
binding, and so does `require("proc").run { cwdd = "x" }`. Such an expression
has no binding to shadow or reassign, so nothing can make it uncertain. The
module name must be a literal, as it must be everywhere else here; a computed
`require(name)` says nothing and is left alone.

Four things are checked against kuu's own interface, and all four are
mistakes that run without complaint today. A code its domain does not have,
so `err.is` answers false for every error and the handler it guards is dead:
`err.is(e, "PROC", "notfund")`. An option a call does not take:
`proc.run { cwdd = "x" }`, which the runtime raises on, but only if the line
is reached. A closed set compared with a literal outside it, such as
`rt.route == "flie"`, which likewise never matches. And `rt.version` compared
by text, which no project should do since the version grew a third component;
use `rt.version_at_least`.

Error *domains* are not checked, only the codes within a domain kuu owns.
`err.new` is public and a project names its own domains, so an unfamiliar one
says nothing about correctness.

Beyond these, no call is type-checked: argument counts, option values, and
types still belong to runtime validation.

## Fixing the declaration

`--fix` writes each file's global declaration: it adds the standard names the
chunk uses and removes the ones it does not, then checks the files again so
the report describes what is now on disk.

It knows nothing about Lua's scoping rules, because the compiler already does.
Under a global declaration the compiler names each undeclared variable in
turn, so the needed set is found by compiling and reading the complaint; and a
declared name is unnecessary exactly when removing it still compiles.

The direction that matters is removal. Forgetting to add a name is a loud
load-time error and fixes itself; forgetting to remove one when its last use
goes is silent forever, so a hand-kept list rots in one direction only.

**A name is only ever added when this runtime has a global by that name.**
`global none` exists so that a misspelling is a load-time error, and a fixer
that declared whatever the compiler complained about would answer
`print(reuslt)` by declaring `reuslt` -- turning a caught mistake into a silent
nil. Such a file is reported as not fixed, with the reason, and left alone
with its error intact.

A file with no global declaration at all is left alone unless `--adopt` is
given, since switching a chunk to declared-only mode is a larger change than
correcting a list that is already there. Nothing else in the file is touched:
a declaration that merely wraps differently is not rewritten, and the file's
line endings are written back as they were, so correcting two lines of a CRLF
file does not rewrite every line of it.

With no paths it rewrites every `.lua` file below the nearest project root,
which is the same set it checks.

```text
app.lua:
  + tostring, ipairs
  - select, math
typo.lua: not fixed: `reuslt` is not a global this runtime has; it reads like a misspelling, and declaring it would hide one
kuu: 6 files, 1 fixed, 1 errors, 0 warnings
```

```text
bad.lua:1: unexpected symbol near '='
strict.lua:2: variable 'print' is not declared
app.lua:12: "notfund" is not a code in PROC, so this never matches; did you mean "notfound"?
app.lua:19: cwdd is not an option of proc.run; did you mean cwd?
app.lua:24: rt.version is Major.Minor.Patch and is never compared by text; use rt.version_at_least(...)
lib/helper.lua: warning: no global declaration: an undeclared global is not an error here; start with `global none`
ghost.lua:3: warning: require "nothere" names no kuu module and no file under C:/work/app
kuu: 6 files, 5 errors, 2 warnings
```

Findings go to standard output, one per line, relative to the root; the
summary goes to standard error. Exit 0 when there are no errors (warnings do
not fail a check), 1 when any file has an error, 2 for a usage mistake or a
path that is not there.

`--json` prints one envelope instead. The structural schema below uses
`?` for an omitted optional field; array fields are present even when empty:

```typescript
type CheckReport = {
  ok: boolean; // true exactly when result.errors is zero
  result: {
    root: string; // absolute path
    fixed?: { path: string; added: string[]; removed: string[] }[];   // --fix only
    unfixed?: { path: string; message: string }[];                    // --fix only
    files: {
      path: string; // relative to root when under it, otherwise as reported
      errors: CheckError[];
      warnings: CheckWarning[];
      requires: string[]; // unique, sorted literal module names
    }[];
    errors: number; // total error count
    warnings: number; // total warning count
  };
};
type CheckError =
  | { kind: "read" | "syntax"; line: number; message: string }
  | { kind: "name" | "code" | "option" | "value"; line: number; message: string;
      module: string; name: string; suggestion?: string };
type CheckWarning = {
  kind: "globals" | "require"; line: number; message: string;
};
```

Each error and warning carries `line` (0 when it is about the whole file) and
`message`. The closed set of error kinds is `read` (cannot read the file),
`syntax` (Lua compilation, including undeclared globals), `name` (an unknown
palette export), `code` (an error code its domain does not have), `option`
(an option a call does not take), and `value` (a closed set compared with a
literal outside it, `rt.version` compared by text included). Warning kinds
are `globals` (no declaration) and `require` (unresolved module). For `name`,
`code`, `option` and `value`, `module` and `name` identify what was written
and `suggestion` is the nearest real spelling, omitted when none is close.

`fixed` and `unfixed` are present only with `--fix`: the declarations that
were rewritten, and the files that were left alone with the reason.

Exit 0 or 1 produces this envelope, with no summary on stderr. Invalid
command arguments or an explicitly named path that does not exist exit 2
before a report is available and print a diagnostic on stderr, even with
`--json`; `--help` prints usage and exits 0.

In a program, `require("check").file(path, root)` returns
`{path, errors, warnings, requires}` with an absolute `path` and the same
finding kinds. `check.tree(dir, root)` returns `{root, reports = {...}}`.

The extraction above is reachable on its own. `check.exports(path)` is the set
of names a module exports, read from its text, or nil when the text does not
bound them; `check.modules(root)` returns
`{root, files, modules = {{name, path, exports}, ...}}` -- every `.lua` file
below the root that a `require` name could reach and whose exports it could
bound, in name order, with `files` counting all of them.
[capabilities](capabilities.md) reports what it returns.

## Errors

The command's complete `CHECK` code set is `notfound`, for an explicitly
named path that is neither a file nor a directory. Invalid command arguments
use `CLI usage`. The checking module returns findings rather than `nil, err`;
a file-read failure is a `read` finding containing the underlying `FS`
diagnostic. Filesystem argument errors retain their original domain and code.
