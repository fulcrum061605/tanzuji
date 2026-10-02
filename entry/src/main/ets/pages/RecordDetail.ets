/**
 * 碳记 · 记录详情（2026-09-29 确认稿）
 * 新建日记的第二步：从行为选择页（BehaviorPicker）带入低碳行为，在此填写数量、
 * 查看即时减排估算，并可补充文字与图片，最后保存为一条记录草稿（RecordDraft）。
 * 图片通过系统相册 PhotoViewPicker 选择并保存用户授权的 URI，
 * 减排系数是公开数据的近似简化值，仅供记录参考；保存结果经 onSave 回调交给父组件，
 * 入口页目前仅返回首页，草稿数据待接入本地存储后启用。
 * 图片/SVG 全部在 resources/base/media 中，断网也可预览；文末提供独立 @Preview 预览入口。
 */
import { BehaviorOption } from './BehaviorPicker';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CarbonEvidenceService, EvidenceSource } from '../services/CarbonEvidenceService';
import { CarbonFactorService, CARBON_FACTOR_CATALOG_SOURCE } from '../services/CarbonFactorService';

/**
 * 保存给日记首页或后续本地存储使用的记录草稿。
 */
export interface RecordDraft {
  /** 稳定的本地记录主键，不依赖数组下标。 */
  recordId?: string;
  /** 首次创建时间与最后更新时间。 */
  createdAt?: number;
  updatedAt?: number;
  /** 本地记录操作号：用于积分服务去重，编辑同一条记录不会重复领奖。 */
  operationId?: string;
  /** 记录发生时间（毫秒时间戳），用于首页和足迹按日期统计。 */
  recordedAt?: number;
  /** 选中的低碳行为（含 id、名称与图标），回传给父组件继续使用 */
  behavior: BehaviorOption;
  /** 完成数量：按所选单位的原始数值，未换算为主单位 */
  amount: number;
  /** 数量单位名称（如 '公里'/'米'/'份'），与 amount 配套 */
  unit: string;
  /** 即时估算的减排量（kg CO₂e），由数量 × 单位换算系数 × 行为减排系数得出 */
  reductionKg: number;
  /** 补充日记文字，可为空串 */
  note: string;
  /** 是否携带真实相册图片；保存时由 photoUri 是否为空统一决定。 */
  hasPhoto: boolean;
  /** 用户从系统相册选择的持久化图片 URI。 */
  photoUri?: string;
  /** 数量来源：系统定位、华为运动或手动待核实。 */
  evidenceSource: EvidenceSource;
  /** 验证状态：只有 verified 记录才计入正式碳积分。 */
  verificationStatus: 'verified' | 'pending';
  /** 轨迹或运动数据的证据编号。 */
  evidenceId: string;
  /** 是否允许计入积分和正式碳足迹。 */
  scoreEnabled: boolean;
}

/**
 * 数量单位选项。
 */
class UnitOption {
  /** 单位显示名称（如 '公里'） */
  name: string;
  /** 与默认主单位之间的换算：例如 1 米 = 0.001 公里。 */
  toBase: number;

  constructor(name: string, toBase: number) {
    this.name = name;
    this.toBase = toBase;
  }
}

/**
 * 默认行为兜底：独立预览或父组件未传入行为时，以"骑行"展示完整表单，
 * 与参考稿的 2.4 公里示例保持一致。
 */
class DefaultBikeBehavior implements BehaviorOption {
  id: string = 'bike';
  name: string = '骑行';
  icon: Resource = $r('app.media.diary_bike');
}

/**
 * 记录详情组件
 * 页面结构：顶部返回栏 + 行为卡片 + 数量输入与减排估算卡片 + 补充日记卡片 + 保存按钮。
 * 数量、单位的每次变化都会即时刷新减排估算与保存按钮状态；
 * 页面事件通过 onBack/onSave 回调交给入口管理。
 */
@Component
export struct RecordDetail {
  /** 当前低碳行为：由 BehaviorPicker 选中后经入口页传入；未传入时使用默认骑行兜底 */
  behavior: BehaviorOption = new DefaultBikeBehavior();
  /** 返回行为选择页回调：由父组件注入（入口页实现为退回选择页重选行为），未注入时点击无动作 */
  onBack?: () => void;
  /** 保存记录回调：携带整理好的 RecordDraft，由父组件决定去向（当前入口仅返回首页） */
  onSave?: (draft: RecordDraft) => void;
  /** 编辑已有记录时传入原草稿；新建记录时为空。 */
  initialDraft?: RecordDraft;

  /** 数量输入框文本：保持 string 便于输入法编辑，计算时再解析为数字 */
  @State private amountText: string = '2.4';
  /** 当前选中的数量单位名：与 units() 返回项的 name 对应，切换后即时重算估算值 */
  @State private selectedUnit: string = '公里';
  /** 补充日记文字：与文本域双向同步，限长 200 字 */
  @State private note: string = '';
  /** 是否携带用户从系统相册选择的图片。 */
  @State private hasPhoto: boolean = false;
  /** 系统相册返回的持久化图片 URI。 */
  @State private photoUri: string = '';
  /** 数量输入框是否聚焦：驱动输入卡片描边加深变绿的编辑反馈 */
  @State private focusedAmount: boolean = false;
  /** 核验状态：verified 已核验 / pending 待核实；只有 verified 计入正式碳积分 */
  @State private verificationStatus: 'verified' | 'pending' = 'pending';
  /** 数量证据来源：系统定位、华为运动或手动记录 */
  @State private evidenceSource: EvidenceSource = 'manual';
  /** 轨迹或运动数据的证据编号 */
  @State private evidenceId: string = '';
  /** 测量流程的提示文案（权限、开始/结束测量与读取运动结果） */
  @State private measurementMessage: string = '';
  /** 是否正在进行系统定位测量 */
  @State private tracking: boolean = false;
  /** 证据服务实例：负责定位轨迹测量与华为运动数据读取 */
  private evidenceService: CarbonEvidenceService = new CarbonEvidenceService();
  /** 碳因子服务：统一提供减排系数、计算与口径来源 */
  private factorService: CarbonFactorService = new CarbonFactorService();

  /**
   * 判断当前行为是否需要系统自动测量
   * 所有出行距离行为不接受手动输入数量，只能通过定位轨迹或华为运动获得
   * @returns true 表示数量由系统测量
   */
  private isAutoMeasured(): boolean {
    return this.behavior.id === 'bike' || this.behavior.id === 'walk' ||
      this.behavior.id === 'transit' || this.behavior.id === 'carpool' || this.behavior.id === 'metro';
  }

  /** 组件即将出现：编辑已有记录时回填原草稿；新建记录时按行为初始化默认值与提示文案 */
  aboutToAppear(): void {
    // 编辑模式：回填原草稿的全部字段
    if (this.initialDraft !== undefined) {
      this.amountText = this.initialDraft.amount.toString();
      this.selectedUnit = this.initialDraft.unit;
      this.note = this.initialDraft.note;
      this.hasPhoto = this.initialDraft.hasPhoto;
      this.photoUri = this.initialDraft.photoUri ?? '';
      this.evidenceSource = this.initialDraft.evidenceSource;
      this.verificationStatus = this.initialDraft.verificationStatus;
      this.evidenceId = this.initialDraft.evidenceId;
      this.measurementMessage = this.initialDraft.verificationStatus === 'verified'
        ? '已由系统测量，数量不可手动修改' : '待核实记录，不计入正式碳积分';
      return;
    }
    // 骑行与参考图保持 2.4 公里；其他行为使用各自第一个单位和中性示例值。
    if (this.isAutoMeasured()) {
      this.amountText = '0';
      this.selectedUnit = '公里';
      this.measurementMessage = '需要定位和运动权限，系统测量后才会计入碳积分';
    } else {
      this.amountText = '1';
      this.selectedUnit = this.units()[0].name;
      this.measurementMessage = '该行为采用手动记录，保存后标记为待核实';
    }
  }

  /** 组件即将销毁：仍在定位测量时先停止，避免离开页面后持续消耗定位资源 */
  aboutToDisappear(): void {
    if (this.tracking) {
      this.evidenceService.stopLocationTracking();
      this.tracking = false;
    }
  }

  /**
   * 当前行为支持的单位列表（首项为主单位）
   * 距离类（步行/骑行/公交）提供公里与米双单位，回收提供千克与克，其余行为只有单一单位；
   * 新增行为时在此补充分支，默认兜底为"次"。
   * @returns 单位选项数组，至少一项
   */
  private units(): UnitOption[] {
    switch (this.behavior.id) {
      // 距离类：公里为主单位，米按 0.001 换算
      case 'walk':
      case 'bike':
      case 'transit':
      case 'carpool':
      case 'metro':
        return [new UnitOption('公里', 1), new UnitOption('米', 0.001)];
      case 'electricity':
        return [new UnitOption('千瓦时', 1)];
      case 'water':
      case 'shower':
        return [new UnitOption('升', 1)];
      case 'meal':
      case 'lowCarbonMeal':
        return [new UnitOption('份', 1)];
      // 回收：千克为主单位，克按 0.001 换算
      case 'recycle':
      case 'paperRecycle':
      case 'clothesRecycle':
        return [new UnitOption('千克', 1), new UnitOption('克', 0.001)];
      case 'reuse':
      case 'disposable':
      case 'shopping':
      case 'reusable':
      case 'secondhand':
        return [new UnitOption('件', 1)];
      default:
        return [new UnitOption('次', 1)];
    }
  }

  /**
   * 解析输入的数量
   * 空串、非数字或负数一律按 0 处理，保证估算与按钮状态不出现 NaN/负值
   * @returns 解析后的数量，非法输入返回 0
   */
  private amount(): number {
    const parsed: number = Number.parseFloat(this.amountText);
    return Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
  }

  /**
   * 即时减排估算：数量 × 单位换算系数 × 行为减排系数
   * 每次输入或切换单位都会重新求值，驱动估算卡片与保存按钮状态刷新
   * @returns 估算减排量（kg CO₂e）
   */
  private reduction(): number {
    // 查找所选单位的换算系数；异常时按主单位（1）兜底，保证计算不中断
    const unit: UnitOption | undefined = this.units().find((item: UnitOption) => item.name === this.selectedUnit);
    return this.factorService.calculate(this.behavior.id, this.amount(), this.selectedUnit,
      unit?.toBase ?? 1);
  }

  /**
   * 格式化减排量文本
   * 0 显示 '0.00'；不足 0.01 保留 3 位小数（避免节水等小额场景显示成 0.00 看不出变化）；
   * 其余保留 2 位小数
   * @returns 减排量展示文本
   */
  private reductionText(): string {
    const value: number = this.reduction();
    if (value === 0) {
      return '0.00';
    }
    if (value < 0.01) {
      return value.toFixed(3);
    }
    return value.toFixed(2);
  }

  /**
   * 核算依据文案：展示统一碳因子目录的口径来源，供追溯数据出处
   * @returns 口径来源说明文本
   */
  private factorSourceText(): string {
    return `口径来源：${CARBON_FACTOR_CATALOG_SOURCE}`;
  }

  /**
   * 数量输入框占位文本：骑行沿用参考稿的 2.4，其他行为显示 0
   * @returns 占位文本
   */
  private placeholderForAmount(): string {
    return this.behavior.id === 'bike' ? '2.4' : '0';
  }

  /**
   * 切换数量单位：切换后减排估算立即按新单位重新计算
   * @param unit 目标单位选项
   */
  private selectUnit(unit: UnitOption): void {
    this.selectedUnit = unit.name;
  }

  /**
   * 保存本次记录
   * 仅当数量大于 0 时触发（保存按钮在数量无效时已禁用，此处再兜底防御），
   * 将当前表单状态整理为 RecordDraft 经 onSave 交给父组件
   */
  private save(): void {
    const amount: number = this.amount();
    // 自动行为必须来自真实测量，且距离至少 50 米；手动行为永远待核实。
    if (amount <= 0 || (this.isAutoMeasured() &&
      (amount <= 0.05 || this.verificationStatus !== 'verified' ||
        (this.evidenceSource !== 'location' && this.evidenceSource !== 'health')))) {
      return;
    }
    if (!this.factorService.supports(this.behavior.id, this.selectedUnit)) {
      return;
    }
    const now: number = Date.now();
    const evidenceSource: EvidenceSource = this.isAutoMeasured() ? this.evidenceSource : 'manual';
    const verificationStatus: 'verified' | 'pending' = this.isAutoMeasured() ? this.verificationStatus : 'pending';
    this.onSave?.({
      recordId: this.initialDraft?.recordId ?? `${this.behavior.id}-${now}-${Math.floor(Math.random() * 100000)}`,
      operationId: this.initialDraft?.operationId ?? `${this.behavior.id}-${Date.now()}`,
      recordedAt: this.initialDraft?.recordedAt ?? Date.now(),
      createdAt: this.initialDraft?.createdAt ?? now,
      updatedAt: now,
      behavior: this.behavior,
      amount: amount,
      unit: this.selectedUnit,
      reductionKg: this.reduction(),
      note: this.note,
      hasPhoto: this.photoUri.length > 0,
      photoUri: this.photoUri,
      evidenceSource: evidenceSource,
      verificationStatus: verificationStatus,
      evidenceId: this.evidenceId,
      scoreEnabled: verificationStatus === 'verified' && evidenceSource !== 'manual'
    });
  }

  /**
   * 开始系统定位测量
   * 申请定位与运动权限并注册轨迹监听，累计距离通过回调实时刷新数量输入框；
   * 权限申请失败时降级为手动待核实
   */
  private async startMeasurement(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      // 启动轨迹测量：回调把累计公里数写回数量输入框
      const result = await this.evidenceService.startLocationTracking(context, (distanceKm: number): void => {
        this.amountText = distanceKm.toFixed(3);
        this.evidenceSource = 'location';
      });
      this.measurementMessage = result.message;
      this.evidenceSource = result.source;
      this.evidenceId = result.evidenceId;
      // 只有真正进入定位测量才置位跟踪标记
      this.tracking = result.source === 'location';
      if (this.tracking) {
        this.verificationStatus = 'pending';
      }
    } catch (error) {
      // 权限申请失败：降级为手动待核实
      this.measurementMessage = '权限申请失败，本次记录将标记为待核实';
      this.evidenceSource = 'manual';
      this.verificationStatus = 'pending';
      this.tracking = false;
    }
  }

  /**
   * 结束系统定位测量
   * 停止轨迹监听并取回累计距离；距离足够（>50 米）时记录核验通过，否则保持待核实
   */
  private async stopMeasurement(): Promise<void> {
    const result = await this.evidenceService.stopLocationTracking();
    this.tracking = false;
    // 用测量结果回填数量、单位与核验状态
    this.amountText = result.amount.toFixed(3);
    this.selectedUnit = '公里';
    this.evidenceSource = result.source;
    this.evidenceId = result.evidenceId;
    this.verificationStatus = result.verified ? 'verified' : 'pending';
    this.measurementMessage = result.message;
  }

  /**
   * 读取华为运动步数
   * 步数按固定口径（0.7 米/步）换算为公里；读取成功且步数大于 0 时核验通过，
   * 否则降级为手动待核实
   */
  private async readHuaweiActivity(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result = await this.evidenceService.readHuaweiActivity(context);
      if (result.source === 'health' && result.amount > 0) {
        // 华为运动返回步数，按 0.7 米/步换算为距离；该换算口径固定保存，不由用户输入。
        this.amountText = (result.amount * 0.0007).toFixed(3);
        this.selectedUnit = '公里';
        this.verificationStatus = 'verified';
        this.evidenceSource = 'health';
        this.evidenceId = result.evidenceId;
      } else {
        // 无可用数据：降级为手动待核实
        this.verificationStatus = 'pending';
        this.evidenceSource = 'manual';
      }
      this.measurementMessage = result.message;
    } catch (error) {
      // 健康服务不可用：降级为手动待核实
      this.verificationStatus = 'pending';
      this.evidenceSource = 'manual';
      this.measurementMessage = '华为运动数据暂不可用，本次记录将标记为待核实';
    }
  }

  /**
   * 打开系统相册选择一张图片，并保存系统授予的持久化 URI。
   * PhotoViewPicker 由系统处理权限，不在应用内自行申请图库读权限。
   */
  private async choosePhoto(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
        isPhotoTakingSupported: true
      });
      const uri: string | undefined = result.photoUris.length > 0 ? result.photoUris[0] : undefined;
      if (uri !== undefined && uri.length > 0) {
        this.photoUri = uri;
        this.hasPhoto = true;
      }
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '未能打开相册，请稍后重试', duration: 1600 });
      } catch (toastError) {
        // 系统相册取消或不可用时，不影响其他记录内容。
      }
    }
  }

  /**
   * 顶部导航栏：居中标题"记录详情" + 左侧返回按钮
   */
  @Builder
  private Header() {
    // Stack 让标题始终在页面几何中心，左侧返回键不会把标题挤向右边。
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        // 左侧返回按钮：透明底仅显示 ‹ 符号，点击触发 onBack 回调（入口页实现为退回行为选择页）
        Button({ type: ButtonType.Normal }) {
          Text('‹')
            .fontSize(36)
            .fontColor('#174E3A')
            .fontWeight(FontWeight.Normal)
        }
        .width(38)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onBack?.())
        .accessibilityText('返回选择低碳行为')
        Blank()
        // 右上角保持等宽留白，和参考图的非对称留白一致。
        Blank().width(38)
      }
      .width('100%')
      .padding({ left: 15, right: 15 })

      // 上层：居中的页面标题
      Text('记录详情')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123F2E')
    }
    .width('100%')
    .height(58)
  }

  /**
   * 行为卡片：圆形浅绿底图标 + 行为名称与副标题
   * 填写前先确认当前记录的是哪个低碳行为
   */
  @Builder
  private BehaviorCard() {
    Row({ space: 10 }) {
      // Stack 叠加：底层 66×66 圆形浅绿底托，上层 46×46 行为图标居中
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(66)
          .height(66)
          .borderRadius(33)
          .backgroundColor('#EAF2E8')
        // 骑行 SVG 自带留白不加内边距，其他图标收窄 3vp，保持视觉尺寸一致
        Image(this.behavior.icon)
          .syncLoad(true)
          .width(46)
          .height(46)
          .padding(this.behavior.id === 'bike' ? 0 : 3)
      }
      // 右侧：行为名称与副标题，左对齐
      Column({ space: 2 }) {
        Text(this.behavior.name)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
        Text('今天的低碳选择')
          .fontSize(14)
          .fontColor('#718078')
      }
      .alignItems(HorizontalAlign.Start)
    }
    // 卡片外观：纸感浅底 + 细描边 + 大圆角，与后续卡片风格统一
    .width('100%')
    .height(90)
    .padding({ left: 14, right: 12 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 数量输入卡片：大号数字输入框 + 竖分隔线 + 单位气泡列
   * 输入框聚焦时卡片描边加深变绿（focusedAmount 驱动），明确当前编辑位置
   */
  @Builder
  private AmountInput() {
    Row({ space: 8 }) {
      // 左侧只占主要区域，输入栏和单位气泡共用同一条卡片。
      // 大号加粗数字排版；输入即时同步 amountText，驱动估算与按钮状态刷新
      TextInput({ placeholder: this.placeholderForAmount(), text: this.amountText })
        .layoutWeight(1)
        .height(60)
        .fontSize(38)
        .fontWeight(FontWeight.Bold)
        .fontColor('#07553D')
        .placeholderColor('#9CB4A6')
        .caretColor('#72B28F')
        .backgroundColor(Color.Transparent)
        .padding({ left: 12, right: 4 })
        .type(InputType.Normal)
        .enabled(!this.isAutoMeasured())
        .onFocus(() => { this.focusedAmount = true; })
        .onBlur(() => { this.focusedAmount = false; })
        .onChange((value: string) => { this.amountText = value; })

      // 竖向细分隔线：隔开数量与单位两个区域
      Divider()
        .vertical(true)
        .height(44)
        .color('#D6E4D8')
        .strokeWidth(1)

      // 单位入口只保留这一处，两个单位气泡上下叠放。
      this.UnitSwitch()
    }
    .width('100%')
    .height(72)
    .padding({ left: 4, right: 6 })
    .backgroundColor('#FAFCF8')
    // 聚焦反馈：描边由 1px 浅绿加深为 2px 中绿
    .border({ width: this.focusedAmount ? 2 : 1, color: this.focusedAmount ? '#78B995' : '#BFDCC5' })
    .borderRadius(18)
    .margin({ bottom: 12 })
  }

  /**
   * 单位气泡列：当前行为支持的单位上下排列（最多两项）
   * 选中项绿色实底白字，未选中项浅绿底灰绿字；点击切换并即时重算减排
   */
  @Builder
  private UnitSwitch() {
    Column({ space: 5 }) {
      // 以单位名作为 ForEach 键；单位列表稳定，避免不必要的重建
      ForEach(this.units(), (unit: UnitOption) => {
        Button(unit.name, { type: ButtonType.Normal, stateEffect: false })
          .width(70)
          .height(25)
          .fontSize(13)
          .fontColor(this.selectedUnit === unit.name ? '#FFFFFF' : '#64776D')
          .backgroundColor(this.selectedUnit === unit.name ? '#4C9576' : '#EAF2E8')
          .borderRadius(14)
          .padding(0)
          .enabled(!this.isAutoMeasured())
          .onClick(() => this.selectUnit(unit))
      }, (unit: UnitOption) => unit.name)
    }
    .width(74)
    .height(60)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 减排估算卡片：叶片图标 + "预计减排"说明 + 右侧即时数值
   * 数值随数量输入与单位切换自动刷新，是本页的核心反馈
   */
  @Builder
  private ReductionCard() {
    Row({ space: 10 }) {
      // Stack 叠加：圆形浅绿底托 + 叶片图标
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(38)
          .height(38)
          .borderRadius(19)
          .backgroundColor('#E4F1E6')
        Image($r('app.media.diary_leaf'))
          .syncLoad(true)
          .width(25)
          .height(25)
      }
      // 左侧：标题与说明文字，占据剩余宽度
      Column({ space: 2 }) {
        Text('预计减排')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#126046')
        Text('根据完成数量自动估算，仅供记录参考')
          .fontSize(11)
          .fontColor('#718078')
        Text(this.factorSourceText())
          .fontSize(9)
          .fontColor('#98A79D')
          .maxLines(2)
      }
      .layoutWeight(1)
      // 右侧：即时估算值，加粗深绿突出显示
      Text(this.verificationStatus === 'verified' ? `${this.reductionText()} kg CO₂e` : '待核实')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor('#07553D')
    }
    // 浅绿提示底色，与上方白色输入卡片形成层级区分
    .width('100%')
    .height(82)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#F0F8EE')
    .borderRadius(14)
  }

  /**
   * 证据采集控制区
   * 需要系统测量的行为（骑行/步行）：显示测量提示文案 + 开始/结束测量按钮，
   * 步行额外提供"读取华为运动"入口；手动行为只显示记录方式提示
   */
  @Builder
  private EvidenceControl() {
    if (this.isAutoMeasured()) {
      // 自动测量行为：提示文案 + 操作按钮行
      Column({ space: 8 }) {
        // 测量状态提示：已核验绿色、未核验灰色
        Text(this.measurementMessage)
          .width('100%')
          .fontSize(13)
          .fontColor(this.verificationStatus === 'verified' ? '#4C9576' : '#718078')
          .textAlign(TextAlign.Start)
        Row({ space: 8 }) {
          // 测量中显示"结束测量"，未测量显示"申请权限并测量"
          if (this.tracking) {
            Button('结束测量', { type: ButtonType.Normal, stateEffect: false })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#4C9576')
              .borderRadius(18)
              .onClick(() => this.stopMeasurement())
          } else {
            Button('申请权限并测量', { type: ButtonType.Normal, stateEffect: false })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#4C9576')
              .borderRadius(18)
              .onClick(() => this.startMeasurement())
          }
          // 步行额外提供华为运动步数读取入口
          if (this.behavior.id === 'walk') {
            Button('读取华为运动', { type: ButtonType.Normal, stateEffect: false })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#4C9576')
              .backgroundColor('#EAF2E8')
              .borderRadius(18)
              .onClick(() => this.readHuaweiActivity())
          }
        }
      }
      .width('100%')
      .padding({ top: 2, bottom: 12 })
    } else {
      // 手动行为：仅显示记录方式提示
      Text(this.measurementMessage)
        .width('100%')
        .fontSize(13)
        .fontColor('#718078')
        .margin({ top: 2, bottom: 12 })
    }
  }

  /**
   * 补充日记卡片：标题 + 限长文本域（右下角字数统计）+ 系统相册图片
   */
  @Builder
  private NoteCard() {
    Column({ space: 8 }) {
      // 区块标题
      Text('补充日记')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123F2E')
        .textAlign(TextAlign.Start)

      // Stack 底右对齐：字数统计叠在文本域右下角内侧，不额外占用布局空间
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 多行文本域：限长 200 字；底部内边距加大，为字数统计留出空间
        TextArea({ placeholder: '记录一下当时的心情、路线或小发现……', text: this.note })
          .width('100%')
          .height(86)
          .fontSize(14)
          .fontColor('#365C4B')
          .placeholderColor('#9AA8A1')
          .backgroundColor('#FAFCF8')
          .border({ width: 1, color: '#D5E4D8' })
          .borderRadius(18)
          .padding({ left: 12, right: 12, top: 10, bottom: 24 })
          .maxLength(200)
          .onChange((value: string) => { this.note = value; })
        // 字数统计：随输入实时更新
        Text(`${this.note.length}/200`)
          .fontSize(13)
          .fontColor('#9AA8A1')
          .margin({ right: 18, bottom: 12 })
      }

      // 图片区：已有图片时显示用户从系统相册选择的缩略图
      Row({ space: 26 }) {
        if (this.hasPhoto && this.photoUri.length > 0) {
          // Stack 顶右对齐：删除角标叠在缩略图右上角
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(this.photoUri)
              .syncLoad(true)
              .width(70)
              .height(58)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
            // 删除角标：点击后 hasPhoto 置 false，按钮文案随之变为"添加图片"
            Button('×', { type: ButtonType.Circle, stateEffect: false })
              .width(20)
              .height(20)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor('#7D837F')
              .padding(0)
              .margin({ top: 3, right: 3 })
              .onClick(() => {
                this.hasPhoto = false;
                this.photoUri = '';
              })
              .accessibilityText('删除图片')
          }
        }
        // 添加/更换图片按钮：透明底，图标加文案随 hasPhoto 状态切换
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Row({ space: 8 }) {
            // Stack 叠加：圆角浅绿底托 + 相机图标
            Stack({ alignContent: Alignment.Center }) {
              Row()
                .width(46)
                .height(46)
                .borderRadius(12)
                .backgroundColor('#EAF4E9')
              Image($r('app.media.diary_camera'))
                .syncLoad(true)
                .width(25)
                .height(25)
            }
            Text(this.hasPhoto ? '更换图片' : '添加图片')
              .fontSize(14)
              .fontColor('#587166')
          }
        }
        .height(58)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.choosePhoto(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    // 卡片外观：与行为卡片一致的纸感浅底细描边
    .width('100%')
    .padding({ left: 14, right: 14, top: 15, bottom: 14 })
    .height(218)
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 页面布局：整页可滚动（小屏弹出输入法时仍能滚到保存按钮），
   * 自上而下依次为 返回栏 → 行为卡片 → 数量与估算卡片 → 补充日记卡片 → 保存按钮
   */
  build() {
    Scroll() {
      Column({ space: 10 }) {
        this.Header()
        this.BehaviorCard()
        // 数量与估算区块：标题按行为切换文案（骑行问"骑了多远"，其他问"完成了多少"）
        Column({ space: 0 }) {
          Text(this.behavior.id === 'bike' ? '这次骑了多远？' : '这次完成了多少？')
            .width('100%')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
            .margin({ bottom: 4 })
          // 输入引导语
          Text('输入实际完成的数量，系统会自动估算减排量')
            .width('100%')
            .fontSize(14)
            .fontColor('#718078')
            .margin({ bottom: 11 })
          this.AmountInput()
          this.EvidenceControl()
          this.ReductionCard()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 16, bottom: 15 })
        // 权限提示和操作按钮会让内容高度动态变化，不能用固定高度裁剪减排卡片。
        // 保留原来的最小高度，内容超出时由 Column 自动撑开。
        .constraintSize({ minHeight: 274 })
        .backgroundColor('#FAFBF6')
        .border({ width: 1, color: '#DDE8DE' })
        .borderRadius(14)
        this.NoteCard()
        // 保存按钮：数量有效时森林绿可点击，无效时灰绿禁用（颜色与 enabled 同源联动）
        Button('保存这次记录', { type: ButtonType.Normal, stateEffect: false })
          .width('100%')
          .height(37)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.amount() > 0 ? '#4C9576' : '#B6CBBE')
          .borderRadius(20)
          .enabled(this.isAutoMeasured() || this.amount() > 0)
          .margin({ top: 6 })
          .onClick(() => this.save())
      }
      .width('100%')
      // 平板限宽 620 居中，手机满宽不受影响
      .constraintSize({ maxWidth: 620 })
      // 底部预留 56，避免保存按钮贴到屏幕边缘
      .padding({ left: 19, right: 19, top: 17, bottom: 56 })
    }
    .width('100%')
    .height('100%')
    // 隐藏滚动条，保持纸面整洁
    .scrollBar(BarState.Off)
    // 与首页一致的纸张底色
    .backgroundColor('#F7F8F2')
  }
}

/**
 * 独立预览入口：打开本文件即可查看记录详情（默认骑行行为），无需登录、联网或启动后端。
 */
@Preview({
  title: 'RecordDetail', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct RecordDetailPreview {
  build() {
    // 直接渲染记录详情组件（使用默认骑行行为展示完整表单）
    RecordDetail()
  }
}
