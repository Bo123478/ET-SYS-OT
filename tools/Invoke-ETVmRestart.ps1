[CmdletBinding()]
param(
    [int]$TimeoutSec = 120,
    [int]$PollMs = 1000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$etRoot = Join-Path $repoRoot 'ETWorkbench'
$coreModule = Join-Path $etRoot 'Modules\ET.Core.psm1'
$watchTaskScript = Join-Path $etRoot 'Tasks\Watch-Commands.ps1'

if (-not (Test-Path -LiteralPath $coreModule)) {
    throw "Missing module: $coreModule"
}
Import-Module $coreModule -Force -ErrorAction Stop

$cmdDir = Get-ETPath -Category LocalDir -Name Commands -Ensure
$resDir = Get-ETPath -Category LocalDir -Name Results -Ensure

$requestId = New-ETRequestId
$cmdPath = Join-Path $cmdDir ("CMD-{0}.json" -f $requestId)
$resPath = Join-Path $resDir ("RES-{0}.json" -f $requestId)

$payload = [pscustomobject]@{
    RequestId   = $requestId
    CommandType = 'RestartWorkbench'
    Params      = [pscustomobject]@{}
    IssuedAt    = (Get-Date -Format 'o')
    IssuedBy    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

Write-ETJsonAtomic -LiteralPath $cmdPath -InputObject $payload -Depth 5

$watchTask = Get-ScheduledTask -TaskName 'ET-WatchCommands' -ErrorAction SilentlyContinue
if ($watchTask) {
    Start-ScheduledTask -TaskName 'ET-WatchCommands' -ErrorAction SilentlyContinue
}
elseif (Test-Path -LiteralPath $watchTaskScript) {
    # Fallback when task is not registered.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $watchTaskScript | Out-Null
}

$deadline = (Get-Date).AddSeconds([Math]::Max(5, $TimeoutSec))
do {
    if (Test-Path -LiteralPath $resPath) {
        $ack = Get-Content -LiteralPath $resPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ack.Success) {
            Write-Host ("[ET] VM restart acknowledged. RequestId={0}" -f $requestId) -ForegroundColor Green
            Write-Host 'DONE' -ForegroundColor Green
            exit 0
        }

        $err = if ($ack.Error) { $ack.Error } else { 'Unknown failure.' }
        Write-Host ("[ET] VM restart failed. RequestId={0} Error={1}" -f $requestId, $err) -ForegroundColor Yellow
        exit 1
    }

    Start-Sleep -Milliseconds ([Math]::Max(200, $PollMs))
} while ((Get-Date) -lt $deadline)

Write-Host ("[ET] VM restart timeout. RequestId={0} (no ack in {1}s)" -f $requestId, $TimeoutSec) -ForegroundColor Yellow
exit 1
