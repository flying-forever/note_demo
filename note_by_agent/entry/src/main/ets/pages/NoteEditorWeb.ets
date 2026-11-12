// 提供长文正式外壳：路由读笔记、标题输入、CodeMirror 正文与离页保存。
import { webview } from '@kit.ArkWeb';
import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText } from '../model/NoteDocument';
import { NoteEditorParams, NoteSaveResult, saveNoteDraft, snapshotNote } from '../services/NoteService';
import { loadFullNote } from '../repository/NoteRepository';
import { NoteEditorSession } from '../viewmodel/NoteEditorSession';

const HEADER_HEIGHT: number = 56;
const TITLE_FONT_SIZE: number = 20;

@Entry
@Component
struct NoteEditorWeb {
  @State private title: string = '';
  @State private ready: boolean = false;
  @State private saving: boolean = false;
  @State private status: string = '正在加载长文引擎';
  private controller: webview.WebviewController = new webview.WebviewController();
  private session: NoteEditorSession = new NoteEditorSession();
  private params: NoteEditorParams = { id: '', group: '' };
  private original?: Note;
  private blockIds: string[] = [];
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.load();
  }

  private async load(): Promise<void> {
    const note: Note | undefined = await loadFullNote(this.params.id);
    if (this.disposed) {
      return;
    }
    if (note === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '笔记不可用' });
      this.getUIContext().getRouter().back();
      return;
    }
    this.original = note;
    this.session.load(note);
    this.title = note.title;
    this.blockIds = (note.blocks ?? []).map((block: BodyBlock) => block.id);
    this.status = `已读 ${note.content.length} 字，等待长文引擎`;
  }

  private async pushText(): Promise<void> {
    if (this.original === undefined) {
      return;
    }
    const text: string = documentText(this.original.blocks ?? []);
    try {
      await this.controller.runJavaScript(`window.noteProbe.load(${JSON.stringify(text)})`);
      this.status = `长文正文已加载（${text.length} 字）`;
    } catch {
      this.status = '长文正文加载失败';
    }
  }

  private async save(): Promise<boolean> {
    if (this.saving || !this.ready) {
      return false;
    }
    this.saving = true;
    try {
      const raw: string = await this.controller.runJavaScript('window.noteProbe.getText()');
      let text: string = '';
      try {
        text = JSON.parse(raw) as string;
      } catch {
        text = raw;
      }
      const blocks: BodyBlock[] = text.split('\n').map((line: string, index: number) => {
        const id: string = this.blockIds[index] ?? `${this.params.id}:${index}`;
        return { id: id, text: line, imageId: '' } as BodyBlock;
      });
      const result: NoteSaveResult = await saveNoteDraft({
        id: this.params.id,
        group: this.params.group,
        title: this.session.title,
        blocks: blocks,
        images: this.session.images,
        skinId: this.original?.skinId ?? 'white',
        expectedSnapshot: snapshotNote(this.original)
      });
      if (result.status === 'saved' && result.note) {
        this.original = result.note;
        this.params.group = result.note.group;
        this.session.markSaved();
        this.status = '已保存';
        return true;
      }
      this.status = result.status === 'conflict' ? '笔记已在其他入口更新，请返回重试' :
        result.status === 'deleted' ? '笔记已删除' : '保存失败，内容仍留在页面';
      this.getUIContext().getPromptAction().showToast({ message: this.status });
      return false;
    } catch {
      this.status = '保存失败，内容仍留在页面';
      this.getUIContext().getPromptAction().showToast({ message: this.status });
      return false;
    } finally {
      this.saving = false;
    }
  }

  private async tryBack(): Promise<void> {
    if (await this.save()) {
      this.getUIContext().getRouter().back();
    }
  }

  onBackPress(): boolean {
    this.tryBack();
    return true;
  }

  aboutToDisappear(): void {
    this.disposed = true;
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
          })
        Text(this.saving ? '保存中…' : '长文')
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
          if (!this.ready) {
            this.ready = true;
            this.pushText();
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
  }
}
