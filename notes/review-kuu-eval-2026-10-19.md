# What projects found lacking in kuu: review of 2026-10-19

Kept at the owner's request as the working list for upcoming kuu work. Nothing in it
is decided yet; the items that need a decision say so.

**How it was made.** Every `kuu-eval.md` in the workspace was collected: Luxor (`_lx`),
FlowNet and Vanisha, each with its full git history (FlowNet keeps only current issues
and removes resolved ones, so most of its reports survive only in history), a copy of
FlowNet's file from 2026-09-14 left in the `.z` cache, and an earlier agent evaluation
(`kuu-evaluation.md`, 2026-09-25). Time Actual has no `kuu-eval.md`. Agents extracted
89 findings, with a second pass per source for anything missed, and merged them into
73 issues. Each issue got a verdict against kuu's source, tests and manual, then an
independent skeptic's check; where the skeptic disagreed, its correction is the final
status. The review read code and ran only `docs` and side-effect-free `-e` probes with
the signed 0.12 release; it built nothing.

**Baseline.** These findings are checked against kuu `main` at 242a126. The latest release is 0.12 (tag 5112bfc, 2026-09-21). FlowNet, Luxor (_lx) and Vanisha run the signed 0.12 (SHA-256 4eb26725…0962c79). Time Actual still runs 0.8. Paths are relative to the workspace folder that holds the projects; `kuu\` is the kuu checkout.

**Sources.**
- `kuu-eval.md` in `_lx`, `flownet` (the current file and its git history) and `vanisha`.
- A 0.11 copy of FlowNet's file in `.z\.cache\kuu-migration`.
- An earlier agent evaluation, `kuu-evaluation.md` (2026-09-25), in a FlowNet editor scratchpad.

None of the findings came from Time Actual.

## 1. Overview

There are 73 issues. Each got a first verdict and then an independent skeptic's check.

| Final status | Count |
|---|---|
| Still present | 14 |
| Partly addressed | 3 |
| Fixed on main, not released | 1 |
| Fixed in a release | 20 |
| By design | 8 |
| Not kuu | 27 |
| Unclear | 0 |

**Where the skeptic changed the status (3 items):**
- Editor launch pattern: fixed-released became partly-addressed.
- Live-editor WAL files: not-kuu became fixed-released.
- Agent manual overhead: not-kuu became by-design.

In a fourth item (.z runtimes) the skeptic corrected the evidence but kept the status.

**Main points:**
- `main` holds one fix that no release carries: the heap-corruption crash at 43 or more arguments.
- The largest open gap is that kuu's child environment is an overlay, not a seal. That is exactly the sealing proposal.

**Where the proposals matter:**
- Sealing would address items 1–3 in section 2.
- Sealing changes the design of items 5–7 and 15.
- Retiring `.z` for project work would make most of the workspace items in section 6 moot. It would also force Vanisha and Time Actual to migrate.

## 2. Still lacking

1. **The project environment is a partial overlay, not a closed environment.** Still present. Impact: major.
   - **Projects:** FlowNet directly; in practice every kuu project.
   - **Evidence:** `kuu\src\launch.c:289-325`: `ku_env_block` always starts from `GetEnvironmentStringsW()`. `kuu\docs\project-environment.md:57-72` says "a partial overlay, not a clean or hermetic environment" and that the module "intentionally does not implement" an allowlist. `flownet\automation\kuu\project.lua:88-140` builds its own closed PATH but lets HOME, USERPROFILE and APPDATA through.
   - **Work:**
     - Add an environment-base option in `ku_env_block`: empty or an allowlist, with case-insensitive names.
     - Add one manifest-level declaration that task.exec, task.command and proc.detach all apply.
     - Record the base and the passed-through names in the ledger.
     - Decide the default in a roadmap decisions row before 1.0.
   - **Sealing:** this is the proposal. A project can already build a closed environment by hand: enumerate `env.all()` and set every unapproved name to false. What is missing is one shared definition and a sealed default.

2. **Editor launch pattern: the clean-environment part is missing.** Partly addressed; disputed. Impact: cosmetic, as first rated.
   - **Projects:** FlowNet.
   - **The two sides:**
     - First verdict, fixed-released: 0.12's `docs\editor.md` covers detach, bounded CLI operations and private-desktop GUI checks, with an example and a test.
     - Skeptic, partly-addressed: FlowNet's "clean environment" meant an empty PATH. editor.md builds on `project_env.overlay`, which `project-environment.md:57-58` itself calls "not a clean or hermetic environment". So three of the four requested parts shipped.
   - **Work:** covered by item 1. Then rebase editor.md on the sealed environment.

3. **Adopting kuu still costs hundreds of lines of project Lua.** Partly addressed. Impact: minor.
   - **Projects:** FlowNet.
   - **What happened:** 19 commits over 12 days, and 1,028 lines of `automation\kuu\*.lua`.
   - **Fixed in 0.12:** the kuu defects FlowNet hit, the 16 s runs, and new recipes.
   - **Still per project:** provisioning (by design) and environment composition.
   - **Not measured:** adoption has never been measured, and no cold adopter is recorded (`roadmap.md:435-438`). `docs\shortcomings.md` stops at 2026-09-11.
   - **Work:**
     - The seal (item 1).
     - A FlowNet adoption entry in `shortcomings.md`.
     - Record adoption time and lines of project Lua for the cold adopter.
   - **Sealing:** removes most of FlowNet's environment and PATH Lua.

4. **The crash handler is silent on heap corruption.** Still present. Impact: minor.
   - **Projects:** Luxor.
   - **Evidence:** `kuu\src\main.c:467` installs only `SetUnhandledExceptionFilter`. Windows does not call it for 0xC0000374 or for fail-fast 0xC0000409. Probe on 0.12:
     - 43 arguments: exit -1073740940 and no output.
     - `--crash-test`: exit 3 with the expected message.
   - **What the docs promise:** "never dies silently" (`roadmap.md:59`) and exit 3 (`index.md:175`, `kuu.md:890`).
   - **What 242a126 changes:** it removes only the known trigger, not this gap.
   - **Work:**
     - Install a first vectored handler for 0xC0000374 and 0xC0000409. It should write the `kuu: crashed:` line with WriteFile only and exit with 3. `crash_filter` currently calls snprintf, despite its own comment.
     - Add a `--crash-test heap` variant and a test for it.
     - If fail-fast cannot be caught, say so next to the exit-code table.
   - **Not verified:** whether a vectored handler receives 0xC0000374 on build 26100.

5. **`kuu run` silently runs another project's manifest.** Still present. Impact: minor.
   - **Projects:** Luxor, FlowNet.
   - **Evidence:**
     - `kuu\lua\project.lua:47-58` walks up from the current directory and ignores where kuu.exe lies.
     - `kuu\lua\cmd\run.lua:203` never prints the root it chose. `list.lua:53` does.
     - Luxor's kuu.exe, started from FlowNet's directory, ran FlowNet's `git` task.
   - **Work:**
     - When the root differs from the exe's directory, warn on stderr and in the `--json` notes.
     - Document the check in task.md "Where kuu looks" and add a test.
     - Whether to refuse instead is an owner decision.
   - **Sealing:** this matters more under a seal, because the wrong project's PATH and home folders would apply.

6. **`kuu check` drops all argument checks once any part of a tool declaration is computed.** Still present. Impact: minor.
   - **Projects:** Luxor, FlowNet.
   - **Evidence:**
     - `kuu\lua\check.lua:381-398` (`literal_of`) reads a declaration all or nothing; `:623-628` issues the warning.
     - FlowNet's `backup-attrib` (`flownet\manifest.lua:202`) has no `args`, so the warning protects nothing and appears on every run.
     - Luxor wrote its gcc paths out in full to clear the warning.
   - **Work:**
     - Judge each field on its own, and keep checking `args` when only `exe` is computed.
     - Drop the warning when a declaration has no `args`.
     - Consider a portable host-program form, such as `system:attrib.exe`.
     - Settle "shape of a tool declaration" (`roadmap.md:519`, still an open decision).
   - **Sealing:** a PATH built from declared tools makes declarations the source of truth. Host tools (attrib, robocopy) would then need a portable form. Otherwise projects either compute paths from SystemRoot or write machine paths.

7. **A tool's `exe` can point outside the project root, and the docs don't say whether that is intended.** Still present. Impact: minor.
   - **Projects:** Vanisha, which uses `exe = "../z.exe"`.
   - **Evidence:**
     - `kuu\docs\tools.md:16,38` says only "relative to the project root".
     - `kuu\lua\task.lua:118-124,359` never checks containment. `..` climbs out, and an absolute path replaces the root.
     - Skeptic: kuu's own test `test\cases\task.lua:433-444` relies on an absolute exe outside the root.
   - **Work:** the owner decides. Then either document it, or refuse with TASK badvalue and a matching `check` finding.
   - **Sealing:** this decides whether a sealed PATH may contain directories outside the project. Retiring `.z` breaks Vanisha's `../z.exe`.

8. **Docs: a plain table's `json.encode` key order is called "stable within a build", but it changes on every run.** Still present. Impact: minor.
   - **Projects:** Luxor, whose Tcl/Tk rebuilt on every run because of it.
   - **Evidence:** `kuu\docs\json.md:43-45` and `kuu.md:4766`. Six runs of the same command gave five or six different orders, because Lua seeds its hash per process.
   - **Work:** replace the sentence and point to `json.object`. Do not pin the seed.

9. **Docs: there is no named section for declaring a tool.** Still present. Impact: cosmetic.
   - **Projects:** Vanisha.
   - **Evidence:** `kuu\docs\tools.md:9-50` sits in the page introduction, so `kuu docs tools declaring-a-tool` returns ENTRY notfound.
   - **Work:** add a `## Declaring one` heading, matching `## Declaring` in task.md, and a docs test.

10. **The manual requires an append-only kuu-eval.md, but FlowNet's owner switched to current issues only.** Still present. Impact: minor.
    - **Projects:** FlowNet.
    - **Evidence:**
      - The manual: `kuu\docs\agent.md:135-137,156-162` and `upgrading-from-0.11.md:59-68`.
      - The override: `flownet\kuu-eval.md:3-5`.
      - `kuu\lua\cmd\capabilities.lua:172-194` counts only `## YYYY-MM-DD` headings, so FlowNet's eval signal reads empty. This comes from reading the code; I did not run it.
    - **Work:** the owner decides and records a decision row. Either let projects choose the format and make `capabilities` count it, or keep append-only and explain how a short current view fits on top.

11. **A GUI child always gets kuu's standard handles, so a failure that happens only from Explorer can't be reproduced.** Still present. Impact: minor.
    - **Projects:** Vanisha.
    - **Evidence:**
      - `kuu\lua\task.lua:384-389` always inherits the handles.
      - `kuu\src\launch.c:558-561` always sets STARTF_USESTDHANDLES.
      - Tcl's `puts stdout` works under kuu and throws from Explorer.
      - Skeptic: the provisional `pty.spawn` passes no handles, but pty is for console programs, and this path is untested.
    - **Work:**
      - Add a `stdio = "none"` proc option and pass it through task.exec.
      - Optionally detect GUI-subsystem images. Making that the default needs an owner decision.
      - Document it in `task.md:191`.

12. **There is no option to run a child on a private desktop.** Still present. Impact: minor.
    - **Projects:** Vanisha.
    - **Evidence:** `kuu\src\proc.c:986-1050,1113`. A 0.12 probe with `desktop = …` returns `PROC usage: unknown option 'desktop'`. The 0.12 `gui_probe.c` recipe can launch only its own built-in child.
    - **Work:**
      - Add `desktop = true | "name"` to the proc spec.
      - If the desktop can't be created, fail; never fall back to the user's desktop.
      - Add a test, and rebase the editor recipe on the option.
      - Alternatively, record "out of scope" as a decision. The skeptic notes that plan step 18 chose a project helper, but that predates Vanisha's request.

13. **Process queries have no window titles or hung state.** Still present. Impact: minor.
    - **Projects:** Vanisha.
    - **Evidence:** `kuu\docs\proc.md:229-249` and `kuu\src\procinfo.c:123-165`. 0.12 returns ten fields, none of them window-related.
    - **Work:** decide one way or the other. Either add an opt-in `windows` field (EnumWindows, GetWindowTextW, IsHungAppWindow), or add a no-go row and a shortcomings entry.

14. **Tools can't declare non-zero success codes.** Partly addressed. Impact: minor.
    - **Projects:** FlowNet, whose robocopy use is now retired.
    - **Evidence:** 0.12 documents an `exec_success` recipe (`docs\process-recipes.md`). `kuu\lua\task.lua:404-406` still treats any non-zero exit as `TASK exit`, so the ledger records robocopy's exit 1 as a failed child under a task that succeeded.
    - **Work:** optional. Either add `success = {…}` to `task.tool`/`task.exec`, or record the recipe as the contract.

15. **kuu's own build appends the machine PATH.** Still present. Impact: minor.
    - **Projects:** kuu.
    - **Evidence:**
      - `kuu\Makefile:24` is `$(TOOLS_WIN)\bin;$(PATH)$(Path)`, unchanged since 0.2.
      - The asan target at `:286` does the same.
      - Skeptic: `make publish` relies on the machine's git, gh and signtool on purpose (`Makefile:295-334`, `kuu.md:10182-10184`).
    - **Work:**
      - Use a closed PATH for build and test: the kit's bin plus a System32 floor.
      - Declare git and gh explicitly for publish.
      - Run the full gate to find tools the recipes use without declaring them.
    - **Sealing:** the same rule, applied to kuu itself.

16. **There is no release-cadence rule, and the 1.0 criteria are not set.** Still present. Impact: minor.
    - **Projects:** kuu, FlowNet.
    - **Evidence:**
      - 10 tags in 13 days; 67 commits from 09-09 to 09-11.
      - Three contracts were each introduced and removed within days: the lock, the version format and tree snapshots.
      - `roadmap.md:431-440` gives the 1.0 criteria as "for the owner to set", and `:518` leaves the decision open.
      - Skeptic: a written proposal exists, with two amendments agreed on 2026-09-11, and the pace has slowed: no release since 09-21.
    - **Work:**
      - Make the 1.0 criteria binding, with measurable thresholds.
      - Write a cadence rule for 0.x.
      - Decide whether 0.12 is the contract-freeze candidate.
      - Add a "changed and reverted" list to stability.md.
    - **Sealing:** changing the default environment is a contract change, so decide it before the freeze.

17. **Bus factor of one: only the owner can sign a release.** Still present. Impact: minor.
    - **Projects:** kuu.
    - **Evidence:**
      - `kuu\Makefile:290-314`; line 294 says the owner runs `make release`.
      - git shortlog shows one human author.
      - Signing with the owner's certificate is by design (`roadmap.md:32`), but the bus factor, and freeze versus continue, are undecided.
      - The 242a126 fix is waiting for a signed release.
    - **Work:**
      - A decision row: either freeze with fixes only, or follow the 1.0 plan.
      - Write down the release procedure, so someone else can rebuild and verify an unsigned build.
    - **"kuu as the only way":** making kuu the only door raises these stakes.

## 3. Fixed on main, not released

**The fix.** Commit 242a126 (2026-09-29), "A long command line no longer corrupts the heap":
- `lua_checkstack` before pushing the program's words (`src\main.c:137-147`) and before pushing the thread (`src\loop.c:206-210`).
- A test with 300 arguments (`test\cases\entry.lua:79-86`).

It covers `kuu -e`, `kuu FILE` and `kuu run`. No tag contains it. I checked it by reading the code and its test; I did not build or run it.

**What a release brings:**
- **FlowNet** can drop its `KUU_ARGUMENT_BATCH=30` batching in `automation\frontdoor.mjs`, and its rule of keeping argument lists under 40.
- **Luxor** can pass 43 or more arguments to `-e` and to file programs.
- **Crash handler:** the known trigger of the silent crash (section 2, item 4) goes away. The handler's gap stays.

**Open issues for the same release:**
1. `sched.spawn` with 28 or more arguments crashes. `src\sched.c:114-119` pushes onto the caller's stack without a check, and the code is unchanged on main. Probe on 0.12: 27 arguments work; 28 and 29 give 0xC0000374; 100 gives an access violation.
2. Audit every other loop that pushes a variable number of values onto a Lua stack.
3. Add an entry to `docs\shortcomings.md` and the upgrading page stating that 0.12 crashes at 43 or more program words, so projects know when they can drop their workarounds.

## 4. Fixed in a release

| Issue | Projects | Fixed in |
|---|---|---|
| Recursive `fs.remove` fails on read-only directories | FlowNet | 0.12 |
| File-attribute operation (`fs.set_attributes`) | FlowNet | 0.12 |
| `fs.remove` sharing violation not documented | FlowNet | 0.12 (cleanup.md) |
| Bounded retry recipe for publishing extracted trees | FlowNet | 0.12 |
| `kuu check` walked ignored and generated trees | FlowNet | 0.12 (kuu.config.json) |
| Check missed `g++` names and task-level timeouts | FlowNet | 0.12 |
| Nested-wrapper cwd example | FlowNet | 0.12 |
| uv relocatable-marker limits | FlowNet | 0.12 |
| Source-directory migration recipe | FlowNet | 0.12 |
| Committed-runtime model in the adoption guide | FlowNet | 0.12 |
| Child-environment cache recipe; running editors keep their environment | FlowNet | 0.12 |
| Native helper for shortcuts | FlowNet | 0.12 |
| About 16 s per run from ledger scans | FlowNet | 0.12 (snapshots removed) |
| Scan time not reported separately | FlowNet | 0.12 (`--timings`) |
| Scan scope not reported; deletion reports after exclusion changes | FlowNet | 0.12 |
| Omitted versus empty `args` and a trailing `--` | FlowNet | 0.12 |
| `run TASK --help` showed no description | FlowNet | 0.12 |
| Reconstruction recipe: cache versus upstream availability | FlowNet | 0.12 |
| Live-editor WAL files in profile copies (disputed) | FlowNet | 0.12 (docs) |
| 0.7 failed to start on Windows 23H2 | kuu | 0.8 |

**About the disputed WAL item.** The first verdict was not-kuu: the cause was a live VS Code plus FlowNet's own staging script. The skeptic found that kuu took the note as feedback (plan step 18) and answered it in the 0.12 manual, in `docs\editor.md`, section "Profiles and database snapshots". So the final status is fixed-released, as documentation.

**Stale entries and leftover workarounds:**
1. **FlowNet's archive-attribute entry.** `flownet\kuu-eval.md:46-58`, "Replace the archive attribute workaround", is still open, although both kuu parts shipped in 0.12. Both verifiers removed read-only trees with the signed 0.12, including a tree unpacked from tar.zst. What remains is FlowNet's work:
   - Switch `writable_stage` to `fs.set_attributes`.
   - Rerun doctor and test-editor.
   - Drop `backup-attrib` (`manifest.lua:202`). That also clears the standing check warning in section 2, item 6.

   `restore_to` also uses `writable_stage`, so it can't simply be deleted.
2. **The 0.11 copy.** `.z\.cache\kuu-migration\kuu-eval.md` is a 0.11 copy of FlowNet's file. 0.12 answers all its "Should change" requests. Treat it as history.
3. **FlowNet workarounds 0.12 makes unnecessary.** I did not check which of these FlowNet still carries:
   - the committed-runtime "owner exception" in AGENTS.md and README;
   - `args = {}` used only to accept a trailing `--`;
   - `kuu list` as a second validation step;
   - its own 20 × 500 ms removal retry, which `cleanup.md`'s `remove_owned` now covers.

The Luxor and Vanisha files list nothing as open that a release has fixed.

**Small leftovers inside fixed items:**
- An unreadable directory in `check` gives a bare "Access is denied" finding that doesn't point to kuu.config.json.
- The built-in exclusions don't cover `.pytest_cache`, `.ruff_cache` or `.mypy_cache`.
- No sentence says plainly that `fs.remove` has no built-in retry.
- No recipe checks whether pinned upstream URLs are still reachable.
- The uv example was never run against a real uv install.
- 0.12 was not run on a 23H2 host.

## 5. By design

1. **Tables that mix array items and named keys refuse to encode.** The refusal is part of the JSON contract (`docs\json.md:75-78`, plan step 13), and 0.12 ships a recipe. Tension: the error text "object keys must be strings, got number" (`src\json.c:400`) names neither the cause nor the recipe.
2. **No durable backup if upstream assets disappear.** "kuu itself fetches nothing, ever" (`roadmap.md:28`). FlowNet built its own backups on private GitHub assets, and 0.12 documents that pattern as a recipe.
3. **Projects use kuu as supplied, and kuu-eval.md is the only feedback channel.** See `agent.md` "Reporting back" and `roadmap.md:16,27`. Tension: kuu only counts entries and sends nothing, so someone has to collect the files by hand, as this survey did. This is linked to section 2, item 10.
4. **`TASK noproject` before a manifest exists.** The error points onward to the adopting guide, and `kuu init` is ruled out (`roadmap.md:92,94`).
5. **kuu does no provisioning.** No lock; verification is a capability (`roadmap.md:22,28,35`). Tension: FlowNet carries its own fetch, verify and unpack code. Sealing would cut the environment part of that code, not the provisioning part.
6. **For FlowNet, kuu is mainly a dispatcher.** That is the front-door role decided in `roadmap.md:34`. The earlier evaluation recommended freezing at 0.12 and writing a "Minimal" exit plan. The owner instead kept fixing kuu (242a126). Tension: "kuu as the only way" is the opposite of that recommendation, so decide it explicitly.
7. **Nothing outside kuu reads the ledger.** A grep of FlowNet, Vanisha, _lx and _timeactual found no reader. `kuu capabilities` reads the ledger and checks its hash chain. Tension: a chained 90-day ledger is a cost no adopter uses. Options: a first-class reader, such as "the last failed task, with a reference to cite", or a decision row saying the ledger is kuu-internal.
8. **Agents read `kuu docs agent` at the start of each session.** Disputed.
   - The report claimed agents read a 9.9k-line manual. In fact the whole manual is 9,942 lines, `docs agent` is 195 lines and pitfalls is 150.
   - First verdict, not-kuu: the requirement is in FlowNet's `AGENTS.md:20`.
   - Skeptic, by-design: kuu's own `upgrading-from-0.11.md:95-112` supplies that instruction text. Every entry point says to read `docs agent` first, and tests enforce it.
   - `kuu run TASK --help` already exists.

## 6. Not kuu

| Area | Items | Notes |
|---|---|---|
| FlowNet project | git task lacks `safe.directory`; launcher queried known folders before parsing flags; Robocopy failed on one exe; oracle goldens held an old path; `go list -deps` probe on a cold checkout; cleanup error hid the verification error; the 30 m child deadline was FlowNet's own default; tasks don't redirect home folders; launcher identity hashes kuu files; versions typed twice in `project.lua`; stale 995 MB `.tools\vscode-1.137.0`; ad hoc PowerShell errors; an exit needs an AGENTS.md exception; no written exit plan | Sealing would make the home-redirect gap and the hand-written `environment()` kuu's job. Sealing cannot redirect the Windows known-folder API. FlowNet's `FLOWNET_*` diagnostics would need a `pass` entry. |
| Host or sandbox | Antivirus locks fresh executables; WinHTTP 12185 in the agent sandbox (diagnostic already in 0.6); anonymous GitHub API rate limits | kuu already retries the scanner race for its own file operations. |
| Workspace | Vanisha pins no kuu hash; the "source not on this machine" report (a stale clone, now at 242a126); the "stray" `_lx\kuu.exe` (now deliberately tracked); three toolchain generations (z, x, kuu) live at once; `dev\CLAUDE.md` names `.z` kitenv as the only environment definition; `.z\vscode.exe` is missing; `.z\PROJECTS.md` still lists FlowNet as a z project; `.z` runtimes upgraded by hand; outer repo has no remote (locked in `.z\DESIGN.md:40`); `.z` attaches its Job Object after the child starts | Correction on the runtimes item: `.z\book\payloads.lock.json` holds 52 hashes that `z ledger check` verifies. What `.z` lacks is a pinned archive hash before download. kuu already does the Job Object correctly: the child is born in the job and the launch fails loudly. |

**If `.z` is retired for project work:**
- `.z\vscode.exe`, `.z\PROJECTS.md`, the `.z` runtimes, the missing remote and the Job Object items become moot for projects.
- The three-generations problem is resolved.

It also requires:
1. A rewrite of `dev\CLAUDE.md`, best done after the sealing decision so it changes only once.
2. Moving Vanisha off `../z.exe`.
3. Moving Time Actual off 0.8, including its CI pin (`.github\workflows\ci.yml:21-26`).
4. Migrating the eight `z.json` projects (_ann, _arbor-designer, _arboretum, _berchem, _gazet, _mirage, els, machteld).
5. Marking `.x` stale.

## 7. Candidate work, ranked

1. **Release 0.13 with 242a126**, the `sched.spawn` fix, the shortcomings/upgrading note and the cheap doc fixes (section 2, items 8 and 9). It is the one major defect that already has a fix, and two projects carry workarounds for it.
2. **Decide the default environment in a decisions row, then build the seal** (section 2, item 1). It is the largest open gap, it closes items 2 and 3 most of the way, and it has to land before the 1.0 freeze.
3. **Settle the tool-declaration questions together:** may `exe` leave the root (item 7); per-field checking and a portable host-program form (item 6). A sealed PATH is derived from declarations, so settling these first avoids a second contract change.
4. **Name the resolved project in `kuu run`** when it differs from the exe's directory (item 5). It is small, and it prevents silent wrong-project runs, which get worse once each project has its own seal.
5. **Write the owner decisions down as rows:** 1.0 criteria and cadence (item 16), continuity (item 17), the kuu-eval.md format (item 10), and whether kuu becomes the only way and what replaces the exit plan. These are cheap, and several items wait on them.
6. **Make the crash handler catch heap corruption** (item 4). It keeps the "never dies silently" promise true. Check on build 26100 first that a vectored handler receives the exception.
7. **Close kuu's own build PATH** (item 15). It is the same rule kuu would then enforce on projects. Do it alongside the seal.
8. **GUI child options:** no standard handles (item 11) and a private desktop (item 12), or record them as out of scope. Only Vanisha needs them; the effort is medium.
9. **Decide window titles (item 13) and success codes (item 14)** in or out, and record the result either way. Neither is much used today.
10. **Small usability follow-ups from fixed items:** point check's access-denied finding to kuu.config.json and add more default exclusions; make the mixed-table JSON error name its cause; add a ledger reader.

**Not verified:**
1. `main` was not built or tested. The fixes were checked by reading the code and tests.
2. GitHub was not fetched, so commits or releases newer than 242a126 are unknown.
3. Whether a vectored handler sees 0xC0000374 on build 26100.
4. 0.12 has not been run on a 23H2 host.
5. FlowNet's task count (84) and its 1,028 lines were not recounted. The earlier evaluation's maintenance estimate (1–2 days a month plus 1–3 per release) could not be checked: its source was not found.
6. FlowNet has not run its backup workflow against 0.12's attribute calls.
7. Whether Time Actual, still on 0.8, hits any of these issues.

## Corrections after the review

1. **GitHub was fetched.** On 2026-10-19 the checkout was fast-forwarded from 831952a to
   GitHub's `main`, which is 242a126. "Commits or releases newer than 242a126 are
   unknown" in the list above no longer applies.
2. **The `sched.spawn` crash was reproduced independently** with the signed 0.12, one run
   per count:

   ```text
   kuu.exe -e "local sched = require 'sched'; local t = sched.spawn(function(...) return select('#', ...) end, 1, 2, ..., N); print('joined: ' .. tostring(t:join()))"
   N = 20, 27, 28, 40   exit 0, prints the count
   N = 29, 100          prints the correct count, then exits 0xC0000374 (-1073740940)
   ```

   The threshold varies between runs (the review's own run crashed at 28), as expected
   from an unchecked write past a stack block: `src/sched.c:115` reserves room on the new
   thread `co`, but lines 116-118 push the `nargs + 1` copies onto the caller's stack `L`.
   The task's result is correct before the process dies, so the corruption is silent
   until later. The code is unchanged on 242a126.

## Appendix: all 73 issues

Sorted by final status. *Disputed* means the skeptic did not agree with the first verdict.

| # | Final status | Impact | Disputed | Issue | Projects |
|---|---|---|---|---|---|
| 1 | still-present | minor |  | `kuu check` cannot verify tools whose exe path is computed, so every check carries a warning or paths are written out in full | Luxor (_lx), FlowNet |
| 2 | still-present | minor |  | A GUI-subsystem child inherits kuu's standard handles, hiding a failure that only occurs from Explorer | Vanisha |
| 3 | still-present | minor |  | High churn: many releases in days, decisions reversed, and no cadence limit or written 1.0 criteria | kuu, FlowNet |
| 4 | still-present | minor |  | kuu resolves the project from the current directory, so one project's kuu.exe can silently run another project's task | Luxor (_lx), FlowNet |
| 5 | still-present | minor |  | kuu's own build appends the machine PATH (Makefile:24) | kuu |
| 6 | still-present | major |  | kuu's project environment is a partial overlay, not closed, so each project builds its own closed PATH | FlowNet |
| 7 | still-present | cosmetic |  | No named docs section on declaring a tool; the guessed `declaring-a-tool` returns ENTRY notfound | Vanisha |
| 8 | still-present | minor |  | No proc/task option to run a child on a private desktop | Vanisha |
| 9 | still-present | minor |  | Process queries do not expose window titles or responsiveness | Vanisha |
| 10 | still-present | minor |  | Recurring maintenance cost, a bus factor of one, and a signing step only the owner can run | kuu |
| 11 | still-present | minor |  | The crash handler stays silent on the heap-corruption crash (no exit 3, no `kuu: crashed:` line) | Luxor (_lx) |
| 12 | still-present | minor |  | The docs say a plain table's json.encode key order is "stable within a build", but it changes on every run | Luxor (_lx) |
| 13 | still-present | minor |  | The embedded manual asks for an append-only kuu-eval.md; FlowNet's owner switched to current issues only | FlowNet |
| 14 | still-present | minor |  | The tools page does not say whether a tool `exe` may point outside the project root | Vanisha |
| 15 | partly-addressed | minor |  | Adopting kuu in FlowNet took 12 days, two of them almost entirely tooling | FlowNet |
| 16 | partly-addressed | cosmetic | yes | No documented pattern for launching an editor | FlowNet |
| 17 | partly-addressed | minor |  | Tools with non-zero success codes (robocopy 0-7) need custom result classification | FlowNet |
| 18 | fixed-unreleased | major |  | About 40 or more arguments crash kuu with heap corruption before the program or tool runs | Luxor (_lx), FlowNet |
| 19 | by-design | cosmetic |  | `kuu list --json` fails with TASK noproject before a project has a manifest | Vanisha |
| 20 | by-design | cosmetic | yes | Agents must read a manual of about 9.9k lines (`kuu docs agent`) every session | FlowNet |
| 21 | by-design | minor |  | For FlowNet, kuu is mainly a dispatcher: 16k+ lines of C doing what a deleted z.json did | FlowNet |
| 22 | by-design | minor |  | kuu does no provisioning since the lock was removed; projects fetch, verify and unpack in their own Lua | FlowNet |
| 23 | by-design | cosmetic |  | Nothing reads the hash-chained ledger | FlowNet |
| 24 | by-design | minor |  | Pinned upstream URLs give no durable backup if upstream assets disappear | FlowNet |
| 25 | by-design | cosmetic |  | Process specs that mix Lua array items and named properties cannot be JSON-encoded | FlowNet |
| 26 | by-design | cosmetic |  | Projects must use kuu as supplied; kuu-eval.md is the only feedback channel | FlowNet |
| 27 | fixed-released | minor |  | `kuu check` walks ignored and generated directories and fails with access errors | FlowNet |
| 28 | fixed-released | cosmetic |  | `run TASK --help` did not show the task description | FlowNet |
| 29 | fixed-released | cosmetic | yes | A live editor holds profile files open, leaving stale SQLite WAL files in copies | FlowNet |
| 30 | fixed-released | cosmetic |  | An omitted `args` and `args = {}` treated a trailing `--` differently | FlowNet |
| 31 | fixed-released | cosmetic |  | Docs do not say that uv's relocatable marker leaves absolute Python paths after a checkout is copied | FlowNet |
| 32 | fixed-released | cosmetic |  | fs.remove fails on a transient Windows sharing violation (error 32), and this is not documented | FlowNet |
| 33 | fixed-released | cosmetic |  | kuu 0.7 failed to start on Windows 23H2 | kuu |
| 34 | fixed-released | minor |  | Ledger and module scans walked ignored private trees, so every `kuu run` took about 16 s | FlowNet |
| 35 | fixed-released | cosmetic |  | No child-environment recipe for cache placement; running editors keep their old environment | FlowNet |
| 36 | fixed-released | minor |  | No file-attribute operation in 0.11; 0.12's fs.set_attributes has not been adopted | FlowNet |
| 37 | fixed-released | minor |  | No recipe for moving a project's source directory (Lua module paths, editable package rebuild, environments left behind) | FlowNet |
| 38 | fixed-released | cosmetic |  | No shortcut/COM API, so Windows shortcuts need a native helper | FlowNet |
| 39 | fixed-released | minor |  | Publishing a freshly extracted directory tree needs a retry longer than fs.rename's built-in one | FlowNet |
| 40 | fixed-released | minor |  | Recursive fs.remove fails on read-only directories; the 0.12 fix is claimed but untested | FlowNet |
| 41 | fixed-released | cosmetic |  | Scan overhead was not reported separately from task execution time | FlowNet |
| 42 | fixed-released | minor |  | Static check missed invalid tool names (`g++`) and task-level timeouts | FlowNet |
| 43 | fixed-released | cosmetic |  | Tasks always run from the manifest root, so nested wrappers lose the caller's working directory | FlowNet |
| 44 | fixed-released | cosmetic |  | The adoption guide says to ignore kuu.exe and does not cover committing the runtime | FlowNet |
| 45 | fixed-released | minor |  | The applied scan scope is not reported, and changing exclusions could show excluded files as source deletions | FlowNet |
| 46 | fixed-released | cosmetic |  | The reconstruction recipe does not separate a cache-based rebuild from a test of upstream-URL availability | FlowNet |
| 47 | not-kuu | cosmetic |  | _lx held a stray, untracked kuu.exe while it still ran on z | Luxor (_lx) |
| 48 | not-kuu | cosmetic |  | .z's editor launcher does not exist, although dev\CLAUDE.md says it does | .z |
| 49 | not-kuu | minor |  | .z's Job Object support attaches the child by PID after it starts and does nothing on failure | .z |
| 50 | not-kuu | minor | yes | .z's runtimes are gitignored and upgraded by hand, with no declared pins | .z |
| 51 | not-kuu | cosmetic |  | .z\PROJECTS.md's FlowNet entry and .x as a whole are stale | .z |
| 52 | not-kuu | cosmetic |  | A cleanup error could hide an earlier verification error in FlowNet's export helper | FlowNet |
| 53 | not-kuu | cosmetic |  | A stale 995 MB VS Code tree remains in FlowNet's .tools | FlowNet |
| 54 | not-kuu | minor |  | Ad hoc agent tool use outside named tasks produced errors (mangled commit message, split -o argument, missed CRLF) | FlowNet |
| 55 | not-kuu | cosmetic |  | Anonymous GitHub API rate limits when resolving prerequisite pins | FlowNet |
| 56 | not-kuu | cosmetic |  | API oracle goldens were tied to an older checkout path | FlowNet |
| 57 | not-kuu | minor |  | dev\CLAUDE.md names kitenv as the single environment definition, but standalone kuu projects define their own | FlowNet |
| 58 | not-kuu | minor |  | FlowNet tasks do not redirect home directories; only the editor path does | FlowNet |
| 59 | not-kuu | minor |  | FlowNet's `git` task lacks the safe.directory trust that Luxor's task passes | FlowNet, Luxor (_lx) |
| 60 | not-kuu | cosmetic |  | FlowNet's launcher identity hashes kuu files, so any change forces a revalidation | FlowNet |
| 61 | not-kuu | cosmetic |  | FlowNet's launcher queried known folders before parsing --headless | FlowNet |
| 62 | not-kuu | minor |  | FlowNet's project.lua repeats version strings that manifest.lua already holds | FlowNet |
| 63 | not-kuu | minor |  | Host antivirus briefly locks freshly built executables | FlowNet |
| 64 | not-kuu | minor |  | No exit plan from kuu is written down | FlowNet |
| 65 | not-kuu | cosmetic |  | Robocopy failed on one extension executable during the editor profile import | FlowNet |
| 66 | not-kuu | cosmetic |  | The `go list -deps` readiness probe failed on a cold checkout without generated assets | FlowNet |
| 67 | not-kuu | minor |  | The child deadline expired on large GitHub uploads that had in fact succeeded | FlowNet |
| 68 | not-kuu | cosmetic |  | The kuu 0.10-0.12 source is not on this machine, and where it lives is not recorded | FlowNet, Vanisha, _timeactual |
| 69 | not-kuu | cosmetic |  | The outer dev repo has no remote and had been idle since 09-04 | .z, _timeactual |
| 70 | not-kuu | cosmetic |  | The way out of kuu needs a bootstrap script that FlowNet's AGENTS.md:23 forbids | FlowNet |
| 71 | not-kuu | minor |  | Three toolchain generations (z, x, kuu) are live at once, and environment composition is defined four times | FlowNet, Vanisha, Luxor (_lx), _timeactual |
| 72 | not-kuu | minor |  | Vanisha pins no kuu runtime hash and had no rollback runtime at the 0.12 upgrade | Vanisha |
| 73 | not-kuu | minor |  | WinHTTP cannot use the corporate TLS client key in the restricted agent sandbox (12185) | FlowNet |
