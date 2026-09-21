# Relocation and an offline doctor

Derive local paths from the current project root, as in
[the shared environment recipe](project-environment.md). After a checkout
moves, the next `kuu run` discovers its new root; a fresh process resolves
declared relative tools there. Already running processes retain their old
working directory, environment and loaded modules. Stop them before moving
the checkout and launch them again afterwards.

## Moving maintained source

For a `scripts/` to `automation/` migration:

1. Move the maintained Lua files and update `require "scripts.health"` to
   `require "automation.health"`, including imports between project modules.
2. Update script arguments, task tool paths, build configuration and tests that
   intentionally name the old directory. `require "a.b"` resolves `a/b.lua` or
   `a/b/init.lua` below the module root; `LUA_PATH` does not override kuu's
   [module lookup](index.md#modules).
3. Run static `kuu check`, then `kuu list` to validate declarations. Keep
   provisioning out of top-level Lua: listing executes the manifest.
4. Recreate generated local launchers, editor settings and shortcuts that
   contain absolute paths, executable targets or working directories. Keep
   these local outputs ignored. Their previous paths are not rewritten by kuu.
5. Inspect obsolete ignored environments separately. Checking out a tracked
   rename, or moving tracked files individually, can leave `scripts/.venv`
   behind. A whole-directory filesystem rename can carry ignored children;
   do not assume every kind of move has the same result.

For a whole-checkout move, retain the project's chosen pinned runtime and
verified dependency caches. Recompute environment/cache paths in the new
location, run the local doctor below, then explicitly recreate installations
that retain absolute paths. A cache directory existing does not establish that
it contains everything needed to rebuild offline.

## Python environments and relocation markers

Recreate a Python virtual environment at its final new path using the declared
pinned interpreter, then reinstall the locked dependencies and editable local
packages against their current source locations. Do not move a venv and assume
that editing `pyvenv.cfg` repairs launchers, `.pth` files, editable metadata,
native packages or references to its base interpreter. Python documents venvs
as disposable rather than portable. [Python venv documentation](https://docs.python.org/3/library/venv.html).

For a project that uses uv, the configured `UV_PROJECT_ENVIRONMENT` selects
one specific environment; avoid pointing several checkouts at one shared
absolute path. uv installs packaged projects and workspace members as editable
packages during synchronization. After a source move, rebuild that environment
and reinstall from the new layout through the project's explicit installation
task. Keep such synchronization out of `doctor`: it can create or change the
environment. [uv environment location](https://docs.astral.sh/uv/concepts/projects/config/#project-environment-path),
[uv editable installation](https://docs.astral.sh/uv/concepts/projects/sync/#editable-installation).

uv's `--relocatable` adjusts standard entrypoint and activation scripts; it does
not rewrite arbitrary binaries or guarantee that every installed package and
editable source reference survives a move. A project's own `relocatable=true`
receipt, or the ownership marker used below, proves neither current path
validity nor application readiness. [uv relocatable option](https://docs.astral.sh/uv/reference/cli/#uv-venv--relocatable).

## A non-repairing doctor

This example checks a small project's pinned local executable and cached
archive. It does not launch either, access the network, provision dependencies
or compile application packages. Missing generated assets cannot prevent it
from diagnosing dependency state. A project's richer doctor can add bounded,
read-only version/import probes through known installed tools; keep application
builds and installers in separate tasks.

Maintain `dependencies.json` in source control with the independently reviewed
SHA-256 values for `.tools/tool/tool.exe` and `.cache/dependencies/tool.zip`:

```json
{
  "tool_sha256": "REPLACE_WITH_REVIEWED_EXECUTABLE_SHA256",
  "archive_sha256": "REPLACE_WITH_REVIEWED_ARCHIVE_SHA256"
}
```

These placeholders deliberately fail validation. Do not generate expected
digests from whatever files happen to be installed during a doctor run. The
archive digest is a byte-integrity check; it does not prove unpacking or full
offline dependency reconstruction will succeed.

Save as `automation/health.lua`:

```lua
global none
global <const> require, type, tostring
local fs, rt, hash, json, err = require "fs", require "rt", require "hash", require "json", require "err"
local root = fs.absolute(rt.root())
local M = {}

local function valid_digest(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-fA-F]+$") ~= nil
end

local function inspect_file(relative, expected)
  local path = fs.join(root, relative)
  local info, why = fs.stat(path, { follow = false })
  if not info then
    return { path = path, status = err.is(why, "FS", "notfound") and "missing" or "unreadable",
      message = tostring(why) }
  end
  if info.kind ~= "file" or info.reparse then
    return { path = path, status = "unexpected-kind", message = "expected an ordinary file" }
  end
  if not expected then return { path = path, status = "present-unverified" } end
  local digest, failure = hash.file("sha256", path)
  if not digest then return { path = path, status = "unreadable", message = tostring(failure) } end
  return { path = path, status = digest == expected:lower() and "verified" or "mismatch", sha256 = digest }
end

function M.inspect()
  local text, why = fs.read(root .. "/dependencies.json", { maxbytes = "16K" })
  if not text then return nil, why end
  local pins, parse_error = json.decode(text)
  if pins == nil then return nil, parse_error end
  if type(pins) ~= "table" or not valid_digest(pins.tool_sha256) or not valid_digest(pins.archive_sha256) then
    return nil, err.new("PROJECT", "pins", "dependencies.json requires reviewed 64-digit tool_sha256 and archive_sha256 values")
  end
  local report = {
    root = root,
    installed = inspect_file(".tools/tool/tool.exe", pins.tool_sha256),
    cache = inspect_file(".cache/dependencies/tool.zip", pins.archive_sha256),
    application = inspect_file("build/app.exe"),
  }
  if report.application.status == "missing" then report.application.status = "not-built" end
  report.application.ready = false -- this doctor does not establish application readiness
  report.ok = report.installed.status == "verified" and report.cache.status == "verified"
  return report
end

return M
```

The three results mean different things: `installed.status == "verified"` says the expected
executable bytes are present, not that every supporting DLL exists;
`cache.status == "verified"` says this archive matches its pin; an application file remains
`present-unverified` until a separate project-specific readiness check succeeds.
Absent application output is `not-built` and does not fail this dependency
doctor. Access and digest failures remain visible rather than becoming missing
dependencies. Filesystem checks are observations, not a transaction against
concurrent writers or a sandbox for untrusted linked ancestors.

Save as `manifest.lua`. This doctor has **no provisioning dependencies**.
`kuu run doctor` prints the report and fails when either dependency check fails.
Run an explicit install or repair task separately after reading the report.
Normal task/run history is still written under `.kuu`; “non-repairing” does not
mean the entire kuu invocation performs zero writes.

```lua
global none
global <const> require, print
local task, json, err = require "task", require "json", require "err"
local health = require "automation.health"
local remove_obsolete = require "automation.remove_obsolete"

task "doctor" {
  desc = "Check local dependency bytes without installing or building",
  run = function()
    local report, why = health.inspect()
    if not report then return nil, why end
    print(json.encode(report))
    if not report.ok then
      return nil, err.new("PROJECT", "health", "installed=" .. report.installed.status ..
        "; cache=" .. report.cache.status .. "; inspect the report before an explicit repair")
    end
    return true
  end,
}
task "clean_obsolete_environment" {
  desc = "Remove only this project's marked obsolete scripts/.venv",
  run = function() return remove_obsolete() end,
}
```

## Remove only the owned obsolete environment

Save the [bounded cleanup module](cleanup.md#a-project-module) as `owned_ops.lua`
at the project root, then save this function as `automation/remove_obsolete.lua`.
It requires the readonly-directory cleanup from 0.12 described on that page;
use `rt.version_at_least(0, 12)` as its minimum-version guard.
The only removal target is the literal `scripts/.venv` below the canonical
project root. It accepts no caller-supplied path. Its owner marker must have
been written by this project's environment-creation task when it created that
directory: `.project-owner` contains exactly `example-project/venv/v1` followed
by a newline. Choose your own project identifier. Never add a marker to an
uninspected directory just to make cleanup accept it.

Use this only during exclusive maintenance: stop processes using or modifying
the old environment. The trusted project root may itself resolve through a
link; below that canonical root, every path component and the marker must be
ordinary, without reparse metadata. These checks are not protection against
concurrent malicious path replacement. Other files under `scripts/`, the
current environment and dependency caches remain outside the removal target.

```lua
global none
global <const> require, ipairs
local fs, rt, err = require "fs", require "rt", require "err"
local owned_ops = require "owned_ops"
local OWNER = "example-project/venv/v1\n"

return function()
  local canonical, why = fs.canon(rt.root())
  if not canonical then return nil, why end
  if canonical.kind ~= "directory" then return nil, err.new("PROJECT", "ownership", "project root is not a directory") end
  local target = canonical.path
  for _, component in ipairs { "scripts", ".venv" } do
    target = fs.join(target, component)
    local info, failure = fs.stat(target, { follow = false })
    if not info then
      if err.is(failure, "FS", "notfound") then return true end
      return nil, failure
    end
    if info.kind ~= "directory" or info.reparse then
      return nil, err.new("PROJECT", "ownership", "refusing linked or non-directory cleanup component: " .. target)
    end
  end
  local marker = target .. "/.project-owner"
  local info, failure = fs.stat(marker, { follow = false })
  if not info then return nil, failure end
  if info.kind ~= "file" or info.reparse or info.size ~= #OWNER then
    return nil, err.new("PROJECT", "ownership", "obsolete environment has no valid ordinary ownership marker")
  end
  local text, read_error = fs.read(marker, { maxbytes = 128 })
  if not text then return nil, read_error end
  if text ~= OWNER then return nil, err.new("PROJECT", "ownership", "obsolete environment belongs to another owner") end
  return owned_ops.remove_owned(target, 0.5)
end
```

Run `kuu run clean_obsolete_environment` only after adopting the new layout.
Already absent cleanup succeeds; an existing unmarked, differently marked or
linked environment fails without removal. Recursive removal can make partial
progress before a failure, including deleting the ownership marker. Keep the
returned error. If the marker still passes validation, rerun this same bounded
cleanup after resolving the cause. If partial removal consumed the marker,
this task safely refuses the remaining directory: inspect and recover it under
explicit project ownership instead of manufacturing a new marker or broadening
the target. The retry loop within one invocation retains the already validated
target, which is another reason exclusive maintenance is required.
