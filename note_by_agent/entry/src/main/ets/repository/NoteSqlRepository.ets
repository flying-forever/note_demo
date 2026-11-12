// 以关系型数据库保存笔记、正文块、附件、位置与设置，并提供迁移写入。
import { relationalStore } from '@kit.ArkData';
import { Note } from '../model/Note';
import { BodyBlock, NoteImage, documentText } from '../model/NoteDocument';
import { DesktopRecord } from './DesktopNoteRepository';
import { noteDatabase } from './NoteDatabase';

const SUMMARY_LIMIT: number = 120;

let noteFilesDir: string = '';

export function setNoteFilesDir(directory: string): void {
  noteFilesDir = directory;
}

function relativeImagePath(path: string): string {
  if (noteFilesDir !== '' && path.startsWith(noteFilesDir + '/')) {
    return path.substring(noteFilesDir.length + 1);
  }
  return path;
}

function absoluteImagePath(path: string): string {
  if (path.startsWith('/') || noteFilesDir === '') {
    return path;
  }
  return `${noteFilesDir}/${path}`;
}

function contentLength(content: string): number {
  return Array.from(content.replace(/\s/g, '')).length;
}

export interface StoredPosition {
  noteId: string;
  revision: number;
  editBlockId: string;
  editOffset: number;
  browseBlockId: string;
  browseOffset: number;
}

export interface NoteStoreCounts {
  notes: number;
  deleted: number;
  blocks: number;
  attachments: number;
}

export function noteSummary(note: Note): string {
  const text: string = note.content.trim();
  if (text === '') {
    return note.blocks?.some((block: BodyBlock) => block.imageId !== '') ? '图片笔记' : '';
  }
  const lines: string[] = text.split('\n');
  const first: string = lines.find((line: string) => line.trim() !== '') ?? text;
  return first.length > SUMMARY_LIMIT ? first.substring(0, SUMMARY_LIMIT) : first;
}

export function noteBlocks(note: Note): BodyBlock[] {
  const blocks: BodyBlock[] | undefined = note.blocks;
  if (blocks && blocks.length > 0) {
    return blocks;
  }
  return [{ id: `${note.id}:0`, text: note.content, imageId: '' }];
}

function noteFromRow(row: Note, blocks: BodyBlock[], images: NoteImage[]): Note {
  return { id: row.id, title: row.title, content: row.content, timeLabel: row.timeLabel,
    group: row.group, skinId: row.skinId, blocks: blocks, images: images };
}

async function readBlocks(noteId: string): Promise<BodyBlock[]> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT block_id, body, image_id FROM blocks WHERE note_id = ? ORDER BY ordinal', [noteId]);
  const blocks: BodyBlock[] = [];
  try {
    while (result.goToNextRow()) {
      blocks.push({ id: result.getString(0), text: result.getString(1), imageId: result.getString(2) });
    }
  } finally {
    result.close();
  }
  return blocks;
}

async function readAttachments(noteId: string): Promise<NoteImage[]> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT id, rel_path, width, height, bytes, caption, small FROM attachments WHERE note_id = ? ORDER BY created_at',
    [noteId]);
  const images: NoteImage[] = [];
  try {
    while (result.goToNextRow()) {
      const path: string = absoluteImagePath(result.getString(1));
      const name: string = path.substring(path.lastIndexOf('/') + 1);
      images.push({ id: result.getString(0), path: path, name: name, width: result.getLong(2),
        height: result.getLong(3), bytes: result.getLong(4), caption: result.getString(5),
        small: result.getLong(6) === 1 });
    }
  } finally {
    result.close();
  }
  return images;
}

export async function loadAllNotes(): Promise<Note[]> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT id, title, group_name, skin_id, time_label FROM notes WHERE deleted = 0 ORDER BY updated_at DESC, id ASC');
  const rows: Note[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({ id: result.getString(0), title: result.getString(1), content: '',
        timeLabel: result.getString(4), group: result.getString(2), skinId: result.getString(3) });
    }
  } finally {
    result.close();
  }
  const notes: Note[] = [];
  for (const row of rows) {
    const blocks: BodyBlock[] = await readBlocks(row.id);
    notes.push(noteFromRow({ id: row.id, title: row.title, content: documentText(blocks), timeLabel: row.timeLabel,
      group: row.group, skinId: row.skinId }, blocks, await readAttachments(row.id)));
  }
  return notes;
}

export async function loadNote(id: string): Promise<Note | undefined> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT id, title, group_name, skin_id, time_label, deleted FROM notes WHERE id = ?', [id]);
  try {
    if (!result.goToFirstRow()) {
      return undefined;
    }
    if (result.getLong(5) === 1) {
      return undefined;
    }
    const row: Note = { id: result.getString(0), title: result.getString(1), content: '',
      timeLabel: result.getString(4), group: result.getString(2), skinId: result.getString(3) };
    const blocks: BodyBlock[] = await readBlocks(id);
    return noteFromRow({ id: row.id, title: row.title, content: documentText(blocks), timeLabel: row.timeLabel,
      group: row.group, skinId: row.skinId }, blocks, await readAttachments(id));
  } finally {
    result.close();
  }
}

async function nextRevision(id: string): Promise<number> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql('SELECT revision FROM notes WHERE id = ?', [id]);
  try {
    return result.goToFirstRow() ? result.getLong(0) + 1 : 1;
  } finally {
    result.close();
  }
}

async function writeBlocks(noteId: string, blocks: BodyBlock[]): Promise<void> {
  const store = noteDatabase();
  const existing: BodyBlock[] = await readBlocks(noteId);
  const sameIds: boolean = existing.length === blocks.length &&
    blocks.every((block: BodyBlock, index: number) => existing[index].id === block.id);
  if (sameIds) {
    for (let index: number = 0; index < blocks.length; index++) {
      const block: BodyBlock = blocks[index];
      if (existing[index].text !== block.text || existing[index].imageId !== block.imageId) {
        await store.executeSql('UPDATE blocks SET body = ?, image_id = ? WHERE note_id = ? AND block_id = ?',
          [block.text, block.imageId, noteId, block.id]);
      }
    }
    return;
  }
  await store.executeSql('DELETE FROM blocks WHERE note_id = ?', [noteId]);
  for (let index: number = 0; index < blocks.length; index++) {
    const block: BodyBlock = blocks[index];
    await store.executeSql('INSERT INTO blocks (note_id, ordinal, block_id, body, image_id) VALUES (?, ?, ?, ?, ?)',
      [noteId, index, block.id, block.text, block.imageId]);
  }
}

async function writeAttachments(noteId: string, images: NoteImage[]): Promise<void> {
  const store = noteDatabase();
  await store.executeSql('DELETE FROM attachments WHERE note_id = ?', [noteId]);
  const now: number = Date.now();
  for (const image of images) {
    await store.executeSql(
      'INSERT OR REPLACE INTO attachments (id, note_id, rel_path, width, height, bytes, sha256, caption, created_at, small) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [image.id, noteId, relativeImagePath(image.path), image.width, image.height, image.bytes, '', image.caption,
        now, image.small ? 1 : 0]);
  }
}

export async function saveNoteRecord(note: Note): Promise<Note> {
  const store = noteDatabase();
  const blocks: BodyBlock[] = noteBlocks(note);
  const content: string = documentText(blocks);
  const now: number = Date.now();
  const revision: number = await nextRevision(note.id);
  const exists: boolean = await hasRecord(note.id);
  store.beginTransaction();
  try {
    const values: relationalStore.ValuesBucket = {
      title: note.title, summary: noteSummary(note), content_length: contentLength(content),
      group_name: note.group, skin_id: note.skinId ?? 'white', revision: revision, updated_at: now,
      deleted: 0, time_label: note.timeLabel
    };
    if (exists) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('notes');
      predicates.equalTo('id', note.id);
      await store.update(values, predicates);
    } else {
      const insertValues: relationalStore.ValuesBucket = {
        id: note.id, title: note.title, summary: noteSummary(note), content_length: contentLength(content),
        group_name: note.group, skin_id: note.skinId ?? 'white', revision: revision, created_at: now,
        updated_at: now, deleted: 0, time_label: note.timeLabel
      };
      await store.insert('notes', insertValues);
    }
    await writeBlocks(note.id, blocks);
    await writeAttachments(note.id, note.images ?? []);
    store.commit();
  } catch (error) {
    store.rollBack();
    throw new Error(`保存笔记失败：${String(error)}`);
  }
  return { id: note.id, title: note.title, content: content, timeLabel: note.timeLabel, group: note.group,
    skinId: note.skinId, blocks: blocks, images: note.images ?? [] };
}

export async function deleteNoteRecord(id: string): Promise<void> {
  const store = noteDatabase();
  await store.executeSql('UPDATE notes SET deleted = 1, updated_at = ? WHERE id = ?', [Date.now(), id]);
}

export async function purgeNoteRecord(id: string): Promise<void> {
  const store = noteDatabase();
  store.beginTransaction();
  try {
    await store.executeSql('DELETE FROM blocks WHERE note_id = ?', [id]);
    await store.executeSql('DELETE FROM attachments WHERE note_id = ?', [id]);
    await store.executeSql('DELETE FROM notes WHERE id = ?', [id]);
    store.commit();
  } catch (error) {
    store.rollBack();
    throw new Error(`清理笔记失败：${String(error)}`);
  }
}

export async function noteRevision(id: string): Promise<number> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql('SELECT revision FROM notes WHERE id = ?', [id]);
  try {
    return result.goToFirstRow() ? result.getLong(0) : 0;
  } finally {
    result.close();
  }
}

export async function updateNoteRecord(id: string, group?: string, skinId?: string): Promise<void> {
  const store = noteDatabase();
  const current: Note | undefined = await loadNote(id);
  if (!current) {
    throw new Error('笔记不存在');
  }
  const values: relationalStore.ValuesBucket = {
    group_name: group ?? current.group,
    skin_id: skinId ?? current.skinId ?? 'white',
    revision: await nextRevision(id)
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('notes');
  predicates.equalTo('id', id);
  await store.update(values, predicates);
}

export async function savePosition(position: StoredPosition): Promise<void> {
  const store = noteDatabase();
  await store.executeSql(
    'INSERT OR REPLACE INTO positions (note_id, revision, edit_block_id, edit_offset, browse_block_id, browse_offset, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [position.noteId, position.revision, position.editBlockId, position.editOffset,
      position.browseBlockId, position.browseOffset, Date.now()]);
}

export async function loadPosition(noteId: string): Promise<StoredPosition | undefined> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT revision, edit_block_id, edit_offset, browse_block_id, browse_offset FROM positions WHERE note_id = ?',
    [noteId]);
  try {
    if (!result.goToFirstRow()) {
      return undefined;
    }
    return { noteId: noteId, revision: result.getLong(0), editBlockId: result.getString(1),
      editOffset: result.getLong(2), browseBlockId: result.getString(3), browseOffset: result.getLong(4) };
  } finally {
    result.close();
  }
}

export async function getSetting(key: string): Promise<string | undefined> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql('SELECT value FROM settings WHERE key = ?', [key]);
  try {
    return result.goToFirstRow() ? result.getString(0) : undefined;
  } finally {
    result.close();
  }
}

export async function setSetting(key: string, value: string): Promise<void> {
  const store = noteDatabase();
  await store.executeSql('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
}

export async function storeCounts(): Promise<NoteStoreCounts> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT (SELECT COUNT(*) FROM notes), (SELECT COUNT(*) FROM notes WHERE deleted = 1), (SELECT COUNT(*) FROM blocks), (SELECT COUNT(*) FROM attachments)');
  try {
    result.goToFirstRow();
    return { notes: result.getLong(0), deleted: result.getLong(1), blocks: result.getLong(2),
      attachments: result.getLong(3) };
  } finally {
    result.close();
  }
}

async function insertNote(note: Note, createdAt: number, deleted: boolean): Promise<void> {
  const store = noteDatabase();
  const blocks: BodyBlock[] = noteBlocks(note);
  const content: string = documentText(blocks);
  const values: relationalStore.ValuesBucket = {
    id: note.id, title: note.title, summary: noteSummary(note), content_length: contentLength(content),
    group_name: note.group, skin_id: note.skinId ?? 'white', revision: 1,
    created_at: createdAt, updated_at: createdAt, deleted: deleted ? 1 : 0, time_label: note.timeLabel
  };
  await store.insert('notes', values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  await writeBlocks(note.id, blocks);
  await writeAttachments(note.id, note.images ?? []);
}

async function hasRecord(id: string): Promise<boolean> {
  const store = noteDatabase();
  const result: relationalStore.ResultSet = await store.querySql('SELECT 1 FROM notes WHERE id = ?', [id]);
  try {
    return result.goToFirstRow();
  } finally {
    result.close();
  }
}

export async function migrateDesktopRecords(records: DesktopRecord[]): Promise<number> {
  const store = noteDatabase();
  let migrated: number = 0;
  store.beginTransaction();
  try {
    for (const record of records) {
      if (await hasRecord(record.id)) {
        continue;
      }
      if (record.deleted || !record.note) {
        const tombstone: relationalStore.ValuesBucket = { id: record.id, deleted: 1, revision: 1,
          created_at: Date.now(), updated_at: Date.now() };
        await store.insert('notes', tombstone, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      } else {
        await insertNote(record.note, Date.now() - migrated * 1000, false);
      }
      migrated++;
    }
    store.commit();
  } catch (error) {
    store.rollBack();
    throw new Error(`迁移桌面笔记失败：${String(error)}`);
  }
  return migrated;
}

export async function seedSampleNotes(samples: Note[]): Promise<number> {
  const store = noteDatabase();
  let seeded: number = 0;
  store.beginTransaction();
  try {
    for (const note of samples) {
      if (await hasRecord(note.id)) {
        continue;
      }
      await insertNote(note, Date.now() - seeded * 1000, false);
      seeded++;
    }
    store.commit();
  } catch (error) {
    store.rollBack();
    throw new Error(`导入样例笔记失败：${String(error)}`);
  }
  return seeded;
}
