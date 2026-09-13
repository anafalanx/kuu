# Plan: kuu explains itself, and asks to be told

Written 2026-09-13 after the front-door plan closed at Phase 4 and a
five-lens audit of the built-in documentation, a skeptic per finding, was
run against the question: does kuu explain itself from inside the
executable, tell agents what is expected of them, and serve its docs in an
agent-friendly way? The audit confirmed twenty-seven findings, refuted two,
and its completeness critic added eight it verified itself. The judgement
was two-thirds met. This plan closes the remaining third, and it ships in
0.10.0.

## The decision

The manual stays inside the executable and stays the authority. What is
added is the statement of conduct — one embedded page that says, as
instructions, what an agent is expected to do in a project that runs
through kuu, including that it reports back — and the routing from every
entry point to that page. The executable points onward at the moment it
matters: a failure, a first crossing, a project in an old shape. The `docs`
verb becomes a verb like the others. The version story becomes one story.
The content gaps the audit found in the jobs an agent does are closed.

The report-back is two things. The ask is on the conduct page, embedded.
The answer is `kuu-eval.md` at the project root — the project's own,
committed with it, since `.kuu/` never travels and kuu sends nothing —
appended never rewritten, one entry per piece of work: the date, the kuu
version, what worked, what was difficult with the exact command and output
(the shortcomings standard), what should change. `kuu capabilities` reports
the entry count and the last date in both forms, so the door shows that an
agent has written. The ledger is the objective half; the eval is the
subjective half; an entry may cite the record it is about.

## Batches, each gated and committed

### Batch 1 — the conduct page and the routing

- `docs/agent.md`, `kuu docs agent`: arriving (capabilities first, pitfalls
  once, the map), running (what a crossing is and what a bypass is, declare
  tools, bound every child, check after every edit, build a tool when kuu
  cannot), writing (`global none`, the raise-or-return law in your own
  code, own domains, nothing on PATH or unhashed, `.kuu/` is kuu's), and
  reporting back with the `kuu-eval.md` contract. A short form at the end.
- Routing: `kuu --help` ends with the pointer; the `kuu docs` footer names
  agent, pitfalls and index; `kuu capabilities` closes on agent then
  pitfalls in its text and carries `next: string[]` in `--json`; index.md
  opens with the pointer and lists the page; kuu.md's Start here and README
  name it; bundle ORDER carries it after index.
- `capabilities` reads `kuu-eval.md`: `project.eval = { entries, last? }`,
  said in the text form, documented in capabilities.md and agent.md.
- Checks: the pointers exist at each entry; eval counted with and without
  the file; the page is in the bundle.

### Batch 2 — the docs verb is a verb

- `rt.page(name)` in C: the text of a manual page, for a program with no
  shell. Documented at index.md's `rt` paragraph.
- `lua/cmd/docs.lua` replaces the C route: `--help`, unknown option is
  `CLI usage`, `--json` on the list (`{ name, description, lines }`, the
  description being the page's first sentence) and on search
  (`{ page, line, heading, text }`), `kuu docs PAGE SECTION` and
  `PAGE#anchor` print one `##` section, search takes all its words joined
  and says it matches literally and case-insensitively, the list prints
  `name  description` and ends with the start-here line. The C dispatch
  drops its docs route; `rt.verbs()` then lists `docs`, and
  capabilities.md's sentence about it changes.
- Every per-module code-set section is headed `## Errors`, so
  `kuu docs MODULE errors` works for every module.
- stability.md's freeze of the `docs` verb then names options that exist.
- Checks: each of the above, and the docs case holds the `## Errors` rule
  across every module page.

### Batch 3 — the executable points onward

- A manifest that loads and declares no task: `list`, `run` and
  `capabilities` say so and name `kuu docs task`; the `tasks none`
  rendering documented.
- A first argument that is neither a verb nor a file: `no verb or program
  file 'x'; kuu --help lists the verbs`.
- `TASK unknown` suggests the nearest task and names `kuu list`; `TASK
  noproject` names `kuu docs adopting`.
- The first creation of `.kuu/` under a root whose `.gitignore` does not
  list it: one stderr line naming ledger.md.
- `check` warns on `rt.version:match(` and on a version compared by
  pattern, naming `rt.version_at_least` and upgrading-0.9; a manifest
  assertion that fails mentioning the version gets the same pointer.
- `check` from a tasks.lua project warns like `run` and `list`, and
  check.md says the fallback.
- Every stderr notice the verbs print (`tasks.lua`, `.kuu/` created) is
  also a `notes: string[]` on the `run`, `list` and `capabilities` JSON
  envelopes, documented.
- Checks for each.

### Batch 4 — the content the jobs need

- ledger.md: a `LedgerRecord` type, kind-discriminated, with the error
  shape and what `code`, `argv` and `task` mean on a verb record, and a
  reader that prints the last failed record.
- `TASK failed` carries `status` and `limit` on the error and the child
  event carries `limit`, so a task branches on fields; task.md says so.
- err.md gains "In your own code"; task.md says a returned string is
  wrapped as `TASK failed`.
- cookbook.md gains four manifest-shaped recipes: a task with arguments
  calling a declared tool; a wrapper module decoding a tool's NDJSON; a
  reader of the `--json` stream; a reader of the ledger. Its "0.7 or later"
  line updated.
- task.md's canonical manifest declares its tools and starts with `global
  none`; mem.md's `.kuu/` exception goes; pitfalls.md's "every message"
  narrows to classified failures and names the progress and warning
  shapes; check.md says a file that does not parse gets that one error and
  nothing else; index.md or task.md says a task without `task.defaults` or
  a `timeout` has no time bound.
- `kuu run TASK --help` prints the task's usage on stdout and exits 0 like
  every other `--help`; task.md follows.
- Checks for each; the cookbook extraction case covers the new recipes.

### Batch 5 — 0.10.0

- `KUU_VERSION` to 0.10.0; index.md's version sentence and inventory;
  upgrading-0.10.md's preamble (released, the guard advice holds);
  ledger.md's example; kuu.md's Where things stand; README's version
  paragraph; `capabilities.md` sentence on which verbs are answered in C.
- One usage string: `kuu --help` carries the full option set for `run` and
  `check`, and `tools/bundle_docs.lua --write` writes index.md's usage
  block and kuu.md's Start here block from it between markers, held by the
  bundle case.
- The final gate. Push and `make publish` are the owner's.

## Out

- A `check` warning for a missing `kuu-eval.md`: an agent that has not
  written yet has done nothing wrong.
- Sending an eval anywhere: kuu fetches nothing and sends nothing; the
  file is the project's, and the maintainer collects it.
- `kuu watch`: still deferred until something runs unattended.

## Status

| batch | state |
|---|---|
| 1 | done 2026-09-13. `docs/agent.md` and the routing from `--help`, the `docs` footer, both forms of `capabilities` (`next`, `project.eval`), index.md, kuu.md, README; task.md's canonical manifest declares its tools. A three-lens review of the page, a skeptic per finding, confirmed twenty (the timeout wording, the sample output, the heading contract stated exactly, fenced output not counted, a file present but empty told apart, the literal-name rule, the two laws, the short form) — all folded in before the gate |
| 2 | done 2026-09-13. `rt.page`; `lua/cmd/docs.lua` replaces the C route: descriptions, sections by heading or GitHub anchor, search over all its words, `--json` for each, `--help`, the unknown-option and surplus-word laws; proc.md heads its code set `## Errors`; index.md documents the verb with four schemas. A two-lens review confirmed eleven (a `## ` inside a fence taken for a section, anchors keeping punctuation, a blank search printing the manual, pty's description a code line, the capabilities verbs row overflowing its column, README's usage line, surplus words accepted) — all folded in before the gate |
| 3 | — |
| 4 | — |
| 5 | — |
