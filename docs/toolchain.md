# Toolchain

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted. This page says exactly what `.tools` holds
so that another machine, or another person, can reproduce it.

## What `.tools` holds

```text
.tools/
  msys2/
    ucrt64/        the MSYS2 UCRT64 GCC toolchain, copied as a tree
```

Only the `ucrt64` subtree is needed; the MSYS2 shell, pacman, and the `usr`
tree are not. The compiler runs from PowerShell or any shell as long as
`ucrt64\bin` is on `PATH`, because the compiler proper (`cc1.exe`, under
`lib\gcc`) loads `libgmp`, `libisl`, `libmpfr`, `libmpc`, `zlib`, and `zstd`
from that directory and the driver does not add it for the programs it spawns.
Without it every compile exits 1 and prints nothing. `tools/build.ps1` sets the
path itself.

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

## What is pinned and what is not

By the owner's decision the toolchain is not yet pinned by hash. The versions
above are a record, not a lock, and `tools/build.ps1` accepts whatever gcc it
finds. A lock with URLs and hashes, hydrated by kuu itself, is the third
milestone's job; when it lands, the intended first entry is a snapshot archive
of this `ucrt64` tree, so a stranger rebuilds with exactly the compiler that
made a release.
