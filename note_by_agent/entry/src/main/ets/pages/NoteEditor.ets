import { NoteSkinPickerView } from '../components/NoteSkinPickerView';
import { NoteCaptionEditorView } from '../components/NoteCaptionEditorView';
import { DynamicSkinView } from '../components/DynamicSkinView';
import { readDesktopNote, readDesktopRecord } from '../repository/DesktopNoteRepository';
import { saveNoteDraft, snapshotNote, isBlankNote } from '../services/NoteService';
import { BodyBlock, NoteImage, textBlock, documentText, copyImage } from '../model/NoteDocument';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

import { GROUP_ALL, GROUP_UNFILED, NOTE_GROUPS, Note } from '../model/Note';
import { changeNoteSkin, deleteNote, moveNote, NoteEditorParams } from '../services/NoteService';
import { findNote, listNotes, syncDesktopNotes } from '../repository/NoteRepository';
import { findSkin, isDynamicSkin, NoteSkin } from '../model/NoteSkin';
import { NoteEditorSession } from '../viewmodel/NoteEditorSession';
import { importNoteImage, releaseUnusedImages } from '../platform/NoteAttachments';
import { NoteShare } from '../platform/NoteShare';
import { common } from '@kit.AbilityKit';

const EDITOR_PADDING: number = 16;
const TITLE_FONT_SIZE: number = 26;
const BODY_FONT_SIZE: number = 17;
const BODY_INPUT_VERTICAL_PADDING: number = 6;
const BODY_LINE_HEIGHT: number = 26;
const TITLE_LINE_HEIGHT: number = 40;
const SKIN_PANEL_HEIGHT: number = 162;
const SCROLL_RESTORE_DELAY: number = 60;
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
const IMAGE_SMALL_WIDTH: string = '50%';
const IMAGE_ACTION_HEIGHT: number = 48;
const IMAGE_ACTIONS: string[] = ['描述', '尺寸', '详情', '删除图片'];
const UNFILED: string = GROUP_UNFILED;
const FOLDER_OPTIONS: string[] = NOTE_GROUPS.filter((group: string) => group !== GROUP_ALL);

@Entry
@Component
struct NoteEditor {
  @StorageLink('desktopEditorRequest') @Watch('refreshDesktopTarget') private desktopEditorRequest: string = '';
  @State private session: NoteEditorSession = new NoteEditorSession();
  private disposed: boolean = false;
  private sessionGeneration: number = 0;
  private deletionPromptVisible: boolean = false;
  @State private pageVisible: boolean = true;
  private scrollRestoreTimer: number = -1;
  private savedBodyOffset: number = 0;
  private inputControllers: Map<string, TextAreaController> = new Map();
  @State private editing: boolean = false;
  @State private skinId: string = 'white';
  @State private skinPickerVisible: boolean = false;
  @State private selectedImage: string = '';
  @State private detailImage: string = '';
  @State private captionVisible: boolean = false;
  @State private captionDraft: string = '';
  @State private pickingImage: boolean = false;
  @State private zoom: number = 1;
  private zoomStart: number = 1;
  private share: NoteShare = new NoteShare();
  @State private menuVisible: boolean = false;
  @State private folderPickerVisible: boolean = false;
  @State private folderProgress: number = 0;
  private gestureLastOffset: number = 0;
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
    this.sessionGeneration++;
    syncDesktopNotes();
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.original = findNote(this.params.id);
    this.session.load(this.original);
    this.editing = this.original === undefined;
    this.selectedGroup = this.original?.group ?? this.params.group;
    this.skinId = this.original?.skinId ?? 'white';
  }

  onPageShow(): void {
    this.pageVisible = true;
    const requested = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    if (requested && requested.id !== this.params.id) {
      if (!this.saveBeforeLeaving()) { return; }
      this.sessionGeneration++;
      releaseUnusedImages(this.session.images, listNotes());
      this.params = requested;
      syncDesktopNotes();
      this.original = findNote(requested.id);
      this.session.load(this.original);
      this.skinId = this.original?.skinId ?? 'white';
      this.selectedGroup = this.original?.group ?? requested.group;
      this.editing = this.original === undefined;
      this.skinPickerVisible = false;
      this.menuVisible = false;
      this.folderPickerVisible = false;
      this.captionVisible = false;
      this.selectedImage = '';
      this.detailImage = '';
      this.folderProgress = 0;
      this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }
    syncDesktopNotes();
    if (this.original && readDesktopRecord(this.params.id)?.deleted) {
      this.resolveDeletedNote();
      return;
    }
    const latest = readDesktopNote(this.params.id);
    if (latest && this.original && JSON.stringify(latest) !== JSON.stringify(this.original)) {
      this.refreshExternalNote(latest);
    }
  }

  private refreshDesktopTarget(): void {
    if (this.pageVisible && !this.disposed) { this.onPageShow(); }
  }

  onPageHide(): void {
    this.pageVisible = false;
    clearTimeout(this.keyboardTimer);
    clearTimeout(this.scrollRestoreTimer);
  }

  private async refreshExternalNote(latest: Note): Promise<void> {
    const generation: number = this.sessionGeneration;
    if (this.session.isDirty()) {
      try {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '笔记已在桌面更新', message: '选择保留当前编辑，或载入桌面保存的内容。',
          buttons: [{ text: '保留当前编辑', color: $r('app.color.text_primary') },
            { text: '载入桌面版本', color: $r('app.color.accent') }]
        });
        if (this.disposed || generation !== this.sessionGeneration || latest.id !== this.params.id) { return; }
        if (choice.index === 0) {
          this.original = latest;
          return;
        }
      } catch {
        return;
      }
    }
    if (this.disposed || generation !== this.sessionGeneration || latest.id !== this.params.id) { return; }
    releaseUnusedImages(this.session.images, listNotes());
    this.sessionGeneration++;
    this.original = latest;
    this.session.load(latest);
    this.skinId = latest.skinId ?? 'white';
    this.selectedGroup = latest.group;
    this.params.group = latest.group;
  }

  private async resolveDeletedNote(): Promise<void> {
    if (this.deletionPromptVisible) { return; }
    const generation: number = this.sessionGeneration;
    this.deletionPromptVisible = true;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '笔记已在其他入口删除', message: '可以将当前内容另存为新笔记，或放弃当前草稿。',
        buttons: [{ text: '另存为新笔记', color: $r('app.color.accent') },
          { text: '放弃当前草稿', color: $r('app.color.text_primary') }]
      });
      if (this.disposed || generation !== this.sessionGeneration) { return; }
      if (choice.index === 0) {
        const result = saveNoteDraft({ id: '', group: this.selectedGroup, title: this.session.title,
          blocks: this.session.blocks, images: this.session.referencedImages(), skinId: this.skinId,
          expectedSnapshot: '' });
        if (result.status === 'saved' && result.note) {
          this.params.id = result.note.id;
          this.params.group = result.note.group;
          this.original = result.note;
          this.session.markSaved();
          this.getUIContext().getPromptAction().showToast({ message: '已另存为新笔记' });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '另存失败，当前草稿仍保留' });
        }
      } else {
        releaseUnusedImages(this.session.images, listNotes());
        this.session.markSaved();
        this.getUIContext().getRouter().back();
      }
    } catch {
      return;
    } finally {
      this.deletionPromptVisible = false;
    }
  }

  private sendToDesktop(): void {
    this.menuVisible = false;
    if (!this.session.title.trim() && !this.session.content.trim() && !this.hasImages()) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写内容后再发送到桌面' });
      return;
    }
    if (this.commitDraft(true)) {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/NoteDesktop', params: this.params });
    }
  }

  aboutToDisappear(): void {
    clearTimeout(this.keyboardTimer);
    clearTimeout(this.scrollRestoreTimer);
    this.disposed = true;
    releaseUnusedImages(this.session.images, listNotes());
    this.share.dispose();
  }

  private inputEditingChanged(active: boolean, id: string): void {
    this.session.closeGroup();
    if (active) {
      clearTimeout(this.keyboardTimer);
      this.activeInput = id;
    } else if (this.activeInput === id) {
      this.activeInput = '';
      this.keyboardTimer = setTimeout(() => {
        if (this.activeInput === '' && this.pageVisible && !this.disposed) {
          this.editing = false;
        }
      }, 0);
    }
  }

  private changeText(value: string, field: string, preview?: PreviewText): void {
    this.session.changeTitle(value, !!preview && preview.value.length > 0);
  }

  private preparePaste(): void { this.session.preparePaste(); }

  private restoreHistory(redo: boolean): void {
    this.session.restoreHistory(redo);
    this.selectedImage = '';
    this.focusTarget = this.session.activeBlock;
    clearTimeout(this.keyboardTimer);
    this.keyboardTimer = setTimeout(() => {
      if (!this.disposed && this.pageVisible && this.editing) {
        this.getUIContext().getFocusController().requestFocus(this.focusTarget);
        this.controllerFor(this.focusTarget).caretPosition(this.session.caret);
      }
    }, 0);
  }

  private controllerFor(id: string): TextAreaController {
    let controller = this.inputControllers.get(id);
    if (!controller) {
      controller = new TextAreaController();
      this.inputControllers.set(id, controller);
    }
    return controller;
  }

  private hasImages(): boolean { return this.session.hasImages(); }

  private imageItem(id: string): NoteImage { return this.session.imageItem(id); }

  private async insertImage(): Promise<void> {
    if (this.pickingImage) { return; }
    this.pickingImage = true;
    this.session.closeGroup();
    const target: string = this.session.activeBlock;
    const offset: number = this.session.caret;
    const generation: number = this.sessionGeneration;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0 || this.disposed || generation !== this.sessionGeneration) { return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const item = await importNoteImage(context.filesDir, result.photoUris[0]);
      if (this.disposed || generation !== this.sessionGeneration) {
        releaseUnusedImages([item], listNotes());
        return;
      }
      this.focusTarget = this.session.insertImage(item, target, offset);
      this.editing = true;
    } catch {
      if (!this.disposed) {
        this.getUIContext().getPromptAction().showToast({ message: '无法插入图片，请重新选择' });
      }
    } finally {
      if (!this.disposed) { this.pickingImage = false; }
    }
  }

  private imageAction(action: string, id: string): void {
    if (action === '描述') {
      this.captionDraft = this.imageItem(id).caption;
      this.captionVisible = true;
    } else if (action === '尺寸') {
      this.session.images = this.session.images.map((item: NoteImage) => item.id === id ? copyImage(item, item.caption, !item.small) : item);
    } else if (action === '详情') {
      this.zoom = 1;
      this.detailImage = id;
    } else {
      this.session.removeImage(id);
      this.selectedImage = '';
    }
  }

  private blockText(id: string): string { return this.session.blockText(id); }

  private changeBlock(value: string, id: string, preview?: PreviewText): void {
    this.session.changeBlock(value, id, !!preview && preview.value.length > 0);
  }

  @Builder
  EditTools() {
    Row() {
      ForEach(['语音', '图片', '手写', '清单', '更多工具'], (label: string) => {
        Button({ type: ButtonType.Normal }) {
          if (label === '图片') {
            Image($r('app.media.ic_image')).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
          } else {
            Text(label === '语音' ? '≋' : label === '手写' ? '✎' : label === '清单' ? '☑' : '+')
              .fontSize(NAV_ICON_SIZE).fontColor(this.skin().text)
          }
        }
        .layoutWeight(1)
        .height(NAV_BUTTON_SIZE)
        .backgroundColor(Color.Transparent)
        .accessibilityText(label)
        .enabled(!this.pickingImage)
        .onClick(() => {
          this.selectedImage = '';
          if (label === '图片') {
            this.insertImage();
          } else {
            this.pendingFeature(label);
          }
        })
      })
    }.width('100%').backgroundColor(this.skin().panel)
  }

  @Builder
  ImageBlock(block: BodyBlock) {
    Column({ space: BODY_INPUT_VERTICAL_PADDING }) {
      Image('file://' + this.imageItem(block.imageId).path)
        .width(this.imageItem(block.imageId).small ? IMAGE_SMALL_WIDTH : '100%')
        .aspectRatio(this.imageItem(block.imageId).width / this.imageItem(block.imageId).height)
        .objectFit(ImageFit.Contain)
        .accessibilityText(this.imageItem(block.imageId).caption || '笔记图片')
        .onClick(() => {
          this.session.closeGroup();
          this.selectedImage = this.selectedImage === block.imageId ? '' : block.imageId;
        })
      if (this.imageItem(block.imageId).caption !== '') {
        Text(this.imageItem(block.imageId).caption)
          .fontSize(META_FONT_SIZE).fontColor(this.skin().secondary).textAlign(TextAlign.Center).width('100%')
      }
    }
    .width('100%')
    .overlay(this.ImageActions(block.imageId), { align: Alignment.Top })
  }

  @Builder
  ImageActions(id: string) {
    if (this.selectedImage === id) {
      Row() {
        ForEach(IMAGE_ACTIONS, (action: string) => {
          Button({ type: ButtonType.Normal }) {
            Image(action === '描述' ? $r('app.media.ic_caption') : action === '尺寸' ?
              (this.imageItem(id).small ? $r('app.media.ic_expand') : $r('app.media.ic_shrink')) :
              action === '详情' ? $r('app.media.ic_info') : $r('app.media.ic_delete_image'))
              .width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
          }
          .width(NAV_BUTTON_SIZE).height(IMAGE_ACTION_HEIGHT)
          .backgroundColor(Color.Transparent)
          .accessibilityText(action === '尺寸' ? (this.imageItem(id).small ? '放大' : '缩小') : action)
          .onClick(() => this.imageAction(action, id))
        })
      }
      .backgroundColor(this.skin().panel).borderRadius(MENU_CORNER)
      .shadow({ radius: 8, color: '#44000000', offsetY: 2 })
    }
  }

  @Builder
  DocumentBody() {
    Scroll(this.bodyScroller) {
      Column({ space: BODY_INPUT_VERTICAL_PADDING }) {
        ForEach(this.session.blocks, (block: BodyBlock) => {
          if (block.imageId !== '') {
            this.ImageBlock(block)
          } else if (this.editing) {
            TextArea({ text: this.blockText(block.id), placeholder: this.session.blocks.length === 1 ? '正文' : '',
              controller: this.controllerFor(block.id) })
              .id(block.id)
              .placeholderColor(this.skin().secondary)
              .backgroundColor(Color.Transparent).borderRadius(0)
              .fontColor(this.skin().text).fontSize(BODY_FONT_SIZE)
              .padding(0)
              .lineHeight(BODY_LINE_HEIGHT)
              .width('100%')
              .constraintSize({ minHeight: NAV_BUTTON_SIZE })
              .onAppear(() => {
                if (this.focusTarget === block.id ||
                  (this.focusTarget === BODY_INPUT_ID && this.session.activeBlock === block.id)) {
                  this.getUIContext().getFocusController().requestFocus(block.id);
                  this.controllerFor(block.id).caretPosition(this.session.caret);
                }
              })
              .onEditChange((active: boolean) => {
                if (active) {
                  this.session.activeBlock = block.id;
                  this.selectedImage = '';
                }
                this.inputEditingChanged(active, block.id);
              })
              .onTextSelectionChange((start: number, end: number) => {
                if (this.activeInput === block.id) {
                  this.session.activeBlock = block.id;
                  this.session.caret = end;
                }
              })
              .onPaste(() => this.preparePaste())
              .onChange((value: string, preview?: PreviewText) => this.changeBlock(value, block.id, preview))
          } else {
            Text(this.blockText(block.id) || (this.session.blocks.length === 1 ? '正文' : ' '))
              .fontColor(this.blockText(block.id) ? this.skin().text : this.skin().secondary)
              .fontSize(BODY_FONT_SIZE).width('100%')
              .lineHeight(BODY_LINE_HEIGHT)
              .constraintSize({ minHeight: NAV_BUTTON_SIZE })
              .onClick(() => {
                this.selectedImage = '';
                this.session.activeBlock = block.id;
                this.startEditing(block.id);
              })
          }
        }, (block: BodyBlock) => block.id)
        Blank().height(NAV_BUTTON_SIZE).width('100%').onClick(() => {
          this.selectedImage = '';
          const last: BodyBlock = this.session.blocks[this.session.blocks.length - 1];
          this.session.activeBlock = last.id;
          this.session.caret = last.text.length;
          this.startEditing(last.id);
        })
      }.width('100%')
    }
    .align(Alignment.TopStart).layoutWeight(1).width('100%')
    .onDidScroll(() => { this.selectedImage = ''; })
  }

  @Builder
  ImageDetails() {
    Column({ space: EDITOR_PADDING }) {
      Row() {
        Button('返回').onClick(() => { this.detailImage = ''; })
        Blank()
        Text('图片详情').fontColor(Color.White).fontSize(BODY_FONT_SIZE)
      }.width('100%')
      Image('file://' + this.imageItem(this.detailImage).path)
        .objectFit(ImageFit.Contain).width('100%').layoutWeight(1)
        .scale({ x: this.zoom, y: this.zoom })
        .gesture(PinchGesture().onActionStart(() => { this.zoomStart = this.zoom; })
          .onActionUpdate((event: GestureEvent) => { this.zoom = Math.max(1, Math.min(5, this.zoomStart * event.scale)); }))
      Text(this.imageItem(this.detailImage).name + '\n' + this.imageItem(this.detailImage).width + ' × ' +
        this.imageItem(this.detailImage).height + ' 像素 · ' + (this.imageItem(this.detailImage).bytes / 1024).toFixed(1) + ' KB')
        .fontColor(Color.White).fontSize(META_FONT_SIZE).textAlign(TextAlign.Center)
    }.padding(EDITOR_PADDING).width('100%').height('100%').backgroundColor(Color.Black).clip(true)
  }

  @Builder
  HistoryButton(resource: Resource, label: string, redo: boolean) {
    Button({ type: ButtonType.Normal }) {
      Image(resource).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
    }
    .width(NAV_BUTTON_SIZE)
    .height(NAV_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .id('note-action-' + label)
    .enabled(redo ? this.session.canRedo : this.session.canUndo)
    .opacity((redo ? this.session.canRedo : this.session.canUndo) ? 1 : 0.3)
    .onClick(() => this.restoreHistory(redo))
  }
  private startEditing(target: string): void {
    if (Date.now() - this.gestureFinishedAt < 200) {
      return;
    }
    this.focusTarget = target;
    this.skinPickerVisible = false;
    this.savedBodyOffset = this.bodyScroller.currentOffset().yOffset;
    this.editing = true;
    clearTimeout(this.scrollRestoreTimer);
    this.scrollRestoreTimer = setTimeout(() => {
      if (!this.disposed) {
        this.bodyScroller.scrollTo({ xOffset: 0, yOffset: this.savedBodyOffset });
      }
    }, SCROLL_RESTORE_DELAY);
  }

  private focusInput(id: string): void {
    if (this.focusTarget === id) {
      this.getUIContext().getFocusController().requestFocus(id);
    }
  }

  private saveBeforeLeaving(): boolean {
    if (!this.session.isDirty()) { return true; }
    if (isBlankNote(this.session.title, this.session.blocks)) {
      if (this.original) {
        this.getUIContext().getPromptAction().showToast({ message: '请填写标题或正文' });
        return false;
      }
      return true;
    }
    return this.commitDraft(false);
  }

  private commitDraft(persistToDesktop: boolean): boolean {
    const result = saveNoteDraft({ id: this.params.id, group: this.selectedGroup,
      title: this.session.title, blocks: this.session.blocks, images: this.session.referencedImages(),
      skinId: this.skinId, expectedSnapshot: snapshotNote(this.original), persistToDesktop: persistToDesktop });
    if (result.status === 'saved' && result.note) {
      this.original = result.note;
      this.params.id = result.note.id;
      this.params.group = result.note.group;
      this.session.markSaved();
      return true;
    }
    const message: string = result.status === 'conflict' ? '笔记已在其他入口更新，请返回编辑页重新确认版本' :
      result.status === 'deleted' ? '笔记已在其他入口删除，当前内容尚未保存' :
      result.status === 'empty' ? '请填写标题或正文' : '保存失败，请稍后重试';
    this.getUIContext().getPromptAction().showToast({ message: message });
    if (result.status === 'deleted') { this.resolveDeletedNote(); }
    return false;
  }

  onBackPress(): boolean {
    if (this.captionVisible) {
      this.captionVisible = false;
      return true;
    }
    if (this.detailImage !== '') {
      this.detailImage = '';
      return true;
    }
    if (this.selectedImage !== '') {
      this.selectedImage = '';
      return true;
    }
    if (this.skinPickerVisible) {
      this.skinPickerVisible = false;
      return true;
    }
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

  private async shareNote(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const message = await this.share.show(context, this.session.title, this.session.content);
    if (message && !this.disposed && this.pageVisible) {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private skin(): NoteSkin {
    return findSkin(this.skinId);
  }

  private skinIconFilter(): number[] {
    const color: string = this.skin().text;
    const red: number = parseInt(color.substring(1, 3), 16) / 255;
    const green: number = parseInt(color.substring(3, 5), 16) / 255;
    const blue: number = parseInt(color.substring(5, 7), 16) / 255;
    return [0, 0, 0, 0, red, 0, 0, 0, 0, green, 0, 0, 0, 0, blue, 0, 0, 0, 1, 0];
  }

  private selectSkin(id: string): void {
    try {
      changeNoteSkin(this.params.id, id);
      this.skinId = id;
      if (this.original) { this.original.skinId = id; }
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: '皮肤保存失败，请重试' });
    }
  }

  private selectFolder(label: string): void {
    const group: string = label === UNFILED ? '' : label;
    try {
      moveNote(this.params.id, group);
      this.selectedGroup = group;
      this.params.group = group;
      if (this.original) { this.original.group = group; }
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: '分组保存失败，请重试' });
      return;
    }
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
      Image(resource).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
    }
    .accessibilityText(label)
    .id('note-action-' + label)
    .width(NAV_BUTTON_SIZE)
    .height(NAV_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (label === '皮肤') {
        this.selectedImage = '';
        this.skinPickerVisible = !this.skinPickerVisible;
      } else if (label === '分享') {
        this.skinPickerVisible = false;
        this.selectedImage = '';
        this.shareNote();
      } else {
        this.pendingFeature(label);
      }
    })
  }

  @Builder
  NavigationBar() {
    Row({ space: NAV_SPACING }) {
      Button('←', { type: ButtonType.Normal })
        .fontSize(NAV_ICON_SIZE)
        .accessibilityText('返回')
        .backgroundColor(Color.Transparent)
        .fontColor(this.skin().text)
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
          .fontColor(this.skin().text)
          .onClick(() => {
            this.session.closeGroup();
            this.getUIContext().getFocusController().clearFocus();
            this.editing = false;
          })
      } else {
        this.ToolbarIcon($r('app.media.ic_share'), '分享')
        this.ToolbarIcon($r('app.media.ic_skin'), '皮肤')
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_more')).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
        }
        .accessibilityText('更多')
        .width(NAV_BUTTON_SIZE)
        .height(NAV_BUTTON_SIZE)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.skinPickerVisible = false;
          this.selectedImage = '';
          this.menuVisible = true;
        })
      }
    }
    .width('100%')
  }

  @Builder
  Metadata() {
    Text(`${this.original ? this.original.timeLabel + '  |  ' : ''}${Array.from(this.session.content.replace(/\s/g, '')).length}字`)
      .fontSize(META_FONT_SIZE)
      .fontColor(this.skin().secondary)
  }

  @Builder
  EditorContent() {
    Column({ space: EDITOR_PADDING }) {
      this.NavigationBar()
      Column() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: BODY_INPUT_VERTICAL_PADDING }) {
            Image($r('app.media.ic_folder')).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
            Text(this.selectedGroup || UNFILED).fontSize(BODY_FONT_SIZE)
          }
        }
        .backgroundColor(this.skin().panel)
        .fontColor(this.skin().text)
        .borderRadius(MENU_CORNER)
        .padding({ left: EDITOR_PADDING, right: EDITOR_PADDING })
        .height(FOLDER_HEIGHT)
        .opacity(this.folderProgress)
        .enabled(!this.editing && this.folderProgress === 1)
        .onClick(() => {
          this.folderPickerVisible = true;
        })
        }
        .height(FOLDER_HEIGHT * this.folderProgress)
        .clip(true)
      if (this.editing) {
        TextInput({ text: this.session.title, placeholder: '标题' })
          .id(TITLE_INPUT_ID)
          .placeholderColor(this.skin().secondary)
          .backgroundColor(Color.Transparent)
          .fontColor(this.skin().text)
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .padding(0)
          .height(TITLE_LINE_HEIGHT)
          .onAppear(() => this.focusInput(TITLE_INPUT_ID))
          .onEditChange((active: boolean) => this.inputEditingChanged(active, TITLE_INPUT_ID))
          .onPaste(() => this.preparePaste())
          .onChange((value: string, preview?: PreviewText) => this.changeText(value, TITLE_INPUT_ID, preview))

      } else {
        Text(this.session.title.length > 0 ? this.session.title : '标题')
          .fontColor(this.session.title.length > 0 ? this.skin().text : this.skin().secondary)
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(TITLE_LINE_HEIGHT)
          .onClick(() => this.startEditing(TITLE_INPUT_ID))

      }
      this.Metadata()
      this.DocumentBody()
      Column() {
        this.EditTools()
      }.height(NAV_BUTTON_SIZE).visibility(this.editing ? Visibility.Visible : Visibility.Hidden)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(EDITOR_PADDING)
    .width('100%')
    .height('100%')
    .backgroundColor(isDynamicSkin(this.skin()) ? Color.Transparent : this.skin().background)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: FOLDER_GESTURE_DISTANCE })
        .onActionStart(() => {
          this.gestureLastOffset = 0;
          this.folderGestureAllowed = !this.editing && !this.menuVisible && !this.folderPickerVisible && !this.skinPickerVisible && this.selectedImage === '' && this.detailImage === '';
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.folderGestureAllowed) {
            const delta: number = event.offsetY - this.gestureLastOffset;
            this.gestureLastOffset = event.offsetY;
            if (delta < 0 || this.bodyScroller.currentOffset().yOffset <= 0) {
              this.folderProgress = Math.max(0, Math.min(1, this.folderProgress + delta / FOLDER_HEIGHT));
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
      if (isDynamicSkin(this.skin())) {
        DynamicSkinView({ effect: this.skin().effect, paused: !this.pageVisible || this.editing || this.captionVisible || this.detailImage !== '' })
      }
      this.EditorContent()
      if (this.detailImage !== '') {
        this.ImageDetails()
      }
      if (this.captionVisible) {
        NoteCaptionEditorView({ initialText: this.captionDraft, panelColor: this.skin().panel,
          textColor: this.skin().text, inputColor: this.skin().background,
          onCancel: () => { this.captionVisible = false; },
          onConfirm: (value: string) => {
            this.session.images = this.session.images.map((item: NoteImage) => item.id === this.selectedImage ?
              copyImage(item, value.trim()) : item);
            this.captionVisible = false;
          } })
      }
      if (this.skinPickerVisible) {
        Column() {
          NoteSkinPickerView({ selectedId: this.skinId, panelColor: this.skin().panel,
            onSelect: (id: string) => this.selectSkin(id) })
        }.width('100%').height(SKIN_PANEL_HEIGHT).position({ x: 0, y: '100%' }).translate({ y: -SKIN_PANEL_HEIGHT })
      }
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
              .fontColor(this.skin().text)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (label === '删除') {
                  this.confirmDelete();
                } else if (label === '发送到桌面') {
                  this.sendToDesktop();
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
        .backgroundColor(this.skin().background)
        .margin({ top: MENU_TOP, right: EDITOR_PADDING })
      }
      if (this.folderPickerVisible) {
        Column() {
          Text('移动到').fontSize(TITLE_FONT_SIZE).fontColor(this.skin().text).padding(EDITOR_PADDING)
          ForEach(FOLDER_OPTIONS, (label: string) => {
            Button(label + ((this.selectedGroup || UNFILED) === label ? '  ✓' : ''), { type: ButtonType.Normal })
              .width('100%')
              .height(MENU_ROW_HEIGHT)
              .backgroundColor(Color.Transparent)
              .fontColor(this.skin().text)
              .onClick(() => this.selectFolder(label))
          })
        }
        .width(MENU_WIDTH)
        .padding(EDITOR_PADDING)
        .backgroundColor(this.skin().background)
        .borderRadius(MENU_CORNER)
        .margin({ top: MENU_TOP, right: EDITOR_PADDING })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.skin().background)
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
