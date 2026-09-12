# capabilities

`kuu capabilities` says what a program can reach from here: this executable's
verbs, manual and palette, and this project's tasks and its own modules.

```text
kuu capabilities [--json]
```

It exists because the answer was scattered. The palette is in the manual, the
tasks are in `kuu list`, and a project's own modules are in its Lua; an agent
arriving in a repository had to assemble those three itself, and an agent that
guesses wrong writes code against a module that is not there. This is the
answer assembled once, and it is the first thing to run in an unfamiliar
checkout.

It is **provisional**: it arrived in 0.10.0, nothing has driven it yet, and
what it reports is the shape a consuming agent would build on, so it sits
outside the planned 1.0 freeze until a project has used it in earnest. See
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
  alone the two do not differ.
- **Tasks are declared by running `tasks.lua`**, which is project code. `kuu
  run` and `kuu list` already do that, and this does no more. A `tasks.lua`
  that does not load costs the task list and nothing else: the reason is
  reported and the rest of the descriptor still stands.
- **What a task installs under `.tools` is not reported at all.** kuu keeps no
  manifest of it, and a guess about a toolchain is worse than saying nothing.

Without a `tasks.lua` at or above the current directory there is no project
half. kuu does not walk whatever directory it was started in instead: that is
a different question, and an expensive one to answer by accident.

```text
kuu 0.9.0 (Lua 5.5.1) at C:\work\app\kuu.exe

  verbs      capabilities, check, list, run    kuu VERB --help
  manual     41 pages                          kuu docs PAGE | search TEXT
  modules    27, 176 names                     require "NAME"
  errors     27 domains, codes in --json       err.is(e, DOMAIN, code)

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
  modules    2 of the 4 .lua files below the root bound their exports
    lib.util      VERSION, slug, titlecase
    tools.report  render, write

Whatever a task installs under .tools is not listed: kuu keeps no manifest
of it, and a guess would be worse than the silence.
Read kuu docs pitfalls first; it is where kuu differs from the Lua you know.
```

Modules are listed in the order the manual's table introduces them, which is
roughly the order they are reached for. Everything goes to standard output;
there is no summary on standard error.

`--json` prints one envelope instead. The structural schema below uses `?` for
an omitted optional field; array fields are present even when empty:

```typescript
type CapabilityReport = {
  ok: true; // this command has no failure of its own
  result: {
    kuu: {
      version: string; // Major.Minor.Patch
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
    project?: {
      root: string; // absolute path of the directory holding tasks.lua
      tasks: { name: string; desc: string }[]; // hidden tasks omitted
      default?: string; // the task kuu run alone runs
      note?: string; // why tasks.lua did not load; tasks is then empty
      modules: { name: string; path: string; names: string[] }[];
      files: number; // .lua files below the root, whether or not they are modules
    };
  };
};
```

`project` is omitted when there is no project. `kuu list --json` has each
task's dependencies and arguments; they are not repeated here.

`verbs` lists the verbs kuu carries as programs, which is what it can
enumerate. `docs` and `version` are answered in C before that dispatch and are
not in the list: `pages` is how the manual shows up in the report, and
`kuu --help` is the complete usage. A reader of the text form sees both,
since the manual has a line of its own there.

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
exits 0, including a project whose `tasks.lua` does not load, because a
descriptor that fails is worse than one that says what it could not find out.
