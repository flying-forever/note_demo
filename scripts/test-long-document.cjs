const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH || 'E:/Softs/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript/lib/typescript.js');
const filename = path.join(__dirname, '../note_by_agent/entry/src/main/ets/diagnostics/LongDocumentFixture.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const exported = {};
vm.runInNewContext(compiled, { exports: exported });
const { splitDemoText, fixtureText, fixtureChunks, DemoChunkSource } = exported;
for (const length of [20000, 100000]) {
  for (const paragraphs of [false, true]) {
    const original = fixtureText(length, paragraphs);
    assert.equal(original.length, length);
    for (const images of [false, true]) {
      const source = new DemoChunkSource();
      source.replace(fixtureChunks(original, images));
      assert.equal(source.exportText(), original);
      const first = source.getData(0);
      const previousLength = first.text.length;
      source.update(first.id, '替换段落\n');
      assert.equal(source.exportText(), '替换段落\n' + original.slice(previousLength));
    }
  }
}
for (const original of ['', '短文', 'a\r\nb\r\nc', '中文😀文字'.repeat(30), 'e\u0301x'.repeat(30), 'a👩‍💻b'.repeat(30)]) {
  const chunks = splitDemoText(original, 8);
  assert.equal(chunks.map(chunk => chunk.text).join(''), original);
  for (const chunk of chunks) {
    assert.ok(chunk.text.length <= 8);
    assert.ok(!/^[\uDC00-\uDFFF\u0300-\u036F\u200D]/.test(chunk.text));
    assert.ok(!/[\uD800-\uDBFF\u200D]$/.test(chunk.text));
  }
}
console.log('PASS: fixture round-trip, local edits, image exclusion, exact newlines and selected Unicode boundaries');
