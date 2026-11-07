import { GROUP_ALL, GROUP_UNFILED, NOTE_GROUPS, Note } from '../model/Note';
import { deleteNote, findNote, moveNote, NoteEditorParams, saveNote } from '../model/NoteStore';
import { NoteDraft, NoteHistory } from '../model/NoteHistory';

const EDITOR_PADDING: number = 16;
const TITLE_FONT_SIZE: number = 26;
const BODY_FONT_SIZE: number = 17;
const BODY_INPUT_VERTICAL_PADDING: number = 6;
const META_FONT_SIZE: number = 13;
const NAV_ICON_SIZE: number = 24;
const TITLE_INPUT_ID: string = 'note-editor-title';
const BODY_INPUT_ID: string = 'note-editor-body';
const MENU_WIDTH: number = 200;
const MENU_ROW_HEIGHT: number = 56;
const MENU_TOP: number = 16;
const MENU_CORNER: number = 20;
const MENU_ITEMS: string[] = ['设置提醒', '设为私密', '发送到桌面', '移动到', '删除'];
const FOLDER_GESTURE_DISTANCE: number = 8;
const FOLDER_HEIGHT: number = 40;
const SETTLE_DURATION: number = 180;
const NAV_BUTTON_SIZE: number = 44;
const NAV_SPACING: number = 8;
const UNFILED: string = GROUP_UNFILED;
const FOLDER_OPTIONS: string[] = NOTE_GROUPS.filter((group: string) => group !== GROUP_ALL);

@Entry
@Component
struct NoteEditor {
  @State private title: string = '';
  @State private content: string = '';
  @State private editing: boolean = false;
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  private history: NoteHistory = new NoteHistory('', '');
  private pastePending: boolean = false;
  @State private menuVisible: boolean = false;
  @State private folderPickerVisible: boolean = false;
  @State private folderProgress: number = 0;
  private gestureStartProgress: number = 0;
  private folderGestureAllowed: boolean = false;
  private activeInput: string = '';
  private keyboardTimer: number = -1;
  @State private selectedGroup: string = '';
  private bodyScroller: Scroller = new Scroller();
  private gestureFinishedAt: number = 0;
  private focusTarget: string = BODY_INPUT_ID;
  private params: NoteEditorParams = { id: '', group: '' };
  private original?: Note;

  aboutToAppear(): void {
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.original = findNote(this.params.id);
    this.title = this.original?.title ?? '';
    this.content = this.original?.content ?? '';
    this.history = new NoteHistory(this.title, this.content);
    this.editing = this.original === undefined;
    this.selectedGroup = this.original?.group ?? this.params.group;
  }

  aboutToDisappear(): void {
    clearTimeout(this.keyboardTimer);
  }

  private inputEditingChanged(active: boolean, id: string): void {
    this.history.closeGroup();
    if (active) {
      clearTimeout(this.keyboardTimer);
      this.activeInput = id;
    } else if (this.activeInput === id) {
      this.activeInput = '';
      this.keyboardTimer = setTimeout(() => {
        if (this.activeInput === '') {
          this.editing = false;
        }
      }, 0);
    }
  }

  private updateHistoryButtons(): void {
    this.canUndo = this.history.canUndo();
    this.canRedo = this.history.canRedo();
  }

  private changeText(value: string, field: string, preview?: PreviewText): void {
    if (field === TITLE_INPUT_ID) {
      this.title = value;
    } else {
      this.content = value;
    }
    if (preview && preview.value.length > 0) {
      return;
    }
    this.history.record(this.title, this.content, field);
    if (this.pastePending) {
      this.history.closeGroup();
      this.pastePending = false;
    }
    this.updateHistoryButtons();
  }

  private preparePaste(): void {
    this.history.closeGroup();
    this.pastePending = true;
  }

  private restoreHistory(redo: boolean): void {
    const draft: NoteDraft = redo ? this.history.redo() : this.history.undo();
    this.title = draft.title;
    this.content = draft.content;
    this.updateHistoryButtons();
  }

  @Builder
  HistoryButton(resource: Resource, label: string, redo: boolean) {
    Button({ type: ButtonType.Normal }) {
      Image(resource).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE)
    }
    .width(NAV_BUTTON_SIZE)
    .height(NAV_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .enabled(redo ? this.canRedo : this.canUndo)
    .opacity((redo ? this.canRedo : this.canUndo) ? 1 : 0.3)
    .onClick(() => this.restoreHistory(redo))
  }
  private startEditing(target: string): void {
    if (Date.now() - this.gestureFinishedAt < 200) {
      return;
    }
    this.focusTarget = target;
    this.editing = true;
  }

  private focusInput(id: string): void {
    if (this.focusTarget === id) {
      this.getUIContext().getFocusController().requestFocus(id);
    }
  }

  private saveBeforeLeaving(): boolean {
    if (this.original?.title === this.title && this.original?.content === this.content) {
      return true;
    }
    if (this.title.trim().length === 0 && this.content.trim().length === 0) {
      if (this.original) {
        this.getUIContext().getPromptAction().showToast({ message: '请填写标题或正文' });
        return false;
      }
      return true;
    }
    saveNote(this.params, this.title, this.content);
    return true;
  }

  onBackPress(): boolean {
    if (this.folderPickerVisible) {
      this.folderPickerVisible = false;
      return true;
    }
    if (this.menuVisible) {
      this.menuVisible = false;
      return true;
    }
    return !this.saveBeforeLeaving();
  }

  private pendingFeature(name: string): void {
    this.getUIContext().getPromptAction().showToast({ message: name + '待实现' });
  }

  private selectFolder(label: string): void {
    const group: string = label === UNFILED ? '' : label;
    this.selectedGroup = group;
    this.params.group = group;
    moveNote(this.params.id, group);
    this.folderPickerVisible = false;
    this.folderProgress = 1;
  }

  private async confirmDelete(): Promise<void> {
    this.menuVisible = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除笔记',
        message: '确定删除这条笔记吗？',
        buttons: [
          { text: '取消', color: $r('app.color.text_primary') },
          { text: '删除', color: $r('app.color.accent') }
        ]
      });
      if (result.index === 1) {
        deleteNote(this.params.id);
        this.getUIContext().getRouter().back();
      }
    } catch {
      return;
    }
  }

  @Builder
  ToolbarIcon(resource: Resource, label: string) {
    Button({ type: ButtonType.Normal }) {
      Image(resource).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE)
    }
    .accessibilityText(label)
    .width(NAV_BUTTON_SIZE)
    .height(NAV_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .onClick(() => this.pendingFeature(label))
  }

  @Builder
  NavigationBar() {
    Row({ space: NAV_SPACING }) {
      Button('←', { type: ButtonType.Normal })
        .fontSize(NAV_ICON_SIZE)
        .accessibilityText('返回')
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          if (this.saveBeforeLeaving()) {
            this.getUIContext().getRouter().back();
          }
        })
      Blank()
      if (this.editing) {
        this.HistoryButton($r('app.media.ic_undo'), '撤销', false)
        this.HistoryButton($r('app.media.ic_redo'), '重做', true)
        Button('✓', { type: ButtonType.Normal })
          .fontSize(NAV_ICON_SIZE)
          .accessibilityText('结束编辑')
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.history.closeGroup();
            this.getUIContext().getFocusController().clearFocus();
            this.editing = false;
          })
      } else {
        this.ToolbarIcon($r('app.media.ic_share'), '分享')
        this.ToolbarIcon($r('app.media.ic_skin'), '皮肤')
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_more')).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE)
        }
        .accessibilityText('更多')
        .width(NAV_BUTTON_SIZE)
        .height(NAV_BUTTON_SIZE)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.menuVisible = true;
        })
      }
    }
    .width('100%')
  }

  @Builder
  Metadata() {
    Text(`${this.original ? this.original.timeLabel + '  |  ' : ''}${Array.from(this.content.replace(/\s/g, '')).length}字`)
      .fontSize(META_FONT_SIZE)
      .fontColor($r('app.color.text_secondary'))
  }

  @Builder
  EditorContent() {
    Column({ space: EDITOR_PADDING }) {
      this.NavigationBar()
      if (!this.editing) {
        Column() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: BODY_INPUT_VERTICAL_PADDING }) {
            Image($r('app.media.ic_folder')).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE)
            Text(this.selectedGroup || UNFILED).fontSize(BODY_FONT_SIZE)
          }
        }
        .backgroundColor($r('app.color.page_bg'))
        .fontColor($r('app.color.text_primary'))
        .borderRadius(MENU_CORNER)
        .height(FOLDER_HEIGHT)
        .opacity(this.folderProgress)
        .enabled(this.folderProgress === 1)
        .onClick(() => {
          this.folderPickerVisible = true;
        })
        }
        .height(FOLDER_HEIGHT * this.folderProgress)
        .clip(true)
      }
      if (this.editing) {
        TextInput({ text: this.title, placeholder: '标题' })
          .id(TITLE_INPUT_ID)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .padding(0)
          .onAppear(() => this.focusInput(TITLE_INPUT_ID))
          .onEditChange((active: boolean) => this.inputEditingChanged(active, TITLE_INPUT_ID))
          .onPaste(() => this.preparePaste())
          .onChange((value: string, preview?: PreviewText) => this.changeText(value, TITLE_INPUT_ID, preview))

        this.Metadata()

        TextArea({ text: this.content, placeholder: '正文' })
          .id(BODY_INPUT_ID)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .fontColor($r('app.color.text_primary'))
          .fontSize(BODY_FONT_SIZE)
          .padding({ top: BODY_INPUT_VERTICAL_PADDING, bottom: BODY_INPUT_VERTICAL_PADDING, left: 0, right: 0 })
          .layoutWeight(1)
          .onAppear(() => this.focusInput(BODY_INPUT_ID))
          .onEditChange((active: boolean) => this.inputEditingChanged(active, BODY_INPUT_ID))
          .onPaste(() => this.preparePaste())
          .onChange((value: string, preview?: PreviewText) => this.changeText(value, BODY_INPUT_ID, preview))
      } else {
        Text(this.title.length > 0 ? this.title : '标题')
          .fontColor(this.title.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .onClick(() => this.startEditing(TITLE_INPUT_ID))

        this.Metadata()

        Scroll(this.bodyScroller) {
          Text(this.content.length > 0 ? this.content : '正文')
            .fontColor(this.content.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .fontSize(BODY_FONT_SIZE)
            .padding({ top: BODY_INPUT_VERTICAL_PADDING })
            .width('100%')
        }
        .align(Alignment.TopStart)
        .layoutWeight(1)
        .width('100%')
        .onClick(() => this.startEditing(BODY_INPUT_ID))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(EDITOR_PADDING)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: FOLDER_GESTURE_DISTANCE })
        .onActionStart(() => {
          this.gestureStartProgress = this.folderProgress;
          this.folderGestureAllowed = !this.editing && !this.menuVisible && !this.folderPickerVisible;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.folderGestureAllowed) {
            if (event.offsetY < 0 || this.bodyScroller.currentOffset().yOffset <= 0) {
              this.folderProgress = Math.max(0, Math.min(1, this.gestureStartProgress + event.offsetY / FOLDER_HEIGHT));
            }
            this.gestureFinishedAt = Date.now();
          }
        })
        .onActionEnd(() => {
          this.settleFolder();
        })
        .onActionCancel(() => {
          this.settleFolder();
        })
    )
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.EditorContent()
      if (this.menuVisible || this.folderPickerVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => {
            this.menuVisible = false;
            this.folderPickerVisible = false;
          })
      }
      if (this.menuVisible) {
        Column() {
          ForEach(MENU_ITEMS, (label: string) => {
            Button(label, { type: ButtonType.Normal })
              .width('100%')
              .height(MENU_ROW_HEIGHT)
              .fontSize(BODY_FONT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (label === '删除') {
                  this.confirmDelete();
                } else if (label === '移动到') {
                  this.menuVisible = false;
                  this.folderPickerVisible = true;
                } else {
                  this.menuVisible = false;
                  this.pendingFeature(label);
                }
              })
          })
        }
        .width(MENU_WIDTH)
        .padding(BODY_INPUT_VERTICAL_PADDING)
        .borderRadius(MENU_CORNER)
        .backgroundColor($r('app.color.card_bg'))
        .margin({ top: MENU_TOP, right: EDITOR_PADDING })
      }
      if (this.folderPickerVisible) {
        Column() {
          Text('移动到').fontSize(TITLE_FONT_SIZE).padding(EDITOR_PADDING)
          ForEach(FOLDER_OPTIONS, (label: string) => {
            Button(label + ((this.selectedGroup || UNFILED) === label ? '  ✓' : ''), { type: ButtonType.Normal })
              .width('100%')
              .height(MENU_ROW_HEIGHT)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.selectFolder(label))
          })
        }
        .width(MENU_WIDTH)
        .padding(EDITOR_PADDING)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(MENU_CORNER)
        .margin({ top: MENU_TOP, right: EDITOR_PADDING })
      }
    }
    .width('100%')
    .height('100%')
  }

  private settleFolder(): void {
    if (this.folderGestureAllowed) {
      this.gestureFinishedAt = Date.now();
      this.getUIContext().animateTo({ duration: SETTLE_DURATION, curve: Curve.EaseOut }, () => {
        this.folderProgress = this.folderProgress >= 0.5 ? 1 : 0;
      });
    }
    this.folderGestureAllowed = false;
  }
}
