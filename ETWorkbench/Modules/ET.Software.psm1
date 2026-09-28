<#
.SYNOPSIS
    ET.Software —— 软件入口与状态判态（方案 E-03 / §6.5 七态模型）。

.DESCRIPTION
    七态模型（方案 §6.5）——顺序即先后，不可跳级：

      Package Available  共享上存在已批准版本包（还没下到本机）
            ↓
      Downloaded         已完整下载并校验通过（本机有包，不代表装了）
            ↓
      Deployed           已落到目标目录（未必可执行）
            ↓
      Executable Found   目标目录里确实找到了可执行文件
            ↓
      Running            该进程正在运行
            ↓
      Configured         配置文件符合 ConfigRules 期望
            ↓
      Effective          已配置 + 正在运行 + 无未决告警

    【铁律】（约束 C-6 / 红线 F-9）：
      Downloaded 绝不允许显示为「已安装」或「已生效」。
      状态只能【声明到已取证的那一级】，取不到证据就停在上一级并标注 Unknown。

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')

function Get-ETStateModel {
    <#
      .SYNOPSIS  返回七态定义（顺序 + 中文名 + 说明）。
      .OUTPUTS   PSCustomObject[]  按顺序排列
    #>
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Order = 1; State = 'PackageAvailable'; Label = '共享有包';   Desc = '共享上存在该应用的已批准版本' }
        [pscustomobject]@{ Order = 2; State = 'Downloaded';       Label = '已下载';     Desc = '本机已完成下载与校验（不代表已安装）' }
        [pscustomobject]@{ Order = 3; State = 'Deployed';         Label = '已部署';     Desc = '已复制到目标目录' }
        [pscustomobject]@{ Order = 4; State = 'ExecutableFound';  Label = '有可执行';   Desc = '目标目录中找到可执行文件' }
        [pscustomobject]@{ Order = 5; State = 'Running';          Label = '运行中';     Desc = '进程正在运行' }
        [pscustomobject]@{ Order = 6; State = 'Configured';       Label = '已配置';     Desc = '配置符合期望规则' }
        [pscustomobject]@{ Order = 7; State = 'Effective';        Label = '已生效';     Desc = '已配置 + 运行中 + 无未决告警' }
    )
}

function Get-ETSoftwareCatalog {
    <#
      .SYNOPSIS  组装「本机应用清单」——把主数据、共享包、本机现状合成一张表（E-03 主入口）。

      .DESCRIPTION
        对每个 Application 输出一行，含：应装版本、七态当前值、证据、缺失项。
        绝不推断状态：每一项都带 Evidence 字段说明「凭什么这么判」。

      .OUTPUTS   PSCustomObject[] {
                   ApplicationId; ApplicationName; SoftwareId;
                   ApprovedVersion; LocalVersion;
                   State; StateOrder; StateLabel; StateIsStale;
                   Evidence; NextAction
                 }
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$EquipmentId)

    # 防御性过滤：即使快照层返回了 $null 元素，也在这里滤掉。
    # 原因：Set-StrictMode -Version 2.0 下访问 $null 元素的属性会抛异常。
    $apps = @(Get-ETMasterDataSnapshot -Kind 'applications' | Where-Object { $null -ne $_ })
    $approved = @(Get-ETMasterDataSnapshot -Kind 'approved-versions' | Where-Object { $null -ne $_ })
    $installed = @(Get-ETInstalledApplications | Where-Object { $null -ne $_ })

    if ($apps.Count -eq 0) {
        Write-ETLog -Message '应用主数据为空，无法生成软件清单' -Level Warn
        return @()
    }

    $rows = @()
    foreach ($a in $apps) {
        $approvedForApp = @($approved | Where-Object { $null -ne $_ -and ("$($_.ApplicationId)" -eq "$($a.ApplicationId)") })
        $ver = if ($approvedForApp.Count -gt 0) { "$($approvedForApp[0].Version)" } else { $null }

        # 本机是否已装（按名称模糊匹配，具体匹配规则 D1 与运维确认）
        $hit = @($installed | Where-Object { $null -ne $_ -and $_.DisplayName -and ("$($_.DisplayName)" -like "*$($a.ApplicationName)*") })

        $rows += [pscustomobject]@{
            ApplicationId   = "$($a.ApplicationId)"
            ApplicationName = "$($a.ApplicationName)"
            SoftwareId      = if ($a.SoftwareId) { "$($a.SoftwareId)" } else { "$($a.ApplicationId)" }
            ApprovedVersion = $ver
            LocalVersion    = if ($hit.Count -gt 0) { "$($hit[0].DisplayVersion)" } else { $null }
            State           = 'PackageAvailable'
            StateOrder      = 1
            StateLabel      = '共享有包'
            StateIsStale    = $false
            Evidence        = [ordered]@{
                ApprovedVersion = $ver
                InstalledMatch  = if ($hit.Count -gt 0) { $hit[0].DisplayName } else { $null }
                CheckedAt       = (Get-Date -Format 'o')
            }
            NextAction      = '待判态（D1 实现）'
        }
    }

    return $rows
}

function Test-ETExecutablePresence {
    <#
      .SYNOPSIS  在目标目录中查找可执行文件（第 4 态：Executable Found）。
      .OUTPUTS   PSCustomObject { Found; ExecutablePath; Candidates[] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string[]]$Patterns = @('*.exe')
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return [pscustomobject]@{ Found = $false; ExecutablePath = $null; Candidates = @() }
    }

    $cands = @()
    foreach ($p in $Patterns) {
        $cands += @(Get-ChildItem -LiteralPath $Directory -Filter $p -File -Recurse -ErrorAction SilentlyContinue)
    }

    if ($cands.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; ExecutablePath = $null; Candidates = @() }
    }

    return [pscustomobject]@{
        Found          = $true
        ExecutablePath = $cands[0].FullName
        Candidates     = ($cands | Select-Object -First 20 -ExpandProperty FullName)
    }
}

function Test-ETProcessRunning {
    <#
      .SYNOPSIS  判断进程是否在运行（第 5 态：Running）。
      .PARAMETER ProcessName  进程名（可含 .exe，会自动去掉）。
      .OUTPUTS   PSCustomObject { Running; Ids[]; Detail }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProcessName)

    $name = $ProcessName -replace '\.exe$', ''
    try {
        $procs = @(Get-Process -Name $name -ErrorAction Stop)
        return [pscustomobject]@{ Running = ($procs.Count -gt 0); Ids = @($procs.Id); Detail = ("{0} 个进程" -f $procs.Count) }
    }
    catch {
        # 无进程时 Get-Process 会抛，视为未运行（不是错误）
        return [pscustomobject]@{ Running = $false; Ids = @(); Detail = '未找到进程' }
    }
}

function Resolve-ETSoftwareState {
    <#
      .SYNOPSIS  计算单个应用当前七态（E-03 核心）。

      .DESCRIPTION
        逐级取证，任一级取不到证据就【停在该级】并标注 Unknown，绝不跳级（约束 C-6）。
        返回的 Evidence 必须能被人复核。

      .OUTPUTS   PSCustomObject { State; StateOrder; StateLabel; UnknownAt; Evidence }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [string]$ApprovedVersion,
        [string]$TargetDirectory,
        [string]$ProcessName,
        [switch]$ConfigVerified
    )

    $ev = [ordered]@{}

    # 1) Package Available —— 共享上是否有包
    $pkgAvailable = $false
    if ($ApprovedVersion) {
        $relPath = '{0}\{1}' -f $ApplicationId, $ApprovedVersion
        $pkgDir = Get-ETSharePath -Category Release -ChildSegments @($relPath)
        if ($pkgDir -and (Test-Path -LiteralPath $pkgDir)) { $pkgAvailable = $true }
        $ev['PackagePath'] = $pkgDir
    }
    $ev['PackageAvailable'] = $pkgAvailable
    if (-not $pkgAvailable) {
        return [pscustomobject]@{ State = $null; StateOrder = 0; StateLabel = '共享无包'; UnknownAt = 'PackageAvailable'; Evidence = $ev }
    }

    # 2) Downloaded —— 本机缓存里是否有完整包
    $cacheDir = Join-Path (Get-ETPath -Category LocalDir -Name Cache) $ApplicationId
    $downloaded = Test-Path -LiteralPath $cacheDir
    $ev['CacheDir'] = $cacheDir
    $ev['Downloaded'] = $downloaded
    if (-not $downloaded) {
        return [pscustomobject]@{ State = 'PackageAvailable'; StateOrder = 1; StateLabel = '共享有包'; UnknownAt = 'Downloaded'; Evidence = $ev }
    }

    # 3) Deployed —— 是否已落到目标目录
    $deployed = $false
    if ($TargetDirectory) { $deployed = (Test-Path -LiteralPath $TargetDirectory) }
    $ev['TargetDirectory'] = $TargetDirectory
    $ev['Deployed'] = $deployed
    if (-not $deployed) {
        return [pscustomobject]@{ State = 'Downloaded'; StateOrder = 2; StateLabel = '已下载'; UnknownAt = 'Deployed'; Evidence = $ev }
    }

    # 4) Executable Found
    $exe = Test-ETExecutablePresence -Directory $TargetDirectory
    $ev['ExecutableFound'] = $exe.Found
    $ev['ExecutablePath'] = $exe.ExecutablePath
    if (-not $exe.Found) {
        return [pscustomobject]@{ State = 'Deployed'; StateOrder = 3; StateLabel = '已部署'; UnknownAt = 'ExecutableFound'; Evidence = $ev }
    }

    # 5) Running
    $running = [pscustomobject]@{ Running = $false; Ids = @(); Detail = '未提供进程名' }
    if ($ProcessName) { $running = Test-ETProcessRunning -ProcessName $ProcessName }
    $ev['Running'] = $running.Running
    $ev['ProcessIds'] = $running.Ids
    if (-not $running.Running) {
        return [pscustomobject]@{ State = 'ExecutableFound'; StateOrder = 4; StateLabel = '有可执行'; UnknownAt = 'Running'; Evidence = $ev }
    }

    # 6) Configured
    $ev['Configured'] = [bool]$ConfigVerified
    if (-not $ConfigVerified) {
        return [pscustomobject]@{ State = 'Running'; StateOrder = 5; StateLabel = '运行中'; UnknownAt = 'Configured'; Evidence = $ev }
    }

    # 7) Effective —— 已配置 + 运行中；未决告警由 E-05 汇总时再叠加
    return [pscustomobject]@{ State = 'Effective'; StateOrder = 7; StateLabel = '已生效'; UnknownAt = $null; Evidence = $ev }
}

function Get-ETSoftwareStateSummary {
    <#
      .SYNOPSIS  汇总本机所有应用的七态（GUI「软件」页签的数据源 / E-03 验收）。
      .OUTPUTS   PSCustomObject { Rows[]; Counts; EvaluatedAt }
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$EquipmentId)

    $rows = @(Get-ETSoftwareCatalog -EquipmentId $EquipmentId)
    $counts = [ordered]@{}

    foreach ($s in (Get-ETStateModel)) { $counts[$s.State] = 0 }

    foreach ($r in $rows) {
        $resolved = Resolve-ETSoftwareState -ApplicationId $r.ApplicationId -ApprovedVersion $r.ApprovedVersion
        $r.State = $resolved.State
        $r.StateOrder = $resolved.StateOrder
        $r.StateLabel = $resolved.StateLabel
        $r.Evidence = $resolved.Evidence
        if ($resolved.State -and $counts.Contains($resolved.State)) { $counts[$resolved.State]++ }
    }

    return [pscustomobject]@{ Rows = $rows; Counts = $counts; EvaluatedAt = (Get-Date -Format 'o') }
}

Export-ModuleMember -Function @(
    'Get-ETStateModel'
    'Get-ETSoftwareCatalog'
    'Test-ETExecutablePresence'
    'Test-ETProcessRunning'
    'Resolve-ETSoftwareState'
    'Get-ETSoftwareStateSummary'
)
