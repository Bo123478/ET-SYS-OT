# ET 发布服务伪代码（Rule Publish Service）

> 目标：把后台“已审批规则”发布为终端可消费的版本化 JSON 包。

## 1. 输入与输出

- 输入：`ruleSetId`, `operator`, `environment`
- 输出：`PublishResult { success, version, artifactPath, hash, message }`

## 2. 目录约定（对接 ET 终端）

- `ConfigRules/current.json`
- `ConfigRules/versions/{version}/ruleset.json`
- `ConfigRules/versions/{version}/meta.json`
- `ConfigRules/versions/{version}/hash.sha256`

## 3. 发布主流程（伪代码）

```text
function PublishRuleSet(ruleSetId, operator, environment):
    begin transaction

    rs = db.RuleSet.get(ruleSetId)
    assert rs exists
    assert rs.Status in ['Approved', 'Published']

    scopes = db.RuleScope.listByRuleSet(ruleSetId, enabled=true)
    rules  = db.RuleItem.listByRuleSet(ruleSetId, enabled=true)

    validateSchema(rs, scopes, rules)
    validateConflict(scopes, rules)
    validateRequiredCategories(rules)

    version = buildVersion(rs, now)
    artifact = buildArtifact(rs, scopes, rules, version, environment)

    bytes = jsonSerializeCanonical(artifact)
    hash = sha256(bytes)

    versionDir = ConfigRules/versions/{version}
    writeFileAtomic(versionDir/ruleset.json, bytes)
    writeFileAtomic(versionDir/meta.json, toJson({
        version: version,
        ruleSetId: rs.RuleSetId,
        environment: environment,
        publishedAt: now,
        publishedBy: operator,
        ruleCount: len(rules),
        scopeCount: len(scopes)
    }))
    writeFileAtomic(versionDir/hash.sha256, hash)

    current = {
        version: version,
        artifact: "versions/{version}/ruleset.json",
        sha256: hash,
        publishedAt: now
    }

    writeFileAtomic(ConfigRules/current.json.tmp, toJson(current))
    renameAtomic(ConfigRules/current.json.tmp, ConfigRules/current.json)

    db.PublishRecord.insert({
        RuleSetId: rs.RuleSetId,
        Version: version,
        ArtifactPath: "ConfigRules/versions/" + version,
        ArtifactHash: hash,
        PreviousVersion: getPreviousPublishedVersion(environment),
        PublishedByName: operator,
        PublishedAt: now,
        Status: 'Success'
    })

    db.RuleSet.update(rs.RuleSetId, {
        Status: 'Published',
        Version: version,
        PublishedByName: operator,
        UpdatedAt: now
    })

    db.ChangeLog.insert({
        EntityName: 'RuleSet',
        EntityId: rs.RuleSetId,
        Action: 'Publish',
        BeforeJson: snapshotBefore,
        AfterJson: snapshotAfter,
        Actor: operator,
        OccurredAt: now
    })

    commit transaction
    return success(version, path, hash)

catch ex:
    rollback transaction
    db.PublishRecord.insert({
        RuleSetId: ruleSetId,
        Version: tryGet(version),
        ArtifactPath: tryGet(path),
        ArtifactHash: tryGet(hash),
        PublishedByName: operator,
        PublishedAt: now,
        Status: 'Failed',
        ErrorMessage: ex.message
    })
    return failure(ex.message)
```

## 4. 回滚流程（伪代码）

```text
function RollbackToVersion(targetVersion, operator, environment):
    assert versionExists(targetVersion)

    current = readJson(ConfigRules/current.json)
    prev = current.version

    targetMeta = readJson(ConfigRules/versions/{targetVersion}/meta.json)
    targetHash = readText(ConfigRules/versions/{targetVersion}/hash.sha256)

    writeFileAtomic(ConfigRules/current.json.tmp, toJson({
        version: targetVersion,
        artifact: "versions/{targetVersion}/ruleset.json",
        sha256: targetHash,
        publishedAt: now,
        rollbackFrom: prev
    }))
    renameAtomic(ConfigRules/current.json.tmp, ConfigRules/current.json)

    db.PublishRecord.insert({
        RuleSetId: targetMeta.ruleSetId,
        Version: targetVersion,
        ArtifactPath: "ConfigRules/versions/" + targetVersion,
        ArtifactHash: targetHash,
        PreviousVersion: prev,
        PublishedByName: operator,
        PublishedAt: now,
        Status: 'RolledBack'
    })

    db.ChangeLog.insert({
        EntityName: 'RuleSet',
        EntityId: targetMeta.ruleSetId,
        Action: 'Rollback',
        BeforeJson: {version: prev},
        AfterJson: {version: targetVersion},
        Actor: operator,
        OccurredAt: now
    })
```

## 5. 终端消费约束（发布服务必须保证）

- `current.json` 始终可读、可解析。
- 先写版本目录，再切换 current 指针。
- 任意失败不覆盖已有 `current.json`。
- 产物 hash 与 `current.json.sha256` 一致。

## 6. 建议 API

- `POST /api/rulesets/{id}/publish`
- `POST /api/rulesets/rollback`
- `GET /api/rulesets/{id}/diff?from=v1&to=v2`
- `GET /api/rulesets/published/current`
