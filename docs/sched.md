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
sched.now()            -- wall-clock Unix seconds; time.now() uses the same Windows clock
```

Durations everywhere in kuu are a number of seconds or a string with a unit:
`"250ms"`, `"30s"`, `"1.5m"`, `"2h"`. A string without a unit is refused.

## Deadlines

```lua
local value, e = sched.deadline("30s", function(a)
  sched.sleep("10ms")
  return a
end, 42)
```

`deadline(duration, fn, ...)` returns the function's results unchanged. If
the deadline expires while that coroutine waits on the loop, it unwinds
the function and returns `nil, SCHED deadline`. Other errors pass through.
Nested scopes use the earliest deadline; an outer deadline crosses inner
scopes until it reaches the scope that owns it. A call's shorter timeout
still produces that call's normal timeout result.

This is a bound on waits, not a CPU interrupt. A function that computes
without waiting cannot be interrupted; a completed operation returns at
once. Spawned tasks have their own coroutine and do not inherit the scope.
Children are not killed by a deadline: keep a `proc.start` handle in a
`<close>` variable when the child's lifetime should end with the scope.
`proc.run` retains its internal handle until the child finishes even if
the wait is interrupted; give it its own `timeout` when it needs a firm
wall-clock lifetime. Program exit still closes every supervised job.
HTTP and network operations cancel their outstanding work when abandoned.

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
| `deadline` | an enclosing deadline expired while its function waited |
| `badvalue` | raised: an invalid duration, or a non-function deadline callback |
| `yield` | a coroutine yielded to kuu with nothing to wait for; the task (or the program) fails |
| `deadlock` | a wait has no possible wakeup; raised by an in-place wait, or terminates a deadlocked program with exit 1 |
| `oserror` | a scheduler allocation or timer could not be created |

These are the complete SCHED codes. `join` and `deadline` also propagate
errors raised by the function they run or observe, preserving the original
error object. Ordinary Lua argument-type errors remain Lua errors; see
[err](err.md).
