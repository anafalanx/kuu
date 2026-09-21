-- An agent with an existing project and only a replacement executable must
-- discover and read the migration guide before evaluating project code.
global none
global <const> require, assert, ipairs

return function(T)
  local fs, proc, json = require "fs", require "proc", require "json"
  local work = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "upgrade-discovery-" })
  local exe = work .. "/kuu.exe"
  assert(fs.copy(fs.absolute(T.exe), exe))
  if require("env").get("KUU_TEST_ASAN") == "1" then
    for _, name in ipairs { "libclang_rt.asan_dynamic-x86_64.dll", "libc++.dll" } do
      assert(fs.copy(fs.absolute(T.root .. "/.tools/msys2/clang64/bin/" .. name), work .. "/" .. name))
    end
  end
  local function run(args)
    local spec = { exe, cwd = work, timeout = "30s" }
    for _, arg in ipairs(args) do spec[#spec + 1] = arg end
    return assert(proc.run(spec))
  end
  local page_name = "upgrading-from-0.11"
  local command = "kuu docs " .. page_name
  assert(fs.write(work .. "/manifest.lua", 'global none\nreturn {}\n'))
  for _, entry in ipairs {
    { name = "entry help", args = { "--help" } },
    { name = "docs help", args = { "docs", "--help" } },
    { name = "manual list", args = { "docs" } },
    { name = "capabilities", args = { "capabilities" } },
  } do
    local r = run(entry.args)
    T.check(entry.name .. " directs existing 0.11 agents to the migration guide",
      r.code == 0 and T.contains(r.out, command), T.describe(r))
  end
  local r = run {}
  T.check("no-argument help also exposes migration", r.code == 2 and T.contains(r.err, command), T.describe(r))

  r = run { "capabilities", "--json" }
  local capabilities = r.code == 0 and json.decode(r.out) or nil
  local next_page
  for _, hint in ipairs(capabilities and capabilities.result.next or {}) do
    next_page = next_page or hint:match("kuu docs (upgrading%-from%-0%.11)")
  end
  T.check("machine discovery supplies the same migration command", next_page == page_name, T.describe(r))
  r = run { "docs", "--json" }
  local listing = r.code == 0 and json.decode(r.out) or nil
  local listed = false
  for _, page in ipairs(listing and listing.result.pages or {}) do
    if page.name == next_page then listed = true end
  end
  T.check("the advertised migration page belongs to the embedded manual", listed, T.describe(r))

  -- A stale project must not prevent reading the replacement's own manual.
  -- The side effect is a sentinel to detect evaluation, not just a load error.
  local manifest = 'global none\nglobal <const> require, error\n' ..
    'require("fs").write("manifest-ran", "unexpected")\nerror("stale manifest")\n'
  assert(fs.write(work .. "/manifest.lua", manifest))
  assert(fs.write(work .. "/kuu.config.json", "invalid old configuration\n"))
  assert(fs.mkdir(work .. "/docs"))
  assert(fs.write(work .. "/docs/" .. page_name .. ".md", "STALE PROJECT COPY\n"))
  local expected = assert(fs.read(fs.absolute(T.root .. "/docs/" .. page_name .. ".md"))):gsub("\r\n", "\n")
  r = run { "docs", next_page or page_name }
  T.check("the advertised command reads the replacement's guide despite stale local docs and invalid project config",
    r.code == 0 and r.out:gsub("\r\n", "\n") == expected, T.describe(r))
  r = run { "docs", page_name, "--json" }
  local guide = r.code == 0 and json.decode(r.out) or nil
  T.check("migration is also available as structured text with retrievable sections",
    guide and guide.result.name == page_name and guide.result.text:gsub("\r\n", "\n") == expected
      and #guide.result.sections > 0, T.describe(r))
  if guide and guide.result.sections[1] then
    local section = guide.result.sections[1]
    r = run { "docs", page_name, section.anchor }
    T.check("the migration checklist section can be retrieved on its own",
      r.code == 0 and T.starts(r.out, "## " .. section.heading .. "\n"), T.describe(r))
  end
  T.check("reading migration leaves the manifest unevaluated and project state untouched",
    fs.exists(work .. "/manifest-ran") == false and fs.exists(work .. "/.kuu") == false
      and fs.read(work .. "/manifest.lua") == manifest)
end
