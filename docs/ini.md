# ini

INI files as Windows has them: `[sections]`, `key=value`, comment lines
starting with `;` or `#`. Where an agent would reach for
`Get-IniContent` from a gallery module, or a regular expression it will
regret.

```lua
local ini = require "ini"

local t = ini.decode(text)                  -- { [""] = { top-level keys }, Section = { key = "value" } }
t.Server.port                               -- "8080": always a string
ini.get(t, "server", "PORT")                -- the same, ignoring case as Windows does
ini.encode(t)                               -- sections and keys sorted; deterministic
ini.set(text, "Server", "port", "9090")     -- the text with that one change, the rest untouched
ini.remove(text, "Server", "port")          -- without that key; without the whole section when key is nil
```

Two ways of working, on purpose. `decode` and `encode` read a file into a
table and write a file of your own. `set` and `remove` edit a file that
belongs to something else: comments, order, spacing, and the line ending
style survive, and section and key names match ignoring case. Read the
file with `fs.read`, edit, write it back with `fs.write`.

## Rules

- Keys before any section header live under the empty section name, `""`.
- Keys and values are trimmed. A value in surrounding double quotes has
  them removed and the inside kept, as the Windows profile functions do;
  encode and set quote a value that would not otherwise survive.
- A line without `=` is a key with an empty value.
- There are no inline comments: everything after `=` is the value, a `;`
  included, which is what Windows does too.
- Duplicate keys: the last wins. Duplicate sections merge.
- Values are strings; numbers and booleans given to `encode` or `set` are
  written with `tostring`.

## ini.set and ini.remove

```lua
ini.set(text, section, key, value)   -- text
ini.remove(text, section [, key])    -- text
```

`set` replaces the value on an existing key's line, keeping the key's own
spelling and the spacing around `=`; adds a missing key after the last
line of its section, before the blank lines that precede the next header;
appends a missing section at the end. `section` `""` means the top level.
`remove` drops one key, or the whole section with its header when `key` is
nil, and returns the text unchanged when there is nothing to remove.

## Errors

Domain `INI`, all raised: `badvalue` for a key holding `=`, a value that
spans lines, or a table that is not sections of keys.
