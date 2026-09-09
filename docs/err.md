# err

The one error shape.

```lua
local err = require("err")
local e = err.new("TASK", "failed", "the build returned 1", { code = 1 })
tostring(e)                 -- "TASK failed: the build returned 1"
e.domain, e.code, e.message, e.code
err.is(e)                   -- true: it is one of these
err.is(e, "TASK")           -- true
err.is(e, "TASK", "failed") -- true
```

Every failure kuu reports to a program is such a table, with a closed set of
domains and codes documented per module. The convention, which kuu's own
modules follow and yours should too:

- An expected failure returns `nil, e`: a program that is not installed, a
  child that timed out waiting, a file that is not there.
- A programming mistake raises `e`: a missing command, a duration without a
  unit, an unknown option name.

Branch on `err.is(e, "PROC", "notfound")`, never on the message text.
Messages are for people; domains and codes are for programs.
