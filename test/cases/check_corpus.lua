-- check_corpus.lua -- `kuu check` over generated Lua: project modules of
-- every shape the extraction knows, consumers that reach into them every
-- way a program does, and the exact findings each must produce.
--
-- The hand-written cases in check.lua hold one example of each shape.  A
-- consumer found `cfg.paths.build` and a constructor-built module before the
-- gate did, because no example combined the shapes.  This generates the
-- combinations from a fixed seed, so the gate sees them first, and every
-- expectation is computed from the rules the checker documents, never read
-- back from its output.
global none
global <const> require, ipairs, pairs, tostring, table

return function(T)
  local check, contains = T.check, T.contains
  local fs = require "fs"
  local json = require "json"

  -- A small deterministic generator: the same corpus on every run, and a
  -- different one when the seed below changes.
  local state = 20260913
  local function rand(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return state % n + 1
  end
  local function word(alphabet, length)
    local out = {}
    for i = 1, length do local k = rand(#alphabet) out[i] = alphabet:sub(k, k) end
    return table.concat(out)
  end
  -- Export names are spelled from one half of the alphabet and strangers
  -- from the other, so every stranger is far from every export and a
  -- misspelling -- an export plus one letter -- has exactly one nearest name.
  local function export_name() return word("abcdefghijklm", 6 + rand(4)) end
  local function stranger() return "zz" .. word("nopqrstuvwxy", 10) end
  local literals = { "1", '"s"', "true", "{}", "function() end", "{ inner = { deeper = 1 } }" }

  -- One project module, with the set of names its text bounds, or nil when
  -- the shape puts that set out of reach.
  local function module()
    local names = {}
    for i = 1, 2 + rand(4) do names[i] = export_name() end
    -- The declaration names setmetatable whether or not the shape uses it:
    -- a declared name is not a use, and the checker must not read it as one.
    local lines = { "global none", "global <const> setmetatable, require" }
    local shape = rand(8)
    local exports = {}
    for _, n in ipairs(names) do exports[n] = true end
    local built = rand(2) == 1 and names or {}
    if shape == 8 then
      -- borrowed: the table was not built here
      lines[#lines + 1] = 'local M = require "fs"'
      exports = nil
    elseif shape == 7 then
      -- a computed key in the constructor
      lines[#lines + 1] = 'local k = "a"'
      lines[#lines + 1] = "local M = { [k] = 1, " .. names[1] .. " = 2 }"
      exports = nil
    else
      local ctor = {}
      for _, n in ipairs(built) do ctor[#ctor + 1] = "  " .. n .. " = " .. literals[rand(#literals)] .. "," end
      if #ctor > 0 then
        lines[#lines + 1] = "local M = {"
        for _, c in ipairs(ctor) do lines[#lines + 1] = c end
        lines[#lines + 1] = "}"
      else
        lines[#lines + 1] = "local M = {}"
      end
    end
    if exports ~= nil then
      for i, n in ipairs(names) do
        if built[i] == nil then
          if rand(2) == 1 then lines[#lines + 1] = "function M." .. n .. "() end"
          else lines[#lines + 1] = "M." .. n .. " = " .. literals[rand(#literals)] end
        end
      end
      if shape == 6 then
        lines[#lines + 1] = "M[" .. '"' .. names[1] .. '"' .. "] = 3" -- a computed key: out of reach
        exports = nil
      elseif shape == 5 then
        lines[#lines + 1] = "setmetatable(M, { __index = function() return 1 end })"
        exports = nil
      elseif shape == 4 then
        -- a metatable on the module's own objects, never on the module:
        -- setmetatable is used, and the exports stay bounded
        lines[#lines + 1] = "local Thing = {}"
        lines[#lines + 1] = "Thing.__index = Thing"
        lines[#lines + 1] = "function M." .. names[1] .. "_new() return setmetatable({}, Thing) end"
        exports[names[1] .. "_new"] = true
      end
    end
    lines[#lines + 1] = "return M"
    return table.concat(lines, "\n") .. "\n", exports, names
  end

  -- One consumer of a module: correct reaches, deeper reaches that the
  -- checker must not judge, misspellings that it must, and strangers.
  local function consumer(modname, exports, names)
    local lines = { "global none", "global <const> require, print", "local a = require \"" .. modname .. "\"" }
    local expected = {}
    for _ = 1, 3 + rand(5) do
      local kind = rand(6)
      local n = names[rand(#names)]
      if kind == 1 then
        lines[#lines + 1] = "print(a." .. n .. ")"
      elseif kind == 2 then
        lines[#lines + 1] = "print(a." .. n .. ".paths.build, a." .. n .. ".x.y.z)"
      elseif kind == 3 then
        lines[#lines + 1] = "print(a." .. n .. "q)"
        if exports then expected[#expected + 1] = { line = #lines, name = n .. "q", suggestion = n } end
      elseif kind == 4 then
        local s = stranger()
        lines[#lines + 1] = "print(a." .. s .. ")"
        if exports then expected[#expected + 1] = { line = #lines, name = s } end
      elseif kind == 5 then
        lines[#lines + 1] = "print(require(\"" .. modname .. "\")." .. n .. "q)"
        if exports then expected[#expected + 1] = { line = #lines, name = n .. "q", suggestion = n } end
      else
        lines[#lines + 1] = "print(a." .. n .. "(), a." .. n .. " == 1)"
      end
    end
    return table.concat(lines, "\n") .. "\n", expected
  end

  local dir = fs.tempdir { prefix = "kuu-corpus-" }
  if not dir then
    check("a temporary project for the generated corpus", false, "fs.tempdir failed")
    return
  end
  local function put(rel, text)
    local path = dir .. "/" .. rel
    fs.mkdir(fs.dirname(path))
    fs.write(path, text)
  end
  put("tasks.lua", 'global none\nglobal <const> require\nlocal task = require "task"\ntask "x" { run = function() end }\n')

  local COUNT = 48
  local plan = {}
  local bounded, unbounded = 0, 0
  for i = 1, COUNT do
    local text, exports, names = module()
    put("tools/m" .. i .. ".lua", text)
    local use, expected = consumer("tools.m" .. i, exports, names)
    put("use" .. i .. ".lua", use)
    plan["use" .. i .. ".lua"] = { expected = expected, module = "tools.m" .. i, bounded = exports ~= nil }
    if exports then bounded = bounded + 1 else unbounded = unbounded + 1 end
  end
  -- The palette the same way: a kuu module's exports are known by running
  -- it, and a misspelt one is found with its nearest real spelling.
  local palette_names = { "absolute", "basename", "dirname", "relative", "tempfile", "tempdir", "exists", "remove" }
  local lines = { "global none", "global <const> require, print", 'local fs = require "fs"' }
  local expected = {}
  for _, n in ipairs(palette_names) do
    lines[#lines + 1] = "print(fs." .. n .. ", fs." .. n .. "q)"
    expected[#expected + 1] = { line = #lines, name = n .. "q", suggestion = n }
  end
  put("palette.lua", table.concat(lines, "\n") .. "\n")
  plan["palette.lua"] = { expected = expected, module = "fs", bounded = true }

  local r = T.kuu({ "check", "--json" }, { cwd = dir })
  local envelope = json.decode(r.out)
  check("the generated corpus checks to an envelope", envelope ~= nil and envelope.result ~= nil, T.describe(r))
  if envelope == nil or envelope.result == nil then fs.remove(dir, { recursive = true }) return end

  local reports = {}
  for _, file in ipairs(envelope.result.files) do reports[file.path:gsub("\\", "/")] = file end

  local wrong, judged, findings = {}, 0, 0
  local total_expected = 0
  for name, entry in pairs(plan) do
    local report = reports[name]
    local errors = report and report.errors or {}
    table.sort(errors, function(x, y) return x.line < y.line end)
    total_expected = total_expected + #entry.expected
    judged = judged + 1
    findings = findings + #errors
    local ok = report ~= nil and #errors == #entry.expected and #report.warnings == 0
    for k, want in ipairs(entry.expected) do
      local got = errors[k]
      if got == nil or got.kind ~= "name" or got.line ~= want.line or got.name ~= want.name
        or got.module ~= entry.module or got.suggestion ~= want.suggestion then ok = false end
    end
    if not ok then
      local shown = {}
      for _, e in ipairs(errors) do shown[#shown + 1] = e.line .. ":" .. tostring(e.kind) .. ":" .. tostring(e.name) .. ":" .. tostring(e.suggestion) end
      local wanted = {}
      for _, w in ipairs(entry.expected) do wanted[#wanted + 1] = w.line .. ":name:" .. w.name .. ":" .. tostring(w.suggestion) end
      wrong[#wrong + 1] = name .. " (bounded=" .. tostring(entry.bounded) .. ") expected [" .. table.concat(wanted, " ") .. "] got ["
        .. table.concat(shown, " ") .. "]" .. (report and #report.warnings > 0 and (" warnings " .. json.encode(report.warnings)) or "")
    end
  end
  check("every generated consumer reports exactly its planned findings",
    #wrong == 0, #wrong .. " of " .. judged .. " differ; first: " .. (wrong[1] or ""))
  check("the corpus covered both bounded and unbounded modules", bounded >= 10 and unbounded >= 10, bounded .. " bounded, " .. unbounded .. " unbounded")
  check("the corpus asked for findings and got that many", total_expected >= 40 and findings == total_expected, findings .. " found, " .. total_expected .. " planned")
  local modules_reported = 0
  for _, file in ipairs(envelope.result.files) do
    if file.path:find("^tools[/\\]m%d+%.lua$") then
      modules_reported = modules_reported + 1
      if #file.errors > 0 then wrong[#wrong + 1] = file.path end
    end
  end
  check("the generated modules themselves are clean", modules_reported == COUNT and #wrong == 0, modules_reported .. " modules; " .. (wrong[1] or ""))
  check("the envelope's total agrees with the files", envelope.result.errors == findings and contains(r.out, '"ok":' .. (findings == 0 and "true" or "false")), tostring(envelope.result.errors))

  fs.remove(dir, { recursive = true })
end
