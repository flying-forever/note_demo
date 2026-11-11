# 数据模型

## 当前实现

`model/Note.ets` 使用 `id`、`title`、`content`、`timeLabel`、`group`。首页从正文生成卡片预览，初始时间沿用假数据的展示文本。`repository/NoteRepository.ets` 管理进程内已提交数据，`services/NoteService.ets` 统一业务保存，`viewmodel/NoteEditorSession.ets` 持有主编辑页唯一草稿及历史。原 NoteStore 与 model 层 DesktopNoteRepository 转发入口已移除。

可选字段 `skinId` 保存笔记皮肤标识，缺失或未知时按默认白显示。`model/NoteSkin.ets` 集中定义当前12款皮肤配色与effect。移动文件夹及保存正文保留皮肤设置。

## 当前图文正文

可选 `blocks: BodyBlock[]` 按顺序存储文字与图片引用；旧笔记首次打开转换为单个文字块。`content` 保持为文字块以换行拼接的纯文本，供首页摘要、字数及纯文本分享使用，不包含图片描述。

可选 `images: NoteImage[]` 保存附件 ID、私有文件路径、应用内文件名、像素宽高、字节数、描述和小号状态。文件在 `filesDir/note-images`，不修改相册源文件。移动文件夹、切换皮肤保留正文与附件。

历史记录保存标题及 blocks 的序列化快照；图片描述和尺寸存于独立附件属性，不随撤销变化。删除节点后，文件和属性保留至离页以支持撤销；保存仅保留正文仍引用的附件，离页删除不被任何内存笔记引用的当前附件。异常退出和跨进程孤立附件清理留待笔记持久化阶段处理。

## 桌面笔记的最小持久化

进入「发送到桌面」预览后，仅对该笔记启用持久保存。完整 Note（含 blocks、images、group、skinId）写入 filesDir/desktop-notes/notes 下独立的版本化 JSON 记录；新建 ID 包含时间戳与进程内序号，避免重启后的计数重复。写入先落临时文件、同步后重命名，再更新内存，写入失败保留原值。其他笔记仍为内存数据。

桌面卡片 ID 按 string 保存，避免 64 位整数精度损失。forms 下每张卡片有独立关联文件，支持多张卡片引用同一笔记。保存、移动、换肤后刷新相关卡片；移除卡片只删除关联，保留笔记。删除笔记写入删除标记，防止同 ID 的假数据在重启后重新出现，并把相关卡片刷新为删除状态。

应用启动及回到前台时从磁盘同步桌面笔记，供 UIAbility、FormExtensionAbility 与 FormEditExtensionAbility 共享数据。主编辑与半模态通过 saveNoteDraft 保存，使用固定字段顺序的 snapshotNote 快照检查，返回 saved、empty、conflict、deleted 或 storageError。外部更新或删除不能被旧草稿静默覆盖；主编辑页回到前台时有未保存草稿则让用户选择版本。快照比较仍为尽力检测，不提供跨进程事务保证。

每次写入使用独立临时文件，避免固定 .tmp 互相踩写；唯一文件名不等于原子并发控制。卡片配色和 FormKit 更新位于 platform/DesktopCards，存储仓库不依赖展示或系统通知；已成功保存不因卡片刷新失败回滚。

数据层回归命令：`node scripts/test-desktop-notes.cjs`。脚本使用本机 DevEco 的 TypeScript 编译器；其他环境通过 DEVECO_TYPESCRIPT_PATH 指定 typescript.js。该检查验证选择性保存、应用重启、图片引用、移动/皮肤、写入失败、跨实例更新、多卡片与删除标记，UI 和系统能力仍需真机验收。

## 当前字段契约

| 类型 | 字段 | 语义 |
| --- | --- | --- |
| Note | id/title/content/timeLabel/group | string；group空字符串为未分类，无folderId关系表 |
| Note | skinId?/blocks?/images? | 可选；缺失皮肤默认白，旧content转文字块 |
| BodyBlock | id/text/imageId | string；imageId为空表示文字，否则引用附件 |
| NoteImage | id/path/name/caption | string；path为应用私有文件 |
| NoteImage | width/height/bytes/small | number/number/number/boolean |
| DesktopRecord | version/id/deleted/note? | version当前1；墓碑不等于回收站 |
| DesktopFormLink | formId/noteId | string/string，一卡一个关联文件 |

当前timeLabel是展示文本，新保存为月日时分，无createdAt/updatedAt时间戳。保存前置笔记，移动/换肤保持顺序；启动合入JSON记录，不是按更新时间排序。当前无置顶、回收站、独立Folder/TodoItem、标签表。

标题为空取正文首个非空行，纯图片显示「图片笔记」；纯图片可保存。字数为正文去空白后码点数，含标点，不含标题和描述。删除仅对已有JSON记录写墓碑；未持久化样例删除是进程内行为，重启可能恢复。JSON读取主要校验version、记录ID和note ID，损坏记录可能抛错，不提供自动修复或完整schema迁移。

## 后续契约与未决定事项

已确认关系型数据库、有序正文块、附件目录和小型设置存储方向，统一选择性JSON，支持10万字按需读写/渲染、草稿及可关闭的位置恢复；尚未成为正式实现。候选字段、迁移和验收统一见[持久化计划](plans/persistence-plan.md)，不在当前契约预设建表和排序。

仍需产品决定：回收站、标签/文件夹管理扩展、相对日期格式、富文本样式范围。现有分组展示和空分组语义已确定。职责与状态见[架构](architecture.md)。

早期未定稿的Folder/TodoItem候选字段及排序设想仅保留于[候选历史](archive/2026-11-12-data-model-proposals.md)，不作为当前实现或正式数据库设计。
