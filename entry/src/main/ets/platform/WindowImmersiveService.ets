import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Isolates HarmonyOS Window immersive, navigation bar hiding, and side-swipe back gesture blocking.
 */
export class WindowImmersiveService {
  /**
   * Disables or restores the system side-swipe back gesture hot zone on the main window (API 13+).
   * When guardEnabled=true, swiping from left/right phone edges will NOT trigger system back or exit the app.
   */
  public async setEdgeGestureGuard(context: common.UIAbilityContext, guardEnabled: boolean): Promise<string> {
    try {
      const win: window.Window = await window.getLastWindow(context);
      await win.setGestureBackEnabled(!guardEnabled);
      return '';
    } catch (err) {
      const e = err as BusinessError;
      return `设置边缘防误触失败: ${e.code} ${e.message}`;
    }
  }

  public async setFullScreen(
    context: common.UIAbilityContext,
    enabled: boolean,
    keepEdgeGuard: boolean
  ): Promise<string> {
    try {
      const win: window.Window = await window.getLastWindow(context);
      await win.setWindowLayoutFullScreen(enabled);
      await win.setSpecificSystemBarEnabled('status', !enabled);
      await win.setSpecificSystemBarEnabled('navigation', !enabled);
      await win.setSpecificSystemBarEnabled('navigationIndicator', !enabled);
      await win.setGestureBackEnabled(!(enabled || keepEdgeGuard));
      return '';
    } catch (err) {
      const e = err as BusinessError;
      return `切换沉浸模式失败: ${e.code} ${e.message}`;
    }
  }
}
