# Plan for 0.9.0, the pre-freeze correction release

0.9.0 is the last release before the 1.0 freeze, and it exists to correct
contracts while correcting them is still allowed. The stability statement
already says 1.x may add a module, function, verb, option, or result field
freely, but may not change a meaning, a default, a unit, an exit code, or
weaken a documented lifetime or atomicity guarantee. Everything that is only
an addition therefore belongs after 1.0, and everything that changes a
contract has to happen now or never.

This release is consequently mostly subtraction and correction. One feature
is added, and only because the absence of it forces every consuming project
to hand-roll a replacement that the freeze would then make permanent.

Agreed with the owner on 2026-09-11.

## The version becomes Major.Minor.Patch

0.9.0 is the first release with a patch component. A frozen 1.x with a long
life needs a way to ship a single defect or security fix without implying new
capability; `1.0` to `1.1` for a one-line correction inflates the minor
number until the history stops being readable. Retrofitting the component
after the freeze is unpleasant, so it lands here.

The consequence is a break, and it is the reason this is not a silent change.
The guard published in [adopting](../docs/adopting.md) and the
[stability statement](../docs/stability.md) is

```lua
local major, minor = rt.version:match("^(%d+)%.(%d+)$")
```

which does not match `0.9.0`. Every project carrying that guard fails at
load with its own "requires kuu ..." error the moment it sees this runtime.
The fix is not a better pattern. It is to stop asking projects to parse a
version string at all:

- `rt.version` keeps its meaning: the release's version text, now three
  components.
- `rt.at_least(major, minor [, patch])` is added, returning a boolean.
  A missing patch is 0. Non-integer arguments raise `RT badvalue`.
- `adopting`, `stability`, and `task` publish the call instead of the
  pattern, and the suite extracts and runs the published example.

`rt` is inside the 1.0 freeze, so this addition has to exist before the
freeze rather than after it.

Naming is the owner's call: `rt.at_least(0, 9)` reads well at the call site,
`rt.version_at_least` is more literal. The plan assumes `rt.at_least`.

## Three modules leave the freeze list

`svc`, `evt`, and `sys.signature` all arrived in 0.7 and have no real-project
adoption evidence in [shortcomings](../docs/shortcomings.md), which is
otherwise dense with it. Service state machines, event-log queries, and
Authenticode trust are three of the easiest Windows surfaces to shape wrongly,
and freezing a wrong shape costs the whole 1.x line. They join `pty` as
provisional and are brought in at 1.1 with evidence behind them.

Nothing is removed from the executable. Only the promise is withheld.

## Contracts to correct

### `fs.dirs` prune lists what it never enters

A pruned directory still appears in `paths`, so the obvious loop over `paths`
walks into exactly the content the prune excluded. It is not documented.
This produced the same defect in two independent implementations of the same
program on the same afternoon, which is strong evidence that the shape, not
the reader, is at fault.

Decide one of:

1. Pruned directories leave `paths` and are reported separately, or
2. They stay, gain an explicit marker, and the manual says so loudly.

Either is a contract change. The second keeps information that is genuinely
useful and is the weaker break; the first is what a caller expects. The owner
decides; the trap does not survive into 1.0 either way.

### `json.encode` has no key order

A Lua table has no key order and the encoder emits hash order, so no kuu
program can produce a canonical document — a manifest, a lockfile, a golden
test fixture, anything to be signed or compared byte for byte — without
writing its own emitter. The Lua-versus-Tcl ledger already records this as
felt three times in one day.

The stability statement declares enumeration order unstable, so this is not
a promise to break; it is a missing capability whose absence is about to be
frozen into every consumer's private workaround. Add an ordered-object form
before 1.0.

### `sched.clock` resolves to 1 ms

Measured on this host: the smallest observable non-zero delta is exactly
1 ms. Nothing below roughly 50 ms can be measured honestly, which is most of
what the month of use before 1.0 would want evidence about. QPC gives about
100 ns. This is a precision improvement rather than a change of meaning, so
it would remain legal at 1.x, but it should land now so that the month
produces numbers worth keeping.

### Cross-module numeric handoffs

The `cli` to `proc` duration defect silently multiplied a deadline by 1,000
and was fixed in 0.6. The class is what matters here, because the freeze
makes the class permanent. Audit every remaining numeric value that crosses
a module boundary — durations, sizes, counts — for unit agreement, and add
regressions where agreement is only conventional.

## The release blocker

`fs.write`'s atomic replace intermittently fails with `FS access`, Windows
error 5. The 2026-09-11 comparison reproduced it in both the published 0.6
executable (4 failures in 1,000 writes) and the compatibility build (3), the
cause is not isolated, and the soak gate is not clean on this host.

Atomicity is a documented guarantee, and 1.x may not weaken one. A promise
the implementation misses in roughly three writes per thousand cannot be
frozen. Before 1.0, either the cause is isolated and fixed, or the
documented promise is narrowed to what the implementation actually delivers.
Narrowing is forbidden after the freeze, so "not decided" is the one outcome
the boundary does not allow.

The existing discipline holds: no permission bypass, and no unconditional
retry. A bounded, documented retry on the replace step alone is a legitimate
answer, and it is a contract-visible decision rather than an implementation
detail.

## Amendments to the 1.0 criteria

The roadmap proposes three projects driven for a month without a runtime
defect, a manual page per module, a signed release cadence, and the
Lua-versus-Tcl ledger closed. Two amendments:

- **A clean soak gate on every target host.** It is knowingly unclean today.
  Freezing while it is unclean rests the 1.x promise on a signal that is not
  trusted.
- **At least one cold adopter.** Every adoption finding on record comes from
  Time Actual, which co-evolved with the runtime. A project that co-evolves
  routes around contract mistakes instead of reporting them. One project
  that meets a frozen 0.9.0 cold will find what the others cannot.

## Not in 0.9.0

- `worker` and `serve`. The need is now demonstrable: kuu's single loop has
  no in-runtime answer for CPU-bound fan-out, and the workaround is roughly
  twenty-five lines of child processes and a hand-rolled JSON protocol,
  rewritten per project. It is nevertheless a pure addition and belongs at
  1.1. The only pre-freeze obligation is a design check that a worker pool
  can be added without changing `sched` or `proc`. If it cannot, that is a
  freeze blocker and this decision is revisited.
- `store`, publishing, Tk, a wrap verb, PATH lookup. Unchanged no-go.

## Order of work

1. Version grammar, `rt.at_least`, docs and tests that derive the version.
2. Stability statement: the three modules leave the freeze list.
3. `sched.clock` precision.
4. `json` ordered object.
5. `fs.dirs` prune, once the owner picks the shape.
6. Numeric handoff audit.
7. `fs.write` atomic replace, isolate or narrow.
8. Roadmap: the 1.0 criteria amendments, and the 0.9.0 milestone entry.
9. `docs/upgrading-0.9.md`, covering the version grammar break above all.

---

## Status, 2026-09-11

The owner settled the four open decisions; the work below is implemented and
the suite is green at **1062 ok, 0 failed**.

| item | decision | state |
|---|---|---|
| version grammar | Major.Minor.Patch, first release `0.9.0` | done |
| the guard | `rt.version_at_least(major [, minor [, patch]])` | done |
| freeze list | `svc`, `evt`, `sys.signature` become provisional | done |
| atomic replace | bounded retry, six attempts, transient errors only | done |
| `fs.dirs` prune | pruned directories leave `paths` for a new `skipped` | done |
| ordered JSON | `json.object { {k, v}, ... }`, a marker beside `json.array` | done |
| `sched.clock` | performance counter; 1 ms to about 500 ns | done |
| numeric handoff audit | no boundary found where agreement was only conventional | done |
| worker-pool design check | a pool on the 0.9.0 surface reached 2.74x; not a freeze blocker | done |

### The blocker, closed

The `FS access` failure was isolated rather than worked around. 2000 atomic
writes from **one** process failed 15 times; every failure recovered on an
immediate retry with no sleep and no change of permission. A single process
reproducing it removes concurrency, `sync`, and kuu's own locking from the
account and leaves the environment: a scanner or an indexer opens the freshly
closed temporary and the rename loses the race. 4000 writes after the retry
failed none. The regression holds a reader open for the whole attempt and
asserts the write still fails, that it spent the retry window rather than
giving up on the first rename, and that the target kept its old bytes.

One correction to the source comment written during this work: it first
claimed a ceiling of roughly 15 ms, the sum of the waits. A file held open
throughout was measured failing after about 60 ms, because `Sleep(1)` carries
the scheduler's ~15 ms timer granularity. The comment now says that.

### The two other intermittent failures

Neither is attributed to kuu without evidence.

- **`proc.tree` on a 31-process chain.** Run in isolation 50 times: **0
  failures in 54 s**. It failed once inside a full suite run, so if it is real
  it is load-dependent rather than inherent to the case. Recorded as
  unreproduced; the repeated full-suite runs are the next evidence.
- **`an unknown host is HTTP notfound`.** Returned `HTTP timeout` when sandbox
  DNS stalled past ten seconds, and passed on other runs. Environmental.

### Not done, and deliberately

`worker` and `serve` stay out of 0.9.0. The need is real, but it is a pure
addition and legal at 1.1. The pre-freeze obligation is only the design check
that a pool can be added without changing `sched` or `proc`.

### The numeric-handoff audit

Clean. Every value that crosses a module boundary into Lua is a duration in
seconds or a size in bytes, and the manual says so on each page: `cli`
(seconds, bytes), `proc.run`'s `elapsed` (seconds), `proc.list`'s `cpu`
(seconds), `net.probe` (seconds), `evt` and `fs.stat` instants (Unix seconds),
`time` throughout. The two computed values were checked against their C:
`cpu` divides FILETIME's 100-nanosecond ticks by 1e7, and `elapsed` divides a
millisecond difference by 1000. Both are seconds, as documented.

The one millisecond quantity left, `ku_parse_duration_ms` and the loop's
`ku_now_ms`, is native-internal and never reaches Lua. `elapsed` inherits that
tick's 1 ms granularity, which is appropriate for a process lifetime and is
not the unit defect the 0.6 `cli`-to-`proc` bug was.

No regression was needed, because no boundary was found where agreement is
only conventional.

### The worker-pool design check: not a freeze blocker

A pool was prototyped against 0.9.0 and runs its workers genuinely in
parallel, using nothing outside the 1.0 freeze list. It reaches only for

    sched.spawn, task:join
    proc.start { stream = true }, c:write, c:read("line", timeout),
    c:close_stdin, c:close
    json.encode, json.decode

so `worker` and `pool` can be added at 1.1 as ordinary Lua, with no C and no
change to `sched` or `proc`. The decision to keep them out of 0.9.0 stands.

The shape follows from two documented rules rather than from invention: only
one task may read a given stream, and a read parks the task that issues it.
So it is one task per worker, each taking the next index off a shared cursor,
which needs no lock because tasks are coroutines and nothing yields between
reading and writing that cursor:

```lua
for w = 1, width do
  local spec = { stream = true, timeout = "5m" }
  for i, a in ipairs(command) do spec[i] = a end
  local child = proc.start(spec)
  tasks[w] = sched.spawn(function()
    while true do
      cursor = cursor + 1
      local index = cursor
      if index > #requests then break end
      child:write(json.encode(requests[index]) .. "\n")
      replies[index] = json.decode(child:read("line", "60s"))
    end
    child:close_stdin()
  end)
end
for _, t in ipairs(tasks) do t:join() end
```

Measured, 16 CPU-bound jobs of 20,000,000 iterations on a 16-processor host:

| width | wall | speedup | jobs per worker |
|---|---|---|---|
| 1 | 1.88 s | 1.00x | 16 |
| 2 | 1.11 s | 1.70x | 8, 8 |
| 4 | 0.74 s | 2.56x | 4, 4, 4, 4 |
| 8 | 0.69 s | 2.74x | 2 each |

N parked reads really are N processes working at once. The curve flattens
because each job is only about 120 ms while a child costs roughly 36 ms to
start, so at width 8 the startups are a large share of the total — the same
economics the earlier contest found, and a reason for a future `pool` to keep
its workers alive across batches rather than per call.

One caution for whoever implements it: `table.unpack(command)` anywhere but
last in a table constructor is adjusted to a single value, which silently
launches the runtime with no program and shows up only as an EOF on the first
read. Build the spec key by key.

### The remaining gates

Run after every change above, on build 22631.7517:

- **`make fuzz`**: passed. 10,000 cases each over durations, dates, paths,
  CSV, INI, JSON and registry text, plus 10,000 command lines, on both fixed
  seeds.
- **`make soak`**: **34 rounds in 61 s, handles -3, private +4.3 MB,
  failures 0.**

That soak figure is the one to notice. The 0.8 record above reads "38 soak
rounds in 61 seconds with stable handles, but **21 state writes failed**".
Those were the atomic replacement failing under repetition. With the retry in
place the same gate reports **zero**, so the 1.0 criterion of a clean soak
gate is met on this host — the first host where it has been.

With the suite green five times running and native analysis passing, every
component of `make gate` now passes.
