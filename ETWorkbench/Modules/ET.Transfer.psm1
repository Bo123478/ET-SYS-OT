<#
.SYNOPSIS
    ET.Transfer —— 一键下载：文件夹递归复制 + 逐文件 Hash + 原子发布（方案 E-04）。

.DESCRIPTION
    下载语义（决策 18 / 方案 §6.3）：
      共享上的 Release 是【整个文件夹】，ET 端做【递归复制】，不是 ZIP 解压。

    事务流程（方案 §6.3）：
      1) 读 manifest.json（文件清单 + 每文件 sha256 + 大小）
      2) 预检：空间是否足够（约束 C-8：不足则暂停，不删业务文件）
      3) 复制到 <Cache>\<ApplicationId>\<Version>.partial\
      4) 逐文件校验 sha256 + 文件总数
      5) 原子发布：.partial -> <Version>\ （rename）
      6) 写下载记录（供 E-05 上报与 E-03 判态）

    并发约束（C-7）：同一时刻只允许 1 个下载（MaxConcurrentDownloads=1）。
    失败保留 .partial 供续传（PreservePartialOnFailure=true）。

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')

# 简单互斥：同进程内串行（跨进程由 GUI 单实例 + Tasks 侧校验保证）
$script:TransferBusy = $false

function Get-ETReleaseManifest {
    <#
      .SYNOPSIS  读取并校验共享上的 manifest.json（方案 §6.2）。
      .OUTPUTS   PSCustomObject { Ok; Manifest; Errors[]; ManifestPath }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Version
    )

    $errors = New-Object System.Collections.ArrayList
    $relRoot = '{0}\{1}' -f $ApplicationId, $Version
    $dir = Get-ETSharePath -Category Release -ChildSegments @($relRoot)
    $manifestPath = if ($dir) { Join-Path $dir 'manifest.json' } else { $null }

    if (-not $manifestPath -or -not (Test-Path -LiteralPath $manifestPath)) {
        [void]$errors.Add("找不到发布清单：$manifestPath")
        return [pscustomobject]@{ Ok = $false; Manifest = $null; Errors = $errors; ManifestPath = $manifestPath }
    }

    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        [void]$errors.Add("manifest.json 不是合法 JSON：$($_.Exception.Message)")
        return [pscustomobject]@{ Ok = $false; Manifest = $null; Errors = $errors; ManifestPath = $manifestPath }
    }

    foreach ($f in @('ApplicationId', 'Version', 'Files')) {
        if (-not (Test-ETObjectHasProperty -InputObject $m -Name $f)) { [void]$errors.Add("manifest 缺少字段：$f") }
    }
    if ($m.ApplicationId -and "$($m.ApplicationId)" -ne $ApplicationId) { [void]$errors.Add("manifest.ApplicationId 不符：$($m.ApplicationId)") }
    if ($m.Version -and "$($m.Version)" -ne $Version) { [void]$errors.Add("manifest.Version 不符：$($m.Version)") }

    foreach ($f in @($m.Files)) {
        if (-not $f.RelativePath) { [void]$errors.Add('Files 中存在缺少 RelativePath 的条目'); continue }
        if (-not $f.Sha256) { [void]$errors.Add("文件缺少 Sha256：$($f.RelativePath)") }
    }

    return [pscustomobject]@{ Ok = ($errors.Count -eq 0); Manifest = $m; Errors = $errors; ManifestPath = $manifestPath }
}

function Test-ETFreeSpace {
    <#
      .SYNOPSIS  检查目标盘可用空间（E-04 步骤 2 / 约束 C-8）。
      .OUTPUTS   PSCustomObject { Ok; FreeBytes; RequiredBytes; FreeGB; RequiredGB }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$RequiredBytes = 0,
        [long]$MinFreeBytes = -1
    )

    if ($MinFreeBytes -lt 0) {
        $cfg = Get-ETConfig
        $MinFreeBytes = [long]$cfg.Transfer.MinFreeSpaceBytes
    }

    $target = $Path
    while ($target -and -not (Test-Path -LiteralPath $target)) {
        $parent = Split-Path -Parent $target
        if ($parent -eq $target) { break }
        $target = $parent
    }
    if (-not $target) { $target = $env:SystemDrive }

    $drive = (Get-Item -LiteralPath $target).PSDrive
    $free = [long]$drive.Free

    $need = [math]::Max($RequiredBytes, $MinFreeBytes)
    return [pscustomobject]@{
        Ok            = ($free -ge $need)
        FreeBytes     = $free
        RequiredBytes = $need
        FreeGB        = [math]::Round($free / 1GB, 2)
        RequiredGB    = [math]::Round($need / 1GB, 2)
    }
}

function Get-ETDownloadPlan {
    <#
      .SYNOPSIS  计算下载计划（不落盘，只回答「要下什么、多大、够不够空间」）。
      .OUTPUTS   PSCustomObject { Ok; ApplicationId; Version; FileCount; TotalBytes; TargetDir; Space; Errors[] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Version
    )

    $errors = New-Object System.Collections.ArrayList
    $mv = Get-ETReleaseManifest -ApplicationId $ApplicationId -Version $Version
    if (-not $mv.Ok) {
        foreach ($e in $mv.Errors) { [void]$errors.Add($e) }
        return [pscustomobject]@{ Ok = $false; ApplicationId = $ApplicationId; Version = $Version; Files = @(); FileCount = 0; TotalBytes = 0; TargetDir = $null; SourceDir = $null; Space = $null; Errors = $errors }
    }

    $files = @($mv.Manifest.Files)
    $totalBytes = 0L
    foreach ($f in $files) { $totalBytes += [long]$f.Size }

    $targetDir = Join-Path (Join-Path (Get-ETPath -Category LocalDir -Name Cache) $ApplicationId) $Version
    $space = Test-ETFreeSpace -Path $targetDir -RequiredBytes $totalBytes
    if (-not $space.Ok) {
        [void]$errors.Add(("空间不足：可用 {0} GB，需要 {1} GB（约束 C-8：暂停，不删业务文件）" -f $space.FreeGB, $space.RequiredGB))
    }

    return [pscustomobject]@{
        Ok          = ($errors.Count -eq 0)
        ApplicationId = $ApplicationId
        Version     = $Version
        Files       = $files
        FileCount   = $files.Count
        TotalBytes  = $totalBytes
        TargetDir   = $targetDir
        SourceDir   = (Split-Path -Parent $mv.ManifestPath)
        Space       = $space
        Errors      = $errors
    }
}

function Invoke-ETDownload {
    <#
      .SYNOPSIS  执行一键下载（E-04 主入口）。

      .DESCRIPTION
        参数一律是【标识符】（ApplicationId + Version），不接受任意路径（约束 C-3）。
        全过程写日志；返回结构化结果；失败保留 .partial。

      .PARAMETER OnProgress  可选回调脚本块，参数 (stage, percent, message)。
      .OUTPUTS   PSCustomObject { Ok; Status; ApplicationId; Version; TargetDir; FileCount; Copied; Verified; DurationSeconds; Errors[] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Version,
        [scriptblock]$OnProgress
    )

    $errs = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    function Report {
        param([string]$Stage, [int]$Percent, [string]$Message)
        Write-ETLog -Message ("[下载] {0} {1}%" -f $Stage, $Percent) -Level Info -Data @{ ApplicationId = $ApplicationId; Version = $Version }
        if ($OnProgress) { & $OnProgress $Stage $Percent $Message }
    }

    if ($script:TransferBusy) {
        [void]$errs.Add('已有下载在进行中（约束 C-7：同一时刻只允许 1 个下载）')
        return [pscustomobject]@{ Ok = $false; Status = 'Busy'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $null; FileCount = 0; Copied = 0; Verified = 0; DurationSeconds = 0; Errors = $errs }
    }

    $script:TransferBusy = $true
    try {
        Report '预检' 0 '读取发布清单'

        $plan = Get-ETDownloadPlan -ApplicationId $ApplicationId -Version $Version
        if (-not $plan.Ok) {
            foreach ($e in $plan.Errors) { [void]$errs.Add($e) }
            return [pscustomobject]@{ Ok = $false; Status = 'PrecheckFailed'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $plan.TargetDir; FileCount = $plan.FileCount; Copied = 0; Verified = 0; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
        }

        $relRoot = '{0}\{1}' -f $ApplicationId, $Version
        $srcDir = $plan.SourceDir

        # 已下载过：先校验现有缓存，通过则直接返回（幂等）
        if (Test-Path -LiteralPath $plan.TargetDir) {
            $verify = Test-ETDownloadedPackage -ApplicationId $ApplicationId -Version $Version
            if ($verify.Ok) {
                Report '跳过' 100 '本机已有完整且校验通过的包'
                return [pscustomobject]@{ Ok = $true; Status = 'AlreadyDownloaded'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $plan.TargetDir; FileCount = $plan.FileCount; Copied = 0; Verified = $verify.VerifiedCount; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
            }
            Write-ETLog -Message '本机已有缓存但校验未通过，重新下载' -Level Warn
        }

        $partial = '{0}.partial' -f $plan.TargetDir
        $null = New-Item -ItemType Directory -Path $partial -Force

        Report '复制' 5 ('开始复制 {0} 个文件' -f $plan.FileCount)
        $copied = 0
        $files = @($plan.Files)
        foreach ($f in $files) {
            $srcFile = Join-Path $srcDir $f.RelativePath
            $dstFile = Join-Path $partial $f.RelativePath
            $dstDir = Split-Path -Parent $dstFile
            if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) { $null = New-Item -ItemType Directory -Path $dstDir -Force }

            if (-not (Test-Path -LiteralPath $srcFile)) {
                [void]$errs.Add("源文件缺失：$($f.RelativePath)")
                break
            }

            Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force -ErrorAction Stop
            $copied++
            $pct = 5 + [int](90 * $copied / [math]::Max($plan.FileCount, 1))
            Report '复制' $pct ('{0}/{1}' -f $copied, $plan.FileCount)
        }

        if ($errs.Count -gt 0) {
            return [pscustomobject]@{ Ok = $false; Status = 'CopyFailed'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $partial; FileCount = $plan.FileCount; Copied = $copied; Verified = 0; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
        }

        # 逐文件校验
        Report '校验' 95 '逐文件校验 SHA256'
        $verified = 0
        foreach ($f in $files) {
            $dstFile = Join-Path $partial $f.RelativePath
            $fi = Get-Item -LiteralPath $dstFile -ErrorAction SilentlyContinue
            if (-not $fi) { [void]$errs.Add("校验失败：文件不存在 $($f.RelativePath)"); continue }
            if ($f.Size -and $fi.Length -ne [long]$f.Size) { [void]$errs.Add("大小不符：$($f.RelativePath)（期望 $($f.Size) 实际 $($fi.Length)）"); continue }
            if (-not (Test-ETFileHash -LiteralPath $dstFile -ExpectedSha256 "$($f.Sha256)")) { [void]$errs.Add("SHA256 不符：$($f.RelativePath)"); continue }
            $verified++
        }

        if ($errs.Count -gt 0 -or $verified -ne $plan.FileCount) {
            if ($errs.Count -eq 0) { [void]$errs.Add("文件数不符：期望 $($plan.FileCount) 通过 $verified") }
            Write-ETLog -Message '下载校验未通过，保留 partial 供续传' -Level Warn
            return [pscustomobject]@{ Ok = $false; Status = 'VerifyFailed'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $partial; FileCount = $plan.FileCount; Copied = $copied; Verified = $verified; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
        }

        # 原子发布：partial -> target
        Report '发布' 98 '原子发布'
        if (Test-Path -LiteralPath $plan.TargetDir) { Remove-Item -LiteralPath $plan.TargetDir -Recurse -Force }
        Move-Item -LiteralPath $partial -Destination $plan.TargetDir -Force -ErrorAction Stop

        Report '完成' 100 '下载完成'
        $result = [pscustomobject]@{ Ok = $true; Status = 'Downloaded'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $plan.TargetDir; FileCount = $plan.FileCount; Copied = $copied; Verified = $verified; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
        try {
            Add-ETDownloadHistory -Record ([pscustomobject]@{
                ApplicationId = $ApplicationId; Version = $Version; Status = 'Downloaded'
                FileCount = $plan.FileCount; Verified = $verified
                TargetDir = $plan.TargetDir; FinishedAt = (Get-Date -Format 'o')
                DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            })
        }
        catch { Write-ETLog -Message '写下载记录失败' -Level Warn -Data @{ Error = $_.Exception.Message } }
        return $result
    }
    catch {
        [void]$errs.Add($_.Exception.Message)
        Write-ETLog -Message ("下载异常：{0}" -f $_.Exception.Message) -Level Error -Data @{ ApplicationId = $ApplicationId; Version = $Version }
        return [pscustomobject]@{ Ok = $false; Status = 'Exception'; ApplicationId = $ApplicationId; Version = $Version; TargetDir = $null; FileCount = 0; Copied = 0; Verified = 0; DurationSeconds = $sw.Elapsed.TotalSeconds; Errors = $errs }
    }
    finally {
        $script:TransferBusy = $false
        $sw.Stop()
    }
}

function Test-ETDownloadedPackage {
    <#
      .SYNOPSIS  校验本机缓存中的包是否完整（E-03 第 2 态取证）。
      .OUTPUTS   PSCustomObject { Ok; VerifiedCount; TotalCount; Errors[] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$Version
    )

    $errs = New-Object System.Collections.ArrayList
    $mv = Get-ETReleaseManifest -ApplicationId $ApplicationId -Version $Version
    if (-not $mv.Ok) {
        foreach ($e in $mv.Errors) { [void]$errs.Add($e) }
        return [pscustomobject]@{ Ok = $false; VerifiedCount = 0; TotalCount = 0; Errors = $errs }
    }

    $dir = Join-Path (Join-Path (Get-ETPath -Category LocalDir -Name Cache) $ApplicationId) $Version
    if (-not (Test-Path -LiteralPath $dir)) {
        [void]$errs.Add("本机缓存不存在：$dir")
        return [pscustomobject]@{ Ok = $false; VerifiedCount = 0; TotalCount = @($mv.Manifest.Files).Count; Errors = $errs }
    }

    $files = @($mv.Manifest.Files)
    $ok = 0
    foreach ($f in $files) {
        $p = Join-Path $dir $f.RelativePath
        if (-not (Test-Path -LiteralPath $p)) { [void]$errs.Add("缺失：$($f.RelativePath)"); continue }
        if (-not (Test-ETFileHash -LiteralPath $p -ExpectedSha256 "$($f.Sha256)")) { [void]$errs.Add("哈希不符：$($f.RelativePath)"); continue }
        $ok++
    }

    return [pscustomobject]@{ Ok = ($errs.Count -eq 0 -and $ok -eq $files.Count); VerifiedCount = $ok; TotalCount = $files.Count; Errors = $errs }
}

function Get-ETDownloadHistory {
    <#
      .SYNOPSIS  读取本机下载记录（E-03/E-05 用）。
      .OUTPUTS   PSCustomObject[]
    #>
    [CmdletBinding()]
    param([int]$Last = 50)

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Cache -Ensure) 'download-history.ndjson'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $lines = @(Get-Content -LiteralPath $f -Encoding UTF8 | Where-Object { $_ })
    $out = @()
    foreach ($l in ($lines | Select-Object -Last $Last)) {
        try { $out += , ($l | ConvertFrom-Json) } catch { continue }
    }
    return $out
}

function Add-ETDownloadHistory {
    <#
      .SYNOPSIS  追加一条下载记录（追加式，不覆盖）。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Record)

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Cache -Ensure) 'download-history.ndjson'
    Add-Content -LiteralPath $f -Value ($Record | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

Export-ModuleMember -Function @(
    'Get-ETReleaseManifest'
    'Test-ETFreeSpace'
    'Get-ETDownloadPlan'
    'Invoke-ETDownload'
    'Test-ETDownloadedPackage'
    'Get-ETDownloadHistory'
    'Add-ETDownloadHistory'
)
