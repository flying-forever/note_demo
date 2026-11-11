// 通过设备操作验证原生编辑器选区与编辑行为，并采集内存信息。
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const hdc = process.env.HDC_PATH || 'E:/Softs/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'note-native-editor-'));
const results = [];
let transientSnapshots = 0;
function command(...args) {
  const value = cp.execFileSync(hdc, args, { encoding: 'utf8', timeout: 30000, windowsHide: true });
  if (/\[Fail\]|Error Code:|error:/i.test(value)) throw new Error(value);
  return value;
}
function snapshot() {
  command('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/note-native-editor.json');
  command('file', 'recv', '/data/local/tmp/note-native-editor.json', path.join(output, 'latest.json'));
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
  for (let attempt = 0; attempt < 6; attempt++) {
    const target = snapshot().nodes.find(node => node.type === 'Button' && node.text === text && node.enabled === 'true');
    if (target) {
      point(target);
      return;
    }
    transientSnapshots++;
  }
  assert.fail(`button not ready: ${text}`);
}
function choose(desired, opposite) {
  if (!snapshot().nodes.some(node => node.type === 'Button' && node.text === desired)) button(opposite);
}
function status(pattern) {
  let all = [];
  for (let attempt = 0; attempt < 6; attempt++) {
    all = snapshot().nodes;
    const found = all.find(node => pattern.test(node.text || ''));
    if (found) return found.text;
  }
  assert.fail(`missing status ${pattern}: ${all.filter(node => node.type === 'Text' && node.text.length < 150).map(node => node.text).join(' | ')}`);
}
function open() {
  const state = snapshot();
  if (state.nodes.some(node => node.text === '原生跨片段编辑试验')) return;
  assert.ok(state.nodes.some(node => node.text === '笔记'), 'start at home or native editor demo');
  point(state.nodes.find(node => node.type === 'Row' && node.longClickable === 'true'), 'longClick');
  function contains(node, text) {
    return node.attributes?.text === text || (node.children || []).some(child => contains(child, text));
  }
  function item(node) {
    if (node.attributes?.type === 'ListItem' && contains(node, '原生跨片段编辑')) return node;
    for (const child of node.children || []) {
      const found = item(child);
      if (found) return found;
    }
  }
  function launch(node) {
    if (node.attributes?.type === 'Button' && node.attributes.text === '打开实验') return node.attributes;
    for (const child of node.children || []) {
      const found = launch(child);
      if (found) return found;
    }
  }
  const entry = item(snapshot().tree);
  assert.ok(entry, 'native editor demo absent');
  point(launch(entry));
}
function memory(label) {
  const pid = command('shell', 'pidof', 'com.example.note_by_agent').trim();
  assert.match(pid, /^\d+$/);
  const report = command('shell', 'hidumper', '--mem', pid);
  fs.writeFileSync(path.join(output, `${label}-memory.txt`), report);
  const total = report.match(/^\s*Total\s+(\d+)/m);
  const native = report.match(/^\s*native heap\s+(\d+)/m);
  return { pssKb: total ? Number(total[1]) : null, nativePssKb: native ? Number(native[1]) : null };
}
try {
  open();
  if (process.argv.includes('--isolated')) {
    choose('✓ 10万', '10万');
    const paragraphs = process.argv.includes('--paragraphs');
    choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
    const mode = process.argv.includes('--bulk') ? '批量' : '逐片段';
    choose(mode, mode === '批量' ? '逐片段' : '批量');
    if (process.argv.includes('--single')) choose('整段开', '整段关');
    const baseline = memory('baseline');
    button('加载全文');
    const measurement = status(/^测量：.*至空闲帧 .*排版 [1-9]\d* 行$/);
    button('全文核对');
    status(/^全文核对通过：100000 字符/);
    const result = { mode: process.argv.includes('--single') ? '整段' : mode, paragraphs, measurement, baseline, loaded: memory('loaded'), result: 'pass' };
    results.push(result);
    console.log(JSON.stringify(result));
  } else if (process.argv.includes('--benchmark')) {
    choose('逐片段', '批量');
    choose('整段关', '整段开');
    choose('✓ 10万', '10万');
    for (const paragraphs of [false, true]) {
      choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
      for (let repeat = 0; repeat < 3; repeat++) {
        for (const mode of repeat % 2 === 0 ? ['逐片段', '批量'] : ['批量', '逐片段']) {
          const opposite = mode === '批量' ? '逐片段' : '批量';
          choose(opposite, mode);
          choose(mode, opposite);
          button('加载全文');
          const metric = status(/^测量：.*至空闲帧 .*排版 [1-9]\d* 行$/);
          button('全文核对');
          status(/^全文核对通过：100000 字符/);
          const result = { mode, paragraphs, repeat, measurement: metric, result: 'pass' };
          results.push(result);
          console.log(JSON.stringify(result));
        }
      }
    }
  } else {
  choose(process.argv.includes('--bulk') ? '批量' : '逐片段', process.argv.includes('--bulk') ? '逐片段' : '批量');
  if (!process.argv.includes('--bulk')) choose(process.argv.includes('--single') ? '整段开' : '整段关', process.argv.includes('--single') ? '整段关' : '整段开');
  for (const length of process.argv.includes('--remaining') ? [100000] : [20000, 100000]) {
    for (const paragraphs of process.argv.includes('--remaining') ? [true] : [false, true]) {
      choose(length === 20000 ? '✓ 2万' : '✓ 10万', length === 20000 ? '2万' : '10万');
      choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
      button('加载全文');
      const imported = status(/^导入 /);
      button('全文核对');
      status(new RegExp(`^全文核对通过：${length} 字符`));
      button('跨片段选区');
      button('检查选区');
      const selected = status(/^选区核对通过：/);
      assert.match(selected, process.argv.includes('--single') ? /[12] 片段，10 字符$/ : /2 片段，10 字符$/);
      button('全选');
      button('检查选区');
      status(new RegExp(`^选区核对通过：0～${length}，.*${length} 字符$`));
      button('跨片段选区');
      command('shell', 'uitest', 'uiInput', 'keyEvent', '2072', '2019');
      status(/复制 1；粘贴 0/);
      button('尾部光标');
      command('shell', 'uitest', 'uiInput', 'keyEvent', '2072', '2038');
      button('校验粘贴');
      status(new RegExp(`^原生粘贴核对通过：${length + 10} 字符$`));
      button('加载全文');
      button('跨片段选区');
      command('shell', 'uitest', 'uiInput', 'keyEvent', '2055');
      button('校验删除');
      status(new RegExp(`^原生删除核对通过：${length - 10} 字符$`));
      button('加载全文');
      button('跨片段删除');
      status(new RegExp(`^跨片段删除通过：当前 ${length - 10} 字符$`));
      const result = { mode: process.argv.includes('--bulk') ? 'bulk' : process.argv.includes('--single') ? 'single' : 'incremental', length, paragraphs, imported, transientSnapshots, checks: 'round-trip, native cross-span selection, select-all, Ctrl+C/V, native deletion, controller deletion', result: 'pass' };
      results.push(result);
      console.log(JSON.stringify(result));
    }
  }
  }
  button('结束编辑');
} finally {
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`Artifacts: ${output}`);
}
