-- bundle.lua -- kuu.md carries the whole manual as Part III, generated from
-- docs/.  A copy of forty pages drifts from its originals, and the copy is the
-- one people read, so the suite regenerates it and compares.
global none
global <const> require, ipairs, tostring, string

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
