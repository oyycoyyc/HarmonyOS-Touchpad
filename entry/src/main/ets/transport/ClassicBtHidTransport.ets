import { access, baseProfile, common as btCommon, connection, constant, hid } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HidConnectionState,
  HidRegistrationConfig,
  HidReportKind,
  PairedHostDevice
} from '../model/TouchpadTypes';
import { HidTransportListener, IHidTransport } from './IHidTransport';

const UNREGISTER_FALLBACK_DELAY_MS: number = 500;
const RETRY_2903051_DELAY_MS: number = 650;

/**
 * Classic Bluetooth HID Device transport (@ohos.bluetooth.hid, API 23+ / 26.0.1).
 * Handles asynchronous unregister -> re-register sequencing safely to avoid 2903051 races.
 */
export class ClassicBtHidTransport implements IHidTransport {
  public readonly transportName: string = 'ClassicBT-HID';
  private listener: HidTransportListener | null = null;
  private hidDevice: hid.HidDeviceProfile | null = null;
  private isRegistered: boolean = false;
  private isUnregistering: boolean = false;
  private pendingConfig: HidRegistrationConfig | null = null;
  private pendingTimerId: number = -1;
  private connState: HidConnectionState = HidConnectionState.DISCONNECTED;

  private connectionStateHandler: (data: baseProfile.StateChangeParam) => void =
    (data: baseProfile.StateChangeParam) => {
      this.handleConnectionStateChange(data);
    };

  private getReportHandler: (data: hid.GetReportData) => void =
    (data: hid.GetReportData) => {
      if (this.listener) {
        this.listener.onGetReport({
          kind: this.fromOhosReportType(data.type),
          reportId: data.id,
          bufferSize: data.bufferSize
        });
      }
    };

  private setReportHandler: (data: hid.SetReportData) => void =
    (data: hid.SetReportData) => {
      if (this.listener) {
        this.listener.onSetReport({
          kind: this.fromOhosReportType(data.type),
          reportId: data.id,
          data: data.data ? data.data : new Uint8Array(0)
        });
      }
      try {
        this.hidDevice?.reportError(hid.ErrorReason.RSP_SUCCESS);
      } catch (_ignored) {
        // Ignore if host disconnected mid-transaction
      }
    };

  private setProtocolHandler: (data: hid.ProtocolData) => void =
    (data: hid.ProtocolData) => {
      const modeName = data.protocol === hid.ProtocolType.PROTOCOL_BOOT_MODE ? 'BOOT_MODE' : 'REPORT_MODE';
      this.log('HANDSHAKE', `收到主机 SET_PROTOCOL: ${modeName} (${data.protocol})`);
      try {
        this.hidDevice?.reportError(hid.ErrorReason.RSP_SUCCESS);
      } catch (_ignored) {
        // Ignore
      }
    };

  private virtualCableUnplugHandler: () => void = () => {
    this.log('WARN', '收到主机 VirtualCableUnplug（远端已解除 HID 绑定）');
  };

  public setListener(listener: HidTransportListener): void {
    this.listener = listener;
  }

  public isBluetoothOn(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `查询蓝牙状态失败: ${e.code} ${e.message}`);
      return false;
    }
  }

  public getPairedHosts(): Array<PairedHostDevice> {
    const result: Array<PairedHostDevice> = [];
    try {
      const addresses: Array<string> = connection.getPairedDevices();
      for (let i = 0; i < addresses.length; i++) {
        const addr = addresses[i];
        let name = addr;
        try {
          const remoteName = connection.getRemoteDeviceName(addr);
          if (remoteName && remoteName.length > 0) {
            name = remoteName;
          }
        } catch (_ignored) {
          name = addr;
        }
        result.push({ address: addr, name: name });
      }
      this.log('INFO', `已加载 ${result.length} 个已配对蓝牙设备`);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `读取已配对列表失败: ${e.code} ${e.message}`);
    }
    return result;
  }

  public register(config: HidRegistrationConfig): void {
    if (!this.isBluetoothOn()) {
      this.log('WARN', '蓝牙未开启，请先打开 nova 15 Pro 蓝牙');
      return;
    }

    this.ensureProfileInstance();
    if (!this.hidDevice) {
      return;
    }

    // If currently registered or mid-unregister, wait asynchronously for unregister completion before registering!
    if (this.isRegistered || this.isUnregistering) {
      this.pendingConfig = config;
      if (!this.isUnregistering) {
        this.isUnregistering = true;
        this.log('INFO', '正在异步注销旧 HID 配置，完成后自动切换...');
        try {
          if (this.connState === HidConnectionState.CONNECTED || this.connState === HidConnectionState.CONNECTING) {
            this.hidDevice.disconnect();
          }
        } catch (_ignored) {
          // Ignore disconnect error during mode switch
        }
        try {
          this.hidDevice.unregisterHidDevice();
        } catch (err) {
          const e = err as BusinessError;
          this.log('WARN', `切换前注销返回: code=${e.code} ${e.message}`);
        }
      }
      this.schedulePendingRegister(UNREGISTER_FALLBACK_DELAY_MS);
      return;
    }

    this.doRegister(config, true);
  }

  public unregister(): void {
    this.clearPendingTimer();
    this.pendingConfig = null;
    this.isUnregistering = false;

    this.ensureProfileInstance();
    if (!this.hidDevice) {
      return;
    }
    try {
      this.hidDevice.unregisterHidDevice();
      this.isRegistered = false;
      this.connState = HidConnectionState.DISCONNECTED;
      this.listener?.onRegistrationChanged(false);
      this.listener?.onConnectionChanged(HidConnectionState.DISCONNECTED, '');
      this.log('INFO', '已发送注销 HID Device 请求（等待系统释放完成）');
    } catch (err) {
      const e = err as BusinessError;
      this.isRegistered = false;
      this.listener?.onRegistrationChanged(false);
      this.log('ERR', `unregister 失败: code=${e.code}, msg=${e.message}`);
    }
  }

  public connect(address: string): void {
    if (!this.hidDevice || !this.isRegistered) {
      this.log('WARN', '请先等待 HID 注册成功，再连接主机');
      return;
    }
    try {
      const target: btCommon.BluetoothAddress = {
        address: address,
        addressType: btCommon.BluetoothAddressType.REAL
      };
      this.log('INFO', `正在发起 HID 连接 -> ${address}`);
      this.hidDevice.connect(target);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `connect 失败: code=${e.code}, msg=${e.message}`);
    }
  }

  public disconnect(): void {
    if (!this.hidDevice) {
      return;
    }
    try {
      this.hidDevice.disconnect();
      this.log('INFO', '已请求断开 HID 主机连接');
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `disconnect 失败: code=${e.code}, msg=${e.message}`);
    }
  }

  public sendInputReport(reportId: number, payload: Uint8Array): boolean {
    if (!this.hidDevice || this.connState !== HidConnectionState.CONNECTED) {
      return false;
    }
    try {
      this.hidDevice.sendReport(reportId, payload);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `sendReport 失败: code=${e.code}, msg=${e.message}`);
      return false;
    }
  }

  public replyReport(kind: HidReportKind, reportId: number, payload: Uint8Array): void {
    if (!this.hidDevice) {
      return;
    }
    try {
      this.hidDevice.replyReport(this.toOhosReportType(kind), reportId, payload);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `replyReport 异常: code=${e.code}, msg=${e.message}`);
    }
  }

  public reportInvalidReportId(): void {
    if (!this.hidDevice) {
      return;
    }
    try {
      this.hidDevice.reportError(hid.ErrorReason.RSP_INVALID_REPORT_ID);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `reportError 异常: code=${e.code}, msg=${e.message}`);
    }
  }

  public destroy(): void {
    this.clearPendingTimer();
    this.pendingConfig = null;
    if (this.hidDevice) {
      this.detachListeners(this.hidDevice);
      if (this.isRegistered) {
        this.unregister();
      }
      this.hidDevice = null;
    }
  }

  private ensureProfileInstance(): void {
    if (this.hidDevice) {
      return;
    }
    try {
      this.hidDevice = hid.createHidDeviceProfile();
      this.attachListeners(this.hidDevice);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `createHidDeviceProfile 失败: code=${e.code}, msg=${e.message}`);
    }
  }

  private doRegister(config: HidRegistrationConfig, allowRetryOn2903051: boolean): void {
    if (!this.hidDevice) {
      return;
    }
    this.clearPendingTimer();
    this.isUnregistering = false;

    const subclass = config.useComboSubclass
      ? hid.Subclass.SUBCLASS_COMBO
      : hid.Subclass.SUBCLASS_MOUSE;

    const sdp: hid.HidDeviceSdp = {
      name: config.name,
      description: config.description,
      provider: config.provider,
      subclass: subclass,
      descriptors: config.descriptors
    };

    const qos: hid.HidDeviceQos = {
      serviceType: hid.ServiceType.SERVICE_BEST_EFFORT,
      tokenRate: 0,
      tokenBucketSize: 0,
      peakBandwidth: 0,
      latency: -1,
      delayVariation: -1
    };

    const subclassLabel = config.useComboSubclass ? 'SUBCLASS_COMBO(192)' : 'SUBCLASS_MOUSE(128)';
    this.log(
      'INFO',
      `[${this.transportName}] 注册 HID Device (${config.name}, ${subclassLabel}, ${config.descriptors.length}B)...`
    );

    try {
      this.hidDevice.registerHidDevice(sdp, qos, qos, (registered: boolean) => {
        this.isRegistered = registered;
        this.log(registered ? 'OK' : 'WARN', `registerHidDevice 回调: registered=${registered}`);
        this.listener?.onRegistrationChanged(registered);

        if (!registered && this.pendingConfig) {
          const nextConfig = this.pendingConfig;
          this.pendingConfig = null;
          this.isUnregistering = false;
          this.clearPendingTimer();
          // Give Bluetooth SDP a brief moment (120ms) after unregister callback before re-registering
          this.pendingTimerId = setTimeout(() => {
            this.pendingTimerId = -1;
            this.doRegister(nextConfig, true);
          }, 120);
        }
      });
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 2903051 && allowRetryOn2903051) {
        this.log('WARN', '捕获 2903051（旧 HID 注册尚未释放），尝试自动注销并在 650ms 后重试...');
        try {
          this.hidDevice.unregisterHidDevice();
        } catch (_ignored) {
          // Ignore
        }
        this.pendingConfig = null;
        this.isRegistered = false;
        this.isUnregistering = true;
        this.pendingTimerId = setTimeout(() => {
          this.pendingTimerId = -1;
          this.isUnregistering = false;
          this.doRegister(config, false);
        }, RETRY_2903051_DELAY_MS);
        return;
      }
      if (e.code === 2903051) {
        this.log('ERR', '仍报 2903051：请将 App 切到后台再切回（或开关一次手机蓝牙）以释放残留 HID 注册');
      } else {
        this.log('ERR', `register 异常: code=${e.code}, msg=${e.message}`);
      }
    }
  }

  private schedulePendingRegister(delayMs: number): void {
    this.clearPendingTimer();
    this.pendingTimerId = setTimeout(() => {
      this.pendingTimerId = -1;
      if (this.pendingConfig) {
        const nextConfig = this.pendingConfig;
        this.pendingConfig = null;
        this.isRegistered = false;
        this.isUnregistering = false;
        this.doRegister(nextConfig, true);
      }
    }, delayMs);
  }

  private clearPendingTimer(): void {
    if (this.pendingTimerId !== -1) {
      clearTimeout(this.pendingTimerId);
      this.pendingTimerId = -1;
    }
  }

  private attachListeners(device: hid.HidDeviceProfile): void {
    try {
      device.on('connectionStateChange', this.connectionStateHandler);
      device.onGetReport(this.getReportHandler);
      device.onSetReport(this.setReportHandler);
      device.onSetProtocol(this.setProtocolHandler);
      device.onVirtualCableUnplug(this.virtualCableUnplugHandler);
    } catch (err) {
      const e = err as BusinessError;
      this.log('ERR', `注册 HID 监听器失败: ${e.code} ${e.message}`);
    }
  }

  private detachListeners(device: hid.HidDeviceProfile): void {
    try {
      device.off('connectionStateChange', this.connectionStateHandler);
      device.offGetReport(this.getReportHandler);
      device.offSetReport(this.setReportHandler);
      device.offSetProtocol(this.setProtocolHandler);
      device.offVirtualCableUnplug(this.virtualCableUnplugHandler);
    } catch (_ignored) {
      // Ignore cleanup errors
    }
  }

  private handleConnectionStateChange(data: baseProfile.StateChangeParam): void {
    let mapped = HidConnectionState.DISCONNECTED;
    if (data.state === constant.ProfileConnectionState.STATE_CONNECTING) {
      mapped = HidConnectionState.CONNECTING;
    } else if (data.state === constant.ProfileConnectionState.STATE_CONNECTED) {
      mapped = HidConnectionState.CONNECTED;
    } else if (data.state === constant.ProfileConnectionState.STATE_DISCONNECTING) {
      mapped = HidConnectionState.DISCONNECTING;
    }
    this.connState = mapped;
    this.log('STATE', `连接状态变化: ${mapped} (device=${data.deviceId})`);
    this.listener?.onConnectionChanged(mapped, data.deviceId);
  }

  private fromOhosReportType(type: hid.ReportType): HidReportKind {
    if (type === hid.ReportType.REPORT_TYPE_FEATURE) {
      return HidReportKind.FEATURE;
    }
    if (type === hid.ReportType.REPORT_TYPE_OUTPUT) {
      return HidReportKind.OUTPUT;
    }
    return HidReportKind.INPUT;
  }

  private toOhosReportType(kind: HidReportKind): hid.ReportType {
    if (kind === HidReportKind.FEATURE) {
      return hid.ReportType.REPORT_TYPE_FEATURE;
    }
    if (kind === HidReportKind.OUTPUT) {
      return hid.ReportType.REPORT_TYPE_OUTPUT;
    }
    return hid.ReportType.REPORT_TYPE_INPUT;
  }

  private log(level: string, message: string): void {
    this.listener?.onLog(level, message);
  }
}
