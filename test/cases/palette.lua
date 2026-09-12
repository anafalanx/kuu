-- palette.lua -- tools/palette.lua is an authored description of the
-- palette's interface, for a checker that reads types.  An authored manifest
-- drifts unless something checks it, and a description that disagrees with
-- the runtime is worse than none, because it is trusted: machteld's cli
-- raised one error code while its manual documented another, and a handler
-- written from the documentation did not catch.
--
-- So this checks the description three ways: against the runtime, whose
-- export tables say what exists; against the manual, whose pages state the
-- closed sets; and against itself, since every type it names must resolve.
global none
global <const> require, ipairs, pairs, pcall, tostring, type, table

return function(T)
  local check = T.check
  local fs = require "fs"

  local root = fs.canon(T.root).path

  -- It ships in the payload now that check reads it, so require finds it.
  -- The leading underscore keeps it outside the public contract.
  local ok, description = pcall(require, "_palette")

  check("the description loads", ok and type(description) == "table",
    tostring(description))
  if not ok or type(description) ~= "table" then return end

  -- Against the runtime: every module named must exist, and every name
  -- attributed to it must be one of its exports.
  local missing_modules, missing_names = {}, {}
  for name, entries in pairs(description.modules) do
    local ok, module = pcall(require, name)
    if not ok or type(module) ~= "table" then
      missing_modules[#missing_modules + 1] = name
    else
      for member in pairs(entries) do
        if module[member] == nil then
          missing_names[#missing_names + 1] = name .. "." .. member
        end
      end
    end
  end
  table.sort(missing_modules); table.sort(missing_names)
  check("every described module exists", #missing_modules == 0,
    table.concat(missing_modules, ", "))
  check("every described name is an export of its module", #missing_names == 0,
    table.concat(missing_names, ", "))

  -- The public list is a promise -- `capabilities` reports it as the contract
  -- -- so it is held to the manual's own module table in both directions. A
  -- module that gains a page and is not listed goes unreported; one listed
  -- without a page is reported as public when nothing documents it.
  local table_names, table_order = {}, {}
  for line in fs.read(root .. "/docs/index.md"):gmatch("[^\n]+") do
    local name = line:match("^| %[?`([%a][%w_]*)`")
    if name then
      table_names[name] = true
      table_order[#table_order + 1] = name
    end
  end
  local unlisted, unpaged = {}, {}
  local listed = {}
  for _, name in ipairs(description.public) do listed[name] = true end
  for _, name in ipairs(table_order) do
    if not listed[name] then unlisted[#unlisted + 1] = name end
  end
  for _, name in ipairs(description.public) do
    if not table_names[name] then unpaged[#unpaged + 1] = name end
  end
  table.sort(unlisted); table.sort(unpaged)
  check("every module the manual's table introduces is public", #unlisted == 0,
    table.concat(unlisted, ", "))
  check("and every public module is in that table", #unpaged == 0,
    table.concat(unpaged, ", "))
  check("in the same order, which is the one capabilities reports",
    table.concat(description.public, " ") == table.concat(table_order, " "),
    table.concat(description.public, " ") .. " vs " .. table.concat(table_order, " "))

  -- Against itself: every type a field names must resolve to a scalar, an
  -- enum, a record, or a plain Lua type.  This is what catches a typo in the
  -- description, which would otherwise become a checker that silently knows
  -- nothing about that field.
  local known = { any = true, table = true, string = true, boolean = true,
    integer = true, number = true, handle = true, ["function"] = true }
  for name in pairs(description.scalars) do known[name] = true end
  for name in pairs(description.enums) do known[name] = true end
  for name in pairs(description.records) do known[name] = true end

  local unresolved = {}
  local function resolve(spec, where)
    if type(spec) == "table" then
      for field, t in pairs(spec) do resolve(t, where .. "." .. tostring(field)) end
      return
    end
    if type(spec) ~= "string" then return end
    for one in spec:gsub("%?$", ""):gmatch("[^|]+") do
      if not known[one] then unresolved[#unresolved + 1] = where .. ": " .. one end
    end
  end
  for rname, record in pairs(description.records) do resolve(record, "records." .. rname) end
  for mname, entries in pairs(description.modules) do
    for member, entry in pairs(entries) do
      local at = mname .. "." .. member
      if entry.options then resolve(entry.options, at .. " options") end
      if entry.result then resolve(entry.result, at .. " result") end
      if entry.field then resolve(entry.field, at .. " field") end
    end
  end
  table.sort(unresolved)
  check("every type named in the description resolves", #unresolved == 0,
    table.concat(unresolved, "; "))

  -- Against the manual: every error code must appear on a page, in one of the
  -- two spellings the manual uses -- a bare `notfound` in a table headed
  -- "FS code", or a combined `ARCHIVE notfound` elsewhere.  Scraping these
  -- was measured unreliable, which is why they are authored; this is the
  -- check that authoring them did not introduce a typo.
  local pages = {}
  for _, entry in ipairs(fs.list(root .. "/docs").entries) do
    if entry.name:match("%.md$") then
      pages[entry.name:sub(1, -4)] = fs.read(root .. "/docs/" .. entry.name) or ""
    end
  end
  local everything = {}
  for _, text in pairs(pages) do everything[#everything + 1] = text end
  everything = table.concat(everything, "\n")

  -- Most domains are named after their page. ENTRY is the exception: its
  -- codes are stated on the front page, since they are kuu's own failures
  -- before a program runs rather than a module's.
  local PAGE = { ENTRY = "index" }

  local undocumented = {}
  for domain, codes in pairs(description.errors) do
    local page = pages[PAGE[domain] or domain:lower()]
    for _, code in ipairs(codes) do
      local bare = page and page:find("`" .. code .. "`", 1, true)
      local joined = everything:find("`" .. domain .. " " .. code .. "`", 1, true)
      if not bare and not joined then
        undocumented[#undocumented + 1] = domain .. " " .. code
      end
    end
  end
  table.sort(undocumented)
  check("every described error code appears in the manual", #undocumented == 0,
    table.concat(undocumented, ", "))

  -- And the other direction, for the domains that state a complete set in the
  -- prose the manual actually uses: a code the manual has and the description
  -- lacks is the drift that matters most, because the checker would then call
  -- a real code a typo.
  local absent = {}
  for domain, codes in pairs(description.errors) do
    local page = pages[PAGE[domain] or domain:lower()]
    if page then
      local have = {}
      for _, code in ipairs(codes) do have[code] = true end
      for code in page:gmatch("`" .. domain .. " ([a-z]+)`") do
        if not have[code] then absent[#absent + 1] = domain .. " " .. code end
      end
    end
  end
  table.sort(absent)
  check("no manual error code is missing from the description", #absent == 0,
    table.concat(absent, ", "))

  -- The enums carry the closed sets the audit found are compared against
  -- string literals.  Each value must appear on some page, or the checker
  -- would reject a spelling the manual teaches.
  local strays = {}
  for name, values in pairs(description.enums) do
    for _, value in ipairs(values) do
      if not everything:find('"' .. value .. '"', 1, true)
        and not everything:find("`" .. value .. "`", 1, true) then
        strays[#strays + 1] = name .. "." .. value
      end
    end
  end
  table.sort(strays)
  check("every enum value appears in the manual", #strays == 0,
    table.concat(strays, ", "))
end
