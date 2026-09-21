# Step 15 — both runtime distribution models

Status: **complete**, under the owner's combined Steps 13–17 request.

The adoption guide now explicitly supports a downloaded, ignored runtime and
a committed runtime. Both keep a reviewed release identity, exact SHA-256 and
expected signing-certificate pin. Ignore examples keep generated tools, state
and outputs out of Git while leaving the runtime choice to the project.
Minimum-version guards describe required features, not approved binary identity.

The complete PowerShell example verifies the candidate through platform APIs
before running it. Placeholder pins fail; an arbitrary new sidecar does not
replace approved pins. Upgrades stage and verify a chosen replacement and
review its pins, along with the executable in the committed model. Unsigned
development builds require their own recorded provenance and hash.

Updated [adopting](../docs/adopting.md), [agent](../docs/agent.md),
[toolchain](../docs/toolchain.md), [upgrading](../docs/upgrading-0.11.md), and
the handwritten adoption section of [kuu.md](../kuu.md). The generated manual
was refreshed. This repository's own `.gitignore` remains unchanged.

- Documentation/bundle checks: **53 passed, 0 failed in 3.6 s**,
  [log](../build/step15-tests.log).
- Actual PowerShell block parsed; unchanged placeholder pins, a wrong digest,
  and a matching digest on this unsigned development runtime were all refused.
  No candidate was launched: [log](../build/step15-verification.log).
- Commands checked against primary Microsoft documentation linked in the
  guide. Positive signed-release verification was not exercised in this step.
- Strict normal/ASAN builds and bundle generation passed:
  [build](../build/step15-build.log), [bundle](../build/step15-bundle.log).
  No new runtime code or sanitizer-specific behavior was introduced.

Runtime SHA-256: `7cf74eadfb887c6d4cd5899ff28caa1b508a39992b2f5e1c5bff782a1ae2284a`.
No commit, release, version bump or FlowNet change. Step 21 retains the full
integration and compatibility gate.

Approximately **3 minutes** after Step 14 acceptance, through **19:16 UTC**
on **2026-09-21**, against **10–15 minutes**; the earlier wording audit ran in
parallel. Step 16 follows under the same authorization.
