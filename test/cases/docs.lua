-- docs.lua -- `kuu docs`, a verb like the others: the page list with a
-- sentence per page, one page, one section, a search over every page, --json
-- for each, --help, and the unknown-option law; rt.page for a program.
global none
global <const> require, ipairs, type, table

return function(T)
  local check, contains = T.check, T.contains
  local fs, json, rt = require "fs", require "json", require "rt"
  local root = fs.canon(T.root).path

  -- the list
  local r = T.kuu { "docs" }
  check("kuu docs lists every page with its first sentence and says where to start",
    r.code == 0 and contains(r.out, "kuu " .. rt.version .. " manual") and contains(r.out, "  agent           What is expected of you")
      and contains(r.out, "  proc            Children with decided lifetimes.") and contains(r.out, "Start with agent"), T.describe(r))
  r = T.kuu { "docs", "--json" }
  local listing = r.code == 0 and json.decode(r.out) or nil
  local pages = listing and listing.result.pages or {}
  local by = {}
  for _, p in ipairs(pages) do by[p.name] = p end
  check("--json lists the pages with name, description and lines, as many as rt.pages",
    listing ~= nil and listing.ok == true and #pages == #rt.pages() and by.agent ~= nil
      and by.agent.description:sub(1, 24) == "What is expected of you " and type(by.agent.lines) == "number" and by.agent.lines > 50, r.out:sub(1, 300))
  local plain = true
  for _, p in ipairs(pages) do
    if p.description == "" or p.description:match("^`[^`]*`%s*$") or p.description:match("^```") or p.description:match("^|") or p.description:find("**", 1, true) then
      plain = false
    end
  end
  check("every description is a sentence of prose, never a code line, a table row or raw emphasis", plain,
    by.pty and by.pty.description or "?")

  -- one page
  r = T.kuu { "docs", "proc" }
  check("kuu docs PAGE prints the page as it is under docs/", r.code == 0 and r.out:gsub("\r\n", "\n") == (fs.read(root .. "/docs/proc.md") or ""):gsub("\r\n", "\n"), T.describe(r))
  r = T.kuu { "docs", "proc", "--json" }
  local page = r.code == 0 and json.decode(r.out) or nil
  local headings = {}
  for _, s in ipairs(page and page.result.sections or {}) do headings[#headings + 1] = s.anchor end
  check("--json carries the page's text and its sections with anchors and lines",
    page ~= nil and page.result.name == "proc" and contains(page.result.text, "# proc") and contains(table.concat(headings, " "), "errors")
      and type(page.result.sections[1].line) == "number", r.out:sub(1, 200))

  -- one section, by heading, by prefix, by anchor
  r = T.kuu { "docs", "proc", "errors" }
  check("kuu docs PAGE SECTION prints one ## section, from its heading to the next",
    r.code == 0 and r.out:match("^## Errors\n") ~= nil and contains(r.out, "| PROC code |") and not contains(r.out, "## Two things"), T.describe(r))
  r = T.kuu { "docs", "sched#deadlines" }
  local by_anchor = r
  r = T.kuu { "docs", "sched", "Deadlines" }
  check("PAGE#anchor and PAGE SECTION name the same section, ignoring case", by_anchor.code == 0 and r.code == 0 and by_anchor.out == r.out
    and contains(r.out, "## Deadlines"), T.describe(by_anchor) .. T.describe(r))
  -- a heading inside a fenced block is text: the agent page's sample entry
  r = T.kuu { "docs", "agent", "reporting" }
  check("a section runs past a fenced `## ` line to the real next heading",
    r.code == 0 and contains(r.out, "## 2026-09-13") and contains(r.out, "The heading is `## YYYY-MM-DD")
      and not contains(r.out, "## The short form"), T.describe(r))
  r = T.kuu { "docs", "agent", "--json" }
  local agent = r.code == 0 and json.decode(r.out) or nil
  local anchors = {}
  for _, s in ipairs(agent and agent.result.sections or {}) do anchors[#anchors + 1] = s.anchor end
  check("and is not listed among the page's sections",
    table.concat(anchors, " ") == "arriving try-an-inline-command running writing reporting-back the-short-form", table.concat(anchors, " "))
  -- GitHub's anchor spelling: punctuation dropped
  r = T.kuu { "docs", "proc", "proclist-procfind-proctree" }
  check("an anchor drops punctuation the way the manual's links do", r.code == 0 and contains(r.out, "## proc.list, proc.find, proc.tree"), T.describe(r))
  r = T.kuu { "docs", "proc", "errors", "extra" }
  check("a third word is a usage error", r.code == 2 and contains(r.err, "CLI usage: unexpected argument 'extra'"), T.describe(r))
  r = T.kuu { "docs", "proc#errors", "streams" }
  check("a section word beside a #anchor is a usage error", r.code == 2 and contains(r.err, "CLI usage: unexpected argument 'streams'"), T.describe(r))
  r = T.kuu { "docs", "proc", "nosuch" }
  check("an unknown section is ENTRY notfound naming the sections", r.code == 2 and contains(r.err, "ENTRY notfound: no section 'nosuch' in page 'proc'")
    and contains(r.err, "errors"), T.describe(r))
  r = T.kuu { "docs", "nosuchpage" }
  check("an unknown page is ENTRY notfound, as before", r.code == 2 and contains(r.err, "ENTRY notfound: no manual page 'nosuchpage'; kuu docs lists them"), T.describe(r))

  -- search: every word, literally, ignoring case
  r = T.kuu { "docs", "search", "decided lifetimes" }
  check("search takes all its words and finds the line", r.code == 0 and contains(r.out, "proc:3: Children with decided lifetimes."), T.describe(r))
  check("a hit before the first section points to the page, not its top-level title",
    contains(r.out, "  Read: kuu docs proc\n") and not contains(r.out, "  Read: kuu docs proc proc"), T.describe(r))
  r = T.kuu { "docs", "search", "fs.read" }
  local reading_hint = "  Read: kuu docs fs reading-and-writing\n"
  local hint_count = 0
  for line in r.out:gmatch("[^\n]+") do
    if line == "  Read: kuu docs fs reading-and-writing" then hint_count = hint_count + 1 end
  end
  check("search gives one retrieval command for repeated hits in a section",
    r.code == 0 and contains(r.out, reading_hint) and hint_count == 1
      and r.out:match("fs:%d+: local bytes = fs.read") ~= nil, T.describe(r))
  local hint_page, hint_section = r.out:match("  Read: kuu docs (fs) (reading%-and%-writing)\n")
  local retrieved = hint_page and T.kuu { "docs", hint_page, hint_section } or nil
  check("the fs.read search command retrieves its enclosing explanation",
    retrieved ~= nil and retrieved.code == 0 and retrieved.out:match("^## Reading and writing\n") ~= nil
      and contains(retrieved.out, "fs.read(") and not contains(retrieved.out, "## Facts about a path"),
    retrieved and T.describe(retrieved) or T.describe(r))
  r = T.kuu { "docs", "search", "fs.set_attributes" }
  check("attribute search names the retrievable API contract",
    r.code == 0 and contains(r.out, "  Read: kuu docs fs file-attributes\n"), T.describe(r))
  retrieved = T.kuu { "docs", "fs", "file-attributes" }
  check("attribute section exposes mutation, link defaults and permission boundaries together",
    retrieved.code == 0 and retrieved.out:match("^## File attributes\n") ~= nil
      and contains(retrieved.out, "fs.set_attributes(path, { readonly = false, hidden = true })")
      and contains(retrieved.out, "`follow=false`") and contains(retrieved.out, "not_content_indexed: boolean")
      and contains(retrieved.out, "does **not** test write") and contains(retrieved.out, "`temporary=true`")
      and not contains(retrieved.out, "## Making and removing"), T.describe(retrieved))
  r = T.kuu { "docs", "search", "## 2026-09-13" }
  check("a matching heading inside a fence points to its real enclosing section",
    r.code == 0 and contains(r.out, "  Read: kuu docs agent reporting-back\n")
      and not contains(r.out, "  Read: kuu docs agent 2026-09-13"), T.describe(r))
  r = T.kuu { "docs", "search", "DECIDED LIFETIMES" }
  check("search ignores case", r.code == 0 and contains(r.out, "proc:3:"), T.describe(r))
  r = T.kuu { "docs", "search", "task.exec {" }
  check("search is literal, not a pattern", r.code == 0 and contains(r.out, "task.exec {") and not contains(r.err, "pattern"), T.describe(r))
  r = T.kuu { "docs", "search", "xyzzy-nothing-says-this" }
  check("a search with no hit says so and exits 0", r.code == 0 and contains(r.out, "nothing in the manual mentions 'xyzzy-nothing-says-this'"), T.describe(r))
  r = T.kuu { "docs", "search", "--json", "decided lifetimes" }
  local hits = r.code == 0 and json.decode(r.out) or nil
  local proc_hit
  for _, h in ipairs(hits and hits.result.hits or {}) do if h.page == "proc" and h.line == 3 then proc_hit = h end end
  check("--json search carries page, line, the enclosing heading and the text",
    hits ~= nil and hits.result.text == "decided lifetimes" and proc_hit ~= nil and proc_hit.heading == "proc"
      and contains(proc_hit.text, "decided"), r.out:sub(1, 300))
  r = T.kuu { "docs", "search" }
  check("search without text is a usage error", r.code == 2 and contains(r.err, "usage"), T.describe(r))
  r = T.kuu { "docs", "search", "" }
  local blank = T.kuu { "docs", "search", "  " }
  check("search with blank text is the same usage error, not the whole manual",
    r.code == 2 and contains(r.err, "ENTRY usage") and blank.code == 2, T.describe(r))
  r = T.kuu { "docs", "search", " decided lifetimes " }
  check("the text is trimmed before it is looked for", r.code == 0 and contains(r.out, "proc:3:"), T.describe(r))

  -- a verb like the others
  r = T.kuu { "docs", "--help" }
  check("--help prints the usage and exits 0", r.code == 0 and contains(r.out, "usage: kuu docs") and contains(r.out, "search TEXT"), T.describe(r))
  r = T.kuu { "docs", "--bogus" }
  check("an unknown option is CLI usage, exit 2", r.code == 2 and contains(r.err, "CLI usage: unknown option '--bogus'"), T.describe(r))
  check("docs is one of the verbs the executable carries", contains(table.concat(rt.verbs(), " "), "docs"))

  -- rt.page for a program with no shell
  local text = rt.page("agent")
  check("rt.page gives a page's text, and nil for no such page",
    type(text) == "string" and contains(text, "# For the agent") and rt.page("nosuch") == nil and rt.page("../lua/task") == nil)

  -- every module page's code-set section is headed Errors, so PAGE errors works everywhere
  local odd = {}
  for _, name in ipairs(rt.pages()) do
    for line in (rt.page(name) or ""):gmatch("[^\n]+") do
      local heading = line:match("^## (.+)$")
      if heading and heading:lower():match("error") and heading ~= "Errors" and name ~= "index" and name ~= "pitfalls"
        and not name:match("^upgrading") and name ~= "shortcomings" and name ~= "cookbook" then
        odd[#odd + 1] = name .. ": " .. heading
      end
    end
  end
  check("every module page heads its code set `## Errors`", #odd == 0, table.concat(odd, "; "))
end
