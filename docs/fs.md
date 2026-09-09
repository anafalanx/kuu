# fs

Files and directories as Windows actually has them.

```lua
local fs = require("fs")
```

Paths in are UTF-8 with either separator. Paths out are absolute, with
forward slashes. Every path is normalised and given the `\\?\` prefix before
Windows sees it, so paths beyond 260 characters simply work. Refused by name,
because Windows would silently make them mean something else: a
drive-relative path such as `C:foo`, a device path, and a component ending in
`.` or a space. Refusals of the path itself raise `FS badvalue`; a path that is
not there is `nil, err` with `FS notfound`.

## Reading and writing

```lua
local bytes = fs.read("build/kuu.exe")                     -- bytes, up to 1 GiB
local text  = fs.read("notes.md", { encoding = "utf-8" })   -- BOM dropped, strictly validated
local old   = fs.read("robocopy.log", { encoding = "cp1252" })
fs.read(path, { maxbytes = "16M" })                        -- nil, FS toobig above that

fs.write("out/result.json", data)                    -- atomic: temp file beside, then rename
fs.write("build/log.txt", line, { append = true })   -- appended in place
fs.write(path, data, { atomic = false })             -- plain overwrite
```

An atomic write leaves either the old bytes or all of the new ones, never a
torn file. It creates `name.kuu-<pid>-<tick>.tmp` in the same directory and
renames it over the target, which a watcher sees as an added temporary file
and a rename.

## Facts about a path

```lua
fs.exists(p)   -- "file" | "directory" | "link" | "other" | false; the name itself, never its target
fs.stat(p)     -- follows links: { kind, size, mtime, ctime, atime, attrs, hidden, readonly,
               --   system, reparse, volume, file, links }
fs.stat(p, { follow = false })   -- the link itself: kind "link", reparse "0xa0000003"
fs.canon(p)    -- { path, volume, file, kind, links }: where it really lives and what it is
fs.same(a, b)  -- true when two paths name one object, through any links
fs.link(p)     -- false, or { type = "junction" | "directory symlink" | "file symlink", target, tag }
```

Times are seconds since the Unix epoch, as numbers. `volume` and `file` are
sixteen-character hex tokens: identity is compared, never computed. A junction
or symlink whose target is gone is `nil, err` with `FS dangling`, distinct from
`notfound`, because a resolver may continue past a missing name but must stop
at an existing broken link.

## Making and removing

```lua
fs.mkdir("build/out/deep")                  -- parents created; existing is fine
fs.remove("build/out/deep/file.txt")
fs.remove("build/out", { recursive = true })
fs.rename(from, to, { replace = true })
fs.copy(from, to, { replace = true })
```

`remove` without `recursive` on a non-empty directory is `FS notempty`. A
recursive remove never follows a junction or symlink: the link is removed as a
link and its target is untouched. Read-only files are removed.

## Listing and walking

```lua
local l = fs.list("src")
for _, e in ipairs(l.entries) do print(e.name, e.kind, e.size, e.mtime) end
#l.errors        -- names that could not be represented, listings cut short

local d = fs.dirs("C:/work", { depth = 3, prune = { "node_modules", ".git" } })
d.root           -- as walked
d.paths          -- every directory, depth-first, siblings in UTF-8 byte order
d.dirs           -- == #d.paths
d.links          -- { path, tag, surrogate, action, type, target } per reparse point
d.errors         -- { path, win32, reason } per branch that could not be read
d.pruned, d.depthlimited, d.maxdepth
```

`dirs` lists directories only; junctions and symlinks are listed and not
entered, and their `links` row says so (`action = "nofollow"`). Hidden
directories are included. Nothing is omitted silently: a branch that could not
be read is an `errors` row with the raw Windows code, and the counts add up.
`depth` omitted is unlimited; `depth = 0` is the root alone. Prune patterns
use `*` and `?`, match base names, and ignore case.

## Watching

```lua
local w <close> = fs.watch("src", { recursive = true })
local events, e = w:read("30s")       -- nil, FS timeout when nothing changed
for _, ev in ipairs(events) do print(ev.action, ev.path, ev.from) end
w:info()                              -- { directory, recursive, pending, dropped, armed }
```

Actions are `added`, `removed`, `modified`, `renamed` (with `from`), and
`overflow`. Paths are relative to the watched directory with forward slashes.
A read returns the first batch the system delivered; changes made over time
arrive over several reads. Within a batch, one path gets one event, by
precedence removed, added, renamed, modified, unless `raw = true` asks for
every notification. The watch is armed before `fs.watch` returns. When
`overflow` appears or `dropped` grows, the system could not describe every
change: reconcile from `fs.list` or `fs.dirs`.

## Paths as strings

```lua
fs.join("build", "out\\", "/app.exe")   -- "build/out/app.exe": either separator in, "/" out
fs.join("a", "C:/x", "y")               -- "C:/x/y": a drive or a share starts over
fs.dirname("a/b/c.txt")                 -- "a/b"; "." for a bare name; a root stays a root
fs.basename("a/b/c.txt")                -- "c.txt"
fs.ext("a/b.tar.gz")                    -- ".gz"; "" for ".gitignore"
fs.stem("a/b.tar.gz")                   -- "b.tar"
fs.relative("C:/work/app/src/x.c", "C:/work/app")   -- "src/x.c"; ".." as needed; case ignored
```

None of these touch the disk except `relative`, which makes both paths
absolute first and returns the absolute path when they share no root.

```lua
local paths, errors = fs.glob("src/**/*.c")           -- sorted; relative when the pattern is
fs.glob("C:/work/**", { kind = "directory" })         -- or "file"
```

`*` and `?` match within one name, `?` one character, and case is folded the
way Windows folds file names, so `É*.TXT` finds `é.txt`; `**` as a whole
component matches any number of directories, including none.
Links are matched by name but never entered. Each directory that could not be
listed is one entry of `errors`, with `path` and `message`, and the rest of
the results stand.

## Places

```lua
fs.cwd()          -- the current directory
fs.chdir(p)       -- change it, for the whole process: every task and every child started afterwards
fs.temp()         -- the temporary directory
fs.absolute(p)    -- the normalised absolute spelling of p
fs.tempfile { dir = "build", prefix = "kuu-", suffix = ".tmp" }   -- a new empty file, uniquely named; every field optional
fs.tempdir { dir = "build", prefix = "kuu-" }                     -- a new empty directory
fs.space("C:/")   -- { total, free, available } in bytes; available is what this user may still use
```

Temporary names are created exclusively, so two callers never receive the
same one. Both default to the temporary directory and to the prefix `kuu-`.
A prefix or suffix with a separator, and a suffix ending in a dot or a space,
which Windows would create and then never name the same way again, are
refused before anything is created.

## Errors

| FS code | when |
|---|---|
| `notfound` | the path is not there |
| `dangling` | the path is a link whose target is not there |
| `access` | denied, or the file is in use |
| `exists` | the target exists and `replace` was not given, or `mkdir` met a file |
| `notempty` | `remove` on a non-empty directory without `recursive` |
| `toobig` | `read` above `maxbytes` |
| `encoding` | a name cannot be represented |
| `badvalue` | raised for a refused path or option value; `nil, err` for a wrong kind of object |
| `usage` | raised: an unknown option |
| `timeout` | `watch:read` waited its whole duration |
| `closed` | raised: a closed watch was used |
| `oserror` | anything else, with the Windows message |
