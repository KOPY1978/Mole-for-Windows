# 架构与安全基线

## 分层

```text
CLI / TUI
   |
Command orchestration (PowerShell)
   |
Safety kernel
  - path canonicalization
  - allowlist / protected paths
  - dry-run plan
  - backup manifest
  - confirmation and audit log
   |
Cleanup providers
  - temp files
  - browser caches
  - developer caches
  - package-manager caches
  - logs / crash dumps
  - registry / app remnants (later phase)
```

## 安全内核要求

1. 先解析真实路径，再做允许性判断；不得只对原始字符串做匹配。
2. 拒绝磁盘根目录、系统目录、用户配置根目录和未明确批准的 reparse point。
3. 生成删除计划后才允许执行；`dry-run` 与真实执行必须共用同一计划生成器。
4. 备份清单记录原路径、文件类型、大小、哈希（可选）和恢复位置。
5. 单个提供器失败不得自动扩大到父目录或相邻目录。
6. 所有管理员权限提升都必须在界面中说明原因，并允许取消。

## 提供器接口（设计草案）

每个提供器应返回：

- `Id`：稳定标识；
- `Title`：用户可读名称；
- `Discover()`：只读发现候选项；
- `Plan()`：生成带来源的清理计划；
- `Execute()`：只执行已确认计划；
- `Restore()`：从备份清单恢复；
- `Risk`：low / medium / high；
- `RequiresElevation`：是否需要管理员权限。

## Windows 特有处理

- 兼容 PowerShell 5.1 的语法和编码；
- 对长路径、锁定文件、junction/reparse point、ACL 拒绝和 UAC 分别测试；
- 区分 Win32、MSIX/UWP、便携式应用和开发工具，不用单一规则推断卸载残留；
- x64 先行，ARM64 作为独立构建目标验证。

## 浏览器缓存提供器边界

- 仅支持已知的默认用户数据根和 `Default` / `Profile N` / `Guest Profile` 等浏览器 profile 目录。
- Chrome/Edge 只进入 profile 下的 `Cache`；Firefox 只进入本地 profile 缓存目录 `cache2`。
- 不发现或删除 Cookie、History、Login Data、扩展数据、Service Worker 存储或未知 profile 文件。
- 发现 Chrome、Edge 或 Firefox 进程时拒绝生成清理计划；执行前以及每个目标删除前再次检查进程状态。
- 自定义 `--user-data-dir`、非标准安装路径和 Firefox MSIX 打包路径暂不支持。

## 审计与预览

- 清理计划包含逐目标 `SizeBytes` 和总估算值；估算可能随文件活动变化，不是磁盘空间释放保证。
- CLI 默认向 `%LOCALAPPDATA%\Mole\audit\operations.jsonl` 追加 JSONL 事件；可通过 `-AuditPath` 改写。
- 审计事件记录目标路径、事件类型、估算字节数和备份 manifest 路径，不复制或记录缓存内容。
- dry-run 也会记为 `plan-created`，但不创建备份、不修改目标。
