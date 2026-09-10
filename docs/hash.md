# hash

Digests, HMAC, and random bytes from Windows' own cryptography (CNG). Nothing
is vendored.

```lua
local hash = require("hash")
hash.sum("sha256", bytes)                    -- lowercase hex
hash.sum("sha256", bytes, { raw = true })    -- the digest bytes
hash.file("sha256", "build/kuu.exe")         -- streamed in 64 KiB chunks; nil, err
hash.hmac("sha256", key, bytes)
hash.random(32)                              -- bytes from the system RNG, 1 to 1048576
hash.uuid()                                  -- "5f3a…-…-4…-…", a random version 4 UUID, lower case
hash.algorithms()                            -- { "md5", "sha1", "sha256", "sha384", "sha512" }

local h = hash.start("sha256")
h:update(part1):update(part2)
h:final()                                    -- hex; the hasher is finished
```

`sum` and `file` accept `{ raw = true }` as the third argument, `hmac` as
the fourth, and `h:final` as its options argument. All default to lowercase
hex; raw results are digest bytes.

Strings are bytes, so what you pass is what is hashed, and
`hash.sum("sha256", "abc")` agrees with every other implementation. The list
`hash.algorithms()` returns is the list the binary has; an unknown name raises
`HASH badvalue` and says so.

`hash.file` uses the same normalized Unicode paths as `fs`, including paths
beyond 260 characters. Ambiguous drive-relative, device, or trailing-dot/space
paths are refused; a path containing NUL raises instead of silently hashing
the filename before that byte.

| HASH code | when |
|---|---|
| `badvalue` | raised: unknown algorithm, a count out of range, an oversized key, or NUL in a filename; returned for an ambiguous path |
| `encoding` | `hash.file`: the path is not valid UTF-8 |
| `notfound`, `access` | `hash.file`: the file cannot be opened or read |
| `oserror` | file I/O failed, or raised when Windows' cryptographic provider failed |
| `closed` | raised: a finished hasher was used again |
