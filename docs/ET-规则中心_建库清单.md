# ET 规则中心建库清单（Dataverse + SQL 对照）

> 目标：服务器端集中维护规则，不直接人工改 JSON。终端仅消费已发布版本。
>
> 对齐当前工程：
> - 终端评估入口：ETWorkbench/Modules/ET.Health.psm1
> - 主数据与快照：ETWorkbench/Modules/ET.MasterData.psm1
> - 路径契约：ETWorkbench/Config/paths.json（ConfigRules）

## 1. 领域模型（统一命名）

- `RuleSet`：规则集头（版本、状态、生效时间）
- `RuleScope`：规则作用域（工程/设备类型/厂区等）
- `RuleItem`：规则明细（版本/服务/COM/Host）
- `PublishRecord`：发布记录（产物路径、哈希、回滚链）
- `ChangeLog`：审计日志（谁在什么时候改了什么）

## 2. Dataverse 实体定义

### 2.1 et_ruleset（规则集）

| 字段逻辑名 | 显示名 | 类型 | 必填 | 说明 |
|---|---|---:|---:|---|
| `et_rulesetid` | 规则集ID | GUID(PK) | 是 | 主键 |
| `et_name` | 规则集名称 | Text(200) | 是 | 如 ET-FactoryA-RuleSet |
| `et_environment` | 环境 | Choice | 是 | Dev/Test/Prod |
| `et_status` | 状态 | Choice | 是 | Draft/Submitted/Approved/Published/Archived |
| `et_version` | 版本号 | Text(50) | 是 | 如 v2026.10.14.001 |
| `et_effectivefrom` | 生效时间 | DateTime | 否 | 发布后计划生效 |
| `et_description` | 说明 | Multiline | 否 | 变更说明 |
| `et_createdbyname` | 创建人 | Text(100) | 否 | 冗余审计字段 |
| `et_approvedbyname` | 审批人 | Text(100) | 否 | 冗余审计字段 |
| `et_publishedbyname` | 发布人 | Text(100) | 否 | 冗余审计字段 |
| `et_createdon` | 创建时间 | DateTime | 是 | 系统字段 |
| `et_modifiedon` | 修改时间 | DateTime | 是 | 系统字段 |

建议索引：
- `et_environment + et_status + et_version`（查询当前可发布版本）

### 2.2 et_rulescope（规则作用域）

| 字段逻辑名 | 显示名 | 类型 | 必填 | 说明 |
|---|---|---:|---:|---|
| `et_rulescopeid` | 作用域ID | GUID(PK) | 是 | 主键 |
| `et_rulesetid` | 所属规则集 | Lookup(et_ruleset) | 是 | 外键 |
| `et_projectcode` | 工程编码 | Text(50) | 否 | 如 FT |
| `et_equipmenttype` | 设备类型 | Text(50) | 否 | 如 PLC-Node |
| `et_plantcode` | 厂区编码 | Text(50) | 否 | 可空 |
| `et_appgroup` | 应用分组 | Text(50) | 否 | 生产软件/系统工具等 |
| `et_priority` | 优先级 | Whole Number | 是 | 数字越小优先级越高 |
| `et_enabled` | 启用 | Two Options | 是 | 默认 true |

建议索引：
- `et_rulesetid + et_projectcode + et_equipmenttype + et_priority`

### 2.3 et_ruleitem（规则明细）

| 字段逻辑名 | 显示名 | 类型 | 必填 | 说明 |
|---|---|---:|---:|---|
| `et_ruleitemid` | 规则ID | GUID(PK) | 是 | 主键 |
| `et_rulesetid` | 所属规则集 | Lookup(et_ruleset) | 是 | 外键 |
| `et_rulescopeid` | 所属作用域 | Lookup(et_rulescope) | 否 | 外键 |
| `et_rulecode` | 规则编码 | Text(80) | 是 | 如 FT-SVC-001 |
| `et_category` | 规则类别 | Choice | 是 | AppVersion/WindowsService/ComPort/HostMapping |
| `et_severity` | 严重级别 | Choice | 是 | Info/Warn/Alarm |
| `et_enabled` | 启用 | Two Options | 是 | 默认 true |
| `et_matcherjson` | 匹配条件 | Multiline(JSON) | 是 | 条件表达式 |
| `et_expectjson` | 期望值 | Multiline(JSON) | 是 | 期望声明 |
| `et_operator` | 比较操作符 | Text(30) | 是 | eq/in/regex/range/subset |
| `et_unknownpolicy` | 未知策略 | Choice | 是 | UnknownAsAlarm/UnknownAsWarn/Ignore |
| `et_messagetpl` | 提示模板 | Multiline | 否 | 告警文案模板 |
| `et_sortorder` | 排序 | Whole Number | 否 | 同范围内执行顺序 |

建议索引：
- `et_rulesetid + et_category + et_enabled`
- `et_rulecode` 唯一（建议）

### 2.4 et_publishrecord（发布记录）

| 字段逻辑名 | 显示名 | 类型 | 必填 | 说明 |
|---|---|---:|---:|---|
| `et_publishrecordid` | 发布记录ID | GUID(PK) | 是 | 主键 |
| `et_rulesetid` | 规则集 | Lookup(et_ruleset) | 是 | 外键 |
| `et_version` | 发布版本 | Text(50) | 是 | 与 RuleSet 版本一致 |
| `et_artifactpath` | 产物路径 | Text(500) | 是 | ConfigRules 下版本目录 |
| `et_artifacthash` | 产物哈希 | Text(128) | 是 | SHA256 |
| `et_previousversion` | 上一版本 | Text(50) | 否 | 回滚链 |
| `et_publishedbyname` | 发布人 | Text(100) | 是 | 操作人 |
| `et_publishedat` | 发布时间 | DateTime | 是 | 审计 |
| `et_status` | 结果 | Choice | 是 | Success/Failed/RolledBack |
| `et_error` | 错误信息 | Multiline | 否 | 发布失败原因 |

### 2.5 et_changelog（审计日志）

| 字段逻辑名 | 显示名 | 类型 | 必填 | 说明 |
|---|---|---:|---:|---|
| `et_changelogid` | 审计ID | GUID(PK) | 是 | 主键 |
| `et_entityname` | 实体名 | Text(80) | 是 | ruleset/rulescope/ruleitem/publishrecord |
| `et_entityid` | 实体主键 | Text(64) | 是 | GUID 文本 |
| `et_action` | 动作 | Choice | 是 | Create/Update/Delete/Submit/Approve/Publish/Rollback |
| `et_beforejson` | 变更前 | Multiline(JSON) | 否 | 审计快照 |
| `et_afterjson` | 变更后 | Multiline(JSON) | 否 | 审计快照 |
| `et_actor` | 操作人 | Text(100) | 是 | 审计 |
| `et_occurredat` | 发生时间 | DateTime | 是 | 审计 |

## 3. 规则类别 JSON 结构建议

### 3.1 应用版本（AppVersion）

```json
{
  "applicationId": "APP-FT-001",
  "allowedVersions": ["3.2.1", "3.2.2"],
  "requiredVersion": "3.2.2"
}
```

### 3.2 服务规则（WindowsService）

```json
{
  "services": [
    { "name": "MSSQLSERVER", "startupType": "Automatic", "state": "Running" },
    { "name": "Spooler", "startupType": "Automatic", "state": "Running" }
  ]
}
```

### 3.3 COM 口规则（ComPort）

```json
{
  "requiredCount": 3,
  "requiredPorts": ["COM3", "COM5", "COM8"],
  "allowExtra": true
}
```

### 3.4 Host 映射规则（HostMapping）

```json
{
  "entries": [
    { "host": "ft-api.local", "ip": "10.10.1.21" },
    { "host": "ft-db.local", "ip": "10.10.1.22" }
  ],
  "checkOnly": true
}
```

## 4. 发布产物目录规范（对接 ET 终端）

- `ConfigRules/current.json`：当前生效版本指针
- `ConfigRules/versions/v2026.10.14.001/ruleset.json`
- `ConfigRules/versions/v2026.10.14.001/hash.sha256`
- `ConfigRules/versions/v2026.10.14.001/meta.json`

`current.json` 示例：

```json
{
  "version": "v2026.10.14.001",
  "artifact": "versions/v2026.10.14.001/ruleset.json",
  "sha256": "...",
  "publishedAt": "2026-10-14T15:00:00+08:00"
}
```

## 5. 运维规则（必须）

- 人员不直接改服务器 JSON；只在管理后台改 RuleSet/RuleItem。
- 发布前必须通过：schema 校验、冲突校验、样例终端回放。
- 发布采用“版本目录 + current 原子切换”。
- 回滚只切 current 指针，不回写历史版本内容。
