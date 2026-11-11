# Windows 工作区子目录不可写

整理日期：2026-11-12。来源为本项目 `note_demo-dsh` 会话的实际排查，供其他 Agent 复用排查方法。症状与另一会话的 `windows-workspace-permissions.md` 相近，但原因在完整性标签而非权限项缺失；两篇合并时按原因分流，合并后可把文件名改成链接。

## 症状与本次原因

工作区根目录能新建、删除文件，但 116 个已有子目录和根目录下的已有文件（如 `AGENTS.md`）全部报 `访问被拒绝`（`UnauthorizedAccessException`）；只有受限进程自己新建的文件和目录可写。仅凭这些错误不能认定是权限项缺失。

排查发现：受限进程令牌是当前用户身份加**低完整性级别**，不含包 SID；失败子目录的权限项继承自上一级目录，`Authenticated Users` 已有 `Modify`，访问本应通过。真正拦截的是完整性级别——**低级别令牌不能写中级别的既有对象**。根目录对象单独带了低完整性标签，所以根可写，标签未覆盖既有子目录和文件。这是已证实的直接原因；标签为何只落在根对象上未确定。

## 排查顺序

1. 全树做写入探针，区分「全部不可写」和「部分不可写」，不要只测一个文件或只测根目录。
2. 在根目录新建子目录并写入：能写说明标签在场、问题只出在既有对象；不能写才继续查权限项。
3. 对比可写对象与失败对象的权限项和继承关系。权限项已足够仍被拒，说明拦在完整性级别或策略层，不要再补权限项。
4. 确认执行进程的完整令牌与完整性级别。文件所有者或 `whoami /user` 不能证明沙箱的有效写权限。
5. 用写入句柄判定失败项，`OPEN_EXISTING`，不截断、不写字节，随后立即关闭；不要拿真实源码试权限。

基础只读检查，路径替换为实际受检目录：

```powershell
$root = 'D:\WorkSpaces\gpt-root\note_demo-dsh'
whoami /groups   # 看 Mandatory Label 与包 SID
Get-Acl -LiteralPath $root | Format-List Owner, AreAccessRulesProtected, Sddl
Get-ChildItem -LiteralPath $root -Directory -Force | ForEach-Object {
  $p = Join-Path $_.FullName '.write_probe'
  try { [System.IO.File]::WriteAllText($p, 'x'); Remove-Item -LiteralPath $p -Force } catch { "FAIL $($_.FullName)" }
}
```

全树探针按目录逐个新建并删除临时文件，比只验原失败项更可靠：本次它同时暴露了同类中未被发现的不可写对象。

## 本次修复方法

- 不手工改权限项、完整性标签或所有者：拒绝不是权限项造成的，改权限项无效且会污染安全信息。
- 先跑平台自带的工作区权限诊断脚本（DSH 的 `diagnose-windows-sandbox-acl.ps1`，一次调用完成判定与范围受限的修复）；本次判定 `NOT_THIS_CLASS`，未做任何改动，无需回滚，报告写入 `D:\WorkSpaces\gpt-root\dsh-acl-recovery\`。
- 向用户报告阻塞对象、缺的是完整性标签而不是权限，并给出报告位置；由用户决定提权本会话或重新登记工作区。本次修复由用户和另一个 Agent 的会话完成，不在本会话内改权限。
- **沙箱外运行不等于管理员权限，命令审批通过也不等于 Windows 放行。**

## 修复验收

必须回到同一受限沙箱内复验，不能只看修复方命令成功：

- 全树每个目录新建并删除临时文件；对既有文件取追加写句柄后立即关闭。
- 确认临时文件无残留，`git status --porcelain` 为空，源码内容无差异。
- 本次 117 个目录、367 个文件全部通过，无残留、无工作树差异。

**完整性标签与权限项是两层机制。** 标签不匹配时权限项授权不起作用，补权限项只会堆叠无用条目。
