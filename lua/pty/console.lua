-- Provisional console automation. This is a text filter, not a screen model.
global none
global <const> require, type, pairs, ipairs, pcall, error, table, string, math, setmetatable

local err, cli, sched = require 'err', require 'cli', require 'sched'

return function(pty)
  local spawn, resize = pty._spawn, pty._resize
  pty._spawn, pty._resize = nil, nil
  local methods = {}
  local function problem(code, message) return err.new('PTY', code, message) end
  local function mapped(e)
    if type(e) == 'table' and e.domain == 'PROC' then
      return problem(e.code == 'usage' and 'badvalue' or e.code, e.message)
    end
    return e
  end
  local function call(fn, ...)
    local r = table.pack(pcall(fn, ...))
    if not r[1] then error(mapped(r[2]), 0) end
    if r[2] == nil and r.n >= 3 then r[3] = mapped(r[3]) end
    return table.unpack(r, 2, r.n)
  end
  local function live(self)
    if self._closed then error(problem('closed', 'the pseudoconsole is closed'), 3) end
  end
  local reader_meta = { __close = function(g) g.owner._reading = false end }
  local function reader(self)
    live(self)
    if self._reading then error(problem('busy', 'another task is already reading this console'), 3) end
    self._reading = true
    return setmetatable({ owner = self }, reader_meta)
  end
  local function character(self, c)
    if self._line[self._column] ~= nil then
      local at = self._line_start + 1
      for i = 1, self._column - 1 do at = at + #self._line[i] end
      self._expect_at = math.min(self._expect_at, at)
    end
    self._line[self._column] = c
    self._column = self._column + 1
  end
  local function feed(self, raw)
    if self._bytes + #raw > self._maxout then
      self._failure = problem('toobig', 'the console transcript exceeded maxout')
      return nil, self._failure
    end
    self._bytes = self._bytes + #raw
    for i = 1, #raw do
      local b = raw:byte(i)
      local c = raw:sub(i, i)
      local state = self._escape
      if state == 'csi' then
        if b >= 64 and b <= 126 then self._escape = nil end
      elseif state == 'osc' then
        if b == 7 then self._escape = nil
        elseif b == 27 then self._escape = 'osc-escape' end
      elseif state == 'osc-escape' then
        if c == '\\' then self._escape = nil else self._escape = 'osc' end
      elseif state == 'escape' then
        if c == '[' then self._escape = 'csi'
        elseif c == ']' then self._escape = 'osc'
        else self._escape = nil end
      elseif b == 27 then
        self._escape = 'escape'
      elseif b == 13 then
        self._column = 1
      elseif b == 10 then
        local line = table.concat(self._line) .. '\n'
        self._lines[#self._lines + 1] = line
        self._line_start = self._line_start + #line
        self._line, self._column = {}, 1
      elseif b == 8 then
        if self._column > 1 then
          self._column = self._column - 1
          self._line[self._column] = ''
        end
      elseif b == 9 then
        character(self, '\t')
      elseif b >= 32 and b ~= 127 then
        if #self._utf > 0 then
          self._utf = self._utf .. c
          if #self._utf == self._utf_length then character(self, self._utf); self._utf = '' end
        elseif b >= 194 and b <= 244 then
          self._utf, self._utf_length = c, b < 224 and 2 or b < 240 and 3 or 4
        else
          character(self, c)
        end
      end
    end
    return true
  end
  local function read_one(self, timeout)
    if self._failure then return nil, self._failure end
    local raw, e = call(self._child.read, self._child, 'some', timeout)
    if raw == nil then return nil, e end
    local ok, problem_value = feed(self, raw)
    if not ok then return nil, problem_value end
    return raw
  end
  function methods:read(timeout)
    local guard <close> = reader(self)
    return read_one(self, timeout)
  end
  function methods:text()
    live(self)
    return table.concat(self._lines) .. table.concat(self._line)
  end
  function methods:expect(patterns, timeout)
    local guard <close> = reader(self)
    if type(patterns) ~= 'table' or #patterns == 0 then error(problem('badvalue', 'expect needs a non-empty array of Lua patterns'), 2) end
    for i = 1, #patterns do
      if type(patterns[i]) ~= 'string' then error(problem('badvalue', 'expect patterns must be a dense array of strings'), 2) end
    end
    for k, pattern in pairs(patterns) do
      if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 or k > #patterns or type(pattern) ~= 'string' then
        error(problem('badvalue', 'expect needs an array of Lua pattern strings'), 2)
      end
      local ok, why = pcall(string.find, '', pattern)
      if not ok then error(problem('badvalue', 'invalid Lua pattern: ' .. why), 2) end
    end
    local seconds = timeout == nil and 30 or cli.duration(timeout)
    if seconds == nil then error(problem('badvalue', 'expect timeout must be a duration'), 2) end
    if self._failure then return nil, self._failure end
    local due = sched.clock() + seconds
    while true do
      local text = self:text()
      local start = self._expect_at
      local first, last, which
      for i, pattern in ipairs(patterns) do
        local valid, a, b = pcall(string.find, text, pattern, start)
        if not valid then error(problem('badvalue', 'invalid Lua pattern: ' .. a), 2) end
        if a and (first == nil or a < first) then first, last, which = a, b, i end
      end
      if which then
        self._expect_at = math.max(last + 1, first + 1)
        return text:sub(start, last), which
      end
      local remaining = due - sched.clock()
      if remaining < 0 then remaining = 0 end
      local raw, e = read_one(self, remaining)
      if raw == nil then
        if e then return nil, e end
        return nil, problem('closed', 'the console ended before a pattern matched')
      end
      if sched.clock() >= due then
        -- One last buffered match is allowed; the next read polls with zero.
        local now_text = self:text()
        local found = false
        for _, pattern in ipairs(patterns) do
          local valid, a = pcall(string.find, now_text, pattern, self._expect_at)
          if not valid then error(problem('badvalue', 'invalid Lua pattern: ' .. a), 2) end
          if a then found = true break end
        end
        if not found then return nil, problem('timeout', 'no pattern matched within the wait') end
      end
    end
  end
  function methods:write(bytes)
    live(self)
    if type(bytes) ~= 'string' then error(problem('badvalue', 'write needs a string of bytes'), 2) end
    return call(self._child.write, self._child, bytes)
  end
  function methods:resize(cols, rows)
    live(self)
    return call(resize, self._child, cols, rows)
  end
  function methods:wait(timeout)
    live(self)
    return call(self._child.wait, self._child, timeout)
  end
  function methods:kill()
    live(self)
    return call(self._child.kill, self._child)
  end
  function methods:close()
    if not self._closed then
      self._closed = true
      call(self._child.close, self._child)
    end
    return true
  end
  local meta = {
    __index = methods,
    __close = methods.close,
    __gc = function(self) if not self._closed then pcall(methods.close, self) end end,
    __metatable = 'kuu.pty',
  }
  function pty.spawn(spec)
    if type(spec) ~= 'table' then error(problem('badvalue', 'spawn needs a command table'), 2) end
    local maxout = spec.maxout == nil and 64 * 1024 * 1024 or cli.size(spec.maxout)
    if maxout == nil or maxout < 1 then error(problem('badvalue', 'maxout must be a positive byte size'), 2) end
    local child, e = call(spawn, spec)
    if not child then return nil, e end
    return setmetatable({ _child = child, pid = child.pid, _closed = false, _reading = false,
      _lines = {}, _line = {}, _column = 1, _line_start = 0, _bytes = 0, _maxout = maxout,
      _utf = '', _utf_length = 0, _expect_at = 1 }, meta)
  end
end
