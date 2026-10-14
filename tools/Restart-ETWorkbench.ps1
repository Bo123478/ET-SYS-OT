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

function Start-WorkbenchInInteractiveSession {
    param(
        [string]$ScriptPath,
        [switch]$UseConsole
    )

    $taskName = "ETWorkbench.Restart.{0}" -f ([guid]::NewGuid().ToString('N'))
    $startAt = (Get-Date).AddMinutes(2).ToString('HH:mm')

    $launchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $UseConsole) { $launchArgs += @('-WindowStyle', 'Hidden') }
    $launchArgs += @('-File', ('"{0}"' -f $ScriptPath))
    if ($UseConsole) { $launchArgs += '-Console' }
    $taskCmd = 'powershell.exe {0}' -f ($launchArgs -join ' ')

    $candidates = @()
    try {
        $who = (whoami.exe 2>$null | Out-String).Trim()
        if ($who) { $candidates += $who }
    }
    catch { }
    if ($env:USERDOMAIN -and $env:USERNAME) { $candidates += ("{0}\\{1}" -f $env:USERDOMAIN, $env:USERNAME) }
    if ($env:COMPUTERNAME -and $env:USERNAME) { $candidates += ("{0}\\{1}" -f $env:COMPUTERNAME, $env:USERNAME) }
    if ($env:USERNAME) { $candidates += $env:USERNAME }
    $candidates = @($candidates | Where-Object { $_ } | Select-Object -Unique)

    $created = $false
    foreach ($runUser in $candidates) {
        $null = & schtasks.exe /Create /TN $taskName /SC ONCE /ST $startAt /F /RL LIMITED /IT /RU $runUser /TR $taskCmd
        if ($LASTEXITCODE -eq 0) {
            $created = $true
            break
        }
    }
    if (-not $created) {
        throw "Failed to create interactive task via schtasks for current user."
    }

    $null = & schtasks.exe /Run /TN $taskName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to run interactive task via schtasks."
    }

    return $taskName
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

$newProc = $null
$interactiveTaskName = $null
if ([Environment]::UserInteractive) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $Console) { $args += @('-WindowStyle', 'Hidden') }
    $args += @('-File', $entryScript)
    if ($Console) { $args += '-Console' }
    $newProc = Start-Process powershell.exe -ArgumentList $args -PassThru -WindowStyle $(if ($Console) { 'Normal' } else { 'Hidden' })
}
else {
    $interactiveTaskName = Start-WorkbenchInInteractiveSession -ScriptPath $entryScript -UseConsole:$Console
}

Start-Sleep -Seconds ([Math]::Max(1, $StartupWaitSec))

$running = Get-WorkbenchProcesses
$ok = (@($running)).Count -gt 0
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($ok) {
    if ($newProc) {
        Write-Host "[ET] Restart completed at $ts. Workbench PID: $($newProc.Id)" -ForegroundColor Green
    }
    else {
        Write-Host "[ET] Restart completed at $ts. Workbench launched to interactive desktop session." -ForegroundColor Green
    }
    exit 0
}

if ($interactiveTaskName) {
    & schtasks.exe /Delete /TN $interactiveTaskName /F | Out-Null
    Write-Host "[ET] Restart dispatched at $ts, but no active Workbench process was detected. Please run this script directly in the VM desktop PowerShell session." -ForegroundColor Yellow
    exit 1
}

if ($newProc -and $newProc.HasExited -and $newProc.ExitCode -eq 0) {
    Write-Host "[ET] Restart workflow completed at $ts. Workbench started and exited normally (likely non-interactive session)." -ForegroundColor Green
    exit 0
}

Write-Host "[ET] Restart attempted at $ts, but no active Workbench process was detected." -ForegroundColor Yellow
exit 1
