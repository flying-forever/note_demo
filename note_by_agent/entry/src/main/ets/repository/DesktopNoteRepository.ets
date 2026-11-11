import { fileIo as fs } from '@kit.CoreFileKit';
import { Note } from '../model/Note';

export interface DesktopRecord {
  version: number;
  id: string;
  deleted: boolean;
  note?: Note;
}

export interface DesktopFormLink {
  formId: string;
  noteId: string;
}

let directory: string = '';
let writeSequence: number = 0;

export function initializeDesktopRepository(filesDir: string): void {
  directory = filesDir + '/desktop-notes';
  [directory, directory + '/notes', directory + '/forms'].forEach((path: string) => {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  });
}

function recordPath(id: string): string {
  return directory + '/notes/' + encodeURIComponent(id) + '.json';
}

function linkPath(id: string): string {
  return directory + '/forms/' + encodeURIComponent(id) + '.json';
}

function writeFile(path: string, value: string): void {
  if (directory === '') {
    throw new Error('Desktop repository is not initialized');
  }
  const temporary: string = `${path}.${Date.now()}-${Math.random().toString(36).substring(2)}-${writeSequence++}.tmp`;
  const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    try {
      fs.writeSync(file.fd, value);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(temporary, path);
  } catch (error) {
    try { fs.unlinkSync(temporary); } catch {}
    throw new Error('Desktop note write failed');
  }
}

export function readDesktopRecord(id: string): DesktopRecord | undefined {
  if (directory === '' || !fs.accessSync(recordPath(id))) {
    return undefined;
  }
  const record = JSON.parse(fs.readTextSync(recordPath(id))) as DesktopRecord;
  if (record.version !== 1 || record.id !== id || (!record.deleted && record.note?.id !== id)) {
    throw new Error('Invalid desktop note record');
  }
  return record;
}

export function readDesktopNote(id: string): Note | undefined {
  const record = readDesktopRecord(id);
  return record?.deleted ? undefined : record?.note;
}

export function listDesktopRecords(): DesktopRecord[] {
  if (directory === '') {
    return [];
  }
  const records: DesktopRecord[] = [];
  fs.listFileSync(directory + '/notes').filter((name: string) => name.endsWith('.json')).forEach((name: string) => {
    const id: string = decodeURIComponent(name.substring(0, name.length - 5));
    const record = readDesktopRecord(id);
    if (record) {
      records.push(record);
    }
  });
  return records;
}

export function persistDesktopNote(note: Note): void {
  const record: DesktopRecord = { version: 1, id: note.id, deleted: false, note: note };
  writeFile(recordPath(note.id), JSON.stringify(record));
}

export function deleteDesktopNote(id: string): void {
  if (readDesktopRecord(id)) {
    const record: DesktopRecord = { version: 1, id: id, deleted: true };
    writeFile(recordPath(id), JSON.stringify(record));
  }
}

export function desktopLink(formId: string): DesktopFormLink | undefined {
  if (directory === '' || !fs.accessSync(linkPath(formId))) {
    return undefined;
  }
  return JSON.parse(fs.readTextSync(linkPath(formId))) as DesktopFormLink;
}

export function bindDesktopForm(formId: string, noteId: string): void {
  const link: DesktopFormLink = { formId: formId, noteId: noteId };
  writeFile(linkPath(formId), JSON.stringify(link));
}

export function removeDesktopForm(formId: string): void {
  if (fs.accessSync(linkPath(formId))) {
    fs.unlinkSync(linkPath(formId));
  }
}

export function listDesktopFormIds(): string[] {
  if (directory === '') {
    return [];
  }
  return fs.listFileSync(directory + '/forms').filter((name: string) => name.endsWith('.json'))
    .map((name: string) => decodeURIComponent(name.substring(0, name.length - 5)));
}
