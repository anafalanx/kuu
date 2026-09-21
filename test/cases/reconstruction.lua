-- Execute the published recipes using disposable archives and a mocked remote.
global none
global <const> require, assert, ipairs, pairs, load, type, math, pcall, error, tostring, string

return function(T)
  local fs, hash, json, err = require "fs", require "hash", require "json", require "err"
  local archive, proc = require "archive", require "proc"
  local check = T.check
  local root = assert(fs.tempdir { dir = fs.absolute(T.work), prefix = "reconstruction-" })
  local fence = string.rep(string.char(96), 3)
  local blocks = {}
  for source in assert(fs.read(T.root .. "/docs/reconstruction.md")):gmatch(fence .. "lua\r?\n(.-)\r?\n" .. fence) do
    blocks[#blocks + 1] = source
  end
  check("reconstruction guide contains two modules and a complete local driver", #blocks == 3)
  if #blocks ~= 3 then return end
  local cleanup_source = assert(fs.read(T.root .. "/docs/cleanup.md")):match(fence .. "lua\r?\n(.-)\r?\n" .. fence)
  assert(fs.write(root .. "/owned_ops.lua", cleanup_source))
  for i, name in ipairs { "restore_cached.lua", "reconstruct.lua", "publish_asset.lua" } do
    assert(fs.write(root .. "/" .. name, blocks[i]))
  end
  local lint = T.kuu({ "check", "--json", "restore_cached.lua", "reconstruct.lua", "publish_asset.lua", "owned_ops.lua" }, { cwd = root })
  local report = json.decode(lint.out)
  check("all published reconstruction blocks pass static checking", lint.code == 0 and report
    and report.result.errors == 0 and report.result.warnings == 0, T.describe(lint))
  local ops = assert(load(cleanup_source, "@owned_ops.lua", "t"))()
  local globals = { type = type, ipairs = ipairs, math = math, pcall = pcall,
    require = function(name) if name == "owned_ops" then return ops end; return require(name) end }
  local rebuild = assert(load(blocks[1], "@restore_cached.lua", "t", globals))()
  local function publisher() return assert(load(blocks[3], "@publish_asset.lua", "t", globals))() end
  local function clone(value) local copy = {}; for key, item in pairs(value) do copy[key] = item end; return copy end

  local payload, cached = root .. "/payload", root .. "/cached.zip"
  local artifact_bytes = "controlled package bytes\0binary\255"
  local receipt = { schema = 1, package = "example-tool", target = "windows-x86_64", recipe = "tool-layout-v1" }
  assert(fs.mkdir(payload .. "/bin"))
  assert(fs.write(payload .. "/bin/tool.exe", artifact_bytes))
  assert(fs.write(payload .. "/package.json", json.encode(receipt)))
  assert(archive.pack(cached, payload, nil, { timeout = "10s" }))
  local pin = clone(receipt)
  pin.archive_sha256, pin.tool_sha256 = assert(hash.file("sha256", cached)), hash.sum("sha256", artifact_bytes)
  assert(fs.write(root .. "/pin.json", json.encode(pin)))
  assert(fs.set_attributes(cached, { readonly = true, hidden = true }))
  local original_cache_flags = assert(fs.attributes(cached)).attrs
  local result = T.kuu({ "reconstruct.lua", "restore", cached, root .. "/installed", root .. "/pin.json" }, { cwd = root })
  check("actual driver reconstructs an absent installation from pinned ZIP bytes", result.code == 0
    and hash.file("sha256", root .. "/installed/bin/tool.exe") == pin.tool_sha256, T.describe(result))
  result = T.kuu({ "reconstruct.lua", "backup", cached, root .. "/separate-backup", root .. "/pin.json" }, { cwd = root })
  check("backup copies and rehashes archive plus reviewed pin", result.code == 0
    and hash.file("sha256", root .. "/separate-backup/package.zip") == pin.archive_sha256
    and assert(json.decode(assert(fs.read(root .. "/separate-backup/pin.json")))).tool_sha256 == pin.tool_sha256, T.describe(result))
  assert(fs.rename(cached, root .. "/cache-held.zip"))
  local ok, why, cleanup, stage = rebuild.restore(cached, root .. "/missing-cache", pin)
  check("missing cache fails without creating an installation", not ok and err.is(why, "HASH", "notfound")
    and not cleanup and not fs.exists(root .. "/missing-cache") and not fs.exists(stage), tostring(why))
  ok, why = rebuild.restore(root .. "/separate-backup/package.zip", root .. "/from-backup", pin)
  check("separately retained backup reconstructs after cache loss", ok == true
    and fs.read(root .. "/from-backup/bin/tool.exe") == artifact_bytes, tostring(why))
  assert(fs.rename(root .. "/cache-held.zip", cached))
  check("reconstruction leaves original cache bytes and attributes intact", hash.file("sha256", cached) == pin.archive_sha256
    and assert(fs.attributes(cached)).attrs == original_cache_flags)
  ok, why, cleanup, stage = rebuild.restore(cached, root .. "/installed", pin)
  check("restore never replaces an existing installation", not ok and err.is(why, "FS", "exists") and not cleanup
    and not fs.exists(stage) and fs.read(root .. "/installed/bin/tool.exe") == artifact_bytes, tostring(why))
  for _, invalid in ipairs { "false", "null", "42", '"scalar"', "[]" } do
    assert(fs.write(root .. "/invalid-pin.json", invalid))
    result = T.kuu({ "reconstruct.lua", "restore", cached, root .. "/bad-pin", root .. "/invalid-pin.json" }, { cwd = root })
    check("driver rejects non-pin JSON " .. invalid, result.code ~= 0 and T.contains(result.err, "PROJECT pin")
      and not fs.exists(root .. "/bad-pin"), T.describe(result))
  end
  local incompatible = clone(pin); incompatible.target = "another-platform"
  ok, why = rebuild.restore(cached, root .. "/wrong-platform", incompatible)
  check("incompatible pin is refused before staging", not ok and err.is(why, "PROJECT", "pin")
    and not fs.exists(root .. "/wrong-platform"), tostring(why))
  local changed = root .. "/changed.zip"
  assert(fs.write(changed, "different bytes"))
  ok, why, cleanup, stage = rebuild.restore(changed, root .. "/changed-install", pin)
  check("changed archive fails its pin and cleans staging", not ok and err.is(why, "PROJECT", "hash")
    and not cleanup and not fs.exists(stage) and fs.read(changed) == "different bytes", tostring(why))
  local malformed_pin = clone(pin); malformed_pin.archive_sha256 = assert(hash.file("sha256", changed))
  ok, why, cleanup, stage = rebuild.restore(changed, root .. "/invalid-archive", malformed_pin)
  check("hashed malformed archive preserves extraction failure and cleans staging", not ok
    and err.is(why, "ARCHIVE", "failed") and not cleanup and not fs.exists(stage), tostring(why))
  for _, invalid in ipairs { "false", "null", "42", '"scalar"', "[]",
    json.encode { schema = 1, package = receipt.package, target = receipt.target, recipe = "obsolete-layout" } } do
    assert(fs.write(payload .. "/package.json", invalid))
    local wrong_archive = root .. "/wrong-receipt.zip"
    assert(archive.pack(wrong_archive, payload, nil, { timeout = "10s" }))
    local wrong_pin = clone(pin); wrong_pin.archive_sha256 = assert(hash.file("sha256", wrong_archive))
    ok, why, cleanup, stage = rebuild.restore(wrong_archive, root .. "/wrong-receipt", wrong_pin)
    check("archive receipt must agree with independent pin: " .. invalid, not ok and err.is(why, "PROJECT", "receipt")
      and not cleanup and not fs.exists(stage) and not fs.exists(root .. "/wrong-receipt"), tostring(why))
  end
  assert(fs.write(payload .. "/package.json", json.encode(receipt)))
  assert(fs.write(payload .. "/bin/tool.exe", "changed tool"))
  assert(archive.pack(root .. "/wrong-tool.zip", payload, nil, { timeout = "10s" }))
  local wrong_tool_pin = clone(pin); wrong_tool_pin.archive_sha256 = assert(hash.file("sha256", root .. "/wrong-tool.zip"))
  ok, why = rebuild.restore(root .. "/wrong-tool.zip", root .. "/wrong-tool", wrong_tool_pin)
  check("matching archive and receipt still require expected executable bytes", not ok and err.is(why, "PROJECT", "hash")
    and not fs.exists(root .. "/wrong-tool"), tostring(why))

  local normalize = assert(fs.tempdir { dir = root, prefix = "normalize-" })
  assert(fs.mkdir(normalize .. "/nested")); assert(fs.write(normalize .. "/nested/kept", "unchanged"))
  for _, path in ipairs { normalize, normalize .. "/nested", normalize .. "/nested/kept" } do
    assert(fs.set_attributes(path, { readonly = true, hidden = true }))
  end
  ok, why = rebuild.normalize_staging(normalize)
  local normalized = ok == true
  for _, path in ipairs { normalize, normalize .. "/nested", normalize .. "/nested/kept" } do
    local flags = assert(fs.attributes(path)); normalized = normalized and not flags.readonly and flags.hidden
  end
  check("normalization clears only readonly on owned files and directories", normalized
    and fs.read(normalize .. "/nested/kept") == "unchanged", tostring(why))
  local native_root = root .. "/native"
  local native = assert(proc.run { fs.absolute(T.root .. "/build/test/attributes_fixture.exe"), "setup", native_root, timeout = "10s" })
  check("native fixture creates a real outside-target junction", native.code == 0, T.describe(native))
  if native.code == 0 then
    local unsafe = assert(fs.tempdir { dir = root, prefix = "unsafe-" })
    assert(fs.write(unsafe .. "/a-readonly", "keep")); assert(fs.set_attributes(unsafe .. "/a-readonly", { readonly = true }))
    assert(fs.rename(native_root .. "/junction", unsafe .. "/z-link"))
    local outside = assert(fs.read(native_root .. "/target/child.bin"))
    local flags = assert(fs.attributes(native_root .. "/target")).attrs
    ok, why = rebuild.normalize_staging(unsafe)
    check("full inspection rejects junction before changing any earlier flags", not ok and err.is(why, "PROJECT", "layout")
      and assert(fs.attributes(unsafe .. "/a-readonly")).readonly
      and assert(fs.attributes(native_root .. "/target")).attrs == flags, tostring(why))
    assert(ops.remove_owned(unsafe, 0.5))
    check("owned cleanup removes link while retaining outside bytes", fs.read(native_root .. "/target/child.bin") == outside)
  end
  local hard = assert(fs.tempdir { dir = root, prefix = "hardlink-" })
  local outside_file = root .. "/outside-alias.bin"
  assert(fs.write(outside_file, "shared bytes")); assert(fs.write(hard .. "/a-readonly", "first"))
  local link_helper = fs.absolute(T.root .. "/build/test/shell_link_reader.exe")
  local hard_result = assert(proc.run { link_helper, "hardlink", hard .. "/z-alias", outside_file, timeout = "10s" })
  check("independent Windows fixture creates a genuine hardlink", hard_result.code == 0
    and assert(fs.stat(outside_file)).links == 2, T.describe(hard_result))
  if hard_result.code == 0 then
    assert(fs.set_attributes(outside_file, { readonly = true, hidden = true }))
    assert(fs.set_attributes(hard .. "/a-readonly", { readonly = true }))
    local outside_flags = assert(fs.attributes(outside_file)).attrs
    ok, why = rebuild.normalize_staging(hard)
    check("hardlink refusal precedes all normalization and preserves alias metadata", not ok and err.is(why, "PROJECT", "layout")
      and assert(fs.attributes(hard .. "/a-readonly")).readonly
      and assert(fs.attributes(outside_file)).attrs == outside_flags and fs.read(outside_file) == "shared bytes", tostring(why))
    -- These fixture aliases are both owned; clear deliberately before scratch cleanup.
    assert(fs.set_attributes(outside_file, { readonly = false }))
    -- TAR preserves two names for one internal file; ZIP may copy their bytes.
    assert(fs.write(payload .. "/bin/tool.exe", artifact_bytes))
    local internal = assert(proc.run { link_helper, "hardlink",
      payload .. "/bin/alias.exe", payload .. "/bin/tool.exe", timeout = "10s" })
    check("archive source owns both names of its hardlinked file", internal.code == 0
      and assert(fs.stat(payload .. "/bin/tool.exe")).links == 2, T.describe(internal))
    if internal.code == 0 then
      local linked_archive = root .. "/internal-links.tar"
      assert(archive.pack(linked_archive, payload, nil, { timeout = "10s" }))
      local linked_pin = clone(pin); linked_pin.archive_sha256 = assert(hash.file("sha256", linked_archive))
      ok, why, cleanup, stage = rebuild.restore(linked_archive, root .. "/linked-install", linked_pin)
      check("extracted internal hardlinks are rejected and owned archive staging is cleaned", not ok
        and err.is(why, "PROJECT", "layout") and not cleanup and not fs.exists(stage)
        and not fs.exists(root .. "/linked-install"), tostring(why))
    end
  end
  local denied = err.new("FS", "access", "controlled cleanup denial")
  local real_remove = ops.remove_owned
  ops.remove_owned = function() return nil, denied end
  ok, why, cleanup, stage = rebuild.restore(changed, root .. "/never-published", pin)
  ops.remove_owned = real_remove
  check("restore preserves primary and cleanup failures with exact leftover identity", not ok
    and err.is(why, "PROJECT", "hash") and cleanup == denied and fs.exists(stage) == "directory"
    and not fs.exists(root .. "/never-published"), tostring(why))
  assert(ops.remove_owned(stage, 0.5))

  -- Adapter behavior is mocked; journal persistence and downloaded bytes are real.
  local artifact = root .. "/release.zip"
  assert(fs.write(artifact, artifact_bytes))
  local timeout = err.new("HTTP", "timeout", "accepted response was lost")
  local unavailable = err.new("PROJECT", "remote_status", "listing temporarily unavailable")
  local function remote_case(label)
    local spec = { repository = "example/project", release_id = 17, name = "tool-win64.zip", size = #artifact_bytes,
      sha256 = pin.tool_sha256, file = artifact, journal = root .. "/" .. label .. ".json", scratch = root }
    local state = { lookups = 0, uploads = 0, downloads = 0, deletes = 0, asset = false, bytes = artifact_bytes }
    local asset = { repository = spec.repository, release_id = spec.release_id, name = spec.name,
      id = 23, size = spec.size, sha256 = spec.sha256, state = "uploaded" }
    local remote = {
      lookup = function()
        state.lookups = state.lookups + 1
        if state.lookup_error and state.lookups > 1 then return nil, state.lookup_error end
        return state.asset
      end,
      upload = function()
        state.uploads = state.uploads + 1
        local saved = assert(json.decode(assert(fs.read(spec.journal))))
        state.intent_before_upload = saved.attempted == true and saved.sha256 == spec.sha256 and saved.release_id == spec.release_id
        if not state.leave_absent then state.asset = clone(asset) end
        if state.throw_upload then error(timeout) end
        return nil, timeout
      end,
      download = function(got, path)
        state.downloads = state.downloads + 1; state.downloaded_id = got.id; state.download_path = path
        assert(fs.write(path, state.bytes))
        if state.throw_download then error(state.throw_download) end
        return true
      end,
      delete = function() state.deletes = state.deletes + 1; error("destructive remote operation forbidden") end,
    }
    return spec, state, remote, asset
  end
  local spec, state, remote = remote_case("accepted-timeout")
  local confirmed = assert(publisher().reconcile(remote, spec))
  check("accepted timeout resolves via metadata and exact-ID downloaded bytes", confirmed.status == "confirmed"
    and state.intent_before_upload and state.lookups == 2 and state.uploads == 1 and state.downloads == 1
    and state.downloaded_id == 23 and state.deletes == 0 and not fs.exists(fs.dirname(state.download_path)))
  confirmed = assert(publisher().reconcile(remote, spec)) -- fresh module models a restarted caller
  check("restarted caller reverifies persisted publication without another upload", confirmed.asset_id == 23
    and state.lookups == 3 and state.uploads == 1 and state.downloads == 2 and state.deletes == 0)
  state.asset.id = 24
  ok, why = publisher().reconcile(remote, spec)
  check("replacement ID conflicts with already confirmed remote identity", not ok and err.is(why, "PROJECT", "conflict")
    and state.uploads == 1 and state.downloads == 2 and state.deletes == 0, tostring(why))
  spec, state, remote = remote_case("absent-timeout"); state.leave_absent = true
  ok, why = publisher().reconcile(remote, spec)
  check("unresolved upload retains original timeout and persisted intent", not ok and err.is(why, "PROJECT", "pending")
    and why.upload_error == timeout and assert(json.decode(assert(fs.read(spec.journal)))).attempted == true
    and state.uploads == 1 and state.downloads == 0, tostring(why))
  ok, why = publisher().reconcile(remote, spec)
  check("uncertain absence never causes automatic upload or deletion retry", not ok and err.is(why, "PROJECT", "pending")
    and state.uploads == 1 and state.deletes == 0 and state.lookups == 3, tostring(why))
  spec, state, remote = remote_case("listing-failure"); state.lookup_error = unavailable
  ok, why = publisher().reconcile(remote, spec)
  check("failed post-upload listing preserves both diagnoses and cannot prove absence", not ok and err.is(why, "PROJECT", "pending")
    and why.upload_error == timeout and why.lookup_error == unavailable and state.uploads == 1 and state.downloads == 0, tostring(why))
  spec, state, remote = remote_case("unwritable-intent"); spec.journal = root .. "/absent-parent/intent.json"
  ok, why = publisher().reconcile(remote, spec)
  check("failure to persist intent prevents any upload attempt", not ok and err.is(why, "FS", "notfound")
    and state.lookups == 1 and state.uploads == 0 and state.downloads == 0, tostring(why))
  spec, state, remote = remote_case("raised-upload"); state.throw_upload = true
  confirmed = assert(publisher().reconcile(remote, spec))
  check("upload exception after acceptance can still be independently confirmed", confirmed.status == "confirmed"
    and state.uploads == 1 and state.downloads == 1 and state.deletes == 0)
  for _, field in ipairs { "repository", "release_id", "name", "size", "sha256", "state" } do
    local asset
    spec, state, remote, asset = remote_case("conflict-" .. field)
    state.asset = clone(asset); state.asset[field] = field == "size" and spec.size + 1 or "different"
    ok, why = publisher().reconcile(remote, spec)
    check("remote " .. field .. " mismatch prevents confirmation without replacement", not ok and err.is(why, "PROJECT", "conflict")
      and state.uploads == 0 and state.downloads == 0 and state.deletes == 0, tostring(why))
  end
  local asset
  spec, state, remote, asset = remote_case("missing-digest"); state.asset = clone(asset); state.asset.sha256 = nil
  ok, why = publisher().reconcile(remote, spec)
  check("missing remote digest is never invented from the local pin", not ok and err.is(why, "PROJECT", "conflict")
    and state.uploads == 0 and state.downloads == 0, tostring(why))
  spec, state, remote = remote_case("corrupt-download"); state.bytes = string.rep("x", #artifact_bytes)
  ok, why, cleanup, stage = publisher().reconcile(remote, spec)
  check("matching metadata cannot bless corrupt same-size downloaded bytes", not ok and err.is(why, "PROJECT", "download")
    and not cleanup and not fs.exists(stage) and state.uploads == 1
    and not assert(json.decode(assert(fs.read(spec.journal)))).confirmed, tostring(why))
  spec, state, remote = remote_case("raised-download"); state.throw_download = unavailable
  ok, why, cleanup, stage = publisher().reconcile(remote, spec)
  check("raised download failure cleans staging and preserves the primary error", not ok and why == unavailable
    and not cleanup and not fs.exists(stage), tostring(why))
  spec, state, remote = remote_case("double-failure"); state.throw_download = unavailable
  ops.remove_owned = function() return nil, denied end
  ok, why, cleanup, stage = publisher().reconcile(remote, spec)
  ops.remove_owned = real_remove
  check("raised verification and cleanup failures both survive with owned leftover path", not ok and why == unavailable
    and cleanup == denied and fs.exists(stage) == "directory" and state.uploads == 1, tostring(why))
  assert(ops.remove_owned(stage, 0.5))
  for _, invalid in ipairs { "false", "null", "42", '"scalar"', "[]" } do
    spec, state, remote = remote_case("invalid-journal")
    assert(fs.write(spec.journal, invalid))
    ok, why = publisher().reconcile(remote, spec)
    check("invalid journal cannot reset attempt protection: " .. invalid, not ok and err.is(why, "PROJECT", "intent")
      and state.lookups == 0 and state.uploads == 0 and fs.read(spec.journal) == invalid, tostring(why))
  end
  spec, state, remote = remote_case("changed-intent")
  assert(publisher().reconcile(remote, spec)); spec.release_id = 18
  ok, why = publisher().reconcile(remote, spec)
  check("changed release cannot reuse prior publication journal", not ok and err.is(why, "PROJECT", "intent")
    and state.uploads == 1 and state.lookups == 2, tostring(why))
  check("all recovery and mocked publication tests retain installed and cached bytes", fs.read(root .. "/installed/bin/tool.exe") == artifact_bytes
    and hash.file("sha256", cached) == pin.archive_sha256)
end
