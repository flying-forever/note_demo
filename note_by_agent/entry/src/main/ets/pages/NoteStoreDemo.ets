// 提供正式笔记库的自检入口，并展示计数、迁移与读写结果。
import { DemoStyle } from '../diagnostics/DemoCatalog';
import { runNoteStoreChecks, StoreCheckResult } from '../diagnostics/NoteStoreProbe';

@Entry
@Component
struct NoteStoreDemo {
  @State private running: boolean = false;
  @State private lines: string[] = [];
  @State private status: string = '未运行';
  private active: boolean = true;

  aboutToDisappear(): void {
    this.active = false;
  }

  onBackPress(): boolean {
    return this.running;
  }

  private async run(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.lines = [];
    this.status = '运行中';
    try {
      await runNoteStoreChecks((result: StoreCheckResult) => {
        if (this.active) {
          this.lines = [...this.lines, `通过：${result.name}｜${result.detail}`];
        }
      });
      if (this.active) {
        this.status = '自检通过';
      }
    } catch (error) {
      if (this.active) {
        this.status = `自检失败：${String(error)}`;
      }
    } finally {
      if (this.active) {
        this.running = false;
      }
    }
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Row({ space: DemoStyle.gap }) {
        Button('返回').enabled(!this.running).onClick(() => this.getUIContext().getRouter().back())
        Text('笔记库自检').fontSize(DemoStyle.font)
      }.width('100%')
      Text('读取正式笔记库，写入并清理一条临时笔记；不修改现有笔记内容。')
        .fontColor($r('app.color.text_secondary'))
      Button('运行自检').enabled(!this.running).onClick(() => { this.run(); })
      Text(this.status).fontSize(DemoStyle.font)
      List({ space: DemoStyle.gap }) {
        ForEach(this.lines, (line: string) => {
          ListItem() {
            Text(line).width('100%')
          }
        }, (line: string) => line)
      }.layoutWeight(1).width('100%')
    }.padding(DemoStyle.padding).width('100%').height('100%')
  }
}
