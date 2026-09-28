<#
.SYNOPSIS
    ET.Core —— 工作台核心基础模块。

.DESCRIPTION
    职责（方案 §5.4）：
      · 路径推导（约束 C-2：禁止硬编码，全部由 $PSScriptRoot 推导）
      · 配置加载（workstation.json / paths.json）
      · 本地数据根初始化（C:\ProgramData\ETWorkbench）
      · 日志（Write-ETLog）
      · JSON 读写与【原子写】（约束 C-4）
      · 原子发布（.tmp -> 校验 -> .ready）
      · 文件哈希与校验
      · 事件编号生成（约束 C-5：One Event = One File）
      · 最小审计埋点（对接未来 A-09 审计）

.NOTES
    编码要求：本文件必须保存为 UTF-8 with BOM（约束 C-1）。

    本模块【不】做任何业务判断，只提供基础设施。
    本模块【不】写共享写操作（共享写由 ET.Outbox 负责，遵守权限矩阵）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ================================================================ 模块状态

# 绿色包根目录：Modules 的上一级
$script:ProgramRoot = Split-Path -Parent $PSScriptRoot

# 惰性加载的配置缓存
$script:Config          = $null
$script:Paths           = $null
$script:DataRoot        = $null
$script:DataRootReady   = $false

# ================================================================ 私有工具

function Get-ETObjectPropertyNames {
    <#
      .SYNOPSIS  安全枚举对象的属性名（缺失/空对象时返回 @()，绝不抛异常）。

      .DESCRIPTION
        为什么需要它：PowerShell 5.1 + Set-StrictMode -Version 2.0 下，
        「成员枚举」写法 $obj.PSObject.Properties.Name 在对象属性数为 0 时
        【会抛】「在此对象上找不到属性 Name」，而不是返回空值。
        只有 >=1 个属性时才正常。

        已实测（PowerShell 5.1.19041.6456 / StrictMode 2.0）：
          [pscustomobject]@{}.PSObject.Properties.Name        -> THROW
          [pscustomobject]@{A=1}.PSObject.Properties.Name     -> OK ('A')
          @(obj.PSObject.Properties | ? { $_.Name })          -> OK (空数组)

        因此所有属性枚举必须走本函数（或等价的管道写法）。

      .OUTPUTS   [string[]]
    #>
    [CmdletBinding()]
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return @() }

    $names = @($InputObject.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return @() }
    return $names
}

function Test-ETObjectHasProperty {
    <#
      .SYNOPSIS  判断对象是否含指定属性（StrictMode 2.0 安全）。
      .OUTPUTS   [bool]
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $false }
    return (@(Get-ETObjectPropertyNames -InputObject $InputObject) -contains $Name)
}

function ConvertTo-ETFlatHashtable {
    <#
      .SYNOPSIS  把 PSCustomObject 递归转换为有序 Hashtable，便于安全取值。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in $InputObject.Keys) {
            if ($k -like '_comment*') { continue }   # 跳过注释键
            $h[$k] = ConvertTo-ETFlatHashtable -InputObject $InputObject[$k]
        }
        return $h
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            if ($p.Name -like '_comment*') { continue }
            if ($p.Name -eq '$schema') { continue }
            $h[$p.Name] = ConvertTo-ETFlatHashtable -InputObject $p.Value
        }
        return $h
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $arr = @()
        foreach ($i in $InputObject) { $arr += , (ConvertTo-ETFlatHashtable -InputObject $i) }
        return $arr
    }

    return $InputObject
}

function Get-ETConfigFilePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FileName)
    return (Join-Path (Join-Path $script:ProgramRoot 'Config') $FileName)
}

function Read-ETJsonFile {
    <#
      .SYNOPSIS  读取 UTF-8 JSON 文件（兼容 BOM）。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        throw "配置文件不存在：$LiteralPath"
    }

    $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "配置文件为空：$LiteralPath"
    }

    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        throw ("配置文件不是合法 JSON：{0} —— {1}" -f $LiteralPath, $_.Exception.Message)
    }
}

# ================================================================ 公开：路径

function Get-ETProgramRoot {
    <#
      .SYNOPSIS  绿色包根目录（约束 C-2：由 $PSScriptRoot 推导）。
    #>
    [CmdletBinding()]
    param()
    return $script:ProgramRoot
}

function Get-ETPath {
    <#
      .SYNOPSIS  按 paths.json 契约解析路径。

      .DESCRIPTION
        Category：
          ProgramDir  -> 绿色包内目录（UI / Modules / Tasks / Config）
          LocalDir    -> 本机数据目录（Config / Snapshot / Commands / Results / Outbox / Logs / Temp ...）
          File        -> 本机数据目录下的文件名
          UploadSub   -> 共享 Upload 子目录名
        -Ensure 会在需要时创建目录（仅限本地目录，不会创建共享目录）。

      .EXAMPLE
        Get-ETPath -Category LocalDir -Name Snapshot -Ensure
        Get-ETPath -Category LocalDir -Name Logs
        Get-ETPath -Category ProgramDir -Name Ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ProgramDir', 'LocalDir', 'File', 'UploadSub')][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [switch]$Ensure
    )

    $paths = Get-ETPathsConfig
    $root = switch ($Category) {
        'ProgramDir' { $script:ProgramRoot }
        'UploadSub'  { return $paths.UploadSubDirs[$Name] }
        default      { Get-ETDataRoot -Ensure:$Ensure }
    }

    if ($Category -eq 'ProgramDir') {
        if (-not $paths.ProgramDirs.Contains($Name)) { throw "未知的 ProgramDir：$Name" }
        $rel = $paths.ProgramDirs[$Name]
    }
    elseif ($Category -eq 'LocalDir') {
        if (-not $paths.LocalDirs.Contains($Name)) { throw "未知的 LocalDir：$Name" }
        $rel = $paths.LocalDirs[$Name]
    }
    else {
        # File：文件位于 LocalDir 根下的哪个子目录由调用方决定，这里要求 Name 直接是文件名
        if (-not $paths.FileNames.Contains($Name)) { throw "未知的 File：$Name" }
        return $paths.FileNames[$Name]
    }

    $full = Join-Path $root $rel
    if ($Ensure -and $Category -eq 'LocalDir') {
        if (-not (Test-Path -LiteralPath $full)) {
            $null = New-Item -ItemType Directory -Path $full -Force
        }
    }
    return $full
}

# ================================================================ 公开：配置

function Get-ETConfig {
    <#
      .SYNOPSIS  读取本机配置 workstation.json（结果缓存）。
      .PARAMETER Reload  强制重新读取。
    #>
    [CmdletBinding()]
    param([switch]$Reload)

    if ($null -ne $script:Config -and -not $Reload) { return $script:Config }

    $file = Get-ETConfigFilePath -FileName 'workstation.json'
    $obj = Read-ETJsonFile -LiteralPath $file
    $script:Config = ConvertTo-ETFlatHashtable -InputObject $obj
    return $script:Config
}

function Get-ETPathsConfig {
    <#
      .SYNOPSIS  读取目录契约 paths.json（结果缓存）。
      .PARAMETER Reload  强制重新读取。
    #>
    [CmdletBinding()]
    param([switch]$Reload)

    if ($null -ne $script:Paths -and -not $Reload) { return $script:Paths }

    $file = Get-ETConfigFilePath -FileName 'paths.json'
    $obj = Read-ETJsonFile -LiteralPath $file
    $script:Paths = ConvertTo-ETFlatHashtable -InputObject $obj
    return $script:Paths
}

function Get-ETHealthRules {
    <#
      .SYNOPSIS  读取健康规则 health-rules.json（E-05 使用）。
    #>
    [CmdletBinding()]
    param()

    $file = Get-ETConfigFilePath -FileName 'health-rules.json'
    $obj = Read-ETJsonFile -LiteralPath $file
    $h = ConvertTo-ETFlatHashtable -InputObject $obj

    $rules = @()
    foreach ($r in $h.Rules) {
        $rules += , $r
    }
    return [pscustomobject]@{
        Global = $h.Global
        Rules  = $rules
    }
}

function Get-ETShareRoot {
    <#
      .SYNOPSIS  共享根 UNC 路径（未配置时返回 $null，不抛异常）。
    #>
    [CmdletBinding()]
    param()

    $cfg = Get-ETConfig
    $shareRoot = $cfg.Share.ShareRoot
    if ([string]::IsNullOrWhiteSpace($shareRoot)) { return $null }
    return $shareRoot.TrimEnd('\')
}

function Get-ETSharePath {
    <#
      .SYNOPSIS  解析共享下的子路径。
      .DESCRIPTION
        Category：MasterData / Release / ConfigRules / Upload / Archive
        共享不可达时返回路径字符串本身（调用方负责 Test-Path）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('MasterData', 'Release', 'ConfigRules', 'Upload', 'Archive')][string]$Category,
        [string[]]$ChildSegments = @()
    )

    $shareRoot = Get-ETShareRoot
    if (-not $shareRoot) { return $null }

    $cfg = Get-ETConfig
    $rel = switch ($Category) {
        'MasterData'  { $cfg.Share.MasterDataRelative }
        'Release'     { $cfg.Share.ReleaseRelative }
        'ConfigRules' { $cfg.Share.ConfigRulesRelative }
        'Upload'      { $cfg.Share.UploadRelative }
        'Archive'     { 'Archive' }
    }

    $p = Join-Path $shareRoot $rel
    foreach ($seg in $ChildSegments) {
        if (-not [string]::IsNullOrWhiteSpace($seg)) { $p = Join-Path $p $seg }
    }
    return $p
}

function Test-ETShareReachable {
    <#
      .SYNOPSIS  共享根是否可达（E-05 检测项 4 / HR-SHARE 规则）。
      .OUTPUTS   [bool]
    #>
    [CmdletBinding()]
    param()
    return [bool](Get-ETShareReachableState)
}

function Get-ETShareReachableState {
    <#
      .SYNOPSIS  共享可达性详情。
      .OUTPUTS   PSCustomObject { IsReachable; IsConfigured; Path; Error }
    #>
    [CmdletBinding()]
    param()

    $shareRoot = Get-ETShareRoot
    if (-not $shareRoot) {
        return [pscustomobject]@{ IsReachable = $false; IsConfigured = $false; Path = $null; Error = '未配置 Share.ShareRoot' }
    }

    try {
        $null = Get-ChildItem -LiteralPath $shareRoot -ErrorAction Stop | Select-Object -First 1
        return [pscustomobject]@{ IsReachable = $true; IsConfigured = $true; Path = $shareRoot; Error = $null }
    }
    catch {
        return [pscustomobject]@{ IsReachable = $false; IsConfigured = $true; Path = $shareRoot; Error = $_.Exception.Message }
    }
}

# ================================================================ 公开：数据根

function Get-ETDataRoot {
    <#
      .SYNOPSIS  本机数据根（默认 C:\ProgramData\ETWorkbench，可被配置覆盖）。
    #>
    [CmdletBinding()]
    param([switch]$Ensure)

    if ($null -eq $script:DataRoot) {
        $cfg = Get-ETConfig
        $root = $cfg.Local.DataRoot
        if ([string]::IsNullOrWhiteSpace($root)) {
            $root = (Get-ETPathsConfig).DataRoot.Default
        }
        $script:DataRoot = $root
    }

    if ($Ensure) { $null = Initialize-ETDataRoot }
    return $script:DataRoot
}

function Initialize-ETDataRoot {
    <#
      .SYNOPSIS  创建本机数据根与全部子目录（幂等）。
      .DESCRIPTION
        失败时抛异常（P-6：ProgramData 必须可读写）。
        只创建【本地】目录，绝不触碰共享。
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($script:DataRootReady -and -not $Force) { return $script:DataRoot }

    $root = Get-ETDataRoot
    $paths = Get-ETPathsConfig

    $dirs = @($root)
    foreach ($k in $paths.LocalDirs.Keys) {
        $rel = $paths.LocalDirs[$k]
        if ($rel) { $dirs += (Join-Path $root $rel) }
    }

    foreach ($d in ($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) {
            $null = New-Item -ItemType Directory -Path $d -Force
        }
    }

    $script:DataRootReady = $true
    return $root
}

# ================================================================ 公开：日志

function Write-ETLog {
    <#
      .SYNOPSIS  写工作台日志（本地 Logs 目录，按天分文件）。

      .DESCRIPTION
        日志失败【不】中断业务——只会静默降级到控制台。
        这是基础设施，必须比业务更健壮。

      .PARAMETER Message  日志正文。
      .PARAMETER Level    Info / Warn / Error / Debug。
      .PARAMETER Data     附加键值对，序列化进日志行。
      .PARAMETER Console  同时输出到控制台（默认 Info 及以上）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$Level = 'Info',
        [hashtable]$Data,
        [switch]$Console
    )

    $line = [ordered]@{
        Time    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
        Level   = $Level
        Pid     = $PID
        Message = $Message
    }
    if ($Data) { $line['Data'] = $Data }

    try {
        $cfg = Get-ETConfig
        $minLevel = $cfg.Ui.LogLevel
        $order = @{ 'Debug' = 0; 'Info' = 1; 'Warn' = 2; 'Error' = 3 }
        if (-not $minLevel) { $minLevel = 'Info' }
        if ($order[$Level] -lt $order[$minLevel]) { return }
    }
    catch {
        # 配置读不到也不阻断日志
    }

    $json = $line | ConvertTo-Json -Compress -Depth 4

    try {
        $logDir = Get-ETPath -Category LocalDir -Name Logs -Ensure
        $logFile = Join-Path $logDir ('et-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        Add-Content -LiteralPath $logFile -Value $json -Encoding UTF8
    }
    catch {
        # 日志写失败不抛异常
        if ($Level -eq 'Error') {
            Write-Host ("[ETLog-Fallback][{0}] {1}" -f $Level, $Message) -ForegroundColor DarkRed
        }
    }

    if ($Console -or $Level -eq 'Error') {
        $color = switch ($Level) {
            'Debug' { 'DarkGray' }
            'Info'  { 'Gray' }
            'Warn'  { 'Yellow' }
            'Error' { 'Red' }
        }
        Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
    }
}

# ================================================================ 公开：哈希

function Get-ETFileHash {
    <#
      .SYNOPSIS  计算文件 SHA256（大写十六进制）。
      .NOTES    与 manifest.json 中的 sha256 字段比对时统一 ToUpperInvariant()。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)

    $h = Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256 -ErrorAction Stop
    return $h.Hash.ToUpperInvariant()
}

function Test-ETFileHash {
    <#
      .SYNOPSIS  校验文件 SHA256。
      .OUTPUTS   [bool]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $false }
    try {
        $actual = Get-ETFileHash -LiteralPath $LiteralPath
        return ($actual -eq $ExpectedSha256.ToUpperInvariant())
    }
    catch {
        return $false
    }
}

# ================================================================ 公开：原子写

function Write-ETJsonAtomic {
    <#
      .SYNOPSIS  原子写 JSON（约束 C-4：.tmp -> 校验 -> rename）。

      .DESCRIPTION
        流程：
          1) 写入 <目标>.tmp
          2) 回读并验证是合法 JSON，且长度 > 0
          3) Move-Item 到目标（同目录 rename 在 NTFS 上原子）

        这样任何时刻都不会存在「半截的可用文件」。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [int]$Depth = 10,
        [switch]$PassThru
    )

    $dir = Split-Path -Parent $LiteralPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $tmp = '{0}.tmp' -f $LiteralPath
    $json = $InputObject | ConvertTo-Json -Depth $Depth

    Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8 -ErrorAction Stop

    # 回读校验
    $back = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($back)) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "原子写失败：临时文件为空（$tmp）"
    }
    try {
        $null = $back | ConvertFrom-Json
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw ("原子写失败：序列化结果不是合法 JSON —— {0}" -f $_.Exception.Message)
    }

    Move-Item -LiteralPath $tmp -Destination $LiteralPath -Force -ErrorAction Stop

    if ($PassThru) { return Get-Item -LiteralPath $LiteralPath }
}

function Write-ETTextAtomic {
    <#
      .SYNOPSIS  原子写文本文件（同 Write-ETJsonAtomic，但不校验 JSON）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $dir = Split-Path -Parent $LiteralPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $tmp = '{0}.tmp' -f $LiteralPath
    Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8 -ErrorAction Stop

    $back = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
    if ($null -eq $back) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "原子写失败：临时文件读回为 null（$tmp）"
    }

    Move-Item -LiteralPath $tmp -Destination $LiteralPath -Force -ErrorAction Stop
}

function Publish-ETFileAtomic {
    <#
      .SYNOPSIS  原子发布一个已就绪的临时文件（约束 C-4）。

      .DESCRIPTION
        用于共享写入：先把内容写成本地/共享上的 .tmp，
        校验通过后 rename 为 .ready（或目标名），保证下游绝不读到半截文件。

      .PARAMETER SourcePath   已写好的源文件（通常是 .tmp）。
      .PARAMETER TargetPath   最终目标路径。
      .PARAMETER ExpectedSize 可选：期望字节数，不符则拒绝发布。
      .PARAMETER ExpectedSha256 可选：期望哈希，不符则拒绝发布。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [long]$ExpectedSize = -1,
        [string]$ExpectedSha256 = ''
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "原子发布失败：源文件不存在（$SourcePath）"
    }

    $fi = Get-Item -LiteralPath $SourcePath

    if ($ExpectedSize -ge 0 -and $fi.Length -ne $ExpectedSize) {
        throw ("原子发布失败：大小不符（期望 {0}，实际 {1}）—— {2}" -f $ExpectedSize, $fi.Length, $SourcePath)
    }

    if ($ExpectedSha256 -and $ExpectedSha256 -ne '') {
        if (-not (Test-ETFileHash -LiteralPath $SourcePath -ExpectedSha256 $ExpectedSha256)) {
            throw ("原子发布失败：SHA256 不符 —— {0}" -f $SourcePath)
        }
    }

    $dir = Split-Path -Parent $TargetPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    Move-Item -LiteralPath $SourcePath -Destination $TargetPath -Force -ErrorAction Stop
    return Get-Item -LiteralPath $TargetPath
}

# ================================================================ 公开：事件编号

function New-ETEventId {
    <#
      .SYNOPSIS  生成事件编号（约束 C-5：One Event = One File）。

      .DESCRIPTION
        格式：<前缀>-<EquipmentId>-<yyyyMMdd>-<6位序号>
        序号按当天该前缀下的已有文件数递增，避免并发冲突时靠重试。

      .PARAMETER Prefix        事件前缀：EVT（健康）/ ALM（告警）/ DEP（部署）/ AUD（审计）。
      .PARAMETER EquipmentId   设备编号。
      .PARAMETER Directory     事件所在目录（用于计算当日序号）；为空则不查序号。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('EVT', 'ALM', 'DEP', 'AUD')][string]$Prefix,
        [Parameter(Mandatory)][string]$EquipmentId,
        [string]$Directory = ''
    )

    $seq = 1
    if ($Directory -and (Test-Path -LiteralPath $Directory)) {
        $pattern = '{0}-{1}-{2}-*.ndjson' -f $Prefix, $EquipmentId, (Get-Date -Format 'yyyyMMdd')
        $existing = @(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue)
        $seq = $existing.Count + 1
    }

    return ('{0}-{1}-{2}-{3:D6}' -f $Prefix, $EquipmentId, (Get-Date -Format 'yyyyMMdd'), $seq)
}

function New-ETRequestId {
    <#
      .SYNOPSIS  GUI <-> 后台通信用的请求关联 ID（方案 §4.2）。
    #>
    [CmdletBinding()]
    param()
    return [guid]::NewGuid().ToString('N')
}

# ================================================================ 公开：审计埋点

function Write-ETAuditEvent {
    <#
      .SYNOPSIS  最小审计埋点（方案 §7 E-05 步骤 9，未来对接 A-09）。

      .DESCRIPTION
        把操作事实写成事件对象返回，由 ET.Outbox 负责落盘。
        本函数【不】直接写共享。

        审计字段：Who / When / EquipmentId / Operation / Target / Result / Detail
        严禁写入配置明文、密码、Token（方案 §10.2 数据脱敏）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EquipmentId,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][ValidateSet('Success', 'Failure', 'Denied', 'Started')][string]$Result,
        [string]$Target = '',
        [string]$Detail = ''
    )

    $id = New-ETEventId -Prefix 'AUD' -EquipmentId $EquipmentId

    return [pscustomobject]@{
        EventId     = $id
        EventType   = 'Audit'
        EquipmentId = $EquipmentId
        CreatedTime = (Get-Date -Format 'o')
        Who         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Operation   = $Operation
        Target      = $Target
        Result      = $Result
        Detail      = $Detail
        SchemaVersion = '1.0.0'
    }
}

# ================================================================ 公开：摘要

function Get-ETCoreInfo {
    <#
      .SYNOPSIS  返回基础环境摘要，供 GUI 顶部状态条与自检使用。
    #>
    [CmdletBinding()]
    param()

    $shareState = Get-ETShareReachableState

    return [pscustomobject]@{
        ModuleVersion    = '1.0.0'
        ProgramRoot      = $script:ProgramRoot
        DataRoot         = Get-ETDataRoot
        DataRootReady    = $script:DataRootReady
        ShareRoot        = (Get-ETShareRoot)
        ShareReachable   = $shareState.IsReachable
        ShareError       = $shareState.Error
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        ExecutionPolicy  = (Get-ExecutionPolicy).ToString()
        ComputerName     = $env:COMPUTERNAME
        UserName         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        IsElevated       = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

function Test-ETWorkbench {
    <#
      .SYNOPSIS  工作台自检（E-06 自更新的冒烟测试入口，方案 §7 E-06 步骤 6）。

      .OUTPUTS   PSCustomObject { Ok; Checks[]; Message }
    #>
    [CmdletBinding()]
    param()

    $checks = New-Object System.Collections.ArrayList

    function Add-Check {
        param([string]$Name, [bool]$Ok, [string]$Detail = '')
        [void]$checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    }

    # 1) 模块自身可加载
    Add-Check 'ET.Core 已加载' $true $script:ProgramRoot

    # 2) 配置文件可读
    try {
        $null = Get-ETConfig -Reload
        Add-Check 'workstation.json 可读' $true ''
    }
    catch { Add-Check 'workstation.json 可读' $false $_.Exception.Message }

    try {
        $null = Get-ETPathsConfig -Reload
        Add-Check 'paths.json 可读' $true ''
    }
    catch { Add-Check 'paths.json 可读' $false $_.Exception.Message }

    try {
        $null = Get-ETHealthRules
        Add-Check 'health-rules.json 可读' $true ''
    }
    catch { Add-Check 'health-rules.json 可读' $false $_.Exception.Message }

    # 3) 本地数据根可写
    try {
        $null = Initialize-ETDataRoot -Force
        $probe = Join-Path (Get-ETPath -Category LocalDir -Name Temp -Ensure) '__smoke.tmp'
        'ok' | Set-Content -LiteralPath $probe -Encoding UTF8
        Remove-Item -LiteralPath $probe -Force
        Add-Check '本地数据根可写' $true (Get-ETDataRoot)
    }
    catch { Add-Check '本地数据根可写' $false $_.Exception.Message }

    # 4) 其他模块是否可导入
    foreach ($m in @('ET.Identity', 'ET.MasterData', 'ET.Software', 'ET.Transfer', 'ET.Health', 'ET.Outbox', 'ET.Update')) {
        $mp = Join-Path (Join-Path $script:ProgramRoot 'Modules') ($m + '.psm1')
        if (-not (Test-Path -LiteralPath $mp)) {
            Add-Check ("模块 {0}" -f $m) $false '文件不存在'
            continue
        }
        try {
            $errs = $null
            $toks = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($mp, [ref]$toks, [ref]$errs)
            if ($errs -and @($errs).Count -gt 0) {
                Add-Check ("模块 {0}" -f $m) $false ($errs[0].Message)
            }
            else {
                Add-Check ("模块 {0}" -f $m) $true '语法通过'
            }
        }
        catch { Add-Check ("模块 {0}" -f $m) $false $_.Exception.Message }
    }

    # 5) 共享可达（不通过【不】算失败——断网时工作台必须仍可用，G-6）
    $shareState = Get-ETShareReachableState
    if (-not $shareState.IsConfigured) {
        Add-Check '共享可达' $true '未配置（断网可用，G-6 允许）'
    }
    else {
        Add-Check '共享可达' $shareState.IsReachable ($shareState.Error)
    }

    $failed = @($checks | Where-Object { -not $_.Ok })

    return [pscustomobject]@{
        Ok      = ($failed.Count -eq 0)
        Checks  = $checks
        Message = if ($failed.Count -eq 0) { '自检通过' } else { ('自检失败 {0} 项' -f $failed.Count) }
    }
}

# ================================================================ 导出

Export-ModuleMember -Function @(
    'Get-ETProgramRoot'
    'Get-ETPath'
    'Get-ETConfig'
    'Get-ETPathsConfig'
    'Get-ETHealthRules'
    'Get-ETShareRoot'
    'Get-ETSharePath'
    'Test-ETShareReachable'
    'Get-ETShareReachableState'
    'Get-ETDataRoot'
    'Initialize-ETDataRoot'
    'Write-ETLog'
    'Get-ETFileHash'
    'Test-ETFileHash'
    'Write-ETJsonAtomic'
    'Write-ETTextAtomic'
    'Publish-ETFileAtomic'
    'New-ETEventId'
    'New-ETRequestId'
    'Write-ETAuditEvent'
    'Get-ETObjectPropertyNames'
    'Test-ETObjectHasProperty'
    'Get-ETCoreInfo'
    'Test-ETWorkbench'
)
