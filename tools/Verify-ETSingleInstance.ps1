# Empirical end-to-end verification of the ET single-instance guards.
# ASCII only (no BOM / no Chinese) so Windows PowerShell 5.1 never mis-decodes it.
[CmdletBinding()]
param(
    [string]$RepoRoot = 'C:\Users\wuhui\Desktop\Dev\ET-workstation&SYS-OT'
)

$ErrorActionPreference = 'Continue'
$out = Join-Path $env:TEMP 'et_si'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Kill-EtProcs {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Start-ETWorkbench.ps1*' -or
                       $_.CommandLine -like '*Start-ETPlate.ps1*' -or
                       $_.CommandLine -like '*Test-ETMutexProbe*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 900
}

# Returns 'FREE' if we could take the mutex (nobody held it), else 'HELD'.
function Test-MutexFree {
    param([string]$MutexName)
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($true, $MutexName, [ref]$created)
        $m.Dispose()
        if ($created) { 'FREE' } else { 'HELD' }
    }
    catch { "ERR: $($_.Exception.Message)" }
}

function Run-Script {
    param([string]$File, [string[]]$ExtraArgs = @(), [int]$TimeoutMs = 15000)
    $tag = [System.IO.Path]::GetFileNameWithoutExtension($File)
    $o = Join-Path $out "$tag.out.txt"
    $e = Join-Path $out "$tag.err.txt"
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $File) + $ExtraArgs
    $p = Start-Process powershell -ArgumentList $argList -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $o -RedirectStandardError $e
    $finished = $p.WaitForExit($TimeoutMs)
    if (-not $finished) { try { $p.Kill() } catch { } ; Start-Sleep -Milliseconds 300 }
    $code = 'n/a'
    try { $p.Refresh(); if ($p.HasExited) { $code = $p.ExitCode } } catch { }
    if ($null -eq $code) { $code = 'null' }
    $so = Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue
    $se = Get-Content -LiteralPath $e -Raw -ErrorAction SilentlyContinue
    if ($null -eq $so) { $so = '' }
    if ($null -eq $se) { $se = '' }
    [pscustomobject]@{
        Name     = $tag
        Finished = $finished
        ExitCode = $code
        StdOut   = ($so -replace "`r?`n", ' | ')
        StdErr   = ($se -replace "`r?`n", ' | ')
    }
}

$plateScript = Join-Path $RepoRoot 'ETWorkbench\Start-ETPlate.ps1'
$wbScript    = Join-Path $RepoRoot 'ETWorkbench\Start-ETWorkbench.ps1'
$probe       = Join-Path $RepoRoot 'tools\Test-ETMutexProbe.ps1'
$PLATE_LOCK  = 'Global\ETWorkbench.Plate.SingleInstance'
$WB_LOCK     = 'Global\ETWorkbench.MainWindow.SingleInstance'

Write-Host '=== 1. clean state ==='
Kill-EtProcs
$n = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Start-ETWorkbench.ps1*' -or $_.CommandLine -like '*Start-ETPlate.ps1*' }).Count
Write-Host ("leftover ET procs: {0}" -f $n)
Write-Host ("plate lock now:  {0}" -f (Test-MutexFree $PLATE_LOCK))
Write-Host ("main  lock now:  {0}" -f (Test-MutexFree $WB_LOCK))

Write-Host ''
Write-Host '=== 2. plate alone (no holder) -> must reach session guard and exit ==='
$r = Run-Script -File $plateScript
Write-Host ("finished={0} exit={1}" -f $r.Finished, $r.ExitCode)
Write-Host ("stdout: {0}" -f $r.StdOut)
Write-Host ("stderr: {0}" -f $r.StdErr)

Write-Host ''
Write-Host '=== 3. workbench alone (no holder) -> must reach session guard and exit ==='
$r = Run-Script -File $wbScript
Write-Host ("finished={0} exit={1}" -f $r.Finished, $r.ExitCode)
Write-Host ("stdout: {0}" -f $r.StdOut)
Write-Host ("stderr: {0}" -f $r.StdErr)

Write-Host ''
Write-Host '=== 4. plate duplicate: hold plate lock, then run plate -> must be BLOCKED ==='
Kill-EtProcs
$holder = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probe,
    '-MutexName', $PLATE_LOCK, '-HoldSeconds', '20')
Start-Sleep -Seconds 2
Write-Host ("holder alive: {0}; plate lock: {1}" -f (-not $holder.HasExited), (Test-MutexFree $PLATE_LOCK))
$r = Run-Script -File $plateScript
Write-Host ("finished={0} exit={1}" -f $r.Finished, $r.ExitCode)
Write-Host ("stdout: {0}" -f $r.StdOut)
Write-Host ("stderr: {0}" -f $r.StdErr)
try { $holder.Kill() } catch { }

Write-Host ''
Write-Host '=== 5. workbench duplicate: hold main lock, then run workbench -> must be BLOCKED ==='
Kill-EtProcs
$holder = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probe,
    '-MutexName', $WB_LOCK, '-HoldSeconds', '20')
Start-Sleep -Seconds 2
Write-Host ("holder alive: {0}; main lock: {1}" -f (-not $holder.HasExited), (Test-MutexFree $WB_LOCK))
$r = Run-Script -File $wbScript
Write-Host ("finished={0} exit={1}" -f $r.Finished, $r.ExitCode)
Write-Host ("stdout: {0}" -f $r.StdOut)
Write-Host ("stderr: {0}" -f $r.StdErr)
try { $holder.Kill() } catch { }

Write-Host ''
Write-Host '=== 6. cleanup ==='
Kill-EtProcs
Write-Host 'done'
