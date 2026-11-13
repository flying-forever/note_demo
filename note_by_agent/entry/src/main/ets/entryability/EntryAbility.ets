// 初始化笔记数据库与主窗口，并处理桌面卡片启动请求。
import { initializeNoteRepository, refreshNotes } from '../repository/NoteRepository';
import { desktopLaunchNoteId } from '../platform/NoteLaunch';
import { SystemBarInitResult, SystemBars } from '../platform/SystemBars';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private receiveWant(want: Want): void {
    AppStorage.setOrCreate('desktopLaunchNoteId', desktopLaunchNoteId(want));
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveWant(want);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveWant(want);
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  private loadContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    try {
      await initializeNoteRepository(this.context);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Note repository initialization failed: %{public}s', String(error));
    }
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    SystemBars.initialize(windowStage)
      .then((result: SystemBarInitResult) => {
        if (result === SystemBarInitResult.CANCELLED) {
          return;
        }
        if (result === SystemBarInitResult.FALLBACK) {
          hilog.warn(DOMAIN, 'testTag', '%{public}s', 'System bars not ready; loading fallback layout.');
        }
        this.loadContent(windowStage);
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to initialize system bars. Cause: %{public}s', JSON.stringify(error));
        this.loadContent(windowStage);
      });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    SystemBars.release();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    refreshNotes().catch(() => {});
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
