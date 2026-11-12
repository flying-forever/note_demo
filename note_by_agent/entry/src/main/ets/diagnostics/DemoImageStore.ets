// 提供开发期内置图片：从 rawfile 复制到沙箱，并按体积上限返回缩略 data URI。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export interface DemoImage {
  name: string;
  mime: string;
  dataUri: string;
  bytes: number;
}

export const MAX_IMAGE_BYTES: number = 300 * 1024;
const NAMES: string[] = ['photo-1.jpg', 'photo-2.jpg', 'photo-3.jpg'];
let cursor: number = 0;

function imageDirectory(context: common.UIAbilityContext): string {
  const directory: string = context.filesDir + '/images';
  if (!fs.accessSync(directory)) {
    fs.mkdirSync(directory, true);
  }
  return directory;
}

export async function seedDemoImages(context: common.UIAbilityContext): Promise<number> {
  const directory: string = imageDirectory(context);
  let ready: number = 0;
  for (const name of NAMES) {
    const path: string = `${directory}/${name}`;
    if (!fs.accessSync(path)) {
      try {
        const bytes: Uint8Array = await context.resourceManager.getRawFileContent(`demo-images/${name}`);
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        try {
          fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
        } finally {
          fs.closeSync(file);
        }
      } catch (error) {
        console.error(`demo image seed failed: ${name} ${error}`);
        continue;
      }
    }
    ready++;
  }
  return ready;
}

export async function nextDemoImage(context: common.UIAbilityContext): Promise<DemoImage | null> {
  const directory: string = imageDirectory(context);
  for (let attempt = 0; attempt < NAMES.length; attempt++) {
    const name: string = NAMES[cursor % NAMES.length];
    cursor++;
    const path: string = `${directory}/${name}`;
    try {
      if (!fs.accessSync(path)) {
        continue;
      }
      const size: number = fs.statSync(path).size;
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let bytes: Uint8Array;
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        fs.readSync(file.fd, buffer);
        bytes = new Uint8Array(buffer);
      } finally {
        fs.closeSync(file);
      }
      if (bytes.byteLength > MAX_IMAGE_BYTES) {
        bytes = compressImage(bytes);
      }
      if (bytes.byteLength > MAX_IMAGE_BYTES) {
        console.error(`demo image too large after compress: ${name} ${bytes.byteLength}`);
        continue;
      }
      const base64: string = new util.Base64Helper().encodeToStringSync(bytes);
      return { name: name, mime: 'image/jpeg', dataUri: `data:image/jpeg;base64,${base64}`,
        bytes: bytes.byteLength };
    } catch (error) {
      console.error(`demo image read failed: ${name} ${error}`);
    }
  }
  return null;
}

function compressImage(bytes: Uint8Array): Uint8Array {
  return bytes;
}

export function resetDemoImageCursor(): void {
  cursor = 0;
}
