// 在十万字原型上执行连续手势和真实系统输入，按临时基线筛查响应。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { command, snapshot, button, choose, open, readMetrics, output } = require('./validate-web-editor-demo.cjs');
const { parse: parseTrace } = require('./parse-web-frame-trace.cjs');
const results = [];
const repeat = Number(process.argv.find(arg => arg.startsWith('--repeat='))?.split('=')[1] || 3);
function stats(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  return { count: sorted.length, p95Ms: sorted.length ? +sorted[Math.ceil(sorted.length * .95) - 1].toFixed(2) : null,
    maxMs: sorted.length ? +sorted.at(-1).toFixed(2) : null, over100ms: sorted.filter(value => value > 100).length };
}
function hideKeyboard() {
  if (snapshot().nodes.some(node => /inputmethod/i.test(node.bundleName || ''))) {
    command('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');
  }
}
function composerFrames(label) {
  const report = command('shell', 'hidumper', '-s', '10', '-a', 'composer fps');
  fs.writeFileSync(path.join(output, `${label}-composer.txt`), report);
  const timestamps = [...new Set(report.split(/\r?\n/).filter(line => /^\d{11,}$/.test(line.trim())).map(Number))].sort((a, b) => a - b);
  return { timestamps, intervals: timestamps.slice(1).map((value, index) => (value - timestamps[index]) / 1e6) };
}
try {
  open(); hideKeyboard();
  choose('✓ 10万', '10万');
  const shapes = process.argv.includes('--paragraphs') ? [true] : [false, true];
  for (const paragraphs of shapes) {
    choose(paragraphs ? '多段' : '无换行', paragraphs ? '无换行' : '多段');
    for (let iteration = 0; iteration < repeat; iteration++) {
      button('加载全文');
      const loaded = readMetrics(data => data.loaded && data.length === 100000 && Number.isFinite(data.loadMs));
      button('全文核对'); readMetrics(data => data.ok === true, false);
      button('中部'); readMetrics(data => data.selectionFrom === 50000 && data.visibleRanges.some(range => range.from <= 50000 && range.to >= 50000));
      const web = snapshot().nodes.find(node => node.id === 'web-editor-probe' || node.key === 'web-editor-probe');
      assert.ok(web, 'Web component bounds unavailable');
      const box = web.bounds.match(/-?\d+/g).map(Number);
      const x = Math.floor((box[0] + box[2]) / 2);
      const bottom = box[3] - 160;
      const top = Math.max(box[1] + 200, bottom - 1000);
      assert.ok(bottom - top > 400, 'visible editor too small for scrolling');
      button('开始采样');
      const frames = [];
      let trace = null;
      for (let gesture = 0; gesture < 6; gesture++) {
        command('shell', 'hidumper', '-s', '10', '-a', 'composer fpsClear');
        const tracing = gesture === 0 && process.argv.includes('--trace');
        if (tracing) command('shell', 'hitrace', '--trace_begin', '--trace_clock', 'mono', '-b', '16384', 'graphic', 'multimodalinput', 'nweb');
        try {
          command('shell', 'uitest', 'uiInput', 'swipe', String(x), String(gesture < 3 ? bottom : top),
            String(x), String(gesture < 3 ? top : bottom), '800');
        } finally {
          if (tracing) command('shell', 'hitrace', '--trace_finish', '-o', '/data/local/tmp/note-web-performance.trace');
        }
        if (tracing) {
          const file = path.join(output, `${paragraphs ? 'paragraphs' : 'single'}-${iteration}.trace`);
          command('file', 'recv', '/data/local/tmp/note-web-performance.trace', file);
          trace = parseTrace(fs.readFileSync(file, 'utf8'));
        }
        frames.push(composerFrames(`${paragraphs ? 'paragraphs' : 'single'}-${iteration}-${gesture}`));
      }
      button('结束采样');
      const scroll = readMetrics(data => data.performance && !data.performance.running, false).performance;
      const presented = stats(frames.flatMap(frame => frame.intervals));
      button('开始采样');
      button('尾部输入');
      command('shell', 'uitest', 'uiInput', 'text', 'DEMOINPUT'.repeat(4));
      for (let deletion = 0; deletion < 12; deletion++) command('shell', 'uitest', 'uiInput', 'keyEvent', '2055');
      hideKeyboard();
      button('结束采样');
      const input = readMetrics(data => data.performance && !data.performance.running &&
        data.performance.inFlightEvents === 0).performance;
      button('核对采样输入');
      const checked = readMetrics(data => data.ok === true && data.length === 100024, false);
      button('结束编辑');
      const scrollProxy = scroll.frameCallback.count >= 60 && scroll.scrollEvents >= 20 && scroll.travelPx >= 1000 ?
        (scroll.frameCallback.p95Ms <= 33 && scroll.frameCallback.maxMs <= 100 ? 'within_baseline_proxy' : 'over_baseline_proxy') : 'insufficient_samples';
      const inputProxy = input.insertKeyToTwoRAF.count >= 36 && input.insertBeforeInputToTwoRAF.count >= 36 &&
        input.deleteKeyToTwoRAF.count >= 12 &&
        input.pendingEvents === 0 && input.inFlightEvents === 0 ?
        ([input.insertKeyToTwoRAF, input.insertBeforeInputToTwoRAF, input.deleteKeyToTwoRAF].every(metric => metric.p95Ms <= 100) ?
          'within_baseline_proxy' : 'over_baseline_proxy') : 'insufficient_samples';
      const touchActivePresentation = trace && trace.activeDurationMs >= 500 && trace.presentIntervals.count >= 30 &&
        trace.webBufferIntervals.count >= 30 ?
        ([trace.presentIntervals, trace.webBufferIntervals].every(metric => metric.p95Ms <= 33 && metric.maxMs <= 100) ?
          ([trace.downToFirstPresentMs, trace.downToFirstWebBufferMs, trace.upToLastPresentMs,
            trace.upToLastWebBufferMs].every(ms => ms !== null && ms <= 100) ?
            'within_baseline_screening' : 'active_intervals_within_baseline_boundary_pending') :
          'over_baseline_screening') : 'not_measured';
      const result = { paragraphs, iteration, length: 100000, loadedCallbackMs: loaded.loadMs,
        scroll, composerPresentation: presented, trace, input, contentExact: checked.ok, scrollProxy, inputProxy, touchActivePresentation,
        acceptance: 'Screening only. Composer is screen-wide, callback gaps are not presented app frame times; input excludes hardware/IME queue and physical display. Visual anchor and Chinese IME remain manual.' };
      results.push(result);
      fs.writeFileSync(path.join(output, 'performance-results.json'), JSON.stringify(results, null, 2));
      console.log(JSON.stringify({ ...result, trace: trace ? { ...trace, presentTimestampsMs: undefined,
        webBufferTimestampsMs: undefined } : null }));
    }
  }
} finally {
  fs.writeFileSync(path.join(output, 'performance-results.json'), JSON.stringify(results, null, 2));
  console.log(`Artifacts: ${output}`);
}
