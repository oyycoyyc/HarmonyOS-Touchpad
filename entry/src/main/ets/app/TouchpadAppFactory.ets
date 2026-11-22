import { ClassicBtHidTransport } from '../transport/ClassicBtHidTransport';
import { TouchpadController } from './TouchpadController';

/**
 * Composition root wiring the concrete Classic BT HID Combo transport into TouchpadController.
 * Keeps pages/ completely decoupled from transport/ and protocol/ implementations.
 */
export function createDefaultTouchpadController(): TouchpadController {
  return new TouchpadController(new ClassicBtHidTransport());
}
