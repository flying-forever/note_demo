# 系统能力与兼容性记录

当前工程目标与兼容 SDK 为 HarmonyOS 5.1.1(19)。新增系统能力时，在此记录接口要求、调用位置、失败处理及验证范围。升级 SDK 或更换设备时，按本表回归验证。

## 已接入能力

| 能力 | 接口与要求 | 调用位置 | 失败处理及边界 | 验证情况 |
| --- | --- | --- | --- | --- |
| 系统纯文本分享 | ShareKit 的 systemShare.SharedData、ShareController.show 及 dismiss 事件，SDK 标注自 HarmonyOS 4.1.0(API 11) 支持，要求 SystemCapability.Collaboration.SystemShare，Stage 模型。纯文本类型来自 ArkData 的 uniformTypeDescriptor。 | pages/NoteEditor.ets 的 shareNote | 空白内容先提示，打开失败提示稍后重试，防止重复打开，关闭时清理控制器监听。分享当前草稿，用户在系统面板选择接收应用。 | 当前连接设备已验证预览格式、取消、再次打开和未保存草稿。实际发送至接收应用、其他系统版本及设备尚未验证。 |
| 输入与键盘收起 | ArkUI TextInput、TextArea 的 onEditChange，FocusController 的 requestFocus、clearFocus。具体成员版本要求升级时对照本地 SDK 声明核验。 | pages/NoteEditor.ets 的 inputEditingChanged、focusInput | 输入框结束编辑后延迟判断是否转移到另一输入区，避免焦点切换误退浏览态。键盘未弹出时可通过勾选结束编辑。 | 当前设备浮动键盘收起和标题/正文切换已验证，实体键盘及其他输入法尚未验证。 |
| 删除确认与提示 | ArkUI UIContext.getPromptAction 的 showDialog、showToast。 | pages/NoteEditor.ets | 删除确认取消或对话框关闭时保留草稿，确认后才执行内存删除。 | 当前设备已验证取消和确认删除。 |

SDK 版本信息来自本机已安装 SDK 的声明文件。运行设备的系统版本、输入法版本和设备型号尚未形成完整测试矩阵，后续适配时补录，设备序列号不作为兼容性标识。

## 接入经验

- 窗口的 keyboardDidShow、keyboardDidHide 在当前浮动键盘场景下未达到预期，最终使用输入框编辑状态回调。
- InputMethodController 的 sendKeyboardStatus 监听要求输入法客户端已 attach，提前注册会报 client detached。当前实现已移除该路径。
- SVG 的 fillColor 未能完整替换描边颜色，深色皮肤使用 colorFilter 为图标整体着色。

## 后续接入时补充

- 图片选择与附件文件管理、录音与权限、手写、提醒通知、私密认证及保护、桌面展示、本地持久化。
- 每项补录最低接口版本、设备能力和权限要求、授权拒绝及系统不支持时的处理、资源与监听释放，以及实际通过验证的设备和系统版本。
