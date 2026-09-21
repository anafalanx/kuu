# Bounded publication and cleanup

Project Lua can retry a short-lived Windows denial while publishing a completed
directory or removing owned staging. These recipes require kuu 0.12 for
`fs.attributes` and readonly-directory cleanup. Use `rt.version_at_least(0, 12)`
as the minimum-version guard, alongside the project's approved runtime pins.

`FS access` includes sharing violations, ACL denial and write protection. A
retry cannot distinguish them immediately. Retry only that classified error,
under an explicit time budget; never parse localized error messages. Other
errors return immediately. The budget limits new attempts and scheduled waits,
not the time spent inside one synchronous filesystem call. `fs.rename` already
has a short native retry; its elapsed time counts toward this outer budget.

## A project module

Save this complete module as `owned_ops.lua` in the project. Its callers must
own the exact staging/removal path and exclude concurrent writers. Pass the
same path on every attempt. Do not use a repository root, a parent directory,
or a user profile as staging. Final-component links are removed themselves;
linked ancestors and concurrent path replacement are not containment barriers.

```lua
global none
global <const> require, assert, type, math, pcall
local fs, err, sched = require "fs", require "err", require "sched"
local M = {}

function M.retry_access(operation, seconds)
  assert(type(seconds) == "number" and seconds >= 0 and seconds < math.huge,
    "retry budget must be finite nonnegative seconds")
  local until_time = sched.clock() + seconds
  local last
  repeat
    local ok, why = operation()
    if ok then return ok end
    if not err.is(why, "FS", "access") then return nil, why end
    last = why
    local remaining = until_time - sched.clock()
    if remaining <= 0 then break end
    sched.sleep(math.min(0.025, remaining))
  until sched.clock() >= until_time
  return nil, last
end

function M.remove_owned(path, seconds)
  return M.retry_access(function()
    local ok, why = fs.remove(path, { recursive = true })
    if ok then return true end
    if err.is(why, "FS", "notfound") then
      -- A missing descendant alone does not prove the root was removed.
      local flags, absent = fs.attributes(path)
      if not flags and err.is(absent, "FS", "notfound") then return true end
    end
    return nil, why
  end, seconds)
end

function M.publish(staging, destination, validate, seconds)
  -- validate returns true or nil,error; raised validation errors survive too.
  local called, valid, primary = pcall(validate, staging)
  if not called then primary, valid = valid, nil end
  if valid then
    valid, primary = M.retry_access(function()
      return fs.rename(staging, destination) -- no replace: destination must be absent
    end, seconds)
  end
  if valid then return true end
  primary = primary or err.new("PROJECT", "invalid", "staging validation failed")
  local removed, cleanup = M.remove_owned(staging, seconds)
  if removed then cleanup = nil end
  return nil, primary, cleanup
end

return M
```

One removal attempt covers the whole tree, so a two-second budget is not
multiplied by the number of files. Removal is nontransactional: earlier entries
may already be gone, and a readonly bit can remain cleared when deletion later
fails. Retrying tolerates that partial progress. There is no blind restoration
of attributes or files after failure.

Publication uses a staging directory beside the destination, on the same
volume, and never replaces an existing destination. Validate before renaming;
readers should use only the published path. A successful rename moves the
completed tree into place, but is not a power-loss durability guarantee.
On failure, publication and cleanup each have their own explicit budget. A
two-second argument can therefore permit up to four seconds of retry waiting,
plus filesystem call time and validation. Raised programming errors from a
filesystem call still propagate; provide valid paths and arguments.

## Extract, validate, publish

Save as `install-cached.lua`; run `kuu install-cached.lua ARCHIVE DEST SHA256`.
This uses an already cached archive whose expected SHA-256 was pinned by the
project. It creates a new owned staging directory and checks a known package
marker before publication; change `bin/tool.exe` to the package's actual
required file. Hash verification and extraction both happen inside the
validation callback, so either failure still attempts staging cleanup.

```lua
global none
global <const> require, assert, io, tostring
local rt, fs, hash = require "rt", require "fs", require "hash"
local archive, err, ops = require "archive", require "err", require "owned_ops"
local cached = assert(rt.args[1], "ARCHIVE is required")
local destination = assert(rt.args[2], "DEST is required")
local expected = assert(rt.args[3], "SHA256 is required")
assert(fs.mkdir(fs.dirname(destination)))
local staging = assert(fs.tempdir { dir = fs.dirname(destination), prefix = ".stage-" })
local ok, primary, cleanup = ops.publish(staging, destination, function(path)
  local digest, why = hash.file("sha256", cached)
  if not digest then return nil, why end
  if digest ~= expected then return nil, err.new("PROJECT", "hash", "archive hash mismatch") end
  local unpacked, unpack_error = archive.unpack(cached, path, { timeout = "2m" })
  if not unpacked then return nil, unpack_error end
  local info, missing = fs.stat(path .. "/bin/tool.exe", { follow = false })
  if not info then return nil, missing end
  if info.kind ~= "file" then return nil, err.new("PROJECT", "invalid", "bin/tool.exe must be a file") end
  return true
end, 2)
if cleanup then io.stderr:write("staging cleanup also failed: ", tostring(cleanup), "\n") end
assert(ok, primary)
```

The secondary cleanup error is printed before the primary error is raised;
neither failure is replaced by a success message. A task can instead report
the cleanup error and `return nil, primary`, preserving its classified task
failure. Validate the real package's required contents; one marker is only
this example's acceptance criterion. For reconstructing installations and
recovering interrupted publication, keep the pinned archive and explicit
ownership of leftover staging directories. The [reconstruction guide](reconstruction.md)
adds receipt and payload verification, staging attribute normalization, independent
backup verification and reconciliation after an uncertain upload.
