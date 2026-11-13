// 采集真实浏览器输入事件与活动滚动回调；这些是显示链路的代理指标。
function stats(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  return { count: sorted.length, p95Ms: sorted.length ? +sorted[Math.ceil(sorted.length * .95) - 1].toFixed(2) : null,
    maxMs: sorted.length ? +sorted[sorted.length - 1].toFixed(2) : null,
    over100ms: sorted.filter(value => value > 100).length };
}

export class PerformanceProbe {
  constructor(view) {
    this.view = view;
    this.running = false;
    this.generation = 0;
    this.reset();
    view.scrollDOM.addEventListener('scroll', () => {
      if (this.running) { this.lastScroll = performance.now(); this.scrollEvents++; }
    }, { passive: true });
    view.scrollDOM.addEventListener('touchstart', () => { this.touching = true; }, { passive: true });
    for (const type of ['touchend', 'touchcancel']) {
      view.scrollDOM.addEventListener(type, () => { this.touching = false; }, { passive: true });
    }
    view.contentDOM.addEventListener('keydown', event => {
      if (this.running && (event.key.length === 1 || ['Backspace', 'Delete'].includes(event.key))) {
        const deletion = ['Backspace', 'Delete'].includes(event.key);
        if (!event.ctrlKey && !event.metaKey) this.pending.push({ kind: deletion ? 'deleteKey' : 'insertKey',
          group: deletion ? 'delete' : 'input', started: performance.now(), trusted: event.isTrusted });
      }
    }, true);
    view.contentDOM.addEventListener('beforeinput', event => {
      if (this.running) {
        const deletion = event.inputType.startsWith('delete');
        this.pending.push({ kind: deletion ? 'deleteBeforeInput' : 'insertBeforeInput',
          group: deletion ? 'delete' : 'input', started: performance.now(), trusted: event.isTrusted });
      }
    }, true);
  }

  reset() {
    this.frames = []; this.inputs = []; this.pending = [];
    this.lastScroll = -Infinity; this.scrollEvents = 0; this.touching = false;
    this.travel = 0; this.documentChanges = 0; this.started = 0;
    this.stopped = 0; this.inFlight = 0; this.initialLength = this.view.state.doc.length;
  }

  start() {
    const generation = ++this.generation;
    this.reset(); this.running = true; this.started = performance.now();
    let previous = this.started;
    let previousTop = this.view.scrollDOM.scrollTop;
    let previousActive = false;
    const tick = () => {
      if (!this.running || generation !== this.generation) return;
      const now = performance.now();
      const top = this.view.scrollDOM.scrollTop;
      this.travel += Math.abs(top - previousTop);
      const active = this.touching || now - this.lastScroll < 150;
      if ((previousActive || active) && this.frames.length < 5000) this.frames.push(now - previous);
      previousActive = active;
      previous = now; previousTop = top;
      if (now - this.started > 60000) this.stop();
      else requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  changed(update) {
    if (!this.running) return;
    this.documentChanges++;
    const generation = this.generation;
    const matches = item => update.transactions.some(transaction => transaction.isUserEvent(item.group));
    const pending = this.pending.filter(matches);
    this.pending = this.pending.filter(item => !matches(item));
    this.inFlight += pending.length;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (generation !== this.generation) return;
      const finished = performance.now();
      this.inFlight -= pending.length;
      for (const item of pending) {
        if (this.inputs.length < 2000) this.inputs.push({ ...item, ms: finished - item.started });
      }
    }));
  }

  stop() { this.running = false; this.stopped = performance.now(); }

  snapshot() {
    return { running: this.running, elapsedMs: this.started ? Math.round((this.stopped || performance.now()) - this.started) : 0,
      frameCallback: stats(this.frames), scrollEvents: this.scrollEvents, travelPx: Math.round(this.travel),
      insertKeyToTwoRAF: stats(this.inputs.filter(item => item.kind === 'insertKey' && item.trusted).map(item => item.ms)),
      deleteKeyToTwoRAF: stats(this.inputs.filter(item => item.kind === 'deleteKey' && item.trusted).map(item => item.ms)),
      insertBeforeInputToTwoRAF: stats(this.inputs.filter(item => item.kind === 'insertBeforeInput' && item.trusted).map(item => item.ms)),
      deleteBeforeInputToTwoRAF: stats(this.inputs.filter(item => item.kind === 'deleteBeforeInput' && item.trusted).map(item => item.ms)),
      trustedSamples: this.inputs.filter(item => item.trusted).length, documentChanges: this.documentChanges,
      pendingEvents: this.pending.length, inFlightEvents: this.inFlight, initialLength: this.initialLength, finalLength: this.view.state.doc.length,
      scope: 'Web callback gaps while scrolling; browser event receipt to model update plus two rAF. Not physical input-to-photon or display presentation.' };
  }
}
