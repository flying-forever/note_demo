// 持久化自动草稿，供强杀恢复、空白清理与附件引用判断使用。
import { relationalStore } from '@kit.ArkData';
import { NoteImage } from '../model/NoteDocument';
import { noteDatabase } from './NoteDatabase';

export interface DraftRecord {
  draftId: string;
  noteId: string;
  groupName: string;
  baseRevision: number;
  title: string;
  blocksJson: string;
  imagesJson: string;
  createdAt: number;
  updatedAt: number;
}

function rowToDraft(result: relationalStore.ResultSet): DraftRecord {
  return {
    draftId: result.getString(0),
    noteId: result.getString(1),
    groupName: result.getString(2),
    baseRevision: result.getLong(3),
    title: result.getString(4),
    blocksJson: result.getString(5),
    imagesJson: result.getString(6),
    createdAt: result.getLong(7),
    updatedAt: result.getLong(8)
  };
}

export async function saveDraftRecord(draft: DraftRecord): Promise<void> {
  const store = noteDatabase();
  await store.executeSql(
    'INSERT OR REPLACE INTO drafts (draft_id, note_id, group_name, base_revision, title, blocks_json, images_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [draft.draftId, draft.noteId, draft.groupName, draft.baseRevision, draft.title, draft.blocksJson,
      draft.imagesJson, draft.createdAt, draft.updatedAt]);
}

export async function loadDraftRecord(draftId: string): Promise<DraftRecord | undefined> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT draft_id, note_id, group_name, base_revision, title, blocks_json, images_json, created_at, updated_at FROM drafts WHERE draft_id = ?',
    [draftId]);
  try {
    return result.goToFirstRow() ? rowToDraft(result) : undefined;
  } finally {
    result.close();
  }
}

export async function findDraftForNote(noteId: string): Promise<DraftRecord | undefined> {
  if (noteId === '') {
    return undefined;
  }
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT draft_id, note_id, group_name, base_revision, title, blocks_json, images_json, created_at, updated_at FROM drafts WHERE note_id = ? ORDER BY updated_at DESC LIMIT 1',
    [noteId]);
  try {
    return result.goToFirstRow() ? rowToDraft(result) : undefined;
  } finally {
    result.close();
  }
}

export async function listDraftRecords(): Promise<DraftRecord[]> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT draft_id, note_id, group_name, base_revision, title, blocks_json, images_json, created_at, updated_at FROM drafts ORDER BY updated_at DESC');
  const drafts: DraftRecord[] = [];
  try {
    while (result.goToNextRow()) {
      drafts.push(rowToDraft(result));
    }
  } finally {
    result.close();
  }
  return drafts;
}

export async function deleteDraftRecord(draftId: string): Promise<void> {
  const store = noteDatabase();
  await store.executeSql('DELETE FROM drafts WHERE draft_id = ?', [draftId]);
}

export async function deleteDraftsForNote(noteId: string): Promise<void> {
  if (noteId === '') {
    return;
  }
  const store = noteDatabase();
  await store.executeSql('DELETE FROM drafts WHERE note_id = ?', [noteId]);
}

export async function draftImagePaths(): Promise<string[]> {
  const drafts: DraftRecord[] = await listDraftRecords();
  const paths: string[] = [];
  for (const draft of drafts) {
    try {
      const images = JSON.parse(draft.imagesJson) as NoteImage[];
      for (const image of images) {
        if (image.path !== '' && !paths.includes(image.path)) {
          paths.push(image.path);
        }
      }
    } catch {
      continue;
    }
  }
  return paths;
}
