// 在独立试验库验证分块读取、版本竞争、事务回滚与重开恢复。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DemoChunk, fixtureText, splitDemoText } from './LongDocumentFixture';

const DATABASE_NAME: string = 'tech_demo_stage1.db';
const DOCUMENT_ID: string = 'fixture';
const DOCUMENT_LENGTH: number = 100000;
const RANGE_START: number = 14;
const RANGE_COUNT: number = 5;
const POSITION_BLOCK: number = 16;
const POSITION_OFFSET: number = 1234;

export interface DatabaseProbeResult {
  name: string;
  detail: string;
}

function verify(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

async function openDatabase(context: common.Context): Promise<relationalStore.RdbStore> {
  const config: relationalStore.StoreConfig = { name: DATABASE_NAME, securityLevel: relationalStore.SecurityLevel.S1 };
  return relationalStore.getRdbStore(context, config);
}

async function schema(store: relationalStore.RdbStore): Promise<void> {
  await store.executeSql('CREATE TABLE IF NOT EXISTS demo_notes (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, title TEXT NOT NULL)');
  await store.executeSql('CREATE TABLE IF NOT EXISTS demo_blocks (note_id TEXT NOT NULL, ordinal INTEGER NOT NULL, block_id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(note_id, ordinal))');
  await store.executeSql('CREATE TABLE IF NOT EXISTS demo_positions (note_id TEXT PRIMARY KEY, revision INTEGER NOT NULL, block_id TEXT NOT NULL, text_offset INTEGER NOT NULL)');
}

async function seed(store: relationalStore.RdbStore, chunks: DemoChunk[]): Promise<void> {
  store.beginTransaction();
  try {
    await store.executeSql('DELETE FROM demo_positions');
    await store.executeSql('DELETE FROM demo_blocks');
    await store.executeSql('DELETE FROM demo_notes');
    await store.executeSql('INSERT INTO demo_notes VALUES (?, ?, ?)', [DOCUMENT_ID, 1, '10万字符试验']);
    for (let index: number = 0; index < chunks.length; index++) {
      await store.executeSql('INSERT INTO demo_blocks VALUES (?, ?, ?, ?)',
        [DOCUMENT_ID, index, chunks[index].id, chunks[index].text]);
    }
    store.commit();
  } catch (error) {
    store.rollBack();
    throw new Error(`初始化试验数据失败：${String(error)}`);
  }
}

async function readRange(store: relationalStore.RdbStore, start: number, count: number): Promise<string[]> {
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT body FROM demo_blocks WHERE note_id = ? ORDER BY ordinal LIMIT ? OFFSET ?', [DOCUMENT_ID, count, start]);
  const rows: string[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(result.getString(0));
    }
  } finally {
    result.close();
  }
  return rows;
}

async function revision(store: relationalStore.RdbStore): Promise<number> {
  const result: relationalStore.ResultSet = await store.querySql('SELECT revision FROM demo_notes WHERE id = ?', [DOCUMENT_ID]);
  try {
    verify(result.goToFirstRow(), '缺少试验笔记');
    return result.getLong(0);
  } finally {
    result.close();
  }
}

async function conditionalUpdate(store: relationalStore.RdbStore, expected: number, title: string): Promise<number> {
  const values: relationalStore.ValuesBucket = { revision: expected + 1, title: title };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('demo_notes');
  predicates.equalTo('id', DOCUMENT_ID).equalTo('revision', expected);
  return store.update(values, predicates);
}

async function rollbackProbe(store: relationalStore.RdbStore): Promise<void> {
  const before: string[] = await readRange(store, 0, 1);
  const beforeRevision: number = await revision(store);
  let rejected: boolean = false;
  store.beginTransaction();
  try {
    await store.executeSql('UPDATE demo_blocks SET body = ? WHERE note_id = ? AND ordinal = 0', ['不应保留', DOCUMENT_ID]);
    await store.executeSql('UPDATE demo_notes SET revision = revision + 1 WHERE id = ?', [DOCUMENT_ID]);
    await store.executeSql('INSERT INTO demo_blocks VALUES (?, 0, ?, ?)', [DOCUMENT_ID, 'duplicate', '触发唯一约束失败']);
    store.commit();
  } catch (error) {
    store.rollBack();
    rejected = true;
  }
  verify(rejected, '重复键没有触发失败');
  const after: string[] = await readRange(store, 0, 1);
  verify(before[0] === after[0] && beforeRevision === await revision(store), '回滚后正文或版本发生改变');
}

async function savePosition(store: relationalStore.RdbStore, chunk: DemoChunk): Promise<void> {
  await store.executeSql('INSERT OR REPLACE INTO demo_positions VALUES (?, ?, ?, ?)',
    [DOCUMENT_ID, await revision(store), chunk.id, POSITION_OFFSET]);
}

async function verifyDisk(store: relationalStore.RdbStore): Promise<void> {
  const text: string = (await readRange(store, 0, DOCUMENT_LENGTH)).join('');
  verify(text === fixtureText(DOCUMENT_LENGTH, false), '重开后正文不一致');
  verify(await revision(store) === 2, '重开后版本不一致');
  const result: relationalStore.ResultSet = await store.querySql(
    'SELECT p.text_offset, p.revision, b.ordinal, length(b.body) FROM demo_positions p JOIN demo_blocks b ON p.note_id = b.note_id AND p.block_id = b.block_id WHERE p.note_id = ?', [DOCUMENT_ID]);
  try {
    verify(result.goToFirstRow(), '位置记录或目标块不存在');
    verify(result.getLong(0) === POSITION_OFFSET && result.getLong(1) === 2 && result.getLong(2) === POSITION_BLOCK,
      '位置记录不一致');
    verify(result.getLong(3) >= POSITION_OFFSET, '位置超过目标块长度');
  } finally {
    result.close();
  }
}

export async function runDatabaseProbe(context: common.Context,
  report: (result: DatabaseProbeResult) => void, verifyOnly: boolean = false): Promise<void> {
  let first: relationalStore.RdbStore | undefined = undefined;
  let second: relationalStore.RdbStore | undefined = undefined;
  try {
    first = await openDatabase(context);
    await schema(first);
    if (verifyOnly) {
      await verifyDisk(first);
      report({ name: '复验落盘', detail: '正文 100000、版本 2、块 17 偏移 1234 均一致' });
      return;
    }
    const chunks: DemoChunk[] = splitDemoText(fixtureText(DOCUMENT_LENGTH, false));
    const start: number = Date.now();
    await seed(first, chunks);
    report({ name: '分块写入', detail: `${chunks.length} 块 / 100000 字符，${Date.now() - start}ms（单次 IO 记录）` });
    const range: string[] = await readRange(first, RANGE_START, RANGE_COUNT);
    verify(range.length === RANGE_COUNT && range.join('') === chunks.slice(RANGE_START, RANGE_START + RANGE_COUNT)
      .map((chunk: DemoChunk) => chunk.text).join(''), '范围读取不一致');
    report({ name: '范围读取', detail: '只取第 15～19 块，5 条记录内容一致' });
    second = await openDatabase(context);
    verify(await revision(second) === 1, '第二句柄没有读到初始版本');
    const firstHandle: relationalStore.RdbStore = first;
    const secondHandle: relationalStore.RdbStore = second;
    const counts: number[] = await Promise.all([
      conditionalUpdate(firstHandle, 1, '入口 A'), conditionalUpdate(secondHandle, 1, '入口 B')
    ]);
    verify(counts[0] + counts[1] === 1 && counts.some((value: number) => value === 0), '条件更新未拒绝过期版本');
    verify(await revision(first) === 2 && await revision(second) === 2, '句柄间版本不可见');
    report({ name: '版本冲突', detail: `两个同进程句柄竞争，更新行数 ${counts.join('/')}，只成功一次` });
    await second.close();
    second = undefined;
    await rollbackProbe(first);
    report({ name: '事务回滚', detail: '正文与版本更新后制造重复键失败，两项恢复原值' });
    await savePosition(first, chunks[POSITION_BLOCK]);
    await first.close();
    first = undefined;
    first = await openDatabase(context);
    await verifyDisk(first);
    report({ name: '关闭重开', detail: '全文一致，版本 2，块 17 的 UTF-16 偏移 1234 恢复' });
  } finally {
    if (second) {
      await second.close();
    }
    if (first) {
      await first.close();
    }
  }
}
