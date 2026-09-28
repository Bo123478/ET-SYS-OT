# ALM 操作手册（Phase 1）— 现场设备与系统运维数字化平台

| 项 | 内容 |
|---|---|
| 版本 | V0.1 |
| 状态 | 设计稿，待评审 |
| 上游 | [`Phase1-实施方案.md`](Phase1-实施方案.md) §12 环境与发布通道、§13 CI/CD |
| 适用对象 | 平台管理员、发布执行人 |

> 本文档记录**操作步骤**，而非设计决策。设计依据见实施方案第 12–13 章。

---

## 1. 环境清单

| 环境 | 用途 | 解决方案类型 | 部署方式 | 环境地址 |
|---|---|---|---|---|
| DEV | 开发 | **Unmanaged** | 人工创作 | 待填 |
| TEST | 测试 | Managed | 自动部署 + 冒烟 | 待填 |
| PROD | 生产 | Managed | 手工触发 + 审批 | 待填 |

> ⚠️ **不可把 Managed 解决方案导入到持有对应 Unmanaged 解决方案的环境。** DEV 只持有 Unmanaged。
> ⚠️ 三个环境**必须均已启用 Dataverse 数据库**，否则流水线在第 2 步就会失败。

### 1.1 环境校验（S0 首要任务）

| # | 检查项 | 通过标准 |
|---|---|---|
| 1 | 环境存在 | 三个环境在 Power Platform 管理中心可见 |
| 2 | **已启用数据库** | 环境详情中「Dataverse」状态为已启用 |
| 3 | 环境类型 | 建议为「生产」或「沙盒」，不用「试用」 |
| 4 | 语言与区域 | 中文（简体）+ 中国标准时间，**三个环境必须一致** |
| 5 | 容量充足 | 至少 1 GB 数据库容量，考虑 3 年数据增长 |

> **区域设置不一致会导致日期时间列行为异常**（用户本地时区）。这是跨环境问题中最隐蔽的一类。

---

## 2. 服务主体配置（S0）

### 2.1 创建

```text
pac admin create-service-principal --environment <DEV_ENV_URL>
```

输出：`Tenant ID`、`Application ID`、`Client Secret`。

**保存这些值**：Client Secret 只在创建时显示一次，无法再次查看。

### 2.2 逐环境授权

对 DEV / TEST / PROD **分别执行**：

```text
pac admin assign-user --environment <ENV_URL> --application-user --user <APP_ID> --role "System administrator"
```

> ⚠️ **容易遗漏**：只授权 DEV 是最常见的错误，直到 `deploy-test` 失败才被发现。

> ⚠️ **System administrator 是权宜之计**。若企业安全策略禁止，需创建自定义安全角色，至少覆盖：解决方案导入、自定义项发布、表结构与关系变更、全表数据读写。

### 2.3 登记密钥到期日

| 项 | 值 |
|---|---|
| 创建日期 | 待填 |
| **到期日期** | **待填** |
| 提前提醒 | 到期前 30 天 |
| 轮换步骤 | 新建密钥 → 更新 GitHub Secrets → 验证流水线 → 删除旧密钥 |

> **必须登记**。密钥过期会导致流水线静默失败，而失败信息通常表现为权限错误，容易被误判为配置问题。

### 2.4 GitHub Secrets

| Secret | 说明 |
|---|---|
| `PP_CLIENT_ID` | Application ID |
| `PP_CLIENT_SECRET` | Client Secret |
| `PP_TENANT_ID` | Tenant ID |
| `DEV_ENV_URL` | DEV 环境地址 |
| `TEST_ENV_URL` | TEST 环境地址 |
| `PROD_ENV_URL` | PROD 环境地址 |

### 2.5 生产环境审批

GitHub 仓库 → Settings → Environments → 新建 `production` → 配置 Required reviewers。

---

## 3. 日常开发流程（DEV）

### 3.1 原则

> **DEV 是部署产物，不是源头。**
> 所有组件在解决方案工程内创作，不在门户手工建表后再倒扒源码。

### 3.2 导出源码到 Git

```text
# 手工触发 export-from-dev.yml，或本地执行：
pac auth create --url <DEV_ENV_URL>
pac solution export --name OpsIssueManagement --path ./exported --managed false
pac solution unpack --zipfile ./exported/OpsIssueManagement.zip --folder ./solution --processCanvasApps
```

然后提交解包结果到分支。

> ⚠️ 1a 阶段使用 **XML 格式**。1b 引入 Canvas App 后迁移到 Dataverse Git 集成 YAML 格式（需 CLI 2.4.1+，靠 `solutions/*solution.yml` 存在与否自动识别）。

> ⚠️ **`pac canvas pack` / `pac canvas unpack` 已弃用。** 不要用它们处理 Canvas App 源码。

### 3.3 发布者前缀

前缀 `bjops` 在 S1 阶段评审通过后**冻结**。**创建任何元数据项后不可更改**——包括列、表、选项集。

---

## 4. 构建与部署

### 4.1 build.yml（push / PR）

1. checkout
2. `who-am-i`（验证凭据）
3. `check-solution`（Power Apps Checker）——**Critical 即失败**
4. `pac solution pack`（Managed）
5. `upload-artifact`

### 4.2 deploy-test.yml（build 成功后自动）

1. `import-solution`（注入 `DeploymentSettings/test.json`）
2. `publish-solution`
3. 执行 `infra/scripts/smoke-test.ps1`

### 4.3 deploy-prod.yml（手工 + 审批）

同 deploy-test，但：
- 手工触发；
- 绑定 GitHub Environment `production`，需审批；
- 注入 `DeploymentSettings/prod.json`。

---

## 5. ⚠️ 导入后必做项（每次部署）

> **这一节是本文档最重要的部分。** 以下步骤没有自动化替代，遗漏会导致数据错误。

### 5.1 核对自动编号 seed（必做）

**背景**：Dataverse 自动编号列的 seed 值**不随解决方案导入**。

**后果**：若 DEV 环境 `bjops_issuenumber` 已排到 `INC-2026-000156`，导入 TEST / PROD 后该环境序号**从默认值 1000 重新开始**。三个环境会产生相同编号，导致：
- Teams 卡片中的编号有歧义；
- 跨环境排查时无法定位；
- 若业务方引用编号做外部对账，会串数据。

**操作步骤**

| # | 步骤 |
|---|---|
| 1 | 打开**新版 Power Apps 门户**（不是经典解决方案资源管理器） |
| 2 | 进入对应环境 → 表 → `bjops_issue` → 列 `bjops_issuenumber` |
| 3 | 查看当前 seed 与下一编号 |
| 4 | 按环境规划设置 seed（见下表） |
| 5 | 同样检查 `bjops_logpackage.bjops_packagecode` |

**seed 规划建议**

| 环境 | `bjops_issuenumber` seed | 编号段 |
|---|---|---|
| DEV | 1000 | `000001`–`299999` |
| TEST | 300000 | `300000`–`599999` |
| PROD | 600000 | `600000`– |

> 按环境分段的好处：**任何编号一眼可辨来源环境**，无需查询即可判断。这比"三环境各自从 1000 开始"更安全。

> ⚠️ **自动编号列只能在新版门户创建和调整**。经典解决方案资源管理器不支持该列类型。

> ⚠️ **行创建后取消会跳号**，序号出现空缺属平台预期行为。需向业务方说明，避免误判为数据丢失。

### 5.2 核对环境变量值

| # | 检查 |
|---|---|
| 1 | 导入时是否指定了正确的 `--settings-file` |
| 2 | Teams 频道 ID 是否为**该环境**对应团队的值（DEV 与 PROD 通常用不同团队） |
| 3 | SharePoint 站点地址是否为该环境对应站点 |
| 4 | `PortalUrl` 是否正确（深链失效会表现为"按钮点了没反应"） |

> 环境变量值的传播是**异步**的。导入后若立即测试发现值为空，**等待数分钟再试**，不要重复导入。

### 5.3 重新绑定连接引用

首次导入到新环境后，以下连接需**手工重新授权**：

| 连接 | 说明 |
|---|---|
| Dataverse | 通常自动绑定 |
| Microsoft Teams | 需重新授权 |
| SharePoint | 需重新授权 |
| Office 365 Outlook | 需重新授权 |

> 授权失败的典型表现：流程保存成功但运行时报 401。**授权后必须人工跑一次流程验证**，不能只看"已连接"标记。

### 5.4 核对审计保留期

新环境中审计保留期通常为默认值（30 天），需手动提高以匹配 `data-dictionary.md` §7.1 的数据保留期。

---

## 6. 回滚

| 场景 | 操作 |
|---|---|
| 应用变更需回滚 | 导入上一版本的 Managed 解决方案 |
| 表结构变更需回滚 | ⚠️ **无法自动回滚**。删除列会丢失数据。需人工评估 |
| 流程异常需紧急停用 | 在解决方案中关闭对应流 |

> ⚠️ **Managed 解决方案的升级不会自动删除旧组件**。删除列、删除表这类破坏性变更需人工在目标环境处理，且**必然伴随数据丢失**。
> **防护措施**：涉及删除的变更必须在 PR 中显式标注并双人复核。

### 6.1 Hotfix 流程

设计稿 §9.4 定义的 Hotfix 路径：

1. 从 PROD 当前版本的源码分支创建 `hotfix/*` 分支；
2. 修改后走 `build.yml` → `deploy-test.yml` 验证；
3. 走 `deploy-prod.yml`（审批）发布；
4. **合并回主线**，避免下次常规发布覆盖掉 Hotfix。

> 第 4 步最容易被遗漏。漏做会导致下次发布把 Hotfix 修复的内容回退，而现象是"修好的问题又出现了"，排查成本极高。

---

## 7. 发布门禁（Phase 1 子集）

| # | 门禁 | 检查方式 |
|---|---|---|
| 1 | Power Apps Checker 0 Critical | `build.yml` 自动 |
| 2 | 导入成功 | 流水线自动 |
| 3 | 冒烟测试通过 | `smoke-test.ps1` |
| 4 | 环境变量注入正确 | **人工核对**（§5.2） |
| 5 | 审批完成 | GitHub Environment |

**Phase 2 补充的门禁**：版本唯一性、测试证据完整性（依赖 `VersionRegistry` / `TestExecution`）。

---

## 8. 常见问题排查

| 现象 | 可能原因 | 排查 |
|---|---|---|
| 流水线 `who-am-i` 失败 | 密钥过期 / 环境未授权服务主体 | 检查 §2.3、§2.2 |
| 导入报"缺少依赖" | 目标环境缺少前置解决方案 | 检查解决方案依赖清单 |
| Managed 导入到 DEV 失败 | DEV 持有 Unmanaged | 见 §1 警告 |
| 流程保存失败 | 环境变量名用了保留名 `$authentication` / `$connection` | 改名 |
| 流程运行 401 | 连接未重新授权 | 见 §5.3 |
| 环境变量值为空 | 传播异步 / 未指定 settings-file | 等待或检查导入参数 |
| 编号重复 | seed 未按 §5.1 设置 | 见 §5.1 |
| 卡片深链点了没反应 | `PortalUrl` 环境变量错误 | 见 §5.2 第 4 项 |
| SharePoint 环境变量绑定失败 | 显示名与逻辑名不一致 | 见实施方案 §11.4 |
| 通知风暴 | 防循环规范未落实 | 检查 §8.3 五条 + 冒烟断言 ③ |
| Requester 看不到自己的问题 | `ownerid` 未设为 `reporter` | 见 `rbac-matrix.md` §3.1 |
| 权限验证通过但实际不生效 | 配置正确 ≠ 行为正确 | 用真实账号验证 |

---

## 9. 检查清单

### 9.1 S0 完成标准

- [ ] 三个环境均已启用 Dataverse 数据库
- [ ] 三环境语言与区域设置一致
- [ ] 服务主体已创建
- [ ] 服务主体在**三个环境**均已授权
- [ ] 密钥到期日已登记（§2.3）
- [ ] GitHub Secrets 已配置（6 项）
- [ ] GitHub Environment `production` 已配审批人

### 9.2 每次发布完成标准

- [ ] `build.yml` 通过，0 Critical
- [ ] 导入无警告
- [ ] 冒烟测试 4 项断言全通过
- [ ] **自动编号 seed 已核对**（§5.1）
- [ ] 环境变量值已核对（§5.2）
- [ ] 连接已授权且**人工跑过一次流程**（§5.3）
- [ ] 审批记录已留痕
