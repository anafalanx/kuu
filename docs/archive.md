# archive

Zip and tar archives, through the `tar.exe` every supported Windows ships.
Nothing else is assumed on the machine.

```lua
local archive = require("archive")

archive.unpack("build/zig.zip", ".tools/zig", { strip = 1 })   -- true | nil, err
archive.pack("build/out.zip", "build/stage")                   -- everything in the directory
archive.pack("build/src.tar.gz", ".", { "src", "Makefile" })   -- named entries, relative to the directory
archive.list("build/zig.zip")                                  -- { "zig-x86_64-windows-0.16.0/", ... }
```

The format follows the archive's extension: `.zip`, `.tar`, `.tar.gz` or
`.tgz`, `.tar.xz`, `.tar.zst`, `.tar.bz2`. `unpack` creates the directory
when needed and overwrites what is there; `strip` drops that many leading
path components, so an archive whose single top-level directory carries the
version lands where you say. `pack` replaces an existing archive; entries are
names inside the directory, never absolute and never climbing out. Windows'
bsdtar refuses archive entries that would climb out of the target directory,
so an unpack stays under the directory you name.

| code | meaning |
|---|---|
| `ARCHIVE notfound` | no archive, or no directory, at that path |
| `ARCHIVE failed` | tar refused: not an archive, an unknown extension, a bad entry; the message is tar's own |
| `ARCHIVE badvalue` | raised: wrong types, a negative `strip`, entries that leave the directory, an empty directory to pack |
| `ARCHIVE timeout` | tar did not finish within `timeout` (default 30m) |

Fetching a prerequisite is these two capabilities together, and nothing more:

```lua
local http, archive = require("http"), require("archive")
local r, e = http.get("https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip", {
  to = "build/zig.zip",
  sha256 = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e",
})
if not r then return nil, e end                              -- a wrong hash is HTTP mismatch, and no file is left
local ok, e2 = archive.unpack("build/zig.zip", ".tools/zig", { strip = 1 })
```
