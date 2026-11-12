// 初始化笔记数据库与主窗口，并处理桌面卡片启动请求。
import { initializeNoteRepository, refreshNotes } from '../repository/NoteRepository';
import { desktopLaunchNoteId } from '../platform/NoteLaunch';
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

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', 'Ability onWindowStageCreate');
    try {
      await initializeNoteRepository(this.context);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Note repository initialization failed: %{public}s', String(error));
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
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
