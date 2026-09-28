<#
.SYNOPSIS
    ET 工作台 · 第 0 天前置条件检查（P-1 ~ P-8）

.DESCRIPTION
    对应《ET-SYS_开发方案.md》§11 的 P-1 ~ P-8，逐项打印 通过/失败/警告/人工/跳过。
    默认【只读】，不会修改共享。
    只有显式传入 -TestUploadWrite，才会在 Upload 目录做一次原子写探针（会写共享）。

    退出码：0 = 无失败项（可进入 D1）；1 = 存在失败项（不得进入 D1）。

.PARAMETER ShareRoot
    共享根，形如 \\fs01\ETOperation。
    若不提供，会尝试从 Config\workstation.json 的 ShareRoot 字段读取。

.PARAMETER SoftwareRoot
    本地软件根，形如 D:\ETSoftware。
    若不提供，会尝试从 Config\workstation.json 的 SoftwareRoot 字段读取。

.PARAMETER EquipmentId
    设备编号，用于 Upload 探针路径。默认取计算机名。

.PARAMETER TestUploadWrite
    开关。加上才会对共享 Upload 目录做写探针（原子写 + rename）。

.PARAMETER Json
    开关。以 JSON 输出结果（便于归档/贴工单）。

.EXAMPLE
    .\Test-ETPrerequisites.ps1 -ShareRoot '\\fs01\ETOperation' -SoftwareRoot 'D:\ETSoftware'

.EXAMPLE
    .\Test-ETPrerequisites.ps1 -ShareRoot '\\fs01\ETOperation' -TestUploadWrite -Json

.NOTES
    编码要求：本文件必须保存为 UTF-8 with BOM（方案约束 C-1），
    否则 Windows PowerShell 5.1 会按系统 ANSI 读取，中文输出乱码。
#>

[CmdletBinding()]
param(
    [string]$ShareRoot = '',
    [string]$SoftwareRoot = '',
    [string]$EquipmentId = $env:COMPUTERNAME,
    [switch]$TestUploadWrite,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$script:Results = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------- 输出辅助

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('通过', '失败', '警告', '人工', '跳过')][string]$Status,
        [string]$Detail = ''
    )
    [void]$script:Results.Add([pscustomobject]@{
        Id     = $Id
        Name   = $Name
        Status = $Status
        Detail = $Detail
    })

    if (-not $Json) {
        $color = switch ($Status) {
            '通过' { 'Green' }
            '失败' { 'Red' }
            '警告' { 'Yellow' }
            '人工' { 'Cyan' }
            '跳过' { 'DarkGray' }
        }
        Write-Host ('[{0}] {1,-5} {2}' -f $Status, $Id, $Name) -ForegroundColor $color
        if ($Detail) { Write-Host ('         {0}' -f $Detail) -ForegroundColor DarkGray }
    }
}

function Get-ShareHost {
    param([string]$Unc)
    if ($Unc -match '^\\\\[^\\]+') {
        return ($Unc.TrimStart('\').Split('\')[0])
    }
    return $null
}

# ---------------------------------------------------------------- 0. 环境信息

function Test-Environment {
    if (-not $Json) { Write-Host '' ; Write-Host '=== 环境信息 ===' -ForegroundColor White }

    $ep = Get-ExecutionPolicy
    if ($ep -in @('Restricted', 'AllSigned')) {
        Add-Result 'EP' 'PowerShell ExecutionPolicy' '警告' "当前为 $ep —— 与已确认的口径不符，请与 IT 核实（IT-08/IT-09）"
    }
    else {
        Add-Result 'EP' 'PowerShell ExecutionPolicy' '通过' "当前为 $ep（已确认允许未签名脚本）"
    }

    $psv = $PSVersionTable.PSVersion.ToString()
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Add-Result 'ENV' 'PowerShell 版本' '通过' "$psv"
    }
    else {
        Add-Result 'ENV' 'PowerShell 版本' '失败' "$psv 低于 5.1，方案要求 Windows PowerShell 5.1"
    }

    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $isDomain = $id.Name -match '\\' -and $id.Name -notmatch ('^' + [regex]::Escape($env:COMPUTERNAME) + '\\')
        Add-Result 'ENV' '当前 Windows 身份' '人工' ("{0}（{1}）— 需确认这是 IT 批准的共享访问身份" -f $id.Name, $(if ($isDomain) { '域账号' } else { '本地账号' }))
    }
    catch {
        Add-Result 'ENV' '当前 Windows 身份' '警告' $_.Exception.Message
    }
}

# ---------------------------------------------------------------- P-1 共享四目录

function Test-P1-ShareDirs {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-1 共享四目录 ===' -ForegroundColor White }

    if ([string]::IsNullOrWhiteSpace($ShareRoot)) {
        Add-Result 'P-1' '共享四目录可访问' '跳过' '未提供 -ShareRoot，且未能从 Config\workstation.json 读取'
        return
    }

    foreach ($dir in @('MasterData', 'Release', 'ConfigRules', 'Upload')) {
        $p = Join-Path $ShareRoot $dir
        if (Test-Path -LiteralPath $p) {
            Add-Result 'P-1' ("共享目录 {0}" -f $dir) '通过' $p
        }
        else {
            Add-Result 'P-1' ("共享目录 {0}" -f $dir) '失败' ("不存在或无权访问：{0}（IT-03 ~ IT-06）" -f $p)
        }
    }
}

# ---------------------------------------------------------------- P-2 共享身份

function Test-P2-ShareIdentity {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-2 共享访问身份 ===' -ForegroundColor White }

    if ([string]::IsNullOrWhiteSpace($ShareRoot)) {
        Add-Result 'P-2' '共享身份可访问' '跳过' '未提供 -ShareRoot'
        return
    }

    try {
        $null = Get-ChildItem -LiteralPath $ShareRoot -ErrorAction Stop | Select-Object -First 1
        Add-Result 'P-2' '共享根可枚举' '通过' $ShareRoot
    }
    catch {
        Add-Result 'P-2' '共享根可枚举' '失败' ("{0} —— {1}（IT-01 / IT-02）" -f $ShareRoot, $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- P-3 Upload 可写

function Test-P3-UploadWrite {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-3 Upload 可写 ===' -ForegroundColor White }

    if ([string]::IsNullOrWhiteSpace($ShareRoot)) {
        Add-Result 'P-3' 'Upload 可写' '跳过' '未提供 -ShareRoot'
        return
    }
    if (-not $TestUploadWrite) {
        Add-Result 'P-3' 'Upload 可写（Create/Write/Rename）' '跳过' '加 -TestUploadWrite 执行探针（会写共享）'
        return
    }

    $target = Join-Path $ShareRoot ('Upload\{0}\{1}\{2}\{3}\Deployment' -f `
            $EquipmentId, (Get-Date -Format 'yyyy'), (Get-Date -Format 'MM'), (Get-Date -Format 'dd'))

    try {
        if (-not (Test-Path -LiteralPath $target)) {
            $null = New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop
        }

        $probe = Join-Path $target ('__etprobe_{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
        'ET-PREREQ-PROBE' | Set-Content -LiteralPath $probe -Encoding UTF8 -ErrorAction Stop

        $ready = [System.IO.Path]::ChangeExtension($probe, '.ready')
        Move-Item -LiteralPath $probe -Destination $ready -Force -ErrorAction Stop

        Add-Result 'P-3' 'Upload 可写（Create/Write/Rename）' '通过' $target

        # 权限矩阵建议 Upload 的 Delete「尽量禁止」，故此处只作信息性提示
        try {
            Remove-Item -LiteralPath $ready -Force -ErrorAction Stop
            Add-Result 'P-3' 'Upload Delete 行为' '警告' 'Delete 被允许 —— 权限矩阵建议尽量禁止，请与 IT 确认（可接受但非最优）'
        }
        catch {
            Add-Result 'P-3' 'Upload Delete 行为' '通过' ("Delete 被拒绝，符合权限矩阵 ✅（探针文件需请 IT 清理：{0}）" -f $ready)
        }
    }
    catch {
        Add-Result 'P-3' 'Upload 可写（Create/Write/Rename）' '失败' ("{0}（IT-06）" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- P-4 计划任务

function Test-P4-ScheduledTask {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-4 计划任务 ===' -ForegroundColor White }

    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        $null = Get-ScheduledTask -ErrorAction Stop | Select-Object -First 1
        Add-Result 'P-4' 'ScheduledTasks 模块可读' '通过' '可枚举计划任务'
    }
    catch {
        Add-Result 'P-4' 'ScheduledTasks 模块可读' '警告' $_.Exception.Message
    }

    Add-Result 'P-4' '未登录状态下访问 UNC' '人工' @'
需人工验证（IT-10 / IT-11）：
  1) 创建 1 个测试任务，触发器选「不管用户是否登录都运行」
  2) 任务动作执行：Test-Path <共享根>\MasterData\Equipment.json
  3) 注销当前会话，等待任务运行，检查其返回码与输出
  4) 若失败：改用「用户登录时运行」，或改用存储凭据，或降级为 GUI 手工触发（见方案 R-2）
'@
}

# ---------------------------------------------------------------- P-5 CIM / 事件日志

function Test-P5-Diagnostics {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-5 CIM / 事件日志 ===' -ForegroundColor White }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        Add-Result 'P-5' 'CIM/WMI 读取' '通过' ("Win32_ComputerSystem = {0}" -f $cs.Name)
    }
    catch {
        Add-Result 'P-5' 'CIM/WMI 读取' '失败' ("{0}（IT-13）" -f $_.Exception.Message)
    }

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $sn = ($bios.SerialNumber | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($sn)) {
            Add-Result 'P-5' 'BIOS 序列号（识别链第 1 步）' '警告' 'SN 为空 —— 该机器无法被识别链自动授权（方案 §4.3）'
        }
        else {
            Add-Result 'P-5' 'BIOS 序列号（识别链第 1 步）' '通过' $sn
        }
    }
    catch {
        Add-Result 'P-5' 'BIOS 序列号（识别链第 1 步）' '失败' $_.Exception.Message
    }

    try {
        $null = Get-WinEvent -LogName System -MaxEvents 1 -ErrorAction Stop
        Add-Result 'P-5' '事件日志读取（System）' '通过' '可读取 System 日志'
    }
    catch {
        Add-Result 'P-5' '事件日志读取（System）' '警告' ("{0}（IT-13；E-05 第 7 项检测将退化为 Unknown）" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- P-6 ProgramData

function Test-P6-ProgramData {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-6 本地数据根 ===' -ForegroundColor White }

    $root = Join-Path $env:ProgramData 'ETWorkbench'
    try {
        foreach ($sub in @('Config', 'Logs', 'Temp')) {
            $p = Join-Path $root $sub
            if (-not (Test-Path -LiteralPath $p)) {
                $null = New-Item -ItemType Directory -Path $p -Force -ErrorAction Stop
            }
        }

        $probe = Join-Path $root 'Temp\__probe.tmp'
        'x' | Set-Content -LiteralPath $probe -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop

        Add-Result 'P-6' 'ProgramData\ETWorkbench 可读写' '通过' $root
    }
    catch {
        Add-Result 'P-6' 'ProgramData\ETWorkbench 可读写' '失败' ("{0}（IT-12）" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- P-7 SMB 连通

function Test-P7-Smb {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-7 SMB 连通 ===' -ForegroundColor White }

    $hostName = Get-ShareHost -Unc $ShareRoot
    if (-not $hostName) {
        Add-Result 'P-7' 'SMB 连通' '跳过' '未提供有效的 UNC 共享根（形如 \\host\share）'
        return
    }

    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($hostName)
        Add-Result 'P-7' ("DNS 解析 {0}" -f $hostName) '通过' (($addrs | ForEach-Object { $_.IPAddressToString }) -join ', ')
    }
    catch {
        Add-Result 'P-7' ("DNS 解析 {0}" -f $hostName) '失败' $_.Exception.Message
    }

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($hostName, 445, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(3000, $false)

        if ($ok) {
            $client.EndConnect($async)
            Add-Result 'P-7' 'TCP 445 连通' '通过' ("{0}:445" -f $hostName)
        }
        else {
            Add-Result 'P-7' 'TCP 445 连通' '失败' ("3 秒内未连通 {0}:445 —— 可能被防火墙拦截（IT-07）" -f $hostName)
        }
    }
    catch {
        Add-Result 'P-7' 'TCP 445 连通' '失败' ("{0}（IT-07）" -f $_.Exception.Message)
    }
    finally {
        if ($client) { $client.Close() }
    }
}

# ---------------------------------------------------------------- P-8 本地软件根

function Test-P8-SoftwareRoot {
    if (-not $Json) { Write-Host '' ; Write-Host '=== P-8 本地软件根 ===' -ForegroundColor White }

    if ([string]::IsNullOrWhiteSpace($SoftwareRoot)) {
        Add-Result 'P-8' '本地软件根可写' '跳过' '未提供 -SoftwareRoot，且未能从 Config\workstation.json 读取'
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $SoftwareRoot)) {
            $null = New-Item -ItemType Directory -Path $SoftwareRoot -Force -ErrorAction Stop
        }

        $probe = Join-Path $SoftwareRoot '__probe.tmp'
        'x' | Set-Content -LiteralPath $probe -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop

        $drive = (Get-Item -LiteralPath $SoftwareRoot).PSDrive
        $freeGb = if ($drive) { [math]::Round($drive.Free / 1GB, 1) } else { $null }

        Add-Result 'P-8' '本地软件根可写' '通过' ("{0}（可用 {1} GB）" -f $SoftwareRoot, $freeGb)
    }
    catch {
        Add-Result 'P-8' '本地软件根可写' '失败' ("{0} —— {1}" -f $SoftwareRoot, $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- 读取配置

function Resolve-Config {
    if ((-not [string]::IsNullOrWhiteSpace($ShareRoot)) -and (-not [string]::IsNullOrWhiteSpace($SoftwareRoot))) { return }

    $candidates = @(
        (Join-Path $PSScriptRoot '..\ETWorkbench\Config\workstation.json'),
        (Join-Path $PSScriptRoot '..\Config\workstation.json'),
        (Join-Path $env:ProgramData 'ETWorkbench\Config\workstation.json')
    )

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            try {
                $cfg = Get-Content -LiteralPath $c -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace($ShareRoot) -and $cfg.ShareRoot) {
                    $script:ShareRoot = [string]$cfg.ShareRoot
                }
                if ([string]::IsNullOrWhiteSpace($SoftwareRoot) -and $cfg.SoftwareRoot) {
                    $script:SoftwareRoot = [string]$cfg.SoftwareRoot
                }
                if (-not $Json) { Write-Host ("已从配置读取：{0}" -f $c) -ForegroundColor DarkGray }
                return
            }
            catch {
                if (-not $Json) { Write-Host ("配置文件解析失败：{0} —— {1}" -f $c, $_.Exception.Message) -ForegroundColor Yellow }
            }
        }
    }
}

# ---------------------------------------------------------------- 主流程

Resolve-Config

if (-not $Json) {
    Write-Host ''
    Write-Host '======================================================' -ForegroundColor White
    Write-Host ' ET 工作台 · 第 0 天前置条件检查（P-1 ~ P-8）' -ForegroundColor White
    Write-Host '======================================================' -ForegroundColor White
    Write-Host (" 共享根     : {0}" -f $(if ($ShareRoot) { $ShareRoot } else { '(未提供)' })) -ForegroundColor Gray
    Write-Host (" 软件根     : {0}" -f $(if ($SoftwareRoot) { $SoftwareRoot } else { '(未提供)' })) -ForegroundColor Gray
    Write-Host (" 设备编号   : {0}" -f $EquipmentId) -ForegroundColor Gray
    Write-Host (" Upload探针 : {0}" -f $(if ($TestUploadWrite) { '开启（会写共享）' } else { '关闭（只读）' })) -ForegroundColor Gray
    Write-Host ''
}

Test-Environment
Test-P1-ShareDirs
Test-P2-ShareIdentity
Test-P3-UploadWrite
Test-P4-ScheduledTask
Test-P5-Diagnostics
Test-P6-ProgramData
Test-P7-Smb
Test-P8-SoftwareRoot

$counts = @{}
foreach ($s in @('通过', '失败', '警告', '人工', '跳过')) {
    $counts[$s] = @($script:Results | Where-Object { $_.Status -eq $s }).Count
}

if ($Json) {
    [pscustomobject]@{
        GeneratedAt   = (Get-Date -Format 'o')
        ShareRoot     = $ShareRoot
        SoftwareRoot  = $SoftwareRoot
        EquipmentId   = $EquipmentId
        Summary       = $counts
        Results       = $script:Results
    } | ConvertTo-Json -Depth 5
}
else {
    Write-Host ''
    Write-Host '======================================================' -ForegroundColor White
    Write-Host (' 汇总：通过 {0} / 失败 {1} / 警告 {2} / 人工 {3} / 跳过 {4}' -f `
            $counts['通过'], $counts['失败'], $counts['警告'], $counts['人工'], $counts['跳过']) -ForegroundColor White
    Write-Host '======================================================' -ForegroundColor White

    if ($counts['失败'] -gt 0) {
        Write-Host ''
        Write-Host ' 失败项（必须解决）：' -ForegroundColor Red
        $script:Results | Where-Object { $_.Status -eq '失败' } | ForEach-Object {
            Write-Host ('   - [{0}] {1}' -f $_.Id, $_.Name) -ForegroundColor Red
            if ($_.Detail) { Write-Host ('     {0}' -f $_.Detail) -ForegroundColor DarkRed }
        }
        Write-Host ''
        Write-Host ' ❌ 存在失败项，【不得进入 D1】。请先按方案 §12 R-1 解决 IT 授权。' -ForegroundColor Red
    }
    else {
        Write-Host ''
        Write-Host ' ✅ 无失败项。请人工确认标记为「人工」的项后，即可进入 D1。' -ForegroundColor Green
    }
    Write-Host ' 提醒：本结果请回填到《ET-SYS_开发进度.md》§3 的前置条件表。' -ForegroundColor DarkGray
    Write-Host ''
}

if ($counts['失败'] -gt 0) { exit 1 } else { exit 0 }
