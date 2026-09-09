# Toolchain

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted. This page says exactly what `.tools` holds
so that another machine, or another person, can reproduce it.

Projects kuu drives are the same: each fetches its own prerequisites by url
and hash into its own `.tools`, with [`http`](http.md) and
[`archive`](archive.md), and carries its own `kuu.exe` there, copied in by
hand. Nothing is shared between projects, and there is no lock: the agent
knows what a project needs, and kuu gives it the means.

## What `.tools` holds

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

## Populating `.tools`

From an existing MSYS2 installation with the packages above:

```bash
robocopy "C:\msys64\ucrt64" ".tools\msys2\ucrt64" /E /MT:16 /R:1 /W:1 /NFL /NDL /NJH /NP
```

Robocopy exits 1 when it copied files; that is success. From nothing: install
MSYS2, run `pacman -S mingw-w64-ucrt-x86_64-gcc` (binutils, crt, headers, and
winpthreads come with it), then copy as above. About 1.1 GB, 42,000 files.

kuu's own compiler is not fetched by kuu, by the owner's decision: kuu does not
build or bootstrap itself, and its repository runs no kuu. The versions above
are a record.

## Releasing

A release is make, cmd recipes, and two plain C tools, never kuu. Every build
already carries a version resource: `tools/versionrc.c` reads the version
from `src/kuu.h` and writes the `.rc`, `windres` compiles it in, so the file's
properties say what `--version` says.

```bash
.tools\msys2\ucrt64\bin\mingw32-make.exe release
```

`release` signs `build\kuu.exe` with the owner's Certum certificate through
the Windows SDK's signtool, selected by thumbprint and timestamped by Certum,
then verifies the signature and checks that the leaf was issued to the
expected name, then writes `build\kuu.exe.sha256` with `tools/sha256sum.c`.
Signing needs the owner's SimplySign session, so the owner runs it.
`publish` does all that and creates the GitHub Release named after the
version, with both files attached and notes generated from the commits.
`SIGNTOOL`, `SIGN_SHA1`, `SIGN_NAME`, `TIMESTAMP`, and `GH` are make variables
whose defaults fit the owner's machine; `GH` names the gh executable when it
is not on `PATH`.

A project takes a release by copying `kuu.exe` into its own `.tools`, after
checking the download against the sidecar, and states the version it expects
at the top of its `tasks.lua`.
