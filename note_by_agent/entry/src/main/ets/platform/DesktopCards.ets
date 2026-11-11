import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Note, noteCardTitle } from '../model/Note';
import { findSkin } from '../model/NoteSkin';
import { desktopLink, readDesktopNote, listDesktopFormIds } from '../repository/DesktopNoteRepository';

export interface DesktopCardData {
  noteId: string;
  cardTitle: string;
  summary: string;
  background: string;
  textColor: string;
  secondary: string;
}

export function desktopCardData(note?: Note, deleted: boolean = false): DesktopCardData {
  const skin = findSkin(note?.skinId ?? 'white');
  return {
    noteId: note?.id ?? '',
    cardTitle: note ? noteCardTitle(note) : (deleted ? '笔记已删除' : '笔记'),
    summary: note ? (note.content.trim() || '图片笔记，点击查看') :
      (deleted ? '可移除此卡片' : '在笔记的更多菜单中发送到桌面'),
    background: skin.background, textColor: skin.text, secondary: skin.secondary
  };
}

export async function refreshDesktopForm(formId: string): Promise<void> {
  const link = desktopLink(formId);
  const note = link ? readDesktopNote(link.noteId) : undefined;
  await formProvider.updateForm(formId, formBindingData.createFormBindingData(desktopCardData(note, link !== undefined && !note)));
}

export async function refreshDesktopCards(noteId: string): Promise<void> {
  try {
    for (const id of listDesktopFormIds()) {
      try {
        if (desktopLink(id)?.noteId === noteId) {
          await refreshDesktopForm(id);
        }
      } catch {
        hilog.warn(0x0000, 'NoteDesktop', 'Desktop card refresh failed');
      }
    }
  } catch {
    hilog.warn(0x0000, 'NoteDesktop', 'Desktop card associations could not be read');
  }
}
