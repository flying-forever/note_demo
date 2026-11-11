const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const hdc = process.env.HDC_PATH || 'E:/Softs/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'note-demo-smoke-'));
const results = [];
function command(...args) {
  const value = cp.execFileSync(hdc, args, { encoding: 'utf8', timeout: 30000, windowsHide: true });
  if (/\[Fail\]|Error Code:|error:/i.test(value)) throw new Error(value);
  return value;
}
function nodes() {
  command('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/note-demo-smoke.json');
  command('file', 'recv', '/data/local/tmp/note-demo-smoke.json', path.join(output, 'latest.json'));
  const all = [];
  function walk(node) {
    if (node.attributes) all.push(node.attributes);
    (node.children || []).forEach(walk);
  }
  walk(JSON.parse(fs.readFileSync(path.join(output, 'latest.json'), 'utf8')));
  return all;
}
function click(text, all = nodes()) {
  const button = all.find(node => node.type === 'Button' && node.text === text);
  assert.ok(button, `missing button: ${text}`);
  const coordinates = button.bounds.match(/\d+/g).map(Number);
  command('shell', 'uitest', 'uiInput', 'click', String(Math.floor((coordinates[0] + coordinates[2]) / 2)), String(Math.floor((coordinates[1] + coordinates[3]) / 2)));
}
function choose(desired, opposite) {
  const all = nodes();
  if (!all.some(node => node.type === 'Button' && node.text === desired)) click(opposite, all);
}
function unfocused(all) {
  assert.ok(!all.some(node => node.type === 'TextArea' && node.focused === 'true'), 'unexpected focused input');
}
function run() {
  assert.ok(nodes().some(node => node.text === '长笔记试验'), 'open LongDocumentDemo before running');
  for (const length of [20000, 100000]) {
    for (const paragraphs of [true, false]) {
      for (const images of [false, true]) {
        choose(length === 20000 ? '✓ 2万' : '✓ 10万', length === 20000 ? '2万' : '10万');
        choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
        choose(images ? '含图片占位' : '纯文字', images ? '纯文字' : '含图片占位');
        choose('懒加载', '整篇输入');
        click('加载');
        let all = nodes();
        const metric = all.find(node => /^首个可见范围回调/.test(node.text));
        assert.ok(all.some(node => /可见块/.test(node.text)), 'missing list');
        unfocused(all);
        click('核对全文', all);
        all = nodes();
        assert.ok(all.some(node => node.text === `当前 ${length} UTF-16 单元；与原文完全一致`));
        for (const target of ['中部', '尾部', '顶部']) {
          click(target, all);
          all = nodes();
          const range = all.find(node => /可见块/.test(node.text));
          const match = range.text.match(/可见块 (\d+)～(\d+)\/(\d+)/);
          const expected = target === '顶部' ? 1 : target === '尾部' ? Number(match[3]) : Math.floor((Number(match[3]) - 1) / 2) + 1;
          assert.ok(Number(match[1]) <= expected && Number(match[2]) >= expected, `wrong jump: ${target}: ${range.text}`);
          unfocused(all);
        }
        const result = { length, paragraphs, images, mode: 'lazy', metric: metric?.text, result: 'pass' };
        results.push(result);
        console.log(JSON.stringify(result));
      }
    }
  }
  for (const length of [20000, 100000]) {
    choose(length === 20000 ? '✓ 2万' : '✓ 10万', length === 20000 ? '2万' : '10万');
    choose('纯文字', '含图片占位');
    choose('整篇输入', '懒加载');
    click('加载');
    let all = nodes();
    const editor = all.find(node => node.type === 'TextArea');
    assert.equal(editor.text.length, length);
    unfocused(all);
    click('核对全文', all);
    all = nodes();
    assert.ok(all.some(node => node.text === `当前 ${length} UTF-16 单元；与原文完全一致`));
    const result = { length, mode: 'whole', result: 'pass' };
    results.push(result);
    console.log(JSON.stringify(result));
  }
}
function inputSmoke() {
  choose('✓ 10万', '10万');
  choose('无换行', '多段');
  choose('纯文字', '含图片占位');
  choose('懒加载', '整篇输入');
  click('加载');
  let all = nodes();
  const text = all.find(node => node.type === 'Text' && node.text.length > 1000);
  assert.ok(text, 'missing text chunk');
  const bounds = text.bounds.match(/\d+/g).map(Number);
  command('shell', 'uitest', 'uiInput', 'click', String(bounds[0] + 100), String(bounds[1] + 50));
  all = nodes();
  const editor = all.find(node => node.type === 'TextArea');
  assert.ok(editor, 'missing chunk editor');
  const editBounds = editor.bounds.match(/\d+/g).map(Number);
  command('shell', 'uitest', 'uiInput', 'click', String(editBounds[0] + 100), String(editBounds[1] + 50));
  command('shell', 'uitest', 'uiInput', 'text', 'DEMOINPUT');
  all = nodes();
  assert.ok(all.some(node => node.type === 'TextArea' && node.text.includes('DEMOINPUT')), 'input missing from editor');
  click('结束单块编辑', all);
  click('核对全文');
  all = nodes();
  assert.ok(all.some(node => node.text === '当前 100009 UTF-16 单元；已编辑，与原文不同'), 'input missing from complete document');
  click('尾部', all);
  click('顶部');
  all = nodes();
  assert.ok(all.some(node => node.type === 'Text' && node.text.includes('DEMOINPUT')), 'edit lost after lazy node recreation');
  unfocused(all);
  results.push({ mode: 'lazy-input', length: 100000, result: 'pass', checks: 'input, full export, jump away/back, no focus after jump' });
  console.log(JSON.stringify(results[0]));
}
try {
  if (process.argv.includes('--input')) inputSmoke();
  else run();
} finally {
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`Artifacts: ${output}`);
}
