# Toolchain

Two things live on this page: the lock that pins a repository's tools, which
kuu hydrates and verifies for any project it drives, and the record of what
kuu's own `.tools` holds, which is populated by hand.

## The lock

A repository that needs tools writes `tools/lock.json`. The lock is
prescriptive: for every tool it says where the bytes come from, what they must
hash to, and how to unpack and check them. Nothing on the machine is consulted,
`PATH` least of all.

```json
{
  "schema": 1,
  "tools": {
    "zig": {
      "version": "0.16.0",
      "url": "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip",
      "sha256": "3f2b0c4e…",
      "bytes": 88811520,
      "kind": "zip",
      "strip": 1,
      "bin": "zig.exe",
      "check": ["version"],
      "expect": "0.16.0",
      "license": "MIT",
      "notice": "LICENSE",
      "noticeSha256": "9a1c7d…"
    },
    "kuu": {
      "url": "https://example.invalid/kuu-0.3/kuu.exe",
      "sha256": "c0ffee…"
    }
  }
}
```

| field | meaning |
|---|---|
| `url` | required; `http://` or `https://`; where the bytes come from |
| `sha256` | required; 64 hex digits; what the download must hash to |
| `bytes` | optional; the download's exact size; a disagreement with the lock's own hash is refused |
| `kind` | `zip`, `tar`, or `exe`; inferred from the url's extension when absent |
| `strip` | archives only; leading path components to drop when unpacking |
| `bin` | the executable inside the tool; default `<name>.exe` for archives, the url's file name for an exe |
| `version` | informational, and the default for `expect` |
| `check`, `expect` | arguments to run the freshly unpacked `bin` with; its output must contain `expect` |
| `license` | informational; repeated in reports |
| `notice`, `noticeSha256` | a file inside the tool that must exist, and what it must hash to |

Tool names are plain words. Unknown fields, a short hash, a `bin` or `notice`
that would escape the tool's directory, a `strip` on an exe, a `check` without
anything to expect: each refuses the whole lock with `TOOLCHAIN badlock`
naming the tool and the field. A lock that is half right installs nothing.

## Hydrate and verify

```text
kuu hydrate [--deep] [--lock FILE] [--root DIR] [--json]
kuu verify  [--deep] [--lock FILE] [--root DIR] [--json]
```

Without `--lock` and `--root`, both use `tools/lock.json` and `.tools` of the
nearest project above the current directory (the one holding `tasks.lua`).
They are one pass with a flag. Each tool is classified:

| status | meaning |
|---|---|
| `ok` | stamped, the stamp matches the lock, the executable is there |
| `missing` | never hydrated, or the executable is gone |
| `stale` | the lock entry changed, or the kuu that hydrated it is not this one |
| `corrupt` | `--deep` only: the executable or the notice no longer hashes as stamped |

`verify` reports and exits 1 unless every tool is `ok`. `hydrate` repairs every
tool that is not, and reports each as `current`, `hydrated`, or `replaced`.
A repair goes in this order, so an interruption anywhere leaves either the old
tool or nothing, and never a half-installed one:

1. Download to `.tools/.downloads/<name>-<hash prefix>.<ext>.partial`, hash
   it, compare the size when the lock gives one, then rename it into the
   cache. A cached download is re-hashed every time and replaced when wrong,
   so a damaged file heals on the next run. The cache is keyed by the hash,
   so a url that moves without its bytes changing costs no download.
2. Unpack into `.tools/<name>.partial` with the `tar.exe` every supported
   Windows ships (zip, tar.gz, tar.xz, tar.zst), which refuses entries that
   would climb out of the directory. An exe is copied into place.
3. Check that `bin` exists, that `notice` exists and hashes as pinned, and
   run `bin check…`, whose output must contain `expect`. A tool that reports
   the wrong version is refused and the old install, if any, stands.
4. Remove the old stamp, remove the old directory, rename the new one in.
5. Write the stamp `.tools/<name>.json` last: the lock entry's fields, the
   executable's and notice's hashes, the time, and the kuu version.

The stamp's key is a hash over the lock entry, the layout format, and the
source of the hydrating code itself. Upgrading kuu therefore makes every tool
stale, and the next `hydrate` re-installs them from the cache without a
download. Every write stays under the tools root.

```text
.tools/
  .downloads/zig-3f2b0c4e1a2b3c4d.zip     the cache, by hash
  zig/                                    the tool, exactly as unpacked
  zig.json                                its stamp
```

Progress goes to standard error (`kuu: download zig: https://…`), the report
to standard output, one line per tool. `--json` silences the progress and
prints one envelope: `{"ok":true,"result":{"root","lock","tools":[{"name",
"version","license","status","action","path"}]}}`, or `ok:false` with `error`
and, for `verify`, the report with each tool's status. Exit codes: 0, 1 when
a tool is not ok or could not be repaired, 2 for a usage mistake or no project.

## In a program

```lua
local toolchain = require "toolchain"
local report, e = toolchain.hydrate("tools/lock.json", ".tools", {
  progress = function(step, name, detail) io.stderr:write(step, " ", name, "\n") end,
})
local report, e = toolchain.verify("tools/lock.json", ".tools", { deep = true })   -- e.report on failure
local zig, e = toolchain.path("tools/lock.json", "zig", ".tools")                    -- absolute, or nil, err
```

`toolchain.path` is how a task finds a tool: it checks the stamp and refuses a
tool that is `missing` or `stale` with that word as the code, so a task never
runs yesterday's compiler by accident. `toolchain.read(path)` returns the
checked lock. Codes: `nolock`, `badlock`, `download`, `mismatch` (hash, size,
or reported version), `unpack`, `notice`, `check`, `replace` (the old install
could not be removed, usually a file in use), `unverified`, `missing`,
`stale`, `corrupt`, and `unknown` (raised, for a name the lock lacks).

## What kuu's own `.tools` holds

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted.

```text
.tools/
  msys2/
    ucrt64/        the MSYS2 UCRT64 GCC toolchain, copied as a tree
```

Only the `ucrt64` subtree is needed; the MSYS2 shell, pacman, and the `usr`
tree are not. It brings GNU make (`mingw32-make.exe`) as well as gcc. The
compiler runs from any shell as long as `ucrt64\bin` is on `PATH`, because the
compiler proper (`cc1.exe`, under `lib\gcc`) loads `libgmp`, `libisl`,
`libmpfr`, `libmpc`, `zlib`, and `zstd` from that directory and the driver does
not add it for the programs it spawns. Without it every compile exits 1 and
prints nothing. The `Makefile` sets the path itself and runs its recipes under
`cmd.exe`, so `make` behaves the same from PowerShell, cmd, or Git Bash:

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8
```

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe test
```

The tree in use on 2026-09-09, by MSYS2 package:

| package | version |
|---|---|
| mingw-w64-ucrt-x86_64-gcc | 16.1.0-5 (reports "gcc version 16.1.0 (Rev5, Built by MSYS2 project)") |
| mingw-w64-ucrt-x86_64-binutils | 2.46-3 |
| mingw-w64-ucrt-x86_64-crt | 14.0.0.r47.g0636d42e1-1 |
| mingw-w64-ucrt-x86_64-headers | 14.0.0.r47.g0636d42e1-1 (the headers identify as mingw-w64 15.0) |
| mingw-w64-ucrt-x86_64-winpthreads | 14.0.0.r47.g0636d42e1-1 |

Target triple `x86_64-w64-mingw32`; C runtime UCRT, which every supported
Windows carries as `ucrtbase.dll`, so the executable has no redistributable.

From an existing MSYS2 installation with the packages above:

```bash
robocopy "C:\msys64\ucrt64" ".tools\msys2\ucrt64" /E /MT:16 /R:1 /W:1 /NFL /NDL /NJH /NP
```

Robocopy exits 1 when it copied files; that is success. From nothing: install
MSYS2, run `pacman -S mingw-w64-ucrt-x86_64-gcc` (binutils, crt, headers, and
winpthreads come with it), then copy as above. About 1.1 GB, 42,000 files.

kuu's own compiler is not in a lock, by the owner's decision: kuu does not
build or bootstrap itself, and its repository runs no kuu. The versions above
are a record. The lock is for the repositories kuu drives, and there the rule
is that nothing is shared between projects: a lock points only at upstream
downloads, each project fetches them into its own `.tools`, and each project
carries its own `kuu.exe` there too, copied in by hand.
