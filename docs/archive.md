# archive

Zip and tar archives using Windows' archive components. `pack` and `unpack`
use the system `tar.exe`. `list` uses the Unicode API in its companion
`System32/archiveint.dll`, the libarchive that Windows ships beside `tar.exe`
since Windows 10 1803. It is loaded only from the system directory and every
entry point is checked; it is not a documented Windows API, so on a Windows
without it, or one that changes it, `list` fails with `ARCHIVE oserror`
naming the library while `pack` and `unpack` keep working. No extra
executable or archive library is installed.

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
| `ARCHIVE failed` | an invalid archive, unsupported format, or rejected entry; pack/unpack retain tar's diagnostic |
| `ARCHIVE badvalue` | raised: wrong types, a negative `strip`, entries that leave the directory, an empty directory to pack |
| `ARCHIVE timeout` | the archive operation did not finish within `timeout` (default 30m) |
| `ARCHIVE encoding` | an entry has no valid Unicode filename |
| `ARCHIVE toobig` | listing exceeds 64 MiB of names, one million entries, or 64 MiB of encoded output |
| `ARCHIVE oserror` | the required Windows component is unavailable |

`list` returns UTF-8 names, including characters outside the system ANSI code
page. Embedded newlines remain part of a name. Directories retain their trailing
slash; backslashes become forward slashes to match Windows extraction semantics.
It does not extract files or parse tar's lossy text listing. The native reader
runs in a supervised copy of this same `kuu.exe`, so deadlines and cancellation
terminate the reader without blocking the parent's scheduler. The internal
`_archive` module is an implementation detail, not a supported public API.
ZIP creation explicitly writes UTF-8 headers so names survive packing too.

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
