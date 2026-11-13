// 运行真实刷新方法，回归输入期间窗口连续性、帧合并及失效遮挡。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const filename = path.join(__dirname, '../note_by_agent/entry/src/main/ets/pages/PrivacyEditorDemo.ets');
const source = fs.readFileSync(filename, 'utf8').replace(/\r\n/g, '\n');
function method(name) {
  const start = source.indexOf('  private ' + name + '(');
  assert.notEqual(start, -1, 'Missing real method ' + name);
  const end = source.indexOf('\n  }\n', start);
  assert.notEqual(end, -1);
  const fn = source.slice(start, end + 4).replace('private ' + name, 'function ' + name);
  const js = ts.transpileModule(fn, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  return vm.runInNewContext(js + '\n' + name, {
    LINE_HEIGHT: 30,
    DemoFrameProbe: class { constructor(callback) { this.callback = callback; } }
  }, { filename: 'PrivacyEditorDemo.' + name });
}
const refresh = method('refresh');
const conceal = method('conceal');
const lineView = method('lineView');
function fixture() {
  const frames = [];
  const draws = [];
  const caret = { x: 80, y: 32 };
  const context = {
    postFrameCallback: frame => frames.push(frame.callback),
    px2vp: value => value / 2
  };
  const editor = {
    alive: true, visible: true, windowActive: true, focused: true, paused: false,
    valid: true, holding: false, queued: false, epoch: 1,
    previousLine: false, editorHeight: 300, holdFinger: -1,
    controller: { getCaretOffset: () => caret, getTextContentRect: () => ({ y: 32 }) },
    getUIContext: () => context,
    drawMask() { draws.push({ visible: lineView.call(this), holding: this.holding }); }
  };
  const flush = () => { assert.equal(frames.length, 1); frames.shift()(); };
  return { editor, frames, draws, caret, flush };
}
{
  const { editor, frames, draws, caret, flush } = fixture();
  for (let frame = 0; frame < 100; frame++) {
    for (let event = 0; event < 6; event++) {
      refresh.call(editor);
      assert.equal(lineView.call(editor), true, 'Typing must retain the bounded window while queued');
    }
    assert.equal(frames.length, 1, 'Repeated input and selection callbacks coalesce');
    assert.equal(draws.length, frame, 'No interim opaque repaint during normal typing');
    caret.x += 2;
    flush();
    assert.equal(editor.caretX, caret.x / 2, 'Frame uses latest native coordinates');
  }
  assert.equal(draws.length, 100);
  assert(draws.every(draw => draw.visible), 'No hidden-window frame inserted into the typing sequence');
}
{
  const { editor, draws, flush } = fixture();
  refresh.call(editor, true);
  assert.equal(editor.valid, false);
  assert.equal(draws[0].visible, false, 'Scroll/resize invalidation conceals immediately');
  flush();
  assert.equal(draws.at(-1).visible, true);
}
for (const state of ['paused', 'background', 'gone', 'old-session']) {
  const { editor, draws, flush } = fixture();
  refresh.call(editor);
  conceal.call(editor);
  if (state === 'background') editor.windowActive = false;
  if (state === 'gone') editor.alive = false;
  if (state === 'old-session') editor.epoch++;
  flush();
  assert.equal(editor.valid, false, state + ': queued refresh must not reopen');
  assert(draws.every(draw => !draw.visible), state + ': only concealed frames');
}
for (const invalid of ['offscreen', 'nan', 'throws']) {
  const { editor, draws, caret, flush } = fixture();
  refresh.call(editor);
  if (invalid === 'offscreen') caret.y = 900;
  if (invalid === 'nan') caret.x = NaN;
  if (invalid === 'throws') editor.controller.getCaretOffset = () => { throw new Error('unavailable'); };
  flush();
  assert.equal(editor.valid, false, invalid + ': invalid geometry closes the window');
  assert.equal(draws.at(-1).visible, false);
}
console.log('PASS: 600 input callbacks / 100 frames retain visibility; invalidation, lifecycle and bad geometry conceal');
