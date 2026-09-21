# Step 07 follow-up — execution history without automatic tree tracking

Status: **revised Step 07 and milestone 1 accepted** under the owner's decision
to remove automatic filesystem-change observation. The former snapshot contract
did not pass its performance gate; it has been retired rather than declared
successful. Step 08 has not started. No indexing investigation remains pending.

The [sequential plan](plan-flownet-feedback-2026-09-15.md) carries the revised
contract. The [September 16 report](step07-flownet-feedback-2026-09-16.md)
preserves the earlier failure and historical measurements. This work continues
the uncommitted development based on release 0.11 at `c7f6c2c`; it does not
change the release number, commit, push, sign or publish. FlowNet was not
modified or executed.

## What changed

Normal `kuu run` now records execution only: runs, tasks and children launched
through `task.exec`, with their arguments, outcomes and durations. It performs
no before/after project-tree collection, source hashing, file-change comparison,
tree-state validation/migration or baseline publication. The unused tree-state
runtime and its snapshot-specific acceptance tests were removed. Abandoned
indexing experiment sources were archived under
`build/step07-index-investigation-sources/` before removal from active test paths.
No watcher, journal, index or background service was introduced.

The ledger writes schema `v:2`, explicitly removing `delta` and `observation`
even when a stale private caller supplies them. Readers and chain verification
accept both `v:1` and `v:2`, including mixed day files, preserving original
NDJSON bytes and predecessor hashes. Existing `.kuu/ledger/tree.json` files are
ignored and left untouched, including malformed and exclusively held files.
Ninety-day retention, canonical-project append locking within a Windows session,
and best-effort Git ref/head context remain. Git context is not a dirty-state
or file-attribution claim. Stream events retain their independent `v:1` schema.

The public run result now reports `ledger = { records, complete, error? }` when
opening is attempted. Counts include successful appends by that invocation.
An open or append failure warns once, marks history incomplete and preserves
the task's outcome; classified errors retain domain/code/message, while raw
exceptions retain their message. Dry runs and preflight failures omit this
summary. Run scope/scan reports and initial/final scan timings were removed;
setup, execution, ledger and total timings remain. Capabilities no longer
reports an inferred `unaccounted` value.

Configuration validation still occurs before loading a project manifest.
Explicit checking and capabilities inventory retain configured exclusions,
safe native traversal, no-follow behavior and truthful completeness reporting.
An application can still deliberately call `fs.watch`. These operations do
not become automatic filesystem-change tracking through normal task execution.

The README, task/ledger/scan/capabilities guides, roadmap and development
migration notes describe this contract. `scan` is now included in the embedded
manual's ordering; all 48 manual pages and the generated `kuu.md` were checked.
The executable still identifies itself as unreleased development of `0.11`.
Older releases cannot read new `v:2` history; the migration note calls this out.

## Final-build acceptance

| Evidence | Result |
|---|---|
| Focused normal suites | **1,121 passed, 0 failed**, 19.8 s |
| Relevant AddressSanitizer suites | **958 passed, 0 failed**, 24.3 s |
| Static check of 19 changed/new Lua files | 0 errors; one expected root-context warning for the test runner's `require "lib"`, which resolves from `test/` during execution |
| Documentation/bundle/embedding checks | Passed in the normal suites |
| Independent final code/documentation review | No actionable remaining removal-contract defect |
| Working-tree whitespace check | Passed |

The suites cover mixed v1/v2 chains, exact legacy bytes, corrupt and unreadable
history, suffix selection, unknown record versions, successful and failed
tasks, nested execution, canonical aliases sharing the actual append lock,
old-tree non-access, configuration preflight, and the absence of source-tree
enumeration during execution. Failure injection covers returned and raised
open failures and partial append failures after a successful dependency record,
including preservation of both successful and failed task outcomes. Public
acceptance guards both collectors, directory traversal and tree-state access.
Real exclusive handles and directory junctions are exercised. File-symlink
creation remains an explicit host limitation.

The selected normal suites were `ledger ledger_execution ledger_tail
execution_acceptance reporting scan_policy scan_native scan scan_activation
check check_corpus fixglobals capabilities task docs bundle palette fs paths
sync entry embed`. The sanitizer run used the corresponding history, execution,
reporting, traversal, checker, capabilities, task, filesystem, path and sync
coverage. This is focused milestone validation; Step 21 still owns the final
whole-plan integration/release checks.

Logs: [normal](../build/step07-execution-tests-final.log),
[sanitizer](../build/step07-execution-asan-final.log),
[static check](../build/step07-execution-static-final.json),
[build](../build/step07-execution-build-final.log),
[manual generation](../build/step07-execution-bundle-final.log).
An earlier validation caught only stale generated test-line figures after
additional tests; regeneration and the final run above resolved it.

## Source-size acceptance

[The execution benchmark](../build/step07-execution-bench-final.json) reused
owned fixtures from the earlier 100,000-file run. Each ordinary command has
one first observation and seven warm samples; the table reports warm medians.
Validation inventory and old-tree hashes run outside the command timer. No
builds or test suites ran concurrently with these measured commands. Timings
include process launch, output capture, command work and shutdown.

| Workload | Tiny control, 66 visible files | 100,000 excluded payload files | 100,066 maintained files | Historical Step 07, maintained files |
|---|---:|---:|---:|---:|
| No-op run | 22.59 ms | 22.03 ms | **21.10 ms** | 11.947 s |
| Tiny child | 43.65 ms | 41.26 ms | **40.49 ms** | 9.709 s |
| Nested run | 75.99 ms | 71.55 ms | **77.06 ms** | 25.652 s |

Warm ranges on maintained source were 20.22–22.76 ms, 38.88–44.26 ms and
75.68–85.30 ms respectively. The current tiny and large fixtures exhibit the
same practical execution cost, and structural tests prove the absence of
automatic source observation. The historical column was measured on another
day with the pre-removal development executable, not in paired trials or with
the signed release. Absolute timings vary with host conditions; the earlier
exploratory run this turn was slower across both tiny and large controls.
No exact cross-day speedup ratio is asserted.

Explicit `kuu check --json` on maintained source took **1.585 s**, and
`capabilities --json` took **1.653 s** (three warm samples each). These commands
still inspect the requested source. All four retained `tree.json` files had
identical before/after hashes. The retained 10,000-record fixture's current
day is newer than its seed day, so its 43.34 ms child result is not used to
claim performance when appending to a large same-day ledger.

## Paired tiny-project control and history cost

[The alternating comparison](../build/step07-execution-tiny-final.json) used
separate fresh baseline/candidate roots, one first pair and fifteen warm pairs
per command. All **192 samples** completed with valid outputs and stable
executable hashes. No checkout alternated old and new writers.

| Command | Signed 0.11 median | Candidate median | Median of paired differences |
|---|---:|---:|---:|
| Version/startup | 21.934 ms | 21.469 ms | −0.400 ms |
| Dry run | 21.349 ms | 21.935 ms | +0.718 ms |
| No-op | 30.956 ms | 22.036 ms | −8.595 ms |
| Tiny child | 50.565 ms | 42.082 ms | −9.551 ms |
| Check | 21.030 ms | 22.150 ms | +1.108 ms |
| Capabilities | 24.808 ms | 25.527 ms | +0.771 ms |

Ordinary execution improved in every paired no-op and child sample. The small
positive inspection/preflight differences are recorded rather than described
as zero overhead; they do not defeat small-command usability. Ranges, MAD,
ordering and raw outputs remain in the report.

A [separate fresh history run](../build/step07-execution-history-final.json)
used `test/scan-bench.lua --files 0 --ledger-records 10000 --repeats 3` with
valid v1 history seeded into the current UTC day's file. The 10,000-record
seed was **10,447,683 bytes**. Its child command's warm median was **70.77 ms**
(63.10–71.21 ms), versus 47.37 ms for its tiny no-seed control; capabilities
took **239.61 ms** (237.01–284.39 ms), including full verification. The
1,000-record case took 69.42 ms and 55.73 ms respectively. These small,
sequential samples establish usability at the tested size, not a precise
cost curve or arbitrary-history bound.

All 19 profiled run commands, plus three separate profiles after changing
0, 1 and 64 files, had no collector, `fs.dirs`, `hash.file` or `ledger.close`
phase. Profiles perturb timing and are separate from uninstrumented samples.
Selected day files are still read in full for predecessor/tail lookup, and
capabilities verifies all retained history. No constant-latency claim is made
for arbitrary history or arbitrarily large Git metadata.

## Artifact identity and limits

| Artifact | SHA-256 |
|---|---|
| Final unsigned candidate `build/kuu.exe` | `03e808952e60858ea233701d76d65e63be845e902e2e0b3654b75e3e2b5e5fd3` |
| Signed 0.11 baseline | `68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450` |
| Pre-removal Step 07 development build | `e5e8bcd28b84a772fbe4dff261923a1215d56c2fb0e48c0313d6b6832fd1599e` |

The host was Windows 11 25H2, build 26200.6899, unelevated, with 12 logical
processors. This is not separate Windows 11 23H2 hardware/VM evidence. Fixtures
are synthetic, retained locally, and neither first observations nor warm
medians are controlled cold-cache measurements. Reports retain raw output,
fixture paths, source/executable hashes and timing boundaries.

The follow-up began **2026-09-21 16:59:35 UTC** and took approximately
**18 minutes**, below the **25–45 minute** forecast, including implementation,
review, correction, sanitizer checks and final performance evidence. The
next step is **08: settle file-attribute semantics with bounded native probes**,
forecast at **10–20 minutes**. It remains unstarted.
