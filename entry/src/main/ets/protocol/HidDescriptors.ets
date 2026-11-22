import { REPORT_ID_KEYBOARD, REPORT_ID_MOUSE } from '../model/HidKeyCodes';

/**
 * Classic Bluetooth HID Report Descriptors (SUBCLASS_COMBO & SUBCLASS_MOUSE):
 * 1) Combo Touchpad Descriptor (111B):
 *    - Report ID 0x01 (5B): Mouse (3 Buttons + Rel X + Rel Y + Vertical Wheel + Horizontal AC Pan)
 *    - Report ID 0x02 (8B): Standard USB Keyboard (Modifier byte + Reserved + 6 Keycodes)
 * 2) Standard Mouse Fallback Descriptor (54B):
 *    - Report ID 0x01 (4B): Mouse (3 Buttons + Rel X + Rel Y + Vertical Wheel)
 */
export function buildComboTouchpadDescriptor(): Uint8Array {
  return new Uint8Array([
    // === TLC 1: Mouse + Vertical Wheel + Horizontal AC Pan (Report ID 0x01, 5 bytes) ===
    0x05, 0x01,            // Usage Page (Generic Desktop Ctrls)
    0x09, 0x02,            // Usage (Mouse)
    0xA1, 0x01,            // Collection (Application)
    0x85, REPORT_ID_MOUSE, // Report ID (1)
    0x09, 0x01,            //   Usage (Pointer)
    0xA1, 0x00,            //   Collection (Physical)
    0x05, 0x09,            //     Usage Page (Button)
    0x19, 0x01,            //     Usage Minimum (Button 1)
    0x29, 0x03,            //     Usage Maximum (Button 3)
    0x15, 0x00,            //     Logical Minimum (0)
    0x25, 0x01,            //     Logical Maximum (1)
    0x95, 0x03,            //     Report Count (3)
    0x75, 0x01,            //     Report Size (1)
    0x81, 0x02,            //     Input (Data,Var,Abs) -- Left/Right/Middle
    0x95, 0x01,            //     Report Count (1)
    0x75, 0x05,            //     Report Size (5)
    0x81, 0x03,            //     Input (Const,Var,Abs) -- 5b padding (Byte 0 complete)
    0x05, 0x01,            //     Usage Page (Generic Desktop)
    0x09, 0x30,            //     Usage (X)
    0x09, 0x31,            //     Usage (Y)
    0x09, 0x38,            //     Usage (Wheel - Vertical)
    0x15, 0x81,            //     Logical Minimum (-127)
    0x25, 0x7F,            //     Logical Maximum (127)
    0x75, 0x08,            //     Report Size (8)
    0x95, 0x03,            //     Report Count (3)
    0x81, 0x06,            //     Input (Data,Var,Rel) -- Bytes 1..3
    0x05, 0x0C,            //     Usage Page (Consumer)
    0x0A, 0x38, 0x02,      //     Usage (AC Pan - Horizontal Scroll)
    0x95, 0x01,            //     Report Count (1)
    0x81, 0x06,            //     Input (Data,Var,Rel) -- Byte 4
    0xC0,                  //   End Collection (Physical)
    0xC0,                  // End Collection (Mouse)

    // === TLC 2: Standard USB Keyboard (Report ID 0x02, 8 bytes) ===
    0x05, 0x01,               // Usage Page (Generic Desktop Ctrls)
    0x09, 0x06,               // Usage (Keyboard)
    0xA1, 0x01,               // Collection (Application)
    0x85, REPORT_ID_KEYBOARD, // Report ID (2)
    0x05, 0x07,               //   Usage Page (Keyboard/Keypad)
    0x19, 0xE0,               //   Usage Minimum (Left Ctrl)
    0x29, 0xE7,               //   Usage Maximum (Right GUI)
    0x15, 0x00,               //   Logical Minimum (0)
    0x25, 0x01,               //   Logical Maximum (1)
    0x75, 0x01,               //   Report Size (1)
    0x95, 0x08,               //   Report Count (8)
    0x81, 0x02,               //   Input (Data,Var,Abs) -- Modifiers (Byte 0)
    0x95, 0x01,               //   Report Count (1)
    0x75, 0x08,               //   Report Size (8)
    0x81, 0x01,               //   Input (Const,Array,Abs) -- Reserved (Byte 1)
    0x95, 0x06,               //   Report Count (6)
    0x75, 0x08,               //   Report Size (8)
    0x15, 0x00,               //   Logical Minimum (0)
    0x26, 0xFF, 0x00,         //   Logical Maximum (255)
    0x05, 0x07,               //   Usage Page (Keyboard/Keypad)
    0x19, 0x00,               //   Usage Minimum (0)
    0x29, 0xFF,               //   Usage Maximum (255)
    0x81, 0x00,               //   Input (Data,Array,Abs) -- 6 Keycodes (Bytes 2..7)
    0xC0                      // End Collection (Keyboard)
  ]);
}

/**
 * Fallback 3-button Relative Mouse + Vertical Wheel (54B).
 */
export function buildStandardMouseDescriptor(): Uint8Array {
  return new Uint8Array([
    0x05, 0x01,
    0x09, 0x02,
    0xA1, 0x01,
    0x85, REPORT_ID_MOUSE,
    0x09, 0x01,
    0xA1, 0x00,
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x03,
    0x15, 0x00,
    0x25, 0x01,
    0x95, 0x03,
    0x75, 0x01,
    0x81, 0x02,
    0x95, 0x01,
    0x75, 0x05,
    0x81, 0x03,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x09, 0x38,
    0x15, 0x81,
    0x25, 0x7F,
    0x75, 0x08,
    0x95, 0x03,
    0x81, 0x06,
    0xC0,
    0xC0
  ]);
}
