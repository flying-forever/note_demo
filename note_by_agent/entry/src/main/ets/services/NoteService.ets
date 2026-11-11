import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText, textBlock, copyImage } from '../model/NoteDocument';
import { findNote, commitNote, removeNote } from '../repository/NoteRepository';
import { readDesktopRecord } from '../repository/DesktopNoteRepository';
import { refreshDesktopCards } from '../platform/DesktopCards';

export interface NoteEditorParams {
  id: string;
  group: string;
}

export interface NoteSaveRequest {
  id: string;
  group: string;
  title: string;
  blocks: BodyBlock[];
  images: NoteImage[];
  skinId?: string;
  expectedSnapshot?: string;
  persistToDesktop?: boolean;
}

export interface NoteSaveResult {
  status: string;
  note?: Note;
}

let nextId: number = 1;

export function snapshotNote(note?: Note): string {
  if (!note) {
    return '';
  }
  const value: Note = { id: note.id, title: note.title, content: note.content, timeLabel: note.timeLabel,
    group: note.group, skinId: note.skinId, blocks: note.blocks, images: note.images };
  return JSON.stringify(value);
}

export function isBlankNote(title: string, blocks: BodyBlock[]): boolean {
  return !title.trim() && !documentText(blocks).trim() && !blocks.some((block: BodyBlock) => block.imageId !== '');
}

function currentNote(id: string): NoteSaveResult {
  const record = readDesktopRecord(id);
  if (record?.deleted) {
    return { status: 'deleted' };
  }
  const note = record?.note ?? findNote(id);
  return note ? { status: 'saved', note: note } : { status: 'deleted' };
}

export function saveNoteDraft(request: NoteSaveRequest): NoteSaveResult {
  try {
    let original: Note | undefined;
    if (request.id !== '') {
      const current = currentNote(request.id);
      if (current.status !== 'saved') {
        return current;
      }
      original = current.note;
      const expected = request.expectedSnapshot ?? snapshotNote(findNote(request.id));
      if (snapshotNote(original) !== expected) {
        return { status: 'conflict' };
      }
    }
    if (isBlankNote(request.title, request.blocks)) {
      return { status: 'empty' };
    }
    const now = new Date();
    const blocks: BodyBlock[] = request.blocks.map((block: BodyBlock) =>
      ({ id: block.id, text: block.text, imageId: block.imageId } as BodyBlock));
    const note: Note = {
      id: original?.id ?? `new-${Date.now()}-${nextId++}`,
      group: original?.group ?? request.group,
      title: request.title,
      content: documentText(blocks),
      blocks: blocks,
      images: request.images.filter((item: NoteImage) => blocks.some((block: BodyBlock) => block.imageId === item.id))
        .map((item: NoteImage) => copyImage(item)),
      skinId: request.skinId ?? original?.skinId ?? 'white',
      timeLabel: `${now.getMonth() + 1}月${now.getDate()}日 ${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`
    };
    commitNote(note, request.persistToDesktop ?? false);
    refreshDesktopCards(note.id);
    return { status: 'saved', note: note };
  } catch {
    return { status: 'storageError' };
  }
}

export function saveNote(params: NoteEditorParams, title: string, content: string, skinId?: string,
  blocks?: BodyBlock[], images?: NoteImage[]): Note {
  const result = saveNoteDraft({ id: params.id, group: params.group, title: title,
    blocks: blocks ?? [textBlock(content)], images: images ?? [], skinId: skinId });
  if (result.status !== 'saved' || !result.note) {
    throw new Error(result.status);
  }
  params.id = result.note.id;
  return result.note;
}

function updateMetadata(id: string, group?: string, skinId?: string): NoteSaveResult {
  try {
    const current = currentNote(id);
    if (current.status !== 'saved' || !current.note) {
      return current;
    }
    const original = current.note;
    const note: Note = { id: original.id, title: original.title, content: original.content,
      timeLabel: original.timeLabel, group: group ?? original.group, skinId: skinId ?? original.skinId,
      blocks: original.blocks, images: original.images };
    commitNote(note, false, false);
    refreshDesktopCards(id);
    return { status: 'saved', note: note };
  } catch {
    return { status: 'storageError' };
  }
}

export function moveNote(id: string, group: string): void {
  const result = updateMetadata(id, group);
  if (result.status === 'storageError') {
    throw new Error(result.status);
  }
}

export function changeNoteSkin(id: string, skinId: string): void {
  const result = updateMetadata(id, undefined, skinId);
  if (result.status === 'storageError') {
    throw new Error(result.status);
  }
}

export function deleteNote(id: string): void {
  removeNote(id);
  refreshDesktopCards(id);
}
