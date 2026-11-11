// 保存和读取首页视图模式等应用级设置。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export const VIEW_WATERFALL: string = 'waterfall';
export const VIEW_LIST: string = 'list';

const STORE_NAME: string = 'note_settings';
const VIEW_MODE_KEY: string = 'view_mode';

export function loadViewMode(context: common.UIAbilityContext): string {
  try {
    const options: preferences.Options = { name: STORE_NAME };
    const store = preferences.getPreferencesSync(context, options);
    return store.getSync(VIEW_MODE_KEY, VIEW_WATERFALL) === VIEW_LIST ? VIEW_LIST : VIEW_WATERFALL;
  } catch {
    return VIEW_WATERFALL;
  }
}

export async function saveViewMode(context: common.UIAbilityContext, mode: string): Promise<boolean> {
  try {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(VIEW_MODE_KEY, mode);
    await store.flush();
    return true;
  } catch {
    return false;
  }
}
