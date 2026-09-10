# svc

Inspect and control local Windows services through the Service Control Manager.

```lua
local svc = require "svc"
svc.list()                       -- list of { name, display, state, start, pid }
svc.status("Dnscache")           -- those fields plus exe, or nil, err
svc.start("MyService", "30s")    -- true, or nil, err; waits until running
svc.stop("MyService", "30s")     -- true, or nil, err; waits until stopped
svc.restart("MyService", "30s")  -- one timeout for the stop and start together
svc.wait("MyService", "running", "10s")
```

`list` is sorted by service name. It lists Win32 services, including per-user
services, rather than kernel drivers. The `start` field is `auto`, `manual`,
`disabled`, `boot`, or `system`. The `exe` field is the configured binary
command line, including its arguments and original quoting. It is not a path
to pass unchanged to `proc.run`. A stopped service has `pid = 0`.

States are `running`, `stopped`, `start_pending`, `stop_pending`, `paused`,
`pause_pending`, and `continue_pending`. `wait` accepts any of these. A state
already held succeeds immediately, even with a zero timeout. Starting an
already running service, or stopping an already stopped one, also succeeds.
Starting a paused service does not resume it; Windows' transition rules apply.

All timeouts accept seconds or durations such as `"10s"`; the default is 30
seconds. State transitions poll every 100 milliseconds, sleeping on the loop
so other tasks keep running. A timeout bounds how long kuu watches: it does
not undo a start or stop already requested. `restart` shares one timeout across
both transitions. Services are managed by Windows and live beyond kuu's exit.

Service names are the internal names (`Dnscache`), not the display strings.
They must be nonempty UTF-8 without NUL or slash characters. Access checks are
those of the current token. A refused operation returns `nil, SVC access`
naming the service; running elevated may be necessary. `list` also needs
permission to read each listed service's configuration.

## Errors

The complete SVC code set is `notfound` (no such service), `access`
(insufficient rights), `timeout` (the target state was not observed in time),
`badvalue` (raised for malformed names, states, or timeouts), and `oserror`
(other Windows failures, including service transition failures).
