# Step 21 — integrated acceptance

Status: **complete**. All remaining implementation and validation steps in the
[FlowNet plan](plan-flownet-feedback-2026-09-15.md) are accepted. The original
automatic-observation work remains explicitly retired; there is no pending
watcher, journal or indexing implementation. Every evaluation entry has a final
disposition in the plan, including project-specific behavior, retired features
and the unconfirmed transient Robocopy report.

## Final change and documentation review

The [migration guide](../docs/upgrading-0.11.md) now explicitly covers optional
and mandatory inspection exclusions, `defaults:false`, configuration validation
before project code, execution-history v2 and new-reader support for original
v1 records. It documents removed report fields and their replacements, untouched
old `tree.json`, task help/separators, file attributes, cleanup and tested recipes.
It makes no claim that older executables can consume v2 history. Development
artifacts still display 0.11 and require build/hash identification.

Final review corrected two documentation mismatches: an in-task `CLI usage`
error can omit `error.exit` while the process/verb exits 2; declared tools under
`.tools` remain reportable, and module inventory follows configured exclusions.
The capabilities/stability pages no longer claim the descriptor has never been
used. Provisional interface status remains unchanged. The roadmap, manual map,
crosslinks and generated `kuu.md` include the accepted work: **56 pages, 27
public modules and 175 functions**, plus handle methods.

Independent reviews covered native GUI/shortcut lifetime and quoting, cache
integrity/publication, archive ownership and error retention, uncertain remote
outcomes, report/schema wording and test/build registration. No material finding
remains open. The new C examples are project tools, not new GUI/COM/publishing
APIs in kuu's palette.

## Complete gate

Recorded command: `.tools/msys2/ucrt64/bin/mingw32-make.exe -j4 gate`.
Its recursive targets serialize normal tests, ASAN, analysis, fuzzing and soak.

| Check | Final result |
|---|---|
| Normal suite | **2,667 passed, 0 failed**, 93.8 s |
| AddressSanitizer suite | **2,667 passed, 0 failed**, 142.6 s |
| GCC static analysis | Passed for authored host C and `examples/*.c` |
| Parser fuzzing | 10,000 cases per family for each of seeds 1, 12648430 and 3735928559; all passed |
| Soak | **25 rounds in 62 s, 0 failures**; reported handle/private-memory deltas −3 / −2.4 MB |
| Documentation/palette/bundle | Retrieval, sections/anchors, schemas, palette agreement and regenerated bundle passed in both suites |
| Declared globals | Final whole-tree `check --fix` required no changes |

[Final gate log](../build/step21-gate-final.log),
[manual generation](../build/step21-bundle.log),
[build preparation](../build/step21-build-pre.log).

The first full normal run passed 2,666 checks and failed the final declaration
maintenance check. That check removed two unused globals, `tostring` and
`table`, from `test/cases/native_helper.lua`. No runtime code changed. The entire
gate was rerun with the corrected test; the table above is that final result.
The [initial log](../build/step21-gate.log) is retained. External native GUI and
shortcut fixtures are strict GCC builds; ASAN instruments kuu and its designated
ASAN fixture, not every external helper.

The suite includes original-byte v1 history, mixed v1/v2 chains, immutable old
tree state, exact argument forwarding, empty PATH, child exit codes, detached
lifetime and task/child records. Standalone report evidence additionally passed
**10 checks** for an in-task `CLI usage` error across the process exit, task
event, final envelope, task history and verb history:
[report](../build/step21-cli-usage-fab777b24e116226/report.json),
[log](../build/step21-cli-usage.log),
[runner](../build/step21-cli-usage.lua).

## Final performance evidence

Measurements ran sequentially after the gate, without concurrent builds,
regression runs or other measured workloads. They used the final executable
hash below. Fixture validation and report writes are outside command timers;
the samples include launch, capture, command work and shutdown. First observations
are not controlled OS-cold samples.

The [large-project report](../build/step21-execution-bench-final.json) reused the
owned Step 07 fixtures, with one first observation and seven warm samples for
ordinary runs. The maintained-source fixture contains **100,066 visible files**.
Warm medians:

| Workload | Tiny control | 100,000 excluded files | 100,066 maintained files | Step 07 maintained files |
|---|---:|---:|---:|---:|
| No-op run | 52.44 ms | 51.69 ms | **41.52 ms** | 21.10 ms |
| Tiny child | 82.86 ms | 87.11 ms | **83.16 ms** | 40.49 ms |
| Nested run | 137.76 ms | 138.98 ms | **134.16 ms** | 77.06 ms |

Maintained-source ranges were 40.00–43.04 ms, 77.58–87.15 ms and
128.22–143.38 ms respectively. There is no source-size penalty comparable to
the retired snapshot design's seconds-long runs. All four retained `tree.json`
files kept identical nonempty before/after hashes. Explicit checking and
capabilities still scale with requested inspection: **3.764 s** and **3.655 s**
here, versus 1.585 s and 1.653 s at Step 07. Absolute times increased throughout
this session; these historical comparisons are not paired trials or precise
speedup estimates.

The [alternating tiny-project comparison](../build/step21-execution-tiny-final.json)
used the unchanged signed 0.11 baseline in separate fresh fixtures, with one
first pair and fifteen warm pairs per command. All **192 samples** completed:

| Command | Signed 0.11 median | Final candidate median |
|---|---:|---:|
| Version/startup | 49.33 ms | 46.36 ms |
| Dry run | 47.34 ms | 49.90 ms |
| No-op | 57.50 ms | 48.12 ms |
| Tiny child | 131.92 ms | 115.59 ms |
| Check | 45.51 ms | 50.58 ms |
| Capabilities | 55.32 ms | 57.23 ms |

The signed baseline also took longer than in Step 07, so the cross-session
increase cannot be attributed solely to candidate changes. The current paired
comparison still favors the candidate for execution; the small inspection and
preflight increases are recorded rather than described as zero overhead.
The report retains ordering, ranges, MAD and paired differences. No source root
alternated old/new history writers, and both executable hashes stayed stable.

A [fresh same-day history run](../build/step21-execution-history-final.json)
seeded **10,000 valid v1 records / 10,447,604 bytes** into the current UTC day.
Its child median was **104.73 ms**, and capabilities, including full history
verification, was **353.87 ms** (three warm samples). The no-seed control child
was 110.22 ms; the 1,000-record child was 95.46 ms. This variation supports
usability at the tested size, not a monotonic cost curve or constant-time claim.
The corresponding Step 07 10,000-record medians were 70.77 / 239.61 ms.
All **22 profiled runs**, including 0/1/64-file mutations, had no collector,
`fs.dirs`, `hash.file` or `ledger.close` phase. Profiles are separate from
uninstrumented timing samples and perturb their own execution.

Recorded commands:

```text
build/kuu.exe test/execution-bench.lua --fixtures build/step07-bench-100k.json --out build/step21-execution-bench-final.json --repeats 7
build/kuu.exe test/scan-bench.lua --files 0 --ledger-records 10000 --repeats 3 --out build/step21-execution-history-final.json
build/kuu.exe test/scan-latency.lua --baseline build/release-011-download/kuu.exe --out build/step21-execution-tiny-final.json --repeats 15
```

Use fresh output names when repeating these commands; the harnesses refuse
existing reports. Logs: [large](../build/step21-execution-bench.log),
[history](../build/step21-execution-history.log),
[paired tiny](../build/step21-execution-tiny.log).

## Separate project and compatibility

The separate `C:/dev/kuu-test-project` was read-only. Its original manifest
bytes and three pinned cached archives were copied into fresh fixtures below
this repository's `build/`. The final executable passed **11 commands**:
legacy list/check/smoke/tools, and migrated list/check/smoke/machine/all/tools/
task-check. Both tool installations reconstructed from those verified local
archives without downloads and ran the expected GNU Make 4.4.1.

The legacy copy kept byte-identical `tasks.lua`. Its check reported zero errors,
one expected undeclared-tool warning, and the deprecation note. The migrated
copy renamed the manifest, updated its corresponding glob expectation and
declared its kuu tool. Its checks reported zero errors/warnings. Machine probes
used an owned ephemeral loopback listener and unique HKCU key with scoped and
parent fallback cleanup, instead of probing arbitrary ports or writing the old
fixed key. No registry fixture remained. The original source/runtime/document/
ignore files and all three archives had unchanged hashes afterward.

[Exerciser report](../build/step21-exerciser-16c5b72187b57c06/report.json),
[command log](../build/step21-exerciser.log),
[one-off runner](../build/step21-exerciser.lua). These are disposable acceptance
copies, not a migration of the external original or a real FlowNet adoption run.

Fresh validation ran unelevated on **Windows 11 25H2, build 26200.6899, NTFS**.
The [final import audit](../build/step21-imports.txt) shows only system DLLs and
no static `ReleasePseudoConsole` import; the existing dynamic fallback remains.
This does not substitute for a fresh Windows 11 23H2 or Server 2025 run. The
historical 23H2 records remain historical evidence, not certification of this
candidate. No real user profile, FlowNet checkout or remote release was changed.

## Artifact and completion boundary

A later [agent upgrade-discovery follow-up](upgrade-discovery-2026-09-21.md)
adds the migration entry points and records its own artifact and focused checks.
The full-gate and performance results on this page belong to the artifact below.

Final unsigned `build/kuu.exe`: **2,023,936 bytes**, SHA-256
`72fe03fb7b313dd942a3c8bfe1d12d708c2ef96bb78731c7649fe84ab4fd382f`.
The signed comparison baseline stayed at
`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`.
Benchmarks and the separate exerciser verified that the candidate bytes remained
unchanged. Final whitespace validation passed.

The implementation plan is complete. Commit/push, release numbering, signing
and publication remain separate actions; this turn performed none of them.

Step 21 started **2026-09-21 19:58 UTC** and was accepted approximately
**20:13 UTC**, about **15 minutes** against **30–60 minutes**. The combined
Steps 18–21 turn started **19:31:01 UTC** and took about **42 minutes**, against
**1 h 55 min–3 h 45 min**. Implementation, preparation and independent reviews
ran in parallel; the full gate and performance workloads were serialized.
