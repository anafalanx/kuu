# A cached native helper and local shortcuts

Use a small project helper when an operation needs a Windows interface outside
kuu's palette. The source [shell_link.c](../examples/shell_link.c) creates a
Shell Link through `IShellLinkW` and `IPersistFile`; it is supplied with this
repository, not embedded as a Lua module. Copy it into `native/shell_link.c`
in the adopting project. Its interface is:

```text
shell_link.exe create LINK TARGET CWD [ARG ...]
```

All three paths are absolute. TARGET is the executable path alone, CWD is its
working directory, and each following value is a separate child argument.
The helper encodes those arguments using Windows C-runtime quoting, including
empty values, embedded quotes and trailing backslashes. It creates LINK without
replacing an existing file. It prints operation/HRESULT diagnostics to stderr
and fails if creation or publication fails. The APIs are documented by
Microsoft: [Shell Links](https://learn.microsoft.com/en-us/windows/win32/shell/links),
[SetArguments](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishelllinkw-setarguments),
[IPersistFile::Save](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-ipersistfile-save),
and [C argument parsing](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments).

## Inputs and ownership

Provision the project's pinned compiler under `.tools/msys2/ucrt64`, following
the complete [UCRT64 package closure](toolchain.md#the-ucrt64-pins). No compiler
is installed on the machine. Save the reviewed package list and the expected
installed compiler hash in `toolchain.lock.json`:

```json
{
  "v": 1,
  "compiler_sha256": "REPLACE_WITH_REVIEWED_GCC_EXE_SHA256",
  "packages": [
    { "file": "REPLACE_WITH_EACH_PINNED_PACKAGE_FILENAME", "sha256": "REPLACE_WITH_REVIEWED_PACKAGE_SHA256" }
  ]
}
```

Replace the placeholders with the **whole** reviewed closure, not just gcc's
package. Provisioning must verify those archives before extraction; record the
compiler digest from that verified installation. Do not repair a pin from
unexpected installed bytes. The recipe hashes the complete lockfile and checks
the actual compiler driver against its pin. It does not re-hash every installed
header, library or compiler subprocess on each cache hit; those remain part of
the project's trusted, exclusively maintained toolchain installation.

Save [owned_ops.lua](cleanup.md#a-project-module) at the project root. Ignore
`/.tools/`, `/.cache/`, `/.local/`, and `/.kuu/`. The generated helper cache and
`.local/native-helper/shell_link.exe` belong exclusively to this recipe.
`.local/project.lnk` is its one replaceable shortcut. No desktop, Start menu,
user profile or machine-wide path is modified.

This uses the cleanup recipe's APIs from 0.12. Require
`rt.version_at_least(0, 12)` and adopt the project's approved runtime by hash.

## Build and verify a cache entry

Save as `automation/native_helper.lua`. Its key includes the source bytes, the
actual build-module bytes and flags, the complete toolchain lockfile, and the
verified compiler-driver digest. A recipe edit therefore invalidates the cache
even when the C source stays unchanged. Every reuse checks the receipt and the
cached executable hash. Corruption is an error with the exact cache path; the
recipe never silently executes, deletes or repairs a corrupt cache entry.

```lua
global none
global <const> require, ipairs, type, tostring, table
local fs, rt, task, hash = require "fs", require "rt", require "task", require "hash"
local json, err, ops = require "json", require "err", require "owned_ops"
local root = fs.absolute(rt.root())
local M = {}
local FLAGS = { "-std=c23", "-O2", "-Wall", "-Wextra", "-Werror", "-municode", "-static", "-s" }
local LIBRARIES = { "-lole32", "-luuid" }

local function digest(value)
  return type(value) == "string" and #value == 64 and value:match("^%x+$") ~= nil
end
local function failure(code, message, cause)
  return nil, err.new("PROJECT", code, message .. (cause and (": " .. tostring(cause)) or ""), { cause = cause })
end
local function ordinary(path, kind)
  local info, why = fs.stat(path, { follow = false })
  if not info then return nil, why end
  if info.kind ~= kind or info.reparse then return failure("cache", "expected ordinary " .. kind .. ": " .. path) end
  return info
end
local function inputs()
  local lock, why = fs.read(root .. "/toolchain.lock.json", { maxbytes = "256K" })
  if not lock then return nil, why end
  local pins, parse_error = json.decode(lock)
  if pins == nil then return nil, parse_error end
  if type(pins) ~= "table" or pins.v ~= 1 or not digest(pins.compiler_sha256)
      or type(pins.packages) ~= "table" or not json.is_array(pins.packages) or #pins.packages == 0 then
    return failure("pins", "toolchain.lock.json requires v=1, compiler_sha256 and the complete pinned packages array")
  end
  for _, package in ipairs(pins.packages) do
    if type(package) ~= "table" or type(package.file) ~= "string" or package.file == "" or not digest(package.sha256) then
      return failure("pins", "each toolchain package needs its reviewed filename and SHA-256")
    end
  end
  local compiler = task.command { tool = "cc" }
  local actual, hash_error = hash.file("sha256", compiler[1])
  if not actual then return nil, hash_error end
  if actual ~= pins.compiler_sha256:lower() then return failure("compiler", "installed gcc does not match compiler_sha256") end
  local source, source_error = fs.read(root .. "/native/shell_link.c", { maxbytes = "256K" })
  if not source then return nil, source_error end
  local builder, builder_error = fs.read(root .. "/automation/native_helper.lua", { maxbytes = "256K" })
  if not builder then return nil, builder_error end
  local identity = {
    source_sha256 = hash.sum("sha256", source),
    recipe_sha256 = hash.sum("sha256", builder .. "\0" .. json.encode(json.array(FLAGS)) .. json.encode(json.array(LIBRARIES))),
    toolchain_sha256 = hash.sum("sha256", lock), compiler_sha256 = actual,
  }
  identity.key = hash.sum("sha256", table.concat({ identity.source_sha256, identity.recipe_sha256,
    identity.toolchain_sha256, identity.compiler_sha256 }, ":"))
  identity.source = source
  return identity
end
local function cached(directory, expected)
  local info, why = ordinary(directory, "directory")
  if not info then return failure("cache", "invalid cache directory " .. directory, why) end
  local receipt_info, receipt_error = ordinary(directory .. "/receipt.json", "file")
  if not receipt_info then return failure("cache", "invalid cache receipt at " .. directory, receipt_error) end
  local text, read_error = fs.read(directory .. "/receipt.json", { maxbytes = "16K" })
  if not text then return failure("cache", "cannot read cache receipt at " .. directory, read_error) end
  local receipt = json.decode(text)
  if type(receipt) ~= "table" or receipt.v ~= 1 or not digest(receipt.executable_sha256) then
    return failure("cache", "malformed cache receipt at " .. directory)
  end
  for _, field in ipairs { "key", "source_sha256", "recipe_sha256", "toolchain_sha256", "compiler_sha256" } do
    if receipt[field] ~= expected[field] then return failure("cache", "cache receipt disagrees on " .. field .. " at " .. directory) end
  end
  local file, file_error = ordinary(directory .. "/shell_link.exe", "file")
  if not file then return failure("cache", "invalid cached executable at " .. directory, file_error) end
  local actual, hash_error = hash.file("sha256", directory .. "/shell_link.exe")
  if not actual then return failure("cache", "cannot hash cached executable at " .. directory, hash_error) end
  if actual ~= receipt.executable_sha256 then return failure("cache", "cached executable hash mismatch at " .. directory) end
  return receipt
end
local function finish(stage, ok, primary)
  local removed, cleanup = ops.remove_owned(stage, 0.5)
  if ok then
    if not removed then return nil, cleanup end
    return true
  end
  return nil, primary, not removed and cleanup or nil
end
local function install(cache, receipt)
  local directory = root .. "/.local/native-helper"
  local made, why = fs.mkdir(directory)
  if not made then return nil, why end
  local target = directory .. "/shell_link.exe"
  local existing, absent = fs.stat(target, { follow = false })
  if existing then
    if existing.kind ~= "file" or existing.reparse then return failure("cache", "refusing non-file helper target: " .. target) end
    if hash.file("sha256", target) == receipt.executable_sha256 then return true end
  elseif not err.is(absent, "FS", "notfound") then return nil, absent end
  local stage, stage_error = fs.tempdir { dir = directory, prefix = ".stage-" }
  if not stage then return nil, stage_error end
  local bytes, read_error = fs.read(cache .. "/shell_link.exe", { maxbytes = "16M" })
  if not bytes then return finish(stage, nil, read_error) end
  if hash.sum("sha256", bytes) ~= receipt.executable_sha256 then
    return finish(stage, nil, err.new("PROJECT", "cache", "cache changed before helper installation: " .. cache))
  end
  local written, write_error = fs.write(stage .. "/shell_link.exe", bytes)
  if not written then return finish(stage, nil, write_error) end
  local placed, place_error = fs.rename(stage .. "/shell_link.exe", target, { replace = true })
  return finish(stage, placed, place_error)
end

function M.ensure()
  local expected, why = inputs()
  if not expected then return nil, why end
  local base = root .. "/.cache/native-helper"
  local directory = base .. "/" .. expected.key
  local info, absent = fs.stat(directory, { follow = false })
  local receipt, reused = nil, info ~= nil
  if info then
    receipt, why = cached(directory, expected)
    if not receipt then return nil, why end
  else
    if not err.is(absent, "FS", "notfound") then return nil, absent end
    local made, make_error = fs.mkdir(base)
    if not made then return nil, make_error end
    local stage, stage_error = fs.tempdir { dir = base, prefix = ".stage-" }
    if not stage then return nil, stage_error end
    local published, primary, cleanup = ops.publish(stage, directory, function(path)
      local written, write_error = fs.write(path .. "/shell_link.c", expected.source)
      if not written then return nil, write_error end
      local spec = { tool = "cc", cwd = path, timeout = "1m", env = {
        PATH = root .. "/.tools/msys2/ucrt64/bin", CPATH = false, C_INCLUDE_PATH = false,
        CPLUS_INCLUDE_PATH = false, OBJC_INCLUDE_PATH = false, COMPILER_PATH = false,
        LIBRARY_PATH = false, GCC_EXEC_PREFIX = false,
      } }
      for _, flag in ipairs(FLAGS) do spec[#spec + 1] = flag end
      spec[#spec + 1] = "shell_link.c"
      spec[#spec + 1] = "-o"; spec[#spec + 1] = "shell_link.exe"
      for _, library in ipairs(LIBRARIES) do spec[#spec + 1] = library end
      local built, build_error = task.exec(spec)
      if not built then return nil, build_error end
      local executable_hash, hash_error = hash.file("sha256", path .. "/shell_link.exe")
      if not executable_hash then return nil, hash_error end
      local record = { v = 1, executable_sha256 = executable_hash }
      for _, field in ipairs { "key", "source_sha256", "recipe_sha256", "toolchain_sha256", "compiler_sha256" } do
        record[field] = expected[field]
      end
      local saved, save_error = fs.write(path .. "/receipt.json", json.encode(record))
      if not saved then return nil, save_error end
      return cached(path, expected)
    end, 0.5)
    if not published then
      if not cleanup and err.is(primary, "FS", "exists") then
        receipt, why = cached(directory, expected)
        if not receipt then return nil, why end
        reused = true
      else return nil, primary, cleanup end
    else receipt, why = cached(directory, expected) end
    if not receipt then return nil, why end
  end
  local installed, install_error, cleanup = install(directory, receipt)
  if not installed then return nil, install_error, cleanup end
  return { key = expected.key, cache = directory, reused = reused,
    helper = root .. "/.local/native-helper/shell_link.exe", sha256 = receipt.executable_sha256 }
end

function M.shortcut(arguments)
  local built, why, cleanup = M.ensure()
  if not built then return nil, why, cleanup end
  local destination = root .. "/.local/project.lnk"
  local old, absent = fs.stat(destination, { follow = false })
  if old and (old.kind ~= "file" or old.reparse) then return failure("shortcut", "refusing non-file shortcut target: " .. destination) end
  if not old and not err.is(absent, "FS", "notfound") then return nil, absent end
  local stage, stage_error = fs.tempdir { dir = root .. "/.local", prefix = ".shortcut-stage-" }
  if not stage then return nil, stage_error end
  local spec = { tool = "shell_link", "create", stage .. "/project.lnk", root .. "/kuu.exe", root, cwd = root }
  for _, argument in ipairs(arguments) do spec[#spec + 1] = argument end
  local made, make_error = task.exec(spec)
  if not made then return finish(stage, nil, make_error) end
  local placed, place_error = fs.rename(stage .. "/project.lnk", destination, { replace = true })
  local done, failure_error, cleanup_error = finish(stage, placed, place_error)
  if not done then return nil, failure_error, cleanup_error end
  built.shortcut = destination
  return built
end

return M
```

The cache directory is published only after compilation and its receipt are
complete, using a rename without replacement. A competing publisher's entry
is accepted only after the same validation. The literal declared helper path
is installed atomically from the verified cache; this keeps tool discovery
useful even though cache keys vary. The shortcut is likewise created at a fresh
owned path, then atomically replaces only `.local/project.lnk`. A failed replace
leaves the preceding destination intact. A cleanup failure after successful
publication still fails the task and may leave its new output in place.

Compilation runs inside its staging directory with relative source and output
filenames. This avoids passing a Unicode checkout path through the compiler's
linker filename arguments; kuu supplies the working directory through Windows'
Unicode process API. The declared compiler still resolves from the project root.

The recipe requires exclusive maintenance of sources, toolchain and these
generated paths. It does not sandbox linked ancestors or authenticate receipts
against someone who can rewrite the whole project. Receipts detect changed
bytes relative to the recorded build. Primary and secondary cleanup errors are
returned separately; the manifest below reports both. After a cache error,
inspect that exact entry and deliberately remove/rebuild it if appropriate;
do not delete the entire cache or regenerate its receipt from corrupt bytes.

## Declare and call the tools

Save as `manifest.lua`, with the verified project runtime at `kuu.exe`. Loading
the module declares no tasks, creates no cache, and runs no compiler; work
begins only inside the requested task.

```lua
global none
global <const> require, print, io, tostring
local task, fs, rt, json = require "task", require "fs", require "rt", require "json"
local helper = require "automation.native_helper"
task.tool "cc" { exe = ".tools/msys2/ucrt64/bin/gcc.exe", output = "lines", timeout = "1m" }
task.tool "shell_link" { exe = ".local/native-helper/shell_link.exe", output = "none", timeout = "10s" }
local function report(value, why, cleanup)
  if cleanup then io.stderr:write("cleanup also failed: ", tostring(cleanup), "\n") end
  if not value then return nil, why end
  print(json.encode(value))
  return true
end
task "build_helper" {
  desc = "Build or verify the pinned native shortcut helper",
  run = function() return report(helper.ensure()) end,
}
task "shortcut" {
  desc = "Regenerate this checkout's owned local shortcut",
  args = { { "argv", type = "string", rest = true, help = "arguments passed to this project's kuu" } },
  run = function(opts)
    local arguments = opts.argv
    if #arguments == 0 then arguments = { "run", "shortcut_probe" } end
    return report(helper.shortcut(arguments))
  end,
}
task "shortcut_probe" {
  desc = "Show where the shortcut ran and the exact arguments it delivered",
  args = { { "argv", type = "string", rest = true } },
  run = function(opts)
    print(json.encode { cwd = fs.cwd(), exe = rt.exe, argv = json.array(opts.argv) })
    return true
  end,
}
```

Run `kuu run build_helper`, then `kuu run shortcut -- run shortcut_probe -- VALUE`.
The resulting link targets this checkout's `kuu.exe`, with its root as cwd.
Argument values are passed as arrays up to the native helper; do not prequote
them or join shell command text. The helper's encoding targets kuu's Windows
C-runtime argv parsing, not a shell or an arbitrary program's custom parser.

After moving the checkout, rerun `kuu run shortcut`. The content cache can be
reused if its identities and hashes still agree, but the link must be rebuilt:
its executable, arguments containing paths, and working directory are local
values. Do not rely on Windows link tracking to choose the intended checkout.
See [relocation](relocation.md) for other generated absolute-path artifacts.

The repository tests compile this exact source, read the link through an
independent COM fixture and launch its stored target to inspect actual argv
and cwd. Their disposable project aliases this repository's already pinned
compiler tree through a junction to avoid duplicating its thousands of files;
that alias is a test-harness arrangement, not independent provisioning.
