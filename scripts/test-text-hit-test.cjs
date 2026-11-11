const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const filename = path.join(__dirname, '../note_by_agent/entry/src/main/ets/platform/NoteTextHitTest.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const exportsObject = {};
vm.runInNewContext(compiled, { exports: exportsObject }, { filename });
const { noteTextCaret } = exportsObject;
function controller(position, lines = 1, visit = () => {}) {
  return { getLayoutManager: () => ({ getLineCount: () => lines,
    getGlyphPositionAtCoordinate: (x, y) => { visit(x, y); return { position, affinity: 0 }; } }) };
}
const content = '中文😀e\u0301👩‍💻末尾';
assert.equal(noteTextCaret(content, controller(4), 36, 80), 4, 'Native UTF-16 position after emoji stays 4');
assert.equal(noteTextCaret(content, controller(11), 36, 80), 11, 'Native ZWJ cluster boundary stays unchanged');
assert.equal(noteTextCaret(content, controller(content.length), 9999, 9999), content.length);
assert.equal(noteTextCaret(content, controller(0), -20, -10), 0, 'Native nearest-boundary behavior handles out-of-bounds coordinates');
let visited = false;
const longText = ('中文😀正文\n').repeat(10000);
assert.equal(noteTextCaret(longText, controller(50000, 10000, (x, y) => {
  visited = true;
  assert.equal(x, 51);
  assert.equal(y, 156780, 'Already-local long-document y passes through without scroll addition');
}), 51, 156780), 50000);
assert.ok(visited);
assert.equal(noteTextCaret(content, undefined, 10, 10), undefined);
assert.equal(noteTextCaret(content, controller(0, 0), 10, 10), undefined);
assert.equal(noteTextCaret(content, { getLayoutManager: () => { throw new Error('unbound'); } }, 10, 10), undefined);
assert.equal(noteTextCaret(content, { getLayoutManager: () => undefined }, 10, 10), undefined);
for (const position of [-1, NaN, Infinity, 0.5, content.length + 1, 3, 7, 10]) {
  assert.equal(noteTextCaret(content, controller(position), 10, 10), undefined, 'Reject invalid position ' + position);
}
assert.equal(noteTextCaret(content, controller(1), NaN, 10), undefined);
assert.equal(noteTextCaret('', undefined, 0, 0), 0, 'Empty content ignores displayed placeholder text');
console.log('PASS: native UTF-16 offsets, Unicode surrogate safety, long local coordinates and unavailable-layout fallback');
