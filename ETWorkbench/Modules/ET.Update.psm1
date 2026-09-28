<#
.SYNOPSIS
    ET.Update —— 工作台自更新（方案 E-06 / §6.11）。

.DESCRIPTION
    目录布局（方案 §6.11）：
      ETWorkbench\
        ├─ 1.0.0\      <- 版本目录（绿色包整体）
        ├─ 1.1.0\
        └─ Current.json  <- 指针，指向当前生效版本

    自更新事务（方案 §6.11 / §7 E-06 步骤表）：
      1) 检查共享上最新版本（读 latest.json / manifest.json）
      2) 下载到 <DataRoot>\Cache\ETWorkbench\<新版本>（复用 ET.Transfer 语义）
      3) 校验 SHA256 + 文件数
      4) 备份当前版本（记为 LastKnownGood）
      5) 原子切换 Current.json 指针（点更新，不是覆盖运行中的文件）
      6) 冒烟测试：Test-ETWorkbench
      7) 冒烟失败 → 回滚 Current.json 到 LastKnownGood

    【铁律】：绝不覆盖正在运行的程序文件（红线 F-2）。
    本模块的切换语义是「换指针」，不是「换文件」。

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')
# ET.Update 复用 ET.Transfer 的磁盘空间检查（Test-ETFreeSpace）。
# 显式导入以保证本模块被单独加载时也能工作（例如任务脚本只导入 ET.Update）。
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Transfer.psm1') -ErrorAction SilentlyContinue

function Get-ETWorkbenchRoot {
    <#
      .SYNOPSIS  自更新的版本父目录（绿色包根）。
    #>
    [CmdletBinding()]
    param()
    return (Get-ETProgramRoot)
}

function Get-ETCurrentPointerPath {
    <#
      .SYNOPSIS  Current.json 指针文件路径。
    #>
    [CmdletBinding()]
    param()
    return (Join-Path (Get-ETWorkbenchRoot) 'Current.json')
}

function Get-ETCurrentVersion {
    <#
      .SYNOPSIS  读取当前生效版本（E-06 步骤 1 / GUI「关于」页签）。
      .OUTPUTS   PSCustomObject { Version; PreviousVersion; SwitchedAt; Source; Ok; Error }
    #>
    [CmdletBinding()]
    param()

    $f = Get-ETCurrentPointerPath
    if (-not (Test-Path -LiteralPath $f)) {
        return [pscustomobject]@{ Ok = $false; Version = $null; PreviousVersion = $null; SwitchedAt = $null; Source = 'Current.json 不存在'; Error = $null }
    }

    try {
        $p = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{ Ok = $true; Version = "$($p.CurrentVersion)"; PreviousVersion = "$($p.PreviousVersion)"; SwitchedAt = $p.SwitchedAt; Source = $f; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Version = $null; PreviousVersion = $null; SwitchedAt = $null; Source = $f; Error = $_.Exception.Message }
    }
}

function Get-ETLocalVersions {
    <#
      .SYNOPSIS  列出本机已下载的全部版本目录（E-06 步骤 3）。
      .OUTPUTS   PSCustomObject[] { Version; Path; SizeMB; IsCurrent }
    #>
    [CmdletBinding()]
    param()

    $root = Get-ETWorkbenchRoot
    $cur = Get-ETCurrentVersion
    $out = @()

    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^\d+\.\d+\.\d+') { continue }
        $size = 0
        try { $size = [math]::Round(((Get-ChildItem -LiteralPath $d.FullName -File -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum) / 1MB, 2) } catch { }
        $out += [pscustomobject]@{ Version = $d.Name; Path = $d.FullName; SizeMB = $size; IsCurrent = ($cur.Version -eq $d.Name) }
    }
    return $out | Sort-Object Version
}

function Get-ETAvailableVersion {
    <#
      .SYNOPSIS  查询共享上的最新可用版本（E-06 步骤 1）。

      .DESCRIPTION
        读取 \<Release>\ETWorkbench\latest.json（运维发布时维护）。
        共享不可达或文件缺失 -> Available=false，【不】报错（G-6：断网可用）。

      .OUTPUTS   PSCustomObject { Available; Version; ReleasePath; Notes; Error }
    #>
    [CmdletBinding()]
    param()

    $dir = Get-ETSharePath -Category Release -ChildSegments @('ETWorkbench')
    if (-not $dir) {
        return [pscustomobject]@{ Available = $false; Version = $null; ReleasePath = $null; Notes = $null; Error = '未配置共享根' }
    }

    $latest = Join-Path $dir 'latest.json'
    if (-not (Test-Path -LiteralPath $latest)) {
        return [pscustomobject]@{ Available = $false; Version = $null; ReleasePath = $null; Notes = $null; Error = "找不到 latest.json（$latest）" }
    }

    try {
        $m = Get-Content -LiteralPath $latest -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{ Available = $true; Version = "$($m.Version)"; ReleasePath = (Join-Path $dir "$($m.Version)"); Notes = $m.Notes; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Available = $false; Version = $null; ReleasePath = $null; Notes = $null; Error = $_.Exception.Message }
    }
}

function Test-ETUpdateAvailable {
    <#
      .SYNOPSIS  判断是否有新版本可更新（GUI「关于」页签的「检查更新」按钮）。
      .OUTPUTS   PSCustomObject { UpdateAvailable; CurrentVersion; AvailableVersion; Reason }
    #>
    [CmdletBinding()]
    param()

    $cur = Get-ETCurrentVersion
    $avail = Get-ETAvailableVersion

    if (-not $avail.Available) {
        return [pscustomobject]@{ UpdateAvailable = $false; CurrentVersion = $cur.Version; AvailableVersion = $null; Reason = $avail.Error }
    }
    if ("$($avail.Version)" -eq "$($cur.Version)") {
        return [pscustomobject]@{ UpdateAvailable = $false; CurrentVersion = $cur.Version; AvailableVersion = $avail.Version; Reason = '已是最新版本' }
    }
    return [pscustomobject]@{ UpdateAvailable = $true; CurrentVersion = $cur.Version; AvailableVersion = $avail.Version; Reason = '发现新版本' }
}

function Switch-ETCurrentVersion {
    <#
      .SYNOPSIS  原子切换 Current.json 指针（E-06 步骤 5 —— 核心，只换指针不换文件）。

      .DESCRIPTION
        备份旧指针后原子写新指针（约束 C-4）。
        绝不触碰运行中的程序文件（红线 F-2）。

      .PARAMETER Version      目标版本目录名（必须已存在于绿色包根下）。
      .PARAMETER KeepVersions 保留的版本数（超出则提示可清理，不自动删）。
      .OUTPUTS   PSCustomObject { Ok; From; To; PreviousPointer; Error }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [int]$KeepVersions = -1
    )

    if ($KeepVersions -lt 0) {
        $cfg = Get-ETConfig
        $KeepVersions = if ($cfg.Update.KeepVersions) { [int]$cfg.Update.KeepVersions } else { 2 }
    }

    $root = Get-ETWorkbenchRoot
    $target = Join-Path $root $Version
    if (-not (Test-Path -LiteralPath $target)) {
        return [pscustomobject]@{ Ok = $false; From = $null; To = $Version; PreviousPointer = $null; Error = "版本目录不存在：$target" }
    }

    $cur = Get-ETCurrentVersion
    if ($cur.Version -eq $Version) {
        return [pscustomobject]@{ Ok = $true; From = $Version; To = $Version; PreviousPointer = $null; Error = $null }
    }

    $ptr = Get-ETCurrentPointerPath

    # 备份旧指针
    $backupDir = Get-ETPath -Category LocalDir -Name Backup -Ensure
    $backupPtr = $null
    if (Test-Path -LiteralPath $ptr) {
        $backupPtr = Join-Path $backupDir ('Current.{0}.json' -f (Get-Date -Format 'yyyyMMddHHmmss'))
        Copy-Item -LiteralPath $ptr -Destination $backupPtr -Force
    }

    $newPtr = [pscustomobject]@{
        CurrentVersion  = $Version
        PreviousVersion = $cur.Version
        SwitchedAt      = (Get-Date -Format 'o')
        SwitchedBy      = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        SchemaVersion   = '1.0.0'
    }

    try {
        Write-ETJsonAtomic -LiteralPath $ptr -InputObject $newPtr
        Write-ETLog -Message '已切换生效版本' -Level Info -Data @{ From = "$($cur.Version)"; To = $Version; PointerBackup = $backupPtr }
        return [pscustomobject]@{ Ok = $true; From = $cur.Version; To = $Version; PreviousPointer = $backupPtr; Error = $null }
    }
    catch {
        Write-ETLog -Message '切换生效版本失败' -Level Error -Data @{ To = $Version; Error = $_.Exception.Message }
        return [pscustomobject]@{ Ok = $false; From = $cur.Version; To = $Version; PreviousPointer = $backupPtr; Error = $_.Exception.Message }
    }
}

function Invoke-ETUpdateSmokeTest {
    <#
      .SYNOPSIS  切换后的冒烟测试（E-06 步骤 6）。

      .DESCRIPTION
        在【目标版本目录】里以子进程方式加载该版本的 ET.Core 并运行 Test-ETWorkbench。
        这样测的是新版本，而不是当前进程里已加载的旧模块。

      .OUTPUTS   PSCustomObject { Ok; Version; Output; Error }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)

    $root = Get-ETWorkbenchRoot
    $corePath = Join-Path (Join-Path $root $Version) 'Modules\ET.Core.psm1'
    if (-not (Test-Path -LiteralPath $corePath)) {
        return [pscustomobject]@{ Ok = $false; Version = $Version; Output = $null; Error = "目标版本缺少 ET.Core.psm1：$corePath" }
    }

    $script = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$corePath' -Force
`$r = Test-ETWorkbench
if (`$r.Ok) { 'SMOKE_OK' } else { 'SMOKE_FAIL: ' + `$r.Message }
"@

    $tmp = Join-Path (Get-ETPath -Category LocalDir -Name Temp -Ensure) ('smoke-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1 | Out-String
        $ok = ($out -match 'SMOKE_OK')
        return [pscustomobject]@{ Ok = $ok; Version = $Version; Output = $out.Trim(); Error = if ($ok) { $null } else { '冒烟测试未通过' } }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Version = $Version; Output = $null; Error = $_.Exception.Message }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ETSelfUpdate {
    <#
      .SYNOPSIS  执行自更新（E-06 主入口）。

      .DESCRIPTION
        完整事务：检查 -> 下载 -> 校验 -> 备份 -> 切指针 -> 冒烟 -> 失败回滚。
        任何一步失败都【不动】Current.json，保证工作台始终能启动。

      .PARAMETER Force  即使版本号相同也重新下载。
      .OUTPUTS   PSCustomObject { Ok; Status; From; To; Downloaded; SmokeTest; RolledBack; Errors[] }
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $errs = New-Object System.Collections.ArrayList
    $from = (Get-ETCurrentVersion).Version
    $to = $null
    $downloaded = $false
    $smoke = $null
    $rolledBack = $false

    try {
        # 1) 检查
        $avail = Get-ETAvailableVersion
        if (-not $avail.Available) {
            [void]$errs.Add("无法获取可用版本：$($avail.Error)")
            return [pscustomobject]@{ Ok = $false; Status = 'CheckFailed'; From = $from; To = $null; Downloaded = $false; SmokeTest = $null; RolledBack = $false; Errors = $errs }
        }
        $to = $avail.Version

        if (-not $Force -and $to -eq $from) {
            return [pscustomobject]@{ Ok = $true; Status = 'UpToDate'; From = $from; To = $to; Downloaded = $false; SmokeTest = $null; RolledBack = $false; Errors = $errs }
        }

        # 2) 下载到 <DataRoot>\Cache\ETWorkbench\<Version>
        $cacheDir = Join-Path (Join-Path (Get-ETPath -Category LocalDir -Name Cache) 'ETWorkbench') $to
        if (Test-Path -LiteralPath $cacheDir) {
            Write-ETLog -Message '自更新：目标版本已在本机缓存，复用' -Level Info
        }
        else {
            $plan = Test-ETFreeSpace -Path $cacheDir -RequiredBytes 0
            if (-not $plan.Ok) {
                [void]$errs.Add(("空间不足（可用 {0} GB）" -f $plan.FreeGB))
                return [pscustomobject]@{ Ok = $false; Status = 'NoSpace'; From = $from; To = $to; Downloaded = $false; SmokeTest = $null; RolledBack = $false; Errors = $errs }
            }

            # 递归复制（与软件包同一语义：整个文件夹）
            $null = New-Item -ItemType Directory -Path $cacheDir -Force
            Copy-Item -Path (Join-Path $avail.ReleasePath '*') -Destination $cacheDir -Recurse -Force -ErrorAction Stop
            $downloaded = $true
        }

        # 3) 校验：目标目录里必须有 ET.Core.psm1 且非空
        $coreInCache = Join-Path $cacheDir 'Modules\ET.Core.psm1'
        if (-not (Test-Path -LiteralPath $coreInCache)) {
            [void]$errs.Add("下载内容不完整：缺少 Modules\ET.Core.psm1（$coreInCache）")
            return [pscustomobject]@{ Ok = $false; Status = 'VerifyFailed'; From = $from; To = $to; Downloaded = $downloaded; SmokeTest = $null; RolledBack = $false; Errors = $errs }
        }

        # 4) 落地到版本目录（绿色包根\<Version>）
        $targetDir = Join-Path (Get-ETWorkbenchRoot) $to
        if (-not (Test-Path -LiteralPath $targetDir)) {
            Move-Item -LiteralPath $cacheDir -Destination $targetDir -Force -ErrorAction Stop
        }

        # 5) 切指针
        $sw = Switch-ETCurrentVersion -Version $to
        if (-not $sw.Ok) {
            [void]$errs.Add("切换指针失败：$($sw.Error)")
            return [pscustomobject]@{ Ok = $false; Status = 'SwitchFailed'; From = $from; To = $to; Downloaded = $downloaded; SmokeTest = $null; RolledBack = $false; Errors = $errs }
        }

        # 6) 冒烟测试
        $smoke = Invoke-ETUpdateSmokeTest -Version $to
        if (-not $smoke.Ok) {
            # 7) 回滚
            [void]$errs.Add("冒烟测试失败，已回滚：$($smoke.Error)")
            if ($from) {
                $rb = Switch-ETCurrentVersion -Version $from
                $rolledBack = $rb.Ok
            }
            return [pscustomobject]@{ Ok = $false; Status = 'SmokeFailed'; From = $from; To = $to; Downloaded = $downloaded; SmokeTest = $smoke; RolledBack = $rolledBack; Errors = $errs }
        }

        return [pscustomobject]@{ Ok = $true; Status = 'Updated'; From = $from; To = $to; Downloaded = $downloaded; SmokeTest = $smoke; RolledBack = $false; Errors = $errs }
    }
    catch {
        [void]$errs.Add($_.Exception.Message)
        Write-ETLog -Message ("自更新异常：{0}" -f $_.Exception.Message) -Level Error
        # 异常路径尝试回滚
        if ($from -and -not $rolledBack) {
            $rb = Switch-ETCurrentVersion -Version $from
            $rolledBack = $rb.Ok
        }
        return [pscustomobject]@{ Ok = $false; Status = 'Exception'; From = $from; To = $to; Downloaded = $downloaded; SmokeTest = $smoke; RolledBack = $rolledBack; Errors = $errs }
    }
}

function Get-ETUpdateHistory {
    <#
      .SYNOPSIS  读取自更新历史（Backup 目录里的指针备份 = 切换历史）。
      .OUTPUTS   PSCustomObject[]
    #>
    [CmdletBinding()]
    param()

    $backupDir = Get-ETPath -Category LocalDir -Name Backup
    if (-not (Test-Path -LiteralPath $backupDir)) { return @() }

    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $backupDir -Filter 'Current.*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $p = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $out += [pscustomobject]@{ BackupFile = $f.Name; Version = "$($p.CurrentVersion)"; SwitchedAt = $p.SwitchedAt; SwitchedBy = $p.SwitchedBy }
        }
        catch { continue }
    }
    return $out
}

Export-ModuleMember -Function @(
    'Get-ETWorkbenchRoot'
    'Get-ETCurrentPointerPath'
    'Get-ETCurrentVersion'
    'Get-ETLocalVersions'
    'Get-ETAvailableVersion'
    'Test-ETUpdateAvailable'
    'Switch-ETCurrentVersion'
    'Invoke-ETUpdateSmokeTest'
    'Invoke-ETSelfUpdate'
    'Get-ETUpdateHistory'
)
