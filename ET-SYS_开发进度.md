# ET-SYS 开发进度

> **版本** V3.1 · **更新日期** 2026-09-30 · **配套文档** `ET-SYS_开发方案.md`
>
> **更新规则（强制）**：**每完成一个任务、每解决一个阻塞、每天收工前**，
> 必须同步更新本文件的 §1 总览、§3 任务明细、§7 更新日志。
> 本文件是**唯一**的进度真相来源，不允许只更新聊天记录而不更新本文件。
>
> **接口契约**：`docs/interface-contract.md`（ET-IFC-001，v1.0.0 冻结基线）。
> 两人并行开发时，**导出函数签名以该文件为准**。改动须走 §1.3 流程。

## 状态图例

| 符号 | 含义 |
|:---:|---|
| ⬜ | 未开始 |
| 🟡 | 进行中 |
| ✅ | 已完成 |
| ⏸ | 暂停（等前置条件） |
| ❌ | 阻塞（需外部解决） |
| ➖ | 不适用/本期不做 |

---

## 1. 总体看板

**当前阶段**：🟡 **准备阶段收尾**（骨架已建、可运行；等第 0 天前置条件）
**整体进度**：**约 30%**（骨架 100% / 7 项功能实现 0%）
**开工状态**：⏸ **骨架就绪，业务实现未开工** — 阻塞于第 0 天前置条件（见 §6 R-1）

> **重要区分**：本期已完成的是**可运行的工程骨架**（8 个模块、83 个函数、界面、计划任务、
> 冒烟测试全绿），**不等于** 7 项功能已实现。骨架只保证"能跑起来、接口不冲突、
> 没有共享时也能诚实降级"；共享可达后的真实业务逻辑仍需 D1~D17 实现。

| 项 | 计划 | 实际 | 状态 |
|---|---|---|---|
| 工期 | 约 20 个有效工作日 | 0 天（骨架不计入工期） | ⬜ |
| 人力 | 2 人 | 2 人已定 | ✅ |
| 功能完成 | 7 项 | 0 项（骨架已备） | ⬜ |
| 前置条件 | 8 项 | 0 项（P-1 已实测通过） | ❌ |
| 验收机器 | 3 台（样机 + 2 现场） | 0 台 | ⬜ |
| **工程骨架** | — | **骨架完成 + 冒烟测试 PASS 45 / FAIL 0** | ✅ |

### 功能级进度

| 编号 | 功能 | 负责人 | 计划人日 | 进度 | 状态 |
|---|---|---|---:|---:|:---:|
| **E-01** | 主数据与配置 | A+B | 3 | 骨架已建（`ET.MasterData` 7 函数 + GUI 页签） | 🟡 |
| **E-02** | 设备与工程识别 | B | 2 | 骨架已建（7 步链路可跑，需共享才能识别） | 🟡 |
| **E-03** | 软件入口与状态展示 | B | 2 | 骨架已建（7 态模型 + 状态汇总有数据形状） | 🟡 |
| **E-04** | 一键下载 | B | 3 | 骨架已建（计划/空间/原子发布/历史） | 🟡 |
| **E-05** | 健康检测与最小上报 | B | 4 | 骨架已建（9 条规则实采 7 条 + Outbox 闭环） | 🟡 |
| **E-06** | 工作台自更新 | A | 2 | 骨架已建（版本切指针 + 回滚 + 冒烟） | 🟡 |
| **E-07** | GUI 界面 | A | 4 | 骨架已建（**5 页签**桌面布局 + 常驻铭牌，桌面语义已实现） | 🟡 |
| | **合计** | | **20** | **骨架 100%，实现 0%** | 🟡 |

> **🟡 的准确含义**："骨架/契约/降级路径已就位并通过冒烟测试"，不是"功能可用"。

### 已完成工作（本次会话）

| # | 事项 | 状态 |
|---|---|---|
| 1 | 阅遍全部项目文档（ET 端基线 + C# 设计 + IT 清单 + SYS-OT 侧） | ✅ |
| 2 | 完成 **5 轮问答**，锁定 **27 项决策** | ✅ |
| 3 | **解析 `IT权限与接口确认清单.xlsx`**，提取 28 项 IT 确认 + 8 条接口 + 权限矩阵 + 架构边界 | ✅ |
| 4 | **工作区重组**：删重复目录、删 C# 骨架、`.git` 提到根 | ✅ |
| 5 | **资产抢救**：5 个未备份文件移到 `docs/` 与 `tools/` | ✅ |
| 6 | 重写 `ET-SYS_开发方案.md` V2.0 | ✅ |
| 7 | 重写 `ET-SYS_开发进度.md` V2.0（本文件） | ✅ |
| 8 | **建 `ETWorkbench/` 可运行骨架**：17 文件 / 8 模块 / 83 导出函数 / XAML 界面 / 4 计划任务 | ✅ |
| 9 | **建 `tools/Test-ETScripts.ps1`**：18 个 `.ps1|.psm1` + 3 JSON + 1 XAML 全量 **BOM + 语法**校验 | ✅ |
| 10 | **建 `tools/Test-ETIntegration.ps1`**：12 节集成冒烟测试，**PASS 45 / FAIL 0 / WARN 1** | ✅ |
| 11 | **实机体检取证**：ExecutionPolicy、BIOS SN、业务 IP、已装软件数、磁盘空间等 | ✅ |
| 12 | **修复 5 个 StrictMode 缺陷**（详见 §3 尾部「工程发现」） | ✅ |
| 13 | **建 `.gitattributes`**：固定换行符与文本/二进制分类，解除风险 R-9 的换行符面 | ✅ |
| 14 | **建 `tools/Install-ETHooks.ps1`**：一键安装 pre-push 闸门，把三个门禁脚本串成一条推送门 | ✅ |
| 15 | **建 `docs/interface-contract.md`**（ET-IFC-001 v1.0.0）：83 个导出函数的冻结契约 | ✅ |
| 16 | **确认角色分工**：A = WHB（主）／ B = QYX（辅），`Config/*.json` 归 A 独占（见 §1.1） | ✅ |

### 已完成工作（2026-09-29 本次会话）

| # | 事项 | 状态 |
|---|---|---|
| 1 | **主窗口三区桌面布局（档位 3）**：`MainWindow.xaml` 重写为「左上软件区 / 右上信息区 / 右下报警区」，隐藏 `MainTabs` 路由保留旧导航语义 → **本项已于 V2.8 被 5 页签方案取代**（见下方完成表第 12~18 项） | ⚠️ 已被 V2.8 取代 |
| 2 | **桌面语义三条需求全部实现**：默认铺满工作区、任务栏不显示、永远最低层（详见 §3.0 新增小节） | ✅ |
| 3 | ~~**常驻铭牌由竖版卡片改为 340×88 横向铭牌条**：与顶栏 `PlateSlot` 像素级重合，像主窗口的一个组件~~ | ⚠️ 已被 V2.6 `T-30` 反转 |
| 4 | **`Start-ETTray.ps1` / `UI/TrayBadge.xaml` / `Start-ETTray.bat` 全量重命名为 `Start-ETPlate.ps1` / `UI/PlateBar.xaml` / `Start-ETPlate.bat`**（旧名文件已删除，脚本/文档引用同步） | ✅ |
| 5 | **两处逃逸通道**：顶栏「关闭工作台」按钮 + 哨兵文件 `workbench.stop` / `plate.stop`（3s / 30s 轮询自退） | ✅ |
| 6 | **两个入口脚本加 Session 0 守卫**，无交互桌面下静默退出 | ✅ |
| 7 | **报警三态「都归红」定案**：`W-01`（未接入共享）与 `W-02`（设备未识别）由 `Warn` 改 `Alarm`；`W-03`（待上报）仍 `Warn` | ✅ |
| 8 | **修复 BOM 缺失**：`Start-ETPlate.ps1` / `PlateBar.xaml`（曾伪装为 41 个语法错误），`Test-ETScripts.ps1` 现扫 **20 + 3 + 2** | ✅ |
| 9 | **消除重复的 `SinkTimer` 滴答注册**并补注释说明位置 | ✅ |
| 10 | **三道闸门全绿**：`ALL CHECKS PASSED` / `PASS 45 FAIL 0 WARN 1` / `13 通过` | ✅ |
| 11 | **建立并回写 `ET-项目待办事项.md`**（V1.2，未完成 35 / 已闭环 21），作为待办唯一汇聚点 | ✅ |
| 12 | **主窗口改为 5 页签**：`MainTabs` 由「零尺寸隐藏路由」**转正为真正可见的功能分区**，三区布局（`SoftCardPanel` / 信息区 / `AlarmCardPanel`）整体收进页签内。页签顺序：**0 生产软件 / 1 警告提示 / 2 信息区 / 3 功能设置 / 4 主数据**（**已于 V3.0 重排为 0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据**）。页签序号成为契约（`G-07`） | ✅ |
| 13 | **新增 §12.5 警告提示分类汇总 + §12.6 信息区汇总**：按 `RuleId` 前缀归入 网络 / Windows / 共享 / 与清单对比 四类卡片；信息区显示身份、共享、软件版本摘要、告警摘要 | ✅ |
| 14 | **修复 `Update-AlarmSummary` 计数恒为 0 的真缺陷**：原代码统计 `Sample.Status -eq 'Alarm'/'Warning'`，而 `Get-ETMetric` 的 `Status` **只可能是 `Ok`/`Unknown`** ⇒ 任何告警下卡片都显示 0 且为绿色。改为从 `Get-ETHealthSnapshot` 的 **`Alarms`** 集合按 `RuleId` 归属统计，`Unknown` 单独计并显示**灰色**（不冒充绿色） | ✅ |
| 15 | **消除三态判据双写（缺陷 `D-10`）**：新增 `$script:ETStateRules`（5 条规则逐字移植自 `Start-ETPlate.ps1`）+ `Get-ETAlarmState` / `Get-ETStateVerdict` / `Get-ETStateColorText`，主窗口与铭牌**共用一个判据函数**，删掉 `Add_Loaded` 内联的 `if (Alarms>0)` | ✅ |
| 16 | **新增 §14.5 功能设置 + `Config/settings.json`**：日志上传开关、自动更新开关、生产软件一键更新（串行 `Invoke-ETDownload`，C-7 并发 1）、打开数据根目录、日志级别/保留天数、界面字号（`$script:ETUiScales` + `Apply-UiScale`）、启动即桌面模式、计划任务节奏只读说明 | ✅ |
| 17 | **新增 `Config/software-categories.json`**：把软件卡片按 生产软件 / 系统工具 / 周边 / 其他 分组（Windows 磁贴式），`SoftwareIds` 为空时按 `SoftwareId` 前缀猜测 | ✅ |
| 18 | **三道闸门全绿（复核）**：`ALL CHECKS PASSED`（20 `.ps1/.psm1` + 5 JSON + 2 XAML）/ `PASS 45 FAIL 0 WARN 1`（含 **`49 control reference(s) all resolve`**）/ `-SelfTest 13 通过` | ✅ |
| 19 | **修复「单实例限制不起作用」的真缺陷**：铭牌与主窗口的**重复打开拦截形同虚设** —— 拦截分支里调用了**当时尚未定义 / 尚未 `Add-Type` 的东西**（主窗口 `Show-ETError` 定义在下方；铭牌的 `[System.Windows.MessageBox]` 要等 §4 才 `Add-Type PresentationFramework`）⇒ 抛「无法识别 / 找不到类型」→ 被**外层大 catch 吞掉** → 脚本继续往下走 → **照样弹出第二个窗口/铭牌**。修法：两把 `Global\` 命名互斥锁提到**最前**（主窗口 §0.5、铭牌 §1，**均在会话 0 守卫之前**）；拦截分支**先 `Write-Host` 再弹窗**、弹窗自带 `try/catch` 且限定 `if ([System.Environment]::UserInteractive)`（无桌面会话里 `MessageBox` 无人点击 ⇒ 永不返回）、最后**无条件 `exit 0`**；锁存入**脚本作用域变量**（`Mutex` 线程亲和，局部变量被 GC 后锁会释放）。新增验证工具 `tools/Test-ETMutexProbe.ps1` / `tools/Verify-ETSingleInstance.ps1`（**内容全 ASCII**；编写时刻意无 BOM，**2026-09-30 已补 BOM**） | ✅ |
| 20 | **主窗口界面四项改动（V3.0）**：① 页签重排为 **0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据**，**信息区为启动默认页**；② 顶栏标题 `现场终端数字化运维 · ET 端` → **`系统运维 · ET端`**，字号 **17 → 26**、水平+垂直居中；③ 信息区左侧**内嵌一张与铭牌逐字段一致的 316×248 竖向卡片**（`Plate*` 共 11 个具名元素：`PlateStrip`/`PlateTitle`/`PlateStatusPill`/`PlateStatusDot`/`PlateStatusText`/`PlateEquip`/`PlateEt`/`PlateIp`/`PlateMpc`/`PlateVer`/`PlateUpdated`），配色与铭牌同源（`#FF2FBF71` / `#FFF2C94C` / `#FFE5533D`），判定仍从**唯一的 `Get-ETStateVerdict`** 取结论以防 `D-10` 复发；④ **脚本导航改为按页签标题寻址**：新增 §6.5 `$script:TabIndex` 映射表 + `$script:TabHome='信息区'` + `Select-ETTab '<标题>'`，**5 处硬编码 `MainTabs.SelectedIndex` 全部替换**（一键下载跳转、卡片「更新」跳转、一键更新、`Esc` 归位、启动默认页）；另新增 §8.1.5 `$script:SamplePlate` / `$script:PlateCardVersion` 与 §12.7 `Update-InfoPlateCard`（IP 取 `Get-ETBusinessIp`，三编号走 `Resolve-ETPlateInfo`，缺失时**整体**回退示例值并在标题加 `· 示例`） | ✅ |

### 1.1 角色分工与模块归属

**A = WHB（主）** ｜ **B = QYX（辅）**

| 模块 / 文件 | 导出数 | 归属 | 改动规则 |
|---|---:|---|---|
| `Modules/ET.Core.psm1` | 24 | **共享** | **只增不改**（append-only）；改/删已有导出须双方同意 |
| `Modules/ET.Identity.psm1` | 7 | **B** | B 主改 |
| `Modules/ET.MasterData.psm1` | 7 | **B** | B 主改 |
| `Modules/ET.Software.psm1` | 6 | **B** | B 主改 |
| `Modules/ET.Transfer.psm1` | 7 | **B** | B 主改 |
| `Modules/ET.Health.psm1` | 10 | **B** | B 主改 |
| `Modules/ET.Outbox.psm1` | 12 | **B** | B 主改 |
| `Modules/ET.Update.psm1` | 10 | **A** | A 主改 |
| `Tasks/*.ps1` | — | **B** | B 主改 |
| `UI/MainWindow.xaml` | — | **A** | A 主改 |
| `UI/PlateBar.xaml` | — | **A** | A 主改（常驻铭牌：**316×248 竖向卡**，停靠工作区**左边缘、垂直居中**；已**不与 `MainWindow` 顶栏做像素对齐**——原 340×88 对齐契约已随 `T-30` 解除） |
| `Start-ETWorkbench.ps1` | — | **A** | A 主改 |
| `Start-ETPlate.ps1` | — | **A** | A 主改（含内嵌 C# `ETPlateNative`/`ETPlateActivate`） |
| `Config/*.json` | — | **A** | **A 独占。B 不直接编辑，需变更时在站会提出** |
| `tools/*.ps1` | — | **共享** | 闸门脚本，改动会同时影响两人推送 |

> **冲突热点**：`Config/*.json`（`Get-ETConfig` 的键被全部 83 个函数消费）与
> `ET.Core.psm1`（每模块都导入）。前者靠「A 独占」隔离，后者靠「只增不改」隔离。

---

## 2. 里程碑看板（D0 ~ D20）
**说明**：`D0` = 开工第 0 天（**前置条件日**）。**因 R-1 阻塞，D0 实际日期待定**，
故「计划日期」列暂缺，`D0` 一确定即回填。

| 里程碑 | 内容 | 计划日期 | 实际日期 | 状态 |
|---|---|---|---|:---:|
| **M0 · D0** | **前置条件全部通过**（P-1~P-8） | 待定 | — | ❌ **阻塞** |
| **M1 · D1** | 骨架 + JSON Schema | 待定 | — | ⬜ |
| **M2 · D3** | ★ **E-01 验收**（主数据与配置） | 待定 | — | ⬜ |
| **M3 · D5** | ★ **E-02 验收**（设备与工程识别） | 待定 | — | ⬜ |
| **M4 · D7** | ★ **E-03 验收**（软件入口与状态） | 待定 | — | ⬜ |
| **M5 · D10** | ★ **E-04 验收**（一键下载） | 待定 | — | ⬜ |
| **M6 · D14** | ★ **E-05 验收**（健康检测与上报） | 待定 | — | ⬜ |
| **M7 · D16** | ★ **E-06 验收**（工作台自更新） | 待定 | — | ⬜ |
| **M8 · D18** | ★ **样机全功能跑通** | 待定 | — | ⬜ |
| **M9 · D19** | ★ **3 台试点机通过** | 待定 | — | ⬜ |
| **M10 · D20** | ★ **整体验收 + 交付物齐备** | 待定 | — | ⬜ |

### 逐日进度

| 日 | 里程碑 | 内容 | 状态 |
|---|---|---|:---:|
| D0 | 前置条件 | IT 共享四目录开通；域账号确认；路径定稿 | ❌ |
| D1 | 骨架 + 契约 | `ETWorkbench/` 目录；`.gitignore`；编码规范；3 份 JSON Schema | ⬜ |
| D2 | E-01 模块 | `ET.MasterData.psm1` 加载/校验/快照 | ⬜ |
| D3 | ★ E-01 | 主数据页签录入/校验/保存/Old-New 差异 + CSV 导入 | ⬜ |
| D4 | E-02 识别 | `Get-ETSerialNumber`、`Get-ETBusinessIp` | ⬜ |
| D5 | ★ E-02 | `Resolve-ETIdentity` 7 步 + 6 种拒绝 + 降级 + 识别页签 | ⬜ |
| D6 | E-03 状态 | 7 态判定函数 + `Test-ETPackageIntegrity` | ⬜ |
| D7 | ★ E-03 | 软件页签：列表 + 双标示 + 进程/可执行检测 | ⬜ |
| D8 | E-04 复制 | `Get-ETReleaseManifest` + `Test-ETSpaceAndPath` | ⬜ |
| D9 | E-04 复制 | `Copy-ETPackageRecursive` + 进度上报 + 并发=1 | ⬜ |
| D10 | ★ E-04 | 逐文件 Hash + 原子发布 + 断网重试 + Deployment 事件 | ⬜ |
| D11 | E-05 采集 | 8 项采集函数（无权限→`Unknown`） | ⬜ |
| D12 | E-05 告警 | `health-rules.json` + 7 段告警模型 | ⬜ |
| D13 | E-05 上报 | 事件原子落盘 + Outbox + `Publish-Outbox.ps1` | ⬜ |
| D14 | ★ E-05 | `Invoke-HealthMonitor.ps1` + `Register-ETTasks.ps1` + 审计埋点 | ⬜ |
| D15 | E-06 自更新 | 多版本目录 + `Current.json` + 下载校验 | ⬜ |
| D16 | ★ E-06 | 冒烟测试 + 自动回滚 + `AboutPage.xaml` | ⬜ |
| D17 | 集成 | `Start-ETWorkbench.ps1` + `Watch-Commands.ps1` + 统一错误提示 | ⬜ |
| D18 | ★ 样机 | 绿色包打包 + 样机全功能走查 | ⬜ |
| D19 | ★ 试点机 | 3 台试点机部署 + 差异排查 | ⬜ |
| D20 | ★ 收尾 | 运维手册 + 推广清单 + 复盘 | ⬜ |

---

## 3. 功能任务明细

> **阅读说明**：下方每项的 `⬜/🟡` 标记的是**任务本身**是否完成。
> 本次会话已把所有 7 项的 **工程骨架（模块 + 函数签名 + 契约 + 降级路径 + 界面页签）** 建完，
> 因此 §3.0 单独列出骨架成果，下方各表仍按**业务逻辑实现**的真实状态标记。

### 3.0 工程骨架实际落地清单（本次会话，✅ 全部完成）

#### 文件与规模

| 项 | 数量 | 说明 |
|---|---:|---|
| 入口脚本 | 2 | `Start-ETWorkbench.ps1`（`-SelfTest` / `-Console`）、`Start-ETPlate.ps1`（常驻铭牌） |
| 模块 | 8 | `ET.Core / Identity / MasterData / Software / Transfer / Health / Outbox / Update` |
| 导出函数 | **83** | Core 24 · Identity 7 · MasterData 7 · Software 6 · Transfer 7 · Health 10 · Outbox 12 · Update 10 |
| 配置文件 | 5 | `workstation.json` / `paths.json` / `health-rules.json` / **`settings.json`**（本机开关与偏好，本地覆盖层）/ **`software-categories.json`**（软件分类） |
| 界面 | 2 | `UI/MainWindow.xaml`（**5 页签**桌面布局，**51** 个 `x:Name`）+ `UI/PlateBar.xaml`（铭牌，**13** 个 `x:Name`） |
| 计划任务脚本 | 4 | `Register-ETTasks` / `Invoke-HealthMonitor` / `Publish-Outbox` / `Watch-Commands` |
| 校验工具 | 3 | `Test-ETScripts.ps1` / `Test-ETIntegration.ps1` / `Test-ETPrerequisites.ps1`（位于 `tools/`） |
| 根目录启动器 | 2 | `Start-ETWorkbench.bat` / `Start-ETPlate.bat`（免打印窗口双击启动） |
| **`ETWorkbench/` 文件总数** | **21** | 全部 UTF-8 with BOM（C-1），全部语法通过（新增 `Config/settings.json`、`Config/software-categories.json`；`UI/MainWindow.xaml.bak` 不计入且已被 `.gitignore` 忽略） |
| `tools/` 脚本总数 | 5 | 上述 3 个 + `show-ui.ps1` / `check-appcontrol.ps1` |

#### 各模块交付内容

| 模块 | 关键交付 |
|---|---|
| `ET.Core` | 配置/路径/日志/哈希/原子写/事件号/审计/自检；新增 `Get-ETObjectPropertyNames`、`Test-ETObjectHasProperty` 两个 StrictMode 安全助手 |
| `ET.Identity` | BIOS SN + 业务 IP 实采可用；7 步识别链可跑（无共享时停在 SN 步，**诚实返回 Unidentified**） |
| `ET.MasterData` | 5 类主数据 + mappings 规格；校验器（主键/外键/版本号/全角标点）；快照导入导出 |
| `ET.Software` | 7 态模型（含 `Downloaded` 不得显示为已生效的约束 C-6）；软件清单 + 状态汇总 |
| `ET.Transfer` | 发布清单校验、空间预检、下载计划、原子发布、历史记录 |
| `ET.Health` | 9 条规则引擎（Cim/PsDrive/Service/Process/EventLog/ShareReachability/Self 七类源）；告警去重/防抖/恢复 |
| `ET.Outbox` | One Event = One File（C-5）；`.tmp → .ready → .done` 原子链路；指数退避重试 |
| `ET.Update` | 版本切指针 + 备份 + 冒烟 + 失败回滚（方案 §6.11） |

#### 🖥️ 实机体检取证（`tools/Test-ETPrerequisites.ps1` + `Test-ETIntegration.ps1`）

| 项 | 实测值 | 结论 |
|---|---|---|
| PowerShell | `5.1.19041.6456` | ✅ 符合（方案要求 5.1） |
| ExecutionPolicy | **`Bypass`** | ✅ **决策 20 已落实**，无需签名/PKI |
| BIOS SN | `6797-4949-0948-8103-0923-4583-04` | ✅ 识别链第 1 步可用 |
| 业务 IP | `192.168.137.88`, `172.29.62.79` | ✅ 多网卡枚举正常 |
| 已装应用数 | **0** | ⚠️ 开发机未装业务软件，E-03 需在场机复测 |
| 本地数据根 | `C:\ProgramData\ETWorkbench` 可读写，15 个目录全部建出 | ✅ |
| 共享状态 | `IsReachable=False / IsConfigured=False` | ⚠️ 未配置（见 R-1），所有共享依赖路径走「未配置」降级分支 |
| 身份 | `DESKTOP-MKP1N8S\wuhui`（本地账号） | ⚠️ **待人工确认**是否为预期生产形态 |
| 磁盘空间 | `FreeGB=80.01`（`$env:TEMP`） | ✅ 空间预检可用 |

#### 🐛 工程发现：5 个 `Set-StrictMode -Version 2.0` 缺陷（均已修复）

> 所有模块均启用 `Set-StrictMode -Version 2.0`，把「属性缺失 / 空元素 / 空对象枚举」
> 从隐性 bug 变成硬失败。冒烟测试因此找出 5 个真实缺陷，全部修复并回归通过。

| # | 缺陷 | 根因 | 修复 |
|---|---|---|---|
| A | `@($null)` 变成含 1 个 `$null` 的数组 | `Get-ETMasterDataSnapshot` 返回 `$null`，`@()` 包装后仍含 `$null`，再访问 `.ApplicationId` 就抛异常 | 快照函数**永不返回 `$null`**（改为 `@()`）；消费侧再加 `Where-Object { $null -ne $_ }` 过滤 |
| B | 读 `Target` 属性抛异常 | `health-rules.json` 中 `HR-CPU`/`HR-MEM`/`HR-SHARE`/`HR-SELF-OUTBOX` **确实没有 `Target` 字段**，StrictMode 下读不存在的键会抛 | 新增 `Get-ETRuleField` 安全读字段，重写 `Get-ETMetric` 与 `Invoke-ETHealthCheck` 全部字段读取 |
| C | 空对象成员枚举抛异常 | `$obj.PSObject.Properties.Name` 在**零属性对象**上会抛「找不到 Name」；`Get-ETHealthState` 返回的 `Rules` 在无状态文件时正是空对象 | 新增 `Get-ETObjectPropertyNames` / `Test-ETObjectHasProperty`，重写 5 处调用点 |
| D | `-contains` 被当成命令参数 | `if (Get-ETObjectPropertyNames ... -contains $k)` 中 PowerShell 把 `-contains` 当作**参数名** | 左操作数加括号：`if ((Get-ETObjectPropertyNames ...) -contains $k)` |
| E | 快照文件被写坏 | **冒烟测试自身缺陷**：把 `Check` 的展示字符串当作 `-Result` 传给了 `Save-ETHealthSnapshot` | 修正测试传真实对象；同时在产品代码给 `Save-ETHealthSnapshot` 加**入参类型防御**，不合法直接报错而不是写坏快照 |

> **经验沉淀**：`$obj.PSObject.Properties.Name` 仅在对象至少 1 个属性时才安全；
> 通用安全写法是 `$obj.PSObject.Properties | ForEach-Object { $_.Name }`。
> 以上经验已沉淀到仓库记忆 `/memories/repo/et-sys-context.md`。

#### GUI 可运行性验证（受环境限制，已用旁证）

| 项 | 结果 |
|---|---|
| `tools/Test-ETScripts.ps1` | ✅ 全量校验 **20 个 `.ps1/.psm1` + 5 JSON + 2 XAML**（`RESULT: ALL CHECKS PASSED`，EXIT=0） |
| `tools/Test-ETIntegration.ps1` | ✅ 12 节冒烟，**PASS 45 / FAIL 0 / WARN 1**（WARN = 主数据快照为空跳过软件汇总，与基线一致） |
| `Start-ETWorkbench.ps1 -SelfTest` | ✅ 退出码 0，**13 项检查全通过**，结论「自检通过」 |
| XAML 解析 + `FindName` | ✅ `MainWindow.xaml` **51** 个 `x:Name`、`PlateBar.xaml` **13** 个，均可 `XamlReader::Load`；且经**无头加载器逐名核对**，脚本所引用的名字全部命中（无悬空引用） |
| `$ui.<Name>` 静态引用 | ✅ 主窗口 **49/49**、铭牌 **9/9** 全部解析（脚本内引用 ↔ XAML 命名逐一比对通过；`Test-ETIntegration.ps1` 报 `49 control reference(s) all resolve`） |
| `ShowDialog()` 是否被走到 | ✅ 控制台日志停在 `[ET] 窗口已就绪` 后进程持续挂住且 stderr 为空 —— 即**模态循环特征**，证明已走到显示步骤 |
| 截图取证 | ⚠️ **无法完成**：当前终端运行在 **Session 0**（无交互桌面），连 3 行最小 WPF 程序也无法显示窗口，属**环境限制而非代码缺陷**。已给 `tools/show-ui.ps1` 加前置探测，在 Session 0 下直接输出说明并以退出码 2 退出，不再报超时错误 |
| 待办 | ⬜ 在真实交互桌面（现场机/样机）跑一次 `tools/show-ui.ps1` 补截图取证 |

#### 🖥️ 桌面语义与常驻铭牌（2026-09-29 新增，✅ 已实现并通过三道闸门）

> 现场要求把工作台做成「像桌面一样」。**不做真 Shell 替换**（三条硬理由）：
> ① 方案 §3.1/§20 明文自禁；② **Shell Launcher 仅 Enterprise/Education/IoT Enterprise 可用，
> 不支持 Windows 专业版**（现场即专业版）；③ 业务软件需 24h 常驻，接管 Shell 会连坐其生命周期，撞红线 F-1/F-2。
> ⇒ 做法是**像桌面但留退路**：不设 `Topmost`（红线 F-4）、不写注册表、不接管 Shell。

| 需求 | 实现要点 | 文件/函数 |
|---|---|---|
| ① 默认铺满工作区、任务栏不显示 | `WindowStyle=None` + `ResizeMode=NoResize` + `ShowInTaskbar=False`；`Enter-ETDesktopMode` 把 `Left/Top/Width/Height` 手工贴合 `SystemParameters.WorkArea`（**不用 `WindowState=Maximized`**，其 GDI 缓存坐标会漏任务栏/多屏算错）；`SourceInitialized` 里按位或 `WS_EX_TOOLWINDOW` 使 Alt+Tab 也不出现 | `MainWindow.xaml`、`Enter`/`Exit-ETDesktopMode`、`Toggle-FullScreen`、`Update-FullScreenLabel` |
| ② 永远处于所有窗口最低层 | `SetWindowPos(HWND_BOTTOM, …, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE)`（**不是 Topmost —— F-4 禁的是置顶，不禁沉底**）；`Add_Activated`/`Add_Deactivated` 立即沉底 + `SinkTimer` 每 3 秒兜底（应对业务软件自行置顶、或有人把窗口藏到下面）；重入保护 `$script:Sinking` | `ETWindowNative`（内嵌 C#）、`Set-ETWindowBottom`、`$script:SinkTimer` |
| ③ ~~铭牌移到左上角、像主窗口的组件~~ **铭牌独立常驻，停靠左边缘垂直居中**（`T-30` 反转本行原方案） | **已回退为原版式**：`PlateBar.xaml` 恢复为**316×248 竖向工业铭牌卡**（源自原 `TrayBadge.xaml`），停靠 `Left = WorkArea.Left`、`Top = round(WorkArea.Top + (WorkArea.Height - 窗口高)/2)`；与主窗口**不做任何像素对齐**，顶栏 `PlateSlot` 槽位已**整体移除**。原「340×88 横向矮条像素重合」方案**作废**（`T-26 详情` 已标注不再适用）。**唯一与原设计的偏离**：`Topmost` 由 `True` 改为 `False`（红线 F-4），改由 `HWND_BOTTOM` 沉底，**不可回退** | `UI/PlateBar.xaml`、`Start-ETPlate.ps1`（`Sync-PlatePosition` + `Add_SizeChanged`）、`UI/MainWindow.xaml`、根目录 `Start-ETPlate.bat` |

**逃逸通道（必须写进现场运维手册）**：两窗口均无标题栏、不在任务栏、且永远沉底，
业务软件全屏时关闭入口可能点不到 ⇒
- 顶栏右上角「关闭工作台」按钮（`BtnCloseWindow`，红底 `DangerBtn`）；
- 哨兵文件（主窗口 3 秒轮询、铭牌 30 秒轮询，删文件即自退）：
  ```powershell
  New-Item -ItemType File -Force "$env:ProgramData\ETWorkbench\Local\Snapshot\workbench.stop"
  New-Item -ItemType File -Force "$env:ProgramData\ETWorkbench\Local\Snapshot\plate.stop"
  ```

**已确认的能力边界**：`F11`/`Esc` 在窗口失焦时收不到（不可见的沉底窗口拿不到键盘），已改用按钮 —— 现场可接受。
两个入口脚本均加 **Session 0 守卫**（`[System.Environment]::UserInteractive` 为 `False` 时打印说明并 `exit 0`），
避免计划任务/服务/远程无桌面会话下抛异常。

> ⚠️ **本次收敛了两处兼容性隐患**：删除了重复注册的 `SinkTimer` 滴答处理；补回 `Start-ETPlate.ps1` 与
> `PlateBar.xaml` 的 UTF-8 BOM（无 BOM 曾伪装成 41 个语法错误，详见待办 **`G-01`**／`D-07`；
> 注意 `G-06` 是另一件事：局部替换编辑工具的「部分匹配」静默污染）。

---

### E-01 主数据与配置 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 1.1 | 定义 `Equipment/Project/Application` JSON Schema | B | ⬜ |
| 1.2 | `Test-ETMasterData`：完整性 + 类型 + 重复主键 + 交叉引用 | B | ⬜ |
| 1.3 | `Get-ETMasterDataSnapshot`：读取 + 校验 + 本地缓存 | B | ⬜ |
| 1.4 | 生成 `snapshot-manifest.json`（版本 + Hash） | B | ⬜ |
| 1.5 | `MasterDataPage.xaml`：表格 + 校验 + 保存 | A | ⬜ |
| 1.6 | CSV 导入（Excel 习惯） | A | ⬜ |
| 1.7 | 保存前 Old/New 差异确认 | A | ⬜ |
| ★ | **验收**：写错 `ProjectId` 被拒绝并指明位置 | — | ⬜ |

### E-02 设备与工程识别 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 2.1 | `Get-ETSerialNumber`：CIM 读 BIOS SN，处理空值/重复 | B | ⬜ |
| 2.2 | `Get-ETBusinessIp`：多网卡匹配 `Allowed IP` | B | ⬜ |
| 2.3 | `Resolve-ETIdentity`：7 步识别链 | B | ⬜ |
| 2.4 | 6 种拒绝规则 + 专属错误码 | B | ⬜ |
| 2.5 | 降级行为：识别失败仍保留入口与健康检测 | B | ⬜ |
| 2.6 | 只读 Device Context 对象 | B | ⬜ |
| 2.7 | `IdentityPage.xaml`：展示识别链每步结果 | A | ⬜ |
| ★ | **验收**：SN 置空 → 明确提示不崩溃 | — | ⬜ |

### E-03 软件入口与状态展示 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 3.1 | `Get-ETSoftwareList`：按快照生成入口 | B | ⬜ |
| 3.2 | **7 态判定函数**（7 个独立函数 + 单测） | B | ⬜ |
| 3.3 | `Test-ETPackageIntegrity`：逐文件 Size + SHA256 | B | ⬜ |
| 3.4 | `Get-ETProcessState` / `Get-ETExecutableState` | B | ⬜ |
| 3.5 | `SoftwarePage.xaml`：列表 + 颜色/文字**双标示** | A | ⬜ |
| 3.6 | 刷新 + 打开目录（走白名单） | A | ⬜ |
| 3.7 | 7 态含义 Tooltip | A | ⬜ |
| ★ | **验收**：显示 `Downloaded`，**不是**「已安装/已生效」 | — | ⬜ |

### E-04 一键下载 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 4.1 | `Get-ETReleaseManifest` + 篡改拒绝 | B | ⬜ |
| 4.2 | `Test-ETSpaceAndPath`：空间 + `SoftwareRoot` 白名单 | B | ⬜ |
| 4.3 | `Copy-ETPackageRecursive`：递归复制到 `.partial` | B | ⬜ |
| 4.4 | 进度上报（写 `Results/`） | B | ⬜ |
| 4.5 | `fileCount` + 逐文件 Size + SHA256 比对 | B | ⬜ |
| 4.6 | 原子发布：`.partial` → 版本目录 | B | ⬜ |
| 4.7 | 不覆盖运行目录（占用时明确拒绝） | B | ⬜ |
| 4.8 | 断网暂停 + 重试；**并发 = 1** | B | ⬜ |
| 4.9 | 写 Deployment 事件到 `Upload/` 或 `Outbox/` | B | ⬜ |
| 4.10 | `DownloadPage.xaml`：预览 + 确认 + 进度 + 取消 | A | ⬜ |
| ★ | **验收**：>100 文件 Hash 全通过；断网明确报错可重试 | — | ⬜ |

### E-05 健康检测与最小上报 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 5.1 | 8 项采集函数（CPU/内存/磁盘/网络/服务/进程/事件日志/自身） | B | ⬜ |
| 5.2 | `health-rules.json`：阈值/持续/恢复/冷却 | B | ⬜ |
| 5.3 | 告警模型：`Collect→Evaluate→Duration→Debounce→Dedup→Alarm→Recovery` | B | ⬜ |
| 5.4 | 事件原子落盘到 `Upload/{EquipmentId}/{yyyy}/{MM}/{dd}/` | B | ⬜ |
| 5.5 | 共享不可达 → 落 `Outbox/`，`Status=Pending` | B | ⬜ |
| 5.6 | `Publish-Outbox.ps1`：补传 + 成功后删本地副本 | B | ⬜ |
| 5.7 | `Invoke-HealthMonitor.ps1` + `Register-ETTasks.ps1`（短生命周期/可重入/幂等） | B | ⬜ |
| 5.8 | `HealthPage.xaml`：当前值/阈值/告警/Outbox 积压 | A | ⬜ |
| 5.9 | 最小审计埋点（Who/When/EquipmentId/Operation/Result） | B | ⬜ |
| ★ | **验收**：断网落本地 → 恢复自动补传且**不重复** | — | ⬜ |

### E-06 工作台自更新 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 6.1 | 多版本目录布局 `{版本}/` + `Current.json` | A | ⬜ |
| 6.2 | `Get-ETWorkbenchUpdate`：读版本 manifest | A | ⬜ |
| 6.3 | 下载 → 校验 → 解压到新版本目录 | A | ⬜ |
| 6.4 | 备份当前 `Current.json` | A | ⬜ |
| 6.5 | 切换 `Current` 指针（原子写） | A | ⬜ |
| 6.6 | **冒烟测试 + 自动回滚** | A | ⬜ |
| 6.7 | `AboutPage.xaml`：版本 / 检查更新 / 回滚 | A | ⬜ |
| ★ | **验收**：放会失败的 1.2.0 → 自动回滚并提示原因 | — | ⬜ |

### E-07 GUI 界面 🟡（骨架已建）

| # | 任务 | 负责 | 状态 |
|---|---|---|:---:|
| 7.1 | `Start-ETWorkbench.ps1`：加载 WPF + XAML，`$PSScriptRoot` 推导 | A | ⬜ |
| 7.2 | Commands/Results 文件契约（`RequestId`） | A+B | ⬜ |
| 7.3 | `Watch-Commands.ps1`：消费命令（可重入、幂等） | A | ⬜ |
| 7.4 | `MainWindow.xaml`：页签框架 + 顶部状态条 | A | ⬜ |
| 7.5 | 接入 5 个 Page | A | ⬜ |
| 7.6 | 统一中文可读错误提示 + 建议动作 | A | ⬜ |
| 7.7 | 长任务进度与取消 | A | ⬜ |
| 7.8 | **全文件存为 UTF-8 with BOM**（约束 C-1） | A+B | ⬜ |
| 7.9 | 绿色包结构 + 拷贝说明 | A | ⬜ |
| ★ | **验收**：拷贝到任意目录双击启动，5 页签可用，中文无乱码 | — | ⬜ |

### 第 0 天前置条件 ❌

| # | 前置条件 | 对应 IT 项 | 状态 |
|---|---|---|:---:|
| **P-1** | 共享四目录建立（`MasterData`/`Release`/`ConfigRules`/`Upload`） | IT-03~06 | ❌ |
| **P-2** | 确认 ET 访问共享的 Windows 身份 | IT-01/02 | ❌ |
| **P-3** | `Upload` 可 Create/Write/Rename | IT-06 | ❌ |
| **P-4** | 计划任务未登录时仍可访问 UNC | IT-10/11 | ❌ |
| **P-5** | CIM/WMI/Event Log 读取权限 | IT-13 | ❌ |
| **P-6** | `C:\ProgramData\ETWorkbench` ACL 可读写 | IT-12 | ❌ |
| **P-7** | SMB 连通（TCP 445、DNS、Firewall ACL） | IT-07 | ❌ |
| **P-8** | 本地软件根路径定稿 | — | ❌ |
| ✅ | PowerShell Execution Policy | IT-08/09 | ✅ **已确认：允许未签名脚本** |

---

## 4. 验收进度

| 编号 | 验收项 | 目标 | 状态 |
|---|---|---|:---:|
| E-01 | 主数据与配置 | 错 `ProjectId` 被拒绝 | ⬜ |
| E-02 | 设备与工程识别 | 空 SN 明确提示 | ⬜ |
| E-03 | 软件入口与状态 | 显示 `Downloaded` 不误报 | ⬜ |
| E-04 | 一键下载 | Hash 全通过 + 断网可重试 | ⬜ |
| E-05 | 健康检测与上报 | 断网落本地 + 自动补传不重复 | ⬜ |
| E-06 | 工作台自更新 | 失败自动回滚 | ⬜ |
| E-07 | GUI 界面 | 5 页签 + 中文无乱码 | ⬜ |
| G-1 | 免安装 | 拷贝即用 | ⬜ |
| G-2 | 路径无关 | 任意目录可运行 | ⬜ |
| G-3 | 编码正确 | UTF-8 BOM 无乱码 | ✅ 闸门已强制（`Test-ETScripts.ps1` 扫 20+3+2，缺 BOM 即拦） |
| G-4 | 安全红线 | §10 无违反 | 🟡 桌面语义已自查（无 `Topmost`、无结束/覆盖业务软件、无强制抢焦点），待现场复核 |
| G-5 | 共享权限 | 下行目录写被拒绝 | ⬜ |
| G-6 | 断网可用 | 入口与健康仍可用 | ⬜ |
| G-7 | 并发安全 | 同时仅 1 个下载 | ⬜ |
| G-8 | 幂等 | 重复任务不产生重复事件 | ⬜ |
| **G-9** | **桌面语义** | 默认铺满工作区、任务栏无图标、永远最低层不遮挡业务软件 | 🟡 代码与旁证已就绪（含 `T-30` 后铭牌**垂直居中坐标实测**：1024×768 工作区 → `Left=0`、`Top=260`、下边缘 `508`，完整落在工作区内不压任务栏），**待真实桌面验收**（N-18/N-19）。⚠️ 竖版铭牌会**盖住软件区卡片左边缘**，需与 `B-12` 一并现场确认 |
| **G-10** | **逃逸通道可用** | 顶栏关闭按钮 + `workbench.stop` / `plate.stop` 哨兵均可退出 | 🟡 已实现（铭牌右键菜单文案已同步为「退出铭牌…」，确认框文案改为「左边缘」），**待真实桌面验收** |
| M-1 | 样机 | 1 台全功能跑通 | ⬜ |
| M-2 | 现场试点机 | 2 台（跨现场）通过 | ⬜ |

---

## 5. 下一步行动

| # | 行动 | 负责人 | 期限 | 状态 |
|---|---|---|---|:---:|
| **N-1** | **与 IT 开会逐项确认 `IT权限与接口确认清单.xlsx` 的 28 项**（重点 IT-01~IT-13） | 项目负责人 | **立即** | ⬜ |
| **N-2** | 按 `docs/IT权限与接口确认清单.xlsx` 的「优先确认 8 项」顺序推进，**优先拿下 P-1、P-2** | 项目负责人 | D0 | ⬜ |
| **N-3** | 定稿共享根 UNC 路径与本地软件根路径（写入 `Config/workstation.json`） | 运维 + IT | D0 | ⬜ |
| **N-4** | 收集各现场机器清单与系统版本（用于 R-4 评估） | 运维 | D0~D1 | ⬜ |
| **N-5** | ✅ ~~建立 `tools/Test-ETPrerequisites.ps1` 逐项验证 P-1~P-8~~（已完成并实测） | 开发 B | ~~D0~~ | ✅ |
| **N-6** | ✅ ~~建立 `ETWorkbench/` 骨架~~（已完成：17 文件 / 8 模块 / 83 函数 / 冒烟测试 FAIL 0） | 开发 A+B | ~~D1~~ | ✅ |
| **N-7** | 提交工作区重组到 git（含资产移动、骨架删除、新文档、ETWorkbench 骨架） | 开发 A | D0 | ⬜ |
| **N-10** | ✅ ~~提交三项工程护栏：`.gitattributes`、`tools/Install-ETHooks.ps1`、`docs/interface-contract.md`，以及归正换行符后的 `docs/ET工作台方案_Version2.md`~~（已完成：commit `edef1df`，5 文件 / +1654 −224） | 开发 A | ~~D0~~ | ✅ |
| **N-11** | 🔴 **修复 D-6**：`Test-ETFreeSpace` 在目标盘不可达时静默回退到系统盘，导致 C-8 空间保护失效（见 `docs/interface-contract.md` §10.2） | 开发 B | D1 | ⬜ |
| **N-12** | 🔴 **修复 D-3**：`paths.json` 声明 `.ndjson`、`ET.Outbox.psm1:238` 实际写 `.json`，两者必居其一（见 §10.3） | 开发 B | D1 | ⬜ |
| **N-13** | ✅ ~~**修复 D-7**：`Save-ETHealthState` 无输入校验，可写坏 `health-state.json` 并致**每轮** `Invoke-ETHealthCheck` 抛错~~（已完成：写侧抛错 + 读侧降级留痕，见 §10.4） | 开发 B | ~~D1~~ | ✅ |
| **N-14** | 提交 D-7 修复与契约 §10.4 增补 | 开发 A | D0 | ⬜ |
| **N-8** | 🔴 **等 R-1**：共享四目录建立后，把 `Config/workstation.json` 的 `Share.ShareRoot` 填上真值，重跑一次冒烟测试 | 运维 + B | D0 | ⏸ |
| **N-9** | 共享可达后补做：主数据样例文件（equipment/devices/projects/applications/approved-versions）放入共享 `MasterData/` | 运维 | D0 | ⏸ |
| **N-15** | ✅ ~~**实现桌面语义三条需求**：默认铺满工作区 + 任务栏不显示 + 永远最低层（`HWND_BOTTOM`，非 `Topmost`，不违 F-4）~~（已完成：`Enter/Exit-ETDesktopMode`、`Set-ETWindowBottom`、`WS_EX_TOOLWINDOW`、3 秒 `SinkTimer`；三道闸门全绿） | 开发 A | ~~D0~~ | ✅ |
| **N-16** | ✅ ~~**常驻铭牌改造**：竖版卡片 → 340×88 横向条，与顶栏 `PlateSlot` 像素级重合~~（**已由 `T-30` 反转**：回退为 316×248 竖版卡、左边缘垂直居中，`PlateSlot` 已移除；但**文件重命名**这一部分仍有效：旧名 `TrayBadge`/`Start-ETTray` 全量重命名为 `PlateBar`/`Start-ETPlate`，全文引用已同步） | 开发 A | ~~D0~~ | ✅ |
| **N-17** | ✅ ~~**修 `Start-ETPlate.ps1` / `PlateBar.xaml` 缺失 BOM**~~（已完成：`tools/Test-ETScripts.ps1 -Fix`，随后闸门全绿） | 开发 A | ~~D0~~ | ✅ |
| **N-18** | ⬜ **现场机上用 `tools/show-ui.ps1` 做一次真实桌面视觉验收**：确认铭牌**左边缘垂直居中**、不压任务栏、无遮挡争议、无高 DPI 接缝（对应待办 T-23 / T-31） | 开发 A + 运维 | 样机到位后 | ⬜ |
| **N-19** | ⬜ **现场接受度确认**：「永远最低层」与「失焦后 F11/Esc 不可用」需现场试用确认可接受，并**把哨兵文件逃逸命令写进现场运维手册**（对应待办 B-12） | 开发 + 运维 | 样机到位后 | ⬜ |
| **N-20** | ⬜ **评估是否抽出共享 `psm1`** 承载主窗口与铭牌重复的内嵌 C# 类（`ETWindowNative`/`ETPlateNative`）；若做需同步 `docs/interface-contract.md` 冻结面（对应待办 B-13） | 开发 A | D1 后 | ⬜ |
| **N-21** | ⬜ **补主数据 schema**：`equipment.json` 增加 `EtCode` / `MpcCode` 字段，否则铭牌恒走「示例」分支 | 开发 B | D1 | ⬜ |
| **N-22** | ⬜ **修 D-09（主窗口控制台黑窗）**：双击 `Start-ETWorkbench.bat` 会闪/留一个黑控制台窗，与「像桌面组件」观感冲突（经铭牌启动时已由 `-WindowStyle Hidden` + `CreateNoWindow` 遮住）。**注意 `-Console` 调试入口必须保持可见** | 开发 A | D1 | ⬜ |
| **N-23** | ✅ ~~**修 D-13（主窗口启动即失败）**：`Start-ETWorkbench.ps1:379` 注释与代码挤成同一物理行 ⇒ `$ui` 缺 `BtnMdLoad` 键 ⇒ `Set-StrictMode 2.0` 读键抛「找不到属性」⇒ 顶层 `trap` 弹「工作台启动失败」~~（已完成：拆回两行 + `Test-ETIntegration.ps1` §12 新增 `$ui` 声明反向门禁；见待办 §3.8） | 开发 A | ~~D1~~ | ✅ |

---

## 6. 风险与阻塞

### 6.1 当前阻塞

| ID | 阻塞 | 影响 | 需谁解决 | 状态 |
|---|---|---|---|:---:|
| **R-1** | 共享四目录未建立、ET 访问共享身份未确认 | **致命**：无共享则 E-01/E-03/E-04/E-05 全部无法验收 | IT / 文件服务 / AD | ❌ **未解决** |
| **R-2** | 计划任务未登录时能否访问 UNC 未验证 | 高：E-05 周期采集可能失效 | Endpoint / AD | ❌ **未解决** |
| **R-11** | **代码仓库换行符/BOM 不一致** | 低：已在这次会话基本解除 | 开发 A | ✅ **已解除**（`.gitattributes` + pre-push 闸门） |

> **结论**：**R-1 未解决前不进入 D1。** 因为 E-01/E-03/E-04/E-05 全部依赖共享，
> 先写代码会在集成时大面积返工。

> **R-11 解除说明**：本项原为“风险 1”（换行符漂移）。已用两个手段解除：
> (1) `.gitattributes` 固定文本/二进制分类与 CRLF；
> (2) pre-push 闸门强制跑 `Test-ETScripts.ps1 -Fix`，拦截缺 BOM 的提交。
> **但需注意能力边界**：Git **无法**强制 BOM（只控制换行与文本/二进制分类），
> 因此 **BOM 的唯一强制点是 pre-push 钩子**，而非 `.gitattributes`。

### 6.2 风险跟踪

| ID | 风险 | 概率 | 影响 | 缓解 | 状态 |
|---|---|---|---|---|---|
| R-1 | IT 授权未落定 | 高 | 致命 | D0 集中攻坚；P-1/P-2 未过则停止开发 | ❌ 未缓解 |
| R-2 | 计划任务 UNC 访问 | 中 | 高 | 备选：登录时触发 / 存储凭据 / 降级为 GUI 手工触发 | 未缓解 |
| R-3 | 排期无缓冲 | 中 | 中 | 5 项可砍项，可腾 4 天 | ✅ 有预案 |
| R-4 | 现场机器差异 | 中 | 中 | 3 台试点机跨现场；多网卡支持 | 🟡 部分 |
| R-5 | 软件包过大 | 中 | 中 | 进度上报 + 可取消 + `fileCount` 前置校验 | 🟡 部分 |
| R-6 | 主数据手工维护易错 | 高 | 中 | E-01 强制校验 + 交叉引用 + 差异确认 | ✅ 已缓解 |
| R-7 | 共享空间膨胀 | 中 | 中 | 日期分区；约定保留策略；ET 不删他人文件 | 🟡 部分 |
| R-8 | SMB 并发写冲突 | 低 | 中 | One Event = One File + 按设备隔离 | ✅ 已缓解 |
| R-9 | 中文乱码 | 中 | 低 | 约束 C-1（UTF-8 BOM）+ D17 全量检查 | ✅ 已缓解 |
| R-10 | 范围蔓延 | 高 | 高 | 范围守则：加需求必等量砍需求 | ✅ 有守则 |

---

## 7. 决策记录（31 项已锁定）

| # | 决策项 | 结论 |
|---|---|---|
| 1 | 重设原因 | 人力或工期不够，原方案太重 |
| 2 | 交付形态 | 只做 ET 端 PowerShell，平台暂缓 |
| 3 | 本期范围 | ET 工作台 only |
| 4 | 数据范围 | 不建 Dataverse 表，用共享 JSON/CSV |
| 5 | 人力 | 2 人 |
| 6 | 工期 | 约 20 个有效工作日 |
| 7 | 终端规模 | >50 台，多现场 |
| 8 | 主数据来源 | 手工维护 JSON/CSV 放共享 |
| 9 | 上报去向 | 最小上报：写共享 + 失败落本地补传 |
| 10 | 终端权限 | 本机管理员权限，Windows 10/11 |
| 11 | 应用数 | 4–10 个 |
| 12 | 部署方式 | 免安装绿色包，放共享用户自拷 |
| 13 | 多现场网络 | 同一内网，共享全可达 |
| 14 | 主数据维护 | 运维维护，需录入/校验工具 |
| 15 | 旧文档处置 | 删除重写 |
| 16 | 工程目录 | C# 骨架删除，新建干净目录 |
| 17 | 完成定义 | 样机跑通全部功能 |
| 18 | 软件包形态 | 整个文件夹递归复制（非 ZIP） |
| 19 | 资产处置 | 文档移 `docs/`，删骨架，新建 `ETWorkbench/` |
| 20 | IT-08/09 PowerShell 安全策略 | ✅ 已确认允许未签名脚本 |
| 21 | 主数据录入工具形态 | GUI 内「主数据」页签 |
| 22 | 本地目录规划 | 绿色包即程序目录；下载软件放 D 盘/用户目录 |
| 23 | 验收与推广 | P0 必做：样机 + 3 台现场试点机 |
| 24 | 工期与人力口径 | 2 人 × 20 个有效工作日 |
| 25 | 版本控制归属 | `.git` 提到工作区根，远程改为 `Bo123478/ET-SYS-OT`（2026-09-28 变更） |
| 26 | 保证等级 | 时间优先，诚实优先于乐观 |
| 27 | 本期交付 | 真实可用 > 覆盖面广 |
| 28 | **两人协作方式** | **A = WHB（主）、B = QYX（辅）**；按模块划分归属（见 §1.1） |
| 29 | **`Config/*.json` 归属** | **归 A（WHB）独占**；B 不直接编辑，变更走站会 |
| 30 | **接口契约冻结** | 以 `docs/interface-contract.md` v1.0.0 为 D1 基线；改动须站会确认并记入其 §1.4 |
| 31 | **推送闸门** | pre-push 串 3 个门禁（BOM+语法 / 集成 / 自检）；`.gitattributes` 只管换行符，**BOM 靠钩子** |

### 未决事项

| # | 事项 | 需谁定 | 状态 |
|---|---|---|---|
| U-1 | 共享根 UNC 路径 | IT / 文件服务 | ⬜ |
| U-2 | ET 访问共享的 Windows 身份 | AD / Endpoint | ⬜ |
| U-3 | `Upload` 能否按 `{EquipmentId}` 隔离 | 文件服务 | ⬜ |
| U-4 | 共享保留策略 | IT / 运维 | ⬜ |
| U-5 | 本地软件根路径 | 运维 | ⬜ |
| U-6 | 各现场机器清单与系统版本 | 运维 | ⬜ |

---

## 8. 更新日志

| 日期 | 版本 | 更新内容 | 更新人 |
|---|---|---|---|
| 2026-09-30 | V3.1 | **修 `D-13`：主窗口启动即失败（P0），同日发现、同日修复并闭环**。① **用户报障原文**：「**主窗口启动失败，显示找不到属性**」。② **根因（已实证）**：`ETWorkbench/Start-ETWorkbench.ps1` 第 **379** 行的物理行是 `    # ---- 页签 4 · 主数据 ----    BtnMdLoad       = Get-UiElement 'BtnMdLoad'` —— 属 `G-06` 那类「注释与代码被挤到同一物理行」的编辑事故，**整行被 PowerShell 当成注释**，于是 `$ui = @{ … }` 里的 **`BtnMdLoad` 从未登记**（静态比对 `declared 59` / `referenced 60`）。后果链：§12.7 刷新链读 `if ($ui.BtnMdLoad) { … }` ⇒ **`Set-StrictMode -Version 2.0` 下读取不存在的哈希键会抛错**（**不是**返回 `$null`，已单独实证）⇒ 被顶层 `trap` 接住 ⇒ `Show-ETError` 弹「工作台启动失败：在此对象上找不到属性"BtnMdLoad"。请确认该属性存在。」⇒ **主窗口一次都没打开过**。③ **为何难排查**：`-Console` 跑不到这里 —— 会话 0 守卫在 **XAML 加载之前**就 `exit 0`，故命令行看起来一切正常；且 XAML 本身无问题、`FindName` 也能解析到 `BtnMdLoad`。④ **修法**：把注释与代码**拆回两行**（**只改这一处**，其余 59 个键未动）。⑤ **补门禁盲区（本次重点）**：`tools/Test-ETIntegration.ps1` §12 原有检查 `every $ui.<Name> exists in the XAML` 只能证明「引用能在 XAML 里解析到」，**证明不了「该键已在 `$ui` 表里登记」**；新增反向检查 `Check 'every $ui.<Name> reference is declared in the $ui table'` —— 逐行**剥掉注释**后统计 `名字 = Get-UiElement '名字'` 形式的声明，再与全脚本 `$ui.<名字>` 引用求**差集**，任一「用了但没登记」的名字直接红。⑥ **双向实测证据**：修复后 → `60 control reference(s) all resolve` + **`60 declared key(s); every reference declared`** + **`PASS 46 / FAIL 0 / WARN 1`**；把 bug **注入回去** → 旧检查**照样**打 `60 control reference(s) all resolve` **全绿**（**盲区已实证**，非猜测）+ 差集报 `BtnMdLoad` + `PASS 45 / FAIL 1 / WARN 1`；由备份恢复修复后再跑全绿。另做**严格模式运行时模拟**：读取 `$ui` 表真实求值（`Get-UiElement` 打桩）后的**全部 60 个键** → `OK: no property-not-found error at runtime`。⑦ **回归全绿**：`Test-ETScripts.ps1` → `Scanned: 22 .ps1/.psm1, 5 .json, 2 .xaml` + `ALL CHECKS PASSED`（BOM 全齐）；`Test-ETIntegration.ps1` → `PASS 46 / FAIL 0 / WARN 1`；`Start-ETWorkbench.ps1 -SelfTest` → `结论：自检通过`（13 项）。⑧ **文档回写**：`ET-项目待办事项.md` **V1.8 → V1.9**（新增 §3.8 + `D-13` 条目；`G-06` 事故计数 **6 → 7**；统计 `D` 已完成 4 → **5**、`G` 已完成 1 → **2**，合计未完成仍 **49** / 已完成 **27 → 29**）；本节新增 **`N-23`** 并标 ✅。**本次无接口变更**（`docs/interface-contract.md` 未动，`tools/` 与入口脚本属未冻结面） | 开发 A |
| 2026-09-29 | V3.0 | **主窗口界面四项改动 + 页签寻址方式重构**。① **页签重排**为 **0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据**，并**把信息区设为启动默认页**（`MainWindow.xaml` 首个 `TabItem`，WPF 默认即选 index 0）；② **顶栏标题**由 `现场终端数字化运维 · ET 端` 改为 **`系统运维 · ET端`**，字号 **17 → 26**、`FontWeight=Bold`、水平+垂直居中（外层 `StackPanel VerticalAlignment="Center"` + `TextBlock HorizontalAlignment="Center"`，`TextTrimming=CharacterEllipsis` 防长标题溢出）；③ **信息区左侧内嵌铭牌卡片**：`MainWindow.xaml` 新增 `PlateCard` 样式（`316×248`、`CornerRadius=16`、渐变 `#FF17395F`→`#FF0D2338`→`#FF08182A`、边框 `#553FA9E0`），**逐字段复刻** `PlateBar.xaml` 的 5 行版式并新增 **11 个 `Plate*` 具名元素**（`PlateStrip`/`PlateTitle`/`PlateStatusPill`/`PlateStatusDot`/`PlateStatusText`/`PlateEquip`/`PlateEt`/`PlateIp`/`PlateMpc`/`PlateVer`/`PlateUpdated`）；配色与铭牌**同源**（`#FF2FBF71` / `#FFF2C94C` / `#FFE5533D`），状态**只从唯一的 `Get-ETStateVerdict` 取结论**（不新增第二份判据，防 `D-10` 复发）；原信息区内容（状态胶囊 5 项 + 本机与边界 + `BtnIdentify` + `TxtAbout` + `TxtIdentityOut`）整体右移为第二列，**旧的信息区 `TabItem` 已删除**（否则同名 `x:Name` 重复会让 `XamlReader::Load` 抛错）；④ **脚本导航改为按页签标题寻址**：新增 §6.5 **页签导航契约** —— `$script:TabIndex = @{ '信息区'=0; '应用区'=1; '警告提示'=2; '功能设置'=3; '主数据'=4 }`、`$script:TabHome = '信息区'`、`Select-ETTab '<标题>'`（未登记标题记 `Warn` 并返回 `$false`，不抛错）；**5 处硬编码 `MainTabs.SelectedIndex` 全部替换**为 `Select-ETTab`（`Invoke-ETAppLaunch` 空白目标与尾部、软件卡片「更新」跳转 → `功能设置`；一键更新 → `应用区`；`Esc` 归位与启动默认 → `$script:TabHome`）；⑤ **新增数据与刷新**：§8.1.5 `$script:SamplePlate`（`W098`/`ZET1025`/`096`，与铭牌同值）与 `$script:PlateCardVersion='1.1.0'`；`Resolve-ETPlateInfo` 新增 `Complete` 标志；`Get-ETAlarmState` 新增 `FromSample` 字段（**仅用于「示例」文案，不参与规则判定**）；新增 §12.7 `Update-InfoPlateCard`（IP 取 `Get-ETBusinessIp` 的 `Addresses[0]`，失败回退 `(未获取)`；三编号**整体**回退示例值，任一缺失就全部用示例并在标题加 `· 示例`），挂进 `Add_Loaded`、`BtnHealthCheck`、`BtnOneKeyUpdate` 三条刷新链；⑥ **注释与章节号同步**：`MainWindow.xaml` 文件头契约注释重写、脚本 §9~§14.5 的章节标题统一改为「页签 0 · 信息区」式命名；⑦ **回归三闸门全绿**：`Test-ETScripts.ps1` → `Scanned: 22 .ps1/.psm1, 5 .json, 2 .xaml` + **`ALL CHECKS PASSED`**；`Test-ETIntegration.ps1` → **`PASS 45 / FAIL 0 / WARN 1`**（`WARN` 为既有的「主数据快照为空」软跳过）+ **`60 control reference(s) all resolve`**（V2.8 为 49，本次新增 11 个 `Plate*`）；`-SelfTest` → **`结论：自检通过`**（13 项）；⑧ **无头 XAML 核对**：`x:Name` 总数 **66**，唯一重复组仍为模板作用域内的 `Bd ×5`（非缺陷），`TabItem` 标题序为 `信息区 | 应用区 | 警告提示 | 功能设置 | 主数据`；⑨ **遗留（未纳入本次）**：`Test-ETIntegration.ps1` §11 的 `DgSoftware` 探针为**陈旧探针**（该控件在 V2.6 已不存在 ⇒ 输出 `7/8`，门禁悄悄失效），已登记为待办 **`T-39`**，本次不改；`x:Name` 计数由 51 → **66**、`$ui` 键 49 → **60**；⑩ **文档回写**：`ET-项目待办事项.md` **V1.8**（新增并同日闭环 **`T-41`**）、`ET-SYS_开发方案.md`（§2.1 `E-07` 注记 + §5.4/§12 页签清单）、`docs/ET工作台方案_Version2.md` §2 实现注记均已同步页签新顺序。**未动任何模块与 83 个导出函数**，`docs/interface-contract.md` 的冻结导出签名未变（UI 文件属 class A，已在 `docs/interface-contract.md` §1.4 变更日志追加「无接口变更」行） | — |
| 2026-09-29 | V2.9 | **修复「单实例限制不起作用」的真缺陷并取证**。① **现象**：铭牌（标签）与主窗口**都能重复打开**，限制作形同虚设；用户报「标签限制没成功」「标签启动个数限制，为什么不起作用」。② **根因（真缺陷）**：**拦截分支里调用了当时尚未定义 / 尚未 `Add-Type` 的东西** —— 主窗口 `Start-ETWorkbench.ps1` 的拦截分支调用 `Show-ETError`（该函数定义在其下方），铭牌 `Start-ETPlate.ps1` 的拦截分支调用 `[System.Windows.MessageBox]::Show(...)`（`PresentationFramework` 要等第 4 步才 `Add-Type`）。两者都抛「无法识别 / 找不到类型」，**被包裹整个启动流程的外层大 catch 吞掉** ⇒ 脚本**不会 `exit`，继续往下走** ⇒ 第二个窗口/铭牌照常弹出。**教训：拦截分支里的任何代码都不允许能抛进外层 catch；必须自带 `try/catch` + 无条件 `exit 0`。** ③ **修法**：两把 `Global\` 命名互斥锁提到**脚本最前面**（主窗口 §0.5、铭牌 §1，**均在会话 0 守卫之前**，否则本环境（Session 0）根本测不到）；锁存入**脚本作用域变量**（`$script:MainWindowMutex` / `$script:PlateMutex`）—— `Mutex` 有**线程亲和性**，存局部变量会被 GC 回收而释放；兜底 `Get-CimInstance Win32_Process` + `CommandLine -like '*Start-ETWorkbench.ps1*'` / `'*Start-ETPlate.ps1*'`（主窗口另加 `-notlike '*-SelfTest*'`）。④ **拦截分支硬化**：**先把提示 `Write-Host` 出来再弹窗**（无头/自动化场景也能看到），弹窗自带 `try/catch` 并加 `if ([System.Environment]::UserInteractive)` 闸门 —— **Session 0 里 `MessageBox` 无人点击会永不返回**（表现为「挂住」），这是本次实测踩到的第二个坑；最后**无条件 `exit 0`**。⑤ **新增验证工具**（`tools/`，**内容全 ASCII**；编写时**刻意无 BOM**，2026-09-30 已补加 BOM。真正的原因是**含中文的**无 BOM `.ps1` 会被 PS 5.1 按 ANSI 解析成假语法错误，故 `tools/` 探测脚本一律只写 ASCII）：`Test-ETMutexProbe.ps1`（持锁 N 秒，看第二进程是否 `BLOCKED`）、`Verify-ETSingleInstance.ps1`（6 节端到端：干净态 → 铭牌单开 → 主窗口单开 → 铭牌被拦 → 主窗口被拦 → 清理，含 `FREE`/`HELD` 锁状态探针）。⑥ **实测证据**：§1 两锁均 `FREE`、残留 ET 进程 0；§2 铭牌单开输出 `[ET-Plate] 当前为会话 0（无交互桌面），无需显示铭牌，已退出。`；§4 持锁后铭牌被拦 → `[ET-Plate] ET 设备铭牌已打开，不能重复打开。`；§5 持锁后主窗口被拦 → `[ET] ET 工作台已打开，不能重复打开。`（两次 `plate lock: HELD` / `main lock: HELD`，第二实例未夺锁）。⑦ **另记一处非缺陷**：不带 `-Console` 运行主窗口在本环境下**没有任何输出是正常的**（会话 0 提示走 `Write-Boot`，而它只在 `-Console`/`-SelfTest`/非 `Info` 时打印），排查时不要误判为「脚本坏了」。另注：`Start-Process -PassThru` 的 `ExitCode` 可能取到 `$null`（即使进程已退出），打印前需判空否则 `-f` 会报「索引(从零开始)必须大于或等于零」。⑧ **回归**：`Test-ETIntegration.ps1` → **`PASS 45 / FAIL 0 / WARN 1`**（无回退）；两入口脚本 **BOM 均在**（`Start-ETWorkbench.ps1` / `Start-ETPlate.ps1`）。⑨ **文档回写**：`ET-项目待办事项.md` **V1.6 → V1.7**（新增并同日闭环 **`T-40`**、§1.2 统计改 **未完成 49 / 已完成 26**）。**未动任何模块与 83 个导出函数**，`docs/interface-contract.md` 未改 | — |
| 2026-09-29 | V2.8 | **主窗口页签化重构（三区 → 5 页签）+ 两个真缺陷修复**。① **`MainTabs` 转正**：V2.5 用「零尺寸隐藏路由」保留旧导航语义的做法作废，`TabControl` 变为**可见的功能分区骨架**，三区内容（`SoftCardPanel` / 信息区 / `AlarmCardPanel`）整体收进页签；顺序 **0 生产软件 / 1 警告提示 / 2 信息区 / 3 功能设置 / 4 主数据**，**页签序号即导航契约**（`Start-ETWorkbench.ps1` §15 切换、`Esc` 归位、软件卡「更新」跳转均按序号寻址，改动须同步，见 `G-07`）。**主窗口 `x:Name` 37 → 51、`$ui` 引用 42 → 49**，`Test-ETIntegration.ps1` 输出 **`49 control reference(s) all resolve`**；② **新增 §12.5 警告提示分类汇总**：`$script:ETAlarmCategories`（网络 / Windows / 共享 / 与系统清单对比）+ `Get-ETRuleCategoryKey`（**提到脚本作用域**，供 §12.5 与 §12.6 共用）+ `New-AlarmSummaryCard` / `Update-AlarmSummary`；③ **修复真缺陷「告警卡片计数恒为 0」**：原实现统计 `$snap.Samples` 里 `Status -eq 'Alarm'/'Warning'`，而 `Get-ETMetric` 的 `Status` **只可能是 `Ok`/`Unknown`**（`ET.Health.psm1:80`）⇒ 有告警时四类卡片全部显示 `0/0` 且渲染为**绿色**，属误报安全；改为从 `$snap.Alarms` 按 `RuleId` 归属 + 按 `Severity` 拆 告警/警告，`Unknown` 样本单独计并显示**灰色**（不冒充绿色）。无头核对结果为 CONSISTENT；④ **新增 §12.6 信息区汇总** `Update-InfoSummary`：主窗口打开后把铭牌式摘要放进信息区（身份 / 共享 / 软件版本摘要 / 重要告警摘要）；⑤ **消除三态判据双写（缺陷 `D-10`）**：新增 `$script:ETStateRules`（5 条规则逐字移植自 `Start-ETPlate.ps1` 的 `$Script:PlateRules`）+ `Get-ETAlarmState` / `Get-ETStateVerdict` / `Get-ETStateColorText`，主窗口与铭牌**共用同一判据**，删除 `Add_Loaded` 内联的三态 `if`（§8.2 注释明文要求「都必须从这里取结论」以防复发）；⑥ **新增 §14.5 功能设置 + `Config/settings.json`**（本地覆盖层语义，A 独占）：日志上传开关、自动更新开关、生产软件一键更新（**串行 `Invoke-ETDownload` 循环，守住 C-7 并发 = 1**）、打开数据根目录、日志级别 / 保留天数、**界面字号**（`$script:ETUiScales` + `Get-ETUiScaleKey` + `Apply-UiScale`，`ComboBox` 绑定**显示文字数组**而非对象以免现场显示类型名）、**启动即进入桌面模式**（`Initialize-ETStartupDesktopMode` 让启动形态由本机偏好决定，不再无条件铺满）、计划任务节奏**只读**说明（`Update-ScheduleNote`，不回写任何节奏）；⑦ **新增 `Config/software-categories.json`**：软件卡片按 生产软件 / 系统工具 / 周边 / 其他 分组（磁贴式，`Get-ETSoftwareCategories` + `New-SoftwareSectionHeader`），`SoftwareIds` 为空时按 `SoftwareId` 前缀猜测；⑧ **修复三处实现缺陷**：`Update-AlarmSummary` 的 `ConvertTo-ETBrush (switch …)` **裸 `switch` 作命令实参导致解析失败**（已提为变量）、`Get-ETConfigFilePath` 未导出（改用 `Get-ETProgramRoot`）、`Invoke-ETDownloadAll` 并不存在（改为串行循环）；⑨ **诚实口径登记**：`LogLevel` / `LogRetentionDays` 已持久化但**尚未有消费者**（日志写入侧未读），已在保存成功提示中明说并登记为 `T-37` 的一部分；`TxtScheduleNote` 本就**只读**（`T-38`）；⑩ **文档回写**：`ET-项目待办事项.md` **V1.5 → V1.6**（新增 §3.7「主窗口页签化重构」整节、新增 `B-14`/`B-15`/`T-32`~`T-39`/`G-07`/`D-12`、`D-10` 与「告警计数恒为 0」两缺陷入 §3.3 与 §4 已闭环、§1.1 看板与 §1.2 统计同步）；`docs/ET工作台方案_Version2.md` 三区需求处加实现注记（**需求原文未改**，仅注记页签是同一三区的另一种实现）；`ET-SYS_开发方案.md` 加 `E-07` 实现注记、`§5.4` 目录树改为现状校准表 + 更正后的树、`§7.5` 加实现注记、`D15` 行标注 `AboutPage.xaml` 已并入页签；⑪ **本文件同步**：§3.0 界面 37 → **51** 个 `x:Name`、配置文件 3 → **5**、文件总数 19 → **21**、`$ui` 42/42 → **49/49**、闸门说明 3 JSON → **5 JSON**、E-07 行与 §7.4 验收行改为 5 页签、附录目录树同步、偏离表 `D-1` 的「6 个页签」更正为 **5 个页签**并注明序号即契约。**三道闸门全绿（复核）**：`ALL CHECKS PASSED`（20 `.ps1/.psm1` + 5 JSON + 2 XAML）/ `PASS 45 FAIL 0 WARN 1`（含 `49 control reference(s) all resolve`）/ `-SelfTest 13 通过`（`结论：自检通过`、`G3_EXIT=0`）；另跑 `.tools-tmp/check-parse.ps1` 得 `PARSE OK: 14 files` + `$ui` 49 唯一 + `x:Name` 51 唯一 + 逐名解析 OK。**未动任何模块与 83 个导出函数**，`docs/interface-contract.md` 未改；⚠️ 已知未解决：`Test-ETIntegration.ps1` §11 仍探 `DgSoftware`（XAML 中已不存在，靠 `Where-Object` 容错，打印 `7/8`）⇒ 登记 `T-39`；`Resolve-ETPlateInfo` 仍无调用点 ⇒ 登记 `D-12`；`UI/MainWindow.xaml.bak` 待删（`.gitignore` 已忽略） | — |
| 2026-09-29 | V2.7 | **文档一致性与工具链护栏（无代码改动）**。① **修复待办文档坏行**：`ET-项目待办事项.md` §6 更新日志的 **`V1.3` 行与 `V1.4` 行被挤成同一物理行**（1593 字符）——这是本仓库第 5 次表格坏行事故，已拆为两行（同次另有 1 次记忆文件整块重复事故）；② **新增待办 `G-06`**（工程护栏，P1）：「局部替换类编辑工具的部分匹配静默污染」——`oldString` 只命中行/块前半部分时，未被覆盖的尾巴会原样保留并拼在新内容之后；详情表列出**全部 6 次事故**与四条硬性要求（含 **PS 5.1 降序区间 `$L[575..574]` 不返回空数组、会反向重复写回** 这条本次实测踩到的坑）；③ **修复知识库文件**：`/memories/repo/et-workbench.md` 由 **282 行**（含重复的 `## 身份`~`## 关键陷阱` 整段）修回 **237 行**，13 个 `##` 标题全部唯一，无 BOM 状态保持不变；④ **纠正一处陈旧交叉引用**：本文件 §3.3 曾把 `PlateBar.xaml` 补 BOM 的事写成「待办 D-07/G-06」，**`G-06` 与 BOM 无关**，已改指 **`G-01`**／`D-07` 并加注区分；⑤ **版本号对齐**：本文件 V2.6 → **V2.7**，附录目录树里的待办版本由 **V1.3 → V1.5**、本文件由 V2.6 → V2.7；⑥ **待办文档升版**：`ET-项目待办事项.md` V1.4 → **V1.5**（新增 `G-06` 进 §3.4 与 §1 P1 看板、§1.2 统计同步为 **未完成 39 / 已闭环 22**、`G` 类 4 → 5）。**文档类改动，未触碰任何 `.ps1`/`.xaml`/`.json` 与 83 个导出函数**；表格完整性自检已跑（`bad table rows: 0`），BOM 状态：本文件**有 BOM**、待办文档**无 BOM**（均维持原状） | — |
| 2026-09-29 | V2.6 | **铭牌方向反转：回退为原尺寸式样 + 左侧垂直居中**（依用户指令「使用原来的尺寸和式样，位置左侧居中」）。① `PlateBar.xaml` 由 340×88 横向矮条**重写回原 `TrayBadge.xaml` 的 316×248 竖向工业铭牌卡**（13 个 `x:Name`，5 行版式，`StatusPill` 新增为具名元素），**与原设计的唯一刻意偏离是 `Topmost` 由 `True` 改为 `False`**（红线 **F-4** 禁置顶），沉底改由 `HWND_BOTTOM` 承担，文件头已注明**不可回退**；② `Start-ETPlate.ps1` 的 `Sync-PlatePosition` 重写为 **`Left = WorkArea.Left` / `Top = round(WorkArea.Top + (H-窗口高)/2)`**（`ActualHeight` 优先、缺失时回退 `Height`、再回退 `248`；`[math]::Round` 避免半像素抖动），新增 **`Add_SizeChanged` 钩子**解决 `ActualHeight` 首帧未就绪，`$Script:ui` 由 **9 → 11** 项（补 `TxtBadgeVer`/`TxtUpdated`/`StatusPill`）并修掉 `RootBorder.ToolTip` 被每次刷新覆盖的缺陷，右键菜单/确认框文案同步为「铭牌」「左边缘」；③ **移除主窗口顶栏 `PlateSlot`**（经 `git show f5123e9` 核对，该槽位**非原始设计**，只是为矮条像素对齐而加）—— 主窗口 `x:Name` **46 → 37**、顶栏由 3 列并为 2 列，同时清理 `Start-ETWorkbench.ps1` 的死代码（删 `Update-PlateStrip`、清 `TxtTitle`/`TxtStatus`/`HdrStrip`/`TxtPlate*` 引用，保留仍被摘要使用的 `Get-ETFirstValue`/`Resolve-ETPlateInfo`）；④ **状态色不丢失**：`StatusBarDot` 迁入底部状态条（新增第 6 个 `Auto` 列）；⑤ **文档同步**：`MainWindow.xaml`/`Start-ETPlate.bat` 陈旧注释改写，`ET-项目待办事项.md` 回写 **V1.4**（新增并闭环 `T-30`、新增 `T-31`、`T-26`/`B-08` 结论作废标注、统计 38/22）。**三道闸门全绿**：`ALL CHECKS PASSED`（并以 `-Fix` 补回 `PlateBar.xaml` 的 BOM）/ `PASS 45 FAIL 0 WARN 1` / `-SelfTest 13 通过`；另用**无头 XAML 加载器逐名核对**（脚本引用的 37 + 12 个名字全命中、无悬空引用），并实测居中坐标（1024×768 工作区 → `Left=0`、`Top=260`）。**未动任何模块与 83 个导出函数**，`docs/interface-contract.md` 未改；⚠️ 已知未解决：竖版铭牌会盖住软件区卡片左边缘（需 `B-12`/`T-31` 现场确认）、`D-09` 控制台黑窗未修、§4 表 `T-17`~`T-22` 编号重复（历史遗留，本次不改编号） | — |
| 2026-09-29 | V2.5 | **桌面语义落地 + 常驻铭牌改造**。① `MainWindow.xaml` 重写为**三区桌面布局**（左上软件区 / 右上信息区 / 右下报警区），保留零尺寸隐藏 `MainTabs` 路由以继承旧导航语义；② 实现现场三条硬需求 —— **默认铺满工作区**（手工贴合 `WorkArea`，不用 `Maximized`）、**任务栏不显示**（`ShowInTaskbar=False` + `WS_EX_TOOLWINDOW`）、**永远处于最低层**（`SetWindowPos(HWND_BOTTOM)` + `SWP_NOACTIVATE`，**这不是 `Topmost`，红线 F-4 禁置顶不禁沉底**，另加 3 秒 `SinkTimer` 兜底）；③ 常驻铭牌由 316×248 竖版卡片改为 **340×88 横向条**，与顶栏 `PlateSlot` 像素级重合；④ 旧名 `TrayBadge`/`Start-ETTray` **全量重命名**为 `PlateBar`/`Start-ETPlate`（旧文件已删）；⑤ 新增两处逃逸通道（顶栏关闭按钮 + 哨兵文件 `workbench.stop`/`plate.stop`）与两入口的 **Session 0 守卫**；⑥ **报警三态「都归红」**（`W-01`/`W-02` 改 `Alarm`）；⑦ 修复 `Start-ETPlate.ps1`/`PlateBar.xaml` **缺失 BOM**（曾伪装为 41 个语法错误）；⑧ 消除重复的 `SinkTimer` 滴答注册；⑨ 建立 `ET-项目待办事项.md` 并回写 V1.2。**三道闸门全绿**：`ALL CHECKS PASSED`（20+3+2）/ `PASS 45 FAIL 0 WARN 1` / `-SelfTest 13 通过`。**未动任何模块与 83 个导出函数**，`docs/interface-contract.md` 未改 | — |
| 2026-09-28 | V2.4 | **三项护栏已提交**（`edef1df`）并在推送前跑通三道闸门（`PASS 45 / FAIL 0`）。修复新发现的 **D-7**：`Save-ETHealthState` 缺输入校验，`-State @{}` 可静默写坏 `health-state.json` 并致**此后每轮** `Invoke-ETHealthCheck` 抛错 —— 该缺陷是在编写契约做探测时被真实触发、而非推演。修复采用「写侧抛错 + 读侧降级留痕」不对称策略，理由见契约 §10.4。同时修好一处被写入挤坏的表格行（N-12 与 N-8 同行） | — |
| 2026-09-28 | V2.3 | **落定两人协作机制**：新增 §1.1 角色分工（A=WHB 主 / B=QYX 辅，`Config/*.json` 归 A 独占）；新增**决策 28~31**（协作方式、配置归属、接口契约冻结、推送闸门）；新增**风险 R-11**（换行符/BOM，已解除）并说明 **Git 无法强制 BOM** 的能力边界。交付三项工程护栏：`.gitattributes`、`tools/Install-ETHooks.ps1`、`docs/interface-contract.md`（ET-IFC-001 v1.0.0，83 导出函数冻结契约） | — |
| 2026-09-28 | V2.2 | **仓库远程地址变更**：`Bo123478/ET-Workstation` → **`Bo123478/ET-SYS-OT`**；首次推送成功（远端 HEAD = `52fda21`）；同步修正方案 §3.1 与决策 25 中的旧地址；修正附录「文件总数 21」为 `ETWorkbench/` **17 文件**（原数字误将 `tools/` 脚本计入） | — |
| 2026-09-28 | V2.1 | **建成可运行工程骨架**：`ETWorkbench/` 17 文件 / 8 模块 / 83 导出函数 / XAML 界面 / 4 计划任务；新增 `Test-ETScripts.ps1`（BOM+语法）与 `Test-ETIntegration.ps1`（12 节冒烟，**PASS 45 / FAIL 0**）；实机体检取证（ExecutionPolicy=`Bypass`、BIOS SN、业务 IP、共享未配置）；**修复 5 个 StrictMode 缺陷**；范围与进度口径澄清（骨架 ≠ 功能实现）；`show-ui.ps1` 死引用修复 + Session 0 探测 | — |
| 2026-09-28 | V2.0 | 全量重写。范围从 6 工作流收缩为 ET 端单工作流；锁定 27 项决策；解析 IT 权限清单 28 项；完成工作区重组；7 项功能全部 ⬜ 未开始；阻塞于 R-1 | — |
| 2026-09-28 | V1.0 | （已删除）原全平台方案进度，因范围重设作废 | — |

---

## 附录：工作区当前状态（已完成）

```text
ET-workstation&SYS-OT/          ← git 仓库根（远程 Bo123478/ET-SYS-OT）
├─ .git/                        ← 由 ET-Workstation/.git 上提而来
├─ .gitignore                   ← 新建（含 ETWorkbench 运行期数据排除）
├─ ET-SYS_开发方案.md            ← V2.0 已重写
├─ ET-SYS_开发进度.md            ← V2.7 本文件
├─ ET-项目待办事项.md            ← 待办唯一汇聚点（V1.7，无 BOM，见 G-01）
├─ Start-ETWorkbench.bat        ← 双击启动工作台
├─ Start-ETPlate.bat            ← 双击启动常驻铭牌条
├─ 现场数字化运维最终方案_PowerShell_M365_Databricks.md   ← 权威 ET 基线（未改）
├─ 数字化运维平台_AI_Agent总体架构 2.pptx                ← 根目录原有
├─ docs/
│  ├─ ET工作台方案_Version2.md                        ← 从 ET-Workstation 抢救（532 行版）
│  ├─ ET数字化运维_IT权限与接口确认清单.xlsx            ← 从未备份状态抢救
│  └─ 现场数字化运维最终方案_汇报版.pptx                ← 13.5 MB 从未备份状态抢救
├─ tools/
│  ├─ show-ui.ps1                                     ← 抢救（已改为指向 ETWorkbench 入口）
│  ├─ check-appcontrol.ps1                            ← 抢救（环境体检）
│  ├─ Test-ETPrerequisites.ps1                        ← 新建（D0 前置条件检查）
│  ├─ Test-ETScripts.ps1                              ← 新建（BOM + 语法全量校验）
│  └─ Test-ETIntegration.ps1                          ← 新建（12 节集成冒烟，FAIL 0）
├─ SYS-Operational Technology/  ← 平台侧（本期暂缓，未改动）
└─ ETWorkbench/                 ← ✅ 骨架已建（D1 提前完成）
   ├─ Start-ETWorkbench.ps1     ← 主窗口入口（-SelfTest / -Console，含内嵌 C# ETWindowNative）
   ├─ Start-ETPlate.ps1         ← 常驻铭牌入口（含内嵌 C# ETPlateNative / ETPlateActivate）
   ├─ Config/                   ← workstation / paths / health-rules / **settings** / **software-categories** 五份 JSON
   ├─ Modules/                  ← 8 个 .psm1，共 83 个导出函数
   ├─ Tasks/                    ← 4 个计划任务脚本
   └─ UI/                       ← MainWindow.xaml（**5 页签**桌面布局）+ PlateBar.xaml（**316×248 左侧垂直居中铭牌**）

已删除：
├─ 运维工作台/                  ← 重复目录 + 重复 git clone（168 文件 / 13.39 MB）
├─ ET-Workstation/              ← 壳目录（骨架已删，.git 已上提）
├─ Workbench.sln + src/**/*.csproj|.cs|.xaml|.manifest   ← C# 骨架（GitHub cdd23b9 可恢复）
└─ src/**/bin + src/**/obj      ← 24 个构建产物目录
```

### 与方案的偏离（必须记录）

| # | 方案写法 | 实际做法 | 原因 |
|---|---|---|---|
| D-1 | `UI/` 下 7 个分页 `*.xaml`（方案 §5.4） | **单文件** `UI/MainWindow.xaml`，内部用 `TabControl` 分 **5 个页签**（**V3.0 起为 0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据**；V2.8 曾为 0 生产软件 / 1 警告提示 / 2 信息区 / 3 功能设置 / 4 主数据） | 单文件无 `ResourceDictionary` 加载顺序/路径问题，绿色包拷贝更简单；页签数量与控件引用完全一致。**页签顺序是导航契约（`G-07`），但寻址方式已于 V3.0 由「数字索引」改为「页签标题」**（`Select-ETTab` + `$script:TabIndex`），重排只需同步该映射表与 XAML |
| D-2 | 主数据录入工具为独立工具 | 并入工作台 GUI 的「主数据」页签 | 决策 21 已锁定 |
| D-3 | `FileNames.Event*` 约定为 `.ndjson` | `ET.Outbox` 实际写 `{EventId}.json` | `New-ETEventId` 按 `.ndjson` 搜序号与写入扩展名不一致，属**外观不一致，不影响功能**；D1 统一为 `.ndjson` 或同步改 `FileNames` |
| D-7 | `Save-ETHealthState` 应受结构校验 | 无任何校验，`-State @{}` 静默写盘并**永久锁死**健康检测 | **已修复**：写侧拒绝非法状态并抛错（与 `Save-ETHealthSnapshot` 对称）、读侧结构异常时降级为空状态并记 `Warn`。触发链与取舍见 `docs/interface-contract.md` §10.4 |
