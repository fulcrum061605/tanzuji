/**
 * 低碳足迹棋盘。
 * 单机离线运行：掷骰消耗积分，沿低碳行为格前进，机会格每周最多发放一次模拟权益。
 */
import { common } from '@kit.AbilityKit';
import { CarbonPointsService, FootprintRollResult, PointsSnapshot } from '../services/CarbonPointsService';

interface FootprintCell {
  name: string;
  icon: Resource;
  kind: string;
}

interface ScienceCard {
  title: string;
  body: string;
  source: string;
}

const FOOTPRINT_CELLS: FootprintCell[] = [
  { name: '起点', icon: $r('app.media.diary_leaf'), kind: 'start' },
  { name: '步行', icon: $r('app.media.diary_walk'), kind: 'action' },
  { name: '骑行', icon: $r('app.media.diary_bike'), kind: 'action' },
  { name: '机会', icon: $r('app.media.diary_sprout'), kind: 'chance' },
  { name: '公交', icon: $r('app.media.diary_transit'), kind: 'action' },
  { name: '节电', icon: $r('app.media.diary_electricity'), kind: 'action' },
  { name: '机会', icon: $r('app.media.diary_sprout'), kind: 'chance' },
  { name: '回收', icon: $r('app.media.diary_recycle'), kind: 'action' },
  { name: '补给', icon: $r('app.media.diary_leaf'), kind: 'bonus' },
  { name: '节水', icon: $r('app.media.diary_water'), kind: 'action' },
  { name: '机会', icon: $r('app.media.diary_sprout'), kind: 'chance' },
  { name: '再利用', icon: $r('app.media.diary_reuse'), kind: 'action' },
  { name: '拼车', icon: $r('app.media.diary_person'), kind: 'action' },
  { name: '机会', icon: $r('app.media.diary_sprout'), kind: 'chance' },
  { name: '低碳餐', icon: $r('app.media.diary_meal'), kind: 'action' },
  { name: '终点', icon: $r('app.media.carbon_icon'), kind: 'finish' }
];

// 5×5 外框棋盘的槽位映射，-1 代表中间留白，用户只沿外围行走。
const FRAME_BOARD_INDEXES: number[] = [
  0, 1, 2, 3, 4,
  15, -1, -1, -1, 5,
  14, -1, -1, -1, 6,
  13, -1, -1, -1, 7,
  12, 11, 10, 9, 8
];

const SCIENCE_CARDS: ScienceCard[] = [
  { title: '低碳出行', body: '短距离步行或骑行，可以减少机动车出行带来的排放。', source: '来源：生态环境部绿色生活科普资料' },
  { title: '待机也会耗电', body: '长期不用的设备及时关闭电源，可以减少待机状态下的持续耗电。', source: '来源：国家发展改革委节能宣传资料' },
  { title: '光盘也是低碳', body: '减少食物浪费，也能减少生产、运输、冷藏和处理过程中的资源消耗。', source: '来源：国家市场监督管理总局反食品浪费资料' },
  { title: '分类带来再利用', body: '准确分类有助于可回收物进入再利用流程，减少原材料消耗。', source: '来源：住房和城乡建设部垃圾分类资料' },
  { title: '一水多用', body: '按需用水、及时修复漏水设施，是校园生活中容易执行的节水行动。', source: '来源：水利部节约用水公开资料' },
  { title: '先减量，再回收', body: '少买少用、重复利用、分类回收，是更完整的资源利用顺序。', source: '来源：国家发展改革委循环经济公开资料' }
];

@Component
export struct FootprintGamePage {
  onBack?: () => void;
  @State private boardPosition: number = 0;
  @State private balance: number = 0;
  @State private rolling: boolean = false;
  @State private feedback: string = '准备好了吗？用积分走出自己的低碳足迹。';
  @State private lastSteps: number = 0;
  @State private scienceCard: ScienceCard = SCIENCE_CARDS[0];
  @State private showingScience: boolean = true;
  @State private benefitCount: number = 0;
  private pointsService: CarbonPointsService = new CarbonPointsService();

  aboutToAppear(): void {
    this.loadGameState();
  }

  private async loadGameState(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: PointsSnapshot = await this.pointsService.load(context);
      this.boardPosition = snapshot.footprintPosition ?? 0;
      this.balance = snapshot.balance;
      this.benefitCount = (snapshot.footprintBenefitIds ?? []).length;
    } catch (error) {
      this.balance = 0;
    }
  }

  private async roll(): Promise<void> {
    if (this.rolling) {
      return;
    }
    this.rolling = true;
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result: FootprintRollResult = await this.pointsService.rollFootprint(context);
      this.balance = result.balance;
      this.boardPosition = result.position;
      this.lastSteps = result.steps;
      this.feedback = result.success ? `前进 ${result.steps} 格 · ${result.rewardTitle}` : result.message;
      if (result.benefitId.length > 0) {
        this.benefitCount += 1;
        this.showingScience = false;
      } else {
        this.scienceCard = SCIENCE_CARDS[result.position % SCIENCE_CARDS.length];
        this.showingScience = true;
      }
    } catch (error) {
      this.feedback = '暂时无法读取本地积分，请稍后再试。';
    } finally {
      this.rolling = false;
    }
  }

  @Builder
  private Header() {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Text('‹').fontSize(40).fontColor('#174E3A')
      }
      .width(44).height(48).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText('返回我的页面').onClick(() => this.onBack?.())
      Blank()
      Text('低碳足迹').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#123F2E')
      Blank()
      Text('每周一次权益').fontSize(11).fontColor('#718078').width(68).textAlign(TextAlign.End)
    }
    .width('100%').height(64).padding({ left: 14, right: 14 })
  }

  @Builder
  private IntroCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 1 }) {
          Text(this.lastSteps > 0 ? `${this.lastSteps}` : '·')
            .fontSize(29).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Text('步').fontSize(10).fontColor('#E8F5E8')
        }
      }
      .width(64).height(64).backgroundColor('#4C9576').borderRadius(22)
      .shadow({ radius: 10, color: '#4C957640', offsetX: 0, offsetY: 4 })
      Column({ space: 5 }) {
        Text('把每一步走成绿色足迹')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#173F2E')
        Text(this.lastSteps > 0 ? '刚刚完成一次低碳行动' : '消耗积分，随机走出下一站')
          .fontSize(12).fontColor('#718078')
        Text(`本周权益 ${this.benefitCount > 0 ? '已获得' : '待发现'}`)
          .fontSize(11).fontColor('#4C9576')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .width('100%').padding(16)
    .backgroundColor('#E7F2E7').border({ width: 1, color: '#CFE3D0' }).borderRadius(22)
  }

  @Builder
  private StatusCard() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(`${this.balance}`).fontSize(27).fontWeight(FontWeight.Bold).fontColor('#174E3A')
        Text('当前积分').fontSize(12).fontColor('#718078')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Column({ space: 3 }) {
        Text(`${this.boardPosition + 1} / ${FOOTPRINT_CELLS.length}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#4C9576')
        Text('足迹位置').fontSize(12).fontColor('#718078')
      }.alignItems(HorizontalAlign.End)
    }
    .width('100%').padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor('#E7F2E7').border({ width: 1, color: '#CFE3D0' }).borderRadius(18)
  }

  @Builder
  private BoardCell(cell: FootprintCell, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      Image(cell.icon)
        .syncLoad(true)
        .width(cell.kind === 'chance' ? 36 : 40)
        .height(cell.kind === 'chance' ? 36 : 40)
        .opacity(this.boardPosition === index ? 1 : 0.82)
    }
    .width('100%').height(72).layoutWeight(1)
    .backgroundColor(this.boardPosition === index ? '#4C9576' : cell.kind === 'chance' ? '#FFF4DD' : '#EDF5EA')
    .border({ width: this.boardPosition === index ? 2 : 1, color: this.boardPosition === index ? '#2F7052' : '#D9E8D9' })
    .borderRadius(18)
    .shadow(this.boardPosition === index ? { radius: 8, color: '#4C957640', offsetX: 0, offsetY: 3 } : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
  }

  @Builder
  private BoardCenter() {
    Column({ space: 4 }) {
      Text('绿色足迹').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#2F7052')
      Text('5 积分').fontSize(11).fontColor('#718078')
      Text('随机 1—6 步').fontSize(10).fontColor('#89958E')
    }
    .width('100%').height(72).justifyContent(FlexAlign.Center)
    .backgroundColor('#F0F6EE').border({ width: 1, color: '#DDE8DE' }).borderRadius(16)
  }

  @Builder
  private Board() {
    Column({ space: 10 }) {
      Grid() {
        ForEach(FRAME_BOARD_INDEXES, (boardIndex: number, slot: number) => {
          GridItem() {
            if (boardIndex >= 0) {
              this.BoardCell(FOOTPRINT_CELLS[boardIndex], boardIndex)
            } else if (slot === 12) {
              this.BoardCenter()
            } else {
              Stack().width('100%').height(72)
            }
          }
        }, (boardIndex: number, slot: number): string => `${slot}-${boardIndex}`)
      }
      .width('100%').columnsTemplate('1fr 1fr 1fr 1fr 1fr').columnsGap(7).rowsGap(7)
    }
    .width('100%').padding({ left: 16, right: 16, top: 17, bottom: 16 })
    .backgroundColor('#FFFFFF').border({ width: 1, color: '#E2ECE1' }).borderRadius(22)
    .shadow({ radius: 12, color: '#285A3A12', offsetX: 0, offsetY: 3 })
  }

  @Builder
  private FeedbackCard() {
    Column({ space: 7 }) {
      Text(this.feedback).width('100%').fontSize(15).fontColor('#365C4B').lineHeight(23)
      if (this.lastSteps > 0) {
        Text(`本次随机步数：${this.lastSteps} · 每次前进消耗 5 积分`)
          .fontSize(11).fontColor('#89958E').width('100%')
      } else {
        Text('每次前进消耗 5 积分，步数由系统随机生成')
          .fontSize(11).fontColor('#89958E').width('100%')
      }
    }
    .width('100%').padding(15).backgroundColor('#F0F6EE').borderRadius(16)
  }

  @Builder
  private Science() {
    if (this.showingScience) {
      Column({ space: 8 }) {
        Row() {
          Text('低碳知识卡').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#2F7052')
          Blank()
          Text('没有中奖也有收获').fontSize(11).fontColor('#87938C')
        }.width('100%')
        Text(this.scienceCard.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#365C4B').width('100%')
        Text(this.scienceCard.body).fontSize(14).fontColor('#65756B').lineHeight(22).width('100%')
        Text(this.scienceCard.source).fontSize(10).fontColor('#89958E').width('100%')
      }
      .width('100%').padding(15).backgroundColor('#FAFBF6')
      .border({ width: 1, color: '#DDE8DE' }).borderRadius(16)
    }
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 14 }) {
          this.IntroCard()
          this.StatusCard()
          this.Board()
          this.FeedbackCard()
          this.Science()
          Text(`本机已获得 ${this.benefitCount} 次棋盘模拟权益 · 每周最多获得 1 次`)
            .fontSize(11).fontColor('#89958E').width('100%').textAlign(TextAlign.Center)
            .padding({ top: 2, bottom: 8 })
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row({ space: 8 }) {
              Text(this.rolling ? '前进中…' : '前进').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              Text(this.rolling ? '' : '消耗 5 积分').fontSize(12).fontColor('#E7F4E9')
            }
          }
          .width('86%').height(52).backgroundColor('#4C9576').enabled(!this.rolling)
          .shadow({ radius: 12, color: '#4C957650', offsetX: 0, offsetY: 4 })
          .onClick(() => this.roll())
        }
        .width('100%').padding({ bottom: 28 })
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }
    .width('100%').height('100%').backgroundColor('#F7F8F2')
  }
}

@Preview({
  title: 'FootprintGamePage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct FootprintGamePagePreview {
  build() {
    FootprintGamePage()
  }
}
