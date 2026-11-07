export interface BodyBlock {
  id: string;
  text: string;
  imageId: string;
}

export interface NoteImage {
  id: string;
  path: string;
  name: string;
  width: number;
  height: number;
  bytes: number;
  caption: string;
  small: boolean;
}

let sequence: number = 0;

export function textBlock(text: string): BodyBlock {
  return { id: `block-${Date.now()}-${sequence++}`, text: text, imageId: '' };
}

export function documentText(blocks: BodyBlock[]): string {
  return blocks.filter((block: BodyBlock) => block.imageId === '').map((block: BodyBlock) => block.text).join('\n');
}

export function copyImage(item: NoteImage, caption: string = item.caption, small: boolean = item.small): NoteImage {
  return { id: item.id, path: item.path, name: item.name, width: item.width, height: item.height,
    bytes: item.bytes, caption: caption, small: small };
}
