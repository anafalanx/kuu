-- _ledger.lua -- the door's memory of what passed through it.
--
-- One record per crossing -- the run, each task, each child a task ran --
-- appended to .kuu/ledger/<day>.ndjson under the project root, written from
-- what kuu observed and never from what a tool reported.  Each record
-- carries the sha256 of the one before it, across days, so an edited line
-- is visible: nothing prevents editing, the chain shows it.  Files older
-- than ninety days go as new ones are written.  The first record of a run
-- carries the tree delta since the previous run -- what changed under the
-- root by size and mtime, with the prune list check uses and .kuu itself,
-- content hashed only for what moved -- which says which edits this run ran
-- against.  An edit with no crossing after it is work in progress, not a
-- bypass.
--
-- Private: the verbs write it, capabilities reads it, and a program has
-- fs.read for the files, which are plain NDJSON.
global none
global <const> require, ipairs, pairs, table

local fs, json, hash, time, rt, sync = require "fs", require "json", require "hash", require "time", require "rt", require "sync"

local ledger = {}
ledger.VERSION = 1
ledger.KEEP_DAYS = 90
ledger.NAMED = 40 -- paths a delta names; its counts are always complete
ledger.PRUNE = { ".git", ".tools", "build", "node_modules", ".kuu" }

local function dir_of(root) return fs.join(root, ".kuu", "ledger") end
local function day_of(instant) return time.iso(instant):sub(1, 10) end -- the UTC day

local function day_files(dir)
  local listing = fs.list(dir)
  if not listing then return {} end
  local names = {}
  for _, e in ipairs(listing.entries) do
    if e.kind == "file" and e.name:match("^%d%d%d%d%-%d%d%-%d%d%.ndjson$") then names[#names + 1] = e.name end
  end
  table.sort(names)
  return names
end

-- The last record line written, today's or the newest day's, for the chain.
local function last_line(dir)
  local names = day_files(dir)
  for i = #names, 1, -1 do
    local text = fs.read(fs.join(dir, names[i]))
    local last = text and text:match("([^\n]+)\n?$")
    if last and last ~= "" then return last end
  end
  return nil
end

local function rotate(dir)
  local cutoff = day_of(time.now() - ledger.KEEP_DAYS * 86400)
  for _, name in ipairs(day_files(dir)) do
    if name:sub(1, 10) < cutoff then fs.remove(fs.join(dir, name)) end
  end
end

-- Every file under the root by relative path, with size and mtime, the
-- prune list left out.
local function snapshot(root)
  local files = {}
  local skip = {}
  for _, name in ipairs(ledger.PRUNE) do skip[name:lower()] = true end
  local walk = fs.dirs(root, { prune = ledger.PRUNE })
  for _, sub in ipairs(walk.paths) do
    local base = sub:match("^.*/(.*)$") or sub
    if sub == root or not skip[base:lower()] then
      local listing = fs.list(sub)
      if listing then
        for _, e in ipairs(listing.entries) do
          if e.kind == "file" then
            files[(sub .. "/" .. e.name):sub(#root + 2)] = { size = e.size, mtime = e.mtime }
          end
        end
      end
    end
  end
  return files
end

-- What changed between two snapshots: complete counts, and up to NAMED
-- paths with the content hash of what is there now.
local function delta_between(root, before, after)
  local out = { added = 0, changed = 0, removed = 0, paths = {} }
  local function name(rel, how)
    if #out.paths >= ledger.NAMED then return end
    local entry = { path = rel, change = how }
    if how ~= "removed" then entry.sha256 = hash.file("sha256", fs.join(root, rel)) or nil end
    out.paths[#out.paths + 1] = entry
  end
  local rels = {}
  for rel in pairs(after) do rels[#rels + 1] = rel end
  for rel in pairs(before) do if after[rel] == nil then rels[#rels + 1] = rel end end
  table.sort(rels)
  for _, rel in ipairs(rels) do
    local b, a = before[rel], after[rel]
    if b == nil then out.added = out.added + 1 name(rel, "added")
    elseif a == nil then out.removed = out.removed + 1 name(rel, "removed")
    elseif b.size ~= a.size or b.mtime ~= a.mtime then out.changed = out.changed + 1 name(rel, "changed") end
  end
  return out
end

-- Where the repository stands, from .git itself: no git.exe is assumed,
-- kuu looks nothing up on PATH.  Whether the tree is dirty is what the
-- delta says; git's own answer would need git.
local function git_of(root)
  local head = fs.read(fs.join(root, ".git", "HEAD"), { encoding = "utf-8" })
  if not head then return nil end
  head = head:gsub("%s+$", "")
  local ref = head:match("^ref:%s*(.+)$")
  if not ref then return { head = head } end
  local sha = fs.read(fs.join(root, ".git", ref), { encoding = "utf-8" })
  if sha then return { ref = ref, head = (sha:gsub("%s+$", "")) } end
  local packed = fs.read(fs.join(root, ".git", "packed-refs"), { encoding = "utf-8" })
  if packed then
    local escaped = ref:gsub("%p", "%%%0")
    local found = packed:match("(%x+) " .. escaped .. "\r?\n")
    if found then return { ref = ref, head = found } end
  end
  return { ref = ref }
end

-- ledger.open(root) -> a ledger for one run.  The tree delta since the
-- previous run is taken here, once, at the door.
function ledger.open(root)
  root = fs.absolute(root)
  local dir = dir_of(root)
  local before_text = fs.read(fs.join(dir, "tree.json"))
  local before = before_text and json.decode(before_text) or {}
  local after = snapshot(root)
  return { root = root, dir = dir, delta = delta_between(root, before, after), git = git_of(root), tree = after, written = 0 }
end

local function locked(root)
  return sync.lock("ledger." .. hash.sum("sha256", root:lower()), "10s")
end

-- ledger.record(book, fields) -> true | nil, err
-- One crossing: `kind` (verb | task | child), `name`, and what the caller
-- observed -- `at`, `seconds`, `status`, `code`, `argv`, `cwd`, `tool`,
-- `bytes`, `error`.  The first record of a run carries the delta.
function ledger.record(book, fields)
  local made, e = fs.mkdir(book.dir)
  if not made then return nil, e end
  local lock <close>, e2 = locked(book.root)
  if not lock then return nil, e2 end
  local record = { v = ledger.VERSION, kuu = rt.version, root = book.root, git = book.git }
  for k, v in pairs(fields) do record[k] = v end
  if book.written == 0 then record.delta = book.delta end
  local previous = last_line(book.dir)
  if previous then record.prev = hash.sum("sha256", previous) end
  local line = json.encode(record) .. "\n"
  local ok, e3 = fs.write(fs.join(book.dir, day_of(time.now()) .. ".ndjson"), line, { append = true })
  if not ok then return nil, e3 end
  book.written = book.written + 1
  rotate(book.dir)
  return true
end

-- ledger.close(book): the tree as this run leaves it, so the next run's
-- delta is what changed in between.
function ledger.close(book)
  local ok, e = fs.mkdir(book.dir)
  if not ok then return nil, e end
  return fs.write(fs.join(book.dir, "tree.json"), json.encode(snapshot(book.root)) .. "\n")
end

-- ledger.tail(root, n) -> the last n records, oldest first, decoded
function ledger.tail(root, n)
  local dir = dir_of(fs.absolute(root))
  local names = day_files(dir)
  local lines = {}
  for i = #names, 1, -1 do
    local text = fs.read(fs.join(dir, names[i])) or ""
    local these = {}
    for line in text:gmatch("[^\n]+") do these[#these + 1] = line end
    for j = #these, 1, -1 do
      table.insert(lines, 1, these[j])
      if #lines >= n then break end
    end
    if #lines >= n then break end
  end
  local records = {}
  for _, line in ipairs(lines) do
    local record = json.decode(line)
    if record then records[#records + 1] = record end
  end
  return records
end

-- ledger.verify(root) -> true, count | nil, err (LEDGER broken at a record)
-- Walks every record in day order and holds each `prev` to the sha256 of
-- the line before it.
function ledger.verify(root)
  local dir = dir_of(fs.absolute(root))
  local err = require "err"
  local previous, count = nil, 0
  for _, name in ipairs(day_files(dir)) do
    local text = fs.read(fs.join(dir, name)) or ""
    local number = 0
    for line in text:gmatch("[^\n]+") do
      number = number + 1
      local record = json.decode(line)
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
