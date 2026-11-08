import { listDesktopRecords, readDesktopRecord, persistDesktopNote, deleteDesktopNote, refreshDesktopCards } from './DesktopNoteRepository';
import { BodyBlock, NoteImage } from './NoteDocument';
import { FAKE_NOTES, Note } from './Note';

export interface NoteEditorParams {
  id: string;
  group: string;
}

let notes: Note[] = FAKE_NOTES.slice();
let nextId: number = 1;

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

function persistIfDesktop(note: Note): Note {
  if (readDesktopRecord(note.id)) {
    persistDesktopNote(note);
    refreshDesktopCards(note.id);
  }
  return note;
}

export function listNotes(): Note[] {
  return notes;
}

export function findNote(id: string): Note | undefined {
  return notes.find((note: Note) => note.id === id);
}

export function deleteNote(id: string): void {
  deleteDesktopNote(id);
  notes = notes.filter((note: Note) => note.id !== id);
  refreshDesktopCards(id);
}

export function moveNote(id: string, group: string): void {
  notes = notes.map((note: Note) => {
    if (note.id !== id) {
      return note;
    }
    return persistIfDesktop({ id: note.id, title: note.title, content: note.content, timeLabel: note.timeLabel, group: group, skinId: note.skinId, blocks: note.blocks, images: note.images });
  });
}

export function changeNoteSkin(id: string, skinId: string): void {
  notes = notes.map((note: Note) => {
    if (note.id !== id) {
      return note;
    }
    return persistIfDesktop({ id: note.id, title: note.title, content: note.content, timeLabel: note.timeLabel, group: note.group, skinId: skinId, blocks: note.blocks, images: note.images });
  });
}

export function saveNote(params: NoteEditorParams, title: string, content: string, skinId?: string, blocks?: BodyBlock[], images?: NoteImage[]): Note {
  const original: Note | undefined = findNote(params.id);
  const now: Date = new Date();
  const hours: string = now.getHours().toString().padStart(2, '0');
  const minutes: string = now.getMinutes().toString().padStart(2, '0');
  const note: Note = {
    id: original?.id ?? `new-${Date.now()}-${nextId++}`,
    group: original?.group ?? params.group,
    blocks: blocks,
    images: images,
    title: title,
    content: content,
    skinId: skinId ?? original?.skinId ?? 'white',
    timeLabel: `${now.getMonth() + 1}月${now.getDate()}日 ${hours}:${minutes}`
  };
  persistIfDesktop(note);
  notes = [note, ...notes.filter((item: Note) => item.id !== note.id)];
  params.id = note.id;
  return note;
}
