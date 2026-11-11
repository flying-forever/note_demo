// 从启动参数或卡片绑定关系解析需要打开的笔记标识。
import { Want } from '@kit.AbilityKit';
import { formInfo } from '@kit.FormKit';
import { desktopLink } from '../repository/DesktopNoteRepository';

export function desktopLaunchNoteId(want: Want): string {
  const noteId = want.parameters?.['noteId'];
  if (typeof noteId === 'string' && noteId !== '') {
    return noteId;
  }
  const serialized = want.parameters?.['params'];
  if (typeof serialized === 'string') {
    try {
      const parameters = JSON.parse(serialized) as Record<string, string>;
      if (typeof parameters.noteId === 'string' && parameters.noteId !== '') {
        return parameters.noteId;
      }
    } catch {
    }
  }
  const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
  return formId === undefined ? '' : (desktopLink(String(formId))?.noteId ?? '');
}
