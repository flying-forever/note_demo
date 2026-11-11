// 通过设备界面操作回归检查首页与长文实验的当前交互流程。
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const hdc = process.env.HDC_PATH || 'E:/Softs/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const output = path.resolve(__dirname, '../note_by_agent/build/verification');
fs.mkdirSync(output, { recursive: true });
function command(...args) {
  const value = cp.execFileSync(hdc, args, { encoding: 'utf8', timeout: 30000, windowsHide: true });
  if (/\[Fail\]|Error Code:|error:/i.test(value)) throw new Error(value);
  return value;
}
function nodes(label = 'latest') {
  command('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/note-cycle.json');
  const file = path.join(output, label + '.json');
  command('file', 'recv', '/data/local/tmp/note-cycle.json', file);
  const all = [];
  function walk(node) {
    if (node.attributes) all.push(node.attributes);
    (node.children || []).forEach(walk);
  }
  walk(JSON.parse(fs.readFileSync(file, 'utf8')));
  return all;
}
function bounds(node) { return node.bounds.match(/-?\d+/g).map(Number); }
function tap(node) {
  assert.ok(node, 'UI node missing');
  const b = bounds(node);
  command('shell', 'uitest', 'uiInput', 'click', String(Math.round((b[0] + b[2]) / 2)), String(Math.round((b[1] + b[3]) / 2)));
}
function text(value, all = nodes()) { return all.find(n => n.text === value); }
function swipe(x1, y1, x2, y2) {
  command('shell', 'uitest', 'uiInput', 'swipe', ...[x1, y1, x2, y2].map(String), '600');
}
function homeHeader() {
  let all = nodes();
  tap(text('未分类', all));
  all = nodes('home-before');
  const before = bounds(text('未分类', all))[1];
  swipe(750, 1500, 750, 800);
  all = nodes('home-collapsed');
  const after = bounds(text('未分类', all))[1];
  assert.ok(after < before - 70, `short group header did not collapse: ${before} -> ${after}`);
  const stable = bounds(text('未分类', nodes('home-settled')))[1];
  assert.equal(stable, after, 'bounce reopened header');
  swipe(750, 850, 750, 1550);
  const restored = bounds(text('未分类', nodes('home-expanded')))[1];
  assert.ok(restored > after + 70, 'pull did not restore header');
  console.log(JSON.stringify({ check: 'short-group header collapse/bounce/pull', before, after, stable, restored }));
}
function longPosition() {
  for (let i = 0; i < 12; i++) swipe(900, 2250, 900, 650);
  const before = nodes('long-bottom-before').find(n => n.type === 'Text' && n.text.startsWith('第1段'));
  assert.ok(before, 'open long test note before this check');
  command('shell', 'uitest', 'uiInput', 'click', '900', '2000');
  const editing = nodes('long-bottom-edit').find(n => n.type === 'TextArea');
  assert.ok(editing && editing.focused === 'true');
  assert.equal(editing.text, before.text, 'mode switch changed text');
  assert.equal(editing.origBounds, before.origBounds, 'entering edit changed scroll position');
  command('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');
  const returned = nodes('long-bottom-return').find(n => n.type === 'Text' && n.text.startsWith('第1段'));
  assert.equal(returned.origBounds, before.origBounds, 'leaving edit changed scroll position');
  const result = { check: 'long-note bottom mode switch', before: before.origBounds,
    editing: editing.origBounds, returned: returned.origBounds, characters: before.text.length };
  fs.writeFileSync(path.join(output, 'long-position-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
if (require.main === module) {
  const action = process.argv[2];
  if (action === 'home') homeHeader();
  else if (action === 'long') longPosition();
  else if (action === 'dump') {
    const all = nodes(process.argv[3] || 'latest');
    console.log(JSON.stringify(all.filter(n => n.text || n.type === 'Button' || n.type === 'TextArea')
      .map(n => ({ type: n.type, text: n.text?.slice(0, 70), id: n.id, description: n.description,
        bounds: n.bounds, focused: n.focused })), null, 2));
  } else throw new Error('Use home or dump');
}
module.exports = { command, nodes, bounds, tap, text, swipe, output };
