# 系统能力与兼容性记录

## 技术验证中的能力（未验收）

原生编辑试验新增 RichEditorStyledStringController、StyledString/TextStyle/StyleOptions 和 UIContext.postFrameCallback/FrameCallback.onIdle、LayoutManager.getLineCount，已按本地 API 19 声明构建。StyledString 的字体长度使用 LengthMetrics.vp。帧回调以试验代次忽略过期样本，离页时失效；不读取真实笔记。当前批量方式虽完成编辑功能检查，但高内存和一次 RssThresholdKiller 退出使稳定性不通过；整段控制器路径也未改善密集多段表现。设备内存用 hidumper --mem 采样 PSS，退出类型用 hidumper -e --list 核对。空闲帧回调不等于像素呈现，样本不代表全设备兼容性。详见技术实验室第四轮。

独立 NativeEditorDemo 使用 RichEditorController 与原生选区、片段读取、删除、光标定位及复制/粘贴事件；本地 API 19 声明核对及 ArkTS 构建通过。已记录设备通过四种合成文本场景的控制器选区与系统按键复制/粘贴/删除检查；用户于 2026-11-09 确认当前 10 万字试验的中文预输入、选词、退格及收起键盘正常；手指拖选、无障碍、图片与复杂 Unicode 仍未验证。10 万密集多段逐片段导入约一秒以上，不能作为性能通过记录。默认 enableKeyboardOnFocus(false)，可手动开启键盘，未影响正式编辑器。

独立 DatabaseDemo 已使用 ArkData relationalStore 的 getRdbStore、querySql、RdbPredicates 条件 update、beginTransaction/commit/rollBack 和 close；接口按本地 API 19 声明及 ArkTS 构建核对。本机已记录设备通过分块范围读取、同进程双句柄版本竞争、事务失败回滚、关闭重开和应用进程重启恢复。ResultSet 在 finally 关闭；数据库句柄结束时关闭，运行中防重复提交与返回；异常显示失败。仅使用 tech_demo_stage1.db，不访问正式数据。跨扩展真实并发、损坏/磁盘满和其他系统设备未验收；不将本结果扩大为正式持久化已接通。详情见 technical-demos.md 第二轮记录。

独立长文实验页使用 List、LazyForEach/IDataSource、Scroller.scrollToIndex 和 TextArea。已核对本地目标 SDK 声明，构建及 DMG-W00 上的基础浏览、块跳转、单块命令输入冒烟检查通过；跨块选择、真实输入法、精确定位及性能未验收。设置入口使用 44vp 容器与 LongPressGesture 优先手势，修复原 22vp 区域长按未触发实验入口。数据库独立试验结果见上文，未接入正式存储。详见 [技术实验室](technical-demos.md)。

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

## 桌面卡片与半模态编辑（第 7 步）

- ArkUI AddFormMenuItem（API 12）提交 2×2 卡片，FormKit FormExtensionAbility 通过 onAddForm、onUpdateForm、onRemoveForm 管理实例，updateForm 刷新。module.json5 声明 form 扩展及表单配置；配置关联 formEdit 扩展，目标仍为 API 19。
- FormEditExtensionAbility 自 API 18 支持。桌面长按卡片的「编辑」通过 cardId 和 previewCardId 指定实际卡片与预览卡片，UIExtensionContentSession.loadContent 加载独立页面，通过会话 terminateSelf 关闭。普通卡片组件清单不包含 TextInput/TextArea，半模态扩展页面可使用这两个组件。
- 卡片只提交标题、文字摘要和皮肤配色；图片保存在笔记中，不传入卡片。点击通过 postCardAction 的 router 事件进入应用。UIAbility 同时处理 onCreate 和 onNewWant，解析序列化的 parameters.params，并可从卡片实例关联恢复目标 ID；通过 AppStorage 交给首页就绪后导航，避免窗口创建时过早操作路由。
- UIAbility 与卡片扩展均使用 filesDir/desktop-notes 下的文件记录，不依赖进程内单例共享。添加前保存笔记，添加成功后保存 formId 与 noteId 的关联；更新失败保留笔记并记录日志；无效或已删除笔记显示占位，点击不创建新笔记。
- 半模态编辑仅修改标题和文字块，保留图片引用；保存前比对记录快照，防止覆盖其他页面已保存的内容。桌面预览和编辑区异步创建，页面显示后最多刷新预览三次，关闭页面清理延迟任务；最终刷新失败显示提示，保存时再次尝试。
- 本地 JSON 写入先写临时文件并 fsync，再 rename；只有成功后才更新内存。重复创建目录前检查存在性。读写异常、磁盘空间不足、其他桌面宿主和真实设备重启等边界需继续扩展验证。

当前连接真机已验证：加桌、冷启动与后台点击跳转、应用内更新、半模态标题/正文输入与保存、预览初始化、取消、应用进程停止后的恢复、删除状态和移除。图片引用保持与多卡片、写入失败通过数据层检查；图片笔记的半模态完整真机流程、设备重启和其他宿主尚未实测。

参考：[卡片编辑](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-event-formeditextensionability/)、[卡片路由](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-ui-widget-event-router/)、[添加卡片菜单](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-formmenu/)。接口版本同时核对本机 SDK 声明。

## 接入经验

- ArkUI 的 `.animation(...)` 不是只作用于紧邻的一个属性。动态皮肤曾把宽高和旋转放在同一无限往复动画范围内，首次窗口测量及全屏/小窗切换后，出现边缘游走缺损、矩形切口和半片闪烁。原 SVG 加 renderGroup、替换为透明 PNG 均未解决；恢复原 SVG，在宽高和透明度之后加 `.animation(null)`，再对 rotate 单独设置循环动画后，全屏、小窗各采样 24 帧未再复现，用户随后确认观感正常。布局尺寸和位置应直接适配窗口，不能混入装饰旋转循环。回归需覆盖首次选择、全屏与小窗往返切换及多个摆动周期，单张截图只能证明当帧显示。
- 列表 key 决定节点身份，不等于 item 数据绑定。稳定 key 下替换数组中的普通对象，复用节点的闭包可能仍读取旧对象，导致输入闪现后回退。当前正文按稳定 ID 查询最新状态，保留输入框实例与焦点。不要以文字内容作为 key 绕过同步问题，否则每次输入可能重建节点并丢失光标、预输入或焦点。
- 多输入框的选区回调不一定代表用户正在编辑该框。只接受当前激活输入框的光标更新，自动聚焦直接使用目标 ID，避免初始化或失焦回调覆盖活动位置。
- 文件系统调用的幂等性要依据实际 API，不能照搬其他平台的语义。附件目录创建前检查是否存在；同时覆盖首次、重复调用和进程重启后调用。
- 构建和数据模型检查不能覆盖 UI 节点复用、焦点及输入法交互。改动编辑器后，真机至少验证连续输入/删除、结构变更后继续输入、切换输入区、撤销重做后输入、离页重开和重启后操作。可用 `uitest uiInput` 注入操作，再用 `dumpLayout` 检查文字与 focused 状态；操作之间确认界面已切换，不把动画期间未命中的点击误判为功能故障。命令注入文本不能替代真实输入法的中文预输入验收。
- 窗口的 keyboardDidShow、keyboardDidHide 在当前浮动键盘场景下未达到预期，最终使用输入框编辑状态回调。
- InputMethodController 的 sendKeyboardStatus 监听要求输入法客户端已 attach，提前注册会报 client detached。当前实现已移除该路径。
- SVG 的 fillColor 未能完整替换描边颜色，深色皮肤使用 colorFilter 为图标整体着色。

## 后续接入时补充

- 图片附件的跨进程孤立文件清理、录音与权限、手写、提醒通知、私密认证及保护、完整笔记持久化。
- 每项补录最低接口版本、设备能力和权限要求、授权拒绝及系统不支持时的处理、资源与监听释放，以及实际通过验证的设备和系统版本。

## 动态皮肤叶脉可见性

当前平板上，低透明度 SVG 的叶脉不可见。依次测试显式 L 命令、将描边属性从 g 移到 path、改用 line、将线段改成同色等宽填充轮廓，均未恢复。恢复原始 SVG，仅对 Image 增加 renderGroup(true) 后，原颜色、3 单位线宽和 12%/16% 不透明度下叶脉恢复可见。对照支持透明合成路径影响内部对比度，不能将此问题误记成路径简写不支持，也不能泛化为全部设备的 SVG 描边故障。图案先整体缓存，再整体透明合成；宽高后的 animation(null) 必须保留，缓存不能代替动画范围隔离。

## 2026-11-11 结构迁移与接入补充

- 系统分享、附件导入/清理、桌面配色/通知、启动参数解析移入 platform；存储仓库不再导入 FormKit。主编辑与半模态共用 services/NoteService，错误分类与现有 JSON 兼容约定见 data-model.md。
- 桌面入口使用 RouterMode.Single；当前顶部实例复用不会可靠重触发 onPageShow，因此路由成功后通过独立 AppStorage 信号要求当前可见编辑页重新读取目标参数。不同目标先保存旧草稿，所有异步图片/弹窗回调核对会话代号。
- 半模态每个会话创建独立 LocalStorage，通过 session.loadContent 注入；页面使用 @Entry({ useSharedStorage: true }) 与 UIContext.getSharedLocalStorage 取得所属会话。SDK19 未提供可依赖的系统完成保存回调，采用常驻先保存提示，输入后标记尚未保存。
- 皮肤选择面板采用显式底部定位，避免通用 align 属性未按预期布局而遮挡导航。动态背景接收 paused，页面隐藏/编辑/图片覆盖层暂停；原樱花落地停留后淡出。实际长时资源压力尚未测量。
- 本轮设备验证与未覆盖场景见 integration-2026-11-11.md；UI树和截图在工程忽略的 build/verification，用户数据备份不提交。

## 第二轮原生排版命中与桌面宿主限制

- 浏览态每个正文块保持TextController，ClickEvent组件局部vp通过UIContext.vp2px转换后交给LayoutManager.getGlyphPositionAtCoordinate（API12）；返回UTF-16偏移，不按Unicode码点二次换算，不再叠加Scroll偏移。布局不可用时不猜测字宽，保护代理对边界。真实首击定位与长文位置回归见optimization-round2.md。
- SDK19不能拦截宿主完成、隐藏宿主标题。UIExtensionContentSession.terminateSelf只结束我们的编辑区，真机宿主预览弹窗仍保留；按钮使用用户确认的“保存并结束编辑”，不可宣称自动关闭整个宿主。取消/系统完成不隐式保存。
