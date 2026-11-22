function clampInt8(value: number): number {
  const rounded = Math.round(value);
  if (rounded < -127) {
    return -127;
  }
  if (rounded > 127) {
    return 127;
  }
  return rounded & 0xFF;
}

/**
 * Encodes 5-byte Combo Mouse Report (Report ID 0x01 excluded):
 * [buttons, relX, relY, vWheel, hPan]
 */
export function encodeComboMouseReport(
  buttons: number,
  dx: number,
  dy: number,
  vWheel: number,
  hPan: number
): Uint8Array {
  const buf = new Uint8Array(5);
  buf[0] = buttons & 0x07;
  buf[1] = clampInt8(dx);
  buf[2] = clampInt8(dy);
  buf[3] = clampInt8(vWheel);
  buf[4] = clampInt8(hPan);
  return buf;
}

/**
 * Encodes 4-byte Standard Mouse Report (Report ID 0x01 excluded):
 * [buttons, relX, relY, vWheel]
 */
export function encodeStandardMouseReport(
  buttons: number,
  dx: number,
  dy: number,
  vWheel: number
): Uint8Array {
  const buf = new Uint8Array(4);
  buf[0] = buttons & 0x07;
  buf[1] = clampInt8(dx);
  buf[2] = clampInt8(dy);
  buf[3] = clampInt8(vWheel);
  return buf;
}

/**
 * Encodes 8-byte Standard Keyboard Report (Report ID 0x02 excluded):
 * [modifiers, reserved(0), key0, key1, key2, key3, key4, key5]
 */
export function encodeKeyboardReport(modifiers: number, keycode: number): Uint8Array {
  const buf = new Uint8Array(8);
  buf[0] = modifiers & 0xFF;
  buf[1] = 0x00;
  buf[2] = keycode & 0xFF;
  return buf;
}

export function formatBytesHex(bytes: Uint8Array, maxLen: number = 16): string {
  const limit = Math.min(bytes.length, maxLen);
  const parts: Array<string> = [];
  for (let i = 0; i < limit; i++) {
    const h = bytes[i].toString(16).toUpperCase();
    parts.push(h.length === 1 ? '0' + h : h);
  }
  return parts.join(' ') + (bytes.length > maxLen ? ` ...(${bytes.length}B)` : '');
}
