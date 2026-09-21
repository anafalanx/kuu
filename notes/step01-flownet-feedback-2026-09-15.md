# Step 01 — scan baseline and defect reproductions

Status: complete. The baseline, phase profiles and seven repeatable defect observations meet step 01's acceptance conditions.

Scope: baseline tooling and evidence only. No production C/Lua module, embedded documentation, executable, release or FlowNet file was modified. FlowNet was consulted read-only at commit d480b35d9f6b76ba6e7f62dfff6de980f19c35a4. Steps 02–21 remain unstarted.

Work started at 2026-09-15 20:25:38 UTC; final validation completed at 20:57:35 UTC. Actual agent wall time: **about 32 minutes**, within the **30–60 minute** forecast. This includes parallel harness work, fixture creation, benchmarking, review and correction cycles.

## Rerun

The commands and interpretation rules are in [the harness guide](../test/scan-baseline.md). The baseline executable is the retained signed 0.11 download, SHA-256:

`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`

```powershell
.\build\release-011-download\kuu.exe test/scan-bench.lua --exe build/release-011-download/kuu.exe --files 100000 --repeats 3 --ledger-records 10000 --out build/step01-bench-100k.json
.\build\release-011-download\kuu.exe test/scan-repros.lua --out build/step01-repro-results.json
```

Choose a new output filename on replay: the benchmark refuses overwrite. Every run creates its own retained fixture root below build/. Known-defect reproductions remain separate from test/run.lua. A successful reproduction-harness exit means the observations completed, not that the defects were fixed.

## What was built

- test/scan-bench.lua creates controlled tiny/generated/unexcluded/already-pruned projects, nested invocations, growing valid ledgers and changed-file workloads. It measures unchanged executable subprocesses and saves every sample, warm median/range, phase profiles and fixture counts.
- test/scan-profile.lua wraps exports around the executable's unchanged embedded commands. It attributes initial/final native walking and listing, hashing, baseline decoding/encoding, manifest loading, task/child waits, records, inventory and ledger verification. It runs separately from uninstrumented latency samples; inclusive rows are not disjoint totals.
- test/scan-repros.lua plus test/fixtures/scan_fixture.c provide bounded, repeatable observations using owned junction targets, temporary exclusive Windows handles, explicit partial-list fault injection and a controlled two-process publication interleave.
- test/scan-baseline.md documents runnable commands, timing boundaries, fixture retention, expected-failure interpretation and later private-state compatibility limits.

## Reproductions

Both build/step01-repro-results.json and build/step01-repro-replay.json completed with seven reproduced observations and zero harness errors:

| Case | Evidence and qualification | Later step |
|---|---|---|
| Automatic check/fix through a junction | Ordinary CLI checking listed, then fixing modified, an owned sibling-directory target outside the fixture project. | 02 |
| Unreadable source directory | A real exclusive directory handle produced Windows error 32. The still-present source was counted as removed and omitted from the published baseline. | 05 |
| Partial listing | Explicit fault injection removed one entry and added a listing error. The ledger still published an exact-looking deletion and incomplete baseline. | 05 |
| Unreadable tree.json | A real exclusive handle blocked predecessor reading. The ledger treated it as empty and counted existing files as additions. | 05 |
| Invalid per-file state values | Valid JSON containing booleans/numbers in place of metadata caused ledger.open to raise. Public run caught this, warned and executed the task successfully, without ledger recording. | 05 |
| Malformed JSON/top-level values | Corrupt/invalid state silently became an empty predecessor, producing false additions. | 05 |
| Overlapping publication | Two real processes took real snapshots; a barrier paused A before writing, B published a later snapshot, then A replaced it with the earlier one. The barrier controls scheduling; natural race frequency was not measured. | 05 |

These seven cases are not seven unrelated root causes. Several exercise different failure modes of unvalidated/incomplete observation state.

## Measurement interpretation

Fixture creation and initial inventory are outside command samples. They warm filesystem caches, so neither the first observation nor the repeated observations are a controlled cold-cache measurement. A first observation is per command; baseline_present_before records whether tree.json already existed. Commands run in recorded order and retain ledger state.

The populated cases have equal payload counts and a common maintained control tree. One payload file in 100 is Lua. Existing .tools pruning is the control for avoiding work below a large subtree. The generated layout models .cache/reconstruction, editor state, nested virtual environments and mixed-case names without copying private data.

The synthetic timing results must not be presented as a measurement of FlowNet's real checkout or as an exact reproduction of its reported 16 seconds. FlowNet's evaluation did not include the file/directory counts needed for that comparison.

## Results and completion

The full benchmark completed successfully in **1,319.55 seconds (about 22 minutes)** of monotonic elapsed time. This includes fixture creation, first observations, warm repeats, separate instrumented profiles and mutation probes. Creating the three populated fixtures alone took about 9 minutes 37 seconds, outside the command samples.

Host: Windows 11 **25H2**, build **26200.6899**, x64, 12 logical CPUs, about 31.7 GiB RAM, unelevated. This is baseline evidence on this host, not a Windows 11 23H2 compatibility test.

Each populated case contains **100,000 payload files** in addition to a common 66-file control tree. The generated case has 100,068 files and 1,019 directories, including a tiny nested checkout. The unexcluded and already-pruned cases each have 100,066 files and 1,004 directories. The tiny case has 66 files and two directories. Counts describe fixtures before command-generated ledger output.

Uninstrumented process wall time, **median of three warm observations**, in seconds:

| Command | Tiny | Generated directories | Unexcluded source | Existing `.tools` pruning |
|---|---:|---:|---:|---:|
| Startup/version | 0.024 | 0.021 | 0.020 | 0.021 |
| Dry run | 0.028 | 0.026 | 0.026 | 0.026 |
| No-op task | 0.070 | 12.152 | 12.991 | 0.049 |
| Task with tiny child | 0.112 | **12.375** | **13.645** | **0.075** |
| Nested kuu run, same project | 0.190 | **24.438** | 28.869 | 0.127 |
| Explicit manifest check | 0.041 | 0.029 | 0.028 | 0.028 |
| Automatic project check | 0.055 | 5.542 | 5.833 | 0.034 |
| Capabilities | 0.069 | 5.271 | 5.775 | 0.048 |

The generated case's nested-checkout invocation took 11.955 seconds. Its tiny nested project adds little to the parent's large-tree observation cost; a nested invocation in the same large project repeats that cost.

Three observations provide a baseline, not a statistical performance guarantee. Generated-child samples ranged from 12.219–12.595 seconds; generated nested runs from 23.997–25.015 seconds. Unexcluded-child samples ranged from 12.856–16.917 seconds, and unexcluded nested runs from 25.201–37.326 seconds. The raw report retains every sample and first observation.

### Attribution

The separate instrumented generated-child run took 13.512 seconds inside the command. Initial ledger observation took **6.382 seconds**, final observation **7.095 seconds**, and task execution **0.031 seconds**. Each observation returned **1,019 directories and 100,068 files**. The initial walk/list calls took 2.657/2.782 seconds; the final walk/list calls took 2.672/3.718 seconds. Remaining observation time includes Lua comparison/sorting, state decoding/encoding and publication. These parent/child timings overlap and must not be added together indiscriminately.

With the equally large payload under `.tools`, each snapshot returned only **two directories and 66 files**; initial/final ledger operations took 0.0066/0.0115 seconds. The native pruning control demonstrates the benefit of avoiding descent into excluded trees. It does not promise that equally large maintained source can be made as cheap by exclusions.

Ordinary task execution did not invoke module inventory. Capabilities did: the generated case spent **6.320 seconds** in inventory, compared with 0.0071 seconds for the pruned case. Therefore task scans and inventory need separate coverage and timing; they are different consumers of traversal work.

### Growing history and changed files

| Initial valid ledger | Initial bytes | Warm child median | Warm capabilities median |
|---|---:|---:|---:|
| 1,000 records | 1,042,701 | 0.155 s | 0.089 s |
| 10,000 records | 10,447,710 | 0.443 s | 0.346 s |

Commands append records, so these are seed counts, not final history sizes. Instrumented capabilities verified 1,015 and 10,015 records respectively. Verification took 0.039/0.315 seconds; tail reading took 0.011/0.084 seconds. The first child record operation took 0.049/0.346 seconds, exposing another history-dependent cost. This is smaller than large-tree traversal here, but must remain visible in step 07's acceptance comparison.

Single-observation mutation probes changed zero, one and 64 files, each populated file carrying approximately 64 KiB of padding. The profiles recorded **zero, one and 40 file hashes**, respectively, confirming the existing hash cap. Uninstrumented child observations were 0.073, 0.091 and 0.372 seconds. These three values are individual observations, not medians.

### Validation and retained evidence

- Full report: [step01-bench-100k.json](../build/step01-bench-100k.json). It contains sample metadata, timings, profile paths and counters. All sampled commands and profile commands completed successfully without truncated captures.
- Compact derived results: [step01-bench-summary.json](../build/step01-bench-summary.json).
- Small-fixture smoke run: [step01-bench-smoke2.json](../build/step01-bench-smoke2.json).
- Independent reproduction runs: [first run](../build/step01-repro-results.json) and [replay](../build/step01-repro-replay.json), each seven reproduced observations and zero harness errors.
- Regression output: [step01-focused-tests.log](../build/step01-focused-tests.log).

Full-run fixtures and per-command artifacts remain in `build/scan-bench-faa34066c3c812f0`; reproduction reports identify their separate fixture roots. These generated files are ignored build artifacts, while the harnesses and this note are reviewable source files. Retain or archive the reports before cleaning build output.

The new Lua harnesses pass static checking with zero errors/warnings. The unchanged signed runtime's focused ledger/check/check-corpus/capabilities/task suite passed **322 checks, zero failures, in 21.5 seconds** (build/step01-focused-tests.log). This suite ran while the last large fixture was being created, and finished before its measured commands began; fixture creation is not a latency sample.

HEAD remains c7f6c2c610023a5cd6456a85e3f9c9e1d0859ef5. Both build/kuu.exe and the release-download executable still have the signed-release hash above. No production files were edited.

### Implications for the remaining plan

The ordering remains appropriate: fix automatic traversal through directory links in **step 02**, define policy in 03, integrate shared traversal in 04, then make state validation/completeness/publication trustworthy before enabling new defaults in 05. The incomplete-baseline and controlled-concurrency reproductions make that dependency concrete. Steps 06–07 should preserve separate task, inventory and history costs in their reporting and acceptance evidence.

Step 01 met its time forecast; one observation is insufficient to narrow estimates for the more complex implementation steps. Keep their existing ranges and re-estimate after step 02. No release build/signing/publication was required for this tooling-only step.
