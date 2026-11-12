// 操作独立 Web 长文实验页，记录模型/视口检查及可区分口径的进程内存。
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const hdc = process.env.HDC_PATH || 'E:/Softs/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const root = process.env.NOTE_VERIFICATION_DIR || path.resolve(__dirname, '../note_by_agent/build/verification');
fs.mkdirSync(root, { recursive: true });
const output = fs.mkdtempSync(path.join(root, 'note-web-editor-'));
const results = [];
function command(...args) {
  const value = cp.execFileSync(hdc, args, { encoding: 'utf8', timeout: 30000, windowsHide: true });
  if (/\[Fail\]|Error Code:|^error:|Missing parameter/im.test(value)) throw new Error(value);
  return value;
}
function snapshot() {
  command('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/note-web-editor.json');
  command('file', 'recv', '/data/local/tmp/note-web-editor.json', path.join(output, 'latest.json'));
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
  const box = node.bounds.match(/-?\d+/g).map(Number);
  command('shell', 'uitest', 'uiInput', action, String(Math.floor((box[0] + box[2]) / 2)), String(Math.floor((box[1] + box[3]) / 2)));
}
function button(text) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const target = snapshot().nodes.find(node => node.type === 'Button' && node.text === text && node.enabled === 'true');
    if (target) return point(target);
  }
  assert.fail(`button not ready: ${text}`);
}
function choose(desired, opposite) {
  if (!snapshot().nodes.some(node => node.type === 'Button' && node.text === desired)) button(opposite);
}
function findNode(node, predicate) {
  if (predicate(node)) return node;
  for (const child of node.children || []) {
    const found = findNode(child, predicate);
    if (found) return found;
  }
}
function open() {
  let state = snapshot();
  if (state.nodes.some(node => node.text === 'Web 长文编辑试验')) return;
  if (!state.nodes.some(node => node.text === '技术实验室')) {
    assert.ok(state.nodes.some(node => node.text === '笔记'), 'start at home, catalog or Web experiment');
    point(state.nodes.find(node => node.type === 'Row' && node.longClickable === 'true'), 'longClick');
    state = snapshot();
  }
  const entry = findNode(state.tree, node => node.attributes?.type === 'ListItem' &&
    !!findNode(node, child => child.attributes?.text === 'Web 长文编辑对照'));
  assert.ok(entry, 'Web experiment absent or offscreen');
  point(findNode(entry, node => node.attributes?.type === 'Button' && node.attributes.text === '打开实验')?.attributes);
}
function parseStatus() {
  const state = snapshot();
  const targets = state.nodes.filter(node => node.id === 'web-probe-status' || node.key === 'web-probe-status' ||
    (node.type === 'Text' && (node.text || '').includes('viewportFrom')));
  for (const node of targets) {
    try {
      let data = JSON.parse(node.text);
      for (let count = 0; count < 2 && typeof data === 'string'; count++) data = JSON.parse(data);
      if (data && typeof data === 'object' && 'ready' in data) return data;
    } catch {}
  }
  return null;
}
function readMetrics(predicate = () => true, refresh = true) {
  for (let attempt = 0; attempt < 8; attempt++) {
    if (refresh) button('读取指标');
    const data = parseStatus();
    if (data && predicate(data)) return data;
  }
  assert.fail(`Web status not ready; see ${path.join(output, 'latest.json')}`);
}
function memory(label) {
  const processes = command('shell', 'ps', '-A', '-o', 'PID,PPID,NAME');
  fs.writeFileSync(path.join(output, `${label}-processes.txt`), processes);
  const mainPid = command('shell', 'pidof', 'com.example.note_by_agent').trim();
  assert.match(mainPid, /^\d+$/);
  const candidates = processes.split(/\r?\n/).map(line => line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/)).filter(Boolean)
    .filter(match => match[1] === mainPid || /web|render|nweb/i.test(match[3]));
  const reports = [];
  for (const match of candidates) {
    try {
      const report = command('shell', 'hidumper', '--mem', match[1]);
      fs.writeFileSync(path.join(output, `${label}-${match[1]}-memory.txt`), report);
      reports.push({ pid: match[1], ppid: match[2], name: match[3], isApp: match[1] === mainPid,
        pssKb: Number(report.match(/^\s*Total\s+(\d+)/m)?.[1]) || null });
    } catch (error) { reports.push({ pid: match[1], name: match[3], error: String(error) }); }
  }
  return { reports, scope: 'Main app and name-matched renderer candidates; ownership and shared services not established. Do not sum as app total or peak.' };
}
function main() {
try {
  open();
  const isolated = process.argv.includes('--isolated');
  for (const length of isolated ? [100000] : [20000, 100000]) {
    for (const paragraphs of isolated ? [process.argv.includes('--paragraphs')] : [false, true]) {
      choose(length === 20000 ? '✓ 2万' : '✓ 10万', length === 20000 ? '2万' : '10万');
      choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
      const baseline = isolated ? memory('baseline') : null;
      button('加载全文');
      const loaded = readMetrics(data => data.loaded && data.length === length && Number.isFinite(data.loadMs));
      const beforeCheck = isolated ? memory('before-check') : null;
      button('全文核对');
      const checked = readMetrics(data => data.ok === true, false);
      const afterCheck = isolated ? memory('after-check') : null;
      button('编辑自检');
      const edited = readMetrics(data => data.ok === true, false);
      assert.equal(edited.length, length);
      assert.equal(edited.restored, true);
      button('全选');
      const selected = readMetrics(data => data.selectionFrom === 0 && data.selectionTo === length);
      const jumps = [];
      for (const [label, fraction] of [['顶部', 0], ['中部', 0.5], ['尾部', 1]]) {
        button(label);
        const target = Math.round(length * fraction);
        jumps.push(readMetrics(data => data.selectionFrom === target && data.viewportFrom <= target &&
          data.viewportTo >= target && data.visibleRanges.some(range => range.from <= target && range.to >= target)));
      }
      let injected = null;
      if (process.argv.includes('--input')) {
        button('尾部输入');
        command('shell', 'uitest', 'uiInput', 'text', 'DEMOINPUT');
        button('核对注入');
        injected = readMetrics(data => data.ok === true && data.length === length + 9, false);
        if (snapshot().nodes.some(node => /inputmethod/i.test(node.bundleName || ''))) {
          command('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');
        }
        button('结束编辑');
      }
      const result = { length, paragraphs, loaded, checked, edited, selected, jumps, baseline, beforeCheck, afterCheck,
        injected,
        virtualization: { modelLength: loaded.length, renderedDOMLines: loaded.domLines,
          viewportLength: loaded.viewportTo - loaded.viewportFrom, fullModelRetained: checked.length === length },
        checks: 'model text equality, transaction replace/undo/redo/restore, model select-all, viewport jumps; not physical IME/handles/clipboard', result: 'pass' };
      results.push(result);
      fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
      console.log(JSON.stringify(result));
    }
  }
} finally {
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`Artifacts: ${output}`);
}
}
if (require.main === module) main();
module.exports = { command, snapshot, button, choose, open, readMetrics, memory, output };
