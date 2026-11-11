import { UIExtensionContentSession } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BodyBlock, textBlock } from '../model/NoteDocument';
import { Note } from '../model/Note';
import { desktopLink, readDesktopNote } from '../repository/DesktopNoteRepository';
import { desktopCardData } from '../platform/DesktopCards';
import { saveNoteDraft, snapshotNote } from '../services/NoteService';

const EDIT_PADDING: number = 12;
const EDIT_FONT_SIZE: number = 16;
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
  private original?: Note;
  private originalSnapshot: string = '';
  private previewTimer: number = -1;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.session = this.getUIContext().getSharedLocalStorage()?.get<UIExtensionContentSession>('editSession');
    try {
      const link = desktopLink(this.formId);
      this.original = link ? readDesktopNote(link.noteId) : undefined;
    } catch {
      this.original = undefined;
    }
    this.originalSnapshot = snapshotNote(this.original);
    this.title = this.original?.title ?? '';
    this.blocks = this.original?.blocks ?? [textBlock(this.original?.content ?? '')];
    this.available = this.original !== undefined;
    this.status = this.available ? '' : '笔记不可用，请从应用内重新发送到桌面';
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
        if (!this.disposed && this.status === '' && attempt === PREVIEW_REFRESH_ATTEMPTS - 1) {
          this.status = '预览暂未更新，保存时将重新刷新';
        }
      }
      if (!this.disposed && attempt < PREVIEW_REFRESH_ATTEMPTS - 1) {
        this.previewTimer = setTimeout(() => this.refreshPreview(attempt + 1), PREVIEW_REFRESH_DELAY * (attempt + 1));
      }
    }
  }

  private async close(): Promise<void> {
    try { await this.session?.terminateSelf(); } catch {}
  }

  private async save(): Promise<void> {
    const original = this.original;
    if (!original || this.saving) {
      return;
    }
    this.saving = true;
    clearTimeout(this.previewTimer);
    try {
      const result = saveNoteDraft({ id: original.id, group: original.group, title: this.title,
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
    } finally {
      if (!this.disposed) {
        this.saving = false;
      }
    }
  }

  build() {
    Column({ space: EDIT_PADDING }) {
      Row() {
        Button('取消').onClick(() => this.close())
        Blank()
        Button('保存').enabled(this.available && !this.saving).onClick(() => this.save())
      }.width('100%')
      if (this.available) {
        Text('修改后请先点“保存”，再点系统“完成”；直接关闭不会保存。')
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        TextInput({ text: this.title, placeholder: '标题' })
          .id('desktop-edit-title').fontSize(EDIT_FONT_SIZE)
          .onChange((value: string) => {
            this.title = value;
            this.status = '尚未保存，请点击“保存”';
          })
        Scroll() {
          Column({ space: EDIT_PADDING }) {
            ForEach(this.blocks, (block: BodyBlock) => {
              if (block.imageId === '') {
                TextArea({ text: this.blockText(block.id), placeholder: '正文' })
                  .id('desktop-edit-' + block.id).fontSize(EDIT_FONT_SIZE).width('100%')
                  .constraintSize({ minHeight: 72 })
                  .onChange((value: string) => {
                    this.blocks = this.blocks.map((item: BodyBlock) => item.id === block.id ?
                      { id: item.id, text: value, imageId: '' } : item);
                    this.status = '尚未保存，请点击“保存”';
                  })
              } else {
                Text('图片已保留').fontSize(12).fontColor($r('app.color.text_secondary'))
              }
            }, (block: BodyBlock) => block.id)
          }.width('100%')
        }.layoutWeight(1).width('100%')
      }
      if (this.status !== '') {
        Text(this.status).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }.padding(EDIT_PADDING).width('100%').height('100%').backgroundColor(Color.White)
    .onAppear(() => this.refreshPreview())
  }
}
