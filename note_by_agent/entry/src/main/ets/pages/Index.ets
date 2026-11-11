// 展示笔记分组与瀑布/列表视图，并处理页头滚动、设置菜单和编辑页跳转。
import { NoteCard } from '../components/NoteCard';
import { NoteListItem } from '../components/NoteListItem';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { TECH_DEMOS_ENABLED } from '../diagnostics/DemoCatalog';
import { GROUP_ALL, GROUP_UNFILED, NOTE_GROUPS, Note, noteCardTitle } from '../model/Note';
import { NoteEditorParams } from '../services/NoteService';
import { listNotes, syncDesktopNotes, findNote } from '../repository/NoteRepository';
import { VIEW_LIST, VIEW_WATERFALL, loadViewMode, saveViewMode } from '../repository/NoteSettings';

const LARGE_TITLE_FONT_SIZE: number = 44;
const HEADER_SLOT_HEIGHT: number = 56;
const GROUP_BAR_HEIGHT: number = 44;
const COLLAPSE_DISTANCE: number = HEADER_SLOT_HEIGHT;
const SEARCH_ROW_HEIGHT: number = 56;
const SEARCH_SETTLE_DURATION: number = 180;
const SEARCH_RELEASE_DELAY: number = 50;
const SETTINGS_MENU_WIDTH: number = 200;
const SETTINGS_MENU_ROW_HEIGHT: number = 56;
const SETTINGS_MENU_TOP: number = 60;
const SETTINGS_MENU_CORNER: number = 20;
const SETTINGS_MENU_PADDING: number = 6;
const SETTINGS_MENU_FONT_SIZE: number = 17;
const SETTINGS_MENU_ICON_SIZE: number = 20;

@Entry
@Component
struct Index {
  @StorageLink('desktopLaunchNoteId') @Watch('openDesktopLaunch') private desktopLaunchNoteId: string = '';
  @State currentTab: number = 0;
  @State selectedGroup: string = GROUP_ALL;
  @State searchProgress: number = 0;
  @State collapseProgress: number = 0;
  @State private allNotes: Note[] = listNotes();
  @State private settingsMenuVisible: boolean = false;
  @State private viewMode: string = VIEW_WATERFALL;

  private searchReleaseTimer: number = -1;
  private touchingList: boolean = false;
  private disposed: boolean = false;
  private viewSaveQueue: Promise<void> = Promise.resolve();

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.viewMode = loadViewMode(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  onPageShow(): void {
    syncDesktopNotes();
    this.allNotes = listNotes();
    this.openDesktopLaunch();
  }

  private openDesktopLaunch(): void {
    const id: string = this.desktopLaunchNoteId;
    if (id === '') {
      return;
    }
    this.desktopLaunchNoteId = '';
    syncDesktopNotes();
    const note = findNote(id);
    if (!note) {
      this.getUIContext().getPromptAction().showToast({ message: '笔记已删除或不可用' });
      return;
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/NoteEditor', params: { id: id, group: note.group } }, router.RouterMode.Single)
      .then(() => AppStorage.setOrCreate('desktopEditorRequest', `${id}:${Date.now()}`))
      .catch(() => this.getUIContext().getPromptAction().showToast({ message: '无法打开笔记，请重试' }));
  }

  private openEditor(id: string): void {
    const params: NoteEditorParams = { id: id, group: this.selectedGroup === GROUP_ALL || this.selectedGroup === GROUP_UNFILED ? '' : this.selectedGroup };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/NoteEditor', params: params });
  }

  private viewLabel(): string {
    return this.viewMode === VIEW_LIST ? '列表' : '瀑布';
  }

  private toggleViewMode(): void {
    this.viewMode = this.viewMode === VIEW_LIST ? VIEW_WATERFALL : VIEW_LIST;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.persistViewMode(this.viewMode);
  }

  private persistViewMode(mode: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.viewSaveQueue = this.viewSaveQueue.then(async () => {
      if (!(await saveViewMode(context, mode)) && !this.disposed) {
        this.getUIContext().getPromptAction().showToast({ message: '视图设置保存失败，本次运行内仍生效' });
      }
    }).catch(() => {});
  }

  private openSettings(): void {
    this.settingsMenuVisible = false;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' })
      .catch(() => this.getUIContext().getPromptAction().showToast({ message: '无法打开设置页' }));
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

  private consumeHeaderScroll(delta: number, source: ScrollSource): number {
    const dragging: boolean = this.touchingList && source === ScrollSource.DRAG;
    if (!dragging && source !== ScrollSource.FLING) {
      return delta;
    }
    if (delta > 0 && this.searchProgress > 0) {
      this.cancelSearchRelease();
      const remaining: number = this.searchProgress * SEARCH_ROW_HEIGHT;
      const consumed: number = Math.min(delta, remaining);
      this.searchProgress = (remaining - consumed) / SEARCH_ROW_HEIGHT;
      delta -= consumed;
    }

    if (delta > 0 && this.collapseProgress < 1) {
      const consumed: number = Math.min(delta, (1 - this.collapseProgress) * COLLAPSE_DISTANCE);
      this.collapseProgress = Math.min(1, this.collapseProgress + consumed / COLLAPSE_DISTANCE);
      return delta - consumed;
    }

    if (delta < 0) {
      const offset: number = Math.max(0, this.scroller.currentOffset().yOffset);
      if (-delta > offset) {
        let pull: number = -delta - offset;
        const consumed: number = Math.min(pull, this.collapseProgress * COLLAPSE_DISTANCE);
        this.collapseProgress = Math.max(0, this.collapseProgress - consumed / COLLAPSE_DISTANCE);
        pull -= consumed;
        if (dragging && pull > 0) {
          const searchConsumed: number = Math.min(pull, (1 - this.searchProgress) * SEARCH_ROW_HEIGHT);
          this.searchProgress = Math.min(1, this.searchProgress + searchConsumed / SEARCH_ROW_HEIGHT);
          pull -= searchConsumed;
        }
        return -offset - pull;
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
        Row() {
          Image($r('app.media.ic_settings'))
            .width(22)
            .height(22)
        }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.settingsMenuVisible = true;
          })
          .priorityGesture(LongPressGesture().onAction(() => {
            if (TECH_DEMOS_ENABLED) {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/TechDemos' })
                .catch(() => this.getUIContext().getPromptAction().showToast({ message: '无法打开技术实验室' }));
            }
          }))
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
        timeLabel: item.timeLabel,
        skinId: item.skinId ?? 'white'
      })
    }
    .width('100%')
    .onClick(() => {
      this.openEditor(item.id);
    })
  }

  @Builder
  NoteRowItem(item: Note) {
    Column() {
      NoteListItem({
        title: noteCardTitle(item),
        summary: item.content.trim(),
        timeLabel: item.timeLabel,
        skinId: item.skinId ?? 'white'
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
    .height(180)
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
        if (this.notes().length === 0) {
          this.EmptyView()
        } else if (this.viewMode === VIEW_LIST) {
          Column({ space: 12 }) {
            ForEach(this.notes(), (item: Note) => {
              this.NoteRowItem(item)
            }, (item: Note) => JSON.stringify(item))
          }
          .width('100%')
          .padding({ top: 4, bottom: 96 })
        } else {
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
          .padding({ top: 4, bottom: 96 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(this.notes().length === 0 ? FlexAlign.Center : FlexAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .borderRadius(12)
    .clip(true)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
      return { xOffset: xOffset, yOffset: this.consumeHeaderScroll(yOffset, source) };
    })
    .onScrollStop(() => {
      this.settleSearch();
    })
  }

  @Builder
  ViewModeRow() {
    Row({ space: 10 }) {
      Image($r('app.media.ic_switch'))
        .width(SETTINGS_MENU_ICON_SIZE)
        .height(SETTINGS_MENU_ICON_SIZE)
      Text(this.viewLabel())
        .fontSize(SETTINGS_MENU_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(SETTINGS_MENU_ROW_HEIGHT)
    .padding({ left: 20, right: 20 })
    .accessibilityText('切换视图，当前' + this.viewLabel())
    .onClick(() => this.toggleViewMode())
  }

  @Builder
  MoreRow() {
    Row() {
      Text('更多')
        .fontSize(SETTINGS_MENU_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text('›')
        .fontSize(SETTINGS_MENU_FONT_SIZE)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(SETTINGS_MENU_ROW_HEIGHT)
    .padding({ left: 20, right: 20 })
    .accessibilityText('更多设置')
    .onClick(() => this.openSettings())
  }

  @Builder
  SettingsMenu() {
    Column() {
      this.ViewModeRow()
      this.MoreRow()
    }
    .width(SETTINGS_MENU_WIDTH)
    .padding(SETTINGS_MENU_PADDING)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(SETTINGS_MENU_CORNER)
    .margin({ top: SETTINGS_MENU_TOP, right: 16 })
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
  }

  onBackPress(): boolean {
    if (this.settingsMenuVisible) {
      this.settingsMenuVisible = false;
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.TopBar()
        if (this.currentTab === 0) {
          Column() {
            this.HeaderSlot()
            this.SearchRow()
            this.GroupBar()
            Column() {
              this.NoteList()
            }
            .layoutWeight(1)
            .width('100%')
            .padding({ left: 16, right: 16 })
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

      if (this.settingsMenuVisible) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#33000000')
            .onClick(() => {
              this.settingsMenuVisible = false;
            })
          this.SettingsMenu()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
