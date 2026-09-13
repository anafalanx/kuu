-- bundle.lua -- kuu.md carries the whole manual as Part III, generated from
-- docs/.  A copy of forty pages drifts from its originals, and the copy is the
-- one people read, so the suite regenerates it and compares.
global none
global <const> require, ipairs, tostring, string, table

return function(T)
  local check = T.check
  local fs = require "fs"
  local proc = require "proc"
  local rt = require "rt"

  local root = fs.canon(T.root).path
  local generator = root .. "/tools/bundle_docs.lua"
  local document = root .. "/kuu.md"

  check("the generator is present", fs.exists(generator) == "file", generator)
  check("kuu.md is present", fs.exists(document) == "file", document)

  local r = proc.run { rt.exe, generator, timeout = "60s" }
  check("the generator runs", r ~= nil and r.status == "exit" and r.code == 0,
    r and (tostring(r.code) .. " " .. r.err) or "no result")

  if r and r.code == 0 then
    local fresh = r.out:gsub("\r\n", "\n"):gsub("%s+$", "")
    local anchors, missing, duplicate = {}, {}, nil
    for id in fresh:gmatch('<a id="([^"]+)"></a>') do
      if anchors[id] then duplicate = id end
      anchors[id] = true
    end
    for target in fresh:gmatch('%]%((#kuu%-page%-[^%)]+)%)') do
      if not anchors[target:sub(2)] then missing[#missing + 1] = target end
    end
    check("every generated manual link has an explicit destination", #missing == 0, table.concat(missing, ", "))
    check("manual destinations are unique across pages", duplicate == nil, duplicate)
    check("page links point to stable destinations despite different titles",
      fresh:find("](#kuu-page-agent)", 1, true) and anchors["kuu-page-agent"])
    check("cross-page section links keep their destination",
      fresh:find("](#kuu-page-sys-syssignature)", 1, true) and anchors["kuu-page-sys-syssignature"])
    local current = (fs.read(document) or ""):gsub("\r\n", "\n")
    local marker = "# Part III — the complete manual"
    local at = current:find(marker, 1, true)

    check("kuu.md contains Part III", at ~= nil)
    if at then
      local present = current:sub(at):gsub("%s+$", "")
      check("kuu.md's Part III matches docs/ -- run tools/bundle_docs.lua --write",
        present == fresh,
        string.format("committed %d bytes, generated %d bytes", #present, #fresh))
    end

    -- Part I's figures are produced, not written: what the executable and
    -- the tree say now must be what the file says.
    local f = proc.run { rt.exe, generator, "--figures", timeout = "60s" }
    local produced = f and f.code == 0 and f.out:gsub("\r\n", "\n"):gsub("%s+$", "") or nil
    local block = current:match("<!%-%- figures %-%->.-<!%-%- /figures %-%->")
    check("kuu.md's Part I figures are what the executable and the tree say -- run tools/bundle_docs.lua --write",
      produced ~= nil and block ~= nil and block == produced,
      (block or "no figures block") .. "\n--- vs ---\n" .. tostring(produced))

    -- capabilities.md's example carries the executable's figures, refreshed
    -- by --write and held here: a hand wrote them wrong once already.
    local c = proc.run { rt.exe, generator, "--capabilities", timeout = "60s" }
    local refreshed = c and c.code == 0 and c.out:gsub("\r\n", "\n") or nil
    local page = (fs.read(root .. "/docs/capabilities.md") or ""):gsub("\r\n", "\n")
    check("docs/capabilities.md's figures are what the executable says -- run tools/bundle_docs.lua --write",
      refreshed ~= nil and refreshed == page, c and (tostring(c.code) .. " " .. c.err) or "no result")

    -- The usage is one string, kuu --help's, quoted between markers in three
    -- places; each must be what the executable prints now.
    local u = proc.run { rt.exe, generator, "--usage", timeout = "60s" }
    local usage = u and u.code == 0 and u.out:gsub("\r\n", "\n"):gsub("%s+$", "") or nil
    for _, name in ipairs { "docs/index.md", "README.md", "kuu.md" } do
      local text = (fs.read(root .. "/" .. name) or ""):gsub("\r\n", "\n")
      local block = text:match("<!%-%- usage %-%->.-<!%-%- /usage %-%->")
      check(name .. "'s usage block is what kuu --help prints -- run tools/bundle_docs.lua --write",
        usage ~= nil and block ~= nil and block == usage, (block or "no usage block") .. "\n--- vs ---\n" .. tostring(usage))
    end

    -- Every page must appear. A page's own title is its own wording, so the
    -- count of separators is what is checked; the generator refuses outright
    -- when a page under docs/ is absent from its order.
    local pages = 0
    for _, entry in ipairs(fs.list(root .. "/docs").entries) do
      if entry.name:match("%.md$") then pages = pages + 1 end
    end
    local separators = 0
    for _ in fresh:gmatch("\n%-%-%-\n") do separators = separators + 1 end
    check("the bundle carries one section per docs page",
      pages > 0 and separators == pages,
      tostring(separators) .. " sections for " .. tostring(pages) .. " pages")

    -- The pages an agent is told to read first must actually be in there.
    -- A page's heading is its own wording, not its file name, so these are the
    -- headings rather than the stems.
    for _, heading in ipairs {
      "## Pitfalls",
      "## Adopting kuu in a repository",
      "## proc",
      "## fs",
      "## Cookbook",
    } do
      check("the bundle includes '" .. heading:sub(4) .. "'",
        fresh:find("\n" .. heading .. "\n", 1, true) ~= nil)
    end
  end
end
