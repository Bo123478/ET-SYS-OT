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

# ================================================================ 0.5 单实例保护（必须最先做）
# 重复打开同一个主窗口容易卡住，避免多个 WPF 消息循环争用窗口/资源。
# 使用 Global 命名空间确保同一用户会话中的所有 PowerShell 进程都能看到同一个互斥锁，
# 这样从 .bat、桌面快捷方式、或左侧铭牌启动时都会被拦住。
#
# ⚠ 这里曾经有过一个真实缺陷（本段注释存在的理由）：
#   被拦住的分支里调用了 Show-ETError，而该函数定义在更下面，
#   于是 PowerShell 抛「无法识别 Show-ETError」→ 被外层 catch 吞掉 → 脚本继续往下走，
#   结果是「限制没生效：照样开了第二个主窗口」。
#   同理，本段必须放在【会话 0 检查之前】（即最前面），否则无桌面会话里根本测不到它。
#   现在：被拦住时先把提示放在【自己的 try/catch】里尽力而为，再【无条件 exit 0】。
$script:MainWindowMutex = $null
$mainIsFirstInstance = $true
try {
    $mainCreatedNew = $false
    $script:MainWindowMutex = New-Object System.Threading.Mutex($true, 'Global\ETWorkbench.MainWindow.SingleInstance', [ref]$mainCreatedNew)
    $mainIsFirstInstance = [bool]$mainCreatedNew
}
catch {
    # 互斥锁不可用（极少数权限受限环境）⇒ 退回进程命令行比对，仍要挡住重复打开。
    try {
        $mainOthers = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*Start-ETWorkbench.ps1*' -and $_.CommandLine -notlike '*-SelfTest*' })
        if ($mainOthers.Count -gt 0) { $mainIsFirstInstance = $false }
    }
    catch { }
    Write-Boot ("单实例保护降级：{0}" -f $_.Exception.Message) 'Warn'
}

if (-not $mainIsFirstInstance) {
    # 先输出（无头/自动化场景也能看到），再弹提示。
    Write-Host '[ET] ET 工作台已打开，不能重复打开。' -ForegroundColor Yellow
    # 只在真实交互桌面里弹模态提示：无桌面会话里 MessageBox 会一直等点击（挂死）。
    if ([System.Environment]::UserInteractive) {
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
            [System.Windows.MessageBox]::Show('ET 工作台已打开，不能重复打开。', 'ET 工作台', 'OK', 'Warning') | Out-Null
        }
        catch { }
    }
    exit 0
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

# 单实例保护已在 §0.5 完成（互斥锁 + 无条件退出）；此处不再重复。

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

# ================================================================ 6.5 页签导航契约（G-07）
#
# 【硬约束】页签索引一旦排序，就打断所有按数字寻址的导航语义。
# 2026-09-30 调整过一次顺序（信息区前移并成为默认页）：当时本文件有 5 处内联裸数字
# （Esc 回首页、一键更新跳卡片区、找不到启动目标跳设置页 ×3）。
# 裸数字散在各处 ⇒ 下次调序必然漏改 ⇒ 现场点了按钮跳错页却不报错。
# 所以现在【一律不再内联数字】，全部走下面这张表 + Select-ETTab 按标题寻址。
#
# 与 UI/MainWindow.xaml 的 TabItem 声明次序【必须一致】：
#     0 信息区（默认打开页） · 1 生产软件 · 2 警告提示 · 3 功能设置 · 4 主数据
$script:TabIndex = @{
    '信息区'   = 0
    '应用区'   = 1
    '警告提示' = 2
    '功能设置' = 3
    '主数据'   = 4
}
$script:TabHome = '信息区'   # Esc / 启动默认落点

function Select-ETTab {
    <#
      .SYNOPSIS 按【页签标题】切换页签（不再按数字），标题不存在时安静返回 $false。
      .DESCRIPTION
        用标题寻址而不是数字，是为了让「页签调序」只改 6.5 这张表 + MainWindow.xaml，
        调用点一处都不用动。找不到标题只记 Warn，不抛异常（页签不是业务功能，
        绝不能因为导航失手把整个按钮点击逻辑打断）。
    #>
    param([Parameter(Mandatory)][string]$Title)
    if (-not $ui.MainTabs) { return $false }
    $idx = $script:TabIndex[$Title]
    if ($null -eq $idx) {
        Write-Boot ("页签标题未登记：{0}" -f $Title) 'Warn'
        return $false
    }
    $ui.MainTabs.SelectedIndex = [int]$idx
    return $true
}

# ================================================================ 7. 控件引用
# 说明：$ui 里的每一个名字都必须是 XAML 里真实存在的 x:Name，
# 否则 tools/Test-ETIntegration.ps1 的「每个 $ui.<Name> 都存在」硬门禁直接报红
# （那个门禁是正则扫本文件源码，不是扫 XAML —— 删 XAML 名必须同批删这里）。
# 反向不强制：只是画在界面上、脚本不写它的控件，不必登记在这里。
$ui = @{
    # ---- 页签容器 ----
    MainTabs        = Get-UiElement 'MainTabs'

    # ---- 底部状态条（顶栏重复摘要已删除，缺陷 D-8）----
    TxtIdentity     = Get-UiElement 'TxtIdentity'
    TxtShare        = Get-UiElement 'TxtShare'
    TxtVersion      = Get-UiElement 'TxtVersion'
    TxtClock        = Get-UiElement 'TxtClock'
    TxtStatusFull   = Get-UiElement 'TxtStatusFull'
    StatusBarDot    = Get-UiElement 'StatusBarDot'
    BtnCloseWindow  = Get-UiElement 'BtnCloseWindow'
    BtnFullScreen   = Get-UiElement 'BtnFullScreen'

    # ---- 页签 0 · 信息区（默认打开页；含内嵌铭牌卡）----
    # 内嵌铭牌卡的控件名一律加 Plate 前缀，与 PlateBar.xaml 的 x:Name 区分开：
    # 两个文件同在一份 XAML 树里会撞名（XamlReader 直接抛异常），但更危险的是
    # 以后有人把 PlateBar.xaml 的片段直接拷过来改名 —— 前缀能让这种拷贝一眼看出来。
    PlateStrip       = Get-UiElement 'PlateStrip'
    PlateTitle       = Get-UiElement 'PlateTitle'
    PlateStatusPill  = Get-UiElement 'PlateStatusPill'
    PlateStatusDot   = Get-UiElement 'PlateStatusDot'
    PlateStatusText  = Get-UiElement 'PlateStatusText'
    PlateEquip       = Get-UiElement 'PlateEquip'
    PlateEt          = Get-UiElement 'PlateEt'
    PlateIp          = Get-UiElement 'PlateIp'
    PlateMpc         = Get-UiElement 'PlateMpc'
    PlateVer         = Get-UiElement 'PlateVer'
    PlateUpdated     = Get-UiElement 'PlateUpdated'
    TxtInfoState     = Get-UiElement 'TxtInfoState'
    TxtInfoRule      = Get-UiElement 'TxtInfoRule'
    TxtInfoEquip     = Get-UiElement 'TxtInfoEquip'
    TxtInfoApp       = Get-UiElement 'TxtInfoApp'
    TxtInfoPending   = Get-UiElement 'TxtInfoPending'
    BtnIdentify      = Get-UiElement 'BtnIdentify'
    TxtIdentityOut   = Get-UiElement 'TxtIdentityOut'
    TxtAbout         = Get-UiElement 'TxtAbout'

    # ---- 页签 1 · 应用区（生产软件 / 系统工具 / 周边）----
    BtnRefreshSoft  = Get-UiElement 'BtnRefreshSoft'
    SoftCardPanel   = Get-UiElement 'SoftCardPanel'
    CmbApplication  = Get-UiElement 'CmbApplication'
    CmbVersion      = Get-UiElement 'CmbVersion'
    BtnPlan         = Get-UiElement 'BtnPlan'
    BtnDownload     = Get-UiElement 'BtnDownload'
    TxtDownloadOut  = Get-UiElement 'TxtDownloadOut'

    # ---- 页签 2 · 警告提示 ----
    # 注意：Topmost 不在此处 —— 本窗口永远沉底、绝不置顶（红线 F-4）。
    AlarmCardPanel  = Get-UiElement 'AlarmCardPanel'
    BtnHealthCheck  = Get-UiElement 'BtnHealthCheck'
    GridHealth      = Get-UiElement 'GridHealth'
    TxtHealthOut    = Get-UiElement 'TxtHealthOut'

    # ---- 页签 3 · 功能设置 ----
    ChkLogUpload    = Get-UiElement 'ChkLogUpload'
    ChkAutoUpdate   = Get-UiElement 'ChkAutoUpdate'
    BtnOneKeyUpdate = Get-UiElement 'BtnOneKeyUpdate'
    BtnCheckUpdate  = Get-UiElement 'BtnCheckUpdate'
    BtnSelfUpdate   = Get-UiElement 'BtnSelfUpdate'
    TxtUpdateOut    = Get-UiElement 'TxtUpdateOut'
    BtnOpenDataRoot = Get-UiElement 'BtnOpenDataRoot'
    TxtSettingOut   = Get-UiElement 'TxtSettingOut'

    # ---- 页签 3 · 本机偏好（写入本地覆盖，不动 workstation.json 冻结键名）----
    CmbLogLevel          = Get-UiElement 'CmbLogLevel'
    TxtLogRetentionDays  = Get-UiElement 'TxtLogRetentionDays'
    CmbUiScale           = Get-UiElement 'CmbUiScale'
    TxtUiScaleNote       = Get-UiElement 'TxtUiScaleNote'
    ChkStartFullScreen   = Get-UiElement 'ChkStartFullScreen'
    TxtStartupCommand    = Get-UiElement 'TxtStartupCommand'
    BtnSavePreferences   = Get-UiElement 'BtnSavePreferences'
    TxtScheduleNote      = Get-UiElement 'TxtScheduleNote'

    # ---- 页签 4 · 主数据 ----
    BtnMdLoad       = Get-UiElement 'BtnMdLoad'
    CmbMdKind       = Get-UiElement 'CmbMdKind'
    TxtMdPath       = Get-UiElement 'TxtMdPath'
    BtnMdValidate   = Get-UiElement 'BtnMdValidate'
    TxtMdOut        = Get-UiElement 'TxtMdOut'
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

        # 摘要只在底部状态条出现一处（顶栏那份已删除，缺陷 D-8）。
        # 只做「已有数据的中文摘要」，不在这里判定红黄绿 —— 颜色归铭牌/§8.2。
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
        .OUTPUTS Hashtable { EquipmentId; EtCode; MpcCode; Complete }
        Complete = 三个编号全部拿到。与 Start-ETPlate.ps1 的 Resolve-ETPlate 同名同义，
        供 §12.7 的内嵌铭牌卡与左侧铭牌走【同一套「三编号不全就整块退示例值」规则】。
    #>
    param([string]$Ip)

    $out = @{ EquipmentId = ''; EtCode = ''; MpcCode = ''; Complete = $false }
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

    $out.Complete = [bool]($out.EquipmentId -and $out.EtCode -and $out.MpcCode)
    return $out
}

# ================================================================ 8.1.5 内嵌铭牌卡的示例值
#
# 【为什么这里也要有一份示例值】
#   左侧铭牌（Start-ETPlate.ps1 的 $Script:SamplePlate）在「共享清单未接入 / 三编号不全」
#   时显示示例值，并在抬头标注「示例」。信息区里这张卡必须【显示同样的东西】，
#   否则同一屏上左边写 W098、右边写「—」，现场只会得出「工具坏了」一个结论。
#   取值必须与 Start-ETPlate.ps1 逐条一致，改一处必须同批改另一处（缺陷 D-10 同理）。
$script:SamplePlate = @{ Equip = 'W098'; Et = 'ZET1025'; Mpc = '096' }

# 铭牌版本号：左侧铭牌是 Start-ETPlate.ps1 -Version 传进来的（默认 1.1.0）。
# 两个进程各自启动、无法互读内存，所以这里必须【手动与 Start-ETPlate.ps1 的默认值对齐】。
# 若用 -Version 启动铭牌，两处页脚版本号会不一致 —— 已知取舍，不为此引入跨进程读值。
$script:PlateCardVersion = '1.1.0'

function Update-Clock {
    <# .SYNOPSIS 顶栏时钟（HH:mm）。秒级刷新交给 DispatcherTimer，见 §15。 #>
    if ($ui.TxtClock) { $ui.TxtClock.Text = (Get-Date -Format 'HH:mm') }
}

function Get-ETStateColorText {
    <# .SYNOPSIS 三态 Key -> 中文文案（与铭牌 $Script:PlateState 逐条一致）。 #>
    param([string]$State)
    switch ("$State") {
        'Alarm' { '报警' }
        'Warn' { '警告' }
        'Normal' { '正常' }
        default { '未知' }
    }
}

# ================================================================ 8.2 三态判定（唯一一处分叉修复点，缺陷 D-10）
#
# 【为什么规则表要在这里再写一遍】
#   铭牌是独立进程（Start-ETPlate.ps1），它的 $Script:PlateRules 无法被本脚本 import
#   （那是另一个进程的内存，且刻意没有抽成 psm1 —— 见 B-13 / N-20）。
#   但「铭牌红、窗口绿」是现场绝对不能接受的：同一个工位上两块显示互相打脸，
#   运维会先怀疑工具坏了。所以这里的规则表必须与 Start-ETPlate.ps1 的
#   $Script:PlateRules 【逐条一致】。改动任一处，必须同批改另一处。
#
#   旧版这里不是规则表，而是一段内联判定：
#       if (Alarms -gt 0) 'Alarm' elseif (Pending -gt 0) 'Warn' else 'Normal'
#   它漏掉了三种「不确定」情形（未接入共享清单 / 共享不可达 / 设备未识别），
#   在那些情形下 Alarms 与 Pending 都是 0 ⇒ 返回绿色「正常」，
#   而铭牌同时报红。这就是缺陷 D-10。
#
# 【判定顺序】先跑 Alarm 组，再跑 Warn 组；组内按声明顺序，命中第一条即定格。
# 【口径】两个脚本块都只读 $S，不写任何状态；要改阈值/加条目/换语义只动这张表。
$script:ETStateRules = @(
    # ---------------- 报警（红）：需要立即处置 ----------------
    @{ Id = 'A-01'; State = 'Alarm'
        Test   = { param($S) $S.Configured -and (-not $S.Reachable) }
        Reason = { param($S) '已配置共享清单但不可达（离线）' } }

    @{ Id = 'A-02'; State = 'Alarm'
        Test   = { param($S) $S.Alarms -gt 0 }
        Reason = { param($S) '健康规则告警 {0} 条' -f $S.Alarms } }

    @{ Id = 'W-01'; State = 'Alarm'
        Test   = { param($S) -not $S.Configured }
        Reason = { param($S) '未接入共享清单' } }

    @{ Id = 'W-02'; State = 'Alarm'
        Test   = { param($S) -not $S.Identified }
        Reason = { param($S) '设备未识别（识别链未命中）' } }

    # ---------------- 警告（黄）----------------
    @{ Id = 'W-03'; State = 'Warn'
        Test   = { param($S) $S.Pending -gt 0 }
        Reason = { param($S) '待上报事件积压 {0} 条' -f $S.Pending } }
)

function Get-ETAlarmState {
    <#
      .SYNOPSIS 三态判定所需的原始采集结果（与铭牌的 Get-ETAlarmState 同形）。
      .DESCRIPTION
        只采集事实，不做判定。字段名必须与 Start-ETPlate.ps1 的 $S 完全一致，
        因为 $script:ETStateRules 里的两个脚本块是按字段名读的。
        FromSample 与铭牌同名同义：当前显示的是示例值（未接入共享清单 / 三编号不全）。
        它【不参与规则判定】（规则表只读 Configured/Reachable/Alarms/Pending/Identified），
        只用在内嵌铭牌卡抬头标注「示例」，与左侧铭牌保持一致。
    #>
    param([bool]$FromSample = $false)
    $s = @{
        FromSample = [bool]$FromSample
        Identified = $false
        Configured = $false
        Reachable  = $false
        Pending    = 0
        Alarms     = 0
        Unknowns   = 0
    }

    try {
        $snap = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'identity.json'
        if (Test-Path -LiteralPath $snap) {
            $id = (Get-Content -LiteralPath $snap -Raw -Encoding UTF8 | ConvertFrom-Json)
            if ($id -and (Test-ETObjectHasProperty -InputObject $id -Name 'Status')) {
                $s.Identified = ("$($id.Status)" -eq 'Identified')
            }
        }
    }
    catch { }

    try {
        $st = Get-ETShareReachableState
        $s.Configured = [bool]$st.IsConfigured
        $s.Reachable = [bool]$st.IsReachable
    }
    catch { }

    try {
        $sum = Get-ETOutboxSummary
        $s.Pending = [int]$sum.Pending
    }
    catch { }

    try {
        $h = Get-ETHealthSnapshot
        if ($h -and (Test-ETObjectHasProperty -InputObject $h -Name 'Alarms')) { $s.Alarms = @($h.Alarms).Count }
        if ($h -and (Test-ETObjectHasProperty -InputObject $h -Name 'Unknowns')) { $s.Unknowns = @($h.Unknowns).Count }
    }
    catch { }

    return $s
}

function Get-ETStateVerdict {
    <#
      .SYNOPSIS 按 $script:ETStateRules 定三态，返回 @{ State; RuleId; Reason }。
      .DESCRIPTION
        State  ∈ Normal | Warn | Alarm；RuleId 命中规则号（未命中为空）；
        Reason 中文原因（未命中为「未命中任何规则」）。
        这是【主窗口唯一的判定入口】。Update-StatusBadgeColor / 信息区 / 警告提示
        都必须从这里取结论，不得各自重写 if-else —— 否则 D-10 会复发。
    #>
    $hit = $null
    try {
        $state = Get-ETAlarmState
        foreach ($want in @('Alarm', 'Warn')) {
            foreach ($r in $script:ETStateRules) {
                if ([string]$r.State -ne $want) { continue }
                $ok = $false
                try { $ok = [bool](& $r.Test $state) } catch { $ok = $false }
                if ($ok) { $hit = $r; break }
            }
            if ($hit) { break }
        }
    }
    catch {
        # 采集本身失败 ⇒ 不能冒充正常。归红（与铭牌「不确定一律归红」同口径）。
        return @{ State = 'Alarm'; RuleId = ''; Reason = ("三态判定采集失败：{0}" -f $_.Exception.Message) }
    }

    if ($hit) {
        $why = ''
        try { $why = [string](& $hit.Reason $state) } catch { $why = '' }
        return @{ State = [string]$hit.State; RuleId = [string]$hit.Id; Reason = $why }
    }
    return @{ State = 'Normal'; RuleId = ''; Reason = '未命中任何规则' }
}

function Update-StatusBadgeColor {
    <#
      .SYNOPSIS 底部状态灯颜色。
      .DESCRIPTION
        结论来自 Get-ETStateVerdict（§8.2 的规则表），本函数只负责把状态换成颜色 ——
        判定与上色分开，保证与铭牌同源。调用方可传 -State 覆盖（仅调试用）。
        颜色取值与铭牌 $Script:PlateState 逐条一致。
    #>
    param([string]$State)
    if (-not $PSBoundParameters.ContainsKey('State') -or -not $State) {
        try { $State = (Get-ETStateVerdict).State } catch { $State = '' }
    }
    $color = switch ("$State") {
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

function Initialize-ETStartupDesktopMode {
    <#
      .SYNOPSIS 按本机偏好决定启动时是全屏桌面模式还是普通窗口。
      .DESCRIPTION
        偏好 = settings.json 的 StartFullScreen（本地覆盖），缺省 $true（现场默认全屏，决策 ⑤）。
        这里刻意【不】直接调用 Enter-ETDesktopMode：偏好为「关」时必须真的不铺满，
        否则「本机偏好」页签上的勾选框就成了假开关 —— 只写不读的设置等于没有设置。
        调用时机在 §14.5 之后（Get-ETSetting 已定义），因此可以放心读文件。
    #>
    try {
        $fs = Get-ETSetting -Name 'StartFullScreen' -Default $null
        if ($null -eq $fs) { $fs = $true }
        if ([bool]$fs) { Enter-ETDesktopMode } else { Exit-ETDesktopMode }
    }
    catch { try { Enter-ETDesktopMode } catch { } }
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

# ================================================================ 9. 页签 0 · 信息区：我是谁（E-02）
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

# ================================================================ 10. 页签 1 · 应用区：软件状态（E-03）
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

function Get-ETResolvedExecutableTarget {
    param(
        [string]$RootFolder,
        [string]$Name,
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($RootFolder) -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
    $folder = Join-Path $RootFolder $Name
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return $null }

    $candidates = @()
    foreach ($file in Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue) {
        if ($file.Extension -ieq '.exe') {
            $lower = $file.Name.ToLowerInvariant()
            if ($lower -notmatch 'vshost\.exe$' -and $lower -notmatch '(update\.exe)$') {
                $candidates += $file.FullName
            }
        }
    }

    if ($candidates.Count -gt 0) {
        return @($candidates | Sort-Object -Property Length | Select-Object -First 1)[0]
    }

    return $folder
}

function Get-ETBrowserExecutablePath {
    $paths = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "$env:ProgramFiles(x86)\Mozilla Firefox\firefox.exe"
    )

    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
    }
    return $null
}

function Get-ETAppIconSource {
    param(
        [string]$Target,
        [string]$AppName = '',
        [string]$Category = ''
    )

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue

        $resolved = $Target
        if ($resolved -and $resolved -match '^explorer\.exe\s+shell:') {
            $resolved = 'explorer.exe'
        }
        elseif ($resolved -like '*.url') {
            $browser = Get-ETBrowserExecutablePath
            if ($browser) { $resolved = $browser }
        }
        elseif ($resolved -eq 'osk.exe') {
            $resolved = (Get-Command -Name 'osk.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
        }

        $icon = $null
        $iconFile = $resolved
        if (-not $iconFile) {
            if ($Category -eq 'SystemTool') {
                switch ($AppName) {
                    '我的电脑' { $iconFile = [System.Environment]::SystemDirectory + '\imageres.dll'; $iconFile = $iconFile; break }
                    '控制面板' { $iconFile = [System.Environment]::SystemDirectory + '\shell32.dll'; break }
                    '网络' { $iconFile = [System.Environment]::SystemDirectory + '\shell32.dll'; break }
                    '软键盘' { $iconFile = [System.Environment]::SystemDirectory + '\osk.exe'; break }
                }
            }
            elseif ($Category -eq 'Peripheral') {
                $browser = Get-ETBrowserExecutablePath
                if ($browser) { $iconFile = $browser }
            }
        }

        if ($iconFile -and ($iconFile -match '\.(exe|dll|ico)$' -or $iconFile -eq 'explorer.exe' -or $iconFile -eq 'osk.exe')) {
            $file = $iconFile
            if ($file -eq 'osk.exe') {
                $file = (Get-Command -Name 'osk.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
            }
            if ($file -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($file)
            }
            elseif ($file -and (Test-Path -LiteralPath $file)) {
                try { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($file) } catch { }
            }
        }

        if (-not $icon) {
            switch ($Category) {
                'SystemTool' {
                    switch ($AppName) {
                        '我的电脑' { $icon = [System.Drawing.SystemIcons]::WinLogo; break }
                        '控制面板' { $icon = [System.Drawing.SystemIcons]::Application; break }
                        '网络' { $icon = [System.Drawing.SystemIcons]::Information; break }
                        '软键盘' { $icon = [System.Drawing.SystemIcons]::Application; break }
                        default { $icon = [System.Drawing.SystemIcons]::Application }
                    }
                    break
                }
                'Peripheral' {
                    $browser = Get-ETBrowserExecutablePath
                    if ($browser -and (Test-Path -LiteralPath $browser -PathType Leaf)) {
                        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($browser)
                    }
                    if (-not $icon) { $icon = [System.Drawing.SystemIcons]::Application }
                    break
                }
                default { $icon = [System.Drawing.SystemIcons]::Application }
            }
        }

        $hIcon = $icon.Handle
        $bitmap = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($hIcon, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $bitmap.Freeze()
        return $bitmap
    }
    catch {
        return $null
    }
}

function Get-ETSoftwareExampleCatalog {
    [CmdletBinding()]
    param()

    $root = 'C:\Users\wuhui\Desktop\Dev\软件列表'
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    $rows = @()
    $catalog = @(
        @{ Category='Production'; AppId='APP-1001'; Name='Monitoring'; Version='1.0.0'; Description='生产监控与运行状态看板'; Target='' },
        @{ Category='Production'; AppId='APP-1002'; Name='MPC-Net'; Version='1.0.0'; Description='网络通信与设备接入辅助'; Target='' },
        @{ Category='Production'; AppId='APP-1003'; Name='SfTag&ATLAS-R'; Version='1.0.0'; Description='标签与分析产线辅助工具'; Target='' },
        @{ Category='SystemTool'; AppId='APP-3001'; Name='我的电脑'; Version='系统'; Description='Windows 文件与磁盘入口'; Target='explorer.exe shell:MyComputerFolder' },
        @{ Category='SystemTool'; AppId='APP-3002'; Name='控制面板'; Version='系统'; Description='Windows 控制面板入口'; Target='explorer.exe shell:ControlPanelFolder' },
        @{ Category='SystemTool'; AppId='APP-3003'; Name='网络'; Version='系统'; Description='网络与共享位置入口'; Target='explorer.exe shell:NetworkPlacesFolder' },
        @{ Category='SystemTool'; AppId='APP-3004'; Name='软键盘'; Version='系统'; Description='On-Screen Keyboard'; Target='osk.exe' },
        @{ Category='Peripheral'; AppId='APP-2001'; Name='Copilot'; Version='Web'; Description='AI 助手页面快捷入口'; Target='' },
        @{ Category='Peripheral'; AppId='APP-2002'; Name='DATA-BRICKS'; Version='Web'; Description='数据平台快捷入口'; Target='' },
        @{ Category='Peripheral'; AppId='APP-2003'; Name='Forms'; Version='Web'; Description='表单与流程入口'; Target='' },
        @{ Category='Peripheral'; AppId='APP-2004'; Name='PowerBI'; Version='Web'; Description='报表与分析入口'; Target='' },
        @{ Category='Peripheral'; AppId='APP-2005'; Name='Loop'; Version='Web'; Description='协作与任务入口'; Target='' }
    )

    foreach ($item in $catalog) {
        $target = $item.Target
        switch ($item.Category) {
            'Production' {
                $p = Join-Path (Join-Path $root '生产软件') $item.Name
                $target = Get-ETResolvedExecutableTarget -RootFolder (Join-Path $root '生产软件') -Name $item.Name -Category $item.Category
                if (-not $target) { $target = $p }
            }
            'SystemTool' {
                if ($item.Name -eq '软键盘') { $target = 'osk.exe' }
            }
            'Peripheral' {
                $p = Join-Path (Join-Path $root '周边') ($item.Name + '.url')
                if (Test-Path -LiteralPath $p) { $target = $p }
            }
        }

        $exists = $false
        if ($target) {
            if ($target -match '^explorer\.exe\s') { $exists = $true }
            elseif ($target -like '*.url') { $exists = (Test-Path -LiteralPath $target) }
            elseif ($target -eq 'osk.exe') { $exists = (Get-Command -Name 'osk.exe' -ErrorAction SilentlyContinue) -ne $null }
            elseif ($target -match '\.exe$') { $exists = (Test-Path -LiteralPath $target -PathType Leaf) }
            else { $exists = (Test-Path -LiteralPath $target) }
        }

        $rows += [pscustomobject]@{
            ApplicationId   = $item.AppId
            ApplicationName = $item.Name
            SoftwareId      = $item.AppId
            ApprovedVersion = $item.Version
            LocalVersion    = $item.Version
            State           = 'Effective'
            StateOrder      = 7
            StateLabel      = '已生效'
            Description     = $item.Description
            LaunchTarget    = $target
            DownloadVisible = (-not $exists)
            Category        = $item.Category
        }
    }

    return $rows
}

function Invoke-ETAppLaunch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [AllowNull()][string]$LaunchTarget
    )

    if ([string]::IsNullOrWhiteSpace($LaunchTarget)) {
        # 没有启动目标 ⇒ 该软件还没下载。跳到【功能设置】页（下载/更新都在那里）。
        [void](Select-ETTab '功能设置')
        return
    }

    if ($LaunchTarget -match '^explorer\.exe\s') {
        $parts = $LaunchTarget -split '\s+', 2
        if ($parts.Count -eq 2) {
            Start-Process -FilePath $parts[0] -ArgumentList $parts[1] | Out-Null
            return
        }
    }

    if ($LaunchTarget -like '*.url') {
        try {
            $url = $null
            foreach ($line in (Get-Content -LiteralPath $LaunchTarget -ErrorAction SilentlyContinue)) {
                if ($line -match '^URL=') { $url = ($line -split '=', 2)[1]; break }
            }
            if ($url) { Start-Process -FilePath $url | Out-Null; return }
        }
        catch { }
    }

    if ($LaunchTarget -match '\.exe$' -and (Test-Path -LiteralPath $LaunchTarget -PathType Leaf)) {
        Start-Process -FilePath $LaunchTarget | Out-Null
        return
    }

    if ($LaunchTarget -and (Test-Path -LiteralPath $LaunchTarget)) {
        if ((Test-Path -LiteralPath $LaunchTarget -PathType Container)) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "\"$LaunchTarget\"" | Out-Null
        }
        else {
            Start-Process -FilePath $LaunchTarget | Out-Null
        }
        return
    }

    if ($ui.MainTabs) {
        # 目标不存在（可能被现场删了/改了路径）⇒ 引导到功能设置页看下载入口。
        [void](Select-ETTab '功能设置')
    }
}

function New-SoftwareCard {
    <#
      .SYNOPSIS  为单个应用生成一张缩小版卡片，点击打开；若目标不存在则显示下载按钮。
    #>
    param($Row, [AllowNull()][string]$Description)

    $appId = "$($Row.ApplicationId)"
    $appName = "$($Row.ApplicationName)"
    if ([string]::IsNullOrWhiteSpace($appName)) { $appName = if ($appId) { $appId } else { '未知应用' } }
    $ver = if ($Row.ApprovedVersion) { "$($Row.ApprovedVersion)" } else { '—' }
    $desc = if ([string]::IsNullOrWhiteSpace($Description)) { '暂无描述' } else { $Description }
    $launchTarget = if ($Row.LaunchTarget) { "$($Row.LaunchTarget)" } else { $null }
    $downloadVisible = [bool]$Row.DownloadVisible

    $card = New-Object System.Windows.Controls.Border
    $card.Width = 186
    $card.Height = 150
    $card.Margin = New-Object System.Windows.Thickness 8
    $card.Padding = New-Object System.Windows.Thickness 10
    $card.CornerRadius = New-Object System.Windows.CornerRadius 14
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.Background = New-Object System.Windows.Media.LinearGradientBrush
    $card.Background.StartPoint = New-Object System.Windows.Point 0,0
    $card.Background.EndPoint = New-Object System.Windows.Point 1,1
    $card.Background.GradientStops.Add((New-Object System.Windows.Media.GradientStop -Property @{ Color = [System.Windows.Media.Color]::FromRgb(255,255,255); Offset = 0.0 }))
    $card.Background.GradientStops.Add((New-Object System.Windows.Media.GradientStop -Property @{ Color = [System.Windows.Media.Color]::FromRgb(244,248,255); Offset = 1.0 }))
    $card.BorderBrush = ConvertTo-ETBrush '#FFD7E7F7'
    $card.Cursor = 'Hand'
    $card.Tag = $appId

    $accent = New-Object System.Windows.Controls.Border
    $accent.Width = 4
    $accent.HorizontalAlignment = 'Left'
    $accent.Background = ConvertTo-ETBrush '#FF2F6FB5'
    $accent.CornerRadius = New-Object System.Windows.CornerRadius 2
    $accent.Margin = New-Object System.Windows.Thickness 0,8,0,8
    $card.Child = $accent

    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 16
    $shadow.ShadowDepth = 3
    $shadow.Opacity = 0.18
    $shadow.Color = [System.Windows.Media.Color]::FromRgb(26,42,60)
    $card.Effect = $shadow

    $main = New-Object System.Windows.Controls.Grid
    $main.Margin = New-Object System.Windows.Thickness 12,10,8,8
    $main.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    $main.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    $main.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    $main.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    $main.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))

    $iconArea = New-Object System.Windows.Controls.Border
    $iconArea.Width = 44
    $iconArea.Height = 44
    $iconArea.CornerRadius = New-Object System.Windows.CornerRadius 12
    $iconArea.Margin = New-Object System.Windows.Thickness 0,0,0,8
    $iconArea.HorizontalAlignment = 'Left'
    $iconArea.Background = New-Object System.Windows.Media.LinearGradientBrush
    $iconArea.Background.StartPoint = New-Object System.Windows.Point 0,0
    $iconArea.Background.EndPoint = New-Object System.Windows.Point 1,1
    $iconArea.Background.GradientStops.Add((New-Object System.Windows.Media.GradientStop -Property @{ Color = [System.Windows.Media.Color]::FromRgb(237,244,255); Offset = 0.0 }))
    $iconArea.Background.GradientStops.Add((New-Object System.Windows.Media.GradientStop -Property @{ Color = [System.Windows.Media.Color]::FromRgb(214,228,255); Offset = 1.0 }))
    $iconArea.BorderBrush = ConvertTo-ETBrush '#FFC2D7F7'
    $iconArea.BorderThickness = New-Object System.Windows.Thickness 1
    $iconArea.SetValue([System.Windows.Controls.Grid]::RowProperty, 0)

    $icon = Get-ETAppIconSource -Target $launchTarget -AppName $appName -Category $Row.Category
    if ($icon) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $icon
        $img.Width = 28
        $img.Height = 28
        $img.Stretch = 'Uniform'
        $img.Margin = New-Object System.Windows.Thickness 8
        $img.HorizontalAlignment = 'Center'
        $img.VerticalAlignment = 'Center'
        $iconArea.Child = $img
    }
    else {
        $iconText = New-Object System.Windows.Controls.TextBlock
        $iconText.Text = $appName.Substring(0,1).ToUpper()
        $iconText.Foreground = ConvertTo-ETBrush '#FF2F6FB5'
        $iconText.FontSize = 17
        $iconText.FontWeight = 'Bold'
        $iconText.HorizontalAlignment = 'Center'
        $iconText.VerticalAlignment = 'Center'
        $iconArea.Child = $iconText
    }
    [void]$main.Children.Add($iconArea)

    $tName = New-Object System.Windows.Controls.TextBlock
    $tName.Text = $appName
    $tName.FontSize = 12
    $tName.FontWeight = 'Bold'
    $tName.TextTrimming = 'CharacterEllipsis'
    $tName.Foreground = ConvertTo-ETBrush '#FF1A2737'
    $tName.Margin = New-Object System.Windows.Thickness 0,0,0,4
    $tName.SetValue([System.Windows.Controls.Grid]::RowProperty, 1)
    [void]$main.Children.Add($tName)

    $tVer = New-Object System.Windows.Controls.TextBlock
    $tVer.Text = "版本：$ver"
    $tVer.FontSize = 10
    $tVer.Foreground = ConvertTo-ETBrush '#FF667589'
    $tVer.SetValue([System.Windows.Controls.Grid]::RowProperty, 2)
    [void]$main.Children.Add($tVer)

    $tId = New-Object System.Windows.Controls.TextBlock
    $tId.Text = "编号：$appId"
    $tId.FontSize = 9
    $tId.Foreground = ConvertTo-ETBrush '#FF7C8AA0'
    $tId.SetValue([System.Windows.Controls.Grid]::RowProperty, 3)
    [void]$main.Children.Add($tId)

    $tDesc = New-Object System.Windows.Controls.TextBlock
    $tDesc.Text = $desc
    $tDesc.FontSize = 9
    $tDesc.Foreground = ConvertTo-ETBrush '#FF6D7D8F'
    $tDesc.TextWrapping = 'Wrap'
    $tDesc.MaxHeight = 30
    $tDesc.Margin = New-Object System.Windows.Thickness 0,4,0,0
    $tDesc.SetValue([System.Windows.Controls.Grid]::RowProperty, 4)
    [void]$main.Children.Add($tDesc)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Orientation = 'Vertical'
    [void]$stack.Children.Add($main)

    $card.Child = $stack

    $card.Add_MouseLeftButtonUp({
            param($sender, $e)
            $aid = $sender.Tag
            $target = $null
            foreach ($r in @($script:SampleSoftwareRows)) {
                if ("$($r.ApplicationId)" -eq "$aid") { $target = $r.LaunchTarget; break }
            }
            Invoke-ETAppLaunch -ApplicationId $aid -LaunchTarget $target
        })

    return $card

    if ($downloadVisible) {
        $btnDownload = New-Object System.Windows.Controls.Button
        $btnDownload.Content = '下载'
        $btnDownload.Width = 62
        $btnDownload.Height = 24
        $btnDownload.Padding = New-Object System.Windows.Thickness 0
        $btnDownload.Margin = New-Object System.Windows.Thickness 0,8,0,0
        $btnDownload.Background = ConvertTo-ETBrush '#FF2F6FB5'
        $btnDownload.Foreground = ConvertTo-ETBrush '#FFFFFFFF'
        $btnDownload.BorderThickness = New-Object System.Windows.Thickness 0
        $btnDownload.Tag = $appId
        $btnDownload.Add_Click({
                param($sender, $e)
                # 点「下载」⇒ 跳到【功能设置】页的下载区，并预选该应用
                [void](Select-ETTab '功能设置')
                if ($ui.CmbApplication) { $ui.CmbApplication.SelectedItem = $sender.Tag }
            })
        $btnDownload.SetValue([System.Windows.Controls.Grid]::RowProperty, 5)
        [void]$grid.Children.Add($btnDownload)
    }

    $card.Add_MouseLeftButtonUp({
            param($sender, $e)
            $aid = $sender.Tag
            $target = $null
            foreach ($r in @($script:SampleSoftwareRows)) {
                if ("$($r.ApplicationId)" -eq "$aid") { $target = $r.LaunchTarget; break }
            }
            Invoke-ETAppLaunch -ApplicationId $aid -LaunchTarget $target
        })

    $card.Child = $grid
    return $card
}

function Get-ETSoftwareCategories {
    <#
      .SYNOPSIS 读取生产软件分类表 Config/software-categories.json（缺失时回落内置默认）。
      .DESCRIPTION
        分类不是「过滤条件」而是「分组标题」—— 未登记的软件自动落到「其他」组，
        绝不隐藏。现场最怕「清单里少了一个软件却没人发现」。
    #>
    $fallback = @{
        Order = @(
            [pscustomobject]@{ Key = 'Production'; Title = '生产软件'; Order = 1 }
            [pscustomobject]@{ Key = 'SystemTool'; Title = '系统工具'; Order = 2 }
            [pscustomobject]@{ Key = 'Peripheral'; Title = '周边';     Order = 3 }
            [pscustomobject]@{ Key = 'Other';      Title = '其他';     Order = 9 }
        )
        Map   = @{}
    }
    try {
        $root = ''
        try { $root = "$(Get-ETProgramRoot)" } catch { }
        if (-not $root) { $root = $Script:Root }
        $file = Join-Path (Join-Path $root 'Config') 'software-categories.json'
        if (-not (Test-Path -LiteralPath $file)) { return $fallback }

        $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $fallback }
        $cfg = $raw | ConvertFrom-Json

        $order = @()
        foreach ($c in @($cfg.Categories | Where-Object { $null -ne $_ })) {
            $order += [pscustomobject]@{ Key = "$($c.Key)"; Title = "$($c.Title)"; Order = [int]$c.Order }
        }
        if ($order.Count -eq 0) { return $fallback }
        if (-not (@($order | Where-Object { $_.Key -eq 'Other' }).Count)) {
            $order += [pscustomobject]@{ Key = 'Other'; Title = '其他'; Order = 99 }
        }
        $order = @($order | Sort-Object -Property Order)

        $map = @{}
        foreach ($m in @($cfg.SoftwareIds | Where-Object { $null -ne $_ })) {
            $names = @($m.PSObject.Properties | Where-Object { $_.Name -ne 'Category' })
            foreach ($p in $names) { $map["$($p.Name)"] = "$($m.Category)" }
        }
        return @{ Order = $order; Map = $map }
    }
    catch {
        Write-Boot ("软件分类表读取失败，使用内置默认分组：{0}" -f $_.Exception.Message) 'Warn'
        return $fallback
    }
}

function New-SoftwareSectionHeader {
    <# .SYNOPSIS 生成一个分组标题（磁贴分区的「小区标题」）。 #>
    param([string]$Title, [int]$Count, [string]$Note)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    # 宽到能独占一整行：WrapPanel 里宽度 >= 面板宽度的元素会被推到新行开头
    $sp.Margin = New-Object System.Windows.Thickness 8, 14, 8, 0
    $sp.MinWidth = 900

    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Title
    $t.FontSize = 15
    $t.FontWeight = 'Bold'
    $t.Foreground = ConvertTo-ETBrush '#FF2B3440'
    [void]$sp.Children.Add($t)

    $n = New-Object System.Windows.Controls.TextBlock
    $n.Text = ("（{0} 项）" -f $Count)
    $n.FontSize = 12
    $n.Foreground = ConvertTo-ETBrush '#FF8A97A6'
    $n.VerticalAlignment = 'Bottom'
    $n.Margin = New-Object System.Windows.Thickness 6, 0, 0, 2
    [void]$sp.Children.Add($n)

    if ($Note) {
        $nn = New-Object System.Windows.Controls.TextBlock
        $nn.Text = $Note
        $nn.FontSize = 11
        $nn.Foreground = ConvertTo-ETBrush '#FFA6B0BC'
        $nn.VerticalAlignment = 'Bottom'
        $nn.Margin = New-Object System.Windows.Thickness 12, 0, 0, 2
        [void]$sp.Children.Add($nn)
    }
    return $sp
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

        $script:SampleSoftwareRows = @(Get-ETSoftwareExampleCatalog)
        $cards = @($script:SampleSoftwareRows)
        if ($cards.Count -eq 0) {
            $sum = Get-ETSoftwareStateSummary
            $cards = @($sum.Rows | Where-Object { $null -ne $_ })
        }
        if ($cards.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = '暂无应用主数据。请先在「主数据」页签拉取最新快照。'
            $empty.Foreground = ConvertTo-ETBrush '#FF6B7787'
            $empty.Margin = New-Object System.Windows.Thickness 8
            [void]$panel.Children.Add($empty)
            return
        }

        $catOrder = @(
            [pscustomobject]@{ Key = 'Production'; Title = '生产软件'; Order = 1 },
            [pscustomobject]@{ Key = 'SystemTool'; Title = '系统工具'; Order = 2 },
            [pscustomobject]@{ Key = 'Peripheral'; Title = '周边'; Order = 3 },
            [pscustomobject]@{ Key = 'Other'; Title = '其他'; Order = 9 }
        )
        $catMap = @{}
        foreach ($r in $cards) {
            $cat = if ($r.Category) { "$($r.Category)" } else { 'Other' }
            if ($cat -and @($catOrder | Where-Object { $_.Key -eq $cat }).Count -gt 0) {
                $catMap["$($r.ApplicationId)"] = $cat
            }
        }

        foreach ($cat in $catOrder) {
            $mine = @()
            foreach ($r in $cards) {
                $appId = "$($r.ApplicationId)"
                $c = if ($catMap.ContainsKey($appId)) { $catMap[$appId] } else { 'Other' }
                if ($c -eq $cat.Key) { $mine += $r }
            }
            if ($mine.Count -eq 0) { continue }

            $section = New-Object System.Windows.Controls.Border
            $section.Margin = New-Object System.Windows.Thickness 8,10,8,10
            $section.Padding = New-Object System.Windows.Thickness 12,10,12,12
            $section.CornerRadius = New-Object System.Windows.CornerRadius 12
            $section.Background = ConvertTo-ETBrush '#FFF7FAFF'
            $section.BorderBrush = ConvertTo-ETBrush '#FFD8E7F8'
            $section.BorderThickness = New-Object System.Windows.Thickness 1

            $stack = New-Object System.Windows.Controls.StackPanel
            $header = New-SoftwareSectionHeader -Title $cat.Title -Count $mine.Count -Note "固定应用区 · $(if ($cat.Key -eq 'Production') {'生产业务'} elseif ($cat.Key -eq 'SystemTool') {'系统入口'} else {'辅助工具'})"
            [void]$stack.Children.Add($header)

            $wrap = New-Object System.Windows.Controls.WrapPanel
            $wrap.Margin = New-Object System.Windows.Thickness 0,4,0,0
            $wrap.ItemWidth = 180
            $wrap.ItemHeight = 138
            foreach ($r in $mine) {
                $desc = if ($r.Description) { "$($r.Description)" } else { if ($descMap.ContainsKey("$($r.ApplicationId)")) { $descMap["$($r.ApplicationId)"] } else { '' } }
                $card = New-SoftwareCard -Row $r -Description $desc
                if ($card) { [void]$wrap.Children.Add($card) }
            }
            [void]$stack.Children.Add($wrap)
            $section.Child = $stack
            [void]$panel.Children.Add($section)
        }
    }
    catch { Write-Boot ("读取软件状态失败：{0}" -f $_.Exception.Message) 'Warn' }
}

if ($ui.BtnRefreshSoft) { $ui.BtnRefreshSoft.Add_Click({ Update-SoftwareGrid }) }

# ================================================================ 11. 页签 3 · 功能设置：一键下载（E-04）
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

# ================================================================ 12. 页签 2 · 警告提示：健康检测（E-05）
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

# ================================================================ 12.5 页签 2 · 警告提示：分类汇总卡片
#
# 用户的期望是「网络未连接 / Windows 的系统报警 / 共享问题 / 与系统清单对比发现的错误」
# 四类各一张汇总卡。这里把「规则 Source」映射到「分类」——
# 之所以按 Source 而不是按规则号硬编码，是因为 health-rules.json 里的规则可以增删，
# 规则号一改硬编码就全错；Source 是规则自带的语义字段，更稳。
#
# ⚠️「与系统清单对比」这一类的规则【目前不存在】（用户明确说「后期会设计规则」）。
#    这里如实显示为「待规则实现」，绝不用别的数据凑数 —— 显示一个假的 0 会让人
#    以为「对比过了，没问题」，那比空着更危险。
$script:ETAlarmCategories = @(
    @{ Key = 'Network'; Title = '网络连通'
        Note  = '网络与共享可达性'
        Sources = @('ShareReachability', 'Network', 'Ping', 'Tcp') }
    @{ Key = 'Windows'; Title = 'Windows 系统'
        Note  = 'CPU / 内存 / 磁盘 / 服务 / 进程 / 事件日志'
        Sources = @('Cim', 'CimInstance', 'PsDrive', 'Service', 'Process', 'EventLog', 'Registry', 'Wmi') }
    @{ Key = 'Share'; Title = '共享问题'
        Note  = '共享清单与上报积压'
        Sources = @('Self', 'Share', 'Outbox') }
    @{ Key = 'Compare'; Title = '与系统清单对比'
        Note  = '规则待设计（后期补充）'
        Sources = @() }
)

function Get-ETRuleCategoryKey {
    <#
      .SYNOPSIS 规则 -> 分类 Key 的归口函数（唯一判定处）。
      .DESCRIPTION
        只认 health-rules.json 里的 Source 字段，映射到 $script:ETAlarmCategories。
        映射不中时归入 Windows（系统类）——不丢弃、不新造分类，
        否则卡片数量与规则数量对不上，现场无法核对（G-07 三层计数核对）。
    #>
    param([string]$RuleId)

    if ($RuleId) {
        $src = ''
        $m = Get-ETRuleSourceMap
        if ($m.ContainsKey($RuleId)) { $src = "$($m[$RuleId])" }
        if ($src) {
            foreach ($c in $script:ETAlarmCategories) {
                if (@($c.Sources) -contains $src) { return "$($c.Key)" }
            }
        }
    }
    return 'Windows'
}

function Get-ETRuleSourceMap {
    <# .SYNOPSIS RuleId -> Source 映射（来自 health-rules.json，供分类汇总用）。 #>
    $map = @{}
    try {
        $hr = Get-ETHealthRules
        foreach ($r in @($hr.Rules | Where-Object { $null -ne $_ })) {
            $id = ''
            try { $id = "$($r.RuleId)" } catch { }
            $src = ''
            try { $src = "$($r.Source)" } catch { }
            if ($id) { $map[$id] = $src }
        }
    }
    catch { }
    return $map
}

function New-AlarmSummaryCard {
    <# .SYNOPSIS 生成一张分类汇总卡片（标题 + 告警/警告/未知计数 + 说明）。 #>
    param([string]$Title, [string]$Note, [int]$AlarmCount, [int]$WarnCount, [int]$UnknownCount = 0,
        [bool]$NotImplemented = $false)

    $card = New-Object System.Windows.Controls.Border
    $card.Width = 250
    $card.Margin = New-Object System.Windows.Thickness 8
    $card.Padding = New-Object System.Windows.Thickness 14
    $card.CornerRadius = New-Object System.Windows.CornerRadius 10
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.Background = ConvertTo-ETBrush '#FFFFFFFF'

    # 侧边色带 = 这一类的整体严重度：红(有严重) > 黄(有警告) > 灰(有未知，无法判定) > 绿(全部正常)
    # 「未知」占灰而不是绿 —— 未知不代表安全（UnknownIsNotFault 只是说不算故障，
    # 不等于可以当绿色报出去）。这是与铭牌「不确定一律归红」同源的口径。
    if ($NotImplemented) { $stripe = '#FF8A94A6' }
    elseif ($AlarmCount -gt 0) { $stripe = '#FFE5533D' }
    elseif ($WarnCount -gt 0) { $stripe = '#FFF2C94C' }
    elseif ($UnknownCount -gt 0) { $stripe = '#FF8A94A6' }
    else { $stripe = '#FF2FBF71' }
    $card.BorderBrush = ConvertTo-ETBrush $stripe

    $sp = New-Object System.Windows.Controls.StackPanel

    $tTitle = New-Object System.Windows.Controls.TextBlock
    $tTitle.Text = $Title
    $tTitle.FontSize = 14
    $tTitle.FontWeight = 'SemiBold'
    $tTitle.Foreground = ConvertTo-ETBrush '#FF2B3440'
    [void]$sp.Children.Add($tTitle)

    $tCount = New-Object System.Windows.Controls.TextBlock
    if ($NotImplemented) {
        $tCount.Text = '— 未设计规则'
        $tCount.Foreground = ConvertTo-ETBrush '#FF8A94A6'
    }
    else {
        $tCount.Text = ("告警 {0} · 警告 {1}" -f $AlarmCount, $WarnCount)
        $tCount.Foreground = ConvertTo-ETBrush $stripe
        $tCount.FontWeight = 'SemiBold'
    }
    $tCount.FontSize = 20
    $tCount.Margin = New-Object System.Windows.Thickness 0, 6, 0, 2
    [void]$sp.Children.Add($tCount)

    if (-not $NotImplemented -and $UnknownCount -gt 0) {
        $tUnk = New-Object System.Windows.Controls.TextBlock
        $tUnk.Text = ("另有 {0} 项无法判定（未知）" -f $UnknownCount)
        $tUnk.FontSize = 12
        $tUnk.Foreground = ConvertTo-ETBrush '#FF8A94A6'
        [void]$sp.Children.Add($tUnk)
    }

    $tNote = New-Object System.Windows.Controls.TextBlock
    $tNote.Text = $Note
    $tNote.FontSize = 11
    $tNote.TextWrapping = 'Wrap'
    $tNote.Foreground = ConvertTo-ETBrush '#FF8A97A6'
    $tNote.Margin = New-Object System.Windows.Thickness 0, 6, 0, 0
    [void]$sp.Children.Add($tNote)

    $card.Child = $sp
    return $card
}

function Update-AlarmSummary {
    <#
      .SYNOPSIS 按分类统计当前告警，刷新「警告提示」页签顶部的汇总卡片。
      .DESCRIPTION
        数据源 = 最后一轮健康检测的快照（Get-ETHealthSnapshot）。

        【计数口径 —— 必须与 ET.Health 的实际数据结构一致，不能拍脑袋】
          · 告警 = $snap.Alarms 里该分类的条目，且 Severity 属「严重」级
          · 警告 = $snap.Alarms 里该分类的条目，Severity 是其余级别
            （当前 health-rules.json 里 9 条规则全部是 Warning，所以今天告警恒为 0，
             这是【如实反映】，不是 bug；将来把某条规则改成 Critical 就会自动出现在「告警」里）
          · 未知 = $snap.Samples 里该分类 Status='Unknown' 的条目

        ⚠️ 之前这里用 Status='Alarm' 统计，那是错的 ——
           Samples 的 Status 只有 Ok / Unknown 两个取值（见 ET.Health 采样块），
           永远不会等于 'Alarm'，所以卡片会永远显示 0，比不显示更误导。

        未做过检测时给出明确提示，而不是显示一组 0 ——
        「没检测过」和「检测过都没问题」必须能分辨，否则现场会漏判。
    #>
    $panel = $ui.AlarmCardPanel
    if (-not $panel) { return }

    $snap = $null
    try { $snap = Get-ETHealthSnapshot } catch { }

    $panel.Children.Clear()

    if (-not $snap) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = '尚未执行过健康检测。点右侧「立即检测」后这里会给出分类汇总。'
        $empty.Foreground = ConvertTo-ETBrush '#FF6B7787'
        $empty.Margin = New-Object System.Windows.Thickness 8
        [void]$panel.Children.Add($empty)
        return
    }

    # ---- 归集：Alarms 按分类统计（Severity 区分 告警/警告） ----
    $alarmBy = @{}
    foreach ($a in @($snap.Alarms | Where-Object { $null -ne $_ })) {
        $rid = ''
        try { $rid = "$($a.RuleId)" } catch { }
        $key = Get-ETRuleCategoryKey -RuleId $rid
        if (-not $alarmBy.ContainsKey($key)) { $alarmBy[$key] = @{ Alarm = 0; Warn = 0 } }
        $sev = ''
        try { $sev = "$($a.Severity)" } catch { }
        if ($sev -eq 'Critical' -or $sev -eq '严重') { $alarmBy[$key].Alarm++ } else { $alarmBy[$key].Warn++ }
    }

    # ---- 归集：Unknowns 按分类统计（未知 ≠ 正常，占灰不占绿） ----
    $unkBy = @{}
    foreach ($s in @($snap.Samples | Where-Object { $null -ne $_ })) {
        $st = ''
        try { $st = "$($s.Status)" } catch { }
        if ($st -ne 'Unknown') { continue }
        $rid = ''
        try { $rid = "$($s.RuleId)" } catch { }
        $key = Get-ETRuleCategoryKey -RuleId $rid
        if (-not $unkBy.ContainsKey($key)) { $unkBy[$key] = 0 }
        $unkBy[$key]++
    }

    foreach ($cat in $script:ETAlarmCategories) {
        $notImpl = (@($cat.Sources).Count -eq 0)
        $a = 0; $w = 0; $u = 0
        if ($alarmBy.ContainsKey($cat.Key)) { $a = [int]$alarmBy[$cat.Key].Alarm; $w = [int]$alarmBy[$cat.Key].Warn }
        if ($unkBy.ContainsKey($cat.Key)) { $u = [int]$unkBy[$cat.Key] }
        [void]$panel.Children.Add((New-AlarmSummaryCard -Title $cat.Title -Note $cat.Note `
                    -AlarmCount $a -WarnCount $w -UnknownCount $u -NotImplemented $notImpl))
    }
}

# ================================================================ 12.6 页签 0 · 信息区：状态摘要药丸
function Update-InfoSummary {
    <#
      .SYNOPSIS 刷新「信息区」页签顶部 5 个药丸（状态 / 命中规则 / 设备 / 应用 / 待上报）。
      .DESCRIPTION
        「状态」与「命中」两个药丸的值直接来自 §8.2 的 Get-ETStateVerdict ——
        与铭牌、与底部状态灯【同一个结论】，不是另算一套。
    #>
    # ---- 1. 三态（与铭牌同源） ----
    try {
        $v = Get-ETStateVerdict
        if ($ui.TxtInfoState) {
            # 注意：switch 只能作为【赋值语句】的值，不能直接塞进命令参数括号里
            # （PowerShell 解析器会报「意外的标记 {」），所以先落变量再上色。
            $stateColor = switch ("$($v.State)") {
                'Alarm' { '#FFE5533D' }
                'Warn' { '#FFC79A18' }
                'Normal' { '#FF1E8A3C' }
                default { '#FF8A94A6' }
            }
            $ui.TxtInfoState.Text = ("状态：{0}" -f (Get-ETStateColorText -State $v.State))
            $ui.TxtInfoState.Foreground = ConvertTo-ETBrush $stateColor
        }
        if ($ui.TxtInfoRule) {
            $ui.TxtInfoRule.Text = if ($v.RuleId) { ("命中：{0} {1}" -f $v.RuleId, $v.Reason) }
            else { ("命中：—（{0}）" -f $v.Reason) }
        }
    }
    catch {
        if ($ui.TxtInfoState) { $ui.TxtInfoState.Text = '状态：判定失败' }
        if ($ui.TxtInfoRule) { $ui.TxtInfoRule.Text = ("命中：—（{0}）" -f $_.Exception.Message) }
    }

    # ---- 2. 设备 ----
    try {
        $s = Get-ETAlarmState
        $eq = ''
        try { $eq = "$(Get-ETOutboxEquipmentId)" } catch { }
        if ($ui.TxtInfoEquip) {
            $ui.TxtInfoEquip.Text = if ($s.Identified -and $eq) { "设备：$eq" }
            elseif ($eq) { "设备：$eq（未识别）" }
            else { '设备：未识别' }
        }
        if ($ui.TxtInfoPending) {
            $ui.TxtInfoPending.Text = ("待上报：{0}" -f $s.Pending)
        }
    }
    catch { }

    # ---- 3. 应用（七态计数，只报「有主数据」和「已装」两个数） ----
    try {
        $sum = Get-ETSoftwareStateSummary
        $total = @($sum.Rows | Where-Object { $null -ne $_ }).Count
        $effective = 0
        $downloaded = 0
        foreach ($r in @($sum.Rows | Where-Object { $null -ne $_ })) {
            if ([int]$r.StateOrder -ge 7) { $effective++ }
            elseif ([int]$r.StateOrder -ge 2) { $downloaded++ }
        }
        if ($ui.TxtInfoApp) {
            $ui.TxtInfoApp.Text = if ($total -eq 0) { '应用：无主数据' }
            else { ("应用：{0} 个 · 已生效 {1} · 有包未生效 {2}" -f $total, $effective, $downloaded) }
        }
    }
    catch { }
}

# ================================================================ 12.7 页签零 · 信息区：内嵌铭牌卡
function Update-InfoPlateCard {
    <#
      .SYNOPSIS 刷新信息区左上角【内嵌铭牌卡】（与 Start-ETPlate.ps1 左侧铭牌同版式同源）。
      .DESCRIPTION
        与铭牌 Update-PlateInfo 一一对应，三件事：
          1) 取本机业务 IP（Get-ETBusinessIp，ET.Identity 导出），写入 IP 行；
             取不到写「(未获取)」—— 与铭牌同一措辞，不写空串（空串看着像卡死）。
          2) 由 IP 反查三个编号（Resolve-ETPlateInfo）；
             【三编号未全部命中就整块退示例值】—— 绝不允许把两个真编号和一个示例值
             混排在一张卡上（真假混排比全示例更容易误读，铭牌同此规矩）。
          3) 三态上色：结论只能来自 Get-ETStateVerdict（§8.2 规则表），
             颜色取值与铭牌 $Script:PlateState 逐条一致。

        【绝不另写一套判定】这里如果内联 if (Alarms -gt 0) ...，就会与左侧铭牌
        出现「左边红、右边绿」，即缺陷 D-10 复发。
    #>
    try {
        # ---- 1. IP ----
        $ip = ''
        try {
            $b = Get-ETBusinessIp
            if ($b -and $b.Addresses) { $ip = @($b.Addresses)[0] }
        }
        catch { }
        if (-not $ip) { $ip = '(未获取)' }
        if ($ui.PlateIp) { $ui.PlateIp.Text = $ip }

        # ---- 2. 设备 / ET / MPC ----
        $plate = $null
        if ($ip -and $ip -ne '(未获取)') { $plate = Resolve-ETPlateInfo -Ip $ip }
        $fromSample = -not ($plate -and $plate.Complete)

        $equip = if ($fromSample) { $script:SamplePlate.Equip } else { $plate.EquipmentId }
        $et = if ($fromSample) { $script:SamplePlate.Et } else { $plate.EtCode }
        $mpc = if ($fromSample) { $script:SamplePlate.Mpc } else { $plate.MpcCode }

        if ($ui.PlateEquip) { $ui.PlateEquip.Text = $equip }
        if ($ui.PlateEt) { $ui.PlateEt.Text = $et }
        if ($ui.PlateMpc) { $ui.PlateMpc.Text = $mpc }

        # ---- 3. 抬头：未接入共享清单时标注「示例」（与左侧铭牌同一字样）----
        if ($ui.PlateTitle) {
            $ui.PlateTitle.Text = if ($fromSample) { 'ET 工作台 · 示例' } else { 'ET 工作台' }
        }

        # ---- 4. 三态：整高灯条 / 胶囊圆点 / 胶囊文字 / 胶囊 ToolTip ----
        $v = $null
        try { $v = Get-ETStateVerdict } catch { $v = $null }
        if ($v) {
            $color = switch ("$($v.State)") {
                'Alarm' { '#FFE5533D' }
                'Warn' { '#FFF2C94C' }
                'Normal' { '#FF2FBF71' }
                default { '#FF8A94A6' }
            }
            $brush = ConvertTo-ETBrush $color
            $tip = '铭牌状态：{0}（{1}）' -f (Get-ETStateColorText -State $v.State), $(if ($v.RuleId) { "命中规则 {0}：{1}" -f $v.RuleId, $v.Reason } else { $v.Reason })

            if ($ui.PlateStrip) { $ui.PlateStrip.Background = $brush }
            if ($ui.PlateStatusDot) { $ui.PlateStatusDot.Fill = $brush }
            if ($ui.PlateStatusText) { $ui.PlateStatusText.Text = (Get-ETStateColorText -State $v.State) }
            if ($ui.PlateStatusPill) { $ui.PlateStatusPill.ToolTip = $tip }
        }

        # ---- 5. 页脚：版本 + 刷新时刻（与铭牌页脚同两项）----
        if ($ui.PlateVer) { $ui.PlateVer.Text = ('铭牌 v{0}' -f $script:PlateCardVersion) }
        if ($ui.PlateUpdated) { $ui.PlateUpdated.Text = ('更新 ' + (Get-Date -Format 'HH:mm')) }
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
                # 检测完，三态可能变了 —— 状态灯、信息区、分类汇总一起刷新，
                # 否则会出现「列表说有告警、状态灯还是绿的」这种当场自相矛盾。
                Update-StatusBadgeColor
                Update-InfoSummary
                Update-InfoPlateCard
                Update-AlarmSummary
                Update-StatusBar
            }
            catch { Set-Output -Control $ui.TxtHealthOut -Text ("健康检测失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 13. 页签 4 · 主数据（E-01）
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

# ================================================================ 14.5 页签 3 · 功能设置：开关与一键更新（E-04 / E-06）
#
# 【为什么另开 settings.json 而不是改 workstation.json】
#   Config/workstation.json 的【键名】被 docs/interface-contract.md:52 冻结，
#   而且它属于「整机契约」，不是「用户随手点的开关」。所以这里用一个新文件
#   Config/settings.json 存「本地覆盖」——键名独立、可随时删掉回到默认，
#   删掉这个文件工作台照常启动（全部回落默认值）。
#
# 【三个开关的真实语义 —— 现场最容易被误解的地方，所以逐条写死】
#   1) 允许上报：只开关 ET.Outbox 是否把事件【发布到共享 Upload】。
#      关掉 ≠ 不采集、≠ 不落盘。关掉期间事件仍然写本地 Outbox，
#      重新打开后会补传（本地队列是唯一真相，共享只是投递目标）。
#   2) 自动检查更新：只针对【工作台自身】(E-06 / ET.Update)，绝不含业务软件。
#      它决定启动时是否顺手看一眼有没有新版工作台，看一眼不动手。
#   3) 生产软件一键更新：下载 + 校验，**止步于「已下载」**。
#      红线 F-9 / 约束 C-6：已下载 ≠ 已安装 ≠ 已生效。
#      本按钮【绝不】结束、重启、覆盖任何正在运行的业务程序（红线 F-1/F-2）。
$script:SettingsFile = $null

function Get-ETSettingsPath {
    if (-not $script:SettingsFile) {
        $root = ''
        # Get-ETProgramRoot 是 ET.Core 的【导出】函数；Get-ETConfigFilePath 没有导出，
        # 所以这里不能直接复用它，只能自己拼 Config 目录（与 Core 拼法一致）。
        try { $root = "$(Get-ETProgramRoot)" } catch { }
        if (-not $root) { $root = $Script:Root }
        $script:SettingsFile = Join-Path (Join-Path $root 'Config') 'settings.json'
    }
    return $script:SettingsFile
}

function Get-ETSetting {
    <# .SYNOPSIS 读一个本地开关（缺文件/缺键/解析失败一律回默认值，绝不抛）。 #>
    param([Parameter(Mandatory)][string]$Name, $Default = $null)
    try {
        $file = Get-ETSettingsPath
        if (-not (Test-Path -LiteralPath $file)) { return $Default }
        $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $obj = $raw | ConvertFrom-Json
        $p = $obj.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($null -eq $p) { return $Default }
        return $p.Value
    }
    catch { return $Default }
}

function Set-ETSetting {
    <# .SYNOPSIS 写一个本地开关（读-改-写，原子落盘 C-4，单写者 C-7）。 #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowNull()]$Value)
    try {
        $file = Get-ETSettingsPath
        $obj = [ordered]@{}
        if (Test-Path -LiteralPath $file) {
            try {
                $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $old = $raw | ConvertFrom-Json
                    foreach ($p in $old.PSObject.Properties) { $obj[$p.Name] = $p.Value }
                }
            }
            catch { }
        }
        $obj[$Name] = $Value
        $obj['UpdatedAt'] = (Get-Date).ToString('o')
        Write-ETJsonAtomic -LiteralPath $file -InputObject $obj | Out-Null
        return $true
    }
    catch {
        Write-Boot ("设置写入失败：{0}" -f $_.Exception.Message) 'Warn'
        return $false
    }
}

function Get-ETWorkstationSetting {
    <# .SYNOPSIS 读 workstation.json 的某个节点/键，取不到返回 $null（不抛）。 #>
    param([string]$Section, [string]$Key)
    try {
        $cfg = Get-ETConfig
        $node = $cfg.$Section
        if ($null -eq $node) { return $null }
        return $node.$Key
    }
    catch { return $null }
}

# ---- 页签 3 · 本机偏好：日志级别 / 保留天数 / 界面字号 / 启动桌面模式 / 启动命令行只读显示 ----
$script:ETLogLevels = @('Trace', 'Debug', 'Info', 'Warn', 'Error')

# 界面字号档位。现场分辨率【多种都有，按最矮的适配】（锁定决策 ⑥）⇒ 默认给「标准」，
# 最矮的分辨率上现场可自行调到「大字 / 超大」，不必改脚本、不必动系统缩放。
# 只放大工作台自身窗口的继承字号：不修改系统 DPI / 分辨率，不影响任何业务软件。
# 另外说明（诚实口径）：本窗口大量文字在样式里已写死 FontSize，那些不受这里影响 ——
# 所以要「全部放大」需要先把样式里的字号改成相对值，这属于界面改造，登记为 T-31 的一部分。
$script:ETUiScales = @(
    [pscustomobject]@{ Key = 'Compact'; Label = '紧凑（100%）'; Factor = 1.00 }
    [pscustomobject]@{ Key = 'Normal'; Label = '标准（115%）'; Factor = 1.15 }
    [pscustomobject]@{ Key = 'Large'; Label = '大字（130%）'; Factor = 1.30 }
    [pscustomobject]@{ Key = 'XLarge'; Label = '超大（145%）'; Factor = 1.45 }
)
$script:ETBaseFontSize = 13   # 与 MainWindow.xaml 的 Window.FontSize 同一口径

function Get-ETUiScaleEntry {
    <# .SYNOPSIS 按 Key 取档位对象；Key 不在表内一律回「标准」档（不抛、不猜）。 #>
    param([string]$Key)
    foreach ($s in $script:ETUiScales) { if ($s.Key -eq $Key) { return $s } }
    foreach ($s in $script:ETUiScales) { if ($s.Key -eq 'Normal') { return $s } }
    return $null
}

function Get-ETUiScaleKey {
    <# .SYNOPSIS 当前生效的界面字号档位 Key（settings.json → 缺省 Normal）。 #>
    $k = "$(Get-ETSetting -Name 'UiScale' -Default '')"
    if (-not $k) { return 'Normal' }
    if ($null -eq (Get-ETUiScaleEntry -Key $k)) { return 'Normal' }
    return $k
}

function Apply-UiScale {
    <#
      .SYNOPSIS 把界面字号档位应用到窗口的继承字号。
      .DESCRIPTION
        只设置 Window.FontSize（未被样式写死字号的控件会跟着变），
        并顺带把默认按钮/输入框的最小高度拉开，避免放大后文字被裁。
        不写注册表、不改系统缩放、不影响其他进程 —— 与红线 F-6（改其他进程）无关。
    #>
    try {
        $key = Get-ETUiScaleKey
        $entry = Get-ETUiScaleEntry -Key $key
        if ($null -eq $entry) { return }
        $size = [double]$script:ETBaseFontSize * [double]$entry.Factor
        $window.FontSize = $size
        if ($ui.TxtUiScaleNote) {
            $ui.TxtUiScaleNote.Text = ('当前：{0}。只作用于未在样式里写死字号的文字；表格与顶栏字体固定。' -f $entry.Label)
        }
        try { $window.UpdateLayout() } catch { }
    }
    catch { }
}

function Update-PreferenceView {
    <#
      .SYNOPSIS 用 settings.json（本地覆盖）→ workstation.json（默认）回填偏好控件。
      .DESCRIPTION
        三级回落，全部走 Get-ETSetting 的「取不到不抛」语义：
          settings.json 有值 → 用它；否则 → workstation.json 的 Ui.LogLevel / Ui.LogRetentionDays；
          再没有 → 脚本内默认。
        这样「删掉 settings.json」就等价于「回到出厂默认」，现场可以放心删。
    #>
    try {
        if ($ui.CmbLogLevel) {
            if (-not $ui.CmbLogLevel.ItemsSource) { $ui.CmbLogLevel.ItemsSource = $script:ETLogLevels }
            $lvl = "$(Get-ETSetting -Name 'LogLevel' -Default '')"
            if (-not $lvl) { $lvl = "$(Get-ETWorkstationSetting -Section 'Ui' -Key 'LogLevel')" }
            if (-not $lvl) { $lvl = 'Info' }
            if ($script:ETLogLevels -contains $lvl) { $ui.CmbLogLevel.SelectedItem = $lvl }
            else { $ui.CmbLogLevel.SelectedItem = 'Info' }
        }
        if ($ui.TxtLogRetentionDays) {
            $d = Get-ETSetting -Name 'LogRetentionDays' -Default $null
            if ($null -eq $d) { $d = Get-ETWorkstationSetting -Section 'Ui' -Key 'LogRetentionDays' }
            if ($null -eq $d) { $d = 30 }
            $ui.TxtLogRetentionDays.Text = "$d"
        }
        if ($ui.ChkStartFullScreen) {
            $fs = Get-ETSetting -Name 'StartFullScreen' -Default $null
            if ($null -eq $fs) { $fs = $true }   # 档位 3：现场默认全屏桌面模式（决策 ⑤）
            $ui.ChkStartFullScreen.IsChecked = [bool]$fs
        }
        if ($ui.CmbUiScale) {
            # 用「显示文字」而不是对象本身绑定：ComboBox 里塞 pscustomobject 会在
            # 未设 DisplayMemberPath 时显示成类型名，现场看不懂。
            $labels = @($script:ETUiScales | ForEach-Object { $_.Label })
            if (-not $ui.CmbUiScale.ItemsSource) { $ui.CmbUiScale.ItemsSource = $labels }
            $idx = 0
            for ($i = 0; $i -lt $script:ETUiScales.Count; $i++) {
                if ($script:ETUiScales[$i].Key -eq (Get-ETUiScaleKey)) { $idx = $i; break }
            }
            $ui.CmbUiScale.SelectedIndex = $idx
        }
    }
    catch { }
}

function Update-StartupHint {
    <# .SYNOPSIS 只读显示本机的启动命令行（满足 N-22：-Console 调试入口必须可见）。 #>
    if (-not $ui.TxtStartupCommand) { return }
    try {
        $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        $cmd = '{0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $exe, (Join-Path $Script:Root 'Start-ETWorkbench.ps1')
        $ui.TxtStartupCommand.Text = ('启动命令：{0}' -f $cmd)
    }
    catch { $ui.TxtStartupCommand.Text = '' }
}

function Update-ScheduleNote {
    <#
      .SYNOPSIS 只读展示采集/上报节奏，并诚实说明改这里不起作用。
      .DESCRIPTION
        现场最容易被「界面上有个数字」误导：以为改了它任务就会变快/变慢。
        实际节奏来自 workstation.json 的 Health.CollectIntervalMinutes /
        Health.OutboxPublishIntervalMinutes，而这两个值只在注册计划任务时被读取
        （Tasks/Register-ETTasks.ps1）。所以此处【故意不做成可编辑控件】，
        只显示当前配置值 + 一句说明，避免制造假开关（登记 T-38）。
    #>
    if (-not $ui.TxtScheduleNote) { return }
    try {
        $c = ''
        $p = ''
        try { $c = "$(Get-ETWorkstationSetting -Section 'Health' -Key 'CollectIntervalMinutes')" } catch { }
        try { $p = "$(Get-ETWorkstationSetting -Section 'Health' -Key 'OutboxPublishIntervalMinutes')" } catch { }
        if (-not $c) { $c = '(未配置)' }
        if (-not $p) { $p = '(未配置)' }

        $tasks = @()
        try {
            $tasks = @(Get-ScheduledTask -TaskName 'ET-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TaskName)
        }
        catch { }
        $taskText = if ($tasks.Count -gt 0) { ($tasks -join '、') } else { '未注册' }

        # 注意：这里先把两头拼好再 -f，避免 + 与 -f 的优先级歧义（PS 5.1 下 -f 绑定更紧）。
        $head = '计划任务节奏（只读）：健康采集每 {0} 分钟，事件上报每 {1} 分钟；本机已注册任务：{2}。'
        $tail = '说明：实际节奏由 Config/workstation.json 的 Health 节 + Tasks/Register-ETTasks.ps1 注册的计划任务决定，改本页任何内容都不会改变任务节奏。'
        $head = $head -f $c, $p, $taskText
        $ui.TxtScheduleNote.Text = ($head + [Environment]::NewLine + $tail)
    }
    catch { }
}

function Load-SettingSwitches {
    <# .SYNOPSIS 用 settings.json 回填开关与偏好的初始状态（启动时调用一次）。 #>
    try {
        if ($ui.ChkLogUpload) { $ui.ChkLogUpload.IsChecked = [bool](Get-ETSetting -Name 'LogUploadEnabled' -Default $true) }
        if ($ui.ChkAutoUpdate) { $ui.ChkAutoUpdate.IsChecked = [bool](Get-ETSetting -Name 'AutoCheckUpdateEnabled' -Default $false) }
    }
    catch { }

    Update-PreferenceView
    Update-StartupHint
    Update-ScheduleNote
    Apply-UiScale

    # 启动自检：若开着「自动检查更新」，顺手看一眼（只报告，不安装）。
    try {
        if ($ui.ChkAutoUpdate -and $ui.ChkAutoUpdate.IsChecked -and $ui.TxtSettingOut) {
            $r = Test-ETUpdateAvailable
            if ($r.AvailableVersion) {
                Set-Output -Control $ui.TxtSettingOut -Text ("启动检查：发现工作台新版本 {0}（当前 {1}）。" -f $r.AvailableVersion, $r.CurrentVersion)
            }
        }
    }
    catch { }
}

# ---- 开关 1：允许上报 ----
if ($ui.ChkLogUpload) {
    $ui.ChkLogUpload.Add_Click({
            try {
                $on = [bool]$ui.ChkLogUpload.IsChecked
                $null = Set-ETSetting -Name 'LogUploadEnabled' -Value $on
                $sum = Get-ETOutboxSummary
                $msg = if ($on) {
                    "已开启上报：本地积压 {0} 条将在下一轮任务中投递到共享 Upload。" -f $sum.Pending
                }
                else {
                    "已暂停上报：事件仍会照常采集并写入本地 Outbox（当前积压 {0} 条），不丢数据；重新打开后会补传。" -f $sum.Pending
                }
                Set-Output -Control $ui.TxtSettingOut -Text $msg
            }
            catch { Set-Output -Control $ui.TxtSettingOut -Text ("开关保存失败：{0}" -f $_.Exception.Message) }
        })
}

# ---- 开关 2：自动检查工作台自身更新 ----
if ($ui.ChkAutoUpdate) {
    $ui.ChkAutoUpdate.Add_Click({
            try {
                $on = [bool]$ui.ChkAutoUpdate.IsChecked
                $null = Set-ETSetting -Name 'AutoCheckUpdateEnabled' -Value $on
                Set-Output -Control $ui.TxtSettingOut -Text $(if ($on) {
                        '已开启：启动时自动检查【工作台自身】是否有新版本（只提示，不自动安装）。'
                    }
                    else { '已关闭：启动时不再自动检查工作台自身更新。' })
            }
            catch { Set-Output -Control $ui.TxtSettingOut -Text ("开关保存失败：{0}" -f $_.Exception.Message) }
        })
}

# ---- 一键更新：下载 + 校验，止步于「已下载」 ----
# 实现说明：没有「一次下载全部」的模块函数，也不新增任何导出函数
# （ET.Core / ET.Transfer 等模块的导出签名由 docs/interface-contract.md 冻结）。
# 所以这里在主窗口里循环调 Invoke-ETDownload —— 它只接受【标识符】
# （ApplicationId + Version，约束 C-3），不接受任何路径（红线 F-8）。
# 约束 C-7 的「同一时刻只允许 1 个下载」由 Invoke-ETDownload 内部保证，
# 因此这里是【串行】循环，不并行、不起后台任务。
if ($ui.BtnOneKeyUpdate) {
    $ui.BtnOneKeyUpdate.Add_Click({
            try {
                Set-Output -Control $ui.TxtSettingOut -Text '一键更新：正在统计需要下载的生产软件……'
                # 切到【应用区】页：卡片上的进度/状态才看得见（不再内联裸数字，见 §6.5）
                [void](Select-ETTab '应用区')

                $sum = Get-ETSoftwareStateSummary
                # 只挑「有主数据、但本机还没拿到包」的行（七态 Order < 2）。
                # Order >= 2 表示已下载/已部署/运行中/已生效 —— 不去碰它（红线 F-2）。
                $targets = @()
                foreach ($r in @($sum.Rows | Where-Object { $null -ne $_ })) {
                    $order = 0
                    try { $order = [int]$r.StateOrder } catch { $order = 0 }
                    if ($order -lt 2) { $targets += $r }
                }

                if ($targets.Count -eq 0) {
                    Set-Output -Control $ui.TxtSettingOut -Text ("没有需要下载的软件（共 {0} 条主数据，均已就位或缺少批准版本）。" -f @($sum.Rows).Count)
                    return
                }

                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine(("共 {0} 项需要下载，串行执行（约束 C-7）：" -f $targets.Count))
                $ok = 0; $skip = 0; $fail = 0
                foreach ($t in $targets) {
                    $aid = ''; $ver = ''
                    try { $aid = "$($t.ApplicationId)" } catch { }
                    try { $ver = "$($t.ApprovedVersion)" } catch { }
                    if (-not $ver) { try { $ver = "$($t.Version)" } catch { } }

                    if (-not $aid -or -not $ver) {
                        $fail++
                        [void]$sb.AppendLine(("  [跳过] {0}：缺少应用编号或批准版本，不猜测（约束 C-6）" -f $(if ($aid) { $aid } else { '(无编号)' })))
                        continue
                    }

                    [void]$sb.AppendLine(("  → {0} {1} …" -f $aid, $ver))
                    Set-Output -Control $ui.TxtSettingOut -Text $sb.ToString()

                    try {
                        $res = Invoke-ETDownload -ApplicationId $aid -Version $ver
                        switch ("$($res.Status)") {
                            'AlreadyDownloaded' { $skip++; [void]$sb.AppendLine(("    已就位（校验通过），跳过" )) }
                            default {
                                if ($res.Ok) { $ok++; [void]$sb.AppendLine(("    完成：{0} 个文件，校验通过 {1}" -f $res.FileCount, $res.Verified)) }
                                else {
                                    $fail++
                                    [void]$sb.AppendLine(("    失败：{0}" -f $(if ($res.Errors) { ($res.Errors -join '；') } else { $res.Status })))
                                }
                            }
                        }
                    }
                    catch {
                        $fail++
                        [void]$sb.AppendLine(("    失败：{0}" -f $_.Exception.Message))
                    }
                    Set-Output -Control $ui.TxtSettingOut -Text $sb.ToString()
                }

                [void]$sb.AppendLine('')
                [void]$sb.AppendLine(("结果：新下载 {0}，已就位 {1}，失败 {2}" -f $ok, $skip, $fail))
                [void]$sb.AppendLine('注意：下载完成 = 文件已就位，不代表已安装 / 已生效（约束 C-6）。')
                [void]$sb.AppendLine('安装与生效由现场按既定流程执行；工作台不会自动结束或覆盖任何正在运行的程序（红线 F-1/F-2）。')
                Set-Output -Control $ui.TxtSettingOut -Text $sb.ToString()
                Update-StatusBar
                Update-SoftwareGrid
                Update-InfoSummary
                Update-InfoPlateCard
            }
            catch { Set-Output -Control $ui.TxtSettingOut -Text ("一键更新失败：{0}" -f $_.Exception.Message) }
        })
}

# ---- 打开数据根目录（只读入口，不接受任何外部传入路径 —— 约束 C-3 / 红线 F-8） ----
if ($ui.BtnOpenDataRoot) {
    $ui.BtnOpenDataRoot.Add_Click({
            try {
                $root = Get-ETDataRoot
                if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
                Start-Process -FilePath 'explorer.exe' -ArgumentList @($root) | Out-Null
                Set-Output -Control $ui.TxtSettingOut -Text ("已打开：{0}" -f $root)
            }
            catch { Set-Output -Control $ui.TxtSettingOut -Text ("打开目录失败：{0}" -f $_.Exception.Message) }
        })
}

# ---- 保存本机偏好（日志级别 / 保留天数 / 启动桌面模式） ----
# 校验口径：只接受白名单级别与正整数天数，任何非法输入都【不写入】并明确报错，
# 不做「猜用户想填什么」的静默纠正（约束 C-3 的同一精神：不替现场做决定）。
if ($ui.BtnSavePreferences) {
    $ui.BtnSavePreferences.Add_Click({
            try {
                $errors = @()

                $lvl = ''
                if ($ui.CmbLogLevel) { $lvl = "$($ui.CmbLogLevel.SelectedItem)" }
                if ($lvl -and -not ($script:ETLogLevels -contains $lvl)) {
                    $errors += ("日志级别不在允许范围（{0}）" -f ($script:ETLogLevels -join '/'))
                }

                $days = $null
                if ($ui.TxtLogRetentionDays) {
                    $txt = "$($ui.TxtLogRetentionDays.Text)".Trim()
                    if ($txt) {
                        $parsed = 0
                        if (-not [int]::TryParse($txt, [ref]$parsed)) { $errors += '日志保留天数必须是整数' }
                        elseif ($parsed -lt 1 -or $parsed -gt 3650) { $errors += '日志保留天数须在 1..3650 之间' }
                        else { $days = $parsed }
                    }
                }

                if ($errors.Count -gt 0) {
                    Set-Output -Control $ui.TxtSettingOut -Text ("未保存，存在以下问题：" + [Environment]::NewLine + (($errors | ForEach-Object { '  · ' + $_ }) -join [Environment]::NewLine))
                    return
                }

                # 界面字号：下拉选中的是「显示文字」，反查回 Key 再落盘（存 Key 不存中文标签）。
                $scaleKey = ''
                if ($ui.CmbUiScale) {
                    $selLabel = "$($ui.CmbUiScale.SelectedItem)"
                    foreach ($s in $script:ETUiScales) { if ($s.Label -eq $selLabel) { $scaleKey = $s.Key; break } }
                    if (-not $scaleKey) { $scaleKey = 'Normal' }
                }

                $okAll = $true
                if ($lvl) { $okAll = (Set-ETSetting -Name 'LogLevel' -Value $lvl) -and $okAll }
                if ($null -ne $days) { $okAll = (Set-ETSetting -Name 'LogRetentionDays' -Value $days) -and $okAll }
                if ($scaleKey) { $okAll = (Set-ETSetting -Name 'UiScale' -Value $scaleKey) -and $okAll }
                if ($ui.ChkStartFullScreen) {
                    $okAll = (Set-ETSetting -Name 'StartFullScreen' -Value ([bool]$ui.ChkStartFullScreen.IsChecked)) -and $okAll
                }

                if ($okAll) {
                    # 字号是「所见即所得」的，落盘后立即生效，不用重启。
                    if ($scaleKey) { Apply-UiScale }

                    $scaleLabel = ''
                    try { $scaleLabel = (Get-ETUiScaleEntry -Key $scaleKey).Label } catch { }

                    Set-Output -Control $ui.TxtSettingOut -Text @"
已保存到 Config/settings.json：
  日志级别      $lvl
  日志保留      $(if ($null -ne $days) { "$days 天" } else { '（未填写，沿用默认）' })
  界面字号      $scaleLabel
  启动桌面模式  $(if ($ui.ChkStartFullScreen -and $ui.ChkStartFullScreen.IsChecked) { '开' } else { '关' })

说明：这些是「本地覆盖」，默认值仍来自 Config/workstation.json（键名未被改动）。
界面字号保存后立即生效；日志级别/保留天数由日志写入方读取生效。
启动桌面模式在下次启动时生效，本次可继续用顶栏的「全屏 / 还原」按钮。
"@
                }
                else {
                    Set-Output -Control $ui.TxtSettingOut -Text '保存失败：写入 settings.json 时出错，已保留原文件。'
                }
            }
            catch { Set-Output -Control $ui.TxtSettingOut -Text ("保存失败：{0}" -f $_.Exception.Message) }
        })
}

# ================================================================ 15. 页签导航与窗口交互
# 页签路由契约（XAML 与脚本必须一致，改动这里要同批改 MainWindow.xaml）：
#   0 生产软件 / 1 警告提示 / 2 信息区 / 3 功能设置 / 4 主数据
# 旧的「抽屉式」主数据 / 关于 已改为页签，Set-Drawer 与其四个按钮一并删除。
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
            # 启动形态由本机偏好决定（StartFullScreen），不再无条件铺满。
            Initialize-ETStartupDesktopMode
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

# 键盘：F11 全屏 / Esc 回到【起始页】。不注册任何全局热键，不抢焦点（红线 F-4）。
# 注意：WS_EX_TOOLWINDOW 只把窗口移出 Alt+Tab，不会影响本窗口处于活动状态时的键盘输入；
# 若现场发现 F11 无效，用顶栏的「全屏 / 还原」按钮，功能完全等价。
# Esc 的语义已从「收抽屉」改为「回到起始页」—— 页签化之后，"取消当前导航"最自然的落点。
# 起始页现在是【信息区】（$script:TabHome），不再是「第 0 个页签」的隐含意思：
# 标题寻址 ⇒ 以后再调序，这里不用改。
$window.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::F11) { Toggle-FullScreen; $e.Handled = $true }
        elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) { [void](Select-ETTab $script:TabHome) }
    })

# ================================================================ 15.1 启动时刷新
$window.Add_Loaded({
        try {
            # 启动默认停在【信息区】。首个 TabItem 本来就是信息区（WPF 默认选中第 0 个），
            # 这里再显式选一次，是为了把「默认页 = 信息区」写成代码上的事实，
            # 避免以后有人调 TabItem 次序后【静默】改了启动落点。
            [void](Select-ETTab $script:TabHome)

            Update-StatusBar
            Update-DownloadTargets
            Update-SoftwareGrid
            Update-HealthGrid
            Update-Clock
            Update-FullScreenLabel
            # 三态颜色【不在这里判定】—— 判定只有一处，就是 §8.2 的规则表。
            # 旧版在这里内联了 if (Alarms>0) ... elseif (Pending>0) ...，
            # 漏掉「未接入共享清单 / 共享不可达 / 设备未识别」，会显示绿色，
            # 与铭牌的红灯直接矛盾（缺陷 D-10）。现在统一走 Get-ETStateVerdict。
            Update-StatusBadgeColor
            Update-InfoSummary
            Update-InfoPlateCard
            Update-AlarmSummary
            Load-SettingSwitches
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
# 注意顺序：SourceInitialized 已经调用过 Initialize-ETStartupDesktopMode，
# 这里只是「显示之前再兜一次」，保证即使 SourceInitialized 因异常没跑到也有正确形态。
try { Initialize-ETStartupDesktopMode } catch { }
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
