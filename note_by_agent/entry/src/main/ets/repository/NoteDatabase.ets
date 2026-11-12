// 打开并迁移版本化笔记数据库，集中定义表结构与事务边界。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export const NOTE_DATABASE_NAME: string = 'notes.db';
export const NOTE_SCHEMA_VERSION: number = 2;

const SCHEMA_STATEMENTS: string[] = [
  `CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    content_length INTEGER NOT NULL DEFAULT 0,
    group_name TEXT NOT NULL DEFAULT '',
    skin_id TEXT NOT NULL DEFAULT 'white',
    revision INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)),
    time_label TEXT NOT NULL DEFAULT ''
  )`,
  'CREATE INDEX IF NOT EXISTS notes_order_v2 ON notes(deleted, updated_at DESC, id ASC)',
  `CREATE TABLE IF NOT EXISTS blocks (
    note_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    block_id TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    image_id TEXT NOT NULL DEFAULT '',
    PRIMARY KEY(note_id, ordinal)
  )`,
  'CREATE UNIQUE INDEX IF NOT EXISTS blocks_note_block ON blocks(note_id, block_id)',
  `CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL,
    rel_path TEXT NOT NULL,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    bytes INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT NOT NULL DEFAULT '',
    caption TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT 0,
    small INTEGER NOT NULL DEFAULT 0
  )`,
  'CREATE INDEX IF NOT EXISTS attachments_note ON attachments(note_id)',
  `CREATE TABLE IF NOT EXISTS positions (
    note_id TEXT PRIMARY KEY NOT NULL,
    revision INTEGER NOT NULL DEFAULT 0,
    edit_block_id TEXT NOT NULL DEFAULT '',
    edit_offset INTEGER NOT NULL DEFAULT 0,
    browse_block_id TEXT NOT NULL DEFAULT '',
    browse_offset INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL DEFAULT ''
  )`
];

let opened: relationalStore.RdbStore | undefined = undefined;
let opening: Promise<relationalStore.RdbStore> | undefined = undefined;

async function createSchema(store: relationalStore.RdbStore): Promise<void> {
  for (const statement of SCHEMA_STATEMENTS) {
    await store.executeSql(statement);
  }
}

async function upgrade(store: relationalStore.RdbStore, from: number): Promise<void> {
  if (from === 0) {
    await createSchema(store);
  } else if (from < 2) {
    await store.executeSql('ALTER TABLE attachments ADD COLUMN small INTEGER NOT NULL DEFAULT 0');
    await store.executeSql('CREATE INDEX IF NOT EXISTS notes_order_v2 ON notes(deleted, updated_at DESC, id ASC)');
    await store.executeSql('CREATE UNIQUE INDEX IF NOT EXISTS blocks_note_block ON blocks(note_id, block_id)');
  }
  if (from > NOTE_SCHEMA_VERSION) {
    throw new Error(`笔记数据库版本 ${from} 高于当前支持版本 ${NOTE_SCHEMA_VERSION}`);
  }
  await store.executeSql('CREATE INDEX IF NOT EXISTS notes_order_v2 ON notes(deleted, updated_at DESC, id ASC)');
  await store.executeSql('CREATE UNIQUE INDEX IF NOT EXISTS blocks_note_block ON blocks(note_id, block_id)');
  store.version = NOTE_SCHEMA_VERSION;
}

function openOnce(context: common.Context): Promise<relationalStore.RdbStore> {
  return (async (): Promise<relationalStore.RdbStore> => {
    const config: relationalStore.StoreConfig = {
      name: NOTE_DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    await upgrade(store, store.version);
    opened = store;
    return store;
  })();
}

export async function openNoteDatabase(context: common.Context): Promise<relationalStore.RdbStore> {
  if (opened) {
    return opened;
  }
  if (!opening) {
    opening = openOnce(context);
  }
  try {
    return await opening;
  } finally {
    opening = undefined;
  }
}

export function noteDatabase(): relationalStore.RdbStore {
  if (!opened) {
    throw new Error('笔记数据库尚未初始化');
  }
  return opened;
}

export async function closeNoteDatabase(): Promise<void> {
  if (opened) {
    await opened.close();
    opened = undefined;
  }
}

export function noteDatabaseReady(): boolean {
  return opened !== undefined;
}
