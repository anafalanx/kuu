# evt

Read local Windows event logs. This module never writes or clears a log.

```lua
local evt = require "evt"
local time = require "time"
evt.logs() -- channel names, including Application and System
local events, e = evt.read("System", {
  since = time.now() - 86400,
  level = "error",
  provider = "Service Control Manager",
  limit = 200,
})
```

Every option is optional. `since` is an instant in Unix seconds, as returned
by `time.now`, between 1601 and 9999. `level` is `critical`, `error`,
`warning`, `information`, or `verbose`. Unclassified level-zero events use
`information` and are included in that filter. `provider` matches the exact
publisher name. Names are UTF-8 without NUL; a provider containing both single
and double quote characters is refused because Windows' restricted XPath
cannot express that literal. Unknown options raise `EVT badvalue`.

`limit` defaults to 1000 and must be an integer from 1 to 100000. Results are
the newest records first. An empty query returns an empty table. Each entry
has these fields:

| field | value |
|---|---|
| `time` | instant in Unix seconds |
| `level` | one of the names above |
| `id` | integer event id |
| `provider` | publisher name |
| `message` | formatted message, or the raw event XML if its publisher resources are missing |
| `record` | integer record number within that channel |
| `computer` | computer name recorded in the event |

The query filters inside Windows and reads in batches. Only the returned
records are rendered. Messages use the machine's available publisher
resources and language; old events can remain readable as XML after their
publisher is uninstalled. This is a bounded snapshot, not a subscription;
choose a small `limit` when polling repeatedly. Channel permissions apply:
reading `Security`, for example, usually requires administrator rights.

## Errors

The complete EVT code set is `notfound` (unknown channel), `access`
(insufficient channel rights), `badvalue` (raised for malformed names,
options, instants, levels, or limits), and `oserror` (other Windows failures).
