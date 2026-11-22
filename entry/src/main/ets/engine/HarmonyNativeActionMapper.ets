import {
  KEY_C,
  KEY_D,
  KEY_ESC,
  KEY_LEFT,
  KEY_RIGHT,
  KEY_S,
  KEY_TAB,
  MOD_LEFT_GUI,
  MOD_NONE
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
 * v0.1 HarmonyOS PC Official Native Logic Mapper:
 * - 3-finger UP (quick lift): Show Desktop (Meta+D)
 * - 3-finger UP + Hold (>=220ms): Multitask Task Center (Meta+Tab)
 * - 3-finger DOWN: Restore hidden windows / toggle Desktop (Meta+D)
 * - 3-finger LEFT/RIGHT: Interactive sticky Alt+Tab app switcher (aligned with highlight animation)
 * - 3-finger TAP: Global Search (Meta+S)
 * - 4-finger TAP: Control Center (Meta+C), LEFT/RIGHT: Split Screen (Meta+Left/Right), DOWN: Back (Esc)
 */
export class HarmonyNativeActionMapper implements ITouchpadActionMapper {
  public readonly mode: MappingMode = MappingMode.HARMONY_NATIVE;
  public readonly displayName: string = 'v0.1鸿蒙原生';
  public readonly isThreeFingerDragEnabled: boolean = false;

  public mapMultiFingerTap(fingerCount: number): TouchpadAction | null {
    if (fingerCount === 3) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_S, '三指轻点 → 全局搜索 (鸿蒙键+S)');
    }
    if (fingerCount >= 4) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_C, '四指轻点 → 控制中心 (鸿蒙键+C)');
    }
    return null;
  }

  public mapMultiFingerSwipe(fingerCount: number, direction: SwipeDirection): TouchpadAction | null {
    if (fingerCount === 3) {
      if (direction === SwipeDirection.UP) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_D, '三指上滑 → 显示桌面 (鸿蒙键+D)');
      }
      if (direction === SwipeDirection.DOWN) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_D, '三指下滑 → 还原窗口 (鸿蒙键+D)');
      }
      if (direction === SwipeDirection.LEFT) {
        return makeAppSwitchStartAction(1, '三指左滑 → 切换应用 (Alt+Tab，不松手可左右选)');
      }
      if (direction === SwipeDirection.RIGHT) {
        return makeAppSwitchStartAction(1, '三指右滑 → 切换应用 (Alt+Tab，不松手可左右选)');
      }
    }

    if (fingerCount >= 4) {
      if (direction === SwipeDirection.UP) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_D, '四指上滑 → 显示桌面 (鸿蒙键+D)');
      }
      if (direction === SwipeDirection.DOWN) {
        return makeKeyAction(MOD_NONE, KEY_ESC, '四指下滑 → 返回上一级 (Esc)');
      }
      if (direction === SwipeDirection.LEFT) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_LEFT, '四指左滑 → 左分屏 (鸿蒙键+←)');
      }
      if (direction === SwipeDirection.RIGHT) {
        return makeKeyAction(MOD_LEFT_GUI, KEY_RIGHT, '四指右滑 → 右分屏 (鸿蒙键+→)');
      }
    }

    return null;
  }

  public mapMultiFingerSwipeUpHold(fingerCount: number): TouchpadAction | null {
    if (fingerCount === 3) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_TAB, '三指上滑停顿 → 任务中心 (鸿蒙键+Tab)');
    }
    if (fingerCount >= 4) {
      return makeKeyAction(MOD_LEFT_GUI, KEY_TAB, '四指上滑停顿 → 任务中心 (鸿蒙键+Tab)');
    }
    return null;
  }
}
