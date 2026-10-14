[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('new', 'validate', 'publish')]
    [string]$Action,

    [string]$DraftDir,
    [string]$RuleSetName = 'ET-Default-RuleSet',
    [ValidateSet('Dev', 'Test', 'Prod')]
    [string]$Environment = 'Dev',
    [string]$Version
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$etRoot = Join-Path $repoRoot 'ETWorkbench'
$coreModule = Join-Path $etRoot 'Modules\ET.Core.psm1'

if (-not (Test-Path -LiteralPath $coreModule)) {
    throw "Missing module: $coreModule"
}

Import-Module $coreModule -Force -ErrorAction Stop

function Get-DraftDirPath {
    param([string]$InputDir, [string]$Name, [string]$Env)

    if ($InputDir) {
        return $InputDir
    }

    $tempRoot = Get-ETPath -Category LocalDir -Name Temp -Ensure
    return (Join-Path $tempRoot ("RuleDraft-{0}-{1}" -f $Name, $Env))
}

function ConvertTo-FlatArray {
    param($InputObject)

    $result = @()
    if ($null -eq $InputObject) { return ,$result }

    if ($InputObject -is [System.Array]) {
        foreach ($i in $InputObject) {
            $result += , $i
        }
        return ,$result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [pscustomobject]) {
        foreach ($i in $InputObject) {
            $result += , $i
        }
        return ,$result
    }

    $result += , $InputObject
    return ,$result
}

function New-RuleDraft {
    param([string]$TargetDir, [string]$Name, [string]$Env)

    $null = New-Item -Path $TargetDir -ItemType Directory -Force

    $ruleset = [pscustomobject]@{
        ruleSetId      = ([guid]::NewGuid().ToString('N'))
        name           = $Name
        environment    = $Env
        status         = 'Draft'
        version        = ''
        effectiveFrom  = ''
        description    = '规则草稿（主档式维护）'
    }

    $scopeId = ([guid]::NewGuid().ToString('N'))
    $scopes = @(
        [pscustomobject]@{
            scopeId        = $scopeId
            projectCode    = 'FT'
            equipmentType  = ''
            plantCode      = ''
            appGroup       = ''
            priority       = 100
            enabled        = $true
        }
    )

    $rules = @(
        [pscustomobject]@{
            ruleCode       = 'FT-APP-001'
            category       = 'AppVersion'
            severity       = 'Warn'
            enabled        = $true
            scopeId        = $scopeId
            operator       = 'eq'
            unknownPolicy  = 'UnknownAsWarn'
            matcher        = [pscustomobject]@{ applicationId = 'APP-FT-001' }
            expected       = [pscustomobject]@{ requiredVersion = '3.2.2'; allowedVersions = @('3.2.1', '3.2.2') }
            messageTemplate = '应用版本不符合工程标准'
            sortOrder      = 10
        },
        [pscustomobject]@{
            ruleCode       = 'FT-SVC-001'
            category       = 'WindowsService'
            severity       = 'Alarm'
            enabled        = $true
            scopeId        = $scopeId
            operator       = 'subset'
            unknownPolicy  = 'UnknownAsAlarm'
            matcher        = [pscustomobject]@{}
            expected       = [pscustomobject]@{
                services = @(
                    [pscustomobject]@{ name = 'MSSQLSERVER'; startupType = 'Automatic'; state = 'Running' },
                    [pscustomobject]@{ name = 'Spooler'; startupType = 'Automatic'; state = 'Running' }
                )
            }
            messageTemplate = 'Windows 服务基线不满足要求'
            sortOrder      = 20
        },
        [pscustomobject]@{
            ruleCode       = 'FT-COM-001'
            category       = 'ComPort'
            severity       = 'Warn'
            enabled        = $true
            scopeId        = $scopeId
            operator       = 'subset'
            unknownPolicy  = 'UnknownAsWarn'
            matcher        = [pscustomobject]@{}
            expected       = [pscustomobject]@{ requiredCount = 3; requiredPorts = @('COM3', 'COM5', 'COM8'); allowExtra = $true }
            messageTemplate = 'COM 口基线不满足要求'
            sortOrder      = 30
        },
        [pscustomobject]@{
            ruleCode       = 'FT-HOST-001'
            category       = 'HostMapping'
            severity       = 'Warn'
            enabled        = $true
            scopeId        = $scopeId
            operator       = 'subset'
            unknownPolicy  = 'UnknownAsWarn'
            matcher        = [pscustomobject]@{}
            expected       = [pscustomobject]@{
                entries = @(
                    [pscustomobject]@{ host = 'ft-api.local'; ip = '10.10.1.21' },
                    [pscustomobject]@{ host = 'ft-db.local'; ip = '10.10.1.22' }
                )
                checkOnly = $true
            }
            messageTemplate = 'Host 映射不满足工程要求'
            sortOrder      = 40
        }
    )

    Write-ETJsonAtomic -LiteralPath (Join-Path $TargetDir 'ruleset.json') -InputObject $ruleset -Depth 8
    Write-ETJsonAtomic -LiteralPath (Join-Path $TargetDir 'scopes.json') -InputObject $scopes -Depth 8
    Write-ETJsonAtomic -LiteralPath (Join-Path $TargetDir 'rules.json') -InputObject $rules -Depth 10

    Write-Host ("[ET] 规则草稿已生成：{0}" -f $TargetDir) -ForegroundColor Green
    Write-Host '[ET] 下一步：先 validate，再 publish。' -ForegroundColor Gray
}

function Validate-RuleDraft {
    param([string]$TargetDir)

    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList

    $rulesetPath = Join-Path $TargetDir 'ruleset.json'
    $scopesPath = Join-Path $TargetDir 'scopes.json'
    $rulesPath = Join-Path $TargetDir 'rules.json'

    foreach ($f in @($rulesetPath, $scopesPath, $rulesPath)) {
        if (-not (Test-Path -LiteralPath $f)) {
            [void]$errors.Add("缺少文件：$f")
        }
    }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{ Ok = $false; Errors = $errors; Warnings = $warnings; RuleCount = 0; ScopeCount = 0 }
    }

    try { $rs = Get-Content -LiteralPath $rulesetPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [void]$errors.Add("ruleset.json 不是合法 JSON：$($_.Exception.Message)") }
    try {
        $scopesObj = Get-Content -LiteralPath $scopesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $scopes = ConvertTo-FlatArray -InputObject $scopesObj
    }
    catch { [void]$errors.Add("scopes.json 不是合法 JSON：$($_.Exception.Message)") }
    try {
        $rulesObj = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $rules = ConvertTo-FlatArray -InputObject $rulesObj
    }
    catch { [void]$errors.Add("rules.json 不是合法 JSON：$($_.Exception.Message)") }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{ Ok = $false; Errors = $errors; Warnings = $warnings; RuleCount = 0; ScopeCount = 0 }
    }

    if ([string]::IsNullOrWhiteSpace("$($rs.name)")) { [void]$errors.Add('ruleset.name 不能为空') }
    if ("$($rs.environment)" -notin @('Dev', 'Test', 'Prod')) { [void]$errors.Add('ruleset.environment 必须为 Dev/Test/Prod') }

    $scopeIds = @{}
    foreach ($s in $scopes) {
        $sid = "$($s.scopeId)"
        if ([string]::IsNullOrWhiteSpace($sid)) { [void]$errors.Add('scopes.scopeId 不能为空'); continue }
        if ($scopeIds.ContainsKey($sid)) { [void]$errors.Add("scopeId 重复：$sid") } else { $scopeIds[$sid] = $true }
        if ($null -eq $s.priority) { [void]$warnings.Add("scope=$sid 未设置 priority，建议显式填写") }
    }

    $validCategory = @('AppVersion', 'WindowsService', 'ComPort', 'HostMapping')
    $validSeverity = @('Info', 'Warn', 'Alarm')
    $validUnknown = @('UnknownAsAlarm', 'UnknownAsWarn', 'Ignore')

    $ruleCodes = @{}
    foreach ($r in $rules) {
        $code = "$($r.ruleCode)"
        if ([string]::IsNullOrWhiteSpace($code)) { [void]$errors.Add('rules.ruleCode 不能为空'); continue }
        if ($ruleCodes.ContainsKey($code)) { [void]$errors.Add("ruleCode 重复：$code") } else { $ruleCodes[$code] = $true }

        $cat = "$($r.category)"
        if ($cat -notin $validCategory) { [void]$errors.Add("规则 $code 的 category 非法：$cat") }

        $sev = "$($r.severity)"
        if ($sev -notin $validSeverity) { [void]$errors.Add("规则 $code 的 severity 非法：$sev") }

        $unk = "$($r.unknownPolicy)"
        if ($unk -notin $validUnknown) { [void]$errors.Add("规则 $code 的 unknownPolicy 非法：$unk") }

        $sid = "$($r.scopeId)"
        if (-not [string]::IsNullOrWhiteSpace($sid) -and -not $scopeIds.ContainsKey($sid)) {
            [void]$errors.Add("规则 $code 引用了不存在的 scopeId：$sid")
        }

        if ($null -eq $r.matcher) { [void]$errors.Add("规则 $code 缺少 matcher") }
        if ($null -eq $r.expected) { [void]$errors.Add("规则 $code 缺少 expected") }
    }

    return [pscustomobject]@{
        Ok = ($errors.Count -eq 0)
        Errors = $errors
        Warnings = $warnings
        RuleCount = $rules.Count
        ScopeCount = $scopes.Count
    }
}

function Publish-RuleDraft {
    param([string]$TargetDir, [string]$Ver)

    $v = Validate-RuleDraft -TargetDir $TargetDir
    if (-not $v.Ok) {
        foreach ($e in $v.Errors) { Write-Host ("[ERR] {0}" -f $e) -ForegroundColor Red }
        throw '规则草稿校验未通过，已拒绝发布。'
    }

    $ruleset = Get-Content -LiteralPath (Join-Path $TargetDir 'ruleset.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $scopesObj = Get-Content -LiteralPath (Join-Path $TargetDir 'scopes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $rulesObj = Get-Content -LiteralPath (Join-Path $TargetDir 'rules.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $scopes = ConvertTo-FlatArray -InputObject $scopesObj
    $rules = ConvertTo-FlatArray -InputObject $rulesObj

    if ([string]::IsNullOrWhiteSpace($Ver)) {
        $Ver = ('v{0}' -f (Get-Date -Format 'yyyy.MM.dd.HHmmss'))
    }

    $bundle = [pscustomobject]@{
        ruleSet = $ruleset
        scopes = $scopes
        rules = $rules
        publishedAt = (Get-Date -Format 'o')
    }

    $shareRules = Get-ETSharePath -Category ConfigRules
    if ([string]::IsNullOrWhiteSpace($shareRules)) {
        throw '未配置 Share.ConfigRulesRelative，无法发布到服务器规则目录。'
    }
    if (-not (Test-Path -LiteralPath $shareRules)) {
        throw "服务器规则目录不可达：$shareRules"
    }

    $versionDir = Join-Path $shareRules (Join-Path 'versions' $Ver)
    $null = New-Item -Path $versionDir -ItemType Directory -Force

    $artifactPath = Join-Path $versionDir 'ruleset.json'
    Write-ETJsonAtomic -LiteralPath $artifactPath -InputObject $bundle -Depth 12

    $hashObj = Get-FileHash -Path $artifactPath -Algorithm SHA256
    $hash = $hashObj.Hash
    [System.IO.File]::WriteAllText((Join-Path $versionDir 'hash.sha256'), $hash, [System.Text.Encoding]::UTF8)

    $meta = [pscustomobject]@{
        version = $Ver
        publishedAt = (Get-Date -Format 'o')
        publishedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        ruleCount = $rules.Count
        scopeCount = $scopes.Count
        artifact = ("versions/{0}/ruleset.json" -f $Ver)
    }
    Write-ETJsonAtomic -LiteralPath (Join-Path $versionDir 'meta.json') -InputObject $meta -Depth 6

    $current = [pscustomobject]@{
        version = $Ver
        artifact = ("versions/{0}/ruleset.json" -f $Ver)
        sha256 = $hash
        publishedAt = (Get-Date -Format 'o')
    }
    Write-ETJsonAtomic -LiteralPath (Join-Path $shareRules 'current.json') -InputObject $current -Depth 5

    Write-Host ("[ET] 发布成功：{0}" -f $Ver) -ForegroundColor Green
    Write-Host ("[ET] 产物目录：{0}" -f $versionDir) -ForegroundColor Gray
}

$resolvedDraft = Get-DraftDirPath -InputDir $DraftDir -Name $RuleSetName -Env $Environment

switch ($Action) {
    'new' {
        New-RuleDraft -TargetDir $resolvedDraft -Name $RuleSetName -Env $Environment
        exit 0
    }
    'validate' {
        $r = Validate-RuleDraft -TargetDir $resolvedDraft
        Write-Host ("[ET] Draft={0}" -f $resolvedDraft)
        Write-Host ("[ET] Scope={0} Rule={1}" -f $r.ScopeCount, $r.RuleCount)
        foreach ($w in $r.Warnings) { Write-Host ("[WARN] {0}" -f $w) -ForegroundColor Yellow }
        if (-not $r.Ok) {
            foreach ($e in $r.Errors) { Write-Host ("[ERR] {0}" -f $e) -ForegroundColor Red }
            exit 1
        }
        Write-Host '[ET] 校验通过。' -ForegroundColor Green
        exit 0
    }
    'publish' {
        Publish-RuleDraft -TargetDir $resolvedDraft -Ver $Version
        exit 0
    }
}
