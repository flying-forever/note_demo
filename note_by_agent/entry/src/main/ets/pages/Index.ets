import { NoteCard } from '../components/NoteCard';
import { FAKE_NOTES, GROUP_ALL, NOTE_GROUPS, Note } from '../model/Note';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State selectedGroup: string = GROUP_ALL;
  @State searchProgress: number = 0;
  @State searchExpanded: boolean = false;
  @State pullDistance: number = 0;

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
    this.pullDistance = 0;
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.searchExpanded = false;
      this.searchProgress = 0;
    });
  }

  private onListScroll(scrollOffset: number, scrollState: ScrollState): void {
    if (this.searchExpanded) {
      return;
    }
    if (scrollOffset < 0) {
      this.pullDistance = Math.min(60, this.pullDistance - scrollOffset);
      this.searchProgress = Math.min(1, this.pullDistance / 36);
      if (this.pullDistance >= 30) {
        this.searchExpanded = true;
        this.searchProgress = 1;
      }
      return;
    }
    if (scrollOffset > 0) {
      this.pullDistance = 0;
      this.searchProgress = 0;
      return;
    }
    if (scrollState === ScrollState.Idle && this.pullDistance > 0) {
      this.pullDistance = 0;
      this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.searchProgress = 0;
      });
    }
  }

  @Builder
  TopBar() {
    Row() {
      Text('笔记')
        .fontSize(this.currentTab === 0 ? 22 : 17)
        .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .margin({ right: 20 })
        .onClick(() => {
          this.currentTab = 0;
        })
      Text('待办')
        .fontSize(this.currentTab === 1 ? 22 : 17)
        .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === 1 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .onClick(() => {
          this.currentTab = 1;
          this.hideSearch();
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
  }

  @Builder
  SearchBar() {
    Column() {
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
          .padding({ left: 8, right: 0 })
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.accent'))
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.hideSearch();
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 4 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(20)
    }
    .width('100%')
    .height(48 * this.searchProgress)
    .opacity(this.searchProgress)
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
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
                  this.selectedGroup = group;
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
      .height(44)
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
    .height(44)
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
    .layoutWeight(1)
    .width('100%')
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

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.TopBar()
        if (this.currentTab === 0) {
          if (this.searchProgress > 0) {
            this.SearchBar()
          }
          this.GroupBar()
          if (this.notes().length === 0) {
            this.EmptyView()
          } else {
            Scroll() {
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
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
              this.onListScroll(yOffset, scrollState);
            })
          }
        } else {
          this.TodoView()
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
