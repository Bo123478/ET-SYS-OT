<#
.SYNOPSIS
    Deeper integration smoke test for the ET workbench skeleton (headless).

.DESCRIPTION
    Loads all 8 modules exactly like Start-ETWorkbench.ps1 does, then exercises
    every public entry point the GUI / task scripts rely on, printing the real
    return shape of each. Intended to catch contract mismatches that a pure
    syntax check cannot.

    Read-only except for the local data root under C:\ProgramData\ETWorkbench.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ETIntegration.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$Root = Join-Path $repoRoot 'ETWorkbench'
$ModuleDir = Join-Path $Root 'Modules'

$pass = 0
$fail = 0
$warn = 0

function Section {
    param([string]$Name)
    Write-Host ''
    Write-Host ("---- {0} " -f $Name).PadRight(70, '-') -ForegroundColor Cyan
}

function Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $v = & $Body
        Write-Host ("  [OK  ] {0}" -f $Name) -ForegroundColor Green
        if ($null -ne $v) {
            $text = ($v | Out-String -Width 160).Trim()
            if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + ' ...' }
            foreach ($line in ($text -split "`r?`n")) { Write-Host ("         {0}" -f $line) -ForegroundColor DarkGray }
        }
        $script:pass++
        return $v
    }
    catch {
        Write-Host ("  [FAIL] {0} -- {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        return $null
    }
}

function Warn {
    param([string]$Name, [string]$Detail)
    Write-Host ("  [WARN] {0} -- {1}" -f $Name, $Detail) -ForegroundColor Yellow
    $script:warn++
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  ET workbench integration smoke test' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# ================================================================ 1. module load order (same as entry point)
Section '1. Module load (entry-point order)'

$scripts = @('ET.Core.psm1', 'ET.Identity.psm1', 'ET.MasterData.psm1', 'ET.Software.psm1',
    'ET.Transfer.psm1', 'ET.Health.psm1', 'ET.Outbox.psm1', 'ET.Update.psm1')

foreach ($m in $scripts) {
    Check ("Import {0}" -f $m) {
        Import-Module (Join-Path $ModuleDir $m) -Force -ErrorAction Stop
        $name = [System.IO.Path]::GetFileNameWithoutExtension($m)
        $mod = Get-Module $name
        ("exported {0} function(s)" -f @($mod.ExportedFunctions.Keys).Count)
    } | Out-Null
}

# ================================================================ 2. exported function inventory
Section '2. Exported functions per module'

foreach ($m in $scripts) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($m)
    $mod = Get-Module $name -ErrorAction SilentlyContinue
    if (-not $mod) { Warn $name 'not loaded'; continue }
    $fns = @($mod.ExportedFunctions.Keys) | Sort-Object
    Write-Host ("  {0,-16} {1,2}  {2}" -f $name, $fns.Count, ($fns -join ', ')) -ForegroundColor Gray
}

# ================================================================ 3. core services
Section '3. Core services'

Check 'Get-ETProgramRoot' { Get-ETProgramRoot } | Out-Null
Check 'Get-ETDataRoot' { Get-ETDataRoot } | Out-Null
Check 'Initialize-ETDataRoot' { $null = Initialize-ETDataRoot; 'ok' } | Out-Null
Check 'Get-ETShareReachableState' { Get-ETShareReachableState } | Out-Null
Check 'Get-ETCoreInfo' { Get-ETCoreInfo } | Out-Null
Check 'Test-ETWorkbench' { (Test-ETWorkbench).Message } | Out-Null

$dataRoot = Get-ETDataRoot
$missing = @()
foreach ($d in @('Config', 'Snapshot', 'Commands', 'Results', 'Outbox', 'Cache', 'Backup', 'Logs', 'Temp')) {
    if (-not (Test-Path -LiteralPath (Join-Path $dataRoot $d))) { $missing += $d }
}
if ($missing.Count -eq 0) {
    Write-Host '  [OK  ] all expected local dirs exist' -ForegroundColor Green
    $pass++
}
else {
    Write-Host ("  [FAIL] missing local dirs: {0}" -f ($missing -join ', ')) -ForegroundColor Red
    $fail++
}

# ================================================================ 4. identity (E-02)
Section '4. Identity (E-02)'

Check 'Get-ETBiosSerialNumber' { Get-ETBiosSerialNumber } | Out-Null
Check 'Get-ETBusinessIp' { Get-ETBusinessIp } | Out-Null
Check 'Get-ETInstalledApplications' {
    $apps = @(Get-ETInstalledApplications)
    ("{0} installed application(s)" -f $apps.Count)
} | Out-Null
Check 'Invoke-ETIdentityChain' { Invoke-ETIdentityChain -NoPersist } | Out-Null

# ================================================================ 5. master data (E-01)
Section '5. Master data (E-01)'

Check 'Get-ETMasterDataSpec' {
    $s = Get-ETMasterDataSpec
    $keys = @($s.Keys)
    ("kinds ({0}): {1}" -f $keys.Count, ($keys -join ', '))
} | Out-Null
Check 'Get-ETMasterDataStatus' { Get-ETMasterDataStatus } | Out-Null
Check 'Get-ETMasterDataSnapshot -Kind applications' { Get-ETMasterDataSnapshot -Kind applications } | Out-Null
Check 'Import-ETMasterDataSnapshot' { Import-ETMasterDataSnapshot } | Out-Null

# ================================================================ 6. software (E-03)
Section '6. Software state (E-03)'

$sum = Check 'Get-ETSoftwareStateSummary' {
    $s = Get-ETSoftwareStateSummary
    ("Rows={0} Counts={1}" -f @($s.Rows).Count, ((@($s.Counts.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" })) -join ' '))
}

if ($sum -and $sum.Rows) {
    $first = @($sum.Rows)[0]
    Check 'Resolve-ETSoftwareState (first row)' {
        Resolve-ETSoftwareState -ApplicationId $first.ApplicationId -ApprovedVersion $first.ApprovedVersion
    } | Out-Null
}
else {
    Warn 'Resolve-ETSoftwareState' 'no rows in software summary (master data snapshot empty) - skipping'
}

Check 'Get-ETStateModel' {
    $m = Get-ETStateModel
    ("{0} states: {1}" -f @($m).Count, ((@($m) | ForEach-Object { $_.Label }) -join ' > '))
} | Out-Null

# ================================================================ 7. transfer (E-04)
Section '7. Transfer (E-04)'

Check 'Test-ETFreeSpace' { Test-ETFreeSpace -Path $env:TEMP -RequiredBytes 1048576 } | Out-Null
Check 'Get-ETDownloadPlan (unknown app -> honest failure)' {
    $p = Get-ETDownloadPlan -ApplicationId 'NO-SUCH-APP' -Version '0.0.0'
    ("Ok={0} Errors={1}" -f $p.Ok, (@($p.Errors) -join '; '))
} | Out-Null
Check 'Get-ETDownloadHistory' { ("{0} record(s)" -f @(Get-ETDownloadHistory).Count) } | Out-Null

# ================================================================ 8. health (E-05)
Section '8. Health (E-05)'

Check 'Get-ETHealthMetricCatalog' { ("{0} metric(s)" -f @(Get-ETHealthMetricCatalog).Count) } | Out-Null
Check 'Get-ETHealthMetrics (pre-check)' { ("{0} row(s)" -f @(Get-ETHealthMetrics).Count) } | Out-Null

$hc = $null
Check 'Invoke-ETHealthCheck' {
    # 必须把真实对象存到脚本作用域：Check 的返回值是【展示字符串】，
    # 不能当作 -Result 传给 Save-ETHealthSnapshot（这曾经真的写坏了快照文件）。
    $script:hcResult = Invoke-ETHealthCheck
    ("samples={0} alarms={1} events={2} unknowns={3}" -f @($script:hcResult.Samples).Count, @($script:hcResult.Alarms).Count, @($script:hcResult.Events).Count, @($script:hcResult.Unknowns).Count)
} | Out-Null
$hc = $script:hcResult

if ($hc) {
    Check 'Save-ETHealthSnapshot' { $null = Save-ETHealthSnapshot -Result $hc; 'saved' } | Out-Null
    Check 'Get-ETHealthMetrics (post-check)' {
        $rows = @(Get-ETHealthMetrics)
        $cols = ''
        $firstRow = @($rows | Select-Object -First 1)
        if ($firstRow.Count -gt 0) { $cols = (@($firstRow[0].PSObject.Properties | ForEach-Object { $_.Name }) -join ', ') }
        ("{0} row(s); columns: {1}" -f $rows.Count, $cols)
    } | Out-Null
    foreach ($a in @($hc.Alarms | Where-Object { $null -ne $_ })) {
        Warn 'Alarm raised on this machine' ("{0} {1}{2} (value {3})" -f $a.Name, $a.ComparatorOp, $a.Threshold, $a.Value)
    }
}

# ================================================================ 9. outbox (E-05 reporting)
Section '9. Outbox (E-05 reporting)'

Check 'Get-ETOutboxEquipmentId' { Get-ETOutboxEquipmentId } | Out-Null
Check 'Get-ETOutboxPendingCount' { Get-ETOutboxPendingCount } | Out-Null
Check 'Get-ETOutboxSummary' { Get-ETOutboxSummary } | Out-Null

Check 'New-ETOutboxItem + Add + Publish (round trip)' {
    $eq = Get-ETOutboxEquipmentId
    $payload = [pscustomobject]@{ Kind = 'SelfTest'; Note = 'integration smoke test'; At = (Get-Date -Format 'o') }
    $item = New-ETOutboxItem -EventType 'Health' -EquipmentId $eq -Payload $payload
    $add = Add-ETOutboxItem -Item $item
    $pub = Publish-ETOutboxItem -LocalPath $add.LocalPath
    $null = Clear-ETOutboxDone -KeepDays 0
    ("EventId={0} Status={1}" -f $item.EventId, $pub.Status)
} | Out-Null

Check 'Publish-ETOutbox (share unreachable -> honest skip)' {
    $r = Publish-ETOutbox
    ("Scanned={0} Published={1} Retried={2} Skipped={3} Reason={4}" -f $r.Scanned, $r.Published, $r.Retried, $r.Skipped, $r.Reason)
} | Out-Null

# ================================================================ 10. update (E-06)
Section '10. Self-update (E-06)'

Check 'Get-ETCurrentVersion' { Get-ETCurrentVersion } | Out-Null
Check 'Get-ETLocalVersions' { ("{0} version dir(s)" -f @(Get-ETLocalVersions).Count) } | Out-Null
Check 'Get-ETAvailableVersion' { Get-ETAvailableVersion } | Out-Null
Check 'Test-ETUpdateAvailable' { Test-ETUpdateAvailable } | Out-Null
Check 'Get-ETUpdateHistory' { ("{0} record(s)" -f @(Get-ETUpdateHistory).Count) } | Out-Null

# ================================================================ 11. XAML load (GUI parseability)
Section '11. GUI XAML'

Check 'XamlReader::Load(MainWindow.xaml)' {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    $xamlPath = Join-Path (Join-Path $Root 'UI') 'MainWindow.xaml'
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8))
    $win = [System.Windows.Markup.XamlReader]::Load($reader)
    $names = @($win.FindName('TxtIdentity'), $win.FindName('DgSoftware'), $win.FindName('CmbApplication'),
        $win.FindName('CmbVersion'), $win.FindName('GridHealth'), $win.FindName('TxtMdOut'),
        $win.FindName('TxtUpdateOut'), $win.FindName('TxtAbout')) | Where-Object { $null -ne $_ }
    ("window '{0}' loaded; {1}/8 key controls resolved" -f $win.Title, $names.Count)
} | Out-Null

# ================================================================ 12. entry script contract
Section '12. Start-ETWorkbench.ps1 control references'

Check 'every $ui.<Name> exists in the XAML' {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $xamlPath = Join-Path (Join-Path $Root 'UI') 'MainWindow.xaml'
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8))
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $entryText = Get-Content -LiteralPath (Join-Path $Root 'Start-ETWorkbench.ps1') -Raw -Encoding UTF8
    $refs = [regex]::Matches($entryText, '\$ui\.([A-Za-z][A-Za-z0-9_]*)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    $bad = @()
    foreach ($r in $refs) { if (-not $win.FindName($r)) { $bad += $r } }
    if ($bad.Count -gt 0) { throw ("unknown control(s) in Start-ETWorkbench.ps1: {0}" -f ($bad -join ', ')) }
    ("{0} control reference(s) all resolve" -f $refs.Count)
} | Out-Null

# ================================================================ summary
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ("  PASS {0}   FAIL {1}   WARN {2}" -f $pass, $fail, $warn) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host '============================================================' -ForegroundColor Cyan

if ($fail -eq 0) { exit 0 } else { exit 1 }
