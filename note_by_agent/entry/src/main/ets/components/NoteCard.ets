import { findSkin } from '../model/NoteSkin';

@Component
export struct NoteCard {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop timeLabel: string = '';
  @Prop skinId: string = 'white';

  build() {
    Column() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(findSkin(this.skinId).text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.summary)
          .fontSize(13)
          .fontColor(findSkin(this.skinId).secondary)
          .lineHeight(19)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Text(this.timeLabel)
        .fontSize(11)
        .fontColor(findSkin(this.skinId).secondary)
        .width('100%')
        .margin({ top: 12 })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(14)
    .constraintSize({ minHeight: 150 })
    .width('100%')
    .backgroundColor(findSkin(this.skinId).background)
    .borderRadius(12)
  }
}
