import {
  HidConnectionState,
  HidProfileMode,
  MappingMode,
  PairedHostDevice
} from '../../model/TouchpadTypes';

@Component
export struct BtControlPanel {
  @Prop permissionGranted: boolean = false;
  @Prop profileMode: HidProfileMode = HidProfileMode.COMBO_TOUCHPAD;
  @Prop mappingMode: MappingMode = MappingMode.MAC_THREE_FINGER_DRAG;
  @Prop naturalScroll: boolean = true;
  @Prop sensitivityLabel: string = '中';
  @Prop isRegistered: boolean = false;
  @Prop connState: HidConnectionState = HidConnectionState.DISCONNECTED;
  @Prop connectedAddr: string = '';
  @Prop txPacketCount: number = 0;
  @Prop pairedDevices: Array<PairedHostDevice> = [];

  onRequestPermission: () => void = () => {};
  onRefreshPaired: () => void = () => {};
  onRegisterMode: (mode: HidProfileMode) => void = () => {};
  onUnregister: () => void = () => {};
  onConnectHost: (address: string) => void = () => {};
  onDisconnectHost: () => void = () => {};
  onToggleMappingMode: () => void = () => {};
  onToggleNaturalScroll: () => void = () => {};
  onCycleSensitivity: () => void = () => {};
  onRunQuickTest: (testId: string) => void = () => {};

  private getConnBadgeColor(): string {
    if (this.connState === HidConnectionState.CONNECTED) {
      return '#16A34A';
    }
    if (this.connState === HidConnectionState.CONNECTING) {
      return '#CA8A04';
    }
    return '#475569';
  }

  build() {
    Column({ space: 6 }) {
      // Status Row
      Row({ space: 6 }) {
        Text(this.connState)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.getConnBadgeColor())
          .borderRadius(4)

        Text(
          this.isRegistered
            ? `已注册:${this.profileMode === HidProfileMode.COMBO_TOUCHPAD ? 'Combo触控板' : '纯鼠标'}`
            : '未注册HID'
        )
          .fontSize(11)
          .fontColor(this.isRegistered ? '#4ADE80' : '#94A3B8')

        Blank()

        Text(`TX:${this.txPacketCount}`)
          .fontSize(11)
          .fontColor('#CBD5E1')
      }
      .width('100%')

      // Profile Register Row
      Row({ space: 6 }) {
        Button('启动触控板(Combo)')
          .height(28)
          .fontSize(11)
          .layoutWeight(1.4)
          .backgroundColor(this.profileMode === HidProfileMode.COMBO_TOUCHPAD && this.isRegistered ? '#059669' : '#0284C7')
          .onClick(() => {
            this.onRegisterMode(HidProfileMode.COMBO_TOUCHPAD);
          })

        Button('纯鼠标兼容')
          .height(28)
          .fontSize(11)
          .layoutWeight(1)
          .backgroundColor(this.profileMode === HidProfileMode.STANDARD_MOUSE && this.isRegistered ? '#059669' : '#334155')
          .onClick(() => {
            this.onRegisterMode(HidProfileMode.STANDARD_MOUSE);
          })

        Button('注销')
          .height(28)
          .fontSize(11)
          .backgroundColor('#7F1D1D')
          .onClick(() => {
            this.onUnregister();
          })
      }
      .width('100%')

      // Paired Hosts Row
      Row({ space: 6 }) {
        Button(this.permissionGranted ? '刷新配对' : '授权蓝牙')
          .height(28)
          .fontSize(11)
          .backgroundColor('#1D4ED8')
          .onClick(() => {
            if (!this.permissionGranted) {
              this.onRequestPermission();
            } else {
              this.onRefreshPaired();
            }
          })

        Scroll() {
          Row({ space: 6 }) {
            if (this.pairedDevices.length === 0) {
              Text('无已配对设备(请先在系统蓝牙配对 MatePad)')
                .fontSize(11)
                .fontColor('#94A3B8')
            } else {
              ForEach(this.pairedDevices, (dev: PairedHostDevice) => {
                Button(dev.name)
                  .height(28)
                  .fontSize(11)
                  .backgroundColor(this.connectedAddr === dev.address ? '#15803D' : '#334155')
                  .onClick(() => {
                    this.onConnectHost(dev.address);
                  })
              }, (dev: PairedHostDevice) => dev.address)
            }
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        if (this.connState === HidConnectionState.CONNECTED) {
          Button('断开')
            .height(28)
            .fontSize(11)
            .backgroundColor('#B91C1C')
            .onClick(() => {
              this.onDisconnectHost();
            })
        }
      }
      .width('100%')

      // Feel & Gesture Strategy Row
      Row({ space: 6 }) {
        Button(this.mappingMode === MappingMode.HARMONY_NATIVE ? 'v0.1鸿蒙原生' : 'v0.2Mac三指拖移')
          .height(26)
          .fontSize(10)
          .layoutWeight(1.4)
          .backgroundColor(this.mappingMode === MappingMode.HARMONY_NATIVE ? '#0F766E' : '#7C3AED')
          .onClick(() => {
            this.onToggleMappingMode();
          })

        Button(this.naturalScroll ? '自然滚动:开' : '自然滚动:关')
          .height(26)
          .fontSize(10)
          .layoutWeight(1)
          .backgroundColor(this.naturalScroll ? '#0369A1' : '#334155')
          .onClick(() => {
            this.onToggleNaturalScroll();
          })

        Button(`速度:${this.sensitivityLabel}`)
          .height(26)
          .fontSize(10)
          .layoutWeight(1.1)
          .backgroundColor('#334155')
          .onClick(() => {
            this.onCycleSensitivity();
          })
      }
      .width('100%')

      // Quick Test Row
      Scroll() {
        Row({ space: 5 }) {
          Button('测光标→')
            .height(24)
            .fontSize(10)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRunQuickTest('cursor_right');
            })

          Button('测滚动↓')
            .height(24)
            .fontSize(10)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRunQuickTest('scroll_down');
            })

          Button('测多任务')
            .height(24)
            .fontSize(10)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRunQuickTest('multitask');
            })

          Button('测回桌面')
            .height(24)
            .fontSize(10)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRunQuickTest('desktop');
            })

          Button('快捷键提示')
            .height(24)
            .fontSize(10)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRunQuickTest('shortcut_help');
            })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#0F172A')
    .borderRadius(10)
    .border({ width: 1, color: '#1E293B' })
  }
}
