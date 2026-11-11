import { DynamicSkinView } from '../components/DynamicSkinView';
import { persistDesktopNote, readDesktopNote, refreshDesktopCards } from '../model/DesktopNoteRepository';
import { BodyBlock, NoteImage, textBlock, documentText, copyImage } from '../model/NoteDocument';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

import { GROUP_ALL, GROUP_UNFILED, NOTE_GROUPS, Note } from '../model/Note';
import { changeNoteSkin, deleteNote, findNote, listNotes, moveNote, NoteEditorParams, saveNote, syncDesktopNotes } from '../model/NoteStore';
import { findSkin, isDynamicSkin, NOTE_SKINS, NoteSkin } from '../model/NoteSkin';
import { NoteDraft, NoteHistory } from '../model/NoteHistory';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

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
const SKIN_CARD_WIDTH: number = 96;
const SKIN_CARD_HEIGHT: number = 130;
const SKIN_SELECTED_COLOR: string = '#FFC107';
const IMAGE_SMALL_WIDTH: string = '50%';
const IMAGE_ACTION_HEIGHT: number = 48;
const IMAGE_ACTIONS: string[] = ['描述', '尺寸', '详情', '删除图片'];
const UNFILED: string = GROUP_UNFILED;
const FOLDER_OPTIONS: string[] = NOTE_GROUPS.filter((group: string) => group !== GROUP_ALL);

@Entry
@Component
struct NoteEditor {
  @State private title: string = '';
  @State private content: string = '';
  @State private editing: boolean = false;
  @State private skinId: string = 'white';
  @State private skinPickerVisible: boolean = false;
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  private history: NoteHistory = new NoteHistory('', '');
  @State private blocks: BodyBlock[] = [];
  @State private images: NoteImage[] = [];
  @State private selectedImage: string = '';
  @State private detailImage: string = '';
  @State private captionVisible: boolean = false;
  @State private captionDraft: string = '';
  @State private pickingImage: boolean = false;
  @State private zoom: number = 1;
  private zoomStart: number = 1;
  private activeBlock: string = '';
  private caret: number = 0;
  private originalDocument: string = '';
  private originalImages: string = '';
  private pastePending: boolean = false;
  private shareController?: systemShare.ShareController;
  private sharing: boolean = false;
  private shareDismissCallback = (): void => {
    this.sharing = false;
    this.shareController?.off('dismiss', this.shareDismissCallback);
    this.shareController = undefined;
  };
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
    syncDesktopNotes();
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.original = findNote(this.params.id);
    this.title = this.original?.title ?? '';
    this.content = this.original?.content ?? '';
    this.blocks = this.original?.blocks?.map((block: BodyBlock) => ({ id: block.id, text: block.text, imageId: block.imageId } as BodyBlock)) ?? [textBlock(this.content)];
    this.images = this.original?.images?.map((item: NoteImage) => copyImage(item)) ?? [];
    this.originalDocument = JSON.stringify(this.blocks);
    this.originalImages = JSON.stringify(this.images);
    this.history = new NoteHistory(this.title, this.originalDocument);
    this.activeBlock = this.blocks[0].id;
    this.editing = this.original === undefined;
    this.selectedGroup = this.original?.group ?? this.params.group;
    this.skinId = this.original?.skinId ?? 'white';
  }

  onPageShow(): void {
    syncDesktopNotes();
    const latest = readDesktopNote(this.params.id);
    if (latest && this.original && JSON.stringify(latest) !== JSON.stringify(this.original)) {
      this.refreshExternalNote(latest);
    }
  }

  private async refreshExternalNote(latest: Note): Promise<void> {
    if (this.title !== this.original?.title || this.originalDocument !== JSON.stringify(this.blocks) ||
      this.originalImages !== JSON.stringify(this.images)) {
      try {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '笔记已在桌面更新', message: '选择保留当前编辑，或载入桌面保存的内容。',
          buttons: [{ text: '保留当前编辑', color: $r('app.color.text_primary') },
            { text: '载入桌面版本', color: $r('app.color.accent') }]
        });
        if (choice.index === 0) {
          this.original = latest;
          return;
        }
      } catch {
        return;
      }
    }
    this.original = latest;
    this.title = latest.title;
    this.content = latest.content;
    this.blocks = latest.blocks ?? [textBlock(latest.content)];
    this.images = latest.images ?? [];
    this.skinId = latest.skinId ?? 'white';
    this.selectedGroup = latest.group;
    this.params.group = latest.group;
    this.originalDocument = JSON.stringify(this.blocks);
    this.originalImages = JSON.stringify(this.images);
    this.history = new NoteHistory(this.title, this.originalDocument);
    this.updateHistoryButtons();
  }

  private sendToDesktop(): void {
    this.menuVisible = false;
    if (!this.title.trim() && !this.content.trim() && !this.hasImages()) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写内容后再发送到桌面' });
      return;
    }
    try {
      const note = saveNote(this.params, this.title, this.content, this.skinId, this.blocks,
        this.images.filter((item: NoteImage) => this.blocks.some((block: BodyBlock) => block.imageId === item.id)));
      persistDesktopNote(note);
      refreshDesktopCards(note.id);
      this.original = note;
      this.originalDocument = JSON.stringify(this.blocks);
      this.originalImages = JSON.stringify(this.images);
      this.getUIContext().getRouter().pushUrl({ url: 'pages/NoteDesktop', params: this.params });
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: '无法保存笔记，请稍后重试' });
    }
  }

  aboutToDisappear(): void {
    clearTimeout(this.keyboardTimer);
    this.images.forEach((item: NoteImage) => {
      if (!listNotes().some((note: Note) => note.images?.some((saved: NoteImage) => saved.path === item.path))) {
        try { fs.unlinkSync(item.path); } catch {}
      }
    });
    this.shareController?.off('dismiss', this.shareDismissCallback);
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
    this.history.record(this.title, JSON.stringify(this.blocks), field);
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
    this.blocks = JSON.parse(draft.content) as BodyBlock[];
    this.content = documentText(this.blocks);
    this.selectedImage = '';
    this.updateHistoryButtons();
  }

  private hasImages(): boolean {
    return this.blocks.some((block: BodyBlock) => block.imageId !== '');
  }

  private imageItem(id: string): NoteImage {
    return this.images.find((item: NoteImage) => item.id === id) ?? {
      id: '', path: '', name: '', width: 1, height: 1, bytes: 0, caption: '', small: false
    };
  }

  private recordDocument(): void {
    this.content = documentText(this.blocks);
    this.history.closeGroup();
    this.history.record(this.title, JSON.stringify(this.blocks), 'image');
    this.history.closeGroup();
    this.updateHistoryButtons();
  }

  private async insertImage(): Promise<void> {
    if (this.pickingImage) {
      return;
    }
    this.pickingImage = true;
    this.history.closeGroup();
    const target: string = this.activeBlock;
    const offset: number = this.caret;
    let copiedPath: string = '';
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const directory: string = context.filesDir + '/note-images';
      if (!fs.accessSync(directory)) {
        fs.mkdirSync(directory, true);
      }
      const id: string = `image-${Date.now()}`;
      copiedPath = directory + '/' + id;
      const source = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(source.fd, copiedPath);
      } finally {
        fs.closeSync(source);
      }
      const file = fs.openSync(copiedPath, fs.OpenMode.READ_ONLY);
      let width: number = 1;
      let height: number = 1;
      try {
        const decoder = image.createImageSource(file.fd);
        try {
          const info = await decoder.getImageInfo();
          width = info.size.width;
          height = info.size.height;
        } finally {
          await decoder.release();
        }
      } finally {
        fs.closeSync(file);
      }
      this.images = [...this.images, {
        id: id, path: copiedPath, name: id, width: width, height: height,
        bytes: fs.statSync(copiedPath).size, caption: '', small: false
      }];
      let index: number = this.blocks.findIndex((block: BodyBlock) => block.id === target && block.imageId === '');
      if (index < 0) {
        index = this.blocks.length - 1;
      }
      const current: BodyBlock = this.blocks[index];
      const split: number = Math.max(0, Math.min(offset, current.text.length));
      const after: BodyBlock = textBlock(current.text.substring(split));
      this.blocks = [...this.blocks.slice(0, index),
        { id: current.id, text: current.text.substring(0, split), imageId: '' },
        { id: id, text: '', imageId: id }, after, ...this.blocks.slice(index + 1)];
      this.activeBlock = after.id;
      this.caret = 0;
      this.focusTarget = after.id;
      this.editing = true;
      this.recordDocument();
    } catch {
      if (copiedPath !== '') {
        try { fs.unlinkSync(copiedPath); } catch {}
      }
      this.getUIContext().getPromptAction().showToast({ message: '无法插入图片，请重新选择' });
    } finally {
      this.pickingImage = false;
    }
  }

  private imageAction(action: string, id: string): void {
    if (action === '描述') {
      this.captionDraft = this.imageItem(id).caption;
      this.captionVisible = true;
    } else if (action === '尺寸') {
      this.images = this.images.map((item: NoteImage) => item.id === id ? copyImage(item, item.caption, !item.small) : item);
    } else if (action === '详情') {
      this.zoom = 1;
      this.detailImage = id;
    } else {
      this.blocks = this.blocks.filter((block: BodyBlock) => block.imageId !== id);
      this.selectedImage = '';
      this.recordDocument();
    }
  }

  private blockText(id: string): string {
    return this.blocks.find((block: BodyBlock) => block.id === id)?.text ?? '';
  }

  private changeBlock(value: string, id: string, preview?: PreviewText): void {
    this.blocks = this.blocks.map((block: BodyBlock) => block.id === id ? { id: block.id, imageId: block.imageId, text: value } : block);
    this.content = documentText(this.blocks);
    if (preview && preview.value.length > 0) {
      return;
    }
    this.history.record(this.title, JSON.stringify(this.blocks), id);
    if (this.pastePending) {
      this.history.closeGroup();
      this.pastePending = false;
    }
    this.updateHistoryButtons();
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
          this.history.closeGroup();
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
        ForEach(this.blocks, (block: BodyBlock) => {
          if (block.imageId !== '') {
            this.ImageBlock(block)
          } else if (this.editing) {
            TextArea({ text: this.blockText(block.id), placeholder: this.blocks.length === 1 ? '正文' : '' })
              .id(block.id)
              .placeholderColor(this.skin().secondary)
              .backgroundColor(Color.Transparent).borderRadius(0)
              .fontColor(this.skin().text).fontSize(BODY_FONT_SIZE)
              .padding({ top: BODY_INPUT_VERTICAL_PADDING, bottom: BODY_INPUT_VERTICAL_PADDING, left: 0, right: 0 })
              .width('100%')
              .constraintSize({ minHeight: NAV_BUTTON_SIZE })
              .onAppear(() => {
                if (this.focusTarget === block.id ||
                  (this.focusTarget === BODY_INPUT_ID && this.activeBlock === block.id)) {
                  this.getUIContext().getFocusController().requestFocus(block.id);
                }
              })
              .onEditChange((active: boolean) => {
                if (active) {
                  this.activeBlock = block.id;
                  this.selectedImage = '';
                }
                this.inputEditingChanged(active, block.id);
              })
              .onTextSelectionChange((start: number, end: number) => {
                if (this.activeInput === block.id) {
                  this.activeBlock = block.id;
                  this.caret = end;
                }
              })
              .onPaste(() => this.preparePaste())
              .onChange((value: string, preview?: PreviewText) => this.changeBlock(value, block.id, preview))
          } else {
            Text(this.blockText(block.id) || (this.blocks.length === 1 ? '正文' : ' '))
              .fontColor(this.blockText(block.id) ? this.skin().text : this.skin().secondary)
              .fontSize(BODY_FONT_SIZE).width('100%')
              .constraintSize({ minHeight: NAV_BUTTON_SIZE })
              .onClick(() => {
                this.selectedImage = '';
                this.activeBlock = block.id;
                this.startEditing(block.id);
              })
          }
        }, (block: BodyBlock) => block.id)
        Blank().height(NAV_BUTTON_SIZE).width('100%').onClick(() => {
          this.selectedImage = '';
          const last: BodyBlock = this.blocks[this.blocks.length - 1];
          this.activeBlock = last.id;
          this.caret = last.text.length;
          this.startEditing(last.id);
        })
      }.width('100%')
    }
    .align(Alignment.TopStart).layoutWeight(1).width('100%')
    .onDidScroll(() => { this.selectedImage = ''; })
  }

  @Builder
  CaptionEditor() {
    Column() {
      Blank().layoutWeight(1).width('100%')
      Column({ space: EDITOR_PADDING }) {
        Text('图片描述').fontSize(BODY_FONT_SIZE).fontColor(this.skin().text)
        TextArea({ text: this.captionDraft, placeholder: '输入图片描述' })
          .height(120).fontColor(this.skin().text).backgroundColor(this.skin().background)
          .onChange((value: string) => { this.captionDraft = value; })
        Row() {
          Button('取消').onClick(() => { this.captionVisible = false; })
          Blank()
          Button('完成').onClick(() => {
            this.images = this.images.map((item: NoteImage) => item.id === this.selectedImage ?
              copyImage(item, this.captionDraft.trim()) : item);
            this.captionVisible = false;
          })
        }.width('100%')
      }.padding(EDITOR_PADDING).width('100%').backgroundColor(this.skin().panel)
      Blank().layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#99000000')
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
    if (this.original?.title === this.title && this.originalDocument === JSON.stringify(this.blocks) &&
      this.originalImages === JSON.stringify(this.images)) {
      return true;
    }
    if (this.title.trim().length === 0 && this.content.trim().length === 0 && !this.hasImages()) {
      if (this.original) {
        this.getUIContext().getPromptAction().showToast({ message: '请填写标题或正文' });
        return false;
      }
      return true;
    }
    try {
      saveNote(this.params, this.title, this.content, this.skinId, this.blocks,
        this.images.filter((item: NoteImage) => this.blocks.some((block: BodyBlock) => block.imageId === item.id)));
      return true;
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请稍后重试' });
      return false;
    }
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
    if (this.sharing) {
      return;
    }
    const parts: string[] = [];
    if (this.title.trim().length > 0) {
      parts.push(this.title);
    }
    if (this.content.trim().length > 0) {
      parts.push(this.content);
    }
    if (parts.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写标题或正文后再分享' });
      return;
    }
    this.sharing = true;
    try {
      const data = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: parts.join('\n\n')
      });
      this.shareController = new systemShare.ShareController(data);
      this.shareController.on('dismiss', this.shareDismissCallback);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.shareController.show(context, {});
    } catch {
      this.shareDismissCallback();
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开分享，请稍后重试' });
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
    this.skinId = id;
    changeNoteSkin(this.params.id, id);
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
      Image(resource).width(NAV_ICON_SIZE).height(NAV_ICON_SIZE).colorFilter(this.skinIconFilter())
    }
    .accessibilityText(label)
    .width(NAV_BUTTON_SIZE)
    .height(NAV_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (label === '皮肤') {
        this.skinPickerVisible = !this.skinPickerVisible && this.selectedImage === '' && this.detailImage === '';
      } else if (label === '分享') {
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
            this.history.closeGroup();
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
      .fontColor(this.skin().secondary)
  }

  @Builder
  EditorContent() {
    Column({ space: EDITOR_PADDING }) {
      this.NavigationBar()
      if (!this.editing) {
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
          .placeholderColor(this.skin().secondary)
          .backgroundColor(Color.Transparent)
          .fontColor(this.skin().text)
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .padding(0)
          .onAppear(() => this.focusInput(TITLE_INPUT_ID))
          .onEditChange((active: boolean) => this.inputEditingChanged(active, TITLE_INPUT_ID))
          .onPaste(() => this.preparePaste())
          .onChange((value: string, preview?: PreviewText) => this.changeText(value, TITLE_INPUT_ID, preview))

        this.Metadata()

        this.DocumentBody()
        this.EditTools()
      } else {
        Text(this.title.length > 0 ? this.title : '标题')
          .fontColor(this.title.length > 0 ? this.skin().text : this.skin().secondary)
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .onClick(() => this.startEditing(TITLE_INPUT_ID))

        this.Metadata()

        this.DocumentBody()
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(EDITOR_PADDING)
    .width('100%')
    .height('100%')
    .backgroundColor(isDynamicSkin(this.skin()) ? Color.Transparent : this.skin().background)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: FOLDER_GESTURE_DISTANCE })
        .onActionStart(() => {
          this.gestureStartProgress = this.folderProgress;
          this.folderGestureAllowed = !this.editing && !this.menuVisible && !this.folderPickerVisible && !this.skinPickerVisible && this.selectedImage === '' && this.detailImage === '';
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
      if (isDynamicSkin(this.skin())) {
        DynamicSkinView({ effect: this.skin().effect })
      }
      this.EditorContent()
      if (this.detailImage !== '') {
        this.ImageDetails()
      }
      if (this.captionVisible) {
        this.CaptionEditor()
      }
      if (this.skinPickerVisible) {
        Column() {
          Blank()
            .layoutWeight(1)
            .width('100%')
            .onClick(() => {
              this.skinPickerVisible = false;
            })
          Scroll() {
            Row({ space: EDITOR_PADDING }) {
              ForEach(NOTE_SKINS, (skin: NoteSkin) => {
                Button({ type: ButtonType.Normal }) {
                  Stack() {
                    if (skin.effect === 'breeze') {
                      Image($r('app.media.skin_breeze_leaf')).width(70).height(100).opacity(0.22)
                    } else if (skin.effect === 'sakura') {
                      Image($r('app.media.skin_sakura_petal')).width(54).height(54).opacity(0.55)
                    } else if (skin.effect === 'firefly') {
                      Row({ space: 8 }) {
                        Circle().width(6).height(6).fill('#F6E58C').opacity(0.9)
                        Circle().width(4).height(4).fill('#F5EFC8').opacity(0.6)
                        Circle().width(7).height(7).fill('#F6E58C').opacity(0.75)
                      }
                    }
                    Column() {
                    Text(skin.name).fontSize(BODY_FONT_SIZE).fontColor(skin.text)
                    Text('笔记预览').fontSize(META_FONT_SIZE).fontColor(skin.secondary)
                    }
                  }
                }
                .width(SKIN_CARD_WIDTH)
                .height(SKIN_CARD_HEIGHT)
                .backgroundColor(skin.background)
                .borderRadius(MENU_CORNER)
                .border({ width: 3, color: this.skinId === skin.id ? SKIN_SELECTED_COLOR : Color.Transparent })
                .accessibilityText(skin.name)
                .onClick(() => this.selectSkin(skin.id))
              })
            }
            .padding(EDITOR_PADDING)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .backgroundColor(this.skin().panel)
        }
        .width('100%')
        .height('100%')
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
          Text('移动到').fontSize(TITLE_FONT_SIZE).padding(EDITOR_PADDING)
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
