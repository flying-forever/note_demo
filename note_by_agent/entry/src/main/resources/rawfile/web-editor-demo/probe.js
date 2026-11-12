// 使用完整文档模型与视口渲染，暴露仅操作合成实验数据的测量接口。
import { EditorState, EditorSelection } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap, undo, redo } from '@codemirror/commands';
import { PerformanceProbe } from './performance';

const statusElement = document.getElementById('status');
let original = '';
let loaded = false;
let changes = 0;
let loadMs = null;
let status = 'ready';
let token = 0;
let ok = null;
let performanceProbe;
const extensions = [EditorView.lineWrapping, history(), keymap.of([...defaultKeymap, ...historyKeymap]),
  EditorView.updateListener.of(update => {
    if (update.docChanged) { changes++; performanceProbe?.changed(update); }
  })];
const view = new EditorView({ state: EditorState.create({ extensions }), parent: document.getElementById('editor') });
performanceProbe = new PerformanceProbe(view);
function result(extra = {}) {
  const selection = view.state.selection.main;
  const data = { ready: true, loaded, length: view.state.doc.length, lines: view.state.doc.lines,
    viewportFrom: view.viewport.from, viewportTo: view.viewport.to,
    visibleRanges: view.visibleRanges.map(range => ({ from: range.from, to: range.to })),
    domLines: view.dom.querySelectorAll('.cm-line').length, contentHeight: view.contentHeight,
    viewportHeight: view.scrollDOM.clientHeight, changes, loadMs, status, ok,
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
  jump(fraction) {
    const position = Math.round(view.state.doc.length * Math.max(0, Math.min(1, fraction)));
    view.dispatch({ selection: { anchor: position }, effects: EditorView.scrollIntoView(position, { y: 'center' }) });
    status = 'jump requested; call snapshot after layout';
    return result();
  }
};
window.addEventListener('error', event => { statusElement.textContent = 'ERROR: ' + event.message; });
result();
