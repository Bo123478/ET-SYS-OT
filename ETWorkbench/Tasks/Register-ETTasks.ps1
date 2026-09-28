<#
.SYNOPSIS
    Register-ETTasks —— 注册/注销工作台的三个计划任务（E-05 后台常驻）。

.DESCRIPTION
    在工作台【本机】注册以下计划任务（不使用 Windows 服务，决策 2）：

      ET-HealthMonitor   每 Health.CollectIntervalMinutes 分钟执行一次健康采集
      ET-OutboxPublish   每 Health.OutboxPublishIntervalMinutes 分钟执行一次补传
      ET-WatchCommands   每 5 分钟轮询一次命令目录

    设计要点：
      - 全部以【当前用户】身份运行（该用户需能访问共享，IT-11）。
      - 使用 powershell.exe -NoProfile -ExecutionPolicy Bypass -File（决策 20：允许未签名脚本）。
      - -WindowStyle Hidden，避免弹窗打断现场作业（红线 F-4：不抢焦点）。
      - 任务动作的脚本路径由 $PSScriptRoot 推导（约束 C-2）。
      - 三个任务都【不】需要联网，断网时算法上仍安全（G-6）。

.PARAMETER Unregister   注销这三个计划任务。
.PARAMETER Force        已存在时先删除再重建（默认即覆盖）。
.PARAMETER RunNow       注册后立即各跑一次，便于验证。
.PARAMETER WhatIf       只打印将要执行的动作，不做任何更改。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Tasks\Register-ETTasks.ps1 -RunNow
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Tasks\Register-ETTasks.ps1 -Unregister
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Unregister,
    [switch]$Force,
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

# ---- 自定位（约束 C-2）
$TaskDir = $PSScriptRoot
$Root = Split-Path -Parent $TaskDir
$ModuleDir = Join-Path $Root 'Modules'

Import-Module (Join-Path $ModuleDir 'ET.Core.psm1') -Force -ErrorAction Stop

$cfg = Get-ETConfig
$healthEvery = if ($cfg.Health.CollectIntervalMinutes) { [int]$cfg.Health.CollectIntervalMinutes } else { 15 }
$outboxEvery = if ($cfg.Health.OutboxPublishIntervalMinutes) { [int]$cfg.Health.OutboxPublishIntervalMinutes } else { 10 }

$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = 'powershell.exe' }

# 任务定义（名称 -> 脚本 + 间隔分钟）
$taskDefs = @(
    [pscustomobject]@{ Name = 'ET-HealthMonitor'; Script = 'Invoke-HealthMonitor.ps1'; EveryMinutes = $healthEvery; Description = 'ET 工作台：周期健康采集与事件落盘' }
    [pscustomobject]@{ Name = 'ET-OutboxPublish'; Script = 'Publish-Outbox.ps1'; EveryMinutes = $outboxEvery; Description = 'ET 工作台：周期补传本地 Outbox' }
    [pscustomobject]@{ Name = 'ET-WatchCommands'; Script = 'Watch-Commands.ps1'; EveryMinutes = 5; Description = 'ET 工作台：轮询命令目录并回执' }
)

function Remove-ETTask {
    param([string]$Name)
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($Name, '注销计划任务')) {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
            Write-Host ("已注销：{0}" -f $Name) -ForegroundColor Yellow
        }
    }
}

if ($Unregister) {
    foreach ($d in $taskDefs) { Remove-ETTask -Name $d.Name }
    Write-Host '计划任务注销完成。' -ForegroundColor Green
    exit 0
}

# ---- 前置检查
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  ET 工作台 —— 计划任务注册' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ("运行账户：{0}" -f $me)
Write-Host ("管理员：  {0}" -f $(if ($isAdmin) { '是' } else { '否' }))
Write-Host ("程序目录：{0}" -f $Root)
Write-Host ("健康采集间隔：{0} 分钟；补传间隔：{1} 分钟" -f $healthEvery, $outboxEvery)
Write-Host ''

if (-not $isAdmin) {
    Write-Host '[警告] 当前会话不是管理员。注册计划任务通常需要管理员权限（决策 10 假设终端有本机管理员权限）。' -ForegroundColor Yellow
    Write-Host '       若注册失败，请用管理员身份重新运行本脚本。' -ForegroundColor Yellow
    Write-Host ''
}

foreach ($d in $taskDefs) {
    $scriptPath = Join-Path $TaskDir $d.Script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host ("[错误] 找不到任务脚本：{0}" -f $scriptPath) -ForegroundColor Red
        exit 2
    }

    if (-not $PSCmdlet.ShouldProcess($d.Name, '注册计划任务')) { continue }

    # 已存在则先删再建（覆盖语义）
    $existing = Get-ScheduledTask -TaskName $d.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host ("任务已存在，先删除：{0}" -f $d.Name) -ForegroundColor DarkGray
        Unregister-ScheduledTask -TaskName $d.Name -Confirm:$false -ErrorAction Stop
    }

    $action = New-ScheduledTaskAction -Execute $powershellExe `
        -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $scriptPath) `
        -WorkingDirectory $Root

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
        -RepetitionInterval (New-TimeSpan -Minutes $d.EveryMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 3650)

    # 关键设置：
    #   - 允许按需启动 / 电源变化后启动
    #   - StartWhenAvailable：错过窗口后补跑（现场机器常关机）
    #   - MultipleInstances=IgnoreNew：绝不并发（约束 C-7）
    #   - ExecutionTimeLimit 15 分钟：避免卡死占住
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -WakeToRun:$false `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $d.Name -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -Description $d.Description -Force -ErrorAction Stop | Out-Null
        Write-Host ("[已注册] {0}  每 {1} 分钟" -f $d.Name, $d.EveryMinutes) -ForegroundColor Green
    }
    catch {
        Write-Host ("[失败]   {0}  {1}" -f $d.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '查看：Get-ScheduledTask -TaskName ET-*' -ForegroundColor DarkGray
Write-Host '立即执行：Start-ScheduledTask -TaskName ET-HealthMonitor' -ForegroundColor DarkGray
Write-Host '注销：    .\Tasks\Register-ETTasks.ps1 -Unregister' -ForegroundColor DarkGray

if ($RunNow) {
    Write-Host ''
    Write-Host '立即各执行一次……' -ForegroundColor Cyan
    foreach ($d in $taskDefs) {
        if (Get-ScheduledTask -TaskName $d.Name -ErrorAction SilentlyContinue) {
            Start-ScheduledTask -TaskName $d.Name -ErrorAction SilentlyContinue
            Write-Host ("  已触发：{0}" -f $d.Name)
        }
    }
    Write-Host '（结果见 <DataRoot>\Logs\et-yyyyMMdd.log）' -ForegroundColor DarkGray
}

exit 0
