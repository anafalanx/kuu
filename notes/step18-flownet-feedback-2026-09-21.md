# Step 18 — detached editor lifetime and private GUI verification

Status: **complete**, first in the owner's request to finish Steps 18–21.

[The editor guide](../docs/editor.md) contains a tested manifest using the
shared project environment for a supervised operation and a detached launch.
Its native project helper, [gui_probe.c](../examples/gui_probe.c), creates a
fresh owned profile and private desktop, starts its own actual window with an
EDIT control, and independently observes that window before accepting the
nonce-bearing readiness signal. It never switches the interactive desktop.

The native supervisor retains its child process handle and a kill-on-close job,
bounds readiness and shutdown, and removes only known files in its own fresh
profile. Reports preserve verification status, Win32 errors and cleanup errors.
Unknown profile entries cause cleanup failure and are preserved. Existing
profiles/reports are refused. A held-readiness handshake proves the supervisor
and GUI outlive the kuu launcher, then releases them within a fixed budget.

The guide separates launch from readiness, task/child history from detached
lifetime, and this probe's evidence from arbitrary editor compatibility. It
explains fresh profiles, live database/WAL snapshot consistency, platform access
limits and the absence of a security-sandbox guarantee, citing Microsoft and
SQLite primary references. No real editor profile or FlowNet process is used.

Updated the Makefile fixture target, test driver, manual index, proc/environment
crosslinks, bundle order and generated manual. There are **54 embedded pages**.

- Normal regression: **368 passed, 0 failed in 16.5 s** across
  `editor_recipe project_environment proc task ledger_execution docs bundle`,
  [log](../build/step18-tests.log).
- ASAN recipe/environment checks: **56 passed, 0 failed in 5.5 s**,
  [log](../build/step18-asan.log). The new editor case contributes **29 checks**.
- The published Lua manifest/module passes static checking with no errors or
  warnings. Native code builds with strict warnings as errors; standalone
  GCC `-fanalyzer -O0` also passed (analysis object
  `build/gui-probe-agent-analysis.o`). External GUI fixtures use GCC; the ASAN
  checks instrument kuu, not that separately compiled helper.
- Native independent smoke reports cover ready, held readiness, timeout and
  early exit, with stopped children and removed profiles:
  [reports](../build/gui-probe-agent-fab9e55485554957a6d3126e94d82fc2).
- Normal/ASAN builds and bundle generation passed:
  [build](../build/step18-build.log), [bundle](../build/step18-bundle.log).

Runtime SHA-256: `3faa7d03f965721b699e7ab97f404f65f6f6b9b631e490c919ebd72d6ed82bc0`.
Host is still Windows 11 25H2, unelevated. Private desktop permissions and job
policy may differ on service/CI sessions; failures never fall back to a visible
desktop. This is not a new 23H2/Server or arbitrary-editor certification.

Started **2026-09-21 19:31:01 UTC**; accepted approximately **19:39 UTC**,
about **8 minutes** against **30–60 minutes**. Native implementation and Lua
tests ran in parallel with documentation/integration; later steps received
read-only preparation. Step 19 follows. No release or external project change.
