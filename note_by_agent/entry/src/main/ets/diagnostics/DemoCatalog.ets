// 集中定义技术实验入口、功能开关与共用布局参数。
export interface DemoEntry {
  id: string;
  title: string;
  description: string;
  route: string;
}

export const TECH_DEMOS_ENABLED: boolean = true;

export const DEMO_CATALOG: DemoEntry[] = [
  {
    id: 'privacy-editor',
    title: '隐私编辑',
    description: '光标行可见、其余遮挡；按住查看全文。仅使用不保存的临时文字。',
    route: 'pages/PrivacyEditorDemo'
  },
  {
    id: 'long-document',
    title: '长笔记与位置定位',
    description: '2 万 / 10 万字符、整篇输入与懒加载对比。仅使用临时数据。',
    route: 'pages/LongDocumentDemo'
  },
  {
    id: 'database',
    title: '数据库与位置存储',
    description: '独立试验库：分块范围读取、版本竞争、事务回滚及重开恢复。',
    route: 'pages/DatabaseDemo'
  },
  {
    id: 'note-store',
    title: '正式笔记库自检',
    description: '计数、块往返、版本递增、墓碑与清理；写入一条临时笔记后删除。',
    route: 'pages/NoteStoreDemo'
  },
  {
    id: 'native-editor',
    title: '原生跨片段编辑',
    description: '单个 RichEditor：跨片段选区、全选、删除及原生复制粘贴。全量加载对照。',
    route: 'pages/NativeEditorDemo'
  },
  {
    id: 'web-editor',
    title: 'Web 长文编辑对照',
    description: '离线 CodeMirror：全文模型、视口渲染与输入试验。不接入正式数据。',
    route: 'pages/WebEditorDemo'
  }
];

export class DemoStyle {
  static readonly gap: number = 12;
  static readonly padding: number = 16;
  static readonly font: number = 16;
  static readonly lineHeight: number = 24;
  static readonly editorHeight: number = 320;
  static readonly imageHeight: number = 180;
  static readonly cacheCount: number = 2;
}
