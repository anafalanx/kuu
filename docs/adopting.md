# Adopting kuu in a repository

How a repository comes to be driven by kuu: one executable of its own, one
`tasks.lua`, and a list of prerequisites it fetches itself. Nothing is
installed on the machine, nothing is shared between repositories, and
nothing is looked up on `PATH`.

```text
repo/
  tasks.lua          the tasks, and the prerequisites as url and sha256
  .tools/            kuu.exe, downloads, unpacked tools; git ignores it
  .kuu/              kuu's notebook for this repository (mem); git ignores it
  build/             outputs; git ignores it
  src/               whatever the repository is about
```

## 1. Give the repository its kuu

Copy `kuu.exe` into `.tools\`. It comes from a
[release](https://github.com/anafalanx/kuu/releases), signed, with a
`kuu.exe.sha256` beside it, or from a build. That copy is the only kuu this
repository knows; another repository has its own, possibly another
version. There is no installer and no bootstrap script, because copying a
small file needs neither.

Add to `.gitignore`:

```text
/.tools/
/.kuu/
/build/
```

## 2. Write tasks.lua

`tasks.lua` sits at the repository root. It states the kuu it was written
for, lists what the repository needs, and declares the tasks. [Tasks](task.md)
has the full contract; this is the shape:

```lua
global none
global <const> require, ipairs, print

local KUU = "0.5" -- the kuu this repository was made for

local rt = require "rt"
local task = require "task"
local http = require "http"
local archive = require "archive"
local proc = require "proc"
local fs = require "fs"
local hash = require "hash"
local err = require "err"

if rt.version ~= KUU then
  error(err.new("PROJECT", "version", "made for kuu " .. KUU .. ", this is " .. rt.version .. "; copy the right kuu.exe into .tools"))
end

-- What this repository needs, by url and hash.  Nothing else is looked up anywhere.
local PACKAGES = {
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-make-4.4.1-5-any.pkg.tar.zst",
    sha256 = "871f760657a360279f29b945a7fd7d9655fe46a3e1e06dd783c9e74514aa0b27" },
}
local MAKE = ".tools/msys2/ucrt64/bin/mingw32-make.exe"

task "prereqs" {
  desc = "fetch the tools by hash into .tools",
  run = function()
    if fs.exists(MAKE) == "file" then return end
    fs.mkdir(".tools/downloads")
    for _, p in ipairs(PACKAGES) do
      local to = ".tools/downloads/" .. fs.basename(p.url)
      if fs.exists(to) ~= "file" or hash.file("sha256", to) ~= p.sha256 then
        local r, e = http.get(p.url, { to = to, sha256 = p.sha256, timeout = "10m" })
        if not r then return nil, e end
      end
      local ok, e = archive.unpack(to, ".tools/msys2")
      if not ok then return nil, e end
    end
  end,
}

task "build" {
  desc = "build with the fetched make",
  deps = { "prereqs" },
  run = function() return task.exec { MAKE, "-j8" } end,
}

task "test" {
  desc = "run the tests",
  deps = { "build" },
  run = function() return task.exec { "build/tests.exe" } end,
}

task "clean" {
  desc = "remove build/",
  run = function() fs.remove("build", { recursive = true }) end,
}

task.default "test"
```

Three habits make this work:

- **Prerequisites are a list, not a system.** A url and a sha256 per file.
  `http.get { to, sha256 }` refuses a file whose hash differs and places
  nothing; `archive.unpack` opens tar, zip, and zst archives with the tar
  Windows ships. Hashes come from upstream's checksum files or from a first
  fetch inspected by hand; once written down they pin the file forever.
- **Tools are called by path**, `.tools/...`, never by name. `PATH` is
  whatever the machine has today; the repository does not depend on it.
- **A task fails by returning `nil, err`** or by a child's exit code
  through `task.exec`. `kuu run` turns that into an exit code and, with
  `--json`, into a record another program can read.

## 3. Run it

```text
.tools\kuu.exe run                  the default task, with its dependencies
.tools\kuu.exe run test             a named task
.tools\kuu.exe run --dry-run test   the plan: what would run, in order, running nothing
.tools\kuu.exe run --json test      the outcome as one JSON object on stdout
.tools\kuu.exe list                 every task with its description and arguments
.tools\kuu.exe check                tasks.lua and the repository's Lua, without running anything
```

Exit codes: 0 when the task returned, 1 when it failed, 2 when kuu could
not even start it. `kuu check` catches a misspelt module or an undeclared
global before anything runs, so run it first after editing.

## 4. Keep state, take turns, ask the machine

- [`mem`](mem.md) is a small notebook per repository in `.kuu/memory.json`:
  the last build's hash, a counter, a note for the next run.
- [`sync`](sync.md) is a named lock across processes, for the task that two
  agents must not run at once.
- [`sys`](sys.md) says what machine this is; [`env`](env.md) sets variables
  for the children a task starts; [`proc`](proc.md) runs them with decided
  lifetimes and finds the ones already running; [`net`](net.md) tells
  whether the service came up.

## 5. Upgrading kuu

Copy the new `kuu.exe` over the old one in `.tools`, change the `KUU`
constant, run `check`, run the tasks. The [roadmap](roadmap.md) lists what
changed per version. Repositories upgrade one at a time; there is no
machine-wide state to keep in step.

## What not to do

- Do not put kuu on `PATH`, and do not share one `.tools` between
  repositories. The point is that each repository stands alone.
- Do not commit `.tools`, `.kuu`, or `build`.
- Do not write a bootstrap script to fetch kuu. A repository's README says
  "copy kuu.exe into .tools" and that is the whole procedure.
- Do not fetch a prerequisite without its hash. If upstream publishes none,
  fetch once, hash with `hash.file("sha256", path)`, and write it down.
