# ET 数字化运维工作台 —— 模块接口契约（D1 冻结基线）

> **文档编号**：ET-IFC-001
> **版本**：v1.0.0（冻结基线）
> **冻结日期**：2026-09-28
> **冻结对象**：`ETWorkbench/Modules/*.psm1` 的 **83 个导出函数**
> **数据来源**：模块元数据 `(Get-Module ET.X).ExportedCommands` + AST 签名提取 + 两轮运行时探测
> **约束依据**：`ET-SYS_开发方案.md` §3.2（C-1 ~ C-8）

---

## 0. 本文档的地位与免责边界

本文档**不是设计文档**，而是**实测快照**。

它只记录一件事：**`ETWorkbench/Modules/` 里那 83 个导出函数，在当前代码状态下，实际接受什么参数、实际返回什么结构、实际如何报错。**

所有内容均来自对当前工作区的只读探测，未做任何推断性补全。凡本文档写"实测"，即为当次运行的真实输出；凡本文档写"未验证"，即**不得**在下游代码中依赖该行为。

### 为什么需要这份文档

两名开发人员（A/B）并行开发时，最大的返工来源不是写错代码，而是**一方按"应该返回什么"编码，另一方按"实际返回什么"实现**。

本项目已实测到三类此类断裂：

| 类型 | 实例 | 后果 |
|---|---|---|
| 返回 `$null` 而非空数组 | `Get-ETSoftwareCatalog` 等 10 处 | 调用方 `.Count` 直接抛错 |
| 返回"文件名模板"而非路径 | `Get-ETPath -Category File` | 调用方 `Test-Path` 永远为 `$false` |
| 参数校验抛异常而非返回错误对象 | 全部 `ValidateSet` 参数 | 调用方 `if (-not $r.Ok)` 完全失效 |

这三类断裂在**编译期不可见、单元测试易漏、只在集成时爆炸**。本文档的作用就是把它们提前钉死在纸上。

---

## 1. 冻结规则

### 1.1 冻结范围

**已冻结**（改动需走 §1.3 流程）：

- 83 个导出函数的**函数名**
- 83 个导出函数的**参数名、参数类型、Mandatory 属性、ValidateSet 枚举域**
- 导出函数的**返回结构字段名**
- §6 定义的**错误语义分类**

**未冻结**（可自由改动）：

- 函数**内部实现**
- 非导出（私有）函数
- 日志文案、错误消息的具体措辞
- `Config/*.json` 的**值**（但键名受 §1.1 保护，因为 `Get-ETConfig` 直接暴露）

### 1.2 为什么冻结

D1 阶段 A/B 两人要同时动 6 个模块。若接口可自由漂移，B 改 `ET.Transfer` 的返回字段，A 的 `ET.Update` 会在**没有任何编译错误**的情况下静默拿到 `$null`。

冻结的目的不是禁止改动，而是**让每次都改动可见**。

### 1.3 变更流程

接口变更**必须**经每日站会确认，并写入 `ET-SYS_开发进度.md` §7 决策记录：

1. 提出方在站会说明：改哪个函数、改哪个字段、**谁会受影响**
2. 受影响方确认已有调用点已同步
3. 在本文件 §1.4 变更日志追加一行
4. 更新本文件对应签名表
5. 版本号按语义化递增（字段增删 = minor；字段删除/改名/枚举域收窄 = **major，必须双方同步发版**）

**禁止**：单人直接改导出函数签名后提交。pre-push 闸门会跑集成测试，但集成测试**覆盖不到全部 83 个函数**，闸门通过不等于接口兼容。

### 1.4 变更日志

| 日期 | 版本 | 变更 | 提出人 | 受影响模块 |
|---|---|---|---|---|
| 2026-09-28 | v1.0.0 | 初版冻结，基线为 89 定义 / 83 导出 / 6 私有 | — | 全部 |
| 2026-09-29 | v1.0.0 | **无接口变更**。单实例限制修复：`Start-ETWorkbench.ps1` / `Start-ETPlate.ps1` 各加一把 `Global\` 命名互斥锁并把守卫前移到 Session 0 检查之前。两者均属**未冻结面**（入口脚本，非模块导出），83 个导出函数的名称/参数/返回字段一字未动 | A | `ETWorkbench/*`（未冻结） |
| 2026-09-29 | v1.0.0 | **无接口变更**。主窗口界面四项改动（页签重排 `0 信息区 / 1 应用区 / 2 警告提示 / 3 功能设置 / 4 主数据`、顶栏标题改 `系统运维 · ET端`、信息区内嵌铭牌卡、默认打开信息区）+ 页签寻址改为按标题（`Select-ETTab`）。`UI/MainWindow.xaml`（`x:Name` 51→66）与 `Start-ETWorkbench.ps1`（`$ui` 49→60）均属**未冻结面**，83 个导出函数未动 | A | `UI/MainWindow.xaml`、`ETWorkbench/Start-ETWorkbench.ps1`（均未冻结） |
| 2026-09-30 | v1.0.0 | **无接口变更**。修复 `D-13`（主窗口启动即失败）：`Start-ETWorkbench.ps1:379` 注释与代码被挤到同一物理行 ⇒ `$ui` 表缺 `BtnMdLoad` 键 ⇒ `Set-StrictMode 2.0` 读缺失哈希键抛「找不到属性」⇒ 主窗口从未打开。`ETWorkbench/Start-ETWorkbench.ps1` 与 `tools/Test-ETIntegration.ps1`（§12 新增 `$ui` 声明反向门禁）均属**未冻结面**，83 个导出函数的名称/参数/返回字段一字未动 | A | `ETWorkbench/Start-ETWorkbench.ps1`、`tools/Test-ETIntegration.ps1`（均未冻结） |

---

## 2. 模块归属与责任人

**A = WHB（主）** ｜ **B = QYX（辅）**

### 2.1 归属表

| 模块 / 文件 | 路径 | 导出数 | 归属 | 改动规则 |
|---|---|---:|---|---|
| `ET.Core.psm1` | `Modules/` | 24 | **共享** | **只增不改**（append-only）。两位都可加新函数；改/删已有导出须双方同意 |
| `ET.Identity.psm1` | `Modules/` | 7 | **B** | B 主改，A 可提 issue |
| `ET.MasterData.psm1` | `Modules/` | 7 | **B** | B 主改 |
| `ET.Software.psm1` | `Modules/` | 6 | **B** | B 主改 |
| `ET.Transfer.psm1` | `Modules/` | 7 | **B** | B 主改 |
| `ET.Health.psm1` | `Modules/` | 10 | **B** | B 主改 |
| `ET.Outbox.psm1` | `Modules/` | 12 | **B** | B 主改 |
| `ET.Update.psm1` | `Modules/` | 10 | **A** | A 主改 |
| `UI/MainWindow.xaml` | `UI/` | — | **A** | A 主改 |
| `Start-ETWorkbench.ps1` | `ETWorkbench/` | — | **A** | A 主改 |
| `Config/*.json` | `Config/` | — | **A** | **A 独占。B 不直接编辑，需变更时提 PR/站会** |
| `Tasks/*.ps1` | `Tasks/` | — | **B** | B 主改 |
| `tools/*.ps1` | `tools/` | — | **共享** | 闸门脚本，改动会影响双方推送 |
| `Tests/*` | `tests/` | — | **共享** | |

### 2.2 冲突热点（重点协调）

| 热点 | 原因 | 缓解 |
|---|---|---|
| `Config/*.json` | `Get-ETConfig` 返回的键被全部 83 个函数消费 | **A 独占**。B 需要新配置项 → 站会提出 → A 加 |
| `ET.Core.psm1` | 每个模块都 `Import-Module ET.Core` | 只增不改。新增函数放在文件末尾，避免 diff 冲突 |
| `paths.json` | C-2 唯一路径来源，A/B 都读 | 同上，A 独占 |
| `Test-ETIntegration.ps1` | 断言全部模块 | 改动前先跑一遍确认基线为绿 |

---

## 3. 全局调用约定（**必须遵守**）

以下 8 条是本文档的**操作核心**。每条都有实测证据支撑。

### ★ 3.1 一切返回集合的调用都必须用 `@()` 包裹

**实测**：至少 **10 个**导出函数在"无数据"时返回 `$null`，而**不是**空数组：

```
Get-ETSoftwareCatalog        Get-ETLocalVersions        Get-ETUpdateHistory
Get-ETDownloadHistory        Get-ETInstalledApplications
Get-ETMasterDataSnapshot     Resolve-ETApplication      Get-ETShareRoot
Get-ETSharePath              Get-ETOutboxTargetPath
```

实测确认：`isNull=True`，`@($null).Count = 0`。

**后果**：`(Get-ETDownloadHistory).Count` → `Set-StrictMode` 下抛 `属性 'Count' 无法在此对象上找到`。

**正确写法**：

```powershell
$rows = @(Get-ETSoftwareCatalog -EquipmentId $eqId)
if ($rows.Count -gt 0) { ... }
```

**错误写法**：

```powershell
$rows = Get-ETSoftwareCatalog -EquipmentId $eqId
if ($rows.Count -gt 0) { ... }   # 无数据时抛异常
```

> 本项为**强制**约定。新增导出函数若无数据，**也允许返回 `$null`**（与现状一致），调用方一律 `@()` 包裹，不做例外。

### ★ 3.2 参数校验失败 = 抛异常，**不**返回错误对象

**实测**：传入不在 `ValidateSet` 内的值时：

```
New-ETOutboxItem -EventType 'Nope'
  -> THROW: 无法对参数"EventType"执行参数验证。
            参数"Nope"不属于 ValidateSet 属性指定的集合"Health,Alarm,Deployment,Audit"。
```

同理，`[Parameter(Mandatory)]` 传 `$null`：

```
Add-ETOutboxItem -Item $null
  -> THROW: 无法将参数绑定到参数"Item"，因为该参数是空值。
```

**后果**：`if (-not $r.Ok)` 这种写法在**参数错误**场景下**永远走不到**，异常直接冒泡。调用方必须用 `try/catch` 或 `-ErrorAction` 控制。

### ★ 3.3 业务失败 = `Ok=$false` + `Errors[]`，**不**抛异常

**实测**（`Get-ETDownloadPlan` / `Get-ETReleaseManifest` / `Test-ETDownloadedPackage` 三者一致）：

```
Get-ETDownloadPlan -ApplicationId 'NOPE' -Version '1.0'
  -> Ok=False   Errors=["找不到发布清单："]
```

**这是 delegate 约定的统一形态**：涉及"外部资源不存在"的业务失败，返回 `Ok=$false` 并在 `Errors[]` 说明原因。

**3.2 与 3.3 的分工**：

| 场景 | 行为 | 判定方式 |
|---|---|---|
| **参数本身非法**（枚举域外、必填传空） | **抛异常** | `try/catch` |
| **参数合法但业务不成立**（清单不存在、路径不可达） | 返回 `Ok=$false` | `if (-not $r.Ok)` |

调用方**必须同时处理两者**：

```powershell
try {
    $plan = Get-ETDownloadPlan -ApplicationId $appId -Version $ver
    if (-not $plan.Ok) { Write-ETLog -Message ($plan.Errors -join '; ') -Level Warn; return }
}
catch {
    Write-ETLog -Message "参数错误：$($_.Exception.Message)" -Level Error
    throw
}
```

### ★ 3.4 `Get-ETPath` 的四个 Category 语义完全不同

**实测**：

| Category | 返回 | 实例 | 是路径吗 |
|---|---|---|---|
| `LocalDir` | **绝对路径**（本地数据区） | `C:\ProgramData\ETWorkbench\Snapshot` | ✅ 是 |
| `ProgramDir` | **绝对路径**（程序区） | `<repo>\ETWorkbench\Modules` | ✅ 是 |
| `File` | **文件名模板**（带占位符） | `EVT-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson` | ❌ **不是路径** |
| `UploadSub` | **裸段名** | `Health` | ❌ **不是路径** |

**后果**：`Test-Path (Get-ETPath -Category File -Name EventHealth)` 恒为 `$false`。把 `File` 类结果当路径用是**高危错误**。

`File` / `UploadSub` 的用途是**取模板再填充**，实际路径必须由 `Get-ETOutboxTargetPath` 或 `Get-ETSharePath` 组装。

**`File` 类全部 8 个键的实测模板值**：

```
Log             et-{yyyyMMdd}.log
EventHealth     EVT-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
EventAlarm      ALM-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
EventDeployment DEP-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
EventAudit      AUD-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
Command         CMD-{RequestId}.json
Result          RES-{RequestId}.json
CurrentPointer  Current.json
```

### ★ 3.5 共享未配置时，`Get-ETShareRoot` / `Get-ETSharePath` 返回 `$null`

**实测**（当前 `workstation.json` 的 `Share.ShareRoot` 为空）：

```
Get-ETShareRoot                       -> [NULL]
Get-ETSharePath -Category MasterData  -> [NULL]
Get-ETSharePath -Category Release     -> [NULL]
Get-ETSharePath -Category ConfigRules -> [NULL]
Get-ETSharePath -Category Upload      -> [NULL]
Get-ETSharePath -Category Archive     -> [NULL]
```

**5 个 Category 全部返回 `$null`**，无一例外。

**调用方规则**：任何依赖共享的代码，**先判空再使用**：

```powershell
$shareRoot = Get-ETShareRoot
if (-not $shareRoot) {
    Write-ETLog -Message '共享根未配置（见 §5.2 N-8）' -Level Warn
    return   # 或返回 Ok=$false 信封
}
```

`Get-ETShareReachableState` / `Test-ETShareReachable` 同样为 `$null` / 不可达。

### ★ 3.6 所有 `-Category` / `-Kind` 参数**必须**传字面量，不可拼接变量

因为 3.2：枚举域外值直接抛异常。`-Category $someVar` 在 `$someVar` 为空时抛错而非友好降级。

### ★ 3.7 `Get-ETHealthState.Rules` 是 `PSCustomObject`，**不是** `Hashtable`

**实测**：`$state.Rules -is [IDictionary]` → `False`。

**后果**：`$state.Rules['HR-CPU']` **取不到值**（返回 `$null`，**不报错**，静默失败 —— 最危险的一类）。

**正确写法**：

```powershell
$state.Rules.PSObject.Properties | ForEach-Object { $_.Name; $_.Value }
```

**实测 7 个 RuleId 键**（`Get-ETHealthState.Rules` 的属性名）：

```
HR-CPU            HR-MEM             HR-DISK-BIZ        HR-DISK-SOFT
HR-SHARE          HR-EVT-ERROR       HR-SELF-OUTBOX
```

### ★ 3.8 `Import-ETMasterDataSnapshot` 会**静默跳过空文件**

**实测**：在 `Snapshot\MasterData` 放入 6 个**空** `.json` 后执行 `Import-ETMasterDataSnapshot -Force`：

```
Status = NotConfigured     （空文件被跳过，状态未激活）
```

**陷阱**：`Status=NotConfigured` **不等于**"导入失败"，也**不代表**"已无数据"。它表示"没有可解析的内容"。调用方不可据此判断共享数据是否存在。

**下游影响**：主数据未激活时，`Get-ETSoftwareCatalog` 返回 `$null`、`Get-ETSoftwareStateSummary` 返回 0 行。集成测试已把此情形降级为 `WARN` 而非 `FAIL`（见 `Test-ETIntegration.ps1` 输出）。

---

## 4. 逐模块签名表

### 图例

| 记号 | 含义 |
|---|---|
| ★ | `[Parameter(Mandatory)]`，必填 |
| `{a\|b}` | `ValidateSet` 枚举域 |
| `=x` | 默认值 |
| `@n` | 位置参数序号 |
| `(无类型)` | 参数未声明静态类型 |

---

### 4.1 `ET.Core.psm1` —— 24 个导出（**归属：共享 / 只增不改**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Get-ETConfig` | `[switch]Reload` | `Hashtable`，8 个键：`SchemaVersion, Identity, Share, Local, Transfer, Health, Update, Ui` |
| `Get-ETCoreInfo` | — | 信息对象 |
| `Get-ETDataRoot` | `[switch]Ensure` | `String` = `C:\ProgramData\ETWorkbench` |
| `Get-ETFileHash` | ★`[string]LiteralPath` | `String`（SHA256 十六进制） |
| `Get-ETHealthRules` | — | `Hashtable{ Global, Rules }`，`Rules.Count=9` |
| `Get-ETObjectPropertyNames` | `InputObject`(无类型) | `String[]` |
| `Get-ETPath` | ★`[string]Category` `{ProgramDir\|LocalDir\|File\|UploadSub}`，★`[string]Name`，`[switch]Ensure` | `String`（**语义见 §3.4**） |
| `Get-ETPathsConfig` | `[switch]Reload` | `Hashtable`（`paths.json` 内容） |
| `Get-ETProgramRoot` | — | `String` = `<repo>\ETWorkbench` |
| `Get-ETSharePath` | ★`[string]Category` `{MasterData\|Release\|ConfigRules\|Upload\|Archive}`，`[string[]]ChildSegments=@()` | `String` 或 **`$null`** |
| `Get-ETShareReachableState` | — | `$null`（未配置时） |
| `Get-ETShareRoot` | — | `String` 或 **`$null`** |
| `Initialize-ETDataRoot` | `[switch]Force` | — |
| `New-ETEventId` | ★`[string]Prefix` `{EVT\|ALM\|DEP\|AUD}`，★`[string]EquipmentId`，`[string]Directory=''` | `String`，实测格式 `EVT-EQ-1-20260928-000001` |
| `New-ETRequestId` | — | `String`（32 位十六进制） |
| `Publish-ETFileAtomic` | ★`[string]SourcePath`，★`[string]TargetPath`，`[long]ExpectedSize=-1`，`[string]ExpectedSha256=''` | — （C-4 原子发布） |
| `Test-ETFileHash` | ★`[string]LiteralPath`，★`[string]ExpectedSha256` | `Boolean` |
| `Test-ETObjectHasProperty` | `InputObject`(无类型)，★`[string]Name` | `Boolean` |
| `Test-ETShareReachable` | — | 布尔/状态对象 |
| `Test-ETWorkbench` | — | 环境自检结果 |
| `Write-ETAuditEvent` | ★`[string]EquipmentId`，★`[string]Operation`，★`[string]Result` `{Success\|Failure\|Denied\|Started}`，`[string]Target=''`，`[string]Detail=''` | — |
| `Write-ETJsonAtomic` | ★`[string]LiteralPath`，★`InputObject`(无类型)，`[int]Depth=10`，`[switch]PassThru` | — （C-4） |
| `Write-ETLog` | ★`[string]Message` `@0`，`[string]Level` `{Debug\|Info\|Warn\|Error}` `='Info'`，`[hashtable]Data`，`[switch]Console` | — |
| `Write-ETTextAtomic` | ★`[string]LiteralPath`，★`[string]Content` | — （C-4） |

---

### 4.2 `ET.Identity.psm1` —— 7 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Get-ETBiosSerialNumber` | — | `{ Value, Source, Success, Error }` |
| `Get-ETBusinessIp` | — | `{ Addresses, Success, Error }` |
| `Get-ETInstalledApplications` | — | **`$null`**（当前） |
| `Invoke-ETIdentityChain` | `[switch]NoPersist` | `{ Status, Steps, Result, SnapshotPath }` |
| `Resolve-ETApplication` | ★`[string]EquipmentId` | **`$null`**（当前） |
| `Resolve-ETEquipment` | ★`[string]SerialNumber`，`[string[]]IpAddresses` | `{ Status, EquipmentId, DeviceId, Candidates, Evidence }` —— ⚠️ **见 §10.1** |
| `Resolve-ETProject` | ★`[string]DeviceId` | `{ Status, ProjectId, Candidates, Evidence }` —— ⚠️ **见 §10.1** |

---

### 4.3 `ET.MasterData.psm1` —— 7 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Export-ETMasterDataToShare` | ★`[string]LocalDir`，`[switch]WhatIf` | — （C-4 原子发布） |
| `Get-ETMasterDataSnapshot` | ★`[string]Kind`（**无 ValidateSet**） | 数组 或 **`$null`**；`-Kind bogus` → **返回**（不抛） |
| `Get-ETMasterDataSpec` | — | 每 Kind 一条**纯字符串**说明，如 `equipment -> "equipment.json  主键：EquipmentId"` |
| `Get-ETMasterDataStatus` | `[int]StaleHours=72` | `{ Loaded, TakenAt, AgeHours, IsStale, Items }` |
| `Import-ETMasterDataSnapshot` | `[switch]Force` | `{ Status, TakenAt, Items, Errors, SnapshotDir }` —— ⚠️ **见 §3.8** |
| `New-ETMasterDataDraft` | ★`[string]Kind`（**无 ValidateSet**） | 见 §4.3.1；`-Kind bogus` → **抛** `未知的主数据类型：bogus` |
| `Test-ETMasterDataDraft` | ★`[string]FileName`，★`[string]LiteralPath` | 校验结果 |

#### 4.3.1 `New-ETMasterDataDraft` 各 Kind 生成的字段（实测）

| Kind | 生成字段 |
|---|---|
| `equipment` | `EquipmentId, SiteName, DeviceId, ProjectId, Note` |
| `devices` | `DeviceId, EquipmentId, DeviceType, Note` |
| `projects` | `ProjectId, ProjectName, Note` |
| `applications` | `ApplicationId, ApplicationName, SoftwareId, Note` |
| `approved-versions` | `ApplicationId, Version, ReleaseId, ReleasePath, ApprovedTime, Note` |
| `mappings` | `BySerialNumber, ByIpAddress` |

⚠️ `Get-ETMasterDataSnapshot` 与 `New-ETMasterDataDraft` 的 `-Kind` **都没有 `ValidateSet`**，但**行为不一致**：前者对未知 Kind **静默返回**，后者**抛异常**。这是实测到的接口不对称，调用方**必须**自己先校验 Kind 字面量。

#### 4.3.2 主数据快照的实测行结构

```
Get-ETMasterDataSnapshot -Kind equipment     -> { EquipmentId, EquipmentName, SiteName, Note }
Get-ETMasterDataSnapshot -Kind applications  -> { ApplicationId, ApplicationName, SoftwareId, Note }
```

---

### 4.4 `ET.Software.psm1` —— 6 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Get-ETSoftwareCatalog` | `[string]EquipmentId` | 数组 或 **`$null`**；行结构见 §4.4.1 |
| `Get-ETSoftwareStateSummary` | `[string]EquipmentId` | `{ Rows, Counts, EvaluatedAt }`；`Counts` 7 个键见 §8 |
| `Get-ETStateModel` | — | `Array(7)`：`{ Order, State, Label, Desc }` —— **见 §8** |
| `Resolve-ETSoftwareState` | ★`[string]ApplicationId`，`[string]ApprovedVersion`，`[string]TargetDirectory`，`[string]ProcessName`，`[switch]ConfigVerified` | `{ State, StateOrder, StateLabel, UnknownAt, Evidence }` |
| `Test-ETExecutablePresence` | ★`[string]Directory`，`[string[]]Patterns=@('*.exe')` | `{ Found, ExecutablePath, Candidates }`；路径不存在 → **返回** `Found=False` |
| `Test-ETProcessRunning` | ★`[string]ProcessName` | `{ Running, Ids, Detail }`；不存在的进程 → `Running=False` |

#### 4.4.1 `Get-ETSoftwareCatalog` 行结构（实测完整样本）

```json
{
  "ApplicationId": "APP-0001",
  "ApplicationName": "SampleApp",
  "SoftwareId": "SW-0001",
  "ApprovedVersion": "1.0.0",
  "LocalVersion": null,
  "State": "PackageAvailable",
  "StateOrder": 1,
  "StateLabel": "共享有包",
  "StateIsStale": false,
  "Evidence": {
    "ApprovedVersion": "1.0.0",
    "InstalledMatch": null,
    "CheckedAt": "..."
  },
  "NextAction": "待判态（D1 实现）"
}
```

> **`NextAction` 是 D1 未实现的显式标记**。凡见到 `待判态（D1 实现）`，即表示该行尚未接入真实判态逻辑。

---

### 4.5 `ET.Transfer.psm1` —— 7 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Add-ETDownloadHistory` | ★`Record`(无类型) —— 传 `$null` → **抛** | — |
| `Get-ETDownloadHistory` | `[int]Last=50` | 数组 或 **`$null`** |
| `Get-ETDownloadPlan` | ★`[string]ApplicationId`，★`[string]Version` | `{ Ok, ApplicationId, Version, Files, FileCount, TotalBytes, TargetDir, SourceDir, Space, Errors }` |
| `Get-ETReleaseManifest` | ★`[string]ApplicationId`，★`[string]Version` | `{ Ok, Manifest, Errors, ManifestPath }` |
| `Invoke-ETDownload` | ★`[string]ApplicationId`，★`[string]Version`，`[scriptblock]OnProgress` | 下载结果 |
| `Test-ETDownloadedPackage` | ★`[string]ApplicationId`，★`[string]Version` | `{ Ok, VerifiedCount, TotalCount, Errors }` |
| `Test-ETFreeSpace` | ★`[string]Path`，`[long]RequiredBytes=0`，`[long]MinFreeBytes=-1` | `{ Ok, FreeBytes, RequiredBytes, FreeGB, RequiredGB }` —— ⚠️ **见 §10.2** |

#### 4.5.1 `Invoke-ETDownload -OnProgress` 契约

类型：`System.Management.Automation.ScriptBlock`。回调形如 `param([string]$Stage, [int]$Percent, [string]$Message)`。

实现内实际调用的是私有函数 `Report`（见 §9.1）。

#### 4.5.2 `Test-ETFreeSpace` 实测值

```
Test-ETFreeSpace -Path 'C:\Windows'
  -> Ok=True  FreeBytes=85822074880  RequiredBytes=5368709120  FreeGB=79.93

Test-ETFreeSpace -Path 'C:\Windows' -MinFreeBytes 999999999999999
  -> Ok=False  FreeGB=79.93  RequiredGB=931322.57
```

`MinFreeBytes=-1`（默认）时从 `Get-ETConfig` 的 `Transfer.MinFreeSpaceBytes` 取（当前 = `5368709120` = 5 GB）。

---

### 4.6 `ET.Health.psm1` —— 10 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Get-ETComparatorSymbol` | ★`[string]Comparator` | `String`，如 `Gt` |
| `Get-ETHealthMetricCatalog` | — | `Array(9)`：`{ Source, Metric, Implemented }` —— **见 §4.6.1** |
| `Get-ETHealthMetrics` | — | `Array(7)`：`{ RuleId, Name, Target, Value, Unit, Status, Severity, Detail, ObservedAt }` |
| `Get-ETHealthSnapshot` | — | `{ CheckedAt, EquipmentId, Samples, Alarms, Events, Unknowns }` |
| `Get-ETHealthState` | — | `{ SchemaVersion, UpdatedAt, Rules }` —— ⚠️ **`Rules` 是 PSCustomObject，见 §3.7** |
| `Get-ETMetric` | ★`Rule`(无类型) | `{ Status, Value, Unit, Detail, ObservedAt }` |
| `Invoke-ETHealthCheck` | `[string]EquipmentId`，`[switch]NoPersist` | 检测结果 |
| `Save-ETHealthSnapshot` | ★`Result`(无类型) | — ；传 `$null` → **抛**（绑定）；传 `@{}` → **抛**（结构校验） |
| `Save-ETHealthState` | ★`State`(无类型) | — ；传 `$null` → **抛**；传 `@{}` → **静默返回**（不抛） |
| `Test-ETComparator` | `Value`(无类型)，`[string]Comparator`，`Threshold`(无类型) | `Boolean` |

> **⚠️ `Save-ETHealthSnapshot` 与 `Save-ETHealthState` 行为不对称**：前者对错误结构**抛异常**（`需要健康检测结果对象（含 Samples/Alarms/Events），实际收到：System.Collections.Hashtable`），后者对 `@{}` **静默返回**。写入状态前应自行校验。

#### 4.6.1 `Get-ETHealthMetricCatalog` 全部 9 条（实测，`Implemented` 全为 `True`）

| Source | Metric |
|---|---|
| `Cim` | `CpuLoadPercent` |
| `Cim` | `AvailableMemoryPercent` |
| `PsDrive` | `FreeSpacePercent` |
| `PsDrive` | `FreeSpaceBytes` |
| `ShareReachability` | `IsReachable` |
| `Service` | `Status` |
| `Process` | `IsRunning` |
| `EventLog` | `ErrorCount` |
| `Self` | `OutboxPendingCount` |

#### 4.6.2 健康规则定义结构（`Get-ETHealthRules.Rules[0]` 实测完整样本）

```json
{
  "RuleId": "HR-CPU",
  "Name": "CPU 持续高占用",
  "Source": "Cim",
  "Metric": "CpuLoadPercent",
  "Comparator": "GreaterThanOrEqual",
  "Threshold": 85,
  "DurationMinutes": 10,
  "DebounceSamples": 3,
  "RecoveryThreshold": 70,
  "RecoveryDurationMinutes": 10,
  "Severity": "Warning",
  "Enabled": true,
  "Note": "..."
}
```

#### 4.6.3 健康规则实测状态分布（共享/软件根未配置时）

| RuleId | Target | 实测 Value | 实测 Status | 说明 |
|---|---|---:|---|---|
| `HR-CPU` | — | 45 | `Ok` | |
| `HR-MEM` | — | 32.6 | `Ok` | |
| `HR-DISK-BIZ` | `{BusinessDrive}` | — | **`Unknown`** | 未配置 Target |
| `HR-DISK-SOFT` | `{SoftwareRoot}` | — | **`Unknown`** | 未配置软件根 |
| `HR-SHARE` | — | — | **`Unknown`** | 未配置共享根 |
| `HR-EVT-ERROR` | `System,Application` | 0 | `Ok` | |
| `HR-SELF-OUTBOX` | — | 1 | `Ok` | |

> `Unknown` **不是** `Ok`（`Config.Health.UnreachableIsUnknown = true`）。报表与告警必须区分二者，否则"未配置"会被当成"健康"。

---

### 4.7 `ET.Outbox.psm1` —— 12 个导出（**归属：B / QYX**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Add-ETOutboxBatch` | ★`[object[]]Items` | — ；传 `@()` → **返回**（无操作） |
| `Add-ETOutboxItem` | ★`Item`(无类型) | — ；传 `$null` → **抛**（绑定） |
| `Clear-ETOutboxDone` | `[int]KeepDays=7` | — ；实测返回 `removed=0` |
| `Get-ETOutboxEquipmentId` | — | `String`，实测 `DESKTOP-MKP1N8S`（= `$env:COMPUTERNAME`） |
| `Get-ETOutboxEventTypeDirName` | ★`[string]EventType` `{Health\|Alarm\|Deployment\|Audit}` | `String`；枚举域外 → **抛** |
| `Get-ETOutboxPendingCount` | — | `Int32`，实测 `1` |
| `Get-ETOutboxRoot` | — | `String` = `C:\ProgramData\ETWorkbench\Outbox` |
| `Get-ETOutboxSummary` | — | `{ Pending, ByType, OldestPendingTime, OldestPendingHours }` |
| `Get-ETOutboxTargetPath` | ★`[string]EquipmentId`，★`[string]EventType`，★`[string]EventId`，`[datetime]Time=(Get-Date)` | `String` 或 **`$null`**（共享未配置时） |
| `New-ETOutboxItem` | ★`[string]EventType` `{Health\|Alarm\|Deployment\|Audit}`，★`[string]EquipmentId`，★`Payload`(无类型)，`[string]ApplicationId`，`[string]Version`，`[string]ReleaseId` | 见 §4.7.1；枚举域外 → **抛** |
| `Publish-ETOutbox` | `[int]MaxItems=200` | 发布结果 |
| `Publish-ETOutboxItem` | ★`[string]LocalPath` | — ；路径不存在 → **返回**（不抛） |

#### 4.7.1 `New-ETOutboxItem` 返回结构（实测完整字段）

```
EventId  EventType  EquipmentId  ApplicationId  Version  ReleaseId
CreatedTime  RetryCount  NextRetry  Checksum  LocalPath  Status  LastError
SchemaVersion  Payload
```

实测样本：`Status=Pending`，`Checksum=D25ED28B...B22BEA8`，**`LocalPath=<空>`**（尚未落盘，符合 C-5「一事件一文件」的生成阶段）。

---

### 4.8 `ET.Update.psm1` —— 10 个导出（**归属：A / WHB**）

| 函数 | 参数 | 返回 |
|---|---|---|
| `Get-ETAvailableVersion` | — | `{ Available, Version, ReleasePath, Notes, Error }`；实测共享未配置 → `Available=False  Version=  Error=未配置共享根` |
| `Get-ETCurrentPointerPath` | — | `String` = `<repo>\ETWorkbench\Current.json` |
| `Get-ETCurrentVersion` | — | `{ Ok, Version, PreviousVersion, SwitchedAt, Source, Error }` |
| `Get-ETLocalVersions` | — | 数组 或 **`$null`** |
| `Get-ETUpdateHistory` | — | 数组 或 **`$null`** |
| `Get-ETWorkbenchRoot` | — | `String` = `<repo>\ETWorkbench` |
| `Invoke-ETSelfUpdate` | `[switch]Force` | 更新结果 |
| `Invoke-ETUpdateSmokeTest` | ★`[string]Version` | 冒烟测试结果 |
| `Switch-ETCurrentVersion` | ★`[string]Version`，`[int]KeepVersions=-1` | 切换结果 |
| `Test-ETUpdateAvailable` | — | `{ UpdateAvailable, CurrentVersion, AvailableVersion, Reason }` |

> **注意**：`Switch-ETCurrentVersion -Version '9.9.9'`（不存在的版本）**静默返回**，不抛异常。调用方**必须**检查返回对象中的 `Ok` / `Error` 字段，不可依赖异常。

---

## 5. 环境前提契约

### 5.1 当前实测环境

| 项 | 值 |
|---|---|
| PowerShell | `5.1.19041.6456` |
| `ExecutionPolicy` | `Bypass` |
| `Set-StrictMode` | `Version 2.0`（**所有模块**） |
| `$env:COMPUTERNAME` | `DESKTOP-MKP1N8S` |
| `DataRoot` | `C:\ProgramData\ETWorkbench` |
| `ProgramRoot` | `<repo>\ETWorkbench` |
| 共享根 | **未配置**（`Share.ShareRoot` 为空） |
| 软件根 | **未配置**（`Local.SoftwareRoot` 为空） |

### 5.2 `Config/workstation.json` 实测内容（**归属：A / WHB 独占**）

```
Identity  { EquipmentIdOverride:"", SiteName:"", AllowedIpPrefixes:[], BusinessAdapterPatterns:[] }
Share     { ShareRoot:"", MasterDataRelative:"MasterData", ReleaseRelative:"Release",
            ConfigRulesRelative:"ConfigRules", UploadRelative:"Upload",
            ConnectTimeoutMs:10000, ReadTimeoutMs:30000 }
Local     { DataRoot:"C:\ProgramData\ETWorkbench", SoftwareRoot:"",
            MaxConcurrentDownloads:1, TempRetentionHours:24 }
Transfer  { VerifySha256:true, VerifyFileCount:true, PreservePartialOnFailure:true,
            MinFreeSpaceBytes:5368709120, UseUncertainProgressBar:false }
Health    { Enabled:true, CollectIntervalMinutes:15, OutboxPublishIntervalMinutes:10,
            UnreachableIsUnknown:true }
Update    { AutoCheckOnStartup:true, EnableGuiCheckButton:true, SmokeTestOnSwitch:true,
            KeepVersions:2 }
Ui        { EnableOpenFolderButton:true, EnableMasterDataImportCsv:true,
            LogLevel:"Info", LogRetentionDays:30 }
```

**两个空值未决**（`ShareRoot` / `SoftwareRoot`），阻塞项 N-8 / N-9 / P-8。

### 5.3 `Config/paths.json`（C-2 唯一路径来源，**归属：A / WHB 独占**）

```
DataRoot.Default           = C:\ProgramData\ETWorkbench

LocalDirs   Config, Snapshot, SnapshotMasterData=Snapshot\MasterData,
            SnapshotRelease=Snapshot\Release, Commands, Results, Outbox,
            OutboxHealth=Outbox\Health, OutboxAlarm=Outbox\Alarm,
            OutboxDeployment=Outbox\Deployment, OutboxAudit=Outbox\Audit,
            Cache, Backup, Logs, Temp

ProgramDirs Ui=UI, Modules=Modules, Tasks=Tasks, Config=Config
UploadSubDirs  Health, Alarm, Deployment, Audit

FileNames   Log             = et-{yyyyMMdd}.log
            EventHealth     = EVT-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
            EventAlarm      = ALM-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
            EventDeployment = DEP-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
            EventAudit      = AUD-{EquipmentId}-{yyyyMMdd}-{seq}.ndjson
            Command         = CMD-{RequestId}.json
            Result          = RES-{RequestId}.json
            CurrentPointer  = Current.json

ReleaseLayout  ManifestName=manifest.json, FilesDirName=files,
               ReleaseNotesName=release-notes.json
```

> **`LocalDirs` 实测可解析的 11 个键**：`Config, Snapshot, SnapshotMasterData, SnapshotRelease, Commands, Results, Outbox, Cache, Backup, Logs, Temp`
> **`ProgramDirs` 4 个键**：`Ui, Modules, Tasks, Config`
>
> `OutboxHealth` / `OutboxAlarm` / `OutboxDeployment` / `OutboxAudit` 未逐一实测（属 `LocalDirs`，应为 `Outbox\Health` 等）。

---

## 6. 错误语义契约（汇总）

### 6.1 抛异常的场景（`try/catch` 才能接住）

| 触发条件 | 实例 | 实测消息 |
|---|---|---|
| `ValidateSet` 枚举域外 | `New-ETOutboxItem -EventType 'Nope'` | `参数"Nope"不属于 ValidateSet 属性指定的集合"Health,Alarm,Deployment,Audit"` |
| `ValidateSet` 枚举域外 | `Get-ETOutboxEventTypeDirName -EventType 'Nope'` | 同上 |
| Mandatory 传 `$null` | `Add-ETOutboxItem -Item $null` | `无法将参数绑定到参数"Item"，因为该参数是空值` |
| Mandatory 传 `$null` | `Add-ETDownloadHistory -Record $null` | 同上（`Record`） |
| Mandatory 传 `$null` | `Save-ETHealthSnapshot -Result $null` | 同上（`Result`） |
| Mandatory 传 `$null` | `Save-ETHealthState -State $null` | 同上（`State`） |
| 无 ValidateSet 但值非法 | `New-ETMasterDataDraft -Kind 'bogus'` | `未知的主数据类型：bogus` |
| 结构不符 | `Save-ETHealthSnapshot -Result @{}` | `需要健康检测结果对象（含 Samples/Alarms/Events），实际收到：System.Collections.Hashtable` |

### 6.2 返回 `Ok=$false` + `Errors[]` 的场景

| 函数 | 实测消息 |
|---|---|
| `Get-ETDownloadPlan` | `Ok=False  Errors=["找不到发布清单："]` |
| `Get-ETReleaseManifest` | `Ok=False  Errors=["找不到发布清单："]` |
| `Test-ETDownloadedPackage` | `Ok=False  Errors=["找不到发布清单："]` |

### 6.3 **静默失败**的场景（最危险，必须自行校验）

| 函数 | 输入 | 实测行为 | 风险 |
|---|---|---|---|
| `Get-ETMasterDataSnapshot` | `-Kind 'bogus'` | **返回**（不抛、不报错） | 调用方误以为"无数据" |
| `Switch-ETCurrentVersion` | `-Version '9.9.9'`（不存在） | **返回**（不抛） | 必须查返回对象 |
| `Invoke-ETUpdateSmokeTest` | `-Version '9.9.9'` | **返回**（不抛） | 同上 |
| `Publish-ETOutboxItem` | 不存在的路径 | **返回**（不抛） | 发布失败被吞 |
| `Save-ETHealthState` | `@{}` | **返回**（不抛） | 状态未落盘 |
| `$state.Rules['HR-CPU']` | 属性名访问 | **返回 `$null`** | 见 §3.7 |
| `Import-ETMasterDataSnapshot` | 空 `.json` | `Status=NotConfigured` | 见 §3.8 |

### 6.4 命名陷阱：以 `Test-` 开头的函数**不保证**返回布尔

| 函数 | 实际返回 |
|---|---|
| `Test-ETFileHash` | `Boolean` ✅ |
| `Test-ETObjectHasProperty` | `Boolean` ✅ |
| `Test-ETComparator` | `Boolean` ✅ |
| `Test-ETProcessRunning` | **对象** `{ Running, Ids, Detail }` |
| `Test-ETExecutablePresence` | **对象** `{ Found, ExecutablePath, Candidates }` |
| `Test-ETFreeSpace` | **对象** `{ Ok, FreeBytes, ... }` |
| `Test-ETDownloadedPackage` | **对象** `{ Ok, VerifiedCount, ... }` |
| `Test-ETMasterDataDraft` | **对象** |
| `Test-ETUpdateAvailable` | **对象** `{ UpdateAvailable, ... }` |
| `Test-ETWorkbench` | **对象** |
| `Test-ETShareReachable` | **对象** |

**必须写 `if ((Test-ETProcessRunning -ProcessName 'x').Running)`，不能写 `if (Test-ETProcessRunning -ProcessName 'x')`** —— 后者对任何非空对象恒为 `$true`。

---

## 7. 全部 `ValidateSet` 枚举域（**必须传字面量**）

| 函数 | 参数 | 允许值 |
|---|---|---|
| `New-ETEventId` | `-Prefix` | `EVT`, `ALM`, `DEP`, `AUD` |
| `Write-ETAuditEvent` | `-Result` | `Success`, `Failure`, `Denied`, `Started` |
| `Write-ETLog` | `-Level` | `Debug`, `Info`, `Warn`, `Error` |
| `Get-ETPath` | `-Category` | `ProgramDir`, `LocalDir`, `File`, `UploadSub` |
| `Get-ETSharePath` | `-Category` | `MasterData`, `Release`, `ConfigRules`, `Upload`, `Archive` |
| `New-ETOutboxItem` | `-EventType` | `Health`, `Alarm`, `Deployment`, `Audit` |
| `Get-ETOutboxEventTypeDirName` | `-EventType` | `Health`, `Alarm`, `Deployment`, `Audit` |

> **无 ValidateSet 的 `-Kind` / `-Category` 参数属于契约漏洞**：`Get-ETMasterDataSnapshot` / `New-ETMasterDataDraft` 的 `-Kind` 无约束，且行为不一致（§4.3）。调用方自建白名单：
>
> `equipment`, `devices`, `projects`, `applications`, `approved-versions`, `mappings`

---

## 8. 七态模型（C-6）

**实测**（`Get-ETStateModel` 返回 `Array(7)`）：

| Order | State | Label | Desc |
|---:|---|---|---|
| 1 | `PackageAvailable` | 共享有包 | 共享上存在该应用的已批准版本 |
| 2 | `Downloaded` | 已下载 | 本机已完成下载与校验（**不代表已安装**） |
| 3 | `Deployed` | 已部署 | 已复制到目标目录 |
| 4 | `ExecutableFound` | 有可执行 | 目标目录中找到可执行文件 |
| 5 | `Running` | 运行中 | 进程正在运行 |
| 6 | `Configured` | 已配置 | 配置符合期望规则 |
| 7 | `Effective` | 已生效 | 已配置 + 运行中 + 无未决告警 |

**Order 0 = 共享无包**（`State=null`，`StateLabel="共享无包"`，`StateOrder=0`）。**Order 0 不在 `Get-ETStateModel` 的 7 条内** —— 它是"未达第 1 态"的兜底显示值。

### 8.1 C-6 强制约束

> **`Downloaded`（Order 2）在任何 UI / 报表 / 日志中，都不允许显示为"已安装"或"已生效"。**

实测 `Desc` 已明示：`本机已完成下载与校验（不代表已安装）`。

只有 `Effective`（Order 7）才可表述为"生效"。`Running`（Order 5）**不等于** `Configured`，`Configured` **不等于** `Effective`。

### 8.2 `Get-ETSoftwareStateSummary` 的 `Counts` 7 个键

```
PackageAvailable   Downloaded   Deployed   ExecutableFound
Running            Configured   Effective
```

当前（主数据未激活）实测**全部为 0**。

### 8.3 `Resolve-ETSoftwareState` 实测样本

```json
{
  "State": null,
  "StateOrder": 0,
  "StateLabel": "共享无包",
  "UnknownAt": "PackageAvailable",
  "Evidence": { "PackagePath": null, "PackageAvailable": false }
}
```

> `UnknownAt` 字段用于标识"卡在哪一态无法判定"。**非空即表示该行不是确定状态**，UI 不得展示为定态。

---

## 9. 私有函数（**契约外，禁止跨模块调用**）

**6 个私有函数**，不由任何模块导出。跨模块调用会失败（`CommandNotFoundException`）。

### 9.1 完整清单

| 函数 | 模块 | 行号 | 说明 |
|---|---|---:|---|
| `ConvertTo-ETFlatHashtable` | `ET.Core` | 84 | 内部扁平化 |
| `Get-ETConfigFilePath` | `ET.Core` | 121 | 内部路径解析 |
| `Read-ETJsonFile` | `ET.Core` | 127 | 内部 JSON 读取 |
| `Add-Check` | `ET.Core` | 745 | 测试脚手架辅助 |
| `Report` | `ET.Transfer` | 176 | **被 `Invoke-ETDownload -OnProgress` 内部调用** |
| `Get-ETRuleField` | `ET.Health` | 29 | 规则字段取值 |

### 9.2 数量核对

```
定义总数 = 89
导出总数 = 83
私有总数 = 89 - 83 = 6  ✅ 与上表一致
```

**逐模块核对**：

| 模块 | 定义 | 导出 | 私有 |
|---|---:|---:|---:|
| `ET.Core` | 28 | 24 | 4 |
| `ET.Health` | 11 | 10 | 1 |
| `ET.Identity` | 7 | 7 | 0 |
| `ET.MasterData` | 7 | 7 | 0 |
| `ET.Outbox` | 12 | 12 | 0 |
| `ET.Software` | 6 | 6 | 0 |
| `ET.Transfer` | 8 | 7 | 1 |
| `ET.Update` | 10 | 10 | 0 |
| **合计** | **89** | **83** | **6** |

### 9.3 方法学警示（**留给后继维护者**）

**不要用 AST 遍历 `Export-ModuleMember` 来统计导出数。**

实测该做法报出 `91 导出 / 4 私有`，与真实值不符 —— 原因是 AST 遍历会把 `Export-ModuleMember` 命令**自身的参数**也当作"被导出的函数名"收集。

**唯一可信方法**：

```powershell
Import-Module .\ETWorkbench\Modules\ET.Core.psm1 -Force
(Get-Module ET.Core).ExportedCommands.Keys
```

---

## 10. 已知偏差与未实现项（**必须知情**）

本节记录**当前实现与设计意图之间的真实差距**。记录目的是防止"按设计意图编码、被现实打脸"。

### 10.1 E-02 身份解析链**尚未实现**（重要）

**实测**：

```
Resolve-ETEquipment -SerialNumber 'SN-0001'
  -> Status = NotImplemented
     EquipmentId = null   DeviceId = null   Candidates = []
     Evidence = { SerialNumber, IpAddresses }

Resolve-ETProject -DeviceId 'DEV-0001'
  -> Status = NotImplemented
     ProjectId = null   Candidates = []
     Evidence = { DeviceId }

Resolve-ETApplication -EquipmentId 'EQ-0001'
  -> [NULL]
```

**契约含义**：

- `Resolve-ETEquipment` / `Resolve-ETProject` **签名与返回结构已冻结**，但 `Status` 恒为 `NotImplemented`
- `Resolve-ETApplication` 返回 **`$null`**（不是 `NotImplemented` 对象）—— **两者行为不一致**
- **任何依赖身份解析链的下游功能，当前均无法工作**。这是 D1 待实现项，不是 bug
- 调用方**必须**先判 `Status`，不得假定已解析成功

### 10.2 D-6：`Test-ETFreeSpace` 在目标不可达时**静默回退到系统盘**（**真实缺陷**）

**源码**（`ET.Transfer.psm1:75-110`）：

```powershell
$target = $Path
while ($target -and -not (Test-Path -LiteralPath $target)) {
    $parent = Split-Path -Parent $target
    if ($parent -eq $target) { break }
    $target = $parent
}
if (-not $target) { $target = $env:SystemDrive }   # ← 缺陷点
$drive = (Get-Item -LiteralPath $target).PSDrive
```

**实测**：

```
Test-Path 'Z:\'                     -> False
Test-ETFreeSpace -Path 'Z:\definitely-not-here'
  -> Ok=True   FreeBytes=85822074880（= C 盘可用空间）
```

**后果**：检查一个**完全不存在的驱动器**，却报告了**系统盘**的空间，且返回 `Ok=True`。

**风险等级：高**。C-8 规定"可用空间不足时必须暂停，且不得删除业务文件"。此缺陷使该保护**在目标盘不可达时静默失效** —— 下载会以"空间充足"为由继续，然后在写盘时失败。

**调用方缓解措施**（在缺陷修复前）：

```powershell
# 先自行确认目标父目录真实存在，再信任 Test-ETFreeSpace
$root = Split-Path -Qualifier $targetDir
if (-not (Test-Path -LiteralPath $root)) {
    return [pscustomobject]@{ Ok = $false; Errors = @("目标驱动器不可达：$root") }
}
$space = Test-ETFreeSpace -Path $targetDir -RequiredBytes $totalBytes
```

**修复方向**（留给 B / QYX）：当向上回溯到根仍不可达时，应返回 `Ok=$false` 并给出 `Errors`，**不可**回退到 `$env:SystemDrive`。

### 10.3 D-3：`paths.json` 声明 `.ndjson`，但 `ET.Outbox` 写 `.json`（**真实缺陷**）

| 位置 | 内容 |
|---|---|
| `Config/paths.json` → `FileNames.EventHealth/EventAlarm/EventDeployment/EventAudit` | `...-{seq}.ndjson` |
| `ET.Outbox.psm1:238` | `return (Join-Path $dir ('{0}.json' -f $EventId))` |

**后果**：出站事件的**实际扩展名与配置不符**。任何按 `paths.json` 模板去查找文件的代码（如上传器、清理器、验收脚本）**都会找不到文件**。

**相关行**：`ET.Outbox.psm1:132`（`$eventId = New-ETEventId -Prefix $prefix -EquipmentId $EquipmentId`）、`:225`（`[Parameter(Mandatory)][string]$EventId`）。

**契约态度**：**暂不冻结实际扩展名**。待双方站会决定是改代码还是改配置后，再写入本文档。

### 10.4 D-7：`Save-ETHealthState` 无输入校验，可写坏状态机并**永久锁死健康检测**（**真实缺陷，已修复**）

| 位置 | 内容 |
|---|---|
| `ET.Health.psm1` → `Save-ETHealthState` | 仅 `[Parameter(Mandatory)]`，**无结构校验**，直接把入参序列化覆盖 `health-state.json` |
| `ET.Health.psm1` → `Get-ETHealthState` | 只用 `try/catch` 包 `ConvertFrom-Json`，**不校验 `Rules` 是否存在** |
| `ET.Health.psm1` → `Invoke-ETHealthCheck` | 后续直接访问 `$state.Rules`，StrictMode 下缺该属性**抛异常** |

**触发链**（本缺陷是在编写本文档的探测过程中被真实触发的，非推演）：

1. `Save-ETHealthState -State @{}` —— 语法合法、`ConvertFrom-Json` 亦不报错，故**静默写入** `{}`；
2. 文件变成 11 字节的 `{}`；
3. 此后**每一轮** `Invoke-ETHealthCheck` 都在 `$state.Rules` 处失败：
   `在此对象上找不到属性"Rules"。请确认该属性存在。`
4. 因 `health-last.json` 与 `health-state.json` 是**两个**文件，健康快照看上去仍正常，
   缺陷只在状态机路径上暴露 —— 排查成本高。

**对既有代码约定的偏离**：孪生函数 `Save-ETHealthSnapshot` 早已有同类防线，
其注释原文即写着「**曾经因为这种误传写坏过 health-last.json**」。
`Save-ETHealthState` 漏了同一道防线 —— 同一文件内两处不对称。

**修复**（三处，均已落地）：

| # | 位置 | 措施 |
|---|---|---|
| 1 | `Save-ETHealthState` | 拒绝非对象 / 缺 `Rules` 的输入，**抛错而非写盘**，与 `Save-ETHealthSnapshot` 对称 |
| 2 | `Get-ETHealthState` | 解析成功但缺 `Rules` 时归一化为空状态并 `Write-ETLog -Level Warn`（**降级但留痕，不静默**），
避免历史坏文件把检测**永久锁死** |
| 3 | 运维动作 | 清理已被污染的 `health-state.json` |

**为什么选「写侧抛错 + 读侧降级」而不都抛错**：写侧是**主动犯错的**调用点，必须立刻失败；
读侧面对的是**已经存在的**历史文件，崩溃只会让终端彻底失去健康检测能力，
而 `UnknownIsNotFault`（方案 §6.5 / G-6）的既有语义正是「取不到数 ≠ 故障」，故降级更符合设计。

**接口影响**：`Save-ETHealthState` 的**抛错语义**自此纳入契约（属 §3.2 类别），
在本文档 §4.6 的签名表中标注为会抛错。

### 10.5 `Get-ETPath -Category File` 的模板语义（见 §3.4）

严格说这不是缺陷，但**极易误用**，故在此重复：`File` 类返回**模板字符串**，不是路径。

### 10.6 `D-13`：主窗口启动即失败「找不到属性」（**真实缺陷，已修复 2026-09-30**）

**现象**：双击启动主窗口，只弹出「工作台启动失败：在此对象上找不到属性"BtnMdLoad"。请确认该属性存在。」，**窗口一次都没有打开**。

**根因**：`ETWorkbench/Start-ETWorkbench.ps1` 第 379 行的物理行把**注释与代码挤在了一起**：

```powershell
    # ---- 页签 4 · 主数据 ----    BtnMdLoad       = Get-UiElement 'BtnMdLoad'
```

整行因此被当作注释，`$ui` 表中 **`BtnMdLoad` 从未登记**（实测 `declared 59` / `referenced 60`）。

**为什么是启动致命**：入口脚本第 31 行有 `Set-StrictMode -Version 2.0`。在该模式下**读取不存在的哈希键会抛异常**，而不是返回 `$null`。于是 §14 事件路径里那句 `if ($ui.BtnMdLoad) {` 直接抛错，被顶层 `trap` 接住 → `Show-ETError` 弹窗 → 主窗口从未创建。

**为什么难发现**：`-Console` 自检跑不到这一段 —— **会话 0 守卫在 XAML 加载之前就 `exit 0`**；XAML 本身完好，`FindName('BtnMdLoad')` 也能解析到。

**门禁盲区（本次最大收获）**：`tools/Test-ETIntegration.ps1` §12 原有检查只验证「`$ui.<名字>` 能在 XAML 里解析到」，**证明不了该键已在 `$ui` 表里登记**。把缺陷注入回去后，旧检查**照样**输出 `60 control reference(s) all resolve`（全绿）。现已在 §12 追加反向检查 `every $ui.<Name> reference is declared in the $ui table`（逐行剥注释后统计声明，与全脚本引用名求差集）。

**修复**：仅把注释与代码拆回两行，其余 59 个键未动。**未涉及任何导出函数签名**，故接口仍为 `v1.0.0`。

**通则（写进本文件供后人避坑）**：
1. `$ui.<名字>` 一旦被引用，**必须**在 `$ui = @{ … }` 里单独占一行写 `名字 = Get-UiElement '名字'`；**注释绝不能与声明挤在同一物理行**。
2. `Set-StrictMode 2.0` 下「找不到属性」这套文案，**第一嫌疑就是 `$ui` 缺键**，不要先去查 XAML。

### 10.7 `C-1` 编码合规现状（**与接口无关但影响提交**）

| 文件范围 | BOM | 状态 |
|---|---|---|
| `ETWorkbench/**`（`Config/*.json` ×3、`Modules/*.psm1` ×8、`Start-ETWorkbench.ps1`、`Tasks/*.ps1` ×4、`UI/*.xaml`） | ✅ 有 | 合规 |
| `tools/*.ps1` ×5 | ✅ 有 | 合规 |
| `SYS-Operational Technology/**/*.md` ×11 | ❌ 无 | **违反 C-1**（含中文） |

**注意**：`tools/Test-ETScripts.ps1` 的默认扫描范围是 `<repo>\ETWorkbench` + `tools\`，**不覆盖仓库根目录与 `docs/`**。因此上述 11 个不合规文件**不会被闸门拦截**。

---

## 11. 如何自行复现本文档的全部结论

本文档所有结论均可复现。**不要信任本文档，信任你自己的运行结果。**

### 11.1 取导出函数清单（权威）

```powershell
Get-ChildItem .\ETWorkbench\Modules\*.psm1 | ForEach-Object {
    Import-Module $_.FullName -Force
    $m = Get-Module ($_.BaseName)
    [pscustomobject]@{
        Module = $m.Name
        Exported = $m.ExportedCommands.Keys.Count
    }
}
# 期望：合计 83
```

### 11.2 取签名

用 AST 走 `FunctionDefinitionAst` → `Parameters`，读 `Parameter` 特性的 `NamedArguments`、`ValidateSet` 的 `PositionalArguments`、参数的 `StaticType` 与 `DefaultValue`。

**不要**用 `Export-ModuleMember` AST 统计（见 §9.3）。

### 11.3 取返回结构

**每个函数都实际调用一次**，用下面的方式打印结构：

```powershell
function Show-Shape {
    param([string]$Label, [scriptblock]$Body)
    try {
        $v = & $Body
        if ($null -eq $v) { Write-Host "$Label -> [NULL]"; return }
        $first = @($v)[0]
        if ($null -eq $first) { Write-Host "$Label -> [empty]"; return }
        $props = $first.PSObject.Properties
        if ($props.Count -eq 0) {
            Write-Host "$Label -> $($v.GetType().Name) = $v"
            return
        }
        Write-Host "$Label -> $(@($v).Count) rows: $($props.Name -join ', ')"
    }
    catch { Write-Host "$Label -> THROW: $($_.Exception.Message)" }
}
```

> ⚠️ 函数名**不要**叫 `Try` —— `Try` 是 PowerShell 保留字，会直接导致脚本解析失败。

### 11.4 运行三道闸门

```powershell
# 1) 编码 + 语法
.\tools\Test-ETScripts.ps1

# 2) 集成（当前基线：PASS 46 / FAIL 0 / WARN 1）
.\tools\Test-ETIntegration.ps1

# 3) 自检（退出码 0 = 通过）
.\ETWorkbench\Start-ETWorkbench.ps1 -SelfTest
```

推送闸门已安装（`tools/Install-ETHooks.ps1`），`git push` 会自动串起这三道。

---

## 附录 A：接口冻结基线快速核验清单

每次提交前，或接口变更后，跑一遍：

| # | 检查项 | 期望 |
|---|---|---|
| 1 | 导出函数总数 | **83** |
| 2 | 定义函数总数 | **89** |
| 3 | 私有函数数 | **6** |
| 4 | `Test-ETScripts.ps1` | `RESULT: ALL CHECKS PASSED` |
| 5 | `Test-ETIntegration.ps1` | `PASS 46 / FAIL 0 / WARN 1` |
| 6 | `Start-ETWorkbench.ps1 -SelfTest` | 退出码 `0` |
| 7 | 新增导出函数是否已写入本文档 | 是 |
| 8 | 是否改了别人模块的导出签名 | **否**（若是，须走 §1.3） |
| 9 | `Config/*.json` 是否由 A（WHB）独占修改 | 是 |
| 10 | 本次改动是否已记入 §1.4 变更日志 | 是（若有接口变更） |

---

## 附录 B：本文档的验证状态声明

| 章节 | 证据等级 | 说明 |
|---|---|---|
| §4 签名表 | **AST 提取 + 实测调用** | 89 个函数全部提取；83 个导出函数均已实际调用探测 |
| §6 错误语义 | **实测** | 27 个错误路径逐一执行 |
| §8 七态模型 | **实测** | `Get-ETStateModel` 直接输出 |
| §9 私有函数 | **模块元数据比对** | 定义数与导出数双向核对 |
| §10.1 E-02 | **实测** | 三个 Resolve 函数直接调用 |
| §10.2 D-6 | **实测 + 源码定位** | 缺陷行为与源码缺陷点均已确认 |
| §10.3 D-3 | **实测 + 源码定位** | 配置与代码双向比对 |
| §5.3 `paths.json` 部分键 | **部分未验证** | `OutboxHealth/Alarm/Deployment/Audit` 未逐一实测 |
| §4.3.1 `mappings` Kind | **未验证** | 结构已知，行为未测 |

> 凡标注"未验证"的条目，**不得**作为下游实现的依据。需要时应先补测并更新本文档。
