# Working directories through wrappers

Keep the caller's directory explicit when a wrapper enters a project and
launches another program through its manifest.

These are separate places:

| place | meaning in this recipe |
|---|---|
| project root | the directory containing `manifest.lua` and the pinned `kuu.exe` |
| caller cwd | the directory from which the user launched the wrapper |
| wrapper cwd | initially the caller cwd; this wrapper leaves its own cwd alone |
| child cwd | the validated directory explicitly supplied to `task.exec` |
| module root | the base for project `require` calls; `rt.root()` starts at a file program's directory and becomes the project root for `kuu run` |

`kuu run` finds the manifest above its starting directory and enters that
project **before loading the manifest**. Therefore `fs.cwd()` at the top of
`manifest.lua` returns the project root, not the original invocation directory.
Capture the caller cwd in the wrapper first and pass it as an argument. No
invocation-directory API or process-wide `fs.chdir` in the task is needed.

## Complete wrapper and manifest

Use this layout. The runtime can be downloaded or committed according to the
project's pinned-runtime policy in [Adopting kuu](adopting.md).

```text
repo/
  kuu.exe
  manifest.lua
  tools/
    from-here.lua
    report.lua
```

Save this as `tools/from-here.lua`. On the file route, kuu sets `rt.root()` to
the script's directory without changing cwd. The wrapper locates its project
from that directory, even when launched from somewhere unrelated. It launches
the project's runtime with the project root as cwd so the intended manifest
is selected. `--cwd` belongs to this task's schema, not to the `kuu run` verb.

```lua
global none
global <const> require, ipairs, io, os, tostring

local fs, rt, proc = require "fs", require "rt", require "proc"
local caller_cwd = fs.cwd()
local project_root = fs.absolute(fs.join(rt.root(), ".."))
local command = {
  fs.join(project_root, "kuu.exe"), "run", "report", "--cwd", caller_cwd, "--",
  cwd = project_root, inherit = true, timeout = "1m",
}
for _, value in ipairs(rt.args) do command[#command + 1] = value end
local result, why = proc.run(command)
if not result then
  io.stderr:write("from-here: ", tostring(why), "\n")
  os.exit(1)
end
if result.status ~= "exit" then
  io.stderr:write("from-here: child status ", result.status, "\n")
  os.exit(1)
end
os.exit(result.code)
```

Save this as `manifest.lua`. Require an absolute directory: resolving a
relative `--cwd` here would resolve it against the project root, after the
original caller context was lost. A directory link is accepted if its target
is a directory. Existence is checked before launch; the actual launch still
reports an error if the directory disappears or becomes inaccessible later.

```lua
global none
global <const> require, ipairs

local task, fs, rt, err = require "task", require "fs", require "rt", require "err"
local project_root = fs.absolute(rt.root())
task.tool "kuu" { exe = "kuu.exe", output = "ndjson", timeout = "20s" }

task "report" {
  desc = "report from the wrapper's original working directory",
  args = {
    { "--cwd", type = "string", required = true, help = "absolute caller directory" },
    { "argv", type = "string", rest = true, help = "arguments for the report program" },
  },
  run = function(opts)
    local cwd = opts.cwd:gsub("\\", "/")
    if not cwd:match("^%a:/") and not cwd:match("^//[^/]+/[^/]+") then
      return nil, err.new("PROJECT", "cwd", "--cwd must be an absolute drive or UNC path")
    end
    local info, why = fs.stat(cwd)
    if not info then return nil, why end
    if info.kind ~= "directory" then
      return nil, err.new("PROJECT", "cwd", "--cwd must name a directory")
    end
    local command = {
      tool = "kuu", fs.join(project_root, "tools/report.lua"), cwd = fs.absolute(cwd),
    }
    for _, value in ipairs(opts.argv) do command[#command + 1] = value end
    return task.exec(command)
  end,
}
```

Save this small diagnostic child as `tools/report.lua`; replace its body with
the real operation when adopting the recipe. Its script path is absolute, so
changing child cwd cannot select a different script. Its `require` root stays
at `tools/`, while relative filesystem operations use the explicit caller cwd.

```lua
global none
global <const> require, io

local fs, rt, json = require "fs", require "rt", require "json"
io.write(json.encode {
  cwd = fs.cwd(), module_root = rt.root(), argv = json.array(rt.args),
}, "\n")
```

Launch the wrapper by its path using the project's runtime, from the project
root, a nested directory, or an unrelated directory. For example, in
PowerShell, `& 'C:\work\my project\kuu.exe' 'C:\work\my project\tools\from-here.lua' 'a file.txt' --help` sends both argument values to
the report program. The wrapper supplies the task parser's first `--`;
later `--`, `--help`, and `--cwd` values are ordinary child arguments. The
file route itself does not consume them as task options.

Use argument arrays at every process boundary. Do not join them into command
text or add quote characters around paths. Empty arguments, embedded double
quotes and trailing backslashes are preserved by kuu's Windows argv encoding;
the initial shell must first deliver the intended values to the wrapper.
Windows filenames cannot contain a double quote: test paths with spaces and
apostrophes, and double quotes inside **argument values** instead.

The wrapper checks process status before forwarding an exit code. An ordinary
nonzero exit passes from the child through `task.exec`, the nested `kuu run`,
and the wrapper. A launch error or timeout is reported as failure, not treated
as a successful exit. See [Process recipes](process-recipes.md) for captured
diagnostics and accepted nonzero codes, and [Tasks](task.md) for child records
and JSON reporting.
