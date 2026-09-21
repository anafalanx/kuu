-- _ledger.lua -- the door's memory of what passed through it.
--
-- One record per crossing -- the run, each task, each child a task ran --
-- appended to .kuu/ledger/<day>.ndjson under the project root, written from
-- what kuu observed and never from what a tool reported.  Each record
-- carries the sha256 of the one before it, across days, so an edited line
-- is visible: nothing prevents editing, the chain shows it.  Files older
-- than ninety days go as new ones are written. Schema version 2 records
-- execution only; historical version 1 records remain readable and retain
-- their original bytes. Project files are never surveyed or hashed here.
--
-- Private: the verbs write it, capabilities reads it, and a program has
-- fs.read for the files, which are plain NDJSON.
global none
global <const> require, ipairs, pairs, pcall, type, table, tostring, math

local fs, json, hash, time, rt, sync = require "fs", require "json", require "hash", require "time", require "rt", require "sync"
local err = require "err"

local ledger = {}
ledger.VERSION = 2
ledger.KEEP_DAYS = 90

local function dir_of(root) return fs.join(root, ".kuu", "ledger") end
local function day_of(instant) return time.iso(instant):sub(1, 10) end -- the UTC day

local function day_files(dir)
  local listing, e = fs.list(dir)
  if not listing then
    if err.is(e, "FS", "notfound") then return {} end
    return nil, e
  end
  if #listing.errors > 0 then
    return nil, err.new("FS", "oserror", "cannot completely list '" .. dir .. "': " .. tostring(listing.errors[1]))
  end
  local names = {}
  for _, e in ipairs(listing.entries) do
    if e.kind == "file" and e.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = e.name end
  end
  table.sort(names)
  return names
end

-- Iterate only the requested suffix, newest line first. Native fs.read still
-- reads the day file; bounded reversed chunks avoid a Lua pattern pass over
-- every historical byte and avoid allocating every historical line.
-- tail preserves CR bytes and counts malformed nonempty rows, exactly like
-- [^\n]+. The append anchor separately strips trailing CR/LF, as before.
local function lines_from_end(text, trim_cr)
  local next_high, chunk, high, position = #text, "", 0, 1
  local skip = trim_cr and "[^\r\n]" or "[^\n]"
  local function available()
    if position <= #chunk then return true end
    if next_high < 1 then return false end
    high = next_high
    local low = math.max(1, high - 8191)
    chunk, next_high, position = text:sub(low, high):reverse(), low - 1, 1
    return true
  end
  return function()
    -- Empty LF-separated rows have never consumed tail's count. Skip runs
    -- in each bounded chunk, including an all-newline chunk.
    while available() do
      local first = chunk:find(skip, position)
      if first then position = first break end
      position = #chunk + 1
    end
    if position > #chunk then return nil end
    local finish = high - position + 1
    while available() do
      local newline = chunk:find("\n", position, true)
      if newline then
        position = newline + 1
        return text:sub(high - newline + 2, finish)
      end
      position = #chunk + 1
    end
    return text:sub(1, finish)
  end
end

-- The last record line written, today's or the newest day's, for the chain.
local function last_line(dir)
  local names, e = day_files(dir)
  if not names then return nil, e end
  for i = #names, 1, -1 do
    local text, why = fs.read(fs.join(dir, names[i]))
    if not text then return nil, why end
    local last = lines_from_end(text, true)()
    if last then return last end
  end
  return nil
end

local function rotate(dir)
  local cutoff = day_of(time.now() - ledger.KEEP_DAYS * 86400)
  local names = day_files(dir)
  if not names then return end -- a rotation failure cannot undo an appended record
  for _, name in ipairs(names) do
    if name:sub(1, 10) < cutoff then fs.remove(fs.join(dir, name)) end
  end
end

-- Where the repository stands, from .git itself: no git.exe is assumed,
-- kuu looks nothing up on PATH. This context does not indicate whether
-- project files are dirty or attribute changes to a run. In a worktree or a
-- submodule .git is a file naming the real directory, whose `commondir`
-- names where the refs are; HEAD is the worktree's own.
local function rooted(base, path)
  if path:match("^%a:") or path:match("^[/\\]") then return path end
  return fs.join(base, path)
end

local function git_dirs(root)
  local dot = fs.join(root, ".git")
  local info = fs.stat(dot)
  if not info then return nil end
  if info.kind ~= "file" then return dot, dot end
  local text = fs.read(dot, { encoding = "utf-8" })
  local target = text and text:match("^gitdir:%s*(.-)%s*$")
  if not target or target == "" then return nil end
  local own = fs.absolute(rooted(root, target))
  local common = fs.read(fs.join(own, "commondir"), { encoding = "utf-8" })
  common = common and common:gsub("%s+$", "") or ""
  if common == "" then return own, own end
  return own, fs.absolute(rooted(own, common))
end

local function git_of(root)
  local own, common = git_dirs(root)
  if not own then return nil end
  local head = fs.read(fs.join(own, "HEAD"), { encoding = "utf-8" })
  if not head then return nil end
  head = head:gsub("%s+$", "")
  local ref = head:match("^ref:%s*(.+)$")
  if not ref then return { head = head } end
  local sha = fs.read(fs.join(own, ref), { encoding = "utf-8" }) or fs.read(fs.join(common, ref), { encoding = "utf-8" })
  if sha then return { ref = ref, head = (sha:gsub("%s+$", "")) } end
  local packed = fs.read(fs.join(common, "packed-refs"), { encoding = "utf-8" })
  if packed then
    local escaped = ref:gsub("%p", "%%%0")
    local found = packed:match("(%x+) " .. escaped .. "\r?\n")
    if found then return { ref = ref, head = found } end
  end
  return { ref = ref }
end

-- One canonical project identity serializes all history appends.
-- Never fall back to a spelling-specific lock when canonicalization fails.
local function locked(root)
  local canon, why = fs.canon(root)
  if not canon then return nil, why end
  return sync.lock("ledger." .. hash.sum("sha256", canon.path:lower()), "10s")
end

-- Opening a book captures only best-effort repository identity. It neither
-- loads scan policy nor reads or maintains project tree state.
function ledger.open(root)
  root = fs.absolute(root)
  local read, git = pcall(git_of, root)
  return { root = root, dir = dir_of(root), git = read and git or nil, written = 0 }
end

-- ledger.record(book, fields) -> true | nil, err
-- One crossing: `kind` (verb | task | child), `name`, and what the caller
-- observed -- `at`, `seconds`, `status`, `code`, `argv`, `cwd`, `tool`,
-- `bytes`, `error`. A record that cannot be encoded -- a string in it that
-- is not UTF-8 -- is `nil, err` like one that cannot be written.
function ledger.record(book, fields)
  local made, e = fs.mkdir(book.dir)
  if not made then return nil, e end
  local lock <close>, e2 = locked(book.root)
  if not lock then return nil, e2 end
  local record = { v = ledger.VERSION, kuu = rt.version, root = book.root, git = book.git }
  for k, v in pairs(fields) do record[k] = v end
  -- Retired private callers may still pass observation fields. New history
  -- always follows the execution schema, without changing caller tables.
  record.v, record.delta, record.observation = ledger.VERSION, nil, nil
  -- The line before this one is the last this run wrote when nothing has
  -- been appended since -- the file is the size it was left at -- and is
  -- read from the file otherwise, so the day file is read once per run and
  -- not once per record, and a run beside this one is still chained to.
  local path = fs.join(book.dir, day_of(time.now()) .. ".ndjson")
  local previous
  if book.last ~= nil and book.last_path == path then
    local info = fs.stat(path)
    if info and info.size == book.last_size then previous = book.last end
  end
  if previous == nil then
    local why
    previous, why = last_line(book.dir)
    if why then return nil, why end
  end
  if previous then record.prev = hash.sum("sha256", previous) end
  local encoded, line = pcall(json.encode, record)
  if not encoded then return nil, line end
  local ok, e3 = fs.write(path, line .. "\n", { append = true })
  if not ok then return nil, e3 end
  local info = fs.stat(path)
  book.last, book.last_path, book.last_size = line, path, info and info.size or nil
  book.written = book.written + 1
  rotate(book.dir)
  return true
end

-- JSON syntax alone does not make a ledger record. In particular scalars,
-- arrays and partially written objects must never reach the descriptor's
-- field accesses. Check the common fields it displays and chains; extra
-- fields remain available to readers as the schema grows.
local function decode_record(line)
  local record = json.decode(line)
  if type(record) ~= "table" or (record.v ~= 1 and record.v ~= ledger.VERSION)
      or type(record.kuu) ~= "string" or type(record.root) ~= "string"
      or type(record.name) ~= "string" or type(record.status) ~= "string"
      or type(record.at) ~= "number" or type(record.seconds) ~= "number" then return nil end
  if record.kind ~= "verb" and record.kind ~= "task" and record.kind ~= "child" then return nil end
  if record.prev ~= nil and (type(record.prev) ~= "string" or #record.prev ~= 64 or record.prev:find("[^%x]")) then return nil end
  return record
end

-- ledger.tail(root, n) -> the last n records, oldest first, decoded | nil, err
-- Malformed lines are omitted here; verify names the first broken line.
function ledger.tail(root, n)
  local dir = dir_of(fs.absolute(root))
  local names, e = day_files(dir)
  if not names then return nil, e end
  local lines = {}
  for i = #names, 1, -1 do
    local text, why = fs.read(fs.join(dir, names[i]))
    if not text then return nil, why end
    for line in lines_from_end(text) do
      lines[#lines + 1] = line
      if #lines >= n then break end
    end
    if #lines >= n then break end
  end
  local records = {}
  for i = #lines, 1, -1 do
    local record = decode_record(lines[i])
    if record then records[#records + 1] = record end
  end
  return records
end

-- ledger.verify(root) -> true, count | nil, err (LEDGER broken or an FS error)
-- Walks every record in day order and holds each `prev` to the sha256 of
-- the line before it.
function ledger.verify(root)
  local dir = dir_of(fs.absolute(root))
  local previous, count = nil, 0
  local names, e = day_files(dir)
  if not names then return nil, e end
  for _, name in ipairs(names) do
    local text, why = fs.read(fs.join(dir, name))
    if not text then return nil, why end
    local number = 0
    for line in text:gmatch("[^\n]+") do
      number = number + 1
      local record = decode_record(line)
      if record == nil then return nil, err.new("LEDGER", "broken", name .. ":" .. number .. " is not a record") end
      -- The first record kept may name a line that rotation removed; it is
      -- the anchor, and every record after it is held to its predecessor.
      if previous ~= nil and record.prev ~= hash.sum("sha256", previous) then
        return nil, err.new("LEDGER", "broken", name .. ":" .. number .. " does not follow the record before it")
      end
      previous = line
      count = count + 1
    end
  end
  return true, count
end

return ledger
