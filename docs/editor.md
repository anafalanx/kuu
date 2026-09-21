# Detached editors and isolated GUI verification

Use the same declared executable and [project environment](project-environment.md)
for a bounded CLI operation and a newly launched editor. A PID means launch
succeeded; it does not establish that the editor loaded its workspace, profile
or extensions. Readiness needs a separate signal from the application.

## A disposable native GUI probe

The source example [gui_probe.c](../examples/gui_probe.c) is a small project
helper, not a new kuu API. Build it with the project's pinned Windows compiler
and keep it at `.tools/gui-probe/gui_probe.exe`. In kuu's source checkout,
`make fixtures` builds this exact source with its pinned UCRT64 toolchain into
`build/test/gui_probe.exe`; the tests copy that artifact into disposable projects.
The C source is supplied with the repository; it is not embedded as a Lua module.

The helper's contract is:

```text
gui_probe.exe verify PROFILE REPORT [ready|no-ready|early-exit|hold-ready]
```

PROFILE and REPORT must be absolute paths with existing parents. The profile
must be absent; an existing profile or report is refused without replacement.
The helper creates a private Windows desktop and launches its own small editor
there. The child creates a window with an EDIT control, verifies the desktop
and selected environment, and signals readiness with a fresh nonce. The helper
never switches the interactive desktop. It owns the child through a retained
process handle and a job that terminates children when closed, then removes
only the known files in its newly created profile. Unexpected entries or
cleanup errors remain failures and are reported.

An atomically published REPORT contains `ok`, `status`, `win32`, `desktop`,
`private_desktop`, `window_ready`, `child_pid`, `child_exited`, `profile_created`,
`profile_removed`, `cleanup_error`, selected `cache` and `recipe` values,
`nonce`, and `elapsed_ms`. `ok` includes cleanup success. Read the report and
exit status together on the supervised path; on the detached path, retain the
PID and report location and explicitly wait for the report.

`no-ready` and `early-exit` exercise failure paths. `hold-ready` is a bounded
test handshake: after window creation the supervisor waits up to three seconds
for PROFILE/continue to contain the exact bytes from PROFILE/ready. This lets
an automated caller prove that both the supervisor and GUI survive the kuu
launcher exiting, then release them. It is not an interactive user prompt.

## A complete manifest

Save the shared module from [Project environment](project-environment.md#a-shared-module)
as `automation/project_env.lua`, keep the project's verified `kuu.exe` at its
root, and save this manifest. Ignore `/.local/` as well as the tool and cache
directories. The helper is the one declared project tool for both launch paths.

```lua
global none
global <const> require, ipairs, print
local task, fs, hash, json, proc = require "task", require "fs", require "hash", require "json", require "proc"
local project_env = require "automation.project_env"
local root = project_env.root
task.defaults { timeout = "12s" }
task.tool "editor_probe" { exe = ".tools/gui-probe/gui_probe.exe", output = "lines", timeout = "12s" }

local function command(mode)
  local directory = root .. "/.local/gui-checks"
  local made, why = fs.mkdir(directory)
  if not made then return nil, why end
  local id = hash.uuid()
  local paths = { profile = directory .. "/profile-" .. id, report = directory .. "/report-" .. id .. ".json" }
  local overlay = project_env.overlay()
  overlay.KUU_EDITOR_RECIPE = "isolated-v1"
  overlay.KUU_EDITOR_CACHE = root .. "/.cache/editor"
  return { tool = "editor_probe", "verify", paths.profile, paths.report, mode,
    cwd = root, env = overlay }, paths
end

task "verify_editor" {
  desc = "Verify a disposable GUI on a private desktop and clean it up",
  run = function()
    local spec, paths = command("ready")
    if not spec then return nil, paths end
    print(json.encode(paths))
    return task.exec(spec)
  end,
}

task "launch_editor" {
  desc = "Detach the same disposable GUI verifier; inspect its completion report",
  args = { { "--hold", type = "flag", help = "bounded test handshake after the kuu launcher exits" } },
  run = function(opts)
    local spec, paths = command(opts.hold and "hold-ready" or "ready")
    if not spec then return nil, paths end
    local resolved = task.command(spec)
    local detached = { cwd = resolved.cwd, env = resolved.env }
    for i, argument in ipairs(resolved) do detached[i] = argument end
    local pid, why = proc.detach(detached)
    if not pid then return nil, why end
    paths.pid = pid
    print(json.encode(paths))
    return true
  end,
}
```

Run `kuu run verify_editor` for the bounded operation; `task.exec` records the
child and reports helper failures. `kuu run launch_editor` returns after
launching; its supervisor has its own internal bounds, and the task timeout
does not govern that detached lifetime. A captured or detached child has no
individual `task.exec` child record; its enclosing task/run still has history.
The `--hold` option is for the automated nonce handshake, not a normal launch.

For a real editor, replace the tool with its pinned project executable and use
its documented profile, workspace and separate-instance arguments. Supply a
fresh disposable profile for verification; an existing editor may accept a
request without starting a new process or adopting the new environment.
Choose an application-specific readiness check instead of treating PID
existence, an open window or a fixed sleep as proof of a usable workspace.

## Profiles and database snapshots

Use generated test settings and fresh profiles. Live cookie databases, locks
and credentials are not ordinary portable configuration files. A copied
profile can combine database files from different moments, or combine a newly
copied database with an old destination WAL. Do not merge snapshots into a
reused destination or delete a WAL merely because it looks stale: SQLite's
[WAL is part of persistent database state](https://www.sqlite.org/wal.html).
For legitimate application backups, use its supported export/backup operation,
or establish a consistent cold snapshot after its writers stop. This recipe
does not import browser profiles or copy live user databases.

## Platform limits

The test creates a desktop in the current session and uses ordinary Win32 GUI
controls. It requires permission to create that desktop and launch a process
on it; noninteractive services, restrictive enclosing jobs and session policy
can prevent the operation. It reports failure rather than falling back to the
interactive desktop. See Microsoft's [desktop access rights](https://learn.microsoft.com/en-us/windows/win32/winstation/desktop-security-and-access-rights).

A private desktop keeps this probe's windows off the interactive desktop; it
is not a filesystem, network or security sandbox. These checks establish this
probe's GUI creation, selected environment, lifetime and cleanup. They do not
certify arbitrary editors, GPU rendering, extension loading, login flows or
application-specific profile formats. No application outside the owned test
processes is terminated or modified.
