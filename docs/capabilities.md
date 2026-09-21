# capabilities

`kuu capabilities` says what a program can reach from here: this executable's
verbs, manual and palette, and this project's tasks and its own modules.

```text
kuu capabilities [--json] [--timings]
```

It exists because the answer was scattered. The palette is in the manual, the
tasks are in `kuu list`, and a project's own modules are in its Lua; an agent
arriving in a repository had to assemble those three itself, and an agent that
guesses wrong writes code against a module that is not there. This is the
answer assembled once. Start with [the agent guide](agent.md) and, when replacing
signed 0.11, [the migration guide](upgrading-from-0.11.md). Then use capabilities
with the verified runtime once the manifest is ready to execute: it loads the
declarations, while `kuu check` inspects them statically.

It is **provisional**: it arrived in 0.10.0, and its descriptor contract remains
under evaluation through project use and feedback. Consuming agents build on
that shape, so it stays outside the planned 1.0 freeze until a later release
explicitly accepts the contract and its adoption evidence. See
[stability](stability.md).

Nothing is reported that kuu cannot know.

- **The palette comes from the modules' own export tables**, so the listing
  cannot drift from the runtime: it is read out of the same tables a program
  would index. Which modules are public is authored in the interface
  description `check` reads, and the suite holds that list to the manual's
  module table in both directions.
- **A project's modules are read from their text and never executed.** The
  extraction is the one [check](check.md) uses, so the two agree; it
  over-approximates, and a module whose exports the text does not bound is
  counted rather than named. A program is not a module, and from the text
  alone the two do not differ. Failed directory listings and unreadable
  candidate modules make the inventory explicitly incomplete, with their
  paths and diagnostics; they never become a successful empty inventory.
  Automatic discovery skips directory links the native walker refuses to
  enter and skips file symlinks. Their targets are excluded from the file
  count and module list; intentional exclusions do not make the inventory
  incomplete. Ordinary filter/cloud reparse metadata remains discoverable.
- **Tasks and tools are declared by running `manifest.lua`**, which is project
  code. `kuu run` and `kuu list` already do that, and this does no more. A
  `manifest.lua` that does not load costs the task and tool lists and nothing
  else: the reason is reported and the rest of the descriptor still stands.
  The tools listed are the executed reading; [check](check.md) reads the
  same declarations from the text, and the suite holds the two equal.
- **Installed executables are not inferred as tools.** An undeclared executable
  under `.tools` does not become a tool entry merely because it is present.
  Tools declared in the manifest are listed, including paths under `.tools`;
  Lua module discovery separately follows the configured inspection exclusions.
- **What agents wrote back is counted, not read.** `kuu-eval.md` at the root,
  the report [For the agent](agent.md) asks for, holds one entry per heading
  shaped `## YYYY-MM-DD — kuu VERSION — what`; the descriptor says whether
  the file is there, how many such headings it holds outside fenced code,
  and the date of the last, and nothing else looks at the file.

Without a `manifest.lua` at or above the current directory there is no project
half. kuu does not walk whatever directory it was started in instead: that is
a different question, and an expensive one to answer by accident.

The root's [`kuu.config.json`](scan.md) controls module discovery. Automatic
inventory always excludes `.git` and `.kuu`, and by default excludes `.tools`,
`build`, `node_modules`, `.cache`, `.local`, `.venv`, and `__pycache__`.
These basename defaults can hide maintained source; `defaults:false` restores
visibility of the optional names. Configuration does not change `require`
resolution or what the manifest may execute.

The command loads configuration before running the manifest and retains that
policy for its inventory, even if the manifest changes the configuration file
or the legacy `check.PRUNE` table.
Invalid or unreadable configuration prevents manifest execution and inventory;
the descriptor still reports the runtime, ledger and feedback, with a
`SCAN config` diagnostic and an explicitly incomplete module inventory.

```text
kuu 0.12 (Lua 5.5.1) at C:\work\app\kuu.exe

  verbs      capabilities, check, docs, list, run  kuu VERB --help
  manual     57 pages                              kuu docs PAGE | search TEXT
  modules    27, 184 names                         require "NAME"
  errors     28 domains, codes in --json           err.is(e, DOMAIN, code)

modules
  proc       alive, detach, find, kill, list, run, start, tree, wait_all,
             wait_any
  fs         absolute, basename, canon, chdir, copy, cwd, dirname, dirs,
             exists, ext, glob, join, link, list, mkdir, read, relative,
             remove, rename, same, space, stat, stem, temp, tempdir, tempfile,
             watch, write
  ...

project C:/work/app
  tasks      build, test*, fmt
             * the default. kuu run TASK; kuu list describes them
  tools      report (ndjson), signtool (lines)
             declared in the manifest; task.exec { tool = NAME } runs one
  ledger     child report exit, task weekly ok, verb run ok
             the last crossings, oldest first; .kuu/ledger holds ninety days of them
             312 records, each hashing the one before it; the chain is intact
  eval       kuu-eval.md holds 3 entries, the last dated 2026-09-12
  modules    2 of the 4 .lua files below the root bound their exports
    lib.util      VERSION, slug, titlecase
    tools.report  render, write

Installed executables are listed only when declared as tools; project modules
follow the inspection scope (kuu docs scan).
Everything that runs in a project runs through kuu.exe; if something cannot
be done from here, build a tool for it and call it through the door (kuu docs tools).
Read kuu docs agent first: what is expected of you here, and how to report back.
From signed 0.11: read kuu docs upgrading-from-0.11 before running project tasks.
Then kuu docs pitfalls, once; it is where kuu differs from the Lua you know.
```

Modules are listed in the order the manual's table introduces them, which is
roughly the order they are reached for. The descriptor goes to standard output;
`--timings` optionally adds one timing line on standard error. A project whose manifest loads and
declares no task shows `tasks      none` and, on the line beneath, the shape
of a declaration and the page that has it, since an empty manifest is
seldom meant; one whose tasks are all hidden shows `none` and names the
listing that has them. A `tasks.lua` not yet renamed is said in the project
section and carried as `notes` in the descriptor.

`--json` prints one envelope instead. The structural schema below uses `?` for
an omitted optional field; array fields are present even when empty:

```typescript
type CapabilityReport = {
  ok: true; // this command has no failure of its own
  result: {
    timings: { setup: number; inventory?: number; ledger_tail?: number;
               ledger_verification?: number; total: number }; // wall-clock seconds
    kuu: {
      version: string; // N.N: two natural-number components
      lua: string; // the Lua release, "Lua 5.5.1"
      exe: string; // this executable
      verbs: string[]; // the verbs carried as programs, sorted; see below
      pages: string[]; // kuu docs PAGE, sorted
    };
    modules: {
      name: string; // require "NAME"
      page?: string; // its manual page, omitted when it has none
      names: string[]; // everything it exports, sorted
    }[];
    errors: { domain: string; codes: string[] }[]; // err.is(e, DOMAIN, code)
    sets: { name: string; values: string[] }[]; // the closed sets, in their own order
    next: string[]; // what to read and do next, in order: the conduct page first
    project?: {
      root: string; // absolute path of the directory holding manifest.lua
      file: string; // "manifest.lua", or "tasks.lua" from a project that has not renamed yet
      tasks: { name: string; desc: string }[]; // hidden tasks omitted
      tools: { name: string; exe: string; output: string; args?: { [name: string]: string };
               emits: string[]; timeout?: number | string; reach: { [kind: string]: string[] } }[];
      default?: string; // the task kuu run alone runs
      note?: string; // why the manifest did not load or configuration prevented it; tasks is then empty
      config_error?: { domain: "SCAN"; code: "config"; message: string };
      scope?: ScanScope; // normalized rules/provenance; absent if config is invalid
      scan?: ScanReport; // inventory collection metadata; absent if collection did not run
      notes: string[]; // what the text form says beside the inventory: a tasks.lua read as the manifest
      ledger: { last: { at: number; kind: string; name: string; status: string; seconds: number }[]; // the last five crossings, oldest first
                records?: number; intact: boolean; broken?: string; unreadable?: string }; // count only after successful verification; broken locates corruption, unreadable describes a read failure
      eval: { present: boolean; entries: number; last?: string }; // kuu-eval.md at the root: whether it is there, how many entries, and the last one's date
      modules: { name: string; path: string; names: string[] }[];
      modules_complete: boolean; // false if configuration, enumeration or reading a candidate module failed
      module_errors: { path: string; message: string; win32?: number; domain?: string; code?: string }[];
      files: number; // discovered .lua files below the root, whether or not they are modules
    };
  };
};
```

`project` is omitted when there is no project. `kuu list --json` has each
task's dependencies and arguments; they are not repeated here.

The ledger describes execution history. It does not track filesystem changes
or expose an `unaccounted` change count. Source files are inspected here to
build the requested module inventory, independently of task execution.

`ScanScope` and `ScanReport` are defined on the [scan](scan.md) page. Scope
exposes normalized mandatory/default/custom exclusions, their fingerprint and
file/default provenance. The scan reports project/starting roots, collection
seconds, completeness, errors, and counts for collected file metadata,
enumerated directories, excluded directories and non-followed links. Scan file
counts include non-Lua files; `project.files` counts discovered Lua files.
`scan.complete` covers collection, while `modules_complete` additionally
covers candidate-module reads. A later unreadable module can therefore make
`modules_complete` false after a complete scan.

`result.timings` is present in JSON whether or not `--timings` was supplied.
`setup` includes imports, palette/project discovery, configuration and manifest
loading, and ends before measured ledger/inventory work. `inventory` measures
collection and static module extraction together; the scan's `seconds` is
nested within it. `ledger_tail` reads recent records and `ledger_verification`
separately measures checking the retained chain. These are elapsed seconds,
not counts or CPU time. An unavailable phase is omitted: without a project,
there is no inventory or ledger phase; invalid configuration omits inventory
while still allowing the ledger descriptor.

`total` covers command work and report assembly, measured from just after the
timing helper loads to just before final serialization/emission and flushing.
Other command imports and final report preparation are included. External wall
time also includes OS process startup and final output, without a promised
bound on the difference. Phases need not add up to total. `--timings` prints
the same measured phases on stderr and leaves JSON on stdout; `--help` prints
no timing line.

`verbs` lists the verbs kuu carries as programs, which is what it can
enumerate; `docs` is one of them. `version` is answered in C before that
dispatch and is not in the list, and `kuu --help` is the complete usage.
`pages` is how the manual shows up in the report, and the text form has a
line of its own for it.

`errors` is every domain kuu raises and the complete set of codes in it, which
is what `err.is(e, DOMAIN, code)` matches against: a code a domain does not
have makes `err.is` answer false for every error, and the handler it guards is
dead. `sets` is the closed sets a result field or an option is drawn from,
such as `ProcStatus`; a literal outside one never matches either. `check`
reports both mistakes where it can see them, and this is the same description
it reads.

## Errors

The command has no error code of its own. Invalid command arguments use
`CLI usage` and exit 2; `--help` prints usage and exits 0. Everything else
exits 0, including a project whose `manifest.lua` does not load, because a
descriptor that fails is worse than one that says what it could not find out.
Invalid scan configuration appears as `project.config_error` with `SCAN config`,
also in the text descriptor and `module_errors`; tasks, tools and modules are
empty and `modules_complete` is false. `--help` does not read configuration.
