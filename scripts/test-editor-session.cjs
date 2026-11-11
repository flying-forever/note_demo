// 回归验证编辑会话的输入合并、撤销重做、图片与脏状态跟踪。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');

const root = path.resolve(__dirname, '../note_by_agent/entry/src/main/ets');
const cache = new Map();
let now = 100000;
class TestDate extends Date {
  static now() { return now; }
}
function load(relative) {
  const filename = path.resolve(root, relative + '.ets');
  assert.ok(filename.startsWith(root + path.sep), 'Only load application modules');
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const source = fs.readFileSync(filename, 'utf8').replace(/^@Observed\s*$/gm, '');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true
  });
  const errors = (compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, 'Transpile failed: ' + errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));
  vm.runInNewContext(compiled.outputText, {
    exports, Date: TestDate,
    require: dependency => {
      assert.ok(dependency.startsWith('.'), 'Unexpected platform dependency: ' + dependency);
      return load(path.relative(root, path.resolve(path.dirname(filename), dependency)));
    }
  }, { filename });
  return exports;
}

const { NoteEditorSession } = load('viewmodel/NoteEditorSession');
const { textBlock, documentText, copyImage } = load('model/NoteDocument');
const note = (content = '原文') => ({ id: 'session-test', title: '原标题', content, timeLabel: '', group: '' });
const image = id => ({ id, path: '/private/' + id, name: id, width: 100, height: 80, bytes: 50, caption: '', small: false });
function session(content) {
  const result = new NoteEditorSession();
  result.load(note(content));
  return result;
}
let passed = 0;
function test(name, run) {
  now += 10000;
  run();
  passed++;
  console.log('PASS: ' + name);
}

test('IME preview does not enter title or body history before commit', () => {
  for (const field of ['title', 'body']) {
    const s = session();
    const id = s.activeBlock;
    const change = (value, previewing) => field === 'title' ? s.changeTitle(value, previewing) : s.changeBlock(value, id, previewing);
    change('拼', true);
    change('拼音', true);
    assert.equal(s.canUndo, false);
    assert.equal(s.canRedo, false);
    change('拼音', false);
    assert.equal(s.canUndo, true);
    s.restoreHistory(false);
    assert.equal(field === 'title' ? s.title : s.content, field === 'title' ? '原标题' : '原文');
    s.restoreHistory(true);
    assert.equal(field === 'title' ? s.title : s.content, '拼音');
  }
});

test('continuous input merges, inactivity and field changes separate groups', () => {
  const s = session();
  s.changeTitle('一', false);
  now += 100;
  s.changeTitle('一二', false);
  now += 1999;
  s.changeTitle('一二三', false);
  s.restoreHistory(false);
  assert.equal(s.title, '原标题');
  s.restoreHistory(true);
  assert.equal(s.title, '一二三');
  now += 2000;
  s.changeTitle('另一段', false);
  s.changeBlock('正文修改', s.activeBlock, false);
  s.restoreHistory(false);
  assert.equal(s.title, '另一段');
  assert.equal(s.content, '原文');
  s.restoreHistory(false);
  assert.equal(s.title, '一二三');
  const timed = session();
  timed.changeTitle('第一段', false);
  now += 1999;
  timed.changeTitle('第一段续写', false);
  now += 2000;
  timed.changeTitle('第二段', false);
  timed.restoreHistory(false);
  assert.equal(timed.title, '第一段续写');
  timed.restoreHistory(false);
  assert.equal(timed.title, '原标题');
});

test('explicit grouping and paste create independent undo steps', () => {
  const s = session('');
  const id = s.activeBlock;
  s.changeBlock('a', id, false);
  s.closeGroup();
  s.changeBlock('ab', id, false);
  s.preparePaste();
  s.changeBlock('ab粘', id, true);
  s.changeBlock('ab粘贴', id, false);
  s.changeBlock('ab粘贴c', id, false);
  for (const expected of ['ab粘贴', 'ab', 'a', '']) {
    s.restoreHistory(false);
    assert.equal(s.content, expected);
  }
  for (const expected of ['a', 'ab', 'ab粘贴', 'ab粘贴c']) {
    s.restoreHistory(true);
    assert.equal(s.content, expected);
  }
});

test('new input after undo discards redo without merging into baseline', () => {
  const s = session();
  s.changeBlock('第一版', s.activeBlock, false);
  s.closeGroup();
  s.changeBlock('第二版', s.activeBlock, false);
  s.restoreHistory(false);
  assert.equal(s.canRedo, true);
  s.changeBlock('新分支', s.activeBlock, false);
  assert.equal(s.canRedo, false);
  s.restoreHistory(false);
  assert.equal(s.content, '第一版');
  s.restoreHistory(true);
  assert.equal(s.content, '新分支');
});

test('image insertion splits text, deletion and undo preserve subsequent input', () => {
  const s = session('abcd');
  const first = s.activeBlock;
  const after = s.insertImage(image('photo'), first, 2);
  assert.equal(s.blocks.length, 3);
  assert.equal(s.blockText(first), 'ab');
  assert.equal(s.blocks[1].imageId, 'photo');
  assert.equal(s.blockText(after), 'cd');
  assert.equal(s.activeBlock, after);
  assert.equal(s.caret, 0);
  assert.equal(s.content, 'ab\ncd');
  s.removeImage('photo');
  assert.equal(s.hasImages(), false);
  assert.equal(s.referencedImages().length, 0);
  s.restoreHistory(false);
  assert.equal(s.hasImages(), true);
  s.restoreHistory(true);
  assert.equal(s.hasImages(), false);
  s.restoreHistory(false);
  s.changeBlock('cd继续', after, false);
  assert.equal(s.content, 'ab\ncd继续');
  assert.equal(s.hasImages(), true);
  assert.equal(s.canRedo, false);
  s.restoreHistory(false);
  assert.equal(s.content, 'ab\ncd');
  s.restoreHistory(false);
  assert.equal(s.content, 'abcd');
  assert.equal(s.hasImages(), false);
  s.changeBlock('abcd继续', first, false);
  assert.equal(s.content, 'abcd继续');
  assert.equal(s.canRedo, false);
});

test('image split clamps caret at both text boundaries', () => {
  for (const [offset, before, after] of [[-10, '', '原文'], [999, '原文', '']]) {
    const s = session();
    s.insertImage(image('boundary-' + offset), s.activeBlock, offset);
    assert.equal(s.blocks[0].text, before);
    assert.equal(s.blocks[2].text, after);
    s.restoreHistory(false);
    assert.equal(s.content, '原文');
  }
});

test('caption and small metadata remain outside text/image undo history', () => {
  const s = session('正文');
  const after = s.insertImage(image('metadata'), s.activeBlock, 2);
  s.markSaved();
  s.images = s.images.map(item => copyImage(item, '图片描述', true));
  assert.equal(s.isDirty(), true);
  s.restoreHistory(false);
  assert.equal(s.hasImages(), false, 'Metadata changes must not add an undo step');
  assert.equal(s.imageItem('metadata').caption, '图片描述');
  assert.equal(s.imageItem('metadata').small, true);
  s.restoreHistory(true);
  assert.equal(s.hasImages(), true);
  s.changeBlock('图片之后', after, false);
  s.restoreHistory(false);
  assert.equal(s.imageItem('metadata').caption, '图片描述');
  assert.equal(s.imageItem('metadata').small, true);
});

test('dirty state tracks saved title, blocks and image metadata', () => {
  const s = session();
  assert.equal(s.isDirty(), false);
  s.changeTitle('保存的标题', false);
  assert.equal(s.isDirty(), true);
  s.markSaved();
  assert.equal(s.isDirty(), false);
  s.closeGroup();
  s.changeTitle('后续修改', false);
  assert.equal(s.isDirty(), true);
  s.restoreHistory(false);
  assert.equal(s.isDirty(), false);
  s.changeBlock('正文修改', s.activeBlock, false);
  assert.equal(s.isDirty(), true);
  s.markSaved();
  assert.equal(s.isDirty(), false);
  s.insertImage(image('dirty-image'), s.activeBlock, 0);
  assert.equal(s.isDirty(), true);
  s.markSaved();
  s.images = s.images.map(item => copyImage(item, '修改描述'));
  assert.equal(s.isDirty(), true);
  s.markSaved();
  assert.equal(s.isDirty(), false);
});

test('exported image references exclude unused assets and preserve redo assets', () => {
  const s = session();
  s.insertImage(image('used'), s.activeBlock, 0);
  s.images = [...s.images, image('unused')];
  assert.equal(s.referencedImages().map(item => item.id).join(','), 'used');
  s.restoreHistory(false);
  assert.equal(s.referencedImages().length, 0);
  assert.equal(s.images.length, 2);
  s.restoreHistory(true);
  assert.equal(s.referencedImages().map(item => item.id).join(','), 'used');
});

test('legacy and block input preserve documentText newline export semantics', () => {
  for (const value of ['', '\n', '甲\n\n乙\n', '甲\r\n乙', '中文😀']) {
    const s = session(value);
    assert.equal(s.content, value);
    s.changeBlock(value, s.activeBlock, false);
    assert.equal(s.content, value);
  }
  const source = note('legacy fallback must not replace blocks');
  source.blocks = [textBlock('甲\n'), { id: 'photo', text: '', imageId: 'photo' }, textBlock('\n乙\r\n')];
  source.images = [image('photo')];
  const s = new NoteEditorSession();
  s.load(source);
  assert.equal(s.content, documentText(source.blocks));
  assert.equal(s.content, '甲\n\n\n乙\r\n');
  s.changeBlock(s.blockText(s.activeBlock), s.activeBlock, false);
  s.images[0].caption = 'session-local';
  assert.equal(source.images[0].caption, '', 'Loading must copy image metadata');
  s.changeBlock('修改', s.activeBlock, false);
  assert.equal(source.blocks[0].text, '甲\n', 'Loading must copy body blocks');
});

test('identical input does not add history or dirty state', () => {
  for (const value of ['', '\n', '甲\n\n乙\n', '甲\r\n乙', '中文😀']) {
    const s = session(value);
    s.changeBlock(value, s.activeBlock, false);
    assert.equal(s.canUndo, false, `Identical body input ${JSON.stringify(value)} must not add history`);
    assert.equal(s.isDirty(), false, 'Identical body input must not mark a clean note dirty');
    s.changeTitle(s.title, false);
    assert.equal(s.canUndo, false);
    assert.equal(s.isDirty(), false);
  }
});

console.log(`PASS: ${passed} editor session behavior scenarios; no filesystem or platform writes`);
