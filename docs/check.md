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
the checked file or loads a project module. A project module's fields and
dynamic indexing such as `files[name]` are left alone.

Name checking follows direct local require bindings and lexical scopes.
Parameters, block locals, and loop variables can shadow an alias. If an
alias is reassigned anywhere, its field accesses are skipped throughout
that binding's scope, including captured uses in functions. This avoids
claiming to know a value that control flow may replace. Aliases passed
through another variable, function arguments, or a function result are not
inferred. Shadowing or reassigning `require` likewise stops treating it as
kuu's loader in that scope. No call is type-checked: argument counts,
option tables, and types still belong to runtime validation.

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

`--json` prints one envelope instead. The structural schema below uses
`?` for an omitted optional field; array fields are present even when empty:

```typescript
type CheckReport = {
  ok: boolean; // true exactly when result.errors is zero
  result: {
    root: string; // absolute path
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
  | { kind: "name"; line: number; message: string;
      module: string; name: string; suggestion?: string };
type CheckWarning = {
  kind: "globals" | "require"; line: number; message: string;
};
```

Each error and warning carries `line` (0 when it is about the whole file) and
`message`. The closed set of error kinds is `read` (cannot read the file),
`syntax` (Lua compilation, including undeclared globals), and `name`
(an unknown palette export). Warning kinds are `globals` (no declaration)
and `require` (unresolved module). A name error's `suggestion` is an export
name without the alias prefix and is omitted when no close name exists.

Exit 0 or 1 produces this envelope, with no summary on stderr. Invalid
command arguments or an explicitly named path that does not exist exit 2
before a report is available and print a diagnostic on stderr, even with
`--json`; `--help` prints usage and exits 0.

In a program, `require("check").file(path, root)` returns
`{path, errors, warnings, requires}` with an absolute `path` and the same
finding kinds. `check.tree(dir, root)` returns `{root, reports = {...}}`.

## Errors

The command's complete `CHECK` code set is `notfound`, for an explicitly
named path that is neither a file nor a directory. Invalid command arguments
use `CLI usage`. The checking module returns findings rather than `nil, err`;
a file-read failure is a `read` finding containing the underlying `FS`
diagnostic. Filesystem argument errors retain their original domain and code.
