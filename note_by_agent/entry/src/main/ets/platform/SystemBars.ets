// 统一处理主窗口全屏、系统栏避让高度和状态栏/导航栏图标明暗。
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SystemBars';
const TOP_KEY = 'systemBarTopVp';
const BOTTOM_KEY = 'systemBarBottomVp';
const TRANSPARENT = '#00000000';
const DARK_CONTENT = '#000000';
const LIGHT_CONTENT = '#FFFFFF';

export enum SystemBarInitResult {
  READY,
  FALLBACK,
  CANCELLED
}

export class SystemBars {
  private static mainWindow: window.Window | undefined = undefined;
  private static avoidAreaListener: ((options: window.AvoidAreaOptions) => void) | undefined = undefined;
  private static styleQueue: Promise<void> = Promise.resolve();
  private static generation: number = 0;

  static async initialize(windowStage: window.WindowStage): Promise<SystemBarInitResult> {
    const generation: number = ++SystemBars.generation;
    let mainWindow: window.Window | undefined = undefined;
    try {
      mainWindow = windowStage.getMainWindowSync();
      await mainWindow.setWindowLayoutFullScreen(true);
    } catch (error) {
      SystemBars.logError('开启全屏布局失败');
      return generation === SystemBars.generation ? SystemBarInitResult.FALLBACK : SystemBarInitResult.CANCELLED;
    }
    if (generation !== SystemBars.generation) {
      return SystemBarInitResult.CANCELLED;
    }
    SystemBars.mainWindow = mainWindow;
    try {
      await mainWindow.setWindowSystemBarProperties(SystemBars.properties(DARK_CONTENT));
    } catch (error) {
      SystemBars.logError('初始化系统栏样式失败');
    }
    if (generation !== SystemBars.generation) {
      return SystemBarInitResult.CANCELLED;
    }
    let insetsReady: boolean = SystemBars.updateInsets();
    if (!insetsReady) {
      if (generation !== SystemBars.generation) {
        return SystemBarInitResult.CANCELLED;
      }
      let rolledBack: boolean = false;
      try {
        await mainWindow.setWindowLayoutFullScreen(false);
        rolledBack = true;
      } catch (error) {
        SystemBars.logError('回退普通布局失败');
      }
      if (generation !== SystemBars.generation) {
        return SystemBarInitResult.CANCELLED;
      }
      if (rolledBack) {
        SystemBars.mainWindow = undefined;
        SystemBars.setInsets(0, 0);
        return SystemBarInitResult.FALLBACK;
      }
      insetsReady = SystemBars.updateInsets();
      if (!insetsReady) {
        SystemBars.logError('系统栏避让区不可用，保留窗口引用等待页面显示后恢复');
      }
    }
    let listener: ((options: window.AvoidAreaOptions) => void) | undefined = undefined;
    try {
      listener = (_options: window.AvoidAreaOptions): void => {
        SystemBars.updateInsets();
      };
      SystemBars.avoidAreaListener = listener;
      mainWindow.on('avoidAreaChange', listener);
    } catch (error) {
      SystemBars.avoidAreaListener = undefined;
      listener = undefined;
      SystemBars.logError('监听系统栏避让区失败');
    }
    if (generation !== SystemBars.generation) {
      if (listener) {
        try {
          mainWindow.off('avoidAreaChange', listener);
        } catch (error) {
          SystemBars.logError('清理过期系统栏监听失败');
        }
      }
      return SystemBarInitResult.CANCELLED;
    }
    return insetsReady ? SystemBarInitResult.READY : SystemBarInitResult.FALLBACK;
  }

  static refreshInsets(): void {
    SystemBars.updateInsets();
  }

  static applyForBackground(background: string): void {
    const generation: number = SystemBars.generation;
    const contentColor: string = SystemBars.isLight(background) ? DARK_CONTENT : LIGHT_CONTENT;
    SystemBars.styleQueue = SystemBars.styleQueue.then(async () => {
      if (generation !== SystemBars.generation) {
        return;
      }
      const mainWindow: window.Window | undefined = SystemBars.mainWindow;
      if (!mainWindow) {
        return;
      }
      await mainWindow.setWindowSystemBarProperties(SystemBars.properties(contentColor));
    }).catch(() => {
      SystemBars.logError('更新系统栏样式失败');
    });
  }

  static release(): void {
    SystemBars.generation++;
    const mainWindow: window.Window | undefined = SystemBars.mainWindow;
    const listener = SystemBars.avoidAreaListener;
    try {
      if (mainWindow && listener) {
        mainWindow.off('avoidAreaChange', listener);
      }
    } catch (error) {
      SystemBars.logError('释放系统栏监听失败');
    } finally {
      SystemBars.mainWindow = undefined;
      SystemBars.avoidAreaListener = undefined;
      SystemBars.setInsets(0, 0);
    }
  }

  private static properties(contentColor: string): window.SystemBarProperties {
    return {
      statusBarColor: TRANSPARENT,
      navigationBarColor: TRANSPARENT,
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor
    };
  }

  private static updateInsets(): boolean {
    const mainWindow: window.Window | undefined = SystemBars.mainWindow;
    if (!mainWindow) {
      return false;
    }
    try {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicatorArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const topPx: number = Math.max(systemArea.topRect.height, cutoutArea.topRect.height);
      const bottomPx: number = Math.max(systemArea.bottomRect.height, indicatorArea.bottomRect.height);
      SystemBars.setInsets(topPx / density, bottomPx / density);
      return true;
    } catch (error) {
      SystemBars.logError('读取系统栏避让区失败');
      return false;
    }
  }

  private static setInsets(topVp: number, bottomVp: number): void {
    AppStorage.setOrCreate(TOP_KEY, topVp);
    AppStorage.setOrCreate(BOTTOM_KEY, bottomVp);
  }

  private static isLight(background: string): boolean {
    if (background.length < 7 || background.charAt(0) !== '#') {
      return true;
    }
    const red: number = parseInt(background.substring(1, 3), 16) / 255;
    const green: number = parseInt(background.substring(3, 5), 16) / 255;
    const blue: number = parseInt(background.substring(5, 7), 16) / 255;
    const luminance: number = 0.2126 * SystemBars.linear(red) +
      0.7152 * SystemBars.linear(green) + 0.0722 * SystemBars.linear(blue);
    return luminance > 0.45;
  }

  private static linear(value: number): number {
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  }

  private static logError(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
  }
}
