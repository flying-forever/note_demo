// 创建桌面卡片编辑会话，并装载编辑页与预览数据。
import { createDesktopEditStorage } from '../model/DesktopEditStorage';
import { FormEditExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { initializeDesktopRepository, desktopLink, readDesktopNote } from '../repository/DesktopNoteRepository';
import { desktopCardData } from '../platform/DesktopCards';

export default class NoteFormEditAbility extends FormEditExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    initializeDesktopRepository(this.context.filesDir);
    const storage = createDesktopEditStorage(want.parameters?.['cardId'] as string ?? '',
      want.parameters?.['previewCardId'] as string ?? '', session);
    session.loadContent('pages/DesktopNoteEdit', storage);
    const formId = storage.get<string>('formId') ?? '';
    const previewId = storage.get<string>('previewFormId') ?? '';
    try {
      const link = desktopLink(formId);
      const note = link ? readDesktopNote(link.noteId) : undefined;
      if (previewId && note) {
        formProvider.updateForm(previewId, formBindingData.createFormBindingData(desktopCardData(note))).catch(() => {});
      }
    } catch {}
  }
}
