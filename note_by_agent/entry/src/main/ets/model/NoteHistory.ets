// 管理草稿撤销与重做历史，并按输入间隔与编辑字段合并记录。
export interface NoteDraft {
  title: string;
  content: string;
}

const INPUT_MERGE_INTERVAL: number = 2000;

export class NoteHistory {
  private entries: NoteDraft[] = [];
  private position: number = 0;
  private lastField: string = '';
  private lastChangedAt: number = 0;

  constructor(title: string, content: string) {
    this.entries = [{ title: title, content: content }];
  }

  closeGroup(): void {
    this.lastField = '';
  }

  record(title: string, content: string, field: string): void {
    const current: NoteDraft = this.entries[this.position];
    if (current.title === title && current.content === content) {
      return;
    }
    const now: number = Date.now();
    const merge: boolean = this.lastField === field && now - this.lastChangedAt < INPUT_MERGE_INTERVAL;
    this.entries = this.entries.slice(0, this.position + 1);
    const draft: NoteDraft = { title: title, content: content };
    if (merge) {
      this.entries[this.position] = draft;
    } else {
      this.entries.push(draft);
      this.position++;
    }
    this.lastField = field;
    this.lastChangedAt = now;
  }

  canUndo(): boolean {
    return this.position > 0;
  }

  canRedo(): boolean {
    return this.position < this.entries.length - 1;
  }

  undo(): NoteDraft {
    this.closeGroup();
    if (this.canUndo()) {
      this.position--;
    }
    return this.entries[this.position];
  }

  redo(): NoteDraft {
    this.closeGroup();
    if (this.canRedo()) {
      this.position++;
    }
    return this.entries[this.position];
  }
}
