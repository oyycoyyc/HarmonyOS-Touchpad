import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface PermissionResult {
  granted: boolean;
  errorMessage: string;
}

/**
 * Isolates HarmonyOS dynamic permission requests from UI components.
 */
export class BluetoothPermissionService {
  public async requestAccessBluetooth(context: common.UIAbilityContext): Promise<PermissionResult> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = ['ohos.permission.ACCESS_BLUETOOTH'];
      const res = await atManager.requestPermissionsFromUser(context, permissions);
      const granted = res.authResults.length > 0 && res.authResults[0] === 0;
      return {
        granted: granted,
        errorMessage: granted ? '' : '用户拒绝了 ACCESS_BLUETOOTH 权限'
      };
    } catch (err) {
      const e = err as BusinessError;
      return {
        granted: false,
        errorMessage: `申请权限异常: ${e.code} ${e.message}`
      };
    }
  }
}
