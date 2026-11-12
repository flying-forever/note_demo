// 统一处理笔记保存、冲突检测、移动、换肤与删除业务。
import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText, copyImage } from '../model/NoteDocument';
import { findNote, commitNote, removeNote, updateNoteMeta } from '../repository/NoteRepository';
import { loadNote } from '../repository/NoteSqlRepository';
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

export async function saveNoteDraft(request: NoteSaveRequest): Promise<NoteSaveResult> {
  try {
    let original: Note | undefined;
    if (request.id !== '') {
      original = await loadNote(request.id);
      if (!original) {
        return { status: 'deleted' };
      }
      const expected: string = request.expectedSnapshot ?? snapshotNote(findNote(request.id) ?? original);
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
    const saved: Note = await commitNote(note, request.persistToDesktop ?? false);
    refreshDesktopCards(saved.id).catch(() => {});
    return { status: 'saved', note: saved };
  } catch {
    return { status: 'storageError' };
  }
}

export async function saveNote(params: NoteEditorParams, title: string, content: string, skinId?: string,
  blocks?: BodyBlock[], images?: NoteImage[]): Promise<Note> {
  const result: NoteSaveResult = await saveNoteDraft({ id: params.id, group: params.group, title: title,
    blocks: blocks ?? [{ id: `block-${Date.now()}-0`, text: content, imageId: '' }], images: images ?? [], skinId: skinId });
  if (result.status !== 'saved' || !result.note) {
    throw new Error(result.status);
  }
  params.id = result.note.id;
  return result.note;
}

async function updateMetadata(id: string, group?: string, skinId?: string): Promise<NoteSaveResult> {
  try {
    const updated: Note | undefined = await updateNoteMeta(id, group, skinId);
    if (!updated) {
      return { status: 'deleted' };
    }
    refreshDesktopCards(id).catch(() => {});
    return { status: 'saved', note: updated };
  } catch {
    return { status: 'storageError' };
  }
}

export async function moveNote(id: string, group: string): Promise<void> {
  const result: NoteSaveResult = await updateMetadata(id, group);
  if (result.status !== 'saved') {
    throw new Error(result.status);
  }
}

export async function changeNoteSkin(id: string, skinId: string): Promise<void> {
  const result: NoteSaveResult = await updateMetadata(id, undefined, skinId);
  if (result.status !== 'saved') {
    throw new Error(result.status);
  }
}

export async function deleteNote(id: string): Promise<void> {
  await removeNote(id);
  refreshDesktopCards(id).catch(() => {});
}
