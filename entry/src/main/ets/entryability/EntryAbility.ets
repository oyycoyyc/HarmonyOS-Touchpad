import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'TouchpadEntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}d %{public}s', e.code, e.message);
    }
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate');

    windowStage.getMainWindow((err: BusinessError, win: window.Window) => {
      if (err && err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'getMainWindow failed: %{public}d %{public}s', err.code, err.message);
      } else {
        win.setWindowKeepScreenOn(true, (keepErr: BusinessError) => {
          if (keepErr && keepErr.code !== 0) {
            hilog.warn(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}d', keepErr.code);
          }
        });
        win.setGestureBackEnabled(false).catch((gestureErr: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'setGestureBackEnabled failed: %{public}d %{public}s', gestureErr.code, gestureErr.message);
        });
      }
    });

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err && err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load pages/Index. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading pages/Index.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground');
  }
}
