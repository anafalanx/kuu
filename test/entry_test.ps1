<#
.SYNOPSIS
    Entry tests for kuu.exe: routes, arguments, decoding, the removed hazards,
    require, error reporting, and exit codes.  Runs the built executable as a
    child with redirected streams and compares bytes.

.PARAMETER Exe
    The executable under test.  Default: build\kuu.exe.
#>
[CmdletBinding()]
param(
    [string]$Exe
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Exe) { $Exe = Join-Path $Root 'build\kuu.exe' }
if (-not (Test-Path $Exe)) { Write-Host "no executable at $Exe"; exit 2 }
$Fixtures = Join-Path $PSScriptRoot 'fixtures'
$Work = Join-Path $Root 'build\test'
New-Item -ItemType Directory -Force $Work | Out-Null

$script:passed = 0
$script:failed = 0
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Quote-Argument {
    param([string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $out = '"'
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
        } elseif ($ch -eq '"') {
            $out += ('\' * ($backslashes * 2 + 1)) + '"'
            $backslashes = 0
        } else {
            $out += ('\' * $backslashes) + $ch
            $backslashes = 0
        }
    }
    $out += ('\' * ($backslashes * 2)) + '"'
    return $out
}

function Invoke-Kuu {
    param(
        [string[]]$Arguments = @(),
        [string]$StdinFile,
        [string]$WorkingDirectory
    )
    $outFile = Join-Path $Work 'stdout.bin'
    $errFile = Join-Path $Work 'stderr.bin'
    if (Test-Path $outFile) { Remove-Item $outFile }
    if (Test-Path $errFile) { Remove-Item $errFile }
    $start = @{
        FilePath = $Exe
        RedirectStandardOutput = $outFile
        RedirectStandardError = $errFile
        Wait = $true
        PassThru = $true
        NoNewWindow = $true
    }
    if ($Arguments.Count -gt 0) {
        $start.ArgumentList = (($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    }
    if ($StdinFile) { $start.RedirectStandardInput = $StdinFile }
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    $process = Start-Process @start
    $stdout = [IO.File]::ReadAllBytes($outFile)
    $stderr = [IO.File]::ReadAllBytes($errFile)
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Out = $Utf8.GetString($stdout)
        Err = $Utf8.GetString($stderr)
        OutBytes = $stdout
    }
}

function Check {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:passed++
        Write-Host "ok   $Name"
    } else {
        $script:failed++
        Write-Host "FAIL $Name" -ForegroundColor Red
        if ($Detail) { Write-Host ("     " + ($Detail -replace "`n", "`n     ")) }
    }
}

function Describe {
    param($Result)
    return "exit $($Result.ExitCode)`nstdout: $($Result.Out)`nstderr: $($Result.Err)"
}

# --- identity and usage -------------------------------------------------------
$r = Invoke-Kuu @('--version')
Check 'version line' ($r.ExitCode -eq 0 -and $r.Out -eq "kuu 0.1.0 (Lua 5.5.1)`n") (Describe $r)

$r = Invoke-Kuu @('--help')
Check 'help exits 0 on stdout' ($r.ExitCode -eq 0 -and $r.Out.Contains('usage: kuu FILE') -and $r.Err -eq '') (Describe $r)

$r = Invoke-Kuu @()
Check 'no arguments is a usage error' ($r.ExitCode -eq 2 -and $r.Err.Contains('usage:') -and $r.Out -eq '') (Describe $r)

$r = Invoke-Kuu @('--bogus')
Check 'unknown option is refused' ($r.ExitCode -eq 2 -and $r.Err.Contains("ENTRY usage: unknown option '--bogus'")) (Describe $r)

$r = Invoke-Kuu @('-e')
Check '-e without a script is a usage error' ($r.ExitCode -eq 2 -and $r.Err.Contains('-e needs a script')) (Describe $r)

# --- inline route -------------------------------------------------------------
$r = Invoke-Kuu @('-e', 'print(_VERSION)')
Check 'inline script runs Lua 5.5' ($r.ExitCode -eq 0 -and $r.Out -eq "Lua 5.5`n") (Describe $r)

$r = Invoke-Kuu @('-e', "print(select('#', ...), ...)", 'a', 'b c')
Check 'inline arguments arrive as ...' ($r.Out -eq "2`ta`tb c`n") (Describe $r)

$r = Invoke-Kuu @('-e', "local rt = require('rt'); print(rt.version, rt.lua, rt.route, #rt.args, rt.args[2], rt.program, rt.exe ~= nil)", 'x', 'y')
Check 'rt module describes the launch' ($r.Out -eq "0.1.0`tLua 5.5.1`teval`t2`ty`tnil`ttrue`n") (Describe $r)

$accented = 'h' + [char]0xE9 + 'llo w' + [char]0xF6 + 'rld ' + [char]0x20AC
$r = Invoke-Kuu @('-e', 'io.write(...)', $accented)
$expected = $Utf8.GetBytes($accented)
Check 'arguments are UTF-8 bytes, output is exact bytes' (($r.OutBytes.Length -eq $expected.Length) -and ([Linq.Enumerable]::SequenceEqual($r.OutBytes, $expected))) (Describe $r)

$r = Invoke-Kuu @('-e', 'io.write("a\nb\n")')
Check 'stdout has no CRLF translation' ($r.Out -eq "a`nb`n") (Describe $r)

$r = Invoke-Kuu @('-e', "error('boom')")
Check 'uncaught error: message, traceback, exit 1' ($r.ExitCode -eq 1 -and $r.Err.StartsWith("kuu: (command line):1: boom`nstack traceback:") -and $r.Out -eq '') (Describe $r)

$r = Invoke-Kuu @('-e', "error({code = 1})")
Check 'table error object without __tostring is named' ($r.ExitCode -eq 1 -and $r.Err.StartsWith('kuu: (error object is a table value)')) (Describe $r)

$r = Invoke-Kuu @('-e', "error(setmetatable({}, {__tostring = function() return 'PROC timeout: gone' end}))")
Check 'error object with __tostring is rendered' ($r.ExitCode -eq 1 -and $r.Err.StartsWith('kuu: PROC timeout: gone')) (Describe $r)

$r = Invoke-Kuu @('-e', "x = = 1")
Check 'syntax error exits 1 with the location' ($r.ExitCode -eq 1 -and $r.Err.StartsWith('kuu: (command line):1:')) (Describe $r)

$r = Invoke-Kuu @('-e', 'coroutine.yield()')
Check 'top-level yield is refused until a scheduler exists' ($r.ExitCode -eq 1 -and $r.Err.Contains('SCHED yield')) (Describe $r)

$r = Invoke-Kuu @('-e', 'print(coroutine.isyieldable())')
Check 'the main chunk runs as a coroutine' ($r.Out -eq "true`n") (Describe $r)

# --- hazards removed, loading rules --------------------------------------------
$r = Invoke-Kuu @('-e', 'print(io.popen, os.execute, os.remove, os.rename, os.tmpname, dofile, loadfile, package.loadlib, debug)')
Check 'hazardous functions are absent' ($r.Out -eq ("nil`t" * 8 + "nil`n")) (Describe $r)

$r = Invoke-Kuu @('-e', 'print(type(os.getenv), type(os.time), type(os.exit), type(io.read), type(io.stderr), type(utf8.char), type(coroutine.wrap), type(string.pack), type(math.tointeger), type(table.create))')
Check 'the intended standard library is present' ($r.Out -eq (("function`t" * 3) + "function`tuserdata`t" + ("function`t" * 4) + "function`n")) (Describe $r)

$r = Invoke-Kuu @('-e', "print(package.path == '', package.cpath == '', #package.searchers)")
Check 'require has no environment paths and two searchers' ($r.Out -eq "true`ttrue`t2`n") (Describe $r)

$r = Invoke-Kuu @('-e', 'print(load(string.dump(function() end)))')
Check 'load refuses binary chunks' ($r.ExitCode -eq 0 -and $r.Out.Contains('binary chunk')) (Describe $r)

$r = Invoke-Kuu @('-e', "print(load('return 1 + 1', 'x', 'b'))")
Check 'load ignores a requested binary mode' ($r.Out.StartsWith('function')) (Describe $r)

$r = Invoke-Kuu @('-e', "print(load('return ...', 'x', 't', nil)('env-nil'))")
Check 'load keeps an explicit nil env distinct from absent' ($r.Out -eq "env-nil`n") (Describe $r)

# --- file route ---------------------------------------------------------------
$hello = Join-Path $Fixtures 'hello.lua'
$r = Invoke-Kuu @($hello, 'one', 'two')
Check 'program file runs with arguments' ($r.ExitCode -eq 0 -and $r.Out -eq "hello`tone`ttwo`n") (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'needs_mod.lua'))
Check 'require finds neighbours by name and by init.lua' ($r.ExitCode -eq 0 -and $r.Out -eq "mod says hi`tsub.pkg`tfile`ttrue`n") (Describe $r)

$r = Invoke-Kuu @('-e', "require('nope')")
Check 'missing module names the paths tried' ($r.ExitCode -eq 1 -and $r.Err.Contains("module 'nope' not found") -and $r.Err.Contains("nope.lua'") -and $r.Err.Contains("nope/init.lua'")) (Describe $r)

$r = Invoke-Kuu @('-e', "require('../escape')")
Check 'require refuses names that are not plain dotted names' ($r.ExitCode -eq 1 -and $r.Err.Contains('not a plain dotted name')) (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'shebang.lua'))
Check 'shebang line is skipped and line numbers hold' ($r.ExitCode -eq 1 -and $r.Out -eq "shebang ok`n" -and $r.Err.Contains('shebang.lua:3: line three')) (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'exit7.lua'))
Check 'os.exit sets the exit code' ($r.ExitCode -eq 7 -and $r.Out -eq "leaving`n") (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'closing.lua'))
Check 'pending <close> variables are closed after an error' ($r.ExitCode -eq 1 -and $r.Err.Contains('closed with: ') -and $r.Err.Contains('failing on purpose')) (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'global_none.lua'))
Check 'Lua 5.5 global declarations work' ($r.ExitCode -eq 0 -and $r.Out -eq "declared`tfile`n") (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'global_typo.lua'))
Check 'under global none a misspelled name is a load error' ($r.ExitCode -eq 1 -and $r.Err.Contains('reuslt')) (Describe $r)

$r = Invoke-Kuu @((Join-Path $Fixtures 'does_not_exist.lua'))
Check 'missing program file is ENTRY notfound' ($r.ExitCode -eq 2 -and $r.Err.StartsWith("kuu: ENTRY notfound: cannot find program file '")) (Describe $r)

$r = Invoke-Kuu @($Fixtures)
Check 'a directory is refused as a program' ($r.ExitCode -eq 2 -and $r.Err.Contains('ENTRY badvalue') -and $r.Err.Contains('is a directory')) (Describe $r)

$unicodeDir = Join-Path $Work ('h' + [char]0xE9 + ' llo')
New-Item -ItemType Directory -Force $unicodeDir | Out-Null
Copy-Item $hello (Join-Path $unicodeDir 'run.lua') -Force
Copy-Item (Join-Path $Fixtures 'mod.lua') (Join-Path $unicodeDir 'mod.lua') -Force
[IO.File]::WriteAllText((Join-Path $unicodeDir 'main.lua'), "print(require('mod').hi, ...)`n", $Utf8)
$r = Invoke-Kuu @((Join-Path $unicodeDir 'main.lua'), 'z')
Check 'program and modules under a non-ASCII path' ($r.ExitCode -eq 0 -and $r.Out -eq "mod says hi`tz`n") (Describe $r)

$r = Invoke-Kuu @('main.lua', 'rel') $null $unicodeDir
Check 'relative program path resolves require from its directory' ($r.ExitCode -eq 0 -and $r.Out -eq "mod says hi`trel`n") (Describe $r)

# --- stdin route --------------------------------------------------------------
$r = Invoke-Kuu @('-', 'from-stdin') $hello
Check 'stdin program runs with arguments' ($r.ExitCode -eq 0 -and $r.Out -eq "hello`tfrom-stdin`n") (Describe $r)

$bomFile = Join-Path $Work 'bom_crlf.lua'
$bytes = [byte[]](0xEF, 0xBB, 0xBF) + $Utf8.GetBytes("print('bom ok')`r`nprint(select('#', ...))`r`n")
[IO.File]::WriteAllBytes($bomFile, $bytes)
$r = Invoke-Kuu @('-', 'a') $bomFile
Check 'BOM and CRLF are accepted' ($r.ExitCode -eq 0 -and $r.Out -eq "bom ok`n1`n") (Describe $r)

$badFile = Join-Path $Work 'bad_utf8.lua'
[IO.File]::WriteAllBytes($badFile, ($Utf8.GetBytes("print('x')`n") + [byte[]](0xFF)))
$r = Invoke-Kuu @('-') $badFile
Check 'invalid UTF-8 on stdin is ENTRY encoding' ($r.ExitCode -eq 2 -and $r.Err -eq "kuu: ENTRY encoding: the stdin program is not valid UTF-8`n") (Describe $r)

$r = Invoke-Kuu @($badFile)
Check 'invalid UTF-8 in a file is ENTRY encoding' ($r.ExitCode -eq 2 -and $r.Err.Contains("ENTRY encoding: program file '") -and $r.Err.Contains('is not valid UTF-8')) (Describe $r)

$bigFile = Join-Path $Work 'too_big.lua'
$stream = [IO.File]::Create($bigFile)
try {
    $chunk = New-Object byte[] (1024 * 1024)
    for ($i = 0; $i -lt $chunk.Length; $i++) { $chunk[$i] = 0x20 }
    for ($i = 0; $i -lt 17; $i++) { $stream.Write($chunk, 0, $chunk.Length) }
} finally {
    $stream.Dispose()
}
$r = Invoke-Kuu @('-') $bigFile
Check 'stdin program over 16 MiB is refused' ($r.ExitCode -eq 2 -and $r.Err.Contains('ENTRY toobig') -and $r.Err.Contains('larger than 16 MiB')) (Describe $r)

$r = Invoke-Kuu @($bigFile)
Check 'program file over 16 MiB is refused' ($r.ExitCode -eq 2 -and $r.Err.Contains('ENTRY toobig')) (Describe $r)

$emptyFile = Join-Path $Work 'empty.lua'
[IO.File]::WriteAllBytes($emptyFile, [byte[]]@())
$r = Invoke-Kuu @($emptyFile)
Check 'an empty program runs and exits 0' ($r.ExitCode -eq 0 -and $r.Out -eq '' -and $r.Err -eq '') (Describe $r)

$r = Invoke-Kuu @($hello, 'with-stdin') $bomFile
Check 'redirected stdin does not disturb the file route' ($r.ExitCode -eq 0 -and $r.Out -eq "hello`twith-stdin`n") (Describe $r)

$r = Invoke-Kuu @($hello, 'shared') $hello
Check 'a program file also open elsewhere is refused with ENTRY access' ($r.ExitCode -eq 2 -and $r.Err.Contains('ENTRY access')) (Describe $r)

# --- summary ------------------------------------------------------------------
Write-Host ''
Write-Host ("entry: {0} ok, {1} failed" -f $script:passed, $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
