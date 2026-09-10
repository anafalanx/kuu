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

Branch on `err.is(e, "PROC", "notfound")`, never on the message text.
Messages are for people; domains and codes are for programs.
