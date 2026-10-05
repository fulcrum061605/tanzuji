/**
 * 碳记 · 记录详情（2026-09-29 确认稿）
 * 新建日记的第二步：从行为选择页（BehaviorPicker）带入低碳行为，在此填写数量、
 * 查看即时减排估算，并可补充文字与图片，最后保存为一条记录草稿（RecordDraft）。
 * 图片通过系统相册 PhotoViewPicker 选择并保存用户授权的 URI，
 * 减排系数是公开数据的近似简化值，仅供记录参考；保存结果经 onSave 回调交给父组件，
 * 入口页负责把记录写入本地 Preferences，并在首页、足迹和我的页面复用同一份数据。
 * 图片/SVG 全部在 resources/base/media 中，断网也可预览；文末提供独立 @Preview 预览入口。
 *
 * 核验与积分口径（与 CarbonEvidenceService / CarbonPointsService 约定一致）：
 * - location：系统定位轨迹测量；health：华为运动健康当日步数（按 STEP_TO_KM = 0.0007 公里/步换算）；
 * - ai_image：端侧 Core Vision Kit OCR 识别，用户保存确认后按 verified 入账，积分按系统核验积分折半；
 * - manual：手动记录，一律 pending 待核实，scoreEnabled 为 false，不计入正式碳积分。
 */
import { BehaviorOption } from './BehaviorPicker';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CarbonEvidenceService, EvidenceSource } from '../services/CarbonEvidenceService';
import { CarbonFactorService, CARBON_FACTOR_CATALOG_SOURCE, STEP_TO_KM, displayUnit } from '../services/CarbonFactorService';
import { AiRecognitionDraft, OnDeviceAiService } from '../services/OnDeviceAiService';

/**
 * 保存给日记首页、足迹和我的页面使用的本地记录草稿。
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
  /** 用户从系统相册选择的持久化图片 URI（日记配图）。 */
  photoUri?: string;
  /** AI 图片辅助认证使用的相册图片 URI；与日记配图相互独立，避免互相覆盖导致证据链断裂。 */
  evidencePhotoUri?: string;
  /** 数量来源：系统定位、华为运动或手动待核实。 */
  evidenceSource: EvidenceSource;
  /** 验证状态：只有 verified 记录才计入正式碳积分。 */
  verificationStatus: 'verified' | 'pending';
  /** 轨迹或运动数据的证据编号。 */
  evidenceId: string;
  /** 是否允许计入积分和正式碳足迹。 */
  scoreEnabled: boolean;
  /** 核验层级：系统数据、AI 辅助图片或手动记录。旧记录缺失时按 manual 处理。 */
  verificationKind?: 'system' | 'ai_assisted' | 'manual';
  /** AI 服务名称，例如 CoreVisionKit.OCR。 */
  aiProvider?: string;
  /** AI 草稿状态：未使用、已生成、已确认或被拒绝。 */
  aiStatus?: 'none' | 'draft' | 'confirmed' | 'rejected';
  /** 本地规则计算的识别置信度，不代表图片真实性。 */
  aiConfidence?: number;
  /** AI 识别时使用的低碳行为名称。 */
  aiRecognizedBehavior?: string;
  /** AI 从图片解析出的距离数量。 */
  aiRecognizedAmount?: number;
  /** AI 解析出的距离单位（'公里'/'米'）。 */
  aiRecognizedUnit?: string;
  /** AI 识别完成的时间（毫秒时间戳）。 */
  aiRecognizedAt?: number;
  /** 图片摘要和风险标记，用于本机重复拦截和答辩追溯。 */
  imageHash?: string;
  riskFlags?: string[];
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
  /** 保存记录回调：携带整理好的 RecordDraft，由入口页写入本地记录并返回首页。 */
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
  /** 系统相册返回的持久化图片 URI（日记配图）。 */
  @State private photoUri: string = '';
  /** AI 图片辅助认证的相册图片 URI；与日记配图相互独立，互不覆盖。 */
  @State private evidencePhotoUri: string = '';
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
  /** AI 图片辅助认证状态；确认后作为已核验记录入账，但积分按系统核验积分折半。 */
  @State private aiStatus: 'none' | 'draft' | 'confirmed' | 'rejected' = 'none';
  @State private aiProvider: string = '';
  @State private aiConfidence: number = 0;
  @State private aiRecognizedBehavior: string = '';
  @State private aiRecognizedAmount: number = 0;
  @State private aiRecognizedUnit: string = '';
  @State private aiRecognizedAt: number = 0;
  @State private imageHash: string = '';
  @State private riskFlags: string[] = [];
  /** 证据服务实例：负责定位轨迹测量与华为运动数据读取 */
  private evidenceService: CarbonEvidenceService = new CarbonEvidenceService();
  /** 碳因子服务：统一提供减排系数、计算与口径来源 */
  private factorService: CarbonFactorService = new CarbonFactorService();
  /** 端侧 OCR 和本地风险规则服务。 */
  private aiService: OnDeviceAiService = new OnDeviceAiService();

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
      this.evidencePhotoUri = this.initialDraft.evidencePhotoUri ?? '';
      this.evidenceSource = this.initialDraft.evidenceSource;
      this.verificationStatus = this.initialDraft.verificationStatus;
      this.evidenceId = this.initialDraft.evidenceId;
      this.aiStatus = this.initialDraft.aiStatus ?? 'none';
      this.aiProvider = this.initialDraft.aiProvider ?? '';
      this.aiConfidence = this.initialDraft.aiConfidence ?? 0;
      this.aiRecognizedBehavior = this.initialDraft.aiRecognizedBehavior ?? '';
      this.aiRecognizedAmount = this.initialDraft.aiRecognizedAmount ?? 0;
      this.aiRecognizedUnit = this.initialDraft.aiRecognizedUnit ?? '';
      this.aiRecognizedAt = this.initialDraft.aiRecognizedAt ?? 0;
      this.imageHash = this.initialDraft.imageHash ?? '';
      this.riskFlags = this.initialDraft.riskFlags ?? [];
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
   * 自动测量行为在完成系统测量或 AI 图片确认前允许点击按钮，但由这里统一拦截并提示原因；
   * 通过校验后将当前表单状态整理为 RecordDraft 经 onSave 交给父组件
   */
  private save(): void {
    const amount: number = this.amount();
    // 自动行为必须来自系统测量，或已经完成 AI 图片草稿确认；两者都不能由输入框伪造。
    if (this.evidenceSource === 'ai_image' && this.aiStatus === 'draft') {
      this.aiStatus = 'confirmed';
    }
    const aiConfirmed: boolean = this.evidenceSource === 'ai_image' && this.aiStatus === 'confirmed';
    // 设备 OCR 不可用时允许用户手动确认数量，但降级为待核实记录，不计正式减排和积分。
    const aiManualFallback: boolean = this.evidenceSource === 'ai_image' &&
      this.aiStatus === 'rejected' && amount > 0;
    if (amount <= 0 || (this.isAutoMeasured() && !aiConfirmed &&
      !aiManualFallback &&
      (amount <= 0.05 || this.verificationStatus !== 'verified' ||
        (this.evidenceSource !== 'location' && this.evidenceSource !== 'health')))) {
      this.showSaveHint(amount);
      return;
    }
    if (!this.factorService.supports(this.behavior.id, this.selectedUnit)) {
      this.showSaveHint(amount);
      return;
    }
    const now: number = Date.now();
    const evidenceSource: EvidenceSource = aiManualFallback ? 'manual' :
      (this.isAutoMeasured() ? this.evidenceSource : 'manual');
    const verificationStatus: 'verified' | 'pending' = aiConfirmed ? 'verified' :
      (aiManualFallback ? 'pending' :
        (this.isAutoMeasured() ? this.verificationStatus : 'pending'));
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
      evidencePhotoUri: this.evidencePhotoUri,
      evidenceSource: evidenceSource,
      verificationStatus: verificationStatus,
      evidenceId: this.evidenceId,
      scoreEnabled: verificationStatus === 'verified' && evidenceSource !== 'manual',
      verificationKind: aiConfirmed ? 'ai_assisted' :
        (evidenceSource === 'manual' ? 'manual' : 'system'),
      aiProvider: this.aiProvider,
      aiStatus: this.aiStatus,
      aiConfidence: this.aiConfidence,
      aiRecognizedBehavior: this.aiRecognizedBehavior,
      aiRecognizedAmount: this.aiRecognizedAmount,
      aiRecognizedUnit: this.aiRecognizedUnit,
      aiRecognizedAt: this.aiRecognizedAt,
      imageHash: this.imageHash,
      riskFlags: this.riskFlags
    });
  }

  /**
   * 保存被拦截时的兜底提示
   * 按钮对自动测量行为保持可点击，拦截时在此给出明确原因，避免点击后没有任何反馈
   * @param amount 当前解析出的完成数量
   */
  private showSaveHint(amount: number): void {
    let message: string = '请先完成系统测量或图片认证，再保存记录';
    if (amount <= 0) {
      message = '请先填写完成数量，或点击测量获取真实数据';
    } else if (!this.factorService.supports(this.behavior.id, this.selectedUnit)) {
      message = '当前行为暂无碳因子，无法保存';
    } else if (this.evidenceSource === 'ai_image' && this.aiStatus === 'rejected') {
      message = '端侧 OCR 暂不可用，请手动确认数量后保存';
    }
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
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
   * 步数按因子目录统一口径（0.7 米/步）换算为公里；读取成功且步数大于 0 时核验通过，
   * 否则降级为手动待核实
   */
  private async readHuaweiActivity(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result = await this.evidenceService.readHuaweiActivity(context);
      if (result.source === 'health' && result.amount > 0) {
        // 华为运动返回步数，统一按因子目录的步幅口径换算为距离；口径固定保存，不由用户输入。
        this.amountText = (result.amount * STEP_TO_KM).toFixed(3);
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
   * @param runAi 是否在选图成功后立即调用端侧 OCR 识别（"上传图片认证"入口为 true）
   */
  private async choosePhoto(runAi: boolean = false): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
        isPhotoTakingSupported: true
      });
      const uri: string | undefined = result.photoUris.length > 0 ? result.photoUris[0] : undefined;
      if (uri !== undefined && uri.length > 0) {
        if (runAi) {
          // 认证入口：图片作为核验证据单独保存，不占用日记配图，避免互相覆盖。
          this.evidencePhotoUri = uri;
          await this.recognizePhoto(uri);
        } else {
          // 日记配图入口：仅作为日记展示图保存。
          this.photoUri = uri;
          this.hasPhoto = true;
        }
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
   * 调用端侧 OCR 识别选中的图片
   * 识别成功后填充草稿（数量、单位、置信度与风险标记），证据来源切换为 ai_image；
   * 无风险且用户保存确认后作为已核验记录入库，积分由服务层按系统核验积分折半。
   * @param uri 系统相册授权的图片 URI
   */
  private async recognizePhoto(uri: string): Promise<void> {
    this.measurementMessage = '正在使用华为端侧 OCR 识别图片……';
    const context: common.Context = this.getUIContext().getHostContext() as common.Context;
    const result: AiRecognitionDraft = await this.aiService.recognize(context, uri, this.behavior.name);
    this.aiProvider = result.provider;
    this.aiConfidence = result.confidence;
    this.aiRecognizedBehavior = result.recognizedBehavior;
    this.aiRecognizedAmount = result.amount;
    this.aiRecognizedUnit = result.unit;
    this.aiRecognizedAt = Date.now();
    this.imageHash = result.imageHash;
    this.riskFlags = result.riskFlags;
    this.aiStatus = result.amount > 0 ? 'draft' : 'rejected';
    this.evidenceSource = 'ai_image';
    this.verificationStatus = 'pending';
    if (result.amount > 0 && result.unit.length > 0) {
      this.amountText = result.amount.toString();
      this.selectedUnit = result.unit;
    }
    if (result.riskFlags.length === 0) {
      this.measurementMessage = '识别完成，请确认行为和数量后保存；核验成功按系统积分一半计入';
    } else {
      this.measurementMessage = `识别完成：${result.riskFlags.join('、')}，请确认后保存`;
    }
  }

  /**
   * 顶部导航栏：居中标题（新建"去记录"/编辑"编辑记录"） + 左侧返回按钮
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

      // 上层：居中的页面标题（新建与编辑使用不同标题，避免录入页误标为"详情"）
      Text(this.initialDraft === undefined ? '去记录' : '编辑记录')
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
        Button(displayUnit(unit.name), { type: ButtonType.Normal, stateEffect: false })
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
   * AI 图片辅助认证入口：选择相册图片并调用端侧 OCR 识别数量
   * 属于核验证据能力，与下方"补充日记"卡片的配图入口相互独立；
   * 认证图单独保存（evidencePhotoUri），不会覆盖日记配图
   */
  @Builder
  private AiCertifyButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text('上传图片认证')
        .fontSize(14)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .height(38)
    .padding(0)
    .backgroundColor('#4C9576')
    .borderRadius(19)
    .margin({ bottom: 10 })
    .accessibilityText('上传图片进行 AI 辅助认证')
    .onClick(() => { this.choosePhoto(true); })
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
        .onClick(() => { this.choosePhoto(false); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    // 卡片外观：与行为卡片一致的纸感浅底细描边；
    // 不再固定高度，大字号模式下由内容自动撑开，避免文字被裁剪
    .width('100%')
    .padding({ left: 14, right: 14, top: 15, bottom: 14 })
    .constraintSize({ minHeight: 220 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 页面布局：整页可滚动内容 + 固定底部保存栏
   * 自上而下依次为 返回栏 → 行为卡片 → 数量与估算卡片（含测量与图片认证入口） → 补充日记卡片；
   * 保存按钮固定在底部不随内容滚动，任何滚动位置都可见
   */
  build() {
    Column() {
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
            this.AiCertifyButton()
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
        }
        .width('100%')
        // 平板限宽 620 居中，手机满宽不受影响
        .constraintSize({ maxWidth: 620 })
        .padding({ left: 19, right: 19, top: 17, bottom: 14 })
      }
      .width('100%')
      .layoutWeight(1)
      // 隐藏滚动条，保持纸面整洁
      .scrollBar(BarState.Off)
      // 固定底部保存栏
      this.SaveBar()
    }
    .width('100%')
    .height('100%')
    // 与首页一致的纸张底色
    .backgroundColor('#F7F8F2')
  }

  /**
   * 固定底部保存栏：不随内容滚动
   * 数量有效时森林绿可点击，无效时灰绿禁用（颜色与 enabled 同源联动）
   */
  @Builder
  private SaveBar() {
    Column() {
      Button('保存这次记录', { type: ButtonType.Normal, stateEffect: false })
        .width('100%')
        .height(44)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor(this.amount() > 0 ? '#4C9576' : '#B6CBBE')
        .borderRadius(22)
        .enabled(this.isAutoMeasured() || this.amount() > 0)
        .onClick(() => this.save())
    }
    .width('100%')
    // 与滚动内容一致的平板限宽，父容器默认居中对齐
    .constraintSize({ maxWidth: 620 })
    .padding({ left: 19, right: 19, top: 8, bottom: 20 })
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
