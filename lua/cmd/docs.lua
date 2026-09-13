-- docs.lua -- `kuu docs [--json] [PAGE [SECTION]] | search [--json] TEXT ...`:
-- the manual, from inside the executable.
--
-- A verb like the others: --help, the unknown-option law, --json.  The
-- pages are carried in the payload and reached through rt.pages() and
-- rt.page(name), so a program with no shell can read them the same way.
global none
global <const> require, ipairs, tostring, string, table, io, os

local rt = require "rt"
local cli = require "cli"
local json = require "json"
local err = require "err"

local USAGE = "kuu docs"
local spec = {
  { "--json", type = "flag", help = "the page list, a page, or the search hits as one envelope" },
  { "words", type = "string", rest = true,
    help = "nothing: the pages; PAGE: one page; PAGE SECTION: one of its sections; search TEXT...: the lines that mention it" },
}
local opts, e = cli.parse(rt.args, spec, USAGE)
if not opts then io.stderr:write("kuu: ", tostring(e), "\n") os.exit(2) end
if opts.help then
  io.write(cli.usage(spec, USAGE),
    "\n  kuu docs                    the pages, each with its first sentence\n",
    "  kuu docs PAGE               one page, as kuu docs PAGE.md would be\n",
    "  kuu docs PAGE SECTION       one ## section of it, by its heading or its anchor; PAGE#anchor is the same\n",
    "  kuu docs search TEXT ...    the lines mentioning the words, joined by spaces, matched literally, ignoring case\n",
    "\nStart with agent, what is expected of you here; then pitfalls, once; index is the map.\n")
  os.exit(0)
end

local function fail(e2)
  if opts.json then
    io.write(json.encode { ok = false, error = { domain = e2.domain, code = e2.code, message = e2.message } }, "\n")
  else
    io.stderr:write("kuu: ", tostring(e2), "\n")
  end
  os.exit(2)
end

-- ---- reading a page ---------------------------------------------------------

-- The lines of a page with their numbers, each told whether it is inside a
-- fenced code block: a `## ` there is text, not a heading -- the agent
-- page's sample entry is one.
local function lines_of(text)
  local out, line, fenced = {}, 0, false
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line + 1
    if raw:match("^```") or raw:match("^~~~") then fenced = not fenced end
    out[#out + 1] = { text = raw, line = line, fenced = fenced or raw:match("^```") ~= nil or raw:match("^~~~") ~= nil }
  end
  return out
end

local function heading_of(entry, level)
  if entry.fenced then return nil end
  return entry.text:match(level == 1 and "^##? (.+)$" or "^## (.+)$")
end

-- Every `## ` heading with its line, in order.
local function sections_of(lines)
  local found = {}
  for _, entry in ipairs(lines) do
    local heading = heading_of(entry, 2)
    if heading then found[#found + 1] = { heading = heading, line = entry.line } end
  end
  return found
end

-- GitHub's anchor for a heading, the spelling the manual's own links use:
-- lower case, everything but letters, digits, spaces, hyphens and
-- underscores dropped, spaces to dashes.
local function anchor(heading)
  return (heading:lower():gsub("[^%w%s_%-]", ""):gsub("%s+", "-"))
end

-- The first sentence of the page after its title, links reduced to their
-- text and emphasis dropped: what the page list says beside each name.  A
-- leading paragraph that is only code -- a require line, a fence -- is
-- passed over for the prose after it.
local function description_of(text)
  local body = text:gsub("^#[^\n]*\n", "", 1)
  for paragraph in (body .. "\n\n"):gmatch("%s*(.-)\n%s*\n") do
    if not paragraph:match("^```") and not paragraph:match("^`[^`]*`%s*$") and not paragraph:match("^|") then
      local prose = paragraph:gsub("%s+", " "):gsub("%[([^%]]-)%]%([^%)]-%)", "%1"):gsub("%*%*", "")
      return prose:match("^(.-[%.!?])%s") or prose
    end
  end
  return ""
end

local function shorten(s, width)
  if #s <= width then return s end
  local cut = s:sub(1, width):match("^(.*)%s") or s:sub(1, width)
  return cut .. " \u{2026}"
end

local function count_lines(text)
  local n = 0
  for _ in text:gmatch("\n") do n = n + 1 end
  if text:sub(-1) ~= "\n" and #text > 0 then n = n + 1 end
  return n
end

-- ---- the three shapes ---------------------------------------------------------

local words = opts.words or {}

if #words == 0 then
  local pages = json.array {}
  for _, name in ipairs(rt.pages()) do
    local text = rt.page(name) or ""
    pages[#pages + 1] = { name = name, description = description_of(text), lines = count_lines(text) }
  end
  if opts.json then
    io.write(json.encode { ok = true, result = { version = rt.version, pages = pages } }, "\n")
  else
    io.write("kuu ", rt.version, " manual. Pages:\n")
    for _, page in ipairs(pages) do
      io.write(string.format("  %-15s %s\n", page.name, shorten(page.description, 62)))
    end
    io.write("\nkuu docs PAGE prints a page; kuu docs PAGE SECTION one section; kuu docs search TEXT finds lines.\n",
      "Start with agent, what is expected of you here; then pitfalls, once; index is the map.\n")
  end
  os.exit(0)
end

if words[1] == "search" then
  local needle = table.concat(words, " ", 2):gsub("^%s+", ""):gsub("%s+$", "")
  if needle == "" then fail(err.new("ENTRY", "usage", "docs search needs text to look for")) end
  local lowered = needle:lower()
  local hits = json.array {}
  for _, name in ipairs(rt.pages()) do
    local heading = nil
    for _, entry in ipairs(lines_of(rt.page(name) or "")) do
      local h = heading_of(entry, 1)
      if h then heading = h end
      if entry.text:lower():find(lowered, 1, true) then
        hits[#hits + 1] = { page = name, line = entry.line, heading = heading, text = entry.text }
      end
    end
  end
  if opts.json then
    io.write(json.encode { ok = true, result = { text = needle, hits = hits } }, "\n")
  elseif #hits == 0 then
    io.write("nothing in the manual mentions '", needle, "'\n")
  else
    for _, hit in ipairs(hits) do io.write(hit.page, ":", hit.line, ": ", hit.text, "\n") end
  end
  os.exit(0)
end

local name, section = words[1], words[2]
local base, tail = name:match("^([^#]+)#(.+)$")
if base and section then fail(err.new("CLI", "usage", "unexpected argument '" .. section .. "' after " .. name)) end
if #words > 2 then fail(err.new("CLI", "usage", "unexpected argument '" .. words[3] .. "'")) end
if base then name, section = base, tail end
local text = rt.page(name)
if text == nil then fail(err.new("ENTRY", "notfound", "no manual page '" .. name .. "'; kuu docs lists them")) end
local lines = lines_of(text)
local sections = sections_of(lines)

if section == nil then
  if opts.json then
    local listed = json.array {}
    for _, s in ipairs(sections) do listed[#listed + 1] = { heading = s.heading, anchor = anchor(s.heading), line = s.line } end
    io.write(json.encode { ok = true, result = { name = name, lines = count_lines(text), sections = listed, text = text } }, "\n")
  else
    io.write(text)
  end
  os.exit(0)
end

-- A section by its heading -- the whole of it, or a prefix, ignoring case
-- -- or by its anchor.
local wanted = section:lower()
local chosen, index
for i, s in ipairs(sections) do
  local lowered = s.heading:lower()
  if lowered == wanted or anchor(s.heading) == wanted then chosen, index = s, i break end
end
if chosen == nil then
  for i, s in ipairs(sections) do
    if s.heading:lower():sub(1, #wanted) == wanted then chosen, index = s, i break end
  end
end
if chosen == nil then
  local names = {}
  for _, s in ipairs(sections) do names[#names + 1] = anchor(s.heading) end
  fail(err.new("ENTRY", "notfound", "no section '" .. section .. "' in page '" .. name .. "'; its sections are " ..
    (#names > 0 and table.concat(names, ", ") or "none")))
end
local span = {}
for _, entry in ipairs(lines) do
  if entry.line >= chosen.line then
    if entry.line > chosen.line and heading_of(entry, 1) then break end
    span[#span + 1] = entry.text
  end
end
while #span > 0 and span[#span] == "" do span[#span] = nil end
local body = table.concat(span, "\n") .. "\n"
if opts.json then
  io.write(json.encode { ok = true, result = { name = name, heading = chosen.heading, anchor = anchor(chosen.heading),
    line = chosen.line, text = body } }, "\n")
else
  io.write(body)
end
os.exit(0)
