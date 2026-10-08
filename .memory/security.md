# Security

- [hard-constraints-c1-c8] 硬性约束（方案 §3.2，违反即返工）：C-1 含中文 .ps1/.psm1/.json 必须 UTF-8 with BOM；C-2 路径必须由 $PSScriptRoot 推导禁止硬编码；C-3 GUI 只传标识符（SoftwareId/RuleId）禁传任意路径执行；C-4 共享写入原子（.tmp→校验 Size+Hash→rename .ready）；C-5 One Event = One File；C-6 Downloaded 不得显示为已安装/已生效；C-7 同一配置禁并发写 / 同时只 1 个下载；C-8 空间不足暂停，绝不删业务文件。

- [red-lines-f1-f12] 红线 F-1…F-12 禁止：自动结束/重启业务软件、覆盖运行中程序文件、强解文件锁、强抢焦点/置顶、自动重启电脑、改其他进程优先级、自动系统修复/服务重启/进程终止、接受任意路径直接执行、把 Downloaded 显示为已生效、空间不足删业务文件、ET 端建 HTTP/API Server 或开放端口、读写其他设备的 Upload 目录。注意：F-4 禁的是 Topmost/抢焦点，不禁沉底（HWND_BOTTOM 是反面，合规）。

- [frozen-interface-contract] docs/interface-contract.md = ET-IFC-001 v1.0.0，83 个导出函数冻结基线，保管人 A(WHB)。冻结：函数名、参数名/类型/Mandatory/ValidateSet、返回结构字段名、§6 错误语义。未冻结：内部实现、私有函数、日志文案、Config/*.json 的值。改签名必须走 §1.3 流程（站会 + 变更日志 + 版本号递增）。禁单人改导出签名后提交。

- [protected-files] 不得修改：ET-SYS_开发方案.md（方案基线）、SYS-Operational Technology/现场数字化运维最终方案_PowerShell_M365_Databricks.md（ET 技术基线）、docs/ET工作台方案_Version2.md（业务语义权威，只加实现注记）。必须持续更新：ET-SYS_开发进度.md（有 BOM，勿去 BOM）、ET-项目待办事项.md。
