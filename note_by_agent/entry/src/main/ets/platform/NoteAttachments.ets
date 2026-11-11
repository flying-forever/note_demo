// 导入图片到应用私有目录并读取元数据，清理不再引用的附件。
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { NoteImage } from '../model/NoteDocument';
import { Note } from '../model/Note';

export async function importNoteImage(filesDir: string, uri: string): Promise<NoteImage> {
  const directory: string = filesDir + '/note-images';
  if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true); }
  const id: string = `image-${Date.now()}`;
  const path: string = directory + '/' + id;
  try {
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try { fs.copyFileSync(source.fd, path); } finally { fs.closeSync(source); }
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
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
    return { id: id, path: path, name: id, width: width, height: height,
      bytes: fs.statSync(path).size, caption: '', small: false };
  } catch (error) {
    try { fs.unlinkSync(path); } catch {}
    throw new Error('Image import failed');
  }
}

export function releaseUnusedImages(images: NoteImage[], saved: Note[]): void {
  images.forEach((item: NoteImage) => {
    if (!saved.some((note: Note) => note.images?.some((image: NoteImage) => image.path === item.path))) {
      try { fs.unlinkSync(item.path); } catch {}
    }
  });
}
