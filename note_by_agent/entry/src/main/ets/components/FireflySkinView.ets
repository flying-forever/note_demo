const ANIMATION_START_DELAY: number = 100;

interface StarSpec {
  x: string;
  y: string;
  size: number;
  duration: number;
  delay: number;
}

interface FireflySpec {
  x: string;
  y: string;
  size: number;
  driftX: number;
  driftY: number;
  duration: number;
  delay: number;
}

const STARS: StarSpec[] = [
  { x: '12%', y: '10%', size: 2, duration: 2600, delay: 0 },
  { x: '26%', y: '20%', size: 3, duration: 3400, delay: 400 },
  { x: '38%', y: '8%', size: 2, duration: 3000, delay: 900 },
  { x: '52%', y: '17%', size: 2, duration: 2200, delay: 1500 },
  { x: '66%', y: '9%', size: 3, duration: 3800, delay: 300 },
  { x: '78%', y: '22%', size: 2, duration: 2800, delay: 1100 },
  { x: '88%', y: '12%', size: 2, duration: 3200, delay: 700 },
  { x: '18%', y: '34%', size: 2, duration: 2400, delay: 1900 },
  { x: '72%', y: '38%', size: 2, duration: 3600, delay: 1300 }
];

const FIREFLIES: FireflySpec[] = [
  { x: '22%', y: '58%', size: 8, driftX: 18, driftY: -46, duration: 5200, delay: 0 },
  { x: '58%', y: '70%', size: 6, driftX: -22, driftY: -32, duration: 6400, delay: 600 },
  { x: '76%', y: '48%', size: 7, driftX: 14, driftY: 38, duration: 5800, delay: 1200 },
  { x: '38%', y: '82%', size: 5, driftX: 26, driftY: -24, duration: 4600, delay: 1800 },
  { x: '86%', y: '76%', size: 6, driftX: -18, driftY: -40, duration: 7000, delay: 900 },
  { x: '10%', y: '68%', size: 5, driftX: 22, driftY: -18, duration: 5400, delay: 2400 }
];

@Component
export struct FireflySkinView {
  @State private active: boolean = false;
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
          angle: 165,
          colors: [['#0B1424', 0.0], ['#16233D', 0.55], ['#101A2E', 1.0]]
        })

      ForEach(STARS, (star: StarSpec) => {
        Circle()
          .width(star.size)
          .height(star.size)
          .fill('#F5EFC8')
          .position({ x: star.x, y: star.y })
          .animation(null)
          .opacity(this.active ? 0.9 : 0.2)
          .animation({
            duration: star.duration,
            delay: star.delay,
            curve: Curve.EaseInOut,
            iterations: -1,
            playMode: PlayMode.Alternate
          })
      })

      ForEach(FIREFLIES, (fly: FireflySpec) => {
        Circle()
          .width(fly.size)
          .height(fly.size)
          .fill('#F6E58C')
          .shadow({ radius: fly.size * 1.8, color: '#B3F6E58C', offsetX: 0, offsetY: 0 })
          .position({ x: fly.x, y: fly.y })
          .animation(null)
          .opacity(this.active ? 0.95 : 0.25)
          .translate({ x: this.active ? fly.driftX : 0, y: this.active ? fly.driftY : 0 })
          .animation({
            duration: fly.duration,
            delay: fly.delay,
            curve: Curve.EaseInOut,
            iterations: -1,
            playMode: PlayMode.Alternate
          })
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
