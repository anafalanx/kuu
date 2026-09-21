-- Native fixtures independently establish read-only bits, ACL denial and sharing.
global none
global <const> require, assert, tostring, setmetatable

return function(T)
  local fs, proc, json, err = require "fs", require "proc", require "json", require "err"
  local check = T.check
  local helper = fs.absolute(T.root .. "/build/test/removal_fixture.exe")
  check("independent removal fixture exists", fs.exists(helper) == "file", helper)
  if fs.exists(helper) ~= "file" then return end
  local root = fs.absolute(T.work .. "/removal-" .. require("hash").uuid())
  local function path(relative) return root .. "/" .. relative end
  local function native(command, ...)
    local args = { helper, command, root, ... }
    args.timeout = "10s"
    local result, why = proc.run(args)
    assert(result and result.code == 0, result and T.describe(result) or tostring(why))
    return assert(json.decode(result.out))
  end
  local function inspect(relative) return native("inspect", relative) end
  local function absent(relative) return inspect(relative).exists == false end
  local function same_metadata(a, b)
    return a.exists == b.exists and a.attrs == b.attrs and a.creation == b.creation
      and a.write == b.write and a.change == b.change
  end
  local function access_failure(label, relative, options)
    local removed, why = fs.remove(path(relative), options)
    check(label, removed == nil and err.is(why, "FS", "access"), tostring(why))
    return why
  end
  local function holder(command, ...)
    local args = { helper, command, root, ... }
    args.stream, args.timeout = true, "65s"
    local child = assert(proc.start(args))
    local active = true
    local function release()
      if not active then return end
      assert(fs.write(path(".release"), "release", { atomic = false }))
      local result = assert(child:wait("5s"))
      active = false
      assert(result.code == 0, "native fixture release failed: " .. tostring(result.code))
    end
    local guard = setmetatable({}, { __close = release })
    return guard, release, child
  end
  local function await_ready(child)
    local ready = assert(json.decode(assert(child:read("line", "5s"))))
    assert(ready.ready, "native restriction setup failed: " .. tostring(ready.win32))
  end

  check("native removal fixture setup succeeds", native("setup").ready == true)
  check("native fixture marks root and nested directories read-only", (inspect("tree").attrs & 1) ~= 0
    and (inspect("tree/nested").attrs & 1) ~= 0 and (inspect("tree/nested/deep").attrs & 1) ~= 0)
  check("native fixture marks regular leaves and junctions read-only", (inspect("tree/root.bin").attrs & 1) ~= 0
    and (inspect("tree/outside-link").attrs & 1) ~= 0 and (inspect("tree/dangling-link").attrs & 1) ~= 0)
  local outside_before, sentinel_before = inspect("outside"), inspect("outside/sentinel.bin")
  local sentinel_bytes = assert(fs.read(path("outside/sentinel.bin")))
  check("recursive removal clears read-only root nested directories and leaves", fs.remove(path("tree"), { recursive = true }) == true
    and absent("tree"))
  check("recursive junction removal preserves outside target metadata", same_metadata(outside_before, inspect("outside"))
    and same_metadata(sentinel_before, inspect("outside/sentinel.bin")))
  check("recursive junction removal preserves outside target contents", fs.read(path("outside/sentinel.bin")) == sentinel_bytes)
  check("read-only empty directory removes without recursive option", fs.remove(path("empty")) == true and absent("empty"))
  check("read-only root junction removes its own entry", fs.remove(path("root-link"), { recursive = true }) == true
    and absent("root-link"))
  check("root junction removal preserves target metadata and bytes", same_metadata(outside_before, inspect("outside"))
    and same_metadata(sentinel_before, inspect("outside/sentinel.bin")) and fs.read(path("outside/sentinel.bin")) == sentinel_bytes)
  check("read-only dangling root junction can be removed", fs.remove(path("dangling-root")) == true and absent("dangling-root"))

  do
    local guard <close>, release, child = holder("acl")
    await_ready(child)
    local before = inspect("attr-denied/child")
    local why = access_failure("recursive removal reports attribute-write permission failure", "attr-denied", { recursive = true })
    check("attribute failure identifies the failing nested directory", tostring(why):find("attr%-denied/child") ~= nil)
    check("failed attribute change leaves read-only and other bits unchanged", inspect("attr-denied/child").attrs == before.attrs)
    check("recursive cleanup is partial and does not restore already removed children", absent("attr-denied/child/removed-first.bin")
      and inspect("attr-denied/child").exists and inspect("attr-denied").exists)
    why = access_failure("ordinary native deletion denial is returned", "delete-denied", { recursive = true })
    check("native deletion denial identifies its actual child", tostring(why):find("delete%-denied/blocked%.bin") ~= nil)
    check("denied native deletion leaves the entry present", inspect("delete-denied/blocked.bin").exists == true)
    release()
    check("retry after ACL restoration finishes partial cleanup", fs.remove(path("attr-denied"), { recursive = true }) == true
      and fs.remove(path("delete-denied"), { recursive = true }) == true
      and absent("attr-denied") and absent("delete-denied"))
  end
  assert(fs.remove(path(".release")))
  do
    local guard <close>, release, child = holder("hold", "hold/locked.bin", "60000")
    await_ready(child)
    local before = inspect("hold/locked.bin")
    local why = access_failure("deletion sharing failure is preserved after read-only clearing", "hold", { recursive = true })
    check("native sharing violation code survives attribute handle cleanup", tostring(why):find("Windows error 32", 1, true) ~= nil)
    check("sharing failure identifies its actual child", tostring(why):find("hold/locked%.bin") ~= nil)
    local after = inspect("hold/locked.bin")
    check("failed delete keeps cleared read-only without blind rollback", after.exists and (after.attrs & 1) == 0
      and after.attrs == (before.attrs & ~1))
    check("failed delete preserves bytes and unrelated timestamps", fs.read(path("hold/locked.bin")) == sentinel_bytes
      and after.creation == before.creation and after.write == before.write)
    access_failure("repeated removal remains failed while sharing hold persists", "hold", { recursive = true })
    release()
    check("retry after sharing release finishes partial cleanup", fs.remove(path("hold"), { recursive = true }) == true and absent("hold"))
  end
  local removed, why = fs.remove(path("hold"), { recursive = true })
  check("missing cleanup target remains an explicit notfound failure", removed == nil and err.is(why, "FS", "notfound"), tostring(why))
  check("all cleanup attempts preserve the outside sentinel", same_metadata(outside_before, inspect("outside"))
    and same_metadata(sentinel_before, inspect("outside/sentinel.bin")) and fs.read(path("outside/sentinel.bin")) == sentinel_bytes)
end
