import { DesktopNoteView } from '../../components/DesktopNoteView';

const widgetStorage: LocalStorage = new LocalStorage();

@Entry(widgetStorage)
@Component
struct NoteWidget {
  @LocalStorageProp('noteId') noteId: string = '';
  @LocalStorageProp('cardTitle') cardTitle: string = '笔记';
  @LocalStorageProp('summary') summary: string = '在笔记的更多菜单中发送到桌面';
  @LocalStorageProp('background') cardBackground: string = '#FFFFFF';
  @LocalStorageProp('textColor') textColor: string = '#1A1A1A';
  @LocalStorageProp('secondary') secondary: string = '#777777';

  build() {
    Column() {
      DesktopNoteView({ cardTitle: this.cardTitle, summary: this.summary, cardBackground: this.cardBackground,
        textColor: this.textColor, secondary: this.secondary })
    }.width('100%').height('100%')
    .onClick(() => {
      postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { noteId: this.noteId } });
    })
  }
}
