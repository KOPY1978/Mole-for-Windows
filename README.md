# Mole for Windows

本目录是 Mole for Windows 的正式推进工作区。目标是把官方 Windows 实验分支推进为可审计、可回滚、可发布的 Windows 版本，而不是直接复刻 macOS 的删除逻辑。

## 当前阶段

**Phase 2 — 部分清理提供器已实现；安全补测与远程 CI 待完成（2026-09-29）**

接手核验与证据见 [TAKEOVER_REVIEW.md](TAKEOVER_REVIEW.md)。本地测试通过不等于已达到发布门槛；崩溃转储提供器尚未实现，执行期路径变化与备份一致性仍需补测。

- 明确 Windows 版本与 macOS 版本的功能边界。
- 所有破坏性操作默认支持 `dry-run`，并在执行前完成路径白名单与受保护路径校验。
- 先建立可测试的核心库，再接入具体清理提供器。
- 已加入文件备份清单、SHA-256 恢复校验、恢复原语和首个用户 TEMP 清理提供器。
- 已加入开发工具缓存提供器，覆盖 npm、Yarn、pnpm、pip、NuGet、Cargo 和 Go 的常见 per-user 缓存路径；锁文件和近期文件默认跳过（默认年龄阈值 14 天）。
- 已加入 Chrome Stable、Edge Stable、Firefox 桌面版的常见磁盘缓存目录发现；只枚举 Cache/cache2，不进入 Cookie、History、登录资料等 profile 数据；浏览器进程运行时拒绝生成计划，并在执行前/每个目标删除前再次检查。自定义目录和 Firefox MSIX 包装版暂不扫描。
- 清理计划显示估算字节数；CLI 默认写 JSONL 审计记录，包含 dry-run 计划、备份清单路径和逐目标执行结果。
- `analyze` 现在可按 provider 或显式路径输出可清理/跳过数量、预计空间和审计日志；不执行清理。
- 真实删除现在仅在显式传入 `-Execute -BackupRoot <目录>` 时执行，并且删除前会重新校验路径、生成备份清单；默认仍为 dry-run。

示例（默认仅预览；Chrome/Edge/Firefox 必须先关闭；自定义安装路径/用户数据目录和 Firefox MSIX 暂不扫描）：

```powershell
.\scripts\mole.ps1 clean -Provider browser-cache
.\scripts\mole.ps1 analyze -Provider dev-cache
.\scripts\mole.ps1 clean -Provider browser-cache -Execute `
  -BackupRoot "$env:LOCALAPPDATA\Mole\backups" `
  -AuditPath "$env:LOCALAPPDATA\Mole\audit\operations.jsonl"
```

## 本地验证

在 Windows PowerShell 5.1 或 PowerShell 7 中运行：

```powershell
Invoke-Pester -Path .\tests -PassThru
.\scripts\mole.ps1 status
.\scripts\mole.ps1 providers
```

2026-09-29 已重新验证：Windows PowerShell 5.1 下 Pester 3.4.0 和 6.2.0 各 21/21；便携 PowerShell 7.6.6 / Pester 6.2.0 也通过 21/21，两个运行时的 `status` / `providers` 冒烟检查通过。测试断言 helper 兼容 Pester 3 与 Pester 5+。

CI 已改为两个显式 job，固定 Pester 6.2.0，并要求完整源码、至少 21 项测试、全部通过且无跳过。修改后的 CI 测试脚本已在本地双运行时执行通过，但**尚未推送或获得新的远程 Actions 结果**。旧远程仓库确实只有两份 workflow 文件，不能作为完整项目或成功 CI 的依据。

默认审计日志位置：`%LOCALAPPDATA%\Mole\audit\operations.jsonl`；可用 `-AuditPath` 指定其他位置。JSONL 记录目标路径、估算字节数、事件和备份 manifest 路径，不记录缓存文件内容。

## 官方基线

[上游 tw93/Mole](https://github.com/tw93/Mole/tree/windows) 的 `windows` 分支与 `v1.30.0-windows` 标签已核实存在。上游 README 明确标注 Windows 版本尚不成熟，并警告不要用于包含重要数据的关键机器。当前仅完成引用与运行要求核验，尚未完成源码差异、安全边界及许可证对照；本地实现不能因此视为经过上游验证。

## 文档

- [项目章程](PROJECT_CHARTER.md)
- [架构与安全基线](ARCHITECTURE.md)
- [阶段计划与验收标准](ROADMAP.md)
- [接手调研与验证记录](TAKEOVER_REVIEW.md)

## 贡献原则

1. 任何删除逻辑必须先有 dry-run 和测试。
2. 清理提供器必须声明目标路径、前置条件、估算大小和可恢复性。
3. 不允许依赖模糊的通配符删除用户目录或系统目录。
4. 每个变更都要附带最小可复现测试和回滚说明。

正式发布前仍需确认许可证边界、二进制签名、升级回滚和 x64/ARM64 支持范围。
