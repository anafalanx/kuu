# sync

One at a time, across processes: a named lock that two kuu processes on one
machine, or two tasks in one, take turns on.

```lua
local sync = require("sync")
local lock <close> = assert(sync.lock("deploy", "10s"))   -- waits up to 10 s; released when the block ends
lock:release()                                            -- or explicitly; idempotent

local now, e = sync.try("deploy")                         -- acquire now or nil, SYNC busy
if now and now.abandoned then log.warn("the previous holder died mid-way") end
```

The lock is a named Windows mutex in the `Local` namespace, so it costs
nothing on disk and there is no stale lock file to break: when a holder dies
without releasing, the kernel hands the lock to the next taker and marks it
`abandoned`, which is the moment to check whatever the dead holder was doing.
kuu keeps one handle per name open for as long as the process lives, because
a mutex whose last handle closes is simply gone and the next taker would get
a fresh one that was never abandoned; a process that has tried a name once
therefore always learns of a death. A kuu that exits normally releases its
locks as its state closes, so only a killed holder abandons.
`lock` waits on the loop, so other tasks keep running while it waits, and
gives up with `SYNC busy` after the timeout, 30 seconds by default. A lock
is released by `release`, by the end of a `<close>` block, or when it is
collected; kuu's own bookkeeping holds it weakly, so dropping the last
reference is enough, though only `release` and `<close>` are prompt. It is
exclusive within one kuu as well: a second `try` from the
same process is `busy`, although Windows would have let the same thread in
again. Names are 1 to 200 bytes without backslashes or control characters,
and are the same across every kuu on the machine.

`mem` holds one of these while it reads, merges, and writes its file.

| SYNC code | when |
|---|---|
| `busy` | `nil, err`: held elsewhere (`try`), or still held after the timeout (`lock`) |
| `badvalue` | raised: a bad name or timeout |
| `oserror`, `encoding` | raised: the mutex could not be opened, or the name is not UTF-8 |
