# Step 09 — native file-attribute API

Status: **complete**. Implemented the [Step 08 contract](step08-flownet-feedback-2026-09-21.md)
in the unreleased development tree based on release 0.11. The
[sequential plan](plan-flownet-feedback-2026-09-15.md) continues with Step 10:
recursive cleanup, including readonly directories and bounded retries. That
step has not started. No commit, push, signing, release or version change was
performed. FlowNet was not modified or executed.

## Delivered behavior

```lua
local fs = require "fs"
local flags = assert(fs.attributes("example.txt"))
assert(fs.set_attributes("example.txt", { readonly = false, hidden = true }))
assert(fs.set_attributes("target-link", { archive = true }, { follow = true }))
```

`fs.attributes` returns a detached seven-field snapshot: the complete unsigned
32-bit Windows mask in `attrs`, and boolean `readonly`, `hidden`, `system`,
`archive`, `temporary` and `not_content_indexed` fields. The setter accepts
only those six named booleans, preserves unspecified native bits, normalizes
`FILE_ATTRIBUTE_NORMAL`, and returns true on success. It does not create paths.

Both APIs default to `follow=false` for the final path component. Explicit
following selects the target; linked ancestors may still be traversed. The
setter reads and writes the same handle, preserving object identity across a
rename without promising an atomic merge with another attribute writer.
Fresh zeroed `FILE_BASIC_INFO` time fields avoid restoring stale timestamps;
the filesystem may still advance metadata change time.

An empty patch queries with read-attributes access only, without testing write
permission. Every nonempty patch requests write-attributes access, including
an already-satisfied patch; unchanged masks skip the native write. A directory
patch containing `temporary=true` fails before any mutation.

Validation uses exact raw table keys and actual booleans, ignoring inherited
fields and metatable callbacks. Unknown/numeric/NUL-containing keys raise
`FS usage`; invalid boolean values raise `FS badvalue`; wrong argument types
raise ordinary Lua argument errors. Existing path validation is preserved:
empty, NUL-containing and refused path spellings raise `FS badvalue`, while
invalid UTF-8 raises `FS encoding`. This clarifies Step 08's broad reference
to malformed paths without changing the path helper.

After successful validation, environmental failures return `nil, err`.
Followed permission failures stay `FS access`. Dangling-link diagnosis only
follows an original Windows error 2 or 3 and confirmation of a final
name-surrogate reparse object; the original native error number remains in
the message. Handles and native buffers are released before constructing
Lua errors or result tables. Existing `fs.stat` defaults and its opener are
unchanged.

Implementation: [src/fs.c](../src/fs.c). Public contract and discovery:
`kuu docs fs file-attributes`, [filesystem manual](../docs/fs.md),
[PowerShell mapping](../docs/powershell.md), and the explicit unreleased
section of [upgrading from 0.11](../docs/upgrading-0.11.md). The signed 0.11
release does not contain these APIs. The manual bundle and generated figures
were refreshed from 48 documentation pages.

The palette describes both functions and the `Attributes` record. Static
checking recognizes their names and `follow` options at arguments 2 and 3,
respectively. Setter patch keys are validated at runtime; this step does not
add patch-shape checking or inference of returned local record fields.

## Independent validation

The new [native fixture](../test/fixtures/attributes_fixture.c) creates and
inspects Windows state independently of kuu's getters/setters. It is built
by the Makefile's `fixtures` target and used by the registered
[attribute suite](../test/cases/attributes.lua). The fixture owns a fresh
marked directory, confines setup and ACL changes to its children, and retains
its small fixture tree. The ACL child saves/restores descriptors on release
or its bounded timeout; a Lua close guard releases it on assertion failures.

The 152 attribute assertions cover:

- All six file flags and five applicable directory flags, complete raw masks,
  detached snapshots, partial patches, clearing flags, NORMAL normalization,
  and preservation of independently created SPARSE state.
- Directory TEMPORARY rejection without a partially applied mixed patch,
  unchanged contents and ordinary file times, and no metadata-time write for
  empty/already-satisfied patches.
- Unicode and extended paths, missing paths without creation, raw-table and
  strict-boolean validation, exact key lengths, malformed paths and UTF-8.
- Junction object versus target updates, dangling junctions, linked ancestors,
  read-data denial with metadata access, actual read-attributes denial,
  write-attributes denial, and successful ACL restoration.

Real file, directory and dangling-file symlink cases report **three explicit
skips**, because native creation is denied with Windows error 1314. Junction
tests ran; they are not counted as symlink coverage. The broader checker
suite separately reports its existing real-file-symlink skip. Host policy
and privileges were not changed.

Independent source review checked raw validation, resource lifetimes, rights,
same-handle mutation, mask normalization, timestamps and error classification.
The earlier Step 08 OS probe established rename/replacement and intervening
timestamp behavior; this step's API tests do not claim a deterministic
concurrent-rename test through the public call.

| Check | Result | Evidence |
|---|---|---|
| Final normal regression, 19 relevant suites | **974 passed, 0 failed, 36.1 s** | [normal log](../build/step09-tests-final.log) |
| Final AddressSanitizer regression, 14 relevant suites | **840 passed, 0 failed, 55.8 s**, no sanitizer diagnostics | [ASAN log](../build/step09-asan-final.log) |
| Strict normal and ASAN builds; GCC analysis of `src/fs.c` | Passed | [validation build](../build/step09-build-validation.log), [final build](../build/step09-build-final.log) |
| GCC `-fanalyzer`, `-Wall -Wextra -Werror` on native fixture | Passed | [fixture analysis log](../build/step09-fixture-analysis.log) |
| Static checking of palette and three changed test files | **0 errors, 0 warnings** | [JSON result](../build/step09-static.json) |
| Manual generation, embedded retrieval, docs search, palette/capabilities consistency | Passed | [bundle generation](../build/step09-bundle-final.log), normal regression |
| `git diff --check` | Passed | Local working-tree check |

The final runs supersede an initial integration-test failure: that test
incorrectly expected the current checker to infer returned local record
fields. It was corrected to check supported behavior, without expanding the
checker implementation. The retained initial log is not counted as a pass.

Commands from the repository root (run the suites sequentially because the
runner shares `build/test-work`):

```powershell
& .tools/msys2/ucrt64/bin/mingw32-make.exe -j4 all build/kuu-asan.exe fixtures build/analyze/fs.o
& .\build\kuu.exe test/run.lua attributes fs paths err docs bundle palette check check_corpus capabilities task ledger ledger_execution execution_acceptance scan_native scan_activation reporting entry embed
$env:PATH = (Resolve-Path '.tools/msys2/clang64/bin').Path + ';' + $env:PATH
$env:KUU_TEST_ASAN = '1'
& .\build\kuu-asan.exe test/run.lua attributes fs paths err check check_corpus capabilities task ledger ledger_execution execution_acceptance scan_native scan_activation reporting
```

Host: Windows 11 **25H2, build 26200.6899**, x64, unelevated, local NTFS.
These are not separate Windows 11 23H2, SMB, ReFS or cloud-provider results.
This step does not change startup or automatic observation behavior, so the
Step 07 performance measurements were not repeated. Step 21 retains the
full-project readiness gate.

Final `build/kuu.exe` SHA-256:
`125c604ce94dcd54536f8fa65165ecb4c8964fcb88d657647095c51957e9ea76`.

Source SHA-256 values at validation:

- `src/fs.c`: `1e1905a6b2b3fa2db0f43f12d57b469f37f01028074ba570caf863cb5f4cae33`.
- `test/fixtures/attributes_fixture.c`: `c152fe74e89ffe8f5804b2a5124da440befcd44e7fbe1634567ab0d177abb912`.

Work began **2026-09-21 17:50:11 UTC** and took approximately **13 minutes**,
against the **40–75 minute** forecast. The settled native contract and parallel
implementation/test/documentation work shortened this step. Step 10 remains
**30–50 minutes**; remaining Steps 10–21 total **4 h 55 min–9 h 15 min** under
the existing forecasts.
