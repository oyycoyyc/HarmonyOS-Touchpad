import { HarmonyNativeActionMapper } from '../engine/HarmonyNativeActionMapper';
import { ITouchpadActionMapper } from '../engine/ITouchpadActionMapper';
import { MacRemapActionMapper } from '../engine/MacRemapActionMapper';
import { TouchpadMotionEngine } from '../engine/TouchpadMotionEngine';
import { REPORT_ID_KEYBOARD } from '../model/HidKeyCodes';
import {
  EncodedHidPacket,
  EngineTickResult,
  HidConnectionState,
  HidGetReportRequest,
  HidProfileMode,
  HidSetReportRequest,
  LogEntry,
  MappingMode,
  PairedHostDevice,
  RawTouchAction,
  RawTouchSnapshot,
  TouchpadAction,
  TouchpadActionType,
  TouchpadSavedSettings,
  VisualTouchDot
} from '../model/TouchpadTypes';
import { ComboProtocolSession } from '../protocol/ComboProtocolSession';
import { HidTransportListener, IHidTransport } from '../transport/IHidTransport';

interface SensitivityPreset {
  label: string;
  gain: number;
}

// Calibrated 4-tier linear sensitivity presets (centered between old 1.9 and 2.6)
const SENSITIVITY_PRESETS: Array<SensitivityPreset> = [
  { label: '低(1.6)', gain: 1.6 },
  { label: '中(2.15)', gain: 2.15 },
  { label: '快(2.35)', gain: 2.35 },
  { label: '高(2.6)', gain: 2.6 }
];

const KEYBOARD_QUEUE_GAP_MS: number = 22;
// Steady ~83Hz Classic BT HID mouse pacing prevents L2CAP packet clumping & OS dx/dt velocity spikes
const MOUSE_SEND_MIN_INTERVAL_MS: number = 12;
const INERTIA_TICK_MS: number = 12;
// Smooth per-report delta cap prevents any coalesced frame jump from triggering OS pointer acceleration cliffs
const MAX_MOUSE_DELTA_PER_REPORT: number = 36;
// Throttle UI re-renders during continuous MOVE to ~25Hz so ArkUI layout/GC never stalls touch sampling
const UI_MOVE_THROTTLE_MS: number = 40;

export interface TouchpadUiState {
  profileMode: HidProfileMode;
  mappingMode: MappingMode;
  naturalScroll: boolean;
  sensitivityIndex: number;
  sensitivityLabel: string;
  inertiaEnabled: boolean;
  inertiaStrength: number;
  inertiaActive: boolean;
  isRegistered: boolean;
  connState: HidConnectionState;
  connectedAddr: string;
  pairedDevices: Array<PairedHostDevice>;
  gestureText: string;
  fingerCountNow: number;
  threeFingerDragging: boolean;
  threeFingerClutchPending: boolean;
  appSwitching: boolean;
  txPacketCount: number;
  visualDots: Array<VisualTouchDot>;
  logs: Array<LogEntry>;
  clickPadDown: boolean;
}

export type TouchpadStateListener = (state: TouchpadUiState) => void;

/**
 * Application-layer coordinator (dependency-injected via IHidTransport).
 * Bridges TouchpadMotionEngine, pluggable ITouchpadActionMapper, ComboProtocolSession,
 * steady-paced Bluetooth mouse emission (eliminating BT L2CAP clumping & OS acceleration spikes),
 * FIFO keyboard packet sequencing, and 320ms drag-lock clutch timer.
 */
export class TouchpadController {
  private transport: IHidTransport;
  private engine: TouchpadMotionEngine;
  private protocol: ComboProtocolSession;
  private mappers: Map<MappingMode, ITouchpadActionMapper> = new Map<MappingMode, ITouchpadActionMapper>();
  private sensitivityIndex: number = 1;
  private stateListener: TouchpadStateListener | null = null;
  private logSeq: number = 0;

  // Timers live strictly in app/ layer so engine/ stays 100% pure
  private dragReleaseTimerId: number = -1;
  private threeFingerHoldTimerId: number = -1;
  private swipeUpHoldTimerId: number = -1;
  private inertiaTimerId: number = -1;
  private lastInertiaTickMs: number = 0;
  private keyQueueTailMs: number = 0;

  // Smooth Classic BT mouse report pacer
  private lastMouseSendMs: number = 0;
  private pendingMoveDx: number = 0;
  private pendingMoveDy: number = 0;
  private pendingMoveBtn: number = 0;
  private mouseFlushTimerId: number = -1;

  // UI render throttle during 120Hz MOVE
  private lastUiEmitMs: number = 0;

  private state: TouchpadUiState = {
    profileMode: HidProfileMode.COMBO_TOUCHPAD,
    mappingMode: MappingMode.MAC_THREE_FINGER_DRAG,
    naturalScroll: true,
    sensitivityIndex: 1,
    sensitivityLabel: SENSITIVITY_PRESETS[1].label,
    inertiaEnabled: false,
    inertiaStrength: 35,
    inertiaActive: false,
    isRegistered: false,
    connState: HidConnectionState.DISCONNECTED,
    connectedAddr: '',
    pairedDevices: [],
    gestureText: '在下方触控区进行 1/2/3/4/5 指操作',
    fingerCountNow: 0,
    threeFingerDragging: false,
    threeFingerClutchPending: false,
    appSwitching: false,
    txPacketCount: 0,
    visualDots: [],
    logs: [],
    clickPadDown: false
  };

  constructor(
    transport: IHidTransport,
    protocol: ComboProtocolSession = new ComboProtocolSession()
  ) {
    this.transport = transport;
    this.protocol = protocol;

    const harmonyMapper = new HarmonyNativeActionMapper();
    const macMapper = new MacRemapActionMapper();
    this.mappers.set(harmonyMapper.mode, harmonyMapper);
    this.mappers.set(macMapper.mode, macMapper);

    // Mac three-finger drag & long-press mode is default
    this.engine = new TouchpadMotionEngine(macMapper);
    this.engine.setPointerSensitivity(SENSITIVITY_PRESETS[this.sensitivityIndex].gain);
    this.engine.setNaturalScroll(this.state.naturalScroll);

    this.bindTransportListener(this.transport);
  }

  public setStateListener(listener: TouchpadStateListener): void {
    this.stateListener = listener;
    this.emitState(true);
  }

  public getState(): TouchpadUiState {
    return this.cloneState();
  }

  public addLog(level: string, message: string): void {
    this.appendLog(level, message);
  }

  public clearLogs(): void {
    this.state.logs = [];
    this.emitState(true);
  }

  public refreshPairedHosts(): void {
    this.state.pairedDevices = this.transport.getPairedHosts();
    this.emitState(true);
  }

  public registerProfile(mode: HidProfileMode): void {
    this.clearDragReleaseTimer();
    this.clearThreeFingerHoldTimer();
    this.clearSwipeUpHoldTimer();
    this.clearInertiaTimer();
    this.clearMousePacer();
    this.engine.reset();
    this.state.profileMode = mode;
    const config = this.protocol.buildRegistrationConfig(mode);
    this.state.threeFingerDragging = false;
    this.state.threeFingerClutchPending = false;
    this.state.appSwitching = false;
    this.state.inertiaActive = false;
    this.emitState(true);
    this.transport.register(config);
  }

  public unregisterProfile(): void {
    this.releaseAnyHeldInputs();
    this.transport.unregister();
  }

  public connectHost(address: string): void {
    this.transport.connect(address);
  }

  public disconnectHost(): void {
    this.releaseAnyHeldInputs();
    this.transport.disconnect();
  }

  public toggleMappingStrategy(): void {
    this.releaseAnyHeldInputs();
    const nextMode = this.state.mappingMode === MappingMode.HARMONY_NATIVE
      ? MappingMode.MAC_THREE_FINGER_DRAG
      : MappingMode.HARMONY_NATIVE;
    const nextMapper = this.mappers.get(nextMode);
    if (nextMapper) {
      this.engine.setMapper(nextMapper);
      this.state.mappingMode = nextMode;
      this.appendLog(
        'INFO',
        nextMode === MappingMode.HARMONY_NATIVE
          ? '切换为 v0.1 鸿蒙原生模式 (3指左右可连续选应用，4指分屏/控制中心)'
          : '切换为 v0.2 Mac 三指拖移模式 (与单指1:1齐平 + 320ms抬手续拖 + 4指接管3指手势)'
      );
      this.emitState(true);
    }
  }

  public toggleNaturalScroll(): void {
    this.state.naturalScroll = !this.state.naturalScroll;
    this.engine.setNaturalScroll(this.state.naturalScroll);
    this.appendLog('INFO', `双指滚动方向: ${this.state.naturalScroll ? '自然滚动(开)' : '传统滚动(关)'}`);
    this.emitState(true);
  }

  public cycleSensitivity(): void {
    this.sensitivityIndex = (this.sensitivityIndex + 1) % SENSITIVITY_PRESETS.length;
    const preset = SENSITIVITY_PRESETS[this.sensitivityIndex];
    this.state.sensitivityIndex = this.sensitivityIndex;
    this.state.sensitivityLabel = preset.label;
    this.engine.setPointerSensitivity(preset.gain);
    this.appendLog('INFO', `光标灵敏度已调整为: ${preset.label}`);
    this.emitState(true);
  }

  public applySavedSettings(settings: TouchpadSavedSettings): void {
    const mapper = this.mappers.get(settings.mappingMode);
    if (mapper) {
      this.engine.setMapper(mapper);
      this.state.mappingMode = settings.mappingMode;
    }

    this.state.naturalScroll = settings.naturalScroll;
    this.engine.setNaturalScroll(settings.naturalScroll);

    const sensIdx = this.clampInt(settings.sensitivityIndex, 0, SENSITIVITY_PRESETS.length - 1);
    this.sensitivityIndex = sensIdx;
    this.state.sensitivityIndex = sensIdx;
    const preset = SENSITIVITY_PRESETS[sensIdx];
    this.state.sensitivityLabel = preset.label;
    this.engine.setPointerSensitivity(preset.gain);

    const strength = this.clampInt(settings.inertiaStrength, 5, 100);
    this.state.inertiaStrength = strength;
    this.engine.setInertiaStrength(strength);

    this.state.inertiaEnabled = settings.inertiaEnabled;
    this.engine.setInertiaEnabled(settings.inertiaEnabled);
    if (!settings.inertiaEnabled) {
      this.clearInertiaTimer();
      this.state.inertiaActive = false;
    }

    this.emitState(true);
  }

  public toggleInertiaEnabled(): void {
    const next = !this.state.inertiaEnabled;
    this.state.inertiaEnabled = next;
    this.engine.setInertiaEnabled(next);
    if (!next) {
      this.clearInertiaTimer();
      this.state.inertiaActive = false;
    }
    this.appendLog('INFO', `轨迹球鼠标惯性: ${next ? `开启 (${this.state.inertiaStrength}%)` : '关闭'}`);
    this.emitState(true);
  }

  public setInertiaStrength(strengthPercent: number, logChange: boolean): void {
    const clamped = this.clampInt(strengthPercent, 5, 100);
    this.state.inertiaStrength = clamped;
    this.engine.setInertiaStrength(clamped);
    if (logChange) {
      this.appendLog('INFO', `轨迹球惯性强度已调整为: ${clamped}%`);
    }
    this.emitState(true);
  }

  private clampInt(value: number, min: number, max: number): number {
    const rounded = Math.round(value);
    if (rounded < min) {
      return min;
    }
    if (rounded > max) {
      return max;
    }
    return rounded;
  }

  public cancelActiveSession(): void {
    this.releaseAnyHeldInputs();
    this.emitState(true);
  }

  public handleTouchSnapshot(snapshot: RawTouchSnapshot): void {
    const tick = this.engine.processSnapshot(snapshot);
    const isContinuousMove = snapshot.action === RawTouchAction.MOVE;
    this.applyEngineTick(tick, !isContinuousMove);
  }

  public setClickPadPressed(pressed: boolean): void {
    this.clearInertiaTimer();
    this.engine.stopInertia();
    this.state.inertiaActive = false;
    this.flushPendingMouseMoveNow();
    this.state.clickPadDown = pressed;
    const action: TouchpadAction = {
      type: TouchpadActionType.MOUSE_BUTTON_STATE,
      dx: 0,
      dy: 0,
      vScroll: 0,
      hScroll: 0,
      buttonMask: pressed ? 0x01 : 0x00,
      modifiers: 0,
      keycode: 0,
      label: pressed ? '物理左键按下' : '物理左键释放'
    };
    if (this.state.connState === HidConnectionState.CONNECTED) {
      this.emitPackets(this.protocol.encodeAction(action));
    }
    this.emitState(true);
  }

  public sendMouseClick(buttonMask: number): void {
    if (this.state.connState !== HidConnectionState.CONNECTED) {
      this.appendLog('WARN', '未连接 MatePad，无法发送点击');
      return;
    }
    this.clearInertiaTimer();
    this.engine.stopInertia();
    this.state.inertiaActive = false;
    this.flushPendingMouseMoveNow();
    const action: TouchpadAction = {
      type: TouchpadActionType.MOUSE_CLICK,
      dx: 0,
      dy: 0,
      vScroll: 0,
      hScroll: 0,
      buttonMask: buttonMask,
      modifiers: 0,
      keycode: 0,
      label: buttonMask === 0x02 ? '鼠标右键点击' : '鼠标左键点击'
    };
    this.emitPackets(this.protocol.encodeAction(action));
    this.emitState(true);
  }

  public runQuickTest(testId: string): void {
    if (this.state.connState !== HidConnectionState.CONNECTED) {
      this.appendLog('WARN', '请先连接 MatePad Pro Max 再发送快捷测试');
      return;
    }
    const packets = this.protocol.buildQuickTestPackets(testId);
    if (packets.length === 0) {
      this.appendLog('WARN', `当前模式(${this.state.profileMode})不支持测试项: ${testId}`);
      return;
    }
    this.appendLog('INFO', `发送快捷测试 [${testId}] (${packets.length} 包)`);
    this.emitPackets(packets);
    this.emitState(true);
  }

  public destroy(): void {
    this.releaseAnyHeldInputs();
    this.transport.destroy();
    this.engine.reset();
  }

  private applyEngineTick(tick: EngineTickResult, forceUiEmit: boolean): void {
    if (tick.cancelPendingDragRelease) {
      this.clearDragReleaseTimer();
    }
    if (tick.cancelPendingThreeFingerHold) {
      this.clearThreeFingerHoldTimer();
    }
    if (tick.cancelPendingSwipeUpHold) {
      this.clearSwipeUpHoldTimer();
    }
    if (tick.stopInertia) {
      this.clearInertiaTimer();
      this.clearMousePacer();
    }

    const modeVisualChanged =
      this.state.threeFingerDragging !== tick.threeFingerDragging ||
      this.state.threeFingerClutchPending !== tick.threeFingerClutchPending ||
      this.state.appSwitching !== tick.appSwitching ||
      this.state.inertiaActive !== tick.inertiaActive ||
      this.state.fingerCountNow !== tick.activeFingerCount;

    this.state.visualDots = tick.visualDots;
    this.state.fingerCountNow = tick.activeFingerCount;
    this.state.gestureText = tick.gestureSummary;
    this.state.threeFingerDragging = tick.threeFingerDragging;
    this.state.threeFingerClutchPending = tick.threeFingerClutchPending;
    this.state.appSwitching = tick.appSwitching;
    this.state.inertiaActive = tick.inertiaActive;

    let hasDiscreteAction = false;
    for (let i = 0; i < tick.actions.length; i++) {
      const action = tick.actions[i];
      if (this.shouldLogAction(action)) {
        hasDiscreteAction = true;
        this.appendLog('GESTURE', action.label);
      }
      if (this.state.connState === HidConnectionState.CONNECTED) {
        if (action.type === TouchpadActionType.POINTER_MOVE) {
          this.enqueuePacedMouseMove(action.dx, action.dy, action.buttonMask);
        } else {
          // Ensure any queued cursor delta lands before clicks, scrolls, or button transitions
          this.flushPendingMouseMoveNow();
          const packets = this.protocol.encodeAction(action);
          this.emitPackets(packets);
        }
      }
    }

    if (tick.pendingDragReleaseMs > 0) {
      this.scheduleDragRelease(tick.pendingDragReleaseMs);
    }
    if (tick.pendingThreeFingerHoldMs > 0) {
      this.scheduleThreeFingerHold(tick.pendingThreeFingerHoldMs);
    }
    if (tick.pendingSwipeUpHoldMs > 0) {
      this.scheduleSwipeUpHold(tick.pendingSwipeUpHoldMs);
    }
    if (tick.startInertia && !this.state.clickPadDown) {
      this.flushPendingMouseMoveNow();
      this.startInertiaLoop();
    }

    this.emitState(forceUiEmit || modeVisualChanged || hasDiscreteAction || tick.pendingSwipeUpHoldMs > 0);
  }

  /**
   * Accumulates cursor deltas and transmits them on a steady >=12ms Classic BT HID cadence
   * with a smooth per-packet clamp (±36). Eliminates BT L2CAP packet clumping & OS dx/dt speed spikes!
   */
  private enqueuePacedMouseMove(dx: number, dy: number, buttonMask: number): void {
    this.pendingMoveDx += dx;
    this.pendingMoveDy += dy;
    this.pendingMoveBtn = buttonMask;

    const now = Date.now();
    const elapsed = now - this.lastMouseSendMs;
    if (elapsed >= MOUSE_SEND_MIN_INTERVAL_MS && this.mouseFlushTimerId === -1) {
      this.sendOnePacedMouseStep();
    } else if (this.mouseFlushTimerId === -1) {
      const waitMs = Math.max(1, MOUSE_SEND_MIN_INTERVAL_MS - elapsed);
      this.scheduleMouseFlush(waitMs);
    }
  }

  private sendOnePacedMouseStep(): void {
    if (this.state.connState !== HidConnectionState.CONNECTED) {
      this.clearMousePacer();
      return;
    }
    if (this.pendingMoveDx === 0 && this.pendingMoveDy === 0) {
      return;
    }

    const sendX = this.clampDeltaStep(this.pendingMoveDx);
    const sendY = this.clampDeltaStep(this.pendingMoveDy);
    this.pendingMoveDx -= sendX;
    this.pendingMoveDy -= sendY;

    const stepAction: TouchpadAction = {
      type: TouchpadActionType.POINTER_MOVE,
      dx: sendX,
      dy: sendY,
      vScroll: 0,
      hScroll: 0,
      buttonMask: this.pendingMoveBtn,
      modifiers: 0,
      keycode: 0,
      label: ''
    };
    const packets = this.protocol.encodeAction(stepAction);
    for (let i = 0; i < packets.length; i++) {
      if (this.transport.sendInputReport(packets[i].reportId, packets[i].payload)) {
        this.state.txPacketCount++;
      }
    }
    this.lastMouseSendMs = Date.now();

    if (this.pendingMoveDx !== 0 || this.pendingMoveDy !== 0) {
      this.scheduleMouseFlush(MOUSE_SEND_MIN_INTERVAL_MS);
    }
  }

  private flushPendingMouseMoveNow(): void {
    if (this.mouseFlushTimerId !== -1) {
      clearTimeout(this.mouseFlushTimerId);
      this.mouseFlushTimerId = -1;
    }
    if (this.pendingMoveDx !== 0 || this.pendingMoveDy !== 0) {
      this.sendOnePacedMouseStep();
    }
  }

  private scheduleMouseFlush(delayMs: number): void {
    if (this.mouseFlushTimerId !== -1) {
      clearTimeout(this.mouseFlushTimerId);
    }
    this.mouseFlushTimerId = setTimeout(() => {
      this.mouseFlushTimerId = -1;
      this.sendOnePacedMouseStep();
    }, delayMs);
  }

  private clearMousePacer(): void {
    if (this.mouseFlushTimerId !== -1) {
      clearTimeout(this.mouseFlushTimerId);
      this.mouseFlushTimerId = -1;
    }
    this.pendingMoveDx = 0;
    this.pendingMoveDy = 0;
    this.pendingMoveBtn = 0;
  }

  private clampDeltaStep(value: number): number {
    if (value > MAX_MOUSE_DELTA_PER_REPORT) {
      return MAX_MOUSE_DELTA_PER_REPORT;
    }
    if (value < -MAX_MOUSE_DELTA_PER_REPORT) {
      return -MAX_MOUSE_DELTA_PER_REPORT;
    }
    return value;
  }

  private scheduleDragRelease(delayMs: number): void {
    this.clearDragReleaseTimer();
    this.dragReleaseTimerId = setTimeout(() => {
      this.dragReleaseTimerId = -1;
      const tick = this.engine.commitPendingDragRelease();
      this.applyEngineTick(tick, true);
    }, delayMs);
  }

  private clearDragReleaseTimer(): void {
    if (this.dragReleaseTimerId !== -1) {
      clearTimeout(this.dragReleaseTimerId);
      this.dragReleaseTimerId = -1;
    }
  }

  private scheduleThreeFingerHold(delayMs: number): void {
    this.clearThreeFingerHoldTimer();
    this.threeFingerHoldTimerId = setTimeout(() => {
      this.threeFingerHoldTimerId = -1;
      const tick = this.engine.commitPendingThreeFingerHold();
      this.applyEngineTick(tick, true);
    }, delayMs);
  }

  private clearThreeFingerHoldTimer(): void {
    if (this.threeFingerHoldTimerId !== -1) {
      clearTimeout(this.threeFingerHoldTimerId);
      this.threeFingerHoldTimerId = -1;
    }
  }

  private scheduleSwipeUpHold(delayMs: number): void {
    this.clearSwipeUpHoldTimer();
    this.swipeUpHoldTimerId = setTimeout(() => {
      this.swipeUpHoldTimerId = -1;
      const tick = this.engine.commitPendingSwipeUpHold();
      this.applyEngineTick(tick, true);
    }, delayMs);
  }

  private clearSwipeUpHoldTimer(): void {
    if (this.swipeUpHoldTimerId !== -1) {
      clearTimeout(this.swipeUpHoldTimerId);
      this.swipeUpHoldTimerId = -1;
    }
  }

  private startInertiaLoop(): void {
    this.clearInertiaTimer();
    if (!this.state.inertiaEnabled || !this.engine.isInertiaActive()) {
      this.state.inertiaActive = false;
      return;
    }
    this.lastInertiaTickMs = Date.now();
    this.scheduleNextInertiaTick();
  }

  private scheduleNextInertiaTick(): void {
    this.clearInertiaTimer();
    this.inertiaTimerId = setTimeout(() => {
      this.inertiaTimerId = -1;
      this.onInertiaTick();
    }, INERTIA_TICK_MS);
  }

  private onInertiaTick(): void {
    if (!this.state.inertiaEnabled || this.state.clickPadDown) {
      this.engine.stopInertia();
      this.state.inertiaActive = false;
      this.emitState(true);
      return;
    }
    const now = Date.now();
    const dtMs = Math.max(8, Math.min(30, now - this.lastInertiaTickMs));
    this.lastInertiaTickMs = now;

    const tick = this.engine.stepInertia(dtMs);
    if (this.state.connState === HidConnectionState.CONNECTED) {
      for (let i = 0; i < tick.actions.length; i++) {
        const action = tick.actions[i];
        if (action.type === TouchpadActionType.POINTER_MOVE) {
          const packets = this.protocol.encodeAction(action);
          for (let j = 0; j < packets.length; j++) {
            if (this.transport.sendInputReport(packets[j].reportId, packets[j].payload)) {
              this.state.txPacketCount++;
            }
          }
          this.lastMouseSendMs = Date.now();
        }
      }
    }

    this.state.inertiaActive = tick.inertiaActive;
    this.state.gestureText = tick.gestureSummary;
    if (tick.inertiaActive) {
      this.scheduleNextInertiaTick();
      this.emitState(false);
    } else {
      this.emitState(true);
    }
  }

  private clearInertiaTimer(): void {
    if (this.inertiaTimerId !== -1) {
      clearTimeout(this.inertiaTimerId);
      this.inertiaTimerId = -1;
    }
  }

  private releaseAnyHeldInputs(): void {
    this.clearDragReleaseTimer();
    this.clearThreeFingerHoldTimer();
    this.clearSwipeUpHoldTimer();
    this.clearInertiaTimer();
    this.clearMousePacer();
    this.engine.reset();
    if (this.state.connState === HidConnectionState.CONNECTED) {
      const releasePackets = this.protocol.buildEmergencyReleasePackets();
      if (releasePackets.length > 0) {
        this.emitPackets(releasePackets);
      }
    } else {
      this.protocol.resetHeldState();
    }
    this.state.threeFingerDragging = false;
    this.state.threeFingerClutchPending = false;
    this.state.appSwitching = false;
    this.state.inertiaActive = false;
    this.state.clickPadDown = false;
    this.state.visualDots = [];
    this.state.fingerCountNow = 0;
  }

  /**
   * Strictly FIFO-sequences Keyboard reports so fast flicks (APP_SWITCH_START followed quickly
   * by APP_SWITCH_COMMIT) can never interleave out-of-order or leave Alt stuck.
   */
  private emitPackets(packets: Array<EncodedHidPacket>): void {
    let hasKeyboard = false;
    for (let i = 0; i < packets.length; i++) {
      if (packets[i].reportId === REPORT_ID_KEYBOARD) {
        hasKeyboard = true;
        break;
      }
    }

    let baseOffsetMs = 0;
    let maxDelayMs = 0;
    const now = Date.now();
    if (hasKeyboard && this.keyQueueTailMs > now) {
      baseOffsetMs = (this.keyQueueTailMs - now) + KEYBOARD_QUEUE_GAP_MS;
    }

    for (let i = 0; i < packets.length; i++) {
      const pkt = packets[i];
      const effectiveDelay = hasKeyboard ? (baseOffsetMs + pkt.delayMs) : pkt.delayMs;
      if (effectiveDelay > maxDelayMs) {
        maxDelayMs = effectiveDelay;
      }

      if (effectiveDelay <= 0) {
        if (this.transport.sendInputReport(pkt.reportId, pkt.payload)) {
          this.state.txPacketCount++;
        }
      } else {
        setTimeout(() => {
          if (this.state.connState === HidConnectionState.CONNECTED) {
            if (this.transport.sendInputReport(pkt.reportId, pkt.payload)) {
              this.state.txPacketCount++;
              this.emitState(false);
            }
          }
        }, effectiveDelay);
      }
    }

    if (hasKeyboard) {
      this.keyQueueTailMs = now + maxDelayMs;
    }
  }

  private shouldLogAction(action: TouchpadAction): boolean {
    return action.type === TouchpadActionType.KEY_COMBO ||
      action.type === TouchpadActionType.MOUSE_CLICK ||
      action.type === TouchpadActionType.PINCH_ZOOM ||
      action.type === TouchpadActionType.MOUSE_BUTTON_STATE ||
      action.type === TouchpadActionType.APP_SWITCH_START ||
      action.type === TouchpadActionType.APP_SWITCH_STEP ||
      action.type === TouchpadActionType.APP_SWITCH_COMMIT;
  }

  private bindTransportListener(target: IHidTransport): void {
    const listener: HidTransportListener = {
      onLog: (level: string, message: string) => {
        this.appendLog(level, message);
      },
      onRegistrationChanged: (registered: boolean) => {
        this.state.isRegistered = registered;
        this.emitState(true);
      },
      onConnectionChanged: (connState: HidConnectionState, deviceId: string) => {
        this.state.connState = connState;
        this.state.connectedAddr = connState === HidConnectionState.CONNECTED ? deviceId : '';
        if (connState === HidConnectionState.DISCONNECTED) {
          this.clearDragReleaseTimer();
          this.clearThreeFingerHoldTimer();
          this.clearSwipeUpHoldTimer();
          this.clearInertiaTimer();
          this.clearMousePacer();
          this.engine.reset();
          this.protocol.resetHeldState();
          this.keyQueueTailMs = 0;
          this.state.threeFingerDragging = false;
          this.state.threeFingerClutchPending = false;
          this.state.appSwitching = false;
          this.state.inertiaActive = false;
          this.state.clickPadDown = false;
          this.state.visualDots = [];
          this.state.fingerCountNow = 0;
        }
        this.emitState(true);
      },
      onGetReport: (req: HidGetReportRequest) => {
        this.handleHostGetReport(req);
      },
      onSetReport: (req: HidSetReportRequest) => {
        this.handleHostSetReport(req);
      }
    };
    target.setListener(listener);
  }

  private handleHostGetReport(req: HidGetReportRequest): void {
    this.appendLog(
      'HANDSHAKE',
      `收到主机 GET_REPORT: kind=${req.kind}, id=0x${req.reportId.toString(16)}, bufSize=${req.bufferSize}`
    );
    const reply = this.protocol.handleGetReport(req);
    if (reply.handled && reply.payload) {
      this.transport.replyReport(req.kind, req.reportId, reply.payload);
      this.appendLog(reply.logLevel, reply.logMessage);
    } else {
      this.transport.reportInvalidReportId();
      this.appendLog(reply.logLevel, `${reply.logMessage} -> 回复 RSP_INVALID_REPORT_ID`);
    }
  }

  private handleHostSetReport(req: HidSetReportRequest): void {
    const res = this.protocol.handleSetReport(req);
    this.appendLog(res.logLevel, res.logMessage);
  }

  private appendLog(level: string, message: string): void {
    const now = new Date();
    const hh = now.getHours().toString().padStart(2, '0');
    const mm = now.getMinutes().toString().padStart(2, '0');
    const ss = now.getSeconds().toString().padStart(2, '0');
    const entry: LogEntry = {
      id: ++this.logSeq,
      time: `${hh}:${mm}:${ss}`,
      level: level,
      message: message
    };
    const nextLogs: Array<LogEntry> = [entry];
    const keepLimit = Math.min(this.state.logs.length, 39);
    for (let i = 0; i < keepLimit; i++) {
      nextLogs.push(this.state.logs[i]);
    }
    this.state.logs = nextLogs;
    this.emitState(true);
  }

  private emitState(force: boolean): void {
    if (!this.stateListener) {
      return;
    }
    const now = Date.now();
    if (!force && now - this.lastUiEmitMs < UI_MOVE_THROTTLE_MS) {
      return;
    }
    this.lastUiEmitMs = now;
    this.stateListener(this.cloneState());
  }

  private cloneState(): TouchpadUiState {
    return {
      profileMode: this.state.profileMode,
      mappingMode: this.state.mappingMode,
      naturalScroll: this.state.naturalScroll,
      sensitivityIndex: this.state.sensitivityIndex,
      sensitivityLabel: this.state.sensitivityLabel,
      inertiaEnabled: this.state.inertiaEnabled,
      inertiaStrength: this.state.inertiaStrength,
      inertiaActive: this.state.inertiaActive,
      isRegistered: this.state.isRegistered,
      connState: this.state.connState,
      connectedAddr: this.state.connectedAddr,
      pairedDevices: this.state.pairedDevices,
      gestureText: this.state.gestureText,
      fingerCountNow: this.state.fingerCountNow,
      threeFingerDragging: this.state.threeFingerDragging,
      threeFingerClutchPending: this.state.threeFingerClutchPending,
      appSwitching: this.state.appSwitching,
      txPacketCount: this.state.txPacketCount,
      visualDots: this.state.visualDots,
      logs: this.state.logs,
      clickPadDown: this.state.clickPadDown
    };
  }
}
