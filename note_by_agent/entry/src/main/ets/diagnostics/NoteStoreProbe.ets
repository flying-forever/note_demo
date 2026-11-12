// 对正式笔记库执行计数、往返、版本与删除清理自检，不保留测试数据。
import { Note } from '../model/Note';
import { BodyBlock, documentText } from '../model/NoteDocument';
import { loadAllNotes, loadNote, saveNoteRecord, saveNoteChecked, deleteNoteRecord, purgeNoteRecord,
  noteRevision, updateNoteRecord, storeCounts, getSetting, noteBlocks, listReferencedImagePaths } from '../repository/NoteSqlRepository';

export interface StoreCheckResult {
  name: string;
  detail: string;
}

function verify(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

export async function runNoteStoreChecks(report: (result: StoreCheckResult) => void): Promise<void> {
  const before = await storeCounts();
  report({ name: '库统计', detail: `笔记 ${before.notes}（墓碑 ${before.deleted}），块 ${before.blocks}，附件 ${before.attachments}` });

  const migrated: string | undefined = await getSetting('migration.desktop_json.v1');
  verify(migrated === 'done', `迁移状态异常：${migrated ?? '缺失'}`);
  const migratedCount: string | undefined = await getSetting('migration.desktop_json.v1.count');
  report({ name: '迁移状态', detail: `状态 done，迁移 ${migratedCount ?? '0'} 条桌面记录` });

  const notes: Note[] = await loadAllNotes();
  verify(notes.length > 0, '笔记库为空');
  const sample: Note = notes.find((note: Note) => note.content.length > 0) ?? notes[0];
  const blocks: BodyBlock[] = noteBlocks(sample);
  verify(documentText(blocks) === sample.content, '正文块与纯文本不一致');
  verify(blocks.length > 0 && blocks[0].id !== '', '正文块缺少 ID');
  report({ name: '往返一致', detail: `${sample.id}：${blocks.length} 块，${sample.content.length} 字符` });

  const id: string = `check-${Date.now()}`;
  const text: string = '第一行\n第二行';
  const note: Note = { id: id, title: '数据层自检', content: text, timeLabel: '自检', group: '',
    skinId: 'white', blocks: [{ id: `${id}:0`, text: text, imageId: '' }], images: [] };
  const saved: Note = await saveNoteRecord(note);
  verify(saved.content === text, '保存后正文不一致');
  const loaded: Note | undefined = await loadNote(id);
  if (!loaded || loaded.title !== note.title) {
    throw new Error('读回失败');
  }
  if (!loaded.blocks || loaded.blocks.length !== 1 || loaded.blocks[0].text !== text) {
    throw new Error('块读回不一致');
  }
  const rev1: number = await noteRevision(id);
  await updateNoteRecord(id, '随记');
  const rev2: number = await noteRevision(id);
  verify(rev2 === rev1 + 1, '版本号未递增');
  const stale = await saveNoteChecked({ id: id, title: '过期写入', content: '过期', timeLabel: '', group: '',
    skinId: 'white', blocks: [{ id: `${id}:0`, text: '过期', imageId: '' }], images: [] }, rev1);
  verify(stale.status === 'conflict', `过期版本未被拒绝：${stale.status}`);
  verify((await loadNote(id))?.title === '数据层自检', '冲突后内容被覆盖');
  await deleteNoteRecord(id);
  verify((await loadNote(id)) === undefined, '墓碑后仍可读到笔记');
  await purgeNoteRecord(id);
  const after = await storeCounts();
  verify(after.notes === before.notes && after.blocks === before.blocks, `清理后计数异常：${after.notes}/${after.blocks}`);
  const referenced = await listReferencedImagePaths();
  verify(referenced.length === after.attachments, `附件引用数不一致：${referenced.length}/${after.attachments}`);
  report({ name: '写入/版本/删除', detail: `版本 ${rev1}→${rev2}，过期写入被拒，墓碑与清理通过` });
}
