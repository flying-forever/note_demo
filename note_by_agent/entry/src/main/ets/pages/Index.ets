import { NoteCard } from '../components/NoteCard';
import { FAKE_NOTES, GROUP_ALL, NOTE_GROUPS, Note } from '../model/Note';

const LARGE_TITLE_FONT_SIZE: number = 44;
const HEADER_SLOT_HEIGHT: number = 56;
const GROUP_BAR_HEIGHT: number = 44;
const COLLAPSE_DISTANCE: number = HEADER_SLOT_HEIGHT;
const SEARCH_PULL_THRESHOLD: number = 30;
const SEARCH_PULL_MAX: number = 60;
const SEARCH_ROW_HEIGHT: number = 56;
const SEARCH_ANIMATION_DURATION: number = 180;

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedGroup: string = GROUP_ALL;
  @State searchProgress: number = 0;
  @State searchExpanded: boolean = false;
  @State pullDistance: number = 0;
  @State collapseProgress: number = 0;

  private searchAnimating: boolean = false;
  private touchingList: boolean = false;

  private scroller: Scroller = new Scroller();

  private notes(): Note[] {
    if (this.selectedGroup === GROUP_ALL) {
      return FAKE_NOTES;
    }
    return FAKE_NOTES.filter((item: Note) => item.group === this.selectedGroup);
  }

  private estimateHeight(note: Note): number {
    const titleLines: number = Math.min(2, Math.ceil(note.title.length / 9));
    const summaryLines: number = Math.min(4, Math.ceil(note.summary.length / 10));
    return titleLines * 22 + summaryLines * 19 + 56;
  }

  private notesForColumn(column: number): Note[] {
    const left: Note[] = [];
    const right: Note[] = [];
    let leftHeight: number = 0;
    let rightHeight: number = 0;
    this.notes().forEach((note: Note) => {
      const height: number = this.estimateHeight(note);
      if (leftHeight <= rightHeight) {
        left.push(note);
        leftHeight += height;
      } else {
        right.push(note);
        rightHeight += height;
      }
    });
    return column === 0 ? left : right;
  }

  private hideSearch(): void {
    this.searchExpanded = false;
    this.pullDistance = 0;
    this.searchAnimating = true;
    this.getUIContext().animateTo({
      duration: SEARCH_ANIMATION_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.searchAnimating = false;
      }
    }, () => {
      this.searchProgress = 0;
    });
  }

  private expandSearch(): void {
    this.searchExpanded = true;
    this.pullDistance = 0;
    this.collapseProgress = 0;
    this.searchAnimating = true;
    this.getUIContext().animateTo({
      duration: SEARCH_ANIMATION_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.searchAnimating = false;
      }
    }, () => {
      this.searchProgress = 1;
    });
  }

  private switchTab(tab: number): void {
    if (this.currentTab === tab) {
      return;
    }
    this.hideSearch();
    this.collapseProgress = 0;
    this.currentTab = tab;
  }

  private onListScroll(deltaY: number, scrollState: ScrollState): void {
    if (this.currentTab !== 0) {
      return;
    }
    const offset: number = this.scroller.currentOffset().yOffset;
    const atTop: boolean = offset <= 0.5;

    if (this.searchExpanded || this.searchAnimating) {
      return;
    }

    this.collapseProgress = Math.min(1, Math.max(0, offset / COLLAPSE_DISTANCE));

    if (atTop && deltaY < 0 && this.touchingList && scrollState === ScrollState.Scroll) {
      this.pullDistance = Math.min(SEARCH_PULL_MAX, this.pullDistance - deltaY);
      if (this.pullDistance >= SEARCH_PULL_THRESHOLD) {
        this.expandSearch();
      }
      return;
    }

    if (deltaY > 0 || scrollState === ScrollState.Idle) {
      this.pullDistance = 0;
    }
  }

  @Builder
  TabSwitcher(large: boolean) {
    Row({ space: 20 }) {
      ForEach(['笔记', '待办'], (title: string, index: number) => {
        Text(title)
          .fontSize(large ? (this.currentTab === index ? LARGE_TITLE_FONT_SIZE : 34) :
            (this.currentTab === index ? 22 : 17))
          .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .maxLines(1)
          .onClick(() => {
            this.switchTab(index);
          })
      }, (title: string) => title)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  TopBar() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Blank()
        Image($r('app.media.ic_settings'))
          .width(22)
          .height(22)
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({ message: '设置页待实现' });
          })
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Row() {
        this.TabSwitcher(false)
      }
      .opacity(this.collapseProgress)
      .visibility(this.collapseProgress > 0 ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
  }

  @Builder
  SearchBar() {
    Row() {
      Image($r('app.media.ic_search'))
        .width(16)
        .height(16)
      TextInput({ placeholder: '搜索笔记' })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .placeholderFont({ size: 14 })
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .height(40)
        .padding({ left: 8, right: 12 })
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .opacity(this.searchProgress)
    .hitTestBehavior(this.searchProgress > 0 ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  HeaderSlot() {
    Stack({ alignContent: Alignment.Start }) {
      Row() {
        this.TabSwitcher(true)
      }
      .opacity(1 - this.collapseProgress)
      .visibility(this.collapseProgress < 1 ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .height(HEADER_SLOT_HEIGHT * (1 - this.collapseProgress))
    .padding({ left: 16, right: 16 })
    .clip(true)
  }

  @Builder
  SearchRow() {
    Column() {
      this.SearchBar()
    }
    .width('100%')
    .height(SEARCH_ROW_HEIGHT * this.searchProgress)
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Center)
    .clip(true)
  }

  @Builder
  GroupBar() {
    Row() {
      List({ space: 20 }) {
        ForEach(NOTE_GROUPS, (group: string) => {
          ListItem() {
            Row() {
              Text(group)
                .fontSize(15)
                .fontWeight(this.selectedGroup === group ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.selectedGroup === group ? $r('app.color.accent') : $r('app.color.text_secondary'))
                .onClick(() => {
                  if (this.selectedGroup === group) {
                    return;
                  }
                  this.selectedGroup = group;
                  this.collapseProgress = 0;
                  if (this.notes().length > 0) {
                    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
                  }
                })
            }
            .height('100%')
            .alignItems(VerticalAlign.Center)
          }
        }, (group: string) => group)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height(GROUP_BAR_HEIGHT)
      .padding({ left: 16 })

      Row() {
        Divider()
          .vertical(true)
          .height(16)
          .color($r('app.color.divider'))
          .margin({ right: 12 })
        Image($r('app.media.ic_folder'))
          .width(20)
          .height(20)
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ right: 16 })
      .onClick(() => {
        this.getUIContext().getPromptAction().showToast({ message: '分组管理页待实现' });
      })
    }
    .width('100%')
    .height(GROUP_BAR_HEIGHT)
  }

  @Builder
  NoteItem(item: Note) {
    Column() {
      NoteCard({
        title: item.title,
        summary: item.summary,
        timeLabel: item.timeLabel
      })
    }
    .width('100%')
    .onClick(() => {
      this.getUIContext().getPromptAction().showToast({ message: '编辑页待实现' });
    })
  }

  @Builder
  EmptyView() {
    Column() {
      Text('还没有笔记')
        .fontSize(15)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  TodoView() {
    Column() {
      Text('待办页面待实现')
        .fontSize(15)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  NoteList() {
    Scroll(this.scroller) {
      Column() {
        Row({ space: 12 }) {
          Column({ space: 12 }) {
            ForEach(this.notesForColumn(0), (item: Note) => {
              this.NoteItem(item)
            }, (item: Note) => item.id)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 12 }) {
            ForEach(this.notesForColumn(1), (item: Note) => {
              this.NoteItem(item)
            }, (item: Note) => item.id)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 16, right: 16, top: 4, bottom: 96 })
      }
      .width('100%')
      .padding({ top: HEADER_SLOT_HEIGHT + GROUP_BAR_HEIGHT + SEARCH_ROW_HEIGHT * this.searchProgress })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.touchingList = true;
        this.pullDistance = 0;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touchingList = false;
        this.pullDistance = 0;
      }
    })
    .onWillScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
      if (this.searchAnimating) {
        return { xOffset: xOffset, yOffset: 0 };
      }
      if (this.searchExpanded && yOffset > 0 && this.touchingList && scrollState === ScrollState.Scroll) {
        this.hideSearch();
        return { xOffset: xOffset, yOffset: 0 };
      }
      return { xOffset: xOffset, yOffset: yOffset };
    })
    .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
      this.onListScroll(yOffset, scrollState);
    })
    .onReachStart(() => {
      if (!this.searchExpanded) {
        this.collapseProgress = 0;
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.TopBar()
        if (this.currentTab === 0) {
          Stack({ alignContent: Alignment.Top }) {
            if (this.notes().length === 0) {
              this.EmptyView()
            } else {
              this.NoteList()
            }
            Column() {
              this.HeaderSlot()
              this.SearchRow()
              this.GroupBar()
            }
            .width('100%')
            .backgroundColor($r('app.color.page_bg'))
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Column() {
            this.HeaderSlot()
            this.TodoView()
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_add'))
          .width(22)
          .height(22)
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.accent'))
      .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ right: 20, bottom: 36 })
      .onClick(() => {
        this.getUIContext().getPromptAction().showToast({ message: this.currentTab === 0 ? '新建笔记待实现' : '新建待办待实现' });
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
