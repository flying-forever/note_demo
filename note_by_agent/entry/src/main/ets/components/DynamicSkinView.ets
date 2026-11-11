import { BreezeSkinView } from './BreezeSkinView';
import { FireflySkinView } from './FireflySkinView';
import { SakuraSkinView } from './SakuraSkinView';
import { ScenicSkinView } from './ScenicSkinView';

@Component
export struct DynamicSkinView {
  @Prop effect: string = '';
  @Prop paused: boolean = false;

  build() {
    Stack() {
      if (this.effect === 'breeze') {
        BreezeSkinView({ paused: this.paused })
      } else if (this.effect === 'sakura') {
        SakuraSkinView({ paused: this.paused })
      } else if (this.effect === 'firefly') {
        FireflySkinView({ paused: this.paused })
      } else if (this.effect === 'aurora' || this.effect === 'rain' || this.effect === 'tide' ||
        this.effect === 'dawn' || this.effect === 'orbit') {
        ScenicSkinView({ effect: this.effect, paused: this.paused })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
