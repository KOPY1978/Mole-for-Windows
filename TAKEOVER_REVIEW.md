# 接手调研与验证记录

日期：2026-09-29。范围：本地项目、交接明确引用的测试运行时、两个公开 GitHub 仓库及 GitHub 官方文档。本轮串行处理；不读取凭据，不清理宿主机真实缓存，不推送远程。

## 1. 已独立核实

### 本地基线

- 工作区最初有 14 个项目文件，没有 `.git` 元数据。模块版本为 `0.5.0`。
- 原有测试全部使用 Pester TestDrive 中的专用夹具；以下结果为本轮实际运行，不是转述交接记录：

| PowerShell | Pester | 结果 |
| --- | --- | --- |
| 5.1.26100.8115 | 3.4.0 | 21 passed / 0 failed |
| 5.1.26100.8115 | 6.2.0 | 21 passed / 0 failed |
| 7.6.6（交接指定便携运行时） | 6.2.0 | 21 passed / 0 failed |

PS7 首次启动遇到调用层的引号转义错误，测试未开始；改用编码命令后上述基线通过。后续直接通过 `-File` 执行从 CI 提取的脚本，避免跨版本转义问题。

### 远程项目

来源：<https://github.com/KOPY1978/Mole-for-Windows>。

无认证 `git ls-remote` 与只读浅克隆均显示 `main` / `HEAD` 为：

```text
7228b9549c5f30964db6ba38653a9c2fe4f0bc75
```

`git ls-tree -r --name-only HEAD` 只有：

```text
.github/workflows/powershell-tests.yml
powershell-tests.yml
```

因此“远程缺少 src/tests/scripts”已核实。匿名 GitHub API 被限流，未重复请求，也没有独立获取旧 Actions 日志。HANDOFF 中的 `matrix.shell` 解析错误仍属于前任报告，不能据此证明所有此类表达式都不合法。

### 上游基线

来源：<https://github.com/tw93/Mole/tree/windows>，通过无认证 Git 引用查询与该分支 README 核实：

- `windows` 分支提交：`3365de00351a5b8e816451d7060aa0703cce06c9`。
- `v1.30.0-windows` 标签对象：`632b3bb9d47b4a7746643ac7e1a03ec14e45e7b9`；解引用提交：`3ff9bb94526afa8ad236693995281adaa851f992`。
- README 明确标注 **Experimental Status / not mature**，警告不要用于重要机器。
- README 列出的平台要求为 Windows 10/11、PowerShell 5.1+；本地构建 TUI 可选 Go 1.24+。

以上仅确认上游存在与公开要求。没有完成源码逐项比对、许可证文本核验、发布资产或签名核验，不宣称本项目已获得上游认可或安全验证。

## 2. 本轮实现

只修改验证链和状态文档，不修改清理语义：

1. 工作流改成两个独立 job，分别固定 `powershell` 和 `pwsh`，避免依赖动态 shell 表达式。
2. Pester 固定为本轮已验证的 `6.2.0`；PS5.1 保留 NuGet provider 初始化并开启 TLS 1.2；PS7 不额外调用该旧初始化步骤。
3. 明确检查模块、CLI 和测试文件存在；要求至少 21 项测试，整体 `Passed`，失败、跳过、未运行计数均为零。
4. 增加 `workflow_dispatch`、`contents: read`、15 分钟 job 超时和只读 CLI 冒烟。
5. `.gitignore` 排除 `.artifacts/` 和默认测试报告，避免原始快照和临时证据进入发布树。

参考的 GitHub 官方上下文说明：
<https://docs.github.com/en/actions/reference/workflows-and-actions/contexts>。
该文档不是此次失败的完整复现证据；最终表达式解析与托管 runner 安装行为仍须远程 Actions 验证。

### 本轮变更验证

- PyYAML 结构解析通过；两个 job 的安全测试步骤内容相同。
- PowerShell 5.1 AST：7 个项目 PowerShell 文件及从 YAML 提取的 6 个脚本，共 13 个文件、0 语法错误。
- 从 YAML 原样提取的测试步骤，分别在 PS5.1 / PS7.6.6 中执行：各 21/21，通过新门槛。
- 对真实远程浅克隆执行新门槛，得到 `Incomplete source tree: src/Mole.Windows/Mole.Windows.psd1`，正确拒绝不完整源码。
- 两个运行时的 `status` / `providers` 冒烟均通过。
- 未执行远程 runner 的安装步骤；没有新的远程 CI 成功证据。

证据文件在 `.artifacts/takeover-20260929/`：`ci-local-ps51.log`、`ci-local-ps7.log`、`ci-incomplete-tree.log`、`smoke-ps51.log`、`smoke-ps7.log`，以及公开来源快照。该目录不应提交。

## 3. 安全疑点：待回归测试，不等于已修复

现有 21 项测试不能覆盖以下静态观察。应先在公开接口和专用夹具上稳定复现，再作最小修复：

| 位置 | 观察 | 后续验证 |
| --- | --- | --- |
| `Mole.Windows.psm1` / `Invoke-MoleCleanupWithBackup` | 批量校验之后先备份，删除循环中仅再次检查浏览器活动；没有逐目标重新检查路径或文件内容 | 备份期间文件变化、父目录替换、文件变为目录时应中止，不删除未备份版本 |
| `Mole.Backup.ps1` / `Invoke-MoleBackup` | `Copy-Item` 后仅计算源文件哈希；未比较备份副本，且哈希失败返回 `$null` | 复制不一致或无法取得哈希时应 fail-closed，保留原文件 |
| `Mole.Backup.ps1` / `Restore-MoleBackup` | 备份来源检查字符串 containment，未显式拒绝来源或其祖先 reparse point | 构造夹具中的 junction/篡改 manifest，拒绝越界来源与异常类型 |
| 测试集 | 缺少系统性锁文件、拒绝访问、长路径、junction 与恢复篡改测试 | 不以当前 21/21 替代 Windows 安全边界验收 |

交接文档宣称“逐目标执行前重新验证”，实际源码只实现逐目标浏览器复查，表述过宽。此处以代码观察为准；上述时序问题尚未做运行时复现。

## 4. 下一步与交付门槛

1. 将完整项目保持目录结构提交到正确的远程仓库，保留远程历史，移除远程根目录误上传的 workflow 副本；不要使用网页多次选文件上传，也不要 force-push。
2. 获得同一新提交上的两个 Actions job 成功结果，记录提交 SHA 和运行 URL。此项尚未完成，不用本地结果替代。
3. 补充上述安全回归并修复，然后再推进 crash-dump provider；该新提供器仍须遵守交接中的远程 CI gate 与用户级目录边界。
4. 上游差异清单、许可证、Win10/11 干净环境测试、发布签名和升级回滚仍属于未完成工作。

## 5. 回滚

修改前的 workflow、README、ROADMAP、CHANGELOG 和 HANDOFF 已保存在 `.artifacts/takeover-20260929/original/`，附 `sha256.json`；恢复时逐文件比对并复制回原位置。HANDOFF 原文没有修改。

本轮新增 `.gitignore` 与本记录；若回滚，仅移除确认不再需要的这两个新增文件，并逐项恢复已修改文件。不要删除整个项目、覆盖原始快照或递归清理未知目录。清理模块未修改，无模块版本变更或用户数据回滚操作。
