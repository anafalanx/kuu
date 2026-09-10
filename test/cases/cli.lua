-- cli.lua -- argument parsing from a declared spec.
global none
global <const> require, ipairs, tostring, type, string, pcall, table, math

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local cli = require "cli"
  local err = require "err"

  local spec = {
    { "--interval", type = "duration", default = "2s", min = 0.1, help = "refresh interval" },
    { "--format", type = "string", default = "text", choices = { "text", "json" }, help = "output format" },
    { "--all", type = "flag", help = "show everything" },
    { "--limit", type = "size", help = "cap" },
    { "--count", type = "int", min = 1, max = 10 },
    { "--ratio", type = "number" },
    { "dir", type = "string", default = ".", help = "directory to watch" },
    { "files", type = "string", rest = true, help = "files to process" },
  }

  local opts = cli.parse({}, spec)
  check("defaults apply", opts.interval == 2 and opts.format == "text" and opts.all == false and opts.dir == "." and #opts.files == 0 and opts.help == false and opts.limit == nil)

  opts = cli.parse({ "--interval", "500ms", "--format=json", "--all", "--limit", "16M", "--count", "3", "--ratio", "0.5", "src", "a.lua", "b.lua" }, spec)
  check("options and positionals parse and convert", opts and opts.interval == 0.5 and opts.format == "json" and opts.all == true
    and opts.limit == 16 * 1024 * 1024 and opts.count == 3 and opts.ratio == 0.5 and opts.dir == "src" and table.concat(opts.files, ",") == "a.lua,b.lua")

  opts = cli.parse({ "--all=false", "--", "--not-an-option", "x" }, spec)
  check("-- ends options and flags accept =false", opts and opts.all == false and opts.dir == "--not-an-option" and opts.files[1] == "x")

  opts = cli.parse({ "--help" }, spec)
  check("--help is a returned value", opts and opts.help == true)

  local none, e = cli.parse({ "--bogus" }, spec, "tool")
  check("an unknown option is nil, CLI usage with the usage text", none == nil and err.is(e, "CLI", "usage") and contains(e.message, "unknown option '--bogus'") and contains(e.message, "usage: tool [options] [dir] [files ...]"), tostring(e))
  none, e = cli.parse({ "--interval" }, spec)
  check("a missing value is refused", none == nil and contains(e.message, "--interval needs a value"), tostring(e))
  none, e = cli.parse({ "--interval", "soon" }, spec)
  check("a bad duration is refused", none == nil and contains(e.message, "needs a duration"), tostring(e))
  none, e = cli.parse({ "--interval", "50ms" }, spec)
  check("min is enforced after conversion", none == nil and contains(e.message, "at least 0.1"), tostring(e))
  none, e = cli.parse({ "--count", "11" }, spec)
  check("max is enforced", none == nil and contains(e.message, "at most 10"), tostring(e))
  none, e = cli.parse({ "--format", "xml" }, spec)
  check("choices are enforced", none == nil and contains(e.message, "one of text, json"), tostring(e))
  none, e = cli.parse({ "--count", "x" }, spec)
  check("an int refuses non-numbers", none == nil and contains(e.message, "whole number"), tostring(e))

  local strict = { { "--name", type = "string", required = true }, { "target", required = true } }
  none, e = cli.parse({}, strict)
  check("a missing required positional is refused", none == nil and contains(e.message, "missing required argument <target>"), tostring(e))
  none, e = cli.parse({ "t" }, strict)
  check("a missing required option is refused", none == nil and contains(e.message, "missing required option --name"), tostring(e))
  opts = cli.parse({ "--help" }, strict)
  check("--help waives missing required values", opts and opts.help == true)
  none, e = cli.parse({ "--name", "n", "t", "extra" }, strict)
  check("an unexpected extra argument is refused", none == nil and contains(e.message, "unexpected argument 'extra'"), tostring(e))

  local usage = cli.usage(spec, "watchit")
  check("usage lists arguments and options with their facts",
    starts(usage, "usage: watchit [options] [dir] [files ...]\n") and contains(usage, "--interval <duration>") and contains(usage, "default 2s")
    and contains(usage, "one of text, json") and contains(usage, "--help") and contains(usage, "files ") , usage)

  local ok, e2 = pcall(cli.parse, {}, { { "--x", typo = 1 } })
  check("an unknown attribute in the spec raises CLI badvalue", not ok and err.is(e2, "CLI", "badvalue"), tostring(e2))
  ok, e2 = pcall(cli.parse, {}, { { "--x", type = "flag" }, { "x" } })
  check("colliding keys raise", not ok and err.is(e2, "CLI", "badvalue") and contains(tostring(e2), "collides"), tostring(e2))
  ok, e2 = pcall(cli.parse, {}, { { "--n", type = "int", default = "abc" } })
  check("a default that fails its own type raises", not ok and err.is(e2, "CLI", "badvalue"), tostring(e2))
  ok, e2 = pcall(cli.parse, {}, { { "--help" } })
  check("redeclaring --help raises", not ok and err.is(e2, "CLI", "badvalue"), tostring(e2))
  ok, e2 = pcall(cli.parse, {}, { { "rest", rest = true }, { "after" } })
  check("a positional after the rest entry raises", not ok and err.is(e2, "CLI", "badvalue"), tostring(e2))

  check("cli.duration and cli.size convert", cli.duration("1.5s") == 1.5 and cli.duration("2h") == 7200 and cli.duration("x") == nil
    and cli.size("2K") == 2048 and cli.size("1MB") == 1048576 and cli.size("10") == 10 and cli.size("x") == nil)
  do
    local cli = require "cli"
    check("CLI durations share sums and days with the native parser",
      cli.duration("1h30m") == 5400 and cli.duration("2d") == 172800 and cli.duration("1m30s") == 90)
    local opts, e = cli.parse({ "--wait", "1h30m" }, { { "--wait", type = "duration" } })
    check("typed CLI arguments accept compound durations", opts and opts.wait == 5400, tostring(e))
    check("CLI durations agree with time.duration, including large values",
      cli.duration("4500000000000021ms") == require("time").duration("4500000000000021ms")
      and cli.duration("1h30m") == require("time").duration("1h30m"))
    check("CLI durations reject NUL suffixes, infinity, NaN, and negative numbers",
      cli.duration("1s\0junk") == nil and cli.duration(math.huge) == nil and cli.duration(0/0) == nil and cli.duration(-1) == nil)
  end

  do
    local numeric = cli.parse({}, {{"--wait", type="duration", default=0.075, min=0.05, max=0.1}})
    check("numeric duration defaults and bounds use seconds", numeric and numeric.wait == 0.075)
    check("duration results can be parsed again without scaling", cli.duration(cli.duration("100ms")) == 0.1)
    local r = T.kuu { "-e", [[
      local cli, proc, rt = require "cli", require "proc", require "rt"
      local opts = assert(cli.parse(rt.args, {{"--timeout", type="duration"}}))
      local r = assert(proc.run {rt.exe, "-e", "require('sched').sleep('5s')", timeout=opts.timeout})
      assert(r.status == "timeout" and r.elapsed < 2)
      io.write("deadline enforced")
    ]], "--timeout", "100ms" }
    check("CLI durations pass directly to process timeouts", r.code == 0 and r.out == "deadline enforced", T.describe(r))
  end

end
