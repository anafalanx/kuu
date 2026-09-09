-- fs/path.lua -- the string half of fs: joining, splitting, relating, and
-- matching paths.  Installed into the fs table when the module opens.
-- Nothing here touches the disk except glob and relative, which list and
-- resolve.  Separators in are either kind; separators out are "/".
global none
global <const> require, ipairs, tostring, type, string, table, error, select

return function(fs)
  local err = require "err"

  local function slashes(p) return (p:gsub("\\", "/")) end

  -- The root of a path with "/" separators: "C:/", "//server/share/", "/",
  -- or "" for a relative path.
  local function root_of(p)
    local drive = p:match("^(%a:)/")
    if drive then return drive .. "/" end
    if p:match("^%a:$") then return p .. "/" end
    local server, share = p:match("^//([^/]+)/([^/]+)")
    if server then return "//" .. server .. "/" .. share .. "/" end
    if p:sub(1, 1) == "/" then return "/" end
    return ""
  end

  local function split(p)
    p = slashes(p)
    local root = root_of(p)
    local comps = {}
    for c in p:sub(#root + 1):gmatch("[^/]+") do comps[#comps + 1] = c end
    return root, comps
  end

  local function under(shown, name)
    if shown == "" then return name end
    if shown:sub(-1) == "/" then return shown .. name end
    return shown .. "/" .. name
  end

  -- fs.join(piece, ...) -> the pieces joined with "/".  A piece with a drive
  -- or a share starts over; a leading separator on a later piece is dropped,
  -- as PowerShell's Join-Path does.
  function fs.join(...)
    local out = ""
    for i = 1, select("#", ...) do
      local piece = select(i, ...)
      if type(piece) ~= "string" then error(err.new("FS", "badvalue", "join takes strings"), 2) end
      piece = slashes(piece)
      if piece ~= "" then
        if out == "" or piece:match("^%a:") or piece:match("^//[^/]") then
          out = piece:match("^%a:$") and (piece .. "/") or piece
        else
          out = under(out, (piece:gsub("^/+", "")))
        end
      end
    end
    return out
  end

  -- fs.dirname("a/b/c.txt") -> "a/b"; of a bare name "."; of a root, the root
  function fs.dirname(p)
    if type(p) ~= "string" then error(err.new("FS", "badvalue", "dirname takes a string"), 2) end
    local root, comps = split(p)
    if #comps <= 1 then return root ~= "" and root or "." end
    return root .. table.concat(comps, "/", 1, #comps - 1)
  end

  -- fs.basename("a/b/c.txt") -> "c.txt"; of a root, ""
  function fs.basename(p)
    if type(p) ~= "string" then error(err.new("FS", "badvalue", "basename takes a string"), 2) end
    local _, comps = split(p)
    return comps[#comps] or ""
  end

  -- fs.ext("a/b.tar.gz") -> ".gz"; a name that is only a dot-prefix, ".gitignore", has none
  function fs.ext(p)
    local base = fs.basename(p)
    return base:match("^.+(%.[^.]*)$") or ""
  end

  -- fs.stem("a/b.tar.gz") -> "b.tar"
  function fs.stem(p)
    local base = fs.basename(p)
    local ext = fs.ext(p)
    return base:sub(1, #base - #ext)
  end

  -- fs.relative(path [, base]) -> path relative to base (default: the current
  -- directory), or the absolute path when they share no root.  Case is ignored
  -- when comparing, as the file system does.
  function fs.relative(p, base)
    local target = fs.absolute(p)
    local from = fs.absolute(base or fs.cwd())
    local troot, tcomps = split(target)
    local froot, fcomps = split(from)
    if troot:lower() ~= froot:lower() then return target end
    local i = 1
    while i <= #tcomps and i <= #fcomps and tcomps[i]:lower() == fcomps[i]:lower() do i = i + 1 end
    local parts = {}
    for _ = i, #fcomps do parts[#parts + 1] = ".." end
    for k = i, #tcomps do parts[#parts + 1] = tcomps[k] end
    if #parts == 0 then return "." end
    return table.concat(parts, "/")
  end

  -- glob -------------------------------------------------------------------

  local function has_wild(c) return c:find("[*?]") ~= nil end

  -- A glob component as an anchored Lua pattern over a lower-cased name.
  local function to_pattern(c)
    local out = { "^" }
    for ch in c:gmatch(".") do
      if ch == "*" then out[#out + 1] = ".*"
      elseif ch == "?" then out[#out + 1] = "."
      elseif ch:match("%w") then out[#out + 1] = ch:lower()
      else out[#out + 1] = "%" .. ch end
    end
    out[#out + 1] = "$"
    return table.concat(out)
  end

  -- fs.glob(pattern [, { kind = "file" | "directory" }]) -> paths, errors
  -- `*` and `?` match within a name, case-insensitively; `**` as a whole
  -- component matches any number of directories, including none.  Results
  -- are sorted, relative when the pattern is, and never enter links.  Every
  -- directory that could not be listed is one entry of `errors`.
  function fs.glob(pattern, options)
    options = options or {}
    if type(pattern) ~= "string" or pattern == "" then error(err.new("FS", "badvalue", "glob needs a pattern"), 2) end
    local kind = options.kind
    if kind ~= nil and kind ~= "file" and kind ~= "directory" then
      error(err.new("FS", "badvalue", "kind must be \"file\" or \"directory\""), 2)
    end
    local root, comps = split(pattern)
    if #comps == 0 then error(err.new("FS", "badvalue", "the pattern names nothing below its root"), 2) end
    local results, seen, errors = {}, {}, {}
    local function accept(path, k)
      if kind ~= nil and k ~= kind then return end
      local key = path:lower()
      if not seen[key] then
        seen[key] = true
        results[#results + 1] = path
      end
    end
    local function entries_of(dir)
      local listing, e = fs.list(dir == "" and "." or dir)
      if not listing then
        errors[#errors + 1] = { path = dir == "" and "." or dir, message = tostring(e) }
        return {}
      end
      table.sort(listing.entries, function(a, b) return a.name < b.name end)
      return listing.entries
    end
    local function walk(dir, shown, i)
      local comp = comps[i]
      local last = i == #comps
      if comp == "**" then
        if not last then walk(dir, shown, i + 1) end
        for _, e in ipairs(entries_of(dir)) do
          local sub = under(shown, e.name)
          if last then accept(sub, e.kind) end
          if e.kind == "directory" then walk(fs.join(dir, e.name), sub, i) end
        end
        return
      end
      if not has_wild(comp) then
        local next_dir = fs.join(dir, comp)
        local k = fs.exists(next_dir)
        if not k then return end
        local sub = under(shown, comp)
        if last then accept(sub, k) elseif k == "directory" then walk(next_dir, sub, i + 1) end
        return
      end
      local pat = to_pattern(comp)
      for _, e in ipairs(entries_of(dir)) do
        if e.name:lower():match(pat) then
          local sub = under(shown, e.name)
          if last then accept(sub, e.kind) elseif e.kind == "directory" then walk(fs.join(dir, e.name), sub, i + 1) end
        end
      end
    end
    walk(root, root, 1)
    table.sort(results)
    return results, errors
  end
end
