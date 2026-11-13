// 验证原生富文本编辑器的跨片段选区、删除与复制粘贴行为。
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { DemoChunk, fixtureText, splitDemoText } from '../diagnostics/LongDocumentFixture';
import { DemoFrameProbe } from '../diagnostics/DemoFrameProbe';
import { SystemBars } from '../platform/SystemBars';
import { LengthMetrics } from '@kit.ArkUI';

const EDITOR_ID: string = 'native-rich-probe';
const SELECTION_RADIUS: number = 5;

@Entry
@Component
struct NativeEditorDemo {
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;
  @State private length: number = 20000;
  @State private paragraphs: boolean = false;
  @State private keyboard: boolean = false;
  @State private ready: boolean = false;
  @State private loaded: boolean = false;
  @State private status: string = '选择场景后加载。';
  @State private selectionLabel: string = '选区：未设置';
  @State private changes: number = 0;
  @State private copies: number = 0;
  @State private pastes: number = 0;
  @State private bulk: boolean = false;
  @State private single: boolean = false;
  @State private measurement: string = '测量：未开始';
  private controller: RichEditorController = new RichEditorController();
  private styledController: RichEditorStyledStringController = new RichEditorStyledStringController();
  private original: string = '';
  private boundary: number = 0;
  private sample: number = 0;

  aboutToAppear(): void {
    SystemBars.applyForBackground('#FFFFFF');
  }

  aboutToDisappear(): void {
    this.sample++;
  }

  private activeController(): RichEditorBaseController {
    return this.bulk ? this.styledController : this.controller;
  }

  private switchImport(): void {
    this.activeController().stopEditing();
    this.sample++;
    this.ready = false;
    this.loaded = false;
    this.bulk = !this.bulk;
    this.measurement = '测量：未开始';
  }

  private exported(): string {
    if (this.bulk) {
      return this.styledController.getStyledString().getString();
    }
    return this.controller.getSpans().map((span: RichEditorImageSpanResult | RichEditorTextSpanResult) =>
      (span as RichEditorTextSpanResult).value).join('');
  }

  private load(): void {
    const totalStart: number = Date.now();
    const token: number = ++this.sample;
    this.activeController().stopEditing();
    this.getUIContext().getFocusController().clearFocus();
    this.original = fixtureText(this.length, this.paragraphs);
    const chunks: DemoChunk[] = splitDemoText(this.original);
    this.boundary = chunks[0].text.length;
    let offset: number = 0;
    const styles: StyleOptions[] = chunks.map((chunk: DemoChunk, index: number) => {
      const style: StyleOptions = { start: offset, length: chunk.text.length, styledKey: StyledStringKey.FONT,
        styledValue: new TextStyle({ fontSize: LengthMetrics.vp(DemoStyle.font),
          fontColor: index % 2 === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary') }) };
      offset += chunk.text.length;
      return style;
    });
    const styled: StyledString | undefined = this.bulk ? new StyledString(this.original, styles) : undefined;
    const preparedAt: number = Date.now();
    if (this.bulk) {
      this.styledController.setStyledString(new StyledString(''));
    } else {
      this.controller.deleteSpans();
    }
    const start: number = Date.now();
    if (styled) {
      this.styledController.setStyledString(styled);
    } else if (this.single) {
      this.controller.addTextSpan(this.original, { style: { fontSize: DemoStyle.font,
        fontColor: $r('app.color.text_primary') } });
    } else {
      chunks.forEach((chunk: DemoChunk, index: number) => {
        this.controller.addTextSpan(chunk.text, { style: { fontSize: DemoStyle.font,
          fontColor: index % 2 === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary') } });
      });
    }
    const committedAt: number = Date.now();
    this.loaded = true;
    this.changes = 0;
    this.copies = 0;
    this.pastes = 0;
    this.selectionLabel = '选区：未设置';
    this.status = `导入 ${chunks.length} 片段 / ${this.original.length} 字符，控制器调用 ${committedAt - start}ms（非首帧）`;
    this.measurement = '测量：等待空闲帧';
    this.getUIContext().postFrameCallback(new DemoFrameProbe(() => {
      if (token !== this.sample) {
        return;
      }
      const elapsed: number = Date.now() - totalStart;
      const lines: number = this.activeController().getLayoutManager().getLineCount();
      this.measurement = `测量：${this.bulk ? '批量' : this.single ? '整段' : '逐片段'}｜准备 ${preparedAt - totalStart}ms｜清理 ${start - preparedAt}ms｜提交 ${committedAt - start}ms｜至空闲帧 ${elapsed}ms｜排版 ${lines} 行`;
    }));
  }

  private select(all: boolean): void {
    this.getUIContext().getFocusController().requestFocus(EDITOR_ID);
    const start: number = all ? 0 : this.boundary - SELECTION_RADIUS;
    const end: number = all ? this.exported().length : this.boundary + SELECTION_RADIUS;
    this.activeController().setSelection(start, end, { menuPolicy: MenuPolicy.HIDE });
    this.status = all ? '已请求原生全选，请检查选区' : `已请求跨片段选区 ${start}～${end}`;
  }

  private checkSelection(): void {
    if (this.bulk) {
      const range: RichEditorRange = this.styledController.getSelection();
      const start: number = range.start ?? 0;
      const end: number = range.end ?? 0;
      const document: MutableStyledString = this.styledController.getStyledString();
      if (end <= start) {
        this.status = '选区核对失败：无有效选区';
        return;
      }
      const selected: string = document.subStyledString(start, end - start).getString();
      const count: number = document.getStyles(start, end - start, StyledStringKey.FONT).length;
      this.status = `选区核对${selected === document.getString().slice(start, end) ? '通过' : '失败'}：${start}～${end}，${count} 片段，${selected.length} 字符`;
      return;
    }
    const selected: RichEditorSelection = this.controller.getSelection();
    const start: number = selected.selection[0];
    const end: number = selected.selection[1];
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.controller.getSpans({ start: start, end: end });
    const text: string = spans.map((span: RichEditorImageSpanResult | RichEditorTextSpanResult) => {
      const item: RichEditorTextSpanResult = span as RichEditorTextSpanResult;
      return item.value.slice(item.offsetInSpan[0], item.offsetInSpan[1]);
    }).join('');
    const expected: string = this.exported().slice(start, end);
    this.status = `选区核对${start >= 0 && end > start && text === expected ? '通过' : '失败'}：${start}～${end}，${spans.length} 片段，${text.length} 字符`;
  }

  private deleteAcross(): void {
    const start: number = this.boundary - SELECTION_RADIUS;
    const end: number = this.boundary + SELECTION_RADIUS;
    const before: string = this.exported();
    if (this.bulk) {
      const document: MutableStyledString = this.styledController.getStyledString();
      document.removeString(start, end - start);
      this.styledController.setStyledString(document);
    } else {
      this.controller.deleteSpans({ start: start, end: end });
    }
    const after: string = this.exported();
    this.status = `跨片段删除${after === before.slice(0, start) + before.slice(end) ? '通过' : '失败'}：当前 ${after.length} 字符`;
  }

  private tail(): void {
    this.getUIContext().getFocusController().requestFocus(EDITOR_ID);
    const offset: number = this.exported().length;
    const success: boolean = this.activeController().setCaretOffset(offset);
    this.status = `尾部光标${success ? '已设置' : '设置失败'}：${offset}`;
  }

  private compare(paste: boolean): void {
    const text: string = this.exported();
    if (paste) {
      const expected: string = this.original + this.original.slice(this.boundary - SELECTION_RADIUS, this.boundary + SELECTION_RADIUS);
      this.status = `原生粘贴核对${text === expected && this.copies > 0 && this.pastes > 0 ? '通过' : '失败'}：${text.length} 字符`;
    } else {
      const count: number = this.bulk ? this.styledController.getStyledString().getStyles(0, text.length, StyledStringKey.FONT).length :
        this.controller.getSpans().length;
      this.status = `全文核对${text === this.original ? '通过' : '已修改'}：${text.length} 字符 / ${count} 片段`;
    }
  }

  private checkDeleted(): void {
    const expected: string = this.original.slice(0, this.boundary - SELECTION_RADIUS) +
      this.original.slice(this.boundary + SELECTION_RADIUS);
    const current: string = this.exported();
    this.status = `原生删除核对${current === expected ? '通过' : '失败'}：${current.length} 字符`;
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Row({ space: DemoStyle.gap }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Text('原生跨片段编辑试验').fontSize(DemoStyle.font)
      }.width('100%')
      if (TECH_DEMOS_ENABLED) {
        Row({ space: DemoStyle.gap }) {
          Button(this.length === 20000 ? '✓ 2万' : '2万').onClick(() => { this.length = 20000; this.loaded = false; })
          Button(this.length === 100000 ? '✓ 10万' : '10万').onClick(() => { this.length = 100000; this.loaded = false; })
          Button(this.paragraphs ? '多段' : '无换行').onClick(() => { this.paragraphs = !this.paragraphs; this.loaded = false; })
          Button('加载全文').enabled(this.ready).onClick(() => this.load())
        }
        Text('全量导入 RichEditor，片段交替色仅用于试验。跨片段选区后可用系统复制，尾部光标后系统粘贴。')
        Button(this.bulk ? '批量' : '逐片段').onClick(() => this.switchImport())
        Button(this.single ? '整段开' : '整段关').enabled(!this.bulk).onClick(() => {
          this.single = !this.single;
          this.sample++;
          this.loaded = false;
          this.measurement = '测量：未开始';
        })
        Row({ space: DemoStyle.gap }) {
          Button('跨片段选区').enabled(this.loaded).onClick(() => this.select(false))
          Button('全选').enabled(this.loaded).onClick(() => this.select(true))
          Button('检查选区').enabled(this.loaded).onClick(() => this.checkSelection())
          Button('跨片段删除').enabled(this.loaded).onClick(() => this.deleteAcross())
        }
        Row({ space: DemoStyle.gap }) {
          Button('尾部光标').enabled(this.loaded).onClick(() => this.tail())
          Button('全文核对').enabled(this.loaded).onClick(() => this.compare(false))
          Button('校验粘贴').enabled(this.loaded).onClick(() => this.compare(true))
          Button('校验删除').enabled(this.loaded).onClick(() => this.checkDeleted())
        }
        Row({ space: DemoStyle.gap }) {
          Button(this.keyboard ? '键盘开' : '键盘关').onClick(() => {
            this.activeController().stopEditing();
            this.keyboard = !this.keyboard;
          })
          Button('结束编辑').onClick(() => {
            this.activeController().stopEditing();
            this.getUIContext().getFocusController().clearFocus();
          })
        }
        Text(this.status).fontColor($r('app.color.text_secondary'))
        Text(this.measurement).fontColor($r('app.color.text_secondary'))
        Text(`${this.selectionLabel}；变更 ${this.changes}；复制 ${this.copies}；粘贴 ${this.pastes}`)
        if (this.bulk) {
          RichEditor({ controller: this.styledController })
            .id(EDITOR_ID).layoutWeight(1).width('100%')
            .enableKeyboardOnFocus(this.keyboard).enablePreviewText(true)
            .onReady(() => {
              this.styledController.onContentChanged({ onDidChange: () => { this.changes++; } });
              this.ready = true;
            })
            .onSelectionChange((range: RichEditorRange) => { this.selectionLabel = `选区：${range.start}～${range.end}`; })
            .onCopy(() => { this.copies++; })
            .onPaste(() => { this.pastes++; })
        } else {
          RichEditor({ controller: this.controller })
          .id(EDITOR_ID).layoutWeight(1).width('100%')
          .enableKeyboardOnFocus(this.keyboard).enablePreviewText(true)
          .onReady(() => { this.ready = true; })
          .onSelectionChange((range: RichEditorRange) => {
            this.selectionLabel = `选区：${range.start}～${range.end}`;
          })
          .onDidChange(() => { this.changes++; })
          .onCopy(() => { this.copies++; })
          .onPaste(() => { this.pastes++; })
        }
      }
    }
    .padding({ left: DemoStyle.padding, right: DemoStyle.padding,
      top: DemoStyle.padding + this.topInset, bottom: DemoStyle.padding + this.bottomInset })
    .width('100%').height('100%').backgroundColor($r('app.color.card_bg'))
  }
}
