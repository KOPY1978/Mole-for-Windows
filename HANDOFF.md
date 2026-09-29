# Mole for Windows：AI 交接文档

更新时间：**2026-09-29（Asia/Singapore）**

这份文档面向下一位接手本项目的 AI。先读本文件，再读 `README.md`、`ROADMAP.md` 和源码；不要把远程 GitHub 仓库当作完整代码源，当前完整代码以本地工作区为准。

## 1. 项目目标

把 Mole 的安全清理体验移植到 Windows 10/11，目标是：

- 默认 dry-run；
- 删除前生成可审计计划；
- allowlist、protected path 和 reparse point 防护；
- 备份、恢复和 SHA-256 校验；
- 可解释的空间估算；
- 可单独启停的清理 provider。

## 2. 本地工作区

路径：`C:\Users\23107\Mole-for-Windows`

本目录**没有 `.git` 元数据，也没有 Git remote**。本地文件清单：

```text
README.md
PROJECT_CHARTER.md
ARCHITECTURE.md
ROADMAP.md
CHANGELOG.md
.github/workflows/powershell-tests.yml
scripts/mole.ps1
src/Mole.Windows/Mole.Windows.psd1       # ModuleVersion 0.5.0
src/Mole.Windows/Mole.Windows.psm1
src/Mole.Windows/Mole.Backup.ps1
src/Mole.Windows/Mole.Providers.ps1
tests/Safety.Tests.ps1
tests/TestHelpers.ps1
```

## 3. 已实现能力

### 安全内核

位于 `src/Mole.Windows/Mole.Windows.psm1`：

- 路径规范化和大小写无关的 containment 检查；
- 默认保护 Windows/System/Program Files/ProgramData、用户文档目录、`.ssh`、`.gnupg` 等；
- 拒绝磁盘根目录、allowlisted root 本身和 reparse-point 祖先；
- 清理计划生成；
- 默认 dry-run；
- 执行前、逐目标执行前重新验证；
- 浏览器 provider 执行期间再次检查浏览器进程；
- JSONL 审计事件；
- `Get-MoleCleanupSummary` 汇总目标数量、跳过数量和估算字节。

### 备份/恢复

位于 `src/Mole.Windows/Mole.Backup.ps1`：

- 文件备份 manifest；
- 文件 SHA-256；
- manifest 路径 containment 校验；
- 恢复前/恢复后哈希验证；
- protected path 恢复拒绝；
- 当前只允许文件和空目录安全备份，非空目录会拒绝。

### 清理 provider

位于 `src/Mole.Windows/Mole.Providers.ps1`：

| Provider | 作用 | 默认阈值 |
|---|---|---:|
| `user-temp` | 当前用户 TEMP 下的旧文件 | 3 天 |
| `dev-cache` | npm、Yarn、pnpm、pip、NuGet、Cargo、Go 用户缓存 | 14 天 |
| `browser-cache` | Chrome/Edge 的 `Cache`、Firefox 的 `cache2` | 14 天 |

浏览器 provider 只扫描已知默认 profile（`Default`、`Profile N`、`Guest Profile` 等），不扫描 Cookie、History、Login Data、扩展数据或未知 profile。Chrome/Edge/Firefox 运行时拒绝计划和执行。自定义 user-data-dir、非标准安装路径、Firefox MSIX 暂不支持。

### CLI

入口：`scripts/mole.ps1`

```powershell
.\scripts\mole.ps1 status
.\scripts\mole.ps1 providers
.\scripts\mole.ps1 analyze -Provider dev-cache
.\scripts\mole.ps1 clean -Provider browser-cache
.\scripts\mole.ps1 clean -Provider browser-cache -Execute `
  -BackupRoot "$env:LOCALAPPDATA\Mole\backups" `
  -AuditPath "$env:LOCALAPPDATA\Mole\audit\operations.jsonl"
```

`-Execute` 外的行为为 dry-run。默认审计位置为 `%LOCALAPPDATA%\Mole\audit\operations.jsonl`。

## 4. 本地验证证据

已在当前机器验证：

- Windows PowerShell 5.1 + Pester 3.4.0：**21 passed / 0 failed**；
- Windows PowerShell 5.1 + Pester 6.2.0：**21 passed / 0 failed**；
- 便携 PowerShell 7.6.6 + Pester 6.2.0：**21 passed / 0 failed**；
- PowerShell AST 检查：6 个 `.ps1/.psm1/.psd1` 文件，0 语法错误；
- PowerShell 5.1 / 7.6.6 下 `status`、`providers` CLI 冒烟通过。

本机没有系统安装的 `pwsh.exe`；7.6.6 是下载到 `%TEMP%\mole-pwsh-7.6.6` 的便携运行时，未写系统注册表。

## 5. GitHub 远程仓库状态

已通过测试账号创建公开仓库：

```text
https://github.com/KOPY1978/Mole-for-Windows
```

已知远程提交：

- `35e26c9`：初始上传（远程文件树曾显示不完整）；
- `7228b95`：`Add CI workflow`。

### 重要：远程代码不完整

远程仓库根页面当前只显示：

- `.github/workflows/`；
- 根目录的 `powershell-tests.yml`。

本地的 `src/`、`tests/`、`scripts/`、文档等**尚未可靠地出现在远程树中**。原因是 Chrome 上传控件多次选择文件时会替换/扁平化选择结果。下一位 AI 必须先把本地完整目录正确提交到远程，再相信 CI 结果。

### 已知远程 CI 失败原因

GitHub Actions run：`36520893565`（commit `7228b95`）失败；页面给出的解析错误是：

```text
(Line: 31, Col: 16): Unrecognized named-value: 'matrix'.
Located at position 1 within expression: matrix.shell
(Line: 38, Col: 16): Unrecognized named-value: 'matrix'.
Located at position 1 within expression: matrix.shell
```

当前 workflow 在 `steps[*].shell` 使用 `${{ matrix.shell }}`，GitHub 解析器拒绝这种写法。不要直接 rerun 该 run；先修 workflow，再推送新 commit。

推荐改为两个显式 job，避免动态 `shell`：

```yaml
jobs:
  pester-windows-powershell:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - shell: powershell
        run: |
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
          Install-Module Pester -MinimumVersion 6.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
          $r = Invoke-Pester -Path ./tests -PassThru
          if ($r.FailedCount -gt 0) { exit 1 }

  pester-pwsh:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - shell: pwsh
        run: |
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
          Install-Module Pester -MinimumVersion 6.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
          $r = Invoke-Pester -Path ./tests -PassThru
          if ($r.FailedCount -gt 0) { exit 1 }
```

## 6. Chrome MCP 诊断结果

当前 Codex 会话没有直接暴露 Chrome MCP namespace，但本地 MCP 服务可用。根因不是 VPN/代理，而是 Bearer 认证缺失：

- 无认证 `initialize`：HTTP 401，正文 `{"error":"Unauthorized"}`；
- 认证后 `initialize`：HTTP 200；
- `tools/list`：27 个工具；
- `get_windows_and_tabs`：成功；
- 当前用户环境变量已配置 `CHROME_MCP_HTTP_TOKEN`（不记录 token 值）；
- `codex mcp get chrome-mcp-server` 应显示：

```text
transport: streamable_http
url: http://127.0.0.1:12306/mcp
bearer_token_env_var: CHROME_MCP_HTTP_TOKEN
```

为支持上传和 JavaScript，当前用户还配置了：

```text
MCP_ALLOWED_CAPABILITIES=filesystem.upload,browser.javascript
```

Chrome Native host 注册路径：

```text
C:\Users\23107\AppData\Roaming\Google\Chrome\NativeMessagingHosts\com.chromemcp.nativehost.json
```

其 executable 指向：

```text
C:\Users\23107\mcp-chrome\app\native-server\dist\run_host.bat
```

下一位 AI 不应读取或输出 token、Cookie、Chrome profile 或 GitHub 凭证。需要 MCP 时，使用本地已配置 Bearer 的连接；操作后只输出脱敏状态。

## 7. 当前阻塞与优先级

### P0：让远程仓库成为完整代码仓库

1. 修复 workflow 的动态 `matrix.shell`；
2. 把本地 `src/`、`tests/`、`scripts/`、文档正确提交到远程，保持目录结构；
3. 确认 GitHub 根页面出现 `src`、`tests`、`scripts`；
4. 确认 `.github/workflows/powershell-tests.yml` 只保留正确版本；
5. 推送新 commit，等待 Actions 两个 job 完成。

### P1：远程 CI gate

只有 Windows PowerShell 5.1 和 PowerShell 7 两个远程 job 都成功，才满足用户设定的 gate。不要用本机 21/21 替代远程 CI 证据。

### P2：Crash-dump provider

远程 CI 通过后再开始。建议：

- 先写 Pester 红测试，再实现 provider；
- 目标限定为用户级 WER/应用崩溃转储目录；
- 默认只处理超过年龄阈值且未锁定的文件；
- 排除系统目录、当前活动转储、锁文件和非标准路径；
- 接入 `Get-MoleProviderCatalog`、`New-MoleProviderPlan`、空间估算、审计和备份后删除；
- 不默认清理内核转储、系统级 Windows Error Reporting 目录或未知 `.dmp` 文件。

## 8. 推荐接手顺序

```text
读取 HANDOFF.md
  -> 检查本地文件与远程根目录
  -> 修复 workflow matrix.shell
  -> 正确上传/提交完整源树
  -> 观察 Actions run 失败/成功
  -> 必要时修复 Windows runner 兼容性
  -> 两个 CI job 全部通过
  -> 为 crash-dump provider 写红测试
  -> 实现 provider、回归测试和文档
```

## 9. 安全边界

- 不打印或提交 `CHROME_MCP_HTTP_TOKEN`；
- 不读取 GitHub token、Cookie、Chrome profile 或账号凭证；
- 不对宿主机真实缓存执行 `-Execute`，除非用户明确指定目标和备份目录；
- 任何新 provider 必须先 dry-run、测试、审计，再加入默认可选列表；
- 所有远程 UI 操作都要核对当前 tab URL、页面文本和提交结果，避免引用过期 ref。
