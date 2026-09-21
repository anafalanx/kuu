# Step 07 — milestone 1 acceptance

> **Superseded acceptance scope.** On September 16 the owner abandoned automatic
> filesystem-change observation; on September 21 the owner authorized
> implementing execution history only. The failed measurements and test results
> below remain historical evidence. The proposed indexing investigation is
> canceled. Current scope and acceptance are in the
> [revised plan](plan-flownet-feedback-2026-09-15.md) and
> [execution-history work note](step07-execution-history-2026-09-21.md).

Status: the Step 07 acceptance run is finished, but **milestone 1 is not accepted**. Correctness, excluded-tree scaling and bounded-history improvements pass. Repeated whole-source observation still makes trivial runs over 100,000 maintained files take seconds, triggering the plan's remaining-dominant-cost gate. Step 07 remains open; Step 08 has not started.

## Acceptance scope

Milestone 1 covers safe shared observation, declarative scope, trustworthy ledger baselines/publication, and visible costs. It does not promise constant-time scans of maintained source or constant-time verification of arbitrary retained history. FlowNet was neither modified nor executed; these are synthetic, owned fixtures on the same host as the signed 0.11 baseline.

Two integration gaps found in the final review now have executable coverage in [scan_acceptance.lua](../test/cases/scan_acceptance.lua): a public run retains its captured configuration through manifest changes, task writes and final publication, then the next run adopts the replacement; and an owned directory junction demonstrably shares the real project's actual ledger lock and advances the same baseline generation after release.

| Required boundary | Evidence |
|---|---|
| Defaults, custom rules, mixed case, nested names and explicit starts | Policy/native/adapter/activation/reporting suites; large-tree structural comparison |
| Invalid configuration before project code | Activation and reporting suites |
| Partial enumeration and unreadable state | Explicit injection plus real exclusive Windows handles; positive defect replays |
| Legacy/corrupt state, common-scope migration and retained baselines | Ledger-state and activation suites; new public-run scope-transition test |
| Links and aliases | Actual directory junctions, no-follow tests, cross-process alias lock test |
| Concurrent and nested runs | Controlled stale-publication interleave, shared lock tests, nested public runs |
| Scope/completeness reporting and overlapping timing boundaries | Reporting suite, preserved existing readers, embedded manual schemas |

Real file-symlink creation remains unavailable on this unelevated host and is explicitly skipped. Junctions and Windows sharing denial were exercised; partial enumeration and ordinary filter/cloud metadata remain explicitly injected cases. This is Windows 11 25H2 build 26200.6899 evidence, not a separate 23H2-host run.

## Remaining history cost found and fixed

A quiet matched benchmark with no generated payload and 10,000 seeded records exposed a remaining ordinary-task penalty: the first ledger append read the latest day and then scanned its whole text to find the predecessor. [Before](../build/step07-history-before.json) and [after](../build/step07-history-after.json) use the same 66-file/two-directory source layout, three warm samples and approximately 10.45 MB of seeded history. Here "before" is the pre-optimization development build `449025f6…`, not signed 0.11; the signed-release comparisons are identified separately below.

| Measurement | Before | After |
|---|---:|---:|
| Child command warm median | 489.25 ms | 124.03 ms |
| Child command warm range | 485.78–516.26 ms | 119.37–126.24 ms |
| Public ledger-phase median | 424.59 ms | 36.72 ms |
| First record, separate profile | 415.90 ms | 17.20 ms |
| Capabilities tail-phase median | 90.23 ms | 17.63 ms |
| Capabilities command warm median | 388.72 ms | 385.80 ms |

The private ledger now extracts the required suffix through reversed 8 KiB chunks, without scanning every older byte in Lua or allocating every historical row. Native reads still load each selected day in full. Full verification, error handling, malformed-row selection, CRLF behavior and exact predecessor bytes remain unchanged. [ledger_tail.lua](../test/cases/ledger_tail.lua) adds 52 assertions for short/long/unterminated lines, chunk seams, blank and malformed rows, multiple days and read failures. Independent review found no semantic regression.

The child workload is about **3.94 times faster** at this history size. The first-record profile's own Lua time fell from 398.74 to 0.36 ms; the remaining approximately 14 ms day-file read is visible. Capabilities' whole-command distributions overlap: do not claim a comparable overall speedup. Its unchanged full verifier dominates, and measured setup/verification drift offset the cheaper tail lookup in these blocks.

This resolves the demonstrated ordinary-task penalty at 10,000 records. Remaining costs are explicit: append/tail I/O and memory scale with selected day-file bytes; capabilities reads the day again for verification and verifies all retained records. There is no arbitrary-history constant-latency claim or skipped integrity check. [The ledger manual](../docs/ledger.md) documents these boundaries.

## Small-command latency and acceptance judgment

The new [alternating harness](../test/scan-latency.lua) ran one first and fifteen warm pairs for six commands, with independent baseline/candidate roots for each command. All **192 samples** exited normally, parsed correctly where JSON was expected, retained their outputs and preserved executable hashes. No checkout alternated old and new baseline writers. Results: [raw comparison](../build/step07-tiny-latency.json), [log](../build/step07-tiny-latency.log).

| Command | Signed 0.11 median | Candidate median | Paired median difference |
|---|---:|---:|---:|
| Startup/version | 28.82 ms | 29.01 ms | +0.42 ms |
| Dry run | 39.41 ms | 40.08 ms | +3.23 ms |
| No-op | 57.24 ms | 61.16 ms | +2.93 ms |
| Tiny child | 86.62 ms | 91.03 ms | +4.90 ms |
| Check | 39.04 ms | 42.45 ms | +2.86 ms |
| Capabilities | 48.37 ms | 51.70 ms | +2.11 ms |

Startup's difference is below its baseline 1.03 ms median absolute deviation. The command cost is small but real: the candidate was slower in every check/capabilities pair and 13 of 15 no-op/child pairs. Dry-run block medians conceal common drift, which paired comparisons expose. This is an approximately **2–5 ms tradeoff**, not zero regression.

Acceptability is based on this host's measured 29 ms process start, approximately 39–87 ms baseline command medians, paired spread and retained extremes, rather than a universal percent/millisecond threshold. The added cost preserves the small-command latency class while providing the correctness and diagnostic guarantees required by this milestone. Check's observed maximum was 46.31 ms versus 41.93 ms; capabilities' was 57.58 versus 56.15 ms. With only fifteen observations, nearest-rank p95 is just the maximum, not a reliable tail estimate or service-level guarantee. Alternation reduces order bias but does not control caches, antivirus, thermal state or unrelated workloads; the baseline is signed and the candidate is unsigned.

## Full-scale comparison

The full candidate benchmark completed in **640.13 seconds**, including creation of 300,000 payload files across the three populated fixtures, all first/warm observations, separate profiles and mutation probes. Fixture creation alone took approximately 348 seconds, outside command samples. Options match the retained signed 0.11 baseline: 100,000 files per populated case, three warm repetitions, 10,000 records in the larger history case and profiles enabled. Logical fixture file/directory counts match exactly.

Uninstrumented process wall times in seconds; ranges are the candidate's three warm observations:

| Fixture / command | Signed 0.11 median | Candidate median | Candidate warm range |
|---|---:|---:|---:|
| Generated / no-op | 12.152 | 0.058 | 0.056–0.058 |
| Generated / child | 12.375 | 0.086 | 0.083–0.087 |
| Generated / nested run | 24.438 | 0.147 | 0.145–0.155 |
| Generated / check | 5.542 | 0.053 | 0.052–0.058 |
| Generated / capabilities | 5.271 | 0.071 | 0.071–0.073 |
| Unexcluded source / no-op | 12.991 | 11.947 | 10.456–12.799 |
| Unexcluded source / child | 13.645 | 9.709 | 9.579–10.465 |
| Unexcluded source / nested run | 28.869 | 25.652 | 25.306–27.650 |
| Unexcluded source / check | 5.833 | 3.714 | 3.603–4.357 |
| Unexcluded source / capabilities | 5.775 | 3.641 | 3.566–3.739 |
| Existing `.tools` pruning / child | 0.075 | 0.070 | 0.069–0.070 |
| Existing `.tools` pruning / nested run | 0.127 | 0.120 | 0.119–0.121 |
| Existing `.tools` pruning / capabilities | 0.048 | 0.039 | 0.038–0.040 |

The generated child result is approximately **144 times faster**, with nested runs approximately **166 times faster**. The nested checkout under an excluded ancestor still executes deliberately and takes 0.172 seconds versus 11.955 seconds; observation exclusions do not prevent execution. These are synthetic results, not a rerun of FlowNet or an exact reconstruction of its reported 16 seconds.

Public scan reports and native profile counters agree: each generated snapshot collects **66 files in five directories**, pruning six encountered boundaries. The existing-pruning control collects **66 files in two directories**. Unexcluded source collects **100,066 files in 1,004 directories**, proving maintained input was not silently dropped to produce the speedup.

The final executable also re-collected retained 1,000-file and 100,000-file generated fixtures read-only. Their entered directories, visible filenames and excluded boundaries were **identical**, not merely equal in count. A supplied custom `src/maintained` subtree exclusion over the large source control produced 66 files in three directories without entering that subtree. This structural proof does not execute manifests or change fixture configuration. The public configuration path is covered independently by the activation and acceptance suites.

Evidence: [full candidate report](../build/step07-bench-100k.json), [baseline](../build/step01-bench-100k.json), [derived comparison](../build/step07-bench-comparison.json), [structural scale proof](../build/step07-scope-scale.json), [benchmark log](../build/step07-bench-100k.log). The harness now retains available public timings/scope/scan reports for every sample. Reproduction commands and interpretation are in [scan-baseline.md](../test/scan-baseline.md).

The baseline and candidate large-tree runs are separate sequential blocks, not paired trials. First observations are not controlled cold-cache samples: preparation warms the filesystem. Small controls show block drift—for example, candidate child medians are 94 ms in the early tiny block and 70 ms in the later pruning control. Use the alternating experiment above to assess millisecond changes; do not turn these three-sample ratios into statistical guarantees. Profiles use different wrappers on old/new collection paths, overlap internally, and serve attribution rather than speed-ratio calculation.

The full run's later 10,000-record case reports an 85 ms child median and 222 ms capabilities median. The separate matched history experiment above yielded 124/386 ms in its earlier block. Both are retained; the variation reinforces the limits of three-sample timing claims. The suffix optimization's eliminated full-text Lua scan and sharply reduced own processing time are directly evidenced in either setting.

## Failed gate and proposed next decision

The agreed plan says: **"If a remaining dominant cost defeats small-command usability, resolve it or explicitly mark this milestone incomplete; exclusion support alone is insufficient evidence."**

The maintained-source result still triggers that condition. It is a scaling control rather than a promise of constant-time traversal, but 9.7–11.9 seconds for trivial runs and 25.7 seconds for nested runs remain far outside the measured small-command noise. Better results than signed 0.11 do not establish usability for that supported workload. The separate child profile attributes about 6.16 seconds to ledger opening and 7.12 seconds to closing, including roughly 3.24/3.42 seconds of collection and substantial validation/comparison/publication work. Those inclusive values must not be summed with their child phases.

**Recommended next action: retain the gate and insert a bounded incremental-observation design/proof step before attributes.** Estimated agent execution: **30–60 minutes for that investigation**, followed by a grounded implementation estimate. It should:

1. Define the unchanged correctness contract: exact deltas require fresh, complete evidence; initial state, unavailable tracking, missed changes and recovery require an explicit complete scan or an honest incomplete result.
2. Determine which cross-process change-tracking/index approaches are viable under kuu's supported Windows and privilege constraints, including aliases, concurrent publishers and fallback behavior. Do not assume a particular filesystem facility or background service is available.
3. Build a disposable proof against the retained large source fixture, measuring initial observation, unchanged repeated runs, edits/renames/deletions and loss/recovery scenarios.
4. Return a concrete implementation contract and estimate. Only a proven approach should replace repeated complete scans; weakening completeness or trusting an unvalidated cache is not an acceptable shortcut.

Alternatively, the owner can explicitly narrow milestone acceptance to excluding generated subtrees while accepting documented whole-source scan cost. That is a change to the agreed acceptance scope, not an inferred pass. No such change has been assumed, and no persistent index or service has been introduced in this step.

## Validation and identity

Final focused regression: **1,155 checks, zero failures, 25.0 seconds**. Relevant AddressSanitizer coverage: **1,019 checks, zero failures, 45.4 seconds**. Six changed/new Lua files passed static checking with zero errors/warnings; native static analysis passed; all 48 embedded manual pages match source. Shared suites and measured benchmark workloads were scheduled sequentially.

The signed baseline reproduced all seven known defects again. The final candidate reproduced none, with positive acceptance prerequisites and no harness errors: [baseline replay](../build/step07-repros-baseline.json), [candidate replay](../build/step07-repros-final.json). This includes the two-process stale-publication case, not an estimate of natural race frequency.

Logs: [build](../build/step07-build-final.log), [focused](../build/step07-focused-final.log), [ASAN](../build/step07-asan-final.log), [static Lua checks](../build/step07-static-final.log), [native analysis](../build/step07-analyze.log), [manual comparison](../build/step07-embedded-docs.log).

Candidate SHA-256: `e5e8bcd28b84a772fbe4dff261923a1215d56c2fb0e48c0313d6b6832fd1599e`.

Signed 0.11 SHA-256, unchanged: `68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`.

Execution began **2026-09-15 22:08:52 UTC**, September 16 locally. The forecast was **30–60 minutes**; the acceptance run and review took **about 24 minutes**. This records completed investigation time, not completion of the failed performance gate. No signing, release, version change, commit or push was performed.
