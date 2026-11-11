export interface DemoEntry {
  id: string;
  title: string;
  description: string;
  route: string;
}

export const TECH_DEMOS_ENABLED: boolean = true;

export const DEMO_CATALOG: DemoEntry[] = [
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
    id: 'native-editor',
    title: '原生跨片段编辑',
    description: '单个 RichEditor：跨片段选区、全选、删除及原生复制粘贴。全量加载对照。',
    route: 'pages/NativeEditorDemo'
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
