-- toolchain.lua -- the lock, hydrate, and verify against the loopback fixture:
-- a zip tool with strip, notice, and a version check, and a bare exe tool.
global none
global <const> require, ipairs, tostring, tonumber, type, string, table, pcall

return function(T)
  local check, contains, starts = T.check, T.contains, T.starts
  local fs = require "fs"
  local hash = require "hash"
  local http = require "http"
  local json = require "json"
  local proc = require "proc"
  local err = require "err"
  local toolchain = require "toolchain"

  local fixture = T.root .. "/build/test/http_fixture.exe"
  if fs.exists(fixture) ~= "file" then
    check("the http fixture server is built (make fixtures)", false, fixture)
    return
  end
  local work = fs.absolute(T.work .. "/toolchain")
  fs.remove(work, { recursive = true })
  local files = work .. "/files"
  fs.mkdir(files)
  fs.mkdir(work .. "/tools")

  -- a fake tool: kuu.exe itself, renamed, in a versioned directory with a notice
  local src = work .. "/src/fake-1.0/bin"
  fs.mkdir(src)
  fs.copy(T.exe, src .. "/fake.exe")
  fs.write(work .. "/src/fake-1.0/LICENSE", "MIT-ish notice text\n")
  local tar = proc.run { "C:\\Windows\\System32\\tar.exe", "-a", "-cf", (files .. "/fake.zip"):gsub("/", "\\"), "-C", (work .. "/src"):gsub("/", "\\"), "fake-1.0" }
  check("Windows' tar.exe builds the zip fixture", tar and tar.code == 0, tar and tar.err)
  fs.copy(T.exe, files .. "/plain.exe")
  local zip_sha = hash.file("sha256", files .. "/fake.zip")
  local zip_bytes = fs.stat(files .. "/fake.zip").size
  local exe_sha = hash.file("sha256", files .. "/plain.exe")
  local notice_sha = hash.sum("sha256", "MIT-ish notice text\n")

  local server <close> = proc.start { fixture, (files:gsub("/", "\\")), stream = true }
  local first = server:read("line", "10s")
  local port = tonumber((first or ""):match("^PORT (%d+)$"))
  check("the fixture reports its port", port ~= nil, tostring(first))
  if port == nil then return end
  local base = "http://127.0.0.1:" .. port
  local function hits(path)
    local r = http.get(base .. "/hits?path=" .. path)
    return r and tonumber(r.body) or -1
  end

  local lock_path = work .. "/tools/lock.json"
  local root = work .. "/.tools"
  local lock = {
    schema = 1,
    tools = {
      fake = { version = "0.3", url = base .. "/files/fake.zip", sha256 = zip_sha:upper(), bytes = zip_bytes, strip = 1,
        bin = "bin/fake.exe", check = json.array { "--version" }, expect = "kuu 0.3", license = "MIT", notice = "LICENSE", noticeSha256 = notice_sha },
      plain = { url = base .. "/files/plain.exe", sha256 = exe_sha },
    },
  }
  local function write_lock(l) fs.write(lock_path, json.encode(l, { pretty = true })) end
  write_lock(lock)

  -- read ---------------------------------------------------------------------------------
  local parsed, e = toolchain.read(lock_path)
  check("read accepts the lock, lowercases hashes, infers kind and bin", parsed and parsed.names[1] == "fake" and parsed.names[2] == "plain"
    and parsed.tools.fake.sha256 == zip_sha and parsed.tools.fake.kind == "zip" and parsed.tools.plain.kind == "exe" and parsed.tools.plain.bin == "plain.exe", tostring(e))

  -- hydrate, twice ------------------------------------------------------------------------
  local steps = {}
  local report, e2 = toolchain.hydrate(lock_path, root, { progress = function(step, name) steps[#steps + 1] = step .. ":" .. name end })
  check("hydrate installs every tool", report and report.ok and #report.tools == 2 and report.tools[1].action == "hydrated" and report.tools[2].action == "hydrated", tostring(e2))
  check("the executables are in place under the root", fs.exists(root .. "/fake/bin/fake.exe") == "file" and fs.exists(root .. "/plain/plain.exe") == "file"
    and fs.exists(root .. "/fake/LICENSE") == "file")
  check("the report paths are absolute and point at the executables", report and report.tools[1].path == fs.absolute(root .. "/fake/bin/fake.exe"), report and report.tools[1].path)
  check("hydrate went missing, download, unpack, check for the zip tool", table.concat(steps, " "):find("missing:fake download:fake unpack:fake check:fake", 1, true) ~= nil, table.concat(steps, " "))
  local stamp_text = fs.read(root .. "/fake.json", { encoding = "utf-8" })
  local stamp = stamp_text and json.decode(stamp_text) or nil
  check("the stamp records the inputs, the executable's hash, the notice's hash, and the kuu that hydrated",
    stamp and stamp.sha256 == zip_sha and stamp.binSha256 == exe_sha and stamp.noticeSha256 == notice_sha and #stamp.key == 64 and stamp.kuu == require("rt").version, fs.read(root .. "/fake.json"))
  check("no temporary directory is left behind", not fs.exists(root .. "/fake.partial") and not fs.exists(root .. "/plain.partial"))
  check("the downloads are cached under the root", fs.exists(root .. "/.downloads/fake-" .. zip_sha:sub(1, 16) .. ".zip") == "file")
  check("each archive was fetched once", hits("/files/fake.zip") == 1 and hits("/files/plain.exe") == 1)

  report, e2 = toolchain.hydrate(lock_path, root)
  check("a second hydrate finds everything current and fetches nothing", report and report.ok and report.tools[1].action == "current" and report.tools[2].action == "current"
    and hits("/files/fake.zip") == 1, tostring(e2))

  -- verify ------------------------------------------------------------------------------
  report, e2 = toolchain.verify(lock_path, root)
  check("verify passes", report and report.ok and report.tools[1].status == "ok", tostring(e2))
  report, e2 = toolchain.verify(lock_path, root, { deep = true })
  check("deep verify passes", report and report.ok, tostring(e2))
  local path, e3 = toolchain.path(lock_path, "fake", root)
  check("toolchain.path gives the executable", path == fs.absolute(root .. "/fake/bin/fake.exe"), tostring(e3))
  local ok, raised = pcall(toolchain.path, lock_path, "ghost", root)
  check("toolchain.path raises TOOLCHAIN unknown for a name the lock lacks", not ok and err.is(raised, "TOOLCHAIN", "unknown"))

  -- damage -------------------------------------------------------------------------------
  fs.write(root .. "/fake/bin/fake.exe", "not the tool")
  report, e2 = toolchain.verify(lock_path, root)
  check("a shallow verify does not notice a damaged executable", report and report.ok, tostring(e2))
  report, e2 = toolchain.verify(lock_path, root, { deep = true })
  check("a deep verify reports it corrupt, with the report on the error", report == nil and err.is(e2, "TOOLCHAIN", "unverified") and contains(e2.message, "fake is corrupt")
    and e2.report.tools[1].status == "corrupt" and e2.report.tools[2].status == "ok", tostring(e2))
  report, e2 = toolchain.hydrate(lock_path, root, { deep = true })
  check("hydrate --deep replaces it from the cache without a download", report and report.ok and report.tools[1].action == "replaced" and hits("/files/fake.zip") == 1
    and hash.file("sha256", root .. "/fake/bin/fake.exe") == exe_sha, tostring(e2))
  fs.write(root .. "/fake/LICENSE", "altered")
  report, e2 = toolchain.verify(lock_path, root, { deep = true })
  check("a deep verify covers the notice too", report == nil and e2.report.tools[1].status == "corrupt", tostring(e2))
  toolchain.hydrate(lock_path, root, { deep = true })

  fs.remove(root .. "/plain.json")
  report, e2 = toolchain.verify(lock_path, root)
  check("a tool without a stamp is missing", report == nil and e2.report.tools[2].status == "missing", tostring(e2))
  path, e3 = toolchain.path(lock_path, "plain", root)
  check("toolchain.path refuses a missing tool", path == nil and err.is(e3, "TOOLCHAIN", "missing"), tostring(e3))
  report = toolchain.hydrate(lock_path, root)
  check("hydrate stamps it again", report and report.ok and report.tools[2].action == "hydrated" and hits("/files/plain.exe") == 1)

  -- the lock moves on --------------------------------------------------------------------
  lock.tools.fake.expect = "kuu 0.3 (Lua"
  write_lock(lock)
  report, e2 = toolchain.verify(lock_path, root)
  check("a changed lock entry makes the tool stale", report == nil and e2.report.tools[1].status == "stale" and e2.report.tools[2].status == "ok", tostring(e2))
  report, e2 = toolchain.hydrate(lock_path, root)
  check("hydrate re-installs a stale tool from the cache", report and report.ok and report.tools[1].action == "replaced" and hits("/files/fake.zip") == 1, tostring(e2))

  -- refusals ------------------------------------------------------------------------------
  lock.tools.fake.expect = "definitely not this"
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("a tool that reports the wrong version is refused and not installed", report == nil and err.is(e2, "TOOLCHAIN", "mismatch") and contains(e2.message, "did not report")
    and not fs.exists(root .. "/fake.partial"), tostring(e2))
  report, e2 = toolchain.verify(lock_path, root)
  check("after a refused replace the old install stands and reads as stale, never ok", report == nil and e2.report.tools[1].status == "stale"
    and hash.file("sha256", root .. "/fake/bin/fake.exe") == exe_sha, tostring(e2))
  lock.tools.fake.expect = "kuu 0.3"

  lock.tools.fake.sha256 = string.rep("0", 64)
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("a download that hashes wrong is refused", report == nil and err.is(e2, "TOOLCHAIN", "mismatch") and contains(e2.message, "hashes to " .. zip_sha), tostring(e2))
  check("the wrong download is not kept", not fs.exists(root .. "/.downloads/fake-0000000000000000.zip") and not fs.exists(root .. "/.downloads/fake-0000000000000000.zip.partial"))
  check("the fetch happened, since that hash was not cached", hits("/files/fake.zip") == 2)
  lock.tools.fake.sha256 = zip_sha

  lock.tools.fake.bytes = zip_bytes + 1
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("a size that disagrees with the lock is refused, even from the cache", report == nil and err.is(e2, "TOOLCHAIN", "mismatch") and contains(e2.message, "disagrees with itself"), tostring(e2))
  lock.tools.fake.bytes = zip_bytes

  lock.tools.fake.bin = "bin/other.exe"
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("an archive without the named executable is refused", report == nil and err.is(e2, "TOOLCHAIN", "unpack") and contains(e2.message, "holds no 'bin/other.exe'"), tostring(e2))
  lock.tools.fake.bin = "bin/fake.exe"

  lock.tools.fake.notice = "COPYING"
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("an archive without the named notice is refused", report == nil and err.is(e2, "TOOLCHAIN", "notice"), tostring(e2))
  lock.tools.fake.notice = "LICENSE"

  lock.tools.fake.url = base .. "/files/absent.zip"
  lock.tools.fake.sha256 = string.rep("1", 64) -- not in the cache, so the url is consulted
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("a 404 is a download failure that names the url", report == nil and err.is(e2, "TOOLCHAIN", "download") and contains(e2.message, "absent.zip answered 404"), tostring(e2))
  lock.tools.fake.url = base .. "/files/fake.zip"
  lock.tools.fake.sha256 = zip_sha
  write_lock(lock)
  report, e2 = toolchain.hydrate(lock_path, root)
  check("the lock restored, hydrate heals everything without a download", report and report.ok and hits("/files/fake.zip") == 2, tostring(e2))

  local function refused(mutate, needle)
    local copy = json.decode(json.encode(lock))
    mutate(copy)
    write_lock(copy)
    local none, e4 = toolchain.read(lock_path)
    return none == nil and err.is(e4, "TOOLCHAIN", "badlock") and contains(e4.message, needle), tostring(e4)
  end
  check("badlock: an unknown key", refused(function(l) l.tools.fake.sha265 = "x" end, "unknown key 'sha265'"))
  check("badlock: a short hash", refused(function(l) l.tools.fake.sha256 = "abc" end, "64 hex digits"))
  check("badlock: bin escaping the tool", refused(function(l) l.tools.fake.bin = "../evil.exe" end, "inside the tool"))
  check("badlock: an absolute bin", refused(function(l) l.tools.fake.bin = "C:/evil.exe" end, "inside the tool"))
  check("badlock: a name with a slash", refused(function(l) l.tools["a/b"] = l.tools.plain end, "plain word"))
  check("badlock: an unknown kind", refused(function(l) l.tools.plain.kind = "msi" end, "kind must be"))
  check("badlock: a url that tells no kind", refused(function(l) l.tools.plain.url = base .. "/files/plain" end, "kind must be"))
  check("badlock: strip on an exe", refused(function(l) l.tools.plain.strip = 1 end, "archives only"))
  check("badlock: check without expect or version", refused(function(l) l.tools.plain.check = json.array { "--version" } end, "needs expect or version"))
  check("badlock: noticeSha256 without notice", refused(function(l) l.tools.plain.noticeSha256 = notice_sha end, "needs notice"))
  check("badlock: a wrong schema", refused(function(l) l.schema = 2 end, "schema"))
  check("badlock: a non-http url", refused(function(l) l.tools.plain.url = "file:///x.exe" end, "http"))
  fs.write(lock_path, "{ not json")
  local none, e5 = toolchain.read(lock_path)
  check("badlock: not JSON", none == nil and err.is(e5, "TOOLCHAIN", "badlock") and contains(e5.message, "not valid JSON"), tostring(e5))
  none, e5 = toolchain.read(work .. "/nowhere.json")
  check("a missing lock is TOOLCHAIN nolock", none == nil and err.is(e5, "TOOLCHAIN", "nolock"), tostring(e5))
  write_lock(lock)

  -- the verbs ------------------------------------------------------------------------------
  local r = T.kuu({ "verify", "--lock", lock_path, "--root", root, "--json" })
  local envelope = r.code == 0 and json.decode(r.out) or nil
  check("kuu verify --json reports ok with every tool", envelope and envelope.ok == true and #envelope.result.tools == 2 and envelope.result.tools[1].status == "ok", T.describe(r))
  fs.remove(root .. "/fake.json")
  r = T.kuu({ "verify", "--lock", lock_path, "--root", root })
  check("kuu verify exits 1 and names what is wrong", r.code == 1 and contains(r.out, "missing   fake") and contains(r.err, "fake is missing; kuu hydrate repairs this"), T.describe(r))
  r = T.kuu({ "hydrate", "--lock", lock_path, "--root", root })
  check("kuu hydrate repairs it and reports the actions", r.code == 0 and contains(r.out, "hydrated  fake") and contains(r.out, "current   plain") and contains(r.err, "kuu: cached fake:"), T.describe(r))
  r = T.kuu({ "hydrate", "--lock", lock_path, "--root", root, "--json" })
  envelope = r.code == 0 and json.decode(r.out) or nil
  check("kuu hydrate --json is an envelope and prints no progress", envelope and envelope.ok == true and envelope.result.tools[1].action == "current" and r.err == "", T.describe(r))
  r = T.kuu({ "hydrate" }, { cwd = T.work })
  check("kuu hydrate outside a project exits 2 with TASK noproject", r.code == 2 and contains(r.err, "TASK noproject"), T.describe(r))
  -- a project with tools/lock.json: defaults for --lock and --root
  local project = work .. "/proj"
  fs.mkdir(project .. "/tools")
  fs.write(project .. "/tasks.lua", "")
  fs.copy(lock_path, project .. "/tools/lock.json")
  r = T.kuu({ "hydrate" }, { cwd = project })
  check("inside a project, hydrate defaults to tools/lock.json and .tools", r.code == 0 and fs.exists(project .. "/.tools/fake/bin/fake.exe") == "file" and hits("/files/fake.zip") >= 2, T.describe(r))
  r = T.kuu({ "verify", "--deep" }, { cwd = project .. "/tools" })
  check("verify --deep from a subdirectory passes", r.code == 0 and contains(r.out, "ok        fake"), T.describe(r))
  r = T.kuu({ "verify", "--nope" }, { cwd = project })
  check("verify refuses unknown options with 2", r.code == 2, T.describe(r))

  http.get(base .. "/quit")
end
