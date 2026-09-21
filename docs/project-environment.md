# Shared project environment and caches

Keep one environment recipe for CLI tools and newly launched editors. Anchor
its paths to the project root, even when `kuu run` starts in a nested directory.
Under `kuu run`, `rt.root()` is the manifest's directory; it is the module
search root, not the caller's original working directory. See
[working directories](working-directories.md) when a child needs that caller's
directory instead.

## A shared module

Save as `automation/project_env.lua`. It computes paths but creates nothing at
module load. Tools create their own caches when needed. Ignore `/.cache/`,
`/.venv/` and `/.tools/` in the project's `.gitignore`.

```lua
global none
global <const> require, ipairs
local fs, rt, task, proc = require "fs", require "rt", require "task", require "proc"
local root = fs.absolute(rt.root())
local M = { root = root }

function M.overlay()
  return {
    UV_CACHE_DIR = root .. "/.cache/uv",
    UV_PROJECT_ENVIRONMENT = root .. "/.venv",
    npm_config_cache = root .. "/.cache/npm",
    GOCACHE = root .. "/.cache/go/build",
    GOMODCACHE = root .. "/.cache/go/modules",
    VIRTUAL_ENV = false,
    PYTHONHOME = false,
    PYTHONPATH = false,
  }
end

local function command(tool, arguments)
  local spec = { tool = tool, cwd = root, env = M.overlay() }
  for i, argument in ipairs(arguments) do spec[i] = argument end
  return spec
end

function M.run(tool, arguments)
  return task.exec(command(tool, arguments))
end

function M.launch(tool, arguments)
  local resolved = task.command(command(tool, arguments))
  -- detach accepts only argv, cwd and env, not a tool/default timeout.
  local detached = { cwd = resolved.cwd, env = resolved.env }
  for i, argument in ipairs(resolved) do detached[i] = argument end
  return proc.detach(detached)
end

return M
```

Each call gets a fresh overlay. A string sets a variable, including an empty
string; `false` removes it. Other inherited variables remain. This is a partial
overlay, not a clean or hermetic environment. The explicit Python removals
prevent those inherited activation settings from choosing a different project.
They do not disable every tool's user configuration or interpreter discovery.
Pin and declare the actual executables separately. For subprocesses a tool
launches by bare name, explicitly provide its required project tool directories
in `PATH`; calling the top-level tool by absolute path does not configure its
own subprocess search.

A strict allowlist requires enumerating `env.all()`, marking every unapproved
name `false`, then adding the approved values. Windows names are case
insensitive: compare names consistently and do not supply differently cased
duplicates. Decide which Windows variables and credentials each tool actually
requires before using such an allowlist. This module intentionally does not
implement that broader policy or persist machine/user settings.

The cache variables are documented upstream: [uv's cache directory](https://docs.astral.sh/uv/reference/environment/#uv_cache_dir),
[uv's project environment path](https://docs.astral.sh/uv/concepts/projects/config/#project-environment-path),
[npm's cache configuration and environment settings](https://docs.npmjs.com/cli/v11/using-npm/config/),
and [Go's environment variables](https://pkg.go.dev/cmd/go#hdr-Environment_variables).
`GOCACHE` must be absolute. `GOMODCACHE` contains downloaded modules; it is
separate from Go's build cache. These settings select locations; they do not
prove a cache is complete, portable or sufficient for offline reconstruction.

## Exercise both launch paths

The following complete example uses kuu itself as an environment probe. It
opens no GUI and needs no installed language tools. Save as `manifest.lua` and
keep the project's verified, pinned `kuu.exe` beside it as described in
[Adopting kuu](adopting.md).

```lua
global none
global <const> require, print
local task, json = require "task", require "json"
local project_env = require "automation.project_env"
task.defaults { timeout = "5s" }
task.tool "environment_probe" { exe = "kuu.exe", output = "lines", timeout = "3s" }
local probe = project_env.root .. "/automation/environment_probe.lua"

task "environment" {
  desc = "Report selected environment settings through a supervised child",
  run = function() return project_env.run("environment_probe", { probe, "cli" }) end,
}
task "editor_environment" {
  desc = "Report the same settings through a short detached probe",
  run = function()
    local pid, why = project_env.launch("environment_probe", { probe, "detached" })
    if not pid then return nil, why end
    print(json.encode { pid = pid })
    return true
  end,
}
```

Save as `automation/environment_probe.lua`. It reports only chosen settings;
do not dump `env.all()` into logs, because the inherited environment may hold
tokens and passwords. The sentinel is a test value, not an application secret.

```lua
global none
global <const> require, assert, print
local fs, env, rt, json = require "fs", require "env", require "rt", require "json"
local report = {
  cwd = fs.cwd(),
  uv = env.get("UV_CACHE_DIR"),
  venv = env.get("UV_PROJECT_ENVIRONMENT"),
  npm = env.get("npm_config_cache"),
  go_build = env.get("GOCACHE"),
  go_modules = env.get("GOMODCACHE"),
  virtual_env = env.get("VIRTUAL_ENV") or json.null,
  python_home = env.get("PYTHONHOME") or json.null,
  python_path = env.get("PYTHONPATH") or json.null,
  path_empty = env.get("PATH") == "",
  sentinel = env.get("PROJECT_ENV_SENTINEL") or json.null,
}
local encoded = json.encode(report)
if rt.args[1] == "detached" then
  assert(fs.mkdir(".cache"))
  assert(fs.write(".cache/detached-environment.json", encoded))
else
  print(encoded)
end
```

Run `kuu run environment`, then `kuu run editor_environment`. The latter
prints the launched PID; its short child writes `.cache/detached-environment.json`
before exiting. A detached process has no kuu console and no supervision or
deadline from `task.defaults`. Its launch succeeding is not a readiness check.
There is no individual `task.exec` child record for `M.launch`; the enclosing
task and run are recorded.

For an actual editor, declare its pinned executable as a tool and call
`project_env.launch("editor", { project_env.root })` with that editor's explicit
arguments. Use its documented separate-instance/profile options when it might
forward the request to an existing process. A running editor keeps the
environment from its original launch; changing this module does not update
that process. Close/restart or start an independent instance before checking
its child tools. [Environment lifetime](env.md#the-two-environments) explains
the same boundary for consoles and persisted settings. Supervised CLI calls
use `M.run` and retain their task/tool timeout and child records.

The [editor recipe](editor.md) demonstrates both paths with a real disposable
GUI on a private desktop, including readiness, failure and cleanup checks.
