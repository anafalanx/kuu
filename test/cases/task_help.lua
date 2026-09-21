-- Task help is preflight; only an explicit rest argument forwards child help.
global none
global <const> require, assert, ipairs, table, tostring

return function(T)
  local fs, json, task, err = require "fs", require "json", require "task", require "err"
  local check = T.check
  local root = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "task-help-" })
  assert(fs.write(root .. "/.gitignore", "/.kuu/\n"))
  assert(fs.write(root .. "/child.lua", [[
local fs, json, rt = require "fs", require "json", require "rt"
assert(fs.write("child.json", json.encode(json.array(rt.args))))
io.write("child reached\n")
os.exit(17)
]]))
  assert(fs.write(root .. "/manifest.lua", [[
local task, fs, rt = require "task", require "fs", require "rt"
local function mark(name) assert(fs.write("bodies.log", name .. "\n", { append = true })) end
task "prepare" { run = function() mark("prepare") end }
task "needy" { args = { { "target", required = true } }, run = function() mark("needy") end }
task "plain" { desc = "plain task description", deps = { "prepare" }, run = function() mark("plain") end }
task "empty" { desc = "explicit empty schema", args = {}, deps = { "prepare" }, run = function() mark("empty") end }
task "schema" { desc = "required task option", args = { { "--name", required = true } },
  deps = { "prepare" }, run = function() mark("schema") end }
task "uses-needy" { desc = "required dependency arguments", deps = { "needy" }, run = function() mark("uses-needy") end }
task "uses-needy-schema" { desc = "required selected and dependency arguments", deps = { "needy" },
  args = { { "own", required = true } }, run = function() mark("uses-needy-schema") end }
task "no-desc" { args = {}, run = function() mark("no-desc") end }
task "empty-desc" { desc = "", run = function() mark("empty-desc") end }
task "forward" { desc = "forward exact arguments", deps = { "prepare" },
  args = { { "argv", rest = true } }, run = function(opts)
    mark("forward")
    local command = { rt.exe, "child.lua" }
    for _, value in ipairs(opts.argv) do command[#command + 1] = value end
    return task.exec(command)
  end }
]]))

  local function untouched()
    return fs.exists(root .. "/bodies.log") == false and fs.exists(root .. "/child.json") == false
      and fs.exists(root .. "/.kuu") == false
  end
  local help_cases = {
    { "plain", "plain task description" },
    { "empty", "explicit empty schema" },
    { "schema", "required task option" },
    { "uses-needy", "required dependency arguments" },
    { "uses-needy-schema", "required selected and dependency arguments" },
    { "forward", "forward exact arguments" },
    { "no-desc", "" },
    { "empty-desc", "" },
  }
  for _, entry in ipairs(help_cases) do
    local name, desc = entry[1], entry[2]
    local result = T.kuu({ "run", name, "--help" }, { cwd = root })
    local prefix = (desc ~= "" and (desc .. "\n\n") or "") .. "usage: kuu run " .. name
    check("task help includes its nonempty description before usage: " .. name,
      result.code == 0 and T.starts(result.out, prefix) and result.err == "", T.describe(result))
    check("task help starts no bodies or children and creates no history: " .. name, untouched())
  end
  for _, name in ipairs { "plain", "schema", "uses-needy-schema", "forward" } do
    local result = T.kuu({ "run", "--json", name, "--help" }, { cwd = root })
    check("JSON task help stays text and performs no execution or history writes: " .. name,
      result.code == 0 and T.contains(result.out, "\n\nusage: kuu run " .. name)
        and result.err == "" and untouched(), T.describe(result))
  end
  local result = T.kuu({ "run", "uses-needy" }, { cwd = root })
  check("a real run still validates required dependency arguments before execution",
    result.code == 2 and T.contains(result.err, "missing required argument <target>") and untouched(), T.describe(result))

  -- A separator alone is empty, but any actual positional value stays an error.
  for _, name in ipairs { "plain", "empty" } do
    for index, extras in ipairs { { "extra" }, { "--", "extra" }, { "--", "--help" }, { "--", "--" }, { "" } } do
      local arguments = { "run", name }
      for _, value in ipairs(extras) do arguments[#arguments + 1] = value end
      result = T.kuu(arguments, { cwd = root })
      check("argument-free task rejects actual extra arguments before execution: " .. name .. " " .. index,
        result.code == 2 and T.contains(result.err, "CLI usage") and untouched(), T.describe(result))
    end
  end
  for _, name in ipairs { "plain", "empty" } do
    result = T.kuu({ "run", name, "--" }, { cwd = root })
    check("a lone separator runs an argument-free task: " .. name,
      result.code == 0 and T.contains(assert(fs.read(root .. "/bodies.log")), name .. "\n"), T.describe(result))
  end

  local function history_bytes()
    local parts = {}
    for _, entry in ipairs(assert(fs.list(root .. "/.kuu/ledger")).entries) do
      if entry.kind == "file" then
        parts[#parts + 1] = entry.name .. "\0" .. assert(fs.read(root .. "/.kuu/ledger/" .. entry.name))
      end
    end
    table.sort(parts)
    return table.concat(parts, "\0")
  end
  local before, bodies = history_bytes(), assert(fs.read(root .. "/bodies.log"))
  for _, arguments in ipairs { { "run", "uses-needy-schema", "--help" }, { "run", "--json", "forward", "--help" } } do
    result = T.kuu(arguments, { cwd = root })
    check("help leaves existing history and prior execution markers unchanged: " .. arguments[2],
      result.code == 0 and history_bytes() == before and fs.read(root .. "/bodies.log") == bodies
        and fs.exists(root .. "/child.json") == false, T.describe(result))
  end

  -- The first separator belongs to the task parser. Later separators and all
  -- quoting-sensitive values belong to the child, including its own --help.
  local forwarded = { "--help", "", "two words", 'say "hi"', [[C:\trailing\]], "--", "tail" }
  local expected = json.encode(json.array(forwarded))
  for _, mode in ipairs { "console", "json" } do
    local arguments = { "run" }
    if mode == "json" then arguments[#arguments + 1] = "--json" end
    arguments[#arguments + 1] = "forward"
    arguments[#arguments + 1] = "--"
    for _, value in ipairs(forwarded) do arguments[#arguments + 1] = value end
    result = T.kuu(arguments, { cwd = root })
    check("rest schema forwards every child argument exactly: " .. mode,
      fs.read(root .. "/child.json") == expected, T.describe(result))
    check("forwarded child help executes and preserves nonzero child exit: " .. mode,
      result.code == 17 and T.contains(mode == "json" and result.err or result.out, "child reached"), T.describe(result))
    if mode == "json" then
      local envelope, finished
      for line in result.out:gmatch("[^\n]+") do
        local row = assert(json.decode(line))
        if row.ok ~= nil then envelope = row end
        if row.event == "child" and row.state == "finished" then finished = row end
      end
      check("JSON child and final report retain the forwarded child's failure",
        envelope and envelope.ok == false and envelope.error.exit == 17
          and finished and finished.status == "exit" and finished.code == 17, result.out)
    end
  end

  local entry = { name = "custom", desc = "custom program description" }
  local options, why = task.arguments(entry, { "--help" }, "project custom")
  check("task.arguments preserves classified help and a caller's program name",
    options == nil and err.is(why, "CLI", "usage") and why.help == true
      and T.starts(why.message, "custom program description\n\nusage: project custom"), tostring(why))
  local arguments = { "--" }
  options = task.arguments(entry, arguments)
  check("accepting an empty separator leaves the caller's argument array untouched",
    options ~= nil and #arguments == 1 and arguments[1] == "--")
end
