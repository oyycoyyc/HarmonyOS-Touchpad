import {
  HidConnectionState,
  HidGetReportRequest,
  HidRegistrationConfig,
  HidReportKind,
  HidSetReportRequest,
  PairedHostDevice
} from '../model/TouchpadTypes';

export interface HidTransportListener {
  onLog: (level: string, message: string) => void;
  onRegistrationChanged: (registered: boolean) => void;
  onConnectionChanged: (state: HidConnectionState, deviceId: string) => void;
  onGetReport: (req: HidGetReportRequest) => void;
  onSetReport: (req: HidSetReportRequest) => void;
}

/**
 * Transport abstraction decoupling Bluetooth implementation from TouchpadController and HID protocol.
 * Implementation: ClassicBtHidTransport (@ohos.bluetooth.hid, SUBCLASS_COMBO / SUBCLASS_MOUSE).
 */
export interface IHidTransport {
  readonly transportName: string;
  setListener(listener: HidTransportListener): void;
  isBluetoothOn(): boolean;
  getPairedHosts(): Array<PairedHostDevice>;
  register(config: HidRegistrationConfig): void;
  unregister(): void;
  connect(address: string): void;
  disconnect(): void;
  sendInputReport(reportId: number, payload: Uint8Array): boolean;
  replyReport(kind: HidReportKind, reportId: number, payload: Uint8Array): void;
  reportInvalidReportId(): void;
  destroy(): void;
}
