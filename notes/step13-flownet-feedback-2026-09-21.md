# Step 13 — process descriptions and outcome recipes

Status: **complete**, first in the owner's request for Steps 13–17. No runtime
API or version change, signing, publishing, commit or FlowNet modification.

[Process recipes](../docs/process-recipes.md) contains four complete programs:
a project module, controlled child probe, task manifest and command-description
program. Process descriptions separate an explicit JSON `argv` array from
`cwd` and the `env` overlay; mixed Lua process tables remain invalid JSON.
Descriptions state their limits: they omit inherited environment, timeout,
limits and stdin, and are not a complete replay format.

The module accepts documented nonzero success codes only through `TASK exit`
on the streaming path, retaining the actual child code in events and history.
Capture uses `task.command` plus `proc.run`, and explicitly documents that the
enclosing task/run are recorded but the individual captured child is not.
Failures distinguish launch, non-exit status, exit policy and truncation before
stdout decoding, retaining actual stderr, argv/cwd context, result and cause.
Environment values are excluded from failure messages. The agent, task, tool
and process manuals now consistently describe this supported capture boundary.

The new test case executes the documentation's actual blocks. It verifies
real exits, timeout, memory limit, launch failure, truncation, classification
precedence, copied JSON fields, unchanged strict JSON semantics, and actual
ledger/JSON child-event boundaries. The sample uses a literal project-owned
`kuu.exe`, copied into owned test fixtures; no external application or download
is needed. Independent review found no remaining issue.

- Normal regression: **272 passed, 0 failed in 7.2 s** across
  `process_recipes json task ledger_execution docs bundle`,
  [log](../build/step13-tests-final.log).
- New recipe suite under ASAN: **26 passed, 0 failed in 2.0 s**,
  [log](../build/step13-asan.log).
- Strict normal/ASAN builds and documentation regeneration passed;
  [build](../build/step13-build.log), [bundle](../build/step13-bundle.log).
- Every published Lua block passes static checking with zero errors/warnings
  as part of the recipe test. The manual now has 50 pages.

The initial run found two example/test assumptions: a dynamic `rt.exe` tool
declaration correctly produces a checker warning, and normalized executable
paths differ from raw Windows spelling. Using the project's literal runtime
path and comparing its normalized spelling fixed both; the final results above
supersede [that first run](../build/step13-tests.log).

Runtime SHA-256: `e103e3b994bfbb0f112bfebeb2189a21ab022cd007b5c136c58829259477d96b`.
Host remains Windows 11 25H2 build 26200.6899, unelevated, NTFS; this is not a
new 23H2 compatibility result. Full acceptance remains Step 21.

Started **2026-09-21 19:03:21 UTC**; accepted **19:09:04 UTC**, approximately
**6 minutes** against **20–35 minutes**. Read-only preparation for later steps
ran in parallel. Step 14 begins next under the same authorization.
