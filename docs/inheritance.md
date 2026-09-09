# Inheritance

What kuu carries over from machteld, the z estate, the els method, and the
archived and adjacent projects, harvested on 2026-09-09 from their sources,
retrospectives, and commit histories. Each item is a law kuu keeps, a trap it
must not fall into again, or a contract it copies. The source is named so the
reasoning can be reread. This is the register the roadmap's "learn every
lesson" instruction produces; add to it, never silently edit it.

## Laws

- **Lua orchestrates; C only for what Lua cannot reach.** Every serious bug in
  the estate's C was a lifetime or bounds bug the script layer structurally
  cannot have. (els method §1)
- **Fail closed; refuse rather than approximate.** A confident wrong artefact
  is worse than a refusal that names what is missing. Whatever subset ships
  is stated exactly, and the rest is refused by name. (els method §11)
- **Nothing goes missing without a counted cause.** A walk, a watch, a
  capture never presents a silent partial result: every omitted branch,
  dropped event, or truncated stream is accounted for in the result.
  (machteld `dirs.c` header; watch `dropped`; `run` `truncated`)
- **Fact and decision are separate keys.** Report what was observed and what
  was done about it as two fields, so a reader can see them disagree.
  (`dirs.c` `surrogate` versus `action`)
- **Strict text at every boundary.** No U+FFFD, no best fit, no ANSI by
  default: a name that cannot be represented is refused, never renamed.
  Windows tools emit the system code page; decode deliberately.
  (`wintext.h`; els method §10 trap 14)
- **Expected outcomes are data.** Timeout, killed, truncated, unknown are
  result states beside the answer, never exceptions and never disguised as
  the answer. Programming mistakes raise. (`proc` result shape; machteld
  research §7, §12)
- **The no-orphans law.** Every child has a decided lifetime and dies with
  the runtime unless detached on purpose; detaching is not a lifetime policy.
  (els method §16; the spac incident of 2026-08-16)
- **An upstream library's vocabulary never becomes the contract.** yyjson,
  SQLite, WinHTTP names stop at the module boundary. (ecosystem policy)
- **The manifest is authored, never inferred.** What kuu advertises about
  itself comes from declarations, not from scanning implementation text.
- **Write the why into the code.** Every load-bearing strangeness carries the
  failure it prevents, so the next reader can tell it from style.
- **Measure honestly.** Register predictions before measuring; a band tighter
  than the noise floor is unfalsifiable; interleave comparisons; a cold file
  cache produced a tenfold wrong number five separate times. (els method §11;
  reken)
- **Verification enumerates from the other side.** A test that iterates your
  own list is blind to what is missing; a 273-of-273 gate hid four missing
  tools for a month.
- **Build the hostile fixture first.** The real junction, dangling link,
  hidden directory, or locked file exposes what self-review never does.

## Windows traps kuu's C obeys

Paths and the file system (`fs`):

- Apply `\\?\` only after `GetFullPathNameW`; recognise the prefix before and
  after normalisation, because `//?/C:/x` normalises into a form the UNC test
  misreads. Without the prefix seven directories at 278 to 424 characters
  vanished from a walk with a clean exit.
- Under `\\?\` a doubled separator is a real empty component. `\\?\UNC\` is
  eight characters standing in for two. A drive root keeps its trailing
  backslash: `\\?\C:` is the device.
- A component ending in `.` or a space is silently rewritten by
  normalisation and can name a different directory; refuse it by name.
- `GetFullPathNameW` returns the needed size and writes nothing when the
  buffer is too small; treat `got >= need` as failure.
- Enumerate with `FILE_ID_BOTH_DIR_INFO`; the restart class returns the first
  batch and is not a seek, so the loop is do-while. Grow the buffer on both
  `ERROR_MORE_DATA` and `ERROR_NOT_ENOUGH_MEMORY`; a 64-byte probe returns the
  latter. Names are not NUL-terminated. The reparse tag in `EaSize` is only
  meaningful when the reparse attribute is set.
- Sort siblings yourself, unsigned, in UTF-8: NTFS order is a case-insensitive
  collation disjoint from byte order, and a signed compare puts every
  non-ASCII name before `a`.
- A directory handle needs `FILE_LIST_DIRECTORY` with backup semantics; open
  reparse points raw (`FILE_FLAG_OPEN_REPARSE_POINT`) or a junction hands you
  its target's contents. Reclassify on the handle immediately before descent;
  the handle may veto but never authorise. The root is exempt: you named it,
  you get it.
- The name-surrogate bit is `0x20000000`; DFS and DFSR redirect without it;
  cloud placeholders are content behind a filter. A dangling link is its own
  error, distinct from not found: a resolver may pass a missing component
  but must stop at an existing broken link.
- The reparse payload's offsets are relative to `PathBuffer`, not the struct,
  and the fixed part must be checked per arm before it is read; one wrong
  constant was a heap over-read with a working proof of concept.
- Identity is the volume serial plus the 64-bit file index, compared as
  opaque tokens; `dev` from a portable stat is the drive letter index, and
  existence predicates answer true for a dangling junction.
- `CloseHandle` clobbers `GetLastError`. A double close is a process that
  stops, not an error you catch: null the handle the moment another owner
  takes it.
- Never delete through a junction: removing a tree opens every directory raw
  and removes a link as a link.

Processes (`proc`), inherited and already applied:

- Born-in-job through `PROC_THREAD_ATTRIBUTE_JOB_LIST`; one `LimitFlags`
  write is authoritative, so re-assert kill-on-close whenever a limit is set;
  duplicate each distinct standard handle once and restrict inheritance to
  the list; resolve `cmd.exe` from your own environment, never the child's.
- `cmd.exe` re-parses its `/c` argument; batch files run through a
  defensively quoted `cmd.exe` (CVE-2024-24576). Environment blocks are
  sorted with `CompareStringOrdinal`, case-insensitively.
- Start output drains before feeding stdin, or two full pipes deadlock. A
  child completes when its whole job is empty, not when its process exits.
- ConPTY, for later: a parent with redirected standard handles poisons the
  child unless `STARTF_USESTDHANDLES` is set with explicit nulls; teardown
  must drain the output pipe on a thread while `ClosePseudoConsole` runs.

Watching (`fs.watch`):

- Arm the first `ReadDirectoryChangesW` before returning; until it is issued
  the OS records nothing. Zero bytes returned means overflow: disclose it as
  an event with a count. Validate name length parity and next-entry offsets
  on every record. Cancel, then reap the completion before freeing the
  buffer. Coalesce by precedence removed, added, renamed, modified, from
  observations, never last-wins. A watch is a trigger; on overflow the caller
  reconciles from a fresh scan. (machteld `proc.c`; drenn)

Text, JSON, hashing, HTTP:

- `MultiByteToWideChar` substitutes U+FFFD and reports success without
  `MB_ERR_INVALID_CHARS`; NTFS accepts names with unpaired surrogates and a
  lenient conversion collapses two siblings into one.
- Duplicate object keys are refused, with detection that is pairwise below
  sixteen members and sort-based above, comparing by length and bytes; a
  quadratic scan turned a 16 MiB object into minutes. Depth is capped at 512
  independently of the parser. Build an error message before freeing the
  document it points into. An unpaired surrogate escape is a parse error.
  Never route a 64-bit integer through a double: one study's int64 test
  vectors were silently corrupted that way.
- Digest a file in 64 KiB chunks; algorithms are a table of values so the
  list the binary reports is the list it has.
- Do not write TLS; WinHTTP is serviced by Windows Update. Crack URLs with
  the OS parser. Zero timeout means infinite to WinHTTP, so refuse it. Set
  both the receive and the receive-response timeouts. Keep raw headers
  beside cooked ones because `Set-Cookie` repeats. Redirect `none` means zero
  further requests. No insecure flag of any kind. A short body that looks
  whole is the one answer never given.

Host and build:

- `_CRT_glob = 0`: the mingw runtime otherwise expands a literal `*.lua`.
- Compile Lua as C. Foreign threads allocate with the C runtime, never
  through the interpreter's allocator. A count hook never fires inside a C
  call, so an in-process budget cannot stop a C loop; only a process boundary
  can.
- Stage what version control tracks, place artefacts by atomic rename, link
  with `--no-insert-timestamp` and a fixed source date, and demand a
  byte-identical rebuild before signing. Sign the final executable, not the
  interpreter it came from.

## Contracts kuu copies

- Durations and sizes carry units; a bare number is seconds or bytes, never
  a guess. `0xFFFFFFFF` is `INFINITE`, not a duration.
- Options take one shape, a table; unknown option names raise.
- Handles are opaque, never reconstructed from a pid, closed explicitly or
  by `<close>`, and refuse use after close.
- `dirs` returns `root`, ordered `paths`, counts, `links` decisions, `errors`
  rows with the raw Win32 code and the system's message; `-depth` omitted is
  unlimited and zero is the root alone; prune patterns match base names.
- `canon` returns path, volume, file, kind, links, with `dangling` as its own
  code. `watch` events are relative paths with forward slashes.
- `log`: levels debug, info, warn, error, off; default info; sink resolved at
  write time; a write failure never raises, it counts as dropped; validate
  the whole configuration before committing any of it; an odd trailing field
  renders as `key=?`.
- `cli`: a spec is a table with a closed attribute set; parsing never prints
  or exits; `--help` is a returned value; a wrong spec is `badvalue`, a wrong
  command line is `usage`; validate the spec eagerly; `--help` waives missing
  required values only.
- JSON on the command line uses one envelope: `{ok true result}` or
  `{ok false error {domain code message}}`. Structured output by default
  for agents, human text as the development aid.
- The manual ships inside the executable at the exact version, with list,
  get, and search that never touch the network. Error messages are greppable
  in the manual. Every example in the manual is executed by a test.

## Task runners and locks, for 0.3

- Five task runners in the estate shared no library; the same converter and
  the same discovery block were copied three to five times and drifted.
  Provide once: script root, tool discovery, streaming exec with exit-code
  passthrough, capturing exec, tool preflight, atomic place, task lock, the
  dispatcher.
- The task list must live in one place; two-file declarations drifted in
  every project that had them. Tasks need a description, dependencies run
  once, a declared argument spec, `list`, `--json`, timing, and consistent
  exit codes: child code passed through, 1 for failure, 2 for usage.
- A lock must be prescriptive: URL, file, SHA-256, size, license, and how to
  unpack and verify, plus patches pinned by before-and-after hashes and
  license notices pinned at source and destination. z's ledger described what
  was on disk and could restore nothing; downloads matched by fuzzy filename
  were a regret in waiting.
- Hydrate and verify are one code path with a flag. Download to `.partial`,
  hash, then rename; re-hash cached downloads and heal; unpack into a
  temporary directory and rename whole; write stamps last; the stamp is a
  hash of the inputs, including the hydrating code itself; every write stays
  under the cache root; cross-check a tool's reported version against the
  lock.
- A `z env --json` that shows the final argv and environment without running
  anything was the most useful verb agents had. Bare invocation from a pipe
  gets help, never an interactive shell.

## What the estate's agents got wrong

- Under strict globals, declaring any `global` switches the chunk into
  declared-only mode and `print` itself then needs a declaration; the luax
  manual shipped it as trap eight rather than fixing it. kuu documents the
  mode, and recommends `global none` with an explicit standard list.
- Deep recursion on large inputs was the only failure class in one study;
  document limits and the iterative idiom.
- A checker that runs two of three passes is not a gate: three constructs
  typed clean and failed to compile. `check` must run every pass it claims.
- Studies with easy corpora cannot measure a feedback-loop benefit; build the
  discriminating corpus before the instrument.
- Lua's thin string library made string-heavy tasks slower than Python's C
  builtins; `text` and `json` are C for that reason.
