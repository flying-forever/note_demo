import { AddFormMenuItem } from '@kit.ArkUI';
import { formBindingData } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DesktopNoteView } from '../components/DesktopNoteView';
import { NoteEditorParams } from '../model/NoteStore';
import { readDesktopNote, bindDesktopForm } from '../repository/DesktopNoteRepository';
import { desktopCardData, DesktopCardData, refreshDesktopForm } from '../platform/DesktopCards';

const PREVIEW_ID: string = 'note-desktop-preview';
const PREVIEW_SIZE: number = 180;
const PAGE_PADDING: number = 24;

@Entry
@Component
struct NoteDesktop {
  @State private data: DesktopCardData = desktopCardData();
  private noteId: string = '';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as NoteEditorParams;
    this.noteId = params.id;
    this.data = desktopCardData(readDesktopNote(this.noteId));
  }

  build() {
    Column({ space: 24 }) {
      Row() {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Blank()
      }.width('100%')
      Text('发送到桌面').fontSize(24).fontWeight(FontWeight.Bold)
      Column() {
        DesktopNoteView({ cardTitle: this.data.cardTitle, summary: this.data.summary,
          cardBackground: this.data.background, textColor: this.data.textColor, secondary: this.data.secondary })
      }.id(PREVIEW_ID).width(PREVIEW_SIZE).height(PREVIEW_SIZE).borderRadius(16).clip(true)
      Text('此笔记已保存在本机。修改后桌面卡片会同步更新。')
        .fontSize(14).fontColor($r('app.color.text_secondary'))
      Menu() {
        AddFormMenuItem({
          bundleName: 'com.example.note_by_agent', abilityName: 'NoteFormAbility',
          parameters: { 'ohos.extra.param.key.form_dimension': 2,
            'ohos.extra.param.key.form_name': 'NoteWidget',
            'ohos.extra.param.key.module_name': 'entry', noteId: this.noteId }
        }, PREVIEW_ID, {
          formBindingData: formBindingData.createFormBindingData(this.data),
          callback: (error: BusinessError, formId: string) => {
            if (!error || error.code === 0) {
              try {
                bindDesktopForm(formId, this.noteId);
                refreshDesktopForm(formId).catch(() => {});
                this.getUIContext().getPromptAction().showToast({ message: '已添加到桌面' });
              } catch {
                this.getUIContext().getPromptAction().showToast({ message: '卡片关联保存失败，请重试' });
              }
            } else {
              this.getUIContext().getPromptAction().showToast({ message: '未添加卡片，可重新尝试' });
            }
          }
        })
      }
      Blank()
    }.padding(PAGE_PADDING).width('100%').height('100%').backgroundColor($r('app.color.page_bg'))
  }
}
