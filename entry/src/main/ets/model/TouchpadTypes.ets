export enum HidProfileMode {
  COMBO_TOUCHPAD = 'COMBO_TOUCHPAD',
  STANDARD_MOUSE = 'STANDARD_MOUSE'
}

export enum MappingMode {
  HARMONY_NATIVE = 'HARMONY_NATIVE',
  MAC_THREE_FINGER_DRAG = 'MAC_THREE_FINGER_DRAG'
}

export enum SwipeDirection {
  NONE = 'NONE',
  UP = 'UP',
  DOWN = 'DOWN',
  LEFT = 'LEFT',
  RIGHT = 'RIGHT'
}

export enum HidConnectionState {
  DISCONNECTED = 'DISCONNECTED',
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  DISCONNECTING = 'DISCONNECTING'
}

export enum RawTouchAction {
  DOWN = 'DOWN',
  MOVE = 'MOVE',
  UP = 'UP',
  CANCEL = 'CANCEL'
}

export enum HidReportKind {
  INPUT = 'INPUT',
  OUTPUT = 'OUTPUT',
  FEATURE = 'FEATURE'
}

export enum TouchpadActionType {
  POINTER_MOVE = 'POINTER_MOVE',
  MOUSE_CLICK = 'MOUSE_CLICK',
  MOUSE_BUTTON_STATE = 'MOUSE_BUTTON_STATE',
  SCROLL_2D = 'SCROLL_2D',
  PINCH_ZOOM = 'PINCH_ZOOM',
  KEY_COMBO = 'KEY_COMBO',
  APP_SWITCH_START = 'APP_SWITCH_START',
  APP_SWITCH_STEP = 'APP_SWITCH_STEP',
  APP_SWITCH_COMMIT = 'APP_SWITCH_COMMIT'
}

export interface RawPointerPoint {
  id: number;
  x: number;
  y: number;
}

export interface RawTouchSnapshot {
  action: RawTouchAction;
  touches: Array<RawPointerPoint>;
  changedTouches: Array<RawPointerPoint>;
  timestampMs: number;
}

export interface TouchpadAction {
  type: TouchpadActionType;
  dx: number;
  dy: number;
  vScroll: number;
  hScroll: number;
  buttonMask: number;
  modifiers: number;
  keycode: number;
  label: string;
}

export interface EngineTickResult {
  actions: Array<TouchpadAction>;
  visualDots: Array<VisualTouchDot>;
  gestureSummary: string;
  activeFingerCount: number;
  threeFingerDragging: boolean;
  threeFingerClutchPending: boolean;
  pendingDragReleaseMs: number;
  cancelPendingDragRelease: boolean;
  pendingThreeFingerHoldMs: number;
  cancelPendingThreeFingerHold: boolean;
  pendingSwipeUpHoldMs: number;
  cancelPendingSwipeUpHold: boolean;
  appSwitching: boolean;
}

export interface PairedHostDevice {
  address: string;
  name: string;
}

export interface LogEntry {
  id: number;
  time: string;
  level: string;
  message: string;
}

export interface VisualTouchDot {
  fingerId: number;
  slotId: number;
  x: number;
  y: number;
}

export interface EncodedHidPacket {
  reportId: number;
  payload: Uint8Array;
  delayMs: number;
}

export interface HidRegistrationConfig {
  name: string;
  description: string;
  provider: string;
  descriptors: Uint8Array;
  useComboSubclass: boolean;
}

export interface HidGetReportRequest {
  kind: HidReportKind;
  reportId: number;
  bufferSize: number;
}

export interface HidSetReportRequest {
  kind: HidReportKind;
  reportId: number;
  data: Uint8Array;
}
