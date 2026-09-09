# Lua in kuu

kuu embeds PUC Lua 5.5.1 unchanged, compiled as C. Everything in the Lua 5.5
reference manual holds, with the additions and removals on this page. Most
agents carry Lua 5.4 habits; the first section is what 5.5 changed, the second
is what kuu changed.

## What Lua 5.5 changed

- **`global` is a contextual keyword.** A statement that begins with `global`
  followed by a name, `none`, `*`, `function`, or an attribute is a global
  declaration. Anywhere else the word is an ordinary name, because kuu builds
  Lua with its default `LUA_COMPAT_GLOBAL`; `local global = 1` still works.
  Avoid the name anyway: a future Lua may reserve it outright.
- **Global declarations.** A chunk may declare its globals: `global x, y` or
  `global <const> print, require`. Any global declaration other than
  `global *` switches the chunk to declared-only: from then on every free
  name must be declared `local` or `global`, including `print`, and a
  misspelled name is a compile-time error instead of a silent nil. `global
  none` is the declaration that adds no names and exists only to switch. kuu
  recommends `global none` at the top of every program and module.
- **For-loop control variables are read-only.** Assigning to the loop variable
  inside a numeric or generic `for` is a compile-time error.
- **Float printing.** Floats print with the shortest representation that
  reads back exactly, so more digits than 5.4 showed: `0.1 + 0.2` prints as
  `0.30000000000000004`, `2^53` as `9007199254740992.0`, `1e15` as `1e+15`.
  Use `string.format` for a fixed layout.
- **New standard functions.** `table.create(n, m)` preallocates a table;
  `utf8.offset` returns two values; `math.tointeger` and `string.pack` exist as
  in 5.4.
- **Attributes exist since 5.4** and are the way to hold resources: `local f
  <close> = ...` closes the value when the block exits, including by error;
  `local n <const> = ...` refuses reassignment.

## What kuu changed

- **Absent by design:** `io.popen`, `os.execute`, `os.remove`, `os.rename`,
  `os.tmpname`, `dofile`, `loadfile`, `package.loadlib`, and the whole `debug`
  library. Processes and files belong to the palette (the next milestones),
  which gives them UTF-8 paths, decided lifetimes, and timeouts. Until the
  palette exists, `io.open` remains for reading and writing files.
- **No binary chunks.** `load` always uses mode `"t"`, whatever mode is asked
  for; `string.dump` still works but its output cannot be loaded.
- **Arguments** reach the main chunk as `...` and as `require("rt").args`.
  There is no `arg` global.
- **`require`** looks in `package.preload`, then in the program's directory
  (`?.lua`, `?/init.lua`). Names must be plain dotted names: no separators,
  drive letters, or `..`. Nothing is read from the environment.
- **The main chunk is a coroutine.** `coroutine.isyieldable()` is true at top
  level. In 0.1.0 nothing waits, so a yield that reaches the host is an error
  (`SCHED yield`); from the scheduler milestone on, waiting palette calls yield
  here and completions resume the program.
- **Bytes in, bytes out.** Strings are bytes. Standard streams are binary; no
  CRLF translation, no re-encoding, no console code page games. UTF-8 is the
  convention everywhere kuu itself produces or consumes text.
- **`os.exit(n)`** ends the process at once with code `n`. Pending
  `<close>` variables are not closed on that path unless you pass `true` as
  the second argument; the scheduler milestone will replace it with `rt.exit`,
  which unwinds first.
- **Warnings.** `warn("@on")` enables `warn(...)` output on standard error,
  as in stock Lua.

## Habits worth keeping

- Start every file with `global none` and declare the standard names you use:
  `global <const> print, require, pairs, ipairs, error, pcall, tostring`.
- Return `nil, err` for expected failures and `error(...)` for programming
  mistakes; kuu's own modules follow this rule and its error objects render
  through `__tostring`.
- Hold every resource in a `<close>` variable.
