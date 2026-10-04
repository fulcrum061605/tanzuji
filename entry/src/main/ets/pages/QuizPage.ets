/**
 * 低碳知识答题页。
 * 题库随 HAP 内置，断网可用；答题积分由 CarbonPointsService 按天结算。
 */
import { common } from '@kit.AbilityKit';
import { CarbonPointsService, PointsActionResult } from '../services/CarbonPointsService';

interface QuizQuestion {
  id: string;
  title: string;
  options: string[];
  answer: number;
  explanation: string;
  source: string;
}

const QUIZ_QUESTIONS: QuizQuestion[] = [
  {
    id: 'carbon-peak', title: '“碳达峰”指的是什么？',
    options: ['二氧化碳排放量达到历史最高后进入下降阶段', '完全停止排放二氧化碳', '所有能源都改用电力', '每天减少一次塑料袋'],
    answer: 0, explanation: '碳达峰是排放量达到峰值后逐步下降，和碳中和不是同一个概念。', source: '国务院《2030年前碳达峰行动方案》'
  },
  {
    id: 'carbon-neutral', title: '“碳中和”更准确的含义是？',
    options: ['不再使用任何能源', '温室气体排放与吸收、清除相抵消', '只种树不减少排放', '只统计交通产生的排放'],
    answer: 1, explanation: '碳中和强调排放与吸收、清除之间达到平衡。', source: '生态环境部公开科普资料'
  },
  {
    id: 'travel-choice', title: '短距离校园出行更低碳的选择通常是？',
    options: ['步行或骑行', '单人驾车', '长时间原地等待', '专门绕远路乘车'],
    answer: 0, explanation: '在安全和时间允许时，步行、骑行不直接消耗燃油，更适合短距离出行。', source: '生态环境部绿色生活方式科普'
  },
  {
    id: 'public-transit', title: '公共交通的低碳价值主要来自？',
    options: ['让每个人都拥有一辆车', '多人共享一次出行的能源消耗', '延长通勤距离', '增加空驶里程'],
    answer: 1, explanation: '公共交通通过多人共享运力，通常可以降低人均出行排放。', source: '交通运输部绿色出行公开资料'
  },
  {
    id: 'standby', title: '减少待机能耗的正确做法是？',
    options: ['设备不用时关闭电源或拔掉插头', '把所有设备一直开着', '只调高屏幕亮度', '反复开关正在运行的设备'],
    answer: 0, explanation: '长期不用的设备关闭电源，可以减少待机状态下的持续耗电。', source: '国家发展改革委节能宣传资料'
  },
  {
    id: 'food-waste', title: '光盘行动为什么与低碳有关？',
    options: ['食物生产、运输和烹饪都需要资源和能源', '吃得越多越节能', '只与餐具颜色有关', '只影响个人口味'],
    answer: 0, explanation: '减少食物浪费，也能减少生产、运输、冷藏和处理过程中不必要的资源消耗。', source: '国家市场监督管理总局反食品浪费资料'
  },
  {
    id: 'recycle', title: '垃圾分类和回收的直接作用是？',
    options: ['让所有垃圾消失', '提高可回收物的再利用效率', '让垃圾变得更多', '代替所有节能行为'],
    answer: 1, explanation: '准确分类有助于可回收物进入再利用流程，减少原材料和处理资源消耗。', source: '住房和城乡建设部生活垃圾分类资料'
  },
  {
    id: 'water-saving', title: '下面哪项属于节约用水？',
    options: ['及时修复漏水设施', '长时间开着水龙头', '把清水直接倒掉', '反复冲洗不需要清洗的物品'],
    answer: 0, explanation: '修复漏水和按需用水是生活中容易执行的节水行为。', source: '水利部节约用水公开资料'
  },
  {
    id: 'reusable', title: '自带水杯或购物袋的主要意义是？',
    options: ['减少一次性用品的使用', '增加一次性用品消耗', '让物品只能使用一次', '只为了改变颜色'],
    answer: 0, explanation: '重复使用可以减少一次性用品的生产、运输和废弃处理需求。', source: '生态环境部绿色生活创建行动资料'
  },
  {
    id: 'low-carbon-order', title: '更合理的低碳行动顺序是？',
    options: ['少买少用、重复利用、分类回收', '先购买再全部丢弃', '只回收不减少浪费', '只追求包装数量'],
    answer: 0, explanation: '减少源头消费、延长物品寿命、最后分类回收，是更完整的资源利用思路。', source: '国家发展改革委循环经济公开资料'
  },
  {
    id: 'renewable', title: '下列哪项属于可再生能源？',
    options: ['太阳能', '煤炭', '石油', '天然气'],
    answer: 0, explanation: '太阳能来自持续的自然过程；煤炭、石油和天然气属于化石能源。', source: '国家能源局可再生能源公开资料'
  },
  {
    id: 'paper-saving', title: '校园中减少纸张浪费的做法是？',
    options: ['双面打印并按需打印', '不看内容就整本打印', '只打印空白页', '打印后立即丢弃'],
    answer: 0, explanation: '双面使用和按需打印可以减少纸张消耗，也减少印刷和运输资源。', source: '教育部绿色校园公开倡议'
  }
];

const CORRECT_FEEDBACK: string[] = [
  '答得漂亮，绿色行动又前进一步。',
  '这一题稳了，低碳知识已成功解锁。',
  '判断准确，环保大侠继续出发。',
  '漂亮，这个知识点掌握得很扎实。',
  '答对了，为你的低碳判断力点赞。',
  '眼光很好，这正是更可持续的选择。'
];

type QuizPhase = 'answering' | 'correctWait' | 'wrongPause' | 'result';

@Component
export struct QuizPage {
  onBack?: () => void;
  @State private questions: QuizQuestion[] = QUIZ_QUESTIONS.slice(0, 10);
  @State private currentIndex: number = 0;
  @State private selectedIndex: number = -1;
  @State private correctCount: number = 0;
  @State private phase: QuizPhase = 'answering';
  @State private feedback: string = '';
  @State private earnedPoints: number = 0;
  @State private resultMessage: string = '';
  @State private submitting: boolean = false;
  private timerId: number = -1;
  private pointsService: CarbonPointsService = new CarbonPointsService();

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private currentQuestion(): QuizQuestion {
    return this.questions[this.currentIndex];
  }

  private choose(index: number): void {
    if (this.phase !== 'answering') {
      return;
    }
    this.selectedIndex = index;
    const question: QuizQuestion = this.currentQuestion();
    if (index === question.answer) {
      this.correctCount += 1;
      this.phase = 'correctWait';
      this.feedback = CORRECT_FEEDBACK[this.currentIndex % CORRECT_FEEDBACK.length];
      this.timerId = setTimeout(() => {
        this.nextQuestion();
      }, 1800);
    } else {
      this.phase = 'wrongPause';
      this.feedback = '胜败乃兵家常事，大侠请重新来过';
    }
  }

  private nextQuestion(): void {
    if (this.currentIndex >= this.questions.length - 1) {
      this.finishQuiz();
      return;
    }
    this.currentIndex += 1;
    this.selectedIndex = -1;
    this.feedback = '';
    this.phase = 'answering';
  }

  private async finishQuiz(): Promise<void> {
    this.phase = 'result';
    this.submitting = true;
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result: PointsActionResult = await this.pointsService.rewardQuiz(context, this.correctCount);
      this.earnedPoints = result.points;
      this.resultMessage = result.message;
    } catch (error) {
      this.earnedPoints = 0;
      this.resultMessage = '答题已完成，积分稍后同步';
    } finally {
      this.submitting = false;
    }
  }

  private resultTitle(): string {
    if (this.correctCount === 10) {
      return '满分收官，今天的低碳知识状态非常好。';
    }
    if (this.correctCount >= 8) {
      return '表现很棒，再补几个知识点就更完整了。';
    }
    if (this.correctCount >= 6) {
      return '基础已经不错，继续积累会越来越稳。';
    }
    return '今天先熟悉知识，看看解析后再来挑战。';
  }

  @Builder
  private Header() {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Text('‹').fontSize(40).fontColor('#174E3A')
      }
      .width(44).height(48).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText('返回我的页面')
      .onClick(() => this.onBack?.())
      Blank()
      Text('低碳答题').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#123F2E')
      Blank()
      Text(this.phase === 'result' ? '' : `${this.currentIndex + 1}/10`)
        .fontSize(14).fontColor('#718078').width(44).textAlign(TextAlign.Center)
    }
    .width('100%').height(64).padding({ left: 14, right: 14 })
  }

  @Builder
  private OptionBubble(option: string, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Text(option)
        .width('100%')
        .fontSize(17)
        .lineHeight(24)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .fontColor(this.phase !== 'answering' && this.currentQuestion().answer === index
          ? '#FFFFFF' : this.phase === 'wrongPause' && this.selectedIndex === index
          ? '#9A5B5B' : '#365C4B')
    }
      .width('100%')
      .height(76)
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .backgroundColor(this.phase !== 'answering' && this.currentQuestion().answer === index
        ? '#4C9576' : this.phase === 'wrongPause' && this.selectedIndex === index
        ? '#F4DEDE' : '#EAF3E7')
      .border({ width: this.selectedIndex === index || (this.phase !== 'answering' && this.currentQuestion().answer === index) ? 2 : 1,
        color: this.phase !== 'answering' && this.currentQuestion().answer === index
          ? '#4C9576' : this.phase === 'wrongPause' && this.selectedIndex === index ? '#D99B9B' : '#D8E7D8' })
      .borderRadius(28)
      .enabled(this.phase === 'answering')
      .accessibilityText(option)
      .onClick(() => this.choose(index))
  }

  @Builder
  private QuestionContent() {
    Scroll() {
      Column({ space: 18 }) {
        Text(`第 ${this.currentIndex + 1} 题`)
          .fontSize(14).fontColor('#5C806D').alignSelf(ItemAlign.Start)
        Text(this.currentQuestion().title)
          .width('100%').fontSize(25).fontWeight(FontWeight.Bold)
          .fontColor('#123F2E').lineHeight(36)
        Column({ space: 12 }) {
          ForEach(this.currentQuestion().options, (option: string, index: number) => {
            this.OptionBubble(option, index)
          }, (option: string, index: number): string => `${this.currentQuestion().id}-${index}-${option}`)
        }.width('100%')
        if (this.phase === 'correctWait' || this.phase === 'wrongPause') {
          Column({ space: 8 }) {
            Text(this.feedback).fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor(this.phase === 'correctWait' ? '#2F7A57' : '#8B5555')
            Text(this.currentQuestion().explanation).width('100%').fontSize(15).fontColor('#5E7468').lineHeight(23)
            Text(`来源：${this.currentQuestion().source}`).width('100%').fontSize(11).fontColor('#89958E')
            if (this.phase === 'wrongPause') {
              Button('继续答题', { type: ButtonType.Capsule, stateEffect: true })
                .width('100%').height(44).fontSize(16).fontColor('#FFFFFF')
                .backgroundColor('#4C9576').onClick(() => this.nextQuestion())
            }
          }
          .width('100%').padding(16).backgroundColor('#F0F6EE').borderRadius(16)
        }
      }
      .width('100%').padding({ left: 24, right: 24, top: 18, bottom: 32 })
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private ResultContent() {
    Column({ space: 18 }) {
      Image($r('app.media.diary_sprout')).syncLoad(true).width(64).height(64)
      Text('本次答题完成').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#123F2E')
      Text(`${this.correctCount} / ${this.questions.length}`).fontSize(42).fontWeight(FontWeight.Bold).fontColor('#4C9576')
      Text(this.resultTitle()).fontSize(16).fontColor('#5E7468').textAlign(TextAlign.Center)
      Text(this.submitting ? '正在保存答题结果…' : `${this.resultMessage}，今日答题最高 4 分`)
        .fontSize(14).fontColor('#718078').textAlign(TextAlign.Center)
      Button('返回我的', { type: ButtonType.Capsule, stateEffect: true })
        .width('100%').height(48).fontSize(17).fontColor('#FFFFFF')
        .backgroundColor('#4C9576').onClick(() => this.onBack?.())
    }
    .width('100%').padding({ left: 28, right: 28 }).layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.Header()
      if (this.phase === 'result') {
        this.ResultContent()
      } else {
        this.QuestionContent()
      }
    }
    .width('100%').height('100%').backgroundColor('#F7F8F2')
  }
}

@Preview({
  title: 'QuizPage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct QuizPagePreview {
  build() {
    QuizPage()
  }
}
