# mem

A small memory across runs: what an agent decided, counted, or saw last time,
kept in one JSON file per project.

```lua
local mem = require("mem")
mem.set("last_build", { at = os.time(), ok = true })   -- any value JSON can hold
mem.get("last_build")                                   -- nil when absent
mem.get("runs", 0)                                      -- with a default
mem.set("runs", mem.get("runs", 0) + 1)
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

Every `get` reads the file and every `set` reads, merges, and writes it
atomically, so two kuu processes take turns rather than overwrite each
other's keys. The whole file may not exceed 1 MiB: `set` refuses with
`MEM toobig` and the file stands. This is a notebook, never a database; the
database stays out of kuu by decision.

| MEM code | when |
|---|---|
| `toobig` | the memory would exceed 1 MiB; nothing was written |
| `badvalue` | raised for a key that is not a string; `nil, err` for a value JSON cannot hold |
| `corrupt` | raised: the file is not a JSON object |
| `unreadable` | raised: the file exists and cannot be read |
