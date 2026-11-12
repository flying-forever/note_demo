# 离线 Web 长文引擎对照

仅使用 ArkTS 传入的临时合成文字，未接入正式笔记、数据库或剪贴板读取。使用 CodeMirror 6 完整文档模型与视口渲染，不开启语法分析。包含自动换行、撤销重做和基础键位。图文编辑尚未实现。

`window.noteProbe` 提供同步返回 JSON 字符串的 `load(text)`、`snapshot()`、`check()`、`select(all)`、`editCheck()`、`jump(fraction)`、`focusTail()`、`clearFocus()`、`inputCheck(marker)`。加载后等待两次动画帧再读取 snapshot；`loadMs` 不含 ArkTS 跨桥传输、不等于冷启动或像素首帧。事务检查不替代真实输入法、手指选区、系统剪贴板及无障碍验收。

固定材料及 SHA-512 在 dependencies.lock.json，许可见 THIRD_PARTY_LICENSES.txt。根目录运行 `node scripts/build-web-editor-demo.cjs` 可重新下载并打包；Windows x64、Node 22、系统 tar；不执行包管理器安装或依赖生命周期脚本。已有下载缓存时可加 `--offline`。缓存解包位于忽略的 note_by_agent/build/verification/web-editor-build，下载内容同时对照上游完整性字段及已有锁定值。页面仅引用本地 bundle，不发网络请求。

官方机制资料：[CodeMirror 系统指南](https://codemirror.net/docs/guide/)、[API](https://codemirror.net/docs/ref/)。本实验固定 view 6.36.5、state 6.5.2、commands 6.8.1；性能结论仅适用于实际测试版本与设备。
