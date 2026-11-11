import { NOTE_SKINS, NoteSkin } from '../model/NoteSkin';

const CARD_WIDTH: number = 96;
const CARD_HEIGHT: number = 130;
const CARD_RADIUS: number = 20;
const PICKER_PADDING: number = 16;
const SELECTED_COLOR: string = '#FFC107';

@Component
export struct NoteSkinPickerView {
  @Prop selectedId: string = 'white';
  @Prop panelColor: string = '#F2F2F2';
  onSelect: (id: string) => void = () => {};

  @Builder
  Preview(skin: NoteSkin) {
    Stack() {
      if (skin.effect === 'breeze') {
        Image($r('app.media.skin_breeze_leaf')).width(60).height(80).opacity(0.28)
      } else if (skin.effect === 'sakura') {
        Image($r('app.media.skin_sakura_petal')).width(40).height(40).opacity(0.6)
      } else if (skin.effect === 'firefly') {
        Row({ space: 10 }) {
          Circle().width(5).height(5).fill('#F6E58C')
          Circle().width(8).height(8).fill('#F6E58C').opacity(0.7)
          Circle().width(4).height(4).fill('#F5EFC8')
        }
      } else if (skin.effect === 'aurora') {
        Ellipse().width(24).height(100).fill('#5584D5AB').rotate({ angle: 28 }).translate({ x: -16 })
        Ellipse().width(22).height(100).fill('#556F83C9').rotate({ angle: 36 }).translate({ x: 14 })
      } else if (skin.effect === 'rain') {
        Row({ space: 12 }) {
          ForEach([0, 1, 2, 3], (index: number) => {
            Column().width(2).height(26 + index * 6).backgroundColor('#8092ABC0')
              .borderRadius(2).rotate({ angle: 12 })
          }, (index: number) => index.toString())
        }
      } else if (skin.effect === 'tide') {
        Ellipse().width(130).height(44).fill('#5079CCC3').translate({ x: -12, y: 20 })
        Ellipse().width(130).height(40).fill('#505DBFC0').translate({ x: 14, y: 38 })
      } else if (skin.effect === 'dawn') {
        Circle().width(68).height(68).fill('#25EFB95A').stroke('#70E6AB4D').strokeWidth(1)
        Circle().width(40).height(40).fill('#50EFB95A')
      } else if (skin.effect === 'orbit') {
        Ellipse().width(78).height(46).fill(Color.Transparent).stroke('#809CA9DD')
          .strokeWidth(1).rotate({ angle: -24 })
        Circle().width(7).height(7).fill('#D7BC8C').translate({ x: 31, y: -16 })
        Circle().width(12).height(12).fill('#A9B8E6')
      } else {
        Column({ space: 8 }) {
          Column().width(40).height(3).backgroundColor(skin.secondary).borderRadius(2)
          Column().width(50).height(3).backgroundColor(skin.secondary).borderRadius(2)
          Column().width(34).height(3).backgroundColor(skin.secondary).borderRadius(2)
        }.alignItems(HorizontalAlign.Start).opacity(0.35)
      }
    }
    .width(CARD_WIDTH)
    .height(88)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }

  build() {
    Scroll() {
      Row({ space: PICKER_PADDING }) {
        ForEach(NOTE_SKINS, (skin: NoteSkin) => {
          Button({ type: ButtonType.Normal }) {
            Column() {
              this.Preview(skin)
              Text(skin.name)
                .fontSize(15)
                .fontColor(skin.text)
                .maxLines(1)
                .height(42)
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          }
          .width(CARD_WIDTH)
          .height(CARD_HEIGHT)
          .padding(0)
          .backgroundColor(skin.background)
          .borderRadius(CARD_RADIUS)
          .border({ width: 3, color: this.selectedId === skin.id ? SELECTED_COLOR : Color.Transparent })
          .clip(true)
          .accessibilityText(skin.name)
          .id('note-skin-' + skin.id)
          .onClick(() => this.onSelect(skin.id))
        }, (skin: NoteSkin) => skin.id)
      }
      .padding(PICKER_PADDING)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(162)
    .backgroundColor(this.panelColor)
  }
}
