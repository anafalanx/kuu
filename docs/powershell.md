# From PowerShell

kuu is the tool an agent holds on a Windows machine instead of PowerShell:
to set up, configure, run, test, script, control, and keep in check. This page
maps what an agent reaches for in PowerShell to the kuu call that does it,
with the differences that matter. Where kuu has nothing yet, it says so, and
when. Everything below runs on the one event loop, so a waiting call never
stalls another task.

## Processes

| PowerShell | kuu | the difference |
|---|---|---|
| `& tool.exe args`, `Start-Process -Wait` | `proc.run { "tool.exe", "arg" }` | the child and its whole tree die when kuu does, or when `timeout` passes; exit codes are results, not exceptions |
| `$LASTEXITCODE`, `$?` | `r.code`, `r.status` | `"exit"`, `"timeout"`, or `"killed"`, never a guess |
| `tool 2>&1 \| Out-String` | `r.out`, `r.err` | bytes, captured separately; beyond `maxout` the rest is dropped and `r.truncated` says so |
| `Start-Process` without `-Wait` | `proc.start { ... }` then `c:wait()` | one child per handle, closed with it |
| `Start-Process -NoNewWindow` for an interactive tool | `proc.run { ..., inherit = true }` | the child gets kuu's own console |
| `tool \| ForEach-Object { }` | `for line in c:lines() do` | live, with backpressure, no thread |
| `Start-Job`, `Wait-Job -Any` | `sched.spawn`, `proc.wait_any` | tasks are coroutines, not processes |
| `Start-Process -WindowStyle Hidden` for a daemon | `proc.detach { ... }` | the one child that outlives kuu, on purpose |
| `taskkill /T` | `c:kill()` | the child's whole tree, since every child has its own job |
| `Stop-Process -Id` | `proc.kill(pid)` | that one process, by id |
| `Get-Process`, `netstat -o`, `tasklist` | `proc.list`, `proc.find { name | pid | port }`, `proc.tree` | the entry carries exe, command line, start, cpu, memory when this user may ask |
| `Start-Process -Verb RunAs` | deferred | elevation needs a broker; not yet |
| `cmd /c "a \| b"` | `proc.run { "cmd.exe", "/c", "a | b" }` | explicit; cmd re-parses its argument, see [proc](proc.md) |

## Files

| PowerShell | kuu | the difference |
|---|---|---|
| `Get-Content -Raw`, `-Encoding` | `fs.read(p)`, `fs.read(p, { encoding = "cp1252" })` | bytes by default; a named encoding is decoded strictly, never repaired |
| `Set-Content`, `Out-File` | `fs.write(p, data)` | atomic: a temporary beside, then a rename; never a torn file |
| `Add-Content` | `fs.write(p, data, { append = true })` | |
| `Test-Path` | `fs.exists(p)` | says what it is: `"file"`, `"directory"`, `"link"`, `"other"`, or `false` |
| `Get-Item`, `Get-ItemProperty` | `fs.stat(p)` | identity too: volume and file ids |
| `New-Item -ItemType Directory -Force` | `fs.mkdir(p)` | parents made, existing fine |
| `Remove-Item -Recurse -Force` | `fs.remove(p, { recursive = true })` | never follows a junction or symlink into its target |
| `Move-Item`, `Copy-Item` | `fs.rename(a, b, { replace = true })`, `fs.copy(a, b)` | |
| `Get-ChildItem -Recurse -Filter *.c` | `fs.glob("src/**/*.c")` | sorted, case-insensitive, links matched but never entered |
| `Get-ChildItem -Directory` | `fs.list(dir)`, `fs.dirs(root, { depth, prune })` | the walk tells the truth about junctions and depth |
| `Join-Path`, `Split-Path -Parent`, `Split-Path -Leaf` | `fs.join`, `fs.dirname`, `fs.basename` | `fs.ext`, `fs.stem`, `fs.relative` too |
| `Resolve-Path` | `fs.absolute(p)`, `fs.canon(p)` | `canon` follows links and gives identity |
| `New-TemporaryFile` | `fs.tempfile { dir, prefix, suffix }`, `fs.tempdir { }` | created exclusively |
| `Get-PSDrive`, `Get-Volume` | `fs.space(p)`, `sys.info().drives` | |
| `Get-FileHash` | `hash.file("sha256", p)` | |
| `Register-ObjectEvent` on a FileSystemWatcher | `fs.watch(dir)` then `w:read()` | on the loop, batched as Windows delivers |
| `Set-Location`, `Get-Location` | `fs.chdir(p)`, `fs.cwd()` | process-wide, as in PowerShell |
| `Get-Acl`, `Set-Acl` | deferred | icacls through `proc.run` until a real need |

## Network and downloads

| PowerShell | kuu | the difference |
|---|---|---|
| `Invoke-WebRequest -OutFile` | `http.get(url, { to = p })` | streamed through a temporary; the previous file survives a failure |
| `Invoke-WebRequest` then `Get-FileHash` | `http.get(url, { to = p, sha256 = "..." })` | hashed as it arrives; a mismatch leaves no file |
| `Invoke-RestMethod` | `http.get(url)` then `json.decode(r.body)` | status codes are results; no insecure switch exists |
| `Invoke-RestMethod -Method Post -Body` | `http.post(url, body, { type = "application/json" })` | |
| `Expand-Archive`, `tar -xf` | `archive.unpack(file, dir, { strip = 1 })` | zip and the tar family, through the tar.exe Windows ships |
| `Compress-Archive` | `archive.pack(file, dir)` | |
| `Test-NetConnection -Port`, `Resolve-DnsName`, `Get-NetTCPConnection`, `Get-NetIPAddress`, `ipconfig` | `net.probe`, `net.resolve`, `net.listeners`, `net.addresses` | probe reports the address that answered and the elapsed time; nothing blocks the loop |

## Data and text

| PowerShell | kuu | the difference |
|---|---|---|
| `ConvertFrom-Json`, `ConvertTo-Json` | `json.decode`, `json.encode` | strict, exact integers, duplicate keys refused |
| `[Convert]::ToBase64String`, `FromBase64String` | `text.tobase64`, `text.frombase64` | |
| `[BitConverter]::ToString`, `-replace '-'` | `text.tohex`, `text.fromhex` | |
| `[Text.Encoding]::GetEncoding(1252).GetString` | `text.decode(bytes, "cp1252")` | strict both ways |
| `New-Guid` | `hash.uuid()` | |
| `.ToUpper()`, `.ToLower()` | `text.upper`, `text.lower` | Unicode, by the rules file names fold by; Lua's own are ASCII only |
| `New-Object Threading.Mutex`, `Wait-Handle` | `sync.lock(name, timeout)`, `sync.try(name)` | a named mutex across processes; a dead holder hands it over as `abandoned` |
| `-match`, `$Matches` | `re.match`, `re.exec` | `exec` gives positions, numbered and named groups in one table |
| `-replace` | `re.gsub(s, pattern, "$1")` | `$1`, `${name}`, `$0`, `$$`; a function or table too |
| `-split` | `re.split` | |
| `Select-String` | `re.find` in a loop over `c:lines()` or `fs.read` | |
| `[regex]::Escape` | `re.escape` | |
| `Get-Date`, `Get-Date -Format`, `[DateTime]::Parse`, `ToUniversalTime` | `time.now`, `time.format`, `time.parse`, `time.iso` | instants are seconds since the epoch; zones are `utc`, `local`, or an offset |
| `New-TimeSpan`, `[TimeSpan]::Parse` | `time.duration("1h30m")`, `time.human(seconds)` | |
| `Import-Csv`, `Export-Csv`, `ConvertFrom-Csv` | `csv.decode { header = true }`, `csv.encode` | every field a string; separators, CRLF, and the BOM handled |
| `Select-Xml`, `[xml]` | deferred | |
| `Write-Host`, `Write-Verbose` | `print`, `io.stderr:write`, `log` | `log` never raises and never interrupts the work |

## The machine

| PowerShell | kuu | the difference |
|---|---|---|
| `[Environment]::OSVersion`, `Get-ComputerInfo` | `sys.info()` | the truthful build, the display name, elevation, cpus, memory, drives, uptime |
| `[Security.Principal.WindowsPrincipal]…IsInRole` | `sys.info().elevated` | |
| `$env:NAME`, `[Environment]::SetEnvironmentVariable(..., 'User')`, `setx` | `env.get`, `env.set`; `env.persist`, `env.forget` with the change broadcast | live and persisted are two different things; see env.md |
| `Get-ItemProperty HKLM:\...`, `Set-ItemProperty`, `New-Item HKCU:\...`, `reg.exe` | `reg.get`, `reg.set`, `reg.values`, `reg.keys`, `reg.remove` | typed: dword, qword, string, expandstring, multistring, binary |
| `Get-Service`, `Start-Service`, `New-Service` | 0.6: `svc` | |
| `Get-WinEvent` | 0.6: `evt` | |
| `Register-ScheduledTask` | `schtasks.exe` through `proc.run` | deferred as a module |
| `New-Object -ComObject WScript.Shell` for shortcuts | no | desktop plumbing, not an agent's tool |
| `Enable-WindowsOptionalFeature`, `New-NetFirewallRule`, `Set-MpPreference` | no | security settings stay with the person |

## The script itself

| PowerShell | kuu | the difference |
|---|---|---|
| `param()` | `cli.parse(rt.args, spec)` | declared once; `--help` is a value, not an exit |
| `$PSScriptRoot` | `rt.root()` | |
| `Start-Sleep` | `sched.sleep("2s")` | other tasks run meanwhile |
| a `.ps1` per job, `Invoke-Build` | `tasks.lua`, `kuu run`, `kuu list` | dependencies once, in order; `--dry-run` shows the plan |
| `Export-Clixml` for state between runs | `mem.set`, `mem.get` | a JSON notebook per project, 1 MiB at most |
| `Set-StrictMode -Version Latest` | `global none` at the top of the file | the compiler refuses an undeclared global |
| `try { } catch { }` | `nil, err` for expected failures, `pcall` for mistakes | see [err](err.md) |
| `-WhatIf` | `kuu run --dry-run` | |
| `Test-ModuleManifest`, `PSScriptAnalyzer` | `kuu check` | parse, global declarations, `require` resolution |
