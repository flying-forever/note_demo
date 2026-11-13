// 统一处理笔记保存、冲突检测、移动、换肤与删除业务。
import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText, copyImage } from '../model/NoteDocument';
import { commitNote, commitNoteChecked, removeNote, updateNoteMeta } from '../repository/NoteRepository';
import { loadStoredNote, StoredNoteRecord, deletePosition, listReferencedImagePaths, noteAttachmentPaths } from '../repository/NoteSqlRepository';
import { releaseAttachmentFile } from '../platform/NoteAttachments';
import { deleteDraftsForNote } from '../repository/DraftRepository';
import { refreshDesktopCards } from '../platform/DesktopCards';

export interface NoteEditorParams {
  id: string;
  group: string;
  draftId?: string;
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
  textOnly?: boolean;
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
    if (request.textOnly && (request.images.length > 0 ||
      request.blocks.some((block: BodyBlock) => block.imageId !== ''))) {
      return { status: 'unsupported' };
    }
    let original: Note | undefined;
    let baseRevision: number = 0;
    if (request.id !== '') {
      const stored: StoredNoteRecord | undefined = await loadStoredNote(request.id);
      if (!stored) {
        return { status: 'deleted' };
      }
      original = stored.note;
      baseRevision = stored.revision;
      const expected: string = request.expectedSnapshot ?? snapshotNote(original);
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
    const persistToDesktop: boolean = request.persistToDesktop ?? false;
    let saved: Note;
    if (original) {
      const outcome = await commitNoteChecked(note, baseRevision, persistToDesktop);
      if (outcome.status !== 'saved' || !outcome.note) {
        return { status: outcome.status };
      }
      saved = outcome.note;
    } else {
      saved = await commitNote(note, persistToDesktop);
    }
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
  const paths: string[] = await noteAttachmentPaths(id);
  await deleteDraftsForNote(id);
  await removeNote(id);
  await deletePosition(id);
  try {
    const referenced: string[] = await listReferencedImagePaths();
    paths.forEach((path: string) => {
      if (!referenced.includes(path)) {
        releaseAttachmentFile(path);
      }
    });
  } catch {
  }
  refreshDesktopCards(id).catch(() => {});
}
