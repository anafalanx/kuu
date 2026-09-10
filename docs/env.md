# env

Environment variables: this process's, and the ones Windows keeps for the
user or the machine. Where an agent would reach for `$env:NAME`,
`[Environment]::SetEnvironmentVariable(name, value, "User")`, or `setx`.

```lua
local env = require "env"

env.get("TEMP")                              -- the live value, UTF-8; os.getenv does the same
env.set("GIT_PAGER", "")                     -- for this process and the children it starts from now on
env.set("GIT_PAGER", nil)                    -- removed
env.all()                                    -- { NAME = value, ... }
env.expand("%LOCALAPPDATA%\\tool")           -- "C:\\Users\\me\\AppData\\Local\\tool"

env.persisted("Path")                        -- the user's stored Path, unexpanded, and its type
env.persist("TOOL_HOME", "%USERPROFILE%\\tool")   -- stored for the user, then the change is broadcast
env.forget("TOOL_HOME")                      -- removed, then the change is broadcast
env.persist("TOOL_HOME", "C:\\tool", "machine")  -- for everyone; needs an elevated kuu
```

## The two environments

The **live environment** is this process's copy. `set` changes it for kuu
and for every child kuu starts afterwards; nothing outside notices. A
child's `env` option in [`proc`](proc.md) does the same for one child.
`get` and `os.getenv` return `""` for an empty value and `nil` for an
absent variable. Names and text values cannot contain NUL.

The **persisted environment** is what Windows hands to new processes: the
user's, under `HKCU\Environment`, and the machine's, under the Session
Manager's key. `persist` and `forget` write there and broadcast
`WM_SETTINGCHANGE`, so Explorer and every console opened afterwards see the
change. Processes already running, kuu itself included, keep their copy:
after `env.persist`, `env.get` still answers as before. A value holding a
`%` is stored as an expandstring, as Windows does for `Path`; `persisted`
returns it unexpanded with its type, and `env.expand` expands it.

To add a directory to the user's `Path`, read `env.persisted("Path")`,
edit the string, and persist it back; nothing here edits `Path` for you,
because appending blindly is how `Path` fills with duplicates.

## Functions

```lua
env.get(name)                       -- value | nil
env.set(name, value)                -- true; value nil or false removes
env.all()                           -- { NAME = value }
env.expand(text)                    -- text with %VAR% references filled in
env.persisted(name [, scope])       -- value, type | nil
env.persist(name, value [, scope])  -- true | nil, err
env.forget(name [, scope])          -- true | nil, err
```

`scope` is `"user"` (the default) or `"machine"`.

## Errors

Domain `ENV`: `badvalue` (raised: an empty name, a name with `=`, an unknown
scope, or embedded NUL), `notfound` (forgetting what is not there), `access` (the machine
scope without elevation), `oserror`.
