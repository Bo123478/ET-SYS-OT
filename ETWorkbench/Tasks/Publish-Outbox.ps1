<#
.SYNOPSIS
    Publish-Outbox —— 周期补传任务（E-05 上报段）。

.DESCRIPTION
    由计划任务 ET-OutboxPublish 周期调用（间隔取 workstation.json 的 Health.OutboxPublishIntervalMinutes）。

    只做两件事：
      1) Publish-ETOutbox —— 把本地 Outbox 中的待发事件补传到共享
      2) Clear-ETOutboxDone —— 清理已发布副本

    幂等且可重入：
      - 同一事件重复发布不会产生重复文件（Publish-ETOutboxItem 按 TargetPath 判重）
      - 共享不可达时【不算失败】，本轮跳过，下轮再试（G-6）

.PARAMETER Console  同时输出到控制台。
#>
[CmdletBinding()]
param(
    [switch]$Console
)

$ErrorActionPreference = 'Stop'

# ---- 自定位（约束 C-2）
$TaskDir = $PSScriptRoot
$Root = Split-Path -Parent $TaskDir
$ModuleDir = Join-Path $Root 'Modules'

foreach ($m in @('ET.Core.psm1', 'ET.Outbox.psm1')) {
    Import-Module (Join-Path $ModuleDir $m) -Force -ErrorAction Stop
}

$exit = 0
try {
    # 共享不可达时直接静默退出（不算失败）
    $share = Get-ETShareReachableState
    if (-not $share.IsConfigured) {
        Write-ETLog '共享未配置，跳过本轮补传（G-6 允许）' -Level Info
        exit 0
    }
    if (-not $share.IsReachable) {
        Write-ETLog '共享不可达，跳过本轮补传（离线待补，不丢事件）' -Level Info -Data @{ Error = $share.Error }
        exit 0
    }

    $r = Publish-ETOutbox
    Write-ETLog -Message ('补传完成：扫描 {0}，成功 {1}，重试 {2}，失败 {3}，跳过 {4}' -f `
            $r.Scanned, $r.Published, $r.Retried, $r.Failed, $r.Skipped) -Level Info

    $null = Clear-ETOutboxDone -KeepDays 7

    if ($Console) {
        Write-Host ("补传完成：扫描 {0}，成功 {1}，重试 {2}，失败 {3}" -f $r.Scanned, $r.Published, $r.Retried, $r.Failed)
    }
}
catch {
    $exit = 1
    try { Write-ETLog -Message ('补传任务失败：{0}' -f $_.Exception.Message) -Level Error } catch { }
    if ($Console) { Write-Host ("补传任务失败：{0}" -f $_.Exception.Message) -ForegroundColor Red }
}

exit $exit
