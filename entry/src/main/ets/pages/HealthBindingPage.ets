/**
 * 运动计步绑定页。
 * 只负责申请运动权限并读取今日步数（华为运动优先，未开通时自动降级本机计步），不创建低碳记录。
 */
import { common } from '@kit.AbilityKit';
import { CarbonEvidenceService, EvidenceResult } from '../services/CarbonEvidenceService';

@Component
export struct HealthBindingPage {
  onBack?: () => void;
  onBound?: (steps: number) => void;
  @State private reading: boolean = false;
  @State private steps: number = 0;
  @State private message: string = '授权后，碳记只读取今日步数用于可信统计';

  private evidenceService: CarbonEvidenceService = new CarbonEvidenceService();

  private async bindHealth(): Promise<void> {
    if (this.reading) {
      return;
    }
    this.reading = true;
    this.message = '正在读取今日步数…';
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result: EvidenceResult = await this.evidenceService.readTodaySteps(context);
      // 华为运动或本机计步任一来源读取成功即视为绑定完成；本机计步首次读取只建立基数
      if (result.source === 'health' || result.source === 'sensor') {
        this.steps = Math.round(result.amount);
        this.message = `${result.message}，可返回“我的”查看`;
        this.onBound?.(this.steps);
      } else {
        this.message = result.message;
      }
    } catch (error) {
      this.message = '今日步数暂时无法读取，请稍后重试';
    } finally {
      this.reading = false;
    }
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Text('‹').fontSize(40).fontColor('#174E3A')
        }
        .width(44)
        .height(48)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回我的')
        .onClick(() => this.onBack?.())
        Blank()
        Text('绑定华为运动')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
        Blank()
        Blank().width(44)
      }
      .width('100%')
      .height(52)
      .padding({ left: 14, right: 14 })

      Column({ space: 18 }) {
        Column({ space: 10 }) {
          Text('读取今日步数')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
          Text('优先读取华为运动健康数据，未开通时自动使用本机计步传感器，均不接受手动修改。')
            .fontSize(14)
            .fontColor('#718078')
            .lineHeight(22)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Column({ space: 6 }) {
          Text(this.steps > 0 ? `${this.steps}` : '—')
            .fontSize(42)
            .fontWeight(FontWeight.Bold)
            .fontColor('#246244')
          Text('今日步数')
            .fontSize(13)
            .fontColor('#718078')
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .backgroundColor('#EAF3E7')
        .borderRadius(18)
        .alignItems(HorizontalAlign.Center)

        Text(this.message)
          .width('100%')
          .fontSize(13)
          .fontColor('#6E7F74')
          .textAlign(TextAlign.Center)
          .lineHeight(20)

        Button(this.reading ? '读取中…' : (this.steps > 0 ? '重新读取今日步数' : '授权并读取今日步数'),
          { type: ButtonType.Capsule, stateEffect: true })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#4C9576')
          .enabled(!this.reading)
          .onClick(() => this.bindHealth())
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 34 })
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
  }
}

@Preview({ title: 'HealthBindingPage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false })
@Component
struct HealthBindingPagePreview {
  build() {
    HealthBindingPage()
  }
}
