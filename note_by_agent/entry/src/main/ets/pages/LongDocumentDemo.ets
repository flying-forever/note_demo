// 对比长文整篇输入与分块懒加载，并验证位置跳转和文本一致性。
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { DemoChunk, DemoChunkSource, fixtureChunks, fixtureText } from '../diagnostics/LongDocumentFixture';
import { SystemBars } from '../platform/SystemBars';

@Entry
@Component
struct LongDocumentDemo {
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;
  @State private length: number = 20000;
  @State private paragraphs: boolean = true;
  @State private images: boolean = false;
  @State private lazy: boolean = true;
  @State private loaded: boolean = false;
  @State private wholeText: string = '';
  @State private selectedId: string = '';
  @State private status: string = '选择场景后加载，数据不落盘。';
  @State private visibleRange: string = '';
  @State private mounted: number = 0;
  private source: DemoChunkSource = new DemoChunkSource();
  private scroller: Scroller = new Scroller();
  private startedAt: number = 0;
  private firstVisible: boolean = false;
  private original: string = '';

  aboutToAppear(): void {
    SystemBars.applyForBackground('#FFFFFF');
  }

  private load(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.loaded = false;
    this.selectedId = '';
    this.firstVisible = false;
    this.startedAt = Date.now();
    this.original = fixtureText(this.length, this.paragraphs);
    this.wholeText = this.original;
    this.source.replace(fixtureChunks(this.original, this.images));
    this.status = `生成与分块 ${Date.now() - this.startedAt}ms；等待布局回调（非首帧耗时）`;
    this.loaded = true;
  }

  private jump(fraction: number): void {
    this.getUIContext().getFocusController().clearFocus();
    this.selectedId = '';
    const index: number = Math.floor((this.source.totalCount() - 1) * fraction);
    this.scroller.scrollToIndex(index, false, ScrollAlign.START);
    this.status = `跳转到块 ${index + 1}，不主动聚焦；块内精确定位待验证`;
  }

  private compare(): void {
    const current: string = this.lazy ? this.source.exportText() : this.wholeText;
    this.status = `当前 ${current.length} UTF-16 单元；${current === this.original ? '与原文完全一致' : '已编辑，与原文不同'}`;
  }

  @Builder
  ChunkView(chunk: DemoChunk) {
    Column() {
      if (chunk.image) {
        Text('图片占位：只测布局，未包含真实图片解码')
          .height(DemoStyle.imageHeight).width('100%')
          .backgroundColor($r('app.color.text_secondary'))
      } else if (this.selectedId === chunk.id) {
        TextArea({ text: chunk.text })
          .height(DemoStyle.editorHeight).fontSize(DemoStyle.font)
          .enablePreviewText(true)
          .onChange((value: string, preview?: PreviewText) => {
            if (preview && preview.value.length > 0) {
              return;
            }
            this.source.update(chunk.id, value);
          })
      } else {
        Text(chunk.text).fontSize(DemoStyle.font).lineHeight(DemoStyle.lineHeight)
          .width('100%').onClick(() => { this.selectedId = chunk.id; })
      }
    }.width('100%')
      .onAppear(() => { this.mounted++; })
      .onDisAppear(() => { this.mounted = Math.max(0, this.mounted - 1); })
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Row({ space: DemoStyle.gap }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Text('长笔记试验').fontSize(DemoStyle.font)
      }.width('100%')
      if (TECH_DEMOS_ENABLED) {
        Row({ space: DemoStyle.gap }) {
          Button(this.length === 20000 ? '✓ 2万' : '2万').onClick(() => { this.length = 20000; this.loaded = false; })
          Button(this.length === 100000 ? '✓ 10万' : '10万').onClick(() => { this.length = 100000; this.loaded = false; })
          Button(this.paragraphs ? '多段' : '无换行').onClick(() => { this.paragraphs = !this.paragraphs; this.loaded = false; })
        }
        Row({ space: DemoStyle.gap }) {
          Button(this.lazy ? '懒加载' : '整篇输入').onClick(() => { this.lazy = !this.lazy; this.loaded = false; })
          Button(this.images ? '含图片占位' : '纯文字').onClick(() => { this.images = !this.images; this.loaded = false; })
          Button('加载').onClick(() => this.load())
        }
        Text('临时实验；切换场景会丢弃修改。懒加载仅单块编辑，不支持跨块原生选择。').fontSize(DemoStyle.font)
        Text(this.status).fontColor($r('app.color.text_secondary'))
        if (this.loaded) {
          if (this.lazy) {
            Row({ space: DemoStyle.gap }) {
              Button('顶部').onClick(() => this.jump(0))
              Button('中部').onClick(() => this.jump(0.5))
              Button('尾部').onClick(() => this.jump(1))
            }
            Text(`${this.visibleRange}；已出现节点 ${this.mounted}`)
            List({ scroller: this.scroller }) {
              LazyForEach(this.source, (chunk: DemoChunk) => {
                ListItem() {
                  this.ChunkView(chunk)
                }
              }, (chunk: DemoChunk) => chunk.id)
            }.cachedCount(DemoStyle.cacheCount).layoutWeight(1)
              .onScrollIndex((start: number, end: number) => {
                this.visibleRange = `可见块 ${start + 1}～${end + 1}/${this.source.totalCount()}`;
                if (!this.firstVisible) {
                  this.firstVisible = true;
                  this.status = `首个可见范围回调 ${Date.now() - this.startedAt}ms（非首帧耗时）`;
                }
              })
          } else {
            TextArea({ text: this.wholeText }).layoutWeight(1).fontSize(DemoStyle.font)
              .onChange((value: string) => { this.wholeText = value; })
          }
          Row({ space: DemoStyle.gap }) {
            Button('结束单块编辑').onClick(() => {
              this.getUIContext().getFocusController().clearFocus();
              this.selectedId = '';
            })
            Button('核对全文').onClick(() => this.compare())
          }
        } else {
          Blank()
        }
      }
    }
    .padding({ left: DemoStyle.padding, right: DemoStyle.padding,
      top: DemoStyle.padding + this.topInset, bottom: DemoStyle.padding + this.bottomInset })
    .height('100%').width('100%').backgroundColor($r('app.color.card_bg'))
  }
}
