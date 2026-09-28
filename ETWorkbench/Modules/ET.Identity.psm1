<#
.SYNOPSIS
    ET.Identity —— 设备与工程识别（方案 E-02 / §6.4 识别链）。

.DESCRIPTION
    识别链（方案 §6.4，7 步）：
      SN → 业务 IP → Equipment ID → Device ID → Project ID → Application → Approved Version

    设计原则（方案 §7 E-02 步骤表）：
      · 每一步都产出【证据】(Evidence)，而不是猜一个结论
      · 任何一步失败 → 返回 Unidentified 并说明卡在哪一步，绝不猜
      · 多候选 → 返回 Ambiguous 并列出候选，交人工确认，不自动选
      · 识别结果写入本地 Snapshot，可离线复核

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
    本模块为 D1 骨架：函数签名与返回结构已定稿，取数逻辑逐条补全。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')

function Get-ETBiosSerialNumber {
    <#
      .SYNOPSIS  识别链第 1 步：取 BIOS/主板序列号。
      .OUTPUTS   PSCustomObject { Value; Source; Success; Error }
    #>
    [CmdletBinding()]
    param()

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
        $sn = ($cs.IdentifyingNumber | ForEach-Object { "$_".Trim() })
        if ([string]::IsNullOrWhiteSpace($sn)) {
            return [pscustomobject]@{ Value = $null; Source = 'Win32_ComputerSystemProduct'; Success = $false; Error = '序列号为空' }
        }
        return [pscustomobject]@{ Value = $sn.ToUpperInvariant(); Source = 'Win32_ComputerSystemProduct'; Success = $true; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Value = $null; Source = 'Win32_ComputerSystemProduct'; Success = $false; Error = $_.Exception.Message }
    }
}

function Get-ETBusinessIp {
    <#
      .SYNOPSIS  识别链第 2 步：取业务网卡 IP（按 AllowedIpPrefixes 过滤）。
      .OUTPUTS   PSCustomObject { Addresses[]; Success; Error }
    #>
    [CmdletBinding()]
    param()

    try {
        $cfg = Get-ETConfig
        $prefixes = @($cfg.Identity.AllowedIpPrefixes | Where-Object { $_ })

        $addrs = @()
        foreach ($nic in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop)) {
            if ($nic.IPAddress -like '127.*' -or $nic.IPAddress -like '169.254.*') { continue }
            $addrs += $nic.IPAddress
        }

        if ($prefixes.Count -gt 0) {
            $addrs = @($addrs | Where-Object { $ip = $_; ($prefixes | Where-Object { $ip.StartsWith($_) }).Count -gt 0 })
        }

        return [pscustomobject]@{ Addresses = $addrs; Success = ($addrs.Count -gt 0); Error = if ($addrs.Count -eq 0) { '未匹配到业务 IP' } else { $null } }
    }
    catch {
        return [pscustomobject]@{ Addresses = @(); Success = $false; Error = $_.Exception.Message }
    }
}

function Resolve-ETEquipment {
    <#
      .SYNOPSIS  识别链第 3~4 步：由 SN / 业务 IP 匹配 EquipmentId 与 DeviceId。
      .DESCRIPTION
        数据来源：共享 MasterData 快照（ET.MasterData 提供）。
        未命中 → Unidentified；命中多条 → Ambiguous（不自动选，方案 §7 E-02 步骤 5）。
      .OUTPUTS   PSCustomObject { Status; EquipmentId; DeviceId; Candidates; Evidence }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][string]$SerialNumber,
        [AllowNull()][string[]]$IpAddresses
    )

    # TODO(D1): 接 ET.MasterData 的 equipment 快照做匹配
    return [pscustomobject]@{
        Status      = 'NotImplemented'
        EquipmentId = $null
        DeviceId    = $null
        Candidates  = @()
        Evidence    = [pscustomobject]@{ SerialNumber = $SerialNumber; IpAddresses = $IpAddresses }
    }
}

function Resolve-ETProject {
    <#
      .SYNOPSIS  识别链第 5 步：由 DeviceId 推导 ProjectId。
      .OUTPUTS   PSCustomObject { Status; ProjectId; Candidates; Evidence }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][string]$DeviceId)

    # TODO(D1): 接 masterdata 快照 / mappings
    return [pscustomobject]@{ Status = 'NotImplemented'; ProjectId = $null; Candidates = @(); Evidence = [pscustomobject]@{ DeviceId = $DeviceId } }
}

function Resolve-ETApplication {
    <#
      .SYNOPSIS  识别链第 6~7 步：识别本机应装的 Application 及批准版本。
      .DESCRIPTION
        来源：masterdata 快照中的 approved-versions + 本机已装清单比对。
      .OUTPUTS   array of PSCustomObject { ApplicationId; ApprovedVersion; InstalledVersion; Status }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][string]$EquipmentId)

    # TODO(D1)
    return @()
}

function Get-ETInstalledApplications {
    <#
      .SYNOPSIS  枚举本机已安装软件（用于「已装 vs 应装」比对）。
      .DESCRIPTION
        只读注册表 Uninstall 键。不修改任何东西。
      .OUTPUTS   array of PSCustomObject { DisplayName; DisplayVersion; Publisher; InstallLocation }
    #>
    [CmdletBinding()]
    param()

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $out = @()
    foreach ($p in $paths) {
        try {
            $out += @(Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation)
        }
        catch { continue }
    }
    return $out
}

function Invoke-ETIdentityChain {
    <#
      .SYNOPSIS  执行完整识别链并落快照（E-02 主入口）。
      .DESCRIPTION
        顺序执行 7 步，逐步记录证据；任何一步 Unidentified 立即停止并如实返回。
        结果写：<DataRoot>\Snapshot\identity.json（原子写）。
      .OUTPUTS   PSCustomObject { Status; Steps[]; Result; SnapshotPath }
    #>
    [CmdletBinding()]
    param([switch]$NoPersist)

    $steps = New-Object System.Collections.ArrayList

    $sn = Get-ETBiosSerialNumber
    [void]$steps.Add([pscustomobject]@{ Step = 1; Name = 'serial-number'; Ok = $sn.Success; Value = $sn.Value; Error = $sn.Error })

    $ip = Get-ETBusinessIp
    [void]$steps.Add([pscustomobject]@{ Step = 2; Name = 'business-ip'; Ok = $ip.Success; Value = ($ip.Addresses -join ', '); Error = $ip.Error })

    $eq = Resolve-ETEquipment -SerialNumber $sn.Value -IpAddresses $ip.Addresses
    [void]$steps.Add([pscustomobject]@{ Step = 3; Name = 'equipment-id'; Ok = ($eq.Status -eq 'Identified'); Value = $eq.EquipmentId; Error = $eq.Status })

    $status = if ($sn.Success -and ($eq.Status -eq 'Identified')) { 'Identified' } else { 'Unidentified' }

    $result = [pscustomobject]@{
        Status         = $status
        SerialNumber   = $sn.Value
        IpAddresses    = $ip.Addresses
        EquipmentId    = $eq.EquipmentId
        DeviceId       = $eq.DeviceId
        ProjectId      = $null
        Applications   = @()
        Steps          = $steps
        EvaluatedAt    = (Get-Date -Format 'o')
        SchemaVersion  = '1.0.0'
    }

    $snapshotPath = $null
    if (-not $NoPersist) {
        try {
            $snapshotPath = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot -Ensure) 'identity.json'
            Write-ETJsonAtomic -LiteralPath $snapshotPath -InputObject $result
        }
        catch {
            Write-ETLog -Message '识别结果落快照失败' -Level Warn -Data @{ Error = $_.Exception.Message }
        }
    }

    return [pscustomobject]@{ Status = $status; Steps = $steps; Result = $result; SnapshotPath = $snapshotPath }
}

Export-ModuleMember -Function @(
    'Get-ETBiosSerialNumber'
    'Get-ETBusinessIp'
    'Resolve-ETEquipment'
    'Resolve-ETProject'
    'Resolve-ETApplication'
    'Get-ETInstalledApplications'
    'Invoke-ETIdentityChain'
)
