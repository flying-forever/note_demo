// 提供设置页的返回与标题框架，具体设置项待定。
import { SystemBars } from '../platform/SystemBars';

@Entry
@Component
struct Settings {
  @StorageProp('systemBarTopVp') private topInset: number = 0;
  @StorageProp('systemBarBottomVp') private bottomInset: number = 0;

  aboutToAppear(): void {
    SystemBars.applyForBackground('#F2F2F2');
  }

  onPageShow(): void {
    SystemBars.refreshInsets();
    SystemBars.applyForBackground('#F2F2F2');
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Row() {
          Button('←', { type: ButtonType.Normal })
            .fontSize(24)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .width(44)
            .height(44)
            .accessibilityText('返回')
            .onClick(() => this.getUIContext().getRouter().back())
          Blank()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .backgroundColor($r('app.color.page_bg'))
  }
}
