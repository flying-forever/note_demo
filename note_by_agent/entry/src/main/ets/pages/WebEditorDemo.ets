// 在离线 Web 组件中对照长文编辑引擎，仅传入合成试验文字。
import { webview } from '@kit.ArkWeb';
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { fixtureText } from '../diagnostics/LongDocumentFixture';

@Entry
@Component
struct WebEditorDemo {
  @State private length: number = 20000;
  @State private paragraphs: boolean = false;
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private status: string = '等待离线编辑器。';
  private controller: webview.WebviewController = new webview.WebviewController();

  private async execute(expression: string): Promise<void> {
    this.busy = true;
    try {
      this.status = await this.controller.runJavaScript(expression);
    } catch (error) {
      this.status = `Web 实验失败：${error}`;
    } finally {
      this.busy = false;
    }
  }

  private load(): void {
    const text: string = fixtureText(this.length, this.paragraphs);
    this.execute(`window.noteProbe.load(${JSON.stringify(text)})`);
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Text('Web 长文编辑试验').fontSize(22)
      if (!TECH_DEMOS_ENABLED) {
        Text('技术实验已关闭。')
      } else {
        Row({ space: DemoStyle.gap }) {
          Button(this.length === 20000 ? '✓ 2万' : '2万').onClick(() => { this.length = 20000; })
          Button(this.length === 100000 ? '✓ 10万' : '10万').onClick(() => { this.length = 100000; })
          Button(this.paragraphs ? '多段' : '无换行').onClick(() => { this.paragraphs = !this.paragraphs; })
          Button('加载全文').enabled(this.ready && !this.busy).onClick(() => this.load())
        }
        Row({ space: DemoStyle.gap }) {
          Button('读取指标').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.snapshot()'))
          Button('全文核对').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.check()'))
          Button('编辑自检').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.editCheck()'))
          Button('全选').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.select(true)'))
        }
        Row({ space: DemoStyle.gap }) {
          Button('顶部').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.jump(0)'))
          Button('中部').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.jump(0.5)'))
          Button('尾部').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.jump(1)'))
          Button('尾部输入').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.focusTail()'))
          Button('核对采样输入').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.inputCheck("DEMOINPUT".repeat(4).slice(0, -12))'))
        }
        Row({ space: DemoStyle.gap }) {
          Button('核对注入').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.inputCheck("DEMOINPUT")'))
          Button('结束编辑').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.clearFocus()'))
          Button('开始采样').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.startPerformance()'))
          Button('结束采样').enabled(this.ready && !this.busy)
            .onClick(() => this.execute('window.noteProbe.stopPerformance()'))
        }
        Text('仅合成文字；回调时间非冷打开或完整首帧。中文输入与手指选区需人工验证。')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
        Text(this.status).id('web-probe-status').fontSize(12).maxLines(7).height(98)
        Web({ src: $rawfile('web-editor-demo/index.html'), controller: this.controller })
          .id('web-editor-probe').width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(false).fileAccess(false)
          .onPageEnd(() => {
            this.ready = true;
            this.execute('window.noteProbe.snapshot()');
          })
      }
    }.padding(DemoStyle.padding).width('100%').height('100%')
  }
}
