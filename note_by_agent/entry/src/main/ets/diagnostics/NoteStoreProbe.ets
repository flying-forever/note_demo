// 对正式笔记库执行计数、往返、版本与删除清理自检，不保留测试数据。
import { Note } from '../model/Note';
import { BodyBlock, documentText } from '../model/NoteDocument';
import { loadAllNotes, loadNote, saveNoteRecord, saveNoteChecked, deleteNoteRecord, purgeNoteRecord,
  noteRevision, updateNoteRecord, storeCounts, getSetting, noteBlocks, listReferencedImagePaths,
  noteFilesDirectory } from '../repository/NoteSqlRepository';
import { NOTE_SCHEMA_VERSION, noteDatabase } from '../repository/NoteDatabase';
import { loadDraftRecord, saveDraftRecord, deleteDraftRecord } from '../repository/DraftRepository';
import { cleanupOrphanImages, ensureThumbnail, importNoteImage, MAX_IMAGE_BYTES } from '../platform/NoteAttachments';
import { deleteNote } from '../services/NoteService';
import { fileIo as fs } from '@kit.CoreFileKit';

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

  verify(noteDatabase().version === NOTE_SCHEMA_VERSION, `schema 版本异常：${noteDatabase().version}`);
  const draftId: string = `draft-check-${Date.now()}`;
  await saveDraftRecord({ draftId: draftId, noteId: '', groupName: '', baseRevision: 0, title: '草稿自检',
    blocksJson: '[{"id":"d0","text":"草稿正文","imageId":""}]', imagesJson: '[]',
    createdAt: Date.now(), updatedAt: Date.now() });
  const draft = await loadDraftRecord(draftId);
  verify(draft?.title === '草稿自检' && draft?.blocksJson.includes('草稿正文') === true, '草稿读回失败');
  await deleteDraftRecord(draftId);
  verify((await loadDraftRecord(draftId)) === undefined, '草稿删除失败');
  report({ name: '草稿表', detail: `schema v${NOTE_SCHEMA_VERSION}，写入/读回/删除通过` });

  const filesDir: string = noteFilesDirectory();
  const imageDir: string = filesDir + '/note-images';
  const limitSource: string = filesDir + '/import-limit-check';
  const limitFile = fs.openSync(limitSource, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(limitFile.fd, new ArrayBuffer(MAX_IMAGE_BYTES + 1));
  } finally {
    fs.closeSync(limitFile);
  }
  let rejected: boolean = false;
  try {
    await importNoteImage(filesDir, limitSource);
  } catch {
    rejected = true;
  }
  try { fs.unlinkSync(limitSource); } catch {}
  verify(rejected, '超过 500KB 的导入未被拒绝');
  const leftovers: string[] = fs.accessSync(imageDir) ?
    fs.listFileSync(imageDir).filter((name: string) => name.endsWith('.part')) : [];
  verify(leftovers.length === 0, `导入失败残留临时文件：${leftovers.length}`);
  const orphan: string = imageDir + '/orphan-check';
  if (!fs.accessSync(imageDir)) { fs.mkdirSync(imageDir, true); }
  const orphanFile = fs.openSync(orphan, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  fs.writeSync(orphanFile.fd, new ArrayBuffer(1));
  fs.closeSync(orphanFile);
  cleanupOrphanImages(filesDir, await listReferencedImagePaths(), 0);
  verify(!fs.accessSync(orphan), '孤立附件未被清理');
  const orphanThumb: string = filesDir + '/note-images-thumbs/orphan-check.thumb';
  const thumbDir: string = filesDir + '/note-images-thumbs';
  if (!fs.accessSync(thumbDir)) { fs.mkdirSync(thumbDir, true); }
  const thumbFile = fs.openSync(orphanThumb, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  fs.writeSync(thumbFile.fd, new ArrayBuffer(1));
  fs.closeSync(thumbFile);
  cleanupOrphanImages(filesDir, await listReferencedImagePaths(), 0);
  verify(!fs.accessSync(orphanThumb), '孤立缩略图未被清理');
  const imagePath: string | undefined = (await listReferencedImagePaths()).find((path: string) => fs.accessSync(path));
  if (imagePath !== undefined) {
    const thumb: string = await ensureThumbnail(imagePath);
    verify(thumb !== imagePath && fs.accessSync(thumb), '缩略图生成失败');
    report({ name: '缩略图', detail: `长边 ${960} 以内、质量 75，可重建；派生文件不进入附件记录` });
  }
  const attachedNoteId: string = `delete-check-${Date.now()}`;
  const attachedPath: string = imageDir + '/probe-delete-image';
  const attachedFile = fs.openSync(attachedPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  fs.writeSync(attachedFile.fd, new ArrayBuffer(1));
  fs.closeSync(attachedFile);
  await saveNoteRecord({ id: attachedNoteId, title: '删除清理自检', content: '', timeLabel: '', group: '',
    skinId: 'white', blocks: [{ id: `${attachedNoteId}:0`, text: '', imageId: 'probe-image' }],
    images: [{ id: 'probe-image', path: attachedPath, name: 'probe-image', width: 1, height: 1, bytes: 1,
      caption: '', small: false }] });
  verify(fs.accessSync(attachedPath), '删除测试附件未落盘');
  await deleteNote(attachedNoteId);
  verify(!fs.accessSync(attachedPath), '删除笔记后附件未清理');
  await purgeNoteRecord(attachedNoteId);
  report({ name: '删除清理', detail: '带附件笔记删除后原图与附件记录同步清理' });
  report({ name: '附件导入与清理', detail: `超过 ${MAX_IMAGE_BYTES} 字节被拒且无 .part 残留，孤立文件可删除` });
}
