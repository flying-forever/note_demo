# 数据模型

## 当前实现

`model/Note.ets` 使用 `id`、`title`、`content`、`timeLabel`、`group`。首页从正文生成卡片预览，初始时间沿用假数据的展示文本。`model/NoteStore.ets` 管理进程内数据，编辑页持有独立草稿。

可选字段 `skinId` 保存笔记皮肤标识，缺失或未知时按默认白显示。`model/NoteSkin.ets` 集中定义皮肤配色，供后续接入素材。移动文件夹及保存正文保留皮肤设置。

## 样式和图片的扩展方向

- 确定样式范围后，可把纯文本正文迁移为带版本的文档。段落中的文本片段可附带加粗等样式，段落与图片可按插入顺序排列。旧纯文本可转成普通段落，保留换行。
- 图片正文节点保存附件 ID。接入持久化时，由应用管理图片文件和引用，在保存、删除时处理文件生命周期。
- 首页摘要和未来的搜索文本从正文提取。加入图片后，判断空笔记时也要检查图片节点，只有图片的笔记可以保存。

## 候选模型

以下字段、默认排序和持久化方案供后续阶段确认。

## Note（笔记）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 唯一标识 |
| `title` | string | 标题（可为空，界面回退为正文首行） |
| `content` | string | 正文纯文本 |
| `createdAt` | number | 创建时间戳 |
| `updatedAt` | number | 更新时间戳 |
| `pinned` | boolean | 是否置顶 |
| `folderId` | string \| null | 所属文件夹，null 为默认 |
| `group` | string \| null | 首页分组名称（旅途/美食/攻略/随记） |
| `color` | string \| null | 标签/卡片颜色，可空 |
| `deleted` | boolean | 回收站标记 |

## TodoItem（待办项）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 唯一标识 |
| `noteId` | string | 所属待办笔记 |
| `text` | string | 内容 |
| `done` | boolean | 是否完成 |
| `order` | number | 排序 |

## Folder（文件夹）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 唯一标识 |
| `name` | string | 名称 |
| `createdAt` | number | 创建时间戳 |
| `order` | number | 排序 |

## 排序规则（默认）

1. 置顶优先
2. `updatedAt` 倒序

## 持久化方案（待定）

候选：
- `@ohos.data.preferences`：键值对，适合小数据、实现简单。
- `@ohos.data.relationalStore`：关系型，适合后续检索/多表。

暂定：先 Preferences 存 JSON，接口保持 `NoteRepository` 抽象，方便替换。

## 待确认

- [ ] 是否需要回收站
- [ ] 是否需要标签/文件夹（首页是否展示）
- [ ] 时间显示格式（今天 HH:mm / 昨天 / 日期）
