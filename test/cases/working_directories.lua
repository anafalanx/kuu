-- Exercise the published wrapper, manifest and child without rewriting them.
global none
global <const> require, assert, ipairs

return function(T)
  local fs, json = require "fs", require "json"
  local check = T.check
  local base = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "working-directories-" })
  local project = base .. "/Project's space"
  local nested = project .. "/nested work/資料's folder"
  local unrelated = base .. "/Unrelated's place"
  assert(fs.mkdir(project .. "/tools")); assert(fs.mkdir(nested)); assert(fs.mkdir(unrelated))
  assert(fs.copy(fs.absolute(T.exe), project .. "/kuu.exe"))
  assert(fs.write(project .. "/.gitignore", "/.kuu/\n"))
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/working-directories.md")):gmatch("```lua\r?\n(.-)\r?\n```") do
    blocks[#blocks + 1] = source
  end
  check("cwd guide contains complete wrapper, manifest and child programs", #blocks == 3)
  if #blocks ~= 3 then return end
  for index, name in ipairs { "tools/from-here.lua", "manifest.lua", "tools/report.lua" } do
    assert(fs.write(project .. "/" .. name, blocks[index]))
  end
  local lint = T.kuu({ "check", "--json", "manifest.lua", "tools/from-here.lua", "tools/report.lua" }, { cwd = project })
  local report = json.decode(lint.out)
  check("all published working-directory blocks pass static checking", lint.code == 0 and report
    and report.result.errors == 0 and report.result.warnings == 0, T.describe(lint))

  local forwarded = { "plain", "two words", 'say "hello"', "", [[C:\trailing\]], [[space ending \]],
    "--help", "--", "--cwd", "not-a-cwd", "資料" }
  for index, cwd in ipairs { project, nested, unrelated } do
    local args = { project .. "/tools/from-here.lua" }
    for _, value in ipairs(forwarded) do args[#args + 1] = value end
    local result = T.kuu(args, { cwd = cwd })
    local record = json.decode(result.out)
    check("wrapper reaches the intended project from caller directory " .. index,
      result.status == "exit" and result.code == 0 and record ~= nil, T.describe(result))
    check("nested kuu preserves original caller cwd " .. index, record and fs.absolute(record.cwd) == cwd, result.out)
    check("child module root stays at its absolute script directory " .. index,
      record and fs.absolute(record.module_root) == project .. "/tools", result.out)
    check("every argument survives both nested process boundaries exactly " .. index,
      record and json.encode(json.array(record.argv)) == json.encode(json.array(forwarded)), result.out)
    check("nested run writes its history at the intended project " .. index,
      fs.exists(project .. "/.kuu/ledger") == "directory" and fs.exists(unrelated .. "/.kuu") == false
        and fs.exists(nested .. "/.kuu") == false)
  end

  local empty = T.kuu({ project .. "/tools/from-here.lua" }, { cwd = unrelated })
  local empty_record = json.decode(empty.out)
  check("empty forwarded argv remains an empty array", empty.code == 0 and empty_record
    and #empty_record.argv == 0 and T.contains(empty.out, '"argv":[]'), T.describe(empty))

  local relative = T.kuu({ "../../tools/from-here.lua", "relative launch" }, { cwd = nested })
  local relative_record = json.decode(relative.out)
  check("a relative wrapper path still locates the project from the script directory",
    relative.code == 0 and relative_record and fs.absolute(relative_record.cwd) == nested
      and fs.absolute(relative_record.module_root) == project .. "/tools"
      and relative_record.argv[1] == "relative launch", T.describe(relative))

  local file = project .. "/ordinary-file"
  assert(fs.write(file, "not a directory"))
  local bad_cases = {
    { {}, "CLI usage", 2 },
    { { "--cwd", "relative path" }, "PROJECT cwd", 1 },
    { { "--cwd", "C:relative" }, "PROJECT cwd", 1 },
    { { "--cwd", "/root-relative" }, "PROJECT cwd", 1 },
    { { "--cwd", file }, "PROJECT cwd", 1 },
    { { "--cwd", project .. "/missing" }, "FS notfound", 1 },
  }
  for index, entry in ipairs(bad_cases) do
    local args = { "run", "report" }
    for _, value in ipairs(entry[1]) do args[#args + 1] = value end
    local result = T.kuu(args, { cwd = project })
    check("task refuses invalid caller cwd without launching its child " .. index,
      result.code == entry[3] and result.out == "" and T.contains(result.err, entry[2]), T.describe(result))
  end

  -- The ordinary leaf above verifies unchanged published blocks. Change only
  -- this fixture leaf afterward to exercise the documented wrapper exit path.
  assert(fs.write(project .. "/tools/report.lua", "global none\nglobal <const> os\nos.exit(23)\n"))
  local exited = T.kuu({ project .. "/tools/from-here.lua", "--help" }, { cwd = unrelated })
  check("nonzero child exit passes through task, nested kuu and wrapper unchanged",
    exited.status == "exit" and exited.code == 23, T.describe(exited))

  -- A failed nested launch is distinct from a successful zero-code exit.
  assert(fs.rename(project .. "/kuu.exe", project .. "/kuu-renamed.exe"))
  local missing = T.kuu({ project .. "/tools/from-here.lua" }, { cwd = unrelated })
  check("wrapper reports a missing project runtime as a launch failure",
    missing.code == 1 and T.contains(missing.err, "from-here: PROC notfound"), T.describe(missing))
end
