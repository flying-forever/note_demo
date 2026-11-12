// 导入图片到应用私有目录并读取元数据，生成可重建缩略图，清理不再被任何笔记引用的附件。
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { NoteImage } from '../model/NoteDocument';

const IMAGE_DIRECTORY: string = '/note-images';
const THUMB_DIRECTORY: string = '/note-images-thumbs';
const THUMB_SUFFIX: string = '.thumb';
const THUMB_LONG_EDGE: number = 960;
const THUMB_QUALITY: number = 75;
export const MAX_IMAGE_BYTES: number = 500 * 1024;
let imageSequence: number = 1;

export function thumbnailPath(path: string): string {
  const marker: string = IMAGE_DIRECTORY + '/';
  const index: number = path.lastIndexOf(marker);
  if (index < 0) {
    return '';
  }
  return path.substring(0, index) + THUMB_DIRECTORY + '/' + path.substring(index + marker.length) + THUMB_SUFFIX;
}

export function thumbnailFor(path: string): string {
  const thumb: string = thumbnailPath(path);
  return thumb !== '' && fs.accessSync(thumb) ? thumb : path;
}

export async function ensureThumbnail(path: string): Promise<string> {
  const thumb: string = thumbnailPath(path);
  if (thumb === '' || !fs.accessSync(path)) {
    return path;
  }
  if (fs.accessSync(thumb)) {
    return thumb;
  }
  const directory: string = thumb.substring(0, thumb.lastIndexOf('/'));
  if (!fs.accessSync(directory)) {
    fs.mkdirSync(directory, true);
  }
  const temporary: string = thumb + '.part';
  try {
    const source: image.ImageSource = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      const longest: number = Math.max(info.size.width, info.size.height);
      const scale: number = longest > THUMB_LONG_EDGE ? THUMB_LONG_EDGE / longest : 1;
      const width: number = Math.max(1, Math.round(info.size.width * scale));
      const height: number = Math.max(1, Math.round(info.size.height * scale));
      const pixel: image.PixelMap = await source.createPixelMap({ desiredSize: { width: width, height: height } });
      try {
        const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          const packer: image.ImagePacker = image.createImagePacker();
          try {
            await packer.packToFile(pixel, file.fd, { format: 'image/jpeg', quality: THUMB_QUALITY });
          } finally {
            await packer.release();
          }
        } finally {
          fs.closeSync(file);
        }
      } finally {
        await pixel.release();
      }
    } finally {
      await source.release();
    }
    fs.renameSync(temporary, thumb);
    return thumb;
  } catch (error) {
    try { fs.unlinkSync(temporary); } catch {}
    return path;
  }
}

export async function importNoteImage(filesDir: string, uri: string): Promise<NoteImage> {
  const directory: string = filesDir + IMAGE_DIRECTORY;
  if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
  const id: string = `image-${Date.now()}-${imageSequence++}`;
  const path: string = directory + '/' + id;
  const temporary: string = path + '.part';
  try {
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try { fs.copyFileSync(source.fd, temporary); } finally { fs.closeSync(source); }
    const bytes: number = fs.statSync(temporary).size;
    if (bytes > MAX_IMAGE_BYTES) {
      throw new Error('Image too large');
    }
    const file = fs.openSync(temporary, fs.OpenMode.READ_ONLY);
    let width: number = 1;
    let height: number = 1;
    try {
      const decoder = image.createImageSource(file.fd);
      try {
        const info = await decoder.getImageInfo();
        width = info.size.width;
        height = info.size.height;
      } finally { await decoder.release(); }
    } finally { fs.closeSync(file); }
    fs.renameSync(temporary, path);
    await ensureThumbnail(path);
    return { id: id, path: path, name: id, width: width, height: height,
      bytes: bytes, caption: '', small: false };
  } catch (error) {
    try { fs.unlinkSync(temporary); } catch {}
    try { fs.unlinkSync(path); } catch {}
    throw new Error('Image import failed');
  }
}

export function releaseAttachmentFile(path: string): void {
  try { fs.unlinkSync(path); } catch {}
  const thumb: string = thumbnailPath(path);
  if (thumb !== '') {
    try { fs.unlinkSync(thumb); } catch {}
  }
}

export function releaseUnusedImages(images: NoteImage[], referencedPaths: string[]): void {
  images.forEach((item: NoteImage) => {
    if (!referencedPaths.includes(item.path)) {
      try { fs.unlinkSync(item.path); } catch {}
    }
  });
}

export function cleanupOrphanImages(filesDir: string, referencedPaths: string[], minAgeMs: number = 60000): void {
  const directory: string = filesDir + IMAGE_DIRECTORY;
  if (!fs.accessSync(directory)) {
    return;
  }
  let names: string[] = [];
  try { names = fs.listFileSync(directory); } catch { return; }
  const now: number = Date.now();
  for (const name of names) {
    const path: string = directory + '/' + name;
    if (referencedPaths.includes(path)) {
      continue;
    }
    try {
      const info = fs.statSync(path);
      const age: number = now - info.mtime * 1000;
      if (age < minAgeMs) {
        continue;
      }
      fs.unlinkSync(path);
    } catch {
      continue;
    }
  }
  const thumbnailDir: string = filesDir + THUMB_DIRECTORY;
  if (!fs.accessSync(thumbnailDir)) {
    return;
  }
  let thumbs: string[] = [];
  try { thumbs = fs.listFileSync(thumbnailDir); } catch { return; }
  for (const name of thumbs) {
    if (!name.endsWith(THUMB_SUFFIX)) {
      if (name.endsWith(THUMB_SUFFIX + '.part')) {
        try {
          const partPath: string = thumbnailDir + '/' + name;
          const partInfo = fs.statSync(partPath);
          if (now - partInfo.mtime * 1000 >= minAgeMs) {
            fs.unlinkSync(partPath);
          }
        } catch {
        }
      }
      continue;
    }
    const original: string = directory + '/' + name.substring(0, name.length - THUMB_SUFFIX.length);
    if (referencedPaths.includes(original) && fs.accessSync(original)) {
      continue;
    }
    try {
      const path: string = thumbnailDir + '/' + name;
      const info = fs.statSync(path);
      if (now - info.mtime * 1000 < minAgeMs) {
        continue;
      }
      fs.unlinkSync(path);
    } catch {
      continue;
    }
  }
}
