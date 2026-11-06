# 数据模型

## 当前实现

`model/Note.ets` 的首页假数据使用 `id`、`title`、`summary`、`timeLabel`、`group` 五个字符串字段。摘要和时间是预设展示文本，分组用名称匹配。

## 候选模型

以下字段、默认排序和持久化方案供后续阶段确认。当前实现以首页假数据字段为准。

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
