<#
.SYNOPSIS
    Start-ETTray —— ET 工作台屏幕左侧常驻【设备铭牌】入口。

.DESCRIPTION
    在屏幕左侧、垂直居中、紧贴左边缘显示一个常驻、置顶（Topmost）的设备铭牌标签，内容：
      设备编号（标题大字） / ET / IP / MPC / 标签版本 / 报警标识

    字段来源：
      IP               本机业务网卡 IP（Get-ETBusinessIp 自动获取）
      设备 / ET / MPC   用 IP 在共享清单（主数据 mappings.json 的 ByIpAddress）中反查；
                        清单不可用时回退到示例值（抬头显示「示例」）。
      标签版本         本标签自身版本号（$Script:BadgeVersion）
      报警标识        三态：绿=正常 / 黄=警告 / 红=报警
                       判定规则集中在一张表里（见 $Script:PlateRules），状态本身只有这三种。

    交互：
      · 单击铭牌主体  -> 展开完整主窗口（Start-ETWorkbench.ps1）
      · 右键铭牌主体  -> 菜单（打开工作台 / 退出标签…）
      · 退出标签      -> 右键菜单 + 二次确认（防止误触直接关闭）
      · 每 30 秒自动刷新

    调试：
      -PreviewState <Normal|Warn|Alarm>  强制显示某一状态颜色，跳过规则判定，用于现场校色 / 联调

    架构：标签是【独立常驻进程】，完整主窗口是另一个进程：
      - 关闭完整窗口，标签仍常驻
      - 标签关闭，不影响已打开的主窗口

    设计约束：
      C-1  本文件含中文，必须 UTF-8 with BOM
      C-2  所有路径由 $PSScriptRoot 推导，禁止硬编码
      C-3  GUI 只传标识符（本标签不传任何路径去执行）
      F-4  不抢焦点：标签仅刷新信息，不主动弹出/抢前台
      F-8  不开放端口 / 不建 HTTP Server
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.0',

    # 调试 / 校色用：强制铭牌显示某一状态颜色，跳过规则判定。留空 = 按规则判定。
    # 例：powershell -NoProfile -ExecutionPolicy Bypass -File .\ETWorkbench\Start-ETTray.ps1 -PreviewState Alarm
    [ValidateSet('', 'Normal', 'Warn', 'Alarm')]
    [string]$PreviewState = ''
)

# 本标签（TrayBadge）自身版本号，显示在铭牌页脚
$Script:BadgeVersion = $Version
# 状态预览开关（'' = 按规则判定，见 $Script:PlateRules）
$Script:PreviewState = $PreviewState

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Show-TrayFatal {
    param([string]$Message)
    try {
        [System.Windows.MessageBox]::Show($Message, 'ET 标签', 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Host ("[ET-Tray] 启动失败：{0}" -f $Message) -ForegroundColor Red
    }
}

try {
    # ================================================================ 0. 根路径（C-2）
    $Script:Root = $PSScriptRoot
    if (-not $Script:Root) { $Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

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
        Import-Module $p -Force -ErrorAction Stop
    }

    # ================================================================ 2. 初始化数据根
    try { $null = Initialize-ETDataRoot }
    catch { throw ("本地数据根初始化失败：{0}" -f $_.Exception.Message) }

    # ================================================================ 3. 加载标签界面
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $trayXamlPath = Join-Path $Script:Root 'UI\TrayBadge.xaml'
    if (-not (Test-Path -LiteralPath $trayXamlPath)) { throw "缺少标签界面文件：$trayXamlPath" }

    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $trayXamlPath -Raw -Encoding UTF8))
    $Script:Tray = [Windows.Markup.XamlReader]::Load($reader)

    # 定位到屏幕左侧、垂直居中、紧贴左边缘（无间隙）
    $wa = [System.Windows.SystemParameters]::WorkArea
    $Script:Tray.Left = $wa.Left
    $Script:Tray.Top = [int][math]::Round($wa.Top + ($wa.Height - $Script:Tray.Height) / 2)

    # 控件引用（XAML 命名元素；缺一个不致命，刷新时逐项判空）
    $Script:ui = @{
        RootBorder  = $Script:Tray.FindName('RootBorder')
        StatusStrip = $Script:Tray.FindName('StatusStrip')
        StatusDot   = $Script:Tray.FindName('StatusDot')
        TxtTitle    = $Script:Tray.FindName('TxtTitle')
        TxtStatus   = $Script:Tray.FindName('TxtStatus')
        TxtEquip    = $Script:Tray.FindName('TxtEquip')
        TxtEt       = $Script:Tray.FindName('TxtEt')
        TxtIp       = $Script:Tray.FindName('TxtIp')
        TxtMpc      = $Script:Tray.FindName('TxtMpc')
        TxtBadgeVer = $Script:Tray.FindName('TxtBadgeVer')
        TxtUpdated  = $Script:Tray.FindName('TxtUpdated')
    }
    if ($Script:ui.TxtBadgeVer) { $Script:ui.TxtBadgeVer.Text = ('标签 v{0}' -f $Script:BadgeVersion) }

    # ================================================================ 3.5 铭牌字段解析（IP -> 设备/ET/MPC）
    # 本次先用示例值：真实值应由本机 IP 在共享清单（mappings.json 的 ByIpAddress）中反查。
    # 清单不可用（共享未配置 / 未接入）时显示示例值，并在抬头标注「示例」。
    $Script:SamplePlate = @{ Equip = 'W098'; Et = 'ZET1025'; Mpc = '096' }

    # ================================================================ 3.6 报警标识（三态）状态模型 + 规则表
    # 状态【只有三种】，颜色与语义一一对应：
    #     正常 Normal -> 绿  #FF2FBF71
    #     警告 Warn   -> 黄  #FFF2C94C
    #     报警 Alarm  -> 红  #FFE5533D
    # 判定优先级：报警 Alarm > 警告 Warn > 正常 Normal（报警压过警告）。
    # 「不确定」的情形（未接入共享清单、设备未识别）一律归入【警告】，绝不冒充正常。
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

        # ---------------- 警告（黄）：具体规则待业务确认，以下为占位 ----------------
          @{ Id = 'W-01'; State = 'Alarm'
              Test   = { param($S) -not $S.Configured }
              Reason = { param($S) '未接入共享清单' } }

          @{ Id = 'W-02'; State = 'Alarm'
              Test   = { param($S) -not $S.Identified }
              Reason = { param($S) '设备未识别（识别链未命中）' } }

        @{ Id = 'W-03'; State = 'Warn'
           Test   = { param($S) $S.Pending -gt 0 }
           Reason = { param($S) '待上报事件积压 {0} 条' -f $S.Pending } }
    )

    function Get-ETFirstPlateValue {
        <# .SYNOPSIS 从对象中按候选字段名取第一个非空字符串（无匹配字段名则返回空串）。 #>
        param([AllowNull()]$InputObject, [string[]]$Names)
        if ($null -eq $InputObject) { return '' }
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

    # ================================================================ 4. 刷新铭牌信息
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
            if ($Script:ui.StatusStrip) {
                $Script:ui.StatusStrip.Background = $brush
                try {
                    if ($Script:ui.StatusStrip.Effect) {
                        $Script:ui.StatusStrip.Effect.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($color)
                    }
                }
                catch { }
            }
            if ($Script:ui.StatusDot) { $Script:ui.StatusDot.Fill = $brush }
            if ($Script:ui.TxtStatus) { $Script:ui.TxtStatus.Text = [string]$style.Text }
            if ($Script:ui.RootBorder) {
                $Script:ui.RootBorder.ToolTip = ($tip + [Environment]::NewLine + '单击展开工作台 · 右键更多操作')
            }
        }
        catch { }
    }

    function Update-TrayInfo {
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
                $Script:ui.TxtTitle.Text = if ($fromSample) { 'ET 设备铭牌 · 示例' } else { 'ET 设备铭牌' }
            }

            # --- 刷新时间 ---
            if ($Script:ui.TxtUpdated) { $Script:ui.TxtUpdated.Text = ('更新 ' + (Get-Date -Format 'HH:mm')) }

            # --- 报警标识：三态（绿=正常 / 黄=警告 / 红=报警） ---
            Set-ETPlateStatus -State (Get-ETAlarmState -FromSample $fromSample)
        }
        catch { }
    }

    # ================================================================ 5. 点击展开完整主窗口
    # P/Invoke：激活已有主窗口（SetForegroundWindow）
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ETWin32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue

    $script:MainProc = $null

    function Invoke-OpenMainWindow {
        try {
            # 若主窗口进程仍在运行，尝试激活其主窗口；否则启动新进程
            if ($script:MainProc -and -not $script:MainProc.HasExited) {
                try {
                    $script:MainProc.Refresh()
                    if ($script:MainProc.MainWindowHandle -ne [IntPtr]::Zero) {
                        $null = [ETWin32]::SetForegroundWindow($script:MainProc.MainWindowHandle)
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

    function Invoke-CloseBadge {
        <# .SYNOPSIS 退出常驻标签：需二次确认，避免误触直接关闭。 #>
        try {
            $text = "确定要退出 ET 常驻标签吗？`n`n退出后，屏幕左侧的状态标签将从桌面消失；后台定时任务（健康监测 / 事件上报 / 指令监听）不受影响，随时可再次双击 Start-ETTray.bat 启动。"
            $ans = [System.Windows.MessageBox]::Show($Script:Tray, $text, '退出 ET 标签', 'YesNo', 'Question')
            if ($ans -eq [System.Windows.MessageBoxResult]::Yes) { $Script:Tray.Close() }
        }
        catch { }
    }

    if ($Script:ui.RootBorder) {
        $Script:ui.RootBorder.Add_MouseLeftButtonUp({ Invoke-OpenMainWindow })
    }

    # 右键菜单：打开工作台 / 退出标签…（退出标签需二次确认，防止误操作）
    $menu = $Script:ui.RootBorder.ContextMenu
    if ($menu) {
        foreach ($mi in $menu.Items) {
            if ($mi -is [System.Windows.Controls.MenuItem]) {
                switch ([string]$mi.Tag) {
                    'open' { $mi.Add_Click({ Invoke-OpenMainWindow }) }
                    'exit' { $mi.Add_Click({ Invoke-CloseBadge }) }
                }
            }
        }
    }

    # ================================================================ 6. 定时刷新（每 30 秒）
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(30)
    $timer.Add_Tick({ Update-TrayInfo })
    $timer.Start()

    # 首次刷新
    Update-TrayInfo

    # ================================================================ 7. 常驻消息循环
    $null = $Script:Tray.ShowDialog()
}
catch {
    Show-TrayFatal ("标签启动失败：{0}" -f $_.Exception.Message)
    exit 1
}

exit 0
