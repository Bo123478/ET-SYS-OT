# 现场设备与系统运维数字化平台 — Phase 1 实施方案

| 项 | 内容 |
|---|---|
| 版本 | V0.1 |
| 状态 | 设计稿，待评审 |
| 上游文档 | [`../现场设备与系统运维数字化平台_开发参考方案.md`](../现场设备与系统运维数字化平台_开发参考方案.md)（V0.1 方案设计稿） |
| 适用范围 | **Phase 1：统一问题入口 + Teams 协同闭环** |
| 交付形态 | 可源码管理的 Power Platform 工程（Power Platform CLI + 解决方案源码 + GitHub Actions CI/CD） |
| 目标环境 | DEV / TEST / PROD，三者均启用 Dataverse 数据库 |

> **阅读提示**：如果只读一章，请读第 1 章。它记录了本方案与上游设计稿之间最重要的架构差异，以及做出该差异的客观依据。

---

## 0. 文档说明

本文档是上游设计稿的**落地实施方案**，只覆盖 Phase 1 范围。上下游关系：

| 文档 | 定位 |
|---|---|
| `现场设备与系统运维数字化平台_开发参考方案.md` | 总体设计稿，覆盖 Phase 1–4 的完整业务构想 |
| **本文档** | Phase 1 的工程落地实施方案，含数据模型、流程、权限、CI/CD |
| `data-dictionary.md` | 数据字典，本文档第 6 章的展开 |
| `rbac-matrix.md` | 权限矩阵，本文档第 7 章的展开 |
| `intake-forms.md` | 问题入口字段映射，本文档第 9 章的展开 |
| `alm-runbook.md` | ALM 操作手册，本文档第 12–13 章的运维落地 |
| `uat-phase1.md` | 验收记录表，本文档第 15 章的留证载体 |

本文档与设计稿冲突时，以本文档为准，并需回改设计稿对应章节（见第 1 章末的修订清单）。

---

## 1. 与设计稿的重大差异（必读）

### 1.1 差异内容

设计稿 **§3.1 工具定位** 与 **§12 SharePoint 数据模型** 将 **SharePoint Lists** 定为业务数据层（12 个列表 + 6 个文档库）。

本方案改为：

| 层 | 设计稿 | 本方案 |
|---|---|---|
| 业务台账 | SharePoint Lists | **Microsoft Dataverse** |
| 大文件 / 附件 | SharePoint 文档库 | SharePoint 文档库（不变） |
| 非结构化附件备选 | — | Azure Blob（仅容量需要时启用） |

### 1.2 依据（不是偏好，是硬约束）

方案采用「可源码管理的工程 + CI/CD」作为交付形态，而：

> **Power Platform 的解决方案式 ALM（`pac solution`、Power Platform Build Tools、GitHub Actions）只支持带数据库的 Dataverse 环境。**

具体表现：

1. **SharePoint 列表不是解决方案组件**。它无法进入 `.cdsproj`，无法 `export` / `import`，无法版本化。用 SharePoint Lists 作数据层，等于放弃"数据模型可源码管理"这一交付目标——表结构只能靠人工在门户里点，环境间靠文档说明对齐，必然漂移。
2. **GitHub Actions 的环境连接会失败**。无数据库的 Dataverse 环境无法作为部署目标，流水线在 `who-am-i` 步骤就报错。
3. **Dataverse 提供 SharePoint Lists 所缺的能力**：列级安全（`ipaddress`、`hostname`）、字段级审计、备用键、真正的多级查找与 N:N 关系、事务性自动编号。

### 1.3 为什么 SharePoint Lists 的设计稿方案不成立

| 维度 | SharePoint Lists | Dataverse |
|---|---|---|
| 可进解决方案 | ❌ 否 | ✅ 是 |
| 表结构版本化 | ❌ 否 | ✅ 是 |
| Canvas App 委派 | ⚠️ 多处不委派（`Not`、`<>`、系统字段） | ✅ 支持 |
| 列表视图阈值 | 5,000 项 | 无此限制 |
| 列级安全 | ❌ 无 | ✅ 有 |
| 字段级审计 | ❌ 无 | ✅ 有 |
| 备用键 / 外键 | ❌ 无 | ✅ 有 |
| 12 表 + N:N + 多级查找建模 | ⚠️ 勉强，易错 | ✅ 原生 |

设计稿的 §12.1 列了 12 个列表 + §12.2 的关系图，其中包含 N:N 关系和多级查找——这正是 SharePoint Lists 最不擅长的建模形态。

### 1.4 需回改的设计稿章节

`§3.1`、`§5.1`、`§6.1`、`§8.4`、`§12`（全章）、`§13.1`、`§14.1`、`§20`（Epic A / Epic B）。

---

## 2. 技术选型

| 层 | 选型 | 说明 |
|---|---|---|
| 台账数据层 | **Microsoft Dataverse** | 表 / 列 / 关系 / 选项集 / 视图 / 表单均作为解决方案组件，可版本化 |
| 大文件层 | **SharePoint 文档库**（备选 Azure Blob） | Dataverse 文件列上限 131 MB、图片列 30 MB，且**创建后不可更改** |
| 流程引擎 | **Power Automate 云流** | 7 条主流程随解决方案部署，靠连接引用 + 环境变量解耦 |
| 问题入口 | **Microsoft Forms（1a 快通道）+ Canvas App（1b 正式入口）** | 见 §9.4 技术债说明 |
| 协同通道 | **Teams `Digital Solution Operation Center` + Adaptive Card** | 9 个频道，见 §10 |
| CI/CD | **GitHub Actions（Power Platform Actions）** | 服务主体 + 客户端密钥；每月 2,000 免费分钟 |
| 工具链 | **Power Platform CLI（`pac`）** | `clone` / `unpack` / `pack` / `import` / `version` / `check` |

### 2.1 关键容量与限制（影响设计）

| 项 | 限制 | 对设计的影响 |
|---|---|---|
| Dataverse 文件列 | 131,072 KB（131 MB），**创建后不可改** | 日志包走 SharePoint，不用文件列 |
| Dataverse 图片列 | 30,720 KB（30 MB），自动转 .jpg、缩略图裁 144×144 | 现场拍照走 SharePoint |
| 单解决方案包 | 约 95 MB | 触发拆分解决方案的阈值 |
| 环境变量值 | 2,000 字符 | 长文本配置改存 DATAVERSE 表或 SharePoint |
| 环境最小容量 | 1 GB | 容量申请前置条件 |
| Canvas App 非委派查询 | 默认仅处理前 500 条（可配 1–2000） | 测试期设为 1 以暴露委派问题 |

---

## 3. 总体架构

```text
┌─────────────────────────────────────────────────────────────┐
│  入口层                                                      │
│  Forms（1a 快通道） ／ Canvas App（1b 正式入口）              │
│  系统内嵌 ／ 日志工具（Phase 3 预留）                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│  接入层（解决方案外，每环境手工绑定，已文档化）                │
│  Power Automate 适配器流：字段映射 + 二次校验                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│  台账层：Microsoft Dataverse                                 │
│  bjops_application    bjops_equipment    bjops_issue         │
│  bjops_issuehistory   bjops_logpackage   bjops_slaconfig     │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│  流程层：Power Automate 主流程组（解决方案内 7 条）           │
│  FL-01 … FL-07                                               │
└───────────┬─────────────────────────────┬───────────────────┘
            │                             │
┌───────────▼──────────────┐  ┌───────────▼───────────────────┐
│ Teams 频道 Adaptive Card │  │ SharePoint 文档库              │
│ 9 个频道                 │  │ IssueEvidence / LogPackages    │
└──────────────────────────┘  └───────────────────────────────┘
```

---

## 4. 关键设计原则

1. **DEV 是部署产物，不是源头。**
   先 `pac solution init` 建解决方案骨架，所有组件在解决方案工程内创作。**严禁**先在门户手工建表、再从环境倒扒源码——那样丢失变更历史，且无法保证 DEV 与源码一致。

2. **台账与原始日志分离**（设计稿 §7.1）。
   Dataverse 存元数据与索引字段，原始日志包与图片存 SharePoint。二者通过 `logpackagelink` / `evidencefolderurl` 关联。

3. **配置外置**。
   SLA 阈值入 `bjops_slaconfig` 表；环境相关值入环境变量；凭据走连接引用。**流程内不得硬编码**任何环境地址、频道 ID、阈值。

4. **发布者前缀一次定对**。
   定为 `bjops`。该前缀**在创建任何元数据项后不可更改**，因此 S1 阶段评审通过后即冻结。

5. **防循环优先**。
   所有写数据流程必须遵守 §8.3 的防死循环规范。这是本项目最容易出事、也最难事后补救的一环。

---

## 5. 工程结构

```text
d:\Dev\prioject\SYS-Operational Technology\
├─ README.md
├─ .gitignore
├─ 现场设备与系统运维数字化平台_开发参考方案.md     上游设计稿
├─ .github/workflows/
│  ├─ README.md                                    流水线说明（已建）
│  ├─ export-from-dev.yml                          ← S7 待建
│  ├─ build.yml                                    ← S7 待建
│  ├─ deploy-test.yml                              ← S7 待建
│  └─ deploy-prod.yml                              ← S7 待建
├─ solution/
│  ├─ OpsIssueManagement.cdsproj                   ← S1 待建
│  └─ DeploymentSettings/
│     ├─ README.md                                 说明（已建）
│     ├─ dev.json                                  ← S7 待建
│     ├─ test.json                                 ← S7 待建
│     └─ prod.json                                 ← S7 待建
├─ infra/
│  ├─ bootstrap/                                   环境校验、服务主体创建与授权（已建目录）
│  ├─ sharepoint/                                  PnP PowerShell 建库与文件夹结构（已建目录）
│  └─ scripts/                                     smoke-test.ps1 等（已建目录）
└─ docs/
   ├─ Phase1-实施方案.md                           本文档
   ├─ data-dictionary.md
   ├─ rbac-matrix.md
   ├─ intake-forms.md
   ├─ alm-runbook.md
   └─ uat-phase1.md
```

> ⚠️ 工作区目录名 `prioject` 为笔误（正确拼写应为 `project`）。当前路径已被多处文档引用，如需更正请在 S1 阶段一并处理，避免后续引用失效。

---

## 6. 数据模型设计

> 完整字段定义、数据类型、必填性、选项集取值见 [`data-dictionary.md`](data-dictionary.md)。本草给出建模决策与依据。

### 6.1 命名规范

- **表与列物理名**：`bjops_` + 小写逻辑名（如 `bjops_issuenumber`）。显示名为中文，供业务用户使用。
- **全局选项集**统一 `bjops_` 前缀，**禁止使用列内联选项（Local Option Set）**。
  理由：内联选项集无法跨表复用，取值调整需逐列修改，是多表状态口径不一致的常见根因。
- **备用键**：`bjops_appcode`、`bjops_equipmentcode`、`bjops_issuenumber`。
  用途：外部系统（MES、日志工具、Phase 3 Agent）按业务编码做 upsert，无需先查询 GUID。
- **系统字段**：`statecode` / `statuscode` 仅作记录启停用，**业务状态另建 `bjops_status` 列**。
  理由：`statuscode` 与 Dataverse 记录生命周期绑定，改状态会与"删除/停用"语义冲突。

### 6.2 全局选项集（12 个）

| 逻辑名 | 取值 |
|---|---|
| `bjops_environment` | DEV / TEST / UAT / PROD |
| `bjops_issuetype` | Incident / Bug / Request / Enhancement |
| `bjops_category` | 功能 / 数据 / 性能 / 通信 / 权限 / 界面 / 其他 |
| `bjops_severity` | Critical / High / Medium / Low |
| `bjops_reproducibility` | Always / Intermittent / Once / Unknown |
| `bjops_issuestatus` | New / Triaged / Assigned / Analyzing / WaitingForInfo / Fixing / ReadyForTest / Testing / ReadyForRelease / Released / Monitoring / Closed / Reopened / Rejected |
| `bjops_closecode` | Fixed / Workaround / Accepted / Rejected / Duplicate / NoRepro / Cancelled |
| `bjops_rootcause` | 10 项（见数据字典） |
| `bjops_waitingreason` | 6 项（见数据字典） |
| `bjops_apptype` | 6 项（见数据字典） |
| `bjops_versionsource` | 自动读取 / 手工选择 |
| `bjops_issuesource` | Forms / Power Apps / 系统内嵌 / 日志工具 / 邮件 / 其他 |

> ⚠️ `bjops_issuestatus` 的 14 个取值**必须与设计稿 §11 的状态机逐字一致**。状态机、选项集、视图筛选条件、流程条件分支四处引用同一套取值，任一处拼写不一致都会导致静默失效。

### 6.3 表清单

**Phase 1 落地 6 张**：

| 表 | 用途 |
|---|---|
| `bjops_application` | 应用登记台账 |
| `bjops_equipment` | 设备/客户端台账 |
| `bjops_issue` | 问题主表 |
| `bjops_issuehistory` | 问题变更历史 |
| `bjops_logpackage` | 日志包登记 |
| `bjops_slaconfig` | SLA 配置 |

**推迟至 Phase 2 的 6 张**：`VersionRegistry`、`ReleaseRegister`、`TestPlan`、`TestCase`、`TestExecution`、`KnowledgeBase`。

推迟的影响与降级方案见 §15.2。

### 6.4 `bjops_application`（应用台账）

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_appcode` | 单行文本(20) | **备用键** |
| `bjops_name` | 单行文本(100) | 应用名称 |
| `bjops_apptype` | 选项集 `bjops_apptype` | 应用类型 |
| `bjops_ownergroup` | 单行文本(100) | 负责团队，**流程据此决定通知对象** |
| `bjops_owner` | 用户 | 负责人 |
| `bjops_defaultenvironment` | 文本 | 默认环境 |
| `bjops_currentprodversion` | 单行文本(50) | 当前生产版本，Phase 2 改查找 |
| `bjops_datamodelversion` | 单行文本(50) | 数据模型版本 |
| `bjops_status` | 文本 | 启用状态 |
| `bjops_description` | 多行文本(2000) | 说明 |

### 6.5 `bjops_equipment`（设备台账）

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_equipmentcode` | 单行文本(30) | **备用键** |
| `bjops_name` | 单行文本(100) | 设备名称 |
| `bjops_application` | 查找 → application | 所属应用 |
| `bjops_productionline` | 单行文本(50) | 生产线 |
| `bjops_area` | 单行文本(50) | 区域 |
| `bjops_hostname` | 单行文本(100) | 主机名（**敏感**） |
| `bjops_ipaddress` | 单行文本(45) | IP 地址（**列级安全**） |
| `bjops_clientversion` | 单行文本(50) | 客户端版本 |
| `bjops_osversion` | 单行文本(100) | 操作系统版本 |
| `bjops_status` | 文本 | 状态 |
| `bjops_lastreporttime` | 日期时间 | **用户本地时区**，最后上报时间 |

### 6.6 `bjops_issue`（问题主表）

字段按设计稿 §6.2 的三段分组组织，并叠加 §11.1（必要状态字段）与 §13.5（流程控制字段）。

**A. 身份与范围**

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_issuenumber` | **自动编号** `INC-{yyyy}-{6位}` | **备用键** |
| `bjops_title` | 单行文本(200) | 标题 |
| `bjops_application` | 查找 → application | 所属应用 |
| `bjops_module` | 文本 | 模块 |
| `bjops_environment` | 选项集 | 发生环境 |
| `bjops_equipment` | 查找 → equipment | 关联设备（**条件必填，用业务规则实现**） |
| `bjops_productionline` | 文本 | 生产线（由流程从设备台账带出） |
| `bjops_detectedversion` | 单行文本(50) | 发现版本，Phase 2 改查找 |
| `bjops_versionsource` | 选项集 | 版本来源 |
| `bjops_clientversion` | 单行文本(50) | 客户端版本 |
| `bjops_datapipelineversion` | 单行文本(50) | 数据管道版本 |

**B. 问题描述**

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_issuetype` | 选项集 | 问题类型 |
| `bjops_category` | 选项集 | 分类 |
| `bjops_severity` | 选项集 | 严重度（§6.3 定义） |
| `bjops_eventtime` | 日期时间 | **用户本地时区**，事件发生时间 |
| `bjops_impactscope` | 多行文本(4000) | 影响范围 |
| `bjops_steps` | 多行文本(4000) | 复现步骤 |
| `bjops_actualresult` | 多行文本(4000) | 实际结果 |
| `bjops_expectedresult` | 多行文本(4000) | 期望结果 |
| `bjops_reproducibility` | 选项集 | 可复现性 |
| `bjops_temporarymeasure` | 多行文本(2000) | 临时措施 |

**C. 证据与关联**

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_evidencefolderurl` | 超链接 | 证据文件夹地址 |
| `bjops_logpackageid` | 单行文本(50) | 日志包编号 |
| `bjops_logpackagelink` | 超链接 | 日志包地址 |
| `bjops_lotbatch` | 单行文本(50) | 批次号 |
| `bjops_relatedissue` | 查找 → issue（自引用） | 关联问题 |
| `bjops_relatedrelease` | 单行文本(50) | 关联发布，Phase 2 改查找 |

**D. 状态与处理**

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_status` | 选项集 `bjops_issuestatus` | 业务状态 |
| `bjops_assignee` | 用户 | 负责人 |
| `bjops_statusupdatetime` | 日期时间 | 状态变更时间 |
| `bjops_statuschangedby` | 用户 | 状态变更人 |
| `bjops_waitingreason` | 选项集 | 等待原因 |
| `bjops_nextaction` | 单行文本(200) | 下一步动作 |
| `bjops_targetdate` | 日期 | 目标日期 |
| `bjops_closecode` | 选项集 | 关闭代码 |
| `bjops_rootcause` | 选项集 | 根本原因 |
| `bjops_solution` | 多行文本(4000) | 解决方案 |
| `bjops_permanentmeasure` | 多行文本(2000) | 永久措施（§11.2 要求与临时措施区分） |
| `bjops_fixversion` | 单行文本(50) | 修复版本 |

**E. 流程控制**

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_automationupdate` | 两选项（是/否） | **防循环标志，默认否** |
| `bjops_formsresponseid` | 单行文本(100) | **唯一索引**，幂等键 |
| `bjops_correlationid` | 单行文本(36) | 关联 ID，贯穿流程链路 |
| `bjops_lastnotifiedon` | 日期时间 | 最后通知时间 |
| `bjops_sladeadline` | 日期时间 | SLA 截止 |
| `bjops_resolutiondeadline` | 日期时间 | 解决截止 |
| `bjops_escalationlevel` | 整数（默认 0） | 升级层级 |
| `bjops_reporter` | 用户 | **必填**，报告人 |
| `bjops_reporteremail` | 单行文本(200) | 报告人邮箱 |
| `bjops_source` | 选项集 `bjops_issuesource` | 来源 |

### 6.7 `bjops_issuehistory`（变更历史）

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_issue` | 查找 → issue | 所属问题 |
| `bjops_fieldname` | 单行文本(100) | 变更字段 |
| `bjops_oldvalue` | 多行文本(2000) | 原值 |
| `bjops_newvalue` | 多行文本(2000) | 新值 |
| `bjops_changedby` | 用户 | 变更人 |
| `bjops_changedon` | 日期时间 | 变更时间 |
| `bjops_changesource` | 选项集 | 人工 / 流程 |
| `bjops_comment` | 多行文本(2000) | 备注 |
| `bjops_correlationid` | 单行文本(36) | 关联 ID（用于追溯是哪次流程运行写入） |

### 6.8 `bjops_logpackage`（日志包登记）

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_packagecode` | **自动编号** `LOG-{yyyyMMdd}-{4位}` | 日志包编号 |
| `bjops_issue` | 查找 → issue | 关联问题 |
| `bjops_equipment` | 查找 → equipment | 关联设备 |
| `bjops_applicationversion` | 文本 | 应用版本 |
| `bjops_environment` | 选项集 | 采集环境 |
| `bjops_collectiontime` | 日期时间 | 采集时间 |
| `bjops_eventtime` | 日期时间 | 事件时间 |
| `bjops_storagelocation` | 超链接 | 存储位置 |
| `bjops_filename` | 单行文本(260) | 文件名 |
| `bjops_filesize` | 整数 | 文件大小（字节） |
| `bjops_sha256` | 单行文本(64) | 校验和 |
| `bjops_collectorversion` | 单行文本(20) | 采集工具版本 |
| `bjops_manifest` | 多行文本（JSON） | 清单（§7.4 结构） |
| `bjops_uploadedby` | 用户 | 上传人 |
| `bjops_uploadedtime` | 日期时间 | 上传时间 |
| `bjops_status` | 文本 | 状态 |

> **设计决策**：设计稿 §7.3 的日志包命名（含设备号）**保留为文件名**。表内编号改用自动编号 `LOG-{yyyyMMdd}-{4位}`，设备号独立成列。
> 理由：设备号参与编号会导致跨设备并发上传时产生重号（按设备分组计数器需要额外锁机制）；自动编号列由平台保证原子递增，无竞态。文件名保留设备号，仍满足现场按文件名识别的需求。此决策属 §17 待决策项 4。

### 6.9 `bjops_slaconfig`（SLA 配置）

| 列 | 类型 | 说明 |
|---|---|---|
| `bjops_name` | 单行文本 | 配置名称 |
| `bjops_severity` | 选项集 | 适用严重度 |
| `bjops_application` | 查找 → application | 适用应用（**留空 = 全局默认**） |
| `bjops_responsehours` | 小数 | 响应时限（小时） |
| `bjops_resolutionhours` | 小数 | 解决时限（小时） |
| `bjops_escalationrole` | 文本 | 升级对象 |
| `bjops_escalationhours` | 小数 | 升级触发时限 |
| `bjops_notifychannel` | 单行文本 | 通知频道，**填环境变量逻辑名而非硬编码 ID** |
| `bjops_isactive` | 两选项 | 是否启用 |

### 6.10 关系（对照设计稿 §12.2）

**Phase 1 落地**：

| 关系 | 类型 |
|---|---|
| Application → Equipment | 1:N |
| Application → Issue | 1:N |
| Equipment → Issue | 1:N |
| Issue → IssueHistory | 1:N |
| Issue → LogPackage | 1:N |
| Issue → Issue（自引用） | N:1 |

**Phase 2 补充**：

| 关系 | 类型 |
|---|---|
| Application → VersionRegistry | 1:N |
| Issue ↔ VersionRegistry | N:N |
| VersionRegistry → TestExecution | 1:N |
| VersionRegistry → ReleaseRegister | 1:N |
| TestCase → TestExecution | 1:N |
| Issue ↔ KnowledgeBase | N:N |

### 6.11 索引与视图

**索引**

| 目标 | 类型 | 目的 |
|---|---|---|
| `bjops_formsresponseid` | 唯一 | 幂等，防表单重复建单 |
| `bjops_status` + `bjops_severity` | 复合（非唯一） | SLA 扫描与看板筛选 |
| `bjops_assignee` | 非唯一 | "我的待办"视图 |
| `bjops_issuenumber` | 备用键 | 外部系统按编号查找 |

**视图**

1. 我的待办
2. 待受理（`status = New`）
3. Critical & High 未关闭
4. 即将超期 / 已超期
5. 我提交的（按 `reporter` 筛选）
6. 待我确认（`status = Monitoring` 且 `reporter` = 当前用户）
7. 全部已关闭

### 6.12 自动编号注意事项（重要）

`bjops_issuenumber` 采用 Dataverse 自动编号列，格式 `INC-{yyyy}-{6位}`。

| 注意项 | 说明 |
|---|---|
| **seed 不随解决方案导入** | 默认 seed 为 1000。DEV 环境排到 `INC-2026-000156` 后，导入 TEST / PROD 时该环境的序号会**从 1000 重新开始**。若不处理，不同环境会产生相同编号。**已列入 `alm-runbook.md` 导入后必做项。** |
| **只能在新版门户创建** | 自动编号列的创建与调整**只能在新版 Power Apps 门户**完成，经典解决方案资源管理器**不支持**该列类型。 |
| **跳号属预期** | 若一行被创建后取消，序号不会回退，会产生空缺。这是平台行为，需在数据字典中说明口径，避免业务方误判为数据丢失。 |

---

## 7. 权限与安全设计

> 完整的角色 × 表 × 操作矩阵见 [`rbac-matrix.md`](rbac-matrix.md)。

### 7.1 角色矩阵（概览）

| 角色 | 主数据 | Issue | History | LogPackage | SLAConfig |
|---|---|---|---|---|---|
| **Requester**（请求人） | 只读 | 创建 + 读自己提交的 | 读自己的 | 创建 + 读自己的 | 无 |
| **Operator**（运维操作员） | 读写 | 全量读 + 改状态/负责人/分类 | 读 | 读写 | 只读 |
| **Developer**（开发） | 只读 | 读全部 + 改技术字段 | 读写 | 读 | 只读 |
| **Admin**（管理员） | 全部 | 全部 | 全部 | 全部 | 全部 |

### 7.2 敏感数据处理（设计稿 §16.2 最小化原则）

| 数据 | 处理方式 |
|---|---|
| `bjops_ipaddress` | **列级安全**，限制到运维与开发角色 |
| `bjops_hostname` | 同上 |
| 证据附件 | SharePoint 文档库**权限分类**（按系统 / 区域 / 敏感级别） |
| 日志包 | 同上 |

日志禁采目录清单、脱敏规则、保留周期定义在 [`data-dictionary.md`](data-dictionary.md)。

### 7.3 审计（设计稿 §16.3）

对以下表启用 Dataverse 审计：`bjops_issue`、`bjops_issuehistory`、`bjops_logpackage`、`bjops_slaconfig`。

审计覆盖：

- 谁创建 / 分派 / 修改 / 关闭问题
- 状态与责任人变更历史
- 日志包下载行为

> Dataverse 审计是**平台级**能力，可记录字段级前后值，且记录无法被业务用户篡改。这是 SharePoint Lists 方案无法提供的合规能力，也是 §1 技术选型的又一支撑点。

---

## 8. 流程设计

### 8.1 解决方案内的 7 条流程

| 编号 | 流程名 | 触发 | 主要动作 |
|---|---|---|---|
| **FL-01** | `FL-Issue-PostCreate` | Dataverse：创建 | 补默认值 → 计算 SLA 截止 → 从设备台账带出生产线 → 写首条历史 → 发 Teams 卡片 → 记录 Correlation ID |
| **FL-02** | `FL-Issue-History` | Dataverse：更新 | 先判断 `automationupdate` → **仅比对关键列**（状态 / 负责人 / 严重度 / 结论 / 修复版本）→ 写历史 |
| **FL-03** | `FL-Issue-NotifyTeams` | Dataverse：更新 | 关键字段变化 → 发 Adaptive Card（设计稿 §5.3 全字段 + 应用深链）→ 幂等键校验 |
| **FL-04** | `FL-Issue-Assign` | 状态 → Assigned | 通知负责人 + 请求人 → 设置目标日期 |
| **FL-05** | `FL-Issue-SLAEscalation` | 定时（每 15 分钟） | 未确认新问题 / 超响应 / 超解决 / 长时无更新 / Critical&High / 临期 → 按 `slaconfig` 升级，**阈值不硬编码** |
| **FL-06** | `FL-Issue-CloseConfirm` | 状态 → Monitoring | 请请求人确认 → Confirmed 则 Closed + 判断是否生成知识草稿；未确认则退回 |
| **FL-07** | `FL-LogPackage-Register` | 文件创建 或 手工登记 | 创建 LogPackage 行 → 回写 Issue 的编号与链接 |

### 8.2 解决方案外的流程（每环境手工绑定，已文档化）

**Forms 适配器流**：`Forms 新响应` → 字段映射 → 创建 `bjops_issue` 行（带 `formsresponseid`、`source = Forms`）。

**为什么不入解决方案**：`Forms 新响应` 触发器的表单选择器是**下拉控件**，无法用环境变量传递 Form ID。把它放进解决方案会产生"导入后必须手工重新选择表单"的配置项，而这类手工步骤无法被流水线自动化，反而制造脆弱点。

**补偿设计**：适配器流做**薄接入层**，只负责字段映射与二次校验；所有业务逻辑（SLA 计算、通知、历史）全部下沉到 FL-01。这样即使适配器流需要每环境手工配置，业务逻辑仍然随解决方案自动部署。

### 8.3 防死循环规范（设计稿 §13.5，强制）

1. **写数据前**置 `automationupdate = 是`，写完置 `否`。
2. FL-02 / FL-03 **第一步**判断：若 `automationupdate = 是`，则只写历史、不发通知、不触发下游。
3. **仅关键字段变化时**才发通知（不要对任意字段改动都通知）。
4. 每次运行写入 `correlationid` + Flow Run ID 到历史行。
5. 通知**幂等键** = `IssueId` + 事件类型 + 关键值哈希。

> 这 5 条缺一不可。特别是第 2 条，它是唯一能在"流程 A 改数据触发流程 B，流程 B 又改数据触发流程 A"这类环路中打断循环的机制。冒烟脚本对此有专项断言（§15.1）。

### 8.4 命名与错误处理（设计稿 §17.3）

- **命名规范**：`FL-<业务域>-<动作>`。
- **失败通知**：所有流程开启失败通知，统一发往 Teams `03-Power Platform` 频道。
- **统一错误分支**：使用 Terminate 动作，携带错误码与 Correlation ID，便于在历史表中定位。

---

## 9. 入口设计

### 9.1 Phase 1a — Forms 快速通道

字段映射表定义在 [`intake-forms.md`](intake-forms.md)。

**校验策略：表单侧一轮 + 适配器流一轮**（对应设计稿 §13.1 步骤 1）。表单侧提供即时反馈，适配器流侧防止绕过表单直接调用 API。

### 9.2 Phase 1b — Canvas App 正式入口

三个表单屏幕：

| 屏幕 | 功能 |
|---|---|
| **提交** | 动态字段、设备/应用联动、版本自动带出、附件上传 |
| **详情与处理** | 状态流转、分派、历史时间线、证据与日志包 |
| **我的问题** | 按 `reporter` 过滤 |

Teams 卡片深链直达详情屏幕。

### 9.3 系统内嵌与日志工具

`bjops_issuesource` 预留 `系统内嵌`、`日志工具` 两个取值。

Phase 3 的 Agent 将通过 Dataverse Web API 自动创建 Issue 与 LogPackage——届时使用备用键（`bjops_appcode` / `bjops_equipmentcode`）做 upsert，无需先同步 GUID。

### 9.4 已知技术债（必须承认）

| 技术债 | 说明 |
|---|---|
| **Forms 定义非解决方案组件** | 表单字段的变更**无法被 Git 追踪**，也无法随解决方案部署。字段调整只能人工在各环境重做。 |
| **§8.4 的版本自动识别无法实现** | Forms 不支持条件显示逻辑，也不支持跨表查询，因此"选择设备后自动带出当前版本"这类联动做不到。 |

**结论**：1a 阶段的 Forms **定位为临时通道**，在文档与界面上显式标注；1b 阶段用 Canvas App 收敛为唯一正式入口。

**收敛路径**：1b 上线后，Forms 通道可保留为「快速反馈」入口（仅接收标题与描述，由运维补全字段），但**不再作为完整问题单的正式来源**。

---

## 10. 附件与文件存储

| 内容 | 去向 | 依据 |
|---|---|---|
| 台账元数据 | Dataverse 行 | 需查询、关系、权限、审计 |
| 现场图片 / 截图 | SharePoint `IssueEvidence` | 单张可能 > 30 MB；Dataverse 图片列有上限且强制转 .jpg 并裁切缩略图 |
| 日志包 | SharePoint `LogPackages` | 常 > 131 MB；Dataverse 文件列上限**创建后不可更改** |
| 发布包 / 手册 / Runbook | SharePoint 对应库 | Phase 2+ |

**文件夹结构**

```text
IssueEvidence/{yyyy}/{IssueID}/
LogPackages/{yyyy}/{IssueID}/
```

**元数据要求**（设计稿 §12.3）：每个文件携带 Issue ID、Application ID、Version、权限分类。

**图片元数据**（设计稿 §7.5）：Issue ID、设备号、拍摄时间、上传人、图片类型、原始文件名、说明。

**图片类型建议取值**：设备全景 / 控制面板 / 报警画面 / 软件界面 / 硬件连接 / 处理前 / 处理后。

---

## 11. 环境变量与连接引用

### 11.1 环境变量定义

**定义在解决方案内，值不入库。**

| 逻辑名 | 类型 | 说明 |
|---|---|---|
| `TeamsGroupId` | Text | Teams 团队 ID |
| `TeamsChannelId` | Text | 默认通知频道（`01-新问题受理`） |
| `AdminNotificationChannelId` | Text | 流程失败告警频道（`03-Power Platform`） |
| `SharePointSiteRootUrl` | Text | SharePoint 站点根地址 |
| `EvidenceLibraryName` | Text | 证据文档库名 |
| `LogPackageLibraryName` | Text | 日志包文档库名 |
| `PortalUrl` | Text | 应用门户地址，用于卡片深链 |
| `DefaultEnvironment` | Text | 默认环境标识 |
| `IntakeFormId` | Text | 问题反馈表单 ID |

### 11.2 连接引用

| 连接引用 | 说明 |
|---|---|
| Dataverse | 当前环境自身连接，导入后通常自动绑定 |
| Microsoft Teams | **需在目标环境重新授权** |
| SharePoint | **需在目标环境重新授权** |
| Office 365 Outlook | **需在目标环境重新授权** |

### 11.3 注入方式

```text
pac solution create-settings --solution-zip <包> --settings-file DeploymentSettings/<env>.json
pac solution import --path <包> --settings-file DeploymentSettings/<env>.json
```

> **禁止把环境值打进解决方案。** 每个环境的值定义在 [`../solution/DeploymentSettings/`](../solution/DeploymentSettings/README.md)。

### 11.4 注意事项

- 保留名 `$authentication`、`$connection` **不可用作环境变量名**。被占用会导致流程保存失败。
- SharePoint 数据源型环境变量要求**显示名与逻辑名一致**，否则跨环境绑定失败。
- 环境变量值的传播是**异步**的，导入后可能需等待一段时间才在流程中生效。

---

## 12. 环境与发布通道

| 环境 | 解决方案类型 | 部署方式 |
|---|---|---|
| DEV | Unmanaged | 源码真相，人工创作 |
| TEST | Managed | 自动部署 + 冒烟测试 |
| PROD | Managed | 手工触发 + 审批 |

> 不可将 Managed 解决方案导入到持有对应 Unmanaged 解决方案的环境。DEV 只应持有 Unmanaged。

**Phase 1 的发布门禁子集**（设计稿 §9.2 的 10 项中取 5 项）：

1. Power Apps Checker 0 Critical
2. 导入成功
3. 冒烟测试通过
4. 环境变量注入正确
5. 审批完成

**版本唯一性**与**测试证据完整性**两项门禁属 Phase 2（依赖 `VersionRegistry` / `TestExecution` 表）。

---

## 13. CI/CD 流水线设计

### 13.1 前置条件

1. DEV / TEST / PROD **三个环境均已启用 Dataverse 数据库**。
2. `pac admin create-service-principal` 创建服务主体。
3. `pac admin assign-user --application-user --role "System administrator"` **逐环境**授权。
4. 配置仓库 Secrets：`PP_CLIENT_ID` / `PP_CLIENT_SECRET` / `PP_TENANT_ID` / `DEV_ENV_URL` / `TEST_ENV_URL` / `PROD_ENV_URL`。
5. GitHub Environment `production` 配置审批人。

### 13.2 工作流

| 文件 | 触发 | 步骤 |
|---|---|---|
| `export-from-dev.yml` | 手工 / 定时 | `who-am-i` → export unmanaged → unpack → 提交 |
| `build.yml` | push / PR | checkout → `who-am-i` → `check-solution`（**Critical 即失败**）→ pack managed → upload-artifact |
| `deploy-test.yml` | build 成功后 | import（TEST，`test.json`）→ publish → `smoke-test.ps1` |
| `deploy-prod.yml` | 手工 + 审批 | import（PROD，`prod.json`）→ publish → 冒烟 |

**认证**：服务主体 + 客户端密钥（支持 MFA）。不使用用户名/密码（不支持 MFA，且密码轮换会中断流水线）。

**运行代理**：统一 `ubuntu-latest`，Linux 代理计费倍率更低，可节省每月 2,000 分钟免费额度。注意 Linux 上 PowerShell 需用 `pwsh`。

### 13.3 源码格式与迁移时机

| 阶段 | 格式 | 说明 |
|---|---|---|
| 1a | `pac solution clone` 的 **XML 格式** | 成熟稳定 |
| 1b | **Dataverse Git 集成 YAML 格式** | 引入 Canvas App 后迁移；需 CLI 2.4.1+；靠 `solutions/*solution.yml` 存在与否自动识别 |

> ⚠️ **`pac canvas pack` / `pac canvas unpack` 已弃用。** Canvas App 的官方源码管理路径是 Dataverse Git 集成，不要再依赖 canvas pack/unpack。此决策属 §17 待决策项 3。

---

## 14. 实施计划

| 阶段 | 内容 | 依赖 | 工期 |
|---|---|---|---|
| **S0** | 环境与工具链：三环境校验、服务主体、`pac`、GitHub 仓库与 Secrets | — | 0.5 周 |
| **S1** | 工程骨架：`solution init`、发布者 `bjops`、目录结构、README、`.gitignore` | S0 | 0.5 周 |
| **S2** | 数据模型：12 选项集 → 6 表 → 关系 → 备用键 / 索引 / 视图 | S1 | 1.5 周 |
| **S3** | 权限与安全：4 角色、列级安全、审计、`rbac-matrix` | S2 | 0.5 周 |
| **S4** | 流程：FL-01…FL-07 + 防循环规范 | S2（与 S3 并行） | 1.5 周 |
| **S5** | 入口：Forms + 适配器流 + `intake-forms` | S2（与 S3/S4 并行） | 0.5 周 |
| **S6** | 附件层：SharePoint 库与文件夹（PnP） | S0（与 S2–S5 并行） | 0.5 周 |
| **S7** | CI/CD：四条工作流 + 环境变量注入 + 冒烟脚本 | S1、S2 | 1 周 |
| **S8** | 测试与 UAT：十一条验收 + 修漏 | S4–S7 | 1 周 |

**串行约 7 周；按并行安排可压缩至约 5 周。**

**关键路径**：S0 → S1 → S2 → S4 → S8。S3 / S5 / S6 可并行，S7 依赖 S1 与 S2（可在 S2 完成后立即启动，与 S4/S5 并行）。

---

## 15. 验证与验收

### 15.1 自动化验证

| # | 检查 | 判定 |
|---|---|---|
| 1 | `pac solution check --path solution/` | 0 Critical（`build.yml` 硬门） |
| 2 | 导入 TEST 后**手工核对自动编号 seed** | 无脚本替代，见 `alm-runbook.md` |
| 3 | `smoke-test.ps1` 断言 ① | 建 Issue 后编号匹配 `INC-\d{4}-\d{6}` |
| 4 | `smoke-test.ps1` 断言 ② | `bjops_issuehistory` 生成首行 |
| 5 | `smoke-test.ps1` 断言 ③ | 置 `automationupdate = 是` 后改状态，**不产生第二条通知** |
| 6 | `smoke-test.ps1` 断言 ④ | Requester 令牌读他人 Issue，返回 403 |

> 断言 ③ 是重中之重。防死循环机制失效会导致通知风暴，且在生产环境极难事后补救。
> 断言 ④ 验证的是"角色真的生效"，而非"角色已配置"——二者并不等价。

### 15.2 设计稿 §19 十一条验收标准映射

| # | 标准 | Phase 1 实现方式 | 状态 |
|---|---|---|---|
| 1 | 统一入口提交 | Forms 落库 | ✅ 完整 |
| 2 | 含系统/设备/环境/版本/时间 | 五字段非空校验 | ✅ 完整 |
| 3 | 上传图片 | `IssueEvidence` 可见且元数据齐全 | ✅ 完整 |
| 4 | 唯一 Issue ID | 连提 3 条不重号 | ✅ 完整 |
| 5 | 运维开发同一记录 | 两角色同 URL 同数据 | ✅ 完整 |
| 6 | 状态/负责人/结论可更新且留史 | 改 3 次，History 有 3 行含原值新值 | ✅ 完整 |
| 7 | 登记测试/修复版本 | **Phase 1 用 `fixversion` 文本列留证** | ⚠️ 降级 |
| 8 | 测试记录 Pass/Fail 与证据 | **Phase 1 用备注 + 证据附件留证** | ⚠️ 降级 |
| 9 | 发布关联版本/测试/回退 | **Phase 1 用 `relatedrelease` 文本列留证** | ⚠️ 降级 |
| 10 | Power BI 四分布图 | 连 Dataverse 直接建模 | ✅ 完整 |
| 11 | 日志受控上传关联 | 上传 zip → LogPackage 行 → Issue 回写 | ✅ 完整 |

> **第 7 / 8 / 9 条 Phase 1 仅做到字段级留证**，完整的版本-测试-发布闭环属 Phase 2（依赖 `VersionRegistry` / `TestExecution` / `ReleaseRegister` 三张表）。
> **需与业务方确认该降级可接受**；若不接受，将 `VersionRegistry` + `TestExecution` 提前可解决，代价约 +1.5 周。此决策属 §17 待决策项 1。

### 15.3 手工 UAT 流程

```text
Forms 提交 → Teams 卡片 → 操作员改 Assigned 并分派 → 请求人看到同记录
→ 上传图片 → 运维改 Monitoring → 请求人确认 → Closed
```

全程在 [`uat-phase1.md`](uat-phase1.md) 中打勾留证。

---

## 16. 风险与控制

| 风险 | 控制措施 |
|---|---|
| 用户绕过平台私聊/邮件 | **Issue ID 为受理前提**；Teams 通知统一回链到记录 |
| 反馈信息不完整 | 表单必填 + 适配器二次校验 + 台账自动带出（生产线、负责人组） |
| 流程死循环通知风暴 | §8.3 全套规范；冒烟脚本专测断言 ③ |
| 自动编号 seed 各环境不一致 | `alm-runbook` 列为导入后必做项；冒烟断言编号格式 |
| 大文件撑爆 Dataverse 容量 | 台账/文件分离；文件列不用于日志包与图片 |
| Forms 技术债不收敛 | 1a 显式标注；1b 排期 Canvas App |
| 环境值误打入解决方案 | settings JSON 注入；`build.yml` 增加检查，禁止提交含环境值的文件 |
| 发布者前缀定错 | 创建元数据后不可改，S1 评审后冻结 |
| 服务主体密钥过期 | 在 `alm-runbook.md` 登记到期日，提前轮换 |
| **状态机取值口径漂移** | 选项集 / 状态机 / 视图 / 流程四处引用同一套取值，纳入 S2 评审检查项 |

---

## 17. 待决策事项

以下 4 项需业务方或技术负责人决策，**建议在 S0 结束前完成**。

### 决策 1 — §19 第 7 / 8 / 9 条是否接受 Phase 1 降级？

| 选项 | 内容 | 代价 |
|---|---|---|
| **A（推荐）** | 接受降级，Phase 1 仅字段级留证 | 省 1.5 周 |
| B | 把 `VersionRegistry` + `TestExecution` 提前 | +1.5 周 |
| C | 只提前 `VersionRegistry` | +0.5 周，解决最常被追问的版本关联 |

### 决策 2 — Teams 卡片交互深度？

| 选项 | 内容 | 说明 |
|---|---|---|
| **A（推荐）** | 信息型卡片 + 深链，状态变更在应用内完成 | 简单可靠 |
| B | 交互式卡片（`wait-for-response`） | 属长时运行流程，耗额度且难调试 |
| C | 纯文本通知 | 最快，但后续需重做 |

### 决策 3 — 源码格式迁移时机？

| 选项 | 内容 | 说明 |
|---|---|---|
| **A（推荐）** | 1b 引入 Canvas App 时迁 YAML | 1a 用成熟的 XML 格式 |
| B | 一开始就用 YAML | 需 CLI 2.4.1+，生态较新 |
| C | 一直用 XML | 无法覆盖 Canvas App 源码管理 |

### 决策 4 — LogPackage 编号是否含设备号？

| 选项 | 内容 | 说明 |
|---|---|---|
| **A（推荐）** | `LOG-{yyyyMMdd}-{4位}`，原子无竞态，设备号独立成列 | 表内编号与文件名解耦 |
| B | 保留 `LOG-20260917-K106-001`，按设备分组计数器 | 接受偶发重号 |

---

## 附录 A — 本方案依赖的平台事实

| 事实 | 影响章节 |
|---|---|
| 解决方案式 ALM 只支持带数据库的 Dataverse 环境 | §1、§13 |
| SharePoint 列表不是解决方案组件 | §1 |
| 发布者前缀创建元数据后不可更改 | §4.4、§16 |
| Dataverse 文件列 131 MB / 图片列 30 MB，创建后不可改 | §2.1、§10 |
| 自动编号 seed 不随解决方案导入 | §6.12、§12、`alm-runbook` |
| 自动编号列只能在新版门户创建 | §6.12 |
| 自动编号行取消会跳号 | §6.12 |
| 环境变量值上限 2,000 字符 | §2.1 |
| `$authentication` / `$connection` 为保留名 | §11.4 |
| SharePoint 数据源型环境变量要求显示名与逻辑名一致 | §11.4 |
| `pac canvas pack` / `unpack` 已弃用 | §13.3 |
| Canvas App 非委派查询默认处理 500 条 | §2.1 |
| Power Platform Actions 每月 2,000 免费分钟 | §2、§13.2 |

## 附录 B — 修订记录

| 版本 | 日期 | 修订内容 |
|---|---|---|
| V0.1 | 2026-09-17 | 初稿。确立 Dataverse 台账 + SharePoint 大文件混合架构；锁定 Phase 1 范围 |
