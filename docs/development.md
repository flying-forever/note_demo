# 开发、构建与验证

本机环境：ArkTS / ArkUI，Stage 模型；目标与兼容 SDK 均为 HarmonyOS 5.1.1(API19)。唯一 entry 模块，包名 com.example.note_by_agent。以下绝对路径仅适用于本机；更换环境需调整。

## 构建与运行（命令行，已验证）

本机 DevEco 安装在 `E:\Softs\Huawei\DevEco Studio`（以下路径为本机专用，换机需调整）。

```powershell
# 1. 必需环境变量，否则报 00303217 Configuration Error
$env:DEVECO_SDK_HOME = "E:\Softs\Huawei\DevEco Studio\sdk"

# 2. 签名需用 DevEco 自带 JBR，否则系统 JDK 17.0.8 会报 Invalid CEN header
$env:PATH = "E:\Softs\Huawei\DevEco Studio\jbr\bin;" + $env:PATH

# 3. 构建（在 note_by_agent/ 下执行）
& "E:\Softs\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
  --mode module -p product=default -p module=entry@default -p buildMode=debug `
  assembleHap --no-daemon

# 4. 安装
& "E:\Softs\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" `
  install -r "entry\build\default\outputs\default\entry-default-signed.hap"

# 5. 启动
& "E:\Softs\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" `
  shell aa start -b com.example.note_by_agent -a EntryAbility

# 查看已连接设备（设备序列号会变，勿硬编码）
& "E:\Softs\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets
```

- 产物：`entry/build/default/outputs/default/entry-default-signed.hap`
- 改完代码先命令行构建自检，再让用户在 DevEco 查看效果。
- 运行时需要有已连接的设备/模拟器。

### 布局坐标校验（无需看图）

应用在前台时，可导出 UI 树查真实坐标/尺寸：

```powershell
$hdc = 'E:\Softs\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
New-Item -ItemType Directory -Path 'D:\WorkSpaces\gpt-root\note_demo\note_by_agent\build\verification' -Force | Out-Null
& $hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
& $hdc file recv /data/local/tmp/layout.json "D:\WorkSpaces\gpt-root\note_demo\note_by_agent\build\verification\layout.json"
```

用 Node 解析 JSON，比用 PowerShell `ConvertFrom-Json` 稳（后者可能因重复键失败）。

## 自动检查

以下命令在仓库根目录运行，使用本机 DevEco TypeScript；可通过 DEVECO_TYPESCRIPT_PATH 指定其他位置。

```powershell
node scripts/test-desktop-notes.cjs
node scripts/test-editor-session.cjs
node scripts/test-editor-async.cjs
node scripts/test-text-hit-test.cjs
node scripts/test-long-document.cjs
```

这些是行为检查或独立模型检查，不替代 ArkTS 构建及真实输入法、焦点、卡片宿主和动画资源验收。src/test 与 ohosTest 中仍有工程模板测试，不能据此认定已有完整单元测试覆盖。

设备自动化脚本在 scripts/validate-*.cjs。运行前阅读脚本的入口与参数，确保已打开对应页面。真机由一个协调者串行使用，不并行安装、导航或输入。当前行为与待验项以[项目进度](progress.md)为准；实验专用操作见[技术实验现状](technical-demos.md)。

## 环境与证据管理

- 文档工作或纯注释改动不需要安装、启动设备；必要时只做构建和静态检查。
- 当前任务要求只写项目时，截图、UI树、备份和临时结果写入忽略的 note_by_agent/build/verification；旧实验脚本可能使用系统临时目录，运行前核对，不把历史脚本当作当前任务权限授权。
- 个人数据备份、设备日志和临时缓存不提交 Git。历史报告记录的验证只对当时版本和范围有效，不自动代表当前版本全通过。
- DevEco Git 映射只应包含当前仓库；若编辑器不显示变更，检查 note_by_agent/.idea/vcs.xml 是否仍引用旧的内层仓库。
- 工作区文件拒绝访问、Git无法替换文件或构建日志EPERM时，见[Windows工作区权限排查](troubleshooting/windows-workspace-permissions.md)。先核对令牌与ACL，不直接放宽整个磁盘权限。
