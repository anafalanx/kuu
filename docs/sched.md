# sched

Tasks and time. The scheduler is the loop that runs every program: one thread,
one Lua state, coroutines that switch only where a palette call waits.

```lua
local sched = require("sched")
```

## Tasks

```lua
local t = sched.spawn(function(a, b) return proc.run { a, b } end, "git", "status")
local r = t:join()           -- the function's results
t:status()                   -- "running", "done", or "failed"
```

`spawn` starts the function as a task and returns at once. Tasks are
coroutines, not threads: exactly one runs at any moment, and a task gives way
only when it waits on something, so plain Lua code never needs locks. A task
keeps running when its handle is dropped; its results wait until joined.

`join` returns what the function returned. If the function raised an error,
`join` raises that same error in the joiner, so a failing task is noticed
where its result was wanted. With a duration, `t:join("30s")` returns
`nil, err` with `SCHED timeout` when the task is still running, and the task
carries on; join again later.

The program ends when its main chunk returns, whatever tasks are still
running; join what you spawn.

## Sleep and time

```lua
sched.sleep("250ms")   -- park this task; other tasks run
sched.sleep(0)         -- give other tasks a turn
sched.clock()          -- monotonic seconds, for measuring
```

Durations everywhere in kuu are a number of seconds or a string with a unit:
`"250ms"`, `"30s"`, `"1.5m"`, `"2h"`. A string without a unit is refused.

## Where waiting is not possible

A palette call parks the running coroutine by yielding. Inside a metamethod,
a `string.gsub` callback, a `table.sort` comparator, or a coroutine the program
created itself, Lua cannot yield to kuu. In those places kuu drives the loop in
place until the wait is over, so the call still returns the right thing, and
other tasks still make progress meanwhile.

## Errors

| SCHED code | when |
|---|---|
| `timeout` | `join` with a duration outlasted the task |
| `badvalue` | raised: a duration that is not one |
| `yield` | a coroutine yielded to kuu with nothing to wait for; the task (or the program) fails |
| `deadlock` | every task is parked and nothing can wake any of them; the program exits 1 |
