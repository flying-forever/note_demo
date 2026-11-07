# 系统能力与兼容性记录

当前工程目标与兼容 SDK 为 HarmonyOS 5.1.1(19)。新增系统能力时，在此记录接口要求、调用位置、失败处理及验证范围。升级 SDK 或更换设备时，按本表回归验证。

## 已接入能力

| 能力 | 接口与要求 | 调用位置 | 失败处理及边界 | 验证情况 |
| --- | --- | --- | --- | --- |
| 系统纯文本分享 | ShareKit 的 systemShare.SharedData、ShareController.show 及 dismiss 事件，SDK 标注自 HarmonyOS 4.1.0(API 11) 支持，要求 SystemCapability.Collaboration.SystemShare，Stage 模型。纯文本类型来自 ArkData 的 uniformTypeDescriptor。 | pages/NoteEditor.ets 的 shareNote | 空白内容先提示，打开失败提示稍后重试，防止重复打开，关闭时清理控制器监听。分享当前草稿，用户在系统面板选择接收应用。 | 当前连接设备已验证预览格式、取消、再次打开和未保存草稿。实际发送至接收应用、其他系统版本及设备尚未验证。 |
| 输入与键盘收起 | ArkUI TextInput、TextArea 的 onEditChange，FocusController 的 requestFocus、clearFocus。具体成员版本要求升级时对照本地 SDK 声明核验。 | pages/NoteEditor.ets 的 inputEditingChanged、focusInput | 输入框结束编辑后延迟判断是否转移到另一输入区，避免焦点切换误退浏览态。键盘未弹出时可通过勾选结束编辑。 | 当前设备浮动键盘收起和标题/正文切换已验证，实体键盘及其他输入法尚未验证。 |
| 删除确认与提示 | ArkUI UIContext.getPromptAction 的 showDialog、showToast。 | pages/NoteEditor.ets | 删除确认取消或对话框关闭时保留草稿，确认后才执行内存删除。 | 当前设备已验证取消和确认删除。 |

SDK 版本信息来自本机已安装 SDK 的声明文件。运行设备的系统版本、输入法版本和设备型号尚未形成完整测试矩阵，后续适配时补录，设备序列号不作为兼容性标识。

## 图片选择与附件（第 6 步）

- 使用 MediaLibraryKit 的 photoAccessHelper.PhotoViewPicker.select，IMAGE_TYPE，maxSelectNumber=1。本地 SDK 声明 PhotoViewPicker 自 API 10 提供，当前目标 API 19。系统选择器让用户选择单张图片，不申请全库读取权限，不接入相机。
- 使用 CoreFileKit 的 fileIo 打开选择结果 URI，将文件复制到 UIAbilityContext.filesDir/note-images；文件句柄在 finally 关闭。ImageKit ImageSource 读取宽高后释放。图片加载使用应用私有文件。
- 用户取消且没有返回图片时保持草稿；选择、复制或解码失败提示重新选择，并清理复制失败的文件；等待选择时防重复点击。
- 私有附件目录先通过 accessSync 检查，不存在时才 mkdirSync，避免已存在目录错误。正文光标只接受当前激活输入框的选区回调。
- 插入与删除可撤销，离页后清理没有笔记引用的本轮附件，不触及相册文件。笔记持久化尚未接入，进程重启后图片文件保留但笔记不恢复；跨进程孤立附件清理待统一实现。
- 构建及当前连接真机验证通过：正文输入/退格、重复插图、重启后插图、图前后输入、图片删除/撤销/重做、离页重开。其他图片格式、选择取消、空间不足、超大图片、中文预输入及更多输入法场景仍待验收。

## 接入经验

- 列表 key 决定节点身份，不等于 item 数据绑定。稳定 key 下替换数组中的普通对象，复用节点的闭包可能仍读取旧对象，导致输入闪现后回退。当前正文按稳定 ID 查询最新状态，保留输入框实例与焦点。不要以文字内容作为 key 绕过同步问题，否则每次输入可能重建节点并丢失光标、预输入或焦点。
- 多输入框的选区回调不一定代表用户正在编辑该框。只接受当前激活输入框的光标更新，自动聚焦直接使用目标 ID，避免初始化或失焦回调覆盖活动位置。
- 文件系统调用的幂等性要依据实际 API，不能照搬其他平台的语义。附件目录创建前检查是否存在；同时覆盖首次、重复调用和进程重启后调用。
- 构建和数据模型检查不能覆盖 UI 节点复用、焦点及输入法交互。改动编辑器后，真机至少验证连续输入/删除、结构变更后继续输入、切换输入区、撤销重做后输入、离页重开和重启后操作。可用 `uitest uiInput` 注入操作，再用 `dumpLayout` 检查文字与 focused 状态；操作之间确认界面已切换，不把动画期间未命中的点击误判为功能故障。命令注入文本不能替代真实输入法的中文预输入验收。
- 窗口的 keyboardDidShow、keyboardDidHide 在当前浮动键盘场景下未达到预期，最终使用输入框编辑状态回调。
- InputMethodController 的 sendKeyboardStatus 监听要求输入法客户端已 attach，提前注册会报 client detached。当前实现已移除该路径。
- SVG 的 fillColor 未能完整替换描边颜色，深色皮肤使用 colorFilter 为图标整体着色。

## 后续接入时补充

- 图片选择与附件文件管理、录音与权限、手写、提醒通知、私密认证及保护、桌面展示、本地持久化。
- 每项补录最低接口版本、设备能力和权限要求、授权拒绝及系统不支持时的处理、资源与监听释放，以及实际通过验证的设备和系统版本。
