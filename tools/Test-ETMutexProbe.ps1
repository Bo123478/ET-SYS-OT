# Empirical two-process test for the named mutex single-instance pattern.
[CmdletBinding()]
param(
    [string]$MutexName = 'Global\ETWorkbench.Plate.SingleInstance',
    [int]$HoldSeconds = 3
)

$ErrorActionPreference = 'Stop'

$holder = $null
$acquired = $false
try {
    $holder = New-Object System.Threading.Mutex($false, $MutexName)
    $acquired = $holder.WaitOne(2000, $false)
}
catch {
    Write-Host ("[TEST] Mutex creation failed: {0}" -f $_.Exception.Message)
    exit 2
}

if ($acquired) {
    Write-Host ("[TEST] PID {0} ACQUIRED lock, holding {1}s" -f $PID, $HoldSeconds)
    Start-Sleep -Seconds $HoldSeconds
    Write-Host ("[TEST] PID {0} releasing lock" -f $PID)
}
else {
    Write-Host ("[TEST] PID {0} BLOCKED - lock already held (single instance works)" -f $PID)
}

exit 0
