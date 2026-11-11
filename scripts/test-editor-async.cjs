// 通过延迟异步结果模拟编辑场景，回归验证编辑器状态与竞态处理。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');

const root = path.resolve(__dirname, '../note_by_agent/entry/src/main/ets');
const editorSource = fs.readFileSync(path.join(root, 'pages/NoteEditor.ets'), 'utf8').replace(/\r\n/g, '\n');
const modules = new Map();
function transpile(source, filename) {
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true
  });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, filename + ': ' + errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));
  return result.outputText;
}
function load(relative) {
  const filename = path.resolve(root, relative + '.ets');
  assert.ok(filename.startsWith(root + path.sep));
  if (modules.has(filename)) return modules.get(filename);
  const exports = {};
  modules.set(filename, exports);
  const source = fs.readFileSync(filename, 'utf8').replace(/^@Observed\s*$/gm, '');
  vm.runInNewContext(transpile(source, filename), {
    exports, Date,
    require: dependency => {
      assert.ok(dependency.startsWith('.'), 'Unexpected platform dependency: ' + dependency);
      return load(path.relative(root, path.resolve(path.dirname(filename), dependency)));
    }
  }, { filename });
  return exports;
}
const { NoteEditorSession } = load('viewmodel/NoteEditorSession');

function editorMethod(name, environment) {
  const marker = '  private async ' + name + '(';
  const start = editorSource.indexOf(marker);
  assert.notEqual(start, -1, 'Missing real editor method: ' + name);
  const end = editorSource.indexOf('\n  }\n', start);
  assert.notEqual(end, -1, 'Missing method end: ' + name);
  const source = editorSource.slice(start, end + 4).replace('private async ' + name, 'async function ' + name);
  return vm.runInNewContext(transpile(source, name) + '\n' + name, environment, { filename: 'NoteEditor.' + name });
}
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const tick = () => new Promise(setImmediate);
const image = id => ({ id, path: '/private/' + id, name: id, width: 100, height: 80, bytes: 50, caption: '', small: false });
const note = (id, title = id) => ({ id, title, content: 'body-' + id, timeLabel: '', group: '旅途', skinId: 'white' });

function fixture() {
  const dialog = deferred();
  const picker = deferred();
  const imported = deferred();
  const events = [];
  const saves = [];
  let dialogs = 0;
  let imports = 0;
  let routeParams;
  let result = { status: 'saved', note: note('new-A') };
  const session = new NoteEditorSession();
  session.load(note('A'));
  session.changeTitle('local draft A', false);
  session.images = [image('draft-image-A')];
  const originalImages = session.images;
  const originalLoad = session.load.bind(session);
  session.load = value => { events.push({ kind: 'load', id: value?.id }); originalLoad(value); };
  const originalInsert = session.insertImage.bind(session);
  session.insertImage = (item, target, offset) => {
    events.push({ kind: 'insert', image: item.id, route: page.params.id, target });
    return originalInsert(item, target, offset);
  };
  const page = {
    session, disposed: false, sessionGeneration: 1, deletionPromptVisible: false,
    pickingImage: false, editing: false, params: { id: 'A', group: '旅途' }, original: note('A'),
    selectedGroup: '旅途', skinId: 'white',
    getUIContext: () => ({
      getHostContext: () => ({ filesDir: '/private' }),
      getPromptAction: () => ({
        showDialog: () => { dialogs++; return dialog.promise; },
        showToast: value => events.push({ kind: 'toast', message: value.message })
      }),
      getRouter: () => ({ getParams: () => routeParams, back: () => events.push({ kind: 'back' }) })
    })
  };
  routeParams = page.params;
  const environment = {
    $r: value => value,
    listNotes: () => [],
    releaseUnusedImages: items => events.push({ kind: 'release', ids: Array.from(items, item => item.id) }),
    saveNoteDraft: request => { saves.push(request); return result; },
    importNoteImage: () => { imports++; return imported.promise; },
    photoAccessHelper: {
      PhotoSelectOptions: class {}, PhotoViewMIMETypes: { IMAGE_TYPE: 'image' },
      PhotoViewPicker: class { select() { return picker.promise; } }
    }
  };
  return {
    page, dialog, picker, imported, events, saves, originalImages,
    method: name => editorMethod(name, environment),
    dialogs: () => dialogs, imports: () => imports, setSaveResult: value => { result = value; },
    switchNote: () => {
      page.sessionGeneration++;
      page.params = { id: 'B', group: '' };
      routeParams = page.params;
      page.original = note('B');
      page.session.load(page.original);
      events.length = 0;
    }
  };
}

let passed = 0;
async function test(name, run) {
  await run();
  passed++;
  console.log('PASS: ' + name);
}
async function run() {
  await test('old external-version dialog cannot change another note for either choice', async () => {
    for (const index of [0, 1]) {
      const f = fixture();
      const pending = f.method('refreshExternalNote').call(f.page, note('A', 'external A'));
      f.switchNote();
      f.dialog.resolve({ index });
      await pending;
      assert.equal(f.page.original.id, 'B');
      assert.equal(f.page.session.title, 'B');
      assert.equal(f.page.params.id, 'B');
      assert.equal(f.events.length, 0);
    }
  });
  await test('accepted external version releases abandoned images before replacing the real session', async () => {
    const f = fixture();
    const generation = f.page.sessionGeneration;
    const pending = f.method('refreshExternalNote').call(f.page, note('A', 'external A'));
    f.dialog.resolve({ index: 1 });
    await pending;
    assert.equal(f.page.session.title, 'external A');
    assert.equal(f.page.session.isDirty(), false);
    assert.ok(f.page.sessionGeneration > generation);
    assert.equal(f.events[0].kind, 'release');
    assert.deepEqual(f.events[0].ids, ['draft-image-A']);
    assert.equal(f.events[1].kind, 'load');
  });
  await test('stale picker completion starts no file import', async () => {
    const f = fixture();
    const pending = f.method('insertImage').call(f.page);
    f.switchNote();
    f.picker.resolve({ photoUris: ['image-A'] });
    await pending;
    assert.equal(f.imports(), 0);
    assert.equal(f.events.length, 0);
    assert.equal(f.page.session.images.length, 0);
  });
  await test('stale or disposed image import releases its result without inserting it', async () => {
    for (const dispose of [false, true]) {
      const f = fixture();
      const pending = f.method('insertImage').call(f.page);
      f.picker.resolve({ photoUris: ['image-A'] });
      await tick();
      assert.equal(f.imports(), 1);
      if (dispose) { f.page.disposed = true; } else { f.switchNote(); }
      f.imported.resolve(image('late-image-A'));
      await pending;
      assert.equal(f.events.some(event => event.kind === 'insert'), false);
      assert.deepEqual(f.events.filter(event => event.kind === 'release').map(event => event.ids), [['late-image-A']]);
    }
  });
  await test('current image import still inserts into the real session', async () => {
    const f = fixture();
    const pending = f.method('insertImage').call(f.page);
    f.picker.resolve({ photoUris: ['image-A'] });
    await tick();
    f.imported.resolve(image('current-image'));
    await pending;
    assert.equal(f.events.filter(event => event.kind === 'insert').length, 1);
    assert.equal(f.events.some(event => event.kind === 'release'), false);
    assert.equal(f.page.session.hasImages(), true);
    assert.equal(f.page.pickingImage, false);
  });
  await test('deleted-note save-as requests a fresh identity and keeps the draft', async () => {
    const f = fixture();
    const pending = f.method('resolveDeletedNote').call(f.page);
    f.dialog.resolve({ index: 0 });
    await pending;
    assert.equal(f.saves.length, 1);
    assert.equal(f.saves[0].id, '');
    assert.equal(f.saves[0].expectedSnapshot, '');
    assert.equal(f.saves[0].title, 'local draft A');
    assert.equal(f.page.params.id, 'new-A');
    assert.equal(f.page.getUIContext().getRouter().getParams().id, 'new-A',
      'The router parameter reference must follow the saved identity to avoid reloading the tombstone on page show');
    assert.equal(f.page.original.id, 'new-A');
    assert.equal(f.page.session.title, 'local draft A');
    assert.equal(f.page.session.isDirty(), false);
    assert.equal(f.events.some(event => event.kind === 'release' || event.kind === 'back'), false);
    assert.equal(f.page.deletionPromptVisible, false);
  });
  await test('deleted-note discard releases draft images and exits without saving', async () => {
    const f = fixture();
    const pending = f.method('resolveDeletedNote').call(f.page);
    f.dialog.resolve({ index: 1 });
    await pending;
    assert.equal(f.saves.length, 0);
    assert.equal(f.events[0].kind, 'release');
    assert.deepEqual(f.events[0].ids, ['draft-image-A']);
    assert.equal(f.events[1].kind, 'back');
    assert.equal(f.page.session.isDirty(), false);
  });
  await test('failed deleted-note save-as preserves unsaved content and images', async () => {
    const f = fixture();
    f.setSaveResult({ status: 'storageError' });
    const pending = f.method('resolveDeletedNote').call(f.page);
    f.dialog.resolve({ index: 0 });
    await pending;
    assert.equal(f.page.params.id, 'A');
    assert.equal(f.page.session.isDirty(), true);
    assert.equal(f.page.session.images, f.originalImages);
    assert.equal(f.events.some(event => event.kind === 'release' || event.kind === 'back'), false);
  });
  await test('stale deleted-note prompt cannot save or discard another note', async () => {
    for (const index of [0, 1]) {
      const f = fixture();
      const pending = f.method('resolveDeletedNote').call(f.page);
      f.switchNote();
      f.dialog.resolve({ index });
      await pending;
      assert.equal(f.saves.length, 0);
      assert.equal(f.page.params.id, 'B');
      assert.equal(f.events.length, 0);
    }
  });
  await test('deleted-note prompt is not duplicated while awaiting a choice', async () => {
    const f = fixture();
    const resolve = f.method('resolveDeletedNote');
    const pending = resolve.call(f.page);
    await resolve.call(f.page);
    assert.equal(f.dialogs(), 1);
    f.dialog.resolve({ index: 1 });
    await pending;
  });
  console.log('PASS: ' + passed + ' async editor behavior groups using current page methods and real NoteEditorSession');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
