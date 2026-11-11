const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const hdc = process.env.HDC_PATH || 'E:/Softs/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'note-database-demo-'));
function command(...args) {
  const value = cp.execFileSync(hdc, args, { encoding: 'utf8', timeout: 30000, windowsHide: true });
  if (/\[Fail\]|Error Code:|error:/i.test(value)) throw new Error(value);
  return value;
}
function snapshot() {
  command('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/note-database-demo.json');
  command('file', 'recv', '/data/local/tmp/note-database-demo.json', path.join(output, 'latest.json'));
  const tree = JSON.parse(fs.readFileSync(path.join(output, 'latest.json'), 'utf8'));
  const nodes = [];
  function walk(node) {
    if (node.attributes) nodes.push(node.attributes);
    (node.children || []).forEach(walk);
  }
  walk(tree);
  return { tree, nodes };
}
function point(node, action = 'click') {
  assert.ok(node, 'missing target');
  const box = node.bounds.match(/\d+/g).map(Number);
  command('shell', 'uitest', 'uiInput', action, String(Math.floor((box[0] + box[2]) / 2)), String(Math.floor((box[1] + box[3]) / 2)));
}
function button(text) {
  point(snapshot().nodes.find(node => node.type === 'Button' && node.text === text));
}
function openFromHome() {
  const home = snapshot();
  point(home.nodes.find(node => node.type === 'Row' && node.longClickable === 'true'), 'longClick');
  const directory = snapshot();
  function contains(node, text) {
    return node.attributes?.text === text || (node.children || []).some(child => contains(child, text));
  }
  function item(node) {
    if (node.attributes?.type === 'ListItem' && contains(node, '数据库与位置存储')) return node;
    for (const child of node.children || []) {
      const found = item(child);
      if (found) return found;
    }
  }
  function findButton(node) {
    if (node.attributes?.type === 'Button' && node.attributes.text === '打开实验') return node.attributes;
    for (const child of node.children || []) {
      const found = findButton(child);
      if (found) return found;
    }
  }
  const target = item(directory.tree);
  assert.ok(target, 'database demo absent from catalog');
  point(findButton(target));
}
function result(expected) {
  for (let attempt = 0; attempt < 12; attempt++) {
    const nodes = snapshot().nodes;
    const texts = nodes.map(node => node.text || '');
    const failure = texts.find(text => text.startsWith('试验失败'));
    assert.ok(!failure, failure);
    if (texts.includes(expected)) {
      const lines = texts.filter(text => text.startsWith('通过：'));
      console.log(JSON.stringify({ status: expected, lines }));
      return lines;
    }
  }
  throw new Error(`timed out: ${expected}`);
}
const results = [];
try {
  let current = snapshot();
  if (!current.nodes.some(node => node.text === '数据库与位置存储试验')) {
    assert.ok(current.nodes.some(node => node.text === '笔记'), 'start at app home or DatabaseDemo');
    openFromHome();
  }
  button('运行完整试验');
  const first = result('数据库试验全部通过');
  assert.equal(first.length, 5);
  results.push({ run: 'first', lines: first });
  button('运行完整试验');
  const second = result('数据库试验全部通过');
  assert.equal(second.length, 5);
  results.push({ run: 'repeat', lines: second });
  command('shell', 'aa', 'force-stop', 'com.example.note_by_agent');
  command('shell', 'aa', 'start', '-b', 'com.example.note_by_agent', '-a', 'EntryAbility');
  openFromHome();
  button('复验上次落盘');
  results.push({ run: 'process-restart', lines: result('落盘复验通过') });
} finally {
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`Artifacts: ${output}`);
}
