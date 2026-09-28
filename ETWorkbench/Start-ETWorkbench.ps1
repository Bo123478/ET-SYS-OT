<#
.SYNOPSIS
    ET 工作台唯一入口（方案 §5.4 / E-07）。

.DESCRIPTION
    用法：
      .\Start-ETWorkbench.ps1              # 启动 GUI
      .\Start-ETWorkbench.ps1 -SelfTest    # 无界面自检（用于部署后验证/自更新冒烟）
      .\Start-ETWorkbench.ps1 -Console     # 带控制台日志

    设计约束：
      C-1  本文件含中文，必须 UTF-8 with BOM
      C-2  所有路径由 $PSScriptRoot 推导，禁止硬编码
      C-3  GUI 只传标识符（SoftwareId / RuleId / RequestId），绝不传任意路径去执行

    安全红线（方案 §3.2）：
      · 不自动结束/重启业务软件
      · 不自动覆盖运行中的程序文件
      · 不强行解除文件锁、不抢焦点、不自动重启电脑
      · 不开放任何端口，不建 HTTP/API Server

.PARAMETER SelfTest  只跑 Test-ETWorkbench 并输出结论，不加载 UI。
.PARAMETER Console   显示控制台窗口与彩色日志。
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Console
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ================================================================ 0. 根路径（C-2）
$Script:Root = $PSScriptRoot
if (-not $Script:Root) { $Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Boot {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) { 'Warn' { 'Yellow' } 'Error' { 'Red' } default { 'Gray' } }
    if ($Console -or $SelfTest -or $Level -ne 'Info') {
        Write-Host ("[ET] {0}" -f $Message) -ForegroundColor $color
    }
}

# ================================================================ 1. 加载模块
$ModuleDir = Join-Path $Script:Root 'Modules'
$ModuleOrder = @(
    'ET.Core.psm1'
    'ET.Identity.psm1'
    'ET.MasterData.psm1'
    'ET.Software.psm1'
    'ET.Transfer.psm1'
    'ET.Health.psm1'
    'ET.Outbox.psm1'
    'ET.Update.psm1'
)

foreach ($m in $ModuleOrder) {
    $p = Join-Path $ModuleDir $m
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少模块文件：$p" }
    try {
        Import-Module $p -Force -ErrorAction Stop
    }
    catch {
        throw ("加载模块失败：{0} —— {1}" -f $m, $_.Exception.Message)
    }
}

# ================================================================ 2. 自检模式
if ($SelfTest) {
    try {
        $r = Test-ETWorkbench
        Write-Host ''
        Write-Host '==== ET 工作台自检 ====' -ForegroundColor Cyan
        foreach ($c in $r.Checks) {
            $mark = if ($c.Ok) { '[通过]' } else { '[失败]' }
            $clr = if ($c.Ok) { 'Green' } else { 'Red' }
            Write-Host ("  {0} {1,-22} {2}" -f $mark, $c.Name, $c.Detail) -ForegroundColor $clr
        }
        Write-Host ''
        Write-Host ("结论：{0}" -f $r.Message) -ForegroundColor $(if ($r.Ok) { 'Green' } else { 'Red' })
        Write-Host ''
        if ($r.Ok) { exit 0 } else { exit 1 }
    }
    catch {
        Write-Host ("自检异常：{0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 2
    }
}

# ================================================================ 3. 初始化数据根
try {
    $null = Initialize-ETDataRoot
    Write-Boot '本地数据根就绪'
}
catch {
    Write-Boot ("本地数据根初始化失败：{0}" -f $_.Exception.Message) 'Error'
    throw
}

# ================================================================ 4. 共享可达性（不阻断）
$shareState = Get-ETShareReachableState
if ($shareState.IsConfigured -and -not $shareState.IsReachable) {
    Write-Boot ("共享不可达，进入离线模式：{0}" -f $shareState.Error) 'Warn'
}

# ================================================================ 5. 加载 WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$UiDir = Join-Path $Script:Root 'UI'
$mainXamlPath = Join-Path $UiDir 'MainWindow.xaml'
if (-not (Test-Path -LiteralPath $mainXamlPath)) { throw "缺少界面文件：$mainXamlPath" }

$reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $mainXamlPath -Raw -Encoding UTF8))
$window = [Windows.Markup.XamlReader]::Load($reader)

# ================================================================ 6. 按名取控件
function Get-UiElement {
    param([Parameter(Mandatory)][string]$Name)
    $e = $window.FindName($Name)
    if ($null -eq $e) { Write-Boot ("界面元素缺失：{0}" -f $Name) 'Warn' }
    return $e
}

# ================================================================ 7. 控件引用
$ui = @{
    TxtTitle        = Get-UiElement 'TxtTitle'
    TxtStatus       = Get-UiElement 'TxtStatus'
    TxtIdentity     = Get-UiElement 'TxtIdentity'
    TxtShare        = Get-UiElement 'TxtShare'
    TxtVersion      = Get-UiElement 'TxtVersion'

    BtnIdentify     = Get-UiElement 'BtnIdentify'
    TxtIdentityOut  = Get-UiElement 'TxtIdentityOut'

    BtnRefreshSoft  = Get-UiElement 'BtnRefreshSoft'
    DgSoftware      = Get-UiElement 'DgSoftware'

    CmbApplication  = Get-UiElement 'CmbApplication'
    CmbVersion      = Get-UiElement 'CmbVersion'
    BtnPlan         = Get-UiElement 'BtnPlan'
    BtnDownload     = Get-UiElement 'BtnDownload'
    TxtDownloadOut  = Get-UiElement 'TxtDownloadOut'

    BtnHealthCheck  = Get-UiElement 'BtnHealthCheck'
    GridHealth      = Get-UiElement 'GridHealth'
    TxtHealthOut    = Get-UiElement 'TxtHealthOut'

    BtnMdLoad       = Get-UiElement 'BtnMdLoad'
    CmbMdKind       = Get-UiElement 'CmbMdKind'
    TxtMdPath       = Get-UiElement 'TxtMdPath'
    BtnMdValidate   = Get-UiElement 'BtnMdValidate'
    TxtMdOut        = Get-UiElement 'TxtMdOut'

    BtnCheckUpdate  = Get-UiElement 'BtnCheckUpdate'
    BtnSelfUpdate   = Get-UiElement 'BtnSelfUpdate'
    TxtUpdateOut    = Get-UiElement 'TxtUpdateOut'
    TxtAbout        = Get-UiElement 'TxtAbout'
}

# ================================================================ 8. 状态条
function Update-StatusBar {
    try {
        $ident = $null
        $snap = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'identity.json'
        if (Test-Path -LiteralPath $snap) {
            $ident = (Get-Content -LiteralPath $snap -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        if ($ui.TxtIdentity) {
            $ui.TxtIdentity.Text = if ($ident -and $ident.EquipmentId) {
                ("设备：{0}" -f $ident.EquipmentId)
            } else { '设备：未识别' }
        }

        $st = Get-ETShareReachableState
        if ($ui.TxtShare) {
            $ui.TxtShare.Text = if (-not $st.IsConfigured) { '共享：未配置' }
            elseif ($st.IsReachable) { '共享：可达' }
            else { '共享：不可达（离线）' }
        }

        $cur = Get-ETCurrentVersion
        if ($ui.TxtVersion) { $ui.TxtVersion.Text = ("版本：{0}" -f $(if ($cur.Version) { $cur.Version } else { '未知' })) }
    }
    catch { }
}

function Set-Output {
    param([Parameter(Mandatory)]$Control, [Parameter(Mandatory)][string]$Text)
    if ($Control) { $Control.Text = $Text }
}

# ================================================================ 9. 页签一：我是谁（E-02）
if ($ui.BtnIdentify) {
    $ui.BtnIdentify.Add_Click({
            try {
                $r = Invoke-ETIdentityChain
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("状态：{0}" -f $r.Status))
                foreach ($s in $r.Steps) {
                    [void]$sb.AppendLine(("  {0,-24} {1}" -f $s.Name, $s.Value))
                }
                if ($r.Status -ne 'Resolved') {
                    [void]$sb.AppendLine('')
                    [void]$sb.AppendLine('未完全识别。请检查主数据是否已发布，或本机业务网卡是否被网络策略过滤。')
                }
                Set-Output -Control $ui.TxtIdentityOut -Text $sb.ToString()
                Update-StatusBar
            }
            catch { Set-Output -Control $ui.TxtIdentityOut -Text ("识别失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 10. 页签二：软件状态（E-03）
function Update-SoftwareGrid {
    try {
        $sum = Get-ETSoftwareStateSummary
        $rows = @($sum.Rows | ForEach-Object {
                [pscustomobject]@{
                    ApplicationId = $_.ApplicationId
                    ApplicationName = $_.ApplicationName
                    ApprovedVersion = $_.ApprovedVersion
                    StateOrder      = $_.StateOrder
                    StateLabel      = $_.StateLabel
                    State           = $_.State
                }
            })
        if ($ui.DgSoftware) {
            $ui.DgSoftware.AutoGenerateColumns = $true
            $ui.DgSoftware.ItemsSource = $rows
        }
    }
    catch { Write-Boot ("读取软件状态失败：{0}" -f $_.Exception.Message) 'Warn' }
}

if ($ui.BtnRefreshSoft) { $ui.BtnRefreshSoft.Add_Click({ Update-SoftwareGrid }) }

# ================================================================ 11. 页签三：一键下载（E-04）
# 缓存一份「应用 -> 批准版本」目录，供两个下拉框使用（避免每次选择都重读快照）
$script:Catalog = @()

function Update-DownloadTargets {
    try {
        $sum = Get-ETSoftwareStateSummary
        $script:Catalog = @($sum.Rows)
        $apps = @($script:Catalog | Select-Object -ExpandProperty ApplicationId -Unique)
        if ($ui.CmbApplication) { $ui.CmbApplication.ItemsSource = $apps }
    }
    catch { Write-Boot ("读取软件目录失败：{0}" -f $_.Exception.Message) 'Warn' }
}

if ($ui.CmbApplication) {
    $ui.CmbApplication.Add_SelectionChanged({
            try {
                $app = $ui.CmbApplication.SelectedItem
                if (-not $app) { return }
                $vers = @($script:Catalog | Where-Object { "$($_.ApplicationId)" -eq "$app" } |
                        Select-Object -ExpandProperty ApprovedVersion -Unique | Where-Object { $_ })
                if ($ui.CmbVersion) {
                    $ui.CmbVersion.ItemsSource = $vers
                    if ($vers.Count -eq 1) { $ui.CmbVersion.SelectedIndex = 0 }
                }
            }
            catch { }
        })
}

if ($ui.BtnPlan) {
    $ui.BtnPlan.Add_Click({
            try {
                $app = $ui.CmbApplication.SelectedItem
                $ver = $ui.CmbVersion.SelectedItem
                if (-not $app -or -not $ver) { Set-Output -Control $ui.TxtDownloadOut -Text '请先选择应用与版本。'; return }

                # C-3：只传标识符
                $plan = Get-ETDownloadPlan -ApplicationId "$app" -Version "$ver"
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("应用：{0}   版本：{1}" -f $plan.ApplicationId, $plan.Version))
                [void]$sb.AppendLine(("文件数：{0}   总大小：{1} MB" -f $plan.FileCount, [math]::Round($plan.TotalBytes / 1MB, 2)))
                [void]$sb.AppendLine(("目标目录：{0}" -f $plan.TargetDir))
                [void]$sb.AppendLine(("源目录：{0}" -f $plan.SourceDir))
                [void]$sb.AppendLine(("磁盘余量：{0} GB（需 {1} GB）" -f $plan.Space.FreeGB, [math]::Round($plan.TotalBytes / 1GB, 2)))
                if ($plan.Errors) { foreach ($e in $plan.Errors) { [void]$sb.AppendLine(("  错误：{0}" -f $e)) } }
                Set-Output -Control $ui.TxtDownloadOut -Text $sb.ToString()
            }
            catch { Set-Output -Control $ui.TxtDownloadOut -Text ("生成计划失败：{0}" -f $_.Exception.Message) }
        })
}

if ($ui.BtnDownload) {
    $ui.BtnDownload.Add_Click({
            try {
                $app = $ui.CmbApplication.SelectedItem
                $ver = $ui.CmbVersion.SelectedItem
                if (-not $app -or -not $ver) { Set-Output -Control $ui.TxtDownloadOut -Text '请先选择应用与版本。'; return }

                Set-Output -Control $ui.TxtDownloadOut -Text '下载中……请勿关闭窗口。'

                # C-3：只传标识符
                $r = Invoke-ETDownload -ApplicationId "$app" -Version "$ver"
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("结果：{0}（{1}）" -f $(if ($r.Ok) { '成功' } else { '失败' }), $r.Status))
                if ($r.Ok) {
                    [void]$sb.AppendLine(("文件数：{0}　已复制：{1}　已校验：{2}" -f $r.FileCount, $r.Copied, $r.Verified))
                    [void]$sb.AppendLine(("目标目录：{0}" -f $r.TargetDir))
                    [void]$sb.AppendLine(("耗时：{0} 秒" -f [math]::Round($r.DurationSeconds, 1)))
                }
                if ($r.Errors) { foreach ($e in $r.Errors) { [void]$sb.AppendLine(("  错误：{0}" -f $e)) } }
                [void]$sb.AppendLine('')
                [void]$sb.AppendLine('注意：下载完成 = 文件已就位，不代表已安装/已生效。')
                Set-Output -Control $ui.TxtDownloadOut -Text $sb.ToString()
                Update-StatusBar
                Update-SoftwareGrid
            }
            catch { Set-Output -Control $ui.TxtDownloadOut -Text ("下载失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 12. 页签四：健康检测（E-05）
function Update-HealthGrid {
    try {
        $rows = @(Get-ETHealthMetrics)
        if ($rows.Count -eq 0) { $rows = @(Get-ETHealthMetricCatalog) }
        if ($ui.GridHealth) {
            $ui.GridHealth.AutoGenerateColumns = $true
            $ui.GridHealth.ItemsSource = $rows
        }
    }
    catch { }
}

if ($ui.BtnHealthCheck) {
    $ui.BtnHealthCheck.Add_Click({
            try {
                Set-Output -Control $ui.TxtHealthOut -Text '采集中……'
                $r = Invoke-ETHealthCheck

                # 采样结果落盘 -> 事件落本地 Outbox -> 尝试补传（方案 §6.6 顺序）
                try { Save-ETHealthSnapshot -Result $r } catch { }
                try {
                    $items = New-Object System.Collections.ArrayList
                    foreach ($a in $r.Alarms) {
                        [void]$items.Add((New-ETOutboxItem -EventType 'Alarm' -EquipmentId (Get-ETOutboxEquipmentId) -Payload $a))
                    }
                    if ($items.Count -gt 0) { $null = Add-ETOutboxBatch -Items $items }
                }
                catch { Write-Boot ("事件落盘失败：{0}" -f $_.Exception.Message) 'Warn' }
                try { $null = Publish-ETOutbox } catch { }

                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("采样 {0} 项，告警 {1} 条，未知 {2} 项" -f $r.Samples.Count, $r.Alarms.Count, $r.Unknowns.Count))
                foreach ($a in $r.Alarms) { [void]$sb.AppendLine(("  [{0}] {1} {2}{3}（当前 {4}）" -f $a.Severity, $a.Name, $a.ComparatorOp, $a.Threshold, $a.Value)) }
                foreach ($e in $r.Events) { [void]$sb.AppendLine(("  · {0}：{1}" -f $e.Name, $e.Detail)) }

                $sum = Get-ETOutboxSummary
                [void]$sb.AppendLine(("待上报事件：{0}（最早 {1} 小时前）" -f $sum.Pending, $sum.OldestPendingHours))
                Set-Output -Control $ui.TxtHealthOut -Text $sb.ToString()
                Update-HealthGrid
            }
            catch { Set-Output -Control $ui.TxtHealthOut -Text ("健康检测失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 13. 页签五：主数据（E-01）
if ($ui.CmbMdKind) {
    $ui.CmbMdKind.ItemsSource = @('equipment', 'devices', 'projects', 'applications', 'approved-versions', 'mappings')
}

if ($ui.BtnMdLoad) {
    $ui.BtnMdLoad.Add_Click({
            try {
                $r = Import-ETMasterDataSnapshot
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("快照状态：{0}" -f $r.Status))
                [void]$sb.AppendLine(("时间：{0}" -f $r.TakenAt))
                foreach ($k in $r.Items.Keys) { [void]$sb.AppendLine(("  {0,-22} {1} 条" -f $k, $r.Items[$k])) }
                if ($r.Errors) { foreach ($e in $r.Errors) { [void]$sb.AppendLine(("  [错误] {0}" -f $e)) } }
                if ($r.Status -eq 'Stale') { [void]$sb.AppendLine('共享不可达，已保留原快照（离线可用）。') }
                Set-Output -Control $ui.TxtMdOut -Text $sb.ToString()
                Set-Output -Control $ui.TxtMdPath -Text $r.SnapshotDir
            }
            catch { Set-Output -Control $ui.TxtMdOut -Text ("加载快照失败：{0}" -f $_.Exception.Message) }
        })
}

if ($ui.BtnMdValidate) {
    $ui.BtnMdValidate.Add_Click({
            try {
                $kind = $ui.CmbMdKind.SelectedItem
                $path = $ui.TxtMdPath.Text
                if (-not $kind) { Set-Output -Control $ui.TxtMdOut -Text '请选择主数据类型。'; return }
                if ([string]::IsNullOrWhiteSpace($path)) { Set-Output -Control $ui.TxtMdOut -Text '请填入待校验 JSON 文件路径。'; return }

                $r = Test-ETMasterDataDraft -FileName ("{0}.json" -f $kind) -LiteralPath $path
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("结果：{0}（{1} 条记录）" -f $(if ($r.Ok) { '通过' } else { '未通过' }), $r.RowCount))
                if ($r.Errors) { foreach ($e in $r.Errors) { [void]$sb.AppendLine(("  [错误] {0}" -f $e)) } }
                if ($r.Warnings) { foreach ($w in $r.Warnings) { [void]$sb.AppendLine(("  [提醒] {0}" -f $w)) } }
                Set-Output -Control $ui.TxtMdOut -Text $sb.ToString()
            }
            catch { Set-Output -Control $ui.TxtMdOut -Text ("校验失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 14. 页签六：关于与自更新（E-06）
if ($ui.BtnCheckUpdate) {
    $ui.BtnCheckUpdate.Add_Click({
            try {
                $r = Test-ETUpdateAvailable
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("当前版本：{0}" -f $(if ($r.CurrentVersion) { $r.CurrentVersion } else { '未知' })))
                [void]$sb.AppendLine(("可用版本：{0}" -f $(if ($r.AvailableVersion) { $r.AvailableVersion } else { '—' })))
                [void]$sb.AppendLine(("结论：{0}" -f $r.Reason))
                Set-Output -Control $ui.TxtUpdateOut -Text $sb.ToString()
            }
            catch { Set-Output -Control $ui.TxtUpdateOut -Text ("检查失败：{0}" -f $_.Exception.Message) }
        })
}

if ($ui.BtnSelfUpdate) {
    $ui.BtnSelfUpdate.Add_Click({
            try {
                Set-Output -Control $ui.TxtUpdateOut -Text '更新中……'
                $r = Invoke-ETSelfUpdate
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("状态：{0}" -f $r.Status))
                $fromText = if ($r.From) { $r.From } else { '—' }
                $toText = if ($r.To) { $r.To } else { '—' }
                [void]$sb.AppendLine(("版本：{0} → {1}" -f $fromText, $toText))
                if ($r.RolledBack) { [void]$sb.AppendLine('已回滚到原版本。') }
                if ($r.Errors) { foreach ($e in $r.Errors) { [void]$sb.AppendLine(("  {0}" -f $e)) } }
                [void]$sb.AppendLine('更新后请重启工作台。')
                Set-Output -Control $ui.TxtUpdateOut -Text $sb.ToString()
                Update-StatusBar
            }
            catch { Set-Output -Control $ui.TxtUpdateOut -Text ("更新失败：{0}" -f $_.Exception.Message) }
        })
}

if ($ui.TxtAbout) {
    $core = Get-ETCoreInfo
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('ET 工作台 —— 现场终端数字化运维（ET 端 PowerShell）')
    [void]$sb.AppendLine('')
    foreach ($p in (Get-ETObjectPropertyNames -InputObject $core)) { [void]$sb.AppendLine(("{0,-22} {1}" -f $p, $core.$p)) }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('安全边界：不开放端口、不结束/重启业务软件、不自动覆盖运行中程序、')
    [void]$sb.AppendLine('不自动执行系统修复、不只写自身 EquipmentId 的 Upload 目录。')
    $ui.TxtAbout.Text = $sb.ToString()
}

# ================================================================ 15. 启动时刷新
$window.Add_Loaded({
        try {
            Update-StatusBar
            Update-DownloadTargets
            Update-SoftwareGrid
            Update-HealthGrid
        }
        catch { Write-Boot ("启动刷新失败：{0}" -f $_.Exception.Message) 'Warn' }
    })

# ================================================================ 16. 显示
Write-Boot '窗口已就绪'
$null = $window.ShowDialog()
