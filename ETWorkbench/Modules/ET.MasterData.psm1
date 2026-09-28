<#
.SYNOPSIS
    ET.MasterData —— 主数据快照加载与校验（方案 E-01）。

.DESCRIPTION
    主数据不建 Dataverse 表，用共享上的 JSON/CSV（方案决策 4/8）。
    本模块负责：
      · 从共享 MasterData 目录【读取】(只读，不写)
      · 校验结构、必填字段、引用的完整性与唯一性
      · 落成本地快照，断网时用快照继续工作（G-6）
      · 对外提供强类型的查询函数，供 E-02/E-03/E-04 使用

    主数据文件契约（方案 §6.1 统一主键）：
      equipment.json          主键：EquipmentId
      devices.json            主键：DeviceId      外键：EquipmentId
      projects.json           主键：ProjectId
      applications.json       主键：ApplicationId
      approved-versions.json  主键：ApplicationId + Version
      mappings.json           SN/IP -> EquipmentId 映射

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
    GUI 侧的「主数据」页签（决策 21）调用 New-ETMasterDataDraft / Test-ETMasterDataDraft
    做录入与校验，再由运维把校验通过的文件放到共享。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')

# 主数据文件 -> 主键字段
$script:MasterDataSpec = [ordered]@{
    'equipment'         = 'EquipmentId'
    'devices'           = 'DeviceId'
    'projects'          = 'ProjectId'
    'applications'      = 'ApplicationId'
    'approved-versions' = ''
    'mappings'          = ''
}

function Get-ETMasterDataSpec {
    <#
      .SYNOPSIS  返回主数据文件与主键的约定表。
      .OUTPUTS   Hashtable
    #>
    [CmdletBinding()]
    param()
    return $script:MasterDataSpec
}

function Test-ETMasterDataDraft {
    <#
      .SYNOPSIS  校验主数据文件内容（E-01 核心 / GUI「主数据」页签调用）。

      .DESCRIPTION
        校验项（方案 §7 E-01 步骤 6）：
          1. 是合法 JSON
          2. 顶层是数组（除 mappings 允许为对象）
          3. 主键字段存在且非空
          4. 主键唯一
          5. 外键引用可解析（devices.EquipmentId ∈ equipment）
          6. 版本号格式（semver 粗校验）
          7. 无全角逗号/引号等常见中文录入事故
        全部通过才允许发布到共享。

      .PARAMETER FileName  主数据文件名（不含路径），如 equipment.json。
      .PARAMETER LiteralPath  待校验文件路径。
      .OUTPUTS   PSCustomObject { Ok; Errors[]; Warnings[]; RowCount }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$LiteralPath
    )

    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $key = $FileName -replace '\.json$', ''

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        [void]$errors.Add("文件不存在：$LiteralPath")
        return [pscustomobject]@{ Ok = $false; Errors = $errors; Warnings = $warnings; RowCount = 0 }
    }

    $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8

    # 常见中文录入事故：全角逗号 / 全角引号
    if ($raw -match '，') { [void]$errors.Add('检测到全角逗号「，」，JSON 只接受半角逗号「,」') }
    if ($raw -match '[""]') { [void]$errors.Add('检测到全角引号，JSON 只接受半角引号「"」') }

    $data = $null
    try { $data = $raw | ConvertFrom-Json }
    catch {
        [void]$errors.Add("不是合法 JSON：$($_.Exception.Message)")
        return [pscustomobject]@{ Ok = $false; Errors = $errors; Warnings = $warnings; RowCount = 0 }
    }

    $rows = @($data)

    if ($key -eq 'mappings') {
        return [pscustomobject]@{ Ok = ($errors.Count -eq 0); Errors = $errors; Warnings = $warnings; RowCount = 1 }
    }

    if ($rows.Count -eq 0) {
        [void]$warnings.Add('文件为空数组（合法，但确认是否漏录）')
        return [pscustomobject]@{ Ok = ($errors.Count -eq 0); Errors = $errors; Warnings = $warnings; RowCount = 0 }
    }

    # 主键存在性 + 唯一性
    if ($key -in $script:MasterDataSpec.Keys -and $script:MasterDataSpec[$key]) {
        $pk = $script:MasterDataSpec[$key]
        $seen = @{}
        $i = 0
        foreach ($r in $rows) {
            $i++
            $v = $null
            if (Test-ETObjectHasProperty -InputObject $r -Name $pk) { $v = $r.$pk }
            if ([string]::IsNullOrWhiteSpace("$v")) {
                [void]$errors.Add("第 $i 行缺少主键 $pk")
                continue
            }
            if ($seen.ContainsKey("$v")) {
                [void]$errors.Add("主键 $pk 重复：$v（第 $($seen["$v"]) 行与第 $i 行）")
            }
            else { $seen["$v"] = $i }
        }
    }

    # approved-versions 复合键
    if ($key -eq 'approved-versions') {
        $seen = @{}
        $i = 0
        foreach ($r in $rows) {
            $i++
            if ([string]::IsNullOrWhiteSpace("$($r.ApplicationId)") -or [string]::IsNullOrWhiteSpace("$($r.Version)")) {
                [void]$errors.Add("第 $i 行缺少 ApplicationId 或 Version")
                continue
            }
            $ck = "$($r.ApplicationId)@$($r.Version)"
            if ($seen.ContainsKey($ck)) { [void]$errors.Add("复合键重复：$ck") } else { $seen[$ck] = $i }
            if ("$($r.Version)" -notmatch '^\d+(\.\d+){1,3}(-[0-9A-Za-z\.\-]+)?$') {
                [void]$warnings.Add("第 $i 行版本号格式可疑：$($r.Version)")
            }
        }
    }

    # 外键：devices.EquipmentId -> equipment
    if ($key -eq 'devices') {
        $eqFile = Join-Path (Split-Path -Parent $LiteralPath) 'equipment.json'
        if (Test-Path -LiteralPath $eqFile) {
            try {
                $eqIds = @((Get-Content -LiteralPath $eqFile -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { "$($_.EquipmentId)" })
                foreach ($r in $rows) {
                    if ($r.EquipmentId -and ("$($r.EquipmentId)" -notin $eqIds)) {
                        [void]$errors.Add("外键悬空：devices.EquipmentId=$($r.EquipmentId) 在 equipment.json 中不存在")
                    }
                }
            }
            catch { [void]$warnings.Add('无法校验 devices->equipment 外键（equipment.json 不可解析）') }
        }
        else { [void]$warnings.Add('未找到 equipment.json，跳过外键校验') }
    }

    return [pscustomobject]@{
        Ok       = ($errors.Count -eq 0)
        Errors   = $errors
        Warnings = $warnings
        RowCount = $rows.Count
    }
}

function New-ETMasterDataDraft {
    <#
      .SYNOPSIS  生成主数据模板草稿（E-01 / GUI「主数据」页签的「新建」按钮）。
      .PARAMETER Kind  equipment / devices / projects / applications / approved-versions / mappings
      .OUTPUTS   PSCustomObject[]  可直接 ConvertTo-Json 的示例行
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Kind)

    switch ($Kind) {
        'equipment' { return @([pscustomobject]@{ EquipmentId = 'EQ-0001'; SiteName = ''; DeviceId = ''; ProjectId = ''; Note = '' }) }
        'devices' { return @([pscustomobject]@{ DeviceId = 'DEV-0001'; EquipmentId = 'EQ-0001'; DeviceType = ''; Note = '' }) }
        'projects' { return @([pscustomobject]@{ ProjectId = 'PRJ-0001'; ProjectName = ''; Note = '' }) }
        'applications' { return @([pscustomobject]@{ ApplicationId = 'APP-0001'; ApplicationName = ''; SoftwareId = 'APP-0001'; Note = '' }) }
        'approved-versions' { return @([pscustomobject]@{ ApplicationId = 'APP-0001'; Version = '1.0.0'; ReleaseId = ''; ReleasePath = ''; ApprovedTime = ''; Note = '' }) }
        'mappings' { return [pscustomobject]@{ BySerialNumber = @{}; ByIpAddress = @{} } }
        default { throw "未知的主数据类型：$Kind" }
    }
}

function Import-ETMasterDataSnapshot {
    <#
      .SYNOPSIS  从共享读取全部主数据并落本地快照（E-01 步骤 4）。
      .DESCRIPTION
        共享不可达时不报错——保留旧快照并返回 Stale，工作台继续可用（G-6）。
      .OUTPUTS   PSCustomObject { Status; TakenAt; Items; Errors[]; SnapshotDir }
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $errors = New-Object System.Collections.ArrayList
    $items = [ordered]@{}

    $shareMd = Get-ETSharePath -Category MasterData
    $snapDir = Get-ETPath -Category LocalDir -Name SnapshotMasterData -Ensure

    if (-not $shareMd) {
        return [pscustomobject]@{ Status = 'NotConfigured'; TakenAt = (Get-Date -Format 'o'); Items = $items; Errors = $errors; SnapshotDir = $snapDir }
    }

    if (-not (Test-Path -LiteralPath $shareMd)) {
        Write-ETLog -Message '共享主数据目录不可达，保留旧快照' -Level Warn -Data @{ ShareMasterData = $shareMd }
        return [pscustomobject]@{ Status = 'Stale'; TakenAt = (Get-Date -Format 'o'); Items = $items; Errors = $errors; SnapshotDir = $snapDir }
    }

    foreach ($kind in $script:MasterDataSpec.Keys) {
        $src = Join-Path $shareMd ($kind + '.json')
        if (-not (Test-Path -LiteralPath $src)) { [void]$errors.Add("缺少主数据文件：$kind.json"); continue }
        $v = Test-ETMasterDataDraft -FileName ($kind + '.json') -LiteralPath $src
        if (-not $v.Ok) {
            foreach ($e in $v.Errors) { [void]$errors.Add("[$kind] $e") }
            continue
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $snapDir ($kind + '.json')) -Force
        $items[$kind] = $v.RowCount
    }

    $meta = [pscustomobject]@{ TakenAt = (Get-Date -Format 'o'); Items = $items; Errors = $errors }
    Write-ETJsonAtomic -LiteralPath (Join-Path $snapDir 'snapshot-meta.json') -InputObject $meta

    return [pscustomobject]@{
        Status      = if ($errors.Count -eq 0) { 'Fresh' } else { 'Partial' }
        TakenAt     = $meta.TakenAt
        Items       = $items
        Errors      = $errors
        SnapshotDir = $snapDir
    }
}

function Get-ETMasterDataSnapshot {
    <#
      .SYNOPSIS  读取本地主数据快照。
      .PARAMETER Kind  equipment / devices / projects / applications / approved-versions / mappings
      .OUTPUTS   Object[] / PSCustomObject，未加载时返回 @()（空数组，绝不返回 $null）
      .NOTES
        重要：本函数【绝不】返回 $null。因为 @( 返回 $null 的函数 ) 会得到
        「含 1 个 $null 元素」的数组，配合 Set-StrictMode -Version 2.0，
        调用方一旦访问 $_.Property 就会抛「找不到属性」。
        返回 @() 可让 @() 包裹与 Where-Object 都安全。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Kind)

    $snapDir = Get-ETPath -Category LocalDir -Name SnapshotMasterData
    $f = Join-Path $snapDir ($Kind + '.json')
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    try {
        $obj = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $obj) { return @() }
        return $obj
    }
    catch { return @() }
}

function Get-ETMasterDataStatus {
    <#
      .SYNOPSIS  快照新鲜度（GUI 顶部状态条 / E-01 验收）。
      .OUTPUTS   PSCustomObject { Loaded; TakenAt; AgeHours; IsStale; Items }
    #>
    [CmdletBinding()]
    param([int]$StaleHours = 72)

    $snapDir = Get-ETPath -Category LocalDir -Name SnapshotMasterData
    $metaFile = Join-Path $snapDir 'snapshot-meta.json'
    if (-not (Test-Path -LiteralPath $metaFile)) {
        return [pscustomobject]@{ Loaded = $false; TakenAt = $null; AgeHours = $null; IsStale = $true; Items = [ordered]@{} }
    }
    $meta = Get-Content -LiteralPath $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $taken = [datetime]::Parse($meta.TakenAt)
    $age = ((Get-Date) - $taken).TotalHours
    return [pscustomobject]@{
        Loaded   = $true
        TakenAt  = $taken
        AgeHours = [math]::Round($age, 1)
        IsStale  = ($age -gt $StaleHours)
        Items    = $meta.Items
    }
}

function Export-ETMasterDataToShare {
    <#
      .SYNOPSIS  把校验通过的主数据发布到共享（E-01 步骤 7）。
      .DESCRIPTION
        遵守权限矩阵：共享 MasterData 对 ET 为【只读】（方案 §5.2）。
        因此本函数默认只【尝试】并在失败时给出明确提示，交由运维账号执行。
        绝不绕过权限，也绝不静默失败。
      .OUTPUTS   PSCustomObject { Ok; Published[]; Failed[]; Message }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalDir,
        [switch]$WhatIf
    )

    $shareMd = Get-ETSharePath -Category MasterData
    $published = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList

    if (-not $shareMd) {
        return [pscustomobject]@{ Ok = $false; Published = $published; Failed = $failed; Message = '未配置共享根' }
    }

    foreach ($kind in $script:MasterDataSpec.Keys) {
        $src = Join-Path $LocalDir ($kind + '.json')
        if (-not (Test-Path -LiteralPath $src)) { continue }

        $v = Test-ETMasterDataDraft -FileName ($kind + '.json') -LiteralPath $src
        if (-not $v.Ok) {
            foreach ($e in $v.Errors) { [void]$failed.Add("[$kind] $e") }
            continue
        }

        if ($WhatIf) { [void]$published.Add("$kind（演练）"); continue }

        try {
            $tmp = Join-Path $shareMd ($kind + '.json.tmp')
            Copy-Item -LiteralPath $src -Destination $tmp -Force -ErrorAction Stop
            Publish-ETFileAtomic -SourcePath $tmp -TargetPath (Join-Path $shareMd ($kind + '.json')) | Out-Null
            [void]$published.Add($kind)
        }
        catch {
            [void]$failed.Add("[$kind] 发布失败：$($_.Exception.Message)（共享 MasterData 对 ET 为只读，需运维账号执行）")
        }
    }

    return [pscustomobject]@{
        Ok        = ($failed.Count -eq 0)
        Published = $published
        Failed    = $failed
        Message   = if ($failed.Count -eq 0) { '全部发布成功' } else { ('{0} 项失败' -f $failed.Count) }
    }
}

Export-ModuleMember -Function @(
    'Get-ETMasterDataSpec'
    'Test-ETMasterDataDraft'
    'New-ETMasterDataDraft'
    'Import-ETMasterDataSnapshot'
    'Get-ETMasterDataSnapshot'
    'Get-ETMasterDataStatus'
    'Export-ETMasterDataToShare'
)
