import { desktopEditStorage } from '../model/DesktopEditStorage';
import { FormEditExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { initializeDesktopRepository, desktopLink, readDesktopNote, desktopCardData } from '../model/DesktopNoteRepository';

export default class NoteFormEditAbility extends FormEditExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    initializeDesktopRepository(this.context.filesDir);
    const storage = desktopEditStorage;
    storage.setOrCreate('formId', want.parameters?.['cardId'] as string ?? '');
    storage.setOrCreate('previewFormId', want.parameters?.['previewCardId'] as string ?? '');
    storage.setOrCreate('editSession', session);
    session.loadContent('pages/DesktopNoteEdit', storage);
    const formId = storage.get<string>('formId') ?? '';
    const previewId = storage.get<string>('previewFormId') ?? '';
    const link = desktopLink(formId);
    const note = link ? readDesktopNote(link.noteId) : undefined;
    if (previewId && note) {
      formProvider.updateForm(previewId, formBindingData.createFormBindingData(desktopCardData(note))).catch(() => {});
    }
  }
}
