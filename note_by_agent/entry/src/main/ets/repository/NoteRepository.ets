// 管理内存笔记列表，并同步和选择性持久化桌面笔记。
import { FAKE_NOTES, Note } from '../model/Note';
import { listDesktopRecords, readDesktopRecord, persistDesktopNote, deleteDesktopNote } from './DesktopNoteRepository';

let notes: Note[] = FAKE_NOTES.slice();

export function syncDesktopNotes(): void {
  const records = listDesktopRecords();
  const restored: Note[] = [];
  records.forEach((record) => {
    if (!record.deleted && record.note) {
      restored.push(record.note);
    }
  });
  notes = [...restored, ...notes.filter((note: Note) => !records.some((record) => record.id === note.id))];
}

export function listNotes(): Note[] {
  return notes;
}

export function findNote(id: string): Note | undefined {
  return notes.find((note: Note) => note.id === id);
}

export function commitNote(note: Note, persistToDesktop: boolean = false, reorder: boolean = true): void {
  if (persistToDesktop || readDesktopRecord(note.id)) {
    persistDesktopNote(note);
  }
  notes = reorder ? [note, ...notes.filter((item: Note) => item.id !== note.id)] :
    notes.map((item: Note) => item.id === note.id ? note : item);
}

export function removeNote(id: string): void {
  deleteDesktopNote(id);
  notes = notes.filter((note: Note) => note.id !== id);
}
