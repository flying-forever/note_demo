import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { initializeDesktopRepository, bindDesktopForm, readDesktopNote, desktopCardData,
  desktopLink, refreshDesktopForm, removeDesktopForm } from '../model/DesktopNoteRepository';

export default class NoteFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    initializeDesktopRepository(this.context.filesDir);
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    const noteId = want.parameters?.['noteId'] as string;
    if (formId && noteId && readDesktopNote(noteId)) {
      bindDesktopForm(formId, noteId);
    }
    const link = formId ? desktopLink(formId) : undefined;
    const note = link ? readDesktopNote(link.noteId) : undefined;
    return formBindingData.createFormBindingData(desktopCardData(note, link !== undefined && !note));
  }

  onUpdateForm(formId: string): void {
    initializeDesktopRepository(this.context.filesDir);
    refreshDesktopForm(formId).catch(() => {});
  }

  onRemoveForm(formId: string): void {
    initializeDesktopRepository(this.context.filesDir);
    removeDesktopForm(formId);
  }
}
