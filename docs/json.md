# json

Strict reading, exact writing.

```lua
local json = require("json")
local v, e = json.decode(text)            -- nil, err JSON parse | depth | duplicate
local s = json.encode(v)                  -- raises JSON badvalue | encoding | depth
local pretty = json.encode(v, { pretty = true })
```

## The mapping

| JSON | Lua |
|---|---|
| `null` | `json.null`, a sentinel, so a null inside an array keeps its slot |
| `true`, `false` | booleans |
| number | an integer when whole and within 64 bits, else a float |
| string | a string, UTF-8 both ways |
| array | a table marked with `json.array`, elements at 1 to n |
| object | a table with string keys |

Decoded arrays are marked, so an empty array stays `[]` on the way back and
`json.is_array(t)` tells. An unmarked table encodes as an array when its keys
are exactly 1 to n with n above zero, and as an object otherwise: `{}` is an
object, `json.array{}` is `[]`. `json.array(t)` marks an existing table.

```lua
local doc = json.decode('{"ids": [1, null, 3], "empty": {}}')
#doc.ids == 3            -- the null kept its place
doc.ids[2] == json.null
json.encode { list = json.array {}, none = json.null }   -- '{"list":[],"none":null}'
```

Integers survive exactly; a document carrying 64-bit identifiers round-trips
without loss. Integers beyond 64 bits decode as floats. Integral floats encode
with a decimal point (`2.0`), so the two number kinds do not blur.

## Refusals

Decoding is strict: a duplicate object key is `JSON duplicate` at any depth,
because last-wins would silently lose data; nesting beyond 512 is `JSON depth`;
a lone surrogate escape, trailing text, or any malformation is `JSON parse` with
the byte offset. Encoding raises for values JSON has no spelling for: NaN and
infinity, functions and userdata other than `json.null`, tables mixing array
and string keys, non-string keys, strings that are not valid UTF-8, and cycles,
which surface as `JSON depth`.

Output is compact by default, with the seven short escapes, lowercase
`\u00xx` for other control characters, and UTF-8 left raw.
