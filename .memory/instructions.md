# Instructions

- [memory-after-every-commit] 每次 git commit 后必须写一次关键记忆（目的、核心决策、已验证结果、已知风险）。用户 2026-10-08 定的规则。模型切换后也照办。用 storeMemory，同 slug 覆盖不重复。

- [memory-sync-two-layers] 两层记忆必须同步。第 1 层 = hackLM 记忆（storeMemory/queryMemory），物理存在 .memory/*.md 这 5 个文件里。第 2 层 = /memories/repo/*.md，细节层，放行号级踩坑与实测。硬规则：① 新增记忆一律走 storeMemory，不手改 .memory/*.md，否则分叉；② 每次 commit 后两层都刷新；③ .github/copilot-instructions.md 在 hacklm-memory 标记之间的内容不由人手改。

- [three-verification-gates] 改动后必跑三道闸门。① tools/Test-ETScripts.ps1 -Fix（BOM+语法，要 ALL CHECKS PASSED）② tools/Test-ETIntegration.ps1（要 FAIL 0；基线 PASS 46 / FAIL 0 / WARN 1）③ Start-ETWorkbench.ps1 -SelfTest（退出码 0，必须在全新进程里跑，否则被单实例锁拦成假失败）。pre-push 钩子已装。测试失败先看闸门，别猜。

- [doc-writeback-required] 每次开发会话结束前必须回写三份文档：ET-项目待办事项.md（唯一待办汇聚点，§5 有模板）、ET-SYS_开发进度.md（唯一进度真相来源）、docs/interface-contract.md（若涉接口）。不回写等于没做完。

- [fix-with-regression-gate] 修复一个会复发的缺陷时，同一次提交里必须加一道自动门禁把它锁住（例：主窗口缺键启动失败的反向门禁）。只改代码不加门禁，算没修完。

- [known-defect-ledger] 每次提交后的记忆里刷新已知缺陷台账：未修的保留编号加一句话现象，修好的标已修并保留。编号一旦分配，永不删除、永不复用。

- [memory-boundary-engineering-first] .memory 只存工程长期事实（架构承诺、接口契约、安全红线、可复用踩坑）。临时运行噪声（终端乱码、一次性命令输出、当次会话状态）不进 Decisions；放会话记忆或 Quirks 的「代理运行」分组。
