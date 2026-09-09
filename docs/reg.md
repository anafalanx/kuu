# reg

The registry, typed. Where an agent would reach for `Get-ItemProperty`,
`Set-ItemProperty`, `New-Item HKCU:\...`, or `reg.exe`.

```lua
local reg = require "reg"

reg.get("HKCU\\Software\\Vendor\\App", "Level")      -- 3, "dword"
reg.set("HKCU\\Software\\Vendor\\App", "Level", 4)   -- creates the key path when needed
reg.set(key, "Path", "%ProgramFiles%\\x", "expandstring")
reg.values(key)                                      -- { { name = "Level", type = "dword", value = 4 }, ... }
reg.keys(key)                                        -- { "Sub1", "Sub2" }
reg.delete(key, "Level")                             -- one value
reg.remove(key)                                      -- the key and everything under it
```

A key is written `HKCU\Software\Vendor\App`; either slash works, and so do
the long root names. Roots: `HKLM`, `HKCU`, `HKCR`, `HKU`, `HKCC`. The
value name `nil` or `""` is the key's default value. kuu is a 64-bit
process and sees the 64-bit view.

## Types

| type | Windows | Lua |
|---|---|---|
| `string` | REG_SZ | a string |
| `expandstring` | REG_EXPAND_SZ | a string, unexpanded; `env.expand` expands it |
| `multistring` | REG_MULTI_SZ | a list of non-empty strings |
| `dword` | REG_DWORD | an integer 0 to 4294967295 |
| `qword` | REG_QWORD | an integer, 64 bits, signed on the way back |
| `binary` | REG_BINARY | a string of bytes |

`get` and `values` return the value and its type name; a type not in the
table reads as bytes named `"unknown"`. `set` without a type stores a
string as `string`, an integer as `dword` when it fits and `qword`
otherwise, and a list as `multistring`; give the type to store an
`expandstring`, a `binary`, or a small `qword`. Floats have no registry
type and raise.

## Functions

```lua
reg.get(key, name)                   -- value, type | nil, err
reg.set(key, name, value [, type])   -- true | nil, err
reg.delete(key, name)                -- true | nil, err
reg.values(key)                      -- { { name, type, value }, ... } sorted by name | nil, err
reg.keys(key)                        -- { name, ... } sorted | nil, err
reg.exists(key)                      -- boolean
reg.create(key)                      -- true | nil, err
reg.remove(key)                      -- true | nil, err
```

`remove` deletes a whole tree and refuses a key directly under a root.
Writing under `HKLM` needs an elevated kuu; without it the answer is
`nil, REG access`, not a silent redirect.

## Errors

Domain `REG`: `notfound` (no such key or value), `access` (run elevated),
`badvalue` (raised: a bad root, type, or value), `oserror`.
