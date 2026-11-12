// 提供数据库实验的运行入口，并展示各项验证结果。
import { common } from '@kit.AbilityKit';
import { DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { DatabaseProbeResult, runDatabaseProbe } from '../diagnostics/DatabaseProbe';
import { SystemBars } from '../platform/SystemBars';

@Entry
@Component
struct DatabaseDemo {
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;
  @State private running: boolean = false;
  @State private lines: string[] = [];
  @State private status: string = '未运行';
  private active: boolean = true;

  aboutToAppear(): void {
    SystemBars.applyForBackground('#FFFFFF');
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  onBackPress(): boolean {
    return this.running;
  }

  private async run(verifyOnly: boolean): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.lines = [];
    this.status = '运行中';
    try {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取上下文');
      }
      await runDatabaseProbe(context, (result: DatabaseProbeResult) => {
        if (this.active) {
          this.lines = [...this.lines, `通过：${result.name}｜${result.detail}`];
        }
      }, verifyOnly);
      if (this.active) {
        this.status = verifyOnly ? '落盘复验通过' : '数据库试验全部通过';
      }
    } catch (error) {
      if (this.active) {
        this.status = `试验失败：${String(error)}`;
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
        Text('数据库与位置存储试验').fontSize(DemoStyle.font)
      }.width('100%')
      Text('仅使用 tech_demo_stage1.db。完整试验会重置该试验库，不接触正式笔记。')
      Text('第二句柄测试属于同进程竞争，不代表跨扩展或跨进程验证通过。')
        .fontColor($r('app.color.text_secondary'))
      if (TECH_DEMOS_ENABLED) {
        Row({ space: DemoStyle.gap }) {
          Button('运行完整试验').enabled(!this.running).onClick(() => { this.run(false); })
          Button('复验上次落盘').enabled(!this.running).onClick(() => { this.run(true); })
        }
      }
      Text(this.status).fontSize(DemoStyle.font)
      List({ space: DemoStyle.gap }) {
        ForEach(this.lines, (line: string) => {
          ListItem() {
            Text(line).width('100%')
          }
        }, (line: string) => line)
      }.layoutWeight(1).width('100%')
    }
    .padding({ left: DemoStyle.padding, right: DemoStyle.padding,
      top: DemoStyle.padding + this.topInset, bottom: DemoStyle.padding + this.bottomInset })
    .width('100%').height('100%').backgroundColor($r('app.color.card_bg'))
  }
}
