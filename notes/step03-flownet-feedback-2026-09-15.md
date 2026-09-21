# Step 03 — declarative scan policy

Status: complete. The private loader, strict configuration contract, regression cases, bounded benchmark and public documentation are implemented. Steps 04–21 remain unstarted.

## Implemented contract

[lua/_scan_policy.lua](../lua/_scan_policy.lua) reads root-level `kuu.config.json` without reading or executing a manifest. Its private `decode` entry point validates text, and `load` performs a bounded UTF-8 file read and records absolute root/source provenance. Every successful call returns fresh data; replacing the file affects subsequent loads, not a previously returned snapshot.

The versioned schema requires `v: 1`, allows an optional `scan` object and accepts only `defaults`, `exclude_dirs` and `exclude_paths` within it. Missing fields have explicit defaults; null, wrong containers/types, unknown keys and duplicate JSON keys are errors. Absence selects defaults; unreadable, malformed, oversized or wrongly typed filesystem entries do not. A missing project root and a read failure on an existing config cannot masquerade as absent configuration.

Normalization produces sorted, deduplicated names/paths using slash separators and **ASCII-only case folding**. It rejects ambiguous Windows components, traversal, roots/drives/streams and wildcard syntax. Mandatory `.git`/`.kuu` rules are separate from the optional default set. The returned descriptor includes normalized custom/effective rules, deterministic canonical scope JSON and its SHA-256 fingerprint, independent of root and source provenance.

Limits are explicit: **256 entries per original list before deduplication**, **1 MiB per configuration file**, **255 UTF-16 units per component**, and **32,760 per relative path**. Those are validation bounds, not a guarantee that a resulting absolute path is usable on every filesystem.

No public command consumes this module yet. Existing checker, capabilities and ledger scopes remain unchanged, including the step 02 link fix. The plan requires collector integration and safe baseline migration before activation. Loading before the manifest, command-level configuration diagnostics, explicit-root overrides and pre-descent matching are documented integration contracts for steps 04–05, rather than falsely advertised as current command behavior. `SCAN config` remains private until public activation also adds its error metadata.

## Files and documentation

- [lua/_scan_policy.lua](../lua/_scan_policy.lua): normalization, validation, source loading and stable scope descriptor.
- [test/cases/scan_policy.lua](../test/cases/scan_policy.lua): table-driven contract cases; registered in [test/run.lua](../test/run.lua).
- [test/scan-policy-bench.lua](../test/scan-policy-bench.lua): repeatable normalization benchmark, with raw observations and runtime/driver hashes.
- [docs/scan.md](../docs/scan.md): exact JSON examples, rules, limits, errors and activation boundary; linked from check, capabilities, ledger and index. The manual now has 48 pages.

Retrieve the embedded contract with `kuu docs scan`.

## Validation

The focused suite passed **564 checks, zero failures, in 17.5 seconds** across `scan_policy`, `check`, `check_corpus`, `capabilities`, `ledger`, `task`, `docs` and `palette`. After optimizing normalization, all **179 policy checks** were rerun and passed in **0.1 seconds**. The focused suite's optional real file-symlink fixture remains skipped on this host; real junction and mandatory metadata coverage pass as in step 02.

Static checking from the test directory passed for all four new/changed Lua files: **zero errors and warnings**. The embedded scan page matches its source, and **both documented JSON examples validate**. `git diff --check` passed. Independent review covered the schema, implementation, tests and documentation; 49 additional in-memory differential cases confirmed that the character-count/folding optimization preserves behavior.

Review caught a doubled-BOM inconsistency: the UTF-8 reader removes one BOM, so passing its output to a decoder that also accepts a BOM could accept two. The loader now rejects a remaining prefix, and both direct decoding and file loading test this case. Diagnostics also have assertions for field/index specificity and parser byte locations.

```powershell
.\.tools\msys2\ucrt64\bin\mingw32-make.exe -j4 all
.\build\kuu.exe test/run.lua scan_policy check check_corpus capabilities ledger task docs palette
.\build\kuu.exe test/scan-policy-bench.lua --out build/NEW-policy-benchmark.json
```

The benchmark refuses an existing output path. It measures JSON decoding, validation, normalization, canonical encoding and hashing inside an already-running process. Input construction, configuration file I/O, manifest execution and tree traversal are outside the samples. Each case warms up five times; ordinary garbage collection remains enabled.

## Normalization measurements

Windows 11 25H2 build 26200.6899, x64, 12 logical CPUs. These are observations on this host, not universal thresholds or a Windows 11 23H2 compatibility result.

| Case | JSON bytes | Warm samples | Median | Range |
|---|---:|---:|---:|---:|
| Defaults only | 7 | 200 | 0.023 ms | 0.021–0.073 ms |
| 256 names + 256 ordinary paths | 12,595 | 200 | 6.496 ms | 4.822–10.071 ms |
| 256 names + 256 long paths, near byte limit | 1,032,499 | 20 | 260.179 ms | 246.033–333.573 ms |

The first implementation measured 8.306 ms for ordinary rules and 939.511 ms near the byte limit. Replacing per-character Lua work with native UTF-8 counting and ASCII replacement-table lookups, and avoiding redundant device-name folding for long stems, reduced the large case by about 72%. The large accepted input still has a noticeable normalization cost; it is bounded and should be loaded once per operation as planned.

Retained evidence:

- [Focused suite](../build/step03-focused-tests.log), [final policy checks](../build/step03-policy-tests-optimized.log), [static checks](../build/step03-static-check-final.log), [embedded examples](../build/step03-doc-examples.log).
- [Initial benchmark](../build/step03-policy-benchmark.json), [optimized benchmark](../build/step03-policy-benchmark-optimized.json), [final build log](../build/step03-build-optimized.log).

Generated evidence is ignored build output; retain it before cleaning build artifacts. Final development executable SHA-256:

`c188ce0472124d7638a86c6171ec2e515e70786e800d248c2083452fc55abc22`

The signed baseline remains unchanged at `build/release-011-download/kuu.exe`, SHA-256 `68d2d31f8238c42f57bed6c9aca452f1d1874453ece473e089b8b5d3ee0f9450`. No native code, version, release, signing, commit or push was changed/performed. FlowNet was not modified or executed.

## Time and next step

Work began at 2026-09-15 21:06:15 UTC; final evidence verification completed at 21:15:06 UTC. Actual agent wall time was **about nine minutes**, below the **20–40 minute** forecast. The next executable step is **04: shared traversal with exclusion before descent**, integrated under existing effective scopes until step 05 can safely activate configuration.
