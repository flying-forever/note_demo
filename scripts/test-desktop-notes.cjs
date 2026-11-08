const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'note-desktop-test-'));
const updates = [];
let failWrite = false;
const fileIo = {
  OpenMode: { CREATE: fs.constants.O_CREAT, WRITE_ONLY: fs.constants.O_WRONLY, TRUNC: fs.constants.O_TRUNC },
  accessSync: fs.existsSync,
  mkdirSync: (name, recursive) => fs.mkdirSync(name, { recursive }),
  openSync: (name, mode) => {
    if (failWrite) throw new Error('simulated disk error');
    return { fd: fs.openSync(name, mode) };
  },
  writeSync: fs.writeSync, fsyncSync: fs.fsyncSync, closeSync: file => fs.closeSync(file.fd),
  renameSync: fs.renameSync, readTextSync: name => fs.readFileSync(name, 'utf8'),
  listFileSync: fs.readdirSync, unlinkSync: fs.unlinkSync
};
function application() {
  const modules = {};
  function load(name) {
    if (modules[name]) return modules[name];
    const exports = {};
    modules[name] = exports;
    const source = fs.readFileSync(path.join(__dirname, '../note_by_agent/entry/src/main/ets/model/', name + '.ets'), 'utf8');
    const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    vm.runInNewContext(code, { exports, Date, encodeURIComponent, decodeURIComponent,
      require: dependency => {
        if (dependency === '@kit.CoreFileKit') return { fileIo };
        if (dependency === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
        if (dependency === '@kit.FormKit') return {
          formBindingData: { createFormBindingData: data => data },
          formProvider: { updateForm: async (id, data) => { updates.push({ id, data }); } }
        };
        return load(dependency.replace('./', ''));
      }
    });
    return exports;
  }
  const repository = load('DesktopNoteRepository');
  repository.initializeDesktopRepository(temporary);
  const store = load('NoteStore');
  store.syncDesktopNotes();
  return { repository, store };
}
async function run() {
  const first = application();
  const draftParams = { id: '', group: '旅途' };
  const transient = first.store.saveNote(draftParams, 'temporary', 'not exported');
  assert.equal(first.repository.readDesktopNote(transient.id), undefined);
  const blocks = [{ id: 'text-a', text: '正文', imageId: '' }, { id: 'image-a', text: '', imageId: 'image-a' }];
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
  const persisted = restarted.repository.readDesktopNote(note.id);
  assert.equal(persisted.skinId, 'green');
  assert.equal(persisted.group, '美食');
  assert.equal(persisted.images[0].small, true);
  failWrite = true;
  assert.throws(() => restarted.store.saveNote({ id: note.id, group: '' }, 'failed', 'failed'));
  failWrite = false;
  assert.equal(restarted.store.findNote(note.id).title, '桌面笔记');
  const external = { ...persisted, title: '半模态更新' };
  restarted.repository.persistDesktopNote(external);
  restarted.store.syncDesktopNotes();
  assert.equal(restarted.store.findNote(note.id).title, '半模态更新');
  await restarted.repository.refreshDesktopCards(note.id);
  assert.ok(updates.some(update => update.id === '90071992547409931' && update.data.cardTitle === '半模态更新'));
  assert.ok(updates.some(update => update.id === '90071992547409932' && update.data.cardTitle === '半模态更新'));
  restarted.repository.removeDesktopForm('90071992547409931');
  assert.equal(restarted.repository.desktopLink('90071992547409931'), undefined);
  assert.equal(restarted.repository.readDesktopNote(note.id).title, '半模态更新');
  restarted.store.deleteNote(note.id);
  await new Promise(setImmediate);
  assert.equal(application().store.findNote(note.id), undefined);
  assert.ok(updates.some(update => update.id === '90071992547409932' && update.data.cardTitle === '笔记已删除'));
  console.log('PASS: selective persistence, restart, image references, skin/folder updates, disk failure, external edits, multiple cards, unbinding and deletion tombstones');
}
run().finally(() => {
  if (temporary.startsWith(path.join(os.tmpdir(), 'note-desktop-test-'))) {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}).catch(error => { console.error(error); process.exitCode = 1; });
