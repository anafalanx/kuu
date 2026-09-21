# Step 11 — static task and tool declarations

Status: **complete**, following Step 10 under the owner's authorization for
steps 10–12 together. No FlowNet changes, release, commit, push or signing.
See the [sequential plan](plan-flownet-feedback-2026-09-15.md).

The checker now recognizes task constructors as well as tool declarations,
in direct and curried forms, through simple copied local/module/member aliases
and saved curried constructors. Binding provenance retains conservative
shadowing and reassignment behavior. Indexed expressions are not accidentally
inferred as callable task constructors.

Literal names use the runtime rule `^[%w][%w%._%-]*$`: an ASCII letter/digit
first, followed by letters, digits, dots, underscores or hyphens. The `g++`
diagnostic suggests a project name such as `cxx`, without inventing a built-in
tool. A visible task `timeout` beside `run=function` is diagnosed at its own
line and points to child timeouts on `task.exec`, `task.defaults` or `task.tool`.

Independently known values are checked against runtime field constraints,
including function/string/boolean types, string arrays, CLI schemas and tool
durations. The checker does not evaluate project code. Unknown, computed,
repeated or reassigned values stay uncertain. A dynamic value can produce nil
and omit a field; unknown-key presence is not inferred from that expression.
Trailing nil array values are allowed. Unknown tool names/specifications do
not create false undeclared-tool findings for consumers.

Public [checker](../docs/check.md), [task](../docs/task.md),
[tool](../docs/tools.md) and [adoption](../docs/adopting.md) documentation now
explain these checks and the separate role of `kuu list`: it loads manifest
declarations and may execute arbitrary top-level Lua, rather than guaranteeing
provisioning or task readiness. Runtime validation rules themselves did not
change in this step.

## Validation

- New declaration suite: **115 checks** covering runtime identifier parity,
  direct/curried aliases, shadowing/reassignment, visible fields, dynamic/nil
  cases, consumer manifests and manifest nonexecution.
- Final integrated normal run: **512 passed, 0 failed in 15.6 seconds**,
  [log](../build/step11-tests-final.log).
- AddressSanitizer: **358 passed, 0 failed in 23.2 seconds**, no sanitizer
  diagnostics, [log](../build/step11-asan.log).
- All authored `lua/` modules and the new declaration/removal/cleanup suites
  passed static checking with zero errors/warnings,
  [JSON report](../build/step11-static.json).
- Strict normal/ASAN builds, documentation regeneration and `git diff --check`
  passed; [build log](../build/step11-build.log).

Normal suites: `declarations check check_corpus palette capabilities task
fixglobals docs bundle cleanup_recipe`. ASAN suites: `declarations check
check_corpus task`. Both use `test/run.lua`, sequentially; ASAN uses the
CLANG64 DLL path and `KUU_TEST_ASAN=1` as in Step 10.

Independent review found and resolved dynamic-nil presence, trailing nil list,
unknown tool identity and nameless tool-error handling issues before acceptance.
The new nonstring-name diagnostic cannot index a consumer's tool map with nil.
The first integration run found an unused `tostring` global in the new test;
the declaration-fixer removed it, and the final run passed. An additional
indexed-alias regression was included in the final executable and test count.

Runtime SHA-256 at Step 11 completion:
`41916cf27f226c44c76143d0c0b4acf6f77dcd9b254953b94866f1c7d8d55332`.
`lua/check.lua` SHA-256:
`99aaa3eaff17e841ba2b0c2bfc62cca4171215fdc115eab8bf29dd87a2e06d8b`.

Implementation began around **18:48 UTC**, after Step 10 passed, with read-only
investigation already performed alongside Step 10. Acceptance finished
**2026-09-21 18:54:38 UTC**, approximately **7 minutes** of sequential execution,
against the **45–90 minute** forecast. Earlier parallel investigation is included
in the combined steps 10–12 wall clock, not additional elapsed time. Step 12
then began.
