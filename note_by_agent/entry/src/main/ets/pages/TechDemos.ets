// 展示已注册的技术实验项目，并导航到对应实验页面。
import { DEMO_CATALOG, DemoEntry, DemoStyle, TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { SystemBars } from '../platform/SystemBars';

@Entry
@Component
struct TechDemos {
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;

  aboutToAppear(): void {
    SystemBars.applyForBackground('#FFFFFF');
  }

  build() {
    Column({ space: DemoStyle.gap }) {
      Row() {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Text('技术实验室').fontSize(DemoStyle.font)
      }.width('100%')
      Text('独立试验数据，不读写正式笔记。新增实验在 DemoCatalog 注册，并登记页面路由。')
        .fontColor($r('app.color.text_secondary'))
      if (TECH_DEMOS_ENABLED) {
        List({ space: DemoStyle.gap }) {
          ForEach(DEMO_CATALOG, (demo: DemoEntry) => {
            ListItem() {
              Column({ space: DemoStyle.gap }) {
                Text(demo.title).fontSize(DemoStyle.font)
                Text(demo.description).fontColor($r('app.color.text_secondary'))
                Button('打开实验').onClick(() => {
                  this.getUIContext().getRouter().pushUrl({ url: demo.route })
                    .catch(() => this.getUIContext().getPromptAction().showToast({ message: '无法打开实验页' }));
                })
              }.alignItems(HorizontalAlign.Start).padding(DemoStyle.padding)
            }
          }, (demo: DemoEntry) => demo.id)
        }.layoutWeight(1)
      }
    }
    .padding({ left: DemoStyle.padding, right: DemoStyle.padding,
      top: DemoStyle.padding + this.topInset, bottom: DemoStyle.padding + this.bottomInset })
    .width('100%').height('100%').backgroundColor($r('app.color.card_bg'))
  }
}
