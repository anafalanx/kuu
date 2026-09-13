# err

The one error shape.

```lua
local err = require("err")
local e = err.new("TASK", "failed", "the build returned 1", { exit = 1 })
tostring(e)                 -- "TASK failed: the build returned 1"
e.domain, e.code, e.message, e.exit
err.is(e)                   -- true: it is one of these
err.is(e, "TASK")           -- true
err.is(e, "TASK", "failed") -- true
```

The optional fourth argument adds fields to the error. Keep `domain`, `code`,
and `message` out of that table: extra fields replace existing fields.

kuu's classified failures use such a table, with a closed set of domains and
codes documented per module. Lua's argument-type checks can still raise a
string error, and errors from user callbacks propagate unchanged. The
convention for classified failures is:

- An expected failure returns `nil, e`: a program that is not installed, a
  child that timed out waiting, a file that is not there.
- A programming mistake raises `e`: a missing command, a duration without a
  unit, an unknown option name.

The line between the two is the function's purpose. A function whose job is
to validate or convert input — `text.decode`, `time.parse`, `csv.decode`,
`cli.duration` — returns for input that fails, because failing input is the
outcome it exists to report. A function that assumes its input is well
formed — `fs.read` given a malformed path, `re.match` given a subject that
is not UTF-8, `time.duration` given a bare number in a string — raises,
because the fix is in the code that called it, not in the data. Every
module follows this since 0.10.0; where two once disagreed on the same kind
of failure, the disagreement is named in [upgrading to 0.10](upgrading-0.10.md).

Branch on `err.is(e, "PROC", "notfound")`, never on the message text.
Messages are for people; domains and codes are for programs.
