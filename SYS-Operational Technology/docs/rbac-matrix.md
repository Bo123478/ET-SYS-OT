# 权限与安全矩阵（Phase 1）— 现场设备与系统运维数字化平台

| 项 | 内容 |
|---|---|
| 版本 | V0.1 |
| 状态 | 设计稿，待评审 |
| 上游 | [`Phase1-实施方案.md`](Phase1-实施方案.md) §7 权限与安全设计 |
| 适用范围 | Phase 1 的 4 个安全角色 × 6 张表 |

---

## 1. 角色定义

| 角色 | 人员 | 职责 |
|---|---|---|
| **Requester**（请求人） | 现场操作员、工艺、质量等 | 提交问题、补充信息、确认关闭 |
| **Operator**（运维操作员） | 现场运维 | 受理、分派、状态流转、上传证据与日志 |
| **Developer**（开发人员） | 系统开发/实施 | 分析根因、填写解决方案、修复版本 |
| **Admin**（管理员） | 平台管理员 | 主数据维护、配置、审计 |

> 设计稿 §4 列出 9 个业务角色（含测试、发布经理、数据工程师等）。Phase 1 的 4 个安全角色是**平台层权限模型**，业务角色通过团队/业务单位映射到安全角色，二者不是一一对应关系。Phase 2 引入版本与测试管理时再扩充（如 Tester、ReleaseManager）。

---

## 2. 权限矩阵

图例：`C` = 创建，`R` = 读取，`U` = 更新，`D` = 删除，`—` = 无权限，🔒 = 列级安全限制

### 2.1 主数据表

| 表 | Requester | Operator | Developer | Admin |
|---|---|---|---|---|
| `bjops_application` | R | C R U | R | C R U D |
| `bjops_equipment` | R 🔒 | C R U 🔒 | R 🔒 | C R U D 🔒 |

> 主数据（应用台账、设备台账）由 Admin 与 Operator 维护，Developer 只读。Requester 只读且**看不到 `hostname` / `ipaddress`**。

### 2.2 `bjops_issue`

| 操作 | Requester | Operator | Developer | Admin |
|---|---|---|---|---|
| 创建 | C | C | C | C |
| 读取 | R（**仅自己提交的**） | R（全部） | R（全部） | R（全部） |
| 更新 | U（**仅自己提交的，且限于补充字段**） | U（**状态 / 负责人 / 分类 / 严重度**） | U（**技术字段**） | U（全部） |
| 删除 | — | — | — | U（停用） |
| 重新分配（Assign） | — | C | — | C |
| 共享（Share） | — | — | — | C |

**字段分组与写权限**

| 组 | 字段 | Requester | Operator | Developer |
|---|---|---|---|---|
| 身份与范围 | application / equipment / detectedversion 等 | 创建时写 | U | U |
| 问题描述 | title / steps / actualresult / severity 等 | C、U（补充） | U | R |
| 证据与关联 | evidencefolderurl / logpackageid 等 | C、U | U | R |
| 状态与处理 | status / assignee / closecode / rootcause / solution / fixversion | — | U（status/assignee/closecode） | U（rootcause/solution/fixversion） |
| 流程控制 | automationupdate / correlationid / sladeadline 等 | — | — | — |

> **流程控制字段不接受人工写入**。这些字段由流程维护，人工修改会产生难以追踪的异常状态。建议用**业务规则**在这些字段上禁用编辑，或在 `rbac-matrix` 对应的安全角色中设为只读。

### 2.3 `bjops_issuehistory`

| 操作 | Requester | Operator | Developer | Admin |
|---|---|---|---|---|
| 创建 | — | — | — | — |
| 读取 | R（**仅自己提交问题的历史**） | R | R | R |
| 更新 | — | — | — | — |
| 删除 | — | — | — | — |

> **历史表完全由流程写入，所有角色均为只读**。
> 这是审计证据，允许人工修改或删除会使 §16.3 的审计要求失效。在安全角色中应**不授予任何写权限**（连 Admin 也不授予），仅靠流程的服务主体身份写入。

### 2.4 `bjops_logpackage`

| 操作 | Requester | Operator | Developer | Admin |
|---|---|---|---|---|
| 创建 | C（**仅自己提交问题的**） | C | — | C |
| 读取 | R（仅自己提交问题的） | R（全部） | R（全部） | R（全部） |
| 更新 | — | U | — | U |
| 删除 | — | — | — | U |

### 2.5 `bjops_slaconfig`

| 操作 | Requester | Operator | Developer | Admin |
|---|---|---|---|---|
| 创建 | — | — | — | C |
| 读取 | — | R | R | R |
| 更新 | — | — | — | U |
| 删除 | — | — | — | U |

> Requester 完全不接触 SLA 配置，避免通过推断响应时限来博弈优先级。

---

## 3. 记录级安全策略

### 3.1 Requester 的数据隔离

Requester 只能看到**自己提交的**问题。实现方式二选一：

| 方案 | 实现 | 优缺点 |
|---|---|---|
| **A（推荐）** | 安全角色 + **Owner 团队**：Requester 仅对 `ownerid = 自己` 的行有读权限 | 平台原生，无需额外配置；但需保证 `ownerid` 正确设置为 `reporter` |
| B | **记录级安全（Record-level Security）** 按 `bjops_reporter` 筛选 | 更灵活但需额外许可与配置复杂度 |

> **关键实现细节**：若采用方案 A，FL-01 创建 Issue 时必须确保 `ownerid` = `bjops_reporter`。若流程以服务主体身份创建，`ownerid` 会默认变成服务主体，导致 Requester 看不到自己的问题。**必须显式指定 Owner**，并在冒烟测试中验证。

### 3.2 跨应用/跨区域的可见范围

Phase 1 不实现按应用或区域的数据隔离，所有 Operator / Developer 可见全部问题。

理由：Phase 1 的团队规模小，全部问题记录有助于运维人员横向发现同类问题。若后续需要隔离，通过**业务单位（Business Unit）**层级实现，但需在 S0 阶段就规划好 BU 结构——**由于 BU 结构变更会牵动所有记录的归属，事后调整代价高**。

---

## 4. 列级安全（Field Security）

| 表 | 列 | 限制 | 允许角色 |
|---|---|---|---|
| `bjops_equipment` | `bjops_hostname` | 读取受限 | Operator / Developer / Admin |
| `bjops_equipment` | `bjops_ipaddress` | 读取受限 | Operator / Developer / Admin |

**配置步骤**

1. 在表定义中启用 `bjops_hostname` 的「字段安全」。
2. 创建**字段安全配置文件（Field Security Profile）**「运维设备敏感字段」。
3. 在配置文件中将两列设为「读取 = 是」，其他为「否」。
4. 将 Operator / Developer / Admin 的角色或团队加入该配置文件。
5. Requester 不属于任何字段安全配置文件 → 默认**无读取权限**。

> ⚠️ **默认行为注意**：启用字段安全后，**不在任何配置文件中的用户将无法读取该列**（fail-closed）。这符合预期，但需注意 Admin 若未显式加入配置文件也会读不到。
> ⚠️ **导出与报表注意**：字段安全对 Power BI 直接连 Dataverse 的**服务主体身份**无效（服务主体通常有系统管理员权限）。因此 Power BI 若要做脱敏，必须在数据集层做，不能依赖字段安全。

---

## 5. 附件权限（SharePoint）

Dataverse 记录权限与 SharePoint 文档库权限是**两套独立体系**，必须分别配置，否则会出现"看不到问题记录但能看到附件"或反之的错位。

| 文档库 | 访问范围 | 实现 |
|---|---|---|
| `IssueEvidence` | Operator / Developer / Admin 全量；Requester 仅自己提交的 | SharePoint 权限组 + 文件级权限继承 |
| `LogPackages` | Operator / Developer / Admin | 文档库级权限，不向 Requester 开放 |

**权限分类维度**（设计稿 §16.1）：按系统、区域、敏感级别分类。

> ⚠️ **已知复杂度**：SharePoint 无法基于 Dataverse 记录权限自动继承。Phase 1 的简化策略：
> - `IssueEvidence` 按**文件夹**（`{yyyy}/{IssueID}/`）继承权限，Operator 及以上有整个库的读写。
> - Requester 的访问通过 Teams 卡片中的**直接文件链接**实现，不依赖库级权限——但这意味着链接一旦外泄即可访问。
> - **若业务方对抗性要求高**，需引入更细的权限同步机制（如 Power Automate 建文件夹时同步授权），代价显著。
> - 该取舍需在 S6 阶段与业务方确认。

---

## 6. 审计配置（设计稿 §16.3）

### 6.1 启用的表

| 表 | 审计 |
|---|---|
| `bjops_issue` | ✅ 启用 |
| `bjops_issuehistory` | ✅ 启用 |
| `bjops_logpackage` | ✅ 启用 |
| `bjops_slaconfig` | ✅ 启用 |
| `bjops_application` | ✅ 启用 |
| `bjops_equipment` | ✅ 启用 |

### 6.2 审计内容

| 事件 | 记录方式 |
|---|---|
| 谁创建 / 分派 / 修改 / 关闭问题 | Dataverse 审计日志（平台级，不可被业务用户删除） |
| 状态与责任人变更历史 | ① Dataverse 审计；② `bjops_issuehistory` 业务历史 |
| 日志包下载 | SharePoint 库审计（需在站点集启用） |

**双层记录的理由**：

- **Dataverse 审计**是平台级、防篡改的，用于合规举证；
- **`bjops_issuehistory`** 是业务级、可在应用内查看的，用于日常追溯。

二者不是冗余，而是面向不同使用者。但需注意二者可能**不完全一致**——例如通过数据导入绕过流程的修改会进审计但不会进业务历史。**这是发现异常操作的线索**。

### 6.3 保留期

审计日志保留期需与数据保留期（`data-dictionary.md` §7.1）匹配，默认 30 天对审计要求远远不足。**需在 S0 阶段提高审计保留期**，代价是环境存储容量增长。

---

## 7. 服务主体与流水线身份

| 用途 | 身份 | 权限 |
|---|---|---|
| GitHub Actions 部署 | 服务主体（应用注册） | **System administrator**（Dataverse 环境内） |
| 冒烟测试 | 同上 | 同上 |
| Forms 适配器流 | 连接所有者（通常是运维账号） | 需有 `bjops_issue` 创建权限 |
| Power BI 读取 | 建议独立服务主体 | **只读**，且不授予字段安全配置文件 |

> ⚠️ **服务主体使用 System administrator 是 Phase 1 的权宜之计**。若企业安全策略禁止，需退而求其次：创建一个自定义安全角色，至少包含**解决方案导入、自定义项发布、表结构变更、数据读写**权限。
> ⚠️ **服务主体密钥有效期**：需在 `alm-runbook.md` 中登记到期日，提前轮换，否则流水线会静默失败。
> ⚠️ **Power BI 与字段安全**：Power BI 使用的服务主体若有 System administrator 权限，会**绕过列级安全**。因此 Power BI 的脱敏必须在报告层实现。

---

## 8. 权限配置检查清单（S3 阶段验收用）

配置完成后逐项核对：

- [ ] 4 个安全角色已创建，且**未授予超出矩阵的权限**
- [ ] `bjops_issuehistory` 表对**所有角色**均无创建/更新/删除权限
- [ ] Requester 无法读取他人提交的 Issue（**用真实账号验证，不只看配置**）
- [ ] FL-01 创建的 Issue 的 `ownerid` = `bjops_reporter`（否则 Requester 看不到）
- [ ] 字段安全配置文件已创建，且 Admin **明确加入**（否则 Admin 也读不到）
- [ ] Requester 账号登录后，设备台账的 `hostname` / `ipaddress` 显示为空白
- [ ] 6 张表的审计已启用，且审计保留期已调整
- [ ] SharePoint `LogPackages` 未向 Requester 开放
- [ ] 服务主体在三个环境均已授权，密钥到期日已登记
- [ ] 冒烟脚本断言 ④（Requester 读他人 Issue 返回 403）通过

> **最后一项是唯一能证明权限真正生效的检查**。前九项都是配置层面的自证，配置正确不等于行为正确——Dataverse 的权限继承、团队归属、业务单位层级都可能导致实际行为与配置预期不符。
