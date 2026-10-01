/**
 * 足迹数据看板。
 * 采用环形进度、时序柱状图、行为构成条形图与核验概览组合，
 * 支持日、周、月、年四种时间口径；正式汇总只接收已核验记录。
 */
import { RecordDraft } from './RecordDetail';
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 判断当前设备是否具备液态玻璃（沉浸式系统材质）能力
 * 需同时满足：系统软件 API 不低于 26 且设备声明支持沉浸式材质；
 * 短路求值保证低版本系统不会调用 isImmersiveMaterialSupported。
 * @returns true 表示可以使用 ImmersiveMaterial 液态玻璃
 */
function isGlassCapable(): boolean {
  return deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported();
}

/** 时序柱状图的单个数据点（横轴标签 + 减排值） */
interface TrendPoint {
  /** 横轴标签（如 '6时'/'一'/'第1周'/'1月'） */
  label: string;
  /** 该时间点的减排量（kg CO₂e） */
  value: number;
}

/** 行为构成条形图的单个类目（名称、减排值、主题色与图标） */
interface CategoryPoint {
  /** 类目名称（如 '绿色出行'） */
  name: string;
  /** 该类目的减排量（kg CO₂e） */
  value: number;
  /** 条形图主题色 */
  color: string;
  /** 类目图标资源 */
  icon: Resource;
}

/** 单一时间口径下的完整看板数据 */
interface FootprintData {
  /** 累计减排量（kg CO₂e） */
  total: number;
  /** 阶段目标减排量（kg CO₂e） */
  goal: number;
  /** 环比对比文案（如 '较上周多 12%'） */
  comparison: string;
  /** 时序柱状图标题（如 '本周每日减排'） */
  trendTitle: string;
  /** 时序柱状图数据点 */
  trend: TrendPoint[];
  /** 行为构成类目列表 */
  categories: CategoryPoint[];
  /** 已核验记录条数 */
  verifiedCount: number;
  /** 记录总条数 */
  totalCount: number;
  /** 树木吸收量等效文案 */
  treeEquivalent: string;
  /** 少开燃油车等效文案 */
  travelEquivalent: string;
}

/** 时间口径切换选项：日 / 周 / 月 / 年 */
const PERIODS: string[] = ['日', '周', '月', '年'];

/** 日口径静态示例数据：按 6 个时段展示当日减排节奏 */
const DAY_DATA: FootprintData = {
  total: 1.36,
  goal: 2,
  comparison: '较昨日多 18%',
  trendTitle: '今日减排节奏',
  trend: [
    { label: '6时', value: 0.08 }, { label: '9时', value: 0.32 }, { label: '12时', value: 0.18 },
    { label: '15时', value: 0.12 }, { label: '18时', value: 0.46 }, { label: '21时', value: 0.20 }
  ],
  categories: [
    { name: '绿色出行', value: 0.71, color: '#3E8E68', icon: $r('app.media.diary_bike') },
    { name: '低碳饮食', value: 0.28, color: '#D4A24C', icon: $r('app.media.diary_meal') },
    { name: '节能用电', value: 0.22, color: '#4F8FA5', icon: $r('app.media.diary_electricity') },
    { name: '循环利用', value: 0.15, color: '#7A9270', icon: $r('app.media.diary_recycle') }
  ],
  verifiedCount: 4,
  totalCount: 5,
  treeEquivalent: '0.06 棵树一天吸收量',
  travelEquivalent: '少开燃油车约 5.4 km'
};

/** 周口径静态示例数据：周一至周日每日减排 */
const WEEK_DATA: FootprintData = {
  total: 8.64,
  goal: 10,
  comparison: '较上周多 12%',
  trendTitle: '本周每日减排',
  trend: [
    { label: '一', value: 0.82 }, { label: '二', value: 1.15 }, { label: '三', value: 0.94 },
    { label: '四', value: 1.42 }, { label: '五', value: 1.08 }, { label: '六', value: 1.71 },
    { label: '日', value: 1.52 }
  ],
  categories: [
    { name: '绿色出行', value: 4.12, color: '#3E8E68', icon: $r('app.media.diary_transit') },
    { name: '低碳饮食', value: 1.86, color: '#D4A24C', icon: $r('app.media.diary_meal') },
    { name: '节水节电', value: 1.54, color: '#4F8FA5', icon: $r('app.media.diary_water') },
    { name: '循环利用', value: 1.12, color: '#7A9270', icon: $r('app.media.diary_reuse') }
  ],
  verifiedCount: 19,
  totalCount: 22,
  treeEquivalent: '0.39 棵树一月吸收量',
  travelEquivalent: '少开燃油车约 34.6 km'
};

/** 月口径静态示例数据：按周汇总本月减排 */
const MONTH_DATA: FootprintData = {
  total: 34.72,
  goal: 40,
  comparison: '较上月多 9%',
  trendTitle: '本月每周减排',
  trend: [
    { label: '第1周', value: 7.12 }, { label: '第2周', value: 8.64 },
    { label: '第3周', value: 10.28 }, { label: '第4周', value: 8.68 }
  ],
  categories: [
    { name: '绿色出行', value: 17.26, color: '#3E8E68', icon: $r('app.media.diary_bike') },
    { name: '低碳饮食', value: 7.34, color: '#D4A24C', icon: $r('app.media.diary_meal') },
    { name: '节水节电', value: 6.18, color: '#4F8FA5', icon: $r('app.media.diary_electricity') },
    { name: '循环利用', value: 3.94, color: '#7A9270', icon: $r('app.media.diary_recycle') }
  ],
  verifiedCount: 73,
  totalCount: 81,
  treeEquivalent: '1.58 棵树一月吸收量',
  travelEquivalent: '少开燃油车约 138.9 km'
};

/** 年口径静态示例数据：按月汇总全年减排 */
const YEAR_DATA: FootprintData = {
  total: 386.40,
  goal: 480,
  comparison: '较去年同期多 21%',
  trendTitle: '年度减排趋势',
  trend: [
    { label: '1月', value: 24.2 }, { label: '2月', value: 27.5 }, { label: '3月', value: 31.8 },
    { label: '4月', value: 29.4 }, { label: '5月', value: 34.7 }, { label: '6月', value: 38.1 },
    { label: '7月', value: 36.8 }, { label: '8月', value: 33.2 }, { label: '9月', value: 42.6 },
    { label: '10月', value: 35.9 }, { label: '11月', value: 28.4 }, { label: '12月', value: 23.8 }
  ],
  categories: [
    { name: '绿色出行', value: 196.80, color: '#3E8E68', icon: $r('app.media.diary_transit') },
    { name: '低碳饮食', value: 76.42, color: '#D4A24C', icon: $r('app.media.diary_meal') },
    { name: '节水节电', value: 69.36, color: '#4F8FA5', icon: $r('app.media.diary_water') },
    { name: '循环利用', value: 43.82, color: '#7A9270', icon: $r('app.media.diary_reuse') }
  ],
  verifiedCount: 786,
  totalCount: 842,
  treeEquivalent: '17.56 棵树一年吸收量',
  travelEquivalent: '少开燃油车约 1545.6 km'
};

/**
 * 足迹看板组件
 * 页面结构：标题栏 + 时间口径切换 + 减排概览（环形进度） + 时序柱状图 + 行为构成 + 核验与等效 + 底部导航。
 * 看板基线为静态示例数据，当前会话中已核验的新记录会实时叠加进汇总。
 */
@Component
export struct FootprintPage {
  /** 入口容器传入的当前栏目，保证跨页切换后只有当前栏目高亮。 */
  @Prop selectedTab: string = '足迹';
  /** 从入口页传入的真实保存记录：已核验部分实时叠加到看板汇总 */
  @Prop savedDrafts: RecordDraft[] = [];
  /** 切换底部栏目回调：参数为目标栏目名，由入口页完成页面切换 */
  onNavigate?: (tab: string) => void;
  /** 当前选中的时间口径：'日'/'周'/'月'/'年'，默认周 */
  @State private selectedPeriod: string = '周';
  /** 当前按下的底部栏目，用于提供与日记页一致的轻微按压反馈。 */
  @State private pressedTab: string = '';
  /** 底部导航条的液态玻璃材质：薄样式 + 低不透明度淡绿赋色；不具备能力的设备为 undefined */
  private navBarMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#59E6EEDF'
    })
    : undefined;

  /**
   * 当前时间口径对应的看板数据
   * @returns 当前时间口径下的本地真实记录聚合（日/月/年，默认周）
   */
  private data(): FootprintData {
    const now: Date = new Date();
    const start: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (this.selectedPeriod === '周') {
      const day: number = start.getDay() === 0 ? 7 : start.getDay();
      start.setDate(start.getDate() - day + 1);
    } else if (this.selectedPeriod === '月') {
      start.setDate(1);
    } else if (this.selectedPeriod === '年') {
      start.setMonth(0, 1);
    }
    const end: Date = new Date(start.getTime());
    if (this.selectedPeriod === '日') {
      end.setDate(end.getDate() + 1);
    } else if (this.selectedPeriod === '周') {
      end.setDate(end.getDate() + 7);
    } else if (this.selectedPeriod === '月') {
      end.setMonth(end.getMonth() + 1);
    } else {
      end.setFullYear(end.getFullYear() + 1);
    }
    const allInPeriod: RecordDraft[] = this.savedDrafts.filter((draft: RecordDraft): boolean => {
      const time: number = draft.recordedAt ?? draft.createdAt ?? 0;
      return time >= start.getTime() && time < end.getTime();
    });
    const verified: RecordDraft[] = allInPeriod.filter((draft: RecordDraft): boolean => {
      return draft.verificationStatus === 'verified' && draft.scoreEnabled;
    });
    const total: number = verified.reduce((sum: number, draft: RecordDraft): number => sum + draft.reductionKg, 0);
    const goal: number = this.selectedPeriod === '日' ? 2 : this.selectedPeriod === '周' ? 10 :
      this.selectedPeriod === '月' ? 40 : 480;
    return {
      total: total, goal: goal,
      comparison: verified.length === 0 ? '暂无已核验记录' : '基于本地已核验记录动态计算',
      trendTitle: this.selectedPeriod === '日' ? '今日减排节奏' :
        this.selectedPeriod === '周' ? '本周每日减排' : this.selectedPeriod === '月' ? '本月每周减排' : '年度减排趋势',
      trend: this.buildTrend(verified), categories: this.buildCategories(verified),
      verifiedCount: verified.length, totalCount: allInPeriod.length,
      treeEquivalent: `${(total / 22).toFixed(2)} 棵树吸收量（估算）`,
      travelEquivalent: `少开燃油车约 ${(total / 0.175).toFixed(1)} km（估算）`
    };
  }

  /**
   * 按时间口径把已核验记录聚合为时序柱状图数据点
   * 日按 6 个时段、周按 7 天、月按 4 周、年按 12 个月分桶累计减排量
   * @param records 当前时间口径内的已核验记录
   * @returns 时序柱状图数据点数组
   */
  private buildTrend(records: RecordDraft[]): TrendPoint[] {
    const count: number = this.selectedPeriod === '日' ? 6 : this.selectedPeriod === '周' ? 7 :
      this.selectedPeriod === '月' ? 4 : 12;
    const values: number[] = new Array<number>(count).fill(0);
    records.forEach((draft: RecordDraft): void => {
      const date: Date = new Date(draft.recordedAt ?? draft.createdAt ?? 0);
      let index: number = 0;
      if (this.selectedPeriod === '日') {
        index = Math.min(count - 1, Math.floor((date.getHours() / 24) * count));
      } else if (this.selectedPeriod === '周') {
        index = date.getDay() === 0 ? 6 : date.getDay() - 1;
      } else if (this.selectedPeriod === '月') {
        index = Math.min(count - 1, Math.floor((date.getDate() - 1) / 7));
      } else {
        index = date.getMonth();
      }
      values[index] += draft.reductionKg;
    });
    const labels: string[] = this.selectedPeriod === '日' ? ['6时', '9时', '12时', '15时', '18时', '21时'] :
      this.selectedPeriod === '周' ? ['一', '二', '三', '四', '五', '六', '日'] :
        this.selectedPeriod === '月' ? ['第1周', '第2周', '第3周', '第4周'] :
          ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    return labels.map((label: string, index: number): TrendPoint => ({ label: label, value: values[index] }));
  }

  /**
   * 把已核验记录按行为归入绿色出行/低碳饮食/节水节电/循环利用四类
   * 减排量为 0 的类目不展示
   * @param records 当前时间口径内的已核验记录
   * @returns 行为构成类目列表
   */
  private buildCategories(records: RecordDraft[]): CategoryPoint[] {
    const groups: CategoryPoint[] = [
      { name: '绿色出行', value: 0, color: '#3E8E68', icon: $r('app.media.diary_bike') },
      { name: '低碳饮食', value: 0, color: '#D4A24C', icon: $r('app.media.diary_meal') },
      { name: '节水节电', value: 0, color: '#4F8FA5', icon: $r('app.media.diary_water') },
      { name: '循环利用', value: 0, color: '#7A9270', icon: $r('app.media.diary_reuse') }
    ];
    records.forEach((draft: RecordDraft): void => {
      const id: string = draft.behavior.id;
      const index: number = ['walk', 'bike', 'transit', 'carpool', 'metro'].includes(id) ? 0 :
        ['meal', 'lowCarbonMeal'].includes(id) ? 1 :
          ['electricity', 'water', 'standby', 'shower'].includes(id) ? 2 : 3;
      groups[index].value += draft.reductionKg;
    });
    return groups.filter((item: CategoryPoint): boolean => item.value > 0);
  }

  /** 当前会话中新建且通过系统核验的记录才进入正式减排量。 */
  private verifiedDraftTotal(): number {
    return this.data().total;
  }

  /**
   * 累计减排量：当前时间口径下已核验真实记录之和
   * @returns 累计减排量（kg CO₂e）
   */
  private totalReduction(): number {
    return this.data().total;
  }

  /**
   * 目标完成百分比（环形进度值）
   * @returns 0–100 的整数百分比
   */
  private goalPercent(): number {
    return Math.min(100, this.totalReduction() / this.data().goal * 100);
  }

  /**
   * 系统核验率（核验概览环的值）
   * @returns 已核验记录占总记录的百分比
   */
  private verifiedPercent(): number {
    if (this.totalRecordCount() === 0) {
      return 0;
    }
    return this.verifiedRecordCount() / this.totalRecordCount() * 100;
  }

  /**
   * 已核验记录条数：当前时间口径下已核验真实记录
   * @returns 已核验记录条数
   */
  private verifiedRecordCount(): number {
    return this.data().verifiedCount;
  }

  /**
   * 记录总条数：当前时间口径下全部本地记录
   * @returns 记录总条数
   */
  private totalRecordCount(): number {
    return this.data().totalCount;
  }

  /**
   * 时序柱状图的最大值
   * 用于柱高归一化；保底 1 防止除零
   * @returns 数据点中的最大减排值
   */
  private maxTrendValue(): number {
    let maximum: number = 1;
    this.data().trend.forEach((point: TrendPoint): void => {
      maximum = Math.max(maximum, point.value);
    });
    return maximum;
  }

  /**
   * 行为构成类目的减排总量
   * 用于各类目占比计算
   * @returns 全部类目减排量之和
   */
  private categoryTotal(): number {
    let total: number = 0;
    this.data().categories.forEach((item: CategoryPoint): void => {
      total += item.value;
    });
    return total;
  }

  /**
   * 单个行为类目的占比百分比
   * @param item 行为类目
   * @returns 该类目占总量的百分比（总量为 0 时返回 0）
   */
  private categoryPercent(item: CategoryPoint): number {
    return this.categoryTotal() === 0 ? 0 : item.value / this.categoryTotal() * 100;
  }

  /**
   * 切换底部栏目
   * 点击当前栏目仅保留按压反馈；切换其他栏目时先播放短暂按压动效再回调入口页
   * @param tab 目标栏目名
   */
  private navigate(tab: string): void {
    // 当前栏目也保留一次轻微反馈，行为与日记页一致。
    this.pressedTab = tab;
    if (tab === this.selectedTab) {
      setTimeout(() => {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
      }, 120);
      return;
    }
    if (this.onNavigate) {
      // 保留短暂按压反馈，再切换页面，保证跨页点击也能看到动效。
      setTimeout(() => {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
        this.onNavigate?.(tab);
      }, 120);
    }
  }

  /**
   * 标题栏：左侧"足迹"标题与副标题 + 右侧"数据已更新"状态徽标
   */
  @Builder
  private Header() {
    Row() {
      // 左侧：标题与副标题
      Column({ space: 3 }) {
        Text('足迹')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
        Text('已核验的低碳成果')
          .fontSize(13)
          .fontColor('#718078')
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      // 右侧：数据更新状态徽标（绿点 + 文案）
      Row({ space: 6 }) {
        Row().width(7).height(7).borderRadius(4).backgroundColor('#4C9576')
        Text('数据已更新')
          .fontSize(12)
          .fontColor('#567064')
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#EAF3E7')
      .borderRadius(16)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 12, bottom: 14 })
  }

  /**
   * 时间口径切换器
   * 日/周/月/年 四段式胶囊按钮组：选中项深绿底白字
   */
  @Builder
  private PeriodSelector() {
    Row() {
      ForEach(PERIODS, (period: string) => {
        Button(period, { type: ButtonType.Normal, stateEffect: false })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontWeight(this.selectedPeriod === period ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedPeriod === period ? '#FFFFFF' : '#617268')
          .backgroundColor(this.selectedPeriod === period ? '#3E8061' : Color.Transparent)
          .borderRadius(19)
          .onClick((): void => {
            this.selectedPeriod = period;
          })
      }, (period: string): string => period)
    }
    .width('100%')
    .height(44)
    .padding(3)
    .backgroundColor('#E9EFE7')
    .borderRadius(22)
    .margin({ left: 22, right: 22, bottom: 18 })
  }

  /**
   * 减排概览卡片
   * 左侧目标完成环形进度 + 右侧累计减排数值、环比与阶段目标
   */
  @Builder
  private Summary() {
    Row({ space: 18 }) {
      // 左侧：目标完成度环形进度，中心显示百分比
      Stack({ alignContent: Alignment.Center }) {
        Progress({ value: this.goalPercent(), total: 100, type: ProgressType.Ring })
          .width(112)
          .height(112)
          .color('#3E8E68')
          .backgroundColor('#DCE8DC')
          .style({ strokeWidth: 9 })
        Column({ space: 2 }) {
          Text(`${Math.round(this.goalPercent())}%`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E5940')
          Text('目标')
            .fontSize(12)
            .fontColor('#718078')
        }
      }
      // 右侧：累计减排数值、环比对比与阶段目标
      Column({ space: 8 }) {
        Text('累计减排')
          .fontSize(14)
          .fontColor('#718078')
        Row({ space: 6 }) {
          Text(this.totalReduction().toFixed(2))
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
          Text('kg CO₂e')
            .fontSize(13)
            .fontColor('#567064')
            .margin({ top: 14 })
        }
        Text(this.data().comparison)
          .fontSize(13)
          .fontColor('#3E8061')
        Text(`阶段目标 ${this.data().goal.toFixed(0)} kg`)
          .fontSize(12)
          .fontColor('#8A968F')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 20, bottom: 20 })
    .backgroundColor('#EDF4EA')
  }

  /**
   * 时序柱状图
   * 标题行 + 柱状数据点：柱高按最大值归一化（保底 12vp），末柱以金色高亮
   */
  @Builder
  private TrendChart() {
    Column({ space: 14 }) {
      // 标题行：图表标题 + 单位说明
      Row() {
        Text(this.data().trendTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text('kg CO₂e')
          .fontSize(12)
          .fontColor('#87938C')
      }
      .width('100%')

      // 柱状数据点行：底部对齐，数据点多时缩小字号
      Row({ space: 5 }) {
        ForEach(this.data().trend, (point: TrendPoint, index: number) => {
          Column({ space: 7 }) {
            // 柱顶数值：≥10 取整，否则保留 1 位小数
            Text(point.value.toFixed(point.value >= 10 ? 0 : 1))
              .fontSize(this.data().trend.length > 8 ? 9 : 11)
              .fontColor('#567064')
              .maxLines(1)
            // 柱体：高度按最大值归一化，末柱金色高亮
            Column() {
              Blank()
              Row()
                .width('72%')
                .height(Math.max(12, point.value / this.maxTrendValue() * 92))
                .backgroundColor(index === this.data().trend.length - 1 ? '#D4A24C' : '#4C9576')
                .borderRadius({ topLeft: 5, topRight: 5 })
            }
            .width('100%')
            .height(96)
            .justifyContent(FlexAlign.End)
            // 横轴标签
            Text(point.label)
              .fontSize(this.data().trend.length > 8 ? 9 : 11)
              .fontColor('#75837A')
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (point: TrendPoint, index: number): string => `${point.label}-${index}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .border({ width: { bottom: 0.5 }, color: '#DBE2D8' })
  }

  /**
   * 行为构成条形图
   * 每个类目一行：图标 + 名称/数值 + 双层进度条（浅底 + 类目色填充）
   */
  @Builder
  private CategoryChart() {
    Column({ space: 17 }) {
      // 标题行：图表标题 + 排序说明
      Row() {
        Text('减排行为构成')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text('按贡献排序')
          .fontSize(12)
          .fontColor('#87938C')
      }
      .width('100%')

      // 类目行：图标 + 名称/数值行 + 占比进度条
      ForEach(this.data().categories, (item: CategoryPoint) => {
        Row({ space: 11 }) {
          // 左侧类目图标（圆角浅绿底）
          Image(item.icon)
            .syncLoad(true)
            .width(31)
            .height(31)
            .padding(4)
            .backgroundColor('#EDF2E9')
            .borderRadius(16)
          Column({ space: 7 }) {
            // 名称与"数值 · 占比"同行展示
            Row() {
              Text(item.name)
                .fontSize(14)
                .fontColor('#365C4B')
              Blank()
              Text(`${item.value.toFixed(2)} kg · ${Math.round(this.categoryPercent(item))}%`)
                .fontSize(12)
                .fontColor('#718078')
            }
            .width('100%')
            // 占比进度条：浅底轨道 + 类目色填充（保底 5% 保证可见）
            Stack({ alignContent: Alignment.Start }) {
              Row().width('100%').height(7).backgroundColor('#E4EAE2').borderRadius(4)
              Row()
                .width(`${Math.max(5, this.categoryPercent(item))}%`)
                .height(7)
                .backgroundColor(item.color)
                .borderRadius(4)
            }
            .width('100%')
            .height(7)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }, (item: CategoryPoint): string => item.name)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .border({ width: { bottom: 0.5 }, color: '#DBE2D8' })
  }

  /**
   * 核验与低碳等效区
   * 系统核验率环形进度 + 说明，以及树木吸收/少开燃油车两个等效卡片
   */
  @Builder
  private VerificationAndImpact() {
    Column({ space: 18 }) {
      // 区块标题
      Text('核验与低碳等效')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#173F2E')
      // 左：核验率环形进度；右：核验说明
      Row({ space: 16 }) {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: this.verifiedPercent(), total: 100, type: ProgressType.Ring })
            .width(76)
            .height(76)
            .color('#4F8FA5')
            .backgroundColor('#DDE8E9')
            .style({ strokeWidth: 7 })
          Text(`${Math.round(this.verifiedPercent())}%`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#356D7E')
        }
        Column({ space: 5 }) {
          Text('系统核验率')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#365C4B')
          Text(`${this.verifiedRecordCount()} 条已核验 / ${this.totalRecordCount()} 条记录`)
            .fontSize(12)
            .fontColor('#718078')
          Text('待核实记录不计入正式减排')
            .fontSize(12)
            .fontColor('#9A7A3C')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 等效卡片：树木吸收量 + 少开燃油车
      Row({ space: 12 }) {
        // 树木吸收量等效卡片
        Row({ space: 10 }) {
          Image($r('app.media.diary_sprout')).syncLoad(true).width(30).height(30)
          Text(this.data().treeEquivalent)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor('#476554')
            .maxLines(2)
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor('#EDF4EA')
        .borderRadius(10)
        // 少开燃油车等效卡片
        Row({ space: 10 }) {
          Image($r('app.media.diary_transit')).syncLoad(true).width(30).height(30)
          Text(this.data().travelEquivalent)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor('#476554')
            .maxLines(2)
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor('#EEF2EE')
        .borderRadius(10)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 190 })
  }

  /**
   * 底部导航条的单个栏目项
   * 与首页 TabItem 一致：选中态淡绿底托 + 按压缩放与提亮反馈
   * @param label 栏目名称
   * @param icon 栏目图标资源
   */
  @Builder
  private NavItem(label: string, icon: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 5 }) {
        // 栏目图标
        Image(icon).syncLoad(true).width(26).height(26)
        // 栏目名称：选中态森林绿加粗
        Text(label)
          .fontSize(12)
          .fontColor(this.selectedTab === label ? '#245C40' : '#8B968E')
          .fontWeight(this.selectedTab === label ? FontWeight.Medium : FontWeight.Normal)
      }
      .width('100%')
      // 底托内边距与颜色：仅选中项显示淡绿底托，按压时提亮
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(this.selectedTab === label
        ? (this.pressedTab === label ? '#CCDCEDE4' : '#B3D2E7D7')
        : (this.pressedTab === label ? '#26FFFFFF' : Color.Transparent))
      .borderRadius(18)
      .animation({ duration: 180, curve: Curve.Friction })
    }
    .layoutWeight(1)
    .height(68)
    .padding(0)
    .backgroundColor(Color.Transparent)
    // 按压缩放：轻微缩小，松开恢复
    .scale({
      x: this.pressedTab === label ? 0.94 : 1,
      y: this.pressedTab === label ? 0.94 : 1
    })
    .animation({ duration: 180, curve: Curve.Friction })
    .accessibilityText(this.selectedTab === label ? `${label}，当前栏目` : label)
    .onClick((): void => this.navigate(label))
    // 跟踪按压状态：按下记录栏目名，抬起/取消时清除
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedTab = label;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedTab === label) {
          this.pressedTab = '';
        }
      }
    })
  }

  /**
   * 底部四栏导航条
   * 磨砂兜底层（半透明浅绿 + 材质模糊 + 细高光描边 + 柔和阴影）+ 液态玻璃升级层
   */
  @Builder
  private BottomControls() {
    Column({ space: 0 }) {
      Row() {
        this.NavItem('日记', $r('app.media.diary_diary'))
        this.NavItem('足迹', $r('app.media.diary_leaf'))
        this.NavItem('成长', $r('app.media.diary_sprout'))
        this.NavItem('我的', $r('app.media.diary_person'))
      }
      .width('100%')
      .height(76)
      .padding({ left: 6, right: 6 })
      // 浅绿半透明底色叠在材质模糊之上
      .backgroundColor('#B8E6EEDF')
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: '#59FFFFFF' })
      .borderRadius(28)
      .shadow({ radius: 16, color: '#09304F35', offsetX: 0, offsetY: 3 })
      // 液态玻璃层：具备能力的设备上接管背景/描边/阴影
      .systemMaterial(this.navBarMaterial)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
    // 空白区域不拦截列表滑动
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * 页面布局
   * Stack 底部对齐：底层为可滚动的看板内容，上层为底部导航条
   */
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底层：看板内容，自上而下依次为各数据区块
      Scroll() {
        Column() {
          this.Header()
          this.PeriodSelector()
          this.Summary()
          this.TrendChart()
          this.CategoryChart()
          this.VerificationAndImpact()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 上层：底部导航条
      this.BottomControls()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
    // 将底部液态玻璃导航的绘制范围延伸到系统手势区，避免导航条与退出手势栏之间出现突兀空白。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

/**
 * 足迹页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 FootprintPage 组件，不参与实际页面路由
 */
@Preview({
  title: 'FootprintPage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct FootprintPagePreview {
  build() {
    // 直接渲染足迹看板组件
    FootprintPage()
  }
}
