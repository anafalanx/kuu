# cli

Declare a program's arguments once; parse and describe them from that.

```lua
local cli = require("cli")
local spec = {
  { "--interval", type = "duration", default = "2s", min = 0.1, help = "refresh interval" },
  { "--format",   type = "string", default = "text", choices = { "text", "json" } },
  { "--all",      type = "flag", help = "show everything" },
  { "dir",        type = "string", default = ".", help = "directory to watch" },
  { "files",      type = "string", rest = true, help = "files to process" },
}
local opts, e = cli.parse(require("rt").args, spec, "watchit")
if not opts then io.stderr:write(tostring(e), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "watchit")) os.exit(0) end
opts.interval   -- 2 (seconds)
opts.files      -- { "a.lua", "b.lua" }
```

The spec is an array, so positionals take declaration order. A name beginning
with `--` is an option; anything else is positional; a positional with
`rest = true` collects everything left over. Types: `flag`, `string`, `int`,
`number`, `duration` (converted to seconds), `size` (converted to bytes).
Attributes: `type`, `default`, `min`, `max`, `choices`, `help`, `required`,
`rest`. Results are keyed by the name without dashes.

On the command line: `--name value` and `--name=value` both work; a flag is
`--all`, `--all=false`; `--` ends options; `--help` is always accepted and
comes back as `opts.help = true`, waiving missing required values but not
malformed ones.

Parsing never prints and never exits. A wrong command line is `nil, err` with
`CLI usage`, whose message names the problem and ends with the generated usage
text, ready to print. A wrong spec raises `CLI badvalue` immediately: an
unknown attribute or type, a default that fails its own type, two entries on
one key, `--help` redeclared, a flag as a positional, or a positional after the
rest entry.

```lua
cli.usage(spec, "watchit")   -- the text: usage line, arguments, options with defaults and ranges
cli.duration("1.5s")         -- 1.5; nil when it is not a duration
cli.size("16M")              -- 16777216
```
Duration arguments and `cli.duration` use the native runtime's grammar,
including sums (`"1h30m"`, `"1m 30s"`) and days (`"2d"`). Results are
seconds; an invalid duration returns nil. Numeric defaults, `min`, `max`,
and `choices` for durations use seconds too. `proc`, `sched`, `http`, `sync`,
and `net` accept these numbers directly, without conversion:

```lua
local opts = assert(cli.parse(require("rt").args, {
  { "--timeout", type = "duration", default = "30s", min = 0.001 },
}))
local r = require("proc").run { "tool.exe", timeout = opts.timeout }
```

This changed in 0.6: 0.5 returned milliseconds. See
[Upgrading to 0.6](upgrading-0.6.md) before reusing an older spec. Rounding and
floating-point precision match `time.duration`; results are numbers of seconds,
not exact integer millisecond counts at arbitrarily large magnitudes.
