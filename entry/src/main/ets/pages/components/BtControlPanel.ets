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
  @Prop inertiaEnabled: boolean = false;
  @Prop inertiaStrength: number = 35;
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
  onToggleInertia: () => void = () => {};
  onChangeInertiaStrength: (value: number, commitLog: boolean) => void = () => {};

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

        Text(this.isRegistered ? '已注册:Combo触控板' : '未注册HID')
          .fontSize(11)
          .fontColor(this.isRegistered ? '#4ADE80' : '#94A3B8')

        Blank()

        Text(`TX:${this.txPacketCount}`)
          .fontSize(11)
          .fontColor('#CBD5E1')
      }
      .width('100%')

      // Profile Register Row (pure mouse compatibility hidden)
      Row({ space: 6 }) {
        Button('启动触控板')
          .height(28)
          .fontSize(11)
          .layoutWeight(1)
          .backgroundColor(this.profileMode === HidProfileMode.COMBO_TOUCHPAD && this.isRegistered ? '#059669' : '#0284C7')
          .onClick(() => {
            this.onRegisterMode(HidProfileMode.COMBO_TOUCHPAD);
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

      // Feel & Gesture Strategy Row 1
      Row({ space: 6 }) {
        Button(this.mappingMode === MappingMode.HARMONY_NATIVE ? 'v0.1鸿蒙原生' : 'v0.2Mac三指拖移')
          .height(26)
          .fontSize(10)
          .layoutWeight(1.3)
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
      }
      .width('100%')

      // Feel & Gesture Strategy Row 2: Speed & Trackball Inertia Toggle
      Row({ space: 6 }) {
        Button(`速度:${this.sensitivityLabel}`)
          .height(26)
          .fontSize(10)
          .layoutWeight(1)
          .backgroundColor('#334155')
          .onClick(() => {
            this.onCycleSensitivity();
          })

        Button(`轨迹球惯性:${this.inertiaEnabled ? '开' : '关'}`)
          .height(26)
          .fontSize(10)
          .layoutWeight(1.1)
          .backgroundColor(this.inertiaEnabled ? '#0284C7' : '#334155')
          .onClick(() => {
            this.onToggleInertia();
          })
      }
      .width('100%')

      // Linear Inertia Slider Row (visible only when trackball inertia is enabled)
      if (this.inertiaEnabled) {
        Row({ space: 6 }) {
          Text('惯性强度')
            .fontSize(10)
            .fontColor('#94A3B8')

          Slider({
            value: this.inertiaStrength,
            min: 5,
            max: 100,
            step: 1,
            style: SliderStyle.OutSet
          })
            .trackThickness(4)
            .blockColor('#38BDF8')
            .selectedColor('#0284C7')
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.onChangeInertiaStrength(
                Math.round(value),
                mode === SliderChangeMode.End || mode === SliderChangeMode.Click
              );
            })

          Text(`${this.inertiaStrength}%`)
            .fontSize(10)
            .fontColor('#E2E8F0')
            .width(34)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#0F172A')
    .borderRadius(10)
    .border({ width: 1, color: '#1E293B' })
  }
}
