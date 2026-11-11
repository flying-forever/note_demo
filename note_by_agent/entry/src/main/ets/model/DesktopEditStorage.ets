// 为桌面编辑页封装卡片标识、预览标识与扩展会话的共享存储。
import { UIExtensionContentSession } from '@kit.AbilityKit';

export function createDesktopEditStorage(formId: string, previewFormId: string,
  session: UIExtensionContentSession): LocalStorage {
  const storage = new LocalStorage();
  storage.setOrCreate('formId', formId);
  storage.setOrCreate('previewFormId', previewFormId);
  storage.setOrCreate('editSession', session);
  return storage;
}
