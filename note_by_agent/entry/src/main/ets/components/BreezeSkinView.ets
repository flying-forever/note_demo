// 绘制随窗口缩放的树叶背景，并控制微风摇摆动画的启停。
const LEAF_ASPECT: number = 4 / 3;
const LEAF_WINDOW_RATIO: number = 0.48;
const LEAF_HEIGHT_LIMIT: number = 0.62;
const SWAY_DURATION: number = 4200;
const ANIMATION_START_DELAY: number = 100;

@Component
export struct BreezeSkinView {
  @Prop @Watch('syncMotion') paused: boolean = false;
  @State private visible: boolean = false;
  @State private swaying: boolean = false;
  @State private leafWidth: number = 170;
  @State private windowWidth: number = 0;
  @State private windowHeight: number = 0;
  private startTimer: number = -1;

  aboutToAppear(): void {
    this.visible = true;
    this.syncMotion();
  }

  aboutToDisappear(): void {
    this.visible = false;
    clearTimeout(this.startTimer);
    this.startTimer = -1;
    this.swaying = false;
  }

  private syncMotion(): void {
    clearTimeout(this.startTimer);
    this.startTimer = -1;
    this.swaying = false;
    if (this.visible && !this.paused) {
      this.startTimer = setTimeout(() => {
        this.startTimer = -1;
        this.swaying = true;
      }, ANIMATION_START_DELAY);
    }
  }

  build() {
    Stack() {
      Image($r('app.media.skin_breeze_leaf'))
        .width(this.leafWidth).height(this.leafWidth * LEAF_ASPECT)
        .renderGroup(true)
        .opacity(0.16)
        .position({ x: this.windowWidth - this.leafWidth * 0.8, y: -this.leafWidth * 0.17 })
        .animation(null)
        .rotate({ angle: this.swaying ? 12 : -8, centerX: '50%', centerY: '100%' })
        .animation(this.paused || !this.visible ? null : { duration: SWAY_DURATION, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })
      Image($r('app.media.skin_breeze_leaf'))
        .width(this.leafWidth).height(this.leafWidth * LEAF_ASPECT)
        .renderGroup(true)
        .opacity(0.12)
        .position({ x: -this.leafWidth * 0.26, y: this.windowHeight - this.leafWidth * (LEAF_ASPECT - 0.2) })
        .animation(null)
        .rotate({ angle: this.swaying ? -16 : 4, centerX: '50%', centerY: '100%' })
        .animation(this.paused || !this.visible ? null : { duration: SWAY_DURATION + 1400, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })
    }
    .width('100%').height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.windowWidth = Number(area.width);
      this.windowHeight = Number(area.height);
      this.leafWidth = Math.min(Number(area.width) * LEAF_WINDOW_RATIO,
        Number(area.height) * LEAF_HEIGHT_LIMIT / LEAF_ASPECT);
    })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
