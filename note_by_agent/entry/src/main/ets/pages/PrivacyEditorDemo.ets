// 用临时文本对比光标周围与按行显示，并用无字形短条提示隐藏内容。
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { DemoFrameProbe } from '../diagnostics/DemoFrameProbe';
import { SystemBars } from '../platform/SystemBars';
import { window } from '@kit.ArkUI';

const INPUT_ID: string = 'privacy-demo-input';
const FONT_SIZE: number = 18;
const LINE_HEIGHT: number = 30;
const INSET: number = 16;
const REVEAL_HALF_WIDTH: number = 96;
const PLACEHOLDER_HEIGHT: number = 7;
const PLACEHOLDER_STEP: number = 28;
const SAMPLE: string = '今天想给自己留一点安静的时间。\n在公共场合，也可以慢慢写下自己的想法，不必把整页文字都展示出来。\n光标停在哪里，就只显示附近的一行。试着点到其他位置，或输入一段新的文字。\n这是一段较长的样例，用来观察自动换行后的显示范围。它没有依靠回车拆成很多小段，因此可以检查遮挡是否真的跟随屏幕上的视觉行。\n也试试中文拼音、选词、退格，以及跨行移动光标。\n表情与混排：今天的心情 🙂，一起去看星星 🌟。Hello, private journal!\n按住下面的按钮，可以暂时查看全文；松开后恢复遮挡。\n这些都是临时样例，离开实验页不会保存。\n最后，给明天的自己留一句话：';

@Entry
@Component
struct PrivacyEditorDemo {
  @State private text: string = SAMPLE;
  @State private cursorMode: boolean = true;
  @State private previousLine: boolean = false;
  @State private paused: boolean = true;
  @State private holding: boolean = false;
  @State private focused: boolean = false;
  @State private valid: boolean = false;
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;
  private top: number = 0;
  private bottom: number = 0;
  private editorHeight: number = 0;
  private editorWidth: number = 0;
  @State private maskReady: boolean = false;
  @State private notice: string = '点击“继续编辑”，显示光标附近；浅灰短条仅提示内容存在。';
  private maskContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasAttached: boolean = false;
  private caretX: number = 0;
  private caretY: number = 0;
  private controller: TextAreaController = new TextAreaController();
  private mainWindow?: window.Window;
  private alive: boolean = false;
  private visible: boolean = false;
  private windowActive: boolean = false;
  private queued: boolean = false;
  private scrollX: number = 0;
  private scrollY: number = 0;
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
    SystemBars.applyForBackground('#F2F2F2');
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
    SystemBars.refreshInsets();
    SystemBars.applyForBackground('#F2F2F2');
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
    this.drawMask();
  }

  private fullView(): boolean {
    return this.holding && this.visible && this.windowActive;
  }

  private lineView(): boolean {
    return !this.paused && this.focused && this.valid && this.visible && this.windowActive;
  }

  private refresh(invalidate: boolean = false): void {
    if (invalidate) {
      this.valid = false;
      this.drawMask();
    }
    if (this.queued || !this.alive || !this.visible) { return; }
    this.queued = true;
    const token: number = this.epoch;
    this.getUIContext().postFrameCallback(new DemoFrameProbe(() => {
      this.queued = false;
      if (!this.alive || token !== this.epoch || !this.visible) { return; }
      if (this.paused || !this.focused || !this.windowActive) {
        this.drawMask();
        return;
      }
      try {
        const caret: CaretOffset = this.controller.getCaretOffset();
        const rect: RectResult = this.controller.getTextContentRect();
        const y: number = this.getUIContext().px2vp(caret.y);
        const origin: number = this.getUIContext().px2vp(rect.y);
        if (!Number.isFinite(y) || !Number.isFinite(origin) || !Number.isFinite(caret.x) ||
          this.editorHeight <= 0 || y < 0 || y >= this.editorHeight) {
          this.valid = false;
          this.drawMask();
          return;
        }
        const row: number = Math.max(0, Math.floor((y - origin + 0.5) / LINE_HEIGHT));
        const start: number = origin + row * LINE_HEIGHT;
        this.top = Math.max(0, start - (this.previousLine ? LINE_HEIGHT : 0));
        this.bottom = Math.min(this.editorHeight, start + LINE_HEIGHT);
        this.caretX = this.getUIContext().px2vp(caret.x);
        this.caretY = start + LINE_HEIGHT / 2;
        this.valid = this.bottom > this.top;
        this.drawMask();
      } catch (_) {
        this.valid = false;
        this.drawMask();
        this.notice = '暂时无法定位光标，保持遮挡。请重新点击正文。';
      }
    }));
  }

  private drawMask(): void {
    if (!this.canvasAttached) { return; }
    try {
      const resources = this.getUIContext().getHostContext()!.resourceManager;
      const width: number = this.maskContext.width;
      const height: number = this.maskContext.height;
      if (width <= 0 || height <= 0 || Math.abs(width - this.editorWidth) > 1 ||
        Math.abs(height - this.editorHeight) > 1) {
        this.maskReady = false;
        return;
      }
      this.maskContext.globalCompositeOperation = 'source-over';
      this.maskContext.fillStyle = resources.getColorSync($r('app.color.card_bg'));
      this.maskContext.fillRect(0, 0, width, height);
      if (this.text.trim().length > 0) {
        const rect: RectResult = this.controller.getTextContentRect();
        const left: number = this.getUIContext().px2vp(rect.x);
        const origin: number = this.getUIContext().px2vp(rect.y);
        const right: number = Math.min(width - INSET, left + this.getUIContext().px2vp(rect.width));
        const count: number = this.controller.getTextContentLineCount();
        const first: number = Math.max(0, Math.floor(-origin / LINE_HEIGHT));
        const last: number = Math.min(count, Math.ceil((height - origin) / LINE_HEIGHT));
        this.maskContext.fillStyle = resources.getColorSync($r('app.color.privacy_placeholder'));
        for (let row: number = first; row < last; row++) {
          for (let x: number = left; x < right; x += PLACEHOLDER_STEP) {
            this.maskContext.fillRect(x, origin + row * LINE_HEIGHT + (LINE_HEIGHT - PLACEHOLDER_HEIGHT) / 2,
              Math.min(PLACEHOLDER_STEP - 8, right - x), PLACEHOLDER_HEIGHT);
          }
        }
      }
      if (this.fullView()) {
        this.maskContext.clearRect(0, 0, width, height);
      } else if (this.lineView()) {
        if (this.cursorMode) {
          const left: number = Math.max(0, this.caretX - REVEAL_HALF_WIDTH);
          const right: number = Math.min(width, this.caretX + REVEAL_HALF_WIDTH);
          const top: number = Math.max(0, this.caretY - LINE_HEIGHT / 2);
          const bottom: number = Math.min(height, this.caretY + LINE_HEIGHT / 2);
          this.maskContext.clearRect(left, top, Math.max(0, right - left), Math.max(0, bottom - top));
        } else {
          this.maskContext.clearRect(0, this.top, width, this.bottom - this.top);
        }
      }
      this.maskReady = true;
    } catch (_) {
      this.valid = false;
      this.maskReady = false;
    }
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
    this.drawMask();
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
        .onContentScroll((x: number, y: number) => {
          if (Math.abs(x - this.scrollX) < 0.5 && Math.abs(y - this.scrollY) < 0.5) { return; }
          this.scrollX = x;
          this.scrollY = y;
          this.refresh(true);
        })
        .onChange((value: string) => { this.text = value; this.refresh(); })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.valid = false; this.drawMask(); }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.refresh(); }
        })
      Canvas(this.maskContext).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        .onReady(() => { this.canvasAttached = true; this.drawMask(); })
      if (!this.maskReady) {
        Column().width('100%').height('100%')
          .backgroundColor($r('app.color.card_bg')).hitTestBehavior(HitTestMode.None)
      }
      if (!this.fullView() && this.paused) {
        Text('内容已遮挡 · 点击继续编辑')
          .fontSize(14).fontColor($r('app.color.text_secondary'))
          .width('100%').height('100%').textAlign(TextAlign.Center).hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').layoutWeight(1).clip(true).borderRadius(12)
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = Number(area.width);
        const height: number = Number(area.height);
        if (Math.abs(width - this.editorWidth) < 0.5 && Math.abs(height - this.editorHeight) < 0.5) { return; }
        this.maskReady = false;
        this.editorWidth = width;
        this.editorHeight = height;
        this.refresh(true);
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
          Button(this.cursorMode ? '✓ 光标周围' : '光标周围').fontSize(14).onClick(() => {
            this.cursorMode = true;
            this.refresh(true);
          })
          Button(!this.cursorMode ? '✓ 按行显示' : '按行显示').fontSize(14).onClick(() => {
            this.cursorMode = false;
            this.refresh(true);
          })
        }.width('100%')
        Row({ space: 8 }) {
          if (!this.cursorMode) {
            Button(this.previousLine ? '范围：当前＋上一行' : '范围：当前行')
              .fontSize(14).onClick(() => { this.previousLine = !this.previousLine; this.refresh(true); })
          } else {
            Text('矩形窗口 · 光标附近可见').fontSize(14).fontColor($r('app.color.text_secondary'))
          }
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
    }.padding({
      top: DemoStyle.padding + this.topInset,
      bottom: DemoStyle.padding + this.bottomInset,
      left: DemoStyle.padding,
      right: DemoStyle.padding
    }).width('100%').height('100%')
      .backgroundColor($r('app.color.page_bg'))
  }
}
