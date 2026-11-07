import { NoteCard } from '../components/NoteCard';
import { GROUP_ALL, GROUP_UNFILED, NOTE_GROUPS, Note, noteCardTitle } from '../model/Note';
import { listNotes, NoteEditorParams } from '../model/NoteStore';

const LARGE_TITLE_FONT_SIZE: number = 44;
const HEADER_SLOT_HEIGHT: number = 56;
const GROUP_BAR_HEIGHT: number = 44;
const COLLAPSE_DISTANCE: number = HEADER_SLOT_HEIGHT;
const SEARCH_ROW_HEIGHT: number = 56;
const SEARCH_SETTLE_DURATION: number = 180;
const SEARCH_RELEASE_DELAY: number = 50;

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedGroup: string = GROUP_ALL;
  @State searchProgress: number = 0;
  @State collapseProgress: number = 0;
  @State private allNotes: Note[] = listNotes();

  private searchReleaseTimer: number = -1;
  private touchingList: boolean = false;

  private scroller: Scroller = new Scroller();

  onPageShow(): void {
    this.allNotes = listNotes();
  }

  private openEditor(id: string): void {
    const params: NoteEditorParams = { id: id, group: this.selectedGroup === GROUP_ALL || this.selectedGroup === GROUP_UNFILED ? '' : this.selectedGroup };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/NoteEditor', params: params });
  }

  private notes(): Note[] {
    if (this.selectedGroup === GROUP_ALL) {
      return this.allNotes;
    }
    return this.allNotes.filter((item: Note) => item.group === (this.selectedGroup === GROUP_UNFILED ? '' : this.selectedGroup));
  }

  private estimateHeight(note: Note): number {
    const titleLines: number = Math.min(2, Math.ceil(noteCardTitle(note).length / 9));
    const summaryLines: number = Math.min(4, Math.ceil(note.content.length / 10));
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

  private cancelSearchRelease(): void {
    if (this.searchReleaseTimer !== -1) {
      clearTimeout(this.searchReleaseTimer);
      this.searchReleaseTimer = -1;
    }
  }

  private settleSearch(): void {
    this.cancelSearchRelease();
    if (this.touchingList || this.searchProgress === 0 || this.searchProgress === 1) {
      return;
    }
    const target: number = this.searchProgress >= 0.5 ? 1 : 0;
    const duration: number = Math.round(SEARCH_SETTLE_DURATION * Math.abs(target - this.searchProgress));
    this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut }, () => {
      this.searchProgress = target;
    });
  }

  private switchTab(tab: number): void {
    if (this.currentTab === tab) {
      return;
    }
    this.cancelSearchRelease();
    this.touchingList = false;
    this.searchProgress = 0;
    this.collapseProgress = 0;
    this.currentTab = tab;
  }

  private consumeSearchScroll(delta: number, source: ScrollSource): number {
    const dragging: boolean = this.touchingList && source === ScrollSource.DRAG;
    if (delta > 0 && this.searchProgress > 0 && (dragging || source === ScrollSource.FLING)) {
      this.cancelSearchRelease();
      const remaining: number = this.searchProgress * SEARCH_ROW_HEIGHT;
      const consumed: number = Math.min(delta, remaining);
      this.searchProgress = (remaining - consumed) / SEARCH_ROW_HEIGHT;
      return delta - consumed;
    }

    if (delta < 0 && dragging) {
      const offset: number = Math.max(0, this.scroller.currentOffset().yOffset);
      if (-delta > offset) {
        const pull: number = -delta - offset;
        this.searchProgress = Math.min(1, this.searchProgress + pull / SEARCH_ROW_HEIGHT);
        return -offset;
      }
    }
    return delta;
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
        title: noteCardTitle(item),
        summary: item.content.trim(),
        timeLabel: item.timeLabel
      })
    }
    .width('100%')
    .onClick(() => {
      this.openEditor(item.id);
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
            }, (item: Note) => JSON.stringify(item))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 12 }) {
            ForEach(this.notesForColumn(1), (item: Note) => {
              this.NoteItem(item)
            }, (item: Note) => JSON.stringify(item))
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
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.cancelSearchRelease();
        this.touchingList = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touchingList = false;
        this.cancelSearchRelease();
        this.searchReleaseTimer = setTimeout(() => {
          this.settleSearch();
        }, SEARCH_RELEASE_DELAY);
      }
    })
    .onWillScroll((xOffset: number, yOffset: number, scrollState: ScrollState, source: ScrollSource) => {
      return { xOffset: xOffset, yOffset: this.consumeSearchScroll(yOffset, source) };
    })
    .onDidScroll(() => {
      const offset: number = this.scroller.currentOffset().yOffset;
      this.collapseProgress = Math.min(1, Math.max(0, offset / COLLAPSE_DISTANCE));
    })
    .onScrollStop(() => {
      this.settleSearch();
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
        if (this.currentTab === 0) {
          this.openEditor('');
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '新建待办待实现' });
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
