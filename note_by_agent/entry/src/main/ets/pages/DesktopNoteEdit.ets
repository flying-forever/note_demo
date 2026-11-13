// 在桌面卡片扩展会话中编辑笔记，校验保存冲突并刷新预览。
import { UIExtensionContentSession } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BodyBlock, textBlock } from '../model/NoteDocument';
import { Note } from '../model/Note';
import { NoteSkin, findSkin } from '../model/NoteSkin';
import { openNoteDatabase } from '../repository/NoteDatabase';
import { loadStoredNote, setNoteFilesDir } from '../repository/NoteSqlRepository';
import { desktopLink, readDesktopNote } from '../repository/DesktopNoteRepository';
import { desktopCardData } from '../platform/DesktopCards';
import { saveNoteDraft, snapshotNote } from '../services/NoteService';

const EDIT_PADDING: number = 8;
const EDIT_FONT_SIZE: number = 16;
const EDIT_RADIUS: number = 20;
const EDIT_INNER_RADIUS: number = 14;
const EDIT_BUTTON_HEIGHT: number = 32;
const EDIT_BODY_MIN_HEIGHT: number = 120;
const EDIT_HINT: string = '系统“完成”不保存，请点“保存并结束编辑”';
const PREVIEW_REFRESH_DELAY: number = 300;
const PREVIEW_REFRESH_ATTEMPTS: number = 3;

@Entry({ useSharedStorage: true })
@Component
struct DesktopNoteEdit {
  @LocalStorageProp('formId') private formId: string = '';
  @LocalStorageProp('previewFormId') private previewFormId: string = '';
  private session?: UIExtensionContentSession;
  @State private title: string = '';
  @State private blocks: BodyBlock[] = [];
  @State private available: boolean = false;
  @State private saving: boolean = false;
  @State private status: string = '';
  @State private skin: NoteSkin = findSkin('white');
  private original?: Note;
  private originalSnapshot: string = '';
  private previewTimer: number = -1;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.session = this.getUIContext().getSharedLocalStorage()?.get<UIExtensionContentSession>('editSession');
    this.loadOriginal();
  }

  private async loadOriginal(): Promise<void> {
    const link = desktopLink(this.formId);
    let note: Note | undefined = undefined;
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      if (context) {
        setNoteFilesDir(context.filesDir);
        await openNoteDatabase(context);
      }
      if (link) {
        const stored = await loadStoredNote(link.noteId);
        note = stored?.note;
      }
    } catch {}
    if (!note && link) {
      try {
        note = readDesktopNote(link.noteId);
      } catch {
        note = undefined;
      }
    }
    if (this.disposed) {
      return;
    }
    this.original = note;
    this.originalSnapshot = snapshotNote(this.original);
    this.title = this.original?.title ?? '';
    this.blocks = this.original?.blocks ?? [textBlock(this.original?.content ?? '')];
    this.available = this.original !== undefined;
    this.skin = findSkin(this.original?.skinId ?? 'white');
    this.status = this.available ? EDIT_HINT : '笔记不可用，请从应用内重新发送到桌面';
  }

  private blockText(id: string): string {
    return this.blocks.find((block: BodyBlock) => block.id === id)?.text ?? '';
  }

  aboutToDisappear(): void {
    this.disposed = true;
    clearTimeout(this.previewTimer);
  }

  private async refreshPreview(attempt: number = 0): Promise<void> {
    if (this.previewFormId && this.original) {
      try {
        await formProvider.updateForm(this.previewFormId,
          formBindingData.createFormBindingData(desktopCardData(this.original)));
      } catch {
        if (!this.disposed && this.status === EDIT_HINT && attempt === PREVIEW_REFRESH_ATTEMPTS - 1) {
          this.status = '预览暂未更新，保存时将重新刷新';
        }
      }
      if (!this.disposed && attempt < PREVIEW_REFRESH_ATTEMPTS - 1) {
        this.previewTimer = setTimeout(() => this.refreshPreview(attempt + 1), PREVIEW_REFRESH_DELAY * (attempt + 1));
      }
    }
  }

  private async close(): Promise<void> {
    try {
      if (!this.session) {
        this.status = '无法关闭，请点系统“完成”退出';
        return;
      }
      await this.session.terminateSelf();
    } catch {
      this.status = '无法关闭，请点系统“完成”退出';
    }
  }

  private async save(): Promise<void> {
    const original = this.original;
    if (!original || this.saving) {
      return;
    }
    this.saving = true;
    clearTimeout(this.previewTimer);
    try {
      const result = await saveNoteDraft({ id: original.id, group: original.group, title: this.title,
        blocks: this.blocks, images: original.images ?? [], skinId: original.skinId,
        expectedSnapshot: this.originalSnapshot });
      if (result.status !== 'saved' || !result.note) {
        this.status = result.status === 'empty' ? '请填写标题或正文' :
          (result.status === 'conflict' ? '笔记已更新，请关闭后重新编辑' :
            (result.status === 'deleted' ? '笔记已删除，请关闭编辑' : '保存失败，请重试'));
        return;
      }
      const note = result.note;
      this.original = note;
      this.originalSnapshot = snapshotNote(note);
      this.status = '已保存';
      if (this.previewFormId) {
        try {
          await formProvider.updateForm(this.previewFormId, formBindingData.createFormBindingData(desktopCardData(note)));
        } catch {
          if (!this.disposed && this.status === '已保存') {
            this.status = '已保存，预览暂未更新';
          }
        }
      }
      await this.close();
    } finally {
      if (!this.disposed) {
        this.saving = false;
      }
    }
  }

  @Builder
  private bodyEditor(block: BodyBlock) {
    TextArea({ text: this.blockText(block.id), placeholder: '正文' })
      .id('desktop-edit-' + block.id).fontSize(EDIT_FONT_SIZE).fontColor(this.skin.text)
      .placeholderColor(this.skin.secondary).backgroundColor(this.skin.background)
      .borderRadius(EDIT_INNER_RADIUS).padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .width('100%').constraintSize({ minHeight: this.blocks.length === 1 ? 0 : EDIT_BODY_MIN_HEIGHT })
      .layoutWeight(this.blocks.length === 1 ? 1 : 0)
      .enabled(!this.saving)
      .onChange((value: string) => {
        this.blocks = this.blocks.map((item: BodyBlock) => item.id === block.id ?
          { id: item.id, text: value, imageId: '' } : item);
        this.status = EDIT_HINT;
      })
  }

  build() {
    Column({ space: EDIT_PADDING }) {
      Row() {
        Button('取消').height(EDIT_BUTTON_HEIGHT).fontSize(14)
          .fontColor(this.skin.secondary).backgroundColor(this.skin.panel)
          .borderRadius(EDIT_INNER_RADIUS).enabled(!this.saving).onClick(() => this.close())
        Blank()
        Button(this.saving ? '保存中' : '保存并结束编辑').height(EDIT_BUTTON_HEIGHT).fontSize(14)
          .fontColor(this.skin.background).backgroundColor(this.skin.text).borderRadius(EDIT_INNER_RADIUS)
          .enabled(this.available && !this.saving).onClick(() => this.save())
      }.width('100%')
      if (this.available) {
        Column() {
          TextInput({ text: this.title, placeholder: '标题' })
            .id('desktop-edit-title').fontSize(18).fontWeight(FontWeight.Medium).height(44)
            .fontColor(this.skin.text).placeholderColor(this.skin.secondary)
            .backgroundColor(this.skin.background).borderRadius(EDIT_INNER_RADIUS)
            .padding({ left: 12, right: 12 })
            .enabled(!this.saving)
            .onChange((value: string) => {
              this.title = value;
              this.status = EDIT_HINT;
            })
          if (this.blocks.length === 1 && this.blocks[0].imageId === '') {
            this.bodyEditor(this.blocks[0])
          } else {
            Scroll() {
              Column({ space: EDIT_PADDING }) {
                ForEach(this.blocks, (block: BodyBlock) => {
                  if (block.imageId === '') {
                    this.bodyEditor(block)
                  } else {
                    Text('图片已保留').fontSize(12).fontColor(this.skin.secondary)
                      .width('100%').padding(EDIT_PADDING).backgroundColor(this.skin.panel)
                      .borderRadius(EDIT_INNER_RADIUS)
                  }
                }, (block: BodyBlock) => block.id)
              }.width('100%')
            }.layoutWeight(1).width('100%').borderRadius(EDIT_INNER_RADIUS).clip(true)
          }
        }.layoutWeight(1).width('100%').backgroundColor(this.skin.background)
        .borderRadius(EDIT_INNER_RADIUS).clip(true)
      }
      if (this.status !== '') {
        Text(this.status).fontSize(11).fontColor(this.skin.secondary).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 4, right: 4 })
      }
    }.padding(EDIT_PADDING).width('100%').height('100%').backgroundColor(this.skin.panel)
    .borderRadius(EDIT_RADIUS).clip(true).onAppear(() => this.refreshPreview())
  }
}
