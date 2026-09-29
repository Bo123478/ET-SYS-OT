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

# ================================================================ 2.5 桌面模式前置：Win32 辅助 + 弹窗 owner
# 目标（档位 3）：工作台像桌面 —— 铺满工作区、不进任务栏、不参与 Alt+Tab、永远在最底层。
# 全部只是【改变本窗口自身的位置与 Z 序】，不结束任何进程、不改注册表、不置顶
# （红线 F-4 禁止抢焦点/置顶，所以业务软件永远盖在本窗口之上）。

$script:EtWin32Ready = $false
try {
    if (-not ('ETWindowNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ETWindowNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
    private static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex) : GetWindowLong32(hWnd, nIndex);
    }
    public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
        return IntPtr.Size == 8 ? SetWindowLongPtr64(hWnd, nIndex, dwNewLong)
                                : SetWindowLong32(hWnd, nIndex, dwNewLong);
    }

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOACTIVATE = 0x0010;
}
'@ -ErrorAction Stop
    }
    $script:EtWin32Ready = $true
}
catch {
    Write-Boot ("Win32 辅助加载失败，窗口沉底将降级为不生效：{0}" -f $_.Exception.Message) 'Warn'
}

# 会话 0（无交互桌面）没有窗口可言。直接退出，别在无桌面环境里空转到超时。
if (-not [System.Environment]::UserInteractive) {
    Write-Boot '当前为会话 0（无交互桌面），无法显示界面，已退出。'
    exit 0
}

# 无边框 + 不在任务栏 + 在最底层 ⇒ 普通 MessageBox 会被业务软件盖住，用户永远看不到。
# 用一个 1px 的不可见 owner 窗口把弹窗拉进 Z 序，保证任何报错都可见。
Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
$script:DialogOwner = $null
try {
    $script:DialogOwner = New-Object System.Windows.Window
    $script:DialogOwner.WindowStyle = 'None'
    $script:DialogOwner.ShowInTaskbar = $false
    $script:DialogOwner.Width = 1
    $script:DialogOwner.Height = 1
    $script:DialogOwner.Left = -4000
    $script:DialogOwner.Top = -4000
    $script:DialogOwner.Show()
    $script:DialogOwner.Hide()
}
catch { $script:DialogOwner = $null }

function Show-ETError {
    <# .SYNOPSIS 报错弹窗；有 owner 时带上 owner，保证不被业务软件盖住。 #>
    param([string]$Text, [string]$Caption = 'ET 工作台')
    try {
        if ($script:DialogOwner) {
            [void][System.Windows.MessageBox]::Show($script:DialogOwner, $Text, $Caption, 'OK', 'Warning')
        }
        else { Write-Boot $Text 'Error' }
    }
    catch { Write-Boot $Text 'Error' }
}

# 顶层兜底：任何未捕获的终止性错误都要让【人】看见，而不是静默退出。
trap {
    Show-ETError ("工作台启动失败：{0}" -f $_.Exception.Message)
    exit 1
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
    MainTabs        = Get-UiElement 'MainTabs'
    TxtIdentity     = Get-UiElement 'TxtIdentity'
    TxtShare        = Get-UiElement 'TxtShare'
    TxtVersion      = Get-UiElement 'TxtVersion'

    BtnIdentify     = Get-UiElement 'BtnIdentify'
    TxtIdentityOut  = Get-UiElement 'TxtIdentityOut'

    BtnRefreshSoft  = Get-UiElement 'BtnRefreshSoft'
    SoftCardPanel   = Get-UiElement 'SoftCardPanel'

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

    # ---- 三区桌面布局（档位 3）：顶部信息条 ----
    TxtClock        = Get-UiElement 'TxtClock'
    TxtStatusFull   = Get-UiElement 'TxtStatusFull'
    TxtStatusTop    = Get-UiElement 'TxtStatusTop'

    # ---- 桌面模式 + 三态状态灯 ----
    # 铭牌已恢复为左侧垂直居中的 316x248 竖版卡（独立进程 Start-ETPlate.ps1），
    # 不再与顶栏对齐，因此顶栏的 PlateSlot / HdrStrip / TxtPlate* 槽位已整体移除；
    # 主窗口内的唯一状态色指示改为底部状态条的 StatusBarDot。
    StatusBarDot    = Get-UiElement 'StatusBarDot'
    BtnCloseWindow  = Get-UiElement 'BtnCloseWindow'

    # ---- 三区桌面布局：主数据 / 关于 底部抽屉 ----
    BtnFullScreen   = Get-UiElement 'BtnFullScreen'
    BtnMdDrawer     = Get-UiElement 'BtnMdDrawer'
    BtnAboutDrawer  = Get-UiElement 'BtnAboutDrawer'
    MdDrawer        = Get-UiElement 'MdDrawer'
    AboutDrawer     = Get-UiElement 'AboutDrawer'
    BtnMdClose      = Get-UiElement 'BtnMdClose'
    BtnAboutClose   = Get-UiElement 'BtnAboutClose'
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

        # 顶部状态灯旁的文字 + 底部通栏摘要：同一句话，两处显示，避免两处口径打架。
        # 只做「已有数据的中文摘要」，不在这里判定红黄绿 —— 颜色归铭牌/§15.1。
        $equipText = if ($ident -and $ident.EquipmentId) { "$($ident.EquipmentId)" } else { '未识别' }
        $shareText = if (-not $st.IsConfigured) { '共享未配置' } elseif ($st.IsReachable) { '共享可达' } else { '离线运行' }

        $alarmText = ''
        try {
            $snapH = Get-ETHealthSnapshot
            if ($snapH) {
                $n = @($snapH.Alarms).Count
                $u = @($snapH.Unknowns).Count
                if ($n -gt 0) { $alarmText = ("告警 {0} 条" -f $n) }
                elseif ($u -gt 0) { $alarmText = ("未知 {0} 条" -f $u) }
                else { $alarmText = '健康正常' }
            }
        }
        catch { }

        $outboxText = ''
        try {
            $os = Get-ETOutboxSummary
            if ($os -and $os.Pending -gt 0) { $outboxText = ("待上报 {0} 条" -f $os.Pending) }
        }
        catch { }

        $parts = @($equipText, $shareText)
        if ($alarmText) { $parts += $alarmText }
        if ($outboxText) { $parts += $outboxText }
        $summary = ($parts -join ' · ')

        if ($ui.TxtStatusTop) { $ui.TxtStatusTop.Text = $summary }
        if ($ui.TxtStatusFull) {
            # 注意：Get-ETPath 的 -Name 是 Mandatory，且没有「DataRoot」这个 Category，
            # 这里必须用 Get-ETDataRoot —— 否则在无控制台的 GUI 里会弹参数提示并卡死。
            $ui.TxtStatusFull.Text = ("{0} · 数据根 {1}" -f $summary, (Get-ETDataRoot))
        }
    }
    catch { }
}

function Set-Output {
    param([Parameter(Mandatory)]$Control, [Parameter(Mandatory)][string]$Text)
    if ($Control) { $Control.Text = $Text }
}

# ================================================================ 8.1 字段取值（三编号共用）
# 铭牌（Start-ETPlate.ps1）才是三编号的显示方；这里保留同一个取值助手，
# 供底部状态条 / 识别结果复用，避免两处写两套字段兼容逻辑。

function Get-ETFirstValue {
    <# .SYNOPSIS 按候选字段名取第一个非空值；取不到返回空串（绝不返回示例值）。 #>
    param([AllowNull()]$InputObject, [string[]]$Names)
    if ($null -eq $InputObject) { return '' }
    foreach ($n in $Names) {
        try {
            if (Test-ETObjectHasProperty -InputObject $InputObject -Name $n) {
                $v = "$($InputObject.$n)".Trim()
                if ($v) { return $v }
            }
        }
        catch { }
    }
    return ''
}

function Resolve-ETPlateInfo {
    <#
      .SYNOPSIS 由本机业务 IP 反查设备 / ET / MPC 三个编号。
      .DESCRIPTION
        来源 1：主数据 mappings.json 的 ByIpAddress[IP]（值可能是纯字符串或对象）。
        来源 2：equipment.json 用 EquipmentId 补全缺失项。
        全部取不到就返回空串 —— 界面显示「—」，**不显示示例值**，避免现场误读。
    #>
    param([string]$Ip)

    $out = @{ EquipmentId = ''; EtCode = ''; MpcCode = '' }
    $equipId = ''

    if ($Ip) {
        try {
            foreach ($m in @(Get-ETMasterDataSnapshot -Kind 'mappings' | Where-Object { $null -ne $_ })) {
                if (-not (Test-ETObjectHasProperty -InputObject $m -Name 'ByIpAddress')) { continue }
                $byIp = $m.ByIpAddress
                if ($null -eq $byIp) { continue }
                if (-not (Test-ETObjectHasProperty -InputObject $byIp -Name $Ip)) { continue }
                $hit = $byIp.$Ip
                if ($null -eq $hit) { continue }
                if ($hit -is [string] -or $hit -is [int]) {
                    $equipId = "$hit".Trim()
                }
                else {
                    $out.EquipmentId = Get-ETFirstValue -InputObject $hit -Names @('EquipmentId', 'equipmentId', 'DeviceNo', 'DeviceId', 'Code')
                    $out.EtCode = Get-ETFirstValue -InputObject $hit -Names @('EtCode', 'ET', 'EtId', 'EtNo')
                    $out.MpcCode = Get-ETFirstValue -InputObject $hit -Names @('MpcCode', 'MPC', 'Mpc', 'MpcNo')
                    if ($out.EquipmentId) { $equipId = $out.EquipmentId }
                }
                break
            }
        }
        catch { }
    }

    if ($equipId) {
        if (-not $out.EquipmentId) { $out.EquipmentId = $equipId }
        try {
            foreach ($e in @(Get-ETMasterDataSnapshot -Kind 'equipment' | Where-Object { $null -ne $_ })) {
                if (-not (Test-ETObjectHasProperty -InputObject $e -Name 'EquipmentId')) { continue }
                if ("$($e.EquipmentId)".Trim() -ne $equipId) { continue }
                if (-not $out.EtCode) { $out.EtCode = Get-ETFirstValue -InputObject $e -Names @('EtCode', 'ET', 'EtId', 'EtNo') }
                if (-not $out.MpcCode) { $out.MpcCode = Get-ETFirstValue -InputObject $e -Names @('MpcCode', 'MPC', 'Mpc', 'MpcNo') }
                break
            }
        }
        catch { }
    }

    return $out
}

function Update-Clock {
    <# .SYNOPSIS 顶栏时钟（HH:mm）。秒级刷新交给 DispatcherTimer，见 §15。 #>
    if ($ui.TxtClock) { $ui.TxtClock.Text = (Get-Date -Format 'HH:mm') }
}

function Update-StatusBadgeColor {
    <#
      .SYNOPSIS 顶部状态灯颜色。
      .DESCRIPTION
        直接复用铭牌的判定结论，不在这里重写规则 —— 规则只有一处，
        否则「铭牌红、窗口绿」这种自相矛盾迟早出现。
        读取顺序：铭牌三态快照 > 健康告警计数 > 未知（灰）。
    #>
    param([string]$State)
    $color = switch ($State) {
        'Alarm' { '#FFE5533D' }
        'Warn' { '#FFF2C94C' }
        'Normal' { '#FF2FBF71' }
        default { '#FF8A94A6' }
    }
    try {
        if ($ui.StatusBarDot) { $ui.StatusBarDot.Fill = ConvertTo-ETBrush $color }
    }
    catch { }
}

function Set-Drawer {
    <# .SYNOPSIS 抽屉互斥显示（主数据 / 关于 同时只开一个）。 #>
    param([ValidateSet('None', 'Md', 'About')][string]$Which)
    try {
        if ($ui.MdDrawer) { $ui.MdDrawer.Visibility = $(if ($Which -eq 'Md') { 'Visible' } else { 'Collapsed' }) }
        if ($ui.AboutDrawer) { $ui.AboutDrawer.Visibility = $(if ($Which -eq 'About') { 'Visible' } else { 'Collapsed' }) }
    }
    catch { }
}

function Enter-ETDesktopMode {
    <#
      .SYNOPSIS 把窗口铺满【工作区】（不是整个屏幕）。
      .DESCRIPTION
        工作区 = 屏幕减去任务栏后剩下的区域 ⇒ 铺满工作区既做到「像桌面」，
        又不会盖住任务栏（不违反方案 §3.1「不移除任务栏与开始菜单」）。
        坐标用 SystemParameters.WorkArea（DIP 单位，与 Window.Left/Width 同单位），
        与铭牌 Start-ETPlate.ps1 的定位算法保持同一口径。
        WindowStyle=None 时窗口矩形就是客户区矩形，SetWindowPos 无需再做非客户区补偿。
    #>
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.WindowState = [System.Windows.WindowState]::Normal
        $window.Left = $wa.Left
        $window.Top = $wa.Top
        $window.Width = $wa.Width
        $window.Height = $wa.Height
    }
    catch { }
}

function Exit-ETDesktopMode {
    <# .SYNOPSIS 还原为居中的普通尺寸窗口（仍无边框、仍沉底）。 #>
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $w = [Math]::Min(1100, [Math]::Max(900, $wa.Width - 80))
        $h = [Math]::Min(720, [Math]::Max(600, $wa.Height - 80))
        $window.WindowState = [System.Windows.WindowState]::Normal
        $window.Width = $w
        $window.Height = $h
        $window.Left = $wa.Left + ($wa.Width - $w) / 2
        $window.Top = $wa.Top + ($wa.Height - $h) / 2
    }
    catch { }
}

function Toggle-FullScreen {
    <# .SYNOPSIS 工作区全屏 / 还原。只改自身窗口位置与大小，不抢焦点、不置顶（红线 F-4）。 #>
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $isFull = ([Math]::Abs($window.Width - $wa.Width) -lt 2) -and ([Math]::Abs($window.Height - $wa.Height) -lt 2)
        if ($isFull) { Exit-ETDesktopMode } else { Enter-ETDesktopMode }
    }
    catch { }
}

function Set-ETWindowBottom {
    <#
      .SYNOPSIS 把窗口沉到 Z 序最底层。
      .DESCRIPTION
        注意这【不是】Topmost（红线 F-4 禁止置顶），反而是它的反面：
        业务软件永远盖在工作台之上；要看工作台先最小化业务软件。
        · SWP_NOACTIVATE 保证沉底动作本身不抢焦点。
        · 用 HWND_BOTTOM 而非降低 WindowState：全屏窗口无法靠自身降级沉底。
        · 若被最小化过，先还原再沉底，否则沉的是个最小化窗口，白做。
        · 加重入锁：Add_Activated / Add_Deactivated 可能因沉底而互相触发。
    #>
    if (-not $script:EtWin32Ready) { return }
    if ($script:Sinking) { return }
    $script:Sinking = $true
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        if ($h -eq [IntPtr]::Zero) { return }
        if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
            $window.WindowState = [System.Windows.WindowState]::Normal
        }
        [void][ETWindowNative]::SetWindowPos($h, [ETWindowNative]::HWND_BOTTOM, 0, 0, 0, 0,
            ([ETWindowNative]::SWP_NOMOVE -bor [ETWindowNative]::SWP_NOSIZE -bor [ETWindowNative]::SWP_NOACTIVATE))
    }
    catch { }
    finally { $script:Sinking = $false }
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
function ConvertTo-ETBrush {
    <# .SYNOPSIS 字符串颜色 -> WPF Brush。失败返回 $null。 #>
    param([string]$Color)
    try {
        $conv = New-Object System.Windows.Media.BrushConverter
        return $conv.ConvertFromString($Color)
    }
    catch { return $null }
}

function Get-ETStateColor {
    <# .SYNOPSIS 七态 -> 徽章颜色（StateOrder 0..7）。 #>
    param([AllowNull()]$StateOrder)
    switch ([int]$StateOrder) {
        0 { return '#FFE5533D' }   # 共享无包 —— 红
        1 { return '#FF8A94A6' }   # 共享有包 —— 灰
        2 { return '#FFF08A3C' }   # 已下载   —— 橙
        3 { return '#FF2F6FB5' }   # 已部署   —— 蓝
        4 { return '#FF12A5B8' }   # 有可执行 —— 青
        5 { return '#FF2FA84F' }   # 运行中   —— 绿
        6 { return '#FF7A4DB8' }   # 已配置   —— 紫
        7 { return '#FF1E8A3C' }   # 已生效   —— 深绿
        default { return '#FF8A94A6' }
    }
}

function New-SoftwareCard {
    <#
      .SYNOPSIS  为单个应用生成一张卡片（图标 + 状态徽章 / 名称 / 版本 / 编号 / 描述 / 详情+更新）。
      .PARAMETER Row            Get-ETSoftwareStateSummary 的单行
      .PARAMETER Description   应用描述（来自主数据 applications.Note）
      .NOTES
        - 按钮用 Tag 携带 ApplicationId（标识符，约束 C-3），handler 从 $sender.Tag 读取，
          避免 PowerShell 闭包捕获循环变量导致所有按钮指向最后一个应用。
    #>
    param($Row, [AllowNull()][string]$Description)

    $appId = "$($Row.ApplicationId)"
    $appName = "$($Row.ApplicationName)"
    if ([string]::IsNullOrWhiteSpace($appName)) { $appName = if ($appId) { $appId } else { '未知应用' } }
    $ver = if ($Row.ApprovedVersion) { "$($Row.ApprovedVersion)" } else { '—' }
    $stateLabel = if ($Row.StateLabel) { "$($Row.StateLabel)" } else { '未知' }
    $stateColor = Get-ETStateColor -StateOrder $Row.StateOrder
    $initial = $appName.Substring(0, 1).ToUpper()
    $desc = if ([string]::IsNullOrWhiteSpace($Description)) { '暂无描述' } else { $Description }

    # ---- 卡片容器（圆角白卡 + 阴影） ----
    $card = New-Object System.Windows.Controls.Border
    $card.Width = 320
    $card.Margin = New-Object System.Windows.Thickness 8
    $card.Padding = New-Object System.Windows.Thickness 16
    $card.CornerRadius = New-Object System.Windows.CornerRadius 10
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.Background = ConvertTo-ETBrush '#FFFFFFFF'
    $card.BorderBrush = ConvertTo-ETBrush '#FFD9E1EA'
    $card.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect

    $sp = New-Object System.Windows.Controls.StackPanel

    # ---- 顶部：图标 + 状态徽章 ----
    $top = New-Object System.Windows.Controls.Grid
    $col0 = New-Object System.Windows.Controls.ColumnDefinition
    $col0.Width = [System.Windows.GridLength]::Auto
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = New-Object System.Windows.GridLength -ArgumentList 1.0, ([System.Windows.GridUnitType]::Star)
    $top.ColumnDefinitions.Add($col0) | Out-Null
    $top.ColumnDefinitions.Add($col1) | Out-Null

    $iconBorder = New-Object System.Windows.Controls.Border
    $iconBorder.Width = 40
    $iconBorder.Height = 40
    $iconBorder.CornerRadius = New-Object System.Windows.CornerRadius 20
    $iconBorder.Background = ConvertTo-ETBrush '#FF2F6FB5'
    $iconText = New-Object System.Windows.Controls.TextBlock
    $iconText.Text = $initial
    $iconText.Foreground = ConvertTo-ETBrush '#FFFFFFFF'
    $iconText.FontSize = 18
    $iconText.FontWeight = 'Bold'
    $iconText.HorizontalAlignment = 'Center'
    $iconText.VerticalAlignment = 'Center'
    $iconBorder.Child = $iconText
    [System.Windows.Controls.Grid]::SetColumn($iconBorder, 0)
    [void]$top.Children.Add($iconBorder)

    $badge = New-Object System.Windows.Controls.Border
    $badge.CornerRadius = New-Object System.Windows.CornerRadius 11
    $badge.Padding = New-Object System.Windows.Thickness 10, 3, 10, 3
    $badge.Background = ConvertTo-ETBrush $stateColor
    $badge.HorizontalAlignment = 'Right'
    $badge.VerticalAlignment = 'Top'
    $badgeText = New-Object System.Windows.Controls.TextBlock
    $badgeText.Text = $stateLabel
    $badgeText.Foreground = ConvertTo-ETBrush '#FFFFFFFF'
    $badgeText.FontSize = 11
    $badgeText.FontWeight = 'SemiBold'
    $badge.Child = $badgeText
    [System.Windows.Controls.Grid]::SetColumn($badge, 1)
    [void]$top.Children.Add($badge)

    [void]$sp.Children.Add($top)

    # ---- 名称 ----
    $tName = New-Object System.Windows.Controls.TextBlock
    $tName.Text = $appName
    $tName.FontSize = 16
    $tName.FontWeight = 'Bold'
    $tName.Foreground = ConvertTo-ETBrush '#FF1B2B3A'
    $tName.Margin = New-Object System.Windows.Thickness 0, 12, 0, 0
    $tName.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($tName)

    # ---- 版本 / 编号 / 描述 ----
    $tVer = New-Object System.Windows.Controls.TextBlock
    $tVer.Text = "版本：$ver"
    $tVer.FontSize = 12
    $tVer.Foreground = ConvertTo-ETBrush '#FF6B7787'
    $tVer.Margin = New-Object System.Windows.Thickness 0, 8, 0, 0
    [void]$sp.Children.Add($tVer)

    $tId = New-Object System.Windows.Controls.TextBlock
    $tId.Text = "应用编号：$appId"
    $tId.FontSize = 12
    $tId.Foreground = ConvertTo-ETBrush '#FF6B7787'
    $tId.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    [void]$sp.Children.Add($tId)

    $tDesc = New-Object System.Windows.Controls.TextBlock
    $tDesc.Text = "应用描述：$desc"
    $tDesc.FontSize = 12
    $tDesc.Foreground = ConvertTo-ETBrush '#FF6B7787'
    $tDesc.Margin = New-Object System.Windows.Thickness 0, 4, 0, 0
    $tDesc.TextWrapping = 'Wrap'
    $tDesc.MaxHeight = 34
    [void]$sp.Children.Add($tDesc)

    # ---- 底部按钮：详情 / 更新 ----
    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'
    $btnRow.Margin = New-Object System.Windows.Thickness 0, 14, 0, 0

    $btnDetail = New-Object System.Windows.Controls.Button
    $btnDetail.Content = '详情'
    $btnDetail.Width = 80
    $btnDetail.Height = 30
    $btnDetail.MinWidth = 0
    $btnDetail.Padding = New-Object System.Windows.Thickness 0
    $btnDetail.Margin = New-Object System.Windows.Thickness 0, 0, 10, 0
    $btnDetail.Background = ConvertTo-ETBrush '#FFFFFFFF'
    $btnDetail.Foreground = ConvertTo-ETBrush '#FF2F6FB5'
    $btnDetail.BorderBrush = ConvertTo-ETBrush '#FF2F6FB5'
    $btnDetail.BorderThickness = New-Object System.Windows.Thickness 1
    $btnDetail.Cursor = 'Hand'
    $btnDetail.Tag = $appId
    $btnDetail.Add_Click({
            param($sender, $e)
            $aid = $sender.Tag
            try {
                $sum = Get-ETSoftwareStateSummary
                $row = @($sum.Rows | Where-Object { "$($_.ApplicationId)" -eq "$aid" } | Select-Object -First 1)
                if ($row) {
                    $sb = New-Object System.Text.StringBuilder
                    [void]$sb.AppendLine("应用名称：$($row.ApplicationName)")
                    [void]$sb.AppendLine("应用编号：$($row.ApplicationId)")
                    [void]$sb.AppendLine("应装版本：$(if ($row.ApprovedVersion) { $row.ApprovedVersion } else { '—' })")
                    [void]$sb.AppendLine("本机版本：$(if ($row.LocalVersion) { $row.LocalVersion } else { '未检测到' })")
                    [void]$sb.AppendLine("当前状态：$(if ($row.StateLabel) { $row.StateLabel } else { '未知' })")
                    [void]$sb.AppendLine('')
                    [void]$sb.AppendLine('证据：')
                    if ($row.Evidence) {
                        foreach ($k in $row.Evidence.Keys) {
                            $v = $row.Evidence[$k]
                            if ($v -is [array]) { $v = ($v -join ', ') }
                            [void]$sb.AppendLine("  ${k} = $v")
                        }
                    }
                    [void][System.Windows.MessageBox]::Show($sb.ToString(), $row.ApplicationName, 'OK', 'Information')
                }
            }
            catch { }
        })

    $btnUpdate = New-Object System.Windows.Controls.Button
    $btnUpdate.Content = '更新'
    $btnUpdate.Width = 80
    $btnUpdate.Height = 30
    $btnUpdate.MinWidth = 0
    $btnUpdate.Padding = New-Object System.Windows.Thickness 0
    $btnUpdate.Margin = New-Object System.Windows.Thickness 0
    $btnUpdate.Background = ConvertTo-ETBrush '#FF2F6FB5'
    $btnUpdate.Foreground = ConvertTo-ETBrush '#FFFFFFFF'
    $btnUpdate.BorderThickness = New-Object System.Windows.Thickness 0
    $btnUpdate.Cursor = 'Hand'
    $btnUpdate.Tag = $appId
    $btnUpdate.Add_Click({
            param($sender, $e)
            $aid = $sender.Tag
            try {
                Update-DownloadTargets
                # 「一键下载」在三区布局里是常驻面板（左下角），抽屉若开着先收起，
                # 否则会把下拉框盖住 —— 点了没反应，现场会以为按钮坏了。
                Set-Drawer -Which 'None'
                if ($ui.CmbApplication) { $ui.CmbApplication.SelectedItem = $aid }
            }
            catch { }
        })

    [void]$btnRow.Children.Add($btnDetail)
    [void]$btnRow.Children.Add($btnUpdate)
    [void]$sp.Children.Add($btnRow)

    $card.Child = $sp
    return $card
}

function Update-SoftwareGrid {
    try {
        $sum = Get-ETSoftwareStateSummary

        # 应用描述映射（主数据 applications.Note）
        $descMap = @{}
        try {
            foreach ($a in @(Get-ETMasterDataSnapshot -Kind 'applications')) {
                if ($null -eq $a) { continue }
                try {
                    $descMap["$($a.ApplicationId)"] = "$($a.Note)"
                }
                catch { }
            }
        }
        catch { }

        $panel = $ui.SoftCardPanel
        if (-not $panel) { return }
        $panel.Children.Clear()

        $cards = @($sum.Rows | Where-Object { $null -ne $_ })
        if ($cards.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = '暂无应用主数据。请先在「主数据」页签拉取最新快照。'
            $empty.Foreground = ConvertTo-ETBrush '#FF6B7787'
            $empty.Margin = New-Object System.Windows.Thickness 8
            [void]$panel.Children.Add($empty)
            return
        }

        foreach ($r in $cards) {
            $desc = if ($descMap.ContainsKey("$($r.ApplicationId)")) { $descMap["$($r.ApplicationId)"] } else { '' }
            $card = New-SoftwareCard -Row $r -Description $desc
            if ($card) { [void]$panel.Children.Add($card) }
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

# ================================================================ 15. 三区桌面布局：交互
# 抽屉：点按钮开、点「收起」或按 Esc 关；两个抽屉互斥。
if ($ui.BtnMdDrawer) { $ui.BtnMdDrawer.Add_Click({ Set-Drawer -Which $(if ($ui.MdDrawer -and $ui.MdDrawer.Visibility -eq 'Visible') { 'None' } else { 'Md' }) }) }
if ($ui.BtnAboutDrawer) { $ui.BtnAboutDrawer.Add_Click({ Set-Drawer -Which $(if ($ui.AboutDrawer -and $ui.AboutDrawer.Visibility -eq 'Visible') { 'None' } else { 'About' }) }) }
if ($ui.BtnMdClose) { $ui.BtnMdClose.Add_Click({ Set-Drawer -Which 'None' }) }
if ($ui.BtnAboutClose) { $ui.BtnAboutClose.Add_Click({ Set-Drawer -Which 'None' }) }
if ($ui.BtnFullScreen) { $ui.BtnFullScreen.Add_Click({ Toggle-FullScreen }) }
# 无边框 + 不在任务栏 ⇒ 必须有一个明确的关闭出口。关闭只关窗口，不动任何后台任务。
if ($ui.BtnCloseWindow) { $ui.BtnCloseWindow.Add_Click({ try { $window.Close() } catch { } }) }

# ================================================================ 15.05 桌面模式：不进任务栏 / 不参与 Alt+Tab / 永远最底层
# 时机很关键：必须在 Handle 已经创建、但窗口还没第一次显示的时候动手，
# 这样连窗口第一次出现都不会在任务栏闪一下。
$window.Add_SourceInitialized({
        try {
            if ($script:EtWin32Ready) {
                $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
                if ($h -ne [IntPtr]::Zero) {
                    # WS_EX_TOOLWINDOW：从 Alt+Tab 列表里移除。
                    # 其实 ShowInTaskbar=False 已经隐式做了这件事，这里显式设一遍更稳。
                    $ex = [ETWindowNative]::GetWindowLongPtr($h, [ETWindowNative]::GWL_EXSTYLE).ToInt64()
                    [void][ETWindowNative]::SetWindowLongPtr($h, [ETWindowNative]::GWL_EXSTYLE,
                        [IntPtr]($ex -bor [ETWindowNative]::WS_EX_TOOLWINDOW))
                    Set-ETWindowBottom
                }
            }
            Enter-ETDesktopMode
        }
        catch { }
    })

function Update-FullScreenLabel {
    <# .SYNOPSIS 全屏按钮文案随实际尺寸变，避免「点了没反应」的错觉。 #>
    if (-not $ui.BtnFullScreen) { return }
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $isFull = ([Math]::Abs($window.Width - $wa.Width) -lt 2) -and ([Math]::Abs($window.Height - $wa.Height) -lt 2)
        $ui.BtnFullScreen.Content = $(if ($isFull) { '还原' } else { '全屏' })
    }
    catch { }
}

# 沉底后重新计算「全屏 / 还原」的方向：沉底会把窗口还原并丢掉最大化状态，
# 所以直接用实测宽高与工作区比对来判断当前是否全屏。
$window.Add_SizeChanged({ try { Update-FullScreenLabel } catch { } })

# 只要本窗口拿到前台（比如用户从铭牌点了展开），立刻主动沉回最底层 ——
# 这就是「无论活动与否都在最低层」的实现；不涉及任何抢焦点动作。
$window.Add_Activated({ try { Set-ETWindowBottom } catch { } })
$window.Add_Deactivated({ try { Set-ETWindowBottom } catch { } })

# 定时兜底：用户点别的窗口一般会触发本窗口 Deactivated，但以下两种情况不会：
#   1) 业务软件自己启动/切前台，本窗口从头到尾没参与；
#   2) 有人用 SetWindowPos 把别的窗口塞进本窗口下面。
# 3 秒一跳，每次只是一个 setwindowpos，开销可以忽略。
# 顺带检查「停止哨兵」：窗口沉底后顶栏按钮可能够不着（业务软件全屏），
# 应急出口是手工建一个空文件，见 ET-项目待办事项.md。
try {
    $script:StopSentinelPath = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'workbench.stop'
}
catch { $script:StopSentinelPath = '' }

try {
    $script:SinkTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SinkTimer.Interval = [System.TimeSpan]::FromSeconds(3)
    $script:SinkTimer.Add_Tick({
            try { Set-ETWindowBottom } catch { }
            try {
                if ($script:StopSentinelPath -and (Test-Path -LiteralPath $script:StopSentinelPath)) {
                    Remove-Item -LiteralPath $script:StopSentinelPath -Force -ErrorAction SilentlyContinue
                    $window.Close()
                }
            }
            catch { }
        })
}
catch { }

# 键盘：F11 全屏 / Esc 收抽屉。不注册任何全局热键，不抢焦点（红线 F-4）。
# 注意：WS_EX_TOOLWINDOW 只把窗口移出 Alt+Tab，不会影响本窗口处于活动状态时的键盘输入；
# 若现场发现 F11 无效，用顶栏的「全屏 / 还原」按钮，功能完全等价。
$window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::F11) { Toggle-FullScreen; $e.Handled = $true }
        elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) { Set-Drawer -Which 'None' }
    })

# ================================================================ 15.1 启动时刷新
$window.Add_Loaded({
        try {
            Update-StatusBar
            Update-DownloadTargets
            Update-SoftwareGrid
            Update-HealthGrid
            Update-Clock
            Update-FullScreenLabel
            # 状态灯颜色直接读铭牌同源数据：有告警=红，有待上报=黄，识别不到=灰
            $st = 'Normal'
            try {
                $snap = Get-ETHealthSnapshot
                if ($snap -and @($snap.Alarms).Count -gt 0) { $st = 'Alarm' }
                else {
                    $os = Get-ETOutboxSummary
                    if ($os -and $os.Pending -gt 0) { $st = 'Warn' }
                }
            }
            catch { $st = '' }
            Update-StatusBadgeColor -State $st
        }
        catch { Write-Boot ("启动刷新失败：{0}" -f $_.Exception.Message) 'Warn' }
    })

# 时钟：30 秒一次足够（顶栏只显示 HH:mm，秒跳会白耗 CPU）
# 注意：$script:ClockTimer 必须存成脚本级变量，否则被 GC 回收后计时器静默停止。
$script:ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ClockTimer.Interval = [System.TimeSpan]::FromSeconds(30)
$script:ClockTimer.Add_Tick({ Update-Clock })

# 计时器启停：沉底动作已经在上面 SinkTimer 的 Tick 里做了（含哨兵检查），
# 这里只负责在窗口 Loaded 时启动、Closed 时停掉，不要再 Add_Tick 一次。
try { $window.Add_Closed({ try { $script:ClockTimer.Stop() } catch { }; try { $script:SinkTimer.Stop() } catch { } }) } catch { }
$window.Add_Loaded({ try { $script:ClockTimer.Start() } catch { }; try { $script:SinkTimer.Start() } catch { } })

# ================================================================ 16. 显示
# 先摆好位置再显示：SourceInitialized 里还会再算一次，因为那时 Handle 才存在。
try { Enter-ETDesktopMode } catch { }
Write-Boot '窗口已就绪'
try {
    # 嵌套消息循环：ShowDialog 返回时窗口已真正关闭，便于区分「关闭退出」与「异常抛出」。
    $null = $window.ShowDialog()
}
catch {
    Show-ETError ("界面异常退出：{0}" -f $_.Exception.Message)
    exit 1
}
finally {
    try { $script:SinkTimer.Stop() } catch { }
    try { $script:ClockTimer.Stop() } catch { }
}

exit 0
