-- check.lua -- what kuu can tell about Lua files before running them.
--
--   local check = require "check"
--   local r = check.file("tasks.lua", root)     -- { path, errors, warnings, requires }
--   local t = check.tree(dir, root)             -- every *.lua below dir: { root, reports }
--
-- For each file: it is parsed by Lua 5.5's own compiler, text only, so a
-- syntax error, and under a global declaration an undeclared global, is found
-- with its line; a file with no global declaration at all gets a warning,
-- because there the classic typo is silent; and every literal `require` is
-- listed and resolved against kuu's modules and the root, so a name that
-- resolves to nothing is a warning before any run gets there. The
-- palette's exported names are checked for direct local require bindings.
-- Project code is never executed, and no call is type-checked.
global none
global <const> require, ipairs, pairs, tostring, tonumber, type, string, table, load, package, select, pcall, math, error

local fs = require "fs"
local rt = require "rt"

local check = {}

check.PRUNE = { ".git", ".tools", "build", "node_modules" }

local function resolves(root, name)
  if package.preload[name] ~= nil or rt.source(name) ~= nil then return true end
  if not name:match("^[%w_%-]+$") and not name:match("^[%w_%-]+%.[%w_%.%-]+$") then return false end
  local rel = name:gsub("%.", "/")
  return fs.exists(root .. "/" .. rel .. ".lua") == "file" or fs.exists(root .. "/" .. rel .. "/init.lua") == "file"
end

-- One lexer serves require discovery and name checking. Strings and comments
-- cannot turn into executable names, and each token retains its source line.
local function tokens_of(text)
  local tokens, pos, line = {}, 1, 1
  local doubles = { ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true,
    ["<<"] = true, [">>"] = true, ["//"] = true, [".."] = true, ["::"] = true }
  while pos <= #text do
    local start, at_line = pos, line
    local c = text:sub(pos, pos)
    local comment = text:sub(pos, pos + 1) == "--"
    local at = comment and pos + 2 or pos
    local equals = text:match("^%[(=*)%[", at)
    local kind, value, after
    if equals ~= nil then
      local closing = "]" .. equals .. "]"
      local stop = text:find(closing, at + #equals + 2, true)
      after = stop and stop + #closing or #text + 1
      kind = comment and "comment" or "string"
    elseif comment then
      after, kind = text:find("[\r\n]", pos + 2) or #text + 1, "comment"
    elseif c:match("%s") then
      after, kind = pos + 1, "space"
    elseif c == '"' or c == "'" then
      after = pos + 1
      while after <= #text do
        local ch = text:sub(after, after)
        if ch == "\\" then after = after + 2
        elseif ch == c then after = after + 1 break
        else after = after + 1 end
      end
      kind = "string"
    elseif c:match("[%a_]") then
      local _, stop = text:find("^[%a_][%w_]*", pos)
      after, kind = stop + 1, "name"
    elseif c:match("%d") or (c == "." and text:sub(pos + 1, pos + 1):match("%d")) then
      after, kind = pos + 1, "number"
      while after <= #text do
        local ch, previous = text:sub(after, after), text:sub(after - 1, after - 1)
        if ch:match("[%w%.]") or (ch:match("[+-]") and previous:match("[eEpP]")) then after = after + 1
        else break end
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
    local _, breaks = text:sub(pos, after - 1):gsub("\r\n", "\n"):gsub("[\r\n]", "")
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

local function nearest(name, exports)
  local best, distance
  for candidate in pairs(exports) do
    local previous = {}
    for j = 0, #candidate do previous[j] = j end
    for i = 1, #name do
      local current = { [0] = i }
      for j = 1, #candidate do
        current[j] = math.min(current[j - 1] + 1, previous[j] + 1,
          previous[j - 1] + (name:sub(i, i) == candidate:sub(j, j) and 0 or 1))
      end
      previous = current
    end
    local d = previous[#candidate]
    if distance == nil or d < distance or (d == distance and candidate < best) then best, distance = candidate, d end
  end
  if distance ~= nil and distance <= math.max(1, math.min(3, #name // 3)) then return best end
end

-- Follow expression/block structure to distinguish bindings, not to infer
-- types. Defer diagnostics until the whole file is scanned: reassignment
-- makes a binding uncertain even in a closure declared before the write.
local function inspect(tokens, report, root)
  local pos, declares = 1, false
  local native_require = { native = true }
  local scopes, calls, accesses = { { require = native_require } }, {}, {}
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
    if not consume(s) then error("check parser expected " .. s .. ", got " .. token().text) end
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
    if base.binding then
      accesses[#accesses + 1] = { binding = base.binding, alias = base.name, name = name.text, line = name.line }
    end
    return {}
  end
  local function arguments()
    if consume("(") then
      local args = {}
      if not is(")") then args = expressions() end
      expect(")")
      return args
    end
    return { expression(13) } -- a string or table constructor
  end
  local function primary()
    local t, result = take(), {}
    if t.text == "(" then
      result = expression(0)
      expect(")")
    elseif t.text == "function" then function_body(false)
    elseif t.text == "{" then
      while not is("}") do
        if consume("[") then expression(0) expect("]") expect("=") expression(0)
        elseif token().kind == "name" and tokens[pos + 1].text == "=" then take() take() expression(0)
        else expression(0) end
        if not consume(",") and not consume(";") then break end
      end
      expect("}")
    elseif t.kind == "string" then result.literal = t.value
    elseif t.kind == "name" then result = { name = t.text, binding = lookup(t.text) }
    end
    while true do
      if consume(".") then result = field(result)
      elseif consume("[") then expression(0) expect("]") result = {}
      elseif consume(":") then result = field(result) arguments() result = {}
      elseif is("(") or is("{") or token().kind == "string" then
        local args, original = arguments(), result
        result = {}
        if original.binding == native_require and #args == 1 and args[1].literal ~= nil then
          local call = { name = args[1].literal, line = t.line }
          calls[#calls + 1] = call
          result.call = call
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
      expression((op == "^" or op == "..") and priority - 1 or priority)
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
        if name ~= "..." then bind(name) end
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
        if modules[name] == nil then modules[name] = exports_of(name) or false end
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
  end
  return declares
end

-- check.file(path [, root]) -> { path, errors, warnings, requires }
function check.file(path, root)
  root = root or fs.absolute(".")
  local report = { path = fs.absolute(path), errors = {}, warnings = {}, requires = {} }
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
  if chunk ~= nil then declares = inspect(tokens, report, root)
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

-- check.tree(dir [, root]) -> { root, reports }: every *.lua below dir, in
-- path order, skipping check.PRUNE directories; requires resolve against root.
function check.tree(dir, root)
  dir = fs.absolute(dir)
  root = root or dir
  local reports = {}
  local skip = {}
  for _, name in ipairs(check.PRUNE) do skip[name:lower()] = true end
  -- the walker lists a pruned directory and only refuses to enter it; its
  -- own files are skipped here, the root's never
  local walk = fs.dirs(dir, { prune = check.PRUNE })
  for _, sub in ipairs(walk.paths) do
    local listing = (sub == dir or not skip[(sub:match("([^/]+)$") or ""):lower()]) and fs.list(sub) or nil
    if listing then
      for _, entry in ipairs(listing.entries) do
        if entry.kind == "file" and entry.name:match("%.lua$") then
          reports[#reports + 1] = check.file(sub .. "/" .. entry.name, root)
        end
      end
    end
  end
  table.sort(reports, function(a, b) return a.path < b.path end)
  return { root = root, reports = reports }
end

return check
