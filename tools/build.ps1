<#
.SYNOPSIS
    Stage-zero build of kuu.exe: Lua 5.5.1 compiled as C plus the host, with
    the project's own gcc from .tools.

.DESCRIPTION
    This script exists because kuu cannot build itself before it exists and no
    other scripting runtime is assumed on the machine.  It is deliberately
    plain: compile what is stale, link, report.  Everything it knows about the
    compiler lives in the flag lists below; docs/toolchain.md says where the
    compiler comes from.

.PARAMETER Clean
    Remove build\ first.
#>
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Gcc = Join-Path $Root '.tools\msys2\ucrt64\bin\gcc.exe'
if (-not (Test-Path $Gcc)) {
    Write-Host "kuu build: no compiler at $Gcc" -ForegroundColor Red
    Write-Host "Populate .tools as described in docs/toolchain.md."
    exit 2
}

# gcc's compiler proper (cc1.exe under lib\gcc) loads libgmp, libisl, libmpfr,
# and friends from ucrt64\bin, and the driver does not put that directory on
# the search path for the programs it spawns.  Without this line every compile
# fails with exit 1 and no message.
$env:PATH = (Join-Path $Root '.tools\msys2\ucrt64\bin') + ';' + $env:PATH

$Build = Join-Path $Root 'build'
if ($Clean -and (Test-Path $Build)) {
    Remove-Item -Recurse -Force $Build
}
$ObjLua = Join-Path $Build 'obj\lua'
$ObjHost = Join-Path $Build 'obj\host'
New-Item -ItemType Directory -Force $ObjLua, $ObjHost | Out-Null

$LuaSrc = Join-Path $Root 'vendor\lua-5.5.1\src'
$HostSrc = Join-Path $Root 'src'
$Out = Join-Path $Build 'kuu.exe'

# Vendored Lua compiles as C with its own minimal flags, never the authored
# warning gate.  luaconf.h derives LUA_USE_WINDOWS from _WIN32 itself; defining
# it on the command line only earns a redefinition warning per file.
$LuaFlags = @('-std=gnu99', '-O2', '-ffunction-sections', '-fdata-sections')

# The host is C23 under the els method's warning set, and warnings are errors.
$HostFlags = @(
    '-std=c23', '-O2',
    '-Wall', '-Wextra', '-Wpedantic', '-Wformat=2', '-Wundef', '-Werror',
    '-DUNICODE', '-D_UNICODE', '-D_WIN32_WINNT=0x0A00',
    '-ffunction-sections', '-fdata-sections',
    "-I$LuaSrc", "-I$HostSrc"
)

# wmain entry, libgcc and winpthread static, unused sections dropped, symbols
# stripped.  The C runtime stays the system's ucrtbase.dll.
$LinkFlags = @('-municode', '-static', '-static-libgcc', '-Wl,--gc-sections', '-s')

function Get-Newest {
    param([string[]]$Paths)
    $newest = [DateTime]::MinValue
    foreach ($path in $Paths) {
        $time = (Get-Item $path).LastWriteTimeUtc
        if ($time -gt $newest) { $newest = $time }
    }
    return $newest
}

function Test-Stale {
    param([string]$Output, [DateTime]$InputsNewest)
    if (-not (Test-Path $Output)) { return $true }
    return ((Get-Item $Output).LastWriteTimeUtc -lt $InputsNewest)
}

function Invoke-Tool {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Exe)) failed with exit code $LASTEXITCODE"
    }
}

$clock = [Diagnostics.Stopwatch]::StartNew()

$luaHeaders = @(Get-ChildItem $LuaSrc -Filter *.h | ForEach-Object { $_.FullName })
$luaHeaderTime = Get-Newest $luaHeaders
$luaObjects = @()
$compiled = 0
foreach ($c in Get-ChildItem $LuaSrc -Filter *.c | Where-Object { $_.BaseName -notin @('lua', 'luac') }) {
    $o = Join-Path $ObjLua ($c.BaseName + '.o')
    $luaObjects += $o
    $newest = $luaHeaderTime
    if ($c.LastWriteTimeUtc -gt $newest) { $newest = $c.LastWriteTimeUtc }
    if (Test-Stale $o $newest) {
        Invoke-Tool $Gcc ($LuaFlags + @('-c', $c.FullName, '-o', $o))
        $compiled++
    }
}
Write-Host ("lua:  {0} objects ({1} compiled)" -f $luaObjects.Count, $compiled)

$hostHeaders = @(Get-ChildItem $HostSrc -Filter *.h | ForEach-Object { $_.FullName })
$hostHeaderTime = Get-Newest ($hostHeaders + $luaHeaders)
$hostObjects = @()
$compiled = 0
foreach ($c in Get-ChildItem $HostSrc -Filter *.c) {
    $o = Join-Path $ObjHost ($c.BaseName + '.o')
    $hostObjects += $o
    $newest = $hostHeaderTime
    if ($c.LastWriteTimeUtc -gt $newest) { $newest = $c.LastWriteTimeUtc }
    if (Test-Stale $o $newest) {
        Invoke-Tool $Gcc ($HostFlags + @('-c', $c.FullName, '-o', $o))
        $compiled++
    }
}
Write-Host ("host: {0} objects ({1} compiled)" -f $hostObjects.Count, $compiled)

$objects = $hostObjects + $luaObjects
if (Test-Stale $Out (Get-Newest $objects)) {
    Invoke-Tool $Gcc ($LinkFlags + @('-o', $Out) + $objects)
    Write-Host "link: $Out"
} else {
    Write-Host "link: up to date"
}

$size = (Get-Item $Out).Length
Write-Host ("kuu.exe {0:N0} bytes in {1:N1} s" -f $size, $clock.Elapsed.TotalSeconds)
