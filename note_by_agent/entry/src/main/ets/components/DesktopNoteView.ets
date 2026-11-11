// 按卡片配色展示桌面笔记的标题与正文摘要。
const CARD_PADDING: number = 16;
const CARD_TITLE_SIZE: number = 18;
const CARD_BODY_SIZE: number = 14;

@Component
export struct DesktopNoteView {
  @Prop cardTitle: string = '笔记';
  @Prop summary: string = '';
  @Prop cardBackground: string = '#FFFFFF';
  @Prop textColor: string = '#1A1A1A';
  @Prop secondary: string = '#777777';

  build() {
    Column({ space: 8 }) {
      Text(this.cardTitle).fontSize(CARD_TITLE_SIZE).fontWeight(FontWeight.Bold)
        .fontColor(this.textColor).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(this.summary).fontSize(CARD_BODY_SIZE).fontColor(this.secondary)
        .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .layoutWeight(1)
      Text('笔记').fontSize(11).fontColor(this.secondary).width('100%')
    }
    .alignItems(HorizontalAlign.Start).padding(CARD_PADDING).width('100%').height('100%')
    .backgroundColor(this.cardBackground)
  }
}
