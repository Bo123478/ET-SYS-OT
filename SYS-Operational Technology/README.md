# 现场设备与系统运维数字化平台

BJ 工厂现场设备与系统运维数字化平台。本仓库承载 **Phase 1（统一问题入口 + Teams 协同闭环）** 的设计文档与工程骨架。

## 文档索引

| 文档 | 说明 |
|---|---|
| [`现场设备与系统运维数字化平台_开发参考方案.md`](现场设备与系统运维数字化平台_开发参考方案.md) | 总体方案设计稿（V0.1），覆盖 Phase 1–4 全部构想 |
| [`docs/Phase1-实施方案.md`](docs/Phase1-实施方案.md) | **Phase 1 实施方案**，本文档集的总纲 |
| [`docs/data-dictionary.md`](docs/data-dictionary.md) | 数据字典：表/列定义、选项集、KPI 口径、保留与脱敏规则 |
| [`docs/rbac-matrix.md`](docs/rbac-matrix.md) | 权限矩阵：角色 × 表 × 操作，含列级安全与审计配置 |
| [`docs/intake-forms.md`](docs/intake-forms.md) | 问题入口设计：Forms 字段映射、Canvas App 规划、技术债登记 |
| [`docs/AI-Agent接入方案.md`](docs/AI-Agent接入方案.md) | AI-Agent 平台接入方案：日志分析、图片识别、知识检索、建议输出与审批治理 |
| [`docs/alm-runbook.md`](docs/alm-runbook.md) | ALM 操作手册：环境、服务主体、导入后必做项、发布与回滚 |
| [`docs/uat-phase1.md`](docs/uat-phase1.md) | Phase 1 验收记录表：MVP 十一条标准逐条留证 |

> 阅读顺序建议：先读 `docs/Phase1-实施方案.md` 的第 1 章（与设计稿的重大差异），再按需查阅其余文档。

### 无代码方案（并行方案集）

[`无代码方案/`](无代码方案/README.md) 是**同一目标的另一条落地路径**：**不写代码、不引入源码仓库、不建立自动化流水线**，全部通过浏览器门户与表单手工配置完成，并延伸到 Databricks 数据加工与 Power BI 报表。

与上方 `docs/` 文档集的关系：

| 项 | `docs/`（代码工程路径） | `无代码方案/`（手工配置路径） |
|---|---|---|
| 交付方式 | `.cdsproj` + `pac` + GitHub Actions | 门户点击 + 表单填写 + 手工 zip 导出导入 |
| 数据范围 | Phase 1 的 6 张表 + 12 个选项集 | **11 张表 + 20 个选项集**（含 Phase 2 的版本/测试/发布表） |
| 数据加工 | 未覆盖 | **Databricks（Notebooks）→ ADLS Gen2 → Power BI** |
| 目标读者 | 开发工程师 | **运维人员 / 业务管理员**（无需编程背景） |

> ⚠️ **两条路径并行存在、互不替代。** 无代码方案在"表数量与报表范围"上覆盖更广，代价是**没有版本控制与自动化测试**，因此**依赖详细的运维手册与变更影响矩阵**来兜底。

| 文档 | 说明 |
|---|---|
| [`无代码方案/README.md`](无代码方案/README.md) | 无代码方案总入口：文档导航、执行顺序、与 `docs/` 的差异总览 |
| [`无代码方案/00-方案总览.md`](无代码方案/00-方案总览.md) | 目标、范围、总体架构、技术选型、阶段划分、风险与待决策事项 |
| [`无代码方案/01-前置条件与许可检查.md`](无代码方案/01-前置条件与许可检查.md) | 许可、账号、环境、Teams 的前置检查清单 |
| [`无代码方案/02-Dataverse台账搭建手册.md`](无代码方案/02-Dataverse台账搭建手册.md) | 11 张表 + 20 个选项集 + 关系 + 视图 + 业务规则 + 列级安全的逐步搭建手册 |
| [`无代码方案/03-权限安全与审计手册.md`](无代码方案/03-权限安全与审计手册.md) | 6 个安全角色、逐表权限、列级安全、审计与托管环境 |
| [`无代码方案/04-问题入口手册.md`](无代码方案/04-问题入口手册.md) | Forms 表单字段映射、适配器测试、技术债登记 |
| [`无代码方案/05-Power-Automate流程手册.md`](无代码方案/05-Power-Automate流程手册.md) | FL-01…FL-08 云端流与计划流、环境变量、连接引用、防循环设计 |
| [`无代码方案/06-附件与日志采集手册.md`](无代码方案/06-附件与日志采集手册.md) | 6 个文档库、Power Automate Desktop 采集流、文件命名与关联方式 |
| [`无代码方案/07-Databricks数据加工手册.md`](无代码方案/07-Databricks数据加工手册.md) | ADLS Gen2、Bronze/Silver/Gold 三层、Notebook、作业调度、时区与敏感字段决策 |
| [`无代码方案/08-Power-BI报表与DAX手册.md`](无代码方案/08-Power-BI报表与DAX手册.md) | 6 个报表页面、数据模型、DAX 度量值、刷新与 RLS |
| [`无代码方案/09-发布迁移与备份手册.md`](无代码方案/09-发布迁移与备份手册.md) | 解决方案导出导入、自动编号分段、连接重授权、回退、备份与恢复 |
| [`无代码方案/10-验收与日常运维手册.md`](无代码方案/10-验收与日常运维手册.md) | 验收标准、手工 UAT、每日/每周/每月巡检、故障处理、变更影响矩阵 |
| [`无代码方案/附录A-门户速查与字段清单.md`](无代码方案/附录A-门户速查与字段清单.md) | 门户菜单路径、表/字段/选项集/环境变量清单、待实测与待决策清单、台账模板 |

## 工程结构

```text
.
├─ README.md                          本文件
├─ .gitignore                         排除构建产物与环境相关文件
├─ .github/workflows/                  GitHub Actions 流水线（Phase 1 待建）
├─ solution/                           Power Platform 解决方案工程
│  └─ DeploymentSettings/              各环境环境变量与连接引用的注入值
├─ infra/
│  ├─ bootstrap/                       环境校验、服务主体创建与授权脚本
│  ├─ sharepoint/                      PnP PowerShell 建文档库与文件夹结构
│  └─ scripts/                         冒烟测试等运维脚本
└─ docs/                               设计与运维文档
```

## 当前状态

**设计阶段**。文档已就绪，工程骨架目录已建立，**尚未开始开发**。

| 阶段 | 内容 | 状态 |
|---|---|---|
| S0 | 环境与工具链准备 | ⬜ 未开始 |
| S1 | 解决方案工程骨架 | ⬜ 未开始 |
| S2 | 数据模型（12 选项集 + 6 表） | ⬜ 未开始 |
| S3 | 权限与安全 | ⬜ 未开始 |
| S4 | 流程开发（FL-01…FL-07） | ⬜ 未开始 |
| S5 | 问题入口（Forms + Canvas App） | ⬜ 未开始 |
| S6 | 附件层（SharePoint 文档库） | ⬜ 未开始 |
| S7 | CI/CD 流水线 | ⬜ 未开始 |
| S8 | 测试与 UAT | ⬜ 未开始 |

## 关键前置条件

在开始 S0 之前必须确认：

1. **DEV / TEST / PROD 三个环境均已启用 Dataverse 数据库**。
   这是硬性要求——Power Platform 的解决方案式 ALM 与 GitHub Actions **不支持无数据库的环境**，也不支持把 SharePoint 列表作为部署单元。
2. Power Platform CLI（`pac`）已安装并可在本地登录目标环境。
3. GitHub 仓库已建立，且可配置 Secrets 与受保护环境。
4. Teams 团队 `Digital Solution Operation Center` 已创建，9 个频道就绪。

## 技术栈

| 层 | 选型 |
|---|---|
| 台账数据层 | Microsoft Dataverse |
| 大文件层 | SharePoint 文档库（备选 Azure Blob） |
| 流程引擎 | Power Automate 云流 |
| 问题入口 | Microsoft Forms（Phase 1a）→ Canvas App（Phase 1b） |
| 协同通道 | Microsoft Teams（Adaptive Card） |
| CI/CD | GitHub Actions（Power Platform Actions） |
| 工具链 | Power Platform CLI（`pac`） |

## 命名约定

- 解决方案：`OpsIssueManagement`
- 发布者前缀：`bjops`（**创建元数据项后不可更改**）
- 表与列：`bjops_` + 小写逻辑名
- 流程：`FL-<业务域>-<动作>`
- 环境变量：PascalCase（如 `TeamsGroupId`）

## 重要提醒

- **不要先在开发环境手工建表再从环境倒扒源码。** 组件应在解决方案工程内创作，DEV 环境是部署产物而非源头。
- **发布者前缀一旦创建了元数据项就不可更改**，S1 阶段评审通过后即冻结。
- **环境相关配置值禁止提交到仓库**（Teams 频道 ID、站点地址等），一律通过 `solution/DeploymentSettings/` 按环境注入。
