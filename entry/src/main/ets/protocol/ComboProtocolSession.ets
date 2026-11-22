import {
  KEY_D,
  KEY_LEFT,
  KEY_NONE,
  KEY_SLASH,
  KEY_TAB,
  MOD_LEFT_ALT,
  MOD_LEFT_CTRL,
  MOD_LEFT_GUI,
  MOD_LEFT_SHIFT,
  MOD_NONE,
  REPORT_ID_KEYBOARD,
  REPORT_ID_MOUSE
} from '../model/HidKeyCodes';
import {
  EncodedHidPacket,
  HidGetReportRequest,
  HidProfileMode,
  HidRegistrationConfig,
  HidReportKind,
  HidSetReportRequest,
  TouchpadAction,
  TouchpadActionType
} from '../model/TouchpadTypes';
import {
  encodeComboMouseReport,
  encodeKeyboardReport,
  encodeStandardMouseReport,
  formatBytesHex
} from './ComboReportEncoder';
import {
  buildComboTouchpadDescriptor,
  buildStandardMouseDescriptor
} from './HidDescriptors';

const KEY_STEP_MS: number = 22;
const KEY_HOLD_MS: number = 44;

export interface GetReportReplyResult {
  handled: boolean;
  payload: Uint8Array | null;
  logLevel: string;
  logMessage: string;
}

export interface SetReportProcessResult {
  logLevel: string;
  logMessage: string;
}

/**
 * Pure HID Combo protocol encoder & handshake handler (zero Bluetooth API dependencies).
 * Translates high-level TouchpadActions into Mouse (0x01) & Keyboard (0x02) HID packets
 * with Bluetooth-safe staggered multi-modifier timing and sticky Alt+Tab switching.
 */
export class ComboProtocolSession {
  private profileMode: HidProfileMode = HidProfileMode.COMBO_TOUCHPAD;
  private heldButtons: number = 0x00;
  private altHeldForSwitch: boolean = false;

  public getProfileMode(): HidProfileMode {
    return this.profileMode;
  }

  public resetHeldState(): void {
    this.heldButtons = 0x00;
    this.altHeldForSwitch = false;
  }

  public buildEmergencyReleasePackets(): Array<EncodedHidPacket> {
    const packets: Array<EncodedHidPacket> = [];
    const isCombo = this.profileMode === HidProfileMode.COMBO_TOUCHPAD;
    if (this.heldButtons !== 0x00) {
      this.heldButtons = 0x00;
      packets.push({
        reportId: REPORT_ID_MOUSE,
        payload: isCombo
          ? encodeComboMouseReport(0x00, 0, 0, 0, 0)
          : encodeStandardMouseReport(0x00, 0, 0, 0),
        delayMs: 0
      });
    }
    if (this.altHeldForSwitch && isCombo) {
      this.altHeldForSwitch = false;
      packets.push({
        reportId: REPORT_ID_KEYBOARD,
        payload: encodeKeyboardReport(MOD_NONE, KEY_NONE),
        delayMs: 0
      });
    }
    return packets;
  }

  public buildRegistrationConfig(mode: HidProfileMode): HidRegistrationConfig {
    this.profileMode = mode;
    this.resetHeldState();
    const isCombo = mode === HidProfileMode.COMBO_TOUCHPAD;
    return {
      name: isCombo ? 'Harmony Touchpad Combo' : 'Harmony BT Mouse',
      description: isCombo
        ? 'Touchpad Combo (Mouse+Scroll+Keys)'
        : 'Standard 3-Button BT Mouse',
      provider: 'HarmonyTouchpad',
      descriptors: isCombo ? buildComboTouchpadDescriptor() : buildStandardMouseDescriptor(),
      useComboSubclass: isCombo
    };
  }

  public encodeAction(action: TouchpadAction): Array<EncodedHidPacket> {
    const isCombo = this.profileMode === HidProfileMode.COMBO_TOUCHPAD;

    if (action.type === TouchpadActionType.POINTER_MOVE) {
      const btn = action.buttonMask | this.heldButtons;
      return [{
        reportId: REPORT_ID_MOUSE,
        payload: isCombo
          ? encodeComboMouseReport(btn, action.dx, action.dy, 0, 0)
          : encodeStandardMouseReport(btn, action.dx, action.dy, 0),
        delayMs: 0
      }];
    }

    if (action.type === TouchpadActionType.MOUSE_BUTTON_STATE) {
      this.heldButtons = action.buttonMask & 0x07;
      return [{
        reportId: REPORT_ID_MOUSE,
        payload: isCombo
          ? encodeComboMouseReport(this.heldButtons, 0, 0, 0, 0)
          : encodeStandardMouseReport(this.heldButtons, 0, 0, 0),
        delayMs: 0
      }];
    }

    if (action.type === TouchpadActionType.MOUSE_CLICK) {
      const pressed = (action.buttonMask | this.heldButtons) & 0x07;
      return [
        {
          reportId: REPORT_ID_MOUSE,
          payload: isCombo
            ? encodeComboMouseReport(pressed, 0, 0, 0, 0)
            : encodeStandardMouseReport(pressed, 0, 0, 0),
          delayMs: 0
        },
        {
          reportId: REPORT_ID_MOUSE,
          payload: isCombo
            ? encodeComboMouseReport(this.heldButtons, 0, 0, 0, 0)
            : encodeStandardMouseReport(this.heldButtons, 0, 0, 0),
          delayMs: 28
        }
      ];
    }

    if (action.type === TouchpadActionType.SCROLL_2D) {
      return [{
        reportId: REPORT_ID_MOUSE,
        payload: isCombo
          ? encodeComboMouseReport(this.heldButtons, 0, 0, action.vScroll, action.hScroll)
          : encodeStandardMouseReport(this.heldButtons, 0, 0, action.vScroll),
        delayMs: 0
      }];
    }

    if (action.type === TouchpadActionType.PINCH_ZOOM) {
      if (!isCombo) {
        return [];
      }
      return [
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_CTRL, KEY_NONE), delayMs: 0 },
        { reportId: REPORT_ID_MOUSE, payload: encodeComboMouseReport(this.heldButtons, 0, 0, action.vScroll, 0), delayMs: 18 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_NONE, KEY_NONE), delayMs: 40 }
      ];
    }

    if (action.type === TouchpadActionType.KEY_COMBO) {
      if (!isCombo) {
        return [];
      }
      return this.buildKeyComboPackets(action.modifiers, action.keycode);
    }

    if (action.type === TouchpadActionType.APP_SWITCH_START) {
      if (!isCombo) {
        return [];
      }
      // dx >= 0 -> forward Alt+Tab (highlight moves right); dx < 0 -> reverse Alt+Shift+Tab (highlight moves left)
      return this.buildAppSwitchStartPackets(action.dx < 0);
    }

    if (action.type === TouchpadActionType.APP_SWITCH_STEP) {
      if (!isCombo) {
        return [];
      }
      return this.buildAppSwitchStepPackets(action.dx < 0);
    }

    if (action.type === TouchpadActionType.APP_SWITCH_COMMIT) {
      if (!isCombo) {
        return [];
      }
      this.altHeldForSwitch = false;
      return [
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_NONE, KEY_NONE), delayMs: 0 }
      ];
    }

    return [];
  }

  /**
   * Builds a Bluetooth-safe staggered keyboard sequence:
   * Modifiers pressed one by one (22ms) -> primary key pressed -> primary key released FIRST (44ms) ->
   * modifiers released in reverse order (22ms each).
   */
  public buildKeyComboPackets(modifiers: number, keycode: number): Array<EncodedHidPacket> {
    if (this.profileMode !== HidProfileMode.COMBO_TOUCHPAD) {
      return [];
    }
    const orderedMods = this.decomposeModifiers(modifiers);
    const packets: Array<EncodedHidPacket> = [];
    let t = 0;

    if (orderedMods.length === 0) {
      packets.push({ reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_NONE, keycode), delayMs: 0 });
      packets.push({ reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_NONE, KEY_NONE), delayMs: KEY_HOLD_MS });
      return packets;
    }

    let currentMask = MOD_NONE;
    for (let i = 0; i < orderedMods.length; i++) {
      currentMask = currentMask | orderedMods[i];
      packets.push({
        reportId: REPORT_ID_KEYBOARD,
        payload: encodeKeyboardReport(currentMask, KEY_NONE),
        delayMs: t
      });
      t += KEY_STEP_MS;
    }

    // Press primary key
    packets.push({
      reportId: REPORT_ID_KEYBOARD,
      payload: encodeKeyboardReport(currentMask, keycode),
      delayMs: t
    });
    t += KEY_HOLD_MS;

    // Release primary key BEFORE releasing modifiers
    packets.push({
      reportId: REPORT_ID_KEYBOARD,
      payload: encodeKeyboardReport(currentMask, KEY_NONE),
      delayMs: t
    });
    t += KEY_STEP_MS;

    // Release modifiers in reverse order
    for (let i = orderedMods.length - 1; i >= 0; i--) {
      currentMask = currentMask & (~orderedMods[i]);
      packets.push({
        reportId: REPORT_ID_KEYBOARD,
        payload: encodeKeyboardReport(currentMask, KEY_NONE),
        delayMs: t
      });
      t += KEY_STEP_MS;
    }

    return packets;
  }

  public buildQuickTestPackets(testId: string): Array<EncodedHidPacket> {
    const isCombo = this.profileMode === HidProfileMode.COMBO_TOUCHPAD;
    if (testId === 'cursor_right') {
      const packets: Array<EncodedHidPacket> = [];
      for (let i = 0; i < 12; i++) {
        packets.push({
          reportId: REPORT_ID_MOUSE,
          payload: isCombo
            ? encodeComboMouseReport(0, 14, 0, 0, 0)
            : encodeStandardMouseReport(0, 14, 0, 0),
          delayMs: i * 12
        });
      }
      return packets;
    }
    if (testId === 'scroll_down') {
      const packets: Array<EncodedHidPacket> = [];
      for (let i = 0; i < 6; i++) {
        packets.push({
          reportId: REPORT_ID_MOUSE,
          payload: isCombo
            ? encodeComboMouseReport(0, 0, 0, -1, 0)
            : encodeStandardMouseReport(0, 0, 0, -1),
          delayMs: i * 35
        });
      }
      return packets;
    }
    if (testId === 'multitask') {
      return this.buildKeyComboPackets(MOD_LEFT_GUI, KEY_TAB);
    }
    if (testId === 'desktop') {
      return this.buildKeyComboPackets(MOD_LEFT_GUI, KEY_D);
    }
    if (testId === 'shortcut_help') {
      return this.buildKeyComboPackets(MOD_LEFT_GUI, KEY_SLASH);
    }
    if (testId === 'reverse_switch_a') {
      // Staggered Alt↓ -> Shift↓ -> Tab↓ -> Tab↑ -> Shift↑ -> Alt↑
      return this.buildKeyComboPackets(MOD_LEFT_ALT | MOD_LEFT_SHIFT, KEY_TAB);
    }
    if (testId === 'reverse_switch_b') {
      if (!isCombo) {
        return [];
      }
      // Open switcher with Alt+Tab, step back twice with Left Arrow while holding Alt, then release Alt
      return [
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 0 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_TAB), delayMs: 24 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 70 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_LEFT), delayMs: 130 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 170 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_LEFT), delayMs: 220 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 260 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_NONE, KEY_NONE), delayMs: 300 }
      ];
    }
    return [];
  }

  public handleGetReport(req: HidGetReportRequest): GetReportReplyResult {
    if (req.kind === HidReportKind.INPUT) {
      if (req.reportId === REPORT_ID_KEYBOARD && this.profileMode === HidProfileMode.COMBO_TOUCHPAD) {
        return {
          handled: true,
          payload: new Uint8Array(8),
          logLevel: 'OK',
          logMessage: '回复空 Keyboard Input Report (8B)'
        };
      }
      const mouseLen = this.profileMode === HidProfileMode.COMBO_TOUCHPAD ? 5 : 4;
      return {
        handled: true,
        payload: new Uint8Array(mouseLen),
        logLevel: 'OK',
        logMessage: `回复空 Mouse Input Report (${mouseLen}B)`
      };
    }
    return {
      handled: false,
      payload: null,
      logLevel: 'WARN',
      logMessage: `未知 GET_REPORT kind=${req.kind} id=0x${req.reportId.toString(16)}`
    };
  }

  public handleSetReport(req: HidSetReportRequest): SetReportProcessResult {
    const hex = req.data.length > 0 ? formatBytesHex(req.data, 16) : '(empty)';
    return {
      logLevel: 'HANDSHAKE',
      logMessage: `收到主机 SET_REPORT kind=${req.kind} id=0x${req.reportId.toString(16)} data=[${hex}]`
    };
  }

  private buildAppSwitchStartPackets(reverse: boolean): Array<EncodedHidPacket> {
    this.altHeldForSwitch = true;
    if (!reverse) {
      return [
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 0 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_TAB), delayMs: KEY_STEP_MS },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: KEY_STEP_MS + KEY_HOLD_MS }
      ];
    }
    const altShift = MOD_LEFT_ALT | MOD_LEFT_SHIFT;
    return [
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: 0 },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_NONE), delayMs: KEY_STEP_MS },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_TAB), delayMs: KEY_STEP_MS * 2 },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_NONE), delayMs: KEY_STEP_MS * 2 + KEY_HOLD_MS },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: KEY_STEP_MS * 3 + KEY_HOLD_MS }
    ];
  }

  private buildAppSwitchStepPackets(reverse: boolean): Array<EncodedHidPacket> {
    this.altHeldForSwitch = true;
    if (!reverse) {
      return [
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_TAB), delayMs: 0 },
        { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: KEY_HOLD_MS }
      ];
    }
    const altShift = MOD_LEFT_ALT | MOD_LEFT_SHIFT;
    return [
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_NONE), delayMs: 0 },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_TAB), delayMs: KEY_STEP_MS },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(altShift, KEY_NONE), delayMs: KEY_STEP_MS + KEY_HOLD_MS },
      { reportId: REPORT_ID_KEYBOARD, payload: encodeKeyboardReport(MOD_LEFT_ALT, KEY_NONE), delayMs: KEY_STEP_MS * 2 + KEY_HOLD_MS }
    ];
  }

  private decomposeModifiers(mask: number): Array<number> {
    const ordered: Array<number> = [];
    // Always press primary OS modifiers (Ctrl/Alt/Gui) BEFORE Shift to prevent Alt+Shift layout conflicts
    if ((mask & MOD_LEFT_CTRL) !== 0) {
      ordered.push(MOD_LEFT_CTRL);
    }
    if ((mask & MOD_LEFT_ALT) !== 0) {
      ordered.push(MOD_LEFT_ALT);
    }
    if ((mask & MOD_LEFT_GUI) !== 0) {
      ordered.push(MOD_LEFT_GUI);
    }
    if ((mask & MOD_LEFT_SHIFT) !== 0) {
      ordered.push(MOD_LEFT_SHIFT);
    }
    return ordered;
  }
}
