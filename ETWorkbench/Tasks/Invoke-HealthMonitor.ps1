<#
.SYNOPSIS
    Invoke-HealthMonitor —— 周期健康采集任务（E-05）。

.DESCRIPTION
    由计划任务 ET-HealthMonitor 周期调用（间隔取 workstation.json 的 Health.CollectIntervalMinutes）。

    流程（方案 §7 E-05 步骤）：
      1) 采集并评估（Invoke-ETHealthCheck，含 Duration/Debounce/Dedupe 状态机）
      2) 采样结果落快照（供 GUI 离线查看）
      3) 告警/恢复事件【先落本地 Outbox】（唯一真相来源，方案 §6.6 第 1 步）
      4) 尝试补传（失败不影响本步成功——事件已在本地，不会丢）
      5) 清理过期 .done 副本

    【关键】：退出码
      0 = 采集成功（无论共享是否可达）
      1 = 采集本身失败
    本任务绝不因为「共享挂了」而失败——断网是正常工况（G-6）。

.PARAMETER Console  同时输出到控制台（人工排障用）。
#>
[CmdletBinding()]
param(
    [switch]$Console
)

$ErrorActionPreference = 'Stop'

# ---- 自定位（约束 C-2：禁止硬编码路径）
$TaskDir = $PSScriptRoot
$Root = Split-Path -Parent $TaskDir
$ModuleDir = Join-Path $Root 'Modules'

foreach ($m in @('ET.Core.psm1', 'ET.MasterData.psm1', 'ET.Software.psm1', 'ET.Health.psm1', 'ET.Outbox.psm1')) {
    Import-Module (Join-Path $ModuleDir $m) -Force -ErrorAction Stop
}

$exit = 0
try {
    Write-ETLog -Message '健康采集任务开始' -Level Info

    # 1) 采集与评估
    $r = Invoke-ETHealthCheck

    # 2) 采样落快照
    try { Save-ETHealthSnapshot -Result $r }
    catch { Write-ETLog -Message '健康快照保存失败' -Level Warn -Data @{ Error = $_.Exception.Message } }

    # 3) 事件先落本地 Outbox
    $equipmentId = Get-ETOutboxEquipmentId
    $items = New-Object System.Collections.ArrayList

    foreach ($a in $r.Alarms) {
        [void]$items.Add((New-ETOutboxItem -EventType 'Alarm' -EquipmentId $equipmentId -Payload $a))
    }
    foreach ($e in $r.Events) {
        [void]$items.Add((New-ETOutboxItem -EventType 'Health' -EquipmentId $equipmentId -Payload $e))
    }
    # 采样本身也记一条健康事件（便于平台侧画趋势）
    [void]$items.Add((New-ETOutboxItem -EventType 'Health' -EquipmentId $equipmentId -Payload ([pscustomobject]@{
                    Kind      = 'HealthSample'
                    CheckedAt = $r.CheckedAt
                    SampleCount = $r.Samples.Count
                    AlarmCount  = $r.Alarms.Count
                    UnknownCount = $r.Unknowns.Count
                    Samples   = $r.Samples
                })))

    if ($items.Count -gt 0) {
        $b = Add-ETOutboxBatch -Items $items
        Write-ETLog -Message ('事件落盘：成功 {0}，失败 {1}' -f $b.Added, $b.Failed) -Level Info
    }

    # 4) 尝试补传（失败无害）
    try {
        $p = Publish-ETOutbox
        Write-ETLog -Message ('本轮补传：扫描 {0}，成功 {1}，待重试 {2}' -f $p.Scanned, $p.Published, $p.Retried) -Level Info
    }
    catch { Write-ETLog -Message '补传阶段异常（不影响采集）' -Level Warn -Data @{ Error = $_.Exception.Message } }

    # 5) 清理过期已完成副本
    try { $null = Clear-ETOutboxDone -KeepDays 7 } catch { }

    if ($Console) {
        Write-Host ("健康采集完成：采样 {0}，告警 {1}，未知 {2}" -f $r.Samples.Count, $r.Alarms.Count, $r.Unknowns.Count)
        foreach ($a in $r.Alarms) { Write-Host ("  [{0}] {1} {2}{3}" -f $a.Severity, $a.Name, $a.ComparatorOp, $a.Threshold) -ForegroundColor Yellow }
    }
}
catch {
    $exit = 1
    try { Write-ETLog -Message ('健康采集任务失败：{0}' -f $_.Exception.Message) -Level Error } catch { }
    if ($Console) { Write-Host ("健康采集任务失败：{0}" -f $_.Exception.Message) -ForegroundColor Red }
}

exit $exit
