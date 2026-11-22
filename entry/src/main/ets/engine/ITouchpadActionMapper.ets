import { MappingMode, SwipeDirection, TouchpadAction } from '../model/TouchpadTypes';

/**
 * Pluggable strategy mapping 3-finger / 4-finger+ gestures into TouchpadActions.
 * Decouples gesture recognition (TouchpadMotionEngine) from OS shortcut / Mac drag policies.
 */
export interface ITouchpadActionMapper {
  readonly mode: MappingMode;
  readonly displayName: string;
  readonly isThreeFingerDragEnabled: boolean;

  mapMultiFingerTap(fingerCount: number): TouchpadAction | null;
  mapMultiFingerSwipe(fingerCount: number, direction: SwipeDirection): TouchpadAction | null;
  mapMultiFingerSwipeUpHold(fingerCount: number): TouchpadAction | null;
}
