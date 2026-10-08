# Decisions

- [project-scope-v2] V2.0 范围：从「全平台 6 工作流 60 人日」收缩为「ET 端 PowerShell 工作台 单工作流 ~40 人日」。人力 2 人，工期 ~20 有效工作日。平台侧（Dataverse/Power Automate/Databricks/Power BI）全部暂缓，仅预留契约。交付 = 免安装绿色包（文件夹递归复制，非 ZIP），放共享用户自拷。

- [mvp-7-features] 7 项 MVP：E-01 主数据与配置 / E-02 设备与工程识别 / E-03 软件入口与状态展示 / E-04 一键下载 / E-05 健康检测与最小上报 / E-06 工作台自更新 / E-07 GUI 界面。排除：A-04 一键改配置、A-06 日志支持包、完整 Outbox 重试、独立审计界面、告警自动修复、平台侧。当前骨架 100% / 业务实现 0%。

- [repo-layout-and-two-projects] 工作区根 = git 仓库根 = ETWorkbench 项目根。远程 Bo123478/ET-SYS-OT，分支 master。两个并行子项目：① ETWorkbench（ET 端 PowerShell 工作台，被 .ps1 闸门覆盖）② SYS-Operational Technology/（客户侧 M365 平台，有 docs/ 工程路径 + 无代码方案/ 手工路径两条并行路线，互不替代）。

- [etworkbench-skeleton-layout] ETWorkbench 骨架：入口 Start-ETWorkbench.ps1（-SelfTest / -Console）。8 模块 83 导出函数：Core 24（共享、只增不改）· Identity 7 · MasterData 7 · Software 6 · Transfer 7 · Health 10 · Outbox 12 · Update 10。Config/ 5 个 json（workstation/paths/health-rules/settings/software-categories）。UI/ 2 xaml（MainWindow/PlateBar）。Tasks/ 4 脚本。本地数据根 C:\ProgramData\ETWorkbench。

- [window-desktop-semantics] 主窗口与铭牌桌面语义：全屏=手工贴合 WorkArea（不用 Maximized）；沉底=HWND_BOTTOM + SWP_NOACTIVATE（Set-ETWindowBottom）；任务栏隐藏=WS_EX_TOOLWINDOW + ShowInTaskbar=False；Topmost 恒 False。窗口无标题栏、不在任务栏、永远沉底 ⇒ 逃生命令靠哨兵文件 workbench.stop / plate.stop（删文件即自退）。铭牌 = 316×248 竖版卡，停靠工作区左边缘垂直居中。

- [tab-navigation-contract] 主窗口 5 页签。V3.0 顺序：0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据，信息区为启动默认页。页签顺序是契约。导航不再用数字索引，改按标题寻址（Select-ETTab + $script:TabIndex 映射表 + $script:TabHome）。重排只需同改映射表与 XAML 两处。E-07 契约见方案 §2.1。

- [single-state-verdict-source] 三态判据只有一个真相源：Get-ETStateVerdict（+ Get-ETAlarmState / Get-ETStateColorText / $script:ETStateRules）。主窗口、铭牌、底栏状态灯、信息区药丸都必须从这里取结论。禁各自重写 if-else —— 否则 D-10「铭牌红、窗口绿」复发。规则表逐字移植自 Start-ETPlate.ps1 的 PlateRules。

- [config-and-ownership-boundary] 分工：A=WHB（主）负责 ET.Update.psm1 / UI/*.xaml / Start-ETWorkbench.ps1 / Config/*.json（独占）/ 契约保管。B=QYX（辅）负责 ET.Identity·MasterData·Software·Transfer·Health·Outbox / Tasks/*.ps1。ET.Core.psm1 共享冻结只追加。tools/*.ps1 共享。Config/*.json 归 A 独占，B 要新配置项须先站会提出再由 A 加。

- [current-baseline-commit] 基线（2026-10-08）：HEAD = 74afdd4「chore(memory): 记忆分层整理（工程事实 vs 代理运行噪声）」，origin/master 仍在 d4753aa，本地领先 1 个提交（未推送）。本次提交只动 `.memory/instructions.md` / `.memory/decisions.md` / `.memory/quirks.md`，无代码、无配置、无接口改动。目的：把工程长期事实与代理运行噪声分层，避免 Decisions 混入会话噪声。验证：Gate1 通过（ALL CHECKS PASSED），Gate2 通过（PASS 46 / FAIL 0 / WARN 1），Gate3 被现有工作台实例拦截（退出码 0，但非 13 项完整自检输出）。文档版本：进度 V3.2 / 待办 V2.0 / 契约 ET-IFC-001 v1.0.0 / 方案 V2.0。已知未修缺陷：D-3、D-6、D-09、T-29、T-31、D-12(半解)、T-39。
