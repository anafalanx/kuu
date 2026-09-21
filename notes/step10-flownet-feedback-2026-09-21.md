# Step 10 — recursive cleanup and bounded publication

Status: **complete**, as part of the owner's request to execute steps 10–12
together. This continues unreleased development after 0.11; no release,
commit, push or signing was performed. FlowNet was not modified or executed.
See the [sequential plan](plan-flownet-feedback-2026-09-15.md).

## Implementation

Completed directories in `remove_tree` now use `remove_one`, as file leaves
and link entries already do. Readonly clearing opens the final entry with
`FILE_FLAG_OPEN_REPARSE_POINT`, queries its current basic information, clears
only readonly, normalizes NORMAL, and writes zero timestamp fields. Every
open/query/set failure is checked and preserved before handles are closed.
Link target attributes are untouched. Initial root-path allocation is checked,
and `l_fs_remove` now saves a failed metadata query's error before closing.

Deletion remains path based and nontransactional. Concurrent path replacement
is not a containment guarantee. Earlier entries may have been deleted; a
cleared readonly bit can remain clear when deletion fails. No unsafe rollback
or per-entry long retry was introduced.

The new [cleanup guide](../docs/cleanup.md) provides a project module and a
complete pinned-archive extraction/validation/publication program. The module
retries only `FS access`, uses monotonic time and scheduler sleeps, and keeps
one retry budget for a whole removal operation. A missing descendant alone
does not count as a removed root. Publication never replaces the destination;
its primary failure and secondary staging-cleanup failure are retained.
Validation raises are retained too. The guide explicitly bounds retries and
waits, not synchronous filesystem-call duration, and explains that publication
and subsequent cleanup have separate budgets. No localized messages are parsed.

The adoption guide's clean task now returns deletion failure and tolerates a
confirmed absent root. Public filesystem documentation covers readonly
directories and partial effects. The embedded guide is discoverable through
`kuu docs cleanup`; documentation generation now includes 49 pages.

## Evidence

The independent native fixture establishes readonly trees, root/nested/dangling
junctions, ACL-denied attribute writes/deletes and held deletion-sharing
handles. Tests verify outside target bytes and metadata, failing paths/native
errors, partial effects and successful subsequent cleanup. The recipe suite
executes the actual documentation blocks, checks deterministic total-budget
behavior, real temporary/persistent sharing denial, non-access failures,
raised/returned validation errors, existing destinations, local extraction and
hash rejection with staging cleanup. Only owned disposable trees are mutated.

- Normal focused regression: **407 passed, 0 failed in 7.5 seconds**,
  [final log](../build/step10-tests-final.log).
- AddressSanitizer: **354 passed, 0 failed in 6.5 seconds**, no sanitizer
  diagnostics, [log](../build/step10-asan.log).
- Strict normal/ASAN builds and GCC analysis of `src/fs.c` passed,
  [build log](../build/step10-build.log).
- Native fixture compiled with `-fanalyzer -Wall -Wextra -Werror`,
  [analysis log](../build/step10-fixture-analysis.log).
- New Lua suites passed static checking with zero errors/warnings,
  [JSON report](../build/step10-static.json).
- A follow-up extracted the adoption guide's actual clean declaration and
  verified error propagation and confirmed-absence handling: **21 recipe
  checks passed**, including three adoption checks,
  [log](../build/step10-adoption-tests.log). These also run in final integration.
- `git diff --check` passed. The first integrated run found stale generated
  capability figures after adding the new documentation page; regeneration
  against the rebuilt runtime corrected them. The retained first log is
  superseded by the final result above.

Commands (run suites sequentially; they share `build/test-work`):

Normal: `build/kuu.exe test/run.lua removal cleanup_recipe attributes fs paths docs bundle`.
ASAN: with `.tools/msys2/clang64/bin` on PATH and `KUU_TEST_ASAN=1`,
`build/kuu-asan.exe test/run.lua removal cleanup_recipe attributes fs paths`.
Build: `.tools/msys2/ucrt64/bin/mingw32-make.exe -j4 all build/kuu-asan.exe fixtures build/analyze/fs.o`.

Host: Windows 11 25H2 build 26200.6899, x64, unelevated, NTFS. The existing
attribute suite still explicitly skips its three real symlink cases on this
host (Windows 1314); real junction removal tests ran. No 23H2 VM result is
claimed. The complete readiness gate remains Step 21.

Runtime SHA-256 at Step 10 completion:
`d0930323fe46e94834937c1ee7e854f71d2da62abeb78127b414e522d1270bf2`.
`src/fs.c` SHA-256:
`98a6358b613fefb786b00211ba366f4645a04a9d0a3d396594532062da8e114a`.

Started **2026-09-21 18:42:37 UTC**; focused implementation and validation
finished around **18:48 UTC**, approximately **6 minutes** against the
**30–50 minute** forecast. Step 11 then began under the same authorization.
