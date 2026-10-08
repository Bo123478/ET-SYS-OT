# Quirks

## Engineering

- [powershell51-strictmode-traps] PowerShell 5.1 + Set-StrictMode 2.0 陷阱：① 读不存在的哈希键/属性会抛错不是返回 $null（错误文案「在此对象上找不到属性"X"」= $ui 缺键第一嫌疑）；② 裸 switch 不能作命令实参，先提为变量；③ -f 比 + 结合更紧，格式串先提变量；④ -contains 在命令调用后会被当参数名，要加括号；⑤ Try 是保留字不能当函数名；⑥ 验证 .ps1 语法必须用带类型的局部变量 $tokens/$errors = $null，[ref]$null 会假阳性通过。

- [session0-no-desktop] VS Code 终端跑在 Session 0（无交互桌面），WPF 无法显示/截图，UserInteractive=False。GUI 验证只能靠：-SelfTest + XamlReader::Load + $ui.* 静态引用 + 日志停在「窗口已就绪」。判断能否起 UI 用 [System.Environment]::UserInteractive。「好不好看/有无遮挡」必须真人上桌面看。-SelfTest 必须在新进程里跑。

- [markdown-table-corruption] 改 Markdown 表格行时 oldString 必须包含行尾的 ` |`（只匹配部分行会把旧尾巴拼进新内容）。本仓库已发生 8 次两行挤成一行。改完立刻回读该行，用 Select-String '^\|' 查行号连续性。multi_replace 不能改 /memories/ 路径。

- [git-cannot-enforce-bom] Git 无法强制 BOM（.gitattributes 只管换行与文本/二进制分类）。BOM 唯一强制点 = pre-push 钩子（.git/hooks/pre-push，用 tools/Install-ETHooks.ps1 装）。Test-ETScripts.ps1 不处理 .md，默认也不扫仓库根与 docs/ ⇒ .md 必须手动加 BOM。create_file 产出无 BOM 的 UTF-8。加 BOM 手法：[System.IO.File]::WriteAllText($p, $t.TrimStart([char]0xFEFF), (New-Object System.Text.UTF8Encoding($true)))

- [known-open-defects] 已知缺陷勿重复报告：D-3 paths.json 声明 .ndjson 但 ET.Outbox 写 .json（待站会定）；D-6 Test-ETFreeSpace 目标盘不可达静默回退系统盘（ET.Transfer.psm1:75-110）；D-09 双击 Start-ETWorkbench.bat 留黑控制台窗（经铭牌启动不会）；T-29 双屏/任务栏在左未验证；T-39 Test-ETIntegration §11 仍探已删的 DgSoftware（稳定打印 7/8，非失败）；D-12 Resolve-ETPlateInfo 半死代码。已修：D-7、D-10、D-13。

- [known-output-is-not-a-new-failure] 输出与台账里登记的已知缺陷现象一致时，算已知情况。不当新失败、不重复排查、不再报告。

- [half-dead-code-not-deleted] 半死代码指还在仓库里但已无调用点的函数。发现后只登记编号，不得顺手删除或重构，去留由站会定。
- [memory-files-eol-lf] .memory/*.md 由 hackLM 工具写入，行尾是 LF。.gitattributes 却对 *.md 声明 eol=crlf。两者不一致 ⇒ 提交时 git 会警告「LF 将被替换为 CRLF」，属无害噪声。别手动改这些文件的换行，工具下次写入又变回 LF。

## Agent Runtime

- [agent-memory-tool-editing-quirks] memory 工具 str_replace：path 必须用 /memories/... 形式，一次一条；old_str 必须覆盖整块（只匹配开头会留下孤立旧尾巴 = 整块被复制）；repo 记忆文件用 CRLF 且正文用全角标点 ⇒ 多行 old_str 几乎必报 did not appear verbatim，解法是单行 str_replace + memory insert 按行号插入。每次编辑后立刻回读文件。

- [agent-memory-tool-may-be-absent] hackLM 的 storeMemory/queryMemory 工具并非每轮都挂载。工具不可用时，直接按同格式手改 .memory/*.md（# 标题 + 空行 + `- [kebab-slug] 内容`，块间空行分隔），写回后立刻用 Get-Content -Encoding UTF8 复核。

- [agent-memories-layer-not-durable] /memories/（含 repo）不是可靠持久层。2026-10-08 实测：同一会话内 /memories/ 突然全部返回「No memories found」，磁盘上也找不到对应文件（$env:USERPROFILE、.vscode-server\data\User\globalStorage、workspaceStorage 都搜过，无 memories 目录）。结论：唯一可靠记忆层 = 随 git 走的 .memory/*.md。/memories/repo/* 丢了就从 .memory 重建，别在它上面放唯一副本。2026-10-08 已按仓库文档重建 `et-sys-context.md` 与 `et-workbench.md`（原 108/419 行内容不可恢复 —— 转录只留本次会话、debug 日志 main.jsonl 为空、仅存在一个会话）。重建件头部已注明「细节层、冲突时以仓库文档为准」。

- [agent-never-recurse-userprofile] 别对 $env:USERPROFILE 做全量 Get-ChildItem -Recurse（含 -Force 更慢）。实测 120 秒必超时被踢到后台。查文件先限定目录：工作区、.vscode-server\data\User、$env:APPDATA。

- [agent-push-credential-store-warning-is-harmless] 本机 git push 可能报 wincredman 凭据持久化失败。判定推送是否成功只看 origin/master..HEAD 是否为 0。
