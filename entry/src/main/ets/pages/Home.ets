/**
 * 碳记 · 日记首页（2026-09-27 确认稿）
 * 首页同时展示本地持久化记录与明确标注的演示数据；演示数据不进入真实统计。
 * 图片/SVG 全部在 resources/base/media 中，断网也可预览。
 * 小体积本地素材同步加载，确保组件静态预览首帧完整；未来用户照片应改回异步加载。
 * 下一步接入真实数据时替换 diaryEntries 和概览；通过回调连接录入、日期、搜索和其他栏目。
 */

import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { RecordDraft } from './RecordDetail';
import { amountWithUnit } from '../services/CarbonFactorService';

/**
 * 判断当前设备是否具备液态玻璃（沉浸式系统材质）能力
 * 需同时满足：系统软件 API 不低于 26（systemMaterial 属性与 ImmersiveMaterial 类自该版本提供）、
 * 且设备声明支持沉浸式材质；短路求值保证低版本系统不会调用 isImmersiveMaterialSupported。
 * @returns true 表示可以创建并使用 ImmersiveMaterial 液态玻璃
 */
function isGlassCapable(): boolean {
  return deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported();
}

/**
 * 单条日记的数据结构，photo 为可选配图。
 */
interface DiaryEntry {
  /** 记录唯一标识：作为 ForEach 的键，保证列表刷新时 diff 的稳定性 */
  id: string;
  /** 记录时间（如 '08:10'），显示在条目顶部 */
  time: string;
  /** 日记标题 */
  title: string;
  /** 日记正文内容 */
  content: string;
  /** 低碳行为标签（如 '步行 · 1.2 km'），以胶囊样式展示 */
  label: string;
  /** 行为类别图标资源（步行/光盘/骑行等） */
  icon: Resource;
  /** 可选配图资源：存在时以缩略图形式显示在条目右侧 */
  photo?: Resource;
  /** 用户从系统相册选择的图片 URI。 */
  photoUri?: string;
  /** 该条记录的估算减排量，用于首页概览汇总 */
  reductionKg: number;
  /** 记录是否通过定位或华为运动核验。 */
  verificationStatus: 'verified' | 'pending';
  /** 只有已核验记录才计入正式减排汇总。 */
  scoreEnabled: boolean;
  /** 记录时间戳；示例记录没有时间戳。 */
  recordedAt?: number;
}

/**
 * 预览阶段的静态示例数据，与真实减排核算服务分开维护。
 * 三条记录分别覆盖"无配图/无配图/有配图"的展示形态，接入真实数据后整体替换。
 */
const DIARY_EXAMPLES: DiaryEntry[] = [
  // 示例 1：步行上学（无配图）
  {
    id: 'preview-walk',
    time: '08:10',
    title: '今天走路去上课',
    content: '绕过操场，顺便看看早晨的树影。',
    label: '演示 · 步行 · 1.2 km',
    icon: $r('app.media.diary_walk'),
    reductionKg: 0.25,
    verificationStatus: 'verified',
    scoreEnabled: true
  },
  // 示例 2：午餐光盘（无配图）
  {
    id: 'preview-meal',
    time: '12:20',
    title: '午餐刚刚好',
    content: '吃完了，也没有浪费。',
    label: '演示 · 光盘行动',
    icon: $r('app.media.diary_meal'),
    reductionKg: 0.18,
    verificationStatus: 'verified',
    scoreEnabled: true
  },
  // 示例 3：骑行去图书馆（带配图）
  {
    id: 'preview-bike',
    time: '17:40',
    title: '骑车去图书馆',
    content: '晚风很舒服，今天慢一点也很好。',
    label: '演示 · 骑行 · 2.4 km',
    icon: $r('app.media.diary_bike'),
    photo: $r('app.media.diary_campus'),
    reductionKg: 0.83,
    verificationStatus: 'verified',
    scoreEnabled: true
  }
];

/**
 * 日记首页组件
 * 页面结构：顶部栏（日期/日历/搜索/今日概览） + 日记列表 + 底部悬浮操作区（加号与四栏导航）。
 * 页面事件通过回调交给入口管理，日期、搜索、新建与栏目切换均可实际操作。
 */
@Component
export struct Home {
  /** 入口容器传入的当前栏目，切换回首页时用于恢复日记/成长视图。 */
  @Prop initialTab: string = '日记';
  /** 已被用户删除的内置示例记录 id。 */
  @Prop hiddenExampleIds: string[] = [];
  /** 从入口页传入的真实保存记录；每次保存后由 @State 触发首页刷新。 */
  @Prop savedDrafts: RecordDraft[] = [];
  /** 当前日历筛选日期的时间戳。 */
  @Prop selectedDate: number = Date.now();
  /** 点击首页日记条目，由入口页打开对应的详情页。 */
  onOpenDiary?: (id: string) => void;
  /** 新建低碳日记回调：由父组件注入，未注入时点击加号显示占位提示 */
  onAddDiary?: () => void;
  /** 打开日历选择日期回调：由父组件注入，未注入时显示占位提示 */
  onOpenCalendar?: () => void;
  /** 打开日记搜索回调：由父组件注入，未注入时显示占位提示 */
  onSearchDiary?: () => void;
  /** 切换底部栏目回调：参数为目标栏目名（'日记'/'足迹'/'成长'/'我的'） */
  onSelectTab?: (tab: string) => void;
  /** 当前选中栏目：仅当真正完成切换时才更新；未接入栏目点击只提示、不改变选中态 */
  @State private selectedTab: string = '日记';
  /** 当前按下的导航项名称：空串表示无按压；驱动按压缩放与材质提亮反馈 */
  @State private pressedTab: string = '';
  /** 悬浮加号是否处于按压状态：驱动按压缩放与材质提亮反馈 */
  @State private plusPressed: boolean = false;
  /** 宽屏布局标记：平板限制日记内容宽度，手机保持原来的满宽布局。 */
  @State private wideLayout: boolean = false;
  /** 搜索框是否展开：true 时在顶部区域下方显示搜索输入行 */
  @State private searchActive: boolean = false;
  /** 搜索关键字：对日记时间/标题/正文/标签做包含匹配 */
  @State private searchText: string = '';

  /** 组件即将出现：恢复入口传入的选中栏目，并按媒体查询结果判断宽屏布局 */
  aboutToAppear(): void {
    this.selectedTab = this.initialTab;
    // 平板/横向大窗口（宽度 ≥600vp）使用宽屏布局
    this.wideLayout = this.getUIContext().getMediaQuery()
      .matchMediaSync('(width >= 600vp)').matches;
  }

  /**
   * 四栏导航条的液态玻璃材质（沉浸式系统材质）
   * 薄样式（THIN）+ 低不透明度淡绿赋色（约 35%），更通透地透出背后滚动的日记内容；
   * 仅在设备具备液态玻璃能力时创建，其余设备保持 undefined，导航条回落到磨砂兜底样式
   */
  private navBarMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#59E6EEDF'
    })
    : undefined;
  /**
   * 悬浮加号按钮的液态玻璃材质（沉浸式系统材质）
   * 薄样式 + 低不透明度淡绿赋色（约 40%，比导航条稍浓以保持主操作存在感），
   * 并启用交互形变（interactive）与按压光晕（lightEffect），由材质提供"液态"按压反馈；
   * 不具备能力的设备保持 undefined，按钮回落到磨砂兜底样式
   */
  private plusMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#664C8A68',
      interactive: true,
      lightEffect: { color: undefined }
    })
    : undefined;
  /** 日记列表数据源：当前为静态示例数据，接入真实数据后替换 */
  private diaryEntries: DiaryEntry[] = DIARY_EXAMPLES;

  /** 将详情页草稿转换为首页日记条目，最新保存的记录排在最前面。 */
  private combinedEntries(): DiaryEntry[] {
    const saved: DiaryEntry[] = this.savedDrafts.map((draft: RecordDraft, index: number): DiaryEntry => {
      const note: string = draft.note.trim();
      const title: string = note.length > 0 ? note.slice(0, 18) : `${draft.behavior.name}记录`;
      const content: string = note.length > 0
        ? note
        : `完成 ${amountWithUnit(draft.amount, draft.unit)}，继续保持低碳生活。`;
      return {
        id: `saved-${draft.recordId ?? draft.operationId ?? `legacy-${index}`}`,
        time: this.formatTime(draft.recordedAt ?? draft.createdAt ?? Date.now()),
        title: title,
        content: content,
        label: draft.verificationStatus === 'verified'
          ? `${draft.behavior.name} · ${amountWithUnit(draft.amount, draft.unit)} · 已核验`
          : `${draft.behavior.name} · 待核实`,
        icon: draft.behavior.icon,
        photoUri: draft.photoUri,
        reductionKg: draft.reductionKg,
        verificationStatus: draft.verificationStatus,
        scoreEnabled: draft.scoreEnabled && draft.verificationStatus === 'verified',
        recordedAt: draft.recordedAt ?? draft.createdAt
      };
    });
    const visibleExamples: DiaryEntry[] = this.diaryEntries.filter((entry: DiaryEntry): boolean => {
      return !this.hiddenExampleIds.includes(entry.id);
    });
    return [...saved.reverse(), ...visibleExamples];
  }

  /** 首页顶部概览使用当前列表中的真实记录数量与减排量。 */
  private entryCount(): number {
    return this.savedDrafts.filter((draft: RecordDraft): boolean => {
      return this.sameDay(draft.recordedAt ?? draft.createdAt ?? Date.now(), this.selectedDate);
    }).length;
  }

  /**
   * 获取过滤后的日记列表
   * 先合并"已保存草稿（倒序，最新在前） + 未删除的内置示例"，
   * 再按关键字对时间/标题/正文/标签做包含匹配
   * @returns 符合搜索条件的日记条目数组
   */
  private filteredEntries(): DiaryEntry[] {
    // 去除关键字首尾空白与内部空格，避免误过滤
    const keyword: string = this.searchText.trim().toLowerCase().replace(/\s/g, '');
    const dateEntries: DiaryEntry[] = this.combinedEntries().filter((entry: DiaryEntry): boolean => {
      // 没有时间戳的内置演示记录只在今天显示，避免切换历史日期时混入示例。
      return entry.recordedAt === undefined
        ? this.sameDay(Date.now(), this.selectedDate)
        : this.sameDay(entry.recordedAt, this.selectedDate);
    });
    // 关键字为空：返回当前日期的记录
    if (keyword.length === 0) {
      return dateEntries;
    }
    // 按可检索字段（时间+标题+正文+标签）做包含匹配
    return dateEntries.filter((entry: DiaryEntry): boolean => {
      const searchable: string = `${entry.time}${entry.title}${entry.content}${entry.label}`
        .toLowerCase().replace(/\s/g, '');
      return searchable.includes(keyword);
    });
  }

  /** 将可见列表分成真实记录和内置演示记录，避免两类数据在视觉上混为一谈。 */
  private realEntries(entries: DiaryEntry[]): DiaryEntry[] {
    return entries.filter((entry: DiaryEntry): boolean => !entry.id.startsWith('preview-'));
  }

  /** 当前日期与搜索条件下仍可见的演示记录。 */
  private previewEntries(entries: DiaryEntry[]): DiaryEntry[] {
    return entries.filter((entry: DiaryEntry): boolean => entry.id.startsWith('preview-'));
  }

  /** 当前筛选条件下可见的真实记录。 */
  private visibleRealEntries(): DiaryEntry[] {
    return this.realEntries(this.filteredEntries());
  }

  /** 当前筛选条件下可见的演示记录。 */
  private visiblePreviewEntries(): DiaryEntry[] {
    return this.previewEntries(this.filteredEntries());
  }

  /** 判断两个时间戳是否属于同一自然日。 */
  private sameDay(leftTimestamp: number, rightTimestamp: number): boolean {
    const left: Date = new Date(leftTimestamp);
    const right: Date = new Date(rightTimestamp);
    return left.getFullYear() === right.getFullYear() &&
      left.getMonth() === right.getMonth() && left.getDate() === right.getDate();
  }

  /** 当前筛选日期是否为系统今天。 */
  private isTodaySelected(): boolean {
    return this.sameDay(Date.now(), this.selectedDate);
  }

  /**
   * 汇总今日估算减排量
   * 只统计允许计分（scoreEnabled）的记录，保留 2 位小数
   * @returns 减排总量展示文本
   */
  private reductionTotal(): string {
    let total: number = 0;
    this.savedDrafts.forEach((draft: RecordDraft): void => {
      if (draft.scoreEnabled && draft.verificationStatus === 'verified' &&
        this.sameDay(draft.recordedAt ?? draft.createdAt ?? Date.now(), this.selectedDate)) {
        total += draft.reductionKg;
      }
    });
    return total.toFixed(2);
  }

  /** 首页无记录或搜索无结果时的明确空状态。 */
  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Image($r('app.media.diary_leaf'))
        .syncLoad(true)
        .width(42)
        .height(42)
        .opacity(0.55)
      Text(this.searchText.trim().length > 0 ? '没找到相关记录，换个关键词试试' :
        (this.isTodaySelected() ? '今天还没有记录，点下面的 + 记一笔' : '这一天还没有可查看的记录'))
        .fontSize(15)
        .fontColor('#718078')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 时间戳格式化为"时:分"（如 '17:40'），不足两位补零
   * @param timestamp 毫秒时间戳
   * @returns 时:分文本
   */
  private formatTime(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  /**
   * 时间戳格式化为"MM月DD日"（如 '09月28日'）
   * @param timestamp 毫秒时间戳
   * @returns 日期文本
   */
  private formatDate(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return `${(date.getMonth() + 1).toString().padStart(2, '0')}月${date.getDate().toString().padStart(2, '0')}日`;
  }

  /**
   * 显示占位提示 Toast
   * 用于尚未接入的功能入口，统一告知用户该功能将在后续版本提供
   * @param message 提示文案
   */
  private showPending(message: string): void {
    // 通过 UIContext 获取 PromptAction（替代已废弃的全局 promptAction API）
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      // Toast 属于非关键提示，弹出失败时静默忽略，不影响页面主流程
    }
  }

  /**
   * 打开日历
   * 优先执行父组件注入的 onOpenCalendar 回调；未注入时显示占位提示
   */
  private openCalendar(): void {
    if (this.onOpenCalendar) {
      this.onOpenCalendar();
    } else {
      this.showPending('日历选择将在后续接入');
    }
  }

  /**
   * 打开搜索
   * 优先执行父组件注入的 onSearchDiary 回调；未注入时显示占位提示
   */
  private openSearch(): void {
    this.searchActive = true;
    this.onSearchDiary?.();
  }

  /**
   * 新建日记
   * 优先执行父组件注入的 onAddDiary 回调；未注入时显示占位提示
   */
  private addDiary(): void {
    if (this.onAddDiary) {
      this.onAddDiary();
    } else {
      this.showPending('下一步：新建低碳日记');
    }
  }

  /**
   * 切换底部栏目
   * 仅当真正完成栏目切换（父组件接管并处理）时才更新选中态；
   * 尚未接入的栏目继续使用占位提示，选中态保持不变
   * @param tab 目标栏目名；点击当前所在栏目时直接忽略
   */
  private selectTab(tab: string): void {
    // 已处于当前栏目，无需切换
    if (tab === this.selectedTab) {
      this.pressedTab = tab;
      setTimeout(() => {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
      }, 120);
      return;
    }
    if (this.onSelectTab) {
      // 父组件接管切换：由目标页面自己绘制选中态，当前日记页保持日记选中。
      // 先保留短暂按压反馈，再切换页面，避免目标页面立即卸载导致动效看不见。
      this.pressedTab = tab;
      setTimeout(() => {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
        this.onSelectTab?.(tab);
      }, 120);
    } else if (tab === '日记' || tab === '成长') {
      this.selectedTab = tab;
    } else {
      // 栏目尚未接入：仅提示，不改变选中态
      this.showPending(`${tab}页面将在后续接入`);
    }
  }

  /**
   * 计算导航项底托颜色
   * 选中项为淡绿色圆角底托；未选中项常态无底托；按压时均提亮一档（材质亮度反馈）
   * @param label 栏目名称
   * @param selected 是否为当前选中栏目
   * @returns 底托背景色
   */
  private tabPadColor(label: string, selected: boolean): ResourceColor {
    const pressed: boolean = this.pressedTab === label;
    if (selected) {
      // 淡绿色底托；按压时提亮
      return pressed ? '#CCDCEDE4' : '#B3D2E7D7';
    }
    // 未选中：常态透明，按压时叠加轻微浅色提亮
    return pressed ? '#26FFFFFF' : Color.Transparent;
  }

  /** 顶部区域：居中日期、日历/搜索入口与今日减排概览。 */
  @Builder
  private Header() {
    // Stack 叠加布局：底层为左右按钮行，上层为居中的日期按钮
    Stack({ alignContent: Alignment.Center }) {
      // 左右图标按钮行
      Row() {
        // 左侧：日历入口按钮（透明背景，仅显示图标）
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.diary_calendar'))
            .syncLoad(true)
            .width(29)
            .height(29)
        }
        .width(48)
        .height(48)
        .padding(8)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .accessibilityText('选择日记日期')
        .onClick(() => this.openCalendar())

        // 弹性占位：将右侧按钮推至行尾
        Blank()

        // 右侧：搜索入口按钮
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.diary_search'))
            .syncLoad(true)
            .width(29)
            .height(29)
        }
        .width(48)
        .height(48)
        .padding(8)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .accessibilityText('搜索日记')
        .onClick(() => this.openSearch())
      }
      .width('100%')

      // 上层：居中的日期按钮，整块区域都打开系统日历
      Button({ type: ButtonType.Normal }) {
        Text(this.formatDate(this.selectedDate))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123D2D')
      }
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(16)
      .accessibilityText(`${this.formatDate(this.selectedDate)}，展开日历`)
      .onClick(() => this.openCalendar())
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })

    // 今日减排概览：富文本拼接"记录数 + 估算减排量"，数值部分加深加粗
    Text() {
      Span(`${this.isTodaySelected() ? '今天' : this.formatDate(this.selectedDate)} ${this.entryCount()} 条真实记录 · 估算减排 `)
        .fontColor('#738078')
      Span(`${this.reductionTotal()} kg`)
        .fontColor('#163D2F')
        .fontWeight(FontWeight.Medium)
    }
    .fontSize(14)
    .textAlign(TextAlign.Center)
    .width('100%')
    .margin({ top: 4, bottom: 12 })

    // 搜索行：点击搜索按钮后展开，关键字实时过滤下方列表
    if (this.searchActive) {
      Row({ space: 8 }) {
        // 搜索图标
        Image($r('app.media.diary_search'))
          .syncLoad(true)
          .width(22)
          .height(22)
        // 关键字输入框：内容变化实时刷新列表
        TextInput({ placeholder: '搜索标题、正文或低碳行为', text: this.searchText })
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor('#365C4B')
          .placeholderColor('#89958E')
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onChange((value: string): void => {
            this.searchText = value;
          })
        // 清除按钮：清空关键字并收起搜索行
        Button('清除', { type: ButtonType.Normal, stateEffect: false })
          .fontSize(13)
          .fontColor('#4C8067')
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.searchText = '';
            this.searchActive = false;
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 12 })
      .backgroundColor('#EAF2E8')
      .borderRadius(24)
      .margin({ left: 20, right: 20, bottom: 8 })
    }
  }

  /**
   * 日记条目的文字部分（时间/标题/正文/标签）
   * 与左侧图标拆分，便于在 EntryRow 中复用并占据剩余宽度
   * @param entry 单条日记数据
   */
  @Builder
  private EntryText(entry: DiaryEntry) {
    Column({ space: 0 }) {
      // 记录时间
      Text(entry.time)
        .fontSize(13)
        .fontColor('#7A877E')
        .margin({ bottom: 8 })
      // 日记标题
      Text(entry.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#153F2E')
        .lineHeight(26)
        .margin({ bottom: 6 })
      // 日记正文
      Text(entry.content)
        .fontSize(15)
        .fontColor('#65756B')
        .lineHeight(24)
        .margin({ bottom: 10 })
      // 低碳行为标签（胶囊样式）
      Text(entry.label)
        .fontSize(13)
        .fontColor('#506F59')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .backgroundColor('#EAF0E5')
        .borderRadius(18)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /**
   * 重复使用的日记条目：行为图标、正文、可选配图。
   * @param entry 单条日记数据
   */
  @Builder
  private EntryRow(entry: DiaryEntry) {
    Row({ space: 14 }) {
      // 左侧：行为类别图标（圆形浅绿底）
      Image(entry.icon)
        .syncLoad(true)
        .width(46)
        .height(46)
        .padding(9)
        .backgroundColor('#EAF0E5')
        .borderRadius(23)
        .accessibilityLevel('no')

      // 中部：文字信息，占据剩余宽度
      this.EntryText(entry)

      // 右侧：可选配图，仅当数据中存在 photo 时渲染
      if (entry.photo !== undefined) {
        Image(entry.photo)
          .syncLoad(true)
          .width('26%')
          // 平板宽屏时按比例会把配图放大到半屏；设置上限只影响宽屏，手机尺寸保持原样。
          .constraintSize({ maxWidth: 440 })
          .aspectRatio(0.86)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .margin({ left: 0 })
          .accessibilityText('阳光穿过校园道路两旁的树叶')
      }
      if (entry.photoUri !== undefined && entry.photoUri.length > 0) {
        Image(entry.photoUri)
          .syncLoad(true)
          .width('26%')
          .constraintSize({ maxWidth: 440 })
          .aspectRatio(0.86)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .margin({ left: 0 })
          .accessibilityText('日记配图')
      }
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ top: 20, bottom: 22 })
    .onClick(() => this.onOpenDiary?.(entry.id))
  }

  /**
   * 底部导航条的单个栏目项
   * 选中项配淡绿色圆角底托：底托渲染在栏目项内部，不增加组件尺寸、不挤压图标文字；
   * 按压时轻微缩小并提亮材质，松开后恢复（约 180ms，缩放为渲染变换、不影响布局占位）
   * @param label 栏目名称（'日记'/'足迹'/'成长'/'我的'）
   * @param icon 栏目图标资源（SVG 自带明确配色，深色系统下不会变白）
   * @param selected 是否为当前选中栏目（影响底托、文字颜色与字重）
   */
  @Builder
  private TabItem(label: string, icon: Resource, selected: boolean) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 5 }) {
        // 栏目图标：尺寸保持 26×26 不变
        Image(icon)
          .syncLoad(true)
          .width(26)
          .height(26)
        // 栏目名称：选中态森林绿加粗，未选中态清晰灰绿（显式配色，避免深色系统下白字）
        Text(label)
          .fontSize(12)
          .fontColor(selected ? '#245C40' : '#8B968E')
          .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      }
      .width('100%')
      // 底托内边距：只为底托留出呼吸空间，图标与文字的尺寸、间距均不变（总高约 60，仍在 68 高的栏目项内）
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      // 淡绿色圆角底托：仅选中项显示，按压时提亮（见 tabPadColor）
      .backgroundColor(this.tabPadColor(label, selected))
      .borderRadius(18)
      // 底托颜色变化的过渡动画，与外层缩放动画保持同步
      .animation({ duration: 180, curve: Curve.Friction })
    }
    .layoutWeight(1)
    .height(68)
    .padding(0)
    .borderRadius(24)
    .backgroundColor(Color.Transparent)
    // 按压缩放：轻微缩小，松开恢复；不改变布局占位
    .scale({
      x: this.pressedTab === label ? 0.94 : 1,
      y: this.pressedTab === label ? 0.94 : 1
    })
    // 按压/恢复过渡动画：约 180ms，摩擦曲线平滑减速、无弹跳
    .animation({ duration: 180, curve: Curve.Friction })
    .accessibilityText(selected ? `${label}，当前栏目` : label)
    .onClick(() => this.selectTab(label))
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
   * 悬浮加号与四栏导航，固定在页面底部
   * 视觉分两层，按设备能力自动升级：
   * 1. 兜底层（所有设备可见）：材质模糊（backgroundBlurStyle）+ 半透明绿色底 + 极细浅色描边 + 柔和阴影，
   *    模糊不可用时自然降级为浅绿半透明外观；
   * 2. 液态玻璃层（API 26+ 且设备支持沉浸光感时生效）：在兜底样式之后追加 systemMaterial
   *    （ImmersiveMaterial，API 26 组件级通用属性），材质接管背景、描边与阴影，
   *    呈现带淡绿赋色的系统液态玻璃；加号按钮同时启用交互形变与按压光晕，按压反馈由材质光效提供。
   * 属性顺序要求：systemMaterial 必须写在背景/描边/阴影之后，材质生效时才能覆盖这些样式；
   * 不具备能力的设备上材质为 undefined，自动保持兜底层磨砂外观。全页仅此两处模糊/材质层，控制性能开销。
   * @param showPlus 是否显示悬浮"新建日记"加号按钮（仅日记栏目显示）
   */
  @Builder
  private BottomControls(showPlus: boolean) {
    Column({ space: 0 }) {
      if (showPlus) {
      // 悬浮"新建日记"圆形按钮：绿色稍浓的玻璃材质 + 柔和投影，突出主要操作
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        // 加号图标保持居中与原尺寸；SVG 本身为近白色，与绿色玻璃底对比清晰
        Image($r('app.media.diary_plus'))
          .syncLoad(true)
          .width(34)
          .height(34)
      }
      .width(66)
      .height(66)
      .padding(16)
      // 按压缩放：轻微缩小，松开恢复；不改变布局占位
      .scale({
        x: this.plusPressed ? 0.92 : 1,
        y: this.plusPressed ? 0.92 : 1
      })
      // 玻璃底色：半透明中绿叠在材质模糊之上，比导航条稍浓；按压时提亮一档（材质亮度反馈）。
      // 液态玻璃生效的设备上此层被材质替代，按压反馈改由材质光晕提供。
      .backgroundColor(this.plusPressed ? '#D983AC8E' : '#B34C8A68')
      // 材质模糊：透出背后柔和的列表内容
      .backgroundBlurStyle(BlurStyle.Thin)
      // 极细、低透明度的浅色边缘高光，表现轻薄玻璃质感
      .border({ width: 1, color: '#59FFFFFF' })
      // 柔和阴影保持悬浮感
      .shadow({ radius: 18, color: '#2943694A', offsetX: 0, offsetY: 6 })
      // 按压/恢复过渡动画：约 180ms，摩擦曲线平滑减速、无弹跳
      .animation({ duration: 180, curve: Curve.Friction })
      // 液态玻璃层：具备能力的设备上接管背景/描边/阴影，并叠加交互形变与按压光晕；
      // 其余设备为 undefined，保持上方磨砂兜底样式
      .systemMaterial(this.plusMaterial)
      .accessibilityText('新建低碳日记')
      .onClick(() => this.addDiary())
      // 跟踪按压状态：按下置位，抬起/取消复位
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.plusPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.plusPressed = false;
        }
      })
      .margin({ bottom: 6 })
      }

      // 四栏导航条：日记/足迹/成长/我的；选中态由 selectedTab 驱动（仅真正切换后更新）
      Row() {
        this.TabItem('日记', $r('app.media.diary_diary'), this.selectedTab === '日记')
        this.TabItem('足迹', $r('app.media.diary_leaf'), this.selectedTab === '足迹')
        this.TabItem('成长', $r('app.media.diary_sprout'), this.selectedTab === '成长')
        this.TabItem('我的', $r('app.media.diary_person'), this.selectedTab === '我的')
      }
      .width('100%')
      .height(76)
      .padding({ left: 6, right: 6 })
      // 浅绿半透明底色叠在材质模糊之上，背后滚动的日记内容透出柔和色彩
      .backgroundColor('#B8E6EEDF')
      // 材质模糊（薄）：与半透明浅绿共同构成磨砂玻璃条，而非透明色块
      .backgroundBlurStyle(BlurStyle.Thin)
      // 极细、低透明度的浅色边缘高光
      .border({ width: 1, color: '#59FFFFFF' })
      .borderRadius(28)
      // 柔和阴影保持悬浮感
      .shadow({ radius: 16, color: '#09304F35', offsetX: 0, offsetY: 3 })
      // 液态玻璃层：具备能力的设备上接管背景/描边/阴影；其余设备为 undefined，保持上方磨砂兜底样式
      .systemMaterial(this.navBarMaterial)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
    // 空白区域不拦截列表滑动，按钮仍可响应点击。
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * 页面布局
   * Stack 底部对齐：底层为可滚动内容区（顶栏 + 日记列表），
   * 上层为悬浮底部操作区（加号 + 导航条）
   */
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底层：纵向内容区
      Column() {
        // 顶部区域：日期、日历/搜索入口与今日概览
        this.Header()

        if (this.filteredEntries().length === 0) {
          this.EmptyState()
        } else {
          // 日记列表：占据剩余高度，可滚动；演示记录单独加分组标题。
          List({ space: 0 }) {
            ForEach(this.visibleRealEntries(), (entry: DiaryEntry) => {
              ListItem() {
                this.EntryRow(entry)
              }
            }, (entry: DiaryEntry) => entry.id)
            if (this.visiblePreviewEntries().length > 0) {
              ListItem() {
                Row() {
                  Text('演示示例')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#718078')
                  Blank()
                  Text('不计入真实记录与积分')
                    .fontSize(12)
                    .fontColor('#A0804A')
                }
                .width('100%')
                .padding({ top: 15, bottom: 7, left: 4, right: 4 })
              }
            }
            ForEach(this.visiblePreviewEntries(), (entry: DiaryEntry) => {
              ListItem() {
                this.EntryRow(entry)
              }
            }, (entry: DiaryEntry) => entry.id)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.wideLayout ? 1320 : 10000 })
          .alignSelf(ItemAlign.Center)
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
          .divider({ strokeWidth: 0.5, color: '#DBE2D8' })
          .contentEndOffset(220)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 12 })

      // 上层：底部悬浮操作区
      this.BottomControls(this.selectedTab === '日记')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
    // 将底部液态玻璃导航的绘制范围延伸到系统手势区，避免导航条与退出手势栏之间出现突兀空白。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    // 时间、电量与底部手势条由系统显示，页面不绘制假的状态栏。
  }
}

/**
 * 独立预览入口：打开本文件即可查看首页，无需登录、联网或启动后端。
 */
@Preview({
  title: 'HomeDiary',      // 预览标题
  deviceType: 'phone',     // 设备类型：手机
  width: 1260,             // 预览宽度（px）
  height: 2800,            // 预览高度（px）
  colorMode: 'light',      // 浅色模式
  dpi: 480,                // 屏幕像素密度
  locale: 'zh_CN',         // 简体中文语言环境
  orientation: 'portrait', // 竖屏方向
  roundScreen: false       // 非圆屏设备
})
@Component
struct HomePreview {
  build() {
    // 直接渲染日记首页组件
    Home()
  }
}
