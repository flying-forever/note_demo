// 绘制极光、雨滴、潮汐、晨光与星轨等可暂停的动态背景。
const START_DELAY: number = 100;

@Component
export struct ScenicSkinView {
  @Prop @Watch('syncMotion') effect: string = '';
  @Prop @Watch('syncMotion') paused: boolean = false;
  @State private active: boolean = false;
  @State private visible: boolean = false;
  @State private sceneWidth: number = 360;
  @State private sceneHeight: number = 800;
  private startTimer: number = -1;
  private readonly layers: number[] = [0, 1, 2];
  private readonly drops: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

  aboutToAppear(): void {
    this.visible = true;
    this.syncMotion();
  }

  aboutToDisappear(): void {
    this.visible = false;
    clearTimeout(this.startTimer);
    this.startTimer = -1;
    this.active = false;
  }

  private syncMotion(): void {
    clearTimeout(this.startTimer);
    this.startTimer = -1;
    this.active = false;
    if (this.visible && !this.paused) {
      this.startTimer = setTimeout(() => {
        this.startTimer = -1;
        this.active = true;
      }, START_DELAY);
    }
  }

  @Builder
  aurora() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 150, colors: [['#111A2B', 0], ['#232340', 0.6], ['#171B35', 1]] })
    ForEach(this.layers, (index: number) => {
      Ellipse()
        .width(this.sceneWidth * 0.85).height(this.sceneHeight * 0.86)
        .fill(index === 0 ? '#143CD6AD' : (index === 1 ? '#1C6A9CCB' : '#207D62B5'))
        .position({ x: this.sceneWidth * (0.12 + index * 0.23), y: -this.sceneHeight * 0.27 })
        .rotate({ angle: 26 + index * 12 })
        .animation(null)
        .translate({ x: this.active ? -24 - index * 9 : 8, y: this.active ? 25 : -10 })
        .opacity(this.active ? 0.95 : 0.45)
        .animation(this.paused || !this.visible ? null : {
          duration: 7600 + index * 1900, curve: Curve.EaseInOut,
          iterations: -1, playMode: PlayMode.Alternate
        })
    }, (index: number) => `aurora-${index}`)
  }

  @Builder
  rain() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 180, colors: [['#DCE6EF', 0], ['#F2F5F7', 0.6], ['#E9EFF4', 1]] })
    ForEach(this.drops, (index: number) => {
      Column()
        .width(index % 3 === 0 ? 2 : 1).height(26 + index % 4 * 12)
        .backgroundColor('#496D8CA3')
        .borderRadius(2)
        .position({ x: this.sceneWidth * (0.04 + index * 0.082), y: -80 - index % 4 * 70 })
        .rotate({ angle: 12 })
        .opacity(this.paused ? 0.16 : 0.55)
        .animation(null)
        .translate({ x: this.active ? -this.sceneHeight * 0.16 : 0,
          y: this.paused ? this.sceneHeight * (0.2 + index % 5 * 0.16) :
            (this.active ? this.sceneHeight + 440 : 0) })
        .animation(this.paused || !this.visible ? null : {
          duration: 3200 + index % 4 * 700, delay: index * 330,
          curve: Curve.Linear, iterations: -1, playMode: PlayMode.Normal
        })
    }, (index: number) => `rain-${index}`)
  }

  @Builder
  tide() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 180, colors: [['#F1FAF8', 0], ['#E8F6F4', 0.62], ['#D5EEEC', 1]] })
    ForEach(this.layers, (index: number) => {
      Ellipse()
        .width(this.sceneWidth * (1.7 + index * 0.12)).height(this.sceneHeight * 0.36)
        .fill(index === 0 ? '#203BA6AB' : (index === 1 ? '#255DBFC0' : '#3879CCC3'))
        .position({ x: -this.sceneWidth * (0.5 - index * 0.05),
          y: this.sceneHeight * (0.79 + index * 0.075) })
        .animation(null)
        .translate({ x: this.active ? 28 - index * 24 : -18 + index * 12,
          y: this.active ? -12 - index * 3 : 4 })
        .animation(this.paused || !this.visible ? null : {
          duration: 5400 + index * 1600, curve: Curve.EaseInOut,
          iterations: -1, playMode: PlayMode.Alternate
        })
    }, (index: number) => `tide-${index}`)
  }

  @Builder
  dawn() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 145, colors: [['#FFF7E9', 0], ['#FFF1DD', 0.65], ['#F8E4CF', 1]] })
    ForEach(this.layers, (index: number) => {
      Circle()
        .width(this.sceneWidth * (0.55 + index * 0.3))
        .height(this.sceneWidth * (0.55 + index * 0.3))
        .fill(index === 0 ? '#28EFB95A' : '#0AE6A53D')
        .stroke('#1CE6AB4D').strokeWidth(1)
        .position({ x: this.sceneWidth * (0.67 - index * 0.15),
          y: this.sceneHeight * 0.09 - this.sceneWidth * index * 0.15 })
        .animation(null)
        .opacity(this.active ? 0.85 : 0.4)
        .scale({ x: this.active ? 1.07 : 0.96, y: this.active ? 1.07 : 0.96 })
        .animation(this.paused || !this.visible ? null : {
          duration: 6000 + index * 1500, curve: Curve.EaseInOut,
          iterations: -1, playMode: PlayMode.Alternate
        })
    }, (index: number) => `dawn-${index}`)
  }

  @Builder
  orbit() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 160, colors: [['#1E2440', 0], ['#171B2C', 0.58], ['#20253C', 1]] })
    ForEach(this.layers, (index: number) => {
      Stack({ alignContent: Alignment.Top }) {
        Circle()
          .width('100%').height('100%')
          .fill(Color.Transparent).stroke('#289CA9DD').strokeWidth(1)
        Circle()
          .width(5 + index * 2).height(5 + index * 2)
          .fill(index === 1 ? '#D7BC8C' : '#A9B8E6')
          .opacity(0.65)
      }
      .width(this.sceneWidth * (0.64 + index * 0.32))
      .height(this.sceneWidth * (0.64 + index * 0.32))
      .position({ x: this.sceneWidth * (0.67 - index * 0.16),
        y: this.sceneHeight * 0.72 - this.sceneWidth * index * 0.16 })
      .animation(null)
      .rotate({ angle: this.active ? 360 + index * 90 : index * 90 })
      .animation(this.paused || !this.visible ? null : {
        duration: 26000 + index * 11000, curve: Curve.Linear,
        iterations: -1, playMode: PlayMode.Normal
      })
    }, (index: number) => `orbit-${index}`)
  }

  build() {
    Stack() {
      if (this.effect === 'aurora') {
        this.aurora()
      } else if (this.effect === 'rain') {
        this.rain()
      } else if (this.effect === 'tide') {
        this.tide()
      } else if (this.effect === 'dawn') {
        this.dawn()
      } else if (this.effect === 'orbit') {
        this.orbit()
      }
    }
    .width('100%').height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.sceneWidth = Number(area.width);
      this.sceneHeight = Number(area.height);
    })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
