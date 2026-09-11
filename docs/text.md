# text

Strict conversion between UTF-8 and the encodings Windows programs emit.

```lua
local text = require("text")
text.decode(bytes, "cp1252")      -- UTF-8, or nil, err TEXT invalid
text.encode(str, "utf-16le")      -- bytes, or nil, err TEXT unencodable
text.valid(bytes)                 -- true when the bytes are strict UTF-8
text.encodings()                  -- the accepted names

text.tobase64(bytes)              -- standard alphabet, padded
text.tobase64(bytes, { url = true })   -- the url alphabet, no padding
text.frombase64(s)                -- bytes, or nil, err TEXT invalid; either alphabet, padding optional, whitespace ignored
text.tohex(bytes)                 -- lower case
text.fromhex(s)                   -- bytes, or nil, err TEXT invalid; either case, whitespace ignored

text.upper(s), text.lower(s)      -- Unicode case mapping by Windows' invariant rules, the ones file names fold by;
                                  -- Lua's own string.upper knows ASCII only; nil, err TEXT invalid for bad UTF-8

text.trim(s)                      -- without leading or trailing blanks
text.trim(s, "left")              -- or "right", or "both", the default
```

`trim` removes the six bytes Lua's `%s` matches -- space, tab, newline,
vertical tab, form feed, carriage return -- from one end or both. It trims
bytes, not characters: a Unicode space that is not one of those six is kept,
as `%s` would keep it. A string needing no trimming is returned as itself
rather than copied, and `where` other than `"both"`, `"left"` or `"right"`
raises `TEXT badvalue`.

It is here because writing it as a pattern is a trap. `s:gsub("%s+$", "")`
looks like it inspects the end of the string and does not: only `^` anchors a
Lua pattern, so Lua retries the match at every position and the cost grows
with the whole string rather than with the blanks. Trimming a 15-byte line
300,000 times measured 300 ms by that pattern, 13 ms through `trim`; on a
278 KB document the pattern took 3.2 seconds against 26 ms. See
[Pitfalls](#pitfalls).

Encodings: `utf-8`, `utf-16le`, `utf-16be`, `latin1`, `ansi` (the system code
page), `oem` (the console code page), and `cpNNN` for any Windows code page
number, such as `cp850` for what `cmd.exe` writes on a Western European
system.

Every conversion is strict. Bytes that are not valid in the named encoding are
refused, never replaced by U+FFFD; a character the target code page cannot
represent is refused, never best-fitted to a lookalike. A silently rewritten
name is worse than a reported one. UTF-16 input must have an even number of
bytes and paired surrogates; byte-order marks are not interpreted or produced.

| TEXT code | when |
|---|---|
| `invalid` | the input is not valid in the named encoding, or is not base64 or hex |
| `unencodable` | the string has characters the target encoding lacks |
| `unsupported` | the code page is not available on this system |
| `badvalue` | raised: an unknown encoding name |
| `toobig` | the input is too long for Windows' case mapping |
| `oserror` | raised: allocation or Windows case mapping failed |
