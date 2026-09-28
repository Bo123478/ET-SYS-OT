# 部署设置（DeploymentSettings）

本目录存放各环境的**部署设置文件**，用于在导入解决方案时注入环境变量值。**当前仅有说明，实际文件待 S7 阶段创建。**

## 为什么需要这个目录

解决方案中只应包含环境变量的**定义**，不应包含**值**。原因：

- 解决方案需要在 DEV → TEST → PROD 之间流转，若把 DEV 的 Teams 频道 ID、SharePoint 站点地址打包进去，PROD 会继承错误的值；
- 每次导入时用 `--settings-file` 指定对应环境的值，即可在同一个解决方案上适配不同环境。

## 计划中的文件

| 文件 | 目标环境 | 用途 |
|---|---|---|
| `dev.json` | DEV | 开发环境的环境变量值 |
| `test.json` | TEST | 测试环境的环境变量值 |
| `prod.json` | PROD | 生产环境的环境变量值 |

生成方式（在解决方案工程目录执行）：

```text
pac solution create-settings --solution-zip <解决方案包> --settings-file DeploymentSettings/<env>.json
```

生成的 JSON 为骨架，需人工填入各环境的实际值后再用于导入。

## 需要注入的环境变量

| 逻辑名 | 类型 | 说明 | 是否含敏感信息 |
|---|---|---|---|
| `TeamsGroupId` | Text | Teams 团队 ID | 否，但不应跨环境复用 |
| `TeamsChannelId` | Text | 默认通知频道（`01-新问题受理`）ID | 否 |
| `AdminNotificationChannelId` | Text | 流程失败告警频道（`03-Power Platform`）ID | 否 |
| `SharePointSiteRootUrl` | Text | SharePoint 站点根地址 | 否 |
| `EvidenceLibraryName` | Text | 证据文档库名（`IssueEvidence`） | 否 |
| `LogPackageLibraryName` | Text | 日志包文档库名（`LogPackages`） | 否 |
| `PortalUrl` | Text | 应用门户地址，用于 Teams 卡片深链 | 否 |
| `DefaultEnvironment` | Text | 默认环境标识（DEV/TEST/UAT/PROD） | 否 |
| `IntakeFormId` | Text | 问题反馈表单 ID | 否 |

> `DefaultEnvironment` 是自定义环境变量，与系统保留项无关；不要使用 `$authentication`、`$connection` 作为环境变量名，这两个是保留名，被占用会导致流程无法保存。

## 连接引用

以下连接引用随解决方案部署，但**每个环境需要重新绑定连接**（首次导入后手工完成）：

| 连接引用 | 说明 |
|---|---|
| Dataverse | 当前环境自身的连接，通常导入后自动绑定 |
| Microsoft Teams | 需在目标环境重新授权 |
| SharePoint | 需在目标环境重新授权 |
| Office 365 Outlook | 邮件通知用，需重新授权 |

## 注意

- 本目录下**禁止提交**含真实环境值的文件（除模板外）。`.gitignore` 已配置忽略 `*.local.json` 与 `*.secrets.json`。
- 若某环境变量未来改为承载敏感值（如连接字符串），应改用 **Secret 类型**并接入 Azure Key Vault，而非明文写入设置文件。
- 环境变量值的传播是**异步**的，导入后可能需等待一段时间才在流程中生效。
