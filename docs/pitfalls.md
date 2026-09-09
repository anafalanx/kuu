# Pitfalls

What an agent's priors get wrong here. kuu embeds PUC Lua 5.5.1 unchanged,
compiled as C, so the Lua 5.5 reference manual holds; this page is the delta
between the Lua most agents know and this runtime, plus the Windows facts kuu
refuses to hide. Read it once.

## Lua 5.5 differences from 5.4 habits

- **`global` is a contextual keyword.** A statement beginning with `global`
  followed by a name, `none`, `*`, `function`, or an attribute is a global
  declaration. Elsewhere it is an ordinary name (kuu keeps Lua's default
  compatibility setting), so `local global = 1` still works. Avoid the name.
- **Any global declaration switches the chunk to declared-only mode**, and
  then every free name must be declared, `print` included. `global none` is
  the declaration that adds nothing and exists only to switch. kuu recommends
  starting every file with it and declaring the standard names you use:

  ```lua
  global none
  global <const> print, require, ipairs, pairs, tostring, error, pcall, type
  ```

  A misspelled name is then a load-time error instead of a silent nil. The
  common mistake is switching on strictness and forgetting `print`; the error
  says exactly that.
- **For-loop control variables are read-only.** Assigning to them is a
  compile-time error.
- **Floats print with more digits.** `0.1 + 0.2` prints as
  `0.30000000000000004`, `2^53` as `9007199254740992.0`. Use `string.format`
  for a fixed layout.
- **New in the library:** `table.create(n, m)`, two return values from
  `utf8.offset`.
- **Attributes are how resources are held:** `local f <close> = ...` closes
  the value when the block exits, including by error; `local n <const> = ...`
  refuses reassignment. Every kuu handle supports `<close>`.

## What kuu removed or changed

- **Absent by design:** `io.popen`, `os.execute`, `os.remove`, `os.rename`,
  `os.tmpname`, `dofile`, `loadfile`, `package.loadlib`, and the `debug`
  library except `traceback` and `getinfo`. Processes belong to
  [`proc`](proc.md), files to [`fs`](fs.md). `io.open` remains and takes
  UTF-8 paths.
- **`os.getenv` reads the live environment as UTF-8**; stock Lua returns the C
  runtime's startup copy in the ANSI code page.
- **No binary chunks.** `load` always uses mode `"t"`.
- **Arguments** reach the main chunk as `...` and as `require("rt").args`.
  There is no `arg` global.
- **`require`** looks in kuu's own modules first, then in the program's
  directory (`?.lua`, `?/init.lua`). Names are plain dotted names; nothing is
  read from the environment; you cannot shadow a kuu module by accident.
- **The main chunk is a coroutine run by kuu's loop.** Waits park it and
  completions resume it. `coroutine.yield()` with nothing to wait for is an
  error. Your own coroutines work; a palette wait inside one is served in
  place.
- **`os.exit(n)`** ends the process at once. Children die with it either way.

## Bytes, text, and Windows

- **Strings are bytes.** `#s` counts bytes, `s:sub` cuts bytes, `s:lower`
  folds ASCII only. Use `utf8.len` and `utf8.codes` for characters.
- **Standard streams are binary.** What you write leaves the process byte for
  byte, no CRLF translation. A terminal on another code page shows UTF-8
  wrongly; a pipe does not.
- **Child output is bytes in whatever encoding the child chose.** `cmd.exe`
  writes CRLF and the OEM code page: `text.decode(r.out, "oem")`. Do not
  assume UTF-8 from a program you did not write.
- **`cmd.exe /c` re-parses its argument.** kuu quotes arguments for programs
  that parse the normal way; cmd does not. Give `/c` one plain argument
  without embedded quotes, or write a `.cmd` file and run that.
- **Paths: forward slashes are fine everywhere in kuu**, and come back that
  way. `C:foo` (drive-relative) and components ending in `.` or a space are
  refused by name, because Windows would quietly change what they mean.
- **A junction is a name for another directory.** `fs.exists` reports
  `"link"`, `fs.stat` follows unless told not to, `fs.dirs` lists it and does
  not enter it, `fs.remove` removes the link and never its target,
  `fs.canon` and `fs.same` see through it. A link whose target is gone is
  `FS dangling`, not `notfound`.
- **An atomic write is a temp file and a rename.** A watcher sees exactly
  that, not an `added` of the final name.
- **A watch read returns the first batch.** Changes made over time arrive
  over several reads; loop until you see what you expect, and reconcile from
  a listing when `overflow` or `dropped` appears.

## Values and results

- **Expected failures are `nil, err`; mistakes raise.** A missing program, a
  file that is not there, a timed-out wait come back as `nil, err`. A bad
  option name or value, a missing argument, a duration without a unit raise.
  Branch on `err.is(e, "PROC", "notfound")`, never on message text.
- **Timeouts are results.** `proc.run` returns `status = "timeout"`; it does
  not raise. A wait that ran out returns `nil, err` with `timeout`, and the
  thing waited on is still alive.
- **Durations and sizes carry units.** `"30s"`, `"250ms"`, `"16M"`. A number
  is seconds or bytes. A bare string without a unit is refused.
- **Option names are checked.** `{ cwdd = "x" }` raises `usage` instead of
  running with the wrong settings.
- **JSON arrays are marked tables and nulls are `json.null`**, so `#` is
  reliable and `{}` stays an object. Integers round-trip exactly; do not
  pass identifiers through floats.
- **`fs.exists` returns a kind string or `false`**, so `if fs.exists(p) then`
  works and `if fs.exists(p) == "directory" then` is available.

## Limits worth knowing

- Deep recursion fails as a Lua stack overflow around two hundred thousand
  frames, far sooner for C-boundary recursion (`pcall`, metamethods) at two
  hundred levels. Write loops for large inputs.
- Programs and stdin programs are bounded at 16 MiB; `fs.read` at 1 GiB
  unless `maxbytes` says otherwise; `proc.run` output at 64 MiB per stream
  unless `maxout` says otherwise, with `truncated` set when cut.

## Errors kuu itself prints

Every message kuu produces has the shape `DOMAIN code: text`, and the codes
are listed per module page. `kuu docs search CODE` finds the page.
