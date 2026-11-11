import { UIExtensionContentSession } from '@kit.AbilityKit';

export function createDesktopEditStorage(formId: string, previewFormId: string,
  session: UIExtensionContentSession): LocalStorage {
  const storage = new LocalStorage();
  storage.setOrCreate('formId', formId);
  storage.setOrCreate('previewFormId', previewFormId);
  storage.setOrCreate('editSession', session);
  return storage;
}
