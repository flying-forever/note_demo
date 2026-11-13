// 按真实触摸活跃时间裁剪系统呈现与 Web 缓冲记录，保留首帧响应。
const fs = require('node:fs');
function stats(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  return { count: sorted.length, p95Ms: sorted.length ? +sorted[Math.ceil(sorted.length * .95) - 1].toFixed(2) : null,
    maxMs: sorted.length ? +sorted.at(-1).toFixed(2) : null, over100ms: sorted.filter(value => value > 100).length };
}
function parse(text) {
  const touches = [], presents = [], buffers = [];
  for (const line of text.split(/\r?\n/)) {
    const time = line.match(/\s(\d+\.\d+): tracing_mark_write:/);
    if (!time) continue;
    const ms = Number(time[1]) * 1000;
    const touch = line.match(/H:HandleTouchEvent touchStatus_:(\d+)/);
    if (touch) touches.push({ ms, action: Number(touch[1]) });
    const present = line.match(/H:HdiOutput::RecordMergedPresentTime (\d+)/);
    if (present && Number(present[1]) > 0) presents.push(Number(present[1]) / 1e6);
    if (/H:AcquireBuffer with PresentTimestamp name: RosenWeb /.test(line)) buffers.push(ms);
  }
  const down = touches.find(item => item.action === 2)?.ms;
  const up = touches.find(item => item.action === 4 && item.ms > down)?.ms;
  const firstMove = touches.find(item => item.action === 3 && item.ms >= down)?.ms;
  if (!Number.isFinite(down) || !Number.isFinite(up)) throw new Error('Trace has no complete touch down/up window');
  const active = values => [...new Set(values.filter(ms => ms >= down && ms <= up))].sort((a, b) => a - b);
  const display = active(presents), web = active(buffers);
  const gaps = values => values.slice(1).map((ms, i) => ms - values[i]);
  return { touchDownMs: down, firstMoveMs: firstMove, touchUpMs: up, activeDurationMs: +(up - down).toFixed(2),
    presentIntervals: stats(gaps(display)), webBufferIntervals: stats(gaps(web)),
    downToFirstPresentMs: display.length ? +(display[0] - down).toFixed(2) : null,
    moveToFirstPresentMs: firstMove && display.some(ms => ms >= firstMove) ?
      +(display.find(ms => ms >= firstMove) - firstMove).toFixed(2) : null,
    downToFirstWebBufferMs: web.length ? +(web[0] - down).toFixed(2) : null,
    upToLastWebBufferMs: web.length ? +(up - web.at(-1)).toFixed(2) : null,
    upToLastPresentMs: display.length ? +(up - display.at(-1)).toFixed(2) : null,
    presentTimestampsMs: display, webBufferTimestampsMs: web,
    scope: 'Touch-active window from system trace; merged screen present-fence timestamps and RosenWeb acquire times. First response separate, no cross-idle intervals; no causal frame-ID correlation or photon timing.' };
}
if (require.main === module) console.log(JSON.stringify(parse(fs.readFileSync(process.argv[2], 'utf8')), null, 2));
module.exports = { parse };
