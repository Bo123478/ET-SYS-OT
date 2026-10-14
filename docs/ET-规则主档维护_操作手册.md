# ET 规则主档维护（类似主数据维护）

> 脚本：tools/Manage-ETRuleDraft.ps1
>
> 目标：规则改动走“草稿 -> 校验 -> 发布”三步，不直接手改服务器 JSON。

## 1. 新建规则草稿

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Manage-ETRuleDraft.ps1 -Action new -RuleSetName ET-FactoryA -Environment Prod
```

默认生成目录：
- `<DataRoot>\Temp\RuleDraft-ET-FactoryA-Prod`

文件：
- `ruleset.json`（规则集头）
- `scopes.json`（作用域）
- `rules.json`（规则明细）

## 2. 编辑草稿

按业务需求编辑 `rules.json`：
- `category`: `AppVersion | WindowsService | ComPort | HostMapping`
- `severity`: `Info | Warn | Alarm`
- `unknownPolicy`: `UnknownAsAlarm | UnknownAsWarn | Ignore`

## 3. 校验草稿

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Manage-ETRuleDraft.ps1 -Action validate -RuleSetName ET-FactoryA -Environment Prod
```

校验项：
- JSON 合法性
- 枚举值合法性
- `ruleCode` 唯一
- `scopeId` 引用完整
- `matcher/expected` 必填

## 4. 发布规则包

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Manage-ETRuleDraft.ps1 -Action publish -RuleSetName ET-FactoryA -Environment Prod -Version v2026.10.14.001
```

发布产物（服务器 ConfigRules 目录）：
- `versions/{version}/ruleset.json`
- `versions/{version}/meta.json`
- `versions/{version}/hash.sha256`
- `current.json`（当前版本指针）

## 5. 注意事项

- 发布前必须先 `validate`。
- 未配置 `Share.ConfigRulesRelative` 时会拒绝发布。
- 若共享路径不可达会拒绝发布（防止“半发布”）。
- 终端应仅消费 `current.json` 指向版本，不读草稿目录。
