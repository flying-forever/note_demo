// 模拟文件与卡片接口，回归验证桌面笔记存储、绑定和保存冲突。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const sourceRoot = path.resolve(__dirname, '../note_by_agent/entry/src/main/ets');
const validationRoot = path.resolve(__dirname, '../note_by_agent/entry/build/validation-desktop');
fs.mkdirSync(validationRoot, { recursive: true });
const temporary = fs.mkdtempSync(path.join(validationRoot, 'run-'));
const updates = [];
const failedForms = new Set();
const openedPaths = [];
let failWrite = false;
let failRename = false;
let failFormsRead = false;
const fileIo = {
  OpenMode: { CREATE: fs.constants.O_CREAT, WRITE_ONLY: fs.constants.O_WRONLY, TRUNC: fs.constants.O_TRUNC },
  accessSync: fs.existsSync,
  mkdirSync: (name, recursive) => fs.mkdirSync(name, { recursive }),
  openSync: (name, mode) => {
    if (failWrite) throw new Error('simulated disk error');
    openedPaths.push(name);
    return { fd: fs.openSync(name, mode) };
  },
  writeSync: fs.writeSync, fsyncSync: fs.fsyncSync, closeSync: file => fs.closeSync(file.fd),
  renameSync: (from, to) => {
    if (failRename) throw new Error('simulated rename error');
    fs.renameSync(from, to);
  },
  readTextSync: name => fs.readFileSync(name, 'utf8'),
  listFileSync: name => {
    if (failFormsRead && name.endsWith('/forms')) throw new Error('simulated association read error');
    return fs.readdirSync(name);
  },
  unlinkSync: fs.unlinkSync
};
function application() {
  const modules = {};
  function load(name, base = path.join(sourceRoot, 'model')) {
    const filename = path.resolve(base, name + '.ets');
    assert.ok(filename.startsWith(sourceRoot + path.sep));
    if (modules[filename]) return modules[filename];
    const exports = {};
    modules[filename] = exports;
    const source = fs.readFileSync(filename, 'utf8');
    const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    vm.runInNewContext(code, { exports, Date, encodeURIComponent, decodeURIComponent,
      require: dependency => {
        if (dependency === '@kit.CoreFileKit') return { fileIo };
        if (dependency === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
        if (dependency === '@kit.FormKit') return {
          formBindingData: { createFormBindingData: data => data },
          formProvider: { updateForm: async (id, data) => {
            if (failedForms.has(id)) throw new Error('simulated card refresh error');
            updates.push({ id, data });
          } }
        };
        return load(dependency, path.dirname(filename));
      }
    });
    return exports;
  }
  const repository = load('../repository/DesktopNoteRepository');
  repository.initializeDesktopRepository(temporary);
  const cards = load('../platform/DesktopCards');
  const store = { ...load('../repository/NoteRepository'), ...load('../services/NoteService') };
  store.syncDesktopNotes();
  return { repository, cards, store };
}
function request(note, overrides = {}) {
  return {
    id: note.id, group: note.group, title: note.title,
    blocks: note.blocks || [{ id: 'legacy-text', text: note.content, imageId: '' }],
    images: note.images || [], skinId: note.skinId,
    expectedSnapshot: JSON.stringify({ id: note.id, title: note.title, content: note.content,
      timeLabel: note.timeLabel, group: note.group, skinId: note.skinId, blocks: note.blocks, images: note.images }), ...overrides
  };
}
async function flushCards() {
  await new Promise(setImmediate);
}
async function run() {
  const first = application();
  const draftParams = { id: '', group: '旅途' };
  const transient = first.store.saveNote(draftParams, 'temporary', 'not exported');
  assert.equal(first.repository.readDesktopNote(transient.id), undefined);
  const blocks = [{ id: 'text-a', text: '正文\r\n第二行', imageId: '' }, { id: 'image-a', text: '', imageId: 'image-a' }];
  const images = [{ id: 'image-a', path: '/private/image-a', name: 'image-a', width: 100, height: 80, bytes: 50, caption: '描述', small: true }];
  const note = first.store.saveNote({ id: 'n01', group: '旅途' }, '桌面笔记', '正文', 'blue', blocks, images);
  first.repository.persistDesktopNote(note);
  first.repository.bindDesktopForm('90071992547409931', note.id);
  first.repository.bindDesktopForm('90071992547409932', note.id);
  const restarted = application();
  assert.equal(restarted.store.findNote(transient.id), undefined);
  assert.equal(restarted.store.findNote(note.id).images[0].caption, '描述');
  assert.equal(restarted.store.findNote(note.id).blocks[1].imageId, 'image-a');
  restarted.store.changeNoteSkin(note.id, 'green');
  restarted.store.moveNote(note.id, '美食');
  let persisted = restarted.repository.readDesktopNote(note.id);
  assert.equal(persisted.skinId, 'green');
  assert.equal(persisted.group, '美食');
  assert.equal(persisted.images[0].small, true);
  assert.equal(persisted.content, '正文\r\n第二行');
  const sameValueDifferentOrder = { images: persisted.images, blocks: persisted.blocks,
    skinId: persisted.skinId, group: persisted.group, timeLabel: persisted.timeLabel,
    content: persisted.content, title: persisted.title, id: persisted.id };
  assert.equal(restarted.store.snapshotNote(sameValueDifferentOrder), restarted.store.snapshotNote(persisted));
  const ownMetadataBaseline = { ...note, skinId: 'green', group: '美食' };
  const afterOwnMetadata = restarted.store.saveNoteDraft(request(ownMetadataBaseline));
  assert.equal(afterOwnMetadata.status, 'saved', 'Saving after own skin/folder change must not report a conflict');
  persisted = afterOwnMetadata.note;
  failWrite = true;
  assert.throws(() => restarted.store.saveNote({ id: note.id, group: '' }, 'failed', 'failed'));
  const failure = restarted.store.saveNoteDraft(request(persisted, { title: 'failed' }));
  assert.equal(failure.status, 'storageError');
  failWrite = false;
  assert.equal(restarted.store.findNote(note.id).title, '桌面笔记');
  const beforeRenameFailure = restarted.repository.readDesktopNote(note.id);
  failRename = true;
  assert.equal(restarted.store.saveNoteDraft(request(beforeRenameFailure, { title: 'rename failure' })).status, 'storageError');
  failRename = false;
  assert.equal(restarted.repository.readDesktopNote(note.id).title, '桌面笔记');
  assert.equal(fs.readdirSync(path.join(temporary, 'desktop-notes/notes')).some(name => name.endsWith('.tmp')), false);
  assert.equal(new Set(openedPaths).size, openedPaths.length, 'Each write uses its own temporary file');

  const external = { ...persisted, title: '半模态更新' };
  restarted.repository.persistDesktopNote(external);
  assert.equal(first.store.saveNoteDraft(request(note, { title: 'stale main edit' })).status, 'conflict');
  assert.throws(() => first.store.saveNote({ id: note.id, group: '' }, 'stale legacy edit', 'overwrite'));
  assert.equal(first.repository.readDesktopNote(note.id).title, '半模态更新');
  first.store.moveNote(note.id, '工作');
  assert.equal(first.repository.readDesktopNote(note.id).title, '半模态更新');
  assert.equal(first.repository.readDesktopNote(note.id).group, '工作');
  const moved = first.repository.readDesktopNote(note.id);
  const newer = { ...moved, title: '更新后的标题' };
  restarted.repository.persistDesktopNote(newer);
  first.store.changeNoteSkin(note.id, 'sakura');
  assert.equal(first.repository.readDesktopNote(note.id).title, '更新后的标题');
  assert.equal(first.repository.readDesktopNote(note.id).skinId, 'sakura');
  restarted.store.syncDesktopNotes();
  const latest = restarted.repository.readDesktopNote(note.id);
  assert.equal(restarted.store.findNote(note.id).title, '更新后的标题');
  await restarted.cards.refreshDesktopCards(note.id);
  assert.ok(updates.some(update => update.id === '90071992547409931' && update.data.cardTitle === '更新后的标题'));
  assert.ok(updates.some(update => update.id === '90071992547409932' && update.data.cardTitle === '更新后的标题'));
  restarted.repository.removeDesktopForm('90071992547409931');
  assert.equal(restarted.repository.desktopLink('90071992547409931'), undefined);
  assert.equal(restarted.repository.readDesktopNote(note.id).title, '更新后的标题');

  failedForms.add('90071992547409932');
  const savedDespiteRefresh = restarted.store.saveNoteDraft(request(latest, { title: '落盘成功卡片失败' }));
  assert.equal(savedDespiteRefresh.status, 'saved');
  await flushCards();
  assert.equal(restarted.repository.readDesktopNote(note.id).title, '落盘成功卡片失败');
  failFormsRead = true;
  const savedDespiteRead = restarted.store.saveNoteDraft(request(savedDespiteRefresh.note, { title: '关联读取失败仍保存' }));
  assert.equal(savedDespiteRead.status, 'saved');
  await flushCards();
  failFormsRead = false;
  failedForms.clear();
  const badLink = path.join(temporary, 'desktop-notes/forms/bad.json');
  fs.writeFileSync(badLink, '{');
  await restarted.cards.refreshDesktopCards(note.id);
  assert.ok(updates.some(update => update.id === '90071992547409932' && update.data.cardTitle === '关联读取失败仍保存'));
  fs.unlinkSync(badLink);

  const base = savedDespiteRead.note;
  const empty = restarted.store.saveNoteDraft(request(base, {
    title: ' \n', blocks: [{ id: 'blank', text: '\t\r\n ', imageId: '' }], images: []
  }));
  assert.equal(empty.status, 'empty');
  assert.equal(restarted.repository.readDesktopNote(note.id).title, base.title);
  const imageOnly = restarted.store.saveNoteDraft(request(base, {
    title: '', blocks: [{ id: 'image-a', text: '', imageId: 'image-a' }],
    images: [...images, { ...images[0], id: 'unused' }]
  }));
  assert.equal(imageOnly.status, 'saved');
  assert.equal(imageOnly.note.content, '');
  assert.equal(imageOnly.note.blocks[0].id, 'image-a');
  assert.equal(imageOnly.note.images.length, 1);
  assert.equal(imageOnly.note.images[0].caption, '描述');
  const firstSend = restarted.store.saveNoteDraft({
    id: '', group: '', title: 'new persistent', blocks: [{ id: 'send-text', text: 'a\nb', imageId: '' }],
    images: [], persistToDesktop: true, expectedSnapshot: '', skinId: 'unknown-future-skin'
  });
  assert.equal(firstSend.status, 'saved');
  assert.equal(firstSend.note.content, 'a\nb');
  assert.equal(application().repository.readDesktopNote(firstSend.note.id).skinId, 'unknown-future-skin');
  assert.equal(restarted.cards.desktopCardData(firstSend.note).background, '#FFFFFF');
  const beforeFirstSendFailure = restarted.store.listNotes().length;
  failWrite = true;
  const firstSendFailure = restarted.store.saveNoteDraft({
    id: '', group: '', title: 'must stay unsaved', blocks: [{ id: 'failed', text: 'text', imageId: '' }],
    images: [], persistToDesktop: true
  });
  failWrite = false;
  assert.equal(firstSendFailure.status, 'storageError');
  assert.equal(restarted.store.listNotes().length, beforeFirstSendFailure);

  restarted.store.deleteNote(note.id);
  await flushCards();
  assert.equal(application().store.findNote(note.id), undefined);
  assert.equal(first.store.saveNoteDraft(request(imageOnly.note, { title: 'revive' })).status, 'deleted');
  assert.throws(() => first.store.saveNote({ id: note.id, group: '' }, 'legacy revive', 'no'));
  first.store.moveNote(note.id, 'must not revive');
  first.store.changeNoteSkin(note.id, 'blue');
  assert.equal(first.repository.readDesktopRecord(note.id).deleted, true);
  assert.ok(updates.some(update => update.id === '90071992547409932' && update.data.cardTitle === '笔记已删除'));
  console.log('PASS: selective persistence, restart, attachments, metadata without lost updates, save conflict/deletion, blank/image-only rules, first export rollback, disk/rename failure, isolated temporary writes, refresh failure isolation, multiple cards and tombstones');
}
run().finally(() => {
  const resolved = path.resolve(temporary);
  if (resolved.startsWith(validationRoot + path.sep)) {
    fs.rmSync(resolved, { recursive: true, force: true });
  }
}).catch(error => { console.error(error); process.exitCode = 1; });
