-- Bounded scan-policy normalization measurements; no project traversal.
-- kuu test/scan-policy-bench.lua [--out NEW_REPORT.json]
global none
global <const> require, assert, ipairs, table, string, io, os, collectgarbage, tostring

local fs, rt, cli, json = require "fs", require "rt", require "cli", require "json"
local policy, sched, hash, time, sys = require "_scan_policy", require "sched", require "hash", require "time", require "sys"
local spec = { { "--out", type = "string", help = "new report path; refuses overwrite" } }
local options, why = cli.parse(rt.args, spec, "kuu test/scan-policy-bench.lua")
if not options then io.stderr:write(tostring(why), "\n") os.exit(2) end
if options.help then io.write(cli.usage(spec, "kuu test/scan-policy-bench.lua")) os.exit(0) end
local build = fs.absolute(fs.join(fs.dirname(rt.program), "../build"))
local output = fs.absolute(options.out or fs.join(build, "scan-policy-bench-" .. hash.uuid() .. ".json"))
local exists, exists_error = fs.exists(output)
assert(exists == false, "report exists or cannot be inspected: " .. output .. ": " .. tostring(exists_error))
assert(fs.mkdir(fs.dirname(output)))

local dirs, paths, long_dirs, long_paths = json.array {}, json.array {}, json.array {}, json.array {}
for i = 1, 256 do
  dirs[i] = string.format("GENERATED-%03d", i)
  paths[i] = string.format("Vendor\\Package-%03d\\Generated", i)
  long_dirs[i] = string.rep("D", 236) .. string.format("%03d", i)
  -- Close to the byte limit without exceeding either component/path bound.
  long_paths[i] = string.rep(string.rep("P", 250) .. "\\", 15) .. string.format("Last-%03d", i)
end
local cases = {
  { name = "default", text = '{"v":1}', repetitions = 200 },
  { name = "512_rules", text = json.encode { v = 1, scan = { exclude_dirs = dirs, exclude_paths = paths } }, repetitions = 200 },
  { name = "512_long_rules", text = json.encode { v = 1, scan = { exclude_dirs = long_dirs, exclude_paths = long_paths } }, repetitions = 20 },
}
local machine = sys.info()
local report = {
  schema = "kuu.scan-policy-bench.v1", at = time.iso(), exe = rt.exe, version = rt.version,
  sha256 = assert(hash.file("sha256", rt.exe)), driver_sha256 = assert(hash.file("sha256", rt.program)),
  windows = machine.windows, cpus = machine.cpus, arch = machine.arch,
  max_rules_per_list = policy.MAX_RULES, max_bytes = policy.MAX_BYTES, cases = json.array {},
  boundary = "Each sample measures decode, schema/path validation, normalization, canonical encoding and fingerprinting. Input generation, file I/O, manifest loading and traversal are excluded. Warmed in-process samples include ordinary garbage collection; no universal timing threshold.",
}
for _, case in ipairs(cases) do
  assert(#case.text <= policy.MAX_BYTES)
  for _ = 1, 5 do assert(policy.decode(case.text)) end
  collectgarbage("collect")
  local samples, total, result = json.array {}, 0
  for i = 1, case.repetitions do
    local started = sched.clock()
    result = assert(policy.decode(case.text))
    samples[i] = sched.clock() - started
    total = total + samples[i]
  end
  local sorted = {}
  for i, value in ipairs(samples) do sorted[i] = value end
  table.sort(sorted)
  local n = #sorted
  local median = (sorted[n // 2] + sorted[n // 2 + 1]) / 2
  report.cases[#report.cases + 1] = {
    name = case.name, bytes = #case.text, repetitions = n, warmup = 5,
    dirs = #result.exclude_dirs, paths = #result.exclude_paths, effective_dirs = #result.effective_dirs,
    fingerprint = result.fingerprint, samples_seconds = samples,
    median_seconds = median, min_seconds = sorted[1], max_seconds = sorted[n], mean_seconds = total / n,
  }
  io.write(string.format("%s: %d bytes, median %.3f ms (%d samples)\n", case.name, #case.text, median * 1000, n))
end
assert(fs.write(output, json.encode(report, { pretty = true }) .. "\n"))
io.write("results: ", output, "\n")
