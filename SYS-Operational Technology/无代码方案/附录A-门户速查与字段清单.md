# 附录 A 门户速查与字段清单

> **本附录是"随手查"用的。**
> **写方案时用不到，配置/运维时天天用。**
>
> ⚠️ **建议把本附录单独导成 PDF 或打印出来，放在运维值班桌上。**

---

## 0. 怎么用本附录

| 我在做什么 | 看哪节 |
|---|---|
| 要配某个东西，忘了在哪个门户 | **§1 门户速查** |
| 忘了表名 / 列名 / 类型 | **§2 表与字段清单** |
| 忘了选项集的值（特别是状态） | **§3 选项集清单** |
| 忘了环境变量怎么填 | **§4 环境变量清单** |
| 忘了连接引用要授权几个 | **§5 连接引用清单** |
| 查本方案新增的列（原设计没有的） | **§6 新增列与新增环境变量** |
| 查"不确定、要实测"的事项 | **§7 待实测清单** |
| 查"没定下来"的事项 | **§8 待决策清单** |
| 要建运维台账 / 记变更 | **§9 模板** |

---

## 1. 门户速查

### 1.1 六个门户

| # | 门户 | 地址 | 用来做什么 |
|---|---|---|---|
| **1** | **Power Platform 管理门户** | `admin.powerplatform.microsoft.com` | 环境、安全角色、审计、托管环境、容量、保留期 |
| **2** | **Power Apps 制造者门户** | `make.powerapps.com` | 表、列、选项集、关系、视图、业务规则、解决方案、云端流、模型驱动应用、Canvas App |
| **3** | **Power Automate** | `make.powerautomate.com` | 云端流（也可从制造者门户进） |
| **4** | **Power BI 服务** | `app.powerbi.com` | 工作区、数据集、报表、App、刷新、RLS、使用指标 |
| **5** | **Azure 门户** | `portal.azure.com` | Databricks 工作区、SQL Warehouse、ADLS Gen2 存储账户、成本 |
| **6** | **Databricks 工作区** | `https://<workspace>.azuredatabricks.net` | Notebook、Job、Catalog、SQL Warehouse 连接信息 |

### 1.2 常用菜单路径（★ = 高频）

| 要做什么 | 路径 |
|---|---|
| **建表 / 加列** | `make.powerapps.com` → 选环境 → **表** → 选表 → 列 |
| **建全局选项集** ★ | `make.powerapps.com` → 选环境 → **表** → 上方 **选项集** 标签 → **+ 新建选项集** |
| **建关系** | 表 → 选表 → **关系** 标签 → **+ 新建关系** |
| **建视图** ★ | 表 → 选表 → **视图** 标签 → **+ 新建视图** |
| **建业务规则** | 表 → 选表 → **业务规则** 标签 |
| **开列级安全** | 表 → 选表 → 选列 → **高级选项 → 启用列安全性** |
| **建自动编号** ★ | 表 → 选表 → 列 → **+ 新列** → 类型选 **自动编号**（⚠️ **只在新版门户有**） |
| **建解决方案** | `make.powerapps.com` → **解决方案** → **+ 新建解决方案** |
| **导出解决方案** ★ | 解决方案 → **导出** → **发布所有更改** → **导出** 选 **托管/非托管** |
| **导入解决方案** ★ | 解决方案 → **导入** → 选 zip → 四步向导 |
| **改环境变量值** | 解决方案 → 打开解决方案 → **环境变量** → 改 **当前值** |
| **建云端流** | `make.powerautomate.com` → **创建** → 自动化云流 / 计划云流 |
| **看流程运行历史** ★ | `make.powerautomate.com` → **我的流** → 选流 → **28 天运行历史** |
| **看流程失败** ★ | 同上一行 → 运行历史 → 状态筛选 **失败** |
| **重授权连接** | `make.powerautomate.com` → **连接** → 看是否有"失效"标记 |
| **换流程拥有者** ★ | `make.powerautomate.com` → 我的流 → 选流 → **详情** → 拥有者 |
| **建安全角色** | `admin.powerplatform.microsoft.com` → 环境 → 选环境 → **设置 → 用户 + 权限 → 安全角色** |
| **复制安全角色** | 安全角色列表 → 行末 **⋯ → 复制角色** |
| **看审计日志** | `admin.powerplatform.microsoft.com` → 环境 → **审核** |
| **看容量** | `admin.powerplatform.microsoft.com` → **资源 → 容量** |
| **看 Databricks 连接信息** ★ | Databricks 工作区 → **SQL Warehouses** → 选 Warehouse → **连接详细信息** → **服务器主机名** + **HTTP 路径** |
| **建/改 Notebook** | Databricks 工作区 → **工作区** → 文件夹 → **创建 Notebook** |
| **建 Job** | Databricks 工作区 → **工作流 → 作业 → 创建作业** |
| **看 Job 运行** ★ | Databricks 工作区 → **工作流 → 作业** → 选作业 → **运行** 标签 |
| **看 ADLS 文件** | Azure 门户 → 存储账户 → **容器** → 浏览 |
| **建 PAD 桌面流** | Power Automate → **我的流** → **+ 新建流 → 桌面流** |
| **看 PAD 机器** ★ | Power Automate → **桌面流** → **计算机** |
| **建 Power BI 数据集** | Power BI 服务 → 工作区 → **新建 → 数据集** / 或 Desktop → 发布 |
| **看刷新历史** ★ | Power BI 工作区 → 数据集 → **⋯ → 刷新历史** |
| **改凭据** ★ | Power BI 工作区 → 数据集 → **⋯ → 设置 → 数据源凭据 → 编辑凭据** |
| **建/改 RLS** | Power BI Desktop → **建模 → 管理角色** |
| **更新 App** ★ | Power BI 工作区 → **更新应用** |
| **看使用指标** | Power BI 工作区 → 报表 → **⋯ → 查看使用指标** |
| **建 Forms** | `forms.office.com` → **新建表单** |
| **看 Forms 响应** | 打开表单 → **响应** 标签 |
| **取 Form Id** ★ | 打开表单编辑页 → 看地址栏 `/Pages/DesignPageV2.aspx?origin=NeoPortal&id=` **后面的 GUID** |
| **取 Teams 团队/频道 ID** ★ | Teams → 频道 → **⋯ → 获取频道链接** → 从链接解析；或 `make.powerautomate.com` 里触发一次取值 |

### 1.3 ⚠️ 三个"取 ID"的实战技巧

| ID | 怎么取 |
|---|---|
| **Teams 频道 ID** | **最简单的方法：在流程里配一次 Teams 动作，界面上选完团队/频道后，切到"表达式"看它生成的 ID**（**然后填进环境变量**） |
| **Form Id** | **打开表单的"编辑"页（不是填写页）**，地址栏里 `id=` 后面那串 GUID |
| **Dataverse 表/列的逻辑名** | `make.powerapps.com` → 表 → 选表 → 列列表里点开某一列 → 看 **Name** 字段（**不是 Display name**） |

> ⚠️ **⚠️ 一句话记住：显示名是中文，逻辑名是 `bjops_xxx`。流程和报表里一律用逻辑名。**

---

## 2. 表与字段清单

### 2.1 11 张表总览

| # | 逻辑名 | 显示名 | 主列（逻辑名） | 列数 | 来源 |
|---|---|---|---|---|---|
| **1** | `bjops_application` | 应用台账 | `bjops_appcode` 应用编码 | 11 | 数据字典 §3.1 |
| **2** | `bjops_equipment` | 设备台账 | `bjops_equipmentcode` 设备编码 | 12 | 数据字典 §3.2 |
| **3** | `bjops_issue` | 问题 | `bjops_issuenumber` 问题编号 | **49** | 数据字典 §3.3 |
| **4** | `bjops_issuehistory` | 变更历史 | — | 10 | 数据字典 §3.4 |
| **5** | `bjops_logpackage` | 日志包 | `bjops_packagecode` 日志包编号 | 16 | 数据字典 §3.5 |
| **6** | `bjops_slaconfig` | SLA 配置 | `bjops_name` 配置名称 | 9 | 数据字典 §3.6 |
| **7** | `bjops_version` | 版本台账 | `bjops_versionnumber` 版本号 | 15 | 设计稿 §8.3（本方案新增） |
| **8** | `bjops_release` | 发布台账 | `bjops_releasenumber` 发布编号 | 17 | 设计稿 §9.2（本方案新增） |
| **9** | `bjops_testplan` | 测试计划 | `bjops_planname` 计划名称 | 10 | 设计稿 §10（本方案新增） |
| **10** | `bjops_testcase` | 测试用例 | `bjops_casecode` 用例编号 | 13 | 设计稿 §10.2（本方案新增） |
| **11** | `bjops_testexecution` | 测试执行 | `bjops_executioncode` 执行编号 | 12 | 设计稿 §10.3（本方案新增） |

> ⚠️ **⚠️ 1–6 是数据字典已定义的；7–11 是 `02` 手册新增的设计。**
> **→ 评审通过后应回填到 `../docs/data-dictionary.md`**（`02` §5 已注明）。

### 2.2 三个必须记住的"陷阱列"

| 列 | 陷阱 |
|---|---|
| **`bjops_issue.bjops_logpackageid`** | ⚠️ **它是"单行文本"（存编号字符串），不是查找列！** 而 `bjops_logpackage` 表的**主键**才叫 `bjops_logpackageid`。**同名不同物，极容易搞错** |
| **`bjops_issue.bjops_statusupdatetime`** | ⚠️ **它只存"最后一次状态变更时间"，不能用来算"关闭时间"** → 关掉时间类 KPI 必须用 `bjops_issuehistory` |
| **`bjops_issue.bjops_automationupdate`** | ⚠️ **防循环标志位**。**不要用它做业务判断**；`05` §4.4 已改为用 `bjops_lastnotifiedstatus` 做判据 |

### 2.3 四个"文本降级列"（本方案建议保持文本）

| 列 | 所在表 | 本方案建议 |
|---|---|---|
| `bjops_detectedversion` | `bjops_issue` | ✅ **保持文本**（`02` §5.1 方案 A） |
| `bjops_fixversion` | `bjops_issue` | ✅ **保持文本** |
| `bjops_relatedrelease` | `bjops_issue` | ✅ **保持文本** |
| `bjops_currentprodversion` | `bjops_application` | ✅ **保持文本** |

> ⚠️ **理由**：**Dataverse 不能把已有的简单文本列改成查找列**，只能删列重建（**丢数据**）。
> ⚠️ **代价**：文本值与 `bjops_version` 表**可能脱节** →
> **`05` 手册需加一步校验：写入 `bjops_fixversion` 时，检查该版本号在 `bjops_version` 里存在。**
> **→ 记入 §7 待实测 / §8 待决策。**

### 2.4 ⚠️ `bjops_issue` 的 49 列怎么数

| 组 | 列数 | 组内内容 |
|---|---|---|
| **A 身份与范围** | 12 | 主键、编号、标题、应用、模块、环境、设备、生产线、发现版本、版本来源、客户端版本、数据管道版本 |
| **B 问题描述** | 10 | 类型、分类、严重度、事件时间、影响范围、复现步骤、实际结果、期望结果、可复现性、临时措施 |
| **C 证据与关联** | 6 | 证据文件夹、日志包编号、日志包链接、批次号、关联问题、关联发布 |
| **D 状态与处理** | 16 | 状态、负责人、状态变更时间、状态变更人、等待原因、下一步动作、目标日期、关闭代码、根本原因、解决方案、永久措施、修复版本 |
| **E 流程控制** | 11 | 自动化更新、表单响应 ID、关联 ID、最后通知时间、SLA 截止、解决截止、升级层级、报告人、报告人邮箱、来源 |
| **+ 系统列** | — | `createdon` / `modifiedon` / `ownerid` / `statecode` / `statuscode` 等（**不计入 49**） |

> ⚠️ **⚠️ 上面 A–E 相加是 12+10+6+16+11 = 55**，超过 49。
> **→ 说明数据字典 §3.3 的"49"是"未含系统列、且 D 组某些行合并计数"的口径。**
> **→ 实际建表时以"数据字典 §3.3 的逐行清单"为准，不要以"49"这个数字为准。**
> **→ 本附录如实记录这个不一致**（**记入 §7 待核对**）。

---

## 3. 选项集清单（20 个）

### 3.1 ⚠️ ⚠️ 状态选项集 `bjops_issuestatus`（14 个值，最要命的一个）

| 值 | 显示名 |
|---|---|
| 1 | New |
| 2 | Triaged |
| 3 | Assigned |
| 4 | Analyzing |
| 5 | WaitingForInfo |
| 6 | Fixing |
| 7 | ReadyForTest |
| 8 | Testing |
| 9 | ReadyForRelease |
| 10 | Released |
| 11 | Monitoring |
| **12** | **Closed** |
| **13** | **Reopened** |
| **14** | **Rejected** |

> ⚠️ **⚠️ 12/13/14 这三个值最容易记错**（**很多人以为是"12 = Reopened"**）。
> **→ 记住：Closed = 12（关闭在 Reopened 之前）。**
>
> ⚠️ **这 14 个值被四处引用**：**① 选项集定义 ② 状态机设计 ③ 视图筛选条件 ④ 流程条件分支**。
> **任一处拼写不一致 → 静默失效。**
> **→ 排查时，"四处都核对一遍"是唯一的办法。**

### 3.2 其余 11 个基础选项集（来自数据字典 §2）

| # | 逻辑名 | 显示名 | 值数 | 关键值 |
|---|---|---|---|---|
| 1 | `bjops_environment` | 环境 | 4 | **1=DEV, 2=TEST, 3=UAT, 4=PROD** |
| 2 | `bjops_issuetype` | 问题类型 | 4 | 1=Incident, 2=Bug, 3=Request, 4=Enhancement |
| 3 | `bjops_category` | 分类 | 7 | 1=功能…7=其他 |
| 4 | `bjops_severity` | 严重度 | 4 | **1=Critical, 2=High, 3=Medium, 4=Low**（⚠️ **1 是最严重**） |
| 5 | `bjops_reproducibility` | 可复现性 | 4 | 1=Always…4=Unknown |
| 6 | `bjops_closecode` | 关闭代码 | 7 | 1=Fixed…7=Cancelled |
| 7 | `bjops_rootcause` | 根本原因 | 10 | 1=需求理解偏差…10=其他/未确定 |
| 8 | `bjops_waitingreason` | 等待原因 | 6 | 1=等待请求人补充信息…6=等待其他问题解决 |
| 9 | `bjops_apptype` | 应用类型 | 6 | 1=上位机软件…6=其他 |
| 10 | `bjops_versionsource` | 版本来源 | 2 | 1=自动读取, 2=手工选择 |
| 11 | `bjops_issuesource` | 问题来源 | 6 | **1=Forms, 2=Power Apps**, 3/4 预留, 5=邮件, 6=其他 |

> ⚠️ **`bjops_severity` 的排序陷阱**：**Critical = 1**。
> **→ Power BI 里按"严重度"排序时，升序 = 最严重在前**（**这符合直觉，但要确认 `dim_severity` 带了 `sort_order`**，`07` §6.6）。

### 3.3 本方案新增的 8 个选项集

| # | 逻辑名 | 显示名 | 值数 | 用在哪 |
|---|---|---|---|---|
| **13** | `bjops_changesource` | 变更来源 | 2 | `bjops_issuehistory.bjops_changesource`（**防死循环判据**） |
| **14** | `bjops_versiontype` | 版本类型 | 4 | `bjops_version` |
| **15** | `bjops_versionstatus` | 版本状态 | 8 | `bjops_version` |
| **16** | `bjops_testtaskstatus` | 测试任务状态 | 8 | `bjops_testplan` / `bjops_testcase` / `bjops_testexecution` |
| **17** | `bjops_testresult` | 测试结果 | 4 | `bjops_testexecution` / `bjops_version` |
| **18** | `bjops_approvalstatus` | 审批状态 | 3 | `bjops_version` / `bjops_release` |
| **19** | `bjops_releaseresult` | 发布结果 | 4 | `bjops_release` |
| **20** | `bjops_testtype` | 测试类型 | 12 | `bjops_testcase` |

**关键值**：

| 选项集 | 值 |
|---|---|
| `bjops_changesource` | **1=人工, 2=流程** |
| `bjops_versiontype` | 1=Test, 2=RC, 3=Production, 4=Hotfix |
| `bjops_versionstatus` | 1=Draft, 2=DevelopmentBuild, 3=TestBuild, 4=ReleaseCandidate, 5=Approved, 6=Production, 7=Retired, 8=RolledBack |
| `bjops_testtaskstatus` | 1=Planned, 2=Ready, 3=InTest, 4=Failed, 5=Blocked, 6=Retest, 7=Passed, 8=Approved |
| `bjops_testresult` | 1=NotTested, **2=Pass, 3=Fail, 4=Blocked** |
| `bjops_approvalstatus` | 1=Pending, 2=Approved, 3=Rejected |
| `bjops_releaseresult` | 1=Success, 2=Failed, 3=RolledBack, 4=InProgress |
| `bjops_testtype` | 1=单元测试…11=UAT, 12=SmokeTest |

> ⚠️ **⚠️ `bjops_approvalstatus` 和 `bjops_releaseresult` 里有"Rejected"**
> **→ 不要与 `bjops_issuestatus` 的 "Rejected"(14) 混淆**。**同名不同表，各自独立。**

### 3.4 ⚠️ 选项集改值时的三级影响

| 改什么 | 影响 |
|---|---|
| **改"显示名"** | ✅ **相对安全**（选项集按数值匹配）。⚠️ **但要注意：流程里若有"比较文本"的分支会挂** |
| **改"数值"** | ⚠️ **危险！** 已有记录会"变成另一个状态"。**→ 基本等于重做数据** |
| **删一个值** | ⚠️ **危险！** 已有记录变成"未知值" → **报表显示为空或原始数字** |
| **加一个值** | ⚠️ **需同步改 Silver 映射**（`07` §6.4），**否则报表显示原始数字** |

> ⚠️ **⚠️ 一句话原则：选项集"只加不改不删"。若必须改，走 §9 的变更记录模板。**

---

## 4. 环境变量清单（10 个）

| # | 逻辑名 | 类型 | 含义 | 示例值 |
|---|---|---|---|---|
| 1 | `TeamsGroupId` | Text | Teams 团队 ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| 2 | `TeamsChannelId` | Text | 默认通知频道 | `19:xxxxx@thread.tacv2` |
| 3 | `AdminNotificationChannelId` | Text | 告警频道 | `19:yyyyy@thread.tacv2` |
| 4 | `SharePointSiteRootUrl` | Text | SharePoint 站点根地址 | `https://<租户>.sharepoint.com/sites/SysOps` |
| 5 | `EvidenceLibraryName` | Text | 证据文档库名 | `IssueEvidence` |
| 6 | `LogPackageLibraryName` | Text | 日志包文档库名 | `LogPackages` |
| 7 | `PortalUrl` | Text | 应用门户地址 | `https://org.crm5.dynamics.com` |
| 8 | `DefaultEnvironment` | Text | 默认环境标识 | `DEV` / `TEST` / `PROD` |
| 9 | `IntakeFormId` | Text | 问题反馈表单 ID | 表单 GUID |
| **10** | **`ModelDrivenAppId`** | **Text** | **模型驱动应用 ID** | ⚠️ **本方案新增**（`05` §1.4） |

### 4.1 ⚠️ 环境变量配置五个坑

| # | 坑 | 说明 |
|---|---|---|
| **1** | ⚠️ **加了前缀** | **Name 填逻辑名（如 `TeamsGroupId`），前缀会自动加。不要手打 `bjops_`** |
| **2** | ⚠️ **值在不同环境不同** | **三个环境各配一遍**（解决方案带的是"默认值"，导入后要改"当前值"） |
| **3** | ⚠️ **改了值流程不生效** | **必须把相关流程"关掉再打开"**（`05` §1.5） |
| **4** | ⚠️ **有些动作读不到环境变量** | **Teams/SharePoint 动作的"团队/站点/库"选择器不能填变量**（`05` §3.5）→ **必须手工选 + 迁移后重选** |
| **5** | ⚠️ **Form Id 会失效** | **Forms 不是解决方案组件 → 迁移到新环境后 Form Id 变了**（`09` §5.4） |

### 4.2 配置登记表（打印用）

| 环境变量 | DEV | TEST | PROD | 备注 |
|---|---|---|---|---|
| `TeamsGroupId` | | | | |
| `TeamsChannelId` | | | | |
| `AdminNotificationChannelId` | | | | |
| `SharePointSiteRootUrl` | | | | |
| `EvidenceLibraryName` | | | | |
| `LogPackageLibraryName` | | | | |
| `PortalUrl` | | | | |
| `DefaultEnvironment` | | | | |
| `IntakeFormId` | | | | ⚠️ **每环境不同** |
| `ModelDrivenAppId` | | | | ⚠️ **每环境不同** |

---

## 5. 连接引用清单（6 个）

| # | 连接 | 是否自动绑定 | 主要用途 | ⚠️ 重新授权要点 |
|---|---|---|---|---|
| **1** | **Dataverse** | ✅ **自动**（在解决方案内） | 所有流程的表操作 | 通常不用手工授权 |
| **2** | **Microsoft Teams** | ❌ 需手工 | 发卡片、发消息、发审批 | **授权后必须人工跑一次流程** |
| **3** | **SharePoint** | ❌ 需手工 | 附件、日志包、文档库 | 同上；⚠️ **站点/库要手工重选** |
| **4** | **Office 365 Outlook** | ❌ 需手工 | 邮件通知 | 同上 |
| **5** | **Microsoft Forms** | ❌ 需手工 | 表单响应触发 | 同上；⚠️ **Form Id 要手工改** |
| **6** | **Approvals** | ❌ 需手工 | 关闭确认、发布审批 | 同上 |

> ⚠️ **⚠️ 一句话：连接"授权成功"≠"能用"。**
> **`docs/alm-runbook.md` §5.3 的原话：授权后必须人工跑一次流程验证。**
> **→ 特别推荐用 FL-02（创建通知）做"连接健康检查"**（**因为它依赖 Teams**）。

---

## 6. 本方案新增的列与环境变量（相对原设计）

> ⚠️ **这一节很重要**：**这些是"原设计稿和数据字典里没有的"**，
> **评审时要单独确认，并回填到 `../docs/data-dictionary.md`。**

### 6.1 新增的 5 个 Dataverse 列（在 `bjops_issue` 上）

| # | 逻辑名 | 显示名 | 类型 | 用途 | 出处 |
|---|---|---|---|---|---|
| **1** | `bjops_notifiedtime` | 已通知时间 | 日期时间 | 记录通知发送时刻 | `05` §3.4 |
| **2** | `bjops_lastnotifiedstatus` | 上次通知状态 | 选项集（`bjops_issuestatus`） | ⚠️ **防循环 + 判"状态是否变了"** | `05` §4.4 |
| **3** | `bjops_lastmodifiedbyemail` | 最后修改人邮箱 | 单行文本(200) | Canvas App 场景取操作人 | `05` §7 |
| **4** | `bjops_closeconfirmationrequested` | 已请求关闭确认 | 两选项 | 防重复请求确认 | `05` §6 |
| **5** | `bjops_warnhours` | 预警小时数 | 小数 | 提前告警阈值 | `05` §5 |

> ⚠️ **列 2 的建法要特别注意**：
> **类型 = 选项集（`bjops_issuestatus`），⚠️ 可选（不要必填）**，
> **因为旧数据没有这个值，必填会导致保存失败。**（`05` §4.4 已强调。）

### 6.2 新增的 1 个环境变量

| 逻辑名 | 类型 | 用途 | 出处 |
|---|---|---|---|
| **`ModelDrivenAppId`** | Text | 拼"打开记录"的深链 | `05` §1.4 |

### 6.3 新增的 5 张表 + 8 个选项集

**已在 §2.1 和 §3.3 列出。**

### 6.4 ⚠️ 这里有一个"要不要补建"的决策

| 选择 | 做法 | 建议 |
|---|---|---|
| **A（推荐）** | **补建这 5 列 + 1 环境变量 + 5 表 + 8 选项集** | ✅ **本方案的流程设计依赖它们** |
| B | 不补建 | ⚠️ **则 `05` 手册的防循环设计、FL-05、FL-06 都要改** |

> ⚠️ **⚠️ 这是"评审必须拍板"的一件事。** **记入 §8 待决策。**

---

## 7. 待实测清单（⚠️ 全部是"未验证"，不要当成事实）

> ⚠️ **本方案是"纸面方案"，以下事项都还没有在真实环境里跑过。**
> **→ 每项都要用真实环境验证，并把结果回填到对应手册。**

### 7.1 平台能力类

| # | 待实测项 | 影响 | 出处 | 结果 |
|---|---|---|---|---|
| **T1** | **ADLS Gen2 只保留最近 5 份快照**，对"增量 Silver 计算"的实际影响 | ⚠️ 作业必须 ≤5 小时跑一次 | `00` §? / `07` §4.2 | |
| **T2** | **CSV + CDM 导出的推荐 Databricks 读法**（是否需读 `model.json`、是否需处理删除向量） | ⚠️ 读错会漏数据 | `07` §3.3 | |
| **T3** | **Notebook 能否写回 Dataverse**（不引入额外组件） | 决定"回写"能力 | `07` | |
| **T4** | **自动编号 seed 能否在解决方案导入后修改** | ⚠️ 决定跨环境编号分段方案 | `09` §5.2 / `02` §8.4 | |
| **T5** | **托管环境是否阻止解决方案 zip 导出** | ⚠️ 决定迁移路径 A/B | `09` §3 | |
| **T6** | **安全角色跨环境复制后的实际行为**（权限、成员） | ⚠️ 决定是否每次重配 | `09` §5 | |
| **T7** | **Apps Checker 是否能检查"云端流"和"模型驱动应用"** | 影响发布质量门禁 | `09` §7 | |
| **T8** | **Dataverse 更改跟踪是否默认开启** | ⚠️ 关了则湖里数据不更新 | `07` §2.4 | |
| **T9** | **ADLS Gen2 + Databricks 是否也需要 Fabric/Power BI 容量** | ⚠️ 影响许可成本 | `00` | |
| **T10** | **Dataverse 的 Exports 是增量还是全量** | 影响存储与成本 | `07` | |

### 7.2 Power Automate 类

| # | 待实测项 | 影响 | 出处 | 结果 |
|---|---|---|---|---|
| **T11** | **Forms 触发器从提交到触发的实际延迟** | ⚠️ **业务方会问"提交后多久能看到"** | `04` §? | |
| **T12** | **Dataverse "修改时"触发器能否拿到"上一版本的值"** | ⚠️ 影响 FL-03 的实现方式 | `05` §7 | |
| **T13** | **触发器里 "Filter columns" 的真实语义** | ⚠️ 配错会漏触发 | `05` §7 | |
| **T14** | **用已知超时记录测一次 SLA 升级** | ⚠️ 验证升级真的会触发 | `05` §6 | |
| **T15** | **实际查找列（Lookup）在流程里的字段名** | ⚠️ 名字与直觉不同（如 `_bjops_application_value`） | `05` §3 | |
| **T16** | **`bjops_slaconfig` 未匹配时，告警分支真的会走到** | ⚠️ 防静默失败 | `02` §6.2 | |

### 7.3 PAD / 采集类

| # | 待实测项 | 影响 | 出处 | 结果 |
|---|---|---|---|---|
| **T17** | **PAD 是否有原生 SharePoint 动作** | ⚠️ 决定"要不要用浏览器点击上传" | `06` §5 | |
| **T18** | **PAD 大文件上传的阈值** | ⚠️ 决定"要不要分卷" | `06` §5.15 | |
| **T19** | **PAD 能否读取性能计数器**（CPU/内存/磁盘/网络） | ⚠️ 设计稿 §7.2 有这个要求（`00` 记为 D13 降级） | `00` §5.1 D13 | |
| **T20** | **PAD 桌面流版本在多台机器上的一致性** | ⚠️ 决定 §9 的"每机版本台账" | `06` §11 / `10` §10 | |

### 7.4 表结构与字段类（⚠️ 这些是"核对"不是"实测"）

| # | 待核对项 | 说明 | 结果 |
|---|---|---|---|
| **T21** | **`bjops_issue` 到底多少列** | ⚠️ **数据字典说 49，但逐行相加是 55**（本附录 §2.4）→ **以逐行清单为准，并把 49 这个数字改正** | |
| **T22** | **`bjops_filesize` 用整数还是 Decimal** | 取决于日志包是否可能 ≥2 GB | |
| **T23** | **列级安全与 Power BI 的关系** | ⚠️ **列级安全不保护 Power BI**（`03` §10.4）→ 决定"排除列"还是"脱敏" | |
| **T24** | **`bjops_fixversion` 文本值与 `bjops_version` 表是否会脱节** | 见 §2.3 | |

### 7.5 ⚠️ T1–T24 的使用方式

| 做 | 不做 |
|---|---|
| ✅ **每次实测后把结果填进"结果"列** | ❌ 把它当成"已知事实" |
| ✅ **若实测结果与手册不符，改手册** | ❌ 只改自己的笔记 |
| ✅ **把实测结果作为"评审的输入"** | ❌ 跳过实测直接上生产 |

---

## 8. 待决策清单（⚠️ 需要"人拍板"，不是技术问题）

| # | 待决策 | 选项 | 建议 | 决策人 | 状态 |
|---|---|---|---|---|---|
| **D1** | **是否补建 5 列 + 1 环境变量 + 5 表 + 8 选项集** | A 补建 / B 不补建 | ✅ **A** | 评审会 | ☐ |
| **D2** | **敏感字段（`hostname`/`ipaddress`）怎么处理** | A 上游排除 / B 报表脱敏 / C 原样 | ✅ **A**（`07` §8） | **安全/IT 必须签** | ☐ |
| **D3** | **`bjops_filesize` 的类型** | 整数 / Decimal（精度 0） | 视日志包大小 | 评审会 | ☐ |
| **D4** | **"降级字段"是否收敛为查找列** | A 保持文本 / B 删列重建 | ✅ **A**（重建会丢数据） | 评审会 | ☐ |
| **D5** | **日志保留期** | 90 天 / 其他 | 90 天（建议） | **业务方** | ☐ |
| **D6** | **证据图片保留期** | 1 年 / 其他 | 1 年（建议） | **业务方** | ☐ |
| **D7** | **跨环境编号是否要全局唯一** | A 各环境独立 / B 加环境前缀 | ✅ **A**（须在 UAT 向业务方说明） | **业务方** | ☐ |
| **D8** | **SLA 历史口径**：用"当前配置"还是"当时的配置"算历史数据 | A 当前配置 / B 加列固化当时值 | A（**代价：改配置会重算历史**） | **业务方** | ☐ |
| **D9** | **是否建"健康日报"流程**（FL-08） | 建 / 不建（接受静默失败） | ✅ **建**（`05` §9） | 运维负责人 | ☐ |
| **D10** | **报表数据延迟（小时级）是否可接受** | 接受 / 不接受 | ✅ **接受**（否则不能走 Databricks） | **业务方** | ☐ |
| **D11** | **迁移路径**：手工 zip / Pipelines | A 手工 zip / B Pipelines | ✅ **A 为默认**（`09` §3） | 运维负责人 | ☐ |
| **D12** | **自动编号跨环境分段值** | DEV 1000 / TEST 300000 / PROD 600000 | ✅ **按此分段**（`09` §5.2） | 运维负责人 | ☐ |
| **D13** | **设备 Availability / MTBF、系统可用性 暂不做** | 接受 / 不接受 | ✅ **接受**（无数据源） | **业务方** | ☐ |
| **D14** | **PAD 是"有人值守"的，且桌面流不随解决方案走** | 接受 / 不接受 | ✅ **接受**（`06` §0） | 运维负责人 | ☐ |
| **D15** | **`bjops_testexecution` 的 Fail 是否必须关联一个 Bug** | 强校验 / 仅提醒 | ✅ **强校验**（设计稿 §10.4） | 评审会 | ☐ |

> ⚠️ **⚠️ 带"**业务方**"的三项（D10/D13/D7）必须在验收前拿到书面确认**（`10` §2.3）。
> ⚠️ **D2 必须有"安全/IT"签字**。

---

## 9. 模板

### 9.1 变更记录模板

```
变更编号：CHG-________
日期：__________   提出人：__________   执行人：__________
复核人：__________（⚠️ 破坏性变更必须双人）

变更内容：____________________________________________

影响到的组件（对照 `10` §9.1 勾选）：
  [ ] 全局选项集 → 已同步 Silver 映射 / 状态机 / 视图 / 流程 / 报表
  [ ] 新增或改名列 → 已同步表单 / 视图 / 业务规则 / 列级安全 /
                      ⚠️ Bronze 显式 schema / Silver / Gold / Power BI / 字段清单
  [ ] 环境变量 → 已关闭再打开相关流程
  [ ] SLA 配置 → 已通知业务方（历史口径会变）
  [ ] Databricks Notebook → 已导出存档 / 已同步 Power BI
  [ ] 解决方案重新发布 → 已走 `09` §5.9 的 12 项

是否涉及数据删除：☐ 是 ☐ 否
  若"是"：已导出数据 ☐   双人复核 ☐   已记录原因：____________

回退方式：____________________________________________
验证方式与结果：______________________________________
```

### 9.2 流程清单模板（`10` §10 台账 2）

| 流程 | 类型 | 拥有者 | 连接 | 用途 | 停用会影响谁 |
|---|---|---|---|---|---|
| FL-01 表单建单 | 自动化 | | Dataverse / Forms | | 所有新问题进不来 |
| FL-02 问题创建通知 | 自动化 | | Dataverse / Teams / Outlook | | 群里看不到新问题 |
| FL-03 状态变更通知 | 自动化 | | Dataverse / Teams / Outlook | | 变更没人知道 |
| FL-04 SLA 扫描与升级 | **计划** | | Dataverse / Teams | | SLA 失效 |
| FL-05 关闭确认 | 自动化（含审批） | | Dataverse / Teams / Approvals | | 问题关不掉 |
| FL-05b 超时自动关闭 | **计划** | | Dataverse | | 长期不关 |
| FL-06 发布审批 | 自动化（含审批） | | Dataverse / Teams / Approvals | | 发布无审批 |
| FL-07 日志包登记 | 自动化 | | SharePoint / Dataverse | | 日志包不登记 |
| FL-08 健康日报 | **计划** | | Dataverse / Teams | | 看不见故障 |

### 9.3 解决方案外组件台账（`10` §10 台账 3）

| 组件 | 位置 | 责任人 | 有版本记录吗 | 迁移时要手工做什么 |
|---|---|---|---|---|
| **Forms 表单** | `forms.office.com` | | ⚠️ **无版本控制** | 重建 + 改 Form Id + 改触发器 |
| **PAD 桌面流** | Power Automate → 桌面流 | | ⚠️ **不随解决方案走** | 每台机器重配 + 重选站点/库 |
| **Power BI 报表** | Power BI 工作区 | | ✅ **有 .pbix** | 改数据源 + 重新发布 |
| **Databricks Notebook** | Databricks 工作区 | | ⚠️ **手工导出** | 手工导入 |
| **ADLS 存储** | Azure 门户 | | — | 无 |
| **SharePoint 站点/库** | SharePoint | | — | 无（同租户） |
| **Teams 团队/频道** | Teams | | — | 无（同租户） |

### 9.4 PAD 机器配置卡（`10` §10 台账 6）

```
机器名：____________   所属区域：____________   责任人：____________

[ ] 1. 同步路径（本地暂存目录）：______________________________
[ ] 2. 采集的日志类型：☐ 应用日志 ☐ Windows 事件日志 ☐ 服务状态 ☐ 文件信息
[ ] 3. 采集的时间范围：______ 小时
[ ] 4. 上传目标库：LogPackages / __________________
[ ] 5. 桌面流版本号：__________   上次更新日期：__________

[ ] Power Automate Desktop 已安装并登录（账号：____________）
[ ] 机器上未启用休眠（否则定时任务不触发）
[ ] 磁盘可用空间：______ GB（阈值 ______ GB）
```

### 9.5 凭据到期表（`10` §10 台账 5）

| 凭据 | 用途 | 到期日 | 提前多少天提醒 | 续期方式 | 更新后谁要改 |
|---|---|---|---|---|---|
| Power BI → Databricks | 报表刷新 | | 14 天 | | 数据集设置 → 编辑凭据 |
| Databricks PAT（若用） | Notebook/API | | 14 天 | | 同上 |
| Azure 服务账号密码 | 存储访问 | | 30 天 | | |
| | | | | | |

### 9.6 视图清单（`02` §11）

| 表 | 视图名 | 关键筛选 |
|---|---|---|
| `bjops_issue` | **我的待办**（默认视图） | 负责人 = 当前用户 且 状态 ∉ {Closed, Rejected} |
| `bjops_issue` | 新问题待受理 | 状态 = New |
| `bjops_issue` | Critical 与 High | 严重度 ∈ {Critical, High} 且未关闭 |
| `bjops_issue` | 等待信息 | 状态 = WaitingForInfo |
| `bjops_issue` | 待测试 | 状态 ∈ {ReadyForTest, Testing} |
| `bjops_issue` | 待发布 | 状态 = ReadyForRelease |
| `bjops_issue` | 未关闭全部 | 状态 ∉ {Closed, Rejected} |
| `bjops_issue` | ⚠️ **自动化异常 - 标志位卡住** | **本方案新增**（`05` §8）→ **列入每日巡检** |
| `bjops_slaconfig` | 启用的配置 | 是否启用 = 是 |
| `bjops_version` | 生产中版本 | 版本状态 = Production |
| `bjops_release` | 进行中发布 | 发布结果 ∈ {InProgress, 空} |
| `bjops_testexecution` | 未通过执行 | 测试结果 ∈ {Fail, Blocked} |

### 9.7 安全角色清单（`03` §2.2）

| 角色（显示名） | 唯一名 | 阶段 | 关键权限 |
|---|---|---|---|
| **请求人** | `SysOps Requester` | Phase 1 | 只能看自己的 Issue；`hostname`/`ipaddress` 不可见 |
| **运维操作员** | `SysOps Operator` | Phase 1 | 改状态/负责人；不能改 `rootcause` |
| **开发人员** | `SysOps Developer` | Phase 1 | 改 `rootcause`/`solution`；不能改状态 |
| **平台管理员** | `SysOps Admin` | Phase 1 | 全部（**但历史表也只读**） |
| **测试人员** | `SysOps Tester` | Phase 2 | `bjops_testcase`/`bjops_testexecution` 读写 |
| **发布经理** | `SysOps ReleaseManager` | Phase 2 | `bjops_version`/`bjops_release` 读写 |

> ⚠️ **安全角色是"环境级"的，不随解决方案走 → 三个环境各配一遍。**
> ⚠️ **复制角色不复制成员 → 成员要在每个环境重新添加。**

---

## 10. 本附录的交叉修订项

- [ ] `../docs/data-dictionary.md` 回填：**5 张新表 + 8 个新选项集 + `bjops_issue` 实际列数（修正 49）**
- [ ] `../docs/data-dictionary.md` 回填：**5 个新列**（`bjops_notifiedtime` / `bjops_lastnotifiedstatus` / `bjops_lastmodifiedbyemail` / `bjops_closeconfirmationrequested` / `bjops_warnhours`）
- [ ] `../docs/Phase1-实施方案.md` §11 补：**`ModelDrivenAppId` 环境变量**
- [ ] `00` 补：**§8 待决策清单的 15 项**
- [ ] `02` 补：**5 个新列的建列步骤 + "自动化异常 - 标志位卡住"视图**
- [ ] `03` 补：**自动化标志位列的列级安全（仅管理员可改）**
- [ ] `04` 补：**Forms 触发延迟的实测记录位置**
- [ ] `05` 补：**`bjops_fixversion` 的版本号存在性校验**
- [ ] `06` 补：**PAD 的 T17/T18/T19 实测结果**
- [ ] `07` 补：**T1/T2/T9/T10 实测结果**
- [ ] `08` 补：**T23（列级安全与 Power BI）的最终处理方式**
- [ ] `09` 补：**T4/T5/T6/T7 实测结果**
- [ ] `10` 补：**T20（PAD 每机版本台账）**
- [ ] 根 `README.md` 补：**`无代码方案/` 目录索引**

---

**相关文档**：[`README.md`](README.md) · [`00-方案总览.md`](00-方案总览.md) · [`02-Dataverse台账搭建手册.md`](02-Dataverse台账搭建手册.md) · [`../docs/data-dictionary.md`](../docs/data-dictionary.md) · [`../docs/Phase1-实施方案.md`](../docs/Phase1-实施方案.md)
