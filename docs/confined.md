# Confined tools

A tool the project builds can confine itself: refuse by default what it was
not granted, and fail rather than ask. kuu names no technology for that and
recommends none; this page says what such a tool must provide, so that a
project choosing one knows what to look for, and it records the one Windows
fact any of them has to deal with.

A confined tool is still called through the door, declared in the manifest
like any other, with `reach` saying what it was granted. The door records
`reach`; it does not enforce it, because it cannot see inside a process it
did not write. Enforcement is the tool's own, and these are its terms.

## What a confined tool must provide

- **Refusal by default.** Nothing is readable, writable, or reachable unless
  granted, and a grant names the thing — a directory, a host — not a class
  of things.
- **Failure, never a prompt.** A tool that stops to ask is a tool that hangs
  under a deadline. Whatever it was not granted, it refuses with an exit code
  and a line on standard error, and runs on or stops, but never waits.
- **No way to spawn.** The door's lifetime law is a job around the tool and
  everything it starts. A tool that can start processes is a second door one
  level down, without the job's guarantees inside; a confined tool has that
  ability turned off, or is declared with it and treated as unconfined.
- **Nothing fetched at run time.** Its dependencies are vendored into the
  repository and pinned, the way the project pins everything it fetches by
  hash. A tool that resolves and downloads on first use is not confined, and
  not reproducible either.
- **Its own file access, not the shell's.** A confined tool opens files
  through its own permission check, which brings the fact below into play.

## The junction

A lexical path sandbox — an allow list of directories, a deny list, or
both — decides by the spelling of a path. Windows decides by what the path
resolves to, and the two disagree at a junction or a directory symlink:

```text
C:\work\app\build            granted
C:\work\app\build\shared  ->  D:\elsewhere            a junction inside the grant
C:\work\app\build\shared\secrets.txt                  spelled inside, resolves outside
```

Every path under the grant is allowed by its spelling, so the tool reads
`D:\elsewhere\secrets.txt` with the sandbox's blessing, and a deny list does
not help, because the spelling never names `D:\elsewhere`. This was
established on 2026-09-12, against a runtime whose permission model is
lexical, and it is a property of the model, not of the runtime.

So a project grants a directory only after looking at what it contains, and
the door supplies part of the look. `fs.dirs` reports directory reparse
points without entering them; it does not inspect file symlinks:

```lua
local fs = require "fs"
local walk = fs.dirs("build")
for _, link in ipairs(walk.links) do
  -- link.path, link.type ("junction" | "directory symlink"), link.target
  print(link.path, "->", link.target)
end
if #walk.links > 0 then
  return nil, require("err").new("PROJECT", "reach", "build holds a link out of itself; refusing to grant it")
end
```

An empty `walk.links` means the directory walk found no directory reparse
points. It does not establish that the tree is free of links: before granting
it, the project must also list the files in each returned directory and
inspect them with `fs.link`, rejecting file symlinks and any inspection failure.
The walk's own `errors` must also be checked. A directory that legitimately
holds a link is granted with that named, or not at all. The complete preflight
is the project's to run, before the grant, every time:
a junction can be made after the check as easily as before it, which is one
more reason `reach` is a declaration and not a promise.

## What the record says

The evidence for the figures a confined runtime costs — startup, footprint,
the round trip of a call — was measured once, on one runtime, and lives in
the repository's notes rather than here, because a number for one technology
is not a fact about confinement. The manual names no runtime; a project that
chooses one owns the choice and the measurement.
