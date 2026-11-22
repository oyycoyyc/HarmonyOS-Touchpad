import { RawPointerPoint, RawTouchAction, RawTouchSnapshot } from '../model/TouchpadTypes';

/**
 * Isolates ArkUI TouchEvent from pure domain modules (TouchTracker & GestureRecognizer).
 */
export function fromArkUiTouchEvent(event: TouchEvent): RawTouchSnapshot {
  let action = RawTouchAction.MOVE;
  if (event.type === TouchType.Down) {
    action = RawTouchAction.DOWN;
  } else if (event.type === TouchType.Up) {
    action = RawTouchAction.UP;
  } else if (event.type === TouchType.Cancel) {
    action = RawTouchAction.CANCEL;
  }

  const touches: Array<RawPointerPoint> = [];
  for (let i = 0; i < event.touches.length; i++) {
    const t = event.touches[i];
    touches.push({ id: t.id, x: t.x, y: t.y });
  }

  const changedTouches: Array<RawPointerPoint> = [];
  for (let i = 0; i < event.changedTouches.length; i++) {
    const t = event.changedTouches[i];
    changedTouches.push({ id: t.id, x: t.x, y: t.y });
  }

  return {
    action: action,
    touches: touches,
    changedTouches: changedTouches,
    timestampMs: Date.now()
  };
}
