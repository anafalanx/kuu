# mem

A small memory across runs: what an agent decided, counted, or saw last time,
kept in one JSON file per project.

```lua
local mem = require("mem")
mem.set("last_build", { at = os.time(), ok = true })   -- any value JSON can hold
mem.get("last_build")                                   -- nil when absent
mem.get("runs", 0)                                      -- with a default
mem.update("runs", function(n) return (n or 0) + 1 end) -- read-modify-write as one step, under the lock
mem.forget("last_build")                                -- so does set(key, nil)
mem.keys()                                              -- sorted
mem.all()                                               -- a copy of everything
mem.path()                                              -- where it lives
mem.open("build/state.json")                            -- somewhere else instead
```

The file is `.kuu/memory.json` under the project root, the nearest
`tasks.lua` upward from the current directory, or under the directory
`require` searches when there is no project. Add `.kuu/` to the project's
`.gitignore` unless the memory is meant to travel with the repository.

Every `get` reads the file. Every `set` holds a [`sync`](sync.md) lock across
processes in the same Windows session, named after the file, while it reads, merges, and
writes atomically, so two kuu processes writing at once take turns and
neither loses the other's keys; a writer that cannot get the lock within ten
seconds gets `SYNC busy`. A value computed from a `get` and then `set` is
still two steps, and two processes counting that way lose increments; `update`
runs the function under the lock, so it is one. The whole file may not exceed 1 MiB: `set` refuses with
`MEM toobig` and the file stands. This is a notebook, never a database; the
database stays out of kuu by decision.

| MEM code | when |
|---|---|
| `toobig` | the memory would exceed 1 MiB; nothing was written |
| `badvalue` | raised for an empty or non-string key or `open` path, or a non-function `update` callback; `nil, err` for a value JSON cannot hold |
| `corrupt` | raised: the file is not a JSON object |
| `unreadable` | raised: the file exists and cannot be read |

Writes can also return the original `FS` error from creating the directory
or writing the file, or `SYNC busy` if the lock times out. Invalid paths and
lock setup failures keep their `FS` or `SYNC` domain. An `update` callback's
error propagates unchanged, releases the lock, and leaves the file intact.
