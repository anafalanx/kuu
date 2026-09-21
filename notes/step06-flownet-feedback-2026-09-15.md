# Step 06 — scope, completeness and phase timings

Status: complete. Step 07 (milestone acceptance and full benchmarks) remains next; steps 07–21 have not started.

## Public behavior

`kuu run`, `kuu check` and `kuu capabilities` now accept `--timings`, which emits one phase summary on stderr. Normal human output has no timing summary unless requested. JSON reports always carry additive `result.timings` fields; the option leaves JSON stdout intact. The option appears in command help, top-level help and the embedded manual. Runner flags belong before the task name; a later `--timings` is still a task argument.

Reports expose normalized scope, configuration-file/default provenance, effective mandatory/default/custom exclusions and the scope fingerprint. Actual scans include their project and starting roots, completeness, metadata-file count, enumerated/excluded directory counts, non-followed link count, diagnostics and collection duration. Counts distinguish all collected files from checked/inventoried Lua files. Explicit starts outside the project disclose that relative subtree rules did not apply. Direct checker API legacy wildcard additions are disclosed separately from the configured fingerprint.

`run` exposes its actual initial/final scans. A record failure retains initial evidence even if it prevents final publication. `check` retains each actual directory scan, including a post-fix recheck; an explicit-file-only check has an empty scan array. Missing later path arguments preserve earlier reports and scans in the failure envelope. Initial path-selection failure prevents fixer writes. Checker/module completeness also covers subsequent source reads, while scan completeness describes metadata collection only. Syntax errors alone do not make observation incomplete.

Shared types and boundaries are documented in [scan](../docs/scan.md), with command-specific schemas in [task](../docs/task.md), [check](../docs/check.md), [capabilities](../docs/capabilities.md), and compatibility information in [ledger](../docs/ledger.md).

## Timing contract

All values are elapsed wall-clock seconds; phases that did not run are omitted rather than invented as zeros.

| Command | Phases |
|---|---|
| `run` | setup, initial scan, final scan, ledger work excluding those scans, execution, total |
| `check` | setup, collection, checking, fixing when attempted, total |
| `capabilities` | setup, inventory, ledger-tail reading, ledger verification, total |

Phases are diagnostic and can overlap. Checking contains collection. Execution sums the existing task durations once; child time is already nested, and child observer recording can overlap ledger work. Inventory includes metadata collection and static export extraction. Ledger scan duration also includes construction of its metadata snapshot map.

The new total begins just after loading the timing helper, before other command imports, and ends after command work and report preparation. It includes ledger finalization and checker rechecks, but excludes OS/runtime startup before command entry and final serialization/emission/flushing. Earlier streamed run events remain inside command work. There is no promised bound between this measurement and an external stopwatch. Existing task, child and ledger verb `seconds` keep their old boundaries; in particular the verb record still precedes final baseline publication.

Reportable failures retain reached phases and partial evidence. Dry runs report setup and total without inventing execution, ledger or scan work. Help/parser exits retain their existing output conventions. The private [timing helper](../lua/_timings.lua) records elapsed time across yielded calls and exceptions without changing their returned values or error object.

## Validation

The new [reporting tests](../test/cases/reporting.lua) provide **50 checks**, including controlled slow manifest/scan/child/record calls, finalization inclusion, unchanged task/child durations, JSON compatibility, opt-in stderr output, dry runs, configuration/task/record failures, retained partial checker output, real Windows sharing denial and separate inventory/verification timing. Timing assertions use deliberate delays to establish boundaries, not arbitrary small-command performance thresholds.

The focused regression suite passed **1,030 checks, zero failures, in 22.6 seconds**. Relevant AddressSanitizer coverage passed **508 checks, zero failures, in 45.8 seconds**. A subsequent help-only synchronization changed three native usage strings and the index page; the final executable passed **94 entry/manual checks**, and the matching sanitizer entry/manual checks also passed. No native runtime algorithm changed in this step.

Nine changed/new Lua files passed static checking with **zero errors and warnings**. All **48 embedded manual pages** match their source. Independent implementation and documentation reviews found no remaining correctness blocker. `git diff --check` passes.

Retained evidence:

- [Final build](../build/step06-build-final.log), [focused regression](../build/step06-focused-final.log), [sanitizer regression](../build/step06-asan-final.log), [final entry/manual checks](../build/step06-help-final.log), [sanitizer entry/manual checks](../build/step06-asan-help-final.log).
- [Static checks](../build/step06-static-validation.log), [embedded-manual comparison](../build/step06-embedded-docs.log).
- [Final defect replay](../build/step06-repros-final.json): all seven earlier defects remain **not reproduced**, with positive acceptance prerequisites and zero harness errors, including the controlled two-process stale-publication interleave.
- [Reporting examples](../build/step06-report-example.json): six successful default/configured run/check/capabilities samples from a disposable project, carrying the final executable hash. JSON parsing and timing output on stderr were verified. External wall readings are functional evidence, not performance acceptance measurements.

The initial reporting run exposed two fixture mistakes (a non-resolvable module name expectation and lost child-script quoting); both were corrected. The declaration invariant then removed one unused global from the new test. The final checks above pass. Optional file-symlink coverage remains host-dependent as recorded in earlier steps; actual junction and sharing-denial fixtures passed.

Reusable commands, from the repository root:

```powershell
.\.tools\msys2\ucrt64\bin\mingw32-make.exe -j4 all build/kuu-asan.exe
.\build\kuu.exe test/run.lua reporting ledger ledger_state scan_policy scan_native scan scan_activation check check_corpus fixglobals capabilities task docs palette fs paths sync
$env:PATH = (Resolve-Path '.tools/msys2/clang64/bin').Path + ';' + $env:PATH
$env:KUU_TEST_ASAN = '1'
.\build\kuu-asan.exe test/run.lua reporting ledger ledger_state scan_activation check capabilities task
.\build\kuu.exe test/scan-repros.lua --exe build/kuu.exe --fixture build/test/scan_fixture.exe --out build/step06-repros-final.json
```

Run shared test suites sequentially. Build evidence is ignored output and should be retained before cleaning. Validation used Windows 11 25H2 build 26200.6899, not a separate 23H2 host. Final development executable SHA-256:

`449025f6c250af9f5205dc6c17259d8e210e0507d5278b9d0bcec1c9972f7bdf`

Signed 0.11 baseline remains unchanged at `build/release-011-download/kuu.exe`, SHA-256:

`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`

Work began **2026-09-15 21:53:24 UTC** (local execution crossed into September 16). Actual execution took **about thirteen minutes**, below the **25–45 minute** forecast. Command implementation, tests and independent review ran in parallel; shared regression suites ran sequentially.

Next is **step 07: milestone 1 acceptance**, including the full before/after benchmark, 100,000-file generated and unexcluded controls, warmed distributions and remaining ledger costs. This step makes those costs visible but does not claim that performance acceptance. No signing, release, version change, commit or push was performed. FlowNet was neither modified nor executed.
