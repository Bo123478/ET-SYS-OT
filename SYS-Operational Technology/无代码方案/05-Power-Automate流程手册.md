# 05 Power Automate 流程手册

> **本手册把 [`../docs/Phase1-实施方案.md`](../docs/Phase1-实施方案.md) §13 的流程设计与设计稿 §13 的 SLA / 防循环规则，翻译成 `make.powerautomate.com` 里的逐步点击操作。**
>
> **执行阶段：S4（与 `04` 并行）。** 前置条件是 S2 表结构完成、S3 权限完成（**流程专用角色已建**）。
>
> ⚠️ **本手册是全套文档里最长的一本。** 建议按流程编号逐个做，**做完一条测一条**，不要一次做完再统一测。
>
> ⚠️ **无代码方案下本手册与代码方案最大的差异**：`Phase1-实施方案.md` 假设用 `.cdsproj` + `pac` 注入环境变量；**本方案全部改为门户手工填写**（§11）。

---

## 0. 开始前必读

### 0.1 流程清单

| 编号 | 流程名 | 类型 | 触发方式 | 本手册章节 | 优先级 |
|---|---|---|---|---|---|
| **FL-01** | **表单建单** | 自动化云流 | Forms 新响应 | [`04` §4](04-问题入口手册.md) | ⭐ **最高（已做）** |
| **FL-02** | **问题创建通知** | 自动化云流 | Dataverse 行新增 | §3 | ⭐ 高 |
| **FL-03** | **状态变更通知** | 自动化云流 | Dataverse 行更新 | §4 | ⭐ 高 |
| **FL-04** | **SLA 扫描与升级** | **计划云流** | 定时（每小时） | §5 | ⭐ 高 |
| **FL-05** | **关闭确认** | 自动化云流（含审批） | 状态变更为 `Monitoring` | §6 | 中 |
| **FL-06** | **发布审批** | 自动化云流（含审批） | `发布记录` 行新增 | §7 | 中（Phase 2 强化） |
| **FL-07** | **日志包登记** | 自动化云流 | SharePoint 文件创建 | [`06` §5](06-附件与日志采集手册.md) | 中 |
| **FL-08** | **流程失败预警** | 自动化云流 | 子流程 / HTTP | §9 | 低但建议做 |

> ⚠️ **编号 FL-01…FL-08 是本方案自行编排的，设计稿 §13 只给了 4 个中文流程名，没有编号。**
> **本手册的编号在 `00`–`10` 各文档中保持一致**，用于相互引用。

### 0.2 ⚠️ 三条铁律（每条都对应一类真实故障）

| # | 铁律 | 违反的后果 |
|---|---|---|
| **1** | **所有流程必须建在 `SysOpsStandard` 解决方案内**（**不是**"我的流程"） | 建在"我的流程"里的流程**不随解决方案导出**，迁移时全部丢失 |
| **2** | **所有流程必须实现防循环**（§8） | 流程 A 改状态 → 触发流程 B → 流程 B 又改状态 → 触发流程 A → **无限循环，一夜烧掉几万次运行** |
| **3** | **没有任何硬编码**（频道 ID / 站点 URL / 表单 ID 全部走环境变量） | 迁移到 TEST/PROD 后，通知发到 DEV 的频道，**且不报错** |

### 0.3 ⚠️ 关于连接账号（`03` §3.8 的延续）

**流程以"连接拥有者"的身份运行。** 这带来三个必须在 S4 处理的问题：

| 问题 | 处理 |
|---|---|
| 拥有者离职 → 流程静默停跑 | §12 的交接清单 |
| 拥有者权限不足 → 流程动作失败 | `03` §3.8 的流程专用角色 |
| 审计日志里是"个人账号在改记录" | §4.6 的 `变更人` 字段设计（用"报告人/操作人"而非流程账号） |

> ⚠️ **建流程之前，先确认 §12.1 的"流程拥有者登记表"已经建好，并且拥有者人选已定。**
> **不要**先用自己账号建好流程、以后再改拥有者 —— **改拥有者需要重建连接，很麻烦**。

### 0.4 执行顺序

```
§1   环境变量与连接引用（先做这个）
§2   通用流程设置（并发、重试、超时）
§3   FL-02 问题创建通知
§4   FL-03 状态变更通知（含合法迁移表）
§5   FL-04 SLA 扫描与升级
§6   FL-05 关闭确认
§7   FL-06 发布审批
§8   防循环规则（五条铁律）
§9   FL-08 流程失败预警
§10  WBS 与工时
§11  环境变量的手工注入（无代码方案的关键差异）
§12  运维：拥有者登记与交接
§13  S4 出口检查表
```

---

## 1. 环境变量与连接引用

> ⚠️ **必须先做本章。** 环境变量要在流程之前建好，否则流程里填的 Dynamic content 引用会绑到错误的东西。

### 1.1 环境变量清单（9 个）

来源：[`../docs/Phase1-实施方案.md`](../docs/Phase1-实施方案.md) §11.1。

| # | 逻辑名（Logical name） | 类型 | 显示名 | 值示例 |
|---|---|---|---|---|
| 1 | `TeamsGroupId` | Text | Teams 团队 ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| 2 | `TeamsChannelId` | Text | 默认通知频道 | `19:xxxxx@thread.tacv2` |
| 3 | `AdminNotificationChannelId` | Text | 告警频道 | `19:yyyyy@thread.tacv2` |
| 4 | `SharePointSiteRootUrl` | Text | SharePoint 站点根地址 | `https://<租户>.sharepoint.com/sites/SysOps` |
| 5 | `EvidenceLibraryName` | Text | 证据文档库名 | `IssueEvidence` |
| 6 | `LogPackageLibraryName` | Text | 日志包文档库名 | `LogPackages` |
| 7 | `PortalUrl` | Text | 应用门户地址 | `https://org.crm5.dynamics.com` |
| 8 | `DefaultEnvironment` | Text | 默认环境标识 | `DEV` / `TEST` / `PROD` |
| 9 | `IntakeFormId` | Text | 问题反馈表单 ID | 表单的 GUID |

> ⚠️ **不要用保留名**。`$authentication`、`$connection` **不能**作为环境变量名，**被占用会导致流程保存失败且报错不明确**（`Phase1-实施方案.md` §11.4）。

### 1.2 ⚠️ 特殊说明：`IntakeFormId` 在本方案里的地位变了

**代码方案的做法**：Form ID 走环境变量，在导入时注入。
**本方案的做法**：⚠️ **不能这样做**。

**原因**（`Phase1-实施方案.md` §9 已论证）：

> `Forms 新响应` 触发器的**表单选择器是下拉控件**，**无法用环境变量传递 Form ID**。
> 把它放进解决方案会产生"导入后必须手工重新选择表单"的配置项，而这类手工步骤无法被流水线自动化，**反而制造脆弱点**。

**本方案的处理**：

| 项 | 做法 |
|---|---|
| `IntakeFormId` 环境变量 | **仍然创建**（保持与其他环境变量一致的命名） |
| **但 FL-01 的触发器不引用它** | FL-01 的 Form Id 是**在设计器里手工选的**（`04` §4.2） |
| 用途 | 仅作为**文档/记录**用途（记录每个环境的 Form ID，便于 `09` 迁移时核对） |
| ⚠️ 迁移时 | **必须手工重选表单**（写进 `09` 手册的迁移清单） |

> ⚠️ **这就是 `04` §1.4 讲的"Forms 不随解决方案迁移"在流程层的表现。** 两处要一起记住。

### 1.3 创建环境变量的步骤

1. `make.powerapps.com` → 确认环境 = **`SysOps-DEV`**
2. 左侧 **Solutions** → 打开 **`SysOpsStandard`**
3. 左侧 **Objects** 树 → **+ New** → **More** → **Environment variable**
4. 逐项填写：

| 字段 | 填什么 |
|---|---|
| **Display name** | 中文名（如 `Teams 团队 ID`） |
| **Name** | **逻辑名**（如 `TeamsGroupId`）。⚠️ **前缀会自动加，不要手打 `bjops_`** |
| **Data type** | **Text**（本方案 9 个全是 Text） |
| **Default value** | **DEV 环境的值** |
| **Current value** | 留空（或将 `Default value` 设为当前值） |

5. **Save**

> ⚠️ **`Default value` 与 `Current value` 的区别**：
> - **Default value** 会**随解决方案导出**（也就是说，从 DEV 导出时会带着 DEV 的值）
> - **Current value** **不会导出**，它在目标环境里是空的，需要重新设置
>
> **本方案的建议**：
> - **`Default value` 填一个明显的占位值**（如 `TODO-CHANGE-IN-TARGET-ENV`），这样**导错环境会立刻暴露**
> - **`Current value` 填本环境的真实值**
> - 使用流程时，流程会**优先读 Current value**，没有再读 Default value
>
> ⚠️ **若把真实值填在 Default value 里**：迁移到 PROD 后，**PROD 的流程会用 DEV 的频道 ID 发通知**（因为 Current value 是空的，回退到 Default），**而且不会报错**——只是通知发到了错误的地方。

**⚠️ 一个必须解释的差异**：Power Automate 流程在使用环境变量时，**实际读取的是"当前值（Current value）"，没有当前值时会回退到"默认值（Default value）"**。
→ 所以上面的建议是：**默认值 = 占位符，当前值 = 真实值。**
→ **迁移后如果忘了设当前值，流程会用占位符，至少在告警里能看到 `TODO-CHANGE-IN-TARGET-ENV` 这个明显的字符串**（比"发到错误频道"好得多）。

### 1.4 ⚠️ 关于 SharePoint 数据源型环境变量的一个坑

`Phase1-实施方案.md` §11.4 提到：

> SharePoint 数据源型环境变量要求**显示名与逻辑名一致**，否则跨环境绑定失败。

**本方案的处理**：**9 个环境变量全部用 Text 类型**，**不用 SharePoint 数据源类型**。
→ 因为 Text 类型**没有这个约束**，迁移更稳。
→ 代价：**SharePoint 的站点/文档库要在流程里用 Text 拼路径**（而不是用类型化的数据源选择器）。
→ **本方案接受这个代价**，理由是"稳"胜过"编辑时的自动补全"。

### 1.5 连接引用（6 个）

**解决方案里的"连接引用"（Connection reference）用来把流程与具体连接解耦。**

| # | 连接引用 | 本方案用在哪 | 迁移时 |
|---|---|---|---|
| 1 | **Dataverse** | FL-01…FL-08 | ✅ **通常自动绑定**（自引用本环境） |
| 2 | **Microsoft Teams** | FL-02 / FL-03 / FL-04 | ⚠️ **必须重新授权** |
| 3 | **SharePoint** | FL-02 / FL-07 | ⚠️ **必须重新授权** |
| 4 | **Office 365 Outlook** | FL-03 / FL-04 / FL-05 | ⚠️ **必须重新授权** |
| 5 | **Microsoft Forms** | FL-01 | ⚠️ **必须重新授权** |
| 6 | **Approvals** | FL-05 / FL-06 | ⚠️ **必须重新授权** |

**创建连接引用的步骤**：

1. 解决方案 → **+ New** → **More** → **Connection reference**
2. **Display name** 填中文，**Name** 填英文（如 `cr_Dataverse`）
3. **Connector** 选对应的连接器
4. **Connection** 选一个已存在的连接（**若还没有，先建一个**）
5. **Save**

> ⚠️ **"重新授权"是什么意思**：迁移到新环境后，**连接引用存在，但它指向的连接是空的或无效的**。
> **表现**：流程能打开，但每个动作上有一个红色的警告三角，提示"连接无效"。
> **处理**：在**解决方案**里找到该连接引用，点 **+ Add connection**，用**该环境的流程账号**登录授权。
>
> **这个动作是 `09` 手册迁移清单的必做项。** 忘做的后果：**流程静默失败**（有些连接失效时，流程会直接进入失败，但**没有人看失败列表**）。

### 1.6 连接引用的自检

- [ ] 9 个环境变量已创建，**默认值是 `TODO-CHANGE-IN-TARGET-ENV`**（占位）
- [ ] **当前值已填 DEV 的真实值**
- [ ] 6 个连接引用已创建
- [ ] 每个连接引用都已**绑定一个有效连接**
- [ ] ⚠️ **没有使用 `$authentication` / `$connection` 作为环境变量名**
- [ ] `IntakeFormId` 已建，且已记录 DEV 环境的 Form ID

---

## 2. 通用流程设置（每条流程都要做）

> ⚠️ **把这些设置做成"模板"，每条流程建完后立刻配。**

**位置**：流程设计器右上角 **⋯** → **Settings**

| 设置项 | 值 | 理由 |
|---|---|---|
| **Concurrency control** | ✅ **打开**，**Degree of parallelism = 1** | 防并发导致的重复处理 |
| **Timeout duration** | `PT2H`（2 小时） | 默认可能是 30 天；**短超时能更快发现卡死** |
| **Retry Policy** | **默认**（4 次，指数退避） | ⚠️ **不要关**。Dataverse 偶发限流靠重试救回来 |
| **Secure Inputs** | ❌ 不勾 | 本方案的数据不是密钥 |
| **Secure Outputs** | ❌ 不勾 | 同上（勾了会导致无法在运行历史里看输出，**排查困难**） |

> ⚠️ **关于超时**：计划流程（FL-04）的超时**不要设 2 小时**——它每小时跑一次，**超时应该短于运行间隔**（例如 `PT50M`），否则会**堆积重叠运行**。

### 2.1 ⚠️ 每条流程都要加"防循环"的前置条件

**见 §8。** 简单说：**每条"由 Dataverse 行更新触发"的流程，第一步必须检查"是不是自己改的"。**

### 2.2 流程命名规范

| 项 | 规范 |
|---|---|
| **显示名** | `FL-XX <中文名>`，如 `FL-02 问题创建通知` |
| **说明（Description）** | 写清：**触发条件、做什么、依赖哪些环境变量、防循环方式** |

> ⚠️ **必须写说明。** 半年后接手的人（可能是你自己）**第一件事就是看说明**。
> **建议的说明模板**：
> ```
> 触发：Dataverse 问题表 行新增
> 作用：向 Teams 频道发 Adaptive Card，并通知报告人（若配了邮箱）
> 依赖环境变量：TeamsGroupId, TeamsChannelId, PortalUrl
> 防循环：本流程只读不写 Dataverse，无循环风险
> ```

---

## 3. FL-02 问题创建通知

### 3.1 目标

问题单创建后，向 Teams 频道发一张 **Adaptive Card**（含关键字段和"查看详情"深链），**同时**给报告人发一条一对一消息（让他拿到编号）。

> ⚠️ **为什么要给报告人单独发**：`04` §2.11 已说明——**Forms 的感谢页是静态的，显示不出编号**。
> 用户提交完只知道"成功了"，不知道编号。**没有编号，他在 Teams 里问"我那个问题怎么样了"时，运维无法定位。**

### 3.2 步骤 1：触发器

1. `make.powerautomate.com` → 环境 = **`SysOps-DEV`**
2. **Solutions** → `SysOpsStandard` → **+ New** → **Automation** → **Cloud flow**
3. **Flow name**：`FL-02 问题创建通知`
4. 触发器搜 `Dataverse` → 选 **When a row is added, modified or deleted**
5. 配置触发器：

| 字段 | 值 |
|---|---|
| **Change type** | **Added**（⚠️ **只选 Added，不要选 Modified**，否则会和 FL-03 冲突） |
| **Table name** | `问题` |
| **Scope** | **Organization**（或 `Business Unit`） |
| **Select columns** | **留空**（⚠️ **填了只是优化性能，填错会导致字段取不到值，得不偿失**） |
| **Filter rows** | **留空**（⚠️ 不要在这里过滤，见下） |
| **Filter columns (with trigger conditions)** | **留空** |

> ⚠️ **关于 Filter rows 的两个注意点**：
>
> **① 不要用 Filter rows 过滤 `bjops_automationupdate`**。看起来合理（"流程创建的不通知"），但：
> - Filter rows 用的是 **Dataverse 查询语法**，**不是 OData**
> - 用 `bjops_status eq 1` 这种写法时，**选项集要填数值**，填显示名不生效
> - **最稳的做法是在流程内用 Condition 判断**（§8）
>
> **② 真正的性能优化手段是"Trigger condition"**（触发器设置里的 **Settings → Trigger conditions**），语法是 **表达式**，例如：
> ```
> @equals(triggerOutputs()?['body/bjops_automationupdate'], false)
> ```
> **本方案建议：不用 Trigger condition，全部在流程内用 Condition 判断。** 理由：**流程内判断看得见、好排查、好加日志**；Trigger condition 不满足时**流程根本不运行，从运行历史里看不出"为什么没跑"**。

6. **+ New step**

### 3.3 步骤 2：防循环判断

1. **+ New step** → **Condition**
2. 左值：**Dynamic content** → 触发器里的 **自动化更新**（`bjops_automationupdate`）
3. 运算符：**is equal to**，右值：`否`（或 `false`）
   > ⚠️ **两选项列（Yes/No）在流程里的值是布尔值 `true`/`false`**。若下拉里没有，用 **Enter custom value** 填表达式 `false`。
4. **If no** 分支 → **+ Add an action** → **Terminate** → **Status = Succeeded**

> ⚠️ **注意 FL-02 的实际风险很低**（它只读不写 Dataverse），**但这里仍然加上判断**，理由：
> 1. **一致性**：所有流程用同一套防护模式，**不容易漏**
> 2. **FL-01 建单时会短暂写入 `bjops_automationupdate = 否`**，所以这里判断 `否` 是通过的
> 3. 将来若 FL-02 增加了"回写 `bjops_notifiedtime`"这类动作，**防护就已经在了**

### 3.4 ⚠️ 步骤 3：深链的构造

**Teams 卡片上的"查看详情"按钮需要一个可点击的 URL。**

**两种深链格式**（`intake-forms.md` §4.5）：

| 场景 | 格式 |
|---|---|
| **模型驱动应用** | `{PortalUrl}/main.aspx?appid={AppId}&pagetype=entityrecord&etn=bjops_issue&id={IssueGUID}` |
| **Canvas App** | 用 Canvas App 的专用深链格式（在应用设置里能找到 **Web link** / **App ID**） |

**本方案的建议**：

```
{PortalUrl}  →  从环境变量 Dynamic content 取
{AppId}      →  ⚠️ 目前没有对应的环境变量 → 三个选择，见下
```

| 方案 | 做法 | 评价 |
|---|---|---|
| **A（推荐）** | **再建一个环境变量 `ModelDrivenAppId`** | ✅ 最干净。**但要记得同步更新 `附录A` 的环境变量清单** |
| B | 用**模型驱动应用的 Web 地址**（不需要 appid） | ⚠️ 有些版本不支持不带 appid 的实体深链 |
| C | 把 appid 硬编码 | ❌ **违反铁律 3**。迁移后会指向错误的应用 |

> **本手册采用方案 A。** 请补建环境变量 **`ModelDrivenAppId`**（Text 类型），并**在 `附录A` 与 `09` 手册的迁移清单里加上它**。
>
> ⚠️ **这是一个本方案对 `Phase1-实施方案.md` §11.1 的补充**（原清单 9 项里没有它）。**原清单的 9 项在模型驱动应用场景下不够用。**

**深链的构造方式（在 Compose 里拼）**：

1. **+ New step** → **Compose**
2. **Inputs** 填：

```
concat(
  variables('PortalUrl'),
  '/main.aspx?appid=',
  variables('ModelDrivenAppId'),
  '&pagetype=entityrecord&etn=bjops_issue&id=',
  triggerOutputs()?['body/bjops_issueid']
)
```

3. **⋯** → **Rename** → `DeepLink`

> ⚠️ **环境变量在流程里的引用方式**：在 Dynamic content 面板里，环境变量**不会出现在常规列表里**，**要展开 "Environment variables" 分组**，或者用表达式 `parameters('TeamsChannelId')`（用逻辑名）。
> ⚠️ **若 Dynamic content 里找不到环境变量**：说明该环境变量**还没被加到当前流程所属的解决方案里**，或者**你不在解决方案上下文里编辑流程**（这是"必须建在解决方案内"的又一个理由）。

### 3.5 步骤 4：发 Teams 频道消息（Adaptive Card）

1. **+ New step** → 搜 `Teams` → 选 **Post card in a chat or channel**
2. 配置：

| 字段 | 值 |
|---|---|
| **Post as** | **Flow bot** |
| **Post in** | **Channel** |
| **Team** | ⚠️ **不能用环境变量的 GUID**（这个字段是下拉选择器）→ 见下 |
| **Channel** | ⚠️ 同上 |
| **Adaptive Card** | 粘 §3.6 的 JSON |

> ⚠️ **⚠️⚠️ 这是本手册最容易踩的一个"环境变量失效"陷阱。**
>
> `Post card in a chat or channel` 动作的 **Team** 和 **Channel** 字段是**类型化的下拉选择器**，**它不接受环境变量**（不放 Dynamic content）。
>
> | 处理方式 | 评价 |
> |---|---|
> | **A（本手册采用）** | **用连接器里支持动态值的替代动作**：搜 Teams → **Post message in a chat or channel**（这个动作的 Team/Channel 也可能同样是选择器） |
> | **B** | **改用"发送 HTTP 请求到 Teams Webhook"** | ⚠️ 引入 Webhook 管理成本；但**完全无代码可控** |
> | **C** | **接受"Team/Channel 字段手工选"**，并**把这一步写进 `09` 手册的迁移清单** | ✅ **最简单、最可靠** |
>
> **本手册采用方案 C**：**Team 与 Channel 在设计器里手工选**，**迁移时手工重选**（写进 `09` 迁移清单）。
> → 这也意味着 **`TeamsGroupId` / `TeamsChannelId` 两个环境变量在这个动作里用不上**。
> → **它们仍然保留**，用于：① 记录每个环境的 ID（便于人工核对）；② 若将来改用 HTTP/Webhook 方式发消息，就要用它们。
>
> ⚠️ **这个事实必须写进 `09` 手册**：**"Teams 消息动作的 Team/Channel 字段在迁移后必须手工重选"**。忘做的后果：**PROD 的流程把通知发到 DEV 的频道**（或者更糟：因为找不到目标而**静默失败**）。

3. **Post as**：选 **Flow bot**
4. **Adaptive Card**：点字段 → 粘 §3.6 的 JSON

### 3.6 Adaptive Card JSON（可直接粘贴）

**注意：粘贴后要把里面的 `<...>` 占位符替换成 Dynamic content。**

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "size": "Large",
      "weight": "Bolder",
      "text": "🐞 新问题：${IssueNumber}" ,
      "wrap": true
    },
    {
      "type": "TextBlock",
      "size": "Medium",
      "weight": "Bolder",
      "color": "${SeverityColor}",
      "text": "${Severity}",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "标题", "value": "${Title}" },
        { "title": "应用", "value": "${Application}" },
        { "title": "设备", "value": "${Equipment}" },
        { "title": "生产线", "value": "${ProductionLine}" },
        { "title": "环境", "value": "${Environment}" },
        { "title": "类型", "value": "${IssueType}" },
        { "title": "分类", "value": "${Category}" },
        { "title": "状态", "value": "${Status}" },
        { "title": "报告人", "value": "${Reporter}" },
        { "title": "报告时间", "value": "${ReportedOn}" },
        { "title": "SLA 截止", "value": "${SlaDeadline}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "**影响范围**",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "${ImpactScope}",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "**已采取的临时措施**",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "${TemporaryMeasure}",
      "wrap": true
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "查看详情",
      "url": "${DeepLink}"
    }
  ]
}
```

**粘贴后要做的事**：

1. 把 `${IssueNumber}` 替换为 **Dynamic content** 里的 **问题编号**
2. 把 `${Title}` 替换为 **标题**
3. ……逐个替换
4. ⚠️ **`${SeverityColor}` 需要手工判断**：Adaptive Card 的颜色只能是 `Good` / `Warning` / `Attention` / `Default`。
   → **做法**：用一个 **Compose** 动作算出颜色字符串（用 `if()` 表达式），然后引用它。
   → 或者**简单一点：不用颜色**，把 `"color"` 这一行删掉。

**颜色映射建议**（若要用）：

| 严重度 | 颜色 |
|---|---|
| Critical | `Attention`（红） |
| High | `Warning`（黄） |
| Medium | `Default` |
| Low | `Default` |

> ⚠️ **关于 `${}` 语法**：Teams 的 **"Post card in a chat or channel"** 动作支持 `${...}` 占位符（这是 Adaptive Card 的 **templating** 语法）。
> **如果你粘进去发现 `${}` 没被替换**：说明这个动作**不支持 templating**，需要改用 **`Compose` 拼好整个 JSON**，再用 **`Post your own adaptive card as the Flow bot to a channel`** 动作（这个动作的输入是**纯 JSON 字符串**）。
>
> **排查方法**：卡片发出来后，若 FactSet 的值显示为字面的 `${Title}`，**就说明 templating 没生效**，改用 Compose 方案。

### 3.7 ⚠️ 步骤 5：通知报告人（拿到编号）

**目标**：让提交人知道自己问题的**编号**。

**方案对比**：

| 方案 | 动作 | 评价 |
|---|---|---|
| **A（推荐）** | **Teams 一对一消息**：`Post message in a chat or channel`，**Post as = Flow bot**，**Post in = Chat with Flow bot**，**Recipient = 报告人邮箱** | ✅ 用户最熟悉；能直接回复 |
| B | **发邮件**（Office 365 Outlook → Send an email） | ✅ 更正式；但现场人员未必看邮件 |
| C | 两者都发 | ⚠️ 会让人烦 |

**本手册采用方案 A（Teams 一对一）**，配置：

| 字段 | 值 |
|---|---|
| **Post as** | **Flow bot** |
| **Post in** | **Chat with Flow bot** |
| **Recipient** | **Dynamic content** → 报告人邮箱（`bjops_reporteremail`） |
| **Message** | 见下 |

**消息内容**：

```
您提交的问题已受理 ✅

编号：<问题编号>
标题：<标题>
严重度：<严重度>
当前状态：新建，待受理

运维团队会在 SLA 时间内跟进。
如需补充截图或日志，请发送到 Teams 频道「02-设备与客户端」并注明编号。

⚠️ 请不要重复提交同一问题。
```

> ⚠️ **⚠️ 这一步有一个必须处理的失败场景**：**`Recipient` 是"报告人邮箱"，但如果用户填的是个人邮箱（非组织账号），Teams 会报错**。
>
> **处理（必须做）**：
> 1. 把这一步放进一个 **Scope**
> 2. 该 Scope 的 **Configure run after** 勾 `has failed` → 加一个 **Compose** 记录失败，**不要中断整个流程**
> 3. ⚠️ **不要因为"给报告人发消息失败"而让整个通知流程失败** —— 频道通知（§3.5）已经成功了，**运维该知道的已经知道了**
>
> **FL-01 里已经做过邮箱匹配检查**（`04` §4.5.3）。若那里已经告警，这里失败是**预期内**的。

### 3.8 ⚠️ 步骤 6：回写"已通知时间"

**为什么要回写**：`10` 手册的日常检查里要统计"通知成功率"。没有时间戳就统计不了。

1. **+ New step** → **Update a row**（Dataverse）
2. **Table name**：`问题`
3. **Row ID**：触发器的记录 ID
4. **已通知时间**（`bjops_notifiedtime`）：`utcNow()`
   > ⚠️ **若 `02` 手册里没有建这一列**，请补建（单行文本或日期时间）。
   > **本方案建议用"日期时间（用户本地时间）"类型**，与其他时间列一致（`02` §9）。
5. ⚠️ **不要改 `bjops_automationupdate`**！

> ⚠️ **这个"回写"动作会让 FL-02 自己触发 `Modified` 事件。**
> → 因为 FL-02 的触发器是 **Added only**，所以**不会**再次触发 FL-02。
> → 但**会触发 FL-03**（它的触发器是 Modified）！
> → **所以 FL-03 必须有防循环判断**（§8）。**这是本方案里最容易形成循环的位置。**

### 3.9 FL-02 自检

- [ ] 流程建在 **`SysOpsStandard`** 内
- [ ] 触发器 **Change type = Added only**
- [ ] **未使用 Filter rows / Trigger condition** 过滤（改用流程内 Condition）
- [ ] 防循环 Condition 已加，**Terminate 用 Succeeded**
- [ ] **`ModelDrivenAppId` 环境变量已补建**
- [ ] 深链用 `Compose` 拼接，**没有硬编码**
- [ ] Teams 频道动作的 **Team / Channel 是手工选的**，且**已记录待迁移时重选**
- [ ] Adaptive Card JSON 已粘贴，**`${}` 占位符已全部替换**（或改用 Compose 方案）
- [ ] **报告人通知已包在 Scope 里，失败不中断**
- [ ] `bjops_notifiedtime` 已回写
- [ ] **Settings：并发度 = 1，超时 = PT2H，重试 = 默认**
- [ ] **流程说明（Description）已写**

---

## 4. FL-03 状态变更通知（含合法迁移校验）

> ⚠️ **这是本手册最复杂的一条流程。** 它同时要做三件事：**校验状态迁移合法性**、**写历史表**、**发通知**。

### 4.1 目标

| # | 做什么 | 为什么 |
|---|---|---|
| 1 | **校验状态迁移是否合法** | 防止用户（或流程）跳到非法状态，破坏状态机 |
| 2 | **写一条 `bjops_issuehistory`** | 设计稿 §11.1 要求所有状态变更留痕 |
| 3 | **发通知** | 状态变了要让相关的人知道 |
| 4 | ⚠️ **防止自己触发自己** | 因为写历史表/回写会再次触发 Modified 事件 |

### 4.2 ⚠️ 合法的状态迁移表（来自 `../docs/data-dictionary.md` §2.6）

**这 14 个状态 + 迁移关系是"唯一真相"。流程与 Canvas App 都按它实现。**

| 当前状态 | 合法的下一个状态 |
|---|---|
| `New` | `Triaged` / `Rejected` |
| `Triaged` | `Assigned` |
| `Assigned` | `Analyzing` |
| `Analyzing` | `WaitingForInfo` / `Fixing` |
| `WaitingForInfo` | `Analyzing` |
| `Fixing` | `ReadyForTest` |
| `ReadyForTest` | `Testing` |
| `Testing` | `Fixing`（失败）/ `ReadyForRelease`（通过） |
| `ReadyForRelease` | `Released` |
| `Released` | `Monitoring` |
| `Monitoring` | `Closed`（确认）/ `Reopened`（复发） |
| `Reopened` | `Analyzing` |
| `Closed` | —（终态） |
| `Rejected` | —（终态） |

> ⚠️ **这 14 个取值被四处引用**：选项集定义、状态机设计、视图筛选条件、流程条件分支。
> **任一处拼写不一致都会导致静默失效**——流程不报错，但分支不进，**且难以排查**（`data-dictionary.md` §2.6 的警告）。
>
> ⚠️ **流程里的实现方式**：**选项集在 Dataverse 里是数值**（1–14）。所以流程里的比较**要么用数值，要么用显示名**，**必须全流程统一**。
> **本手册建议：用显示名**（可读性好，排查方便）。**前提是流程里的值是从 Dynamic content 里"选"出来的，不是手打的。**

### 4.3 ⚠️ 在无代码方案里怎么实现"迁移校验"

**Dataverse 的业务规则做不到这件事**（`02` §12.4 的限制里包括"业务规则无法做跨状态的迁移校验"）。**只能在流程里做。**

**实现方式（用条件分支树）**：

```
┌─ 触发器（Dataverse，Modified，表 = 问题）─┐
│                                          │
│  ① 防循环判断（§8）                       │
│     automationupdate = 否 ?              │
│     ↓ 是                                  │
│  ② 状态是否真的变了？                     │
│     bjops_status != 上一步的 bjops_status │
│     ↓ 是                                  │
│  ③ 合法迁移校验（switch / 14 个 Condition）│
│     ├─ 合法 → ④⑤⑥                        │
│     └─ 非法 → ⑦ 告警 + 回退（可选）       │
└──────────────────────────────────────────┘
```

**② 的实现（"状态是否真的变了"）**：

**Power Automate 的 Dataverse 触发器提供了一个"变更前的值"**：

| Dynamic content | 含义 |
|---|---|
| **触发器的字段**（如 `状态`） | **当前值**（变更后） |
| **触发器的 `...`（展开后）** | 有 **"Previous value"** 之类的项，或 `triggerOutputs()?['body/...']` 与 `triggerBody()?[...]` 的区别 |

> ⚠️ **待实测**：不同的触发器版本对"上一版本的值"的暴露方式不同。常见的有：
> - 触发器输出里有一个 **`value`**（当前）与 **`@odata.etag`** 之类的元数据
> - 有些版本的 Dataverse 触发器的 **"Select columns"** 里可以勾 **"Include previous values"**
>
> **本手册的建议（不依赖上一版本值）**：
> **在流程里往"上一次的状态"推**——即：**不比较新旧，而是直接校验"当前状态是否是终态" + "是否有并发的非法变更"**。
>
> 更实用的做法（**本手册采用**）：
> 1. **把状态迁移校验放在"写入端"**（即 `05` 手册 FL-03 的**前置校验**）而不是"检测端"
> 2. 也就是说：**凡是改状态的流程，都在改之前先校验**
> 3. 而 FL-03 的职责就简化为"**状态变了就通知 + 写历史**"

> ⚠️ **这是一个重要的架构决策，请理解清楚**：
>
> | 架构 | 做法 | 评价 |
> |---|---|---|
> | **A（严格，复杂）** | FL-03 检测所有变更，非法则**回退** | ❌ **不推荐**。回退会再次触发流程，**形成循环**；且"回退"在业务上很怪（用户看到状态跳回去了）|
> | **B（本手册采用）** | **"写入端校验 + 检测端记录"** | ✅ **推荐**。改状态的入口只有几个（Canvas App 的按钮、FL-05 审批通过、FL-06 发布完成），**每个入口各自校验** |
>
> **B 的代价**：若有人**手工在 Dataverse 界面改状态**（Admin 可以），**绕过了校验**。
> → **应对**：FL-03 **仍然记录**这种变更（进历史表 + 告警），**只是不回退**。**审计能发现，这就够了。**

**③ 的实现（写入端校验，在 FL-05/FL-06 与 Canvas App 里）**：

在**每一个改状态的动作之前**加一个 **Condition** 判断"目标状态是否属于合法集合"。

例：从 `Testing` 出发，只允许 `Fixing` 或 `ReadyForRelease`：

```
Condition:
  or(
    equals(<目标状态>, 'Fixing'),
    equals(<目标状态>, 'ReadyForRelease')
  )
```

> ⚠️ **这需要为每个源状态写一段判断，共 12 段（去掉两个终态）。**
> **在无代码方案里的一个实用技巧**：用 **`Switch`** 动作（搜索 `Switch`）按"当前状态"分支，**每个分支里再判断目标状态**。
> ⚠️ **Power Automate 的 `Switch` 默认只比较"等于"**，所以每个分支里仍要 Condition。**这比 12 个平级 Condition 清晰得多。**

### 4.4 步骤 1–3：触发器 + 防循环 + 状态变更判断

1. 触发器：**When a row is added, modified or deleted**
   | 字段 | 值 |
   |---|---|
   | **Change type** | **Modified** |
   | **Table name** | `问题` |
   | **Scope** | `Organization` |
   | **Select columns** | **留空** |

2. **Condition 1（防循环）**：`自动化更新` **is equal to** `否` → **If no → Terminate(Succeeded)**

3. **Condition 2（只关心状态变更）**：

   ⚠️ **这里是最需要技巧的地方。** 因为 Dataverse 的 Modified 触发器**不知道该列是否变了**。
   **不判断的话，任何字段的修改都会触发通知**（例如改了个错别字，也发一遍"状态变更通知"）。

   **三个可选做法**：

   | 做法 | 实现 | 评价 |
   |---|---|---|
   | **A（推荐）** | **在触发器上勾 "Filter columns"** 只勾 `bjops_status` | ⚠️ **Filter columns 的语义是"只在这些列变更时才触发"**（有些版本是"只返回这些列"）。**必须实测确认语义** |
   | **B** | 流程内比较新旧值 | ⚠️ 依赖触发器是否暴露旧值（见上） |
   | **C** | **用一个"影子列"**：`02` 里加一列 `bjops_lastnotifiedstatus`，流程判断 `bjops_status != bjops_lastnotifiedstatus`，然后回写 `bjops_lastnotifiedstatus = bjops_status` | ✅ **最可靠，不依赖任何触发器特性**。**代价：多一列** |

   > **本手册采用做法 C。**
   >
   > ⚠️ **请在 `02` 手册补建这一列**：`bjops_lastnotifiedstatus`，类型 = **选项集（`bjops_issuestatus`）**，**可选**（不要必填，否则旧数据无法保存）。
   > **并把这个列加进 `附录A` 的字段清单。**
   >
   > **这是本方案对 `docs/data-dictionary.md` 的一处补充**（原字典里没有这一列）。**必须记录为偏差。**

   流程内判断：

   ```
   Condition: <当前状态> is not equal to <上次通知状态>
   ```

   → **If yes** → 继续；**If no** → **Terminate(Succeeded)**

   > ⚠️ **注意首次变更时 `bjops_lastnotifiedstatus` 是空的**，判断"不等于"会通过。**这是对的**（第一次变更必须要通知）。

4. ⚠️ **回写 `bjops_lastnotifiedstatus` 必须在流程的最末尾**（§4.7），而且**要跳过防循环判断**——**所以在回写之前要先设 `自动化更新 = 是`**（见 §8.3）。

### 4.5 步骤 4：写历史表

**+ New step** → **Add a new row**（Dataverse）→ **Table = `问题历史`**

| 字段 | 值 |
|---|---|
| **所属问题** | 触发器的记录 |
| **变更字段** | 固定值 `bjops_status`（⚠️ 用**逻辑名**，与 `02` 的列逻辑名一致，便于下游解析） |
| **原值** | ⚠️ **拿不到旧值时留空**，或填 `<未捕获>` |
| **新值** | ⚠️ **必须是"新状态的显示名"**（如 `Analyzing`），**不是数值** |
| **变更人** | ⚠️ **见下** |
| **变更时间** | `utcNow()` |
| **变更来源** | ⚠️ **见下** |
| **关联 ID** | ⚠️ 见下 |
| **备注** | 例：`状态由 <操作人> 变更为 <新状态>` |

> ⚠️ **"变更人"字段怎么填（这是 `03` §10 / §6.1 讲过的问题）**：
>
> **流程以连接拥有者身份运行，所以 `Modified By` 字段是流程账号，不是真实操作人。**
> **但业务要求知道"是谁改的"。**
>
> | 方案 | 做法 | 评价 |
> |---|---|---|
> | **A** | 读 `Modified By`（= 流程账号） | ❌ **错的人** |
> | **B** | **在 `问题` 表上加一列 `bjops_lastmodifiedbyemail`**，凡是通过流程改状态的入口（Canvas App / 审批）都在改之前写入操作人邮箱 | ✅ **可行**。**代价：多一列** |
> | **C** | 用 **Dataverse 审计日志**反查（审计记录的是流程账号，**也拿不到真人**） | ❌ **同样拿不到** |
> | **D** | **审批流程天然带审批人**（`05` §6）：审批通过的场景用**审批响应里的审批人** | ✅ **这个场景下最准** |
>
> **本手册的建议**：
> - **审批场景（FL-05/FL-06）**：用**审批响应里的审批人**（方案 D）
> - **Canvas App 场景**：用**方案 B**，读 `bjops_lastmodifiedbyemail`
> - **手工在界面改**：用 `Modified By`（**此时流程账号 = 真人**，因为是人直接在界面操作，**不走流程**）
>
> ⚠️ **这需要 `02` 补建 `bjops_lastmodifiedbyemail` 列**（单行文本，200）。**记入 `附录A`。**
>
> ⚠️ **不要试图用 `bjops_reporter`（报告人）**。报告人 ≠ 改状态的人。**这个错误会导致历史表里"每次都是报告人改的状态"，完全失去追溯价值。**

> ⚠️ **"变更来源"（`bjops_changesource`）怎么填**：
> 数据字典 §2 里 `bjops_changesource` 是**人工 / 流程**两个值。
> - **FL-03 自己写的历史记录** → 填 **`流程`**
> - **FL-01 建单时写的** → 填 **`流程`**（`04` §4.6）
> - **若将来 Canvas App 直接写历史** → 填 **`人工`**
>
> ⚠️ **这个字段是"三层审计"的对照依据**（`03` §6.1）。**必须准确。**

> ⚠️ **"关联 ID"（`bjops_correlationid`）怎么填**：
> - FL-01 建单时生成的 → **把它带到这条记录上**（若可传递）
> - FL-03 自己的运行 → **用 `workflow()?['runName']` 作为关联 ID**（这样能把"一次流程运行产生的所有写入"串起来）
> - **两者的取舍**：**用 `runName` 更实用**（能反查流程运行历史）。**但会丢失"与表单提交的关联"**。
> → **本手册建议**：`bjops_correlationid` 填 **`runName`**；**表单响应 ID 已经在 `问题` 表上**，需要时从那里取。

### 4.6 步骤 5：发通知

**通知对象**：

| 谁 | 用什么 | 内容 |
|---|---|---|
| **频道**（`01-新问题受理`） | Teams **Post card in a chat or channel** | 简版卡片：编号 + 标题 + 旧状态 → 新状态 + 操作人 |
| **报告人**（`bjops_reporteremail`） | Teams **Post message in a chat or channel**（Chat with Flow bot） | 编号 + 新状态 + 一句业务解释 |
| **新负责人**（若状态变成 `Assigned`） | Teams 一对一 | 编号 + 标题 + "请跟进" |

> ⚠️ **通知量控制**：**每个状态变更都发频道通知会淹没频道**（14 个状态，一个单能变 6–8 次）。
>
> **本手册的建议（按状态分级）**：

| 状态 | 发频道 | 发报告人 | 发负责人 |
|---|---|---|---|
| `New` | ✅ | ✅ | |
| `Triaged` | ❌ | | |
| `Assigned` | ✅ | | ✅ |
| `Analyzing` | ❌ | | |
| `WaitingForInfo` | ✅ | ✅（**要他补信息**） | |
| `Fixing` | ❌ | | |
| `ReadyForTest` | ❌ | | |
| `Testing` | ❌ | | |
| `ReadyForRelease` | ✅ | | |
| `Released` | ✅ | ✅（**告诉他修好了**） | |
| `Monitoring` | ❌ | ✅（**请他确认**） | |
| `Closed` | ✅ | ✅ | |
| `Reopened` | ✅ | | ✅ |
| `Rejected` | ✅ | ✅ | |

> ⚠️ **`WaitingForInfo` 和 `Monitoring` 必须发报告人**：
> - `WaitingForInfo`：**要他补信息**，不发他就卡住了
> - `Monitoring`：**要他确认是否已解决**，不发他就永远不关单（设计稿 §11.2 的关闭条件里要求"请求人确认"）

**实现方式**：在 §4.5 之后加一个 **Switch**（按新状态分支），每个分支里配对应的通知动作。

### 4.7 ⚠️ 步骤 6：回写"上次通知状态"（必须最后做）

1. **+ New step** → **Update a row**（Dataverse）
2. **Table = `问题`**，**Row ID** = 触发器记录
3. **自动化更新** = **`是`** ← ⚠️ **必须先设这个！**
4. **上次通知状态** = **触发器的当前状态值**

> ⚠️ ⚠️ **为什么必须最后做、且必须设 `自动化更新 = 是`**：
>
> 1. 这个 Update 动作**会再次触发 FL-03 的触发器**（因为它触发了 Modified 事件）
> 2. **第一次触发时**，`bjops_automationupdate` 被设为 `是` → **FL-03 的防循环判断会拦截它**
> 3. 但 ⚠️ **FL-02 的触发器是 Added only**，所以不会被这条 Update 触发
> 4. ⚠️ **FL-04（SLA 扫描）是定时的**，不受影响
>
> **⚠️ 但这里有一个更深的问题**：**这条 Update 之后，`bjops_automationupdate` 会永久停留在 `是`**。
> → **下次真人改状态时，防循环判断会拦住，通知就不发了。**
>
> **必须解决！** 有两个做法：
>
> | 做法 | 说明 |
> |---|---|
> | **A（推荐）** | **在最后再加一步 Update，把 `自动化更新` 设回 `否`** | ✅ **最直接**。⚠️ **这一步又会触发 FL-03 一次**（第三次），但那次 `automationupdate` 已经是 `否` → **会通过防循环判断**！ |
> | **B** | **不用 `bjops_automationupdate`，改用 `bjops_lastnotifiedstatus` 单独做防循环** | ✅ **更干净**。**因为 FL-03 的 §4.4 Condition 2 已经在比较"状态是否变了"了** |
>
> **⚠️ 本手册采用做法 B，并修正 §4.4 的设计。**
>
> **修正后的 FL-03 逻辑**：
> - **不用 `bjops_automationupdate` 做防循环**（那是给"其他流程"的标志）
> - **用 `bjops_lastnotifiedstatus` 做防循环**：`状态 != 上次通知状态` 才继续
> - **回写 `bjops_lastnotifiedstatus`** 后，再次触发的 FL-03 会发现"状态 == 上次通知状态" → **Terminate(Succeeded)** ✅
> - **`bjops_automationupdate` 只在"流程真的改了业务字段"时使用**（例如 FL-05 改状态、FL-06 改发布结果），且**用完立刻设回 `否`**
>
> **✅ 这个设计更干净：**
> | 流程 | 防循环机制 |
> |---|---|
> | **FL-01** | 幂等键 `bjops_formsresponseid` 查重 |
> | **FL-02** | 触发器 Added only + `automationupdate = 否` 判断 |
> | **FL-03** | **`bjops_lastnotifiedstatus` 比较**（新设计） |
> | **FL-04** | 定时触发，无循环风险 + `automationupdate = 否` 判断 |
> | **FL-05** | `automationupdate` 用完设回 |
> | **FL-06** | `automationupdate` 用完设回 |

> ⚠️ **这个设计决策很重要，请在 `02` 手册补建 `bjops_lastnotifiedstatus` 列。**（本手册 §4.4 已提到，此处确认。）

### 4.8 FL-03 自检

- [ ] 触发器 **Change type = Modified**
- [ ] **`bjops_lastnotifiedstatus` 列已补建**（`02` 手册）
- [ ] **`bjops_lastmodifiedbyemail` 列已补建**（`02` 手册）
- [ ] 防循环用 **`状态 != 上次通知状态`**（不是 `automationupdate`）
- [ ] 合法的状态迁移表已按 §4.2 实现（**在写入端校验**，不是在 FL-03 里回退）
- [ ] 历史表写入：**`变更人` 用真人（不是报告人）**；**`变更来源` = `流程`**；**`新值` 用显示名**
- [ ] 通知已分级（§4.6 的表），**不是每个状态都发频道**
- [ ] **`WaitingForInfo` 与 `Monitoring` 都发了报告人**
- [ ] 回写"上次通知状态"在**最后**
- [ ] Settings 已配（并发 1 / PT2H / 默认重试）

---

## 5. FL-04 SLA 扫描与升级

### 5.1 目标

| # | 做什么 |
|---|---|
| 1 | 每小时扫一遍**未关闭**的问题单 |
| 2 | 找出**已超过 SLA 截止时间**或**即将超时**的 |
| 3 | 按 `bjops_slaconfig` 的升级规则**提高升级层级** |
| 4 | 通知对应的人（负责人 / 组长 / 管理员） |

### 5.2 步骤 1：触发器（计划云流）

1. **+ New** → **Scheduled cloud flow**
2. **Flow name**：`FL-04 SLA 扫描与升级`
3. **Starting**：**当前时间往后 5 分钟**（便于测试）
4. **Repeat every**：**`1` `Hour`**

   > ⚠️ **为什么是 1 小时（不是每天一次）**：
   > 因为 `bjops_slaconfig` 的 SLA 时限可能是小时级；且**审批/升级要有及时性**。
   > **不能更频繁**（每 15 分钟）的原因：**Dataverse 的 API 调用量会显著上升**，且**这个流程要全表扫描**。
   >
   > ⚠️ **⚠️ 与 `07` 手册（Databricks）的联动注意**：ADLS 的 CDM 快照**只保留最近 5 个**（C14 事实）。**若 Databricks 的作业频率低于"每 5 小时一次"，会丢快照。**
   > → **FL-04 的 1 小时频率与此无关**（它读的是 Dataverse 实时数据，不是 ADLS）。**但两者都设成 1 小时，便于记忆。**

5. **时区**：选**本地时区**（如"中国标准时间"）
   > ⚠️ **时区设错会导致流程在错误的时刻跑**（例如凌晨 3 点发通知）。**配完要确认一次。**

### 5.3 ⚠️ 步骤 2：取"未关闭的问题"（分页！）

**这是本流程最需要技巧的一步。**

1. **+ New step** → **List rows**（Dataverse）
2. **Table name**：`问题`
3. **Filter rows**：

```
bjops_status ne 12 and bjops_status ne 14 and bjops_sladeadline ne null
```

> ⚠️ **⚠️ 这里必须用数值！**
> Dataverse 的 **List rows** 使用的是 **OData** 语法，**选项集比较时要用整数值**（`12` = `Closed`，`14` = `Rejected`）。
> **用显示名 `'Closed'` 是不生效的，而且不报错**——只是**筛不出来**，流程拿到全表数据。
>
> **验证方法**：配完后**先在运行历史里看输出行数**，若返回了已关闭的单，说明筛选没生效。
>
> ⚠️ **`bjops_sladeadline` 的 OData 过滤**：日期时间字段的 OData 比较语法是
> `bjops_sladeadline lt 2026-09-17T00:00:00Z`
> **⚠️ 注意 `Z` 后缀（UTC）**。**用 `utcNow()` 时也要保证是 UTC 格式。**
> **若不确定**，**建议不筛时间**，让流程拿到全部未关闭的单，**在流程内判断超时**（`addHours` / `less` 表达式）。**代价：数据量大时性能差，但正确性有保障。**

4. **Row count**：⚠️ **这是关键**

| 设置 | 效果 |
|---|---|
| **留空** | 默认返回 **5000 行**（Dataverse 的默认单页上限） |
| **填一个数** | 最多返回这么多行 |
| **勾 "Paginate"**（或 **Settings → Pagination**） | ✅ **自动翻页取全部** |

> ⚠️ **必须勾 Pagination**，或者**明确写一个足够大的 Row count**。
> **不勾的后果**：超过 5000 条未关闭问题时，**后面的单永远扫不到**，**而且不报错**。运维会以为"SLA 都正常"。

5. **+ New step** → **Apply to each**（把上一步的输出作为输入）

### 5.4 步骤 3：判断超时

**+ New step** → **Condition**

**判断"已超时"**：

```
less(triggerOutputs()?['body/bjops_sladeadline'], utcNow())
```

> ⚠️ **表达式里的日期时间比较**：Power Automate 会自动把 ISO 字符串解析成时间戳比较。
> **若两边格式不一致**（一个有 `Z`，一个没有），**比较结果会错**。
> **⚠️ 待实测**：配完后**必须用一个已知超时的记录测一次**。

**"即将超时"（预警）**：

```
less(
  triggerOutputs()?['body/bjops_sladeadline'],
  addHours(utcNow(), 2)
)
```

→ 即"2 小时内到期"。

> ⚠️ **"2 小时"这个数字应该来自 `bjops_slaconfig`**，但**没有对应的列**（`02` §6.2 的 9 个列里没有"预警提前量"）。
> **两个选择**：
> - **A**：**硬编码 2 小时**（违反铁律 3，但这是**业务规则**不是**环境配置**，可以接受）
> - **B**：**在 `bjops_slaconfig` 补一列 `bjops_warnhours`**（整数），从表里读取
>
> **本手册推荐 B**（保持配置一致，不同严重度可以有不同预警提前量）。**请 `02` 手册补建此列，并记入 `附录A`。**

### 5.5 步骤 4：升级与通知

**按 `bjops_slaconfig` 的升级规则处理**（`02` §6.2 的 3 步查找优先级）。

**升级逻辑**（`bjops_escalationlevel` 从 0 开始，超时后 +1）：

| 升级层级 | 通知谁 | 内容口径 |
|---|---|---|
| **0 → 1** | **负责人**（`ownerid`） | "您负责的问题 <编号> 已超过响应时限。" |
| **1 → 2** | **负责人 + 团队频道** | "问题 <编号> 已超时 2 小时，请立即处理。" |
| **2 → 3** | **负责人 + 频道 + 管理员** | "问题 <编号> 严重超时，已升级至平台管理员。" |

> ⚠️ **升级的"何时升"要写清楚**。`02` §6.2 的 9 个列里**没有"每级升级的间隔时间"**。
> **本手册的建议**：**每次扫描（1 小时）发现仍超时就 +1**，直到 3 封顶。
> → 即：**超时 1 小时 → 级别 1；超时 2 小时 → 级别 2；超时 3 小时及以上 → 级别 3。**
> ⚠️ **这个规则需要业务确认**。**写入 `附录A` 并在 `00` 的待决策清单里标注。**

**更新升级层级**：

1. **+ New step** → **Update a row**（Dataverse）
2. **自动化更新** = **`是`**
3. **升级层级** = `add(int(triggerOutputs()?['body/bjops_escalationlevel']), 1)`
4. **+ New step** → **Update a row** → **自动化更新** = **`否`**

> ⚠️ **必须设回 `否`**，否则这个人后续的状态变更通知会被防循环规则拦住（§4.7 的教训）。
> ⚠️ **这个"改了又改回来"会触发 2 次 Modified 事件**，**每次都让 FL-03 跑一遍**（但会被 `状态 != 上次通知状态` 拦住）。**这是可接受的代价。**

### 5.6 ⚠️ 步骤 5：写历史（可选但建议）

超时升级是**业务事件**，应当留痕：

**+ New step** → **Add a new row**（`问题历史`）：

| 字段 | 值 |
|---|---|
| **所属问题** | 当前记录 |
| **变更字段** | `bjops_escalationlevel` |
| **原值** | 升级前的层级 |
| **新值** | 升级后的层级 |
| **变更人** | ⚠️ **流程账号**（这是系统行为，没有真人） |
| **变更来源** | `流程` |
| **备注** | `SLA 超时自动升级` |

> ⚠️ **注意**：`变更人` 这里填流程账号是**正确的**，因为**这是系统行为**。**不要为了"好看"填负责人** —— 那会**污染审计数据**。

### 5.7 FL-04 自检

- [ ] 计划触发器：**每 1 小时**，时区已确认
- [ ] **List rows 勾了 Pagination**（或 Row count 足够大）
- [ ] Filter rows 用的是**选项集的数值**（`12`/`14`），已用运行历史验证筛选生效
- [ ] 超时判断表达式已用**真实超时记录测试过**
- [ ] `bjops_warnhours` 列已补建（或明确接受硬编码 2 小时）
- [ ] 升级逻辑：**超时 1h→级别1，2h→级别2，≥3h→级别3**（**已与业务确认**）
- [ ] **`自动化更新` 用完已设回 `否`**
- [ ] 历史记录已写，**`变更人` 填流程账号**（不是负责人）
- [ ] **Settings：并发 1，超时 `PT50M`**（短于运行间隔）

---

## 6. FL-05 关闭确认（含审批）

### 6.1 目标

状态进入 `Monitoring`（已修复，观察中）后：

| # | 做什么 |
|---|---|
| 1 | 向**报告人**发一张**可交互的确认卡片**（"问题是否已解决？"） |
| 2 | 报告人点"已解决" → 走**审批**（可选）→ 状态转 `Closed` |
| 3 | 报告人点"仍存在" → 状态转 `Reopened` |
| 4 | **超时未响应** → **自动关闭**（或升级） |

### 6.2 ⚠️ 关于"可交互卡片"的已知限制（E22 事实）

| 事实 | 影响 |
|---|---|
| **Teams 连接器是标准连接器** | ✅ **不需要 Premium** |
| **Adaptive Cards 不需要 Premium** | ✅ 本方案可以用 |
| ⚠️ **`Post adaptive card and wait for a response` 会"暂停流程"** | 流程会**一直等**，最长取决于超时设置 |
| ⚠️ **不能与"当有人回复时"触发器组合使用** | 二选一 |
| ⚠️ **卡片只能提交一次** | 用户点了之后卡片上的按钮会失效（重复点是无效的） |
| ⚠️ **私有频道不支持** | 只能用标准频道 |
| ⚠️ **@提及最多 20 个** | 本方案不涉及 |

> ⚠️ **"暂停流程"是个大问题**：如果报告人一直不点，**这条流程运行会挂在那里**。
> **应对**：
> 1. **在动作上设一个"超时"**（该动作通常有一个 **"Until"** 或超时设置，不同版本不同）
> 2. 若无法设超时 → **流程会一直等**，**这本身也是一种"等待"的实现**（设计上可接受）
> 3. **但要注意并发度 = 1** 的设置！**如果流程串行，一条挂着的运行会阻塞后续所有运行。**
> → ⚠️ **FL-05 必须把并发度设为"不限"**（或者足够大），**不能是 1**。
> → **这是 §2 通用设置的一个例外，务必注意。**

### 6.3 步骤 1：触发与卡片

1. 触发器：**When a row is added, modified or deleted**
   | 字段 | 值 |
   |---|---|
   | **Change type** | **Modified** |
   | **Table name** | `问题` |
2. **Condition（防循环）**：`自动化更新 = 否`
3. **Condition（只关心进入 Monitoring）**：`状态` **is equal to** `Monitoring` **and** `上次通知状态` **is not equal to** `Monitoring`
   > ⚠️ 用 `bjops_lastnotifiedstatus` 辅助，避免重复触发。
   > ⚠️ **但注意 FL-03 也在回写 `lastnotifiedstatus`**，两条流程会"抢"这一列。
   > → **处理**：**FL-05 不用 `lastnotifiedstatus`，改用一个新列 `bjops_closeconfirmrequested`（两选项）**。
   > → **`02` 需补建此列。** 记入 `附录A`。
4. **Which card to post** → **Custom**，粘 §6.4 的 JSON
5. **Post in**：**Chat with Flow bot**，**Recipient** = `bjops_reporteremail`
6. **Update message**（提交后的提示）：`感谢确认，系统已记录。`

> ⚠️ **第 5 步用的是"Chat with Flow bot"（一对一聊天）**，**不是频道**。
> 原因：**频道卡片谁都能点** —— 别人点了会导致状态错误变更。
> **必须发一对一**（或者说，**必须确保只有报告人能点**）。

### 6.4 关闭确认卡片的 JSON

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "size": "Medium",
      "weight": "Bolder",
      "text": "❓ 问题已修复，请确认"
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "编号", "value": "${IssueNumber}" },
        { "title": "标题", "value": "${Title}" },
        { "title": "修复版本", "value": "${FixVersion}" },
        { "title": "解决方案", "value": "${Solution}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "请问您反馈的问题是否已经解决？",
      "wrap": true
    }
  ],
  "actions": [
    {
      "type": "Action.Submit",
      "title": "✅ 已解决",
      "data": { "action": "confirm" }
    },
    {
      "type": "Action.Submit",
      "title": "⚠️ 仍存在问题",
      "data": { "action": "reopen" }
    }
  ]
}
```

**之后**：

1. **+ New step** → **Condition**：判断返回值
   - 用表达式取卡片提交的数据（通常是 `outputs('动作名')?['body/action']`）
2. **If `confirm`** → 走 §6.5 的关闭流程
3. **If `reopen`** → 走 §6.6 的重开流程

### 6.5 "已解决"分支

**两个选择**：

| 方案 | 做法 | 评价 |
|---|---|---|
| **A（简单）** | **直接置 `Closed`** | ✅ 适用于**低严重度**问题 |
| **B（正式）** | **走审批**（`Start and wait for an approval`），审批通过才 `Closed` | ✅ 适用于**高严重度**或**合规要求**的问题 |

**本手册采用：按严重度分流。**

```
若 严重度 in (Critical, High) → 方案 B（审批）
否则 → 方案 A（直接关闭）
```

**方案 B 的配置**：

1. **+ New step** → **Start and wait for an approval** → **Create an approval**
2. **Approval type**：**Approve/Reject - First to respond**
3. **Title**：`关闭确认：<问题编号>`
4. **Assigned to**：**发布经理或管理员**（⚠️ **不是报告人**——报告人已经在卡片上确认过了）
5. **Details**：编号 + 标题 + 解决方案 + 报告人确认时间

> ⚠️ **审批超过 30 天的注意事项**：
> **"Start and wait for an approval" 的审批记录默认存放在某个位置，超过一定期限后可能失效。**
> **若业务上可能出现"审批挂超过 30 天"**，需要用两个流程：
> 1. 流程 1：发起审批（不等待）
> 2. 流程 2：**"当审批响应时"触发器** → 处理结果
> ⚠️ **并把审批记录存到 Dataverse**（否则审批历史无法长期保留）。
> **本方案的建议**：**本场景的审批不会挂 30 天**（关闭确认是日常动作），**用简单的"Start and wait"即可**。
> **若将来发现审批经常堆积**，再改造成两流程模式。

**审批结果处理**：

| 结果 | 动作 |
|---|---|
| **Approved** | `状态 = Closed` + `关闭代码` 填写 + `关闭时间` = `utcNow()` |
| **Rejected** | ⚠️ **不改状态**，发通知给审批人问原因（或退回 `Fixing`） |

### 6.6 "仍存在问题"分支

1. `状态 = Reopened`
2. `关闭确认已请求 = 否`（重置，允许下次再发确认卡片）
3. **通知频道**（`01-新问题受理`）："问题 <编号> 由报告人重新打开"
4. **写历史表**：`变更字段 = bjops_status`，`原值 = Monitoring`，`新值 = Reopened`，`变更人 = 报告人邮箱`，`变更来源 = 流程`

### 6.7 ⚠️ 超时未响应的处理

**问题**：报告人永远不点卡片怎么办？

| 方案 | 做法 | 评价 |
|---|---|---|
| **A（推荐）** | **再建一条计划流程**（每天跑一次）：找出 `状态 = Monitoring` 且 `关闭确认已请求 = 是` 且 **超过 7 天**的单 → **自动关闭**并注明"超时自动关闭" | ✅ 简单、可控 |
| B | 在 FL-05 里用 `Parallel branch` + `Delay until` | ⚠️ 复杂，且会挂住流程运行 |
| C | 升级到管理员 | ⚠️ 管理员不会去点报告人的卡片 |

**本手册采用方案 A。** 把它作为 **FL-05b**：

| 项 | 值 |
|---|---|
| **触发器** | 计划，每天 1 次（建议**工作时间开始后**，如 09:00） |
| **List rows** | `bjops_status eq 11 and bjops_closeconfirmationrequested eq true` |
| **Condition** | `addDays(确认请求时间, 7) < utcNow()` |
| **动作** | `状态 = Closed`、`关闭代码 = 超时自动关闭`（需在 `bjops_closecode` 里确认有这个值）、写历史、发通知 |

> ⚠️ **`bjops_closecode` 的 7 个值里必须有对应的"超时自动关闭"类取值**（`data-dictionary.md` §2.7）。**若没有，需要在选项集里补一个值，并同步更新 `02`/`附录A`。**

### 6.8 FL-05 自检

- [ ] **`bjops_closeconfirmationrequested` 列已补建**（`02` 手册）
- [ ] **并发度不是 1**（因为卡片会挂住运行）⚠️ **这是 §2 通用设置的例外**
- [ ] 卡片**发一对一**（不是频道）
- [ ] 卡片 JSON 已粘，`${}` 已替换
- [ ] **"已解决"分支按严重度分流**（Critical/High 走审批）
- [ ] **审批人不是报告人**（报告人已在卡片上确认）
- [ ] "仍存在问题"分支会**重置 `关闭确认已请求`**
- [ ] **FL-05b（超时自动关闭）已建**，7 天阈值已与业务确认
- [ ] `bjops_closecode` 里**有"超时自动关闭"的取值**

---

## 7. FL-06 发布审批

### 7.1 目标

`发布记录`（`bjops_release`）新建后，走发布审批；审批通过后，**批量把相关问题的状态推到 `Released`**。

### 7.2 步骤

1. **触发器**：**When a row is added**，Table = `发布记录`
2. **Condition（防循环）**：`自动化更新 = 否`
3. **Start and wait for an approval** → **Create an approval**
   | 字段 | 值 |
   |---|---|
   | **Approval type** | **Approve/Reject - First to respond**（或 **Everyone must approve**） |
   | **Title** | `发布审批：<版本号> @ <环境>` |
   | **Assigned to** | **发布经理组 / 管理员** |
   | **Details** | 版本号 + 环境 + 变更说明 + **关联的问题编号列表** |
   | **Attachments** | ⚠️ **可选**：发布包/发布说明的 SharePoint 链接 |
4. **Approved 分支**：
   - `发布记录.结果 = Approved`、`完成时间 = utcNow()`
   - ⚠️ **批量更新关联问题的状态** → 用 **List rows + Apply to each + Update a row**
   - 发通知
5. **Rejected 分支**：
   - `发布记录.结果 = Rejected`
   - 通知提出人（附拒绝理由）

> ⚠️ **关于"关联的问题"**：`02` §5.3 的 `bjops_release` 有 `bjops_result` 和 `bjops_completedtime`，**但"关联哪些问题"的关系在哪里？**
>
> **设计稿 §9.3 的发布流程**涉及"问题 → 版本 → 发布"的关联。本方案的关联方式是：
> - **问题 → 版本**：`bjops_issue.bjops_fixversion`（**文本列**，按方案 A）
> - **版本 → 发布**：`bjops_version` ↔ `bjops_release` 的关系（`02` §7 的 15 个关系之一）
>
> → **所以"批量更新"的查询是**：
> ```
> 1. 从 发布记录 找到关联的 版本（通过关系）
> 2. List rows: bjops_issue where bjops_fixversion eq '<版本号>' and bjops_status eq 9  (ReadyForRelease)
> 3. Apply to each: Update 状态 = Released
> ```
>
> ⚠️ **这里是"方案 A（`bjops_fixversion` 是文本）"的一个代价**：**文本匹配不精确**。
> - 若用户填了 `2.3.1` vs `v2.3.1` vs `2.3.1 `（带空格）→ **匹配不上**
> - **应对（`02` §5.1 已提到）**：**`05` 流程要校验 `bjops_fixversion` 的值能在 `bjops_version` 里找到**，找不到就告警。
> → **本手册在此确认这个校验要做，位置在"状态变更为 `Fixing` → 保存修复版本时"。**

### 7.3 ⚠️ 关于"发布审批"在 Phase 1 的简化

设计稿 §9.2 有 **10 项发布门禁**（十项检查）。**Phase 1 只取 5 项**（`Phase1-实施方案.md` §12）。

**本手册在 Phase 1 的做法**：

| 门禁 | Phase 1 怎么做 |
|---|---|
| 有测试通过记录 | ⚠️ **人工确认**（审批详情里列出来，审批人自己看） |
| 关键问题已关闭 | ⚠️ **人工确认** |
| 版本号已登记 | ✅ **流程自动校验**（`bjops_version` 里存在） |
| 发布包已上传 | ⚠️ **人工确认**（审批详情里给链接） |
| 回滚方案已准备 | ⚠️ **人工确认** |

> ⚠️ **"人工确认"是本方案在 Phase 1 的现实选择**。**不要把它自动化**——因为**自动化的门禁在 Phase 1 阶段会误拦**（数据质量不够）。
> **Phase 2 有了 `bjops_testcase` / `bjops_testexecution` 后，可以自动校验测试通过率。**

---

## 8. ⚠️ 防循环规则（五条铁律）

> ⚠️ **这是本手册最重要的一章。** 循环会**在一夜之间烧掉几万次流程运行**（如果按用量计费，就是**真金白银**；即使不计费，**环境的 API 调用限额也会被打爆**）。

### 8.1 五条规则

| # | 规则 | 实现方式 |
|---|---|---|
| **1** | **流程自己改的记录，自己不再处理** | `bjops_automationupdate` 标志（用于"流程主动改业务字段"的场景） |
| **2** | **自己改完立刻把标志设回 `否`** | 在流程的**最后**加一步 Update |
| **3** | **"通知类"流程不用 `automationupdate`，用自己的"影子列"做幂等** | FL-03 用 `bjops_lastnotifiedstatus`；FL-05 用 `bjops_closeconfirmationrequested` |
| **4** | **"写入端"先校验，不要让"检测端"回退** | 状态迁移的合法性在改之前校验（§4.3） |
| **5** | **触发器只选必要的 Change type** | FL-01 / FL-02 只选 **Added**；FL-03 / FL-05 才选 **Modified** |

### 8.2 为什么"流程 A 改 → 触发流程 B → 流程 B 又改 → 触发流程 A"会发生

```
FL-03（Modified 触发）
   → 写历史表（不同表，安全）
   → 回写 问题.上次通知状态  ← ⚠️ 这是对 问题 表的 Update
   → 触发 FL-03 自己（Modified）
   → 第二次运行时，"状态 == 上次通知状态" → Terminate ✅
```

**这个循环是"有限"的（跑 2 次就停），可以接受。**

**但如果 FL-03 用的是 `bjops_automationupdate`**：

```
FL-03 第一次：检测到 状态变了 → 处理 → 设 automationupdate = 是
  → 触发 FL-03 第二次：automationupdate = 是 → Terminate ✅ （但 automationupdate 还停在 是）
  → ⚠️ 之后真人再改状态：automationupdate 还是 是 → Terminate → **通知永远不发了**
```

**这是一个"不循环但功能坏死"的 bug，比循环更难发现。** ← **这就是 §4.7 改用影子列的原因。**

### 8.3 标志位的正确用法

| 场景 | 用哪个标志 | 用完怎么处理 |
|---|---|---|
| **流程主动改业务字段**（如 FL-04 改升级层级、FL-06 改发布结果） | `bjops_automationupdate = 是` | **改完立刻设回 `否`** |
| **流程改"影子列"**（如 FL-03 回写上次通知状态） | **不用 `automationupdate`**，靠影子列自身幂等 | 无需处理 |
| **流程只读**（如 FL-02 大部分逻辑） | 无需标志 | — |

> ⚠️ **"改完立刻设回 `否`"这个动作本身会触发一次 Modified 事件**，但因为**当前是 `否`**，所以会**通过防循环判断**（即**会真的跑一次后续流程**）。
> → **这正是需要的**：因为业务字段确实变了，**应该通知**。
> → 但要确保**这次运行不会再改 `automationupdate`**（否则又循环）。**保证方式：所有"改 automationupdate"的步骤都只在"业务字段变更"的分支里。**

### 8.4 ⚠️ 排查"通知不发了"的步骤

若发现"状态变了但没人收到通知"：

| # | 检查 | 怎么看 |
|---|---|---|
| 1 | **流程是否还在启用状态** | `make.powerautomate.com` → 解决方案 → 流程 → 状态 |
| 2 | **触发器是否还在**（迁移后 Form ID 失效等） | 打开设计器看有没有红色警告 |
| 3 | **流程运行历史**里有没有对应的运行 | 流程 → **28-day run history** |
| 4 | **运行的输出**：防循环判断走了哪个分支 | 点开那次运行，看 Condition 的**输入**和**输出** |
| 5 | **`bjops_automationupdate` 的当前值** | 在 Dataverse 界面看。⚠️ **如果是"是"，说明有流程没把它设回来** |
| 6 | **`bjops_lastnotifiedstatus` 的值** | 如果它**已经等于当前状态**，说明流程认为"通知过了" |
| 7 | ⚠️ **连接是否失效** | 解决方案 → 连接引用 → 看有没有警告 |

> ⚠️ **第 5 条是最常见的原因。** 建议在 `10` 手册的日常检查里**加一条："查 `automationupdate = 是` 且超过 1 小时未变化的记录"**。

### 8.5 一条实用的排查视图

在 Dataverse 里建一个视图（`02` §11 的视图规范）：

| 项 | 值 |
|---|---|
| **视图名** | `⚠️ 自动化异常 - 标志位卡住` |
| **筛选** | `自动化更新 = 是` **and** `修改时间 > 1 小时前` |
| **列** | 编号、标题、状态、自动化更新、修改时间 |

> ⚠️ **这个视图是"流程健康度"的直接指标。** 正常情况它**应该永远是空的**。有数据就一定有问题。

---

## 9. FL-08 流程失败预警

### 9.1 为什么需要它

**Power Automate 的流程失败默认不会通知任何人**（除非拥有者手动去看运行历史）。

**本方案的故障模式**里，有多个会**静默失败**：

| 故障 | 症状 |
|---|---|
| 连接失效 | 流程进失败列表，**没人看** |
| 触发器失效（Form ID 变了） | 流程**根本不运行**，**没有失败记录** |
| 权限变更 | 流程进失败列表 |
| 拥有者离职 | 流程**被禁用**（某些情况下），**没人发现** |

> ⚠️ **本手册的建议**：**接受"没有自动预警"这个现状，改用"人工例行检查"**（`10` 手册的日常检查）。
> **理由**：实现"流程失败自动预警"需要**另一条流程去监控所有流程**，而**这条监控流程自己失败了也没人知道**（递归问题）。
>
> **一个更简单的替代**：**每天在 Teams 频道发一条"健康日报"**。

### 9.2 健康日报流程（推荐实现）

| 项 | 值 |
|---|---|
| **触发器** | 计划，每天 08:30 |
| **动作 1** | **List rows**（`问题`）：`bjops_status ne 12 and bjops_status ne 14`（未关闭）→ 统计数量 |
| **动作 2** | **List rows**（`问题`）：`bjops_automationupdate eq true` → **⚠️ 应该永远为空** |
| **动作 3** | **List rows**（`问题历史`）：`bjops_changedon` 在最近 24 小时内 → 统计数量 |
| **动作 4** | 发 Teams 频道消息（`03-Power Platform`）：一张小卡片，列上面三个数字 |
| **附加** | 若有 **过期未处理** 或 **标志位卡住** → 用红色标注 |

> ⚠️ **这个"日报"有一个隐藏的好处**：**如果日报某天没发，说明计划流程本身挂了**（或拥有者离职了）。**这是唯一能发现"计划流程死了"的方式。**

### 9.3 一个"心跳"技巧

在日报流程的最后，**更新一条专用的记录**（例如 `bjops_slaconfig` 里的一条特殊记录，或建一个 `系统心跳` 表）。

- 每次日报成功运行就更新一次时间戳
- **若有单独的人工检查发现"心跳超过 2 天没更新"** → 说明日报流程挂了

> ⚠️ **这是"看门狗看门狗"的问题**。**根本解法还是人工例行检查**（`10` 手册）。
> **本方案的建议**：**不做心跳表**（增加复杂度且仍解决不了"谁来报警"的问题），**改为每周一次人工核对**。

---

## 10. WBS 与工时估算

| 阶段 | 任务 | 前置 | 工时（人日） |
|---|---|---|---|
| S4-1 | 建 9 + 1 个环境变量（**含补建的 `ModelDrivenAppId`**） | S3 完成 | 0.5 |
| S4-2 | 建 6 个连接引用并授权 | — | 0.5 |
| S4-3 | FL-01 表单建单流程（**`04` 手册**） | 表单已建 | 2 |
| S4-4 | FL-02 问题创建通知（含 Adaptive Card） | FL-01 | 1.5 |
| S4-5 | FL-03 状态变更通知（含历史表 + 分级通知） | FL-02 | 3 |
| S4-6 | FL-04 SLA 扫描与升级 | FL-03 | 2 |
| S4-7 | FL-05 关闭确认（含卡片 + 审批） | FL-03 | 2 |
| S4-8 | FL-05b 超时自动关闭 | FL-05 | 0.5 |
| S4-9 | FL-06 发布审批 | FL-03 | 1.5 |
| S4-10 | FL-08 健康日报 | FL-04 | 0.5 |
| S4-11 | **防循环验证**（每两条流程之间都测一遍） | 全部 | 1.5 |
| S4-12 | 端到端联调（表单 → 建单 → 通知 → 状态流转 → 关闭） | 全部 | 2 |
| **合计** | | | **≈ 17.5 人日** |

> ⚠️ **这个估算假设"配置的人已经熟悉 Power Automate 设计器"**。若团队第一次用 Power Platform，**乘以 1.5**。

---

## 11. ⚠️ 环境变量的手工注入（无代码方案的关键差异）

### 11.1 代码方案 vs 本方案

| 项 | 代码方案（`Phase1-实施方案.md` §11.3） | **本方案** |
|---|---|---|
| 注入方式 | `pac solution create-settings` + `import --settings-file` | **门户里手工填 `Current value`** |
| 配置来源 | `solution/DeploymentSettings/<env>.json` | **没有配置文件** |
| 可追溯性 | Git 里的 JSON 文件 | ⚠️ **只有门户里的值** |

> ⚠️ **本方案失去了"配置即代码"的能力。** 补偿措施：
> 1. **每个环境的配置值要记录在文档里**（见 §11.3 的表格）
> 2. **迁移时逐项对照填写**（`09` 手册的迁移清单）
> 3. ⚠️ **值里不要放敏感信息**（环境变量在门户里是明文可见的，且会进审计）

### 11.2 手工填写的步骤

1. `make.powerapps.com` → **Solutions** → `SysOpsStandard`
2. 左侧 **Objects** → 展开 **Environment variables**
3. 逐个打开环境变量：
   - **Default value**：保持 `TODO-CHANGE-IN-TARGET-ENV`（**不要改**）
   - **Current value**：点 **+ New value** → 填本环境的真实值 → **Save**
4. 保存后，**当前值是新值**（会带一个时间戳）

> ⚠️ **环境变量值的传播是异步的**（`Phase1-实施方案.md` §11.4）。
> **改完值后，流程里可能几分钟内还是旧值。** **不要重复改**（`alm-runbook.md` §5.2 的提示），**等几分钟再测**。
>
> **排查方法**：改完值后，**手工运行一次流程**（流程 → **Test → Manually**），在**运行历史里看环境变量的实际取值**。

### 11.3 ⚠️ 每个环境的配置值登记表（必须填）

| 环境变量 | DEV | TEST | PROD |
|---|---|---|---|
| `TeamsGroupId` | | | |
| `TeamsChannelId` | | | |
| `AdminNotificationChannelId` | | | |
| `SharePointSiteRootUrl` | | | |
| `EvidenceLibraryName` | | | |
| `LogPackageLibraryName` | | | |
| `PortalUrl` | | | |
| `DefaultEnvironment` | `DEV` | `TEST` | `PROD` |
| `IntakeFormId` | | | |
| **`ModelDrivenAppId`**（本方案补建） | | | |

> ⚠️ **这张表是 `09` 迁移手册的核心输入。** **请在 S4 完成时填满 DEV 列**，并在 `09` 阶段填满 TEST/PROD。
> **建议存放位置**：本手册（`05`）内直接填写；或用 SharePoint 的一个受控文档。
> ⚠️ **不要放在公开的 Wiki 上**（`PortalUrl` / 站点地址可能被视为内部信息）。

### 11.4 ⚠️ 流程里"环境变量失效"的三个位置

**配流程时，以下三个位置用不了环境变量，必须手工选/填，且迁移时要重做：**

| # | 位置 | 处理 |
|---|---|---|
| 1 | **FL-01 触发器的 Form Id** | 手工选（或填 GUID）→ 迁移时重做（**`04` §1.4 / §4.2**） |
| 2 | **Teams 动作的 `Team` / `Channel`** | 手工选（**`05` §3.5**）→ 迁移时重做 |
| 3 | **SharePoint 动作的 `Site Address` / `Library Name`** | ⚠️ **可能是选择器**（不是文本输入）→ 手工选 → 迁移时重做 |

> ⚠️ **这三项必须进 `09` 手册的"迁移后必做清单"，且要逐项打勾。**
> **忘做的后果**：流程能跑、不报错，但**通知发到 DEV 频道 / 文件传到 DEV 站点**。

### 11.5 一个"防御性"技巧（推荐）

**在每条流程的说明（Description）里，把"该流程依赖的手工配置项"列出来。**

例：

```
FL-02 问题创建通知
依赖环境变量：PortalUrl, ModelDrivenAppId
⚠️ 手工配置项（迁移后必须重做）：
  - Teams 动作的 Team = "Digital Solution Operation Center"
  - Teams 动作的 Channel = "01-新问题受理"
```

> ⚠️ **这样迁移时，只要打开每条流程看一眼说明，就知道要改哪些东西。** 比翻文档快得多。

---

## 12. 运维：拥有者登记与交接

> ⚠️ **本章是 `03` §3.8 的落地。** **它是"无代码方案"最大的运维风险。**

### 12.1 流程拥有者登记表（必须建，必须维护）

| 流程 | 连接拥有者（主） | 连接拥有者（备） | 共享给 | 最后核对日期 |
|---|---|---|---|---|
| FL-01 表单建单 | | | | |
| FL-02 问题创建通知 | | | | |
| FL-03 状态变更通知 | | | | |
| FL-04 SLA 扫描与升级 | | | | |
| FL-05 关闭确认 | | | | |
| FL-05b 超时自动关闭 | | | | |
| FL-06 发布审批 | | | | |
| FL-07 日志包登记 | | | | |
| FL-08 健康日报 | | | | |

> ⚠️ **"共享给"必须至少有 2 个人**。**否则主拥有者离职时，没人能打开这条流程。**

**共享流程的步骤**：

1. `make.powerautomate.com` → **Solutions** → `SysOpsStandard`
2. 找到流程 → 行末 **⋯** → **Share**
3. 添加用户 → 权限选 **Can edit**（若需要改）或 **Can view**
4. **Save**

> ⚠️ **"共享"** ≠ **"改拥有者"**。共享之后，**流程仍以原拥有者的身份运行**。
> **改拥有者**：流程详情 → **Owners** → **+ Add owner**（这会让人也能改流程，但**连接仍是原拥有者的**）。
> **要真正换身份运行**，必须**修改流程里的连接**（重建连接引用 → 重新绑定）。
>
> ⚠️ **这就是为什么"选对拥有者"必须在建流程之前决策。**

### 12.2 季度核对清单

**每季度做一次，指定责任人：**

- [ ] 打开 §12.1 的表格，逐个流程核对
- [ ] 检查每个拥有者**是否仍在职**
- [ ] 检查每个流程**是否仍在启用状态**
- [ ] 检查**连接引用是否有效**（解决方案 → 连接引用，看有无警告）
- [ ] 检查**最近的运行历史**（是否有失败堆积）
- [ ] 检查 **`automationupdate = 是` 且超时未变**的记录（§8.5 的视图）
- [ ] 检查**健康日报是否每天都有发**（§9.2）
- [ ] 更新"最后核对日期"列

> ⚠️ **这个季度核对是"发现静默故障"的主要手段。** **不要跳过。**

### 12.3 拥有者离职时的交接清单

| # | 步骤 |
|---|---|
| 1 | 用 §12.1 的表格，列出该人的**所有流程**和**所有连接** |
| 2 | ⚠️ **在该人账号停用之前**，把每条流程 **Share** 给接班人，并**设为共同拥有者** |
| 3 | **重建连接**：让接班人**在自己的账号下创建新连接**，然后修改流程的每个动作，改用新连接 |
| 4 | 运行每条流程做一次测试（**手工触发**） |
| 5 | ⚠️ **确认环境变量的值没变**（换连接不会影响环境变量，但要确认） |
| 6 | **确认第三方连接**（Teams / SharePoint / Outlook）都重新授权了 |
| 7 | 更新 §12.1 表格 |
| 8 | ⚠️ **停用该人的账号之后，再回来测一遍**（确保没有残留的依赖） |

> ⚠️ **第 8 步很容易漏，但很重要。** 有些"隐性依赖"（如流程里引用了该人个人 OneDrive 上的文件）**只有在账号停用后才会暴露**。

---

## 13. S4 出口检查表

### 环境变量与连接

- [ ] 9 个环境变量已建，**另补建 `ModelDrivenAppId`**（共 10 个）
- [ ] 每个环境变量的**默认值 = 占位符**，**当前值 = DEV 真实值**
- [ ] 6 个连接引用已建并绑定有效连接
- [ ] §11.3 的**配置值登记表 DEV 列已填满**
- [ ] 未使用保留名 `$authentication` / `$connection`

### 流程

- [ ] FL-01…FL-08 全部建在 **`SysOpsStandard`** 内
- [ ] 每条流程的**说明（Description）已写**，含"依赖的环境变量"与"手工配置项"
- [ ] 每条流程的 **Settings**：并发度（⚠️ **FL-05 是例外，不是 1**）/ 超时 / 重试
- [ ] **没有任何硬编码**（频道 ID / 站点 URL / 表单 ID 全部走变量或手工选择器）

### 防循环

- [ ] **`bjops_lastnotifiedstatus` 列已补建**
- [ ] **`bjops_lastmodifiedbyemail` 列已补建**
- [ ] **`bjops_closeconfirmationrequested` 列已补建**
- [ ] **`bjops_warnhours` 列已补建**（或在 `附录A` 记录"接受硬编码"）
- [ ] FL-03 用**影子列**防循环（不是 `automationupdate`）
- [ ] FL-04 / FL-06 的 `automationupdate` **用完已设回 `否`**
- [ ] §8.5 的**排查视图**已建
- [ ] ✅ **已实测：任意两条流程之间不形成无限循环**（连续改 5 次状态，运行次数可预期）

### 通知

- [ ] Adaptive Card JSON 已粘，`${}` 已全部替换（或改用 Compose）
- [ ] **通知已分级**（不是每个状态都发频道）
- [ ] `WaitingForInfo` 与 `Monitoring` **都发报告人**
- [ ] 关闭确认卡片**发一对一**（不是频道）
- [ ] **所有"给报告人发消息"的动作都包在 Scope 里，失败不中断**

### 测试

- [ ] **端到端联调通过**：表单 → 建单 → 通知 → 状态流转 → 关闭
- [ ] **SLA 扫描已用真实超时记录验证**
- [ ] **健康日报已成功发过一次**
- [ ] **每条流程都手工触发测试过一次**

### 运维

- [ ] **§12.1 流程拥有者登记表已建并填满**
- [ ] **每条流程至少共享给 2 个人**
- [ ] **季度核对清单已交给指定责任人**
- [ ] **离职交接清单已交给 HR/IT 流程**

---

**相关文档**：[`04-问题入口手册.md`](04-问题入口手册.md) · [`06-附件与日志采集手册.md`](06-附件与日志采集手册.md) · [`10-验收与日常运维手册.md`](10-验收与日常运维手册.md) · [`../docs/Phase1-实施方案.md`](../docs/Phase1-实施方案.md) §13
