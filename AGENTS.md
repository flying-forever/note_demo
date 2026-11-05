# AGENTS.md

本文件记录协作约定，供每次开始工作前阅读。

## 项目概况

- 项目：小米笔记（简化复刻 demo）
- 工程根目录：`note_by_agent/`（ArkTS 鸿蒙项目）
- 素材目录：`picture/`（设计参考截图）
- 协作文档：`docs/`

## 技术栈与环境

- 语言：ArkTS / ArkUI 声明式 UI
- 模型：Stage 模型
- SDK：HarmonyOS 5.1.1(19)，`targetSdkVersion` = `compatibleSdkVersion` = 5.1.1(19)
- 包名：`com.example.note_by_agent`
- 模块：`entry`（唯一 entry 模块）
- 当前入口页：`entry/src/main/ets/pages/Index.ets`（`pages/Index`）
- 测试：`@ohos/hypium` + `@ohos/hamock`
- 构建/预览：在 DevEco Studio 中 Build / Previewer 运行（工程未检出 hvigorw 包装脚本）

## 目录约定

```
note_by_agent/entry/src/main/ets/
  entryability/        Ability 入口
  pages/               页面（@Entry）
  components/          可复用组件（后续新建）
  model/               数据模型与假数据（后续新建）
  viewmodel/           状态与业务逻辑（后续新建）
  common/              常量、工具（后续新建）
```

## 代码约定

- 一个页面一个 `.ets` 文件，`@Entry @Component struct Xxx`。
- 可复用 UI 抽到 `components/`，命名 `XxxView` / `XxxItem`。
- 颜色、字号、间距优先集中在 `resources/base/element/` 或 `common/` 常量中，禁止到处写魔法值。
- 资源引用用 `$r('app.color.xxx')` / `$r('app.string.xxx')`。
- 状态用 `@State` / `@Prop` / `@Link`，跨页传参用 `router` 或 `AppStorage`。
- 缩进 2 空格。
- 除非明确要求，不写注释。

## 协作流程

1. 每次只做一个页面或一个功能闭环。
2. 先对齐需求（用户口头描述布局/交互），同步更新 `docs/pages.md`。
3. 实现时尽量少改文件，完成后列出改动清单。
4. 用户在 DevEco Studio 构建，把完整报错原样贴回。
5. 视觉差异由用户反馈，逐条修正。
6. 不自动执行 git commit / push，除非用户明确要求。
7. 设计不确定时先问，不自行臆造。

## 阶段目标

- 先做 `home` 页假数据界面（无底部导航，顶部导航栏）。
- 其余页面（dir / edit / todo）后续迭代。
- 持久化在界面稳定后实现。

## 文档索引

- `docs/design.md`：设计规范（色值、字号、间距）
- `docs/pages.md`：页面规格
- `docs/data-model.md`：数据模型
- `docs/progress.md`：进度、决策、待定项
