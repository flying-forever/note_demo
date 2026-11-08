import { fileIo as fs } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Note, noteCardTitle } from './Note';
import { findSkin } from './NoteSkin';

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

export interface DesktopCardData {
  noteId: string;
  cardTitle: string;
  summary: string;
  background: string;
  textColor: string;
  secondary: string;
}

let directory: string = '';

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
  const temporary: string = path + '.tmp';
  const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, value);
    fs.fsyncSync(file.fd);
  } finally {
    fs.closeSync(file);
  }
  fs.renameSync(temporary, path);
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

export function desktopCardData(note?: Note, deleted: boolean = false): DesktopCardData {
  const skin = findSkin(note?.skinId ?? 'white');
  return {
    noteId: note?.id ?? '',
    cardTitle: note ? noteCardTitle(note) : (deleted ? '笔记已删除' : '笔记'),
    summary: note ? (note.content.trim() || '图片笔记，点击查看') :
      (deleted ? '可移除此卡片' : '在笔记的更多菜单中发送到桌面'),
    background: skin.background, textColor: skin.text, secondary: skin.secondary
  };
}

export async function refreshDesktopForm(formId: string): Promise<void> {
  const link = desktopLink(formId);
  const note = link ? readDesktopNote(link.noteId) : undefined;
  await formProvider.updateForm(formId, formBindingData.createFormBindingData(desktopCardData(note, link !== undefined && !note)));
}

export async function refreshDesktopCards(noteId: string): Promise<void> {
  if (directory === '') {
    return;
  }
  const names: string[] = fs.listFileSync(directory + '/forms').filter((name: string) => name.endsWith('.json'));
  for (const name of names) {
    const id: string = decodeURIComponent(name.substring(0, name.length - 5));
    if (desktopLink(id)?.noteId === noteId) {
      try {
        await refreshDesktopForm(id);
      } catch {
        hilog.warn(0x0000, 'NoteDesktop', 'Desktop card refresh failed');
      }
    }
  }
}
