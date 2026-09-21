# Step 14 — explicit working directories through nested wrappers

Status: **complete**, under the owner's combined Steps 13–17 request.

[Working directories](../docs/working-directories.md) supplies three complete
programs: a wrapper, manifest and diagnostic child. The wrapper captures the
caller cwd before entering the project, locates its project through its script
root, and supplies an explicit task `--cwd`. The manifest validates an absolute
directory and launches its declared tool there. Arguments remain arrays through
both process boundaries; ordinary child exits are forwarded unchanged.

The guide distinguishes caller, wrapper, project, child and module directories.
It explains why manifest-level `fs.cwd()` cannot recover the original caller.
No new runtime API is needed. The task manual and index link the recipe; it is
included in the embedded manual and generated bundle (now 51 pages).

The new test executes the actual documentation blocks from project-root,
nested and unrelated directories, including paths with spaces, apostrophes and
Unicode. Arguments include empty strings, quotes, trailing backslashes and
literal task-looking flags. Invalid cwd values, a missing nested runtime,
relative wrapper invocation, and nonzero child exit propagation are covered.

- Focused normal regression: **148 passed, 0 failed in 4.3 s**, across
  `working_directories process_recipes task_help docs bundle`,
  [log](../build/step14-tests.log).
- New recipe under ASAN: **27 passed, 0 failed in 1.4 s**,
  [log](../build/step14-asan.log).
- Published blocks pass static checking with zero errors/warnings.
- Normal/ASAN builds and bundle regeneration passed:
  [build](../build/step14-build.log), [bundle](../build/step14-bundle.log).

Runtime SHA-256: `837a686caa7134e237bad8b2c5ce087c19e5914551b0b1770315b34b542d9466`.
Host is unchanged from Step 13; this is not a new 23H2 compatibility result.
No version bump, release, commit or FlowNet change.

Acceptance work ran from **19:09:04 to approximately 19:13 UTC** on
**2026-09-21**, about **4 minutes** against **15–25 minutes**, with earlier
recipe preparation in parallel. Step 15 follows under the same authorization.
