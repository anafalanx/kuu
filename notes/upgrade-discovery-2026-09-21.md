# Agent discovery when upgrading from signed 0.11

Follow-up to the completed FlowNet feedback plan: make the next executable
explain its changed contract to agents arriving with signed-0.11 expectations.

The development changes were previously buried in a page titled **Upgrading to
0.11**. They now live in [Upgrading from 0.11](../docs/upgrading-from-0.11.md),
available offline as `kuu docs upgrading-from-0.11`. The old page retains the
historical signed-release guidance and points to the new page.

Entry help (including no arguments), documentation help/listing, capabilities
text and JSON `next`, the agent guide, index, README and adoption instructions
all expose the migration path. The new page gives an ordered checklist and a
short bootstrap for project agent instructions. It covers stale tree-observation
claims, v1/v2 history, removed JSON fields, inspection exclusions, captured tool
output, attributes, stronger declaration checking and the new recipes. Existing
task declarations do not require wholesale replacement.

The guide distinguishes embedded docs and static checking from commands that
execute a manifest. Candidate validation happens in an isolated project copy;
the adoption guidance no longer implies that saving an old binary alone proves
rollback works after new live history has been written.

## Validation

- Normal strict build and GCC native static analysis passed.
- Focused `entry docs upgrade_discovery capabilities bundle fixglobals` tests:
  **196 passed, 0 failed** with the normal executable (7.4 seconds), and
  **196 passed, 0 failed** with AddressSanitizer (28.6 seconds).
- The new eleven-check journey copies the executable without its source/manual
  files, follows discovery hints, and retrieves the embedded page and its section.
  Retrieval also succeeds beside deliberately stale local documentation and an
  invalid project configuration, without evaluating a side-effecting manifest
  or creating `.kuu` state.
- The generated manual contains **57 pages**. Bundle, usage-block, page inventory,
  link-destination and declaration checks passed. `git diff --check` passed.

Logs: [build and analysis](../build/upgrade-discovery-build.log),
[normal tests](../build/upgrade-discovery-test.log),
[ASAN tests](../build/upgrade-discovery-asan.log).

Unsigned `build/kuu.exe`: **2,034,176 bytes**, SHA-256
`5a4fab1e5c63331e803428b625f95009be7c30d26506fa613e079c44bdb34b93`.
It still reports `0.11`. The previous full gate and performance evidence in
[Step 21](step21-flownet-feedback-2026-09-21.md) applies to its recorded earlier
artifact; this follow-up changed help, discovery text and documentation and ran
the focused checks above. It did not repeat performance or platform certification.

Release preparation must replace the explicit unreleased-development caveats
with the chosen release identity and corresponding feature guards. No version
bump, commit, push, signing or publication was performed here, and no external
project was changed.

## Project evaluation follow-up

The migration checklist, reusable agent instructions, agent reporting guide and
adoption guide now explicitly require maintaining the project's `kuu-eval.md`.
Agents read earlier feedback, append dated evidence and follow-ups, preserve old
entries, identify the tested artifact and conditions, and distinguish verified
fixes from workarounds or untested claims. Relevant isolated-copy results belong
in the project's maintained document; candidate testing is distinct from adoption.

After this documentation-only follow-up, the embedded manual and bundle were
rebuilt. Existing `docs upgrade_discovery bundle` checks passed: **64 passed,
0 failed**, 2.7 seconds; whitespace validation passed. Logs:
[build](../build/eval-docs-build.log), [tests](../build/eval-docs-test.log).
This build is **2,037,248 bytes**, SHA-256
`b7f3b3348d3a105aefeb0ec98356f003ada852f302c473c0a371488d9b49331a`.
The earlier normal/ASAN results above remain evidence for their recorded artifact.
