# Upgrading to 0.9

0.9.0 is the last release before the 1.0 freeze, and it exists to correct
contracts while correcting them is still allowed. It carries one breaking
change every project must act on — the version now has three components — and
one defect fix that removes an intermittent failure from every atomic write.

Copy the new executable into the repository root, verify its signature and
SHA-256 against the release, **replace the minimum-version guard as described
below**, run `kuu check`, and run the project's tasks. For earlier releases,
read [upgrading to 0.8](upgrading-0.8.md), [to 0.7](upgrading-0.7.md), and the
[0.6 duration migration](upgrading-0.6.md).

## The version is Major.Minor.Patch

`rt.version` now reads `0.9.0` rather than `0.9`. A frozen 1.x needs a way to
ship a single correction without claiming new capability, and the component is
far cheaper to add before the freeze than after it.

**This breaks every guard written against the published pattern.** Releases
through 0.8 documented

```lua
local major, minor = rt.version:match("^(%d+)%.(%d+)$")
```

which does not match `0.9.0`. A project carrying it does not merely mis-compare:
`major` is nil, the guard's own assertion fires, and the project refuses this
runtime and every later one, whatever minimum it asks for. The failure is loud
and immediate rather than silent, but it happens before any task runs.

Replace the pattern with `rt.version_at_least`, which compares components and
never asks a project to parse the version text:

```lua
global none
global <const> require, assert
local rt = require "rt"
assert(rt.version_at_least(0, 9),
  "this project requires kuu 0.9.0 or later; found " .. rt.version)
```

`rt.version_at_least(major [, minor [, patch]])` answers whether the running
kuu is that version or newer. An omitted component is zero, so
`rt.version_at_least(1)` means 1.0.0. A component that is not a natural number
raises `RT badvalue`. Because it compares numbers, 0.10 correctly follows 0.9
and 1.0 follows both.

A project that must accept both 0.8 and 0.9.0 during a migration can ask for
the function before using it:

```lua
local rt = require "rt"
local recent = rt.version_at_least ~= nil
  and rt.version_at_least(0, 9)
```

`rt` is inside the planned 1.0 freeze, which is why `version_at_least`
arrives now rather than after it.

## Atomic writes no longer fail transiently

`fs.write` renames a temporary over its target, and that rename failed
intermittently with `FS access`, Windows error 5. On Windows a scanner or an
indexer routinely opens a file the moment its handle closes, and the rename of
a freshly written temporary loses that race. One process is enough to
reproduce it: 15 of 2000 single-process writes failed that way on the owner's
machine, and each one succeeded on an immediate second attempt. The same
defect made `mem.update` fail under concurrency and left the suite red.

The rename is now retried, up to six attempts over a few tens of milliseconds,
and only for access-denied and sharing-violation. After the change, 4000
writes failed none. Nothing else moved:

- No permission is bypassed. A target that genuinely cannot be replaced still
  fails with `FS access`, only later. A target somebody holds open past the
  window still fails, and that remains the intended answer.
- Atomicity is unchanged. Each attempt either replaced the target or left it
  alone, so a reader still sees the old bytes or all of the new ones.
- A caller that measured the timing of a failing write will see it take longer
  to fail. Success timing is unaffected in the common case.

See [fs](fs.md) for the contract and
[observed shortcomings](shortcomings.md) for the evidence.

## A pruned directory leaves `fs.dirs`'s `paths`

`fs.dirs` emitted a pruned directory into `paths` and skipped only its
descent. The plain walk — list the files of every path — therefore read exactly
the content the prune was asked to exclude. Two independent programs made that
mistake within an afternoon, which is evidence about the shape rather than
about their authors.

From 0.9.0 a pruned directory is reported in a new `skipped` array and is
never in `paths`. `dirs` still equals `#paths`, and `pruned` still counts
them.

```lua
local d = fs.dirs("C:/work", { prune = { ".*" } })

-- 0.8: d.paths included C:/work/.git, and this read its files
-- 0.9.0: it does not, and this reads what was asked for
for _, dir in ipairs(d.paths) do
  for _, e in ipairs(fs.list(dir).entries) do ... end
end

d.skipped   -- { "C:/work/.git", ... }   new
```

A caller that wants the old list can concatenate `paths` and `skipped`. A
directory stopped by the `depth` cap, or a link not followed, is unaffected
and stays in `paths`: those are the frontier the walk was asked to stop at,
not names it was asked to exclude.

## `json.object` gives an object a decided key order

New, and nothing changes for code that does not use it. A Lua table has no key
order, so until now no kuu program could emit a canonical document — a
manifest, a lockfile, a golden fixture — without writing its own emitter
around `json.encode`. Every project that needed one wrote a different one, and
the freeze would have made that permanent.

```lua
json.encode(json.object {
  { "tool",    "sigil" },
  { "version", "1" },
  { "count",   14 },
})
-- {"tool":"sigil","version":"1","count":14}
```

It marks a table as `json.array` does, nests at any depth, and `json.object {}`
encodes as `{}`. `json.is_object` tells one apart. Each entry must be a
two-element `{ key, value }` pair with a string key; anything else raises
`JSON badvalue` naming the entry. Decoding is untouched — order is a property
of writing, not of the value — so a document read back is an ordinary table.

## `sched.clock` resolves below a microsecond

It read the event loop's millisecond tick, so the smallest difference two
readings could show was exactly 1 ms and nothing under roughly 50 ms could be
measured honestly. It now reads the performance counter: measured on the
owner's machine, the smallest observable difference fell from 1 ms to about
500 ns.

Its meaning is unchanged — monotonic seconds from an arbitrary epoch, where
only differences mean anything — so this is precision rather than a new
contract. Code that rounded a reading to whole milliseconds will now see
fractions.

## Three modules leave the planned freeze

`svc`, `evt`, and `sys.signature` arrived in 0.7 and have no real-project
adoption evidence behind them. Service state machines, event-log queries, and
Authenticode trust are easy surfaces to shape wrongly, and freezing a wrong
shape would cost the whole 1.x line. They join `pty` as provisional, outside
the freeze, and are brought in at 1.1 with evidence behind them.

Nothing is removed from the executable and no call changes. Only the
compatibility promise is withheld; see the
[stability statement](stability.md).
