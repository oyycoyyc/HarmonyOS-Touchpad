import { common } from '@kit.AbilityKit';
import { createDefaultTouchpadController } from '../app/TouchpadAppFactory';
import { TouchpadController, TouchpadUiState } from '../app/TouchpadController';
import {
  HidConnectionState,
  HidProfileMode,
  LogEntry,
  MappingMode,
  PairedHostDevice,
  VisualTouchDot
} from '../model/TouchpadTypes';
import { fromArkUiTouchEvent } from '../platform/ArkUiTouchAdapter';
import { BluetoothPermissionService } from '../platform/BluetoothPermissionService';
import { WindowImmersiveService } from '../platform/WindowImmersiveService';
import { BtControlPanel } from './components/BtControlPanel';
import { LogConsoleView } from './components/LogConsoleView';
import { TouchpadSurfaceView } from './components/TouchpadSurfaceView';

/**
 * Pure UI composition shell.
 * Contains ZERO Bluetooth API calls, ZERO HID descriptor logic, and ZERO gesture math.
 */
@Entry
@Component
struct Index {
  @State isFullScreenPad: boolean = false;
  @State edgeGuardEnabled: boolean = true;
  @State showLogs: boolean = true;
  @State permissionGranted: boolean = false;

  // Mirrored reactive UI state from TouchpadController
  @State profileMode: HidProfileMode = HidProfileMode.COMBO_TOUCHPAD;
  @State mappingMode: MappingMode = MappingMode.MAC_THREE_FINGER_DRAG;
  @State naturalScroll: boolean = true;
  @State sensitivityLabel: string = '中(2.15)';
  @State isRegistered: boolean = false;
  @State connState: HidConnectionState = HidConnectionState.DISCONNECTED;
  @State connectedAddr: string = '';
  @State pairedDevices: Array<PairedHostDevice> = [];
  @State gestureText: string = '在下方触控区进行 1/2/3/4/5 指操作';
  @State fingerCountNow: number = 0;
  @State threeFingerDragging: boolean = false;
  @State threeFingerClutchPending: boolean = false;
  @State appSwitching: boolean = false;
  @State txPacketCount: number = 0;
  @State visualDots: Array<VisualTouchDot> = [];
  @State logs: Array<LogEntry> = [];
  @State clickPadDown: boolean = false;

  private controller: TouchpadController = createDefaultTouchpadController();
  private permissionService: BluetoothPermissionService = new BluetoothPermissionService();
  private windowService: WindowImmersiveService = new WindowImmersiveService();

  aboutToAppear(): void {
    this.controller.setStateListener((next: TouchpadUiState) => {
      this.syncState(next);
    });
    this.controller.addLog('INFO', '无线触控板已就绪（纯线性光标 + 边缘防误触已开启）');
    this.applyEdgeGuard(this.edgeGuardEnabled);
    this.requestBluetoothPermission();
  }

  aboutToDisappear(): void {
    this.toggleFullScreen(false);
    this.applyEdgeGuard(false);
    this.controller.destroy();
  }

  onBackPress(): boolean {
    if (this.isFullScreenPad) {
      this.controller.addLog('INFO', '已拦截边缘返回手势（请点右上角“退出全屏”）');
      return true;
    }
    if (this.edgeGuardEnabled) {
      this.controller.addLog('INFO', '防误触已拦截返回退出（关闭顶部“防误触”或从底部上滑可退出）');
      return true;
    }
    return false;
  }

  private syncState(next: TouchpadUiState): void {
    this.profileMode = next.profileMode;
    this.mappingMode = next.mappingMode;
    this.naturalScroll = next.naturalScroll;
    this.sensitivityLabel = next.sensitivityLabel;
    this.isRegistered = next.isRegistered;
    this.connState = next.connState;
    this.connectedAddr = next.connectedAddr;
    this.pairedDevices = next.pairedDevices;
    this.gestureText = next.gestureText;
    this.fingerCountNow = next.fingerCountNow;
    this.threeFingerDragging = next.threeFingerDragging;
    this.threeFingerClutchPending = next.threeFingerClutchPending;
    this.appSwitching = next.appSwitching;
    this.txPacketCount = next.txPacketCount;
    this.visualDots = next.visualDots;
    this.logs = next.logs;
    this.clickPadDown = next.clickPadDown;
  }

  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (_ignored) {
      return null;
    }
  }

  private requestBluetoothPermission(): void {
    const context = this.getAbilityContext();
    if (!context) {
      this.controller.addLog('ERR', '无法获取 UIAbilityContext');
      return;
    }
    this.permissionService.requestAccessBluetooth(context).then((res) => {
      this.permissionGranted = res.granted;
      if (res.granted) {
        this.controller.addLog('OK', '已获取 ACCESS_BLUETOOTH 权限');
        this.controller.refreshPairedHosts();
      } else {
        this.controller.addLog('WARN', res.errorMessage);
      }
    });
  }

  private applyEdgeGuard(enabled: boolean): void {
    this.edgeGuardEnabled = enabled;
    const context = this.getAbilityContext();
    if (!context) {
      return;
    }
    this.windowService.setEdgeGestureGuard(context, enabled).then((errMsg: string) => {
      if (errMsg.length > 0) {
        this.controller.addLog('WARN', errMsg);
      }
    });
  }

  private toggleFullScreen(enabled: boolean): void {
    this.isFullScreenPad = enabled;
    const context = this.getAbilityContext();
    if (!context) {
      return;
    }
    this.windowService.setFullScreen(context, enabled, this.edgeGuardEnabled).then((errMsg: string) => {
      if (errMsg.length > 0) {
        this.controller.addLog('WARN', errMsg);
      }
    });
  }

  @Builder
  private buildTopBar() {
    Row({ space: 6 }) {
      Text('无线触控板')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')

      Blank()

      Button(this.edgeGuardEnabled ? '防误触:开' : '防误触:关')
        .height(30)
        .fontSize(10)
        .backgroundColor(this.edgeGuardEnabled ? '#059669' : '#475569')
        .onClick(() => {
          const next = !this.edgeGuardEnabled;
          this.applyEdgeGuard(next);
          this.controller.addLog('INFO', next ? '已开启边缘防误触（禁用左右侧滑返回）' : '已关闭边缘防误触（恢复侧滑返回）');
        })

      Button(this.showLogs ? '隐日志' : '显日志')
        .height(30)
        .fontSize(10)
        .backgroundColor('#334155')
        .onClick(() => {
          this.showLogs = !this.showLogs;
        })

      Button('全屏')
        .height(30)
        .fontSize(10)
        .backgroundColor('#0F766E')
        .onClick(() => {
          this.toggleFullScreen(true);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 6, bottom: 4 })
  }

  build() {
    Column({ space: this.isFullScreenPad ? 0 : 8 }) {
      if (!this.isFullScreenPad) {
        this.buildTopBar()
      }

      Column({ space: this.isFullScreenPad ? 0 : 8 }) {
        if (!this.isFullScreenPad) {
          BtControlPanel({
            permissionGranted: this.permissionGranted,
            profileMode: this.profileMode,
            mappingMode: this.mappingMode,
            naturalScroll: this.naturalScroll,
            sensitivityLabel: this.sensitivityLabel,
            isRegistered: this.isRegistered,
            connState: this.connState,
            connectedAddr: this.connectedAddr,
            txPacketCount: this.txPacketCount,
            pairedDevices: this.pairedDevices,
            onRequestPermission: () => {
              this.requestBluetoothPermission();
            },
            onRefreshPaired: () => {
              this.controller.refreshPairedHosts();
            },
            onRegisterMode: (mode: HidProfileMode) => {
              this.controller.registerProfile(mode);
            },
            onUnregister: () => {
              this.controller.unregisterProfile();
            },
            onConnectHost: (addr: string) => {
              this.controller.connectHost(addr);
            },
            onDisconnectHost: () => {
              this.controller.disconnectHost();
            },
            onToggleMappingMode: () => {
              this.controller.toggleMappingStrategy();
            },
            onToggleNaturalScroll: () => {
              this.controller.toggleNaturalScroll();
            },
            onCycleSensitivity: () => {
              this.controller.cycleSensitivity();
            },
            onRunQuickTest: (testId: string) => {
              this.controller.runQuickTest(testId);
            }
          })
        }

        TouchpadSurfaceView({
          isFullScreenPad: this.isFullScreenPad,
          connState: this.connState,
          mappingMode: this.mappingMode,
          gestureText: this.gestureText,
          fingerCountNow: this.fingerCountNow,
          threeFingerDragging: this.threeFingerDragging,
          threeFingerClutchPending: this.threeFingerClutchPending,
          appSwitching: this.appSwitching,
          txPacketCount: this.txPacketCount,
          clickPadDown: this.clickPadDown,
          visualDots: this.visualDots,
          onTouchInput: (event: TouchEvent) => {
            this.controller.handleTouchSnapshot(fromArkUiTouchEvent(event));
          },
          onClickPadChanged: (pressed: boolean) => {
            this.controller.setClickPadPressed(pressed);
          },
          onRightClick: () => {
            this.controller.sendMouseClick(0x02);
          },
          onExitFullScreen: () => {
            this.toggleFullScreen(false);
          }
        })

        if (!this.isFullScreenPad && this.showLogs) {
          LogConsoleView({
            logs: this.logs,
            onClear: () => {
              this.controller.clearLogs();
            }
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding(this.isFullScreenPad ? 0 : { left: 10, right: 10, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#020617')
  }
}
