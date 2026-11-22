/**
 * Pure USB HID Keyboard Modifier & Usage ID constants (Usage Page 0x07).
 * Zero platform or protocol dependencies; shared cleanly across engine/ and protocol/.
 */

export const REPORT_ID_MOUSE: number = 0x01;
export const REPORT_ID_KEYBOARD: number = 0x02;

// USB HID Keyboard Modifiers (Byte 0 of 8-byte Keyboard Input Report)
export const MOD_NONE: number = 0x00;
export const MOD_LEFT_CTRL: number = 0x01;
export const MOD_LEFT_SHIFT: number = 0x02;
export const MOD_LEFT_ALT: number = 0x04;
export const MOD_LEFT_GUI: number = 0x08; // HarmonyOS Key / Meta / Win

// USB HID Keyboard Usage IDs (Page 0x07)
export const KEY_NONE: number = 0x00;
export const KEY_C: number = 0x06;
export const KEY_D: number = 0x07;
export const KEY_N: number = 0x11;
export const KEY_S: number = 0x16;
export const KEY_ENTER: number = 0x28;
export const KEY_ESC: number = 0x29;
export const KEY_BACKSPACE: number = 0x2A;
export const KEY_TAB: number = 0x2B;
export const KEY_SLASH: number = 0x38; // With Meta -> HarmonyOS shortcut cheat sheet
export const KEY_RIGHT: number = 0x4F;
export const KEY_LEFT: number = 0x50;
export const KEY_DOWN: number = 0x51;
export const KEY_UP: number = 0x52;
