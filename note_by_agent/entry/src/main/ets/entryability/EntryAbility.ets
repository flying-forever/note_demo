import { formInfo } from '@kit.FormKit';
import { initializeDesktopRepository, desktopLink } from '../model/DesktopNoteRepository';
import { syncDesktopNotes } from '../model/NoteStore';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private pendingNoteId: string = '';

  private receiveWant(want: Want): void {
    initializeDesktopRepository(this.context.filesDir);
    syncDesktopNotes();
    this.pendingNoteId = typeof want.parameters?.['noteId'] === 'string' ? want.parameters['noteId'] as string : '';
    const serialized = want.parameters?.['params'];
    if (this.pendingNoteId === '' && typeof serialized === 'string') {
      try {
        const parameters = JSON.parse(serialized) as Record<string, string>;
        if (typeof parameters.noteId === 'string') {
          this.pendingNoteId = parameters.noteId;
        }
      } catch {
        this.pendingNoteId = '';
      }
    }
    if (this.pendingNoteId === '') {
      const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
      if (formId !== undefined) {
        this.pendingNoteId = desktopLink(String(formId))?.noteId ?? '';
      }
    }
    AppStorage.setOrCreate('desktopLaunchNoteId', this.pendingNoteId);
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

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    syncDesktopNotes();
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}