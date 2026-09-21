-- Observation benchmark, separate from the passing regression suite.
-- Run with --help. All generated projects are new directories below build/.
global none
global <const> require, assert, error, ipairs, pairs, tostring, tonumber, type,
               table, string, math, io, os, pcall

local fs, rt, cli, json = require 'fs', require 'rt', require 'cli', require 'json'
local proc, sched, hash, time = require 'proc', require 'sched', require 'hash', require 'time'
local sys = require 'sys'
local options, why = cli.parse(rt.args, {
  { '--exe', type = 'string', help = 'executable under test; defaults to this executable' },
  { '--files', type = 'int', default = 1000, min = 0, max = 100000, help = 'files per populated tree' },
  { '--repeats', type = 'int', default = 3, min = 1, max = 10, help = 'warm repetitions after the first observation' },
  { '--ledger-records', type = 'int', default = 10000, min = 100, max = 100000, help = 'larger valid ledger size; smaller case is one tenth' },
  { '--out', type = 'string', help = 'new report path; refuses an existing path' },
  { '--no-profile', type = 'flag', help = 'only uninstrumented measurements' },
  { '--timeout', type = 'duration', default = '3m', min = 1, help = 'deadline per measured subprocess' },
}, 'kuu test/scan-bench.lua')
if not options then io.stderr:write(tostring(why), '\n'); os.exit(2) end
if options.help then
  io.write(cli.usage({
    { '--exe', type = 'string' }, { '--files', type = 'int', default = 1000 },
    { '--repeats', type = 'int', default = 3 }, { '--ledger-records', type = 'int', default = 10000 },
    { '--out', type = 'string' }, { '--no-profile', type = 'flag' }, { '--timeout', type = 'duration', default = '3m' },
  }, 'kuu test/scan-bench.lua'))
  os.exit(0)
end

options.ledger_records = options['ledger-records']
options.no_profile = options['no-profile']
local repository = fs.absolute(fs.join(fs.dirname(rt.program), '..'))
local build = fs.join(repository, 'build')
assert(fs.mkdir(build))
local scratch = assert(fs.tempdir { dir = build, prefix = 'scan-bench-' })
local output = fs.absolute(options.out or fs.join(scratch, 'report.json'))
assert(not fs.exists(output), 'report already exists: ' .. output)
assert(fs.mkdir(fs.dirname(output)))
local exe = fs.absolute(options.exe or rt.exe)
local profile_script = fs.join(repository, 'test/scan-profile.lua')
assert(fs.exists(exe) == 'file', 'missing executable: ' .. exe)
if not options.no_profile then assert(fs.exists(profile_script) == 'file', 'missing scan-profile.lua') end
local initial_hash = assert(hash.file('sha256', exe))
local began = sched.clock()
local machine = sys.info()
local report = {
  schema = 'kuu.scan-bench.v1', status = 'running', at = time.iso(), scratch = scratch,
  exe = exe, sha256 = initial_hash, driver = rt.exe, driver_version = rt.version,
  driver_sha256 = assert(hash.file('sha256', rt.exe)),
  machine = { windows = machine.windows, cpus = machine.cpus, arch = machine.arch,
    memory_total = machine.memory.total, memory_available = machine.memory.available, elevated = machine.elevated },
  options = { files = options.files, warm_repeats = options.repeats, ledger_records = options.ledger_records,
    timeout_seconds = options.timeout, profiles = not options.no_profile },
  cases = json.array {}, mutations = json.array {},
  limitations = json.array {
    'First observation is not OS-cold: creating fixtures warms metadata and file caches.',
    'Uninstrumented subprocess wall time includes launch, output capture and shutdown; profiles are separate later runs.',
    'Commands run in the listed order; first_observation is per command, not a fresh ledger baseline. Ledger state and OS caches persist.',
    'Profiles wrap embedded modules and perturb timing; nested child processes are not instrumented.',
    'Synthetic file counts and times do not reproduce the unknown file count in FlowNet.',
    'Generated projects and raw outputs are retained below scratch; no cleanup or runtime modification is performed.',
  },
}
local function save()
  report.elapsed_seconds = sched.clock() - began
  assert(fs.write(output, json.encode(report, { pretty = true }) .. '\n'))
end
save()

local function write(path, bytes)
  local f <close> = assert(io.open(path, 'wb'))
  assert(f:write(bytes))
end
local function must_run(argv, cwd)
  local command = { exe, timeout = options.timeout, maxout = '128M', cwd = cwd }
  for _, arg in ipairs(argv) do command[#command + 1] = arg end
  local started = sched.clock()
  local result, e = proc.run(command)
  local elapsed = sched.clock() - started
  assert(result, e)
  assert(result.status == 'exit' and result.code == 0 and not result.truncated,
    'subprocess failed: ' .. table.concat(argv, ' ') .. '\n' .. tostring(result.status)
      .. '/' .. tostring(result.code) .. '\n' .. result.err .. '\n' .. result.out:sub(1, 2000))
  return result, elapsed
end
local version = must_run { '--version' }
report.version_output = version.out
report.signature = sys.signature(exe)

local manifest = [[global none
global <const> require
local task, rt = require 'task', require 'rt'
task.tool 'self' { exe = rt.exe, output = 'lines' }
task 'noop' { run = function() end }
task 'child' { run = function() return task.exec { tool = 'self', '-e', "print('baseline-child')", timeout = '30s' } end }
task 'nested' { run = function() return task.exec { tool = 'self', 'run', '--json', 'child', timeout = '2m' } end }
task 'nested-checkout' { run = function() return task.exec { tool = 'self', 'run', '--json', 'child', cwd = '.cache/reconstruction/work/relocated checkout', timeout = '2m' } end }
task.default 'child'
]]
local child_manifest = [[global none
global <const> require
local task, rt = require 'task', require 'rt'
task.tool 'self' { exe = rt.exe, output = 'lines' }
task 'child' { run = function() return task.exec { tool = 'self', '-e', "print('nested-checkout-child')", timeout = '30s' } end }
]]
local function make_project(name, prefixes, count)
  local started = sched.clock()
  local root = fs.join(scratch, name)
  assert(fs.mkdir(root))
  write(fs.join(root, 'manifest.lua'), manifest)
  write(fs.join(root, '.gitignore'), '/.kuu/\n/.cache/\n/.local/\n/.tools/\n**/.venv/\n')
  assert(fs.mkdir(fs.join(root, 'observed')))
  for i = 1, 64 do write(fs.join(root, 'observed', string.format('change_%03d.txt', i)), 'initial\n') end
  if count > 0 then
    for i = 1, count do
      local bucket = math.floor((i - 1) / 100)
      local dir = fs.join(root, prefixes[bucket % #prefixes + 1], string.format('shard_%05d', bucket))
      if (i - 1) % 100 == 0 then assert(fs.mkdir(dir)) end
      local is_lua = (i - 1) % 100 == 0
      write(fs.join(dir, is_lua and 'module.lua' or string.format('file_%06d.txt', i)),
        is_lua and 'global none\nreturn { value = 1 }\n' or 'generated fixture\n')
      if i % 10000 == 0 then io.stderr:write(name, ': created ', i, '/', count, ' files\n') end
    end
  end
  local tree = assert(fs.dirs(root))
  assert(#tree.errors == 0 and #tree.links == 0)
  local files, lua_files = 0, 0
  for _, dir in ipairs(tree.paths) do
    local listing = assert(fs.list(dir))
    assert(#listing.errors == 0)
    for _, entry in ipairs(listing.entries) do
      if entry.kind == 'file' then
        files = files + 1
        if entry.name:sub(-4) == '.lua' then lua_files = lua_files + 1 end
      end
    end
  end
  local case = { name = name, root = root, payload_files = count, files_before_runs = files,
    lua_files_before_runs = lua_files, directories_before_runs = #tree.paths,
    creation_seconds = sched.clock() - started, commands = json.array {}, prefixes = json.array(prefixes) }
  report.cases[#report.cases + 1] = case
  save()
  return case
end
local function summaries(samples)
  local values = {}
  for _, s in ipairs(samples) do if s.label ~= 'first_observation' then values[#values + 1] = s.wall_seconds end end
  table.sort(values)
  local middle = math.floor((#values + 1) / 2)
  local median = #values % 2 == 1 and values[middle] or (values[middle] + values[middle + 1]) / 2
  return { count = #values, min_seconds = values[1], median_seconds = median, max_seconds = values[#values] }
end
local function sample(case, label, argv, index)
  local baseline_present = fs.exists(fs.join(case.root, '.kuu/ledger/tree.json')) == 'file'
  local r, elapsed = must_run(argv, case.root)
  local result = { label = index == 0 and 'first_observation' or 'warm_' .. index,
    baseline_present_before = baseline_present,
    wall_seconds = elapsed, process_elapsed = r.elapsed, stdout_bytes = #r.out, stderr_bytes = #r.err }
  local last = nil
  for line in r.out:gmatch('[^\r\n]+') do last = line end
  local decoded = last and json.decode(last)
  if type(decoded) == 'table' then
    assert(decoded.ok ~= false, 'command reported failure despite zero exit')
    local body = decoded.result
    if body then
      result.tasks, result.timings = body.tasks, body.timings
      result.scope, result.scans = body.scope, body.scans
      if body.project then
        result.inventory = { files = body.project.files, complete = body.project.modules_complete,
          scope = body.project.scope, scan = body.project.scan }
      end
    end
  end
  if index == 0 then
    local raw = fs.join(scratch, case.name .. '-' .. label)
    write(raw .. '.stdout.txt', r.out)
    write(raw .. '.stderr.txt', r.err)
    result.stdout_path, result.stderr_path = raw .. '.stdout.txt', raw .. '.stderr.txt'
  end
  return result
end
local function profile(case, label, argv)
  if options.no_profile then return nil end
  local path = fs.join(scratch, case.name .. '-' .. label .. '.profile.json')
  local args = { profile_script, '--out', path }
  for _, arg in ipairs(argv) do args[#args + 1] = arg end
  must_run(args, case.root)
  local data = assert(json.decode(assert(fs.read(path))))
  assert(data.exit_code == 0, 'profile did not preserve successful exit')
  return { path = path, data = data }
end
local function measure(case, label, argv)
  io.stderr:write('measure ', case.name, '/', label, '\n')
  local command = { name = label, argv = json.array(argv), samples = json.array {} }
  case.commands[#case.commands + 1] = command
  for i = 0, options.repeats do
    command.samples[#command.samples + 1] = sample(case, label, argv, i)
    save()
  end
  command.warm = summaries(command.samples)
  save()
end
local function measure_project(case, nested_checkout)
  measure(case, 'startup', { '--version' })
  measure(case, 'dry_run', { 'run', '--dry-run', 'child' })
  measure(case, 'noop', { 'run', '--json', 'noop' })
  measure(case, 'child', { 'run', '--json', 'child' })
  measure(case, 'nested', { 'run', '--json', 'nested' })
  if nested_checkout then measure(case, 'nested_checkout', { 'run', '--json', 'nested-checkout' }) end
  measure(case, 'explicit_check', { 'check', '--json', 'manifest.lua' })
  measure(case, 'automatic_check', { 'check', '--json' })
  measure(case, 'capabilities', { 'capabilities', '--json' })
  -- Instrumentation follows all raw observations, so wrappers do not warm a measured first run.
  for _, command in ipairs(case.commands) do
    if command.argv[1] ~= '--version' then
      command.profile = profile(case, command.name, command.argv)
      save()
    end
  end
end
local function seed_ledger(case, count)
  local dir = fs.join(case.root, '.kuu/ledger')
  assert(fs.mkdir(dir))
  local path = fs.join(dir, time.iso():sub(1, 10) .. '.ndjson')
  local previous = nil
  local file <close> = assert(io.open(path, 'wb'))
  for i = 1, count do
    local line = json.encode { v = 1, kuu = '0.11', root = case.root, kind = 'child', name = 'seed',
      at = time.now(), seconds = 0, status = 'exit', code = 0, sequence = i,
      padding = string.rep('x', 768), prev = previous and hash.sum('sha256', previous) or nil }
    assert(file:write(line, '\n'))
    previous = line
  end
  assert(file:flush())
  case.seeded_records, case.seeded_bytes = count, assert(fs.stat(path)).size
end

local function run()
  local tiny = make_project('tiny', {}, 0)
  measure_project(tiny)
  for _, shape in ipairs {
    { 'generated', { '.cache/reconstruction/work/checkout/generated', '.local/editor/user-data',
      'automation/.venv/Lib', 'nested/.CaChE', 'nested/python/.VeNv/Lib' } },
    { 'unexcluded', { 'src/maintained' } },
    { 'pruned_control', { '.tools/payload' } },
  } do
    local case = make_project(shape[1], shape[2], options.files)
    if shape[1] == 'generated' then
      local nested = fs.join(case.root, '.cache/reconstruction/work/relocated checkout')
      assert(fs.mkdir(nested))
      write(fs.join(nested, 'manifest.lua'), child_manifest)
      write(fs.join(nested, '.gitignore'), '/.kuu/\n')
      case.nested_checkout = nested
      case.files_before_runs = case.files_before_runs + 2
      case.lua_files_before_runs = case.lua_files_before_runs + 1
      case.directories_before_runs = #assert(fs.dirs(case.root)).paths
    end
    measure_project(case, shape[1] == 'generated')
  end
  for _, count in ipairs { math.floor(options.ledger_records / 10), options.ledger_records } do
    local case = make_project('ledger_' .. count, {}, 0)
    seed_ledger(case, count)
    measure(case, 'child', { 'run', '--json', 'child' })
    measure(case, 'capabilities', { 'capabilities', '--json' })
    for _, command in ipairs(case.commands) do command.profile = profile(case, command.name, command.argv) end
    save()
  end
  -- Mutate the same small visible tree at three sizes. Historical runtimes
  -- hash up to their named-path limit; execution-only history should not
  -- observe these files at all. Keep both behaviors visible in the profile.
  for _, count in ipairs { 0, 1, 64 } do
    local function change(tag)
      for i = 1, count do
        write(fs.join(tiny.root, 'observed', string.format('change_%03d.txt', i)),
          tag .. string.rep('x', 65536 + count))
      end
    end
    change('raw-' .. count)
    local row = { changed_files = count, payload_padding_bytes = count > 0 and 65536 + count or 0,
      raw = sample(tiny, 'changed_' .. count, { 'run', '--json', 'child' }, 0) }
    change('instrumented-' .. count)
    row.profile = profile(tiny, 'changed_' .. count, { 'run', '--json', 'child' })
    report.mutations[#report.mutations + 1] = row
    save()
  end
end
local ok, failure = pcall(run)
report.finished_at = time.iso()
report.final_sha256 = assert(hash.file('sha256', exe))
if report.final_sha256 ~= initial_hash then ok, failure = false, 'executable changed during benchmark' end
report.status = ok and 'complete' or 'failed'
if not ok then report.error = tostring(failure) end
save()
io.write(output, '\n')
if not ok then io.stderr:write(tostring(failure), '\n'); os.exit(1) end
