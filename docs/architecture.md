# 当前架构

基于当前源码，不把[重构计划](archive/2026-11-12-refactoring-plan.md)的全部阶段出口视为已验收。路径相对note_by_agent/entry/src/main/ets/。

## 职责与状态所有者

| 层/文件 | 实际职责与状态 |
| --- | --- |
| pages/Index | 当前tab、分组、搜索/标题进度、列表快照与滚动；显示前从数据库刷新缓存 |
| pages/NoteEditor | 路由参数、原笔记快照、皮肤/分组、编辑模式、焦点、滚动、控制器、浮层、会话代号及异步生命周期 |
| viewmodel/NoteEditorSession | 主编辑唯一标题、blocks、images、派生content、历史、活动块/光标及脏状态；不负责落盘 |
| model/NoteHistory | 标题和序列化blocks历史、时间合并与分组（预输入过滤由会话调用方负责）；图片描述/尺寸不进入历史 |
| services/NoteService | 主编辑、长文外壳与半模态共同保存、空白检查、ID/时间、图片引用筛选、快照冲突检查、移动/皮肤/删除及卡片刷新编排；保存为异步 |
| repository/NoteRepository | 模块级首页摘要缓存；初始化从 notes.db 加载摘要，编辑页按 ID 读整篇，写入委托 NoteSqlRepository，并维护桌面 JSON 投影 |
| repository/NoteDatabase | notes.db 打开、schema v3 建表与 v2→v3 升级、事务边界；不承载业务规则 |
| repository/NoteSqlRepository | 笔记、正文块、附件、位置与设置的 CRUD，块↔纯文本转换，JSON 迁移与样例播种 |
| repository/DraftRepository | `drafts` 草稿表 CRUD、按笔记查找、列表与删除；不判断何时保存 |
| repository/DesktopNoteRepository | filesDir/desktop-notes下版本化记录、墓碑及form关联；不依赖FormKit |
| platform | NoteAttachments管私有附件与派生缩略图，NoteShare管系统分享，DesktopCards管配色/刷新，NoteLaunch管启动解析，NoteTextHitTest管原生排版命中 |
| components | 展示、皮肤背景/选择和图片描述；动态组件持有各自动画生命周期 |
| pages/NoteEditorWeb | 长文外壳的标题、Web 控制器、原笔记快照、800ms 草稿、实时字数、块级位置、图片 data URL 映射与保存/返回生命周期；正文状态由 CodeMirror 持有 |
| pages/DesktopNoteEdit | 每个半模态独立title/blocks草稿、原快照、状态和预览timer；并未使用NoteEditorSession |
| entryability / entryformability / entryformeditability | 主Ability启动和前台同步、卡片生命周期、独立半模态会话注入 |

页面仍保留不少交互编排、弹窗和布局代码，不声称已实现完全无状态页面或所有能力均迁出。

编辑引擎替换边界：`Note`/`BodyBlock`/`documentText`、`NoteEditorSession` 的标题与块状态、`NoteService` 保存/冲突/草稿、Repository、附件、分享、桌面和启动解析可跨引擎复用；页面壳、焦点/输入法、首击定位、滚动恢复、皮肤与工具栏与原生 `TextArea` 绑定，换引擎时需要重写或抽适配层。`NoteEditorWeb` 已复用会话和保存服务，当前覆盖文字笔记的草稿、实时字数与块级定位；4a 余拆合块边界、撤销手验和粘贴，4b 再处理图片、精确偏移、10 万字与共享 UI。

## 正式读写路径

首页onPageShow → refreshNotes 从 notes.db 重载摘要缓存 → listNotes → 筛选和双列展示。缓存只含标题、摘要与元信息，是同步读模型，数据库是权威存储；旧桌面 JSON 仅保留为卡片投影和回退。

打开主编辑 → aboutToAppear 按 ID 从数据库加载整篇 → session.load复制草稿并初始化历史 → 输入更新session并约800ms写`drafts` → 离页先冲刷草稿再saveNoteDraft（异步）。业务层从数据库读取最新笔记与 revision，比对固定字段顺序snapshotNote后条件更新，返回saved/empty/conflict/deleted/storageError。事务内更新notes与blocks，提交后更新摘要缓存；随后平台刷新卡片，卡片刷新失败不回滚已保存笔记。正文保存前置，元数据更新保持顺序且不改变首页排序。已有笔记移动和换肤立即提交元数据，新草稿首次保存携带。打开已有笔记发现草稿时提示恢复或忽略，`base_revision` 不一致时提示旧版本。主编辑「更多 → 长文编辑」先把当前页保存，再按 ID 打开 `NoteEditorWeb`：读块用换行拼整篇交给 CodeMirror，标题用原生输入，返回时取回全文按带权对齐复用原块 ID，经同一 `saveNoteDraft` 写库；旧含图笔记用缩略图 data URL 和 `\uFFFC` 占位块显示，新图压缩后由“图”按钮插入并保存。旧主编辑页仍保留，二者尚未共享 UI 外壳。Web 外壳已在页面可见时定时取字数、约 800ms 写草稿并冲刷，打开时按 `positions.edit_block_id` 定位到块；拆合块边界、撤销分组和真实粘贴仍待验，4b 再处理图片删除/浮层、精确偏移与 10 万字。

进入桌面预览 → persistToDesktop保存完整Note到数据库，并写桌面JSON投影供卡片同步读取 → AddFormMenuItem → form关联。每个formId为string，允许多卡对应一笔记。移除只删关联；删除已持久笔记写数据库墓碑和JSON墓碑并刷新删除状态。UIAbility和扩展共享数据库文件与私有目录，不能靠模块单例跨进程通信。

卡片点击 → NoteLaunch解析Want（含序列化params/关联回退）→ AppStorage目标ID → 首页就绪后RouterMode.Single导航 → desktopEditorRequest显式通知已复用编辑页。切目标先保存旧草稿，过期异步回调按会话代号丢弃。

半模态扩展每会话创建LocalStorage，经loadContent注入；页面从shared LocalStorage取session/formId，优先从数据库按 ID 读取原笔记、失败回退桌面JSON投影，持独立草稿 → 同一saveNoteDraft写数据库与投影 → 刷新预览 → terminateSelf。取消和销毁不隐式保存，成功只结束应用编辑区，不关闭宿主预览。

图片URI → 私有note-images的`.part`副本 → 校验500KB与尺寸 → 重命名 → 生成960/75缩略图 → session图片引用/正文块 → 保存筛选仍引用的附件。草稿`images_json`中的图片也计入引用；删除笔记时先取该笔记附件路径，删附件记录后在无其他引用时立即清理原图与缩略图；离页按数据库附件引用清理当前未引用附件，启动时清理无引用且超过60秒的文件并补建缺失缩略图，不修改相册源图；附件查询失败时跳过清理。分享直接读取当前草稿的纯文字，不触发保存。

## 可靠性和已知局限

- 数据库写入使用事务，失败回滚并保留原有笔记；主编辑与半模态保存使用 `revision` 条件更新，过期写入返回冲突；快照检查仍用于提前发现外部变化，不提供跨进程事务保证。
- 卡片和半模态读取仍走桌面 JSON 投影，投影由保存流程维护，可随时从数据库重建；迁移前数据保留为回退。
- 当前主编辑正文Text/TextArea块完整加载，不是10万字按需编辑器；长文外壳把整篇交给 CodeMirror 并一次加载，已做块级定位，尚未做块内偏移与区间回写；实验数据库和RichEditor页均隔离于正式数据。
- 当前正文视口恢复属于页内切换，不等于重开笔记恢复编辑位置；主编辑历史也不跨页保存。
- SDK19宿主完成无法拦截、宿主标题无法隐藏；明确保存和常驻提示是当前产品行为。
- 单设备记录不覆盖完整输入法、emoji、折叠切换、其他宿主与长时资源压力；职责迁移不等于全部验收完成。

当前契约见[数据模型](data-model.md)，系统接口/失败边界见[系统能力](system-capabilities.md)，未来统一存储见[持久化计划](plans/persistence-plan.md)。详细迁移及设备证据见[集成历史](archive/2026-11-11-integration.md)和[第二轮历史](archive/2026-11-11-optimization-round2.md)。
