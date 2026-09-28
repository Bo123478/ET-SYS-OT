<#
.SYNOPSIS
    Watch-Commands —— 命令轮询任务（方案 §4.2 GUI<->后台通道）。

.DESCRIPTION
    由计划任务 ET-WatchCommands 周期调用（间隔 5 分钟）。

    契约：
      输入  <DataRoot>\Commands\CMD-{RequestId}.json
      输出  <DataRoot>\Results\RES-{RequestId}.json

    命令信封字段：
      RequestId    : 与文件名一致（必填，^[A-Za-z0-9\-_]{1,64}$）
      CommandType  : 见下方【命令白名单】（必填）
      Params       : 命令参数对象（可选）
      IssuedAt     : 签发时间（可选）
      IssuedBy     : 签发者（可选，仅记录）

    【安全红线 F-8 / 约束 C-3】：
      - 只接受白名单内的 CommandType；未知类型一律拒绝并回执，绝不执行。
      - Params 中的值只作为【标识符/枚举】使用（ApplicationId / Version / EquipmentId），
        绝不接受任意路径后直接执行/复制/删除。
      - 本任务不接受 "RunScript" / "Exec" / "Shell" 这类通用执行命令。

    命令白名单（v1）：
      Ping              —— 存活探测，回执主机名/设备号/时间
      GetIdentity       —— 执行识别链并落快照
      GetSoftwareState  —— 返回软件 7 态摘要
      StartDownload     —— 触发指定应用的批准版本下载（只传 ApplicationId + Version）
      HealthCheck       —— 立即执行一次健康采集
      PublishOutbox     —— 立即补传一次
      GetOutboxSummary  —— 返回本地 Outbox 待发统计
      SelfUpdate        —— 检查并执行工作台自更新（可带 Force）

.PARAMETER Console  同时输出到控制台。
#>
[CmdletBinding()]
param(
    [switch]$Console,
    [int]$MaxCommands = 20
)

$ErrorActionPreference = 'Stop'

# ---- 自定位（约束 C-2）
$TaskDir = $PSScriptRoot
$Root = Split-Path -Parent $TaskDir
$ModuleDir = Join-Path $Root 'Modules'

foreach ($m in @('ET.Core.psm1', 'ET.Identity.psm1', 'ET.MasterData.psm1', 'ET.Software.psm1', 'ET.Transfer.psm1', 'ET.Health.psm1', 'ET.Outbox.psm1', 'ET.Update.psm1')) {
    Import-Module (Join-Path $ModuleDir $m) -Force -ErrorAction Stop
}

# ---- 命令白名单（约束 C-3 / 红线 F-8）
$script:AllowedCommands = @(
    'Ping'
    'GetIdentity'
    'GetSoftwareState'
    'StartDownload'
    'HealthCheck'
    'PublishOutbox'
    'GetOutboxSummary'
    'SelfUpdate'
)

function Test-Identifier {
    <#
      .SYNOPSIS  校验一个字符串是安全标识符（不含路径分隔符、无 ..）。
      .DESCRIPTION  约束 C-3：任何来自外部的值只能是标识符，不能是路径。
    #>
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '[\\/]|\.\.') { return $false }
    if ($Value -notmatch '^[A-Za-z0-9\.\-_]{1,64}$') { return $false }
    return $true
}

function Invoke-ETCommand {
    <#
      .SYNOPSIS  执行一条命令，返回回执对象。
      .OUTPUTS   PSCustomObject { RequestId; CommandType; Success; Result; Error; ExecutedAt; DurationMs }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Command)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $reqId = "$($Command.RequestId)"
    $type = "$($Command.CommandType)"
    $success = $false
    $result = $null
    $errorText = $null

    if ($script:AllowedCommands -notcontains $type) {
        $errorText = ("命令不在白名单内，拒绝执行：{0}" -f $type)
        try { Write-ETAuditEvent -EquipmentId (Get-ETOutboxEquipmentId) -Operation ("Command:{0}" -f $type) -Result 'Denied' -Target $reqId -Detail $errorText } catch { }
        $sw.Stop()
        return [pscustomobject]@{
            RequestId = $reqId; CommandType = $type; Success = $false; Result = $null
            Error = $errorText; ExecutedAt = (Get-Date -Format 'o'); DurationMs = $sw.ElapsedMilliseconds
        }
    }

    $p = $Command.Params
    try {
        switch ($type) {
            'Ping' {
                $result = [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    EquipmentId  = Get-ETOutboxEquipmentId
                    User         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                    ServerTime   = (Get-Date -Format 'o')
                }
                $success = $true
            }
            'GetIdentity' {
                $r = Invoke-ETIdentityChain
                $result = [pscustomobject]@{ Status = $r.Status; EquipmentId = $r.Result.EquipmentId; Steps = $r.Steps }
                $success = $true
            }
            'GetSoftwareState' {
                $sum = Get-ETSoftwareStateSummary
                $result = [pscustomobject]@{ EvaluatedAt = $sum.EvaluatedAt; Counts = $sum.Counts; Rows = $sum.Rows }
                $success = $true
            }
            'StartDownload' {
                if (-not (Test-Identifier $p.ApplicationId)) { throw '缺少或非法参数：ApplicationId' }
                if (-not (Test-Identifier $p.Version)) { throw '缺少或非法参数：Version' }
                $r = Invoke-ETDownload -ApplicationId "$($p.ApplicationId)" -Version "$($p.Version)"
                $result = [pscustomobject]@{
                    Ok = $r.Ok; Status = $r.Status; TargetDir = $r.TargetDir
                    FileCount = $r.FileCount; Copied = $r.Copied; Verified = $r.Verified; Errors = $r.Errors
                }
                $success = [bool]$r.Ok
            }
            'HealthCheck' {
                $r = Invoke-ETHealthCheck
                Save-ETHealthSnapshot -Result $r
                $equipmentId = Get-ETOutboxEquipmentId
                $items = New-Object System.Collections.ArrayList
                foreach ($a in $r.Alarms) { [void]$items.Add((New-ETOutboxItem -EventType 'Alarm' -EquipmentId $equipmentId -Payload $a)) }
                foreach ($e in $r.Events) { [void]$items.Add((New-ETOutboxItem -EventType 'Health' -EquipmentId $equipmentId -Payload $e)) }
                if ($items.Count -gt 0) { $null = Add-ETOutboxBatch -Items $items }

                $p = Publish-ETOutbox
                $result = [pscustomobject]@{
                    CheckedAt = $r.CheckedAt; SampleCount = $r.Samples.Count
                    AlarmCount = $r.Alarms.Count; UnknownCount = $r.Unknowns.Count
                    Published = $p.Published; Retried = $p.Retried
                }
                $success = $true
            }
            'PublishOutbox' {
                $r = Publish-ETOutbox
                $result = [pscustomobject]@{ Scanned = $r.Scanned; Published = $r.Published; Retried = $r.Retried; Failed = $r.Failed; Skipped = $r.Skipped; Reason = $r.Reason }
                $success = $true
            }
            'GetOutboxSummary' {
                $s = Get-ETOutboxSummary
                $result = [pscustomobject]@{ Pending = $s.Pending; ByType = $s.ByType; OldestPendingTime = $s.OldestPendingTime; OldestPendingHours = $s.OldestPendingHours }
                $success = $true
            }
            'SelfUpdate' {
                $force = $false
                if ($p -and $p.Force) { $force = [bool]$p.Force }
                $r = Invoke-ETSelfUpdate -Force:$force
                $result = [pscustomobject]@{ Ok = $r.Ok; Status = $r.Status; From = $r.From; To = $r.To; RolledBack = $r.RolledBack; Errors = $r.Errors }
                $success = [bool]$r.Ok
            }
        }
    }
    catch {
        $errorText = $_.Exception.Message
        $success = $false
    }

    try {
        $audit = Write-ETAuditEvent -EquipmentId (Get-ETOutboxEquipmentId) -Operation ("Command:{0}" -f $type) `
            -Result $(if ($success) { 'Success' } else { 'Failure' }) -Target $reqId -Detail ("{0} ms" -f $sw.ElapsedMilliseconds)
        $null = Add-ETOutboxItem -Item (New-ETOutboxItem -EventType 'Audit' -EquipmentId (Get-ETOutboxEquipmentId) -Payload $audit)
    }
    catch { }

    $sw.Stop()
    return [pscustomobject]@{
        RequestId = $reqId; CommandType = $type; Success = $success; Result = $result
        Error = $errorText; ExecutedAt = (Get-Date -Format 'o'); DurationMs = $sw.ElapsedMilliseconds
    }
}

$exit = 0
try {
    $cmdDir = Get-ETPath -Category LocalDir -Name Commands -Ensure
    $resDir = Get-ETPath -Category LocalDir -Name Results -Ensure

    $files = @(Get-ChildItem -LiteralPath $cmdDir -Filter 'CMD-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -First $MaxCommands)

    if ($files.Count -eq 0) { if ($Console) { Write-Host '无待执行命令。' }; exit 0 }

    foreach ($f in $files) {
        $reqId = $f.BaseName -replace '^CMD-', ''
        $rejected = $false
        $ack = $null

        if (-not (Test-Identifier $reqId)) {
            $rejected = $true
            $ack = [pscustomobject]@{
                RequestId = $reqId; CommandType = '(unknown)'; Success = $false; Result = $null
                Error = '文件名中的 RequestId 非法，已忽略。'; ExecutedAt = (Get-Date -Format 'o'); DurationMs = 0
            }
        }
        else {
            try {
                # 约束 C-7：命令文件先原子 rename 到 .processing，避免两个进程重复执行
                $working = Join-Path $cmdDir ("CMD-{0}.processing" -f $reqId)
                Move-Item -LiteralPath $f.FullName -Destination $working -Force
                $cmd = Get-Content -LiteralPath $working -Raw -Encoding UTF8 | ConvertFrom-Json
                $ack = Invoke-ETCommand -Command $cmd
                Remove-Item -LiteralPath $working -Force -ErrorAction SilentlyContinue
            }
            catch {
                $rejected = $true
                $ack = [pscustomobject]@{
                    RequestId = $reqId; CommandType = '(unparsable)'; Success = $false; Result = $null
                    Error = ("命令文件无法解析：{0}" -f $_.Exception.Message)
                    ExecutedAt = (Get-Date -Format 'o'); DurationMs = 0
                }
                Remove-Item -LiteralPath (Join-Path $cmdDir ("CMD-{0}.processing" -f $reqId)) -Force -ErrorAction SilentlyContinue
            }
        }

        # 回执原子落盘
        $resPath = Join-Path $resDir ("RES-{0}.json" -f $reqId)
        try { Write-ETJsonAtomic -LiteralPath $resPath -InputObject $ack -Depth 6 }
        catch { Write-ETLog -Message ('回执写入失败：{0}' -f $resPath) -Level Warn -Data @{ Error = $_.Exception.Message } }

        Write-ETLog -Message ('命令处理：{0} -> {1}' -f $ack.CommandType, $(if ($ack.Success) { 'OK' } else { 'FAIL' })) -Level Info
        if ($Console) {
            Write-Host ("{0}  {1}  {2}" -f $ack.RequestId, $ack.CommandType, $(if ($ack.Success) { 'OK' } else { 'FAIL：' + $ack.Error }))
        }
        if ($rejected) { Write-ETLog -Message ('命令被拒绝：{0}' -f $ack.Error) -Level Warn }
    }
}
catch {
    $exit = 1
    try { Write-ETLog -Message ('命令轮询任务失败：{0}' -f $_.Exception.Message) -Level Error } catch { }
    if ($Console) { Write-Host ("命令轮询任务失败：{0}" -f $_.Exception.Message) -ForegroundColor Red }
}

exit $exit
