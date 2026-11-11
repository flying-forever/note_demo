const ANIMATION_START_DELAY: number = 100;

interface PetalSpec {
  x: string;
  size: number;
  duration: number;
  delay: number;
  sway: number;
  swayDuration: number;
  startOffset: number;
  opacity: number;
}

const PETALS: PetalSpec[] = [
  { x: '8%', size: 30, duration: 12000, delay: 0, sway: 16, swayDuration: 2800, startOffset: 0, opacity: 0.7 },
  { x: '22%', size: 22, duration: 9600, delay: 1600, sway: 12, swayDuration: 2400, startOffset: 180, opacity: 0.55 },
  { x: '36%', size: 34, duration: 15000, delay: 3200, sway: 18, swayDuration: 3400, startOffset: 60, opacity: 0.65 },
  { x: '50%', size: 26, duration: 10800, delay: 800, sway: 10, swayDuration: 2200, startOffset: 320, opacity: 0.5 },
  { x: '64%', size: 30, duration: 13200, delay: 2400, sway: 14, swayDuration: 3000, startOffset: 120, opacity: 0.6 },
  { x: '76%', size: 20, duration: 9000, delay: 4000, sway: 20, swayDuration: 2600, startOffset: 260, opacity: 0.55 },
  { x: '88%', size: 28, duration: 12600, delay: 1200, sway: 12, swayDuration: 3200, startOffset: 40, opacity: 0.68 },
  { x: '58%', size: 24, duration: 11400, delay: 5200, sway: 16, swayDuration: 2500, startOffset: 400, opacity: 0.45 }
];

@Component
struct SakuraPetalView {
  @Prop petal: PetalSpec = PETALS[0];
  @Prop windowHeight: number = 800;
  @Prop @Watch('syncMotion') paused: boolean = false;
  @State private visible: boolean = false;
  @State private falling: boolean = false;
  @State private fading: boolean = true;
  private launchTimer: number = -1;
  private landTimer: number = -1;
  private fadeTimer: number = -1;
  private resetTimer: number = -1;

  aboutToAppear(): void {
    this.visible = true;
    this.syncMotion();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.clearTimers();
    this.falling = false;
  }

  private clearTimers(): void {
    clearTimeout(this.launchTimer);
    clearTimeout(this.landTimer);
    clearTimeout(this.fadeTimer);
    clearTimeout(this.resetTimer);
    this.launchTimer = -1;
    this.landTimer = -1;
    this.fadeTimer = -1;
    this.resetTimer = -1;
  }

  private syncMotion(): void {
    this.clearTimers();
    this.falling = false;
    this.fading = true;
    if (this.visible && !this.paused) {
      this.launchTimer = setTimeout(() => this.fall(), ANIMATION_START_DELAY + this.petal.delay);
    }
  }

  private fall(): void {
    if (!this.visible || this.paused) {
      return;
    }
    this.fading = false;
    this.falling = true;
    this.landTimer = setTimeout(() => {
      this.fadeTimer = setTimeout(() => {
        this.fading = true;
        this.resetTimer = setTimeout(() => {
          this.falling = false;
          this.launchTimer = setTimeout(() => this.fall(), ANIMATION_START_DELAY);
        }, 950);
      }, 1200);
    }, this.petal.duration);
  }

  build() {
    Stack() {
      Image($r('app.media.skin_sakura_petal'))
        .width(this.petal.size).height(this.petal.size)
        .renderGroup(true)
        .animation(null)
        .rotate({ angle: this.falling ? this.petal.sway : -this.petal.sway })
        .animation(this.paused || !this.visible ? null : {
          duration: this.petal.swayDuration, curve: Curve.EaseInOut,
          iterations: -1, playMode: PlayMode.Alternate
        })
    }
    .width(this.petal.size).height(this.petal.size)
    .position({ x: this.petal.x, y: this.paused ?
      this.windowHeight * (0.1 + this.petal.startOffset / 600) : -this.petal.size - this.petal.startOffset })
    .animation(null)
    .opacity(this.paused ? this.petal.opacity * 0.35 : (this.fading ? 0 : this.petal.opacity))
    .animation(this.paused || !this.visible ? null : { duration: this.fading ? 900 : 100, curve: Curve.Linear })
    .translate({ y: this.falling ? this.windowHeight + this.petal.startOffset - 8 : 0 })
    .animation(this.paused || !this.visible || !this.falling ? null : {
      duration: this.petal.duration, curve: Curve.Linear
    })
  }
}

@Component
export struct SakuraSkinView {
  @Prop paused: boolean = false;
  @State private windowHeight: number = 800;

  build() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 160,
          colors: [['#FFF9F7', 0.0], ['#FCEFF1', 0.5], ['#FDF3F4', 1.0]]
        })
      ForEach(PETALS, (petal: PetalSpec) => {
        SakuraPetalView({ petal: petal, windowHeight: this.windowHeight, paused: this.paused })
      }, (petal: PetalSpec) => petal.x)
    }
    .width('100%').height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.windowHeight = Number(area.height);
    })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
