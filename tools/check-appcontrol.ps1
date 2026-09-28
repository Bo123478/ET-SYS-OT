$ErrorActionPreference = 'Continue'

# NOTE: intentionally NO non-ASCII characters in this file (see show-ui.ps1).
# READ-ONLY diagnostics: inspects application-control policy configuration.
# Loads no application code, executes only the specific EXE names requested.

function Section([string]$t) {
    Write-Host ''
    Write-Host ('=' * 68)
    Write-Host $t
    Write-Host ('=' * 68)
}

Section '1. AppLocker policy (HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2)'
$srp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2'
if (Test-Path $srp) {
    Get-ChildItem $srp -ErrorAction SilentlyContinue | ForEach-Object {
        $coll = $_.PSChildName
        Write-Host ("  Collection: {0}" -f $coll)
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
            $xml = (Get-ItemProperty -Path $_.PSPath -Name Value -ErrorAction SilentlyContinue).Value
            $ruleName = ''
            $action = ''
            $type = ''
            $cond = ''
            if ($xml) {
                try {
                    $x = [xml]$xml
                    $ruleName = $x.Rule.Name
                    $action = $x.Rule.Action
                    $type = $x.Rule.RuleType
                    $cond = $x.Rule.Conditions.InnerXml
                } catch { }
            }
            Write-Host ("    Rule      : {0}" -f $ruleName)
            Write-Host ("    Action    : {0}   Type: {1}" -f $action, $type)
            if ($cond) {
                $cond -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                    Write-Host ("      {0}" -f $_.Trim())
                }
            }
            Write-Host ''
        }
    }
} else {
    Write-Host '  (not present - AppLocker policy not configured)'
}

Section '2. Software Restriction Policies (SRP Safer)'
$safer = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer'
if (Test-Path $safer) {
    Get-ChildItem $safer -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 40 |
        ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
} else {
    Write-Host '  (not present - SRP not configured)'
}

Section '3. AppLocker service state'
Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType |
    Format-Table -AutoSize | Out-String | Write-Host

Section '4. WDAC / CI policy files present'
$ci = Join-Path $env:windir 'System32\CodeIntegrity\CiPolicies\Active'
if (Test-Path $ci) {
    $pol = Get-ChildItem $ci -ErrorAction SilentlyContinue
    if ($pol) { $pol | ForEach-Object { Write-Host ("  {0}  {1} bytes" -f $_.Name, $_.Length) } }
    else { Write-Host '  (active folder empty - no WDAC policy deployed)' }
} else {
    Write-Host '  (folder not present)'
}

Section '5. AppLocker enforcement effective?'
Write-Host '  Checking AppLocker service readiness...'
$ready = (Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status
Write-Host ("  AppIDSvc status: {0}" -f $ready)
Write-Host '  Note: AppLocker enforces only if AppIDSvc is Running AND a policy exists.'
