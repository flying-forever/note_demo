import { NoteCard } from '../components/NoteCard';
import { FAKE_NOTES, GROUP_ALL, NOTE_GROUPS, Note } from '../model/Note';

const LARGE_TITLE_FONT_SIZE: number = 44;
const HEADER_SLOT_HEIGHT: number = 56;
const GROUP_BAR_HEIGHT: number = 44;
const COLLAPSE_DISTANCE: number = HEADER_SLOT_HEIGHT;
const SEARCH_PULL_THRESHOLD: number = 30;
const SEARCH_PULL_MAX: number = 60;

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedGroup: string = GROUP_ALL;
  @State searchProgress: number = 0;
  @State searchExpanded: boolean = false;
  @State pullDistance: number = 0;
  @State collapseProgress: number = 0;

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

  private currentTitle(): string {
    return this.currentTab === 0 ? '笔记' : '待办';
  }

  private cancelPull(): void {
    if (this.pullDistance === 0 && this.searchProgress === 0) {
      return;
    }
    this.pullDistance = 0;
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.searchProgress = 0;
    });
  }

  private hideSearch(): void {
    this.searchExpanded = false;
    this.cancelPull();
  }

  private expandSearch(): void {
    this.searchExpanded = true;
    this.pullDistance = 0;
    this.collapseProgress = 0;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
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

    if (this.searchExpanded) {
      if (offset > 8) {
        this.hideSearch();
      } else {
        return;
      }
    }

    this.collapseProgress = Math.min(1, Math.max(0, offset / COLLAPSE_DISTANCE));

    if (atTop && deltaY < 0) {
      this.pullDistance = Math.min(SEARCH_PULL_MAX, this.pullDistance - deltaY);
      if (this.pullDistance >= SEARCH_PULL_THRESHOLD) {
        this.expandSearch();
      }
      return;
    }

    if (deltaY > 0 || scrollState === ScrollState.Idle) {
      this.cancelPull();
    }
  }

  @Builder
  TopBar() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Text('笔记')
          .fontSize(this.currentTab === 0 ? 22 : 17)
          .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .margin({ right: 20 })
          .onClick(() => {
            this.switchTab(0);
          })
        Text('待办')
          .fontSize(this.currentTab === 1 ? 22 : 17)
          .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 1 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .onClick(() => {
            this.switchTab(1);
          })
        Blank()
        Image($r('app.media.ic_settings'))
          .width(22)
          .height(22)
          .onClick(() => {
            this.getUIContext().getPromptAction().showToast({ message: '设置页待实现' });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Text(this.currentTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .opacity(this.collapseProgress)
        .hitTestBehavior(HitTestMode.None)
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
  HeaderSlot(showSearch: boolean) {
    Stack({ alignContent: Alignment.Start }) {
      Text(this.currentTitle())
        .fontSize(LARGE_TITLE_FONT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .opacity((1 - this.collapseProgress) * (1 - this.searchProgress))
      if (showSearch) {
        this.SearchBar()
      }
    }
    .width('100%')
    .height(HEADER_SLOT_HEIGHT * (1 - this.collapseProgress))
    .padding({ left: 16, right: 16 })
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
      .padding({ top: HEADER_SLOT_HEIGHT + GROUP_BAR_HEIGHT })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
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
              this.HeaderSlot(true)
              this.GroupBar()
            }
            .width('100%')
            .backgroundColor($r('app.color.page_bg'))
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Column() {
            this.HeaderSlot(false)
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
