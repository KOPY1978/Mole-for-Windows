# Changelog

## Unreleased — 2026-09-29

- 接手复现三组本地测试，各 21/21；记录上游实验状态、远程缺失源码与待补安全测试。
- CI 改为 Windows PowerShell 5.1 / PowerShell 7 两个显式 job，固定 Pester 6.2.0，增加手动触发、只读仓库权限和超时。
- CI 增加源码完整性检查及“至少 21 项、全通过、无跳过/未运行”门槛，并加入只读 CLI 冒烟检查。
- 新 CI 测试步骤在本地双运行时通过；不完整远程树被门槛正确拒绝。远程发布和 Actions 验证仍待完成。
- 新增 `.gitignore`，避免提交本地原始快照、下载资料及测试日志；本轮未修改清理内核或新增提供器。

## 0.5.0 — 2026-09-28

- 增加 `Get-MoleCleanupSummary`，汇总可清理/跳过目标和估算空间。
- 将 `analyze` 接入 provider 清理计划，输出摘要并审计 dry-run，不执行删除。
- CI 改为 Windows PowerShell 5.1 / PowerShell 7 双矩阵，安装 Pester 6 并处理旧 Pester publisher 冲突。
- 测试断言 helper 同时支持 Pester 3.4.0 和 Pester 6；Windows PowerShell 5.1 下两者各 21/21，便携 PowerShell 7.6.6/Pester 6.2.0 也 21/21。

## 0.4.0 — 2026-09-28

- 增加 Chrome、Edge、Firefox 默认磁盘缓存目录发现；不扫描 Cookie、History、登录资料或自定义用户数据目录。
- 增加浏览器活动进程检查：计划阶段拒绝活动浏览器，执行前及逐目标删除前重新检查。
- 清理计划附带估算字节数，CLI 显示可回收空间估算。
- CLI 默认追加 JSONL 审计事件：计划、执行开始、备份成功/失败、逐目标删除和执行完成/中断。
- 增加对应路径发现、缓存计划、活动进程拒绝、估算及审计测试；本机 Pester 3.4.0 为 19/19。
- 将 CI 改为 Windows PowerShell 5.1 / PowerShell 7 双矩阵，使用 Pester 6，并保留 Pester 3 本机测试兼容。

## 0.3.0 — 2026-09-28

- 增加常见用户级 npm、Yarn、pnpm、pip、NuGet、Cargo 和 Go 缓存路径。
- 跳过锁文件/活动标记和年龄阈值以内的文件。

## 0.2.0 — 2026-09-28

- 增加带 SHA-256 清单的文件备份与恢复，恢复时校验路径和文件哈希。
- 增加用户 TEMP 提供器及显式 `-Execute -BackupRoot` 备份后删除流程。
- 执行前重新校验 allowlist、受保护路径和 reparse point 祖先。
- 默认 CLI 行为保持 dry-run。

## 0.1.0 — 2026-09-28

- 初始安全内核骨架、项目章程、架构说明、Pester 测试和 CI workflow。
