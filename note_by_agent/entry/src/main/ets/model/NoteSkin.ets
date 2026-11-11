export interface NoteSkin {
  id: string;
  name: string;
  background: string;
  text: string;
  secondary: string;
  panel: string;
  effect: string;
}

export const NOTE_SKINS: NoteSkin[] = [
  { id: 'white', name: '默认白', background: '#FFFFFF', text: '#1A1A1A', secondary: '#777777', panel: '#F2F2F2', effect: 'none' },
  { id: 'yellow', name: '浅黄', background: '#FFF4CC', text: '#332B19', secondary: '#786B45', panel: '#F5E6AD', effect: 'none' },
  { id: 'green', name: '浅绿', background: '#DCEEE3', text: '#183C2E', secondary: '#527261', panel: '#C8DFD1', effect: 'none' },
  { id: 'breeze', name: '微风树叶', background: '#F1F4E8', text: '#293D30', secondary: '#687B64', panel: '#E4EBD8', effect: 'breeze' },
  { id: 'sakura', name: '樱落微风', background: '#FDF3F4', text: '#452B31', secondary: '#8A6A72', panel: '#F6E2E7', effect: 'sakura' },
  { id: 'firefly', name: '星夜萤火', background: '#101A2E', text: '#F2EEDC', secondary: '#A9B4C8', panel: '#1E2C47', effect: 'firefly' },
  { id: 'blue', name: '深蓝', background: '#173458', text: '#F4F7FC', secondary: '#BCCBE0', panel: '#25476E', effect: 'none' }
];

export function findSkin(id: string): NoteSkin {
  return NOTE_SKINS.find((skin: NoteSkin) => skin.id === id) ?? NOTE_SKINS[0];
}

export function isDynamicSkin(skin: NoteSkin): boolean {
  return skin.effect !== 'none';
}
