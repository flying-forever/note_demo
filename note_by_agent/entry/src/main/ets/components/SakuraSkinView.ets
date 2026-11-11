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
export struct SakuraSkinView {
  @State private active: boolean = false;
  @State private windowHeight: number = 800;
  private startTimer: number = -1;

  aboutToAppear(): void {
    this.startTimer = setTimeout(() => {
      this.active = true;
    }, ANIMATION_START_DELAY);
  }

  aboutToDisappear(): void {
    clearTimeout(this.startTimer);
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [['#FFF9F7', 0.0], ['#FCEFF1', 0.5], ['#FDF3F4', 1.0]]
        })

      ForEach(PETALS, (petal: PetalSpec) => {
        Stack() {
          Image($r('app.media.skin_sakura_petal'))
            .width(petal.size)
            .height(petal.size)
            .renderGroup(true)
            .animation(null)
            .rotate({ angle: this.active ? petal.sway : -petal.sway, centerX: '50%', centerY: '50%' })
            .animation({
              duration: petal.swayDuration,
              curve: Curve.EaseInOut,
              iterations: -1,
              playMode: PlayMode.Alternate
            })
        }
        .width(petal.size)
        .height(petal.size)
        .position({ x: petal.x, y: -petal.size - petal.startOffset })
        .animation(null)
        .opacity(petal.opacity)
        .translate({ y: this.active ? this.windowHeight + petal.size * 2 + petal.startOffset : 0 })
        .animation({
          duration: petal.duration,
          delay: petal.delay,
          curve: Curve.Linear,
          iterations: -1,
          playMode: PlayMode.Normal
        })
      })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.windowHeight = Number(area.height);
    })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
