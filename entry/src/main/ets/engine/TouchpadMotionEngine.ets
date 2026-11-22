import {
  EngineTickResult,
  RawPointerPoint,
  RawTouchAction,
  RawTouchSnapshot,
  SwipeDirection,
  TouchpadAction,
  TouchpadActionType,
  VisualTouchDot
} from '../model/TouchpadTypes';
import { ITouchpadActionMapper } from './ITouchpadActionMapper';

const MAX_VISUAL_SLOTS: number = 5;
const SINGLE_TAP_MAX_DURATION_MS: number = 180;
const SINGLE_TAP_MAX_MOVE_VP: number = 5.5;
const SINGLE_FINGER_MOVE_DEADZONE_VP: number = 2.0;
const MULTI_TAP_MAX_DURATION_MS: number = 280;
const MULTI_TAP_MAX_MOVE_VP: number = 16;
const MULTI_SWIPE_TRIGGER_VP: number = 32;
const SWIPE_UP_HOLD_MS: number = 220;
const APP_SWITCH_STEP_VP: number = 48;
const SCROLL_STEP_VP: number = 10;
const PINCH_STEP_VP: number = 24;
const MAC_DRAG_START_VP: number = 3;
const THREE_FINGER_HOLD_MS: number = 180;
const THREE_FINGER_DRAG_GAIN: number = 1.0; // 1:1 parity with single-finger cursor movement
const MAC_DRAG_CLUTCH_MS: number = 320;
const CLUTCH_REENGAGE_GRACE_MS: number = 95;
const CLUTCH_ABORT_MOVE_VP: number = 10;
const GLITCH_MAX_STEP_VP: number = 120;
const GLITCH_MAX_DT_MS: number = 25;

interface FingerState {
  id: number;
  slotId: number;
  startX: number;
  startY: number;
  x: number;
  y: number;
}

interface AcceleratedDelta {
  dx: number;
  dy: number;
}

/**
 * Pure domain multi-finger touchpad motion & gesture engine (zero ArkUI / zero Bluetooth / zero timer imports).
 * Features:
 *  - 1-finger: pure linear velocity scaling (zero double-acceleration with host OS) + sub-pixel remainder + crisp tap
 *  - 2-finger: per-finger displacement tap detection (immune to async finger lift centroid jump!) + 2D scroll + pinch
 *  - Mac 3-finger drag: 1:1 single-finger parity, mid-drag finger-jitter immunity (1~3 fingers), and 320ms clutch
 *  - 3/4+ finger swipe: interactive sticky Alt+Tab app switching (hold & scrub across 3+ apps, release to commit)
 */
export class TouchpadMotionEngine {
  private fingers: Map<number, FingerState> = new Map<number, FingerState>();
  private mapper: ITouchpadActionMapper;

  // User-tunable feel parameters
  private pointerSensitivity: number = 2.15;
  private naturalScroll: boolean = true;

  // Session state
  private sessionActive: boolean = false;
  private sessionStartMs: number = 0;
  private lastMoveTimestampMs: number = 0;
  private peakFingerCount: number = 0;
  private startCentroidX: number = 0;
  private startCentroidY: number = 0;
  private lastCentroidX: number = 0;
  private lastCentroidY: number = 0;
  private centroidAnchorFingerCount: number = 0;
  private maxFingerMoveVp: number = 0;
  private singleFingerDeadzoneCleared: boolean = false;
  private sessionEmittedScrollOrZoom: boolean = false;
  private multiSwipeLatched: boolean = false;

  // Interactive sticky Alt+Tab switcher & HarmonyOS PC swipe-up-and-hold state
  private appSwitching: boolean = false;
  private appSwitchAnchorX: number = 0;
  private swipeUpHoldPending: boolean = false;
  private swipeUpFingerCount: number = 0;

  // Sub-pixel / fractional accumulators for buttery-smooth pointer, scroll & pinch
  private pointerRemX: number = 0;
  private pointerRemY: number = 0;
  private scrollAccumX: number = 0;
  private scrollAccumY: number = 0;
  private lastPinchDist: number = 0;
  private pinchAccum: number = 0;

  // Mac 3-finger drag, static long-press & 320ms clutch state
  private threeFingerDragging: boolean = false;
  private threeFingerMoved: boolean = false;
  private threeFingerHoldPending: boolean = false;
  private threeFingerDragClutchPending: boolean = false;
  private clutchResuming: boolean = false;
  private clutchResumeStartMs: number = 0;

  private lastGestureSummary: string = '在触控区进行 1/2/3/4/5 指操作';

  constructor(mapper: ITouchpadActionMapper) {
    this.mapper = mapper;
  }

  public setMapper(mapper: ITouchpadActionMapper): void {
    this.mapper = mapper;
  }

  public setPointerSensitivity(gain: number): void {
    this.pointerSensitivity = gain;
  }

  public setNaturalScroll(natural: boolean): void {
    this.naturalScroll = natural;
  }

  public reset(): void {
    this.fingers.clear();
    this.sessionActive = false;
    this.peakFingerCount = 0;
    this.maxFingerMoveVp = 0;
    this.singleFingerDeadzoneCleared = false;
    this.sessionEmittedScrollOrZoom = false;
    this.multiSwipeLatched = false;
    this.appSwitching = false;
    this.appSwitchAnchorX = 0;
    this.swipeUpHoldPending = false;
    this.swipeUpFingerCount = 0;
    this.pointerRemX = 0;
    this.pointerRemY = 0;
    this.scrollAccumX = 0;
    this.scrollAccumY = 0;
    this.lastPinchDist = 0;
    this.pinchAccum = 0;
    this.threeFingerDragging = false;
    this.threeFingerMoved = false;
    this.threeFingerHoldPending = false;
    this.threeFingerDragClutchPending = false;
    this.clutchResuming = false;
    this.clutchResumeStartMs = 0;
    this.centroidAnchorFingerCount = 0;
  }

  /**
   * Called by TouchpadController when the 320ms macOS drag-lock clutch timer expires.
   * Pure state transition: emits Left Button Up (0x00) if still awaiting clutch resume.
   */
  public commitPendingDragRelease(): EngineTickResult {
    const actions: Array<TouchpadAction> = [];
    if (this.threeFingerDragClutchPending && !this.sessionActive) {
      this.releaseThreeFingerDrag(actions, 'Mac 三指拖移完成 (左键已释放)');
    }
    return this.buildTickResult(actions, 0, false, 0, false, 0, false);
  }

  /**
   * Called by TouchpadController when 3 fingers rest stationary for 180ms in Mac mode:
   * engages Left Mouse Button hold (0x01) even without moving, enabling static long-press & seamless drag.
   */
  public commitPendingThreeFingerHold(): EngineTickResult {
    const actions: Array<TouchpadAction> = [];
    if (
      this.threeFingerHoldPending &&
      this.sessionActive &&
      this.fingers.size === 3 &&
      this.peakFingerCount === 3 &&
      !this.threeFingerDragging &&
      !this.multiSwipeLatched &&
      this.mapper.isThreeFingerDragEnabled
    ) {
      this.threeFingerHoldPending = false;
      this.threeFingerDragging = true;
      this.threeFingerMoved = false;
      actions.push(this.makeButtonStateAction(0x01, 'Mac 三指原地长按 (左键按下)'));
      this.lastGestureSummary = 'Mac 三指长按中 (左键已按住，可原地长按或拖移)';
    }
    return this.buildTickResult(actions, 0, false, 0, false, 0, false);
  }

  /**
   * Called by TouchpadController when the 220ms HarmonyOS PC swipe-up-and-hold timer expires
   * while fingers are still resting on the pad -> triggers Multitask Task Center (Meta+Tab).
   */
  public commitPendingSwipeUpHold(): EngineTickResult {
    const actions: Array<TouchpadAction> = [];
    if (this.swipeUpHoldPending && this.sessionActive) {
      const fingers = this.swipeUpFingerCount;
      this.swipeUpHoldPending = false;
      this.swipeUpFingerCount = 0;
      const holdAction = this.mapper.mapMultiFingerSwipeUpHold(fingers);
      if (holdAction) {
        actions.push(holdAction);
        this.lastGestureSummary = holdAction.label;
      }
    }
    return this.buildTickResult(actions, 0, false, 0, false, 0, false);
  }

  public processSnapshot(snapshot: RawTouchSnapshot): EngineTickResult {
    const actions: Array<TouchpadAction> = [];
    const now = snapshot.timestampMs;
    let pendingDragReleaseMs = 0;
    let cancelPendingDragRelease = false;
    let pendingThreeFingerHoldMs = 0;
    let cancelPendingThreeFingerHold = false;
    let pendingSwipeUpHoldMs = 0;
    let cancelPendingSwipeUpHold = false;

    if (snapshot.action === RawTouchAction.DOWN) {
      for (let i = 0; i < snapshot.changedTouches.length; i++) {
        const pt = snapshot.changedTouches[i];
        if (!this.fingers.has(pt.id)) {
          const slot = this.allocateSlot();
          this.fingers.set(pt.id, {
            id: pt.id,
            slotId: slot,
            startX: pt.x,
            startY: pt.y,
            x: pt.x,
            y: pt.y
          });
        }
      }
      const activeCount = this.fingers.size;

      if (!this.sessionActive) {
        this.sessionActive = true;
        this.sessionStartMs = now;
        this.lastMoveTimestampMs = now;
        this.peakFingerCount = activeCount;
        this.maxFingerMoveVp = 0;
        this.singleFingerDeadzoneCleared = false;
        this.sessionEmittedScrollOrZoom = false;
        this.multiSwipeLatched = false;
        this.appSwitching = false;
        this.swipeUpHoldPending = false;
        this.swipeUpFingerCount = 0;
        this.threeFingerHoldPending = false;
        this.threeFingerMoved = false;
        this.pointerRemX = 0;
        this.pointerRemY = 0;
        this.scrollAccumX = 0;
        this.scrollAccumY = 0;
        this.pinchAccum = 0;
        this.lastPinchDist = 0;

        if (this.threeFingerDragClutchPending) {
          cancelPendingDragRelease = true;
          if (activeCount === 3 && this.mapper.isThreeFingerDragEnabled) {
            this.threeFingerDragClutchPending = false;
            this.clutchResuming = false;
            this.threeFingerDragging = true;
            this.lastGestureSummary = 'Mac 三指拖移续接中 (左键持续按住)';
          } else if (activeCount < 3 && this.mapper.isThreeFingerDragEnabled) {
            this.clutchResuming = true;
            this.clutchResumeStartMs = now;
            this.lastGestureSummary = '等待三指落齐续拖...';
          } else {
            this.releaseThreeFingerDrag(actions, 'Mac 三指拖移结束 (切换至多指手势)');
          }
        } else {
          this.lastGestureSummary = `${this.fingerLabel(activeCount)}按下`;
        }

        this.anchorCentroid(true);
        if (activeCount === 2) {
          this.lastPinchDist = this.measureTwoFingerDistance();
        }
        if (
          activeCount === 3 &&
          this.peakFingerCount === 3 &&
          !this.threeFingerDragging &&
          this.mapper.isThreeFingerDragEnabled
        ) {
          this.threeFingerHoldPending = true;
          pendingThreeFingerHoldMs = THREE_FINGER_HOLD_MS;
        }
      } else {
        if (activeCount > this.peakFingerCount) {
          this.peakFingerCount = activeCount;
        }

        if (activeCount >= 4 && this.threeFingerHoldPending) {
          this.threeFingerHoldPending = false;
          cancelPendingThreeFingerHold = true;
        }

        if (this.clutchResuming) {
          if (activeCount === 3 && this.mapper.isThreeFingerDragEnabled) {
            this.threeFingerDragClutchPending = false;
            this.clutchResuming = false;
            this.threeFingerDragging = true;
            this.threeFingerMoved = true;
            this.lastGestureSummary = 'Mac 三指拖移续接中 (左键持续按住)';
          } else if (activeCount >= 4) {
            this.releaseThreeFingerDrag(actions, 'Mac 三指拖移结束 (四指手势)');
          }
        } else if (this.threeFingerDragging && activeCount >= 4) {
          this.releaseThreeFingerDrag(actions, 'Mac 三指拖移结束 (四指手势)');
        }

        this.anchorCentroid(true);
        if (activeCount === 2) {
          this.lastPinchDist = this.measureTwoFingerDistance();
          this.pinchAccum = 0;
        }
        if (
          activeCount === 3 &&
          this.peakFingerCount === 3 &&
          !this.threeFingerDragging &&
          !this.threeFingerHoldPending &&
          !this.multiSwipeLatched &&
          this.mapper.isThreeFingerDragEnabled
        ) {
          this.threeFingerHoldPending = true;
          pendingThreeFingerHoldMs = THREE_FINGER_HOLD_MS;
        }
        if (!this.threeFingerDragging) {
          this.lastGestureSummary = `${this.fingerLabel(activeCount)}按下`;
        }
      }
    } else if (snapshot.action === RawTouchAction.MOVE && this.sessionActive) {
      for (let i = 0; i < snapshot.touches.length; i++) {
        const pt: RawPointerPoint = snapshot.touches[i];
        const existing = this.fingers.get(pt.id);
        if (existing) {
          existing.x = pt.x;
          existing.y = pt.y;
          const ownDx = existing.x - existing.startX;
          const ownDy = existing.y - existing.startY;
          const ownDist = Math.sqrt(ownDx * ownDx + ownDy * ownDy);
          if (ownDist > this.maxFingerMoveVp) {
            this.maxFingerMoveVp = ownDist;
          }
        } else {
          const slot = this.allocateSlot();
          this.fingers.set(pt.id, {
            id: pt.id,
            slotId: slot,
            startX: pt.x,
            startY: pt.y,
            x: pt.x,
            y: pt.y
          });
        }
      }

      const activeCount = this.fingers.size;
      if (activeCount > this.peakFingerCount) {
        this.peakFingerCount = activeCount;
      }

      if (activeCount > 0) {
        if (this.centroidAnchorFingerCount !== activeCount) {
          this.anchorCentroid(true);
          if (activeCount === 2) {
            this.lastPinchDist = this.measureTwoFingerDistance();
          }
        } else {
          const prevX = this.lastCentroidX;
          const prevY = this.lastCentroidY;
          this.updateCurrentCentroid();
          const stepDx = this.lastCentroidX - prevX;
          const stepDy = this.lastCentroidY - prevY;
          const moveDtMs = now - this.lastMoveTimestampMs;
          this.lastMoveTimestampMs = now;
          const stepDist = Math.sqrt(stepDx * stepDx + stepDy * stepDy);
          // Guard against impossible capacitive digitizer teleport glitches (>120vp in <25ms)
          if (moveDtMs >= 0 && moveDtMs < GLITCH_MAX_DT_MS && stepDist > GLITCH_MAX_STEP_VP) {
            this.anchorCentroid(false);
            return this.buildTickResult(
              actions,
              pendingDragReleaseMs,
              cancelPendingDragRelease,
              pendingThreeFingerHoldMs,
              cancelPendingThreeFingerHold,
              pendingSwipeUpHoldMs,
              cancelPendingSwipeUpHold
            );
          }
          const totalDx = this.lastCentroidX - this.startCentroidX;
          const totalDy = this.lastCentroidY - this.startCentroidY;
          const totalDist = Math.sqrt(totalDx * totalDx + totalDy * totalDy);

          if (this.clutchResuming) {
            if (activeCount === 3 && this.mapper.isThreeFingerDragEnabled) {
              this.threeFingerDragClutchPending = false;
              this.clutchResuming = false;
              this.threeFingerDragging = true;
              this.handleMacThreeFingerDragMove(stepDx, stepDy, totalDist, actions);
            } else if (
              this.maxFingerMoveVp >= CLUTCH_ABORT_MOVE_VP ||
              (now - this.clutchResumeStartMs) > CLUTCH_REENGAGE_GRACE_MS
            ) {
              this.releaseThreeFingerDrag(actions, 'Mac 三指拖移结束');
              this.anchorCentroid(true);
              if (activeCount === 1) {
                this.singleFingerDeadzoneCleared = true;
                this.handleSingleFingerMove(stepDx, stepDy, actions);
              } else if (activeCount === 2) {
                this.handleTwoFingerMove(stepDx, stepDy, actions);
              }
            }
          } else if (this.appSwitching) {
            this.handleInteractiveAppSwitchMove(actions);
          } else if (this.threeFingerDragging && activeCount >= 1 && activeCount <= 3) {
            // Jitter immunity: once 3-finger drag has started, brief drops to 2 or 1 finger keep dragging smoothly
            this.handleMacThreeFingerDragMove(stepDx, stepDy, totalDist, actions);
          } else if (activeCount === 1 && this.peakFingerCount === 1) {
            if (!this.singleFingerDeadzoneCleared) {
              if (this.maxFingerMoveVp >= SINGLE_FINGER_MOVE_DEADZONE_VP) {
                this.singleFingerDeadzoneCleared = true;
                this.handleSingleFingerMove(stepDx, stepDy, actions);
              }
            } else {
              this.handleSingleFingerMove(stepDx, stepDy, actions);
            }
          } else if (activeCount === 2 && this.peakFingerCount <= 2) {
            this.handleTwoFingerMove(stepDx, stepDy, actions);
          } else if (
            activeCount === 3 &&
            this.peakFingerCount <= 3 &&
            !this.multiSwipeLatched &&
            this.mapper.isThreeFingerDragEnabled
          ) {
            const wasDraggingBefore = this.threeFingerDragging;
            this.handleMacThreeFingerDragMove(stepDx, stepDy, totalDist, actions);
            if (!wasDraggingBefore && this.threeFingerDragging && this.threeFingerHoldPending) {
              this.threeFingerHoldPending = false;
              cancelPendingThreeFingerHold = true;
            }
          } else if (activeCount >= 3) {
            const holdDelay = this.handleMultiFingerSwipeMove(activeCount, totalDx, totalDy, totalDist, actions);
            if (holdDelay > 0) {
              pendingSwipeUpHoldMs = holdDelay;
            }
          }
        }
      }
    } else if ((snapshot.action === RawTouchAction.UP || snapshot.action === RawTouchAction.CANCEL) && this.sessionActive) {
      for (let i = 0; i < snapshot.changedTouches.length; i++) {
        this.fingers.delete(snapshot.changedTouches[i].id);
      }

      const remaining = this.fingers.size;
      if (this.threeFingerHoldPending && remaining !== 3) {
        this.threeFingerHoldPending = false;
        cancelPendingThreeFingerHold = true;
      }
      if (remaining > 0) {
        this.anchorCentroid(false);
      } else {
        const durationMs = now - this.sessionStartMs;
        const fingers = this.peakFingerCount;
        const maxFingerMove = this.maxFingerMoveVp;
        const emittedScrollOrZoom = this.sessionEmittedScrollOrZoom;
        const wasThreeFingerDrag = this.threeFingerDragging;
        const hadThreeFingerMoved = this.threeFingerMoved;
        const wasClutchResuming = this.clutchResuming;
        const wasAppSwitching = this.appSwitching;
        const wasSwipeUpHoldPending = this.swipeUpHoldPending;
        const pendingUpFingers = this.swipeUpFingerCount;
        const wasMultiLatched = this.multiSwipeLatched;

        this.sessionActive = false;
        this.multiSwipeLatched = false;
        this.appSwitching = false;
        this.swipeUpHoldPending = false;
        this.swipeUpFingerCount = 0;
        this.threeFingerHoldPending = false;
        this.threeFingerMoved = false;
        this.centroidAnchorFingerCount = 0;

        if (wasSwipeUpHoldPending) {
          cancelPendingSwipeUpHold = true;
          if (snapshot.action !== RawTouchAction.CANCEL) {
            const quickUpAction = this.mapper.mapMultiFingerSwipe(pendingUpFingers, SwipeDirection.UP);
            if (quickUpAction) {
              actions.push(quickUpAction);
              this.lastGestureSummary = quickUpAction.label;
            }
          }
        } else if (wasAppSwitching) {
          actions.push(this.makeAppSwitchCommitAction('松手确认切换应用'));
          this.lastGestureSummary = '已切换至目标应用';
        } else if (wasClutchResuming) {
          // Single-finger tap during 320ms clutch immediately drops dragged item (macOS behavior)
          this.releaseThreeFingerDrag(actions, '轻点立即放下 (Mac 三指拖移完成)');
        } else if (wasThreeFingerDrag) {
          if (snapshot.action === RawTouchAction.CANCEL) {
            this.releaseThreeFingerDrag(actions, 'Mac 三指拖移被打断 (左键释放)');
          } else if (!hadThreeFingerMoved) {
            // Pure static 3-finger long-press (no drag motion): release Left Button immediately on lift!
            this.releaseThreeFingerDrag(actions, 'Mac 三指原地长按结束 (左键已释放)');
          } else {
            this.threeFingerDragClutchPending = true;
            pendingDragReleaseMs = MAC_DRAG_CLUTCH_MS;
            this.lastGestureSummary = `Mac 三指拖移待续接 (${MAC_DRAG_CLUTCH_MS}ms内放回三指续拖)`;
          }
        } else if (snapshot.action === RawTouchAction.CANCEL) {
          this.lastGestureSummary = `${this.fingerLabel(fingers)}被系统手势打断 (Cancel)`;
        } else if (!wasMultiLatched && fingers === 1) {
          if (durationMs <= SINGLE_TAP_MAX_DURATION_MS && maxFingerMove <= SINGLE_TAP_MAX_MOVE_VP) {
            actions.push(this.makeClickAction(0x01, '单指轻点 → 鼠标左键'));
            this.lastGestureSummary = '单指轻点 → 鼠标左键';
          } else {
            this.lastGestureSummary = '单指移动完成';
          }
        } else if (!wasMultiLatched && fingers >= 2) {
          const isValidMultiTap =
            !emittedScrollOrZoom &&
            durationMs <= MULTI_TAP_MAX_DURATION_MS &&
            maxFingerMove <= MULTI_TAP_MAX_MOVE_VP;
          if (isValidMultiTap) {
            if (fingers === 2) {
              actions.push(this.makeClickAction(0x02, '双指轻点 → 鼠标右键'));
              this.lastGestureSummary = '双指轻点 → 鼠标右键';
            } else {
              const tapAction = this.mapper.mapMultiFingerTap(fingers);
              if (tapAction) {
                actions.push(tapAction);
                this.lastGestureSummary = tapAction.label;
              } else {
                this.lastGestureSummary = `${this.fingerLabel(fingers)}轻点 (已识别)`;
              }
            }
          } else {
            this.lastGestureSummary = `${this.fingerLabel(fingers)}操作完成`;
          }
        }
      }
    }

    return this.buildTickResult(
      actions,
      pendingDragReleaseMs,
      cancelPendingDragRelease,
      pendingThreeFingerHoldMs,
      cancelPendingThreeFingerHold,
      pendingSwipeUpHoldMs,
      cancelPendingSwipeUpHold
    );
  }

  private computeAcceleratedDelta(stepDx: number, stepDy: number, gainMultiplier: number): AcceleratedDelta {
    // Pure linear scaling: MatePad HarmonyOS host already applies its native OS mouse acceleration curve.
    // Removing app-side speed multipliers eliminates quadratic "double acceleration" on fast finger swipes.
    const scale = this.pointerSensitivity * gainMultiplier;
    const scaledX = stepDx * scale + this.pointerRemX;
    const scaledY = stepDy * scale + this.pointerRemY;
    const emitX = Math.trunc(scaledX);
    const emitY = Math.trunc(scaledY);
    this.pointerRemX = scaledX - emitX;
    this.pointerRemY = scaledY - emitY;
    return { dx: emitX, dy: emitY };
  }

  private handleSingleFingerMove(stepDx: number, stepDy: number, actions: Array<TouchpadAction>): void {
    const delta = this.computeAcceleratedDelta(stepDx, stepDy, 1.0);
    if (delta.dx !== 0 || delta.dy !== 0) {
      actions.push({
        type: TouchpadActionType.POINTER_MOVE,
        dx: delta.dx,
        dy: delta.dy,
        vScroll: 0,
        hScroll: 0,
        buttonMask: 0x00,
        modifiers: 0,
        keycode: 0,
        label: '单指移动'
      });
      this.lastGestureSummary = `单指移动 (${delta.dx >= 0 ? '+' : ''}${delta.dx}, ${delta.dy >= 0 ? '+' : ''}${delta.dy})`;
    }
  }

  private handleTwoFingerMove(stepDx: number, stepDy: number, actions: Array<TouchpadAction>): void {
    const curDist = this.measureTwoFingerDistance();
    if (this.lastPinchDist <= 0) {
      this.lastPinchDist = curDist;
    }
    const deltaPinch = curDist - this.lastPinchDist;
    this.lastPinchDist = curDist;

    const centroidStep = Math.sqrt(stepDx * stepDx + stepDy * stepDy);
    if (Math.abs(deltaPinch) > centroidStep * 1.4 && Math.abs(deltaPinch) > 1.2) {
      this.pinchAccum += deltaPinch;
      if (Math.abs(this.pinchAccum) >= PINCH_STEP_VP) {
        const zoomDir = this.pinchAccum > 0 ? 1 : -1;
        this.pinchAccum = 0;
        this.sessionEmittedScrollOrZoom = true;
        actions.push({
          type: TouchpadActionType.PINCH_ZOOM,
          dx: 0,
          dy: 0,
          vScroll: zoomDir,
          hScroll: 0,
          buttonMask: 0,
          modifiers: 0,
          keycode: 0,
          label: zoomDir > 0 ? '双指张开 → 放大 (Ctrl+滚轮↑)' : '双指捏合 → 缩小 (Ctrl+滚轮↓)'
        });
        this.lastGestureSummary = zoomDir > 0 ? '双指张开 → 放大' : '双指捏合 → 缩小';
      }
      return;
    }

    let effDx = stepDx;
    let effDy = stepDy;
    if (Math.abs(effDy) > Math.abs(effDx) * 2.2) {
      effDx = 0;
    } else if (Math.abs(effDx) > Math.abs(effDy) * 2.2) {
      effDy = 0;
    }

    this.scrollAccumX += effDx;
    this.scrollAccumY += effDy;

    let vSteps = 0;
    let hSteps = 0;

    if (Math.abs(this.scrollAccumY) >= SCROLL_STEP_VP) {
      const rawV = Math.trunc(this.scrollAccumY / SCROLL_STEP_VP);
      this.scrollAccumY -= rawV * SCROLL_STEP_VP;
      vSteps = this.naturalScroll ? rawV : -rawV;
    }

    if (Math.abs(this.scrollAccumX) >= SCROLL_STEP_VP) {
      const rawH = Math.trunc(this.scrollAccumX / SCROLL_STEP_VP);
      this.scrollAccumX -= rawH * SCROLL_STEP_VP;
      hSteps = this.naturalScroll ? -rawH : rawH;
    }

    if (vSteps !== 0 || hSteps !== 0) {
      this.sessionEmittedScrollOrZoom = true;
      actions.push({
        type: TouchpadActionType.SCROLL_2D,
        dx: 0,
        dy: 0,
        vScroll: vSteps,
        hScroll: hSteps,
        buttonMask: 0,
        modifiers: 0,
        keycode: 0,
        label: `双指滚动 (V:${vSteps} H:${hSteps})`
      });
      this.lastGestureSummary = vSteps !== 0
        ? (vSteps > 0 ? '双指滚动 ↑' : '双指滚动 ↓')
        : (hSteps > 0 ? '双指水平滚动 →' : '双指水平滚动 ←');
    }
  }

  private handleMacThreeFingerDragMove(
    stepDx: number,
    stepDy: number,
    totalDist: number,
    actions: Array<TouchpadAction>
  ): void {
    if (!this.threeFingerDragging && totalDist >= MAC_DRAG_START_VP) {
      this.threeFingerDragging = true;
      actions.push(this.makeButtonStateAction(0x01, 'Mac三指拖移开始 (左键按下)'));
    }

    if (this.threeFingerDragging) {
      const delta = this.computeAcceleratedDelta(stepDx, stepDy, THREE_FINGER_DRAG_GAIN);
      if (delta.dx !== 0 || delta.dy !== 0) {
        this.threeFingerMoved = true;
        actions.push({
          type: TouchpadActionType.POINTER_MOVE,
          dx: delta.dx,
          dy: delta.dy,
          vScroll: 0,
          hScroll: 0,
          buttonMask: 0x01,
          modifiers: 0,
          keycode: 0,
          label: 'Mac 三指拖移中'
        });
        this.lastGestureSummary = `Mac 三指拖移中 (左键按住 ${delta.dx >= 0 ? '+' : ''}${delta.dx}, ${delta.dy >= 0 ? '+' : ''}${delta.dy})`;
      }
    }
  }

  private handleMultiFingerSwipeMove(
    fingerCount: number,
    totalDx: number,
    totalDy: number,
    totalDist: number,
    actions: Array<TouchpadAction>
  ): number {
    if (this.multiSwipeLatched || totalDist < MULTI_SWIPE_TRIGGER_VP) {
      return 0;
    }
    this.multiSwipeLatched = true;
    const dir = this.resolveDirection(totalDx, totalDy);

    // HarmonyOS PC official UP logic: quick lift -> Show Desktop (Meta+D), hold >=220ms -> Task Center (Meta+Tab)
    if (dir === SwipeDirection.UP && this.mapper.mapMultiFingerSwipeUpHold(fingerCount) !== null) {
      this.swipeUpHoldPending = true;
      this.swipeUpFingerCount = fingerCount;
      this.lastGestureSummary = `${this.fingerLabel(fingerCount)}上滑：松手回桌面 / 停顿进任务中心`;
      return SWIPE_UP_HOLD_MS;
    }

    const mapped = this.mapper.mapMultiFingerSwipe(fingerCount, dir);
    if (mapped) {
      actions.push(mapped);
      this.lastGestureSummary = mapped.label;
      if (mapped.type === TouchpadActionType.APP_SWITCH_START) {
        this.appSwitching = true;
        this.appSwitchAnchorX = this.lastCentroidX;
      }
    } else {
      this.lastGestureSummary = `${this.fingerLabel(fingerCount)}滑动 ${dir}`;
    }
    return 0;
  }

  private handleInteractiveAppSwitchMove(actions: Array<TouchpadAction>): void {
    const deltaX = this.lastCentroidX - this.appSwitchAnchorX;
    // Match Alt+Tab highlight box animation direction: slide RIGHT -> Tab (box moves right), slide LEFT -> Shift+Tab (box moves left)
    if (deltaX >= APP_SWITCH_STEP_VP) {
      this.appSwitchAnchorX = this.lastCentroidX;
      actions.push({
        type: TouchpadActionType.APP_SWITCH_STEP,
        dx: 1,
        dy: 0,
        vScroll: 0,
        hScroll: 0,
        buttonMask: 0,
        modifiers: 0,
        keycode: 0,
        label: '继续右滑 → 选择右侧应用 (Tab)'
      });
      this.lastGestureSummary = '切应用选择中: → 右侧应用 (松手确认)';
    } else if (deltaX <= -APP_SWITCH_STEP_VP) {
      this.appSwitchAnchorX = this.lastCentroidX;
      actions.push({
        type: TouchpadActionType.APP_SWITCH_STEP,
        dx: -1,
        dy: 0,
        vScroll: 0,
        hScroll: 0,
        buttonMask: 0,
        modifiers: 0,
        keycode: 0,
        label: '继续左滑 → 选择左侧应用 (Shift+Tab)'
      });
      this.lastGestureSummary = '切应用选择中: ← 左侧应用 (松手确认)';
    }
  }

  private releaseThreeFingerDrag(actions: Array<TouchpadAction>, label: string): void {
    const wasHeld = this.threeFingerDragging || this.threeFingerDragClutchPending;
    this.threeFingerDragging = false;
    this.threeFingerMoved = false;
    this.threeFingerHoldPending = false;
    this.threeFingerDragClutchPending = false;
    this.clutchResuming = false;
    if (wasHeld) {
      actions.push(this.makeButtonStateAction(0x00, label));
      this.lastGestureSummary = label;
    }
  }

  private buildTickResult(
    actions: Array<TouchpadAction>,
    pendingDragReleaseMs: number,
    cancelPendingDragRelease: boolean,
    pendingThreeFingerHoldMs: number,
    cancelPendingThreeFingerHold: boolean,
    pendingSwipeUpHoldMs: number,
    cancelPendingSwipeUpHold: boolean
  ): EngineTickResult {
    return {
      actions: actions,
      visualDots: this.buildVisualDots(),
      gestureSummary: this.lastGestureSummary,
      activeFingerCount: this.fingers.size,
      threeFingerDragging: this.threeFingerDragging,
      threeFingerClutchPending: this.threeFingerDragClutchPending,
      pendingDragReleaseMs: pendingDragReleaseMs,
      cancelPendingDragRelease: cancelPendingDragRelease,
      pendingThreeFingerHoldMs: pendingThreeFingerHoldMs,
      cancelPendingThreeFingerHold: cancelPendingThreeFingerHold,
      pendingSwipeUpHoldMs: pendingSwipeUpHoldMs,
      cancelPendingSwipeUpHold: cancelPendingSwipeUpHold,
      appSwitching: this.appSwitching
    };
  }

  private anchorCentroid(resetStart: boolean): void {
    this.updateCurrentCentroid();
    this.centroidAnchorFingerCount = this.fingers.size;
    if (resetStart) {
      this.startCentroidX = this.lastCentroidX;
      this.startCentroidY = this.lastCentroidY;
    }
  }

  private updateCurrentCentroid(): void {
    const count = this.fingers.size;
    if (count === 0) {
      return;
    }
    let sx = 0;
    let sy = 0;
    this.fingers.forEach((f: FingerState) => {
      sx += f.x;
      sy += f.y;
    });
    this.lastCentroidX = sx / count;
    this.lastCentroidY = sy / count;
  }

  private measureTwoFingerDistance(): number {
    if (this.fingers.size < 2) {
      return 0;
    }
    const pts: Array<FingerState> = [];
    this.fingers.forEach((f: FingerState) => {
      pts.push(f);
    });
    const dx = pts[1].x - pts[0].x;
    const dy = pts[1].y - pts[0].y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private allocateSlot(): number {
    const used: Array<boolean> = [false, false, false, false, false];
    this.fingers.forEach((f: FingerState) => {
      if (f.slotId >= 0 && f.slotId < MAX_VISUAL_SLOTS) {
        used[f.slotId] = true;
      }
    });
    for (let s = 0; s < MAX_VISUAL_SLOTS; s++) {
      if (!used[s]) {
        return s;
      }
    }
    return 0;
  }

  private buildVisualDots(): Array<VisualTouchDot> {
    const dots: Array<VisualTouchDot> = [];
    this.fingers.forEach((f: FingerState) => {
      dots.push({
        fingerId: f.id,
        slotId: f.slotId,
        x: f.x,
        y: f.y
      });
    });
    return dots;
  }

  private resolveDirection(dx: number, dy: number): SwipeDirection {
    if (Math.abs(dx) >= Math.abs(dy)) {
      return dx >= 0 ? SwipeDirection.RIGHT : SwipeDirection.LEFT;
    }
    return dy >= 0 ? SwipeDirection.DOWN : SwipeDirection.UP;
  }

  private fingerLabel(count: number): string {
    if (count === 1) {
      return '单指';
    }
    if (count === 2) {
      return '双指';
    }
    if (count === 3) {
      return '三指';
    }
    if (count === 4) {
      return '四指';
    }
    return `${count}指`;
  }

  private makeClickAction(buttonMask: number, label: string): TouchpadAction {
    return {
      type: TouchpadActionType.MOUSE_CLICK,
      dx: 0,
      dy: 0,
      vScroll: 0,
      hScroll: 0,
      buttonMask: buttonMask,
      modifiers: 0,
      keycode: 0,
      label: label
    };
  }

  private makeButtonStateAction(buttonMask: number, label: string): TouchpadAction {
    return {
      type: TouchpadActionType.MOUSE_BUTTON_STATE,
      dx: 0,
      dy: 0,
      vScroll: 0,
      hScroll: 0,
      buttonMask: buttonMask,
      modifiers: 0,
      keycode: 0,
      label: label
    };
  }

  private makeAppSwitchCommitAction(label: string): TouchpadAction {
    return {
      type: TouchpadActionType.APP_SWITCH_COMMIT,
      dx: 0,
      dy: 0,
      vScroll: 0,
      hScroll: 0,
      buttonMask: 0,
      modifiers: 0,
      keycode: 0,
      label: label
    };
  }
}
