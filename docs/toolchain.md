# Toolchain

kuu stands alone: everything needed to build it lives inside this checkout,
under `.tools/`, which git ignores. Nothing is installed on the machine and no
other project's tools are consulted. This page says exactly what `.tools` holds
so that another machine, or another person, can reproduce it.

Projects kuu drives are the same: each fetches its own prerequisites by url
and hash into its own `.tools`, with [`http`](http.md) and
[`archive`](archive.md), and carries its own `kuu.exe` directly in the
project root, copied in by hand. Nothing is shared between projects, and there is no lock: the agent
knows what a project needs, and kuu gives it the means.

## What `.tools` holds

```text
.tools/
  msys2/
    ucrt64/        the MSYS2 UCRT64 GCC toolchain, copied as a tree
    clang64/       the separately pinned, test-only AddressSanitizer toolchain
```

Production builds need only the `ucrt64` subtree; the MSYS2 shell, pacman,
and the `usr` tree are not needed. It brings GNU make (`mingw32-make.exe`) as well as gcc. The
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

Each build checks the complete embedded Lua/manual file set, including added
and deleted files. The C generator writes a temporary payload and replaces
the previous output only after successful reads and writes. Identical output
keeps its timestamp, avoiding unnecessary recompilation; a failed generation
is retried on the next build.

Target triple `x86_64-w64-mingw32`; C runtime UCRT, which every supported
Windows carries as `ucrtbase.dll`, so the executable has no redistributable.

### The UCRT64 pins

The production tree is unpacked from these 18 MSYS2 packages, fetched on
2026-09-13 from the [MSYS2 UCRT64 mirror](https://mirror.msys2.org/mingw/ucrt64/)
and checked against the SHA-256 each
[package page](https://packages.msys2.org/packages/mingw-w64-ucrt-x86_64-gcc)
publishes before extraction. They are gcc's complete runtime closure plus
GNU make; `cc-libs` is a virtual dependency that `gcc-libs` provides. The
same day, the complete gate — suite, `asan`, `analyze`, `fuzz`, `soak` —
passed under this tree before it replaced the previous one.

Until then the tree was a robocopy of a live MSYS2 install carrying gcc
16.1.0-5, recorded by version only: 42,000 files, of which the 6,384 in this
closure are the ones a build touches. That compiler had already left the
mirror, which keeps only current versions, by the time anyone tried to obtain
it again. The archives are retained so that this cannot happen twice.

For each row, the download name is
`mingw-w64-ucrt-x86_64-<package>-<version>-any.pkg.tar.zst`, below the mirror
URL above. Keep the archives under `.tools/downloads/ucrt64`. Download the
exact versions, compare `certutil -hashfile <archive> SHA256` with the table,
then unpack each verified archive with Windows' own tar, which reads zstd —
`C:\Windows\System32\tar.exe -xf <archive> -C .tools\msys2 ucrt64` — taking
only the `ucrt64` member so the package's own metadata files are left out. Do
not run package scripts. The first check is
`.tools\msys2\ucrt64\bin\gcc.exe --version`, which must report
`gcc.exe (Rev3, Built by MSYS2 project) 16.2.0`.

| package | version | SHA-256 |
|---|---|---|
| gcc | 16.2.0-3 | `1cd86e5817f6e0d7310d7cb2bb91f4a55e1256cb4ce580a0c5f2a74e013d144d` |
| gcc-libs | 16.2.0-3 | `5763fabf86fa13a4449ee765006d3446384ed66af7bf827459710eb777e0b11c` |
| binutils | 2.47-3 | `ba98af202fe71e0884bb51daf78ce10bd8a51c69528c700dcf5855e6ece06dd3` |
| crt | 14.0.0.r375.g9c1abbbf5-1 | `09bccbb31c7bdc9090358cac429a78b8bffe5142a98a1e1d54f5b869f3068055` |
| headers | 14.0.0.r375.g9c1abbbf5-1 | `046cc32a88739738e94976486ace1e8e457e6beb6ae866de2f07d2d3eebcabb6` |
| winpthreads | 14.0.0.r375.g9c1abbbf5-1 | `3cdd84d957e4bb8b5a30df548afd82b97a52fedc77974a43debd1d0685ed669c` |
| libwinpthread | 14.0.0.r375.g9c1abbbf5-1 | `61d340fe8eebc77ee821badca246827fe90545e99685e503bdea16a8d25df512` |
| gmp | 6.3.0-2 | `e82a75968a556484a50084578238a84eb60fb93e34986fd6695c537975bd39ea` |
| isl | 0.28-1 | `8594e01a253d5a72646c586cf5a1626c1b1c2be7c30060fe67abd9bebe3fe223` |
| mpc | 1.4.1-1 | `f06556e811c711ce91609484e31d358e4f495811ba29813bf2284a3b236d82ce` |
| mpfr | 4.2.2-3 | `6b70a275d2ec75c70aa50a236c218e6b7ee9a5ab4c6d52cb0b580267b7d200fe` |
| zlib | 1.3.2-2 | `841401182976d2f9e17e5c0ebaac51f2a8014140ea53d67625e91c8fb3c85ea0` |
| zstd | 1.5.7-2 | `dbdb8427280046a2b41697780aa4c52983b708082b0da4755951dc3bea96ca89` |
| windows-default-manifest | 20260815-1 | `b39039f754a600cc0dec49df7d675a59a3cb2b63691d91b4ae60735ee7075eca` |
| make | 4.4.1-5 | `871f760657a360279f29b945a7fd7d9655fe46a3e1e06dd783c9e74514aa0b27` |
| gettext-runtime | 1.0-1 | `ba693dda4ac375af76ce481ff3a6e7481286546cc7dc6d56c7021dae34084157` |
| tzdata | 2026c-1 | `b6af6fd6acb676b9bb0761b75b1d8330b89abd4c8d467fda35cee8925b170db9` |
| libiconv | 1.19-1 | `9a500f38c2b91808741c62fae746b3e9110b33a1ecf5c30fa0c66dbedddf7e16` |

## Populating `.tools`

From the pinned archives, as above: 18 downloads, 70 MB, verified, unpacked
into `.tools/msys2/ucrt64`. No MSYS2 install and no pacman are involved.

kuu's own compiler is not fetched by kuu, by the owner's decision: kuu does not
build or bootstrap itself, and there is no tool in the repository that fetches
or verifies these archives — the table is the record, `certutil` is the
check. Only verification targets run the built executable.

## Verification

Run the complete production gate from the checkout root:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8 gate
```

`gate` runs the regression suite, `asan`, `analyze`, `fuzz`, and `soak` in
that order, stopping at the first failure. Recursive makes keep these stages
sequential even with `-j8`: the suite and soak share scratch files. Each
stage is also available separately (`test`, `asan`, `analyze`, `fuzz`,
`soak`). `asan` is inside the gate since 0.10.0; before that it was described
as a required release check and run by hand, and on 2026-09-12 its build was
found 22 commits stale. `SOAK` defaults to
60 seconds; `FUZZ` and `FUZZ_SEED` below are inherited by the gate.

`analyze` compiles all authored `src/*.c` files separately into `build/analyze`
with GCC's `-fanalyzer`, no optimization, and the normal warning-as-error gate.
It does not analyze vendored libraries or claim to prove memory safety.

`fuzz` defaults to 10,000 cases per parser family for each of three fixed
seeds: 1, 12648430, and 3735928559. It checks durations, dates/zones, lexical
paths, Windows command-line quoting, CSV decoding, INI decoding and edits,
JSON decoding, and registry key text. Inputs include arbitrary bytes,
mutated boundary cases, valid Unicode, independently known arithmetic, and
round trips. Native quoting is compared with `CommandLineToArgvW`; batch
quoting also checks newline rejection. CSV fields and exact JSON integers
have round-trip checks; INI edits must return the requested value after
decoding. Registry inputs only go to `reg.exists`: no registry keys or
values are written. Fuzzed strings are never executed as commands or opened
as filesystem paths. Each worker has a five-minute
deadline; any crash, nonzero exit, timeout, or truncated output fails the gate.

For a longer run or a deterministic replay:

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe fuzz FUZZ=100000 FUZZ_SEED=12648430
```

Assertion failures print the seed, case, and input bytes in hexadecimal.
A native crash or deadline failure identifies the worker and seed; rerun
that seed, reducing `FUZZ` to narrow the failing prefix if needed. The gates
are bounded regression tools, not coverage-guided fuzzing.

## AddressSanitizer

GCC remains the production compiler. `make asan` builds a separate
`build/kuu-asan.exe` with Clang, `-fsanitize=address`, debug information,
frame pointers, and `-O1`, then runs the full regression suite with that
executable. Every authored and vendored native object is instrumented;
objects and generated payloads stay under `build/asan`. Build helpers and
external test fixtures still use GCC. No kuu is used to build either runtime.

```text
.tools\msys2\ucrt64\bin\mingw32-make.exe -j8 asan
```

This is a test executable, with a dependency on CLANG64's
`libclang_rt.asan_dynamic-x86_64.dll`; it is never signed or released.
The target adds the local `clang64/bin` to its own process environment so
the DLL and `llvm-symbolizer` are found, including by child kuus. No machine
environment variable changes. The two existing printf wrappers are exempt
from Clang's annotation suggestions only; GCC's warning gate is unchanged.
The target sets `KUU_TEST_ASAN=1` for the suite: its deliberate crash probe
must reach ASAN's exception reporter instead of kuu's production handler.
The production suite continues to require kuu's diagnostic and exit code 3.
ASAN detects memory access errors on exercised paths. It does not establish
race freedom, correct Win32 handle ownership, or coverage of unexecuted paths.

### The CLANG64 pins

These 17 packages were fetched on 2026-09-10 from the
[MSYS2 CLANG64 mirror](https://mirror.msys2.org/mingw/clang64/) and checked
against SHA-256 values published on their MSYS2 package pages before
extraction. They include Clang's complete runtime dependency closure;
`libc++` provides the `cc-libs` dependency. Only this test toolchain uses them.
The [Clang package metadata](https://packages.msys2.org/packages/mingw-w64-clang-x86_64-clang)
links to each dependency's package page and published checksum.

For each row, the download name is
`mingw-w64-clang-x86_64-<package>-<version>-any.pkg.tar.zst`, below the mirror
URL above. Keep the archives under `.tools/downloads/clang64`. Download the
exact versions, compare `certutil -hashfile <archive> SHA256` with the table,
then unpack each verified archive with
`tar -xf <archive> -C .tools/msys2 clang64`. The package's `clang64/` tree
lands alongside `ucrt64/`; do not mix the two trees or run package scripts.
The first check is `.tools\msys2\clang64\bin\clang.exe --version`, which
must report 22.1.8 and target `x86_64-w64-windows-gnu`.

| package | version | SHA-256 |
|---|---|---|
| clang | 22.1.8-2 | `4eb99c39d1ade53dc55362c7c334265e629b84270dbe474377900330e0b81a5d` |
| clang-libs | 22.1.8-2 | `335106bd756266322d8beb2d55ac650dafa339f470e6932c3490ba242022149a` |
| compiler-rt | 22.1.8-2 | `840675b14938bed10d982529e7312a8e1cfa9503b438ee73a3efe2559440f586` |
| crt | 14.0.0.r353.g6df76fa52-4 | `f34cec18643c421aeb606bddd887514bd69950a6be2c669aec7e5ef0d94e8c89` |
| headers | 14.0.0.r353.g6df76fa52-2 | `e8cbff539567875775a2d8145da0c34c38deaf88766b8336c21040b3e262095d` |
| lld | 22.1.8-2 | `db67211e280929e20c0908f90c48a426281b0b39bc30687ce31af93ad8b7b571` |
| llvm-tools | 22.1.8-2 | `c176f89d38a5a36ceb7461416d7a8aefef4a3cb8642c104dcba9ad274c174e47` |
| winpthreads | 14.0.0.r353.g6df76fa52-2 | `0a8ea5b96e89b0dc7de55e50f7a980593c2559f0ea2ab6c952ea996b373bdec8` |
| llvm-libs | 22.1.8-2 | `63d87b17d6e249cb90c8cf1decaff6a3ad944b8551d5342b8b9b329c01a12318` |
| zlib | 1.3.2-2 | `96d8db2f2bf24c0d4e82b899d50a3497d97536a8bd38ce275401d0f2b9580b5e` |
| zstd | 1.5.7-2 | `2d75c4ddf8f4f7b76fe33e3f1eea16450f9b3aede14285c886462d72f0ffd87d` |
| libwinpthread | 14.0.0.r353.g6df76fa52-2 | `2ff874bf57f71a9192bc39cb0227f87021576ee5f98878f740dd3ef8057fc705` |
| libc++ | 22.1.8-1 | `de0bd1b9d62f81b6ac06ea915af8da3fbd63e6705e1bb62ef3f553d1e5fbe4ef` |
| libffi | 3.8.0-1 | `4d27339b52eabae86a1dff79cf432191ad8dd6acfa653b1179b12490234c66a6` |
| libxml2 | 2.15.4-1 | `61de987a3655c1bc81ea50ee1bdc6ac91836d96e91115ba8afdb82283272f6d8` |
| libunwind | 22.1.8-1 | `1427583ab43306045b06df71e4a31686d5848bddabba628ea1b8068f38dbd5fd` |
| libiconv | 1.19-1 | `26c4ac9f2023eecdfffb291cab40c60585a0cd0f72539ca03c5558f3ecd309ec` |

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
`publish` first runs `gate`, then signs and hashes only after the gate passed
and the tree was checked for uncommitted changes. It creates the GitHub Release named after the
version, with both files attached and notes generated from the commits. The
release is bound to the commit the tree was built from: the tag is created on
`HEAD`, which must already be pushed, and a tree with uncommitted changes is
refused.
`SIGNTOOL`, `SIGN_SHA1`, `SIGN_NAME`, `TIMESTAMP`, and `GH` are make variables
whose defaults fit the owner's machine; `GH` names the gh executable when it
is not on `PATH`.

A project takes a release by copying `kuu.exe` directly into its root, after
checking the download against the sidecar, and states the version it expects
at the top of its `manifest.lua`.

Before publishing a release:

1. Run `make gate` on the final sources and review every stage's result.
2. Resolve every sanitizer finding from the gate's ASAN stage. `make asan`
   also runs that stage independently when investigating a failure.
3. Commit and push the tested tree. Run `make publish GH=<gh.exe>`; it repeats
   the production gate before signing and publishing that commit.
4. Verify the release tag, signed executable, and SHA-256 sidecar, then run
   the exerciser with a copy of the released executable.
