# 数据模型

> 当前阶段：界面用内存假数据；字段先定形，后续替换为持久化存储时尽量少改 UI。

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
