import {
  KEY_D,
  KEY_S,
  KEY_TAB,
  MOD_LEFT_GUI
} from '../model/HidKeyCodes';
import {
  MappingMode,
  SwipeDirection,
  TouchpadAction,
  TouchpadActionType
} from '../model/TouchpadTypes';
import { ITouchpadActionMapper } from './ITouchpadActionMapper';

function makeKeyAction(modifiers: number, keycode: number, label: string): TouchpadAction {
  return {
    type: TouchpadActionType.KEY_COMBO,
    dx: 0,
    dy: 0,
    vScroll: 0,
    hScroll: 0,
    buttonMask: 0,
    modifiers: modifiers,
    keycode: keycode,
    label: label
  };
}

function makeAppSwitchStartAction(dx: number, label: string): TouchpadAction {
  return {
    type: TouchpadActionType.APP_SWITCH_START,
    dx: dx,
    dy: 0,
    vScroll: 0,
    hScroll: 0,
    buttonMask: 0,
    modifiers: 0,
    keycode: 0,
    label: label
  };
}

/**
 * v0.2 Mac-Style Remap Mapper (aligned with HarmonyOS PC 3-finger logic on 4 fingers):
 * - 3-finger slide: Mac-style Three-Finger Drag (1:1 parity sensitivity + jitter immunity + 320ms clutch)
 * - 4-finger+ gestures: Full HarmonyOS PC 3-finger gesture set!
 *     * 4-finger UP (quick lift) -> Show Desktop (Meta+D)
 *     * 4-finger UP + Hold (>=220ms) -> Multitask Task Center (Meta+Tab)
 *     * 4-finger DOWN -> Restore Windows (Meta+D)
 *     * 4-finger LEFT/RIGHT -> Interactive sticky Alt+Tab app switcher
 *     * 4-finger TAP -> Global Search (Meta+S)
 */
export class MacRemapActionMapper implements ITouchpadActionMapper {
  public readonly mode: MappingMode = MappingMode.MAC_THREE_FINGER_DRAG;
  public readonly displayName: string = 'v0.2 Mac三指拖移';
  public readonly isThreeFingerDragEnabled: boolean = true;

  public mapMultiFingerTap(fingerCount: number): TouchpadAction | null {
    if (fingerCount >= 4) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_S, '四指轻点(映三指) → 全局搜索 (鸿蒙键+S)');
    }
    return null;
  }

  public mapMultiFingerSwipe(fingerCount: number, direction: SwipeDirection): TouchpadAction | null {
    if (fingerCount >= 4) {
      if (direction === SwipeDirection.UP) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_D, '四指上滑(映三指) → 显示桌面 (鸿蒙键+D)');
      }
      if (direction === SwipeDirection.DOWN) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_D, '四指下滑(映三指) → 还原窗口 (鸿蒙键+D)');
      }
      if (direction === SwipeDirection.LEFT) {
        return makeAppSwitchStartAction(1, '四指左滑(映三指) → 切换应用 (Alt+Tab，不松手可左右选)');
      }
      if (direction === SwipeDirection.RIGHT) {
        return makeAppSwitchStartAction(1, '四指右滑(映三指) → 切换应用 (Alt+Tab，不松手可左右选)');
      }
    }
    return null;
  }

  public mapMultiFingerSwipeUpHold(fingerCount: number): TouchpadAction | null {
    if (fingerCount >= 4) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_TAB, '四指上滑停顿(映三指) → 任务中心 (鸿蒙键+Tab)');
    }
    return null;
  }
}
