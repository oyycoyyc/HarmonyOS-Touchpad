import { HidConnectionState, MappingMode, VisualTouchDot } from '../../model/TouchpadTypes';

const DOT_COLORS: Array<string> = ['#38BDF8', '#4ADE80', '#FBBF24', '#F472B6', '#A78BFA'];

@Component
export struct TouchpadSurfaceView {
  @Prop isFullScreenPad: boolean = false;
  @Prop connState: HidConnectionState = HidConnectionState.DISCONNECTED;
  @Prop mappingMode: MappingMode = MappingMode.MAC_THREE_FINGER_DRAG;
  @Prop gestureText: string = '';
  @Prop fingerCountNow: number = 0;
  @Prop threeFingerDragging: boolean = false;
  @Prop threeFingerClutchPending: boolean = false;
  @Prop appSwitching: boolean = false;
  @Prop txPacketCount: number = 0;
  @Prop clickPadDown: boolean = false;
  @Prop visualDots: Array<VisualTouchDot> = [];

  onTouchInput: (event: TouchEvent) => void = () => {};
  onClickPadChanged: (pressed: boolean) => void = () => {};
  onRightClick: () => void = () => {};
  onExitFullScreen: () => void = () => {};

  private getDotColor(slotId: number): string {
    return DOT_COLORS[Math.abs(slotId) % DOT_COLORS.length];
  }

  private getBorderColor(): string {
    if (this.appSwitching) {
      return '#F59E0B';
    }
    if (this.threeFingerClutchPending) {
      return '#C084FC';
    }
    if (this.threeFingerDragging) {
      return '#A855F7';
    }
    return this.connState === HidConnectionState.CONNECTED ? '#0284C7' : '#334155';
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 6 }) {
          if (this.appSwitching) {
            Text('切应用选择中 (左右续滑切换 / 松手确认)')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor('#D97706')
              .borderRadius(12)
          } else if (this.threeFingerClutchPending) {
            Text('Mac 三指拖移待续接 (放回三指续拖 / 轻点放下)')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor('#9333EA')
              .borderRadius(12)
          } else if (this.threeFingerDragging) {
            Text('Mac 三指拖移中 (左键已锁定)')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor('#7C3AED')
              .borderRadius(12)
          }

          Text(this.gestureText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E0F2FE')
            .textAlign(TextAlign.Center)

          Text(
            `当前触点: ${this.fingerCountNow} 指  |  模式: ${
              this.mappingMode === MappingMode.HARMONY_NATIVE ? 'v0.1 鸿蒙原生逻辑' : 'v0.2 Mac三指拖移 / 4指映3指'
            }`
          )
            .fontSize(11)
            .fontColor('#64748B')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)

        ForEach(this.visualDots, (dot: VisualTouchDot) => {
          Stack() {
            Circle({ width: 44, height: 44 })
              .fill(this.getDotColor(dot.slotId))
              .opacity(0.35)
              .stroke(this.getDotColor(dot.slotId))
              .strokeWidth(2)
            Text(`F${dot.slotId + 1}`)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .position({ x: dot.x - 22, y: dot.y - 22 })
          .hitTestBehavior(HitTestMode.None)
        }, (dot: VisualTouchDot) => `${dot.fingerId}`)

        if (this.isFullScreenPad) {
          Row({ space: 8 }) {
            Blank()
            Text(`${this.connState} | TX:${this.txPacketCount}`)
              .fontSize(11)
              .fontColor('#94A3B8')
              .hitTestBehavior(HitTestMode.None)
            Button('退出全屏')
              .height(28)
              .fontSize(11)
              .backgroundColor('#334155')
              .onClick(() => {
                this.onExitFullScreen();
              })
          }
          .width('100%')
          .padding({ top: 40, right: 16, left: 16 })
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#111827')
      .borderRadius(this.isFullScreenPad ? 0 : 14)
      .border({
        width: this.isFullScreenPad ? 0 : ((this.threeFingerDragging || this.appSwitching) ? 2.5 : 1.5),
        color: this.getBorderColor()
      })
      .onTouch((event: TouchEvent) => {
        this.onTouchInput(event);
      })

      if (!this.isFullScreenPad) {
        Row({ space: 8 }) {
          Button(this.clickPadDown ? '左键按下中...' : '物理左键 (按住可拖移)')
            .height(38)
            .fontSize(12)
            .layoutWeight(2)
            .backgroundColor(this.clickPadDown ? '#0284C7' : '#1E293B')
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.onClickPadChanged(true);
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.onClickPadChanged(false);
              }
            })

          Button('右键点击')
            .height(38)
            .fontSize(12)
            .layoutWeight(1)
            .backgroundColor('#1E293B')
            .onClick(() => {
              this.onRightClick();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
}
