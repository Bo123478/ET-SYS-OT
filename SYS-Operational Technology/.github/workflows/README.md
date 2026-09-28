# GitHub Actions 流水线（Phase 1 待建）

本目录将承载 4 条 Power Platform CI/CD 流水线。**当前为空占位，尚未开发。**

## 计划中的工作流

| 文件 | 触发方式 | 职责 |
|---|---|---|
| `export-from-dev.yml` | 手工 / 定时 | 从 DEV 导出 unmanaged 解决方案 → 解包 → 提交到分支 |
| `build.yml` | push / PR | 运行 Power Apps Checker（Critical 即失败）→ 打包 managed → 上传制品 |
| `deploy-test.yml` | `build` 成功后自动 | 导入 TEST（注入 `test.json`）→ 发布 → 执行冒烟脚本 |
| `deploy-prod.yml` | 手工 + 环境审批 | 导入 PROD（注入 `prod.json`）→ 发布 → 执行冒烟脚本 |

## 认证方式

使用**服务主体 + 客户端密钥**（支持 MFA）。不采用用户名/密码方式。

需要的仓库 Secrets：

| Secret | 说明 |
|---|---|
| `PP_CLIENT_ID` | 应用注册的客户端 ID |
| `PP_CLIENT_SECRET` | 应用注册的客户端密钥 |
| `PP_TENANT_ID` | 租户 ID |
| `DEV_ENV_URL` | DEV 环境地址 |
| `TEST_ENV_URL` | TEST 环境地址 |
| `PROD_ENV_URL` | PROD 环境地址 |

服务主体的创建与授权步骤见 [`docs/alm-runbook.md`](../../docs/alm-runbook.md)。

## 运行环境

统一使用 `ubuntu-latest`：

- Power Platform Actions 同时支持 Windows 与 Linux 代理；
- Linux 代理计费倍率更低，可节省每月 2000 分钟的免费额度；
- 冒烟脚本若要复用 PowerShell，注意在 Linux 上需用 `pwsh` 而非 `powershell`。

## 注意

- `deploy-prod.yml` 必须绑定 GitHub Environment `production` 并配置审批人，避免误发布。
- `build.yml` 中的 Power Apps Checker 是**硬性质量门**，出现 Critical 级别告警即阻断流水线。
- 环境变量值一律通过 `solution/DeploymentSettings/<env>.json` 注入，**不得写入工作流文件或解决方案**。
