// 使用完整文档模型与视口渲染，暴露仅操作合成实验数据的测量接口。
import { EditorState, EditorSelection, Compartment, StateEffect, StateField } from '@codemirror/state';
import { EditorView, keymap, Decoration, WidgetType } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap, undo, redo } from '@codemirror/commands';
import { PerformanceProbe } from './performance';

const statusElement = document.getElementById('status');
const editableCompartment = new Compartment();
let original = '';
let loaded = false;
let changes = 0;
let loadMs = null;
let status = 'ready';
let token = 0;
let ok = null;
let performanceProbe;
let pasteStart = 0;
let pasteMs = null;
let jumpMs = null;
let jumpVisible = null;
let jumpTarget = 0;
const insertImageEffect = StateEffect.define();
const imagePlaceholder = '\uFFFC';
const imageData = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
class ImageBlock extends WidgetType {
  eq() { return true; }
  toDOM() {
    const img = document.createElement('img');
    img.src = imageData;
    img.alt = '插图试验';
    img.style.cssText = 'display:block;width:200px;height:100px;object-fit:cover;margin:8px 0;border-radius:8px;background:#eee;';
    return img;
  }
}
const imageMark = Decoration.replace({ widget: new ImageBlock() });
const imageField = StateField.define({
  create: () => Decoration.none,
  update(deco, transaction) {
    let next = deco.map(transaction.changes);
    for (const effect of transaction.effects) {
      if (effect.is(insertImageEffect)) next = next.update({ add: [imageMark.range(effect.value, effect.value + 1)] });
    }
    return next;
  },
  provide: field => EditorView.decorations.from(field)
});
function lineGaps() {
  const rects = [];
  const walker = document.createTreeWalker(view.contentDOM, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    const range = document.createRange();
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) {
      if (rect.height > 0) rects.push({ top: rect.top, bottom: rect.bottom });
    }
  }
  rects.sort((a, b) => a.top - b.top);
  const heights = rects.map(rect => rect.bottom - rect.top).sort((a, b) => a - b);
  const median = heights.length ? heights[Math.floor(heights.length / 2)] : 0;
  let count = 0;
  let visible = 0;
  let max = 0;
  const samples = [];
  const box = view.scrollDOM.getBoundingClientRect();
  for (let index = 1; index < rects.length; index++) {
    const gap = rects[index].top - rects[index - 1].bottom;
    if (gap > Math.max(8, median * 0.8)) {
      count++;
      max = Math.max(max, Math.round(gap));
      const edge = rects[index - 1].bottom;
      if (edge >= box.top && edge <= box.bottom) {
        visible++;
        if (samples.length < 5) samples.push({ gap: Math.round(gap), y: Math.round(edge - box.top) });
      }
    }
  }
  return { count, visible, max, samples, firstTop: rects.length ? Math.round(rects[0].top - box.top) : null,
    lastBottom: rects.length ? Math.round(rects[rects.length - 1].bottom - box.bottom) : null };
}
const extensions = [EditorView.lineWrapping, history(), keymap.of([...defaultKeymap, ...historyKeymap]),
  EditorView.updateListener.of(update => {
    if (update.docChanged) {
      changes++;
      performanceProbe?.changed(update);
      if (pasteStart) {
        const start = pasteStart;
        requestAnimationFrame(() => requestAnimationFrame(() => {
          pasteMs = Math.round(Math.max(pasteMs || 0, performance.now() - start) * 10) / 10;
          pasteStart = 0;
        }));
      }
    }
  }), editableCompartment.of(EditorView.editable.of(true)), imageField,
  EditorView.atomicRanges.of(view => view.state.field(imageField))];
const view = new EditorView({ state: EditorState.create({ extensions }), parent: document.getElementById('editor') });
performanceProbe = new PerformanceProbe(view);
let editableState = true;
let pressAt = 0;
let pressX = 0;
let pressY = 0;
view.contentDOM.addEventListener('paste', () => {
  pasteStart = performance.now();
  pasteMs = null;
}, true);
view.contentDOM.addEventListener('pointerdown', event => {
  if (editableState) return;
  pressAt = performance.now();
  pressX = event.clientX;
  pressY = event.clientY;
});
view.contentDOM.addEventListener('pointerup', event => {
  const quick = performance.now() - pressAt < 400;
  const still = Math.hypot(event.clientX - pressX, event.clientY - pressY) < 8;
  pressAt = 0;
  if (editableState || !quick || !still) return;
  const position = view.posAtCoords({ x: event.clientX, y: event.clientY });
  if (position == null) return;
  editableState = true;
  view.dispatch({ effects: editableCompartment.reconfigure(EditorView.editable.of(true)), selection: { anchor: position } });
  view.focus();
  status = 'tap entered edit mode at tapped position';
  result();
});
function result(extra = {}) {
  const selection = view.state.selection.main;
  const data = { ready: true, loaded, length: view.state.doc.length, lines: view.state.doc.lines,
    viewportFrom: view.viewport.from, viewportTo: view.viewport.to,
    visibleRanges: view.visibleRanges.map(range => ({ from: range.from, to: range.to })),
    domLines: view.dom.querySelectorAll('.cm-line').length, contentHeight: view.contentHeight,
    viewportHeight: view.scrollDOM.clientHeight, changes, loadMs, status, ok, pasteMs,
    gaps: lineGaps(), jumpMs, jumpVisible, images: view.state.field(imageField).size,
    selectionFrom: selection.from, selectionTo: selection.to, composing: view.composing,
    focused: view.hasFocus, performance: performanceProbe.snapshot(), ...extra };
  statusElement.textContent = JSON.stringify(data);
  return JSON.stringify(data);
}
window.noteProbe = {
  ready: true,
  load(text) {
    const current = ++token;
    const start = performance.now();
    original = text;
    view.contentDOM.blur();
    view.setState(EditorState.create({ doc: text, extensions }));
    view.scrollDOM.scrollTop = 0;
    loaded = true;
    changes = 0;
    loadMs = null;
    ok = null;
    status = 'loaded; waiting for two animation frames (not cold first paint)';
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (current !== token) return;
      loadMs = Math.round((performance.now() - start) * 10) / 10;
      status = 'loaded; loadMs includes model creation and two animation frames, excludes ArkTS bridge';
      result();
    }));
    return result();
  },
  snapshot() { return result(); },
  startPerformance() { performanceProbe.start(); return result(); },
  stopPerformance() { performanceProbe.stop(); return result(); },
  focusTail() {
    view.dispatch({ selection: { anchor: view.state.doc.length }, scrollIntoView: true });
    view.focus();
    status = 'focused at document end; awaiting actual input';
    return result();
  },
  clearFocus() { view.contentDOM.blur(); return result(); },
  setEditable(editable) {
    editableState = !!editable;
    view.dispatch({ effects: editableCompartment.reconfigure(EditorView.editable.of(editableState)) });
    if (!editableState) view.contentDOM.blur();
    status = editableState ? 'editable; tap text to focus and input' : 'read-only; finger selection should not raise keyboard';
    return result();
  },
  inputCheck(marker) {
    ok = loaded && view.state.doc.toString() === original + marker;
    status = 'checking actual input against original plus supplied marker';
    return result({ check: ok });
  },
  check() {
    ok = loaded && view.state.doc.toString() === original;
    status = ok ? 'original text exact match' : 'text differs from original';
    return result({ check: ok });
  },
  select(all) {
    const boundary = Math.min(3000, Math.floor(view.state.doc.length / 2));
    const from = all ? 0 : Math.max(0, boundary - 5);
    const to = all ? view.state.doc.length : Math.min(view.state.doc.length, boundary + 5);
    view.dispatch({ selection: EditorSelection.single(from, to), scrollIntoView: true });
    status = all ? 'model full selection; inspect native handles manually' : 'model selection across position 3000';
    return result();
  },
  editCheck() {
    if (!loaded || view.composing) { ok = false; status = 'load first; finish IME composition'; return result({ check: false }); }
    const before = view.state.doc.toString();
    const from = Math.max(0, Math.min(2995, before.length - 10));
    const to = Math.min(before.length, from + 10);
    const inserted = '实验🙂e\u0301\n';
    view.dispatch({ changes: { from, to, insert: inserted }, selection: { anchor: from + inserted.length } });
    const replaced = view.state.doc.toString() === before.slice(0, from) + inserted + before.slice(to);
    const undone = undo(view) && view.state.doc.toString() === before;
    const redone = redo(view) && view.state.doc.toString() === before.slice(0, from) + inserted + before.slice(to);
    const restored = undo(view) && view.state.doc.toString() === before;
    ok = replaced && undone && redone && restored;
    status = 'transaction replace / undo / redo / restore; not IME or clipboard validation';
    return result({ check: ok, replaced, undone, redone, restored });
  },
  undoLast() {
    const before = view.state.doc.length;
    const undone = undo(view);
    status = undone ? `undo applied; length ${before} -> ${view.state.doc.length}` : 'nothing to undo';
    return result({ undone });
  },
  insertImage() {
    if (!loaded) { ok = false; status = 'load first'; return result({ check: false }); }
    const from = view.state.selection.main.from;
    view.dispatch({ changes: { from, insert: imagePlaceholder }, effects: insertImageEffect.of(from), selection: { anchor: from + 1 } });
    status = 'image placeholder inserted at caret';
    return result({ images: view.state.field(imageField).size });
  },
  jump(fraction) {
    const position = Math.round(view.state.doc.length * Math.max(0, Math.min(1, fraction)));
    const start = performance.now();
    jumpTarget = position;
    jumpMs = null;
    view.dispatch({ selection: { anchor: position }, effects: EditorView.scrollIntoView(position, { y: 'center' }) });
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const coords = view.coordsAtPos(jumpTarget);
      const box = view.scrollDOM.getBoundingClientRect();
      jumpMs = Math.round((performance.now() - start) * 10) / 10;
      jumpVisible = !!coords && coords.top >= box.top - 1 && coords.bottom <= box.bottom + 1;
      result();
    }));
    status = 'jump requested; call snapshot after layout';
    return result();
  }
};
window.addEventListener('error', event => { statusElement.textContent = 'ERROR: ' + event.message; });
result();
