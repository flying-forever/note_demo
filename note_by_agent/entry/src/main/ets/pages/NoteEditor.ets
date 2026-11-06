import { Note } from '../model/Note';
import { findNote, NoteEditorParams, saveNote } from '../model/NoteStore';

const EDITOR_PADDING: number = 16;
const TITLE_FONT_SIZE: number = 26;
const BODY_FONT_SIZE: number = 17;
const BODY_INPUT_VERTICAL_PADDING: number = 6;
const META_FONT_SIZE: number = 13;
const NAV_ICON_SIZE: number = 24;
const TITLE_INPUT_ID: string = 'note-editor-title';
const BODY_INPUT_ID: string = 'note-editor-body';

@Entry
@Component
struct NoteEditor {
  @State private title: string = '';
  @State private content: string = '';
  @State private editing: boolean = false;
  private focusTarget: string = BODY_INPUT_ID;
  private params: NoteEditorParams = { id: '', group: '' };
  private original?: Note;

  aboutToAppear(): void {
    this.params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.original = findNote(this.params.id);
    this.title = this.original?.title ?? '';
    this.content = this.original?.content ?? '';
    this.editing = this.original === undefined;
  }

  private startEditing(target: string): void {
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
    return !this.saveBeforeLeaving();
  }

  @Builder
  NavigationBar() {
    Row() {
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
        Button('✓', { type: ButtonType.Normal })
          .fontSize(NAV_ICON_SIZE)
          .accessibilityText('结束编辑')
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.getUIContext().getFocusController().clearFocus();
            this.editing = false;
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

  build() {
    Column({ space: EDITOR_PADDING }) {
      this.NavigationBar()
      if (this.editing) {
        TextInput({ text: this.title, placeholder: '标题' })
          .id(TITLE_INPUT_ID)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .padding(0)
          .onAppear(() => this.focusInput(TITLE_INPUT_ID))
          .onChange((value: string) => {
            this.title = value;
          })

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
          .onChange((value: string) => {
            this.content = value;
          })
      } else {
        Text(this.title.length > 0 ? this.title : '标题')
          .fontColor(this.title.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .fontSize(TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .onClick(() => this.startEditing(TITLE_INPUT_ID))

        this.Metadata()

        Scroll() {
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
  }
}
