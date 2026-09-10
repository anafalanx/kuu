# re

Regular expressions, on PCRE2: the syntax of Perl, PCRE, and every editor,
with alternation, counted repetition, named groups, and Unicode, which Lua
patterns lack. Strings are bytes as everywhere in kuu; positions are Lua's,
one-based and inclusive.

```lua
local re = require("re")
re.find("the year 2026", "\\d+")                    -- 10, 13
re.find("key = value", "(\\w+)\\s*=\\s*(\\w+)")     -- 1, 11, "key", "value"
re.match("x=42", "(\\w)=(\\d+)")                    -- "x", "42"; the whole match when there are no groups
for word in re.gmatch("one two", "\\w+") do end
re.gsub("2026-09-09", "(\\d+)-(\\d+)-(\\d+)", "$3/$2/$1")            -- "09/09/2026", 1
re.gsub("john smith", "(?<first>\\w+) (?<last>\\w+)", "${last}, ${first}")
re.gsub("a b c", "\\w", function(w) return w:upper() end)             -- a function or a table, as string.gsub
re.split("a, b,c", "\\s*,\\s*")                    -- { "a", "b", "c" }
re.exec("Date: 2026-09-09", "(?<year>\\d{4})-(\\d{2})-(\\d{2})")
-- { start = 7, stop = 16, "2026", "09", "09", year = "2026" }; an unset group is false
re.escape("a.b*c")                                  -- "a\\.b\\*c"

local rx = re.compile("(?<key>\\w+)=(?<value>\\d+)", "i")
rx:find(s), rx:match(s), rx:gmatch(s), rx:gsub(s, r), rx:split(s), rx:exec(s)
rx.groups, rx.names                                 -- 2, { key = 1, value = 2 }
```

Every function takes the pattern as a string and optional flags as its last
argument; `find`, `match`, and `exec` take an `init` before the flags, as
`string.find` does. Compiled patterns are cached, so the functions cost no
more than the methods; `compile` is for a pattern used many times or for its
`groups` and `names`.

`gsub` takes an optional replacement count before its flags:
`re.gsub(s, pattern, replacement, n, flags)` or `rx:gsub(s, replacement, n)`.
Omitting `n` replaces every match; zero makes no replacements. For flags
without a count, pass nil in that slot.

| flag | meaning |
|---|---|
| `i` | caseless |
| `m` | `^` and `$` match at every line; a line ends at CR, LF, or CRLF |
| `s` | `.` matches a newline too |
| `x` | whitespace and `#` comments in the pattern are ignored |
| `b` | bytes: no UTF-8, `.` is one byte, any subject is fine |
| `u` | `\d`, `\w`, `\b` and friends know Unicode, not only ASCII |

Patterns and subjects are UTF-8 unless `b`. A subject that is not valid
UTF-8 is refused as `RE invalid`, naming the byte, rather than matched wrongly;
for arbitrary bytes, such as a log with a stray byte, use `b`. `\C` is never
allowed.

In a replacement string, `$1` to `$99` and `${name}` are groups, `$0` the
whole match, and `$$` a dollar; anything else after `$` is refused. An unset
group expands to nothing. A function replacement is called with the
captures, or the whole match when there are none, and a table is looked up by
the first capture, or the whole match; `nil` or `false` keeps the original,
as in `string.gsub`.

An empty match advances by one character, or one CRLF, and never repeats at
the same place, so `gmatch`, `gsub`, and `split` always finish. `split` makes
no piece from an empty match at a boundary, so `re.split("abc", "")` is the
characters, and keeps empty fields between and after separators, so
`re.split("a,,b,", ",")` is `{ "a", "", "b", "" }`.

The engine's own limits stop a catastrophic pattern rather than letting it run
for hours: `RE limit`. No JIT is built in, on purpose; the interpreter handles
a megabyte of `gsub` well under a second.

| RE code | when |
|---|---|
| `badpattern` | raised: the pattern does not compile; the message has PCRE2's words and the offset |
| `badvalue` | raised: an unknown flag, `b` with `u`, a bad `$` in a replacement, a replacement that is not a string |
| `invalid` | raised: the subject is not UTF-8, or `init` is inside a character; flag `b` matches bytes |
| `limit` | raised: the match exceeded the engine's limits |
| `oserror` | raised: allocation failed, or the engine returned another internal error |
