# Step 02 — automatic checking respects directory links

Status: complete. Automatic checking, fixing and module inventory now honor the native walker's decision not to enter discovered directory links. Steps 03–21 remain unstarted.

## Change and contract

`fs.dirs` includes discovered directory links in `paths` and records its refusal to enter them as `action = "nofollow"` in `links`. The checker previously called `fs.list` for those paths anyway, following their targets. The shared Lua collector now builds a set of these paths and skips listing them. Both `check.tree` and `check.modules`, and consequently `kuu check --fix` and capabilities inventory, use this collector.

The test is the walker's **action**, not its reparse flag or surrogate bit. That preserves ordinary cloud/filter metadata and deliberately followed roots, and handles name-surrogate tags such as DFS whose reported surrogate bit can be false. Native directory-handle checks are unchanged. Discovered file symlinks already have `kind = "link"` and remain excluded by the existing file-only condition.

Existing explicit-target behavior is preserved and documented:

- `check.tree` and `check.modules` follow an explicitly supplied linked starting directory, while skipping links discovered beneath it.
- A CLI argument naming a link itself is still rejected with `CHECK notfound`.
- An explicitly named ordinary file or subdirectory beneath a linked ancestor can still be checked, including deliberate fixing.

This is a discovery rule. Literal require analysis may read module text through linked ancestors, and it is not filesystem confinement against concurrent ancestor replacement. Intentionally excluded links do not create read errors or make an inventory incomplete.

Files changed:

- [lua/check.lua](../lua/check.lua): collector fix and API comments.
- [test/cases/check.lua](../test/cases/check.lua): junction/fixing/inventory/explicit-target regressions and metadata-contract cases; complete existing filesystem mocks.
- [test/cases/capabilities.lua](../test/cases/capabilities.lua): real junction coverage for JSON and text inventory; complete an existing filesystem mock.
- [docs/check.md](../docs/check.md), [docs/capabilities.md](../docs/capabilities.md): discovery and explicit-target behavior.
- [docs/fs.md](../docs/fs.md): correct the walk-and-list recipe to honor `nofollow`, using an unlimited walk so a depth frontier is not mistaken for permission to enter a link.

## Validation

The new check/capabilities regressions were first run against the unchanged signed 0.11 download. They produced **144 passing checks and 12 failures**, demonstrating that the cases detect the existing defect. Some failed assertions are downstream consequences of the same outside-target modification; they are not 12 separate defects. Evidence: [step02-baseline-regressions.log](../build/step02-baseline-regressions.log).

The rebuilt development runtime passed **515 checks, zero failures, in 17.7 seconds** across `check`, `check_corpus`, `fixglobals`, `capabilities`, `fs`, `docs`, `ledger` and `task`. Evidence: [step02-focused-tests.log](../build/step02-focused-tests.log).

```powershell
.\.tools\msys2\ucrt64\bin\mingw32-make.exe -j4 all fixtures
.\build\kuu.exe test/run.lua check check_corpus fixglobals capabilities fs docs ledger task
.\build\kuu.exe check lua/check.lua test/cases/check.lua test/cases/capabilities.lua
```

Static checking passed: **three files, zero errors or warnings**. `git diff --check` passed. The build succeeded; [final build log](../build/step02-build-final.log) and [static-check log](../build/step02-static-check.log) are retained. An independent review of the collector, native semantics, documentation and new tests found no remaining correctness issue.

The step 01 reproduction harness was also run after the code fix: **junction-check-fix no longer reproduced**, while all six deferred ledger observations still reproduced. Evidence: [step02-repro-results.json](../build/step02-repro-results.json). That report identifies the build before the final documentation rebuild; the 515-check run exercised the final build.

Real junctions at the project root and beneath an ordinary directory verified that outside sentinels remain byte-for-byte unchanged. Tests also verified that ordinary in-project content is still repaired, explicit linked-root APIs work, and capabilities excludes outside modules without claiming incomplete inventory.

Windows refused creation of a real file symlink on this host, so that optional OS case explicitly reports a skip. Mandatory metadata tests still cover file-link exclusion, filter-backed files/directories and `nofollow` with `surrogate = false`. Real cloud-provider and DFS environments were not required or simulated as OS evidence; those distinctions are tested at the existing native/Lua metadata boundary.

Host: Windows 11 25H2, build 26200.6899. This step did not rerun a Windows 11 23H2 compatibility gate; no native code or API was changed. FlowNet was not modified or executed.

Final development executable SHA-256:

`a9ddce99e00d0797aca1029fd7baebdc5355412ec4deaec1a9829a828d108a6c`

The retained signed baseline at `build/release-011-download/kuu.exe` remains unchanged:

`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`

No version bump, signing, commit, push or publication was performed. Generated logs and reports remain ignored build artifacts. The next step is **03: define and validate declarative scan configuration**.

## Time and forecast

Work began at 2026-09-15 21:00:48 UTC; final evidence validation completed at 21:05:15 UTC. Actual agent wall time was **about five minutes**, below the **15–30 minute** forecast. The existing native traversal contract made this a small Lua correction; most of the work was regression coverage and clarifying documentation. Keep later step forecasts unchanged: shared traversal and concurrent ledger publication are substantially broader changes, so this step is not a basis for scaling all estimates down.
