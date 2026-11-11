const PANEL_PADDING: number = 16;
const PANEL_RADIUS: number = 20;

@Component
export struct NoteCaptionEditorView {
  @Prop initialText: string = '';
  @Prop panelColor: string = '#F2F2F2';
  @Prop textColor: string = '#1A1A1A';
  @Prop inputColor: string = '#FFFFFF';
  @State private draft: string = '';
  onCancel: () => void = () => {};
  onConfirm: (value: string) => void = () => {};

  aboutToAppear(): void {
    this.draft = this.initialText;
  }

  build() {
    Column() {
      Column({ space: PANEL_PADDING }) {
        Text('图片描述')
          .fontSize(16)
          .fontColor(this.textColor)
          .width('100%')
        TextArea({ text: this.draft, placeholder: '输入图片描述' })
          .height(120)
          .fontSize(16)
          .fontColor(this.textColor)
          .placeholderColor(this.textColor)
          .backgroundColor(this.inputColor)
          .borderRadius(12)
          .padding(12)
          .onChange((value: string) => { this.draft = value; })
        Row() {
          Button('取消')
            .height(40)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .onClick(() => this.onCancel())
          Blank()
          Button('完成')
            .height(40)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .onClick(() => this.onConfirm(this.draft))
        }
        .width('100%')
      }
      .padding(PANEL_PADDING)
      .width('88%')
      .constraintSize({ maxWidth: 420 })
      .borderRadius(PANEL_RADIUS)
      .backgroundColor(this.panelColor)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
  }
}
