# Upgrading to 0.6

0.6 is a local development version; no release has been published by this work.
Keep `kuu.exe` directly in the project root and declare the supported runtime
version in `tasks.lua`. The previous 0.5 review fixes are included.

## Duration migration

`cli.duration` and CLI entries with `type="duration"` now return **seconds**,
the same numeric unit accepted by `proc`, `sched`, `http`, `sync`, and `net`.
For example, `100ms` returns `0.1`; `2s` returns `2`.

- Divide old duration `min`, `max`, and numeric `choices` by 1,000.
- Numeric defaults already represented input seconds; keep them unchanged.
- Remove conversions such as `opts.timeout / 1000` before a process call.
- Remove workarounds such as `tostring(opts.timeout) .. "ms"`.
- Multiply a result by 1,000 only when deliberately calling an API that wants
  milliseconds. Native Kuu duration APIs already want seconds.

The string grammar and millisecond rounding remain shared with `time.duration`.
If an unusually large duration must preserve an exact integer millisecond count,
keep the unit-bearing string and pass it directly to the consuming native API.

Time Actual currently accepts 0.5 and 0.6 with explicit compatibility branches,
so its pinned published CI binary stays usable before a 0.6 release.

## Other changes

- `kuu version` and `kuu --version` print the same identity and reject extra
  arguments. Use `kuu ./version` to execute a script literally named `version`.
- `task "all" {deps={"build", "test"}}` needs no empty `run` function.
- `proc.list`, `proc.find`, and `proc.tree` return `exe` with forward slashes.
  Command lines remain verbatim; path aliases still require `fs.canon` identity.
- Archive listings preserve Unicode names and embedded newlines. They use the
  Windows archive library in a supervised copy of Kuu, rather than tar's ANSI
  text output. ZIP packing explicitly selects UTF-8 headers too.
- TLS client-key and proxy failures report `HTTP tls` and actionable details.

Windows' Tcl sandbox behavior and tools that construct their own shell commands
remain external boundaries; see [observed shortcomings](shortcomings.md).
