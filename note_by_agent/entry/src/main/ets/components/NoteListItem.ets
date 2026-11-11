// 按笔记皮肤以单列行展示标题、摘要与时间。
import { findSkin } from '../model/NoteSkin';

@Component
export struct NoteListItem {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop timeLabel: string = '';
  @Prop skinId: string = 'white';

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(findSkin(this.skinId).text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.timeLabel)
          .fontSize(11)
          .fontColor(findSkin(this.skinId).secondary)
          .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.summary)
        .fontSize(13)
        .fontColor(findSkin(this.skinId).secondary)
        .lineHeight(19)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .constraintSize({ minHeight: 96 })
    .width('100%')
    .backgroundColor(findSkin(this.skinId).background)
    .borderRadius(12)
  }
}
