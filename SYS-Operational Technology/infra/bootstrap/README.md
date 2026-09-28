# Bootstrap 脚本（S0 阶段待建）

本目录将存放**环境准备与校验**脚本。**当前为空占位，尚未开发。**

## 计划内容

| 脚本（拟定） | 职责 |
|---|---|
| `check-environments.ps1` | 校验 DEV/TEST/PROD 三个环境存在且**已启用 Dataverse 数据库**，输出环境地址与数据库状态 |
| `create-service-principal.ps1` | 调用 `pac admin create-service-principal` 生成应用注册，输出 Tenant ID / App ID / Client Secret |
| `assign-application-user.ps1` | 调用 `pac admin assign-user --application-user` 为服务主体逐环境授权 |
| `set-autonumber-seed.ps1` | **每次导入后执行**：核对并设置各环境自动编号列的 seed 值 |

## 为什么必须校验数据库

Power Platform 的解决方案式 ALM（`pac solution`、Power Platform Build Tools、GitHub Actions）**只支持带数据库的 Dataverse 环境**。

- 无数据库的环境无法导入包含表结构的解决方案；
- GitHub Actions 的环境连接会直接失败。

因此 S0 阶段的第一件事就是确认三者均已启用数据库，避免后续返工。

## 关于服务主体

- 认证方式选**服务主体 + 客户端密钥**（支持 MFA），不使用用户名/密码（不支持 MFA，且账号密码轮换会中断流水线）。
- 服务主体需要 `System administrator` 安全角色才能导入解决方案、创建表、发布自定义项。若企业安全策略不允许，需与平台管理员确认替代方案（至少需覆盖解决方案导入与自定义项发布权限）。
- 客户端密钥**有有效期**，需在过期前轮换并同步更新 GitHub Secrets，建议在 `alm-runbook.md` 中登记到期日。

## 关于自动编号 seed

Dataverse 自动编号列的 seed 值（起始序号）**不会随解决方案导入到其他环境**。

这意味着：即便 DEV 环境已经排到 `INC-2026-000156`，导入 TEST / PROD 后该环境的序号会**从默认值 1000 重新开始**。若不做处理，会导致不同环境产生相同的 Issue 编号。

处理方式见 [`docs/alm-runbook.md`](../../docs/alm-runbook.md)。同时注意：自动编号列**只能在新版 Power Apps 门户创建和调整**，经典解决方案资源管理器不支持。
