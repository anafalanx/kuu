# log

Say what happened, where someone can read it later.

```lua
local log = require("log")
log.info("built", { target = out, bytes = size })
log.warn("queue at 90%")
log.error("cannot open", { path = p, err = e })
log.debug("retrying", { attempt = n })
```

A line is the local time with milliseconds, the level, the message, and the
fields sorted by key, quoted where a space or quote would make them ambiguous:

```text
2026-09-09T14:03:05.123 INFO  built bytes=307200 target=build/kuu.exe
```

Field values may be strings, numbers, booleans, error objects (rendered as
`DOMAIN code: message`), or tables (rendered as JSON). Each call returns true
when the line was emitted and false when it was filtered or dropped.

## Configuration

```lua
log.configure { level = "debug" }            -- debug, info, warn, error, off; default info
log.configure { file = "build/log.txt" }     -- append to a file; false returns to stderr
log.configure { json = true }                -- one JSON object per line: ts, level, msg, fields
log.configure { sink = function(line) end }  -- your own destination; false removes it
log.configure()                              -- { level, file, json, sink, dropped }
```

Levels are `debug`, `info`, `warn`, `error`, and `off`, and the default is
`info`. A record below the configured level is filtered, and its call returns
false rather than raising.

Every option is validated before any is applied, so a bad call leaves the
previous configuration intact; a file that cannot be opened raises
`LOG oserror` at configure time rather than being discovered by silently
counting drops. Writing never raises: a sink that fails increments `dropped`,
which `configure()` reports, because a diagnostic must not terminate the work
it describes. The default sink is standard error, resolved at write time, so a
program that never logs opens nothing.

| LOG code | when |
|---|---|
| `badvalue` | raised: an unknown level, or a `file` or `sink` of the wrong kind |
| `usage` | raised: an unknown option, or a non-table argument |
| `oserror` | raised: the log file cannot be opened |
