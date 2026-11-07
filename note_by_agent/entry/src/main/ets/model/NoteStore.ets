import { FAKE_NOTES, Note } from './Note';

export interface NoteEditorParams {
  id: string;
  group: string;
}

let notes: Note[] = FAKE_NOTES.slice();
let nextId: number = 1;

export function listNotes(): Note[] {
  return notes;
}

export function findNote(id: string): Note | undefined {
  return notes.find((note: Note) => note.id === id);
}

export function deleteNote(id: string): void {
  notes = notes.filter((note: Note) => note.id !== id);
}

export function moveNote(id: string, group: string): void {
  notes = notes.map((note: Note) => {
    if (note.id !== id) {
      return note;
    }
    return { id: note.id, title: note.title, content: note.content, timeLabel: note.timeLabel, group: group, skinId: note.skinId };
  });
}

export function changeNoteSkin(id: string, skinId: string): void {
  notes = notes.map((note: Note) => {
    if (note.id !== id) {
      return note;
    }
    return { id: note.id, title: note.title, content: note.content, timeLabel: note.timeLabel, group: note.group, skinId: skinId };
  });
}

export function saveNote(params: NoteEditorParams, title: string, content: string, skinId?: string): void {
  const original: Note | undefined = findNote(params.id);
  const now: Date = new Date();
  const hours: string = now.getHours().toString().padStart(2, '0');
  const minutes: string = now.getMinutes().toString().padStart(2, '0');
  const note: Note = {
    id: original?.id ?? `new-${nextId++}`,
    group: original?.group ?? params.group,
    title: title,
    content: content,
    skinId: skinId ?? original?.skinId ?? 'white',
    timeLabel: `${now.getMonth() + 1}月${now.getDate()}日 ${hours}:${minutes}`
  };
  notes = [note, ...notes.filter((item: Note) => item.id !== note.id)];
}
