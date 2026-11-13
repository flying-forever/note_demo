// 提供长文正式外壳：路由读笔记、草稿恢复、标题输入、CodeMirror 正文、实时字数与块级位置。
import { webview } from '@kit.ArkWeb';
import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText, textBlock } from '../model/NoteDocument';
import { NoteEditorParams, NoteSaveResult, isBlankNote, saveNoteDraft, snapshotNote } from '../services/NoteService';
import { DraftRecord, deleteDraftRecord, findDraftForNote, saveDraftRecord } from '../repository/DraftRepository';
import { StoredPosition, loadPosition, loadStoredNote, savePosition } from '../repository/NoteSqlRepository';
import { NoteEditorSession } from '../viewmodel/NoteEditorSession';
import { mergeTextBlocks } from '../viewmodel/WebDocument';

const HEADER_HEIGHT: number = 56;
const TITLE_FONT_SIZE: number = 20;
const DRAFT_SAVE_DELAY: number = 800;
const STATS_POLL_DELAY: number = 250;

interface WebStats {
  version: number;
  length: number;
  count: number;
  lines: number;
  activeLine: number;
  editable: boolean;
}

interface WebText {
  text: string;
}

function textCount(text: string): number {
  return Array.from(text.replace(/\s/g, '')).length;
}

@Entry
@Component
struct NoteEditorWeb {
  @State private title: string = '';
  @State private ready: boolean = false;
  @State private saving: boolean = false;
  @State private charCount: number = 0;
  @State private status: string = '正在加载长文引擎';
  private controller: webview.WebviewController = new webview.WebviewController();
  private session: NoteEditorSession = new NoteEditorSession();
  private params: NoteEditorParams = { id: '', group: '' };
  private original?: Note;
  private revision: number = 0;
  private blockIds: string[] = [];
  private lineBlockIds: string[] = [];
  private initialText: string = '';
  private initialLine: number = 1;
  private activeLine: number = 1;
  private loadedLength: number = -1;
  private draftId: string = '';
  private draftCreatedAt: number = 0;
  private draftTimer: number = -1;
  private pollTimer: number = -1;
  private draftInterval: number = -1;
  private draftEpoch: number = 0;
  private lastDraftAt: number = 0;
  private lastStatsVersion: number = -1;
  private pageVisible: boolean = true;
  private pageEnded: boolean = false;
  private hasDocument: boolean = false;
  private started: boolean = false;
  private disposed: boolean = false;
  private polling: boolean = false;
  private draftSaving: boolean = false;
  private draftDisabled: boolean = false;
  private leaving: boolean = false;

  aboutToAppear(): void {
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.draftId = this.params.id;
    this.draftCreatedAt = Date.now();
    this.load();
  }

  private async load(): Promise<void> {
    const stored = await loadStoredNote(this.params.id);
    if (this.disposed) {
      return;
    }
    if (stored === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '笔记不可用' });
      this.getUIContext().getRouter().back();
      return;
    }
    const note: Note = stored.note;
    this.original = note;
    this.revision = stored.revision;
    this.session.load(note);
    this.session.baseRevision = stored.revision;
    this.title = note.title;
    this.blockIds = (note.blocks ?? []).map((block: BodyBlock) => block.id);
    this.refreshLineBlockIds();
    this.charCount = textCount(documentText(note.blocks ?? []));
    if (this.hasImages(note)) {
      this.getUIContext().getPromptAction().showToast({ message: '含图笔记暂不支持长文外壳' });
      this.getUIContext().getRouter().back();
      return;
    }
    await this.loadPosition();
    await this.resolveDraft(stored.revision);
    if (this.disposed) {
      return;
    }
    if (this.session.hasImages()) {
      this.getUIContext().getPromptAction().showToast({ message: '草稿含图片，暂不支持长文外壳' });
      this.getUIContext().getRouter().back();
      return;
    }
    await this.loadPosition();
    this.initialText = documentText(this.session.blocks);
    this.blockIds = this.session.blocks.map((block: BodyBlock) => block.id);
    this.hasDocument = true;
    this.tryStart();
  }

  private hasImages(note: Note): boolean {
    return (note.images ?? []).length > 0 || (note.blocks ?? []).some((block: BodyBlock) => block.imageId !== '');
  }

  private refreshLineBlockIds(): void {
    const ids: string[] = [];
    for (const block of this.session.blocks) {
      const count: number = block.imageId !== '' ? 1 : Math.max(1, block.text.split('\n').length);
      for (let index: number = 0; index < count; index++) {
        ids.push(block.id);
      }
    }
    this.lineBlockIds = ids;
  }

  private async loadPosition(): Promise<void> {
    try {
      const position: StoredPosition | undefined = await loadPosition(this.params.id);
      if (position === undefined) {
        return;
      }
      const id: string = position.editBlockId !== '' ? position.editBlockId : position.browseBlockId;
      const index: number = this.lineBlockIds.indexOf(id);
      if (index >= 0) {
        this.initialLine = index + 1;
        this.activeLine = this.initialLine;
      }
    } catch {
      this.initialLine = 1;
    }
  }

  private async resolveDraft(currentRevision: number): Promise<void> {
    const draft: DraftRecord | undefined = await findDraftForNote(this.params.id);
    if (draft === undefined || this.disposed) {
      return;
    }
    const stale: boolean = draft.baseRevision !== currentRevision;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: stale ? '草稿基于旧版本' : '发现未保存的草稿',
        message: stale ? '正式笔记已在其他入口更新。恢复草稿后保存会覆盖当前版本，或忽略并删除这份草稿。' :
          '可以恢复上次编辑内容，或忽略并删除这份草稿。',
        buttons: [{ text: '恢复草稿', color: $r('app.color.accent') },
          { text: '忽略并删除', color: $r('app.color.text_primary') }]
      });
      if (this.disposed) {
        return;
      }
      if (choice.index === 0) {
        this.applyDraft(draft);
      } else {
        await deleteDraftRecord(draft.draftId);
      }
    } catch {
      return;
    }
  }

  private applyDraft(draft: DraftRecord): void {
    let blocks: BodyBlock[] = [];
    let images: NoteImage[] = [];
    try {
      blocks = JSON.parse(draft.blocksJson) as BodyBlock[];
      images = JSON.parse(draft.imagesJson) as NoteImage[];
    } catch {
      return;
    }
    if (blocks.length === 0) {
      blocks = [textBlock('')];
    }
    this.draftId = draft.draftId;
    this.draftCreatedAt = draft.createdAt;
    this.session.restoreDraft(draft.title, blocks, images);
    this.session.baseRevision = draft.baseRevision;
    this.title = draft.title;
    this.blockIds = blocks.map((block: BodyBlock) => block.id);
    this.refreshLineBlockIds();
    this.initialText = documentText(blocks);
    this.charCount = textCount(this.initialText);
  }

  private async tryStart(): Promise<void> {
    if (this.started || !this.hasDocument || !this.pageEnded || this.disposed) {
      return;
    }
    this.started = true;
    try {
      await this.controller.runJavaScript(`window.noteProbe.load(${JSON.stringify(this.initialText)})`);
      const stats: WebStats = await this.readStats();
      if (stats.length !== this.initialText.length) {
        this.ready = false;
        this.started = false;
        this.status = '长文正文未就绪，请返回后重试';
        return;
      }
      this.loadedLength = stats.length;
      this.charCount = stats.count;
      this.ready = true;
      this.lastStatsVersion = -1;
      await this.controller.runJavaScript('window.noteProbe.setEditable(false)');
      await this.controller.runJavaScript(`window.noteProbe.jumpToLine(${this.initialLine})`);
      this.status = `长文正文已加载（${textCount(this.initialText)} 字），定位第 ${this.initialLine} 行`;
      this.startPolling();
    } catch {
      this.started = false;
      this.status = '长文正文加载失败';
    }
  }

  private startPolling(): void {
    this.stopPolling();
    if (!this.ready || !this.pageVisible || this.disposed) {
      return;
    }
    this.pollTimer = setInterval(() => { this.pollStats(); }, STATS_POLL_DELAY);
    if (this.draftInterval < 0) {
      this.draftInterval = setInterval(() => { this.persistDraft().catch(() => {}); }, DRAFT_SAVE_DELAY);
    }
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    if (this.draftInterval >= 0) {
      clearInterval(this.draftInterval);
      this.draftInterval = -1;
    }
  }

  private async pollStats(): Promise<void> {
    if (!this.ready || this.polling || !this.pageVisible || this.disposed) {
      return;
    }
    this.polling = true;
    try {
      const stats: WebStats = await this.readStats();
      this.charCount = stats.count;
      this.activeLine = Math.max(1, stats.activeLine);
      if (stats.version !== this.lastStatsVersion) {
        this.lastStatsVersion = stats.version;
        if (Date.now() - this.lastDraftAt >= DRAFT_SAVE_DELAY) {
          await this.persistDraft();
        } else {
          this.scheduleDraftSave();
        }
      }
    } catch {
    } finally {
      this.polling = false;
    }
  }

  private scheduleDraftSave(): void {
    if (this.disposed) {
      return;
    }
    clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => { this.persistDraft().catch(() => {}); }, DRAFT_SAVE_DELAY);
  }

  private async readStats(): Promise<WebStats> {
    const raw: string = await this.controller.runJavaScript('window.noteProbe.getStats()');
    let value: Object = JSON.parse(raw) as Object;
    if (typeof value === 'string') {
      const nested: string = value as string;
      if (nested.startsWith('{')) {
        value = JSON.parse(nested) as Object;
      }
    }
    return value as WebStats;
  }

  private async readEditorText(): Promise<string> {
    const raw: string = await this.controller.runJavaScript('window.noteProbe.getText()');
    let value: Object = JSON.parse(raw) as Object;
    if (typeof value === 'string') {
      const nested: string = value as string;
      if (nested.startsWith('{')) {
        value = JSON.parse(nested) as Object;
      }
    }
    const payload: WebText = value as WebText;
    if (typeof payload.text !== 'string') {
      throw new Error('Invalid web text payload');
    }
    return payload.text;
  }

  private applyEditorText(text: string): void {
    const blocks: BodyBlock[] = mergeTextBlocks(this.session.blocks, text.split('\n'));
    this.session.blocks = blocks;
    this.session.content = documentText(blocks);
    this.blockIds = blocks.map((block: BodyBlock) => block.id);
    this.refreshLineBlockIds();
    this.initialText = text;
  }

  private async persistDraft(): Promise<void> {
    if (!this.ready || this.disposed || this.saving || this.draftDisabled) {
      return;
    }
    if (this.draftSaving) {
      this.scheduleDraftSave();
      return;
    }
    this.draftSaving = true;
    const epoch: number = this.draftEpoch;
    try {
      const text: string = await this.readEditorText();
      this.applyEditorText(text);
      const blocks: BodyBlock[] = this.session.blocks;
      if (!this.session.isDirty()) {
        await deleteDraftRecord(this.draftId);
        return;
      }
      if (isBlankNote(this.session.title, blocks)) {
        await deleteDraftRecord(this.draftId);
        return;
      }
      const draft: DraftRecord = {
        draftId: this.draftId,
        noteId: this.params.id,
        groupName: this.params.group,
        baseRevision: this.session.baseRevision,
        title: this.session.title,
        blocksJson: JSON.stringify(blocks),
        imagesJson: JSON.stringify(this.session.images),
        createdAt: this.draftCreatedAt,
        updatedAt: Date.now()
      };
      if (epoch !== this.draftEpoch || this.saving || this.draftDisabled) {
        return;
      }
      await saveDraftRecord(draft);
      if (epoch !== this.draftEpoch || this.draftDisabled) {
        await deleteDraftRecord(this.draftId);
        return;
      }
      this.lastDraftAt = Date.now();
    } catch {
    } finally {
      this.draftSaving = false;
    }
  }

  private async flushDraft(): Promise<void> {
    clearTimeout(this.draftTimer);
    await this.persistDraft();
  }

  private async save(): Promise<boolean> {
    if (this.saving || !this.ready) {
      return false;
    }
    this.saving = true;
    this.draftDisabled = true;
    this.draftEpoch++;
    let saved: boolean = false;
    try {
      const stats: WebStats = await this.readStats();
      this.charCount = stats.count;
      this.activeLine = Math.max(1, stats.activeLine);
      const text: string = await this.readEditorText();
      if (this.loadedLength > 0 && text.length === 0 && !this.session.isDirty()) {
        this.status = '正文未加载，不能保存';
        return false;
      }
      this.applyEditorText(text);
      const blocks: BodyBlock[] = this.session.blocks;
      if (!this.session.isDirty()) {
        await deleteDraftRecord(this.draftId);
        await this.saveCurrentPosition();
        return true;
      }
      const result: NoteSaveResult = await saveNoteDraft({
        id: this.params.id,
        group: this.params.group,
        title: this.session.title,
        blocks: blocks,
        images: this.session.referencedImages(),
        skinId: this.original?.skinId ?? 'white',
        expectedSnapshot: snapshotNote(this.original),
        textOnly: true
      });
      if (result.status === 'saved' && result.note) {
        this.original = result.note;
        this.params.group = result.note.group;
        this.session.blocks = result.note.blocks ?? blocks;
        this.session.content = documentText(this.session.blocks);
        this.session.markSaved();
        this.blockIds = this.session.blocks.map((block: BodyBlock) => block.id);
        this.refreshLineBlockIds();
        this.charCount = textCount(this.session.content);
        this.draftEpoch++;
        await deleteDraftRecord(this.draftId);
        await this.refreshRevision();
        this.session.baseRevision = this.revision;
        await this.saveCurrentPosition();
        this.status = '已保存';
        saved = true;
        return true;
      }
      this.status = result.status === 'conflict' ? '笔记已在其他入口更新，请返回重试' :
        result.status === 'deleted' ? '笔记已删除' :
        result.status === 'unsupported' ? '含图笔记暂不支持长文外壳' :
        result.status === 'empty' ? '标题和正文不能同时为空' : '保存失败，内容仍留在页面';
      this.getUIContext().getPromptAction().showToast({ message: this.status });
      return false;
    } catch {
      this.status = '保存失败，内容仍留在页面';
      this.getUIContext().getPromptAction().showToast({ message: this.status });
      return false;
    } finally {
      this.saving = false;
      if (!saved) {
        this.draftDisabled = false;
      }
    }
  }

  private async refreshRevision(): Promise<void> {
    try {
      const stored = await loadStoredNote(this.params.id);
      if (stored !== undefined) {
        this.revision = stored.revision;
      }
    } catch {
    }
  }

  private async saveCurrentPosition(): Promise<void> {
    if (this.lineBlockIds.length === 0) {
      return;
    }
    const index: number = Math.max(0, Math.min(this.activeLine - 1, this.lineBlockIds.length - 1));
    const blockId: string = this.lineBlockIds[index];
    if (blockId === '') {
      return;
    }
    try {
      await savePosition({ noteId: this.params.id, revision: this.revision, editBlockId: blockId,
        editOffset: 0, browseBlockId: '', browseOffset: 0 });
    } catch {
    }
  }

  private async history(redo: boolean): Promise<void> {
    if (!this.ready || this.disposed) {
      return;
    }
    try {
      await this.controller.runJavaScript(`window.noteProbe.${redo ? 'redoLast' : 'undoLast'}()`);
    } catch {
    }
  }

  private async tryBack(): Promise<void> {
    if (this.leaving) {
      return;
    }
    if (!this.ready) {
      this.getUIContext().getRouter().back();
      return;
    }
    this.leaving = true;
    try {
      while (!this.disposed) {
        if (await this.save()) {
          this.getUIContext().getRouter().back();
          return;
        }
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: '保存失败',
          message: this.status,
          buttons: [{ text: '重试', color: $r('app.color.accent') },
            { text: '保留草稿并离开', color: $r('app.color.text_primary') }]
        });
        if (this.disposed) {
          return;
        }
        if (choice.index === 1) {
          await this.flushDraft().catch(() => {});
          this.getUIContext().getRouter().back();
          return;
        }
      }
    } catch {
      return;
    } finally {
      this.leaving = false;
    }
  }

  onBackPress(): boolean {
    this.tryBack();
    return true;
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.startPolling();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.stopPolling();
    this.flushDraft().catch(() => {});
    this.saveCurrentPosition().catch(() => {});
  }

  aboutToDisappear(): void {
    this.stopPolling();
    clearTimeout(this.draftTimer);
    this.flushDraft().catch(() => {}).finally(() => { this.disposed = true; });
  }

  private countLabel(): string {
    return `${this.charCount ?? 0}字`;
  }

  build() {
    Column() {
      Row() {
        Button('←')
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => { this.tryBack(); })
        TextInput({ text: this.title, placeholder: '标题' })
          .layoutWeight(1)
          .height(44)
          .fontSize(TITLE_FONT_SIZE)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.title = value;
            this.session.changeTitle(value, false);
            this.scheduleDraftSave();
          })
        Button('↶')
          .width(36)
          .height(44)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.history(false); })
        Button('↷')
          .width(36)
          .height(44)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.history(true); })
        Text(this.saving ? '保存中…' : this.countLabel())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(HEADER_HEIGHT)
      .padding({ left: 8, right: 16 })

      Text(this.status)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .height(20)
        .width('100%')
        .padding({ left: 16, right: 16 })

      Web({ src: $rawfile('web-editor-shell/index.html'), controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .onPageEnd(() => {
          this.pageEnded = true;
          this.tryStart();
        })
        .onRenderExited(() => {
          this.ready = false;
          this.started = false;
          this.stopPolling();
          this.status = '长文引擎已重载，正在保存草稿';
          this.flushDraft().catch(() => {}).finally(() => {
            try {
              this.controller.refresh();
            } catch {
            }
          });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
  }
}
