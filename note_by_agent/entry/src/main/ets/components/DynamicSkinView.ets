import { BreezeSkinView } from './BreezeSkinView';
import { FireflySkinView } from './FireflySkinView';
import { SakuraSkinView } from './SakuraSkinView';

@Component
export struct DynamicSkinView {
  @Prop effect: string = '';

  build() {
    Stack() {
      if (this.effect === 'breeze') {
        BreezeSkinView()
      } else if (this.effect === 'sakura') {
        SakuraSkinView()
      } else if (this.effect === 'firefly') {
        FireflySkinView()
      }
    }
    .width('100%')
    .height('100%')
  }
}
