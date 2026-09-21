# Step 05 — trustworthy ledger baselines and active scan configuration

Status: complete. Validated state, scope migration, incomplete-observation handling and guarded publication are implemented. Public commands now consume `kuu.config.json`. Steps 06–21 remain unstarted.

## Behavior

[lua/_tree_state.lua](../lua/_tree_state.lua) reads the separate tree baseline without repairing it. The versioned envelope contains `kind:"kuu.tree"`, `v:1`, a positive integer generation, `complete:true`, canonical effective scope/fingerprint and a relative-path `{size,mtime}` file map. It checks every metadata record and structural path, rejects files outside the recorded scope, and recomputes the scope fingerprint through [lua/_scan_policy.lua](../lua/_scan_policy.lua). Native-observable filenames such as trailing-dot names remain representable even when normal file reads refuse them. Impossible sizes, unknown metadata fields and malformed rules cannot become an exact predecessor.

Absent, valid, legacy, invalid, unsupported and unreadable state are distinct. A valid 0.11 map has **unknown completeness**, including a syntactically valid partial map or an empty map. First observation, legacy migration and corrupt-state recovery establish coverage without exact addition/deletion claims. A complete later observation can rebaseline malformed state. Unreadable and future-format state are retained. Baseline input/output is bounded to 64 MiB; generation exhaustion withholds publication rather than wrapping or writing a baseline the reader would reject.

[lua/_ledger.lua](../lua/_ledger.lua) compares complete observations only over their common scope. Newly visible files increment `coverage.baselined`; removed coverage increments `coverage.retired` without listing or hashing retired private paths. Actual metadata additions/changes/removals in common scope retain exact counts and bounded content hashes. A non-exact delta has `complete:false`, a status and empty `paths`, with numeric change counts omitted. An incomplete initial or final scan preserves the last baseline for the invocation; task execution and crossing recording continue.

Tree publication reads its predecessor before the final scan, releases the canonical-project lock, collects/encodes, then reacquires the lock and checks both generation and a hash of the actual predecessor bytes before an atomic write. One stale attempt is discarded with an explicit result; there is no blind retry. The guard starts at the **final scan**, rather than the beginning of a potentially long task, allowing nested runs and a parent's later fresh observation. Locks are not held during tasks or scans. Record history keeps schema version 1 and its existing immutable chain; observation fields are additive.

## Public activation

`kuu run`, `kuu check`, `kuu list` and `kuu capabilities` load and validate configuration before executing a manifest. The same captured scope is used for an operation's scans, including final ledger publication and checker rechecks after fixes. A manifest changing configuration affects the next invocation. Checker contexts also stay fixed if a manifest mutates the legacy `check.PRUNE` table; direct APIs without supplied contexts retain intentional additive wildcard overrides. Mandatory/configured exclusions cannot be removed through that compatibility hook.

The shared defaults now exclude directories named `.git`, `.kuu`, `.tools`, `build`, `node_modules`, `.cache`, `.local`, `.venv` and `__pycache__`. Configured exact basename/subtree rules and `defaults:false` are active. Explicit checker files/starting directories and require resolution retain their documented behavior; root files remain visible. Direct `check.file` can inspect source without loading configuration. Invalid configuration reports `SCAN config`; capabilities retains its descriptor and diagnostics while withholding manifest execution and inventory.

The first crossing carries `observation` beside `delta`. `run --json` also reports `result.ledger.observation` and the final `publication` outcome. Incomplete, invalid, unreadable and withheld outcomes are visible in warnings/notes without changing a successful task into a failed task. Record failures still prevent replacing the tree baseline.

Code integration is in [check](../lua/check.lua), the [run](../lua/cmd/run.lua), [check](../lua/cmd/check.lua), [list](../lua/cmd/list.lua) and [capabilities](../lua/cmd/capabilities.lua) commands, and [error metadata](../lua/_palette.lua). Documentation now describes active behavior in [scan](../docs/scan.md), [ledger](../docs/ledger.md), [check](../docs/check.md), [capabilities](../docs/capabilities.md), [task](../docs/task.md) and [index](../docs/index.md).

## Verification

The final focused suite passed **980 checks, zero failures, in 18.5 seconds**. It covers ledger/state, policy, native/shared collector, public activation, checker/corpus/declarations, capabilities, tasks, docs, palette, fs/paths and synchronization. The matching AddressSanitizer run passed **612 checks, zero failures, in 20.9 seconds**. Sixteen changed/new Lua files passed static checking with zero errors/warnings. All six modified embedded manual pages match their source. `git diff --check` passed.

New tests in [ledger_state.lua](../test/cases/ledger_state.lua) cover malformed envelopes/records, legacy partial maps, exact/common coverage, retirement privacy, every configured rule surviving persistence, generation boundaries, unknown future formats, initial/final scan failure, real Windows sharing denial, same-generation byte replacement, competing publication and nested runs. [scan_activation.lua](../test/cases/scan_activation.lua) covers active defaults/overrides, configuration errors before project code, broken manifests, captured policy and PRUNE mutation. Existing [ledger tests](../test/cases/ledger.lua) now require honest initial/missing-root observations.

Review caught and corrected the maximum-generation boundary and acceptance of impossible floating-point sizes. It also prompted freezing supplied checker contexts against later PRUNE mutation. An initial development compile caught an assignment to a Lua const loop variable; that was corrected before the passing integrated runs.

```powershell
.\.tools\msys2\ucrt64\bin\mingw32-make.exe -j4 all build/kuu-asan.exe
.\build\kuu.exe test/run.lua ledger ledger_state scan_policy scan_native scan scan_activation check check_corpus fixglobals capabilities task docs palette fs paths sync
$env:PATH = (Resolve-Path '.tools/msys2/clang64/bin').Path + ';' + $env:PATH
$env:KUU_TEST_ASAN = '1'
.\build\kuu-asan.exe test/run.lua ledger ledger_state scan_activation scan_policy scan_native scan check capabilities
```

Run suites sequentially because their test workspace is shared. Retained logs: [final build](../build/step05-build-final.log), [focused suite](../build/step05-focused-final.log), [ASAN](../build/step05-asan-final.log), [static checks](../build/step05-static-validation.log), [embedded manuals](../build/step05-embedded-docs.log). No native runtime implementation changed in this step; step 04's native analyzer result remains applicable.

The optional real file-symlink fixture remains unavailable on this host and is explicitly skipped. Real junctions and exclusive Windows handles passed. Partial enumeration and ordinary filter metadata remain clearly identified fault-injection cases.

## Reproduction and profile evidence

The updated [reproduction harness](../test/scan-repros.lua) still reproduces all seven original defects against signed 0.11: [baseline report](../build/step05-repros-legacy-agent.json). Against the final development executable, **all seven are not reproduced**, with positive acceptance prerequisites and zero harness errors: [final report](../build/step05-repros-final.json).

The publication test pauses process A after its final native collection and before lock acquisition. B publishes generation 2 containing a later file; A then reports `stale`. B's exact bytes and generation remain intact. This tests an actual two-process controlled interleave, not natural race frequency. Partial/held observations explicitly require absent exact counts and preserved baseline bytes; invalid state recovery also checks continued task execution and verified crossings. Simply missing a count or skipping an injection is not accepted as proof of a fix. Methods are documented in [scan-baseline.md](../test/scan-baseline.md).

A separate public-command smoke benchmark completed with **1,000 payload files**, one first and two warm command observations, generated/unexcluded/control trees, nested runs and growing ledger fixtures. [Full report](../build/step05-profile-smoke.json), [compact collector counts](../build/step05-profile-counts.json):

| Public child-run fixture | Directories per snapshot | Files per snapshot |
|---|---:|---:|
| Tiny | 2 | 66 |
| Generated, defaults active | 5 | 66 |
| Unexcluded source | 14 | 1,066 |
| Already-pruned control | 2 | 66 |

Both initial/final snapshots use `scan.collect` and the native collector. The smoke report confirms public activation and profiler compatibility, not milestone performance acceptance. The full 100,000-file command comparison and timing-distribution assessment remain step 07. Step 04's retained 100,000-file collector evidence remains unchanged.

## Boundaries and next step

Canonical named locks coordinate writers using this protocol in the **same Windows session**. They do not coordinate different logon sessions/machines or old runtime writers, and are not a sandbox against ancestor replacement. Old runtimes do not understand the new tree envelope; alternating old/new baseline writers in one checkout is unsupported. Observations over a changing tree are not atomic filesystem snapshots or proof of which task caused an edit. These limits are stated in the public ledger documentation.

Validation ran on Windows 11 25H2 build 26200.6899, not a separate 23H2 host. Generated reports are ignored build artifacts and should be retained before cleaning build output. Final development executable SHA-256:

`b419431d564c86fbdd6680da4e1624241e3b484e15c31b1e9e313b333e47ecbe`

Signed 0.11 baseline remains unchanged at `build/release-011-download/kuu.exe`, SHA-256:

`68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`

Work began at **2026-09-15 21:36:12 UTC**. Actual wall time was **about sixteen minutes**, below the **60–120 minute** forecast. Activation, tests and independent review/evidence work ran in parallel; shared test suites were coordinated sequentially.

Next is **step 06: expose normalized scope, completeness and separate phase timings**. This step adds only the observation/publication diagnostics required for trustworthy behavior; it does not claim completion of the broader timing/report work. No signing, release, version change, commit or push was performed. FlowNet was not modified or executed.
