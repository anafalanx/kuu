# Scan baseline and defect reproductions

Current development records execution history without automatic tree snapshots.
`scan-bench.lua`, `scan-profile.lua` and `scan-latency.lua` support this build as
well as the historical runtimes. `scan-repros.lua` is retained for historical
snapshot-era executables; use the `ledger_execution`, `execution_acceptance`,
`scan_native` and `check` suites for current correctness acceptance. The abandoned
indexing probes and their outputs are retained under `build/step07-index-*`,
outside the active source/test surface.

These tools, introduced in Step 01 and extended through ledger migration,
measure the executable supplied to them and retain evidence
in disposable projects under this repository's `build/` directory. They do not
modify the runtime, production Lua modules, or FlowNet. No instrumented runtime
build is required. The small native reproduction helper is a separate program.

| File | Purpose |
|---|---|
| `scan-bench.lua` | Synthetic projects, external command timings, optional profiles, and a JSON report |
| `scan-profile.lua` | Diagnostic execution of the selected runtime's unchanged embedded command, with timed export wrappers |
| `scan-repros.lua` | Known-defect observations with explicit methods and status |
| `scan-collector-bench.lua` | Read-only reuse of retained projects to compare private collector scopes |
| `scan-latency.lua` | Alternating baseline/candidate small-command samples in separate fresh projects |
| `execution-bench.lua` | Reuse owned 100,000-file fixtures to measure execution-only runs and verify old tree state stays untouched |
| `fixtures/scan_fixture.c` | Real Windows directory junctions and temporary exclusive file/directory handles |

## Run the benchmark

Run these PowerShell commands from the kuu repository. The example executable
is the retained, signed 0.11 release download. Substitute another existing kuu
executable to compare a later build. `--exe PATH` can independently select the
runtime under observation; without it the benchmark uses its own executable.

Start with 1,000 payload files per populated scenario:

```powershell
$scanBaseline = 'C:\dev\kuu\build\release-011-download\kuu.exe'
$scanRunId = [guid]::NewGuid().ToString('N')
& $scanBaseline test/scan-bench.lua --files 1000 --repeats 3 --ledger-records 10000 --out "build/scan-smoke-$scanRunId.json"
```

Then run the 100,000-file scale:

```powershell
$scanBaseline = 'C:\dev\kuu\build\release-011-download\kuu.exe'
$scanRunId = [guid]::NewGuid().ToString('N')
& $scanBaseline test/scan-bench.lua --files 100000 --repeats 3 --ledger-records 10000 --out "build/scan-full-$scanRunId.json"
```

`--files` counts payload files **in each** populated scenario, not the entire
run. There are three such scenarios: generated directories, maintained source,
and an already-pruned `.tools` control. Thus the full command creates 300,000
payload files, plus small manifests, visible mutation fixtures, ledgers, and
reports. Allow roughly 1.2 GB for the three large trees, plus reports and ledger
state; actual allocation depends on the filesystem. Fixture creation and its
initial inventory are outside the command timing samples.

The driver prints progress to standard error and the report path to standard
output. The benchmark refuses an existing `--out` path. Without `--out`, it uses
`report.json` inside its newly created `build/scan-bench-*` directory. It saves
progress after samples; a completed report has `status: "complete"`. A command
failure, timeout, or truncated capture fails the benchmark rather than becoming
a successful timing sample. `--timeout` changes the per-command deadline
(default `3m`). `--no-profile` skips diagnostic profiles. `--help` lists options.

## What the benchmark measures

The tiny fixture establishes startup and ordinary task costs. Populated
fixtures distribute payloads under `.cache`, `.local`, nested `.venv`, mixed-case
variants, unexcluded `src/maintained`, and the `.tools` control. One in every 100
payload files is Lua; the rest are small text files. The generated case includes
a nested checkout whose path contains a space. Separate cases seed smaller and
larger valid ledgers. Visible-file mutations cover 0, 1, and 64 changed files;
the unchanged 0.11 ledger hashes at most its `NAMED` limit of 40 named paths.

Commands include version/startup, dry run, no-op, a tiny child, nested kuu tasks,
explicit manifest checking, automatic tree checking, and capabilities. Each
command has a first observation and the requested number of repeated warm
observations. The report gives warm minimum, median, and maximum, retains every
sample, and records initial file/directory counts before ledger seeding and task
operations for each fixture.

Newer reports also retain the command's additive `timings`, scope and scan
metadata for every sample when the measured runtime provides them. Older
executables omit those fields; their external wall measurements remain usable.

`first_observation` is the first sample **of that command**, not necessarily an
empty-ledger run. Earlier commands in the listed sequence may already have
created the tree baseline. `baseline_present_before` records whether
`.kuu/ledger/tree.json` existed immediately before a sample. Neither the first
sample nor subsequent samples establish a controlled cold OS cache: creating
fixtures already warms filesystem caches, and files and ledger state persist
between commands. The mutation samples are separate one-shot observations,
not warm distributions.

`wall_seconds` surrounds the uninstrumented `proc.run` call and includes launch,
captured output, and shutdown. `process_elapsed` and any reported task durations
have different boundaries. Synthetic results are not a measurement of FlowNet's
checkout and must not be presented as reproducing its reported 16-second command.

## Interpret profiles

After all uninstrumented command samples for a case, the driver invokes the
profile worker in separate processes. A profile can also be collected directly
from a disposable project's working directory:

```powershell
& 'C:\dev\kuu\build\release-011-download\kuu.exe' 'C:\dev\kuu\test\scan-profile.lua' --out 'C:\dev\kuu\build\my-unique-profile.json' run --json child
```

Use an output outside the observed project so the report does not become input
to a later scan. The standalone worker also accepts `check` and `capabilities`.
Unlike the benchmark driver, the standalone worker writes its supplied output
path directly, so choose a new filename.

Profiles contain `phases` rows with `path`, `name`, `calls`, `seconds`,
`self_seconds`, error/result counts, and operation-specific counters.
`seconds` is inclusive wall time. `self_seconds` subtracts directly nested
wrappers on the same coroutine. **Do not sum inclusive rows as disjoint phases.**
Separate scheduler coroutines have their own `async` roots, and nested kuu
processes remain uninstrumented. A parent's task duration includes its wait for
those children. Aggregate all matching `name` rows when examining an operation
such as `ledger.record`, because child crossings occur beneath task execution.

On 0.11, initial and final metadata snapshots appear as `fs.dirs` and `fs.list` underneath
`ledger.open` and `ledger.close`. Directory walking includes native recursive
traversal; subsequent listings are the separate metadata pass. `hash.file`
isolates changed-file hashing. Other rows expose record operations, final JSON
encoding/writing, manifest setup, module inventory, ledger tail reading, and
whole-ledger verification. Residual `ledger.open` self time includes delta
construction/sorting and other Lua work; it is not a pure snapshot timer.

Counters count calls and returned entries, not unique paths. Read/write byte
counts describe the Lua strings involved. File hashing counts files; it does
not add extra I/O to discover their sizes. Profiles include instrumentation
limitations. Wrappers and counters perturb execution, and module preloading
removes normal first-require cost from `command_seconds`; use uninstrumented
wall samples for latency comparisons.

## Compare small commands with less order bias

The full benchmark runs command blocks sequentially, so its three warm samples
do not capture all between-block drift. Supplement it with alternating
baseline/candidate runs:

```powershell
.\build\kuu.exe test/scan-latency.lua --baseline build/release-011-download/kuu.exe --candidate build/kuu.exe --out build/NEW-small-command-comparison.json --repeats 15
```

This creates a separate pair of tiny projects for each of six commands:
startup/version, dry run, no-op, child task, checking and capabilities. A project
is used by only one executable version, so incompatible baseline writers never
alternate in one checkout. Each pair gets one first observation and fifteen
warm observations by default. Execution order reverses each pair and the first
side alternates between commands. Every output, sample order, exit status,
executable hash and signature result is retained.

Warm summaries include median, median absolute deviation, range, nearest-rank
p95 and paired candidate-minus-baseline differences. Adjacent baseline changes
help describe the observed noise. These are host-specific descriptive values,
not confidence intervals or an automatic universal latency threshold. Compare
absolute differences with contemporaneous startup, paired spread and the full
benchmark's tiny/already-pruned controls before deciding whether an increase
matters. No-op and child cases accumulate small histories equally by repetition;
large-history costs remain separate cases in the full benchmark.

Run measured workloads sequentially, without test suites, builds or fixture
creation from another harness competing for resources. First observations are
still not controlled cold-cache measurements. Output persistence, report writing
and fixture preparation happen outside each process timer. The harness refuses
an existing report and retains all scratch projects beneath `build/`.

On historical shared-collector builds, each snapshot's walk-then-list work was replaced by
`scan.compat` or `scan.collect` / `native_scan.collect` rows; both initial and final snapshots
still happen. Their counters report enumerated
directories, collected files, exclusions and errors. The worker detects this
private interface when present and still supports signed 0.11. Inclusive
parent/child rows overlap here too.

Current execution-only runs have no initial/final collection and no
`ledger.close`. Their ledger profile measures Git context and record work only;
checking and capabilities still show explicit collector/inventory phases.

To repeat the execution-only acceptance against the retained large fixtures:

```powershell
.\build\kuu.exe test/execution-bench.lua --fixtures build/step07-bench-100k.json --out build/NEW-execution-comparison.json --repeats 7
```

This measures tiny, excluded, maintained-source and 10,000-record-history cases,
checks ordinary runs for the execution-only report shape, and verifies that each
old `tree.json` remains byte-for-byte unchanged. Fixture inventory and old-state
hashing are harness checks outside command timings. The existing histories and
filesystem caches persist. Earlier-day figures in the input report are
historical comparisons, not contemporaneous paired measurements.

## Measure the shared collector

With a development executable containing `_scan` and `_scan_policy`, reuse
the fixture paths from a completed `scan-bench.lua` report:

```powershell
.\build\kuu.exe test/scan-collector-bench.lua --baseline build/step01-bench-100k.json --out build/NEW-collector-benchmark.json --repeats 3
```

The four measured scenarios are tiny, generated, unexcluded and pruned control.
Each is observed under legacy ledger scope and configured defaults.
The report retains the first observation and repeated warm samples, counts,
runtime/driver/baseline hashes and timing boundaries. It refuses existing output
files, duplicate or missing scenarios, output paths inside the retained fixture
paths, incomplete scans and counts that change between samples. Path checks are
ordinary absolute-path comparisons, not protection against aliases or races.

Collection runs without executing manifests, tasks or ledger writes. Scope
loading, process startup and content hashing are outside the sample timer.
These numbers measure collection cost, not end-to-end command speed; the first
sample is not a controlled cold-cache sample. This harness exercises configured
defaults through the private collector. They became active in public commands
with Step 05's ledger migration; Step 04 builds retain the legacy public scope.

## Run defect reproductions

```powershell
$scanBaseline = 'C:\dev\kuu\build\release-011-download\kuu.exe'
$scanRunId = [guid]::NewGuid().ToString('N')
& $scanBaseline test/scan-repros.lua --out "build/scan-repros-$scanRunId.json"
```

Check a retained snapshot-era development build against the same seven
scenarios, using the helper prepared by `make fixtures`:

```powershell
$scanRunId = [guid]::NewGuid().ToString('N')
.\build\step07-pre-execution-history.exe test/scan-repros.lua --fixture build/test/scan_fixture.exe --out "build/scan-repros-historical-$scanRunId.json"
```

The driver normally compiles `fixtures/scan_fixture.c` with the repository-local
GCC at `.tools/msys2/ucrt64/bin/gcc.exe`. Supply `--fixture PATH` to reuse a
previously built helper. `--exe PATH` selects another runtime and re-executes the
driver under it. The default report lives in a fresh `build/scan-repros-*`
directory. Choose a unique explicit output filename; this driver writes that
path directly.

These observations intentionally remain separate from `test/run.lua`:

| Observation | Evidence method |
|---|---|
| Automatic checking/fixing through a junction | Real junction to an owned sibling target; ordinary CLI commands |
| Unreadable scan branch | Real exclusive directory handle and native enumeration |
| Partial listing | Explicit fault injection: hide one returned entry and add a listing error |
| Unreadable tree state | Real exclusive handle on `tree.json` |
| Invalid per-file tree records | Real malformed state contents and a public task run |
| Malformed tree JSON/top-level state | Real truncated/scalar state contents |
| Older snapshot replacing a newer publication | Two processes with a controlled pause after A's final scan and before its publication lock on versioned builds; older builds pause before the real write |

Each observation is `reproduced`, `not_reproduced`, or `unconfirmed`. Exit 0 means
the harness completed, **not** that defects are fixed. Setup or harness failures
produce exit 2; an OS probe unable to establish its prerequisite is explicitly
unconfirmed. On a fixed build, acceptance requires `complete: true`, no harness
errors, and all seven observations marked `not_reproduced`, with their positive
evidence checks satisfied. Missing counts or an unexecuted fault injection do
not count as a fix. The overlap reproducer determines whether the controlled
interleaving permits stale publication; it does not measure natural frequency.
Fault-injected partial enumeration is distinguished from an observed OS error.
The partial-enumeration injection uses `_scan_native.collect` on shared-collector
builds and `fs.list` on older builds; the report records which boundary was used
and whether the injection actually ran.
The driver detects `ledger.TREE_VERSION == 1` for the versioned `kuu.tree`
envelope and retains the signed 0.11 map-format branch. Seeding verifies that
the new envelope is complete, has a positive generation, and is accepted by
the ledger as a valid unchanged predecessor. For versioned builds:

- Unreadable or partial scans must report an explicitly non-exact
  `incomplete` delta and an incomplete scan, withhold publication, and preserve
  the previous baseline bytes and files.
- Unreadable state must be identified as `unreadable`, with no exact delta or
  replacement; its original bytes are checked after the native handle closes.
- Invalid state must be diagnosed without an exception or fabricated exact
  additions, remain unchanged during open, then explicitly publish a complete
  replacement after a successful scan. The public corruption case also requires
  the task to execute and verified ledger crossings to retain the non-exact delta.
- The overlap case records A's initial generation and complete candidate,
  proves B published a later generation, and requires A to return an explicit
  `stale` outcome while preserving B's bytes and generation. Its barrier is
  installed after `ledger.open` and pauses after the real final collection,
  outside the publication lock; pausing a writer while it holds that lock would
  test an artificial deadlock instead.

The report retains delta, observation and publication metadata alongside the
filesystem evidence. A missing positive check is `unconfirmed`, not
`not_reproduced`. File attribute probes belong to the later attribute steps,
outside this harness.

## Retained evidence

Both drivers retain their fixtures and reports; they perform no recursive
cleanup. The benchmark also retains the first observation's stdout/stderr for
each command and complete profile JSON. Report paths point to the owned scratch
directories. Review their absolute locations before any later manual cleanup.

Reports record runtime paths, versions, SHA-256 hashes, and host information.
The benchmark records driver/runtime hashes and confirms the measured executable
hash after completion. Profiles additionally identify the embedded command
source hash. Reproduction reports identify the helper binary and C source hashes.
Keep these with the source revision when comparing results from later steps.

See the [Step 01 work note](../notes/step01-flownet-feedback-2026-09-15.md) for the
measured baseline, reproduction outcomes, and execution time from this
implementation.
