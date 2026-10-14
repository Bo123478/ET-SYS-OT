[CmdletBinding()]
param(
    [switch]$Console,
    [int]$CloseTimeoutSec = 12,
    [int]$StartupWaitSec = 3
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$etRoot = Join-Path $repoRoot 'ETWorkbench'
$coreModule = Join-Path $etRoot 'Modules\ET.Core.psm1'
$entryScript = Join-Path $etRoot 'Start-ETWorkbench.ps1'

if (-not (Test-Path -LiteralPath $coreModule)) {
    throw "Missing module: $coreModule"
}
if (-not (Test-Path -LiteralPath $entryScript)) {
    throw "Missing entry script: $entryScript"
}

Import-Module $coreModule -Force -ErrorAction Stop

$snapshotDir = Get-ETPath -Category LocalDir -Name Snapshot
$sentinelPath = Join-Path $snapshotDir 'workbench.stop'

function Get-WorkbenchProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -like '*Start-ETWorkbench.ps1*' -and
            $_.CommandLine -notlike '*-SelfTest*'
        })
}

$before = Get-WorkbenchProcesses

if ((@($before)).Count -gt 0) {
    # Prefer graceful shutdown via sentinel because the app already watches this file.
    if (-not (Test-Path -LiteralPath $snapshotDir)) {
        New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($sentinelPath, '', [System.Text.Encoding]::UTF8)

    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $CloseTimeoutSec))
    $left = @()
    do {
        Start-Sleep -Milliseconds 250
        $left = Get-WorkbenchProcesses
    } while ((@($left)).Count -gt 0 -and (Get-Date) -lt $deadline)

    if ((@($left)).Count -gt 0) {
        # Fallback: force close stale instances that ignored sentinel.
        foreach ($p in $left) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { }
        }
    }
}

if (Test-Path -LiteralPath $sentinelPath) {
    Remove-Item -LiteralPath $sentinelPath -Force -ErrorAction SilentlyContinue
}

$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $entryScript)
if ($Console) { $args += '-Console' }

$newProc = Start-Process powershell.exe -ArgumentList $args -PassThru

Start-Sleep -Seconds ([Math]::Max(1, $StartupWaitSec))

$running = Get-WorkbenchProcesses
$ok = (@($running)).Count -gt 0
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($ok) {
    Write-Host "[ET] Restart completed at $ts. Workbench PID: $($newProc.Id)" -ForegroundColor Green
    exit 0
}

if ($newProc.HasExited -and $newProc.ExitCode -eq 0) {
    Write-Host "[ET] Restart workflow completed at $ts. Workbench started and exited normally (likely non-interactive session)." -ForegroundColor Green
    exit 0
}

Write-Host "[ET] Restart attempted at $ts, but no active Workbench process was detected." -ForegroundColor Yellow
exit 1
