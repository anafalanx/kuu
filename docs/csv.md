# csv

Comma-separated values as RFC 4180 has them, and the variants Windows tools
write: other separators, CRLF or LF line ends, a leading byte order mark.
Where an agent would reach for `Import-Csv`, `Export-Csv`, or `ConvertFrom-Csv`.

```lua
local csv = require "csv"

local rows = csv.decode(text)                          -- { { "a", "b" }, { "1", "2" } }
local recs = csv.decode(text, { header = true })       -- { { a = "1", b = "2" } }, recs.columns = { "a", "b" }
csv.decode(text, { separator = ";" })                  -- Excel in many locales; "\t" for TSV
csv.encode(rows)                                       -- CRLF line ends, quotes only where needed
csv.encode(recs, { columns = { "a", "b" } })           -- records: a header row, then each record's fields
csv.encode(rows, { separator = ";", bom = true })      -- Excel opens it as UTF-8
```

## csv.decode

```lua
csv.decode(text [, options])   -- rows | nil, err
```

Every field is a string; nothing guesses at numbers, dates, or booleans.
Quoted fields may hold the separator, quotes (written doubled), and line
ends. CRLF, LF, and CR all end a line; a final line end is not an extra row;
blank lines are skipped; a leading UTF-8 byte order mark is dropped.

| option | default | |
|---|---|---|
| `separator` | `","` | one character; `";"` for European Excel, `"\t"` for TSV |
| `header` | `false` | the first row names the columns; the result is records keyed by name, with `columns` alongside |
| `ragged` | `false` | allow rows with a different number of fields than the first row |

Failures are `nil, CSV parse` with the line number: an unterminated quoted
field, a quote inside an unquoted field, text after a closing quote, or a
row whose field count differs from the first row's unless `ragged` allows
it.

## csv.encode

```lua
csv.encode(rows [, options])   -- text
```

Rows are arrays of fields, or records when `columns` names the fields, in
that order; a decoded records table carries its `columns` and encodes back
as it came. Strings, numbers, booleans, and `nil` (empty) are fields;
anything else raises CSV badvalue. A field is quoted only when it holds the
separator, a quote, a line end, or leading or trailing whitespace.

| option | default | |
|---|---|---|
| `separator` | `","` | |
| `columns` | `rows.columns` | the field names, for records |
| `header` | `true` | write the column names first, for records |
| `newline` | `"\r\n"` | RFC 4180 and Excel; `"\n"` when a Unix tool reads it |
| `bom` | `false` | a leading byte order mark, which Excel needs to read UTF-8 |

## Errors

Domain `CSV`: `parse` (returned) and `badvalue` (raised).
