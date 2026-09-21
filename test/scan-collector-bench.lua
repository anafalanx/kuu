-- Reuse retained scan-bench projects read-only; measure shared collection,
-- not task latency. No manifest execution, fixture writes or ledger changes.
global none
global <const> require, assert, ipairs, table, tostring, type, io, os, collectgarbage, string

local fs, rt, cli, json, scan, policy = require "fs", require "rt", require "cli", require "json", require "_scan", require "_scan_policy"
local sched, hash, time, sys = require "sched", require "hash", require "time", require "sys"
local began = sched.clock()
local spec = {
  { "--baseline", type = "string", required = true, help = "retained scan-bench JSON report identifying fixture roots" },
  { "--out", type = "string", required = true, help = "new result JSON path; refuses overwrite" },
  { "--repeats", type = "int", default = 3, min = 1, max = 20, help = "warm observations after the first" },
}
local opts, why = cli.parse(rt.args, spec, "kuu test/scan-collector-bench.lua")
if not opts then io.stderr:write(tostring(why), "\n") os.exit(2) end
if opts.help then io.write(cli.usage(spec, "kuu test/scan-collector-bench.lua")) os.exit(0) end
local output = fs.absolute(opts.out)
local exists, problem = fs.exists(output)
assert(exists == false, "report exists or cannot be inspected: " .. output .. ": " .. tostring(problem))
local baseline_text = assert(fs.read(opts.baseline))
local baseline = assert(json.decode(baseline_text))
assert(baseline.schema == "kuu.scan-bench.v1" and baseline.status == "complete", "expected a complete scan-bench report")
assert(type(baseline.cases) == "table", "baseline cases must be an array")
local chosen = { tiny = true, generated = true, unexcluded = true, pruned_control = true }
local selected, seen = {}, {}
local output_folded = output:lower()
for _, case in ipairs(baseline.cases) do
  assert(type(case) == "table", "baseline case must be an object")
  assert(type(case.root) == "string", "retained case has no root: " .. tostring(case.name))
  case.root = fs.absolute(case.root)
  -- Ordinary absolute-path comparison prevents accidentally placing the
  -- result in any retained fixture, including cases not measured here.
  -- It does not resolve aliases or provide confinement.
  local boundary = case.root:lower():gsub("/+$", "")
  assert(output_folded ~= boundary and output_folded:sub(1, #boundary + 1) ~= boundary .. "/",
    "report must be outside retained fixture: " .. case.root)
  if chosen[case.name] then
    assert(not seen[case.name], "duplicate retained case: " .. case.name)
    seen[case.name] = true
    assert(fs.exists(case.root) == "directory", "missing retained fixture: " .. case.root)
    selected[#selected + 1] = case
  end
end
for _, name in ipairs { "tiny", "generated", "unexcluded", "pruned_control" } do
  assert(seen[name], "baseline is missing retained case: " .. name)
end
local defaults = assert(policy.decode('{"v":1}'))
local machine = sys.info()
local report = {
  schema = "kuu.scan-collector-bench.v1", at = time.iso(), exe = rt.exe,
  sha256 = assert(hash.file("sha256", rt.exe)), driver_sha256 = assert(hash.file("sha256", rt.program)),
  baseline = fs.absolute(opts.baseline), baseline_sha256 = hash.sum("sha256", baseline_text),
  original_payload_files_per_populated_case = baseline.options.files, warm_repeats = opts.repeats,
  windows = machine.windows, cpus = machine.cpus, cases = json.array {},
  boundary = "Read-only reuse of retained fixture roots. Measures in-process native collection, adapter sorting and compatibility filtering. Scope loading, process startup, task execution, content hashing and ledger publication are excluded. First observations are not controlled cold-cache samples; order and all samples are retained.",
}
local count_fields = { "files", "enumerated_dirs", "excluded_dirs", "nofollow_links", "errors" }
for _, case in ipairs(selected) do
  for _, mode in ipairs { "legacy-ledger", "configured-defaults" } do
    collectgarbage("collect")
    local row = { case = case.name, mode = mode, root = case.root, samples = json.array {} }
    local warm = {}
    for i = 0, opts.repeats do
      local started = sched.clock()
      local observed
      if mode == "legacy-ledger" then observed = scan.compat(case.root, "ledger")
      else observed = scan.collect(case.root, defaults) end
      local seconds = sched.clock() - started
      assert(observed.complete, json.encode(observed.errors))
      local expected = row.samples[1] and row.samples[1].counts
      if expected then
        for _, name in ipairs(count_fields) do
          assert(observed.counts[name] == expected[name], string.format(
            "%s / %s: retained fixture count %s changed from %s to %s",
            case.name, mode, name, tostring(expected[name]), tostring(observed.counts[name])))
        end
      end
      row.samples[#row.samples + 1] = { seconds = seconds, first = i == 0, counts = observed.counts }
      if i > 0 then warm[#warm + 1] = seconds end
    end
    table.sort(warm)
    local n = #warm
    row.median_seconds = n % 2 == 1 and warm[n // 2 + 1] or (warm[n // 2] + warm[n // 2 + 1]) / 2
    row.min_seconds, row.max_seconds = warm[1], warm[n]
    report.cases[#report.cases + 1] = row
    io.write(string.format("%s / %s: %.3f ms, %d dirs, %d files\n", case.name, mode,
      row.median_seconds * 1000, row.samples[1].counts.enumerated_dirs, row.samples[1].counts.files))
  end
end
report.status, report.finished_at = "complete", time.iso()
report.elapsed_seconds = sched.clock() - began
assert(fs.mkdir(fs.dirname(output)))
assert(fs.write(output, json.encode(report, { pretty = true }) .. "\n"))
io.write("results: ", output, "\n")
