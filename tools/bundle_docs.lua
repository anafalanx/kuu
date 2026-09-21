-- Assemble Part III of kuu.md: every page of the manual, in a deliberate
-- reading order, inlined so an agent can read everything up front.
--
-- The bundle is generated rather than hand-maintained, because forty pages
-- copied by hand drift from their originals and the copy is the one people
-- read.  test/cases/bundle.lua regenerates it and fails when kuu.md is stale.
--
--   kuu tools/bundle_docs.lua            print the bundle
--   kuu tools/bundle_docs.lua --write    rewrite kuu.md's Part III in place
global none
global <const> require, ipairs, pairs, error, os, io, table, tostring, type, string, assert

local fs = require "fs"
local rt = require "rt"
local proc = require "proc"

local rtrim_both = require("text").trim
local function rtrim(s) return rtrim_both(s, "right") end

-- The marker after which kuu.md is generated.  Everything above it is written
-- by hand; everything from it down is this file's output.
local MARKER = "# Part III — the complete manual"

-- A deliberate order: the map, the one page to read first, then getting a
-- project going, the palette, the recipes, and finally the record.
local ORDER = {
  "index", "agent", "pitfalls", "capabilities",
  "adopting", "task", "tools", "confined", "ledger", "check", "scan", "cli",
  "proc", "fs", "http", "net", "sched", "json", "csv", "ini",
  "hash", "text", "re", "time", "archive", "log", "err",
  "mem", "sync", "sys", "reg", "env", "svc", "evt", "pty",
  "powershell", "cookbook", "cleanup", "process-recipes", "working-directories", "project-environment", "relocation", "editor", "native-helper", "reconstruction",
  "inheritance", "roadmap", "shortcomings", "stability", "toolchain",
  "upgrading-from-0.11", "upgrading-0.11", "upgrading-0.10", "upgrading-0.9", "upgrading-0.8", "upgrading-0.7", "upgrading-0.6",
}

local function root()
  return fs.dirname(fs.dirname(fs.canon(rt.program).path))
end

-- Part I's figures, produced from the executable and the tree rather than
-- by hand: every wrong figure found on 2026-09-12 was one a hand wrote and
-- nothing generated.  --write puts them between the markers in Part I,
-- --figures prints them, and the suite holds the two equal.
local FIGURES_OPEN, FIGURES_CLOSE = "<!-- figures -->", "<!-- /figures -->"

local function count_lines(pattern)
  local lines = 0
  for _, path in ipairs(fs.glob(pattern)) do
    for _ in (fs.read(path) or ""):gmatch("\n") do lines = lines + 1 end
  end
  return lines
end

local function thousands(n)
  local reversed = tostring(n):reverse():gsub("(%d%d%d)", "%1,")
  return (reversed:reverse():gsub("^,", ""))
end

local function figures(here)
  local palette = require "_palette"
  local functions = 0
  for _, name in ipairs(palette.public) do
    for _, value in pairs(require(name)) do
      if type(value) == "function" then functions = functions + 1 end
    end
  end
  local pages = 0
  for _, entry in ipairs(fs.list(here .. "/docs").entries) do
    if entry.name:match("%.md$") then pages = pages + 1 end
  end
  local help = proc.run { rt.exe, "--help", timeout = "30s" }
  local verbs = help and rtrim((help.out:gsub("\r\n", "\n"))) or "(kuu --help did not run)"
  local c = count_lines(here .. "/src/*.c")
  local lua = count_lines(here .. "/lua/*.lua") + count_lines(here .. "/lua/*/*.lua")
  local suite = count_lines(here .. "/test/*.lua") + count_lines(here .. "/test/cases/*.lua")
  local manual = count_lines(here .. "/docs/*.md")
  return table.concat({
    FIGURES_OPEN,
    string.format("By the numbers, %s is %s lines of authored host C, %s lines of kuu's own", rt.version, thousands(c), thousands(lua)),
    string.format("Lua, a suite of %s lines, and %s lines of manual in %d pages that ship", thousands(suite), thousands(manual), pages),
    string.format("inside the executable. The palette is %d public modules and %d functions,", #palette.public, functions),
    "plus methods on handles. The suite's own count is what `make test` prints.",
    "These figures are produced by `tools/bundle_docs.lua` from the executable",
    "and the tree, and the suite holds them.",
    "",
    "The verbs, as `kuu --help` prints them:",
    "",
    "```text",
    verbs,
    "```",
    FIGURES_CLOSE,
  }, "\n")
end

-- capabilities.md's example carries the executable's own figures -- the
-- version, the page count, the module and name counts, the error domains
-- -- and a hand wrote them wrong once already.  --write refreshes them
-- from `kuu capabilities` run here, and --capabilities prints the page as
-- --write leaves it, which the suite holds equal to the page.
local function capabilities_page(here)
  local text = fs.read(here .. "/docs/capabilities.md") or error("no docs/capabilities.md under " .. here)
  local r = proc.run { rt.exe, "capabilities", cwd = here, timeout = "30s" }
  if not (r and r.code == 0) then error("kuu capabilities did not run: " .. (r and r.err or "no result")) end
  local out = r.out:gsub("\r\n", "\n")
  local function figure(pattern, what)
    return out:match(pattern) or error("kuu capabilities printed no " .. what)
  end
  local facts = {
    { "(```text\nkuu )%S+ %(Lua [^)]+%)", figure("^kuu (%S+ %(Lua [^)]+%))", "version line") },
    { "(\n  manual%s+)%d+ pages", figure("\n  manual%s+(%d+ pages)", "manual line") },
    { "(\n  modules%s+)%d+, %d+ names", figure("\n  modules%s+(%d+, %d+ names)", "modules line") },
    { "(\n  errors%s+)%d+ domains", figure("\n  errors%s+(%d+ domains)", "errors line") },
  }
  for _, fact in ipairs(facts) do
    local pattern, value = fact[1], fact[2]
    local n
    text, n = text:gsub(pattern, function(prefix) return prefix .. value end, 1)
    if n ~= 1 then error("docs/capabilities.md has no line matching " .. pattern) end
  end
  return text
end

-- The usage is one string, the one `kuu --help` prints, and the three
-- places that quote it -- index.md, kuu.md's Start here, README -- carry
-- it between markers that --write refreshes and the suite holds equal;
-- three hand copies disagreed on the verbs' options before this.
local USAGE_OPEN, USAGE_CLOSE = "<!-- usage -->", "<!-- /usage -->"

local function usage_block()
  local r = proc.run { rt.exe, "--help", timeout = "30s" }
  if not (r and r.code == 0) then error("kuu --help did not run: " .. (r and r.err or "no result")) end
  local text = rtrim((r.out:gsub("\r\n", "\n")))
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  table.remove(lines, 1) -- the version line; the block is the usage alone
  return table.concat({ USAGE_OPEN, "```text", table.concat(lines, "\n"), "```", USAGE_CLOSE }, "\n")
end

local function with_usage(text, path)
  local open_at = text:find(USAGE_OPEN, 1, true)
  local close_at = text:find(USAGE_CLOSE, 1, true)
  if not open_at or not close_at then error(path .. " has no usage block between " .. USAGE_OPEN .. " and " .. USAGE_CLOSE) end
  return text:sub(1, open_at - 1) .. usage_block() .. text:sub(close_at + #USAGE_CLOSE)
end

-- Explicit page anchors remain stable when titles change. Section anchors
-- carry the page name, so repeated headings across pages cannot collide.
local function anchor(name)
  return "kuu-page-" .. (name:lower():gsub("%.", ""))
end

local function section_slug(heading)
  return (heading:lower():gsub("%p", function(p)
    return (p == "-" or p == "_") and p or ""
  end):gsub("%s", "-"))
end

-- Demote every heading one level so the pages nest under Part III, rewrite
-- cross-page links to anchors inside this document, and lift relative links
-- by the one directory level the page itself moves up.  Headings inside
-- fenced code blocks are left alone.
local function transform(text, page_name)
  local out, fenced, headings = {}, nil, {}
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw
    local fence = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      if not fenced then fenced = fence
      elseif fence:sub(1, 1) == fenced:sub(1, 1) and #fence >= #fenced then fenced = nil end
    end
    if not fenced then
      local heading = line:match("^#+%s+(.+)$")
      if heading then
        local slug = section_slug(heading)
        local occurrence = headings[slug] or 0
        headings[slug] = occurrence + 1
        if occurrence > 0 then slug = slug .. "-" .. occurrence end
        out[#out + 1] = '<a id="' .. anchor(page_name) .. "-" .. slug .. '"></a>'
        out[#out + 1] = ""
        line = "#" .. line
      end
      line = line:gsub("%]%((%w[%w%-%.]-)%.md#([%w_%-]+)%)", function(page, section)
        return "](#" .. anchor(page) .. "-" .. section .. ")"
      end)
      line = line:gsub("%]%((%w[%w%-%.]-)%.md%)", function(page)
        return "](#" .. anchor(page) .. ")"
      end)
      line = line:gsub("%]%((#[%w_%-]+)%)", function(target)
        if target:find("#kuu-page-", 1, true) == 1 then return "](" .. target .. ")" end
        return "](#" .. anchor(page_name) .. "-" .. target:sub(2) .. ")"
      end)

      -- A page moves up one level when it is inlined: from docs/ into kuu.md
      -- at the root.  A link that reaches outside docs/ loses that level with
      -- it, or it would point above the repository.  The rewrites above never
      -- see these, because their targets do not begin with a word character.
      line = line:gsub("%]%(%.%./", "](")
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

local function build(docs)
  local parts = {
    MARKER,
    "",
    "Every page of the manual, inlined. This is the same text `kuu docs`",
    "serves from inside the executable, assembled here so that everything kuu",
    "knows about itself can be read in one pass without querying anything.",
    "",
    "It is generated by `tools/bundle_docs.lua` and checked by the suite; edit",
    "the pages under `docs/`, never this part.",
    "",
  }
  for _, name in ipairs(ORDER) do
    do
      local path = docs .. "/" .. name .. ".md"
      local text = fs.read(path)
      if not text then error("no such page: " .. path) end
      parts[#parts + 1] = "---"
      parts[#parts + 1] = ""
      parts[#parts + 1] = '<a id="' .. anchor(name) .. '"></a>'
      parts[#parts + 1] = ""
      parts[#parts + 1] = rtrim(transform(text, name))
      parts[#parts + 1] = ""
    end
  end
  return table.concat(parts, "\n")
end

local here = root()
if rt.args[1] == "--write" then
  -- the pages' figures and usage first, so the bundle carries the refreshed pages
  assert(fs.write(here .. "/docs/capabilities.md", capabilities_page(here)))
  for _, name in ipairs { "docs/index.md", "README.md" } do
    local path = here .. "/" .. name
    assert(fs.write(path, with_usage(fs.read(path) or error("no " .. path), name)))
  end
end
local bundle = build(here .. "/docs")

-- Every page must be in the order, or a new page would silently go missing.
local listed = {}
for _, name in ipairs(ORDER) do listed[name] = true end
local missing = {}
for _, entry in ipairs(fs.list(here .. "/docs").entries) do
  local page = entry.name:match("^(.+)%.md$")
  if page and not listed[page] then missing[#missing + 1] = page end
end
if #missing > 0 then
  io.stderr:write("pages missing from ORDER: ", table.concat(missing, ", "), "\n")
  os.exit(1)
end

if rt.args[1] == "--write" then
  local path = here .. "/kuu.md"
  local current = fs.read(path)
  if not current then error("no kuu.md at " .. path) end
  local head = current:match("^(.-)\n" .. MARKER) or rtrim(current)
  local open_at = head:find(FIGURES_OPEN, 1, true)
  local close_at = head:find(FIGURES_CLOSE, 1, true)
  if not open_at or not close_at then
    error("kuu.md's Part I has no figures block between " .. FIGURES_OPEN .. " and " .. FIGURES_CLOSE)
  end
  head = head:sub(1, open_at - 1) .. figures(here) .. head:sub(close_at + #FIGURES_CLOSE)
  head = with_usage(head, "kuu.md")
  assert(fs.write(path, rtrim(head) .. "\n\n" .. bundle .. "\n"))
  io.write("kuu.md: Part I's figures, the usage and Part III regenerated from ", tostring(#ORDER),
    " pages; docs/capabilities.md's figures and the usage in index.md and README.md refreshed\n")
elseif rt.args[1] == "--figures" then
  io.write(figures(here), "\n")
elseif rt.args[1] == "--usage" then
  io.write(usage_block(), "\n")
elseif rt.args[1] == "--capabilities" then
  io.write(capabilities_page(here))
else
  io.write(bundle, "\n")
end
