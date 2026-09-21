# Step 17 — relocation, offline diagnosis and owned cleanup

Status: **complete**. This finishes the owner's request for Steps **13–17
inclusive**. Step 18 has not started.

[Relocation](../docs/relocation.md) contains a complete health module, manifest
and obsolete-environment cleanup function. The latter reuses the published
bounded cleanup module. The guide covers maintained source renames, updated
Lua module references, whole-checkout relocation, Python venv/editable-install
recreation, and regeneration of local paths and shortcuts. It explains why
ignored old environments can survive tracked-file moves, and why an ownership
or relocation marker cannot establish package portability or readiness.

The doctor has no provisioning dependencies, package-manager calls or network
access. It checks an installed executable and a cached archive against reviewed
digests, reporting missing, unreadable, unexpected-kind and mismatching files.
Generated application output is separate: absent output is not-built; a present
file remains unverified and is never called ready. Normal task/run history is
still written, so the guide does not promise zero filesystem writes.

Cleanup accepts no arbitrary path. It chooses only `scripts/.venv` below the
canonical project root, checks every component and its bounded ownership
marker without following the final component, and rejects reparse metadata.
Exclusive maintenance is required: these path checks are not a sandbox against
concurrent replacement. Removal may be partial; if it consumes the marker,
a later invocation refuses unmarked remnants rather than manufacturing trust.

The index, adoption and upgrade guides link the new recipes. The env guide's
existing inheritance wording was corrected during integration, with Microsoft
references. The test driver and bundle order include the new case/page, and
all generated documentation is refreshed. The embedded manual has **53 pages**.

## Evidence

The **35 relocation assertions** execute the actual published blocks using
disposable fixtures. They move source files, demonstrate stale `require`
failure, update the references, move the complete checkout and invoke its own
copied runtime at the new path. They verify root-derived dependency paths;
missing/corrupt installed and cached files without repair; invalid pin documents
including JSON false/null/scalars; absent/present application output; and exact
owned cleanup with real junctions at ancestor, final and marker positions.
Readonly directories are removed while a junction's target, neighboring source
notes, current environment and dependency bytes survive. The cached dependency
fixture is a real locally packed ZIP; the doctor checks bytes, not rebuildability.

Independent reviews caught and resolved two draft issues before acceptance:
JSON `false` must be invalid pin data rather than a nil/nil early return, and
partial removal can consume the marker needed for a later cleanup invocation.
The testcase's unused `tostring` declaration was removed before the final
whole-tree declaration check. No runtime API defect or change was needed.

- Step 17 focused checks: **163 passed, 0 failed in 7.9 s** across
  `relocation cleanup_recipe project_environment working_directories docs bundle`,
  [log](../build/step17-tests.log).
- Final combined regression for Steps 13–17: **313 passed, 0 failed in 13.3 s**,
  [normal log](../build/steps13-17-final-normal.log).
- The same combined suites under ASAN: **313 passed, 0 failed in 40.8 s**,
  [ASAN log](../build/steps13-17-final-asan.log).
- Combined suites: `process_recipes working_directories project_environment
  relocation task_help ledger_execution docs bundle capabilities palette
  fixglobals`. This includes the actual documentation blocks, task/history
  boundaries, palette/capabilities consistency, all generated anchors and
  whole-tree global-declaration checks.
- Strict normal/ASAN builds, fixture build and bundle generation passed:
  [build](../build/step17-build.log), [bundle](../build/step17-bundle.log).
- Separate embedded retrieval checks read all four new recipe pages, the
  doctor section by anchor and the cache-variable search result:
  [log](../build/steps13-17-doc-retrieval.log).
- `git diff --check` passed. Earlier per-step evidence is in the
  [13](step13-flownet-feedback-2026-09-21.md),
  [14](step14-flownet-feedback-2026-09-21.md),
  [15](step15-flownet-feedback-2026-09-21.md) and
  [16](step16-flownet-feedback-2026-09-21.md) work notes.

Final normal executable SHA-256:
`ff33d7327ed8db4e3f7da5e80cb89081a860d000267a9a0fe5e90463f7791451`.
Final ASAN executable SHA-256:
`537ee49d01de03632cd44abecd210c24aee10de58ad4d87eeaf5c0573b8fa0f3`.

## Limits and timing

The host remains Windows 11 25H2 build 26200.6899, unelevated, on NTFS.
These checks do not constitute a new 23H2/Server compatibility run. Real
Python/uv installation and editable-package recreation were not exercised;
that guidance cites primary upstream documentation. GUI/profile verification,
native shortcut generation and dependency reconstruction remain Steps 18–20.
The full normal/ASAN/analysis/fuzz/soak and compatibility acceptance is Step 21.

The executable remains an unsigned development build reporting **0.11**.
No commit, push, signing, publication, version bump or FlowNet modification was
performed. Steps 13–17 added tested adoption guidance, not new native APIs.

Step 17 ran from **19:19:29 to approximately 19:26 UTC** on **2026-09-21**,
about **7 minutes**, against **30–60 minutes**. The combined Steps 13–17 work
started **19:03:21 UTC** and took approximately **23 minutes**, against
**90–160 minutes**, including review, builds, corrections and final checks.
Read-only preparation and independent review ran in parallel.

Next is **Step 18: detached editor and isolated GUI verification**, estimated
**30–60 minutes**. Steps **18–21** remain, retaining a combined forecast of
**1 h 55 min–3 h 45 min**. No later step was implemented in this turn.
