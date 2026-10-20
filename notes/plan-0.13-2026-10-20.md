# Plan: kuu 0.13 — one folder per project, shared tools, and the waiting fixes

Approved by the owner on 2026-10-20. It records the decisions taken in conversation on 2026-10-19 and
2026-10-20, the contracts 0.13 freezes, and the order of the work. The list of what agents found lacking is
[review-kuu-eval-2026-10-19.md](review-kuu-eval-2026-10-19.md); this plan refers to its items as
"shortcoming #N" (section 2 of that note).

## What 0.13 is

1. Every kuu project becomes one manifest, `kuu.lua`, plus one folder, `_kuu/`, that holds everything
   else: the door, the project's Lua, fetched tools, downloads and kuu's state.
2. A project pins every tool it needs by URL and SHA-256, or builds it from pinned sources, and kuu
   installs exactly that. A tool may be installed in the project's own `_kuu/tools/` or in a
   `_kuu/tools/` in a folder above it, so projects that sit together can share identical tools. A single
   checkout always knows what it is missing.
3. Every child a task starts gets a sealed environment by default: PATH from the project's pinned
   tools, home folders inside the project, and nothing from the caller unless the manifest passes it.
4. The fixes that are waiting: the heap corruption at 43 or more program words (242a126, on main),
   `sched.spawn` with many arguments, an audit of similar stack pushes, a crash handler that reports heap
   corruption instead of dying silently, and two documentation errors.

## Owner decisions

1. Keep kuu: compact, a single file, the best tool for these projects (2026-10-20).
2. Projects may share tools through folders above them; a collaborator who checks out one project is
   told what is missing and chooses between installing in the project or in a folder above (2026-10-20).
   This replaces the 2026-10-19 decision to keep no commonality at all.
3. A folder above the projects (the workspace) is simply a regular kuu project with its own `kuu.lua`,
   `_kuu/` and door. There is no special marker file and no separate kind of folder.
4. Everything kuu-related lives in one folder; the only file outside it is the manifest, named `kuu.lua`.
5. Prerequisites are shareable unless the declaration says `scope = "project"`; a tool that rewrites its
   own folder stays in the project. Built prerequisites may be shared too (decision 15).
6. Downloaded archives are kept, so a tool can be rebuilt offline.
7. kuu's own documentation tells agents that tools can be shared with projects in the folders above
   when that suits them or their user.
8. Everything in this plan ships as 0.13: the fixes and the new layout together.
9. MSYS2 is tested read-only before it may be shared.
10. Luxor (`_lx`) migrates first.
11. On its first run in a project, 0.13 moves kuu's existing state (`.kuu/ledger/`, `.kuu/memory.json`)
    into `_kuu/state/`.
12. The sealed environment and the crash handler for heap corruption are part of 0.13.
13. `kuu run` resolves every prerequisite before the first task; a prerequisite declared
    `optional = true` is skipped then and resolved when a task first uses it.
14. Single-file downloads (`unpack = false`) are part of 0.13.
15. A project must be able to reproduce every prerequisite it uses from its own contents plus internet
    access: the prerequisite is committed in the project, or the project pins where to download it, or
    the project holds the recipe to build it from pinned sources. Only fetched and built prerequisites may
    live in a tools folder above.
16. The folder is named `_kuu` (2026-10-20).
17. A tool may name a program Windows itself ships, with `system = "attrib.exe"`, resolved from
    `SystemRoot`. It is the one exception to decision 15: like the `System32` folders on the sealed PATH,
    it belongs to the operating system, not to any project (2026-10-20).
18. The workspace gets six tasks: `check-all`, `status`, `pull-all`, `search`, `edit NAME` and
    `kuu-versions` (not `mirror`). It pins git, rg and, as optional, VS Code for them (2026-10-20).
19. Every project stands on its own: a single checkout plus internet access reproduces everything it
    needs; the workspace and tools folders above only save downloads and disk (2026-10-20).

## The project layout

```text
project/
  kuu.lua            the manifest (committed)
  _kuu/
    kuu.exe          the door (committed or ignored, the project's choice)
    lua/             the project's Lua modules (committed)
    kuu-eval.md      agents' reports (committed)
    config.json      inspection settings, formerly kuu.config.json at the root (committed)
    tools/           fetched and built tools (ignored)
    downloads/       archives by SHA-256 (ignored)
    home/            the sealed environment's home folders (ignored)
    state/           ledger, mem's notebook, the local tools choice (ignored)
```

The `.gitignore` block every project uses:

```text
/_kuu/*
!/_kuu/lua/
!/_kuu/kuu-eval.md
!/_kuu/config.json
!/_kuu/kuu.exe        # only when the project commits its door
```

**Why `_kuu`.** Tested 2026-10-20:

1. ripgrep, which agents search with, treats a name starting with a dot as hidden: with `.kuu/`, `rg`
   found a match in `kuu.lua` but not in `.kuu/lua/`, and `.gitignore` whitelists do not change that.
   With a visible folder and the block above in a git repository, `rg` searched `lua/` and `kuu-eval.md`
   and skipped `tools/` and `state/`; git committed exactly `kuu.lua`, `.gitignore`, `lua/` and
   `kuu-eval.md`. `_kuu` is not hidden, so it behaves like the visible folder.
2. A plain `kuu/` would collide at the workspace level with the kuu repository's own folder
   (`HEAD\dev\kuu`).
3. Sort order: in Explorer (`StrCmpLogicalW`) `_kuu` comes first after the dot-entries; in a
   culture-aware sort like VS Code's it comes first of all; in byte order (git, `ls`) it follows names
   that start with a capital letter.

Rules:

1. **The door decides the project.** When `kuu.exe` runs from a folder named `_kuu` whose parent holds
   `kuu.lua`, that parent is the project root, whatever the current directory is. Only a `kuu.exe`
   outside any `_kuu` (a development build, a copy elsewhere) still walks up from the current directory,
   and it then says which root it chose on stderr and in the `--json` notes. This closes shortcoming #5:
   one project's door can no longer run another project's tasks, and a folder without its own manifest
   can no longer pick up a workspace's tasks by accident.
2. **The manifest is `kuu.lua`.** `manifest.lua` and `tasks.lua` are still read, as deprecated fallbacks
   with a warning. When more than one exists, `kuu.lua` wins and kuu warns. 0.13 freezes the name.
3. **Modules load from `_kuu/lua/`.** Today `require` searches the program file's directory, which for
   the manifest is the project root; with the manifest named `kuu.lua`, `require "kuu"` would load the
   manifest itself. The manifest's require root becomes `_kuu/lua/`.
4. **State lives in `_kuu/state/`**: the ledger in `_kuu/state/ledger/`, mem's notebook in
   `_kuu/state/memory.json`, the local tools choice in `_kuu/state/tools.json`. On the first 0.13 run,
   kuu moves an existing `.kuu/ledger/` and `.kuu/memory.json` there by rename, removes `.kuu/` when it is
   then empty, says so on stderr and records it in the ledger. If both an old and a new location exist,
   it moves nothing and reports both. kuu never moves committed files on its own; the move recipe covers
   those.
5. **`_kuu/` is not disposable**: it holds the door and committed Lua. A reset deletes `_kuu/tools/` or
   `_kuu/state/`, never `_kuu/` itself. (0.4 and 0.5 kept `kuu.exe` in the disposable `.tools`; 0.6 moved
   it to the root. The door now sits beside the disposable folders, not inside one.)
6. **`kuu-eval.md` and `config.json` move into `_kuu/`.** During migration `capabilities` and `check`
   read both the old root locations and the new ones, and say which they used.

## Prerequisites

A prerequisite is declared once, in `kuu.lua`:

```lua
task.prereq "rg" {
  version = "15.1.0",
  url = "https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-pc-windows-msvc.zip",
  sha256 = "…",
  strip = 1,
  path = { "." },          -- folders to put on PATH, relative to the installed tool
}

task.prereq "ucrt64" {
  version = "16.2.0-3",
  parts = {                -- several archives unpacked into one folder, in this order
    { url = MSYS2 .. "gcc-16.2.0-3-any.pkg.tar.zst", sha256 = "…" },
    { url = MSYS2 .. "gcc-libs-16.2.0-3-any.pkg.tar.zst", sha256 = "…" },
  },
  path = { "ucrt64/bin" },
}

task.prereq "jq" { version = "1.8.1", url = "…/jq-windows-amd64.exe", sha256 = "…", unpack = false, file = "jq.exe" }

task.prereq "vscode" { version = "1.139.0", url = "…", sha256 = "…", scope = "project", optional = true }

task.tool "rg" { prereq = "rg", exe = "rg.exe", args = { … } }
```

1. **Attributes**: `version` (text), either `url` and `sha256` or `parts`, `strip`, `path`, `scope`
   (`"shared"`, the default, or `"project"`), `optional` (decision 13), and `unpack = false` with `file`
   for a download that is itself the program (decision 14). Unknown attributes raise `TASK usage`, as
   tool declarations do.
2. **Identity.** A fetched tool's identity is the SHA-256 of a fixed text: `kuu-tool 1`, then each part's
   SHA-256 in declared order, then `strip`, `unpack` and `file`. Two declarations with the same identity
   install the same bytes in the same arrangement, whatever their names. `path`, `scope` and `optional`
   are not part of the identity.
3. **Tools refer to a prerequisite.** `task.tool { prereq = "rg", exe = "rg.exe" }` resolves `exe` against
   wherever `rg` is installed. `exe` relative to the project root stays for programs the project itself
   builds or commits. An `exe` that climbs out of the root with `..` or is absolute is refused with
   `TASK badvalue`: anything outside the project must be a prerequisite the project can reproduce
   (decision 15; this settles shortcoming #7). Vanisha's `exe = "../z.exe"` does not meet that rule and
   is replaced by prerequisites during its migration. Windows' own programs (FlowNet's `attrib.exe`)
   use `system = "attrib.exe"`, resolved from `SystemRoot` (decision 17); a `system` name with a path
   separator or `..` is refused, so it can only name a file in `System32`.
4. **Built prerequisites.** A prerequisite may be built from pinned sources by a recipe in the project:

   ```lua
   task.prereq "tcltk" {
     version = "9.0.4-static",
     parts = { TCL_SOURCE, TK_SOURCE },     -- pinned sources, as for a fetched prerequisite
     uses = { "ucrt64" },                   -- prerequisites the build needs, sealed onto its PATH
     recipe = { "build/tcltk.lua" },        -- the files under _kuu/lua/ that the build reads
     build = "build.tcltk",                 -- the module whose build(src, out, tools) makes the tool
     path = { "bin" },
   }
   ```

   Its identity covers everything the result depends on: `kuu-built 1`, the source hashes, the SHA-256
   of each recipe file, the identities of the `uses` prerequisites, and the declared options. A changed
   recipe therefore makes a new entry instead of reusing a stale build; two projects with identical
   inputs share one build. kuu runs the build in a staging folder under the lock, sealed, and writes the
   marker last, as for a download. Builds are rarely byte-identical, so `verify` checks the tree against
   what was recorded at build time; identity is defined by the inputs.
5. **`kuu check`** reads `task.prereq` and `task.tool` as literals. A tool declared through a prerequisite
   has a literal `exe`, so its arguments are checked again. This settles most of shortcoming #6.
6. **kuu installs what is pinned.** This replaces each project's own fetch, verify and unpack code
   (FlowNet's `automation/kuu`, Luxor's `toolchain.prereqs`). kuu still fetches nothing a manifest did
   not pin by SHA-256.

## The tools folder (format 1, frozen in 0.13)

An installed tool is a folder:

```text
<some project>/_kuu/tools/<name>/<version>-<first 12 hex digits of the identity>/
    kuu-tool.json    written last; the entry exists only when this file does
    …                the unpacked or built tool, read-only
```

`kuu-tool.json` holds: `format` (1), `kind` (`fetched` or `built`), `name`, `version`, `identity`,
`parts` (each `url` and `sha256`), `strip`, `unpack`, `file`, for built tools `recipe` (each file and its
SHA-256) and `uses` (each identity), `path`, `scope`, `tree` (the SHA-256 of the sorted list of relative
paths, sizes and file hashes, for `verify`), `installed` (UTC) and `by` (the kuu version that installed
it).

Installing:

1. Take a named lock, `kuu-tool-<identity>` (`sync`), so two projects installing the same tool at once
   cannot collide.
2. If a valid entry is already there, stop.
3. For each part, use `<that _kuu>/downloads/<sha256>` if it is present and its hash matches; otherwise
   download it there, verifying the hash.
4. Unpack (or, for a built tool, unpack the sources and run the recipe) into
   `<that _kuu>/tools/.staging/<random>/`, apply `strip`, compute `tree`, set every file read-only
   (`fs.set_attributes`, 0.12), write `kuu-tool.json`, and rename the staging folder into place.
5. Release the lock. A crash leaves only staging debris, which `kuu tools verify` reports.

Reading: an entry counts only when `kuu-tool.json` parses, its `format` is one this kuu knows, and its
`identity` matches the declaration. A kuu that meets an unknown format treats the tool as missing and
never writes into that entry. Many kuu versions will share one folder, so format 1 must stay readable by
every later version.

## Finding tools, and the question

1. **Order.** For each prerequisite kuu looks in the project's own `_kuu/tools/`, then in the
   `_kuu/tools/` of each folder above, nearest first, up to the drive root. The first valid entry with the
   right identity wins. A stray or foreign tools folder above can never supply a wrong tool; at worst it
   holds nothing that matches. `scope = "project"` prerequisites look only in the project.
2. **When.** `kuu run` resolves every declared prerequisite before the first task (decision 13), so a
   missing tool is found before anything runs. This costs one file read per candidate folder. An
   `optional = true` prerequisite is resolved when a task first calls a tool that uses it. `kuu list`,
   `check`, `docs`, `capabilities` and `tools` never require tools.
3. **Missing, in an interactive console** (standard input and standard error are consoles, no `--json`,
   no `--dry-run`): kuu asks once.

   ```text
   This project needs 5 tools that are not installed: rg 15.1.0, gh 2.94.0, git 2.54.0, ucrt64 16.2.0-3, node 24.16.0.
     1  Install them in this project only (_kuu\tools)
     2  Install them in C:\work\_kuu\tools, shared with the projects in C:\work
     3  Cancel
   ```

   Choice 2 names the nearest existing `_kuu/tools` above, or offers to create one in the parent folder.
   The answer is stored as a relative path in `_kuu/state/tools.json`, so it is asked once per checkout.
4. **Missing, anywhere else** (agents, CI, piped or redirected runs): no question. kuu exits with code 2
   and `TASK missing`, lists the tools, and gives both commands: `kuu tools install --here` and
   `kuu tools install --above`. `--json` carries the same list.
5. **Agents** read in `kuu docs agent` that sharing through a folder above is available, when it fits
   (several projects on one machine pinning the same tools), when it does not (a single checkout, CI,
   tools that rewrite themselves), and that they ask their user before writing to any folder above the
   project, because that folder lies outside the repository and serves other projects.

## `kuu tools`

1. `kuu tools`: for each prerequisite, where it resolves or that it is missing; which tools folders exist
   above; for a workspace, how many versions of each tool its projects pin.
2. `kuu tools install [--here | --above [DIR]] [NAME …]`.
3. `kuu tools verify [--deep] [NAME …]`: markers and identities; `--deep` recomputes `tree`; reports
   staging debris and files that lost their read-only attribute.
4. `kuu tools prune [--apply] [--downloads]`: a dry run unless `--apply`. In a tools folder, an entry is
   unused when no `kuu.lua` at or below that folder's project pins its identity, read as literals. A
   manifest whose pins cannot be read as literals counts as an unknown user and blocks deleting any entry
   with a name it might pin. There are no registration files and nothing is ever deleted automatically
   (a registration list with a stale entry is how Playwright's installer nearly deleted a browser another
   project used, 2026-10-19).

## The workspace

The workspace folder (here `HEAD\dev`) becomes a regular kuu project: `HEAD\dev\kuu.lua` and
`HEAD\dev\_kuu\kuu.exe`. Its tasks work across the projects below it through their own doors, for example
`task.exec { "_lx/_kuu/kuu.exe", "run", "check" }`; its pins serve only those tasks (decision 18):

1. `check-all`: every project's own `check` through its own door, one line per project.
2. `status`: per repository, its branch, uncommitted changes, and commits not yet pushed or pulled.
3. `pull-all`: fetch every repository and fast-forward the clean ones; never merge or rebase; list the
   skipped ones.
4. `search TEXT`: one ripgrep search across all projects, each project's `.gitignore` respected.
5. `edit NAME`: VS Code on one project, with that project's sealed environment.
6. `kuu-versions`: which `kuu.exe` each project runs, and placing a verified newer one in a named project.

The workspace's own manifest and these tasks belong to the outer repository, not to kuu, and are written
after 0.13 is released.
Sharing does not depend on the workspace's pins: when a project chooses "install above", its tools land
in `HEAD\dev\_kuu\tools` and serve every project that pins the same identity. No project depends on the
workspace: each pins its own tools and installs them itself when nothing above matches. The z kit is not
involved; `.z` keeps its own tools for z projects.

The outer workspace repository marks hosted projects with `/_*/` in its `.gitignore`, which would also
ignore the workspace's own `_kuu/`. Its `.gitignore` therefore gets, after that line:

```text
!/_kuu/
/_kuu/*
!/_kuu/lua/
!/_kuu/kuu-eval.md
!/_kuu/config.json
```

## The sealed environment

Today a child's environment is the caller's environment with the task's `env` laid over it
(`src/launch.c:289-325` starts from `GetEnvironmentStringsW()`; `docs/project-environment.md` calls it
"not a clean or hermetic environment"). Each project therefore builds its own closed environment in Lua
(FlowNet about 1,240 lines with its tasks, Luxor about 1,200, Vanisha about 550), and anything the caller
carries leaks through: on 2026-10-19 a session started in FlowNet's editor passed `NODE_COMPILE_CACHE`,
`UV_PYTHON` and `FLOWNET_PROJECT_ROOT` to another project's tools.

In 0.13, every child kuu starts while running a task in a project (`task.exec`, `task.command`, and
`proc.run`, `proc.start` and `proc.detach` called from a task) gets a composed environment:

1. **PATH** is the `path` folders of the resolved prerequisites, in declaration order, then any folders
   the manifest adds, then the Windows floor: `System32`, the Windows folder, `System32\Wbem` and
   `System32\WindowsPowerShell\v1.0`. The caller's PATH is not used.
2. **Home folders** point into `_kuu/home/`: `HOME`, `USERPROFILE`, `HOMEDRIVE` and `HOMEPATH`, `APPDATA`,
   `LOCALAPPDATA`, `TEMP`, `TMP` and the `XDG_*` folders.
3. **Windows' own variables pass**, from a fixed list in the manual: `SystemRoot`, `windir`,
   `SystemDrive`, `ComSpec`, `PATHEXT`, `OS`, the `PROCESSOR_*` variables, `NUMBER_OF_PROCESSORS`,
   `COMPUTERNAME`, `USERNAME`, `USERDOMAIN`, `ProgramData`, `ProgramFiles` and `ProgramFiles(x86)`.
4. **Nothing else passes.** It is an allowlist, not a list of known leaks, so a variable nobody thought
   of cannot leak either.

Escapes, each recorded in the ledger by name (never by value):

1. In `kuu.lua`: `task.environment { pass = { "HTTPS_PROXY", "FLOWNET_*" }, set = { GOTOOLCHAIN = "local" },
   path = { "build/bin" } }`.
2. Per call: `seal = false` for a child that needs the real user, such as an Edge sign-in through
   Windows; and `env = { … }` overlays, as today.
3. Per run: `kuu run --pass NAME` for a one-off diagnostic.
4. Outside a project (`kuu -e`, or a program file with no manifest) nothing is sealed, as today.

Limits the manual states plainly: this seals environment variables, not the machine. Programs that find
folders through the Windows known-folder API still reach the real profile; the registry, absolute paths
and the network stay reachable. Anything started from a sealed editor inherits that project's seal.
Projects whose diagnostics read the caller's variables (FlowNet's `$env:FLOWNET_EBP_TRACK_CENSUS_DB`) add
a `pass` entry; their own environment code becomes redundant and is deleted during migration, not kept as
a second definition.

## The fixes

1. **Program words** (242a126, on main): 43 or more program words no longer corrupt the heap.
2. **`sched.spawn`**: `src/sched.c:115` reserves room on the new thread, but lines 116-118 push the
   `nargs + 1` copies onto the caller's stack unchecked. On signed 0.12, 29 and 100 arguments died with
   0xC0000374 after printing the correct result; 28 and 40 passed in the same run, so the threshold
   varies. Fix: `luaL_checkstack(L, nargs + 1, "task arguments")` before the loop, or move the values to
   the thread without copying them on the caller. Regression test: a task spawned with 300 arguments.
3. **Audit** every push whose count depends on input. Already safe: `main.c:139`, `loop.c:208`,
   `sched.c:67` and `:144`, `re.c:252`; `proc.c:954` (one push and one pop per argument, at most 4096).
   Still to read: the loops in `state.c`, `fs_dirs.c`, `json.c`, `http.c`, `net.c` and `procinfo.c`.
4. **Documentation**: `docs/json.md` calls a plain table's key order "stable within a build", but it
   changes on every run (shortcoming #8); the tools page gets a named section for declaring a tool
   (shortcoming #9), as part of its rewrite for prerequisites.
5. **`docs/shortcomings.md`**: record that 0.12 corrupts the heap at 43 or more program words and at
   about 28 or more `sched.spawn` arguments, so projects know when to drop workarounds (FlowNet batches
   frontend tests by 30, `KUU_ARGUMENT_BATCH`).
6. **The crash handler** (shortcoming #4): `src/main.c` installs only `SetUnhandledExceptionFilter`,
   which Windows does not call for heap corruption (0xC0000374) or a fail-fast (0xC0000409), so 0.12 died
   silently despite the promise "never dies silently" and the documented exit code 3. Install a first
   vectored exception handler for those two codes that writes `kuu: crashed: …` with `WriteFile` only (the
   heap is what broke; the current filter calls `snprintf` despite its own comment) and exits with 3. Add a
   `--crash-test heap` variant and a test. If a fail-fast cannot be caught in-process on Windows 11 build
   26100, say so beside the exit-code table instead of promising it.

Settled in 0.13: the sealed environment (#1), the crash handler (#4), and through the layout and
prerequisites #5, #6 (mostly) and #7.
Not in 0.13: #10 the `kuu-eval.md` format, #11 to #14 process and GUI options, #15 kuu's own build PATH,
#16 and #17 cadence and continuity.

## Decision rows

| Row | Now | Proposed |
|---|---|---|
| a mandated runtime | … "and `.kuu/` never holds anything that runs" | … "`_kuu/` holds the door, the project's Lua, installed tools and kuu's state; its subfolders decide what is committed" |
| dependency pinning | "none: a project fetches what it needs by url and hash with `http` and `archive`" … | "a project pins each prerequisite by URL and SHA-256, or as pinned sources plus a recipe, in `kuu.lua`; kuu fetches, verifies, builds and installs exactly that; no lock file" |
| projects share nothing | "every project carries its own `kuu.exe` … directly in its root since 0.6" … | "every project carries its own `kuu.exe` in `_kuu/`; a tool pinned identically may be used from a `_kuu/tools` in a folder above, matched by identity, never by name; nothing on `PATH`, no machine changes" |
| what a project may fetch | "… into its own `.tools`; nothing re-hosted, nothing shared between projects … kuu itself fetches nothing, ever" | "upstream downloads pinned by SHA-256, into the project's `_kuu/tools` or a `_kuu/tools` above, as the owner or user chooses; kuu fetches only what a manifest pins; every prerequisite is reproducible from the project plus internet access; Windows' own programs are named with `system =`" |
| the project's declaration file | "`manifest.lua` at the root …; `tasks.lua` remains a deprecated fallback" | "`kuu.lua` at the root, the only kuu file outside `_kuu/`; `manifest.lua` and `tasks.lua` are deprecated fallbacks with a warning" |
| dependencies | "no lock: verification is a capability …, and the agent writes its own setup" | "no lock; the agent declares prerequisites and kuu installs them" |
| the project root (new) | — | "the door's own location: `_kuu/kuu.exe` beside `kuu.lua`; only a `kuu.exe` outside any `_kuu` walks up from the current directory, and says which root it chose" |
| the workspace (new) | — | "a folder above projects may be a regular kuu project whose tasks drive the others through their own doors; no project depends on it" |
| the child environment (new) | — | "sealed by default inside a project: PATH from the resolved prerequisites plus the Windows floor, home folders in `_kuu/home`, an allowlist of Windows' own variables, and what the manifest passes or sets; escapes recorded in the ledger by name" |

## Build order

1. The owner reviews this note; the decision rows are written into `docs/roadmap.md`.
2. The fixes: `sched.spawn`, the audit, the crash handler, regression tests, the shortcomings entries,
   the json sentence.
3. The layout: the door decides the project; `kuu.lua` with the two fallbacks; `_kuu/lua` as the require
   root; state in `_kuu/state` with the first-run move; `kuu-eval.md` and `config.json` in `_kuu`;
   `capabilities` and `check` updated; tests for each, including a door started from another project's
   directory.
4. Prerequisites in the project: `task.prereq` (fetched, single-file and built), identity,
   `task.tool { prereq = }`, `optional`, the refusal of `exe` outside the root, the tools folder format,
   locking, read-only entries, downloads; `check` support; tests with local archives and a small built
   prerequisite (no network).
5. Folders above: the lookup, `--above`, the question, the stored choice, the non-interactive failure.
6. `kuu tools`: status, install, verify, prune (dry run by default).
7. The sealed environment: the allowlist base in `ku_env_block`, `task.environment`, `seal = false`,
   `--pass`, ledger records; tests that a variable set by the caller does not reach a child.
8. Documentation: `agent.md` (sharing and the guardrail), `adopting.md` (the layout and `.gitignore`),
   `task.md` and the tools page (prerequisites), `project-environment.md` and `editor.md` (the seal),
   `capabilities.md`, `ledger.md`, `mem.md`, `scan.md` (new paths), `upgrading-0.13.md` (the move
   recipe), `roadmap.md`, `shortcomings.md`.
9. MSYS2 read-only test; then migrate `_lx` (its own repository, its own commit) and record it in its
   `kuu-eval.md`.
10. The full gate (normal, ASAN, static analysis, fuzz seeds, soak), release notes; the owner signs and
    publishes.

The move recipe for existing projects (step 8): rename `manifest.lua` to `kuu.lua`; move `kuu.exe` to
`_kuu/`; move the project's kuu Lua into `_kuu/lua/` and fix its `require` names; move `kuu-eval.md`
and `kuu.config.json`; replace the `.gitignore` block; convert the project's fetch and build code into
`task.prereq` declarations; delete `.tools` once `kuu tools` shows everything resolved.

## Open questions

None at approval. (Decided 2026-10-20: the folder is `_kuu`; state moves on the first run; the seal and
the crash handler are in 0.13; prerequisites resolve up front with `optional = true`; `unpack = false` is
in; tools above must be reproducible from the project; Windows' own programs through `system =`; the
workspace's six tasks.)

## Not verified

1. Whether MSYS2 works from a read-only folder (build step 9 tests it).
2. Console detection inside VS Code terminals and agents' pseudo-consoles; agents' tools run with
   standard input redirected, so they should never see the question.
3. Path lengths: `_kuu/tools/<name>/<version>-<12 hex>/` adds about 30 characters to every tool path.
4. How long `verify --deep` takes on a large tool such as MSYS2 or VS Code.
5. Sort order in VS Code itself; the culture-aware sort was measured with .NET, not in the editor.
