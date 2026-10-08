# Quirks

- [powershell51-strictmode-traps] PowerShell 5.1 + Set-StrictMode 2.0 陷阱：① 读不存在的哈希键/属性会抛错不是返回 $null（错误文案「在此对象上找不到属性"X"」= $ui 缺键第一嫌疑）；② 裸 switch 不能作命令实参，先提为变量；③ -f 比 + 结合更紧，格式串先提变量；④ -contains 在命令调用后会被当参数名，要加括号；⑤ Try 是保留字不能当函数名；⑥ 验证 .ps1 语法必须用带类型的局部变量 $tokens/$errors = $null，[ref]$null 会假阳性通过。

- [session0-no-desktop] VS Code 终端跑在 Session 0（无交互桌面），WPF 无法显示/截图，UserInteractive=False。GUI 验证只能靠：-SelfTest + XamlReader::Load + $ui.* 静态引用 + 日志停在「窗口已就绪」。判断能否起 UI 用 [System.Environment]::UserInteractive。「好不好看/有无遮挡」必须真人上桌面看。-SelfTest 必须在新进程里跑。

- [markdown-table-corruption] 改 Markdown 表格行时 oldString 必须包含行尾的 ` |`（只匹配部分行会把旧尾巴拼进新内容）。本仓库已发生 8 次两行挤成一行。改完立刻回读该行，用 Select-String '^\|' 查行号连续性。multi_replace 不能改 /memories/ 路径。

- [git-cannot-enforce-bom] Git 无法强制 BOM（.gitattributes 只管换行与文本/二进制分类）。BOM 唯一强制点 = pre-push 钩子（.git/hooks/pre-push，用 tools/Install-ETHooks.ps1 装）。Test-ETScripts.ps1 不处理 .md，默认也不扫仓库根与 docs/ ⇒ .md 必须手动加 BOM。create_file 产出无 BOM 的 UTF-8。加 BOM 手法：[System.IO.File]::WriteAllText($p, $t.TrimStart([char]0xFEFF), (New-Object System.Text.UTF8Encoding($true)))

- [memory-tool-editing-quirks] memory 工具 str_replace：path 必须用 /memories/... 形式，一次一条；old_str 必须覆盖整块（只匹配开头会留下孤立旧尾巴 = 整块被复制）；repo 记忆文件用 CRLF 且正文用全角标点 ⇒ 多行 old_str 几乎必报 did not appear verbatim，解法是单行 str_replace + memory insert 按行号插入。每次编辑后立刻回读文件。

- [project-quirks] Project-specific weirdness — the non-obvious stuff.

- [known-open-defects] 已知缺陷勿重复报告：D-3 paths.json 声明 .ndjson 但 ET.Outbox 写 .json（待站会定）；D-6 Test-ETFreeSpace 目标盘不可达静默回退系统盘（ET.Transfer.psm1:75-110）；D-09 双击 Start-ETWorkbench.bat 留黑控制台窗（经铭牌启动不会）；T-29 双屏/任务栏在左未验证；T-39 Test-ETIntegration §11 仍探已删的 DgSoftware（稳定打印 7/8，非失败）；D-12 Resolve-ETPlateInfo 半死代码。已修：D-7、D-10、D-13。

- [known-output-is-not-a-new-failure] 输出与台账里登记的已知缺陷现象一致时，算已知情况。不当新失败、不重复排查、不再报告。

- [half-dead-code-not-deleted] 半死代码指还在仓库里但已无调用点的函数。发现后只登记编号，不得顺手删除或重构，去留由站会定。
