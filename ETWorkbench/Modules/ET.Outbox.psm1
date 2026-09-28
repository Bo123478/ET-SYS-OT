<#
.SYNOPSIS
    ET.Outbox —— 事件落盘与补传（方案 E-05 / §6.6）。

.DESCRIPTION
    最小上报模型（方案 §6.6 / 决策 9）：
      1) 任何事件【先落本地 Outbox】——这是唯一真相来源
      2) 尝试写共享（\Upload\{EquipmentId}\{yyyy}\{MM}\{dd}\...）
      3) 写失败 → 保留在本地，等 Publish-Outbox.ps1 周期补传
      4) 补传成功才删本地；带指数退避，避免网络恢复时打爆共享

    Outbox 字段（方案 §6.10）：
      EventId, EventType, EquipmentId, ApplicationId, Version, ReleaseId,
      CreatedTime, RetryCount, NextRetry, Checksum, LocalPath, Status, LastError

    并发约束（C-7）：同一时刻只有一个进程写 Outbox（由锁文件保证）。

    权限约束（方案 §5.2 / 红线 F-12）：
      只允许读/写【自身 EquipmentId】的 Upload 子目录；
      绝不访问其他设备的 Upload。

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')

# 未上报事件的状态标签
$script:PendingStatuses = @('Pending', 'Retry', 'Failed')

function Get-ETOutboxRoot {
    <#
      .SYNOPSIS  本地 Outbox 根目录（已确保存在）。
    #>
    [CmdletBinding()]
    param()
    return (Get-ETPath -Category LocalDir -Name Outbox -Ensure)
}

function Get-ETOutboxEventTypeDirName {
    <#
      .SYNOPSIS  事件类型 -> Outbox 子目录名（与 paths.json 一致）。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Health', 'Alarm', 'Deployment', 'Audit')][string]$EventType)

    $paths = Get-ETPathsConfig
    return $paths.OutboxSubDirs[$EventType]
}

function Get-ETOutboxPendingCount {
    <#
      .SYNOPSIS  统计待上报事件数（HR-SELF-OUTBOX 规则与 E-05 用）。
      .OUTPUTS   [int]
    #>
    [CmdletBinding()]
    param()

    $root = Get-ETOutboxRoot
    if (-not (Test-Path -LiteralPath $root)) { return 0 }

    $n = 0
    foreach ($sub in @('Health', 'Alarm', 'Deployment', 'Audit')) {
        $d = Join-Path $root $sub
        if (Test-Path -LiteralPath $d) {
            # 只看 .json（未发布）/ .pending（待重试）；.done 表示已发布
            $n += @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.json', '.pending') }).Count
        }
    }
    return $n
}

function Get-ETOutboxEquipmentId {
    <#
      .SYNOPSIS  取本机设备编号（供构造事件信封）。

      .DESCRIPTION
        取值优先级（与方案 §6.4 识别链一致，但不做网络访问）：
          1) <DataRoot>\Snapshot\identity.json 的 Result.EquipmentId（识别链结果，最权威）
          2) workstation.json 的 Identity.EquipmentIdOverride（人工待定值）
          3) $env:COMPUTERNAME（最后兜底，保证仍能落盘而不丢事件）

      .OUTPUTS   [string]
    #>
    [CmdletBinding()]
    param()

    try {
        $f = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'identity.json'
        if (Test-Path -LiteralPath $f) {
            $s = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.Result -and $s.Result.EquipmentId) { return "$($s.Result.EquipmentId)" }
        }
    }
    catch { }

    try {
        $cfg = Get-ETConfig
        if ($cfg.Identity.EquipmentIdOverride) { return "$($cfg.Identity.EquipmentIdOverride)" }
    }
    catch { }

    return $env:COMPUTERNAME
}

function New-ETOutboxItem {
    <#
      .SYNOPSIS  构造一条符合 §6.10 字段约定的事件信封（不落盘）。
      .OUTPUTS   PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Health', 'Alarm', 'Deployment', 'Audit')][string]$EventType,
        [Parameter(Mandatory)][string]$EquipmentId,
        [Parameter(Mandatory)]$Payload,
        [string]$ApplicationId,
        [string]$Version,
        [string]$ReleaseId
    )

    $prefix = switch ($EventType) {
        'Health'     { 'EVT' }
        'Alarm'      { 'ALM' }
        'Deployment' { 'DEP' }
        'Audit'      { 'AUD' }
    }

    $eventId = New-ETEventId -Prefix $prefix -EquipmentId $EquipmentId
    $created = (Get-Date -Format 'o')

    $env = [pscustomobject]@{
        EventId       = $eventId
        EventType     = $EventType
        EquipmentId   = $EquipmentId
        ApplicationId = $ApplicationId
        Version       = $Version
        ReleaseId     = $ReleaseId
        CreatedTime   = $created
        RetryCount    = 0
        NextRetry     = $created
        Checksum      = ''
        LocalPath     = ''
        Status        = 'Pending'
        LastError     = ''
        SchemaVersion = '1.0.0'
        Payload       = $Payload
    }

    $json = $env | ConvertTo-Json -Compress -Depth 10
    $sha = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($json))
    ).Replace('-', '')
    $env.Checksum = $sha

    return $env
}

function Add-ETOutboxItem {
    <#
      .SYNOPSIS  事件先落本地 Outbox（方案 §6.6 第 1 步，唯一真相来源）。

      .DESCRIPTION
        One Event = One File（约束 C-5）：一个事件一个 .json 文件。
        原子写：.tmp -> 校验 -> rename。文件名即 EventId，天然幂等。

      .OUTPUTS   PSCustomObject { EventId; LocalPath; Ok; Error }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)

    $dirName = Get-ETOutboxEventTypeDirName -EventType "$($Item.EventType)"
    $dir = Join-Path (Get-ETOutboxRoot) $dirName
    $null = New-Item -ItemType Directory -Path $dir -Force

    $path = Join-Path $dir ('{0}.json' -f $Item.EventId)

    try {
        Write-ETJsonAtomic -LiteralPath $path -InputObject $Item -Depth 10
        return [pscustomobject]@{ Ok = $true; EventId = $Item.EventId; LocalPath = $path; Error = $null }
    }
    catch {
        Write-ETLog -Message '事件落本地 Outbox 失败' -Level Error -Data @{ EventId = "$($Item.EventId)"; Error = $_.Exception.Message }
        return [pscustomobject]@{ Ok = $false; EventId = $Item.EventId; LocalPath = $path; Error = $_.Exception.Message }
    }
}

function Add-ETOutboxBatch {
    <#
      .SYNOPSIS  批量落盘（一轮健康检测产出的多条事件一次写入）。
      .OUTPUTS   PSCustomObject { Added; Failed; Items[] }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)

    $added = 0; $failed = 0; $out = New-Object System.Collections.ArrayList
    foreach ($i in $Items) {
        $r = Add-ETOutboxItem -Item $i
        if ($r.Ok) { $added++ } else { $failed++ }
        [void]$out.Add($r)
    }
    return [pscustomobject]@{ Added = $added; Failed = $failed; Items = $out }
}

function Get-ETOutboxTargetPath {
    <#
      .SYNOPSIS  计算事件在共享上的目标路径（方案 §7.2 目录契约）。

      .DESCRIPTION
        \Upload\{EquipmentId}\{yyyy}\{MM}\{dd}\{EventType}\{EventId}.json

        安全前提：EquipmentId 来自识别链，不是用户输入任意字符串。
        本函数仍做校验——禁止路径穿越（红线 F-12 的落地实现）。

      .OUTPUTS   [string] 或 $null（未配置共享/非法 EquipmentId）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EquipmentId,
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$EventId,
        [datetime]$Time = (Get-Date)
    )

    # 防路径穿越：EquipmentId 只允许字母数字与 - _
    if ($EquipmentId -notmatch '^[A-Za-z0-9\-_]+$') {
        Write-ETLog -Message '拒绝发布：EquipmentId 含非法字符' -Level Error -Data @{ EquipmentId = $EquipmentId }
        return $null
    }

    $segs = @($EquipmentId, $Time.ToString('yyyy'), $Time.ToString('MM'), $Time.ToString('dd'), $EventType)
    $dir = Get-ETSharePath -Category Upload -ChildSegments $segs
    if (-not $dir) { return $null }
    return (Join-Path $dir ('{0}.json' -f $EventId))
}

function Publish-ETOutboxItem {
    <#
      .SYNOPSIS  尝试把一条本地事件发布到共享（方案 §6.6 第 2~3 步）。

      .DESCRIPTION
        原子发布（约束 C-4）：先写 <目标>.tmp，校验大小 + SHA256，再 rename 为 .json。
        失败不删除本地文件，只更新 RetryCount / NextRetry / LastError（指数退避）。

      .OUTPUTS   PSCustomObject { Ok; EventId; Status; TargetPath; Error }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LocalPath)

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; EventId = $null; Status = 'Missing'; TargetPath = $null; Error = '本地文件不存在' }
    }

    try {
        $item = Get-Content -LiteralPath $LocalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ Ok = $false; EventId = $null; Status = 'Corrupt'; TargetPath = $null; Error = $_.Exception.Message }
    }

    $target = Get-ETOutboxTargetPath -EquipmentId "$($item.EquipmentId)" -EventType "$($item.EventType)" -EventId "$($item.EventId)" -Time ([datetime]::Parse($item.CreatedTime))
    if (-not $target) {
        return [pscustomobject]@{ Ok = $false; EventId = "$($item.EventId)"; Status = 'NoTarget'; TargetPath = $null; Error = '无法解析共享目标路径（共享未配置或 EquipmentId 非法）' }
    }

    $dir = Split-Path -Parent $target
    try {
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

        # 幂等：已发布过就直接标记完成
        if (Test-Path -LiteralPath $target) {
            $done = Join-Path (Split-Path -Parent $LocalPath) ('{0}.json.done' -f $item.EventId)
            Move-Item -LiteralPath $LocalPath -Destination $done -Force
            return [pscustomobject]@{ Ok = $true; EventId = "$($item.EventId)"; Status = 'AlreadyPublished'; TargetPath = $target; Error = $null }
        }

        $tmp = '{0}.tmp' -f $target
        Copy-Item -LiteralPath $LocalPath -Destination $tmp -Force -ErrorAction Stop

        Publish-ETFileAtomic -SourcePath $tmp -TargetPath $target -ExpectedSize (Get-Item -LiteralPath $LocalPath).Length | Out-Null

        $done2 = Join-Path (Split-Path -Parent $LocalPath) ('{0}.json.done' -f $item.EventId)
        Move-Item -LiteralPath $LocalPath -Destination $done2 -Force

        return [pscustomobject]@{ Ok = $true; EventId = "$($item.EventId)"; Status = 'Published'; TargetPath = $target; Error = $null }
    }
    catch {
        # 失败：更新重试信息（不删本地）
        try {
            $item.RetryCount = [int]$item.RetryCount + 1
            $delayMinutes = [math]::Min(120, [math]::Pow(2, [math]::Min($item.RetryCount, 7)))
            $item.NextRetry = (Get-Date).AddMinutes($delayMinutes).ToString('o')
            $item.Status = 'Retry'
            $item.LastError = $_.Exception.Message
            Write-ETJsonAtomic -LiteralPath $LocalPath -InputObject $item -Depth 10
        }
        catch { }

        Write-ETLog -Message '事件上报失败，保留本地待补传' -Level Warn -Data @{ EventId = "$($item.EventId)"; Error = $_.Exception.Message }
        return [pscustomobject]@{ Ok = $false; EventId = "$($item.EventId)"; Status = 'Retry'; TargetPath = $target; Error = $_.Exception.Message }
    }
}

function Publish-ETOutbox {
    <#
      .SYNOPSIS  批量补传（E-05 主入口，Publish-Outbox.ps1 计划任务调用）。

      .DESCRIPTION
        扫描全部 Outbox 子目录，按 NextRetry <= now 挑出可重试的事件逐条发布。
        单次运行有 MaxItems 上限，避免网络恢复瞬间把共享打爆。

      .PARAMETER MaxItems  单次最多发布多少条（默认 200）。
      .OUTPUTS   PSCustomObject { Scanned; Published; Retried; Failed; Skipped; DurationSeconds }
    #>
    [CmdletBinding()]
    param([int]$MaxItems = 200)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $root = Get-ETOutboxRoot

    # 共享不可达时直接退出，不做无谓重试（HR-SHARE 会另行告警）
    $share = Get-ETShareReachableState
    if (-not $share.IsConfigured) {
        return [pscustomobject]@{ Scanned = 0; Published = 0; Retried = 0; Failed = 0; Skipped = 0; DurationSeconds = 0; Reason = '未配置共享' }
    }
    if (-not $share.IsReachable) {
        Write-ETLog -Message '共享不可达，本轮补传跳过' -Level Warn -Data @{ Error = $share.Error }
        return [pscustomobject]@{ Scanned = 0; Published = 0; Retried = 0; Failed = 0; Skipped = 0; DurationSeconds = 0; Reason = '共享不可达' }
    }

    $files = @()
    foreach ($sub in @('Health', 'Alarm', 'Deployment', 'Audit')) {
        $d = Join-Path $root $sub
        if (Test-Path -LiteralPath $d) {
            $files += @(Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue)
        }
    }

    $scanned = $files.Count
    $published = 0; $retried = 0; $failed = 0; $skipped = 0

    foreach ($f in ($files | Sort-Object LastWriteTime | Select-Object -First $MaxItems)) {
        # 检查 NextRetry
        $due = $true
        try {
            $probe = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($probe.NextRetry) { $due = ((Get-Date) -ge [datetime]::Parse($probe.NextRetry)) }
        }
        catch { $due = $true }

        if (-not $due) { $skipped++; continue }

        $r = Publish-ETOutboxItem -LocalPath $f.FullName
        switch ($r.Status) {
            'Published'        { $published++ }
            'AlreadyPublished' { $published++ }
            'Retry'            { $retried++ }
            default            { $failed++ }
        }
    }

    $sw.Stop()
    Write-ETLog -Message ('Outbox 补传完成：扫描 {0}，成功 {1}，待重试 {2}，跳过 {3}' -f $scanned, $published, $retried, $skipped) -Level Info

    return [pscustomobject]@{
        Scanned = $scanned; Published = $published; Retried = $retried
        Failed = $failed; Skipped = $skipped
        DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        Reason = $null
    }
}

function Get-ETOutboxSummary {
    <#
      .SYNOPSIS  Outbox 概览（GUI 状态条 / E-05 验收）。
      .OUTPUTS   PSCustomObject { Pending; ByType; OldestPendingTime; OldestPendingHours }
    #>
    [CmdletBinding()]
    param()

    $root = Get-ETOutboxRoot
    $byType = [ordered]@{ Health = 0; Alarm = 0; Deployment = 0; Audit = 0 }
    $oldest = $null

    foreach ($sub in @('Health', 'Alarm', 'Deployment', 'Audit')) {
        $d = Join-Path $root $sub
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $items = @(Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue)
        $byType[$sub] = $items.Count
        if ($items.Count -gt 0) {
            $o = ($items | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
            if (-not $oldest -or $o -lt $oldest) { $oldest = $o }
        }
    }

    $pending = ($byType.Values | Measure-Object -Sum).Sum
    return [pscustomobject]@{
        Pending            = [int]$pending
        ByType             = $byType
        OldestPendingTime  = $oldest
        OldestPendingHours = if ($oldest) { [math]::Round(((Get-Date) - $oldest).TotalHours, 1) } else { 0 }
    }
}

function Clear-ETOutboxDone {
    <#
      .SYNOPSIS  清理已发布完成（.done）的本地副本，保留最近 N 天。
      .DESCRIPTION
        只删 .done 文件——绝不删未上报的 .json（否则会丢事件）。
    #>
    [CmdletBinding()]
    param([int]$KeepDays = 7)

    $cut = (Get-Date).AddDays(-$KeepDays)
    $removed = 0
    foreach ($sub in @('Health', 'Alarm', 'Deployment', 'Audit')) {
        $d = Join-Path (Get-ETOutboxRoot) $sub
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.done' -File -ErrorAction SilentlyContinue)) {
            if ($f.LastWriteTime -lt $cut) { Remove-Item -LiteralPath $f.FullName -Force; $removed++ }
        }
    }
    return $removed
}

Export-ModuleMember -Function @(
    'Get-ETOutboxRoot'
    'Get-ETOutboxEventTypeDirName'
    'Get-ETOutboxEquipmentId'
    'Get-ETOutboxPendingCount'
    'New-ETOutboxItem'
    'Add-ETOutboxItem'
    'Add-ETOutboxBatch'
    'Get-ETOutboxTargetPath'
    'Publish-ETOutboxItem'
    'Publish-ETOutbox'
    'Get-ETOutboxSummary'
    'Clear-ETOutboxDone'
)
