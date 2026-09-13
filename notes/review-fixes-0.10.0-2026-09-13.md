# Corrections following the 0.10.0 review

The review identified 23 prioritized findings and four smaller validation or
documentation issues. The corrections are grouped below by their review IDs.
They are working-tree changes for the next release; this work does not change
the version or publish an executable.

| Review IDs | Correction | Regression coverage |
|---|---|---|
| 1, 7, 8 | The global fixer refuses initialized or unsupported declarations, retains strict globals, and handles long comment headers. Refused source remains unchanged. | `test/cases/fixglobals.lua` |
| 2, 6 | HTTP downloads retain their absolute destination across waits and reject embedded NUL output paths before opening a file. | `test/cases/http.lua` |
| 3 | Packing stages the new archive beside its destination and promotes it only on success. Validation and packing failures preserve the previous archive. Exact exclusions keep the old and temporary output out of input traversal; compact temporary names preserve long output filenames. | `test/cases/archive.lua` |
| 4 | Streaming processes can inherit stdin independently of output. JSON task execution preserves input bytes and EOF, including an explicit `inherit_stdin` request. | `test/cases/proc.lua`, `test/cases/task.lua` |
| 5 | Aggregate process waiters retain their allocations until cleanup, including partial completion and allocation failure. | `test/fixtures/proc_waiter_fixture.c`, `test/cases/proc.lua` |
| 9 | The checker supports Lua 5.5 named varargs and reports unexpected analysis failures through its normal envelope. | `test/cases/check.lua` |
| 10 | Ledger write and close failures warn without changing task success or suppressing the final report. | `test/cases/ledger.lua` |
| 11 | Ledger readers validate record shape, and capabilities reports a broken chain even when no recent record is readable. | `test/cases/ledger.lua` |
| 12 | Dependencies and tool lists require contiguous arrays of strings. | `test/cases/task.lua` |
| 13 | A shared private JSON-report helper repairs invalid UTF-8 in values and keys without losing entries when repaired keys collide. | `test/cases/capabilities.lua`, `test/cases/task.lua` |
| 14 | Export inference treats escaped table references conservatively, including ordinary aliases. | `test/cases/check.lua` |
| 15 | Tool argument checking honors inline values and the end-of-options delimiter. | `test/cases/check.lua` |
| 16 | Malformed literal tool declarations produce findings instead of crashing descriptor serialization. | `test/cases/check.lua` |
| 17 | Directory pruning takes precedence over depth-limit reporting. | `test/cases/fs.lua` |
| 18 | Unrenderable log messages and failed writes/flushes count as drops; logging does not raise on those failures. Custom sinks may return failure explicitly. | `test/cases/log.lua` |
| 19 | Marked JSON containers reject holes and extra keys; ordered objects reject duplicate names. | `test/cases/json.lua` |
| 20 | Required rest arguments require at least one value, except when requesting help. | `test/cases/cli.lua` |
| 21 | The manual generator emits explicit page and section anchors, preserves section destinations, and checks for missing or duplicate targets. Two source links that incorrectly referred to another page as a local section were corrected. | `test/cases/bundle.lua` |
| 22 | Numeric Windows version resources retain the patch component and reject malformed or out-of-range components. | `test/fixtures/versionrc_fixture.c`, `test/cases/entry.lua` |
| 23 | The confined-tool guide distinguishes directory-link inspection from file-link inspection and requires checking inspection errors. | Source/documentation consistency review |
| Additional: sizes | Overflowing size strings are rejected instead of returning infinity. | `test/cases/cli.lua` |
| Additional: INI | Setting and encoding keys share validation, rejecting names that become comments, sections, or differently trimmed keys. | `test/cases/ini.lua` |
| Additional: CSV | Header-mode decoding and record encoding reject duplicate column names; array mode preserves cells. | `test/cases/csv.lua` |
| Additional: gate docs | README and release checklist correctly include ASAN in the full gate. | Makefile/documentation consistency review |

The waiter ownership fixture was also compiled against an isolated copy of the
old faulty callback: the old code fails and the corrected code passes. The
original repeated-wait reproduction no longer accumulates private memory after
garbage collection on this host.

Final validation on 2026-09-13: `make -j8 gate` completed with exit 0.

- Normal build: 1,480 checks passed, zero failed, in 43.9 seconds.
- AddressSanitizer build: 1,480 checks passed, zero failed, in 73.1 seconds.
- Native static analysis passed.
- All three deterministic fuzz seeds passed (10,000 cases per parser family).
- Soak: 26 rounds in 62 seconds, zero failures, handles -3, private memory
  +2.8 MB over the run.
- `git diff --check` passed.

The complete local log is `build/fix-010-gate-final.log`. The first integrated
run exposed a remaining cross-page link written as a local fragment; the
new link-validation regression caught it, it was corrected, and the final
gate above includes that correction. Additional archive checks cover output
inside the source tree and long filenames discovered during review of the fix.
