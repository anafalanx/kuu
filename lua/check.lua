-- check.lua -- what kuu can tell about Lua files before running them.
--
--   local check = require "check"
--   local r = check.file("manifest.lua", root)     -- { path, errors, warnings, requires }
--   local t = check.tree(dir, root)             -- every *.lua below dir: { root, reports }
--
-- For each file: it is parsed by Lua 5.5's own compiler, text only, so a
-- syntax error, and under a global declaration an undeclared global, is found
-- with its line; a file with no global declaration at all gets a warning,
-- because there the classic typo is silent; and every literal `require` is
-- listed and resolved against kuu's modules and the root, so a name that
-- resolves to nothing is a warning before any run gets there. The
-- palette's exported names are checked for direct local require bindings.
--
-- It also reads _palette, an authored description of the palette's
-- interface, and checks three things against it that are silent today: a
-- code its domain does not have, so `err.is` never matches and the branch it
-- guards never runs; an option name a call does not take; and a closed set
-- compared with a literal outside it, `rt.version` included. Error domains
-- themselves are open, because `err.new` is public and projects define their
-- own. Project code is never executed, and no call is type-checked beyond
-- these.
global none
global <const> require, ipairs, pairs, tostring, tonumber, type, table, load,
               package, pcall, error, string, next

local fs = require "fs"
local rt = require "rt"

-- Absent only if the payload were built without it; the checks below then
-- simply do not run, rather than the checker failing to load.
local ok_palette, palette = pcall(require, "_palette")
if not ok_palette or type(palette) ~= "table" then palette = nil end

local check = {}

check.PRUNE = { ".git", ".tools", "build", "node_modules" }

-- Match state.c's module_relative: dots separate nonempty components; a
-- component may contain Unicode or spaces, but no path separator or drive
-- colon. Filesystem validation then rejects names Windows cannot represent.
local function module_path(root, name)
  if name == "" or name:find("[/\\:%z]") or name:sub(1, 1) == "."
    or name:sub(-1) == "." or name:find("..", 1, true) then return nil end
  local rel = root .. "/" .. name:gsub("%.", "/")
  for _, tail in ipairs { ".lua", "/init.lua" } do
    local path = rel .. tail
    local ok, kind = pcall(fs.exists, path)
    if ok and kind == "file" then return path end
  end
  return nil
end

local function resolves(root, name)
  return package.preload[name] ~= nil or rt.source(name) ~= nil or module_path(root, name) ~= nil
end

-- One lexer serves require discovery and name checking. Strings and comments
-- cannot turn into executable names, and each token retains its source line.
-- Bytes rather than patterns, throughout. The obvious spelling of this loop
-- asks `text:sub(pos, pos)` for a one-character string and then matches
-- patterns against it, which allocates a string and runs the pattern engine
-- for every byte of every file; it also tried the long-bracket pattern at
-- every position rather than only where a bracket is, and counted line
-- breaks with a substring and two gsubs per token. Comparing byte values
-- does the same work about one and a half times faster. The two token
-- streams were compared over every Lua file in the repository and were
-- identical, text, kind, line and decoded value for every token; that was a
-- check run while replacing the lexer, not one the suite keeps, since the
-- pattern version no longer exists to compare against.
local NAME_START, DIGIT, SPACE = {}, {}, {}
for b = 65, 90 do NAME_START[b] = true end
for b = 97, 122 do NAME_START[b] = true end
NAME_START[95] = true
for b = 48, 57 do DIGIT[b] = true end
for _, b in ipairs { 32, 9, 10, 11, 12, 13 } do SPACE[b] = true end

local function tokens_of(text)
  local tokens, pos, line, n = {}, 1, 1, #text
  local byte = string.byte
  local doubles = { ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true,
    ["<<"] = true, [">>"] = true, ["//"] = true, [".."] = true, ["::"] = true }
  while pos <= n do
    local start, at_line = pos, line
    local b = byte(text, pos)
    local comment = b == 45 and byte(text, pos + 1) == 45
    local at = comment and pos + 2 or pos
    local kind, value, after, equals
    -- The long-bracket pattern is tried only where a bracket actually is.
    if byte(text, at) == 91 then equals = text:match("^%[(=*)%[", at) end
    if equals ~= nil then
      local closing = "]" .. equals .. "]"
      local stop = text:find(closing, at + #equals + 2, true)
      after = stop and stop + #closing or n + 1
      kind = comment and "comment" or "string"
    elseif comment then
      after, kind = text:find("[\r\n]", pos + 2) or n + 1, "comment"
    elseif SPACE[b] then
      after, kind = pos + 1, "space"
    elseif b == 34 or b == 39 then
      after = pos + 1
      while after <= n do
        local ch = byte(text, after)
        if ch == 92 then after = after + 2
        elseif ch == b then after = after + 1 break
        else after = after + 1 end
      end
      kind = "string"
    elseif NAME_START[b] then
      local _, stop = text:find("^[%a_][%w_]*", pos)
      after, kind = stop + 1, "name"
    elseif DIGIT[b] or (b == 46 and DIGIT[byte(text, pos + 1) or 0]) then
      after, kind = pos + 1, "number"
      while after <= n do
        local ch, previous = byte(text, after), byte(text, after - 1)
        local body = DIGIT[ch] or NAME_START[ch] or ch == 46
        local exponent = (ch == 43 or ch == 45)
          and (previous == 101 or previous == 69 or previous == 112 or previous == 80)
        if body or exponent then after = after + 1 else break end
      end
    else
      local two, three = text:sub(pos, pos + 1), text:sub(pos, pos + 2)
      after, kind = pos + (three == "..." and 3 or doubles[two] and 2 or 1), "symbol"
    end
    if kind ~= "comment" and kind ~= "space" then
      local spelling = text:sub(start, after - 1)
      if kind == "string" then
        -- Exactly one isolated literal, never a source expression. Lua
        -- decodes its own escapes and long brackets in an empty environment.
        local literal = load("return " .. spelling, "=(check literal)", "t", {})
        if literal then value = literal() end
      end
      tokens[#tokens + 1] = { text = spelling, kind = kind, value = value, line = at_line }
    end
    -- CRLF counts once, and so does a lone CR.
    local breaks = 0
    for i = pos, after - 1 do
      local ch = byte(text, i)
      if ch == 10 then breaks = breaks + 1
      elseif ch == 13 and byte(text, i + 1) ~= 10 then breaks = breaks + 1 end
    end
    line, pos = line + breaks, after
  end
  tokens[#tokens + 1] = { text = "<eof>", kind = "eof", line = line }
  return tokens
end

-- Load only public, top-level modules shipped by kuu, never project modules
-- or embedded command/helper chunks such as cmd.run.
local function exports_of(name)
  if not name:match("^[%a][%w_]*$") or (package.preload[name] == nil and rt.source(name) == nil) then return nil end
  local ok, module = pcall(require, name)
  if not ok or type(module) ~= "table" then return nil end
  local exports = {}
  for key in pairs(module) do if type(key) == "string" then exports[key] = true end end
  -- Public optional fields are absent from their tables when nil.
  if name == "task" then exports.relay = true end
  if name == "rt" then exports.program = true end
  return exports
end

-- The exports of a project module, read from its text rather than by running
-- it -- project code is never executed, and that rule is not relaxed here.
--
-- It over-approximates on purpose. A field wrongly included costs only a
-- missed diagnostic; one wrongly excluded is a false positive on correct
-- code, which is far more expensive. So anything that puts the set out of
-- reach yields nothing at all and the module goes unchecked: a computed key,
-- a metatable, a return that is not a plain local, or a local that was not
-- freshly built as a table.
local function project_exports(path)
  local text, e = fs.read(path, { encoding = "utf-8" })
  if text == nil then return nil, e end
  if load(text, "@check", "t") == nil then return nil end
  local tokens = tokens_of(text)

  -- The module's table is whatever the file's last statement returns, and it
  -- has to be a plain name.
  local returned
  for i = #tokens - 1, 2, -1 do
    if tokens[i].text == "return" and tokens[i + 1].kind == "name"
      and tokens[i + 2] ~= nil and tokens[i + 2].kind == "eof" then
      returned = tokens[i + 1].text
      break
    end
  end
  if returned == nil then return nil end

  -- and it has to have been built here, not received from somewhere else.
  local opened, declarations = nil, 0
  for i = 1, #tokens - 3 do
    if tokens[i].text == "local" and tokens[i + 1].text == returned then
      declarations = declarations + 1
      if tokens[i + 2].text == "=" and tokens[i + 3].text == "{" then opened = i + 3 end
    end
  end
  -- Resolving arbitrary same-spelled locals requires full lexical binding
  -- inference. Leave a redeclared table unchecked rather than use the wrong
  -- constructor's export set.
  if opened == nil or declarations ~= 1 then return nil end

  local exports = {}

  -- The constructor's own named keys are exports: `local M = { LIMIT = 10 }`
  -- declares one as surely as `M.LIMIT = 10` does, and a module that opens
  -- with a table of constants is an ordinary shape. Only the top level of
  -- that constructor counts, and a computed key in it puts the set out of
  -- reach exactly as an assigned one does.
  local depth = 0
  for i = opened, #tokens do
    local t = tokens[i]
    if t.text == "{" then depth = depth + 1
    elseif t.text == "}" then
      depth = depth - 1
      if depth == 0 then break end
    elseif depth == 1 and t.text == "[" then return nil
    elseif depth == 1 and t.kind == "name" and tokens[i + 1] ~= nil and tokens[i + 1].text == "=" then
      local before = tokens[i - 1]
      if before ~= nil and (before.text == "{" or before.text == "," or before.text == ";") then
        exports[t.text] = true
      end
    end
  end

  -- Any escaped reference can add exports, including ordinary alias.field
  -- assignments. A metatable or rawset elsewhere is neither necessary nor
  -- sufficient. Keep ordinary M.name accesses and the final return bounded;
  -- passing, aliasing, replacing or using the table as self is uncertain.
  local escapes = false
  for i = 1, #tokens do
    local t = tokens[i]
    if t.text == returned then
      local before, next1, next2, next3 = tokens[i - 1], tokens[i + 1], tokens[i + 2], tokens[i + 3]
      if next1 ~= nil and next1.text == "[" then return nil end
      if next1 ~= nil and next1.text == "." and next2 ~= nil and next2.kind == "name" then
        if (next3 ~= nil and next3.text == "=") or (before ~= nil and before.text == "function") then
          exports[next2.text] = true
        end
      elseif not (before ~= nil and before.text == "local" and next1 ~= nil and next1.text == "=")
        and not (before ~= nil and before.text == "return" and next1 ~= nil and next1.kind == "eof") then
        escapes = true
      end
    end
  end
  if escapes then return nil end
  if next(exports) == nil then return nil end
  return exports
end

-- check.exports(path) -> the set of names a project module exports, or nil
-- when its text does not bound them.  Public because `capabilities` reports
-- the same set, and reporting a different one than the checker uses would be
-- worse than reporting none.
check.exports = project_exports

-- The nearest real spelling of a misspelt name, shared with the runner's
-- own "no task" message.
local nearest = require "_nearest"

local function set_of(list)
  local set = {}
  for _, one in ipairs(list) do set[one] = true end
  return set
end

-- What the description buys. Each of these is a mistake the runtime does not
-- refuse and cannot: the call is well formed and the program runs, but the
-- branch it guards can never be taken, or the option it names is not the one
-- that was meant.
local function contract_findings(contracts, report)
  for _, entry in ipairs(contracts) do
    local b = entry.binding
    local module = palette.modules[entry.module]
    local spec = module and module[entry.member]

    if b and not b.changed then
      -- err.is(e, DOMAIN, code). A code the domain does not have makes
      -- the call answer false for every error forever, so the handler is
      -- dead code and nothing at run time ever says so.
      if entry.kind == "call" and entry.module == "err" and entry.member == "is" then
        local domain = entry.args[2] and entry.args[2].literal
        local code = entry.args[3] and entry.args[3].literal
        -- Only the codes within a domain kuu owns are closed. The set of
        -- domains is not: `err.new` is public and projects define their own
        -- -- PROJECT, SMOKE, PREREQS, TEST in the corpus at hand -- so an
        -- unfamiliar domain is a program's own and says nothing. Guessing
        -- otherwise is not merely imprecise: TEST is one edit from kuu's
        -- TEXT, so a suggestion would have been confidently wrong.
        if type(domain) == "string" then
          local codes = palette.errors[domain]
          if codes and type(code) == "string" and not set_of(codes)[code] then
            local suggestion = nearest(code, set_of(codes))
            local message = "\"" .. code .. "\" is not a code in " .. domain .. ", so this never matches"
            if suggestion then message = message .. "; did you mean \"" .. suggestion .. "\"?" end
            report.errors[#report.errors + 1] = { kind = "code", line = entry.line,
              message = message, module = domain, name = code, suggestion = suggestion }
          end
        end

      -- An option name the call does not take. The runtime raises on this,
      -- but only if the line is reached; here it is found without running.
      elseif entry.kind == "call" and spec and spec.options_at and spec.options then
        local given = entry.args[spec.options_at]
        if given and given.keys then
          for _, key in ipairs(given.keys) do
            if spec.options[key.name] == nil then
              local suggestion = nearest(key.name, spec.options)
              local message = key.name .. " is not an option of " .. entry.alias .. "." .. entry.member
              if suggestion then message = message .. "; did you mean " .. suggestion .. "?" end
              report.errors[#report.errors + 1] = { kind = "option", line = key.line,
                message = message, module = entry.module, name = key.name, suggestion = suggestion }
            end
          end
        end

      -- Public versions have two numeric components from 0.11 onward.
      -- A guard requiring the former three-component spelling cannot match
      -- one, regardless of the minimum it is trying to require.
      elseif entry.kind == "pattern" and spec and spec.field == "Version" and type(entry.pattern) == "string" then
        -- Only three numeric components matched to the end are judged;
        -- two-component guards and partial or rewriting patterns are left
        -- alone. Numeric comparisons remain the recommended version gate.
        local shape = entry.pattern:gsub("[()]", "")
        if shape == "^%d+%.%d+%.%d+$" or shape == "%d+%.%d+%.%d+$" then
          report.errors[#report.errors + 1] = { kind = "value", line = entry.line,
            message = entry.alias .. "." .. entry.member .. " is N.N (two natural numbers), and this pattern requires three components"
              .. " to its end, so it cannot match releases from 0.11 onward; use "
              .. entry.alias .. ".version_at_least(...) (kuu docs upgrading-0.11)",
            module = entry.module, name = entry.pattern }
        end

      -- A closed set compared with a literal outside it, and the version,
      -- which is never compared by text at all.
      elseif entry.kind == "compare" and spec and spec.field then
        if spec.field == "Version" then
          report.errors[#report.errors + 1] = { kind = "value", line = entry.line,
            message = entry.alias .. "." .. entry.member .. " is N.N (two natural numbers) and is never compared by text; use "
              .. entry.alias .. ".version_at_least(...)",
            module = entry.module, name = entry.literal }
        elseif entry.operator == "==" or entry.operator == "~=" then
          local values = palette.enums[spec.field]
          if values and not set_of(values)[entry.literal] then
            local suggestion = nearest(entry.literal, set_of(values))
            local message = "\"" .. tostring(entry.literal) .. "\" is not one of " .. entry.alias .. "."
              .. entry.member .. "'s values, so this never matches"
            if suggestion then message = message .. "; did you mean \"" .. suggestion .. "\"?" end
            report.errors[#report.errors + 1] = { kind = "value", line = entry.line,
              message = message, module = entry.module, name = entry.literal, suggestion = suggestion }
          end
        end
      end
    end
  end
end

-- The literal a constructor node spells: a string, a number, a boolean, or a
-- table of those and of tables; nil where any part is not a literal, since
-- a computed key or a value the text does not show puts the whole out of
-- reach, exactly as it does for a module's exports.
local function literal_of(node)
  if node.literal ~= nil then return node.literal end
  if node.keys == nil or node.computed then return nil end
  local out = {}
  for _, key in ipairs(node.keys) do
    local value = literal_of(key.value)
    if value == nil then return nil end
    out[key.name] = value
  end
  for i, item in ipairs(node.items) do
    local value = literal_of(item)
    if value == nil then return nil end
    out[i] = value
  end
  return out
end

-- The tools a file declares, read as literals, and the calls it makes
-- through the door checked against the declarations -- its own when the
-- file is the manifest, the manifest's otherwise. A declaration with a part
-- the text does not show is reported and its calls are not judged. A call
-- with `tool = "x"` names a declaration, and its literal arguments that look
-- like options must be ones the declaration names: the same kind of finding
-- as an option a palette call does not take. A call with no `tool` at all
-- is a warning: the door still runs it, but nothing describes it.
local TOOL_ATTRIBUTES = { exe = true, args = true, output = true, emits = true, timeout = true, reach = true }

-- Literal does not mean well formed. Only describe declarations whose
-- fields have the shapes the wire format promises; malformed literals get
-- a finding instead of reaching json.array with a string or mixed table.
local function tool_shape(decl)
  local function strings(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for k, v in pairs(value) do
      if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or type(v) ~= "string" then return false end
      count = count + 1
    end
    for i = 1, count do if value[i] == nil then return false end end
    return true
  end
  if type(decl.exe) ~= "string" or decl.exe == "" then return "exe must be a non-empty string" end
  if decl.args ~= nil then
    if type(decl.args) ~= "table" then return "args must be a table of argument name = type" end
    local kinds = { flag = true, string = true, path = true, int = true, number = true, duration = true, size = true }
    for name, kind in pairs(decl.args) do
      if type(name) ~= "string" or not kinds[kind] then return "args must map string names to supported argument types" end
    end
  end
  if decl.emits ~= nil and not strings(decl.emits) then return "emits must be an array of strings" end
  if decl.reach ~= nil then
    if type(decl.reach) ~= "table" then return "reach must be a table of read, write and net lists" end
    for name, list in pairs(decl.reach) do
      if name ~= "read" and name ~= "write" and name ~= "net" then return "reach only accepts read, write and net" end
      if not strings(list) then return "reach." .. name .. " must be an array of strings" end
    end
  end
  local outputs = { none = true, json = true, ndjson = true, lines = true }
  if decl.output ~= nil and not outputs[decl.output] then return "output must be none, json, ndjson or lines" end
  if decl.timeout ~= nil and require("cli").duration(decl.timeout) == nil then return "timeout must be a duration" end
end

local function tool_findings(contracts, declared, context, report)
  -- A file's own declarations serve its own calls, wherever it is; the
  -- manifest's serve every file under the root. Only the manifest is told
  -- when a declaration is out of reach, and only the manifest's are reported,
  -- since that is the file the door reads.
  local known = {}
  report.tools = {}
  for _, t in ipairs(declared) do
    -- An attribute the declaration cannot hold, found here rather than when
    -- the declaration runs, in whichever file it stands: `task.tool "x"
    -- { ... }` is two calls, so the description's option check never sees
    -- its table.  The direct spelling `task.tool("x", { ... })` reaches
    -- that check, which says the same thing once.
    if t.node.keys and not t.direct then
      for _, key in ipairs(t.node.keys) do
        if TOOL_ATTRIBUTES[key.name] == nil then
          local suggestion = nearest(key.name, TOOL_ATTRIBUTES)
          local message = key.name .. " is not an option of task.tool"
          if suggestion then message = message .. "; did you mean " .. suggestion .. "?" end
          report.errors[#report.errors + 1] = { kind = "option", line = key.line, message = message,
            module = "task", name = key.name, suggestion = suggestion }
        end
      end
    end
    local decl = literal_of(t.node)
    local invalid = decl ~= nil and tool_shape(decl) or nil
    if known[t.name] ~= nil then
      -- Declared more than once -- one arm of an `if` each, say -- the text
      -- cannot tell which one runs, so neither is held to.
      if context.is_manifest then
        report.warnings[#report.warnings + 1] = { kind = "tool", line = t.line,
          message = "tool '" .. t.name .. "' is declared more than once, so its arguments are not checked" }
        for i = #report.tools, 1, -1 do
          if report.tools[i].name == t.name then table.remove(report.tools, i) end
        end
      end
      known[t.name] = false
    elseif decl == nil then
      if context.is_manifest then
        report.warnings[#report.warnings + 1] = { kind = "tool", line = t.line,
          message = "tool '" .. t.name .. "' has a part that is not a literal, so its arguments are not checked" }
      end
      known[t.name] = false
    elseif invalid then
      known[t.name] = false
      report.errors[#report.errors + 1] = { kind = "value", line = t.line,
        module = "task.tool", name = t.name, message = "tool '" .. t.name .. "': " .. invalid }
    else
      known[t.name] = decl
      if context.is_manifest then
        report.tools[#report.tools + 1] = { name = t.name, line = t.line, exe = decl.exe, args = decl.args,
          output = decl.output or "none", emits = decl.emits or {}, timeout = decl.timeout, reach = decl.reach or {} }
      end
    end
  end
  if not context.is_manifest then
    for name, decl in pairs(context.tools) do
      if known[name] == nil then known[name] = decl end
    end
  end
  -- What reads as an option name in a tool's argv: `-x`, `--long`, or a
  -- Windows switch `/x`; not `-` or `--` alone, not a negative number, not a
  -- path that happens to start with a slash.  `--name=value` is judged by
  -- its name.
  local function option_name(text)
    local head = text:match("^([^=]+)=") or text
    if head == "-" or head == "--" then return nil end
    if head:sub(1, 1) == "-" then return not head:match("^%-%-?%d") and head or nil end
    if head:sub(1, 1) == "/" then return not head:find("[/\\.:]", 2) and head or nil end
    return nil
  end
  for _, entry in ipairs(contracts) do
    local b = entry.binding
    if b and not b.changed and entry.kind == "call" and entry.module == "task"
      and (entry.member == "exec" or entry.member == "command") then
      local given = entry.args[1]
      local tool, named = nil, false
      if given and given.keys then
        for _, key in ipairs(given.keys) do
          if key.name == "tool" then
            named = true
            if type(key.value.literal) == "string" then tool = { name = key.value.literal, line = key.line } end
          end
        end
      end
      if not context.readable then
        -- the manifest could not be read: nothing is known, so nothing is judged
      elseif given == nil or given.keys == nil then
        -- a table the checker cannot see into is not judged
      elseif not named then
        -- Only task.exec runs anything, and only where there is a manifest to
        -- declare it in: a program with no project around it has nowhere to
        -- put the declaration.
        if context.has_manifest and entry.member == "exec" then
          report.warnings[#report.warnings + 1] = { kind = "tool", line = entry.line,
            message = entry.alias .. ".exec runs a program without a tool declaration; declare it in the manifest so its arguments are checked and capabilities lists it" }
        end
      elseif tool == nil then
        -- tool = <not a literal>: not judged
      elseif known[tool.name] == nil then
        local names = {}
        for name in pairs(known) do names[#names + 1] = name end
        local suggestion = nearest(tool.name, set_of(names))
        local message = context.has_manifest and ("tool '" .. tool.name .. "' is not declared in the manifest")
          or ("tool '" .. tool.name .. "' is not declared: this file declares none, and there is no manifest.lua here or above")
        if suggestion then message = message .. "; did you mean '" .. suggestion .. "'?" end
        report.errors[#report.errors + 1] = { kind = "name", line = tool.line, message = message,
          module = "manifest", name = tool.name, suggestion = suggestion }
      elseif known[tool.name] and type(known[tool.name].args) == "table" then
        local args = known[tool.name].args
        local expects_value, options = false, true
        for _, item in ipairs(given.items) do
          local text = item.literal
          if not options then
            -- Everything following the end-of-options delimiter is positional.
          elseif type(text) ~= "string" then
            expects_value = false
          elseif expects_value then
            expects_value = false -- the value of the option before it
          elseif text == "--" then
            options = false
          elseif args[text] ~= nil then
            expects_value = args[text] ~= "flag" -- a declared name, `sign` say, that takes a value
          else
            local name = option_name(text)
            if name ~= nil and args[name] == nil then
              local suggestion = nearest(name, args)
              local message = "'" .. name .. "' is not an argument of tool '" .. tool.name .. "'"
              if suggestion then message = message .. "; did you mean '" .. suggestion .. "'?" end
              report.errors[#report.errors + 1] = { kind = "option", line = entry.line, message = message,
                module = tool.name, name = name, suggestion = suggestion }
            elseif name ~= nil then
              expects_value = args[name] ~= "flag" and not text:find("=", 1, true)
            end
          end
        end
      end
    end
  end
end

-- Follow expression/block structure to distinguish bindings, not to infer
-- types. Defer diagnostics until the whole file is scanned: reassignment
-- makes a binding uncertain even in a closure declared before the write.
local function inspect(tokens, report, root, context)
  local pos, declares = 1, false
  local native_require = { native = true }
  local scopes, calls, accesses, contracts, tools = { { require = native_require } }, {}, {}, {}, {}
  local expression, block, function_body
  local function token() return tokens[pos] end
  local function is(s) return token().text == s end
  local function take()
    local t = token()
    pos = pos + 1
    return t
  end
  local function consume(s)
    if is(s) then take() return true end
    return false
  end
  local function expect(s)
    if not consume(s) then error("check parser at line " .. token().line .. " expected " .. s .. ", got " .. token().text) end
  end
  local function lookup(name)
    for i = #scopes, 1, -1 do if scopes[i][name] ~= nil then return scopes[i][name] end end
  end
  local function bind(name, initial) scopes[#scopes][name] = { call = initial and initial.call } end
  local function push() scopes[#scopes + 1] = {} end
  local function pop() scopes[#scopes] = nil end
  local function attributes()
    if consume("<") then take() expect(">") end
  end
  local function expressions()
    local values = { expression(0) }
    while consume(",") do values[#values + 1] = expression(0) end
    return values
  end
  local function field(base)
    local name = take()
    -- Only the first field after a module alias names one of its exports.
    -- In `cfg.paths.build`, `paths` is asked of the module and `build` is
    -- asked of whatever `paths` turned out to be, which the module's export
    -- set cannot answer. A bare name is the only node carrying `name`, so
    -- that is the test; without it the second field was recorded against the
    -- module with no alias at all, and the report crashed building its
    -- message.
    if base.binding and base.name then
      accesses[#accesses + 1] = { binding = base.binding, alias = base.name, name = name.text, line = name.line }
      -- Carry which module member this is, so that a call on it can be
      -- checked against the description, and so that comparing it with a
      -- literal can be. The binding travels too, because a reassigned one is
      -- uncertain and its findings are dropped at the end like the others.
      if base.binding.call then
        return { binding = base.binding, module = base.binding.call.name,
                 member = name.text, alias = base.name, line = name.line }
      end
    end
    -- `string.match` and its kin, the standard library reached by name:
    -- carried as a free name so a call through it can be read.
    if base.name == "string" and (base.binding == nil or base.binding.call == nil) then
      return { free = "string." .. name.text, line = name.line }
    end
    return {}
  end
  -- The body of a table constructor, after its `{`. The named keys are kept
  -- so that a constructor passed as a call's option table can be checked
  -- against the names that call takes, and the values and items with them,
  -- so that a declaration written as a constructor can be read as the
  -- literal it is. A computed key says nothing, is parsed past, and marks
  -- the constructor as not literal.
  local function constructor()
    local result, keys, items, computed = {}, {}, {}, false
    while not is("}") do
      if consume("[") then
        -- `["--out"] = "path"` is a literal key spelled the only way a name
        -- with a dash can be; anything else in brackets is computed.
        if token().kind == "string" and tokens[pos + 1].text == "]" then
          local key = take()
          take()
          expect("=")
          local value = expression(0)
          keys[#keys + 1] = { name = key.value, line = key.line, value = value }
        else expression(0) expect("]") expect("=") expression(0) computed = true end
      elseif token().kind == "name" and tokens[pos + 1].text == "=" then
        local key = take()
        take()
        local value = expression(0)
        keys[#keys + 1] = { name = key.text, line = key.line, value = value }
      else items[#items + 1] = expression(0) end
      if not consume(",") and not consume(";") then break end
    end
    result.keys, result.items, result.computed = keys, items, computed
    expect("}")
    return result
  end
  local function arguments()
    if consume("(") then
      local args = {}
      if not is(")") then args = expressions() end
      expect(")")
      return args
    end
    -- A string or a constructor as the sole argument is the argument itself:
    -- in `f "x" { ... }` the constructor is a second call on f's result,
    -- never a call on the string, so neither takes suffixes here.
    if consume("{") then return { constructor() } end
    return { { literal = take().value } }
  end
  local function primary()
    local t, result = take(), {}
    if t.text == "(" then
      result = expression(0)
      expect(")")
    elseif t.text == "function" then function_body(false)
    elseif t.text == "{" then result = constructor()
    elseif t.kind == "string" then result.literal = t.value
    elseif t.kind == "number" then result.literal = tonumber(t.text)
    elseif t.text == "true" or t.text == "false" then result.literal = t.text == "true"
    elseif t.kind == "name" then result = { name = t.text, binding = lookup(t.text) }
    end
    while true do
      if consume(".") then result = field(result)
      elseif consume("[") then expression(0) expect("]") result = {}
      elseif consume(":") then
        -- `rt.version:match(...)`: a module field matched by pattern is
        -- recorded with the pattern, so an incompatible version guard is found
        -- before it runs.
        local method, target = token().text, result
        result = field(result)
        local args = arguments()
        if target.module and (method == "match" or method == "find") then
          contracts[#contracts + 1] = { kind = "pattern", binding = target.binding, module = target.module,
            member = target.member, alias = target.alias, line = target.line, method = method,
            pattern = args[1] and args[1].literal }
        end
        result = {}
      elseif is("(") or is("{") or token().kind == "string" then
        local args, original = arguments(), result
        result = {}
        -- The same guard spelled `string.match(rt.version, ...)`.
        if (original.free == "string.match" or original.free == "string.find") and args[1] and args[1].module then
          contracts[#contracts + 1] = { kind = "pattern", binding = args[1].binding, module = args[1].module,
            member = args[1].member, alias = args[1].alias, line = args[1].line, method = original.free,
            pattern = args[2] and args[2].literal }
        end
        if original.binding == native_require and #args == 1 and type(args[1].literal) == "string" then
          local call = { name = args[1].literal, line = t.line }
          calls[#calls + 1] = call
          result.call = call
          -- Indexed where it is required, `require("rt").version` is the same
          -- access as through a local binding, and it is the shape a real
          -- project turned out to use for two branches none of these checks
          -- saw. A binding of its own stands in for the local one: it is in no
          -- scope, so nothing can shadow or reassign it, and everything
          -- downstream -- names, codes, options, closed sets -- is unchanged.
          result.binding = { call = call }
          result.name = "require(\"" .. call.name .. "\")"
        elseif original.module then
          contracts[#contracts + 1] = { kind = "call", binding = original.binding,
            module = original.module, member = original.member,
            alias = original.alias, line = original.line, args = args }
          -- `task.tool "name" { ... }` declares a tool: the first call names
          -- it, the constructor that follows describes it, and both are read
          -- here as the literal they are. The direct spelling with two
          -- arguments is the same declaration.
          if original.module == "task" and original.member == "tool" and args[1] and type(args[1].literal) == "string" then
            if args[2] and args[2].keys then
              tools[#tools + 1] = { name = args[1].literal, line = original.line, node = args[2], direct = true, binding = original.binding }
            else
              result.declaring = { name = args[1].literal, line = original.line, binding = original.binding }
            end
          end
        elseif original.declaring and args[1] and args[1].keys then
          tools[#tools + 1] = { name = original.declaring.name, line = original.declaring.line, node = args[1], binding = original.declaring.binding }
        end
      else break end
    end
    return result
  end
  local priorities = { ["or"] = 1, ["and"] = 2, ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3,
    ["~="] = 3, ["=="] = 3, ["|"] = 4, ["~"] = 5, ["&"] = 6, ["<<"] = 7, [">>"] = 7,
    [".."] = 8, ["+"] = 9, ["-"] = 9, ["*"] = 10, ["/"] = 10, ["//"] = 10, ["%"] = 10, ["^"] = 12 }
  expression = function(minimum)
    local result
    if is("not") or is("#") or is("-") or is("~") then take() expression(11) result = {}
    else result = primary() end
    while true do
      local op = token().text
      local priority = priorities[op]
      if priority == nil or priority <= minimum then break end
      take()
      local right = expression((op == "^" or op == "..") and priority - 1 or priority)
      -- A closed set compared for equality with a literal outside it never
      -- matches. Version ordering by text is wrong as well: "0.11" < "0.9".
      if op == "==" or op == "~=" or op == "<" or op == ">" or op == "<=" or op == ">=" then
        local member, value = result, right
        if member.module == nil then member, value = right, result end
        if member.module and type(value.literal) == "string" then
          contracts[#contracts + 1] = { kind = "compare", binding = member.binding,
            module = member.module, member = member.member, alias = member.alias,
            line = member.line, literal = value.literal, operator = op }
        end
      end
      result = {}
    end
    return result
  end
  function_body = function(method)
    push()
    if method then bind("self") end
    expect("(")
    if not is(")") then
      repeat
        local name = take().text
        if name == "..." then
          if token().kind == "name" then bind(take().text) end
          break
        else bind(name) end
      until not consume(",")
    end
    expect(")")
    block() expect("end") pop()
  end
  local function assign(target)
    if target.binding then target.binding.changed = true end
  end
  local function declaration(local_names)
    if consume("function") then
      local name = take().text
      if local_names then bind(name) else assign({ binding = lookup(name) }) end
      function_body(false)
      return
    end
    attributes()
    local names = {}
    repeat names[#names + 1] = take().text attributes() until not consume(",")
    local values = consume("=") and expressions() or {}
    for i, name in ipairs(names) do
      if local_names then bind(name, values[i])
      elseif values[i] then assign({ binding = lookup(name) }) end
    end
  end
  block = function()
    while not is("<eof>") and not is("end") and not is("else") and not is("elseif") and not is("until") do
      if consume(";") then
      elseif consume("local") then declaration(true)
      elseif is("global") and (tokens[pos + 1].kind == "name" or tokens[pos + 1].text == "<" or tokens[pos + 1].text == "*") then
        take() declares = true
        if not consume("none") and not consume("*") then declaration(false) end
      elseif consume("function") then
        local name = take()
        local target = { name = name.text, binding = lookup(name.text) }
        while consume(".") do target = field(target) end
        local method = consume(":")
        if method then target = field(target) end
        assign(target) function_body(method)
      elseif consume("if") then
        expression(0) expect("then") push() block() pop()
        while consume("elseif") do expression(0) expect("then") push() block() pop() end
        if consume("else") then push() block() pop() end
        expect("end")
      elseif consume("while") then expression(0) expect("do") push() block() pop() expect("end")
      elseif consume("do") then push() block() pop() expect("end")
      elseif consume("repeat") then push() block() expect("until") expression(0) pop()
      elseif consume("for") then
        local names = { take().text }
        while consume(",") do names[#names + 1] = take().text end
        if not consume("=") then expect("in") end
        expressions() expect("do") push()
        for _, name in ipairs(names) do bind(name) end
        block() pop() expect("end")
      elseif consume("return") then
        if not is("end") and not is("else") and not is("elseif") and not is("until") and not is("<eof>") and not is(";") then expressions() end
      elseif consume("break") then
      elseif consume("goto") then take()
      elseif consume("::") then take() expect("::")
      else
        local targets = { primary() }
        while consume(",") do targets[#targets + 1] = primary() end
        if consume("=") then
          for _, target in ipairs(targets) do assign(target) end
          expressions()
        end
      end
    end
  end
  block()
  if not native_require.changed then
    local seen, modules = {}, {}
    for _, call in ipairs(calls) do
      if not seen[call.name] then
        seen[call.name] = true
        report.requires[#report.requires + 1] = call.name
        if not resolves(root, call.name) then
          report.warnings[#report.warnings + 1] = { kind = "require", line = call.line,
            message = "require \"" .. call.name .. "\" names no kuu module and no file under " .. root }
        end
      end
    end
    for _, access in ipairs(accesses) do
      local b = access.binding
      if b.call and not b.changed then
        local name = b.call.name
        if modules[name] == nil then
          local found = exports_of(name)
          if found == nil then
            local path = module_path(root, name)
            found = path ~= nil and project_exports(path) or nil
          end
          modules[name] = found or false
        end
        local exports = modules[name]
        if exports and not exports[access.name] then
          local suggestion = nearest(access.name, exports)
          local message = access.alias .. "." .. access.name .. " is not a name in " .. name
          if suggestion then message = message .. "; did you mean " .. access.alias .. "." .. suggestion .. "?" end
          report.errors[#report.errors + 1] = { kind = "name", line = access.line, message = message,
            module = name, name = access.name, suggestion = suggestion }
        end
      end
    end
    if palette then contract_findings(contracts, report) end
    local certain_tools = {}
    for _, t in ipairs(tools) do
      if t.binding and not t.binding.changed then certain_tools[#certain_tools + 1] = t end
    end
    tool_findings(contracts, certain_tools, context, report)
  end
  return declares
end

-- The project's manifest under `root`: manifest.lua, else tasks.lua, else nil.
local function manifest_path(root)
  for _, name in ipairs { "manifest.lua", "tasks.lua" } do
    if fs.exists(root .. "/" .. name) == "file" then return root .. "/" .. name end
  end
  return nil
end

-- The tools the manifest under `root` declares, read from its text once per
-- check operation: name -> the declaration as a literal, or false where the text does
-- not bound it. The manifest's own check reads its own declarations and
-- never comes here, so there is no circle.
local function project_tools(root, tool_cache)
  if tool_cache[root] == nil then
    local known, readable = {}, true
    local path = manifest_path(root)
    if path ~= nil then
      local report = check.file(path, root)
      -- A manifest that does not parse declares nothing anyone can read;
      -- the syntax error is the finding, and no call is judged against it.
      for _, e in ipairs(report.errors) do
        if e.kind == "read" or e.kind == "syntax" or e.kind == "analysis" then readable = false end
        if e.module == "task.tool" then known[e.name] = false end
      end
      for _, t in ipairs(report.tools or {}) do known[t.name] = t end
      for _, w in ipairs(report.warnings) do
        local name = w.kind == "tool" and (w.message:match("^tool '(.-)' has a part") or w.message:match("^tool '(.-)' is declared more")) or nil
        if name then known[name] = false end
      end
    end
    tool_cache[root] = { tools = known, has_manifest = path ~= nil, readable = readable }
  end
  return tool_cache[root]
end

-- check.tools(root) -> the tools the manifest declares, as check reads them:
-- { { name, line, exe, args, output, emits, timeout, reach }, ... } in
-- declaration order, only those the text bounds. The same reading the
-- checker uses, so that capabilities' executed reading can be held to it.
function check.tools(root)
  root = fs.absolute(root)
  local path = manifest_path(root)
  if path == nil then return {} end
  return check.file(path, root).tools or {}
end

-- check.file(path [, root]) -> { path, errors, warnings, requires, tools }
function check.file(path, root, tool_cache)
  -- The root is spelled as fs.absolute spells it, however the caller wrote
  -- it: paths under it are compared as text, and the manifest must be
  -- recognised as itself whichever way its root was given.
  root = fs.absolute(root or ".")
  local report = { path = fs.absolute(path), errors = {}, warnings = {}, requires = {}, tools = {} }
  local text, e = fs.read(path, { encoding = "utf-8" })
  if not text then
    report.errors[1] = { kind = "read", line = 0, message = tostring(e) }
    return report
  end
  if text:sub(1, 1) == "#" then text = text:gsub("^[^\n]*", "", 1) end
  local chunk, load_error = load(text, "@" .. path, "t")
  if chunk == nil then
    local line, message = tostring(load_error):match("^.-:(%d+):%s*(.*)$")
    report.errors[#report.errors + 1] = { kind = "syntax", line = tonumber(line) or 0, message = message or tostring(load_error) }
  end
  local tokens, declares = tokens_of(text), false
  local is_manifest = report.path:lower() == (manifest_path(root) or ""):lower()
  if chunk ~= nil then
    local context = is_manifest and { tools = {}, has_manifest = true, readable = true } or project_tools(root, tool_cache or {})
    context = { tools = context.tools, has_manifest = context.has_manifest, readable = context.readable, is_manifest = is_manifest }
    local inspected, result = pcall(inspect, tokens, report, root, context)
    if inspected then declares = result
    else
      report.errors[#report.errors + 1] = { kind = "analysis",
        line = tonumber(tostring(result):match("check parser at line (%d+)")) or 0,
        message = "could not inspect this valid Lua chunk: " .. tostring(result) }
      for _, t in ipairs(tokens) do if t.text == "global" then declares = true break end end
    end
  else
    for _, t in ipairs(tokens) do if t.text == "global" then declares = true break end end
  end
  if not declares then
    report.warnings[#report.warnings + 1] = { kind = "globals", line = 0,
      message = "no global declaration: an undeclared global is not an error here; start with `global none`" }
  end
  table.sort(report.requires)
  return report
end

-- Collect readable Lua paths and every incomplete enumeration. A partial
-- walk is useful, but cannot be reported as a complete successful check.
local function lua_files(dir)
  local paths, errors, failed = {}, {}, {}
  local function failure(path, why, win32)
    if failed[path] then return end
    failed[path] = true
    errors[#errors + 1] = { path = path, message = tostring(why), win32 = win32 }
  end
  local skip = {}
  for _, name in ipairs(check.PRUNE) do skip[name:lower()] = true end
  local walk, why = fs.dirs(dir, { prune = check.PRUNE })
  if not walk then failure(dir, why) return paths, errors end
  for _, e in ipairs(walk.errors) do
    failure(e.path, "FS oserror: " .. e.reason .. " (win32 " .. tostring(e.win32) .. ")", e.win32)
  end
  for _, sub in ipairs(walk.paths) do
    -- `^.*/(.*)$` rather than `([^/]+)$`: only `^` anchors a Lua pattern, so
    -- the second is retried at every position while the first is tried once
    -- and lets the greedy `.*` fall back to the last separator. See pitfalls.
    local base = sub:match("^.*/(.*)$") or sub
    if not failed[sub] and (sub == dir or not skip[base:lower()]) then
      local listing, e = fs.list(sub)
      if not listing then failure(sub, e)
      else
        for _, message in ipairs(listing.errors) do failure(sub, "FS oserror: " .. message) end
        for _, entry in ipairs(listing.entries) do
          if entry.kind == "file" and entry.name:sub(-4) == ".lua" then
            paths[#paths + 1] = fs.join(sub, entry.name)
          end
        end
      end
    end
  end
  table.sort(paths)
  table.sort(errors, function(a, b) return a.path < b.path end)
  return paths, errors
end

-- check.tree(dir [, root]) -> { root, reports }: every *.lua below dir, in
-- path order, skipping check.PRUNE directories; requires resolve against root.
function check.tree(dir, root)
  dir = fs.absolute(dir)
  root = root and fs.absolute(root) or dir
  local reports, tool_cache = {}, {}
  local paths, errors = lua_files(dir)
  for _, path in ipairs(paths) do reports[#reports + 1] = check.file(path, root, tool_cache) end
  for _, e in ipairs(errors) do
    reports[#reports + 1] = { path = e.path, enumeration = true, warnings = {}, requires = {}, tools = {},
      errors = { { kind = "read", line = 0, message = e.message, win32 = e.win32 } } }
  end
  table.sort(reports, function(a, b) return a.path < b.path end)
  return { root = root, reports = reports }
end

-- check.modules(root) -> { root, files, modules, complete, errors }: the project's own modules
-- and what each one exports, `{ name, path, exports }` in name order.
--
-- Every *.lua below the root is read and the ones whose exports the text
-- bounds are returned; the rest are only counted. A program is not a module,
-- and from the text alone it does not differ from a module whose exports
-- cannot be bounded, so naming either would be a guess. Nothing is executed.
function check.modules(root)
  root = fs.absolute(root)
  local paths, errors = lua_files(root)
  local candidates = {}
  local prefix = root:gsub("/$", "")
  for _, path in ipairs(paths) do
    local stem = path:sub(#prefix + 2, -5)
    -- A literal dot in a filename is not a module separator. Confirm that
    -- converting the candidate to a require name resolves back to this file,
    -- with the loader's ordinary-file and bundled-module precedence.
    local init = stem:sub(-5) == "/init"
    local dotted = (init and stem:sub(1, -6) or stem):gsub("/", ".")
    local resolved = module_path(root, dotted)
    if resolved and fs.absolute(resolved):lower() == path:lower()
        and package.preload[dotted] == nil and rt.source(dotted) == nil then
      candidates[dotted] = path
    end
  end
  local modules = {}
  for name, path in pairs(candidates) do
    local exports, e = project_exports(path)
    if e then errors[#errors + 1] = { path = path, message = tostring(e) } end
    if exports ~= nil then
      local names = {}
      for export in pairs(exports) do names[#names + 1] = export end
      table.sort(names)
      modules[#modules + 1] = { name = name, path = path, exports = names }
    end
  end
  table.sort(modules, function(a, b) return a.name < b.name end)
  table.sort(errors, function(a, b) return a.path < b.path end)
  return { root = root, files = #paths, modules = modules, complete = #errors == 0, errors = errors }
end

return check
