# Reconstructing tools and reconciling publication

A retained cache, a reachable upstream download and an independent backup are
three different recovery options. Keep reviewed pins in maintained source;
record which archives are necessary for an offline rebuild. A cache directory
alone proves neither completeness nor that upstream URLs will remain available.
This recipe requires 0.12 for the [attribute APIs](fs.md#file-attributes) and
readonly-directory removal, with the complete `owned_ops.lua` module from
[cleanup](cleanup.md). Use `rt.version_at_least(0, 12)` as its minimum-version guard.

| Recovery source | What must remain available |
|---|---|
| Retained cache | Every required pinned archive, for offline reconstruction. |
| Pinned upstream | Network, URL and access still working; a hash does not preserve availability. |
| Independent backup | A separately retained complete set of verified archives and reviewed pins, with restore testing. |

## Restore an installation from local bytes

Save the following as `restore_cached.lua`. This example package contains
`package.json` with `{schema:1, package, target, recipe}` and `bin/tool.exe`.
The independently reviewed pin adds `archive_sha256` and `tool_sha256`, both
lowercase SHA-256 values. Set `target` to `windows-x86_64` and `recipe` to
`tool-layout-v1`; deliberately revise this recipe before accepting another
layout or platform. An archive's own receipt cannot establish its trust.

Paths and their parents must be project-owned, with writers stopped throughout
the operation. The destination must be absent; publication never replaces an
existing installation. Extraction occurs only after the archive matches its
pin, into a newly created sibling directory. The full tree is inspected before
readonly normalization, rejecting reparse objects and multiply linked files.
These checks close their handles and do not prevent concurrent path replacement.
Use this with reviewed packages, not arbitrary untrusted archives.
Post-extraction checks are not an archive sandbox: review must exclude aliases
outside staging during extraction too. Recursive failure cleanup can clear a
readonly flag shared by hardlinks; rejecting a hardlink during validation does
not undo that risk or establish ownership of its other names.

```lua
global none
global <const> require, type, ipairs
local fs, hash, json = require "fs", require "hash", require "json"
local archive, err, ops = require "archive", require "err", require "owned_ops"
local M = {}
local function refused(code, message) return nil, err.new("PROJECT", code, message) end
local function digest(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end
local function pin_valid(pin)
  return type(pin) == "table" and pin.schema == 1 and type(pin.package) == "string"
    and #pin.package > 0 and pin.target == "windows-x86_64" and pin.recipe == "tool-layout-v1"
    and digest(pin.archive_sha256) and digest(pin.tool_sha256)
end
local function matches(path, expected)
  local actual, why = hash.file("sha256", path)
  if not actual then return nil, why end
  if actual ~= expected then return refused("hash", "pinned bytes differ: " .. path) end
  return true
end

-- Only call for a newly created, exclusively owned staging tree.
function M.normalize_staging(staging)
  local ordinary = {}
  local function inspect(path, depth)
    if depth > 64 or #ordinary >= 100000 then return refused("layout", "staging inspection limit") end
    local info, why = fs.stat(path, { follow = false })
    if not info then return nil, why end
    if (info.attrs & 0x400) ~= 0 or (info.kind ~= "directory" and info.kind ~= "file")
      or (info.kind == "file" and info.links > 1) then
      return refused("layout", "staging requires ordinary unaliased files/directories: " .. path)
    end
    ordinary[#ordinary + 1] = path
    if info.kind == "directory" then
      local listing, listing_error = fs.list(path)
      if not listing then return nil, listing_error end
      if #listing.errors > 0 then return refused("layout", "incomplete staging directory listing") end
      for _, entry in ipairs(listing.entries) do
        local ok, child_error = inspect(path .. "/" .. entry.name, depth + 1)
        if not ok then return nil, child_error end
      end
    end
    return true
  end
  local inspected, why = inspect(staging, 0)
  if not inspected then return nil, why end
  for _, path in ipairs(ordinary) do
    local flags, flag_error = fs.attributes(path) -- nofollow
    if not flags then return nil, flag_error end
    if flags.readonly then
      local ok, update_error = fs.set_attributes(path, { readonly = false })
      if not ok then return nil, update_error end
    end
  end
  return true
end

local function staged(destination, validate)
  local parent = fs.dirname(destination)
  local made, why = fs.mkdir(parent)
  if not made then return nil, why end
  local stage, stage_error = fs.tempdir { dir = parent, prefix = ".reconstruct-" }
  if not stage then return nil, stage_error end
  local ok, primary, cleanup = ops.publish(stage, destination, validate, 0.5)
  return ok, primary, cleanup, stage -- retain the exact owned path if cleanup failed
end

function M.restore(cached, destination, pin)
  if not pin_valid(pin) then return refused("pin", "reviewed compatible package pin required") end
  return staged(destination, function(stage)
    local ok, why = matches(cached, pin.archive_sha256)
    if not ok then return nil, why end
    ok, why = archive.unpack(cached, stage, { timeout = "2m" })
    if not ok then return nil, why end
    ok, why = M.normalize_staging(stage)
    if not ok then return nil, why end
    local bytes, read_error = fs.read(stage .. "/package.json", { maxbytes = "16K" })
    if not bytes then return nil, read_error end
    local receipt, parse_error = json.decode(bytes)
    if receipt == nil then return nil, parse_error end
    if type(receipt) ~= "table" or receipt.schema ~= pin.schema or receipt.package ~= pin.package
      or receipt.target ~= pin.target or receipt.recipe ~= pin.recipe then
      return refused("receipt", "package receipt does not match the reviewed pin")
    end
    local tool, missing = fs.stat(stage .. "/bin/tool.exe", { follow = false })
    if not tool then return nil, missing end
    if tool.kind ~= "file" then return refused("layout", "bin/tool.exe must be a file") end
    return matches(stage .. "/bin/tool.exe", pin.tool_sha256)
  end)
end

function M.backup(cached, destination, pin)
  if not pin_valid(pin) then return refused("pin", "reviewed compatible package pin required") end
  return staged(destination, function(stage)
    local ok, why = matches(cached, pin.archive_sha256)
    if not ok then return nil, why end
    ok, why = fs.copy(cached, stage .. "/package.zip")
    if not ok then return nil, why end
    ok, why = fs.write(stage .. "/pin.json", json.encode(pin))
    if not ok then return nil, why end
    return matches(stage .. "/package.zip", pin.archive_sha256)
  end)
end
return M
```

Save this driver as `reconstruct.lua`. For example, run
`kuu reconstruct.lua restore .cache/tool.zip .tools/tool tool-pin.json` or
`kuu reconstruct.lua backup .cache/tool.zip E:/project-backup/tool tool-pin.json`.
The backup destination must be a new directory on separately retained storage;
the tests use a separate disposable directory, not a simulated disk failure.
Restore from its `package.zip` with the maintained pin, comparing its saved
`pin.json` with the reviewed source. Rehash after any later transfer. Use ZIP
caches with this driver so the backup filename matches its format.
Successful byte reconstruction does not prove
that an application built with the tool is ready or that its runtime works.

```lua
global none
global <const> require, assert, io, tostring, print
local rt, fs, json = require "rt", require "fs", require "json"
local rebuild = require "restore_cached"
assert(#rt.args == 4, "usage: reconstruct.lua restore|backup CACHE DEST PIN")
local mode, cached, destination, pin_path = rt.args[1], rt.args[2], rt.args[3], rt.args[4]
assert(mode == "restore" or mode == "backup", "mode must be restore or backup")
local pin, parse_error = json.decode(assert(fs.read(pin_path, { maxbytes = "16K" })))
assert(pin ~= nil, parse_error)
local ok, primary, cleanup, stage = rebuild[mode](cached, destination, pin)
if cleanup then io.stderr:write("owned staging remains at ", stage, ": ", tostring(cleanup), "\n") end
assert(ok, primary)
print(json.encode { status = "verified", operation = mode, destination = fs.absolute(destination) })
```

Keep the primary error and any secondary cleanup error. Removal can make partial
progress; inspect the exact reported staging path before recovering it. The
recipe clears only readonly, preserving hidden and other flags; it does not
repair ACLs or modify the retained source archive. It does not provision or
download anything. A missing archive requires a separate deliberate decision
to restore a backup or fetch the already pinned upstream bytes.

## An upload timed out: reconcile before deciding what to do

Save this module as `publish_asset.lua`. It is an executable project recipe with
an injected remote adapter, not a GitHub client. Its journal, local artifact and
scratch parent belong to one publisher: exclude all concurrent writers and
publishers. Keep the journal after failure; removing or rolling it back removes
the protection against a duplicate attempt. An atomic local write is not a
power-loss durability guarantee or a distributed lock.

The maintained `spec` contains `repository`, numeric `release_id`, `name`,
`size`, `sha256`, `file`, `journal` and `scratch`. Use a stable release ID, not
only a mutable tag. The adapter's three functions return `value` or `nil,error`:

- `lookup(spec)` returns one asset or `false` for confirmed absence. It must
  enumerate all pages for that release, reject duplicates, and never turn a
  failed or incomplete listing into absence. Assets contain `repository`,
  `release_id`, `name`, `id`, `size`, `sha256` and `state="uploaded"`; normalize
  a provider's `sha256:` digest prefix before returning it. A missing provider
  digest is unsupported confirmation; never fill it from the local pin.
- `upload(spec)` attempts once, without internal retries, and returns a result
  or an error. A timeout may mean the server accepted it.
- `download(asset, path)` fetches that exact asset ID into the new owned path,
  with a byte cap of `asset.size` and a finite timeout. It returns true or an error.

Bound each complete adapter call (for example 30 seconds), the number of listing
pages (for example 20), and each page's size. Pages and redirects share the call's
remaining deadline; they do not reset it. An exceeded limit is an error. This
module makes at most two lookups, one upload and one verification download per
invocation; it has no polling, delete, replacement or automatic upload retry.

```lua
global none
global <const> require, type, math, pcall
local fs, hash, json = require "fs", require "hash", require "json"
local err, ops = require "err", require "owned_ops"
local M = {}
local function fail(code, message, context) return nil, err.new("PROJECT", code, message, context) end
local function integer(value) return type(value) == "number" and math.type(value) == "integer" and value > 0 end
local function same(a, b)
  return a.repository == b.repository and a.release_id == b.release_id and a.name == b.name
    and a.size == b.size and a.sha256 == b.sha256
end
function M.reconcile(remote, spec)
  if type(spec) ~= "table" or type(spec.repository) ~= "string" or #spec.repository == 0
    or not integer(spec.release_id) or type(spec.name) ~= "string" or #spec.name == 0
    or not integer(spec.size) or type(spec.sha256) ~= "string" or #spec.sha256 ~= 64
    or not spec.sha256:match("^[0-9a-f]+$") then
    return fail("intent", "complete pinned asset identity required")
  end
  local info, why = fs.stat(spec.file, { follow = false })
  if not info then return nil, why end
  if info.kind ~= "file" or (info.attrs & 0x400) ~= 0 or info.size ~= spec.size then
    return fail("artifact", "local artifact kind or size differs")
  end
  local digest, hash_error = hash.file("sha256", spec.file)
  if not digest then return nil, hash_error end
  if digest ~= spec.sha256 then return fail("artifact", "local artifact digest differs") end
  local state = { schema = 1, repository = spec.repository, release_id = spec.release_id,
    name = spec.name, size = spec.size, sha256 = spec.sha256, attempted = false, confirmed = false }
  local bytes, read_error = fs.read(spec.journal, { maxbytes = "16K" })
  if bytes then
    local saved, parse_error = json.decode(bytes)
    if saved == nil then return nil, parse_error end
    if type(saved) ~= "table" or saved.schema ~= 1 or not same(saved, state)
      or type(saved.attempted) ~= "boolean" or type(saved.confirmed) ~= "boolean"
      or (saved.asset_id ~= nil and not integer(saved.asset_id))
      or (saved.confirmed and saved.asset_id == nil) then
      return fail("intent", "saved publication identity or state differs")
    end
    state = saved
  elseif not err.is(read_error, "FS", "notfound") then return nil, read_error end
  local function save() return fs.write(spec.journal, json.encode(state)) end
  local asset, lookup_error = remote.lookup(spec)
  local upload_error
  if asset == nil then return nil, lookup_error end
  if asset == false then
    if state.attempted or state.confirmed or state.asset_id then
      return fail("pending", "previous attempt is unresolved; retain journal and inspect the release")
    end
    state.attempted = true -- persist BEFORE allowing the only upload attempt
    local saved, save_error = save()
    if not saved then return nil, save_error end
    local called, uploaded, why_upload = pcall(remote.upload, spec)
    if not called then upload_error = uploaded
    elseif not uploaded then upload_error = why_upload end
    asset, lookup_error = remote.lookup(spec)
    if asset == nil or asset == false then
      return fail("pending", "upload outcome unresolved; do not retry or delete",
        { upload_error = upload_error, lookup_error = lookup_error })
    end
  end
  if type(asset) ~= "table" or not same(asset, spec) or asset.state ~= "uploaded" or not integer(asset.id)
    or (state.asset_id ~= nil and state.asset_id ~= asset.id) then
    return fail("conflict", "remote asset identity, state, size or digest differs", { upload_error = upload_error })
  end
  state.asset_id = asset.id
  local saved, save_error = save()
  if not saved then return nil, save_error end
  local stage, stage_error = fs.tempdir { dir = spec.scratch, prefix = ".verify-asset-" }
  if not stage then return nil, stage_error end
  local path = stage .. "/asset.bin"
  local called, ok, primary = pcall(function()
    local downloaded_ok, download_error = remote.download(asset, path)
    if not downloaded_ok then return nil, download_error end
    local downloaded, inspect_error = fs.stat(path, { follow = false })
    if not downloaded then return nil, inspect_error end
    if downloaded.kind ~= "file" or (downloaded.attrs & 0x400) ~= 0 or downloaded.size ~= spec.size then
      return fail("download", "downloaded asset kind or size differs")
    end
    local actual, verify_error = hash.file("sha256", path)
    if not actual then return nil, verify_error end
    if actual ~= spec.sha256 then return fail("download", "downloaded asset digest differs") end
    return true
  end)
  if not called then primary, ok = ok, nil end
  local removed, cleanup = ops.remove_owned(stage, 0.5)
  if removed then cleanup = nil end
  if not ok then return nil, primary, cleanup, stage end
  if cleanup then return nil, err.new("PROJECT", "cleanup", "verified download cleanup failed"), cleanup, stage end
  state.confirmed = true
  saved, save_error = save()
  if not saved then return nil, save_error end
  return { status = "confirmed", asset_id = asset.id, size = spec.size, sha256 = spec.sha256 }
end
return M
```

Retain the primary diagnostic and any cleanup error returned by `reconcile`.
Unresolved post-upload errors also retain `upload_error` and `lookup_error`
when available; inspect those Lua fields when reporting the failure.
An upload's immediate response is deliberately insufficient evidence of success
or failure; a verified remote object resolves even a lost response. Re-running
with the same journal performs inspection and download verification, without
uploading again. A previously confirmed asset is reverified, never deleted.
The journal's `confirmed` flag records a past successful observation; only the
current invocation's return establishes its latest verification result.
If an attempted asset stays absent, investigate before making a new, explicitly
reviewed publication decision. Tests simulate timeout after acceptance, missing
assets, conflicts, corrupt downloads and cleanup failure; they make no live
release or network changes.

GitHub returns asset IDs, state, size and digest. Download endpoints can redirect;
handle that according to the API, preserving normal certificate validation.
A failed upload can leave a `starter` asset; this recipe reports it for review
and does not delete it. Choose a provider-stable filename: GitHub can rename
special characters, which would fail this recipe's exact-name check. See the
[release assets API](https://docs.github.com/en/rest/releases/assets).

For public API failures, distinguish anonymous rate limits from missing assets:
use the documented status and rate-limit headers, authenticated requests where
appropriate, and `Retry-After`/reset timing. A throttled or truncated asset list
cannot prove absence. See [GitHub rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

For `HTTP tls`, preserve the native WinHTTP code. Client-certificate private-key
absence and lack of access to that key require different certificate/account
repairs; neither calls for disabling TLS verification. Inspect the Windows
certificate configuration and the account running the request, using
[WinHTTP errors](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages)
and [WinHTTP SSL guidance](https://learn.microsoft.com/en-us/windows/win32/winhttp/ssl-in-winhttp).
