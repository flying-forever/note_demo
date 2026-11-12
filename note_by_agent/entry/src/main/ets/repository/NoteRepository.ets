// 维护笔记内存缓存，并把写入委托给关系型存储与桌面卡片投影。
import { common } from '@kit.AbilityKit';
import { FAKE_NOTES, Note } from '../model/Note';
import { initializeDesktopRepository, listDesktopRecords, persistDesktopNote, deleteDesktopNote,
  readDesktopRecord } from './DesktopNoteRepository';
import { openNoteDatabase } from './NoteDatabase';
import { loadAllNotes, saveNoteRecord, saveNoteChecked, deleteNoteRecord, updateNoteRecord,
  migrateDesktopRecords, seedSampleNotes, getSetting, setSetting, setNoteFilesDir, NoteWriteResult } from './NoteSqlRepository';

const SEED_KEY: string = 'bootstrap.samples.v1';
const SEED_VALUE: string = 'seeded';
const MIGRATION_KEY: string = 'migration.desktop_json.v1';
const MIGRATION_COUNT: string = 'migration.desktop_json.v1.count';
const MIGRATION_ERROR: string = 'migration.desktop_json.v1.error';

let notes: Note[] = [];
let ready: boolean = false;

export function noteRepositoryReady(): boolean {
  return ready;
}

export async function initializeNoteRepository(context: common.Context): Promise<void> {
  initializeDesktopRepository(context.filesDir);
  setNoteFilesDir(context.filesDir);
  await openNoteDatabase(context);
  if ((await getSetting(MIGRATION_KEY)) !== 'done') {
    await setSetting(MIGRATION_KEY, 'running');
    try {
      const migrated: number = await migrateDesktopRecords(listDesktopRecords());
      await setSetting(MIGRATION_COUNT, String(migrated));
      await setSetting(MIGRATION_KEY, 'done');
    } catch (error) {
      await setSetting(MIGRATION_ERROR, String(error));
      await setSetting(MIGRATION_KEY, 'failed');
      throw new Error(String(error));
    }
  }
  if ((await getSetting(SEED_KEY)) !== SEED_VALUE) {
    await seedSampleNotes(FAKE_NOTES);
    await setSetting(SEED_KEY, SEED_VALUE);
  }
  notes = await loadAllNotes();
  ready = true;
}

export async function refreshNotes(): Promise<void> {
  if (!ready) {
    return;
  }
  notes = await loadAllNotes();
}

export function listNotes(): Note[] {
  return notes;
}

export function findNote(id: string): Note | undefined {
  return notes.find((note: Note) => note.id === id);
}

export async function commitNote(note: Note, persistToDesktop: boolean = false,
  reorder: boolean = true): Promise<Note> {
  const saved: Note = await saveNoteRecord(note);
  if (persistToDesktop || readDesktopRecord(saved.id)) {
    persistDesktopNote(saved);
  }
  notes = reorder ? [saved, ...notes.filter((item: Note) => item.id !== saved.id)] :
    notes.map((item: Note) => item.id === saved.id ? saved : item);
  return saved;
}

export async function commitNoteChecked(note: Note, expectedRevision: number,
  persistToDesktop: boolean = false): Promise<NoteWriteResult> {
  const result: NoteWriteResult = await saveNoteChecked(note, expectedRevision);
  if (result.status !== 'saved' || !result.note) {
    return result;
  }
  const saved: Note = result.note;
  if (persistToDesktop || readDesktopRecord(saved.id)) {
    persistDesktopNote(saved);
  }
  notes = [saved, ...notes.filter((item: Note) => item.id !== saved.id)];
  return result;
}

export async function updateNoteMeta(id: string, group?: string, skinId?: string): Promise<Note | undefined> {
  await updateNoteRecord(id, group, skinId);
  let updated: Note | undefined = undefined;
  notes = notes.map((item: Note) => {
    if (item.id !== id) {
      return item;
    }
    updated = { id: item.id, title: item.title, content: item.content, timeLabel: item.timeLabel,
      group: group ?? item.group, skinId: skinId ?? item.skinId, blocks: item.blocks, images: item.images };
    return updated;
  });
  if (updated && readDesktopRecord(id)) {
    persistDesktopNote(updated);
  }
  return updated;
}

export async function removeNote(id: string): Promise<void> {
  await deleteNoteRecord(id);
  deleteDesktopNote(id);
  notes = notes.filter((note: Note) => note.id !== id);
}
