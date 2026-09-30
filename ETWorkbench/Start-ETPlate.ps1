<#
.SYNOPSIS
    Start-ETPlate —— ET 工作台【设备铭牌】（工作区左边缘常驻，垂直居中）。

.DESCRIPTION
    在工作区【左边缘、垂直居中】显示一块常驻的设备铭牌（316x248 竖版卡）。
    版式仿工业设备铭牌（沿用原 TrayBadge.xaml 的设计），内容：
      设备编号（大字） / ET / IP / MPC / 状态胶囊 / 三态灯条 / 页脚（版本 + 刷新时间）

    字段来源：
      IP               本机业务网卡 IP（Get-ETBusinessIp 自动获取）
      设备 / ET / MPC   用 IP 在共享清单（主数据 mappings.json 的 ByIpAddress）中反查；
                        清单不可用时回退到示例值（抬头显示「示例」）。
      铭牌版本         本铭牌自身版本号（$Script:PlateVersion），显示在页脚
      刷新时间         最后一次刷新的 HH:mm，显示在页脚右侧
      报警标识         三态：绿=正常 / 黄=警告 / 红=报警
                        判定规则集中在一张表里（见 $Script:PlateRules），状态本身只有这三种。

    窗口语义（2026-09-29 决策，与主窗口一致）：
      · 无边框、不显示在任务栏、不参与 Alt+Tab
      · 不置顶（Topmost=False）—— 这是红线 F-4 的要求，也是刻意的桌面语义：
        业务软件永远盖在铭牌之上；要看铭牌先最小化业务软件
        （原 TrayBadge.xaml 是 Topmost=True，已按 F-4 改为 False，不可回退）
      · 主动沉到 Z 序最底层（HWND_BOTTOM），并在窗口激活/失活时重新沉底
      · 定位 = 左边缘 + 垂直居中，只在【启动时 / 显示参数变化时】计算，不做轮询跟随
        （显示器拔插 → 见 Add_DisplaySettingsChanged）

    交互：
      · 单击铭牌主体  -> 展开完整主窗口（Start-ETWorkbench.ps1）
      · 右键铭牌主体  -> 菜单（打开工作台 / 退出铭牌…）
      · 退出铭牌      -> 右键菜单 + 二次确认（防止误触直接关闭）
      · 每 30 秒自动刷新
      · 应急退出      -> 创建哨兵文件（见 Invoke-CheckStopSentinel），用于铭牌沉底后
                        右键菜单够不着的情况（例如业务软件全屏且不允许切出）

    调试：
      -PreviewState <Normal|Warn|Alarm>  强制显示某一状态颜色，跳过规则判定，用于现场校色 / 联调

    架构：铭牌是【独立常驻进程】，完整主窗口是另一个进程：
      - 关闭完整窗口，铭牌仍常驻
      - 铭牌关闭，不影响已打开的主窗口
      - 铭牌不再与主窗口做像素对齐（主窗口顶栏的 PlateSlot 已移除）

    设计约束：
      C-1  本文件含中文，必须 UTF-8 with BOM
      C-2  所有路径由 $PSScriptRoot 推导，禁止硬编码
      C-3  GUI 只传标识符（本铭牌不传任何路径去执行）
      F-4  不抢焦点 / 不置顶：本铭牌只改自身 Z 序为【最底层】，绝不置顶
      F-8  不开放端口 / 不建 HTTP Server
#>
[CmdletBinding()]
param(
    [string]$Version = '1.1.0',

    # 调试 / 校色用：强制铭牌显示某一状态颜色，跳过规则判定。留空 = 按规则判定。
    # 例：powershell -NoProfile -ExecutionPolicy Bypass -File .\ETWorkbench\Start-ETPlate.ps1 -PreviewState Alarm
    [ValidateSet('', 'Normal', 'Warn', 'Alarm')]
    [string]$PreviewState = '',

    # 诊断用：只摆好窗口与事件，不沉底（排查「窗口不见了」时用）
    [switch]$NoSink
)

# 本铭牌（PlateBar）自身版本号，显示在状态胶囊 ToolTip
$Script:PlateVersion = $Version
# 状态预览开关（'' = 按规则判定，见 $Script:PlateRules）
$Script:PreviewState = $PreviewState
# 是否沉底
$Script:NoSink = [bool]$NoSink

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Show-PlateFatal {
    param([string]$Message)
    try {
        [System.Windows.MessageBox]::Show($Message, 'ET 铭牌', 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Host ("[ET-Plate] 启动失败：{0}" -f $Message) -ForegroundColor Red
    }
}

try {
    # ================================================================ 0. 根路径（C-2）
    $Script:Root = $PSScriptRoot
    if (-not $Script:Root) { $Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

    # ================================================================ 1. 单实例保护：铭牌与主窗口都不能重复打开
    # 这里使用 Global 命名空间，确保从桌面启动、重复双击 .bat、以及从主窗口再次打开时，
    # 所有相关 PowerShell 进程都共享同一把锁，防止重复弹出多个标签/主窗口。
    #
    # ⚠ 这里曾经有过一个真实缺陷（本段注释存在的理由）：
    #   被拦住的分支里调用了 [System.Windows.MessageBox]::Show(...)，
    #   但 PresentationFramework 要到第 4 步才 Add-Type，此处的 MessageBox 会抛
    #   「找不到类型」→ 被下面的大 catch 吞掉 → 脚本【继续往下走】→ 又开了一块铭牌。
    #   这就是「标签启动个数限制不起作用」的真正原因。
    #   现在：被拦住时提示放在【自己的 try/catch】里，然后【无条件 exit 0】。
    $script:PlateMutex = $null
    $plateIsFirstInstance = $true
    try {
        $plateCreatedNew = $false
        $script:PlateMutex = New-Object System.Threading.Mutex($true, 'Global\ETWorkbench.Plate.SingleInstance', [ref]$plateCreatedNew)
        $plateIsFirstInstance = [bool]$plateCreatedNew
    }
    catch {
        # 互斥锁不可用（极少数权限受限环境）⇒ 退回进程命令行比对，仍要挡住重复打开。
        try {
            $plateOthers = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*Start-ETPlate.ps1*' })
            if ($plateOthers.Count -gt 0) { $plateIsFirstInstance = $false }
        }
        catch { }
        Write-Host ('[ET-Plate] 单实例保护降级（{0}）' -f $_.Exception.Message) -ForegroundColor Yellow
    }

    if (-not $plateIsFirstInstance) {
        # 先输出（无头/自动化场景也能看到），再弹提示。
        Write-Host '[ET-Plate] ET 设备铭牌已打开，不能重复打开。' -ForegroundColor Yellow
        # 只在真实交互桌面里弹模态提示：无桌面会话里 MessageBox 会一直等点击（挂死）。
        if ([System.Environment]::UserInteractive) {
            try {
                Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
                [System.Windows.MessageBox]::Show('ET 设备铭牌已打开，不能重复打开。', 'ET 铭牌', 'OK', 'Warning') | Out-Null
            }
            catch { }
        }
        exit 0
    }

    # 会话 0（无交互桌面）没有窗口可言，直接退出，别在无桌面环境里空转到超时。
    # 注意：这段必须在【单实例检查之后】—— 否则无桌面会话连测都测不到单实例逻辑。
    if (-not [System.Environment]::UserInteractive) {
        Write-Host '[ET-Plate] 当前为会话 0（无交互桌面），无需显示铭牌，已退出。'
        exit 0
    }

    # ================================================================ 2. 加载模块
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
        Import-Module $p -Force -ErrorAction Stop
    }

    # ================================================================ 2. 初始化数据根
    try { $null = Initialize-ETDataRoot }
    catch { throw ("本地数据根初始化失败：{0}" -f $_.Exception.Message) }

    # ================================================================ 3. Win32 辅助（定位 + 沉底）
    $Script:PlateWin32Ready = $false
    try {
        if (-not ('ETPlateNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ETPlateNative {
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
        $Script:PlateWin32Ready = $true
    }
    catch { $Script:PlateWin32Ready = $false }

    # ================================================================ 4. 加载铭牌界面
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $plateXamlPath = Join-Path $Script:Root 'UI\PlateBar.xaml'
    if (-not (Test-Path -LiteralPath $plateXamlPath)) { throw "缺少铭牌界面文件：$plateXamlPath" }

    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $plateXamlPath -Raw -Encoding UTF8))
    $Script:Plate = [Windows.Markup.XamlReader]::Load($reader)

    # 控件引用（XAML 命名元素；缺一个不致命，刷新时逐项判空）
    $Script:ui = @{
        RootBorder  = $Script:Plate.FindName('RootBorder')
        StatusStrip = $Script:Plate.FindName('StatusStrip')
        StatusDot   = $Script:Plate.FindName('StatusDot')
        TxtTitle    = $Script:Plate.FindName('TxtTitle')
        TxtStatus   = $Script:Plate.FindName('TxtStatus')
        TxtEquip    = $Script:Plate.FindName('TxtEquip')
        TxtEt       = $Script:Plate.FindName('TxtEt')
        TxtIp       = $Script:Plate.FindName('TxtIp')
        TxtMpc      = $Script:Plate.FindName('TxtMpc')
        TxtBadgeVer = $Script:Plate.FindName('TxtBadgeVer')
        TxtUpdated  = $Script:Plate.FindName('TxtUpdated')
        StatusPill  = $Script:Plate.FindName('StatusPill')
    }

    # 页脚版本号：与 -Version 参数同源（改 XAML 里的初始文案不影响这里）
    if ($Script:ui.TxtBadgeVer) { $Script:ui.TxtBadgeVer.Text = ('铭牌 v{0}' -f $Script:PlateVersion) }

    function Sync-PlatePosition {
        <#
          .SYNOPSIS 把铭牌摆到【工作区左边缘、垂直居中】（紧贴左边缘，无间隙）。
          .DESCRIPTION
            坐标用 SystemParameters.WorkArea（DIP，与 Window.Left/Top 同单位），
            与主窗口 Enter-ETDesktopMode 完全同一口径。
            WindowStyle=None ⇒ 客户区左上角就是窗口左上角，因此：
              Left = 工作区左边缘（不加偏移 ⇒ 铭牌紧贴屏幕左侧，无缝隙）
              Top  = 工作区上沿 + (工作区高 - 铭牌高) / 2   ⇒ 垂直居中
            高度优先取 ActualHeight（已布局完成的真实高度），未布局时退回 Height（XAML 声明值）。
            取整用 [math]::Round，避免半像素导致 DPI 缩放下的 1px 抖动。
        #>
        if (-not $Script:Plate) { return }
        try {
            $wa = [System.Windows.SystemParameters]::WorkArea
            $h = [double]$Script:Plate.ActualHeight
            if ($h -le 0) { $h = [double]$Script:Plate.Height }
            if ($h -le 0) { $h = 248.0 }
            $Script:Plate.Left = [double]$wa.Left
            $Script:Plate.Top = [double][math]::Round($wa.Top + (($wa.Height - $h) / 2))
        }
        catch { }
    }

    function Set-PlateWindowBottom {
        <#
          .SYNOPSIS 把铭牌沉到 Z 序最底层（保证业务软件盖在铭牌之上）。
          .DESCRIPTION
            HWND_BOTTOM 而不是 Topmost —— 红线 F-4 禁止置顶，沉底是它的反面。
            SWP_NOACTIVATE 保证沉底动作本身不抢焦点。
        #>
        if ($Script:NoSink) { return }
        if (-not $Script:PlateWin32Ready) { return }
        if ($Script:Sinking) { return }
        $Script:Sinking = $true
        try {
            $h = (New-Object System.Windows.Interop.WindowInteropHelper $Script:Plate).Handle
            if ($h -eq [IntPtr]::Zero) { return }
            [void][ETPlateNative]::SetWindowPos($h, [ETPlateNative]::HWND_BOTTOM, 0, 0, 0, 0,
                ([ETPlateNative]::SWP_NOMOVE -bor [ETPlateNative]::SWP_NOSIZE -bor [ETPlateNative]::SWP_NOACTIVATE))
        }
        catch { }
        finally { $Script:Sinking = $false }
    }

    # Handle 就绪后：加 WS_EX_TOOLWINDOW（不进 Alt+Tab）+ 摆位 + 沉底
    $Script:Plate.Add_SourceInitialized({
            try {
                if ($Script:PlateWin32Ready) {
                    $h = (New-Object System.Windows.Interop.WindowInteropHelper $Script:Plate).Handle
                    if ($h -ne [IntPtr]::Zero) {
                        $ex = [ETPlateNative]::GetWindowLongPtr($h, [ETPlateNative]::GWL_EXSTYLE).ToInt64()
                        [void][ETPlateNative]::SetWindowLongPtr($h, [ETPlateNative]::GWL_EXSTYLE,
                            [IntPtr]($ex -bor [ETPlateNative]::WS_EX_TOOLWINDOW))
                    }
                }
                Sync-PlatePosition
                Set-PlateWindowBottom
            }
            catch { }
        })

    # 激活 / 失活都重新沉底：「无论活动与否都在最低层」
    $Script:Plate.Add_Activated({ try { Set-PlateWindowBottom } catch { } })
    $Script:Plate.Add_Deactivated({ try { Set-PlateWindowBottom } catch { } })

    # 首次布局完成后 ActualHeight 才是真实高度（垂直居中要靠它）。
    # 只同步这一次，后面高度不会变（ResizeMode=NoResize）。
    $Script:Plate.Add_SizeChanged({ try { Sync-PlatePosition } catch { } })

    # 显示器拔插 / 分辨率变化 ⇒ 工作区尺寸会变，垂直居中位置随之改变。
    # WPF 的 SystemParameters 变化通知在 PowerShell 里不好接（静态事件 + 需要消息泵），
    # 所以改成由 30 秒定时器顺带重算坐标（见 §10）——最多迟 30 秒，代价为零。
    # 对应待办 B-07 / T-06。

    # ================================================================ 5. 铭牌字段解析（IP -> 设备/ET/MPC）
    # 清单不可用（共享未配置 / 未接入）时显示示例值，并在抬头标注「示例」。
    $Script:SamplePlate = @{ Equip = 'W098'; Et = 'ZET1025'; Mpc = '096' }

    # ================================================================ 6. 报警标识（三态）状态模型 + 规则表
    # 状态【只有三种】，颜色与语义一一对应：
    #     正常 Normal -> 绿  #FF2FBF71
    #     警告 Warn   -> 黄  #FFF2C94C
    #     报警 Alarm  -> 红  #FFE5533D
    # 判定优先级：报警 Alarm > 警告 Warn > 正常 Normal（报警压过警告）。
    # 「不确定」的情形（未接入共享清单、设备未识别）一律归入【报警】，绝不冒充正常。
    $Script:PlateState = @{
        Normal = @{ Key = 'Normal'; Text = '正常'; Color = '#FF2FBF71' }
        Warn   = @{ Key = 'Warn';   Text = '警告'; Color = '#FFF2C94C' }
        Alarm  = @{ Key = 'Alarm';  Text = '报警'; Color = '#FFE5533D' }
    }

    # ---- 判定规则表【占位版：警告 / 报警的具体规则待业务确认后替换】----------
    # 约定：
    #   1) Test / Reason 都是脚本块，执行时按位置传入 $S = Get-ETAlarmState 的采集结果。
    #   2) 判定顺序 = 先跑 Alarm 组，再跑 Warn 组；组内按声明顺序，命中第一条即定格。
    #   3) 两个脚本块都只读 $S，不写任何状态，保证同一份采集结果判定结果稳定。
    #   4) 要改阈值 / 加条目 / 换语义，只动这张表，不必改 Set-ETPlateStatus。
    #   5) 字段：Id 规则号 / State 归属状态(Normal|Warn|Alarm) / Test 命中条件 / Reason 原因文案。
    $Script:PlateRules = @(
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

    function Get-ETFirstPlateValue {
        <# .SYNOPSIS 从对象中按候选字段名取第一个非空字符串（无匹配字段名则返回空串）。 #>
        param([AllowNull()]$InputObject, [string[]]$Names)        if ($null -eq $InputObject) { return '' }
        foreach ($n in $Names) {
            if (Test-ETObjectHasProperty -InputObject $InputObject -Name $n) {
                $v = "$($InputObject.$n)".Trim()
                if ($v) { return $v }
            }
        }
        return ''
    }

    function Resolve-ETPlate {
        <#
          .SYNOPSIS 由本机 IP 反查铭牌三个编号（设备 / ET / MPC）。
          .DESCRIPTION
            来源 1：主数据 mappings.json 的 ByIpAddress[IP]。
                    值可能是纯字符串（就是设备编号，如 "EQ-0001"），也可能是对象（含各编号字段）。
            来源 2：主数据 equipment.json，用 EquipmentId 补全缺失的 ET / MPC。
            Complete = 三个编号全部拿到，否则整块退回示例值（避免真假混排误导现场）。
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
                        $out.EquipmentId = Get-ETFirstPlateValue -InputObject $hit -Names @('EquipmentId', 'equipmentId', '设备', 'DeviceNo', 'DeviceId', 'Code')
                        $out.EtCode      = Get-ETFirstPlateValue -InputObject $hit -Names @('EtCode', 'ET', 'et', 'EtId', 'EtNo')
                        $out.MpcCode     = Get-ETFirstPlateValue -InputObject $hit -Names @('MpcCode', 'MPC', 'mpc', 'Mpc', 'MpcNo')
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
                    if (-not $out.EtCode) { $out.EtCode = Get-ETFirstPlateValue -InputObject $e -Names @('EtCode', 'ET', 'et', 'EtId', 'EtNo') }
                    if (-not $out.MpcCode) { $out.MpcCode = Get-ETFirstPlateValue -InputObject $e -Names @('MpcCode', 'MPC', 'mpc', 'Mpc', 'MpcNo') }
                    break
                }
            }
            catch { }
        }

        $out.Complete = [bool]($out.EquipmentId -and $out.EtCode -and $out.MpcCode)
        return $out
    }

    # ================================================================ 7. 刷新铭牌信息
    function Get-ETAlarmState {
        <#
          .SYNOPSIS 采集状态判定的原始依据（供 $Script:PlateRules 消费，本函数不做任何状态判定）。
          .OUTPUTS    Hashtable { FromSample; Identified; Configured; Reachable; Pending; Alarms; Unknowns }
          .PARAMETER FromSample 铭牌当前显示的是示例值（未接入共享清单）。
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

    function Set-ETPlateStatus {
        <#
          .SYNOPSIS 报警标识：三态唯一映射 —— 绿=正常 / 黄=警告 / 红=报警。
          .DESCRIPTION
            状态判定与上色分离：
              判定 —— 全部委托给 $Script:PlateRules（先 Alarm 组、再 Warn 组，命中即定格，全不中=正常）。
              上色 —— 本函数只做三件事：整高灯条背景、状态胶囊圆点、胶囊文字 + ToolTip。
            规则要改，只改 $Script:PlateRules 那张表。
          .PARAMETER State Get-ETAlarmState 采集到的依据对象。
        #>
        param($State)
        try {
            # ---------- 1. 定状态：调试预览 > 规则匹配（报警优先，其次警告）> 正常 ----------
            $hit = $null
            if (-not $Script:PreviewState) {
                foreach ($want in @('Alarm', 'Warn')) {
                    foreach ($r in $Script:PlateRules) {
                        if ([string]$r.State -ne $want) { continue }
                        $ok = $false
                        try { $ok = [bool](& $r.Test $State) } catch { $ok = $false }
                        if ($ok) { $hit = $r; break }
                    }
                    if ($hit) { break }
                }
            }

            if ($Script:PreviewState) {
                $key = $Script:PreviewState
                $reason = '调试预览（-PreviewState），未按规则判定'
            }
            elseif ($hit) {
                $key = [string]$hit.State
                $why = ''
                try { $why = [string](& $hit.Reason $State) } catch { $why = '' }
                $reason = '命中规则 {0}：{1}' -f $hit.Id, $why
            }
            else {
                $key = 'Normal'
                $reason = '未命中任何规则'
            }

            $style = $Script:PlateState[$key]
            if (-not $style) { $style = $Script:PlateState['Normal'] }

            # ---------- 2. 上色（唯一三处：灯条 / 圆点 / 文字） ----------
            $color = [string]$style.Color
            $tip = '铭牌状态：{0}（{1}）' -f $style.Text, $reason

            $conv = New-Object System.Windows.Media.BrushConverter
            $brush = $conv.ConvertFromString($color)
            if ($Script:ui.StatusStrip) { $Script:ui.StatusStrip.Background = $brush }
            if ($Script:ui.StatusDot) { $Script:ui.StatusDot.Fill = $brush }
            if ($Script:ui.TxtStatus) { $Script:ui.TxtStatus.Text = [string]$style.Text }
            # 状态胶囊的 ToolTip 单独挂：可以单独悬停问「为什么是这个颜色」，不必悬停整块铭牌
            if ($Script:ui.StatusPill) { $Script:ui.StatusPill.ToolTip = $tip }
            # RootBorder 的 ToolTip 每次刷新都会被重写 ⇒ 交互提示必须一起带上
            # （否则 XAML 里写的「单击展开工作台 · 右键更多操作」会在首次刷新后被抹掉）
            if ($Script:ui.RootBorder) {
                $Script:ui.RootBorder.ToolTip = ($tip + [Environment]::NewLine + '单击展开工作台 · 右键更多操作')
            }
        }
        catch { }
    }

    function Update-PlateInfo {
        try {
            # --- IP：自动获取本机业务网卡 IP ---
            $ip = ''
            try {
                $b = Get-ETBusinessIp
                if ($b -and $b.Addresses) { $ip = @($b.Addresses)[0] }
            }
            catch { }
            if (-not $ip) { $ip = '(未获取)' }
            if ($Script:ui.TxtIp) { $Script:ui.TxtIp.Text = $ip }

            # --- 设备 / ET / MPC：IP -> 共享清单反查；三编号未全部命中则整块用示例值 ---
            $plate = $null
            if ($ip -and $ip -ne '(未获取)') { $plate = Resolve-ETPlate -Ip $ip }
            $fromSample = -not ($plate -and $plate.Complete)

            $equip = if ($fromSample) { $Script:SamplePlate.Equip } else { $plate.EquipmentId }
            $et = if ($fromSample) { $Script:SamplePlate.Et } else { $plate.EtCode }
            $mpc = if ($fromSample) { $Script:SamplePlate.Mpc } else { $plate.MpcCode }

            if ($Script:ui.TxtEquip) { $Script:ui.TxtEquip.Text = $equip }
            if ($Script:ui.TxtEt) { $Script:ui.TxtEt.Text = $et }
            if ($Script:ui.TxtMpc) { $Script:ui.TxtMpc.Text = $mpc }

            # --- 抬头：接入共享清单后不再标注「示例」 ---
            if ($Script:ui.TxtTitle) {
                $Script:ui.TxtTitle.Text = if ($fromSample) { 'ET 工作台 · 示例' } else { 'ET 工作台' }
            }

            # --- 报警标识：三态（绿=正常 / 黄=警告 / 红=报警） ---
            Set-ETPlateStatus -State (Get-ETAlarmState -FromSample $fromSample)

            # --- 页脚：最后一次刷新时刻（与页脚版本号并排） ---
            if ($Script:ui.TxtUpdated) { $Script:ui.TxtUpdated.Text = ('更新 ' + (Get-Date -Format 'HH:mm')) }
        }
        catch { }
    }

    # ================================================================ 8. 应急退出哨兵
    function Invoke-CheckStopSentinel {
        <#
          .SYNOPSIS 检查「停止哨兵」文件，存在则退出。
          .DESCRIPTION
            铭牌沉底后右键菜单可能够不着（业务软件全屏且不允许切出）。
            应急出口：手工建一个空文件即可让铭牌自我退出。
                New-Item -ItemType File -Force "$env:ProgramData\ETWorkbench\Local\plate.stop"
            退出后删除哨兵，下次启动不会立刻又退出。
        #>
        try {
            $sentinel = $Script:StopSentinelPath
            if ($sentinel -and (Test-Path -LiteralPath $sentinel)) {
                Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
                $Script:Plate.Close()
            }
        }
        catch { }
    }
    try {
        $Script:StopSentinelPath = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'plate.stop'
    }
    catch { $Script:StopSentinelPath = '' }

    # ================================================================ 9. 点击展开完整主窗口
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ETPlateActivate {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue

    $script:MainProc = $null

    function Invoke-OpenMainWindow {
        try {
            $mutex = New-Object System.Threading.Mutex($false, 'Global\ETWorkbench.MainWindow.SingleInstance')
            $lockHeld = $mutex.WaitOne(300, $false)
            if (-not $lockHeld) {
                [System.Windows.MessageBox]::Show($Script:Plate, 'ET 工作台已打开，不能重复打开。', 'ET 工作台', 'OK', 'Warning') | Out-Null
                $mutex.Dispose()
                return
            }
            $mutex.ReleaseMutex()
            $mutex.Dispose()

            # 若主窗口进程仍在运行，尝试激活其主窗口；否则启动新进程
            if ($script:MainProc -and -not $script:MainProc.HasExited) {
                try {
                    $script:MainProc.Refresh()
                    if ($script:MainProc.MainWindowHandle -ne [IntPtr]::Zero) {
                        $null = [ETPlateActivate]::SetForegroundWindow($script:MainProc.MainWindowHandle)
                        return
                    }
                }
                catch { }
            }

            $entry = Join-Path $Script:Root 'Start-ETWorkbench.ps1'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $entry + '"'
            $psi.WorkingDirectory = $Script:Root
            # 隐藏控制台窗口：主窗口是 WPF（ShowDialog），无需控制台，避免黑窗闪现
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $script:MainProc = [System.Diagnostics.Process]::Start($psi)
        }
        catch { }
    }

    function Invoke-ClosePlate {
        <# .SYNOPSIS 退出常驻铭牌：需二次确认，避免误触直接关闭。 #>
        try {
            $text = "确定要退出 ET 设备铭牌吗？`n`n退出后，工作区左边缘的状态铭牌将消失；后台定时任务（健康监测 / 事件上报 / 指令监听）不受影响，随时可再次双击 Start-ETPlate.bat 启动。"
            $ans = [System.Windows.MessageBox]::Show($Script:Plate, $text, '退出 ET 铭牌', 'YesNo', 'Question')
            if ($ans -eq [System.Windows.MessageBoxResult]::Yes) { $Script:Plate.Close() }
        }
        catch { }
    }

    if ($Script:ui.RootBorder) {
        $Script:ui.RootBorder.Add_MouseLeftButtonUp({ Invoke-OpenMainWindow })
    }

    # 右键菜单：打开工作台 / 退出铭牌…（退出需二次确认，防止误操作）
    $menu = $Script:ui.RootBorder.ContextMenu
    if ($menu) {
        foreach ($mi in $menu.Items) {
            if ($mi -is [System.Windows.Controls.MenuItem]) {
                switch ([string]$mi.Tag) {
                    'open' { $mi.Add_Click({ Invoke-OpenMainWindow }) }
                    'exit' { $mi.Add_Click({ Invoke-ClosePlate }) }
                }
            }
        }
    }

    # ================================================================ 10. 定时刷新（每 30 秒）
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(30)
    $timer.Add_Tick({ Update-PlateInfo; Sync-PlatePosition; Invoke-CheckStopSentinel })
    $timer.Start()

    # 首次刷新
    Update-PlateInfo

    # ================================================================ 11. 常驻消息循环
    $null = $Script:Plate.ShowDialog()
}
catch {
    Show-PlateFatal ("铭牌启动失败：{0}" -f $_.Exception.Message)
    exit 1
}

exit 0
