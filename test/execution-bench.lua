-- Reuse owned Step 07 fixtures to verify execution-only scaling without
-- recreating 300,000 files. No old executable writes into these fixtures.
global none
global <const> require, assert, ipairs, table, tostring, string, io, os, pcall, print, collectgarbage
local fs, rt, json, cli = require 'fs', require 'rt', require 'json', require 'cli'
local proc, sched, hash, time, sys = require 'proc', require 'sched', require 'hash', require 'time', require 'sys'
local scan, policy = require '_scan', require '_scan_policy'
local options, why = cli.parse(rt.args, {
  { '--fixtures', type = 'string', required = true },
  { '--out', type = 'string', required = true },
  { '--repeats', type = 'int', default = 7, min = 3, max = 30 },
}, 'kuu test/execution-bench.lua')
assert(options, tostring(why))
local repository = fs.absolute(fs.join(fs.dirname(rt.program), '..'))
local build = fs.join(repository, 'build')
local output = fs.absolute(options.out)
assert(not fs.exists(output), 'refusing an existing output')
local prior = assert(json.decode(assert(fs.read(options.fixtures))))
assert(prior.status == 'complete', 'fixture report must be complete')
local by_name = {}
for _, case in ipairs(prior.cases) do by_name[case.name] = case end
local wanted = { 'tiny', 'generated', 'unexcluded', 'ledger_10000' }
local selected = {}
for _, name in ipairs(wanted) do
  local case = assert(by_name[name], 'missing fixture: ' .. name)
  local root = assert(fs.canon(case.root)).path
  local relative = fs.relative(root, build)
  assert(relative:match('^scan%-bench%-[^/]+/[^/]+$'), 'not an owned benchmark root')
  local relout = fs.relative(output, root)
  assert(relout == '..' or relout:sub(1, 3) == '../' or relout:find(':', 1, true), 'output must be outside fixture')
  selected[#selected + 1] = { name = name, root = root, historical = case }
end
local machine = sys.info()
local report = { schema = 'kuu.execution-bench.v1', status = 'running', at = time.iso(),
  exe = rt.exe, sha256 = assert(hash.file('sha256', rt.exe)), source_sha256 = assert(hash.file('sha256', rt.program)),
  fixture_report = fs.absolute(options.fixtures), previous_executable_sha256 = prior.sha256,
  host = { windows = machine.windows, elevated = machine.elevated, cpus = machine.cpus },
  warm_repeats = options.repeats, cases = json.array {},
  limitations = json.array {
    'Owned existing fixtures retain history from earlier experiments; they are not fresh or OS-cold.',
    'Historical samples were collected on another day; ratios are descriptive, not paired trials.',
    'Commands run sequentially; process timings include startup/output capture/shutdown, but exclude preparation and report writes.',
    'Fixture validation scans and tree-state hashes are harness work outside measured commands.',
    'Only commands below are rerun; explicit checking and inventory remain proportional to source size.',
    'No runtime modification or filesystem index; ordinary run continues to append execution history.',
  } }
local began = sched.clock()
local function save()
  report.elapsed_seconds = sched.clock() - began
  assert(fs.write(output, json.encode(report, { pretty = true }) .. '\n'))
end
local function last_json(text)
  local last
  for line in text:gmatch('[^\r\n]+') do last = assert(json.decode(line)) end
  return assert(last)
end
local function summary(samples)
  local values = {}
  for i = 2, #samples do values[#values + 1] = samples[i].seconds end
  table.sort(values)
  local n = #values
  local median = n % 2 == 1 and values[(n + 1) // 2] or (values[n // 2] + values[n // 2 + 1]) / 2
  return { median = median, min = values[1], max = values[n], count = n }
end
local function run()
  for _, fixture in ipairs(selected) do
    local scope = assert(policy.load(fixture.root))
    local inventory = scan.collect(fixture.root, scope)
    assert(inventory.complete)
    if fixture.name == 'unexcluded' then assert(inventory.counts.files == 100066) end
    local tree = fs.join(fixture.root, '.kuu/ledger/tree.json')
    local old_tree_hash = fs.exists(tree) and assert(hash.file('sha256', tree)) or nil
    local case = { name = fixture.name, root = fixture.root, counts = inventory.counts,
      tree_sha256_before = old_tree_hash, commands = json.array {} }
    report.cases[#report.cases + 1] = case
    inventory = nil
    collectgarbage('collect') -- discard validation inventory outside timers
    local commands = {
      { name = 'noop', argv = { 'run', '--json', 'noop' } },
      { name = 'child', argv = { 'run', '--json', 'child' } },
      { name = 'nested', argv = { 'run', '--json', 'nested' } },
    }
    if fixture.name == 'ledger_10000' then commands = { commands[2] } end
    if fixture.name == 'unexcluded' then
      commands[#commands + 1] = { name = 'automatic_check', argv = { 'check', '--json' }, repeats = 3 }
      commands[#commands + 1] = { name = 'capabilities', argv = { 'capabilities', '--json' }, repeats = 3 }
    end
    for _, command in ipairs(commands) do
      local row = { name = command.name, argv = json.array(command.argv), samples = json.array {} }
      case.commands[#case.commands + 1] = row
      for _, older in ipairs(fixture.historical.commands) do
        if older.name == command.name then row.historical = older.warm end
      end
      for sample = 0, command.repeats or options.repeats do
        local argv = { rt.exe, cwd = fixture.root, timeout = '60s', maxout = '16M' }
        for _, arg in ipairs(command.argv) do argv[#argv + 1] = arg end
        local t0 = sched.clock()
        local result = assert(proc.run(argv))
        local elapsed = sched.clock() - t0
        assert(result.status == 'exit' and result.code == 0 and not result.truncated, json.encode(result))
        local envelope = last_json(result.out)
        assert(envelope.ok)
        if command.argv[1] == 'run' then
          assert(envelope.result.ledger.complete and envelope.result.ledger.records >= 2)
          assert(envelope.result.scans == nil and envelope.result.scope == nil)
          assert(envelope.result.timings.initial_scan == nil and envelope.result.timings.final_scan == nil)
        end
        row.samples[#row.samples + 1] = { label = sample == 0 and 'first' or 'warm', seconds = elapsed,
          stdout = result.out, stderr = result.err, timings = envelope.result.timings,
          ledger = envelope.result.ledger, process_elapsed = result.elapsed }
      end
      row.warm = summary(row.samples)
      io.write(fixture.name, '/', command.name, ': ', string.format('%.3f ms', row.warm.median * 1000), '\n')
      save()
    end
    case.tree_sha256_after = fs.exists(tree) and assert(hash.file('sha256', tree)) or nil
    assert(case.tree_sha256_after == old_tree_hash, 'legacy tree state changed')
    case.tree_untouched = true
    save()
  end
end
save()
local ok, failure = pcall(run)
report.status = ok and 'complete' or 'failed'
report.error = not ok and tostring(failure) or nil
report.final_sha256 = assert(hash.file('sha256', rt.exe))
assert(report.final_sha256 == report.sha256)
save()
if not ok then io.stderr:write(tostring(failure), '\n'); os.exit(1) end
print('Execution benchmark complete: ', output)
