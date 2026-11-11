export function noteTextCaret(text: string, controller: TextController | undefined,
  localXPx: number, localYPx: number): number | undefined {
  if (text.length === 0) { return 0; }
  if (!controller || !Number.isFinite(localXPx) || !Number.isFinite(localYPx)) { return undefined; }
  try {
    const layout: LayoutManager = controller.getLayoutManager();
    if (!layout || layout.getLineCount() <= 0) { return undefined; }
    const hit: PositionWithAffinity = layout.getGlyphPositionAtCoordinate(localXPx, localYPx);
    if (!hit || !Number.isInteger(hit.position) || hit.position < 0 || hit.position > text.length) {
      return undefined;
    }
    const offset: number = hit.position;
    if (offset > 0 && offset < text.length) {
      const before: number = text.charCodeAt(offset - 1);
      const after: number = text.charCodeAt(offset);
      if (before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF) {
        return undefined;
      }
    }
    return offset;
  } catch {
    return undefined;
  }
}
