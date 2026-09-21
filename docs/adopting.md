# Adopting kuu in a repository

How a repository comes to be driven by kuu: one executable of its own, one
`manifest.lua`, and a list of prerequisites it fetches itself. Nothing is
installed on the machine, nothing is shared between repositories, and
nothing is looked up on `PATH`.

```text
repo/
  manifest.lua          the tasks, and the prerequisites as url and sha256
  kuu.exe            this project's pinned runtime; downloaded or committed
  .tools/            downloads and unpacked tools; git ignores it
  .kuu/              kuu's own: the ledger of every crossing, and mem's notebook; git ignores it
  build/             outputs; git ignores it
  src/               whatever the repository is about
```

The examples require 0.10 or later, since they declare their tools. Read
[upgrading to 0.10](upgrading-0.10.md) when moving from 0.9, and the
earlier upgrading pages from further back. A project that already uses signed
0.11 should start with [Upgrading from 0.11](upgrading-from-0.11.md), including
its checklist for project instructions, inspection and history consumers.

## 1. Give the repository its kuu

Each repository owns a particular `kuu.exe` in its root. Another repository
can own a different version. Choose either distribution model; both are
supported, and neither needs a machine-wide install:

| Model | What the repository keeps | What a fresh checkout does |
|---|---|---|
| Downloaded runtime | A reviewed release version, exact asset URL, SHA-256 and expected signing-certificate identity; `/kuu.exe` is ignored | Obtain that exact signed release, verify it as below, then use the local copy |
| Committed runtime | The same reviewed identity and pins, plus the signed `kuu.exe` bytes in Git; `/kuu.exe` is not ignored | Check out the binary, verify it as below, then use it without a runtime download |

Record the pins in the project's README or a committed runtime record. Select
the asset from a specific [release](https://github.com/anafalanx/kuu/releases),
not a moving latest-release URL. The release's `kuu.exe.sha256` supplies the
checksum to review and pin; a newly fetched sidecar must not silently replace
the project's approved hash. Establish the expected signing identity through
the owner's release review, then pin its certificate thumbprint. A valid
signature from a different publisher does not satisfy that pin.

Ignore generated tools, state and outputs in either model:

```text
/.tools/
/.kuu/
/build/
```

Add `/kuu.exe` only for the downloaded model. In the committed model, keep the
runtime as an ordinary binary asset and review upgrades alongside its pins.
Do not substitute an unreviewed local build for the project's signed release.
A project intentionally adopting a development build records its separate
build provenance and hash; the signed-release verification below does not
claim to accept an unsigned build.

### Verify before first execution

Read the project's runtime record before running its executable, including
`--version`, `capabilities` or `docs`. Use an already trusted runtime or platform
tools for verification; the candidate must not establish its own initial
trust. This PowerShell example uses the platform's
[Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash)
and [Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature).
It only inspects the file and does not launch it.

Fill all three pin values from the reviewed project record. The release label
identifies the selected release; SHA-256 identifies the exact approved bytes.
The placeholders deliberately fail until replaced. Run from the repository
root, or change `$kuuCandidatePath` to the staged candidate during an upgrade.

```powershell
$kuuRelease = 'N.N'
$kuuExpectedHash = 'REPLACE_WITH_REVIEWED_64_HEX_SHA256'
$kuuExpectedSigner = 'REPLACE_WITH_REVIEWED_40_HEX_CERTIFICATE_THUMBPRINT'
$kuuCandidatePath = '.\kuu.exe'

if ($kuuRelease -notmatch '^[0-9]+\.[0-9]+$' -or
    $kuuExpectedHash -notmatch '^[0-9A-Fa-f]{64}$' -or
    $kuuExpectedSigner -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'Supply the reviewed release, SHA-256 and signing-certificate pins first.'
}
$kuuCandidate = (Resolve-Path -LiteralPath $kuuCandidatePath -ErrorAction Stop).Path
$kuuActualHash = Get-FileHash -LiteralPath $kuuCandidate -Algorithm SHA256 -ErrorAction Stop
if ($kuuActualHash.Hash -ine $kuuExpectedHash) {
    throw 'kuu.exe does not match the approved SHA-256.'
}
$kuuSignature = Get-AuthenticodeSignature -LiteralPath $kuuCandidate -ErrorAction Stop
if ($kuuSignature.Status -ne 'Valid' -or $null -eq $kuuSignature.SignerCertificate) {
    throw "kuu.exe signature was not accepted: $($kuuSignature.Status)"
}
if ($kuuSignature.SignerCertificate.Thumbprint -ine $kuuExpectedSigner) {
    throw 'kuu.exe was signed with a different certificate than the project approved.'
}
Write-Output "Verified kuu $kuuRelease at $kuuCandidate"
```

Verification must succeed before proceeding; do not regenerate pins from a
mismatching candidate. Keep the candidate under project control between the
check and use. An already trusted kuu can instead compare `hash.file` and
`sys.signature` against the same pins; launching the candidate itself to make
those checks would reverse this order. Once verified, use that project copy
for the commands in the rest of this guide.

The first `kuu run` that creates `.kuu/` under a root that no `.gitignore`
ignores it in — the root's own, or one in a directory above it up to the
repository's — says so once, on standard error and as a note in its
`--json` envelope; nothing else reminds you, and nothing fails over it.

## 2. Write manifest.lua

`manifest.lua` sits at the repository root. It states the minimum kuu version
it needs, lists the prerequisites, and declares the tasks. [Tasks](task.md)
has the full contract; this is the shape:

```lua
global none
global <const> require, ipairs, print, error

local NEED_MAJOR, NEED_MINOR = 0, 10

local rt = require "rt"
local task = require "task"
local http = require "http"
local archive = require "archive"
local fs = require "fs"
local hash = require "hash"
local err = require "err"

if not rt.version_at_least(NEED_MAJOR, NEED_MINOR) then
  error(err.new("PROJECT", "version", "requires kuu 0.10.0 or later, found " .. rt.version .. "; copy a supported kuu.exe into the repository root"))
end
task.defaults { timeout = "10m" }

-- What this repository needs, by url and hash.  Nothing else is looked up anywhere.
local PACKAGES = {
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-make-4.4.1-5-any.pkg.tar.zst",
    sha256 = "871f760657a360279f29b945a7fd7d9655fe46a3e1e06dd783c9e74514aa0b27" },
  -- make imports gettext's libintl, which also needs libiconv.
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-gettext-0.22.4-3-any.pkg.tar.zst",
    sha256 = "adb418766c639868e513ab76a1c4676fc63900a183264e7ffa9c1d21a254c45d" },
  { url = "https://mirror.msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-libiconv-1.19-1-any.pkg.tar.zst",
    sha256 = "9a500f38c2b91808741c62fae746b3e9110b33a1ecf5c30fa0c66dbedddf7e16" },
}
-- The tools this repository calls through the door, declared beside the
-- tasks that call them: where each is and what it emits.  See Tools.
task.tool "make" { exe = ".tools/msys2/ucrt64/bin/mingw32-make.exe", output = "lines", timeout = "30m" }
task.tool "tests" { exe = "build/tests.exe", output = "lines" }

task "prereqs" {
  desc = "fetch the tools by hash into .tools",
  run = function()
    if fs.exists(task.tool_get("make").exe) == "file" then return end
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
  run = function() return task.exec { tool = "make", "-j8" } end,
}

task "test" {
  desc = "run the tests",
  deps = { "build" },
  run = function() return task.exec { tool = "tests" } end,
}

task "clean" {
  desc = "remove build/",
  run = function()
    local ok, why = fs.remove("build", { recursive = true })
    if ok then return true end
    if err.is(why, "FS", "notfound") then
      local info, absent = fs.stat("build", { follow = false })
      if not info and err.is(absent, "FS", "notfound") then return true end
    end
    return nil, why
  end,
}

task.default "test"
```

Three habits make this work:

- **Prerequisites are a list, not a system.** A url and a sha256 per file.
  `http.get { to, sha256 }` refuses a file whose hash differs and places
  nothing; `archive.unpack` opens tar, zip, and zst archives with the tar
  Windows ships. Hashes come from upstream's checksum files or from a first
  fetch inspected by hand; once written down they pin the file forever.
- **Tools are declared by path**, `.tools/...`, and called by the name the
  declaration gives them; nothing is looked up on `PATH`, which is whatever
  the machine has today, and the repository does not depend on it.
- **A task fails by returning `nil, err`** or by a child's exit code
  through `task.exec`. `kuu run` turns that into an exit code and, with
  `--json`, into a record another program can read.

## 3. Run it

```text
.\kuu.exe run                  the default task, with its dependencies
.\kuu.exe run test             a named task
.\kuu.exe run --dry-run test   the plan: what would run, in order, running nothing
.\kuu.exe run --json test      the run as JSON lines on stdout, the outcome the last of them
.\kuu.exe list                 every task with its description and arguments
.\kuu.exe check                manifest.lua and the repository's Lua, without running anything
```

Exit codes: 0 when the task returned, a child's nonzero code when `task.exec`
failed, 1 for another task failure, and 2 when kuu could not start it.
`kuu check` catches an unknown palette export or an undeclared global and
warns about unresolved modules before anything runs, so run it first after
editing.

Then use `kuu list` to load and validate the manifest's declarations. Keep
provisioning inside task bodies: listing executes top-level Lua and is not a
sandbox or a guarantee that required programs are installed.

## 4. Keep state, take turns, ask the machine

Use the [shared project environment](project-environment.md) recipe when CLI
tools and newly launched editors need the same project-local cache paths.
It keeps those choices independent of the caller's working directory.

For moved checkouts and renamed source directories, use the
[relocation and doctor recipes](relocation.md). Their offline checks distinguish
installed tools, cached dependencies and application outputs, and report missing
dependencies without installing them.

The [editor recipe](editor.md) demonstrates detached GUI lifetime and isolated
verification. The [native-helper recipe](native-helper.md) builds a small
project tool, verifies its cached bytes and creates an ignored local shortcut.
The [reconstruction guide](reconstruction.md) separates cached installation,
upstream availability and independent backup, with verified recovery after
an uncertain upload.

- [`mem`](mem.md) is a small notebook per repository in `.kuu/memory.json`:
  the last build's hash, a counter, a note for the next run.
- [`sync`](sync.md) is a named lock across processes, for the task that two
  agents must not run at once.
- [`sys`](sys.md) says what machine this is; [`env`](env.md) sets variables
  for the children a task starts; [`proc`](proc.md) runs them with decided
  lifetimes and finds the ones already running; [`net`](net.md) tells
  whether the service came up.
- [`svc`](svc.md) inspects and controls services; [`evt`](evt.md) reads the
  event logs. [`sys.signature`](sys.md#syssignature) verifies an embedded
  Authenticode signature before a project runs an installer.
- [`sched.deadline`](sched.md#deadlines) bounds a sequence of waits, while
  `task.defaults` and [`proc` limits](proc.md#limits) bound the children.
  The [cookbook](cookbook.md) has complete programs for these jobs.

## 5. Upgrading kuu

The project owner decides when to change its pinned runtime. An agent follows
that reviewed choice instead of fetching the latest release, accepting any
runtime that passes the minimum guard, or rewriting pins to match local bytes.

Read the intervening upgrading notes, obtain the chosen signed candidate at a
separate project-owned path, and apply the [pre-execution verification](#verify-before-first-execution)
to the proposed new pins. For a project coming from signed 0.11, follow
[Upgrading from 0.11](upgrading-from-0.11.md) before loading project code with
the candidate. Reading `docs` is offline and does not load the manifest;
`check` without `--fix` is read-only static inspection. `capabilities` and
`list` execute the manifest to read its declarations.

Validate the candidate with `check` and the project's tests in an isolated
project copy, using the candidate at its expected runtime path. Review task
side effects and external paths so the copy stays isolated. Stop tasks using
the old runtime before replacing the live copy. Retain the old approved runtime
and a separate pre-upgrade history copy if rollback is required: new runs write
ledger v2, which older executables have not been validated to read or append.
Replacing only the executable after those runs is not an established rollback
procedure. Preserve the old and new histories rather than rewriting ledger lines.

In the downloaded model, review and commit the updated runtime record; in the
committed model, review and commit the executable and that record together.
Include changed project instructions, configuration and helpers in the upgrade
review. A signing-certificate change also requires an explicitly reviewed new
identity.

Maintain the project's root `kuu-eval.md` through the upgrade, using
[the reporting format](agent.md#reporting-back). Preserve earlier feedback and
append the tested runtime identity, validation results and follow-ups on old
difficulties, including when adoption fails or is deferred. Carry relevant
findings from an isolated validation copy into that project document.

Raise
`NEED_MAJOR` and `NEED_MINOR` only when the recipes begin to require a newer
feature. Compare the components numerically: 0.10 is newer than 0.9. The
[stability statement](stability.md) defines this minimum guard and the future
1.x promise; the [roadmap](roadmap.md) lists what changed per version.
Repositories upgrade one at a time; there is no machine-wide state to keep
in step.

## What not to do

- Do not put kuu on `PATH`, and do not share one `.tools` between
  repositories. The point is that each repository stands alone.
- Do not commit generated `.tools`, `.kuu`, or `build` contents. Commit
  `kuu.exe` when the project chooses the committed-runtime model.
- Do not add an unpinned bootstrap download. The project's runtime record
  explains how to obtain or check out its chosen bytes and verify them before
  first execution; neither model needs a self-updating runtime.
- Do not fetch a prerequisite without its hash. If upstream publishes none,
  fetch once, hash with `hash.file("sha256", path)`, and write it down.
