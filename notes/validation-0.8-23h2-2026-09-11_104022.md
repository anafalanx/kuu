# Published 0.8 validation on Windows 11 23H2

The owner requested a GitHub sync and promotion of the published Kuu 0.8
executable into Time Actual. Kuu fast-forwarded to `b169ac8`; Time Actual
was already at `b55e5e1`. This validates the final signed artifact on the
23H2 host that was unavailable during release publication.

## Artifact and promotion

- Release: https://github.com/anafalanx/kuu/releases/tag/0.8
- Release commit: `f5c112b633b089e3749805733ec1b5d1bd81fff2`.
- Executable: 1,542,008 bytes.
- SHA-256: `91e50197decee3206554cdcfae0c691abe4a7682c8dbb756d793d19afd84f48d`.
- The executable matches the published sidecar and GitHub asset digest;
  the sidecar also matches its own GitHub asset digest.
- Windows Authenticode: valid, timestamped, expected signer
  `Open Source Developer Vincent Vercauteren`, certificate thumbprint
  `FFF5468E3B61A5C466FC5A07A7BB9FD2B9975B4B`.
- Host: Windows 11 Enterprise 23H2, build 22631.7517.
- The published executable starts and reports `kuu 0.8 (Lua 5.5.1)`.
  Its import table does not contain `ReleasePseudoConsole`.
- The verified release is now `_timeactual/kuu.exe`. The preceding unsigned
  compatibility build is retained under that project's `.tools/kuu-backups/`;
  a timestamped receipt records the release, digest and backup path.

## Release tests on 23H2

Compiled the updated native fixtures with the local GCC toolchain, then
ran `test/run.lua` using Time Actual's actual signed root executable.

The full suite completed in 55.2 seconds: **1,045 passed, 2 failed**. The
signed executable adds the signer-identity check to the unsigned suite.
All **48 console checks** passed, including pending input/output shutdown,
resize after exit, and an exited console whose finalizer is followed by a
finalizer that runs another process. The native orphaned-I/O dispatch
regression also passed, as did signature identity and tamper checks.

Both failures came from the existing intermittent memory-file replacement
issue: Windows error 5 (`FS access`) stopped one concurrent counter at 69,
then its dependent expected-value assertion failed. The isolated `mem`
case subsequently passed **19 checks** in 2.2 seconds. This does not erase
the full-suite failure or identify its cause. See the existing finding in
[observed shortcomings](../docs/shortcomings.md#intermittent-access-denied-while-replacing-files).

No AddressSanitizer or soak run was repeated for this artifact adoption.
The separate release record covers those gates on 25H2.

## Time Actual validation

Using the promoted signed executable and the existing project-local tools:

- Source check: 8 Lua files, no errors or warnings.
- Complete `test` task graph: JSON dry-run passed.
- Task integration: 9 checks passed.
- Prerequisite-recovery fixtures: 17 checks passed.
- Engine unit tests: 2,191 checks passed.
- Application rebuilt; isolated self-test: `status=ok`, `bgerrors=0`.

The task and recovery scripts ran directly, followed by the repository's
build module for unit tests, compilation and application checks. This was
not a new cold toolchain provisioning or Tcl/Tk rebuild.

Time Actual's local CI URL/digest and current setup documentation now
select 0.8. Its API minimum remains 0.5; the documented supported runtime
for 23H2 is 0.8 or later. These adoption source/documentation edits were
left local; no publication of this follow-up was requested.

Ignored evidence in Kuu: `build/0.8-consumer-fixtures.log`,
`build/0.8-signed-23h2-tests.log`, `build/0.8-signed-23h2-mem-recheck.log`.
Time Actual evidence: `build/kuu-0.8-test-plan.json`,
`build/kuu-0.8-task-tests.log`, `build/kuu-0.8-recovery-tests.log`,
`build/kuu-0.8-build-tests.log`, and `.tools/kuu-backups/promotion-*.json`.
