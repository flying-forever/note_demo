import { BodyBlock, NoteImage, textBlock, documentText, copyImage } from '../model/NoteDocument';
import { Note } from '../model/Note';
import { NoteDraft, NoteHistory } from '../model/NoteHistory';

@Observed
export class NoteEditorSession {
  title: string = '';
  content: string = '';
  blocks: BodyBlock[] = [];
  images: NoteImage[] = [];
  canUndo: boolean = false;
  canRedo: boolean = false;
  activeBlock: string = '';
  caret: number = 0;
  private history: NoteHistory = new NoteHistory('', '');
  private pastePending: boolean = false;
  private savedTitle: string = '';
  private savedBlocks: string = '';
  private savedImages: string = '';

  load(note?: Note): void {
    this.title = note?.title ?? '';
    this.blocks = note?.blocks?.map((block: BodyBlock) => ({ id: block.id, text: block.text, imageId: block.imageId } as BodyBlock)) ?? [textBlock(note?.content ?? '')];
    this.images = note?.images?.map((item: NoteImage) => copyImage(item)) ?? [];
    this.content = documentText(this.blocks);
    this.history = new NoteHistory(this.title, JSON.stringify(this.blocks));
    this.activeBlock = this.blocks.find((block: BodyBlock) => block.imageId === '')?.id ?? '';
    this.caret = 0;
    this.pastePending = false;
    this.markSaved();
    this.updateHistoryButtons();
  }

  markSaved(): void {
    this.savedTitle = this.title;
    this.savedBlocks = JSON.stringify(this.blocks);
    this.savedImages = JSON.stringify(this.images);
  }

  isDirty(): boolean {
    return this.title !== this.savedTitle || JSON.stringify(this.blocks) !== this.savedBlocks || JSON.stringify(this.images) !== this.savedImages;
  }

  closeGroup(): void { this.history.closeGroup(); }

  preparePaste(): void {
    this.closeGroup();
    this.pastePending = true;
  }

  private record(field: string, previewing: boolean): void {
    if (previewing) { return; }
    this.history.record(this.title, JSON.stringify(this.blocks), field);
    if (this.pastePending) {
      this.closeGroup();
      this.pastePending = false;
    }
    this.updateHistoryButtons();
  }

  changeTitle(value: string, previewing: boolean): void {
    this.title = value;
    this.record('note-editor-title', previewing);
  }

  blockText(id: string): string {
    return this.blocks.find((block: BodyBlock) => block.id === id)?.text ?? '';
  }

  changeBlock(value: string, id: string, previewing: boolean): void {
    this.blocks = this.blocks.map((block: BodyBlock) => block.id === id ? { id: block.id, text: value, imageId: block.imageId } : block);
    this.content = documentText(this.blocks);
    this.record(id, previewing);
  }

  hasImages(): boolean { return this.blocks.some((block: BodyBlock) => block.imageId !== ''); }

  referencedImages(): NoteImage[] {
    return this.images.filter((item: NoteImage) => this.blocks.some((block: BodyBlock) => block.imageId === item.id));
  }

  imageItem(id: string): NoteImage {
    return this.images.find((item: NoteImage) => item.id === id) ?? {
      id: '', path: '', name: '', width: 1, height: 1, bytes: 0, caption: '', small: false
    };
  }

  insertImage(item: NoteImage, target: string, offset: number): string {
    this.images = [...this.images, item];
    let index: number = this.blocks.findIndex((block: BodyBlock) => block.id === target && block.imageId === '');
    if (index < 0) { index = this.blocks.findIndex((block: BodyBlock) => block.imageId === ''); }
    if (index < 0) {
      this.blocks = [...this.blocks, textBlock('')];
      index = this.blocks.length - 1;
    }
    const current: BodyBlock = this.blocks[index];
    const split: number = Math.max(0, Math.min(offset, current.text.length));
    const after: BodyBlock = textBlock(current.text.substring(split));
    this.blocks = [...this.blocks.slice(0, index),
      { id: current.id, text: current.text.substring(0, split), imageId: '' },
      { id: item.id, text: '', imageId: item.id }, after, ...this.blocks.slice(index + 1)];
    this.activeBlock = after.id;
    this.caret = 0;
    this.recordDocument();
    return after.id;
  }

  removeImage(id: string): void {
    this.blocks = this.blocks.filter((block: BodyBlock) => block.imageId !== id);
    this.recordDocument();
  }

  private recordDocument(): void {
    this.content = documentText(this.blocks);
    this.closeGroup();
    this.record('image', false);
    this.closeGroup();
  }

  restoreHistory(redo: boolean): void {
    const draft: NoteDraft = redo ? this.history.redo() : this.history.undo();
    this.title = draft.title;
    this.blocks = JSON.parse(draft.content) as BodyBlock[];
    this.content = documentText(this.blocks);
    if (!this.blocks.some((block: BodyBlock) => block.id === this.activeBlock && block.imageId === '')) {
      this.activeBlock = this.blocks.find((block: BodyBlock) => block.imageId === '')?.id ?? '';
    }
    this.caret = Math.min(this.caret, this.blockText(this.activeBlock).length);
    this.updateHistoryButtons();
  }

  private updateHistoryButtons(): void {
    this.canUndo = this.history.canUndo();
    this.canRedo = this.history.canRedo();
  }
}
