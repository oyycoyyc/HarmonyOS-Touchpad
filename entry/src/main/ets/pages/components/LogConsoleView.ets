import { LogEntry } from '../../model/TouchpadTypes';

@Component
export struct LogConsoleView {
  @Prop logs: Array<LogEntry> = [];
  @Prop consoleHeight: number = 105;
  onClear: () => void = () => {};

  private resolveColor(level: string): string {
    if (level === 'ERR') {
      return '#F87171';
    }
    if (level === 'OK' || level === 'HANDSHAKE') {
      return '#4ADE80';
    }
    if (level === 'GESTURE') {
      return '#38BDF8';
    }
    if (level === 'WARN') {
      return '#FBBF24';
    }
    return '#CBD5E1';
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('蓝牙 HID 握手 & 手势日志 (重点关注 GET_REPORT / SET_REPORT)')
          .fontSize(11)
          .fontColor('#94A3B8')
          .layoutWeight(1)
        Text('清空')
          .fontSize(11)
          .fontColor('#38BDF8')
          .onClick(() => {
            this.onClear();
          })
      }
      .width('100%')

      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.logs, (entry: LogEntry) => {
            Text(`[${entry.time}][${entry.level}] ${entry.message}`)
              .fontSize(10)
              .fontColor(this.resolveColor(entry.level))
              .width('100%')
          }, (entry: LogEntry) => `${entry.id}`)
        }
        .width('100%')
      }
      .height(this.consoleHeight)
      .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#0B1120')
    .borderRadius(8)
    .border({ width: 1, color: '#1E293B' })
  }
}
