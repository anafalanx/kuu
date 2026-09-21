-- Alternating small-command latency comparison. Unmodified executables use
-- separate fresh fixtures; no instrumentation, profile wrappers or shared
-- baseline writers. Run with --help. Fixtures and every output are retained.
global none
global <const> require, assert, error, ipairs, pairs, type, tostring, table, string, math, pcall, io, os

local fs, rt, cli, json = require "fs", require "rt", require "cli", require "json"
local proc, sched, hash, time, sys = require "proc", require "sched", require "hash", require "time", require "sys"
local spec = {
  { "--baseline", type = "string", required = true, help = "signed baseline executable" },
  { "--candidate", type = "string", help = "candidate executable; defaults to this executable" },
  { "--out", type = "string", required = true, help = "new JSON report path; refuses existing files" },
  { "--repeats", type = "int", default = 15, min = 3, max = 100, help = "warm paired observations after the first pair" },
  { "--timeout", type = "duration", default = "30s", min = 1, help = "timeout per subprocess" },
}
local opts, why = cli.parse(rt.args, spec, "kuu test/scan-latency.lua")
if not opts then io.stderr:write(tostring(why), "\n"); os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu test/scan-latency.lua")); os.exit(0) end

local script = fs.absolute(rt.program)
local repository = fs.absolute(fs.join(fs.dirname(script), ".."))
local build = fs.join(repository, "build")
local output = fs.absolute(opts.out)
local exists, output_error = fs.exists(output)
assert(exists == false, "report already exists or cannot be inspected: " .. output .. ": " .. tostring(output_error))
local executables = { baseline = fs.absolute(opts.baseline), candidate = fs.absolute(opts.candidate or rt.exe) }
for side, exe in pairs(executables) do assert(fs.exists(exe) == "file", side .. " executable missing: " .. exe) end
assert(not fs.same(executables.baseline, executables.candidate), "baseline and candidate must be different executable files")
assert(fs.mkdir(build))
local scratch = assert(fs.tempdir { dir = build, prefix = "scan-latency-" })
local output_parent = fs.dirname(output)
assert(fs.mkdir(output_parent))
local began = sched.clock()
local machine = sys.info()
local report = {
  schema = "kuu.scan-latency.v1", status = "running", at = time.iso(), scratch = scratch,
  driver = { exe = rt.exe, version = rt.version, sha256 = assert(hash.file("sha256", rt.exe)),
    script = script, script_sha256 = assert(hash.file("sha256", script)) },
  host = { windows = machine.windows, cpus = machine.cpus, arch = machine.arch,
    memory_total = machine.memory.total, memory_available = machine.memory.available, elevated = machine.elevated },
  options = { warm_pairs = opts.repeats, timeout_seconds = opts.timeout },
  executables = {}, cases = json.array {}, order = json.array {},
  method = {
    measurement = "sched.clock immediately before and after proc.run; includes process launch, output capture, command work and shutdown",
    fixtures = "Separate newly created baseline/candidate roots for every command. Identical authored bytes, no preseeded ledger history; no checkout receives both executable versions.",
    order = "One first pair then warm pairs per command. Baseline/candidate order reverses each pair and the initial order reverses between commands; full order is retained.",
    first = "First observation per executable and command, not an OS-cold sample; fixture creation and executable hashing already warm filesystem caches.",
    summaries = "Warm samples only. Median, median absolute deviation (MAD), range and nearest-rank p95; paired differences are candidate minus baseline for the same round.",
    interpretation = "Compare absolute and relative median differences with the observed baseline MAD, baseline range, adjacent-baseline changes and paired spread. These describe this host/run, not a confidence interval, universal cutoff or automatic pass/fail rule.",
    history = "Noop and child fixtures accumulate their own small histories equally by repetition. Other command fixtures stay independent; large-history scaling belongs to scan-bench.lua.",
    instrumentation = "Executables run their normal commands without wrappers. Candidate built-in JSON phase reporting remains enabled by --json and is part of its measured command cost.",
    exclusions = "Fixture creation, signatures/hashes, JSON decoding, output persistence and report writing are outside each measured interval. Parent-process and output-capture overhead remain included.",
    limitation = "Alternation reduces drift and order bias but does not control OS caching, antivirus, thermal state or unrelated workloads. This harness must be scheduled apart from other measured workloads.",
  },
}
for _, side in ipairs { "baseline", "candidate" } do
  local signature, signature_error = sys.signature(executables[side])
  report.executables[side] = { path = executables[side], sha256 = assert(hash.file("sha256", executables[side])),
    signature = signature, signature_error = signature_error and tostring(signature_error) or nil }
end
local function save()
  report.elapsed_seconds = sched.clock() - began
  assert(fs.write(output, json.encode(report, { pretty = true }) .. "\n"))
end
save()

local manifest = [[global none
global <const> require
local task, rt = require "task", require "rt"
task.tool "self" { exe = rt.exe, output = "lines" }
task "noop" { run = function() end }
task "child" { run = function() return task.exec { tool = "self", "-e", "io.write('tiny-child')", timeout = "20s" } end }
task.default "noop"
]]
local fixture_files = {
  ["manifest.lua"] = manifest,
  [".gitignore"] = "/.kuu/\n",
  ["README.md"] = "Synthetic tiny project for alternating kuu process-latency observations.\n",
  ["src/value.lua"] = "global none\nlocal M = { value = 1 }\nreturn M\n",
  ["src/input.txt"] = "small maintained input\n",
}
local function create_fixture(root)
  assert(fs.mkdir(root))
  local files = json.array {}
  for name, contents in pairs(fixture_files) do
    local path = fs.join(root, name)
    assert(fs.mkdir(fs.dirname(path)))
    assert(fs.write(path, contents))
    files[#files + 1] = { path = name, bytes = #contents, sha256 = hash.sum("sha256", contents) }
  end
  table.sort(files, function(a, b) return a.path < b.path end)
  return { root = root, initial_files = files, initial_file_count = #files, initial_directory_count = 2,
    ledger_seeded = false }
end
local commands = {
  { name = "startup_version", argv = { "--version" } },
  { name = "dry_run", argv = { "run", "--json", "--dry-run", "child" } },
  { name = "noop", argv = { "run", "--json", "noop" } },
  { name = "tiny_child", argv = { "run", "--json", "child" } },
  { name = "check", argv = { "check", "--json" } },
  { name = "capabilities", argv = { "capabilities", "--json" } },
}
local function median(sorted)
  local n = #sorted
  if n % 2 == 1 then return sorted[n // 2 + 1] end
  return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end
local function statistics(values)
  local sorted = {}
  for i, value in ipairs(values) do sorted[i] = value end
  table.sort(sorted)
  local center = median(sorted)
  local deviations = {}
  for i, value in ipairs(sorted) do deviations[i] = math.abs(value - center) end
  table.sort(deviations)
  return { count = #sorted, median_seconds = center, mad_seconds = median(deviations),
    min_seconds = sorted[1], max_seconds = sorted[#sorted], p95_seconds = sorted[math.ceil(#sorted * 0.95)] }
end
local sequence = 0
local function sample(case, side, round, position)
  local root = case.fixtures[side].root
  local baseline_present = fs.exists(fs.join(root, ".kuu/ledger/tree.json")) == "file"
  local argv = { executables[side], cwd = root, timeout = opts.timeout, maxout = "4M" }
  for _, argument in ipairs(case.argv) do argv[#argv + 1] = argument end
  sequence = sequence + 1
  local started = sched.clock()
  local child, failure = proc.run(argv)
  local wall = sched.clock() - started
  local row = { sequence = sequence, round = round, side = side, position_in_pair = position,
    label = round == 0 and "first_observation" or "warm_" .. round,
    wall_seconds = wall, baseline_present_before = baseline_present,
    status = child and child.status or "launch_failed", code = child and child.code or nil,
    truncated = child and child.truncated or false, process_elapsed = child and child.elapsed or nil,
    error = failure and tostring(failure) or nil }
  case.samples[side][#case.samples[side] + 1] = row
  report.order[#report.order + 1] = { sequence = sequence, case = case.name, round = round, side = side, position_in_pair = position }
  if child then
    local stem = fs.join(scratch, "raw", case.name, string.format("%02d-%s", round, side))
    assert(fs.mkdir(fs.dirname(stem)))
    row.stdout_path, row.stderr_path = stem .. ".stdout.txt", stem .. ".stderr.txt"
    row.stdout_bytes, row.stderr_bytes = #child.out, #child.err
    assert(fs.write(row.stdout_path, child.out))
    assert(fs.write(row.stderr_path, child.err))
    if case.name == "startup_version" then
      if round == 0 then report.executables[side].version_output = child.out end
    else
      local last
      for line in child.out:gmatch("[^\r\n]+") do last = line end
      local decoded, decode_error
      if last then decoded, decode_error = json.decode(last) end
      row.envelope_ok = type(decoded) == "table" and decoded.ok == true
      row.envelope_error = decode_error and tostring(decode_error) or nil
      if type(decoded) == "table" then
        row.command_error = decoded.error
        if type(decoded.result) == "table" then
          row.command_timings, row.tasks = decoded.result.timings, decoded.result.tasks
        end
      end
    end
  end
  save()
  assert(child and child.status == "exit" and child.code == 0 and not child.truncated,
    "unsuccessful sample " .. case.name .. "/" .. side .. "/" .. row.label .. ": " .. json.encode(row))
  assert(case.name == "startup_version" or row.envelope_ok,
    "invalid or failed JSON command envelope in " .. row.stdout_path)
  return wall
end
local function run()
  -- Make every fixture before timing, so creating the next candidate's root
  -- does not occur between the two observations in one pair.
  for _, command in ipairs(commands) do
    local case = { name = command.name, argv = json.array(command.argv), fixtures = {},
      samples = { baseline = json.array {}, candidate = json.array {} } }
    for _, side in ipairs { "baseline", "candidate" } do
      case.fixtures[side] = create_fixture(fs.join(scratch, "fixtures", command.name, side))
    end
    report.cases[#report.cases + 1] = case
  end
  save()
  for command_index, case in ipairs(report.cases) do
    io.stderr:write("measure ", case.name, ": first pair + ", opts.repeats, " warm pairs\n")
    local baseline_values, candidate_values, differences, adjacent_baseline = {}, {}, {}, {}
    for round = 0, opts.repeats do
      local order = (command_index + round) % 2 == 1 and { "baseline", "candidate" } or { "candidate", "baseline" }
      local pair = {}
      for position, side in ipairs(order) do pair[side] = sample(case, side, round, position) end
      if round > 0 then
        baseline_values[#baseline_values + 1], candidate_values[#candidate_values + 1] = pair.baseline, pair.candidate
        differences[#differences + 1] = pair.candidate - pair.baseline
        if round > 1 then adjacent_baseline[#adjacent_baseline + 1] = math.abs(pair.baseline - baseline_values[round - 1]) end
      end
    end
    local baseline_stats, candidate_stats = statistics(baseline_values), statistics(candidate_values)
    case.warm = { baseline = baseline_stats, candidate = candidate_stats,
      paired_candidate_minus_baseline = statistics(differences),
      baseline_adjacent_absolute_change = statistics(adjacent_baseline),
      median_delta_seconds = candidate_stats.median_seconds - baseline_stats.median_seconds,
      median_ratio = baseline_stats.median_seconds > 0 and candidate_stats.median_seconds / baseline_stats.median_seconds or nil }
    save()
    io.write(string.format("%s: baseline %.3f ms, candidate %.3f ms, median delta %+.3f ms; baseline MAD %.3f ms\n",
      case.name, baseline_stats.median_seconds * 1000, candidate_stats.median_seconds * 1000,
      case.warm.median_delta_seconds * 1000, baseline_stats.mad_seconds * 1000))
  end
  for _, side in ipairs { "baseline", "candidate" } do
    local final_hash = assert(hash.file("sha256", executables[side]))
    report.executables[side].final_sha256 = final_hash
    assert(final_hash == report.executables[side].sha256, side .. " executable changed during measurements")
  end
  report.status, report.finished_at = "complete", time.iso()
end

local ok, failure = pcall(run)
if not ok then
  report.status, report.error, report.finished_at = "failed", tostring(failure), time.iso()
end
save()
io.write("results: ", output, "\nfixtures and raw outputs: ", scratch, "\n")
if not ok then io.stderr:write(tostring(failure), "\n"); os.exit(2) end
