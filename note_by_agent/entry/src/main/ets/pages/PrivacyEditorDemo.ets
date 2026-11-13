// 用隔离的临时文本验证原生输入框的光标行遮挡与按住查看交互。
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { DemoFrameProbe } from '../diagnostics/DemoFrameProbe';
import { window } from '@kit.ArkUI';

const INPUT_ID: string = 'privacy-demo-input';
const FONT_SIZE: number = 18;
const LINE_HEIGHT: number = 30;
const INSET: number = 16;
const SAMPLE: string = '今天想给自己留一点安静的时间。\n在公共场合，也可以慢慢写下自己的想法，不必把整页文字都展示出来。\n光标停在哪里，就只显示附近的一行。试着点到其他位置，或输入一段新的文字。\n这是一段较长的样例，用来观察自动换行后的显示范围。它没有依靠回车拆成很多小段，因此可以检查遮挡是否真的跟随屏幕上的视觉行。\n也试试中文拼音、选词、退格，以及跨行移动光标。\n表情与混排：今天的心情 🙂，一起去看星星 🌟。Hello, private journal!\n按住下面的按钮，可以暂时查看全文；松开后恢复遮挡。\n这些都是临时样例，离开实验页不会保存。\n最后，给明天的自己留一句话：';

@Entry
@Component
struct PrivacyEditorDemo {
  @State private text: string = SAMPLE;
  @State private previousLine: boolean = false;
  @State private paused: boolean = true;
  @State private holding: boolean = false;
  @State private focused: boolean = false;
  @State private valid: boolean = false;
  @State private top: number = 0;
  @State private bottom: number = 0;
  @State private editorHeight: number = 0;
  @State private notice: string = '点击“继续编辑”，只显示光标所在行。';
  private controller: TextAreaController = new TextAreaController();
  private mainWindow?: window.Window;
  private alive: boolean = false;
  private visible: boolean = false;
  private windowActive: boolean = false;
  private queued: boolean = false;
  private epoch: number = 0;
  private holdWidth: number = 0;
  private holdHeight: number = 0;
  private holdFinger: number = -1;
  private windowChanged = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_INACTIVE || event === window.WindowEventType.WINDOW_HIDDEN ||
      event === window.WindowEventType.WINDOW_DESTROYED) {
      this.windowActive = false;
      this.conceal();
      this.notice = '已暂停显示，点击“继续编辑”恢复。';
    } else if (event === window.WindowEventType.WINDOW_ACTIVE) {
      this.windowActive = true;
    }
  };

  aboutToAppear(): void {
    this.alive = true;
    const token: number = ++this.epoch;
    window.getLastWindow(this.getUIContext().getHostContext()).then((value: window.Window) => {
      if (!this.alive || token !== this.epoch) { return; }
      this.mainWindow = value;
      value.on('windowEvent', this.windowChanged);
      this.windowActive = value.isFocused();
    }).catch(() => { this.notice = '窗口监听不可用，本次保持全遮，请返回重试。'; });
  }

  onPageShow(): void {
    this.visible = true;
  }

  onPageHide(): void {
    this.visible = false;
    this.conceal();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.visible = false;
    this.epoch++;
    this.conceal();
    this.mainWindow?.off('windowEvent', this.windowChanged);
    this.mainWindow = undefined;
  }

  private conceal(): void {
    this.paused = true;
    this.holding = false;
    this.holdFinger = -1;
    this.valid = false;
  }

  private fullView(): boolean {
    return this.holding && this.visible && this.windowActive;
  }

  private lineView(): boolean {
    return !this.paused && this.focused && this.valid && this.visible && this.windowActive;
  }

  private refresh(): void {
    this.valid = false;
    if (this.queued || !this.alive || this.paused || !this.focused || !this.visible || !this.windowActive) { return; }
    this.queued = true;
    const token: number = this.epoch;
    this.getUIContext().postFrameCallback(new DemoFrameProbe(() => {
      this.queued = false;
      if (!this.alive || token !== this.epoch || this.paused || !this.focused ||
        !this.visible || !this.windowActive) { return; }
      try {
        const caret: CaretOffset = this.controller.getCaretOffset();
        const rect: RectResult = this.controller.getTextContentRect();
        const y: number = this.getUIContext().px2vp(caret.y);
        const origin: number = this.getUIContext().px2vp(rect.y);
        if (!Number.isFinite(y) || !Number.isFinite(origin) || this.editorHeight <= 0 ||
          y < 0 || y >= this.editorHeight) { return; }
        const row: number = Math.max(0, Math.floor((y - origin + 0.5) / LINE_HEIGHT));
        const start: number = origin + row * LINE_HEIGHT;
        this.top = Math.max(0, start - (this.previousLine ? LINE_HEIGHT : 0));
        this.bottom = Math.min(this.editorHeight, start + LINE_HEIGHT);
        this.valid = this.bottom > this.top;
      } catch (_) {
        this.notice = '暂时无法定位光标，保持遮挡。请重新点击正文。';
      }
    }));
  }

  private resume(): void {
    if (!this.windowActive) { return; }
    this.holding = false;
    this.paused = false;
    this.notice = '遮挡已开启；输入法候选词和系统选区浮层不在保护范围内。';
    this.getUIContext().getFocusController().requestFocus(INPUT_ID);
    this.refresh();
  }

  private previewTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.touches.length === 1 && this.windowActive) {
      this.holdFinger = event.touches[0].id;
      this.holding = true;
    } else if (event.type === TouchType.Move) {
      const point: TouchObject | undefined = event.touches.find((item: TouchObject) => item.id === this.holdFinger);
      if (!point || event.touches.length !== 1 || point.x < 0 || point.y < 0 ||
        point.x > this.holdWidth || point.y > this.holdHeight) {
        this.holding = false;
        this.holdFinger = -1;
      }
    } else {
      this.holding = false;
      this.holdFinger = -1;
      this.refresh();
    }
  }

  @Builder
  Editor() {
    Stack({ alignContent: Alignment.TopStart }) {
      TextArea({ text: this.text, controller: this.controller })
        .id(INPUT_ID).width('100%').height('100%')
        .fontSize(FONT_SIZE).lineHeight(LINE_HEIGHT).minFontScale(1).maxFontScale(1)
        .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_bg'))
        .padding(INSET).borderRadius(0).enablePreviewText(true)
        .selectionMenuHidden(true)
        .onEditChange((editing: boolean) => {
          this.focused = editing;
          if (editing) { this.refresh(); } else { this.conceal(); }
        })
        .onTextSelectionChange(() => this.refresh())
        .onContentScroll(() => this.refresh())
        .onChange((value: string) => { this.text = value; this.refresh(); })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.valid = false; }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.refresh(); }
        })
      if (!this.fullView()) {
        Column().width('100%').height(this.lineView() ? this.top : '100%')
          .backgroundColor($r('app.color.card_bg')).hitTestBehavior(HitTestMode.None)
        Column().width('100%').height(this.lineView() ? Math.max(0, this.editorHeight - this.bottom) : 0)
          .position({ x: 0, y: this.lineView() ? this.bottom : this.editorHeight })
          .backgroundColor($r('app.color.card_bg')).hitTestBehavior(HitTestMode.None)
        if (!this.lineView()) {
          Text(this.paused ? '内容已遮挡 · 点击继续编辑' : '正在定位光标…')
            .fontSize(14).fontColor($r('app.color.text_secondary'))
            .width('100%').height('100%').textAlign(TextAlign.Center).hitTestBehavior(HitTestMode.None)
        }
      }
    }.width('100%').layoutWeight(1).clip(true).borderRadius(12)
      .onAreaChange((_old: Area, area: Area) => {
        this.editorHeight = Number(area.height);
        this.refresh();
      })
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Row({ space: DemoStyle.gap }) {
        Button('返回').onClick(() => {
          this.conceal();
          this.getUIContext().getRouter().back();
        })
        Text('隐私编辑实验').fontSize(20).fontWeight(FontWeight.Medium)
      }.width('100%')
      if (TECH_DEMOS_ENABLED) {
        Text('临时样例 · 离页不保存 · 非加密功能').fontSize(13)
          .fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 8 }) {
          Button(this.previousLine ? '范围：当前＋上一行' : '范围：当前行')
            .fontSize(14).onClick(() => { this.previousLine = !this.previousLine; this.refresh(); })
          Button(this.paused ? '继续编辑' : '立即遮住').fontSize(14).onClick(() => {
            if (this.paused) { this.resume(); } else { this.conceal(); }
          })
        }.width('100%')
        this.Editor()
        Button(this.holding ? '松开恢复遮挡' : '按住查看全文')
          .width('100%').fontSize(16).onTouch((event: TouchEvent) => this.previewTouch(event))
          .onAreaChange((_old: Area, area: Area) => {
            this.holdWidth = Number(area.width);
            this.holdHeight = Number(area.height);
          })
        Text(this.notice).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.padding(DemoStyle.padding).width('100%').height('100%')
      .backgroundColor($r('app.color.page_bg'))
  }
}
