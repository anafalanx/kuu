# FlowNet feedback: reevaluation and sequential implementation plan

Revised 2026-09-15 after a second full reading and independent source reviews;
updated 2026-09-21 for the owner's execution-history decision.

Status: steps 01–06 are historically complete. On September 16 the owner
abandoned automatic filesystem-change observation; on September 21 the owner
authorized continuing with execution history only. The tree-baseline portions
of steps 04–06 are retired. **Revised step 07 is complete and milestone 1 is
accepted under the execution-history contract. Steps 08 and 09's file-attribute
contract, probes and production API are complete. Step 10's cleanup fix and
bounded recipes, Step 11's declaration checking and Step 12's task help are
complete. Milestones 2 and 3 are accepted. Steps 13–17's process recipes,
working directories, runtime distribution guidance, shared environments,
relocation and offline health checks are complete, as is Step 18's detached
editor/private GUI recipe, Step 19's verified native-helper/shortcut recipe
and Step 20's reconstruction/publication recovery. Milestone 4 is accepted.**
**Step 21 is complete and milestone 5 is accepted. All implementation-plan
steps are closed under their final contracts.** No indexing investigation is
pending. Release numbering, commit/push, signing and publication remain separate.

The [step 01 work note](step01-flownet-feedback-2026-09-15.md) records baseline
evidence; [step 02](step02-flownet-feedback-2026-09-15.md), the directory-link
fix; [step 03](step03-flownet-feedback-2026-09-15.md), configuration;
[step 04](step04-flownet-feedback-2026-09-15.md), shared traversal;
[step 05](step05-flownet-feedback-2026-09-15.md), the now-retired tree-state
protocol and retained public-policy activation; and
[step 06](step06-flownet-feedback-2026-09-15.md), reporting and timings.
The [original step 07 report](step07-flownet-feedback-2026-09-16.md) preserves
the failed whole-source cost gate and its measurements. Current implementation
and acceptance evidence belongs in
[the execution-history work note](step07-execution-history-2026-09-21.md).
The [step 08 work note](step08-flownet-feedback-2026-09-21.md) is the
authoritative file-attribute contract and records its native evidence and
platform limitations. The [step 09 work note](step09-flownet-feedback-2026-09-21.md)
records the completed production API, documentation and regression evidence.
The [Step 10](step10-flownet-feedback-2026-09-21.md),
[Step 11](step11-flownet-feedback-2026-09-21.md) and
[Step 12](step12-flownet-feedback-2026-09-21.md) work notes record the combined
cleanup, declaration-checker and help implementation, including final evidence.
The [Step 17 work note](step17-flownet-feedback-2026-09-21.md) records final
combined evidence for Steps 13–17 and links each earlier step's work note.
The [Step 21 work note](step21-flownet-feedback-2026-09-21.md) records final
full-gate, performance, compatibility and separate-project acceptance, following
the accepted [18](step18-flownet-feedback-2026-09-21.md),
[19](step19-flownet-feedback-2026-09-21.md) and
[20](step20-flownet-feedback-2026-09-21.md) recipes.

Evidence: [the complete FlowNet evaluation at d480b35](https://github.com/Northern-Rail-Labs/flownet/blob/d480b35d9f6b76ba6e7f62dfff6de980f19c35a4/kuu-eval.md). This was still the latest main commit when reread. Reviewed kuu baseline: 0.11, commit c7f6c2c610023a5cd6456a85e3f9c9e1d0859ef5.

## Assessment

FlowNet supplies meaningful adoption evidence: pinned prerequisites, exact argument forwarding, empty-PATH use, native builds, editor orchestration, dependency backups, and offline reconstruction/relocation. Its reported successful checks are adoption evidence, not tests independently rerun during this review.

The highest-priority reported problem is repeated observation cost on populated checkouts. The owner-approved resolution is to remove automatic filesystem-change tracking from normal execution, preserving execution history and purposeful source inspection. The runtime also has a reproduced read-only-directory cleanup defect, declaration-checking gaps, and small help/argument inconsistencies. Most other requests call for precise, executable documentation rather than more native APIs. File-attribute operations are explicitly requested by the owner and are included as a runtime feature.

The original source review added three related scan defects/risks. The latter
two motivated the tree-state work now superseded by removing that subsystem:

- Confirmed in 0.11 and fixed in step 02: automatic checking listed files through directory junctions, allowing automatic `check --fix` to modify a file outside the project. Discovery now honors the native walker's `nofollow` decisions.
- Reproduced in step 01: incomplete ledger scans can look like complete trees and produce false deletion counts; missing, unreadable and malformed tree state are conflated. Evidence distinguishes real Windows sharing failures from injected partial listings.
- Reproduced in step 01 using a controlled two-process interleave: snapshot publication has no generation/locking check, so parallel runs can replace a newer baseline with an older observation. Natural race frequency was not measured.

The earlier plan was directionally useful but not yet an execution specification. It understated shared traversal work, omitted several recipe needs, and made overly broad assumptions about directory attributes, case folding, timing, retry classification, and access to the caller's working directory. This revision replaces it.

## How to execute this plan

Run steps 01 through 21 in order. A step includes its implementation, relevant tests and immediate public documentation; do not defer a new API's basic documentation to the last step.

Each step ends with a buildable, reviewable result and focused checks passing. Record files changed, checks run, evidence paths, remaining limitations and actual time in a dated work note. Update the status checkbox only after its acceptance conditions pass. If a later discovery changes a contract, revise affected later steps explicitly rather than quietly expanding the current step.

Use disposable fixtures for filesystem mutations, profiles and integration experiments. For the entire plan, the owner explicitly permits consulting FlowNet code as read-only reference; do not change its files, supplied executable, private profiles or remote state. Changes belong to kuu. Existing authorization permits implementation and verification without asking for permission at each step. Signing, release numbering and publication are outside these implementation steps.

Two estimates are retained below. Engineering hours describe focused work for a maintainer familiar with kuu. Agent wall clock predicts my own elapsed execution time on this workspace, including reasoning, editing, tool latency, builds, focused tests, review and ordinary correction cycles.

The agent estimates assume sequential steps, the current tools/model setup, a usable local toolchain, and independent review in parallel where useful within a step. They exclude owner pauses, service outages, major new scope, signing and publication. These are judgment-based forecasts, not a measured model-throughput benchmark or a delivery guarantee. Update them from actual elapsed time after steps 01–02 and again after 08.

| Step | Deliverable | Engineering hours | Agent wall clock | Status |
|---|---|---:|---:|---|
| 01 | Baseline, reproductions and performance harness | 4–6 | 30–60 min | [x] |
| 02 | Stop automatic checking/fixing through directory links | 2–4 | 15–30 min | [x] |
| 03 | Define and validate declarative scan configuration | 3–5 | 20–40 min | [x] |
| 04 | Implement shared traversal and integrate scan consumers | 10–18 | 45–90 min | [x] historical; ledger scanning retired |
| 05 | Make ledger state/migration/publication trustworthy; enable new defaults | 8–14 | 60–120 min | [x] historical; tree-state protocol retired |
| 06 | Expose scan scope, completeness and separate timings | 4–6 | 25–45 min | [x] historical; run scan reports retired |
| 07 | Remove automatic tree tracking; accept execution history and explicit inspection | 4–6 (original scope) | 25–45 min follow-up | [x] revised milestone accepted |
| 08 | Pin down the file-attribute contract with native probes | 2–4 | 10–20 min | [x] contract settled; implementation followed in 09 |
| 09 | Implement file-attribute inspection and mutation | 8–12 | 40–75 min | [x] |
| 10 | Fix recursive removal and document bounded cleanup retries | 4–7 | 30–50 min | [x] |
| 11 | Align static declaration checks with runtime constraints | 9–15 | 45–90 min | [x] |
| 12 | Fix task help and empty-separator consistency | 3–5 | 15–30 min | [x] |
| 13 | Add process-description, outcomes and diagnostics recipes | 3–5 | 20–35 min | [x] |
| 14 | Add an accurate nested-wrapper cwd recipe | 2–3 | 15–25 min | [x] |
| 15 | Support both runtime distribution models in the guides | 1–2 | 10–15 min | [x] |
| 16 | Add shared environment and cache placement guidance | 2–3 | 15–25 min | [x] |
| 17 | Add relocation and non-repairing health-check recipes | 4–7 | 30–60 min | [x] |
| 18 | Add detached editor and isolated GUI verification recipe | 4–6 | 30–60 min | [x] |
| 19 | Add native-helper caching and local shortcut example | 3–5 | 30–60 min | [x] |
| 20 | Add reconstruction, backup and interrupted-publication guidance | 4–7 | 25–45 min | [x] |
| 21 | Complete integration, compatibility and documentation validation | 5–8 | 30–60 min | [x] |

Step 01 actual: **about 32 minutes**, including the full 100,000-file benchmark and reproduction replay, within its 30–60 minute forecast. Step 02 actual: **about five minutes**, below its 15–30 minute forecast. Step 03 actual: **about nine minutes**, below its 20–40 minute forecast. Step 04 actual: **about sixteen minutes**, below its 45–90 minute forecast, including native analysis, sanitizer checks and retained 100,000-file collection measurements. Step 05 actual: **about sixteen minutes**, below its 60–120 minute forecast, including migration/concurrency tests, sanitizer checks, defect replays and public-command profiling. Step 06 actual: **about thirteen minutes**, below its 25–45 minute forecast, including reporting/controlled-delay tests, sanitizer checks and documentation review. The original Step 07 acceptance run took **about 24 minutes**, including a demonstrated history-cost fix, full-scale controls and independent review; it failed the whole-source cost gate. The owner subsequently replaced automatic tracking with execution history. The completed follow-up took **about 18 minutes**, below its **25–45 minute** forecast, starting **2026-09-21 16:59:35 UTC**. Step 08 took **about 11 minutes** from **2026-09-21 17:20:59 UTC**, within its **10–20 minute** forecast. The earlier indexing proposal is canceled, not additional pending work.

Step 09 actual: **about 13 minutes** from **2026-09-21 17:50:11 UTC**, below
its **40–75 minute** forecast, including production implementation, independent
native readback, API documentation, normal regression and sanitizer checks.

The forecast review after step 08 retained steps 09–21 at **5 h 35 min–
10 h 30 min**, because production validation, API documentation and integration
were still ahead. After Step 09, the forecast for Steps 10–21 was **4 h 55 min–
9 h 15 min**. Steps 10–12 are now complete: approximately **6**, **7** and **5
minutes** respectively, with early read-only preparation in parallel. The
combined execution and reporting took approximately **18 minutes**, against
**90–170 minutes**, starting **2026-09-21 18:42:37 UTC**. The final combined
checks passed **1,261 normal** and **1,058 ASAN** assertions, zero failures.
At Step 12 acceptance, the forecast for remaining Steps **13–21** was
**3 h 25 min–6 h 25 min**, with Step 13 at **20–35 minutes**.

Steps **13–17 are now complete**, taking approximately **6**, **4**, **3**,
**4** and **7 minutes** respectively, with preparation and independent review
in parallel. The combined turn took approximately **23 minutes**, from
**2026-09-21 19:03:21 UTC**, against **90–160 minutes**. Final combined checks
passed **313 normal** and **313 ASAN** assertions, zero failures. Remaining
Steps **18–21** were forecast at **1 h 55 min–3 h 45 min** at that point.
Steps 18, 19 and 20 subsequently took approximately **8**, **9** and **10
minutes**, respectively, including independent review and focused acceptance.
Their combined elapsed time was approximately **27 minutes**, from
**2026-09-21 19:31:01 UTC**. Step 21 took approximately **15 minutes** from
**19:58 UTC**, against **30–60 minutes**, including the corrected full gate,
final benchmarks and isolated exerciser. Steps **18–21 together took about
42 minutes**, against **1 h 55 min–3 h 45 min**, with implementation, review
and preparation delegated in parallel where independent. No implementation
or indexing work remains in this plan.

Original-scope total: **89–148 engineering hours**, approximately **110–180 with contingency**. These historical estimates include the now-retired tree-state work; they are not an updated forecast for implementing it again. The post-step-08 review of remaining agent time is recorded above. The original increase over the first estimate came principally from traversal integration, ledger correctness/concurrency, the junction defect and previously omitted recipe coverage.

The original predicted execution time totaled **9 h 30 min–18 h 15 min**, rounded to **10–18 hours** for planning, with a working central estimate of **about 14 hours**. The remaining estimate above accounts for completed steps; these ranges are not statistical confidence intervals. Do not apply the separate human-engineering contingency multiplier automatically.

| Milestone | Steps | Predicted agent wall clock |
|---|---|---:|
| 1: execution history and explicit inspection — accepted | 01–07 | original 3 h 45 min–7 h 25 min; follow-up forecast 25–45 min, actual about 18 min |
| 2: attributes and cleanup — accepted | 08–10 complete | actual about 30 min across steps; none remaining |
| 3: checker and help — accepted | 11–12 complete | actual about 12 min after Step 10, with prior parallel preparation; none remaining |
| 4: tested recipes — accepted | 13–20 complete | actual about 50 min across two turns; none remaining |
| 5: integrated acceptance — accepted | 21 complete | actual about 15 min; none remaining |

The original widest uncertainty was in shared traversal, concurrent tree state and declaration analysis (04, 05, 11). Tree-state implementation is no longer planned. Execution time includes validating the documentation's runnable examples, not just drafting prose. Full-suite runtime is only one part of step 21; reviewing failures and integration evidence accounts for the rest.

Milestones remain recognizable: **1 = steps 01–07** (35–59 originally estimated hours); **2 = 08–10**; **3 = 11–12**; **4 = 13–20**; **5 = 21**. All five are accepted. Milestone 1 follows the owner's execution-history contract with automatic filesystem-change tracking removed; its retired tree-state work remains historical. Implementation and integrated validation are complete.

## Milestone 1: execution history and explicit inspection

Steps 01–06 below retain their original implementation and acceptance
specifications as a historical record of completed work. Their tree snapshots,
delta comparisons, baseline migration/publication and run scan reports are
superseded by revised step 07. Safe traversal, scan configuration, checking,
module inventory, history integrity and useful timings remain in scope.

### Step 01 — Establish the baseline and reusable reproductions

Inputs: signed 0.11, current source, the pinned FlowNet evaluation.

Create a disposable benchmark/reproduction harness. Cover a tiny manifest/child, large generated trees under .cache/.local/.venv, equally large unexcluded source, a growing ledger, and nested kuu subprocesses. Measure process wall time separately from manifest/setup, initial metadata traversal, changed-file hashing, record writing, final scan/write, module inventory, and ledger verification. Instrument a development build only where required; retain an unmodified release baseline.

Use first-run and repeated warm measurements. Do not describe a first run as a controlled cold OS cache. Begin with small fixtures, then scale to 100,000 generated files. Record environment and file/directory counts; fixture creation is outside timing.

Add targeted reproductions for junction checking, unreadable/partial scans, malformed tree state, and overlapping baseline publication. Keep known failures in a separate reproduction harness or explicit expected-failure cases until their fixes land, so the ordinary regression suite remains meaningful and passing. Reuse existing probes rather than repeat their discovery.

Done when: a rerunnable command and saved results identify which phases scale, and each suspected defect has either a failing fixture or an explicitly unconfirmed status. FlowNet's reported 16 seconds is not a target to manufacture. Ordinary run has two ledger snapshots; capabilities performs module inventory and whole-ledger verification separately.

### Step 02 — Fix automatic checker traversal through links

Files: lua/check.lua, test/cases/check.lua, capabilities tests, checker documentation.

Before broadening scan policy, prevent automatic tree checking and module inventory from listing name-surrogate directory targets returned by fs.dirs. The existing collector ignores walk.links and then fs.list follows those paths. Keep deliberately named file/starting-directory behavior explicit; automatically discovered descendants must not become permission to read or rewrite outside targets.

Distinguish a link that native traversal refused to follow from ordinary filter/cloud reparse metadata. Do not simply skip every reparse entry. Preserve the existing native traversal's directory-handle checks.

Done when: a sibling-directory junction with a Lua sentinel is neither inventoried nor modified by automatic check/check --fix; ordinary in-project files still check/fix; deliberate explicit targets behave as documented. Test file links and nested directory links. This is not a guarantee of filesystem confinement against concurrent ancestor replacement.

### Step 03 — Define and implement the scan configuration loader

Files: new internal scan-policy module; focused tests; new scan documentation linked from check/ledger/capabilities.

Use a tracked, root-level kuu.config.json that can be read without executing manifest.lua:

```json
{
  "v": 1,
  "scan": {
    "defaults": true,
    "exclude_dirs": ["artifacts"],
    "exclude_paths": ["vendor/generated"]
  }
}
```

Freeze these semantics in code/tests before wiring them into traversal:

- exclude_dirs means exact basenames at any depth; exclude_paths means exact project-relative directory subtrees.
- Normalize separators, sort and deduplicate; reject absolute/drive-relative paths, traversal, invalid components, wildcard syntax, unknown keys and malformed array/value shapes.
- Preserve the current matching convention explicitly: ASCII A–Z case folding. Do not call it general Unicode Windows case-insensitivity. Test non-ASCII names according to this stated contract.
- No Git-ignore parsing or dependency on git.exe. Explain that ignored files are not automatically excluded by Git rules.
- Defaults are optional; defaults:false with explicit lists restores visibility of names otherwise treated as generated. .git and .kuu remain mandatory exclusions for automatic project scans and are shown separately.
- Explicit checker files/starting directories are deliberate overrides; descendant exclusions still apply. A project root's own basename is not pruned.
- Absent config uses defaults. Malformed/unreadable config is an actionable configuration error before task execution; a broken manifest does not stop static configuration/check diagnostics.
- Load once before the manifest, so manifest execution cannot alter the current invocation's policy. Direct check APIs load once per operation unless supplied an internal context.
- Exclusion changes observation, not execution or require resolution; it does not impose a sandbox.

Resolve configured rule-count limits explicitly rather than silently inheriting fs.dirs' current 64-pattern limit. Recommended initial bound: 256 names and 256 paths with a useful validation error; benchmark normalization under that bound.

Step 03 result: the private loader enforces 256 entries per original list, 1 MiB of UTF-8 JSON, 255 UTF-16 units per component and 32,760 per relative path. It rejects ambiguous components and folds ASCII only. Public commands intentionally do not consume it yet; activation and before-manifest loading wait for steps 04–05. Exact examples and staging are documented in `docs/scan.md`.

Done when: table-driven contract cases pass and public docs contain exact examples. The loader exists but default ledger behavior is not changed yet.

### Step 04 — Share traversal and integrate consumers under compatible defaults

Historical completed step. Checker and module-inventory integration remains;
ledger-tree collection and the migration dependency below are retired by the
owner-approved step 07 revision.

Files: internal collector/policy module, lua/check.lua, lua/_ledger.lua, lua/cmd/check.lua, lua/cmd/capabilities.lua; native walker only if needed.

Prune by basename/path **before descent**. Filtering fs.dirs results afterward does not fix either performance or unwanted observation. Extend native internal traversal if necessary to preserve handle-based link checks; do not replace it blindly with recursive Lua fs.list calls. Keep any new mechanism private unless a public filesystem API has a justified contract.

Reuse enumeration metadata where practical, since the old callers traverse directories and then list them again. Propagate branch errors, rejected names, and partial listings. Distinguish skipped directories, deliberately non-followed links, and failed enumeration. Establish consistent counts, boundaries and ordering across checker, inventory and ledger.

Integrate behind compatible effective defaults/policy activation until step 05 supports migration. Until that step, commands retain their previous effective scope; custom-policy acceptance tests call the new collector directly. Do not advertise configuration as active in public commands or silently ignore a newly accepted user setting. Do not activate custom ledger exclusions in an intermediate state that compares unlike scopes. Preserve require resolution even when a module is excluded from inventory.

Done when: all consumers are wired to the shared collector with their prior effective scope; direct collector tests establish the new configured matching semantics, exclusion before descent, and no per-file reads below excluded directories. Link and partial-enumeration collector fixtures pass. Public policy activation and ledger delta acceptance wait for step 05. Existing check/file/module and task tests remain green.

Step 04 result: shared private native collection now serves all three consumers, reusing enumeration metadata and retaining completeness diagnostics. Public command scopes remain compatible. The final focused suite passed 841 checks; AddressSanitizer passed 469 checks; native static analysis passed. A retained generated fixture with 100,000 payload files drops from 1,019 enumerated directories under legacy scope to five under the staged configured defaults. Full methods, timing boundaries and remaining ledger defects are recorded in the work note.

### Step 05 — Make ledger baselines and scope transitions trustworthy

Historical completed step, **superseded for tree state**. The requirements and
results below describe work done before the owner removed automatic tracking.
Do not implement or retain tree-envelope migration, comparisons or guarded
publication to satisfy the current plan. Configuration activation and its
before-manifest validation remain; canonical locking is retained for history
appends only.

Files: lua/_ledger.lua, run integration, test/cases/ledger.lua, ledger documentation.

Introduce a validated tree-state envelope with version, generation, normalized scope/fingerprint, completeness and files. Validate every per-file record. Distinguish absent legacy state, valid 0.11 state, malformed/unsupported state and unreadable state. Keep existing immutable NDJSON history/hash chains intact; additive metadata does not require pretending all old records have a new schema.

A complete old/new comparison only covers their common observed scope. Report expanded scope as newly baselined coverage, not newly created source; narrowed scope is no longer observed, not deleted. Avoid listing retired private filenames merely to announce their exclusion. Legacy 0.11 state has a known old policy but no proof of scan completeness: label its completeness unknown and establish a fresh complete baseline without exact addition/deletion claims on that transition. Test a syntactically valid legacy state produced by a partial scan. No history rewrite is needed.

On incomplete scans, suppress exact delta claims and retain the last trustworthy baseline. Runs and child crossings continue under the existing best-effort ledger principle, with visible incomplete-observation metadata. Corrupt state must not turn into an apparently exact empty baseline. A later complete scan may explicitly rebaseline if no trustworthy predecessor exists.

Publish tree state under a short canonical-project lock with a generation check. Never hold the lock throughout the task or scan, because nested kuu runs must work. Detect overlapping publication and discard or retry stale candidates within a fixed bound; report the outcome. Metadata snapshots are observations over time, not atomic filesystem snapshots or proof that one task caused each edit.

Now activate the shared defaults: .git, .tools, .kuu, build, node_modules, .cache, .local, .venv, __pycache__. Document overrides and the fact that basename defaults can hide intentionally maintained source. Also preserve explicit checks of manifest/config/root files.

At public activation, expose the loader's `SCAN config` error in `_palette.lua` and the command/error documentation. Until then that domain belongs to the private staged loader and is deliberately absent from public capability error inventories.

Done when: old state upgrades without false additions/deletions, narrowing/expanding scope works, partial scans preserve good state, malformed state cannot crash the run, concurrent runs cannot publish a stale baseline silently, and nested child/task ledger records still work. Replace the existing test that equates an unavailable root with an empty tree.

Step 05 result: versioned validated baselines, honest common-scope comparisons, incomplete-scan withholding and generation/byte-token publication guards are implemented; shared configuration/defaults are active before manifest execution. The final focused suite passed 980 checks and AddressSanitizer passed 612. All seven original defect reproductions now pass their positive acceptance criteria; signed 0.11 still reproduces all seven. The canonical named-lock guarantee has the existing same-Windows-session boundary, explicitly documented with limits for old writers and changing filesystems. Phase timings and broader reporting remain step 06.

### Step 06 — Surface scope and timing

Historical completed step. Scope/completeness reports remain for check and
module inventory. Revised step 07 removes run scope/scans and initial/final
scan phases, retaining setup, execution, ledger-append and total timings.

Files: run/check/capabilities commands, internal ledger/scanner results, report schemas and docs.

Expose normalized effective scope, provenance, completeness, directory/file counts and skipped counts where relevant. Add opt-in human-readable timings and additive JSON timing fields. Include setup, initial/final scan, ledger work, execution and total observed command duration; inventory and ledger verification have separate phases in capabilities.

Define which measurements overlap. Preserve existing task/child duration meanings. Do not add nested child time to parent wall time as if disjoint. Include finalization in the new total: the existing verb seconds is captured before ledger.close. Final emission/flush and OS process startup can make external wall time larger, without a promised bound on that difference; state this boundary.

Keep existing readers working; no fake zero durations for unavailable phases. Report failures and partial output as well as successful runs.

Done when: a deliberately slow scan is distinguishable from a slow child; final-scan delay appears in the total; legacy report consumers still parse; human output stays quiet unless requested, aside from actionable warnings.

### Step 07 — Remove automatic tracking and accept execution history

Owner decision: automatic filesystem-change observation is no longer kuu's
responsibility. The September 16 decision supersedes the earlier proposed
indexing investigation; implementation was authorized on September 21. This
step removes the responsibility rather than caching snapshots or weakening
their completeness claims. No watcher, filesystem journal, index or background
service is planned.

Remove source-tree snapshots, changed-file hashes, deltas, tree-state
validation/migration and baseline publication from normal `kuu run`. Remove
unused runtime code and tests for that retired subsystem. A run must not walk
maintained or excluded source merely to record its execution. Keep purposeful
checking, module inventory, safe native traversal, exclusions and explicitly
requested `fs.watch` unchanged.

Preserve execution records for runs, tasks and `task.exec` children, their
arguments, outcomes and timing meanings. Retain the canonical-project append
lock, best-effort Git ref/head metadata captured at ledger opening, history
read validation, chain verification, retention and nonfatal recording errors.
Git ref/head is repository identity, not a dirty-state or attribution claim.
Public commands still validate configuration before executing the manifest;
configuration preflight does not imply a source scan.

Write durable ledger records as schema `v:2`, without `delta` or `observation`.
Readers accept old `v:1` and new `v:2` records, including mixed day files, and
preserve original NDJSON bytes/hash links under normal retention. Existing
`.kuu/ledger/tree.json` is ignored and left untouched regardless of its old
format or readability; there is no tree-state migration or cleanup. Stream
events retain their independent schema `v:1`.

Replace run observation/publication reporting with
`result.ledger = { records, complete, error? }` once ledger opening is
attempted. Count successful appends by this invocation; a failed open has
zero records and `complete:false`. Errors retain `message` and, when
classified, `domain`/`code`; warnings and `notes` preserve the task's outcome.
Preflight failures and dry runs omit that summary. Remove run `scope`, `scans`,
`initial_scan` and `final_scan`; retain setup, ledger open/append, execution and
total timings with overlap and emission boundaries documented. Remove the
misleading capabilities `project.ledger.unaccounted` field.

Run focused history, task, check, capabilities, policy and reporting tests,
relevant sanitizer coverage and final-build performance comparisons. Cover
v1/v2 history, malformed/unreadable records, append failures, canonical aliases,
nested/concurrent runs, old tree-state non-access, configuration preflight and
the absence of source-tree enumeration during execution. Preserve inspection
tests for default/custom rules, mixed-case/nested names, explicit overrides,
partial enumeration and links. Retired snapshot tests are not counted as
passing execution-history tests.

Reuse the retained 100,000-file generated and maintained-source fixtures.
Measure ordinary no-op, child and nested runs against tiny controls and the
signed baseline, recording repeated warm distributions and executable hashes.
File count must no longer drive normal-run observation work. Check and module
inventory may still scale with the source they explicitly inspect. Retain
history-size controls and describe full-verification/day-file I/O costs; do
not promise arbitrary-history constant latency or treat a first observation
as a controlled cold cache.

Done when: final-build evidence, regression results, new report schemas,
history compatibility and updated embedded/public docs are reviewed together.
If a remaining execution-history cost defeats small-command usability, leave
the milestone incomplete. Step 08 does not start automatically.

Historical result before this decision: the original acceptance run passed
1,155 regression and 1,019 sanitizer checks, fixed a history suffix-scan cost,
and reduced a child run over 100,000 excluded payload files from 12.375 seconds
to 0.086 seconds. It nevertheless failed the dominant-cost gate: 100,000
maintained files still caused 9.7–11.9-second trivial runs and 25.7-second nested
runs. Those measurements remain in the
[superseded acceptance report](step07-flownet-feedback-2026-09-16.md).

Current result: **revised step 07 is complete; milestone 1 is accepted** under
the execution-history contract. The final normal checks passed **1,121 checks,
zero failures, in 19.8 seconds**; AddressSanitizer passed **958 checks, zero
failures, in 24.3 seconds**. The current source no longer performs normal-run
tree observation, while explicit inspection and history integrity remain.

On the final build, warm medians for no-op, child and nested runs over the
retained **100,000 maintained files** were **21.101 ms, 40.488 ms and 77.055 ms**.
The same-build tiny controls measured **22.591 ms, 43.655 ms and 75.994 ms**.
The original Step 07 candidate measured **11.947 s, 9.709 s and 25.652 s** on
those large-source workloads; that is a historical comparison from a different
day, not a same-session paired benchmark. Explicit checking and module
inventory still inspect source, measuring **1.585 s and 1.653 s** here.

History-size cost remains visible: with **10,000 same-day records, about
10.45 MB**, the child median was **70.772 ms** and full capabilities was
**239.609 ms**, including complete history verification. Acceptance does not
claim constant latency for arbitrary retained history.

Final candidate SHA-256:
`03e808952e60858ea233701d76d65e63be845e902e2e0b3654b75e3e2b5e5fd3`.
The follow-up took **about 18 minutes** from **2026-09-21 16:59:35 UTC**, against
the **25–45 minute** forecast. Full evidence, commands and limits are in
[the current work note](step07-execution-history-2026-09-21.md). No indexing
investigation remains. Step 08 was not started as part of step 07; its later
completion is recorded below.

## Milestone 2: attributes and reliable Windows cleanup

### Step 08 — Settle the attribute contract using bounded native probes

Retain the verified evidence in build/review-plan-attrs-probe.json: native and kuu recursive deletion fail on a read-only directory with Win32 5; clearing the bit permits deletion; a nofollow handle changes a junction's bit without changing its target; TEMPORARY on a directory fails with Win32 87.

Settled API for implementation in step 09:

```lua
local flags = assert(fs.attributes(path))
assert(fs.set_attributes(path, { readonly = false, hidden = true }))
assert(fs.set_attributes(path, { archive = false }, { follow = true }))
```

The getter returns a raw attribute mask for inspection plus six booleans:
`readonly`, `hidden`, `system`, `archive`, `temporary` and
`not_content_indexed`. The setter accepts only those named flags, preserving
unspecified bits. Paths must be actual UTF-8 strings; patch and options
validation examines raw stored table entries rather than accepting values
provided through metamethods. Flag values and `follow` must be actual booleans.
Unknown keys, including strings containing NUL, raise `FS usage`; non-boolean
values raise `FS badvalue`.

The getter/setter default to `follow=false` for the final component. Existing
`fs.stat` defaults stay unchanged. This is not protection against linked
ancestors. An empty patch reads and validates the object without requesting
write-attribute permission. A nonempty patch requests read/write-attribute
access even when its requested values are already set, but skips the native
setter if the mask would not change. `temporary=true` on a directory returns
`nil, FS badvalue`.

An open failure is classified as dangling only when `follow=true`, native
error 2 or 3 was returned, and a separate nofollow inspection verifies that
the final component is a name-surrogate link. Native access denied 5 stays
access denied. A single handle preserves object identity during read/patch,
but does not atomically merge competing attribute writers. Set timestamp
fields to zero for the native metadata update rather than explicitly
rewriting timestamps; the filesystem's change time may still advance.
Compression, encryption, sparse allocation, link creation and ACL permission
management are outside this setter.

Step 08 result: **complete**. The native probe matrix passed **61 checks,
zero failures and three explicit skips**. The AddressSanitizer plus
UndefinedBehaviorSanitizer run passed the same **61/0/3**, with no sanitizer
diagnostics. The three symlink creation probes were skipped
because this host returned privilege error **1314**; junction evidence does
not substitute for those symlink cases. These are local-host results, not a
separate Windows 11 23H2 certification run.

The actual kuu recursive-removal fixture reproduced **`FS access`, Win32 5**
on a read-only directory after its child had already been removed. This
confirms the partial-removal behavior and leaves its fix in step 10.
Production code and public API documentation were not changed in step 08;
implementation and documentation followed in step 09. The full contract,
evidence matrix and remaining limitations are authoritative in
[the step 08 work note](step08-flownet-feedback-2026-09-21.md).

Actual execution: **about 11 minutes** from **2026-09-21 17:20:59 UTC**, within
the **10–20 minute** forecast. At that point step 09 had not started; its later
completion is recorded below.

### Step 09 — Implement the attribute API

Files: src/fs.c and shared path/error helpers, palette metadata, fs docs, native/Lua tests.

Implement the exact [step 08 contract](step08-flownet-feedback-2026-09-21.md).
Validate actual UTF-8 string paths and raw stored patch/options entries before
resource acquisition. Reject unknown keys including embedded-NUL spellings
and non-boolean values with the agreed raised error classes. Use read access
for inspection/empty patches; nonempty patches request read/write-attribute
access even for no-ops, then omit the setter if unchanged. Read and patch
through the same handle, preserve unrelated flags, and handle Windows'
NORMAL/zero special case. Same-handle identity is not an atomic merge of
simultaneous writers. Supply zero timestamp fields rather than restoring
stale copies; preserve file data/write timestamps without promising unchanged
filesystem change time.

Access denied must stay access denied. Restrict dangling classification to
the verified `follow=true`, native 2/3, final-name-surrogate case agreed in
step 08. Ensure handle cleanup on every return/raise. The getter returns a
raw mask plus six booleans and the setter returns true; environmental failures
return `nil, FS error`. Directory `temporary=true` returns `nil, FS badvalue`.

Done when: independent Windows setup/inspection confirms flags, bytes/write times and unrelated bits are preserved; clearing all mutable flags works; missing/denied paths, long/Unicode names, file/directory constraints, junctions and symlinks behave as specified. Tests must not merely prove that a buggy getter agrees with a buggy setter.

Step 09 result: **complete**. Production `fs.attributes` and
`fs.set_attributes`, palette metadata, public API documentation and embedded
discovery coverage implement the settled contract. The final normal regression
passed **974 checks, zero failures, in 36.1 seconds**
([log](../build/step09-tests-final.log)); the final AddressSanitizer regression
passed **840 checks, zero failures, in 55.8 seconds**
([log](../build/step09-asan-final.log)). Independent native setup/readback
supports the attribute tests. Three new real-symlink cases were explicitly
skipped because creation returned Win32 **1314**; real junction cases ran.
These skips remain a stated host limitation, not passing symlink coverage.

Final runtime SHA-256:
`125c604ce94dcd54536f8fa65165ecb4c8964fcb88d657647095c51957e9ea76`.
The work took **about 13 minutes** from **2026-09-21 17:50:11 UTC**, against
the **40–75 minute** forecast. The
[step 09 work note](step09-flownet-feedback-2026-09-21.md) records the complete
implementation, validation and remaining limits. At Step 09 completion,
Step 10 was next; its subsequent cleanup implementation is recorded below.

### Step 10 — Fix recursive removal and provide bounded retry recipes

Route completed-directory deletion through the same attribute-aware logic as files. Check attribute-change errors, preserve the real deletion failure, and leave link targets untouched. Recursive removal remains nontransactional: earlier entries may already be removed, and a cleared read-only bit can remain clear when a later delete fails. Do not add unsafe blind rollback.

Provide scheduler-friendly, bounded recipes for publishing extracted directories and removing owned staging. FS access currently merges sharing violations, permission denial and other Windows failures; a recipe can retry that category only with an explicit maximum budget. It cannot promise immediate distinction of permanent denial without a new structured error field. Never parse localized error messages.

Keep longer retry policy in project Lua initially. Do not multiply a seconds-long delay by every file or retry unrelated failures. Preserve both a primary validation error and secondary cleanup error; tolerate partial previous cleanup without broadening the target. Fix the adoption guide's clean example, which currently discards fs.remove failure.

Done when: read-only root/nested-directory cleanup passes, outside link targets are unchanged, transient and persistent failure fixtures show bounded behavior, and cleanup cannot falsely report success or erase the original failure.

Step 10 result: **complete**, with **407 normal checks** and **354 ASAN checks**,
zero failures. Native ACL/sharing fixtures verify partial cleanup, real errors
and untouched junction targets; executable documentation verifies bounded
publication and cleanup. Approximately **6 minutes**, against **30–50 minutes**.
See the [Step 10 work note](step10-flownet-feedback-2026-09-21.md).

## Milestone 3: declarations and command help

### Step 11 — Align static declaration checks with runtime validation

Files: lua/check.lua, lua/task.lua, shared pure validation where useful, checker corpus/tests, docs.

Validate literal task/tool names against the actual identifier rule; cxx is an example replacement for g++, not a special built-in tool name. Support direct/curried syntax and binding aliases, with shadowing/reassignment coverage.

Recognize task constructors as well as tool declarations. Inspect visible table keys independently of whether the whole table is literal: a run=function field must not suppress a diagnosable timeout key. Validate independently known values conservatively. Point misplaced task-level timeouts to child/default/tool timeouts.

Done when: the FlowNet examples fail static checking with locations and remedies, dynamic declarations gain no speculative false errors, and static checking never executes the manifest. Document list as a separate manifest-loading validation step, not a provisioning guarantee for arbitrary manifests.

Step 11 result: **complete**, with **512 normal checks** and **358 ASAN checks**,
zero failures, including **115 declaration checks**. Literal names and visible
declaration fields are checked through direct/curried aliases without evaluating
the manifest or guessing dynamic values. Approximately **7 minutes** after
Step 10 acceptance, against **45–90 minutes**, with earlier read-only preparation
in parallel. See the [Step 11 work note](step11-flownet-feedback-2026-09-21.md).

### Step 12 — Make task help and empty separators consistent

Show a non-empty task description above usage for omitted and explicit argument schemas. Accept a lone trailing -- as empty for a task with no args schema, matching args={}; keep rejecting real extra arguments.

Document run TASK --help versus deliberate child forwarding run TASK -- --help. Helper help is not guaranteed by task help. Do not silently strip arguments from schemas with rest/forwarding behavior.

Done when: help runs no task/dependency/child and writes no ledger; required-dependency arguments do not block selected-task help; exact forwarded arguments and nonzero child exits remain unchanged.

Step 12 result: **complete**. **42 task-help checks** cover description/schema
consistency, help without execution/history writes, separators, exact child
arguments and exit 17 in console/JSON modes. The final combined run passed
**1,261 normal checks** and **1,058 ASAN checks**, zero failures. Approximately
**5 minutes** after Step 11 acceptance, against **15–30 minutes**, with earlier
read-only preparation. The [Step 12 work note](step12-flownet-feedback-2026-09-21.md)
records final hashes, logs, host limitations and the combined wall clock.

## Milestone 4: tested adoption guidance

### Step 13 — Explain process specifications, outcomes and diagnostics

Add complete recipes for serializing a process specification as {argv, cwd, env}, constructing argv as an explicit JSON array. Retain strict JSON array/object semantics; no JSON runtime change is needed.

Show documented nonzero success-code classification using task.exec's TASK exit error when capture is unnecessary, retaining child records. For captured output, use task.command plus proc.run and state the missing individual child-record boundary. Reconcile the agent guide's broad bypass wording with this supported use.

Show status-first timeout/limit handling, actual stderr, truncation checks, and useful context. Test with small fixtures returning representative codes, not the retired Robocopy migration application.

Done when: recipes distinguish accepted exits from timeout/limit/launch failures, encode correctly, preserve diagnostics, and describe actual ledger behavior.

Step 13 result: **complete**. The four published recipe blocks pass **272 normal
checks** and **26 focused ASAN checks**, zero failures, including actual child
history and status/diagnostic behavior. Approximately **6 minutes**, against
**20–35 minutes**. See the [Step 13 work note](step13-flownet-feedback-2026-09-21.md).

### Step 14 — Make nested working directories explicit

Document project root, caller cwd, wrapper cwd and child cwd separately. A wrapper captures its cwd before launching kuu and passes an explicit task --cwd argument; the task validates/forwards it.

Do not recommend capturing the original invocation directory with fs.cwd() inside manifest.lua: project.enter has already changed it. No new rt invocation-directory API is required for this recipe.

Done when: a nested wrapper launched from a path with spaces/quotes sends the intended cwd and exact arguments through a second kuu invocation. Run from unrelated and project-root directories too.

Step 14 result: **complete**, with **148 normal** and **27 focused ASAN**
checks, zero failures. The actual wrapper, manifest and child blocks preserve
cwd, arguments and exit codes across both process boundaries. Approximately
**4 minutes**, against **15–25 minutes**, with earlier preparation in parallel.
See the [Step 14 work note](step14-flownet-feedback-2026-09-21.md).

### Step 15 — Reconcile runtime distribution instructions

Support downloaded pinned/signed executables and committed pinned/signed executables as explicit alternatives. Update adopting, agent instructions, ignore examples and all blanket “do not commit” wording consistently. Describe checksum/signature verification and deliberate ownership of upgrades.

Done when: a committed-runtime project no longer needs a special exception to kuu's own guide, and the downloaded-runtime path remains complete.

Step 15 result: **complete**. Both models have complete acquisition, pinning,
verification and upgrade instructions. **53 documentation checks** passed;
the actual PowerShell verification block parses and rejects placeholders,
wrong bytes and an unsigned development candidate. Approximately **3 minutes**,
against **10–15 minutes**, with earlier audit work in parallel. See the
[Step 15 work note](step15-flownet-feedback-2026-09-21.md).

### Step 16 — Add shared environment and cache placement guidance

Derive cache paths from the project root and pass them consistently to CLI tools and newly launched editors. Explain that proc env values overlay inherited variables; “clean” requires explicit removal/allowlisting and must not be used to describe a partial overlay.

Link existing environment-lifetime documentation: running editors retain their launch environment until restarted. Do not log full environments containing secrets in example diagnostics; show selected test variables.

Done when: nested cwd and empty-PATH fixtures use the intended cache locations, and the example doesn't rely on one developer's parent environment.

Step 16 result: **complete**, with **345 normal regression checks** and final
recipe checks of **27 normal / 27 ASAN**, zero failures. CLI and detached
probes share root-derived overlays under genuinely empty PATH; unrelated
inherited variables remain, selected Python settings are removed, and the
fixture logs only chosen values. Approximately **4 minutes**, against
**15–25 minutes**, with earlier reference/design preparation. See the
[Step 16 work note](step16-flownet-feedback-2026-09-21.md).

### Step 17 — Add relocation and health-check recipes

Cover source-directory renames, Lua module paths, rebuilding Python venvs/editable installs, obsolete ignored environments left by Git moves, and regeneration of local paths/shortcuts. Explain the limits of a relocatable marker.

Provide a doctor task with no provisioning dependencies, local/offline checks, and no dependence on generated application assets. Distinguish installed tools, cached dependencies and ready application outputs. A missing dependency should produce a useful failure without repairing it.

Done when: disposable source and checkout relocation work; missing-dependency injection is detected and causes no installation; cleanup is scoped to owned old environments. Check current upstream tool documentation when writing concrete uv/npm/Go commands.

Step 17 result: **complete**, with **35 new relocation assertions** in a
**163-check focused run**. Final combined Steps 13–17 regression passed
**313 normal / 313 ASAN checks**, zero failures. Disposable source and whole
checkout moves use the relocated runtime; doctor failures cause no repair;
owned cleanup rejects linked/unmarked targets and preserves neighboring data.
Approximately **7 minutes**, against **30–60 minutes**, including final
combined checks and earlier read-only preparation. The
[Step 17 work note](step17-flownet-feedback-2026-09-21.md) records evidence,
artifact hashes and the limits of the fixture-based verification.

### Step 18 — Add editor launching and isolated GUI verification

Use one declared project runtime/toolchain, explicit environment and fresh disposable profile. Show detached GUI lifetime versus bounded CLI operations and distinguish launch success from readiness.

Keep desktop/profile verification in a small declared native helper where needed. Explain how live cookie/database files and stale WAL files affect cold profile snapshots; do not revive FlowNet's retired profile-import product or operate on real profiles.

Done when: the example launches/verifies a disposable GUI away from the interactive desktop, cleans up only its own processes/files, and documents platform/desktop limitations. No new broad GUI/COM API is implied.

Step 18 result: **complete**, with **368 normal** and **56 ASAN** checks,
zero failures. Native strict compilation and standalone static analysis also
passed. The private GUI, nonce readiness, detached lifetime, history boundary,
failure cleanup and preservation of existing/unknown profile data are exercised.
Approximately **8 minutes**, against **30–60 minutes**. See the
[Step 18 work note](step18-flownet-feedback-2026-09-21.md).

### Step 19 — Add a small native-helper and shortcut example

Compile a minimal Shell Link helper through the pinned compiler and declare it as a tool. Cache by source, recipe and compiler identity, and verify cached executable bytes before reuse. Demonstrate publication of the completed helper/shortcut.

Generated shortcuts contain local paths, remain ignored, and are recreated after relocation. Test quoting, target, arguments, working directory and regeneration.

Done when: a fresh and relocated disposable project both resolve to their own kuu; a corrupted cached helper is detected; the example needs no machine-wide compiler installation.

Step 19 result: **complete**, with **133 normal / 51 ASAN** checks, zero
failures, plus native strict builds and independent static analysis. Corrupt
cache/receipt/compiler pins are refused, changed inputs select new entries,
failed publication preserves prior output, and fresh/moved Unicode checkouts
round-trip exact shortcut arguments and cwd. Approximately **9 minutes**,
against **30–60 minutes**. See the [Step 19 work note](step19-flownet-feedback-2026-09-21.md).

### Step 20 — Explain reconstruction, backup and uncertain publication

Clearly separate (a) an empty installation rebuilt from preserved caches, (b) fetching currently reachable pinned upstream URLs, and (c) an independently stored verified dependency backup. Include cache-only restore, receipt/pin/hash verification and read-only archive staging normalization using steps 09–10.

Explain upload timeouts: they terminate local observation and do not establish rollback or server failure. Inspect remote identity/size/digest before retrying, retain completed assets, prefer bounded per-asset operations, and verify downloaded copies. Test recovery through fixtures/mocked remote states, never a live release.

Add short troubleshooting notes for corporate TLS client-key access and anonymous API limits, preserving actual diagnostics and using appropriate account access/official release endpoints. Do not suggest TLS bypasses.

Done when: recipes preserve primary/cleanup errors, reject changed or incompatible archives, distinguish the three reconstruction guarantees, and handle “timeout but asset accepted” without duplicate destructive retries.

Step 20 result: **complete**, with **161 normal / 78 ASAN** checks, zero
failures. The exact public recipes restore verified archives, preserve cache
attributes, reject linked staging, recover from a separate backup and reconcile
mocked uncertain uploads without duplicate or destructive retries. Approximately
**10 minutes**, against **25–45 minutes**. See the
[Step 20 work note](step20-flownet-feedback-2026-09-21.md).

## Milestone 5: integrated acceptance

### Step 21 — Validate the complete change set

Run the full normal/ASAN/static-analysis/fuzz/soak gate after integration; focused tests already ran per step. Validate palette accuracy, report schema examples, embedded documentation retrieval, anchors, and regenerated kuu.md. Run the separate exerciser and current-version/legacy-history fixtures, including mixed v1/v2 records and ignored old tree state.

Repeat the step-01 benchmarks only on the final build, and compare them with step 07 if intervening changes could affect them. Check that exact argument forwarding, empty-PATH behavior, exit codes, detached lifetime and task/child records still satisfy the adoption evidence.

Prepare a migration note covering scan defaults/configuration for explicit inspection, execution-history schema v2 with continued reading of v1 records, run/capabilities report removals and replacements, empty-separator behavior and new attribute APIs. State that old `tree.json` is ignored untouched: no tree-format migration exists. Do not imply that old executables can read v2 history without tested compatibility; preserve original v1 bytes rather than rewriting history to simulate it.

Done when: checks and before/after evidence are recorded, every evaluation entry below has a final disposition, and no acceptance-blocking issue is hidden as a documentation limitation. A real FlowNet adoption run, if subsequently authorized, uses a separate checkout/runtime first. Release/sign/publish remains a separate requested action.

Step 21 result: **complete**, with **2,667 normal / 2,667 ASAN** checks,
static analysis, all three 10,000-case fuzz seeds and a 25-round soak passing.
All 11 isolated legacy/migrated exerciser commands and 10 additional report
checks passed. The final 100,066-file no-op/child medians are **41.52/83.16 ms**,
with practical cost comparable to the tiny control; signed-baseline paired
measurements and same-day history costs are recorded, not inferred from old
results. All four old tree files kept their hashes. Migration notes, 56-page
manual, palette and evaluation dispositions are complete. Approximately
**15 minutes**, against **30–60 minutes**. See the
[Step 21 work note](step21-flownet-feedback-2026-09-21.md) for exact artifacts,
the initial unused-global correction and limits of platform/adoption evidence.

## Coverage of every evaluation entry

| FlowNet entry | Disposition |
|---|---|
| Standalone adoption | **Fixed and documented:** execution cost 07, declaration checking 11, cwd 14, publication/cleanup 10, relocation 17 and TLS/API diagnostics 20. Exact argv, empty PATH and supervised process evidence remain tested. Launcher headless ordering was a corrected FlowNet bug, not a kuu defect. |
| Committed bootstrap runtime | **Documented and validated:** both runtime distribution models, verification before execution, agent and ignore instructions in [15](step15-flownet-feedback-2026-09-21.md). Owner-controlled adoption remains deliberate. |
| One kuu and private editor | **Validated project recipes:** process outcomes [13](step13-flownet-feedback-2026-09-21.md), shared environment 16 and private GUI [18](step18-flownet-feedback-2026-09-21.md). Nonzero-status behavior uses generic fixtures; automatic tree tracking was removed. This is not an arbitrary-editor certification. |
| Editor profile transfer follow-up | **Generic lessons covered; product retired:** primary diagnostics and bounded cleanup in 10/13/18. The original transient Robocopy failure remains **unconfirmed**; the retired import feature is neither restored nor counted as fixed/passed. |
| Maintained scripts renamed to automation | **Validated relocation recipe:** [17](step17-flownet-feedback-2026-09-21.md) exercises source and checkout moves. Path-sensitive golden output was project-specific; no generic normalization is prescribed. |
| Consolidate root caches | **Validated shared environment recipe:** [16](step16-flownet-feedback-2026-09-21.md), including detached launch and empty PATH. Already-running processes retain their original environment; restart is expected. |
| Root editor shortcut | **Validated native project helper:** [19](step19-flownet-feedback-2026-09-21.md) verifies inputs/output bytes, exact arguments, target/cwd and regeneration after relocation. No general COM subsystem was added. |
| Environment health and reconstruction | **Validated recipes:** readonly cleanup 10, non-repairing doctor 17, and cache/backup reconstruction [20](step20-flownet-feedback-2026-09-21.md). The Go generated-asset probe was a project issue. |
| Command help and remaining boundaries | **Fixed/documented:** descriptions and separators [12](step12-flownet-feedback-2026-09-21.md), explicit inspection policy 03–07, independently retained backups 20. |
| Supplied runtime and scan overhead | **Resolved by the owner's contract change:** normal execution records history without observing the source tree. Revised [07](step07-execution-history-2026-09-21.md) and final [21](step21-flownet-feedback-2026-09-21.md) pass source-size acceptance. Task/child records and deliberate runtime adoption remain. |
| Environment archives and directory attributes | **Implemented and validated:** native attribute APIs and removal 08–10; verified backup and mocked uncertain-upload reconciliation 20. No live release recovery was performed. |
| Structure cleanup/current-only installations | **Covered by inspection policy and verified recipes:** 03–07, helper cache integrity 19 and reconstruction/publication 20. Tests operate on owned disposable installations; retired FlowNet tests are not counted as passed. |

Additional source-review corrections: junction traversal → 02; incomplete/malformed/concurrent tree state → historical 05, retired by execution-history-only 07; overstated timing totals → 06 and revised 07; discarded cleanup error in adoption example → 10; misleading broad bypass wording → 13.

These dispositions distinguish reproduced kuu fixes, executable project recipes,
project-specific behavior, retired features and unconfirmed reports. They do
not claim that the real FlowNet adoption suite was rerun or its repository
changed. Final integrated evidence belongs to Step 21 and its work note.

## Evidence and implementation anchors

These are original-review anchors in signed 0.11, not claims that removed
snapshot code remains in the current implementation. Current acceptance
evidence is linked from revised step 07.

- lua/check.lua:983–1017 ignores walk.links before fs.list; src/fs.c:831–837 lists through the final component. Signed-0.11 reproduction: build/scan-junction-review-aee92b8ad0c641c4a8bf2451b677fb4a, with a sibling target modified by automatic --fix.
- lua/_ledger.lua:82–105 accepts incomplete snapshots; :188–194 lacks sufficient state validation; :248–253 publishes without a generation check. The signed-baseline test/cases/ledger.lua:295–297 treated a missing root as an empty tree.
- lua/cmd/run.lua:149–157 records duration before final state publication. Inventory is in lua/cmd/capabilities.lua:181; retained-ledger verification is at :146.
- src/fs_dirs.c:319–342 uses ASCII folding; :571–650 supports basename patterns, not root-relative exclusions.
- src/fs.c:611–616 clears readonly in remove_one, while :646 removes expanded directories directly. Native/kuu reproduction and junction/temporary probes: build/review-plan-attrs-probe.json.
- lua/task.lua:66,107 validates names; :248,258 omits descriptions in help; :251 rejects no-schema trailing separators. lua/check.lua:727 recognizes tool declarations but not equivalent callable task declarations.
- lua/cmd/run.lua:173–178 and lua/project.lua:61–65 explain why manifest-time fs.cwd cannot recover invocation cwd.
- docs/tools.md:72–80 supports task.command/proc.run; docs/agent.md:59–69 needs consistent exception wording. docs/adopting.md:117 discards cleanup failure.
- Attribute design references: [SetFileAttributesW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileattributesw), [FILE_BASIC_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_basic_info), [symbolic-link effects](https://learn.microsoft.com/en-us/windows/win32/fileio/symbolic-link-effects-on-file-systems-functions). Native probe results take precedence over an inference from the ambiguous directory-readonly wording.
