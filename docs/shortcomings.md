# Shortcomings observed in real use

Findings from adopting Kuu in real repositories. Record the trigger, impact,
workaround, and verification status. A limitation or rough edge is not
necessarily a runtime defect; fixes should follow reproduced evidence.

## Time Actual adoption — 2026-09-10

0.6 addresses seven runtime/API findings below. The
Tcl sandbox limitation remains external; the windres recipe issue is resolved
in Time Actual. Original observations and 0.5 workarounds are retained for context.

### `kuu version` executes a repository's VERSION file

- **Kind:** command-line diagnostic / discoverability.
- **Observed:** in Time Actual, `kuu.exe version` resolves the case-insensitive
  `VERSION` filename and reports `version:1: unexpected symbol near '0.58'`.
- **Impact:** an intuitive version query produces an unrelated Lua parse error.
- **Workaround:** use `kuu.exe --version`.
- **Status:** Fixed in 0.6. `version` is a reserved verb; `./version` still
  executes a file. Both version forms reject extra arguments.

### Dependency-only tasks require an empty function

- **Kind:** task declaration friction.
- **Observed:** declaring `test` with `deps` but no `run` passes `kuu check`,
  then `kuu list` fails with `TASK badvalue: task 'test' needs a run function`.
- **Impact:** aggregate tasks need boilerplate, and syntax checking alone
  does not validate declarations.
- **Workaround:** add `run = function() end`; run `kuu list` as well as `check`.
- **Status:** Fixed in 0.6. A task with non-empty dependencies may omit `run`;
  cycles, failure propagation, argument checks, and JSON plans still apply.

### Restricted networking produces an opaque WinHTTP error

- **Kind:** error diagnostics / execution environment.
- **Observed:** upstream HTTPS requests inside the agent's restricted sandbox
  returned `HTTP oserror: ... Windows error 12185`. The same requests succeeded
  with network permission, with no runtime or URL change.
- **Impact:** the message gives little guidance about the network/proxy context.
- **Diagnosis:** Windows defines 12185 as a client-certificate context without
  an associated private key. The different execution contexts explain the
  observed success/failure difference; the number alone does not prove a ban.
  See [Microsoft's error reference](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages).
- **Workaround:** use the execution context with the required network and
  certificate access; inspect its credential configuration when necessary.
- **Status:** Diagnostic fixed in 0.6. Errors 12185–12188 are `HTTP tls`, with
  named client-key/proxy causes and actionable context. The hosting restriction itself
  is external.

### CLI durations cannot be passed directly to process timeouts

- **Kind:** cross-module unit mismatch; confirmed during real task execution.
- **Observed:** `cli` parses `--timeout 100ms` as the integer `100` (milliseconds).
  Passing this value directly to `proc.run { timeout = opts.timeout }` sets a
  **100-second** deadline, because numeric process durations are seconds.
  A fixture sleeping for 30 seconds completed instead of timing out at 100 ms;
  an enclosing 10-second deadline subsequently confirmed the mismatch.
- **Impact:** natural composition silently lengthens a deadline by 1,000 times.
  This remains after the duration grammar was unified in the 0.5 review fixes.
- **Workaround:** pass `tostring(opts.timeout) .. "ms"` to the process API.
  Time Actual retains this for 0.5 compatibility and exercises both runtime versions.
- **Status:** Fixed in 0.6. CLI results, bounds, and choices use seconds, matching
  native consumers. This is an intentional API change; see [migration
  notes](upgrading-0.6.md). Time Actual handles both 0.5 and 0.6 explicitly.

### Tcl path normalization fails inside the agent's filesystem sandbox

- **Kind:** hosting-environment limitation, not established as a Kuu defect.
- **Observed:** the same locally built Tcl 9.0.3 normalized
  `C:/Users/.../HEAD/dev/_timeactual/.tools/twapi` into a path missing
  `HEAD/dev` inside the agent sandbox. TWAPI loading failed, and the packaged
  GUI self-test timed out before producing its report.
- **Control:** outside that sandbox, the same interpreter returned the exact
  path, loaded TWAPI 5.2.0, and the packaged app passed its self-test.
- **Workaround:** execute affected Tcl/GUI tasks in a normal Windows process
  with the agent's required execution permission. Headless engine/task tests
  can still run inside the sandbox.
- **Status:** External limitation remains. Normal Windows execution passes; no Kuu
  runtime defect was demonstrated.

### `archive.list` returns non-UTF-8 filenames on Windows

- **Kind:** encoding defect at an API boundary.
- **Observed:** listing the official Go 1.27.1 Windows ZIP returns two names
  under `go/test/fixedbugs/issue27836.dir/` containing the single byte `0xDE`.
  `utf8.len` rejects both at byte 34; saving the inventory with `json.encode`
  fails with `JSON encoding: a string is not valid UTF-8`.
- **Impact:** extracted files are usable, but archive listings do not compose
  safely with Kuu's UTF-8/JSON/file APIs. A prerequisite task can fail after
  successfully unpacking its tool.
- **Workaround:** if a listing has invalid UTF-8, inventory extracted files
  with `fs.glob` and `fs.relative`, which return native Unicode paths. Time
  Actual initially used this fallback. Its current recovery installer
  inventories extracted files directly with an anchored `fs.list` walk.
- **Status:** Fixed in 0.6. A supervised native reader uses the Unicode API in
  Windows archiveint.dll, without extraction or ANSI-output guessing. Unicode, JSON,
  empty archives, and cancellation have regression coverage.

### Downstream tools can reintroduce shell quoting problems

- **Kind:** external tool limitation encountered through process orchestration.
- **Observed:** a moved Time Actual checkout named `Time Actual` reached the
  native resource build, then windres failed because its internal preprocessor
  command split the path at the space. Kuu had passed the original argv intact.
- **Workaround:** use windres's `--use-temp-file` mode, run it in `build/`, and
  pass relative resource/include paths. The moved checkout then built and
  passed its tests with the original toolchain directories unavailable.
- **Status:** Resolved in the Time Actual recipe. The internal-command boundary and
  windres workaround are documented in [proc](proc.md); no Kuu quoting defect was
  demonstrated.

### Process metadata and filesystem paths use different separators

- **Kind:** API composition friction; native Windows paths are both valid.
- **Observed:** `proc.tree` returned executable paths with backslashes, while
  `fs.absolute` returned forward slashes. A case-insensitive string comparison
  missed the expected child and could have hidden survivors in a cleanup test.
- **Workaround:** normalize the process path with `fs.absolute` before comparing
  it with another absolute path. Use canonical file identity when aliases matter.
- **Status:** Fixed in 0.6. Process `exe` paths use forward slashes like
  `fs.absolute`; command lines remain unchanged. Regression coverage checks a real child
  process.

### ZIP creation loses names outside the system code page

- **Kind:** confirmed encoding defect in the archive wrapper's writer options.
- **Observed:** the Unicode regression packed `漢字.txt` using Windows tar's
  default ZIP settings. The archive contained `??.txt`, which extracted as
  `__.txt`. Tar-family archives preserved the same name.
- **Impact:** a successful ZIP pack could silently rename a source file.
- **Fix:** pass `--options zip:hdrcharset=UTF-8` for ZIP creation.
- **Status:** fixed in 0.6; the regression compares the source name,
  Unicode listing, and extracted file for ZIP and compressed tar formats.

### Intermittent access denied while replacing files

- **Kind:** observed file-access failure; underlying cause not isolated.
- **Observed:** one full Kuu run reported Windows error 5 during an atomic
  `mem.update` write. That stopped one concurrent counter and caused two related
  checks to fail. Later, Time Actual's native `strip.exe` reported permission
  denied replacing a freshly linked executable. The file was not read-only,
  and no running application held that executable when inspected.
- **Control:** the memory case passed alone, then passed five consecutive
  runs; the complete Kuu suite subsequently passed. The exact strip operation
  passed on retry, followed by a successful complete Time Actual build/test.
- **Status:** observed, not reproduced deterministically. Do not attribute it
  to a Kuu locking defect, antivirus, or the filesystem sandbox without more
  evidence. No permission bypass or unconditional retry was added.
- **23H2 follow-up, 2026-09-11:** the compatibility gate completed 38 soak
  rounds in 61 seconds with stable handles, but 21 state writes failed. A
  separate 1,000-write comparison reproduced `FS access`, Windows error 5,
  in both the original 0.6 executable (4 failures) and the compatibility
  build (3 failures). This predates the OS-floor change; its cause remains
  unisolated. The soak gate is not clean on this host.

### Entry routes leave startup allocations to process teardown

- **Kind:** native allocation cleanup found by GCC analysis, not a reported
  long-running workload failure.
- **Observed:** failed UTF-16 argument conversion returned without freeing the
  partially converted argument array. Reviewing that path also found argument,
  launch-path, and chunk-name allocations left to process teardown on other
  entry routes.
- **Status:** fixed locally. The entry dispatcher borrows converted arguments;
  its caller releases them, and file/eval/stdin routes share explicit cleanup.
  GCC analysis and the entry regression cases pass.

## Validation of 0.6 before its release

- Full Kuu suite: **834 checks passed**, including **23 new adoption checks**;
  reconfirmed after native cleanup and hardening-gate work on 2026-09-10.
- `make analyze`: all authored host C files pass GCC `-fanalyzer` with warnings
  as errors. The shared error raiser now declares its non-returning contract,
  allowing GCC to follow Lua error paths correctly without suppressing warnings.
- `make fuzz`: **30,000 cases per family** across command lines, durations,
  dates, and paths (**120,000 randomized cases**), plus fixed boundary cases
  and valid-value/round-trip checks. All three fixed seeds pass. Workers are
  bounded by deadlines; this is not a proof of memory safety.
- Time Actual: build, **2,191 engine checks**, **nine task checks**, and the
  packaged GUI self-test passed with root `kuu.exe` at 0.6.
- All **27 pinned prerequisite archives** listed successfully: **42,849 UTF-8
  names**. The Go archive's two formerly corrupted names matched extracted files.
- The original restricted HTTP request now reports `HTTP tls`, error 12185,
  its symbolic name, and client-certificate context. Native fixtures also cover
  errors 12186–12188 without changing certificate stores or TLS policy.
- Time Actual retains explicit compatibility for published 0.5; its task and
  application checks pass with that binary as well. The installed root runtime
  is restored to 0.6 after compatibility testing.

The intermittent file-access failures above remain recorded despite passing
reruns. These validation results preceded the source checkpoint push; no
release or signing was performed.

## Cold setup and recovery — 2026-09-10

### File hashing fails on paths that the filesystem API can read

- **Kind:** confirmed native path-boundary inconsistency.
- **Observed:** `fs.read` successfully read a 376-character filename, but
  `hash.file("sha256", path)` returned `HASH notfound`. Content verification
  of a deeply nested installed tool could therefore reject a valid file.
- **Fix:** use the shared normalized Unicode filesystem boundary in
  `hash.file`, including extended-length paths, and reject embedded NUL.
- **Status:** fixed in the source checkpoint. Four regressions cover long
  paths, NUL, ambiguous trailing-dot paths and invalid UTF-8. The complete
  suite passes **838 checks**, and native static analysis passes.
- **Published 0.5 workaround:** Time Actual's installer supplies an explicit
  extended-length Windows path until the fixed 0.6 binary is released.

### Installation presence stamps accept damaged tools

- **Kind:** consuming-project recipe defect, not a new Kuu runtime API.
- **Observed:** a tool whose bytes were changed was accepted by the original
  Time Actual presence-only recipe; malformed record data could instead
  raise a Lua indexing error. Individually tracking overlapping archives
  also risks repeated repairs after a later package overwrites an earlier one.
- **Fix:** Time Actual inventories and hashes the final merged destination,
  validates records, stages archive extraction and preserves a recoverable
  old tree until promotion succeeds. Kuu supplies the existing primitives.
- **Status:** **17 recovery fixture checks pass on 0.5 and 0.6**, including
  corruption, interruptions, offline repair, relocation and concurrency.
  Real cold toolchain setup and full recovery/relocation validation were
  paused and remain incomplete. Tcl/Tk's compiled tree still rebuilds in
  place after invalidating its completion record.

See [the dated handoff](../notes/handoff-2026-09-10_193511.md) for the exact paused
state, local evidence and remaining work. Earlier full application results
above do not establish completion of the new recovery recipe's validation.

## Cold setup and recovery on a second machine — 2026-09-10

Step 2 of the [dated handoff](../notes/handoff-2026-09-10_193511.md), run
on the owner's other machine with the 0.6 build at commit 9abab18.

- **Main checkout, empty `.tools`.** `prereqs --all` fetched all 27 pinned
  archives and built Tcl/Tk 9.0.3 shared and static in 22 min 50 s. `env`
  verified gcc 16.2.0, Python 3.14.6, and Tcl 9.0.3. The complete `test`
  task passed in 1 min 41 s: 9 task checks, 17 recovery checks, the build
  (6,428,720 bytes), 2,191 engine checks, and the application self-test at
  `status=ok`.
- **Cold lab, a second clone with an empty `.tools`.** 23 min 18 s to the
  same state. Then twelve fault-injection and relocation steps passed: a
  changed byte in `ar.exe` repaired from the cached archives (0 downloads,
  21 unpacks, 445 s); a deleted Python record rebuilt (8 s); a corrupt cached
  Python archive plus a missing `python.exe` fetched again, verified, and
  repaired (1 download, 11 s); a deleted Tcl/Tk record rebuilt in place
  (662 s); the checkout moved to `cold lab moved` with the original path gone
  and the inherited tool environment replaced by junk paths, after which
  `env` (6 s), reuse (10 s, 0 downloads, 0 unpacks), repair of a damaged tool
  from the cache (0 downloads, 181 s), and the complete `test` task (69 s,
  every check as above) all passed from the moved path.
- **CI.** The checkpoint push's GitHub run succeeded in 7 min 34 s on
  windows-latest with published 0.5; the run for the commit that pins 0.6
  succeeded in 7 min 36 s.

Observations, none of them a kuu defect:

- **Tcl/Tk cannot be rebuilt from a path with spaces.** The thirteenth step
  removed the Tcl/Tk record in the moved checkout and asked for a rebuild.
  Tcl 9.0.3's `win/configure` and Makefile fail with `cd: too many
  arguments` and `No rule to make target '.../cold'` when the source or
  prefix path holds a space. Using the already built Tcl/Tk from such a path
  works, as the moved test run showed. Time Actual's recipe now refuses the
  rebuild with that explanation instead of make's output. An upstream
  build-system limitation.
- **Repair is bundle-granular.** One damaged byte re-extracts and
  re-inventories the whole destination: for the MSYS2 bundle 21 archives and
  some 22,000 files, 3 to 7 minutes here. The design trades repair time for
  one simple, verifiable record per destination.
- **The first verification after a repair is slow.** `env` took 87 s right
  after the MSYS2 repair and 5 to 10 s at every other time: freshly written
  files are read once by the on-access scanner. Hosting, not kuu.
- **`env` printed a stray `1`** after the Python and Tcl versions, `gsub`'s
  count reaching `print`. Fixed in the recipe.

## Promoting 0.7 on Windows 11 23H2 — 2026-09-11

- **Kind:** a newly supported OS exposed a static-import and console-lifetime
  incompatibility. The owner lowered the Windows 11 floor from 25H2 to 23H2.
- **Observed:** the signed 0.7 release, verified against its sidecar, GitHub
  asset digest and Time Actual's CI pin, exits before `--version` with
  `0xC0000139` (entry point not found) on Windows 11 Enterprise 23H2,
  build 22631.7517. Its Authenticode signature and expected signer match.
- **Cause:** the release statically imports `ReleasePseudoConsole` from
  `kernel32.dll`; a direct export lookup confirms that this host lacks it.
  The other three ConPTY entry points are present. The loader rejects the
  executable before Kuu can report its OS requirement, even for commands
  that do not use `pty`.
- **Local recovery:** restored the original root Kuu 0.6 executable by its
  saved hash. The synced Time Actual source accepts it: eight Lua files
  check without warnings/errors, task declarations load, and the complete
  test plan validates. The verified 0.7 download remains in that project's
  `.tools/downloads/kuu/0.7/` for later promotion.
- **Fix:** resolve `ReleasePseudoConsole` only when exported. On 23H2,
  reserve close/drain workers before creating a console; wait for the whole
  supervised job on natural exit, and transfer abandoned output only after
  canceled I/O completes. Dedicated completion events let final shutdown
  finish without depending on stopped IOCP dispatch. The 24H2+ OS path is
  retained, as is the public Lua API.
- **Regression coverage:** descendant lifetime and final output, blocked
  unread output, native launch failure, console-host cleanup, pending input
  and output at process exit, and canceled I/O while Lua finalizers run other
  children. The complete suite now contains 1,044 checks. Validation runs on
  Windows 11 Enterprise 23H2 build 22631.7517; no newer Windows host was
  available for a fresh run. See the file-access finding above for the
  pre-existing soak failure.
- **Release status:** the compatibility fix is included in
  [0.8](upgrading-0.8.md). The published signed 0.7 asset and its digest are
  unchanged and still cannot start on 23H2. The validation evidence above
  records the earlier development build; its remaining findings stay open.

## JSON duplicate-key error lifetime — 2026-09-11

- **Observed:** the full AddressSanitizer suite on 23H2 found a heap use after
  free in the existing `json.decode` duplicate-key diagnostic. The offending
  key points into the yyjson document, which was freed before formatting it.
- **Fix:** build the error while the document still owns the key, then free
  the document. The existing duplicate-key regression now checks the key in
  the message as well as the error code. Included in 0.8.

## Process-tree chain check during 23H2 validation — 2026-09-11

- **Observed:** one complete run failed the existing 31-process-chain
  assertion that each node has at most one child. The cause is unisolated.
- **Control:** the isolated process suite passed all 82 checks; the final
  complete production suite then passed all 1,044 checks. No change to
  process-tree enumeration was made.
- **Evidence:** [dated validation record](../notes/validation-23h2-2026-09-11_094612.md).

## Orphaned I/O completion during console shutdown — 2026-09-11

- **Observed:** the 0.8 release review found that a canceled console read
  could outlive its child state during Lua shutdown. A later finalizer
  running another process could dispatch that queued completion and read
  its freed source before noticing that the request was orphaned.
- **Fix:** overlapped I/O uses a stable completion key; dispatch consults
  the request's source only after checking whether it is orphaned.
- **Regression:** a native fixture cancels real pipe I/O, releases the
  source's memory before dequeue, and dispatches the orphaned completion.
  The console suite also leaves an exited console open through shutdown
  while another Lua finalizer runs a process. Included in 0.8.
