# 数据模型

| 范围 | 当前状态 | 阶段 2 目标 |
| --- | --- | --- |
| 笔记数据源 | 关系库 `notes.db` 为权威；首页缓存只存摘要，编辑页按 ID 读取整篇；桌面 JSON 为卡片投影和回退 | `relationalStore` 的 `notes.db` |
| 正文权威 | 关系库 `blocks`；旧 JSON 的 `blocks` 为迁移来源 | `blocks` 表 |
| 图片 | 私有文件；附件元数据在关系库与旧 `Note.images` 并存 | 私有文件 + `attachments` 表 |
| 位置 | 页内视口，不跨页 | `positions` 表 |
| 设置 | 初始化/迁移标记写入 `settings`（接入中） | `settings` 表 |
| 结构版本 | `RdbStore.version=3`（v2 增加 `attachments.small`；v3 增加 `drafts` 表）；旧 JSON `DesktopRecord.version=1` | `RdbStore.version=3` |

## 应用设置

`repository/NoteSettings.ets` 独立使用 Preferences 的 `note_settings` 保存 `view_mode`（`waterfall`/`list`），读取失败回退瀑布；不进入笔记字段或保存快照。

**当前处于阶段 3：主应用已走关系库 Repository，首页只读摘要、编辑页按 ID 读整篇并写自动草稿；桌面 JSON 保留为卡片投影和回退。迁移验收完成前不删除旧 JSON，也不把数据库当作可随意清空的唯一副本。** 本文第 2～5 节是目标契约，第 6 节是旧字段事实。

## 1. 当前实现

- `model/Note.ets` 定义 `id`、`title`、`content`、`timeLabel`、`group`，可选 `skinId`、`blocks`、`images`；`FAKE_NOTES` 是首次初始化使用的样例来源。
- `repository/NoteRepository.ets` 维护首页摘要缓存，初始化时从关系库加载摘要；保存和删除委托 `NoteSqlRepository`；编辑页通过 `loadFullNote` 按 ID 读取整篇。仍用 `DesktopNoteRepository` 为桌面预览笔记写版本化 JSON 和卡片关联。
- `services/NoteService.ets` 统一保存、快照冲突检查、空白检查、移动、换肤和删除；保存异步读取数据库最新 revision 并条件更新。`viewmodel/NoteEditorSession.ets` 持有主编辑页唯一草稿及历史；`pages/DesktopNoteEdit.ets` 每个半模态另持独立草稿，并优先从数据库读取原笔记。
- 旧 JSON 仍参与当前路径：进入「发送到桌面」预览的笔记额外写入 `filesDir/desktop-notes/notes` 下的完整 `Note`（含 `blocks`、`images`、`group`、`skinId`），作为卡片投影和回退；新建 ID 含时间戳与进程内序号。卡片读取该投影，主应用修改后同步更新。
- 图片文件在 `filesDir/note-images`，旧 JSON 的附件元数据仍跟随 `Note.images`；关系库 `attachments` 已开始接入，尚未成为唯一来源。
- JSON 写入采用独立临时文件、`fsync`、重命名，成功后才更新内存；写入失败保留原值。唯一临时文件名避免互相踩写，但不等于跨进程原子控制。卡片关联在 `filesDir/desktop-notes/forms`，每张卡片一个文件。
- 主应用、卡片、半模态目前仍通过文件共享部分数据；卡片和半模态当前读旧 JSON，主编辑保存已接入同一 `saveNoteDraft`，以固定字段顺序的 `snapshotNote` 做尽力冲突检查，返回 `saved`、`empty`、`conflict`、`deleted` 或 `storageError`。

阶段 2 的数据库与仓库代码已接入主应用；迁移状态机与幂等已在真机自检，首页摘要读取、编辑页按 ID 加载整篇已接通。卡片仍读旧 JSON 投影，半模态改为优先读库、失败回退投影；多入口读库验收尚未完成，旧 JSON 保留为回退，不得删除。

## 应用设置

`repository/NoteSettings.ets` 独立使用 Preferences 的 `note_settings` 保存 `view_mode`（`waterfall`/`list`），读取失败回退瀑布；不进入笔记字段或保存快照。

## 2. 目标数据契约（阶段 3）

数据库使用 `relationalStore`，文件名 `notes.db`，当前 `schema` 版本为 3，安全级别 S1。v2 在 v1 上增加 `attachments.small` 列与 `notes_order_v2` 索引；v3 增加 `drafts` 草稿表与索引，旧库打开时执行 `ALTER TABLE`/`CREATE TABLE` 并在事务中更新版本号。正文文字直接存于正文块记录，`notes` 不保存全文；图片等二进制只存应用私有文件，数据库保存附件元数据和相对路径。建表与仓库代码在 `repository/NoteDatabase.ets`、`repository/NoteSqlRepository.ets`、`repository/DraftRepository.ets`；字段语义以本文为准，接入时按本文校验。

**正文块表是正文的权威存储。** 主编辑以段落块为主，长文外壳按行读写文本块；块粒度是运行时策略，不改变表结构。图片按独立图片块存放，因此含图笔记的 `blocks` 行数可以大于 1。

| 表 | 主键 | 保存内容 | 用途 |
| --- | --- | --- | --- |
| `notes` | `id` | 标题、摘要、字数、分组、皮肤、版本、时间、墓碑 | 首页列表只读摘要与元信息；编辑页按 ID 读取正文块 |
| `blocks` | `(note_id, ordinal)` | 有序正文文本与图片引用 | 正文权威存储 |
| `attachments` | `id` | 图片元数据与私有文件相对路径 | 正文只引用 ID |
| `drafts` | `draft_id` | 未提交的标题、块、图片与基线版本 | 自动草稿与崩溃恢复；不进入首页列表 |
| `positions` | `note_id` | 编辑与浏览锚点 | 位置恢复，不参与首页排序 |
| `settings` | `key` | 全局设置、初始化与迁移标记 | 字符串键值 |
| schema | — | 结构版本 | 使用 `RdbStore.version`，不建 `schema_meta` |

### 2.1 `notes`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | TEXT | 主键，NOT NULL | 与路由参数、卡片关联共用同一字符串；删除后不复用 |
| `title` | TEXT | NOT NULL DEFAULT '' | 保存原始标题；可为空，展示回退不写库 |
| `summary` | TEXT | NOT NULL DEFAULT '' | 首页摘要；保存时由正文派生，去首尾空白后截断到 120 个 UTF-16 单元，不含图片描述；纯图片写「图片笔记」 |
| `content_length` | INTEGER | NOT NULL DEFAULT 0 | 正文去空白后的 Unicode 码点数，含标点，不含标题、图片和图注；保存时重算，不按输入增量累加 |
| `group_name` | TEXT | NOT NULL DEFAULT '' | 空字符串为未分类；只存分组名，「全部」是筛选不是数据；不建 folder 表 |
| `skin_id` | TEXT | NOT NULL DEFAULT 'white' | 皮肤标识；缺失或未知按默认白显示 |
| `revision` | INTEGER | NOT NULL DEFAULT 1 | 笔记记录版本；任意已提交写入（正文、标题、附件、移动、换肤、删除）后递增；条件更新和位置校验使用；位置写入不改变它 |
| `created_at` | INTEGER | NOT NULL DEFAULT 0 | 创建时间，epoch 毫秒；旧 JSON 无此值，迁移时按枚举顺序填递减值 |
| `updated_at` | INTEGER | NOT NULL DEFAULT 0 | 内容或标题提交时间，首页排序键；移动、换肤、位置更新不改变它，保持列表位置 |
| `deleted` | INTEGER | NOT NULL DEFAULT 0，CHECK(deleted IN (0,1)) | 软删除墓碑；列表和按 ID 读取默认排除；不是回收站 |
| `time_label` | TEXT | NOT NULL DEFAULT '' | 编辑器元信息展示文本，如「11月12日 21:35」；样例保留「今天 07:42」等原文；仅展示，不参与排序 |

索引建议：

- `notes_order_v2 ON notes(deleted, updated_at DESC, id ASC)`，支撑首页列表。
- 分组过滤在 v1 读取少量元信息后于内存完成；若以后改为分组分页，再补 `(deleted, group_name, updated_at DESC)`。
- 不建标题索引，也不引入全文检索索引。

删除时在事务中置 `deleted=1`，正文块保留（当前不做级联清理，回收站与彻底清理另定），同时删除该笔记的 `attachments` 行和草稿，保留 `notes` 行作为墓碑，阻止同 ID 的旧 JSON、旧草稿或样例复生。迁移来的 JSON 墓碑同样落为 `deleted=1` 行。

### 2.2 `blocks`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `note_id` | TEXT | NOT NULL | 逻辑外键 `notes.id`；删除和清理在事务中显式执行，不依赖数据库外键开关 |
| `ordinal` | INTEGER | NOT NULL | 0 起递增，决定顺序；不要求连续，插入可取间隔，间隔耗尽时只重排该笔记 |
| `block_id` | TEXT | NOT NULL | 笔记内唯一；位置锚点引用；普通保存不得改写 |
| `body` | TEXT | NOT NULL DEFAULT '' | 文本块正文；图片块为 ''；不做 trim，按原字符保存 |
| `image_id` | TEXT | NOT NULL DEFAULT '' | 空字符串为文本块；非空引用 `attachments.id`；图片块 `body` 必须为 '' |

约束与索引：

- 主键 `(note_id, ordinal)`，按 `note_id` 读取时 `ORDER BY ordinal`。
- 唯一索引 `blocks_note_block ON blocks(note_id, block_id)`；位置恢复和差异回写按块 ID 定位，不依赖会变化的序号。
- 图片块 `body` 必须为空，由写入层保证，不建 CHECK（SQLite 无法给既有表追加 CHECK）。
- 不单独索引 `image_id`；附件引用清理按笔记读取正文后判断。

### 2.3 `attachments`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | TEXT | 主键，NOT NULL | 正文 `image_id` 只存这个值 |
| `note_id` | TEXT | NOT NULL | 所属笔记；逻辑外键，一张图片只归属一篇笔记 |
| `rel_path` | TEXT | NOT NULL | 相对应用 `filesDir` 的私有路径，如 `note-images/image-...`；不存绝对沙盒路径，迁移时去掉现有绝对前缀 |
| `width` | INTEGER | NOT NULL DEFAULT 0 | 入库文件的像素宽（压缩后） |
| `height` | INTEGER | NOT NULL DEFAULT 0 | 入库文件的像素高（压缩后） |
| `bytes` | INTEGER | NOT NULL DEFAULT 0 | 入库文件字节数；新导入目标不超过 512000（500KB） |
| `sha256` | TEXT | NOT NULL DEFAULT '' | 文件内容哈希；新写入计算，旧数据可空；用于校验或去重，不设唯一约束 |
| `caption` | TEXT | NOT NULL DEFAULT '' | 现有图片描述；可为空；独立图注流程延后 |
| `small` | INTEGER | NOT NULL DEFAULT 0，CHECK(small IN (0,1)) | 现有 `NoteImage.small` 的小号显示标记；v2 新增 |
| `created_at` | INTEGER | NOT NULL DEFAULT 0 | 导入时间，epoch 毫秒 |

索引建议：`attachments_note ON attachments(note_id)`。去重尚未实现，`sha256` 暂不建索引。

图片文件规则：

- 原图导入先写 `filesDir/note-images/<id>.part`，校验体积与尺寸后重命名到最终路径，再在事务中提交附件记录与正文块引用；失败删除 `.part` 和最终文件。正文只存附件 ID，不存路径、base64 或描述文本。
- 入库前优先保留原文件；超过 500KB 时按长边 2048/1600/1024 逐级缩放并用 JPEG 85/75/65 重压，仍超限才拒绝。迁移的历史大图保留，不因超过上限自动删除或压缩。
- 缩略图长边 960、JPEG 质量 75，是派生缓存：导入成功后生成到 `filesDir/note-images-thumbs/<原文件名>.thumb`，先写 `.part` 再重命名；正文和列表优先用缩略图，详情用原图。生成失败回退原图；启动时补建缺失缩略图；原图被删除或不再被引用时随清理删除，可随时重建，不进入附件主记录。
- 附件记录归属一篇笔记，不做跨笔记共享。

### 2.4 `drafts`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `draft_id` | TEXT | 主键，NOT NULL | 已有笔记取笔记 ID；新笔记为 `draft-<时间戳>-<序号>`；保存成功或丢弃后删除 |
| `note_id` | TEXT | NOT NULL DEFAULT '' | 关联的正式笔记 ID；新笔记在首次保存前为空字符串 |
| `group_name` | TEXT | NOT NULL DEFAULT '' | 草稿所属分组，恢复后作为保存分组 |
| `base_revision` | INTEGER | NOT NULL DEFAULT 0 | 写入草稿时正式笔记的 `revision`；恢复时用于判断草稿是否基于旧版本 |
| `title` | TEXT | NOT NULL DEFAULT '' | 未提交标题 |
| `blocks_json` | TEXT | NOT NULL DEFAULT '[]' | 完整块数组 JSON，含块 ID、文本与 `imageId`；不是正文纯文本 |
| `images_json` | TEXT | NOT NULL DEFAULT '[]' | 会话内全部图片 JSON，含撤销历史中暂时不在块里的图片 |
| `created_at` | INTEGER | NOT NULL DEFAULT 0 | 首次写入时间，epoch 毫秒 |
| `updated_at` | INTEGER | NOT NULL DEFAULT 0 | 最近写入时间，用于排序和首页草稿条 |

- 一份笔记最多保留一份活跃草稿。`draft_id` 对已有笔记直接复用笔记 ID，新笔记使用临时 ID；首次保存成功后把 `draft_id` 切换为正式笔记 ID，并删除旧草稿行。
- 编辑停顿约 800ms 写入草稿；`onPageHide`、页面销毁和离开编辑页时冲刷。正式保存成功、空白草稿或用户选择「忽略并删除」时删除草稿。
- 长文外壳复用同一 `drafts` 表、约 800ms 窗口和恢复/旧版本提示；页面隐藏/销毁冲刷，接受与原生一致的末段窗口，不丢整篇。当前外壳已接入定时草稿，真机强杀可恢复，回到已保存文本时删除草稿。
- 打开已有笔记时按 `note_id` 查草稿；`base_revision` 与当前 `notes.revision` 不一致时提示「草稿基于旧版本」，由用户选择恢复或忽略，避免静默覆盖其他入口的修改。
- `blocks_json`/`images_json` 让草稿中的图片路径计入引用，清理不得删除；草稿只服务恢复，不是权威数据，最终仍通过 `notes`/`blocks`/`attachments` 事务提交。
- 索引：`drafts_updated ON drafts(updated_at DESC)` 支撑首页草稿条，`drafts_note ON drafts(note_id)` 支撑按笔记查找。不建数据库外键，删除时由应用显式清理。

### 2.5 `positions`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `note_id` | TEXT | 主键，NOT NULL | 每篇笔记一行，按需 upsert |
| `revision` | INTEGER | NOT NULL DEFAULT 0 | 写入锚点时的 `notes.revision`；恢复时用于判断是否需要重新校验 |
| `edit_block_id` | TEXT | NOT NULL DEFAULT '' | 编辑位置所在块；空字符串表示无有效锚点 |
| `edit_offset` | INTEGER | NOT NULL DEFAULT 0 | 块内 UTF-16 code unit 偏移，范围 `[0, body.length]` |
| `browse_block_id` | TEXT | NOT NULL DEFAULT '' | 浏览位置所在块；与编辑位置分开 |
| `browse_offset` | INTEGER | NOT NULL DEFAULT 0 | 块内 UTF-16 code unit 偏移 |
| `updated_at` | INTEGER | NOT NULL DEFAULT 0 | 位置写入时间；不更新 `notes.updated_at`，不影响首页排序 |

- 位置锚点是「块 ID + 块内文本偏移 + 内容版本」，内容版本取 `notes.revision`；块表不另存版本列。
- 单纯滚动只更新 `browse_*`，不覆盖 `edit_*`；进入编辑并提交后更新 `edit_*`。
- 标题位置不占列；本期不持久化标题光标。若后续需要，另加标识，不与正文块 ID 混用。
- 锚点失效时回退到邻近块或正文首尾，不阻塞打开；位置读写失败不改变笔记内容和首页排序。
- 阶段 4 只使用 `edit_block_id` 做块级恢复，`edit_offset` 暂为 0；精确块内偏移、浏览/编辑位置分离和滚动不覆盖编辑位置在阶段 5 验收。
- 索引：主键 `note_id` 已覆盖单篇读取，无额外索引；按笔记清理时直接按主键删除。

### 2.6 `settings`

| 字段 | 类型 | 约束与默认值 | 说明 |
| --- | --- | --- | --- |
| `key` | TEXT | 主键，NOT NULL | 全局键，按业务加前缀 |
| `value` | TEXT | NOT NULL DEFAULT '' | 布尔用 `'0'`/`'1'`，结构化值用 JSON 字符串 |

设置是全局的，不按笔记分；按笔记的数据放 `notes` 或 `positions`。v1 至少使用以下保留键：

| 键 | 值 | 用途 |
| --- | --- | --- |
| `editor.restore_position` | `'0'` 或 `'1'` | 恢复上次编辑位置的全局开关；默认值与 UI 未实现，先不写入 |
| `bootstrap.samples.v1` | `'seeded'` | 样例已播种；只写一次，删光后也不重置 |
| `migration.desktop_json.v1` | `'pending'`、`'running'`、`'done'` 或 `'failed'` | 现有桌面 JSON 的一次性迁移状态 |
| `migration.desktop_json.v1.count` | 数字字符串 | 迁移或校验的笔记条数，便于诊断 |
| `migration.desktop_json.v1.error` | 文本 | 最近一次失败原因，仅诊断，不参与启动判断 |

索引：主键 `key`，无额外索引；设置项少，按主键读写即可。

### 2.7 结构版本与 `schema_meta`

- 当前结构版本 3 使用 `RdbStore.version` 保存，不建 `schema_meta` 表。结构版本只描述表和索引形态；样例播种、JSON 迁移等数据状态放 `settings`。
- 打开流程：读取 `store.version`；为 0 时建表并写入 1；低于当前版本时按版本顺序升级；高于当前版本时报明确错误并停止打开，不降级、不重建、不静默清库。
- 升级只做加法：`CREATE TABLE IF NOT EXISTS`、`ALTER TABLE`、`CREATE INDEX`；每个版本在一个事务中完成，成功后才更新版本号，失败回滚，不留下半套表。
- 如果后续需要 schema 级校验和或分步迁移表，在下一结构版本新增 `schema_meta(key, value)`；v1 不预建空表。

## 3. 块表与整篇文档的转换契约

### 3.1 `documentText`

`documentText(blocks)` 按 `ordinal` 升序，取所有 `image_id == ''` 的文本块，以单个 `\n` 连接；图片块不参与，不插入占位符或图注。

- 块 `body` 可以包含正文自身的换行；连接用的那一个 `\n` 不写入 `body`，只由连接规则产生。
- 文本块边界必须落在原文的换行处；阶段 2 采用单块，不受目标块大小限制；单段无换行超长文本只能保留为一个块。不得为了满足块大小在段内切块，否则连接会凭空增加换行。
- 空文本块参与连接，因此空行和末尾空行可以保留。
- 表结构不因拆块而变化；如果未来需要在段内拆块，必须同时升级拼装契约并记录版本，不能只改切分策略。

### 3.2 单块初始化

- 新建并首次保存：写入一个文本块，`ordinal=0`、`body` 为当前正文、`image_id=''`；不再额外创建空块。空白新草稿不创建笔记，纯图片允许保存。
- 旧笔记没有 `blocks`：正文非空时用 `content` 生成一个文本块；只有图片时按 `images` 生成图片块，不额外保留空文本块；已有 `blocks` 的原顺序、原块 ID 保留，不重新编号。
- 纯图片笔记：可以只有一个图片块，`body=''`、`image_id` 指向附件；此时 `documentText` 返回空字符串，标题回退显示「图片笔记」。
- `block_id` 由写入方生成并在笔记内唯一；已有块在普通保存中不得重新生成。被删除块的 ID 不复用。

### 3.3 整篇读入与差异回写

读入：按 ID 读取 `notes` 元信息、按 `ordinal` 读取 `blocks`、读取所属 `attachments` 和 `positions`；用 `documentText` 还原整篇纯文本，同时把 `revision` 交给编辑会话。

回写要求：

1. 保存请求携带笔记 ID、`baseRevision`、标题、整篇文档或等价变更，以及图片增删。
2. 在事务中先校验笔记存在、`deleted=0`、`revision == baseRevision`；不满足则返回 `conflict` 或 `deleted`，不写任何行。
3. 对旧文档和新文档做差异比较，只更新变化区间涉及的块；未变化块的 `block_id`、`ordinal` 和正文保持不变。
4. 禁止每次保存先 `DELETE FROM blocks WHERE note_id` 再整篇插入；这会让普通输入重切全文并放大写入。
5. 结构变化（拆块、合块、插入或删除图片块）只调整受影响区间；`ordinal` 允许间隔，间隔耗尽时只重排该笔记。
6. 同一事务内更新 `title`、`summary`、`content_length`、`revision`、`updated_at` 和附件引用；提交失败整笔回滚，编辑页保留草稿。
7. 图片插入或删除只改图片块和附件引用，不把图片写成文本、base64 或路径。

当前 `NoteEditorWeb` 用独立 Web 投影：文本块按行、图片块写成 `\uFFFC` 占位行，返回时按行拆分并用带权顺序对齐复用原块 ID；图片只以附件 ID 参与，缩略图经 data URL 显示。单行修改和行尾新增已验证保留原块 ID；旧含图笔记的显示与保存已验证，附件引用保持；拆块、合块、旧块内含换行和大段重写仍可能换 ID 或触发整篇重插，新图插入仍待验。目标契约仍以本节 1～7 为准。

### 3.4 偏移、版本与冲突校验

- 偏移单位是 UTF-16 code unit，不是字节或码点；范围 `[0, body.length]`，落在代理对中间时视为无效并校正到字符边界。
- 位置恢复按 `(note_id, block_id)` 查找块，不按 `ordinal`；块不存在或偏移越界时回退到邻近块或正文末尾。
- `positions.revision` 与当前 `notes.revision` 不一致时，不直接丢弃锚点：先校验块是否存在、偏移是否在范围内；有效则复用并更新版本，无效才回退。
- 保存冲突由 `revision` 条件更新判定；快照只用于辅助发现外部变化或迁移期兜底，不能代替条件更新。

### 3.5 往返一致性与撤销边界

- 对任意已保存笔记，`documentText(按 ID 读出的 blocks)` 必须与保存时的正文逐字符一致；不 trim、不替换换行、不吞尾随空格。
- 保存后重新读取，块顺序、块 ID 和未修改块正文保持一致；只有变化区间允许不同。
- 分享包含标题和 `documentText` 正文，不含其他元信息、分组、皮肤、图片和图注；复制和字数统计同样基于正文纯文本。
- 字数为正文去空白后的 Unicode 码点数，含标点，不含标题、图片和图注；`content_length` 必须是该值的缓存。实时字数与 `content_length` 同口径，缓存策略见 3.6。
- 撤销是编辑引擎内的事务级历史，按键合并窗口 1 秒，粘贴、插图、删除选区各自独立一步；不写数据库，离页清空。数据库只接收提交后的正文，不保存撤销栈。
- 当前长文外壳的 CodeMirror 历史已配 1 秒合并窗口；主编辑仍是标题/正文块的内存历史，合并窗口 2 秒。

### 3.6 块粒度、字数缓存与定位分期

- `block_id` 是数据库最小可寻址单位，但不限制块内文本长度。当前块通常按段落使用，单段 10 万字仍是一个块；这是暂时接受的边界，不代表已支持 10 万字，验收挂在阶段 4b，若后续需要可在块内再分文本段或做变化区间写入，届时需评估 schema。
- 实时字数保留“正文去空白后的 Unicode 码点数”口径，与 `content_length` 一致。4a 已按块维护计数缓存：块文本变化时重算整个块，总数只做 `newCount - oldCount` 差值；拆块/合块只重算受影响块。保存时全文重算一次作为权威校验，缓存与全文不一致时以全文为准；Web 外壳头部已显示字数。
- 不采用“全文档逐字符变化量”作为首版：多 change、输入法预输入、撤销、代理对和换行都会引入边界错误；块内增量留到单段超长块真正需要时再做。
- 阶段 4 的位置只记录 `edit_block_id`，打开时滚动到块并以浏览态进入；块内偏移、浏览位置和编辑位置分离在阶段 5。

## 4. 迁移与初始化

### 4.1 打开与初始化顺序

1. 打开 `notes.db`，读取 `RdbStore.version`；为 0 时建表并写 1，高于当前版本则报错停止。
2. 检查 `migration.desktop_json.v1`；未完成时执行现有 JSON 的一次性迁移。
3. 检查 `bootstrap.samples.v1`；首次初始化时播种 `FAKE_NOTES` 并写标记。
4. 初始化和迁移通过后，才允许列表、编辑和卡片读取数据库。

步骤 1～3 已接入主应用；首页摘要缓存与旧 JSON 投影仍保留，迁移验收完成前不把数据库当作可随意清空的唯一副本。

### 4.2 JSON → 数据库迁移

来源是 `filesDir/desktop-notes/notes` 下的 `DesktopRecord` v1、`forms` 下的卡片关联和 `filesDir/note-images` 中的文件。迁移只读原数据，不修改、不移动、不删除。

| 来源 | 目标 | 规则 |
| --- | --- | --- |
| `DesktopRecord.note` | `notes` + `blocks` + `attachments` | 按 ID 写入；正文块缺失时用 `content` 建单块；图片 `path` 转为相对 `rel_path` |
| `DesktopRecord.deleted` | `notes.deleted=1` | 写入墓碑行；保留 ID，防止旧样例或旧草稿复活 |
| `Note.blocks` | `blocks` | 保留顺序和块 ID；图片块 `body=''` |
| `Note.images` | `attachments` | 保留 ID、宽高、字节数、描述与小号标记；`name` 由 `rel_path` 文件名派生 |
| `forms/*.json` | 保留原文件 | 卡片关联不迁入数据库；校验 `noteId` 可解析，关联不是笔记内容权威 |

- 以笔记 ID 为单位幂等：已存在的 ID 跳过，不覆盖数据库中更新的内容；重复执行不会重复插入块或附件。
- v1 数据量小，整批一个事务即可满足中断可恢复：启动前写 `running`，全部写入并校验后写 `done`；中途崩溃回滚，重启从头重跑。若以后改为分批，必须按 ID 记录进度并保持每批幂等。
- 成功后校验：笔记条数与墓碑数、每个 ID 的正文往返一致、附件文件存在、块引用能解析。校验不通过不写 `done`。
- 成功前保留原 JSON 和图片；成功后原 JSON 只作卡片投影/回退，可随保存更新；不是权威，不参与版本判定。至少保留到阶段 2 验收，清理另做。迁移失败不切换数据源，不重置数据库，记录错误并允许重试。

### 4.3 样例播种与「删光不复生」

- 首次初始化且 `bootstrap.samples.v1` 不存在时，在一个事务中写入 `FAKE_NOTES`（含长文回归样例），并写 `'seeded'`；已存在的同 ID 行跳过，墓碑保持删除状态。
- 样例时间戳按数组顺序递减，保证首次列表顺序与当前样例顺序一致；旧 JSON 迁移也按枚举顺序填递减时间，避免重启后顺序跳变。
- 是否播种以标记为准，不以列表是否为空判断。删除全部笔记后列表为空，标记仍保留，重启不重新生成样例。
- 升级前在内存中删除的样例没有持久墓碑，首次初始化可能恢复一次；这是旧路径没有持久化删除记录的迁移边界，此后不再恢复。

## 5. 多入口与冲突

### 5.1 共享方式

- 主应用、桌面卡片 `FormExtensionAbility`、半模态 `FormEditExtensionAbility` 共享同一个数据库文件和私有附件目录；每个进程各自打开 `RdbStore`，不能依赖模块单例跨进程共享。
- 首页和卡片只读 `notes` 的标题、摘要、分组、皮肤、版本和墓碑；首页缓存只保存摘要，编辑页按 ID 读取整篇，附件清理按数据库引用而非首页缓存判断。
- 首页摘要读取已接入；编辑页懒加载整篇后仍保留同步草稿会话，未加载完成时不显示空白保存入口。
- 主应用与半模态共用同一保存服务和 Repository，保存规则只有一份；页面内草稿在提交前不是权威数据。

### 5.2 `revision` 与冲突处理

| 入口 | 读取 | 写入 | 冲突处理 |
| --- | --- | --- | --- |
| 主应用 | 列表元信息；编辑页读整篇 | 正文、标题、图片、移动、换肤、删除 | 按 `revision` 条件更新，失败保留草稿 |
| 桌面卡片 | 按 `noteId` 读投影 | 不写正文；只增删卡片关联 | 删除笔记显示占位，不创建替代笔记 |
| 半模态 | 读整篇及附件 | 标题、正文块 | 与主应用相同的条件更新 |

- 打开笔记时记录 `notes.revision`；保存时在事务中执行 `WHERE id=? AND revision=? AND deleted=0` 的更新，受影响行数为 0 时返回 `conflict` 或 `deleted`。已由 `saveNoteChecked` 接入主编辑与半模态。
- 条件检查通过后才写 `blocks`、`attachments` 和 `notes` 派生字段；提交后 `revision` 加 1。移动和换肤也递增 `revision`，但不改 `updated_at`。
- 冲突时保留编辑中的草稿并提示用户选择版本，不能用旧草稿静默覆盖新内容；笔记已被删除时按 `deleted` 处理。
- 回到前台发现外部更新且存在未保存草稿时，让用户选择版本；快照和条件更新都不提供跨进程事务保证。
- `snapshotNote` 固定字段快照仍保留为辅助检查；冲突判定以 `revision` 条件更新为准。
- 写入失败返回明确错误并保留草稿；卡片刷新失败不回滚已成功提交的笔记。

### 5.3 卡片 JSON 的定位

采用「卡片是派生投影」：

- 目标形态是卡片内容由数据库笔记按 `formId → noteId` 实时或刷新时生成；当前过渡实现仍写完整 JSON 投影，见下方事实说明。
- `forms/*.json` 继续保存 `formId` 和 `noteId` 的关联，属于平台卡片身份映射，不是笔记内容，也不作为第二份权威数据。
- `formId`、`noteId` 均按 string 保存，避免 64 位整数精度损失；一个 `formId` 一个关联文件，允许多张卡片指向同一笔记。
- 当前实现仍写完整 `Note` JSON 作为卡片投影：仅进入发送预览或已有投影记录的笔记写入，包含正文块和附件路径；投影可随时从数据库重建，但删除或清空数据前必须确认数据库是权威副本。
- 移除卡片只删除关联，保留笔记；删除笔记写入墓碑并把卡片刷新为删除占位。

### 5.4 位置与设置

- 编辑位置和浏览位置分别写入 `positions`，互不覆盖；单纯滚动只更新浏览锚点。
- 多入口同时写位置时按最后写入生效，不弹冲突提示；位置写入不改 `notes.updated_at`，不影响首页排序。
- 全局设置按最后写入生效；不做跨设备同步或跨进程事务承诺。

## 6. 当前字段契约

| 当前类型 | 字段 | 当前语义 | 目标映射 |
| --- | --- | --- | --- |
| Note | `id`/`title`/`content`/`timeLabel`/`group` | string；`group` 空字符串为未分类；`content` 为正文纯文本 | `id`/`title`；`content` 不单独存，由 `blocks` 派生；`timeLabel` → `time_label`；`group` → `group_name` |
| Note | `skinId?`/`blocks?`/`images?` | 可选；缺失皮肤默认白，旧 `content` 转文字块 | `skin_id`；`blocks` → `blocks`；`images` → `attachments` |
| BodyBlock | `id`/`text`/`imageId` | string；`imageId` 为空表示文字，否则引用附件 | `block_id`/`body`/`image_id` |
| NoteImage | `id`/`path`/`name`/`caption` | string；`path` 为应用私有文件绝对路径 | `attachments.id`；`path` → `rel_path`；`name` 由路径文件名派生；`caption` 保留 |
| NoteImage | `width`/`height`/`bytes`/`small` | number/number/number/boolean | `width`/`height`/`bytes`/`small` |
| DesktopRecord | `version`/`id`/`deleted`/`note?` | `version` 当前 1；墓碑不等于回收站 | 版本由 schema/迁移状态取代；`id`/`deleted` → `notes`；`note` → 各目标行 |
| DesktopFormLink | `formId`/`noteId` | string/string，一卡一个关联文件 | 保留 `forms` JSON，不建表 |

仍有效的现行规则：

- 标题为空取正文首个非空行，纯图片显示「图片笔记」；纯图片可保存。
- 字数为正文去空白后码点数，含标点，不含标题和描述。
- 当前 `timeLabel` 是展示文本，新保存为「月日 时分」，无 `createdAt`/`updatedAt` 时间戳。移动文件夹和保存正文保留皮肤设置；保存前置笔记，移动/换肤保持顺序；启动合入 JSON 记录，不按更新时间排序。
- 图片插入/删除入历史，描述和尺寸独立保存、不随撤销变化；删除图片后文件和属性保留至离页以支持撤销；保存仅保留正文仍引用的附件；草稿存在时 `images_json` 内的图片视为引用，启动时清理无引用且超过 60 秒的文件。跨进程导入中的竞态只靠时间窗规避，未做锁或事务级回收。
- 删除仅对已有 JSON 记录写墓碑；未持久化样例的删除是进程内行为，重启可能恢复。目标改为所有删除写数据库墓碑并依赖播种标记。
- JSON 读取主要校验 `version`、记录 ID 和 `note.id`，损坏记录可能抛错，不提供自动修复或完整 schema 迁移。
- `saveNoteDraft` 返回 `saved`、`empty`、`conflict`、`deleted` 或 `storageError`；空白新草稿退出不创建，已有笔记清空不自动删除。
- 当前无置顶、回收站、独立 Folder/TodoItem、标签表；文件夹入口仍为占位。分组展示和空分组语义已确定。
- 当前 JSON 数据层回归命令：`node scripts/test-desktop-notes.cjs`。脚本使用本机 DevEco 的 TypeScript 编译器，其他环境通过 `DEVECO_TYPESCRIPT_PATH` 指定 `typescript.js`；该脚本只覆盖 JSON 路径，数据库迁移需补对应检查。

## 7. 未实现与待定

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 关系库正式接入 | 基础看板已接入 | 首页读摘要、编辑页按 ID 加载整篇，保存走 revision 条件更新；半模态优先读库并已真机验证写回主应用；卡片无写入、读数据库写入同步的投影；迁移逐 ID 校验未完成，旧 JSON 保留为投影/回退 |
| 迁移状态记录 | 已实现基本状态机 | `migration.desktop_json.v1` 记录 `running`/`done`/`failed`，并写条数与错误；失败下次启动重试；逐 ID 往返校验未实现 |
| 自动草稿 | 已接入 | schema v3 `drafts` 表；编辑停顿约 800ms 写入，离页/销毁冲刷，首页草稿条恢复，保存成功、空白或忽略后删除；主编辑和长文外壳均复用，草稿旧版本校验、图文草稿恢复与旧版本提示均已真机验证 |
| 位置恢复 | 部分实现 | `positions` 读写已接；长文外壳用 `edit_block_id` 做块级定位，打开滚动到块并以只读态进入，`browse_*` 留空；开关、失效回退、块内偏移和浏览/编辑位置分离仍未接，标题位置不持久化 |
| 缩略图 | 已接入 | 长边 960、质量 75，生成到 `note-images-thumbs`；正文优先缩略图、详情用原图；缺失可重建，随原图引用清理，不进入附件主记录 |
| 原图压缩与 500KB 拒绝 | 已接入 | 原文件不超过 500KB 时直接保留；超过时按长边 2048/1600/1024 缩放并用 JPEG 85/75/65 重压，仍超限才拒绝。真机截图压缩到 101281 字节后插入 |
| 图注 | 部分 | `attachments.caption` 承接现有图片描述；独立图注编辑、排版、导入图注延后 |
| 图片大小号 | 已接入 | `attachments.small`（v2）保留 `NoteImage.small` 语义 |
| 搜索 | 未实现 | 首页搜索框仅输入，无查询、索引或 FTS |
| 回收站 | 未实现 | `deleted` 是墓碑，不是回收站；无恢复入口 |
| 文件夹/标签/待办 | 未实现 | 只有 `group_name`；无 Folder、Tag、TodoItem 表 |
| 多设备同步/导入导出/备份 | 不在本轮 | 目标只保证本机进程重启恢复；旧路径只有桌面笔记可重启恢复，数据库路径尚未验收，不承诺卸载恢复或跨设备 |
| 十万字按需读写/渲染 | 部分实现 | 主编辑整篇加载；`NoteEditorWeb` 把整篇交给 CodeMirror 视口渲染，已做块级定位，但一次加载、未做块内/分块读写，单段 10 万字暂缓验收 |
| 事务级撤销 | 部分实现 | 长文外壳 CodeMirror 已配 1 秒合并窗口；主编辑仍为页内 2 秒合并历史，均不落库 |
| 相对日期格式 | 未实现 | `time_label` 为固定展示文本，无「今天/昨天」动态格式化 |
| 旧 JSON 清理 | 未实现 | 迁移成功前不得删除；成功后备份清理另行安排 |
| `schema_meta` | 未实现 | v3 使用 `RdbStore.version`；确有 schema 级元数据需求时在下一版本新增 |
| 孤立附件回收 | 部分实现 | 启动时扫描 `note-images`，删除无引用且超过 60 秒的文件；草稿图片计入引用，删除笔记时删附件记录并立即清理该笔记原图/缩略图；导入中的跨进程竞态只靠时间窗保护 |

仍需产品决定：回收站、标签/文件夹管理扩展、相对日期格式、富文本样式范围。现有分组展示和空分组语义已确定。职责与状态见[架构](architecture.md)，阶段任务与验收见[持久化计划](plans/persistence-plan.md)，早期候选字段仅保留于[候选历史](archive/2026-11-12-data-model-proposals.md)。
