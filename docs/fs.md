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
`.` or a space. Refused path spellings raise `FS badvalue`; invalid UTF-8 raises
`FS encoding`. A path that is not there is `nil, err` with `FS notfound`.

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
torn file. It creates `.kuu-<32 random hex digits>.tmp` in the same directory and
renames it over the target, which a watcher sees as an added temporary file
and a rename.

The rename is retried, up to six attempts over a few tens of milliseconds,
when it fails with access denied or a sharing violation. On Windows a scanner
or an indexer routinely opens a file the moment its handle closes, and the
rename of a freshly written temporary loses that race: 15 of 2000
single-process writes failed that way on the owner's machine before the retry,
and none of 4000 after. The retry bypasses no permission — a target that
genuinely cannot be replaced still fails with `FS access`, only later — and it
does not weaken atomicity, because each attempt either replaced the target or
left it alone. A target somebody holds open for longer than that window still
fails, and that is the intended answer rather than a defect.

`rename` and `copy` retry the same way, since 0.10.0, for the same two
errors and the same bound. 0.9.0 gave the retry to the atomic write alone,
and the intermittent failures the suite kept seeing were exactly the two
calls it had not reached.

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

## File attributes

`fs.attributes` inspects Windows file attributes; `fs.set_attributes` patches
named flags on an existing file, directory or reparse object. These calls are
available from [0.12](upgrading-from-0.11.md); use `rt.version_at_least(0, 12)`
when a project depends on them. For an existing file:

```lua
local path = "build/output.bin"
local flags = assert(fs.attributes(path))
print(flags.attrs, flags.readonly, flags.hidden)
assert(fs.set_attributes(path, { readonly = false, hidden = true }))

local target = assert(fs.attributes(path, { follow = true }))
assert(fs.set_attributes(path, { archive = false }, { follow = true }))
```

The getter returns a table with all seven fields present:

```typescript
type Attributes = {
  attrs: number; // complete unsigned 32-bit Windows mask, as an integer
  readonly: boolean; hidden: boolean; system: boolean; archive: boolean;
  temporary: boolean; not_content_indexed: boolean;
};
```

It is a detached snapshot: assigning `flags.hidden` changes only the Lua
table. A setter patch accepts the six named booleans; `true` sets a flag,
`false` clears it, and omitted/nil fields preserve the queried value. The raw
`attrs` mask is inspection only. Passing it back as a patch, or naming `normal`,
directory/reparse bits, compression, encryption or sparse allocation, is an
error. Unrelated native bits are preserved, including when all mutable flags
are cleared. The setter returns `true` on success.

Both calls default to **`follow=false` for the final path component**, selecting
the link itself; `{follow=true}` selects its target. `fs.stat` keeps its
existing following default. Linked ancestors may still be traversed, so this
selection does not confine access to a directory. A failed nofollow call never
silently retries against the target.

An empty patch, `fs.set_attributes(path, {})`, opens and reads metadata,
validates the selected object, and makes no write. It does **not** test write
permission. Every nonempty patch requests read/write-attribute access, even
if its values are already set; an unchanged effective mask skips the native
setter after that check. Only attribute access is requested, not permission
to read or write file contents.

`temporary=true` on a directory returns `nil, FS badvalue` before any part of
the patch is written. This also applies to directory links selected without
following. `temporary=false` is allowed on directories. File attributes are
separate from ACL permissions: a directory's readonly flag is not a general
write-permission control, though it can prevent removal. These calls do not
create paths, recurse, change ACLs or create links. Successfully opened
non-disk objects return `nil, FS badvalue`; other provider failures keep their
native error classification.

Paths must actually be UTF-8 strings; numbers are not coerced. A patch must be
a table, and options must be a table or nil. Only stored table entries count:
`__index`, `__pairs` and other metatable behavior do not supply fields.
Unknown, numeric or embedded-NUL keys raise `FS usage`. Every present flag
and `follow` must be a boolean; other values raise `FS badvalue`. Wrong
argument types raise Lua argument errors. Invalid UTF-8 raises `FS encoding`;
empty paths, malformed path spellings and paths containing NUL raise
`FS badvalue`. Validation happens before native handles are acquired.

Environmental failures return `nil, err`. Missing ordinary paths are
`FS notfound`; permission or sharing denial is `FS access`. `FS dangling`
requires a followed open to fail with native file/path-not-found, followed by
a successful nofollow query confirming a name-surrogate link at the final
component. Otherwise the original error is kept, including access denied.
That diagnosis uses separate observations and can race with path replacement.

Each update reads and patches through the same handle, keeping it attached to
the selected object if the path is renamed. It does not atomically merge
concurrent attribute writers: preservation refers to the state read by this
call. File contents are unchanged. This call does not explicitly rewrite
creation, access or write times; the filesystem's metadata change time may
advance.
`fs.stat().ctime` is creation time, not that change time.

## Making and removing

```lua
fs.mkdir("build/out/deep")                  -- parents created; existing is fine
fs.mkdir("build/out", { parents = false })  -- the parent must already exist
fs.remove("build/out/deep/file.txt")
fs.remove("build/out", { recursive = true })
fs.rename(from, to, { replace = true })
fs.copy(from, to, { replace = true })
```

`remove` without `recursive` on a non-empty directory is `FS notempty`. A
recursive remove never follows a junction or symlink: the link is removed as a
link and its target is untouched. Read-only files and directories are removed:
the readonly bit is cleared on the selected object before deletion, and a
failure to clear it is reported. Removal is nontransactional: earlier entries
may already be gone, and a cleared readonly bit can remain clear if deletion
later fails. Attribute clearing does not change a link target. Do not race
removal against path replacement; linked ancestors are not a containment boundary.
Readonly-directory handling here requires 0.12 or later.

For longer, scheduler-friendly retries, use the project's
[bounded publication and cleanup recipe](cleanup.md). It retries `FS access`
under one budget per tree operation and preserves primary and cleanup failures.

## Listing and walking

```lua
local l = fs.list("src")
for _, e in ipairs(l.entries) do print(e.name, e.kind, e.size, e.mtime) end
#l.errors        -- names that could not be represented, listings cut short

local d = fs.dirs("C:/work", { prune = { "node_modules", ".git" } })
d.root           -- as walked
d.paths          -- directory paths, including link/depth frontiers; depth-first, siblings in UTF-8 byte order
d.dirs           -- == #d.paths
d.skipped        -- the directories a prune pattern excluded; never in d.paths
d.links          -- { path, tag, surrogate, action, type, target } per reparse point
d.errors         -- { path, win32, reason } per branch that could not be read
d.pruned, d.depthlimited, d.maxdepth
```

`dirs` lists directories only; junctions and symlinks are listed and not
entered, and their `links` row says so (`action = "nofollow"`). Hidden
directories are included. Nothing is omitted silently: a branch that could not
be read is an `errors` row with the raw Windows code, and the counts add up.
`depth` omitted is unlimited; `depth = 0` is the root alone. Prune patterns
use `*` and `?`, match base names, and ignore case; at most 64 are accepted.

**A pruned directory is not in `paths`.** It was excluded by name, so it is
reported in `skipped` and `pruned` instead, including at the depth limit
(where pruning takes precedence over `depthlimited`).

Directory links remain in `paths`, however. Listing one would follow its
target despite the walk's refusal to enter it. For the unlimited walk above,
also honor the walk's `nofollow` decisions when listing discovered directories:

```lua
local nofollow = {}
for _, link in ipairs(d.links) do
  if link.action == "nofollow" then nofollow[link.path] = true end
end
for _, dir in ipairs(d.paths) do
  if not nofollow[dir] then
    local listing, why = fs.list(dir)
    -- Handle a nil listing and listing.errors before treating it as complete.
    if listing then
      for _, e in ipairs(listing.entries) do
        -- e.kind == "link" identifies file/directory name-surrogate links.
        -- Inspect ordinary entries here.
      end
    end
  end
end
```

Use `action`, rather than rejecting all reparse metadata: filter/cloud
directories can be ordinary content. A linked starting directory is followed
deliberately and reported with `action = "descended"` when successfully read.

Through 0.8 a pruned directory appeared in `paths` and only its descent was
skipped, so that loop listed the files of every excluded directory. Two
independent programs made exactly that mistake. A directory stopped by the
`depth` cap, or a link not followed, does stay in `paths`: those are the
frontier the walk was asked to stop at, not names it was asked to exclude.
See [upgrading to 0.9](upgrading-0.9.md).

## Watching

```lua
local w <close> = fs.watch("src", { recursive = true })
local events, e = w:read("30s")       -- nil, FS timeout when nothing changed
for _, ev in ipairs(events) do print(ev.action, ev.path, ev.from) end
w:info()                              -- { directory, recursive, pending, dropped, armed }
```

The options are `recursive` (default true) and `raw` (default false).

Actions are `added`, `removed`, `modified`, `renamed` (with `from`), and
`overflow`. Paths are relative to the watched directory with forward slashes.
A read returns the first batch the system delivered; changes made over time
arrive over several reads. Within a batch, one path gets one event, by
precedence removed, added, renamed, modified, unless `raw = true` asks for
every notification. The watch is armed before `fs.watch` returns. When
`overflow` appears or `dropped` grows, the system could not describe every
change: reconcile from `fs.list` or `fs.dirs`.

Concurrent readers compete for batches in the order they started waiting.
One reader receives each batch; the others remain parked for later changes
or their own timeout. Events are not broadcast. Closing the watch wakes all
waiting readers with `FS closed`.

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
| `encoding` | a name cannot be represented, or a path is not valid UTF-8 |
| `badvalue` | raised for a refused path, a path or name holding NUL, or an option/attribute value; `nil, err` for a wrong kind of object — a directory given to `read`, a file given to `list`, a non-disk attribute handle, or `temporary=true` on a directory |
| `usage` | raised: an unknown option or attribute patch key |
| `timeout` | `watch:read` waited its whole duration |
| `closed` | raised: a closed watch was used |
| `oserror` | anything else, with the Windows message |

`read` with `encoding` keeps conversion failures in the `TEXT` domain, as
documented in [text](text.md). A surrounding `sched.deadline` can interrupt
a watch read with `SCHED deadline`; it does not preempt synchronous file I/O.
