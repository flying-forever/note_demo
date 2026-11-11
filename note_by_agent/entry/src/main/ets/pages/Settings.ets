// 提供设置页的返回与标题框架，具体设置项待定。
@Entry
@Component
struct Settings {
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
    .backgroundColor($r('app.color.page_bg'))
  }
}
