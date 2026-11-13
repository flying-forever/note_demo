# 当前架构

基于当前源码，不把[重构计划](archive/2026-11-12-refactoring-plan.md)的全部阶段出口视为已验收。路径相对note_by_agent/entry/src/main/ets/。

## 职责与状态所有者

| 层/文件 | 实际职责与状态 |
| --- | --- |
| pages/Index | 当前tab、分组、搜索/标题进度、视图模式与设置菜单、列表快照与滚动；显示前同步桌面记录 |
| pages/NoteEditor | 路由参数、原笔记快照、皮肤/分组、编辑模式、焦点、滚动、控制器、浮层、会话代号及异步生命周期 |
| viewmodel/NoteEditorSession | 主编辑唯一标题、blocks、images、派生content、历史、活动块/光标及脏状态；不负责落盘 |
| model/NoteHistory | 标题和序列化blocks历史、时间合并与分组（预输入过滤由会话调用方负责）；图片描述/尺寸不进入历史 |
| services/NoteService | 主编辑/半模态共同保存、空白检查、ID/时间、图片引用筛选、快照冲突检查、移动/皮肤/删除及卡片刷新编排 |
| repository/NoteRepository | 模块级进程内已提交notes，初始假数据；与桌面JSON合并、写入和排序 |
| repository/NoteSettings | Preferences中的首页视图模式，读取失败回退瀑布 |
| repository/DesktopNoteRepository | filesDir/desktop-notes下版本化记录、墓碑及form关联；不依赖FormKit |
| platform | NoteAttachments管私有附件，NoteShare管系统分享，DesktopCards管配色/刷新，NoteLaunch管启动解析，NoteTextHitTest管原生排版命中，SystemBars管主窗口全屏/避让区/系统栏样式 |
| components | 展示、皮肤背景/选择和图片描述；动态组件持有各自动画生命周期 |
| pages/DesktopNoteEdit | 每个半模态独立title/blocks草稿、原快照、状态和预览timer；并未使用NoteEditorSession |
| entryability / entryformability / entryformeditability | 主Ability启动和前台同步、卡片生命周期、独立半模态会话注入 |

页面仍保留不少交互编排、弹窗和布局代码，不声称已实现完全无状态页面或所有能力均迁出。

## 正式读写路径

主窗口启动 → EntryAbility先调用SystemBars初始化全屏/透明系统栏并读取避让区 → 写入AppStorage后loadContent → 页面用@StorageProp上下让位并按页面/皮肤背景切换图标。半模态扩展和桌面卡片组件不走该路径。

首页onPageShow → syncDesktopNotes → JSON覆盖同ID内存笔记/排除墓碑 → listNotes → 筛选和瀑布/列表展示。普通内存笔记与选择性JSON共存，没有统一数据库。首页启动另读取 Preferences 视图模式，切换只写该设置，不读改笔记数据。

打开主编辑 → 路由参数查笔记 → session.load复制草稿并初始化历史 → 输入更新session → 离页saveNoteDraft。业务层读取最新桌面记录优先于内存，比对固定字段顺序snapshotNote，返回saved/empty/conflict/deleted/storageError。仓库先持久写入（适用时）再改内存；随后平台刷新卡片，卡片刷新失败不回滚已保存笔记。正文保存前置，元数据更新保持顺序。已有笔记移动和换肤立即提交元数据，新草稿首次保存携带。

进入桌面预览 → persistToDesktop保存完整Note → AddFormMenuItem → form关联。每个formId为string，允许多卡对应一笔记。移除只删关联；删除已持久笔记写墓碑并刷新删除状态。UIAbility和扩展以文件共享数据，不能靠模块单例跨进程通信。

卡片点击 → NoteLaunch解析Want（含序列化params/关联回退）→ AppStorage目标ID → 首页就绪后RouterMode.Single导航 → desktopEditorRequest显式通知已复用编辑页。切目标先保存旧草稿，过期异步回调按会话代号丢弃。

半模态扩展每会话创建LocalStorage，经loadContent注入；页面从shared LocalStorage取session/formId，直接读JSON并持独立草稿 → 同一saveNoteDraft → 刷新预览 → terminateSelf。取消和销毁不隐式保存，成功只结束应用编辑区，不关闭宿主预览。

图片URI → 私有note-images副本 → session图片引用/正文块 → 保存筛选仍引用的附件。离页按内存笔记引用清理当前附件，不修改相册源图。分享直接读取当前草稿的纯文字，不触发保存。

## 可靠性和已知局限

- JSON使用独立临时文件、fsync、rename，失败保留旧内存；快照检查与唯一临时名都不是跨进程原子事务，仍有比较后竞争窗口。
- 只有发送预览后的笔记持久化，其他内容重启丢失；无正式自动草稿、关系库迁移、损坏恢复或跨进程孤立附件回收。
- 首页视图模式是唯一已持久化的应用设置；Preferences读取失败回退瀑布，写入失败只影响下次启动，不阻断笔记数据路径。
- 当前正文Text/TextArea块完整加载，不是10万字按需编辑器；实验数据库和RichEditor页均隔离于正式数据。
- 当前正文视口恢复属于页内切换，不等于重开笔记恢复编辑位置；主编辑历史也不跨页保存。
- SDK19宿主完成无法拦截、宿主标题无法隐藏；明确保存和常驻提示是当前产品行为。
- 系统栏全屏、透明背景、图标明暗和避让高度已接入主窗口；DMG-W00 已验收透明呈现、深浅皮肤图标、手势导航、浮动键盘和横竖屏，三键导航/折叠/其他设备仍待验，半模态与桌面卡片只做代码边界确认。
- 单设备记录不覆盖完整输入法、emoji、折叠切换、其他宿主与长时资源压力；职责迁移不等于全部验收完成。

当前契约见[数据模型](data-model.md)，系统接口/失败边界见[系统能力](system-capabilities.md)，未来统一存储见[持久化计划](plans/persistence-plan.md)。详细迁移及设备证据见[集成历史](archive/2026-11-11-integration.md)和[第二轮历史](archive/2026-11-11-optimization-round2.md)。
