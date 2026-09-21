# Step 12 — task help and separator consistency

Status: **complete**. This concludes the owner's combined request for
[Step 10](step10-flownet-feedback-2026-09-21.md),
[Step 11](step11-flownet-feedback-2026-09-21.md) and Step 12. All three steps
passed their relevant checks; no scope decision or user intervention was
needed. The [sequential plan](plan-flownet-feedback-2026-09-15.md) now continues
with Step 13. No commit, push, signing, release or version change occurred.
FlowNet was not modified or executed.

## Behavior

`task.arguments` uses one help renderer for tasks with omitted and explicit
argument schemas. A non-empty description appears above usage, separated by
a blank line. Empty descriptions add nothing. A task without an argument
schema accepts exactly one trailing `--` as empty, matching `args={}`; actual
extra arguments remain errors and the caller's argument array is unchanged.

The CLI parser and runner ordering did not change. Rest schemas retain exact
argument forwarding, including an empty string, spaces, quotes, trailing
backslashes, a later literal `--`, and child `--help`. `run TASK --help` is
task help, whereas `run TASK -- --help` can execute dependencies and forward
help to a child only when the task schema and body support that operation.

Task help executes no task/dependency bodies or their children and writes no
execution history. A dependency's required arguments do not block selected
task help. Manifest top-level Lua still loads; configuration, manifest or
dependency-graph errors can still prevent help. These boundaries are explicit
in the [task manual](../docs/task.md#running-and-failing), and all three steps
are marked as unreleased in [upgrading from 0.11](../docs/upgrading-0.11.md).

## Final combined evidence

The new task-help suite has **42 checks**. It covers omitted/empty/required/rest
schemas, plain and JSON help, no new `.kuu` directory, unchanged existing
ledger bytes, body/child markers, required-dependency validation for real runs,
extra-argument rejection, exact forwarding and child exit 17 in both console
and JSON reports. Independent review found no further gap in code, tests or
documentation.

- Normal integration across **24 suites**: **1,261 passed, 0 failed in 32.9 s**,
  [final normal log](../build/steps10-12-tests-final.log).
- AddressSanitizer across **17 suites**: **1,058 passed, 0 failed in 51.3 s**,
  no sanitizer diagnostics, [final ASAN log](../build/steps10-12-asan-final.log).
- The combined normal run includes **28 native removal checks**, **21 cleanup
  recipe/adoption checks**, **115 declaration checks** and **42 task-help
  checks**, alongside existing filesystem, checker, CLI, task, history,
  reporting, scan, documentation and embedded-payload regression coverage.
- All **33** authored Lua modules/new test files selected for static checking
  passed with **0 errors and 0 warnings**,
  [JSON report](../build/steps10-12-static.json).
- Strict normal and ASAN builds, native fixture builds, GCC filesystem
  analysis, documentation generation and `git diff --check` passed.
  [Build log](../build/steps10-12-build.log),
  [bundle log](../build/steps10-12-bundle.log); Step 10 records the additional
  native-fixture analyzer run.
- Embedded retrieval succeeds for `kuu docs cleanup` and
  `kuu docs check task-and-tool-declarations`; outputs are retained in
  [cleanup help](../build/steps10-12-cleanup-help.txt) and
  [declaration help](../build/steps10-12-declaration-help.txt).

Normal command:

```powershell
& .\build\kuu.exe test/run.lua removal cleanup_recipe attributes fs paths declarations check check_corpus palette capabilities task task_help cli ledger ledger_execution execution_acceptance reporting docs bundle fixglobals entry embed scan_activation scan_native
```

ASAN command, with CLANG64 DLLs on PATH:

```powershell
$env:PATH = (Resolve-Path '.tools/msys2/clang64/bin').Path + ';' + $env:PATH
$env:KUU_TEST_ASAN = '1'
& .\build\kuu-asan.exe test/run.lua removal cleanup_recipe attributes fs paths declarations check check_corpus task task_help cli ledger ledger_execution execution_acceptance reporting scan_activation scan_native
```

Run suites sequentially because `test/run.lua` shares `build/test-work`.

Host: Windows 11 **25H2, build 26200.6899**, x64, unelevated, NTFS. Three
attribute symlink cases and the existing checker real-file-symlink case remain
explicitly skipped because Windows denies symlink creation. Real junction
cases passed. These runs do not claim independent Windows 11 23H2, SMB, ReFS
or cloud-provider results. The full compatibility/fuzz/soak/readiness gate
remains Step 21; no startup or observation behavior was changed in steps 10–12.

Final runtime SHA-256:
`d89b1ef55b0097ab531d31b8efdc46b608587b2d06b762ab7dc89226b78cb16c`.

Validated source SHA-256:

- `src/fs.c`: `98a6358b613fefb786b00211ba366f4645a04a9d0a3d396594532062da8e114a`.
- `lua/check.lua`: `99aaa3eaff17e841ba2b0c2bfc62cca4171215fdc115eab8bf29dd87a2e06d8b`.
- `lua/task.lua`: `3086f6daa2b95d14e218edf559c244047397124fa62a706919aec4026b7aa9a9`.

Step 12 began **2026-09-21 18:54:38 UTC** after Step 11 acceptance; final
combined validation finished **18:59:05 UTC**, approximately **5 minutes**,
against the **15–30 minute** forecast. Read-only preparation happened in
parallel with earlier steps. The combined turn began **18:42:37 UTC** and
took approximately **18 minutes including final reporting**, against the
combined **90–170 minute** forecast. Phase estimates/actuals are rounded;
parallel preparation is included in the combined elapsed time.

Step 13, process-description/outcomes/diagnostics recipes, is next and has not
started: **20–35 minutes** forecast. Remaining Steps 13–21 total **3 h 25 min–
6 h 25 min** under the existing individual forecasts.
