# Step 04 — shared native traversal

Status: complete. Checking, module inventory and ledger snapshots now use one private collector, with compatible public scopes. Configuration activation and ledger-state migration remain step 05; steps 05–21 are unstarted.

## Implementation

[src/fs_dirs.c](../src/fs_dirs.c) extends the existing handle-based walker behind a private `_scan_native.collect` module registered in [src/state.c](../src/state.c). The public `fs.dirs` interface and result shape are unchanged. The collector decides exact basename and project-relative path exclusions before descent, and returns ordinary file metadata from the same native directory enumeration that discovers subdirectories. It avoids the former second listing of every directory. Collection does not read file contents or stat every file.

The private interface accepts all **265 effective basenames** (256 configured entries plus mandatory/default names) and **256 relative paths**, independent of the public walker's 64-pattern limit. Raw Lua option access and validation happen before resource acquisition. A separate private legacy-pattern option preserves `check.PRUNE` wildcard matching; configured policy rules remain exact and ASCII-case-folded.

[lua/_scan.lua](../lua/_scan.lua) supplies the shared observation: sorted files and errors, native paths/links/exclusions, actual enumerated-directory counts and completeness. Native branch failures, partial results and rejected names remain visible. Deliberate exclusions and non-followed links do not make a scan incomplete. Handle-classification failure does. Explicit starting directories override their own/ancestor exclusions; descendants still match. Starts outside the project keep basename exclusions without applying unrelated project-relative rules.

[lua/check.lua](../lua/check.lua) uses that observation for automatic checking and module inventory. Discovered name-surrogate links remain non-followed, ordinary filter metadata remains observable, and an explicitly supplied linked starting directory is followed. Existing Lua-file ordering, case-sensitive `.lua` suffix matching, result shapes and require resolution are preserved.

[lua/_ledger.lua](../lua/_ledger.lua) constructs its existing relative-path metadata map from the same file rows. It retains initial/final scan summaries internally for step 05. On-disk tree state and record formats are unchanged. Its legacy omission of files directly inside reparse-directory rows is retained until migration can account for coverage changes safely; ordinary descendants remain visible as before.

The public checker/inventory still excludes `.git`, `.tools`, `build` and `node_modules`; the ledger additionally excludes `.kuu`. No public command reads `kuu.config.json` yet. Newly specified generated-directory defaults are exercised directly in collector tests and benchmarks. This prevents an intermediate release from comparing unlike ledger scopes.

## Tests and documentation

- [test/cases/scan.lua](../test/cases/scan.lua): exact matching and boundaries, ASCII/non-ASCII handling, rule limits, metadata reuse, explicit roots, compatible scopes, wildcard overrides, real junctions, real sharing denial, partial-result/rejected-name propagation.
- [test/cases/scan_native.lua](../test/cases/scan_native.lua): 59 checks of native option shapes, strings, bounds, raw metatable access, root errors, metadata parity and public-walker compatibility.
- [test/cases/check.lua](../test/cases/check.lua) and [test/cases/capabilities.lua](../test/cases/capabilities.lua): existing fault-injection tests moved to the collector result boundary. The ordinary test runner includes both new cases.
- [Makefile](../Makefile): builds the existing Windows scan fixture helper for regular tests. Included directories held exclusively produce an incomplete scan; excluded held directories do not get entered; metadata for an exclusively held ordinary file is still collected.
- [docs/scan.md](../docs/scan.md) and [docs/ledger.md](../docs/ledger.md): explain shared traversal, compatibility and the remaining activation/migration boundary. `kuu docs scan` matches the source page.
- [test/scan-profile.lua](../test/scan-profile.lua), [test/scan-repros.lua](../test/scan-repros.lua), [test/scan-collector-bench.lua](../test/scan-collector-bench.lua) and [test/scan-baseline.md](../test/scan-baseline.md): keep old/new evidence comparable and provide a read-only retained-fixture collection benchmark.

Final focused regression suite: **841 checks passed, zero failures, 15.4 seconds**, covering policy, collector/native boundary, fs/paths, checker/corpus/declarations, capabilities, ledger, tasks, docs and error metadata. An earlier pass found three unused globals in the new test; they were removed and the full focused run was repeated successfully.

AddressSanitizer: **469 checks passed, zero failures, 18.0 seconds**, covering the native collector, adapter and affected consumers. Native static analysis passed. The ASAN build contains the final runtime code; the subsequent production rebuild only updated one manual sentence. Static checking of eleven changed/new Lua files reports zero errors and warnings. Independent native/adapter review found no remaining blockers. `git diff --check` passed.

The host cannot create the optional real file-symlink fixture; that skip is explicit. Real directory-junction and exclusive-handle tests passed. Ordinary filter/cloud metadata and partial/rejected-name cases use injected native result rows, not claims about observed cloud hardware or naturally occurring enumeration faults.

```powershell
.\.tools\msys2\ucrt64\bin\mingw32-make.exe -j4 all build/kuu-asan.exe analyze
.\build\kuu.exe test/run.lua scan_policy scan_native scan fs paths check check_corpus fixglobals capabilities ledger task docs palette
$env:PATH = (Resolve-Path '.tools/msys2/clang64/bin').Path + ';' + $env:PATH
$env:KUU_TEST_ASAN = '1'
.\build\kuu-asan.exe test/run.lua scan_native scan fs paths check capabilities ledger
```

Run suites sequentially because their disposable test workspace is shared. The final native build/analyzer log is [here](../build/step04-native-validation-build.log); the production documentation rebuild is [here](../build/step04-build-final.log). Other evidence: [focused tests](../build/step04-focused-tests-final.log), [ASAN](../build/step04-asan-tests.log), [static checks](../build/step04-static-check-final.log), [embedded page](../build/step04-docs-check.log).

## Reproductions and profiling

The migrated reproduction harness completed against both binaries. Signed 0.11 still reproduces all seven original issues. The development build does not reproduce the fixed junction issue; the six ledger issues still reproduce, as expected before step 05. The partial-listing observation now records that injection reached `_scan_native.collect`, and the retained initial/final summaries correctly say `complete=false`. The old executable still uses the `fs.list` injection boundary. This prevents a moved implementation boundary from falsely appearing to fix the defect.

Evidence: [development reproductions](../build/step04-repros-dev.json), [signed 0.11 reproductions](../build/step04-repros-release011.json). Their runtime hashes identify the observed binaries; the development replay preceded the final documentation-only rebuild.

Small end-to-end benchmark/profile smoke runs completed against both development and signed 0.11, with 100 payload files and one warm repetition. The tiny child profile shows exactly one native collection under each of `ledger.open` and `ledger.close`, each enumerating two directories and collecting 66 files. Signed 0.11 instead shows one walk plus two subsequent `fs.list` calls per snapshot. Initial and final snapshots still both occur. Other ledger operations may legitimately list the ledger directory.

Evidence: [development smoke](../build/step04-profile-smoke-dev.json), [signed 0.11 smoke](../build/step04-profile-smoke-release011.json), [compact phase comparison](../build/step04-profile-validation.json). These are harness/integration checks, not an end-to-end performance acceptance claim; that remains step 07.

## Retained 100,000-file fixtures

[The final collector benchmark](../build/step04-collector-benchmark-final.json) reused the step 01 fixture trees without task execution, content hashing, ledger updates or writes into those trees. It checks expected case presence, rejects duplicate cases, verifies stable counts across samples, and records executable/driver/baseline hashes. Output is outside the retained fixture paths. It measures in-process native collection plus Lua adaptation/sorting, excluding policy loading and process startup. Each row retains one first observation and three warm samples; the first is not a controlled cold-cache sample.

Windows 11 25H2 build 26200.6899, x64, 12 logical CPUs. These measurements do not constitute a separate Windows 11 23H2 validation.

| Fixture / scope | Enumerated directories | Collected files | Warm median |
|---|---:|---:|---:|
| Tiny / legacy ledger | 2 | 66 | 2.293 ms |
| Tiny / configured defaults | 2 | 66 | 2.523 ms |
| Generated / legacy ledger | 1,019 | 100,068 | 2,419.421 ms |
| Generated / configured defaults | 5 | 66 | 1.997 ms |
| Unexcluded / legacy ledger | 1,004 | 100,066 | 2,672.031 ms |
| Unexcluded / configured defaults | 1,004 | 100,066 | 2,389.997 ms |
| Pruned control / legacy ledger | 2 | 66 | 1.497 ms |
| Pruned control / configured defaults | 2 | 66 | 1.649 ms |

The generated-tree contrast measures the benefit of changing observation scope on the same collector, not a speedup caused solely by replacing the old traversal. Large unexcluded trees still require work proportional to their visible entries. Timing differences at equal counts are observations from this short run, not statistically established improvements. Public commands keep legacy scopes until step 05.

```powershell
.\build\kuu.exe test/scan-collector-bench.lua --baseline build/step01-bench-100k.json --out build/NEW-collector-benchmark.json --repeats 3
```

The initial run is retained separately as [step04-collector-benchmark.json](../build/step04-collector-benchmark.json); the final run adds stricter evidence/provenance checks and uses the final production executable. Generated evidence is ignored build output and must be retained before cleaning the build directory.

Final development executable SHA-256:

`e2ffe1ae0c8c84d7478eb1de1f391bb46de977bbe123bfb7eab97fd758c94137`

Signed baseline remains unchanged at `build/release-011-download/kuu.exe`, SHA-256:

`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`

## Time and next step

Work began at 2026-09-15 21:19:22 UTC. Actual wall time was **about sixteen minutes**, below the **45–90 minute** forecast. Native implementation, test development and independent review ran in parallel; builds and shared-workspace tests were coordinated sequentially.

The next executable step is **05: validated ledger state, safe scope migration, incomplete-scan handling and guarded publication**, followed by activation of the shared defaults/configuration. No version, signing, release, commit or push was performed. FlowNet was not modified or executed.
