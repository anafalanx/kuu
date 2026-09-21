# Step 16 — shared project environment and cache placement

Status: **complete**, under the owner's combined Steps 13–17 request.

[Project environment](../docs/project-environment.md) contains three complete
programs: a shared module, manifest and selected-variable probe. The module
anchors uv/npm/Go cache paths and the uv project environment to the manifest's
root, creates a fresh child overlay, and explicitly removes three inherited
Python activation settings. Other inherited variables remain; the text does
not describe this partial overlay as a clean environment.

Supervised CLI calls use `task.exec`. New detached processes use the same
overlay and declared executable through `task.command`, copying only argv,
cwd and env because detach does not accept task timeouts. Existing editors
retain their original environment; a forwarded request is not a fresh launch.
The example opens no GUI and logs only selected test variables. Real GUI
lifetime/readiness verification remains Step 18.

The env/proc/adoption guides and index link the new page. The bundle order,
test driver and generated documentation were updated; there are now 52 manual
pages. Primary uv/npm/Go documentation supports the concrete variables and is
linked in the guide. No actual language toolchain installation was needed.

Integration review also corrected the existing env page's broad claim that
every newly opened console receives persisted changes: a child inherits its
launcher's live copy unless an explicit block is supplied. Broadcast refresh
depends on the receiving application. The page links the primary Microsoft
contracts; Step 17's final bundle checks include this wording correction.

- Focused regression: **345 passed, 0 failed in 18.6 s**, across
  `project_environment env proc task docs bundle`,
  [log](../build/step16-tests.log).
- Independent review led to stronger test cleanup: confirm the detached PID
  still names the fixture's unique executable before terminating it, then wait
  within a bound and check it is gone. The final recipe passes **27 normal
  checks in 0.5 s** and **27 ASAN checks in 1.3 s**, zero failures:
  [normal](../build/step16-recipe-final.log), [ASAN](../build/step16-asan.log).
- Tests execute the published blocks, check/list without provisioning, launch
  from root/nested cwd, replace conflicting cache variables, remove selected
  variables, preserve an unrelated sentinel, and avoid printing a dummy secret.
- PATH is genuinely empty in both normal and ASAN fixtures. The test-only
  ASAN runtime's two non-system DLLs are copied beside its owned executable;
  this does not change the static production runtime's distribution.
- Strict normal/ASAN builds, bundle generation and static recipe checks pass:
  [build](../build/step16-build.log), [bundle](../build/step16-bundle.log).

Runtime SHA-256: `bf62bb3b5e78541527c565a5504812e96dd249c0e8ebcf1f36f46f3ef4f3d913`.
No runtime API, version, release or FlowNet change. Full compatibility and
integration acceptance remains Step 21.

Approximately **4 minutes**, from Step 15 acceptance at **19:15:35 UTC** to
**19:19:29 UTC** on **2026-09-21**, against **15–25 minutes**. Upstream reference
and design preparation ran earlier in parallel. Step 17 follows next.
