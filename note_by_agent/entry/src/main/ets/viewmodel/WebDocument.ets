// 合并 Web 整篇文本与已有文字块，尽量保留块 ID，避免结构变化时整篇重写。
import { BodyBlock } from '../model/NoteDocument';

let sequence: number = 1;

function newBlockId(): string {
  return `block-web-${Date.now()}-${sequence++}`;
}

function lineScore(oldLine: string, newLine: string): number {
  if (oldLine === newLine) {
    return 1000000;
  }
  let prefix: number = 0;
  while (prefix < oldLine.length && prefix < newLine.length && oldLine.charCodeAt(prefix) === newLine.charCodeAt(prefix)) {
    prefix++;
  }
  let suffix: number = 0;
  while (suffix < oldLine.length - prefix && suffix < newLine.length - prefix &&
    oldLine.charCodeAt(oldLine.length - 1 - suffix) === newLine.charCodeAt(newLine.length - 1 - suffix)) {
    suffix++;
  }
  const longest: number = Math.max(1, oldLine.length, newLine.length);
  return 1 + (prefix + suffix) * 8 / longest;
}

function alignLines(oldLines: string[], newLines: string[]): number[] {
  const newCount: number = newLines.length;
  const match: number[] = [];
  for (let index: number = 0; index < newCount; index++) {
    match.push(-1);
  }
  const oldCount: number = oldLines.length;
  if (oldCount === 0 || newCount === 0 || oldCount * newCount > 40000) {
    const common: number = Math.min(oldCount, newCount);
    for (let index: number = 0; index < common; index++) {
      match[index] = index;
    }
    return match;
  }
  const dp: number[][] = [];
  for (let oldIndex: number = 0; oldIndex <= oldCount; oldIndex++) {
    const row: number[] = [];
    for (let newIndex: number = 0; newIndex <= newCount; newIndex++) {
      row.push(0);
    }
    dp.push(row);
  }
  for (let oldIndex: number = 1; oldIndex <= oldCount; oldIndex++) {
    for (let newIndex: number = 1; newIndex <= newCount; newIndex++) {
      const diagonal: number = dp[oldIndex - 1][newIndex - 1] +
        lineScore(oldLines[oldIndex - 1], newLines[newIndex - 1]);
      dp[oldIndex][newIndex] = Math.max(diagonal, dp[oldIndex - 1][newIndex], dp[oldIndex][newIndex - 1]);
    }
  }
  let oldIndex: number = oldCount;
  let newIndex: number = newCount;
  while (oldIndex > 0 && newIndex > 0) {
    const score: number = lineScore(oldLines[oldIndex - 1], newLines[newIndex - 1]);
    if (dp[oldIndex][newIndex] === dp[oldIndex - 1][newIndex - 1] + score) {
      match[newIndex - 1] = oldIndex - 1;
      oldIndex--;
      newIndex--;
    } else if (dp[oldIndex - 1][newIndex] >= dp[oldIndex][newIndex - 1]) {
      oldIndex--;
    } else {
      newIndex--;
    }
  }
  return match;
}

export function hasImageBlocks(blocks: BodyBlock[]): boolean {
  return blocks.some((block: BodyBlock) => block.imageId !== '');
}

export function mergeTextBlocks(blocks: BodyBlock[], lines: string[]): BodyBlock[] {
  if (hasImageBlocks(blocks)) {
    throw new Error('image blocks are not supported by the text-only web editor');
  }
  const oldLines: string[] = blocks.map((block: BodyBlock) => block.text);
  let prefix: number = 0;
  while (prefix < oldLines.length && prefix < lines.length && oldLines[prefix] === lines[prefix]) {
    prefix++;
  }
  let suffix: number = 0;
  while (suffix < oldLines.length - prefix && suffix < lines.length - prefix &&
    oldLines[oldLines.length - 1 - suffix] === lines[lines.length - 1 - suffix]) {
    suffix++;
  }
  const oldMiddle: string[] = oldLines.slice(prefix, oldLines.length - suffix);
  const newMiddle: string[] = lines.slice(prefix, lines.length - suffix);
  const match: number[] = alignLines(oldMiddle, newMiddle);
  const result: BodyBlock[] = [];
  for (let index: number = 0; index < prefix; index++) {
    result.push({ id: blocks[index].id, text: lines[index], imageId: '' } as BodyBlock);
  }
  for (let index: number = 0; index < newMiddle.length; index++) {
    const id: string = match[index] >= 0 ? blocks[prefix + match[index]].id : newBlockId();
    result.push({ id: id, text: newMiddle[index], imageId: '' } as BodyBlock);
  }
  for (let index: number = 0; index < suffix; index++) {
    const oldIndex: number = oldLines.length - suffix + index;
    result.push({ id: blocks[oldIndex].id, text: lines[lines.length - suffix + index], imageId: '' } as BodyBlock);
  }
  return result;
}
