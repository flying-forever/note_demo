export interface DemoChunk {
  id: string;
  text: string;
  image: boolean;
}

export const CHUNK_TARGET: number = 3000;
export const CHUNK_LIMIT: number = 8000;

function protectedBoundary(text: string, offset: number): boolean {
  const before: number = text.charCodeAt(offset - 1);
  const after: number = text.charCodeAt(offset);
  return (before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF) ||
    before === 0x200D || after === 0x200D || (before === 13 && after === 10) ||
    (after >= 0x0300 && after <= 0x036F) || (after >= 0xFE00 && after <= 0xFE0F);
}

export function splitDemoText(text: string, target: number = CHUNK_TARGET): DemoChunk[] {
  if (target < 2 || target > CHUNK_LIMIT) {
    throw new Error('invalid chunk target');
  }
  const result: DemoChunk[] = [];
  let start: number = 0;
  while (start < text.length) {
    let end: number = Math.min(start + target, text.length);
    if (end < text.length) {
      const boundary: number = text.lastIndexOf('\n', end - 1);
      if (boundary >= start + Math.floor(target / 2)) {
        end = boundary + 1;
      }
      while (end > start && protectedBoundary(text, end)) {
        end--;
      }
      if (end === start) {
        throw new Error('unsupported grapheme sequence');
      }
    }
    result.push({ id: `text-${result.length}`, text: text.slice(start, end), image: false });
    start = end;
  }
  return result;
}

export function fixtureText(length: number, paragraphs: boolean): string {
  const seed: string = paragraphs ? '清晨沿着河岸散步，记录沿途见闻。\n下午整理照片，继续写下今天的想法。\n' :
    '清晨沿着河岸散步记录沿途见闻下午整理照片继续写下今天的想法';
  return seed.repeat(Math.ceil(length / seed.length)).slice(0, length);
}

export function fixtureChunks(text: string, images: boolean): DemoChunk[] {
  const chunks: DemoChunk[] = splitDemoText(text);
  if (!images) {
    return chunks;
  }
  const result: DemoChunk[] = [];
  chunks.forEach((chunk: DemoChunk, index: number) => {
    result.push(chunk);
    if (index % 4 === 3) {
      result.push({ id: `image-${index}`, text: '', image: true });
    }
  });
  return result;
}

export class DemoChunkSource implements IDataSource {
  private chunks: DemoChunk[] = [];
  private listeners: DataChangeListener[] = [];
  private generation: number = 0;

  totalCount(): number {
    return this.chunks.length;
  }

  getData(index: number): DemoChunk {
    return this.chunks[index];
  }

  replace(chunks: DemoChunk[]): void {
    this.generation++;
    chunks.forEach((chunk: DemoChunk) => { chunk.id = `${this.generation}-${chunk.id}`; });
    this.chunks = chunks;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  update(id: string, value: string): void {
    const index: number = this.chunks.findIndex((chunk: DemoChunk) => chunk.id === id);
    if (index >= 0) {
      this.chunks[index].text = value;
    }
  }

  exportText(): string {
    return this.chunks.filter((chunk: DemoChunk) => !chunk.image)
      .map((chunk: DemoChunk) => chunk.text).join('');
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
