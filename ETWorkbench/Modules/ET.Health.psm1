<#
.SYNOPSIS
    ET.Health —— 采集、评估、告警模型（方案 E-05 / §6.8）。

.DESCRIPTION
    告警模型（方案 §6.8）：
      Collect → Evaluate → Duration → Debounce → Deduplicate → Alarm → Recovery

    关键语义：
      · Duration  必须【持续】超过阈值才算，瞬时尖峰不告警
      · Debounce  连续 N 次采样都超阈值才升级为告警
      · Dedupe    同一 RuleId + Target 在 CooldownMinutes 内只报一次
      · Recovery  低于 RecoveryThreshold 且持续 RecoveryDurationMinutes 才恢复
      · UnknownIsNotFault：取不到数 ≠ 故障（方案 §6.5 / G-6）

    规则全部来自 Config\health-rules.json，改阈值【不改代码】（方案 §7 E-05 步骤 2）。

.NOTES
    编码要求：UTF-8 with BOM（约束 C-1）。
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Core.psm1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Software.psm1') -ErrorAction SilentlyContinue
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\ET.Outbox.psm1') -ErrorAction SilentlyContinue

function Get-ETRuleField {
    <#
      .SYNOPSIS  安全读取规则对象的字段（缺失时返回默认值，绝不抛异常）。

      .DESCRIPTION
        为什么需要它：Set-StrictMode -Version 2.0 下，对「不含该属性」的对象
        直接写 $Rule.Target 会抛「在此对象上找不到属性」。而 health-rules.json
        中只有部分规则需要 Target（例如 HR-CPU / HR-MEM 走 Cim 源，不需要 Target）。
        因此凡是读规则字段都必须走本函数。

        规则对象来自 ConvertTo-ETFlatHashtable，运行时是 OrderedDictionary；
        为兼容传入 PSCustomObject 的场景，两种形态都支持。

      .OUTPUTS   字段值，或 $Default
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Rule,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $Rule) { return $Default }

    if ($Rule -is [System.Collections.IDictionary]) {
        if ($Rule.Contains($Name)) { return $Rule[$Name] }
        return $Default
    }

    if (Test-ETObjectHasProperty -InputObject $Rule -Name $Name) { return $Rule.$Name }
    return $Default
}

function Get-ETMetric {
    <#
      .SYNOPSIS  按规则取一个指标值（E-05 步骤 3）。

      .DESCRIPTION
        Source 取值：Cim / PsDrive / ShareReachability / Service / Process / EventLog / Self
        取数失败返回 Status=Unknown，【不】抛出、【不】判定为故障。

      .OUTPUTS   PSCustomObject { Status; Value; Unit; Detail; ObservedAt }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rule)

    $now = Get-Date -Format 'o'
    $src = "$(Get-ETRuleField -Rule $Rule -Name 'Source' -Default '')"
    $met = "$(Get-ETRuleField -Rule $Rule -Name 'Metric' -Default '')"
    $tgt = "$(Get-ETRuleField -Rule $Rule -Name 'Target' -Default '')"
    $dur = Get-ETRuleField -Rule $Rule -Name 'DurationMinutes'
    $unknown = { param($msg) [pscustomobject]@{ Status = 'Unknown'; Value = $null; Unit = $null; Detail = $msg; ObservedAt = $now } }

    try {
        switch ($src) {

            'Cim' {
                switch ($met) {
                    'CpuLoadPercent' {
                        $c = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
                        $v = ($c | Measure-Object -Property LoadPercentage -Average).Average
                        return [pscustomobject]@{ Status = 'Ok'; Value = [math]::Round($v, 1); Unit = '%'; Detail = 'Win32_Processor.LoadPercentage'; ObservedAt = $now }
                    }
                    'AvailableMemoryPercent' {
                        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                        $v = 100.0 * [double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize
                        return [pscustomobject]@{ Status = 'Ok'; Value = [math]::Round($v, 1); Unit = '%'; Detail = 'FreePhysicalMemory / TotalVisibleMemorySize'; ObservedAt = $now }
                    }
                    default { return (& $unknown "未实现的 Cim 指标：$met") }
                }
            }

            'PsDrive' {
                $target = $tgt
                if ([string]::IsNullOrWhiteSpace($target) -or $target -like '{*') {
                    return (& $unknown '未配置 Target（如 {SoftwareRoot} / {BusinessDrive}）')
                }
                # Target 可以是盘符、目录或路径片段
                $probe = $target
                if ($target -match '^[A-Za-z]:') { $probe = $target.Substring(0, 2) + '\' }
                if (-not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Qualifier $target }

                $drive = (Get-Item -LiteralPath $probe -ErrorAction Stop).PSDrive
                if ($met -eq 'FreeSpacePercent') {
                    $v = 100.0 * [double]$drive.Free / [double]($drive.Free + $drive.Used)
                    return [pscustomobject]@{ Status = 'Ok'; Value = [math]::Round($v, 1); Unit = '%'; Detail = $probe; ObservedAt = $now }
                }
                if ($met -eq 'FreeSpaceBytes') {
                    return [pscustomobject]@{ Status = 'Ok'; Value = [long]$drive.Free; Unit = 'bytes'; Detail = $probe; ObservedAt = $now }
                }
                return (& $unknown "未实现的 PsDrive 指标：$met")
            }

            'ShareReachability' {
                $s = Get-ETShareReachableState
                if (-not $s.IsConfigured) { return (& $unknown '未配置共享根') }
                return [pscustomobject]@{ Status = 'Ok'; Value = $s.IsReachable; Unit = 'bool'; Detail = $s.Path; ObservedAt = $now }
            }

            'Service' {
                $names = @($tgt -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notlike '{*' })
                if ($names.Count -eq 0) { return (& $unknown '未配置 Target 服务名列表') }
                $bad = @()
                foreach ($n in $names) {
                    try {
                        $svc = Get-Service -Name $n -ErrorAction Stop
                        if ($svc.Status -ne 'Running') { $bad += ("{0}={1}" -f $n, $svc.Status) }
                    }
                    catch { $bad += ("{0}=NotFound" -f $n) }
                }
                return [pscustomobject]@{ Status = 'Ok'; Value = ($bad.Count -eq 0); Unit = 'bool'; Detail = if ($bad.Count) { $bad -join '; ' } else { '全部 Running' }; ObservedAt = $now }
            }

            'Process' {
                $names = @($tgt -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notlike '{*' })
                if ($names.Count -eq 0) { return (& $unknown '未配置 Target 进程名列表') }
                $missing = @()
                foreach ($n in $names) {
                    $r = Test-ETProcessRunning -ProcessName $n
                    if (-not $r.Running) { $missing += $n }
                }
                return [pscustomobject]@{ Status = 'Ok'; Value = ($missing.Count -eq 0); Unit = 'bool'; Detail = if ($missing.Count) { '缺少：' + ($missing -join ', ') } else { '全部在运行' }; ObservedAt = $now }
            }

            'EventLog' {
                $logs = @($tgt -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if ($logs.Count -eq 0) { $logs = @('System', 'Application') }
                $since = (Get-Date).AddMinutes(-[int]$dur)
                $count = 0
                foreach ($l in $logs) {
                    try {
                        $count += @(Get-WinEvent -FilterHashtable @{ LogName = $l; Level = 1, 2; StartTime = $since } -ErrorAction Stop).Count
                    }
                    catch {
                        # 无事件 / 无权限 —— 都不算故障
                        continue
                    }
                }
                return [pscustomobject]@{ Status = 'Ok'; Value = $count; Unit = 'count'; Detail = ('近 {0} 分钟（{1}）' -f $dur, ($logs -join '+')); ObservedAt = $now }
            }

            'Self' {
                if ($met -eq 'OutboxPendingCount') {
                    $n = Get-ETOutboxPendingCount
                    return [pscustomobject]@{ Status = 'Ok'; Value = [int]$n; Unit = 'count'; Detail = '本地未上报事件数'; ObservedAt = $now }
                }
                return (& $unknown "未实现的 Self 指标：$met")
            }

            default { return (& $unknown "未知的 Source：$src") }
        }
    }
    catch {
        return (& $unknown ("取数异常：" + $_.Exception.Message))
    }
}

function Get-ETComparatorSymbol {
    <#
      .SYNOPSIS  把 Comparator 名映射为数学符号（GUI 显示用）。
      .OUTPUTS   [string]
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Comparator)

    $map = @{
        'GreaterThan'        = '>'
        'GreaterThanOrEqual' = '>='
        'LessThan'           = '<'
        'LessThanOrEqual'    = '<='
        'Equals'             = '=='
        'NotEquals'          = '!='
    }
    if ($map.ContainsKey($Comparator)) { return $map[$Comparator] }
    return $Comparator
}

function Test-ETComparator {
    <#
      .SYNOPSIS  按 ComparatorMap 比较两个值。
      .OUTPUTS   [bool]
    #>
    [CmdletBinding()]
    param($Value, [string]$Comparator, $Threshold)

    if ($null -eq $Value) { return $false }
    try {
        switch ($Comparator) {
            'GreaterThan'        { return ([double]$Value -gt [double]$Threshold) }
            'GreaterThanOrEqual' { return ([double]$Value -ge [double]$Threshold) }
            'LessThan'           { return ([double]$Value -lt [double]$Threshold) }
            'LessThanOrEqual'    { return ([double]$Value -le [double]$Threshold) }
            'Equals'             { return ("$Value" -eq "$Threshold") }
            'NotEquals'          { return ("$Value" -ne "$Threshold") }
            default              { return $false }
        }
    }
    catch { return $false }
}

function Get-ETHealthState {
    <#
      .SYNOPSIS  读取健康状态机（历史采样与去重状态）。
      .DESCRIPTION
        存放于 <DataRoot>\Snapshot\health-state.json，用于跨次运行维持
        Duration / Debounce / Cooldown 语义（计划任务每次是【新进程】）。
      .OUTPUTS   PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot -Ensure) 'health-state.json'
    if (-not (Test-Path -LiteralPath $f)) {
        return [pscustomobject]@{ SchemaVersion = '1.0.0'; Rules = [pscustomobject]@{} }
    }

    $doc = $null
    try { $doc = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $doc = $null }

    # 语法能解析但结构不对（例如被写成了 {}）时，ConvertFrom-Json 不会抛错，
    # 于是坏状态会一路传到 $state.Rules 处才炸，表现为每轮检测都失败。
    # 这里显式归一化为空状态并记 Warn —— 记录在案，不是静默吞掉。
    if ($null -eq $doc -or -not (Test-ETObjectHasProperty -InputObject $doc -Name 'Rules')) {
        Write-ETLog -Message 'health-state.json 结构不合法（缺少 Rules），已按空状态继续' -Level Warn -Data @{ File = $f }
        return [pscustomobject]@{ SchemaVersion = '1.0.0'; Rules = [pscustomobject]@{} }
    }

    return $doc
}

function Save-ETHealthState {
    <#
      .SYNOPSIS  原子保存健康状态机。
      .NOTES
        必须传入【健康状态对象】（含 Rules）。与 Save-ETHealthSnapshot 同理，
        对非对象 / 缺 Rules 的输入直接报错，而不是写出一份坏状态机。

        为什么必须守：Get-ETHealthState 读回结果后，调用方要访问 $state.Rules；
        在本模块的 Set-StrictMode -Version 2.0 下，对不含该属性的对象读属性会
        【抛异常】。因此一旦写坏，后续每一轮 Invoke-ETHealthCheck 都会失败，
        而不是优雅降级 —— 坏状态比没有状态更危险。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)

    if ($null -eq $State -or $State -is [string] -or $State -is [System.Collections.IEnumerable]) {
        throw "Save-ETHealthState 需要健康状态对象（含 Rules），实际收到：$($State.GetType().FullName)"
    }
    if (-not (Test-ETObjectHasProperty -InputObject $State -Name 'Rules')) {
        throw 'Save-ETHealthState 收到的对象缺少 Rules 字段，不是合法的健康状态机，已拒绝写入以保护 health-state.json。'
    }

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot -Ensure) 'health-state.json'
    Write-ETJsonAtomic -LiteralPath $f -InputObject $State -Depth 8
}

function Invoke-ETHealthCheck {
    <#
      .SYNOPSIS  执行一轮健康检测（E-05 主入口，计划任务调用）。

      .DESCRIPTION
        流程：Collect 全部规则 -> 对每条规则施加 Duration/Debounce/Dedupe ->
              产出「当前告警集合」与「本轮事件」。
        Duration / Debounce 靠 health-state.json 跨进程维持。

      .PARAMETER PersistState  是否写回状态机（默认写）。
      .OUTPUTS   PSCustomObject { CheckedAt; Samples[]; Alarms[]; Events[]; Unknowns[] }
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$EquipmentId,
        [switch]$NoPersist
    )

    $rulesDoc = Get-ETHealthRules
    $g = $rulesDoc.Global
    $state = Get-ETHealthState

    $samples = New-Object System.Collections.ArrayList
    $alarms = New-Object System.Collections.ArrayList
    $events = New-Object System.Collections.ArrayList
    $unknowns = New-Object System.Collections.ArrayList

    if ($g.Enabled -eq $false) {
        return [pscustomobject]@{ CheckedAt = (Get-Date -Format 'o'); Samples = $samples; Alarms = $alarms; Events = $events; Unknowns = $unknowns }
    }

    # 新建状态容器
    $newRules = [ordered]@{}

    foreach ($rule in $rulesDoc.Rules) {
        if ($null -eq $rule) { continue }

        $ruleId = "$(Get-ETRuleField -Rule $rule -Name 'RuleId' -Default '')"
        $ruleName = "$(Get-ETRuleField -Rule $rule -Name 'Name' -Default '')"
        $ruleSeverity = "$(Get-ETRuleField -Rule $rule -Name 'Severity' -Default 'Warning')"
        $ruleComparator = "$(Get-ETRuleField -Rule $rule -Name 'Comparator' -Default '')"

        # 注意：Enabled 缺失时视为【启用】（与旧行为一致：只有显式 False 才跳过）
        $enabled = Get-ETRuleField -Rule $rule -Name 'Enabled' -Default $true
        if ("$enabled" -eq 'False') { continue }

        $metric = Get-ETMetric -Rule $rule
        $targetKey = "$(Get-ETRuleField -Rule $rule -Name 'Target' -Default '')"
        $stateKey = '{0}|{1}' -f $ruleId, $targetKey

        $prev = $null
        # 不能用 $state.Rules.PSObject.Properties.Name —— 空对象（属性数 0）时
        # 在 StrictMode 2.0 下会抛「找不到属性 Name」。统一走安全枚举。
        # 注意：必须加括号，否则 -contains 会被当成命令的参数而不是运算符。
        if ((Get-ETObjectPropertyNames -InputObject $state.Rules) -contains $stateKey) { $prev = $state.Rules.$stateKey }

        $prevBreachCount = if ($prev) { [int]$prev.BreachCount } else { 0 }
        $prevLastAlarm   = if ($prev -and $prev.LastAlarmTime) { $prev.LastAlarmTime } else { $null }
        $prevFirstBreach = if ($prev -and $prev.FirstBreachTime) { $prev.FirstBreachTime } else { $null }
        $prevActive      = if ($prev) { [bool]$prev.AlarmActive } else { $false }

        $sample = [pscustomobject]@{
            RuleId = $ruleId; Name = $ruleName; Target = $targetKey
            Status = $metric.Status; Value = $metric.Value; Unit = $metric.Unit
            Detail = $metric.Detail; Severity = $ruleSeverity; ObservedAt = $metric.ObservedAt
        }
        [void]$samples.Add($sample)

        if ($metric.Status -eq 'Unknown') {
            [void]$unknowns.Add($sample)
            $newRules[$stateKey] = [pscustomobject]@{ BreachCount = $prevBreachCount; FirstBreachTime = $prevFirstBreach; LastAlarmTime = $prevLastAlarm; AlarmActive = $prevActive; LastStatus = 'Unknown' }
            continue
        }

        $breached = Test-ETComparator -Value $metric.Value -Comparator $ruleComparator -Threshold (Get-ETRuleField -Rule $rule -Name 'Threshold' -Default $null)
        $recovered = $false
        $recoveryThreshold = Get-ETRuleField -Rule $rule -Name 'RecoveryThreshold' -Default $null
        if ($null -ne $recoveryThreshold -and "$recoveryThreshold" -ne '') {
            $recovered = -not (Test-ETComparator -Value $metric.Value -Comparator $ruleComparator -Threshold $recoveryThreshold)
        }

        $breachCount = if ($breached) { $prevBreachCount + 1 } else { 0 }
        $firstBreach = if ($breached -and $breachCount -eq 1) { (Get-Date -Format 'o') } else { $prevFirstBreach }
        $lastAlarm = $prevLastAlarm
        $alarmActive = $prevActive

        $debounceSamples = Get-ETRuleField -Rule $rule -Name 'DebounceSamples' -Default $null
        $debounce = if ($debounceSamples) { [int]$debounceSamples } else { 1 }

        if ($breached -and $breachCount -ge $debounce) {
            # Duration 判定：从首次越界到现在是否已持续够久
            $durationOk = $true
            $durationMinutes = Get-ETRuleField -Rule $rule -Name 'DurationMinutes' -Default $null
            if ($durationMinutes -and $firstBreach) {
                $elapsed = ((Get-Date) - [datetime]::Parse($firstBreach)).TotalMinutes
                $durationOk = ($elapsed -ge [int]$durationMinutes)
            }

            if ($durationOk) {
                # Dedupe：冷却期内不重复报
                $cool = if ($g.CooldownMinutes) { [int]$g.CooldownMinutes } else { 30 }
                $cdOk = $true
                if ($lastAlarm) { $cdOk = (((Get-Date) - [datetime]::Parse($lastAlarm)).TotalMinutes -ge $cool) }

                if ($cdOk) {
                    $alarm = [pscustomobject]@{
                        EventType     = 'Alarm'
                        RuleId        = $ruleId
                        Name          = $ruleName
                        Target        = $targetKey
                        Severity      = $ruleSeverity
                        Value         = $metric.Value
                        Unit          = $metric.Unit
                        Threshold     = (Get-ETRuleField -Rule $rule -Name 'Threshold' -Default $null)
                        Comparator    = $ruleComparator
                        ComparatorOp  = (Get-ETComparatorSymbol -Comparator $ruleComparator)
                        Detail        = $metric.Detail
                        DedupKey      = $stateKey
                        RaisedAt      = (Get-Date -Format 'o')
                    }
                    [void]$alarms.Add($alarm)
                    $lastAlarm = $alarm.RaisedAt
                    $alarmActive = $true
                }
            }
        }
        elseif ($recovered -and $alarmActive) {
            [void]$events.Add([pscustomobject]@{
                EventType  = 'AlarmRecovery'
                RuleId     = $ruleId
                Name       = $ruleName
                Target     = $targetKey
                Value      = $metric.Value
                Unit       = $metric.Unit
                Detail     = $metric.Detail
                RecoveredAt = (Get-Date -Format 'o')
            })
            $alarmActive = $false
            $breachCount = 0
        }
        elseif ($breached) {
            [void]$events.Add([pscustomobject]@{
                EventType  = 'RulePersisting'
                RuleId     = $ruleId
                Name       = $ruleName
                Target     = $targetKey
                Value      = $metric.Value
                Unit       = $metric.Unit
                BreachCount = $breachCount
                DebounceThreshold = $debounce
                Detail     = ("连续 {0}/{1} 次超阈值，未达持续时长" -f $breachCount, $debounce)
                ObservedAt = (Get-Date -Format 'o')
            })
        }

        $newRules[$stateKey] = [pscustomobject]@{
            BreachCount     = $breachCount
            FirstBreachTime = $firstBreach
            LastAlarmTime   = $lastAlarm
            AlarmActive     = $alarmActive
            LastStatus      = 'Ok'
            LastValue       = $metric.Value
        }
    }

    if (-not $NoPersist) {
        $newState = [pscustomobject]@{
            SchemaVersion = '1.0.0'
            UpdatedAt     = (Get-Date -Format 'o')
            Rules         = [pscustomobject]$newRules
        }
        try { Save-ETHealthState -State $newState }
        catch { Write-ETLog -Message '保存健康状态机失败' -Level Warn -Data @{ Error = $_.Exception.Message } }
    }

    $result = [pscustomobject]@{
        CheckedAt = (Get-Date -Format 'o')
        EquipmentId = $EquipmentId
        Samples   = $samples
        Alarms    = $alarms
        Events    = $events
        Unknowns  = $unknowns
    }

    Write-ETLog -Message ('健康检测完成：采样 {0}，告警 {1}，未知 {2}' -f $samples.Count, $alarms.Count, $unknowns.Count) -Level Info
    return $result
}

function Get-ETHealthSnapshot {
    <#
      .SYNOPSIS  读取最近一次健康采样结果（GUI「健康」页签数据源，不重新采集）。
      .OUTPUTS   PSCustomObject / $null
    #>
    [CmdletBinding()]
    param()

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot) 'health-last.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Save-ETHealthSnapshot {
    <#
      .SYNOPSIS  原子保存最近一次健康采样结果。
      .NOTES
        必须传入【健康检测结果对象】（含 Samples/Alarms/Events）。
        若只传字符串/数组等非对象（常见于把函数的展示文本误当参数），
        直接报错而不是写出一份坏快照 —— 曾经因为这种误传写坏过 health-last.json。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result)

    if ($null -eq $Result -or $Result -is [string] -or $Result -is [System.Collections.IEnumerable]) {
        throw "Save-ETHealthSnapshot 需要健康检测结果对象（含 Samples/Alarms/Events），实际收到：$($Result.GetType().FullName)"
    }
    if (-not (Test-ETObjectHasProperty -InputObject $Result -Name 'Samples')) {
        throw 'Save-ETHealthSnapshot 收到的对象缺少 Samples 字段，不是合法的健康检测结果。'
    }

    $f = Join-Path (Get-ETPath -Category LocalDir -Name Snapshot -Ensure) 'health-last.json'
    Write-ETJsonAtomic -LiteralPath $f -InputObject $Result -Depth 8
}

function Get-ETHealthMetrics {
    <#
      .SYNOPSIS  返回最近一次采样结果中的【指标行】，用于 GUI 表格（未采集时返回空数组）。

      .DESCRIPTION
        与 Get-ETHealthSnapshot 的区别：本函数做「投影 + 扁平化」，
        直接给出适合 DataGrid 显示的列，不把整个快照丢给界面。

      .OUTPUTS   PSCustomObject[] { RuleId; Name; Target; Value; Unit; Status; Severity; Detail; ObservedAt }
    #>
    [CmdletBinding()]
    param()

    $snap = Get-ETHealthSnapshot
    if (-not $snap -or -not (Test-ETObjectHasProperty -InputObject $snap -Name 'Samples')) { return @() }

    $rows = @()
    foreach ($s in @($snap.Samples | Where-Object { $null -ne $_ })) {
        $rows += [pscustomobject]@{
            RuleId     = "$($s.RuleId)"
            Name       = "$($s.Name)"
            Target     = "$($s.Target)"
            Value      = $s.Value
            Unit       = "$($s.Unit)"
            Status     = "$($s.Status)"
            Severity   = "$($s.Severity)"
            Detail     = "$($s.Detail)"
            ObservedAt = "$($s.ObservedAt)"
        }
    }
    return $rows
}

function Get-ETHealthMetricCatalog {
    <#
      .SYNOPSIS  列出已实现的指标 Source/Metric 组合，供 GUI 与自检显示覆盖面。
      .OUTPUTS   PSCustomObject[] { Source; Metric; Implemented }
    #>
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Source = 'Cim';               Metric = 'CpuLoadPercent';         Implemented = $true }
        [pscustomobject]@{ Source = 'Cim';               Metric = 'AvailableMemoryPercent'; Implemented = $true }
        [pscustomobject]@{ Source = 'PsDrive';           Metric = 'FreeSpacePercent';       Implemented = $true }
        [pscustomobject]@{ Source = 'PsDrive';           Metric = 'FreeSpaceBytes';         Implemented = $true }
        [pscustomobject]@{ Source = 'ShareReachability'; Metric = 'IsReachable';            Implemented = $true }
        [pscustomobject]@{ Source = 'Service';           Metric = 'Status';                 Implemented = $true }
        [pscustomobject]@{ Source = 'Process';           Metric = 'IsRunning';              Implemented = $true }
        [pscustomobject]@{ Source = 'EventLog';          Metric = 'ErrorCount';             Implemented = $true }
        [pscustomobject]@{ Source = 'Self';              Metric = 'OutboxPendingCount';     Implemented = $true }
    )
}

Export-ModuleMember -Function @(
    'Get-ETMetric'
    'Get-ETComparatorSymbol'
    'Test-ETComparator'
    'Get-ETHealthState'
    'Save-ETHealthState'
    'Invoke-ETHealthCheck'
    'Get-ETHealthSnapshot'
    'Save-ETHealthSnapshot'
    'Get-ETHealthMetrics'
    'Get-ETHealthMetricCatalog'
)
