/**
 * 碳积分与模拟权益服务。
 *
 * 积分只保存在本机 Preferences 中，权益兑换只生成本地“已领取”记录，
 * 不连接真实平台。核验记录由入口在保存成功后调用本服务入账，避免页面
 * 自己修改积分。所有上限都在服务层执行，防止重复点击或重复打开页面刷分。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/** 本机积分快照：同时作为持久化结构与服务层返回值 */
export interface PointsSnapshot {
  /** 当前可用积分余额 */
  balance: number;
  /** 累计获得积分（签到 + 核验记录，不扣除兑换） */
  totalEarned: number;
  /** 累计兑换消耗的积分 */
  totalRedeemed: number;
  /** 已领取的任务键列表（如每日签到 check-in-日期） */
  claimedTaskKeys: string[];
  /** 已入账的核验记录 operationId 列表，用于防重复计分 */
  rewardedOperationIds: string[];
  /** 已兑换的模拟权益 id 列表 */
  redeemedRewardIds: string[];
  /** 与 redeemedRewardIds 一一对应的兑换日期（yyyy-MM-dd），用于荣誉墙展示 */
  redeemedRewardDates?: string[];
  /** 核验记录计分所属日期（yyyy-MM-dd），跨天自动重置 */
  recordDay: string;
  /** 当日核验记录已入账积分，配合每日上限使用 */
  recordDayPoints: number;
  /** 图片辅助认证使用独立的每日积分上限。 */
  aiRecordDay?: string;
  /** 当日图片辅助认证已入账积分，配合独立每日上限使用 */
  aiRecordDayPoints?: number;
  /** 手动记录（无法系统核验）计分所属日期，跨天自动重置 */
  manualRecordDay?: string;
  /** 当日手动记录已入账积分，配合折扣每日上限使用 */
  manualRecordDayPoints?: number;
  /** 已获得图片辅助认证积分的图片摘要。 */
  aiRewardedImageHashes?: string[];
  /** 最近一次答题结算日期；每天只能结算一次答题积分。 */
  quizDay?: string;
  /** 最近一次答题获得的积分，供我的页面展示和兼容恢复使用。 */
  quizDayPoints?: number;
  /** 足迹棋盘当前位置，旧数据默认为起点。 */
  footprintPosition?: number;
  /** 已获得的棋盘模拟权益 id，避免机会格重复发放同一权益。 */
  footprintBenefitIds?: string[];
  /** 最近一次棋盘权益领取日期，按本地周限制。 */
  footprintBenefitWeek?: string;
}

/** 签到/入账/兑换操作的统一结果 */
export interface PointsActionResult {
  /** 操作是否成功 */
  success: boolean;
  /** 本次变动的积分（失败为 0） */
  points: number;
  /** 操作后的最新余额 */
  balance: number;
  /** 面向用户的提示文案 */
  message: string;
}

/** 足迹棋盘掷骰结果：补充步数、落点和落点反馈。 */
export interface FootprintRollResult extends PointsActionResult {
  steps: number;
  position: number;
  rewardTitle: string;
  benefitId: string;
}

/** 可兑换的模拟权益定义 */
export interface PointsReward {
  /** 权益唯一标识，兑换去重依据 */
  id: string;
  /** 权益名称 */
  title: string;
  /** 权益说明文案 */
  description: string;
  /** 兑换所需积分 */
  cost: number;
}

/** 权益兑换唯一目录：页面展示与服务层价格校验共用同一份，避免两处维护后不一致 */
export const POINTS_REWARDS: PointsReward[] = [
  { id: 'green-badge', title: '校园绿能徽章', description: '虚拟低碳徽章，兑换后点亮在“我的低碳荣誉”中', cost: 30 },
  { id: 'tree-certificate', title: '虚拟植树证书', description: '生成专属编号的植树纪念证书，展示在荣誉中', cost: 80 },
  { id: 'travel-coupon', title: '低碳出行优惠券', description: '模拟权益码：GREEN-TRAVEL-2026', cost: 120 }
];

/** 日常任务定义：任务 id 与分值白名单条目 */
export interface DailyTaskDef {
  /** 任务唯一标识，领取时由服务层校验 */
  id: string;
  /** 任务完成后可领取的积分 */
  points: number;
}

/** 日常任务白名单：页面展示分值与服务层校验共用同一份，避免两处维护后不一致 */
export const DAILY_TASKS: DailyTaskDef[] = [
  { id: 'verified-travel', points: 5 },
  { id: 'knowledge-favorite', points: 3 }
];

/** 反序列化时的宽松类型：字段合法性由 normalize 统一兜底 */
interface StoredPoints extends PointsSnapshot {
}

/** 首次使用或数据损坏时的空白积分快照 */
const EMPTY_POINTS: PointsSnapshot = {
  balance: 0,
  totalEarned: 0,
  totalRedeemed: 0,
  claimedTaskKeys: [],
  rewardedOperationIds: [],
  redeemedRewardIds: [],
  redeemedRewardDates: [],
  recordDay: '',
  recordDayPoints: 0,
  aiRecordDay: '',
  aiRecordDayPoints: 0,
  manualRecordDay: '',
  manualRecordDayPoints: 0,
  aiRewardedImageHashes: [],
  quizDay: '',
  quizDayPoints: 0,
  footprintPosition: 0,
  footprintBenefitIds: [],
  footprintBenefitWeek: ''
};

export class CarbonPointsService {
  /** Preferences 存储库名 */
  private static readonly STORE_NAME: string = 'tanji_carbon_points_v1';
  /** 快照在存储库中的键名 */
  private static readonly STATE_KEY: string = 'points_state';
  /** 核验记录每日入账积分上限 */
  private static readonly DAILY_RECORD_LIMIT: number = 30;
  /** 图片辅助认证每日积分上限，不与系统核验上限混用。 */
  private static readonly DAILY_AI_RECORD_LIMIT: number = 10;
  /** 手动记录（无法系统核验）每日积分上限：鼓励记录但防止无凭证刷分。 */
  private static readonly DAILY_MANUAL_RECORD_LIMIT: number = 5;
  /** 手动记录积分折算比例：按系统核验积分的 15% 入账。 */
  private static readonly MANUAL_POINTS_RATE: number = 0.15;
  /** 单位减排量对应积分；积分只对系统核验的减排量开放。 */
  private static readonly POINTS_PER_KG: number = 20;
  /** 单条核验记录积分下限，避免小额记录被四舍五入清零。 */
  private static readonly MIN_RECORD_POINTS: number = 2;
  /** 单条核验记录积分上限，避免大数值记录一次性刷满。 */
  private static readonly MAX_RECORD_POINTS: number = 20;

  /** 生成本地日期键（yyyy-MM-dd），用于签到去重与每日上限跨天重置 */
  private today(): string {
    const date: Date = new Date();
    const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    const day: string = date.getDate().toString().padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  /**
   * 打开积分专用的 Preferences 存储库
   * @param context 应用上下文
   */
  private async openStore(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: CarbonPointsService.STORE_NAME });
  }

  /**
   * 清洗快照数据：数值夹取非负、数组兜底为空、字符串校验类型，
   * 防止历史数据或异常 JSON 破坏积分不变量。
   * @param value 待清洗的快照
   * @returns 字段合法的快照
   */
  private normalize(value: PointsSnapshot): PointsSnapshot {
    return {
      balance: Math.max(0, Number(value.balance) || 0),
      totalEarned: Math.max(0, Number(value.totalEarned) || 0),
      totalRedeemed: Math.max(0, Number(value.totalRedeemed) || 0),
      claimedTaskKeys: Array.isArray(value.claimedTaskKeys) ? value.claimedTaskKeys : [],
      rewardedOperationIds: Array.isArray(value.rewardedOperationIds) ? value.rewardedOperationIds : [],
      redeemedRewardIds: Array.isArray(value.redeemedRewardIds) ? value.redeemedRewardIds : [],
      redeemedRewardDates: Array.isArray(value.redeemedRewardDates)
        ? value.redeemedRewardDates.filter((item: string): boolean => item.length > 0) : [],
      recordDay: typeof value.recordDay === 'string' ? value.recordDay : '',
      recordDayPoints: Math.max(0, Number(value.recordDayPoints) || 0),
      aiRecordDay: typeof value.aiRecordDay === 'string' ? value.aiRecordDay : '',
      aiRecordDayPoints: Math.max(0, Number(value.aiRecordDayPoints) || 0),
      manualRecordDay: typeof value.manualRecordDay === 'string' ? value.manualRecordDay : '',
      manualRecordDayPoints: Math.max(0, Number(value.manualRecordDayPoints) || 0),
      aiRewardedImageHashes: Array.isArray(value.aiRewardedImageHashes)
        ? value.aiRewardedImageHashes.filter((item: string): boolean => item.length > 0) : [],
      quizDay: typeof value.quizDay === 'string' ? value.quizDay : '',
      quizDayPoints: Math.max(0, Number(value.quizDayPoints) || 0),
      footprintPosition: Math.max(0, Math.floor(Number(value.footprintPosition) || 0)) % 16,
      footprintBenefitIds: Array.isArray(value.footprintBenefitIds)
        ? value.footprintBenefitIds.filter((item: string): boolean => item.length > 0) : [],
      footprintBenefitWeek: typeof value.footprintBenefitWeek === 'string' ? value.footprintBenefitWeek : ''
    };
  }

  /**
   * 读取积分快照；无数据或 JSON 解析失败时返回空白快照
   * @param context 应用上下文
   */
  async load(context: common.Context): Promise<PointsSnapshot> {
    const store: preferences.Preferences = await this.openStore(context);
    const value: preferences.ValueType = await store.get(CarbonPointsService.STATE_KEY, '');
    if (typeof value !== 'string' || value.length === 0) {
      return this.normalize(EMPTY_POINTS);
    }
    try {
      return this.normalize(JSON.parse(value) as StoredPoints);
    } catch (error) {
      return this.normalize(EMPTY_POINTS);
    }
  }

  /**
   * 整包恢复积分快照（备份恢复场景使用）
   * @param context 应用上下文
   * @param snapshot 备份中的积分快照
   */
  async restoreSnapshot(context: common.Context, snapshot: PointsSnapshot): Promise<void> {
    await this.save(context, snapshot);
  }

  /**
   * 清洗并持久化积分快照后立即落盘
   * @param context 应用上下文
   * @param snapshot 待保存的快照
   */
  private async save(context: common.Context, snapshot: PointsSnapshot): Promise<void> {
    const store: preferences.Preferences = await this.openStore(context);
    await store.put(CarbonPointsService.STATE_KEY, JSON.stringify(this.normalize(snapshot)));
    await store.flush();
  }

  /** 组装操作结果的快捷方法，保证各分支返回结构一致 */
  private result(success: boolean, points: number, balance: number, message: string): PointsActionResult {
    return { success: success, points: points, balance: balance, message: message };
  }

  /**
   * 兑换目录在服务层再次校验，避免页面传入任意低价或负价权益破坏积分平衡。
   * 目录与页面展示共用 POINTS_REWARDS 单一数据源，后续接真实平台时可替换为服务端目录。
   */
  private isAllowedReward(reward: PointsReward): boolean {
    const catalog: PointsReward | undefined =
      POINTS_REWARDS.find((item: PointsReward): boolean => item.id === reward.id);
    return catalog !== undefined && catalog.cost === reward.cost;
  }

  /**
   * 每天一次签到，固定 5 分，不与碳减排行为积分重复计算。
   * @param context 应用上下文
   * @returns 统一操作结果（重复签到时失败并返回当前余额）
   */
  async checkIn(context: common.Context): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    const key: string = `check-in-${this.today()}`;
    if (snapshot.claimedTaskKeys.includes(key)) {
      return this.result(false, 0, snapshot.balance, '今天已经签到过了');
    }
    snapshot.claimedTaskKeys = [...snapshot.claimedTaskKeys, key];
    snapshot.balance += 5;
    snapshot.totalEarned += 5;
    await this.save(context, snapshot);
    return this.result(true, 5, snapshot.balance, '签到成功，获得 5 积分');
  }

  /**
   * 领取白名单中的日常低碳任务。
   * 任务只能由页面在满足本地条件后调用，服务层再次校验任务 id、分值和当日去重。
   * @param context 应用上下文
   * @param taskId 任务 id（当前白名单：verified-travel 5 分 / knowledge-favorite 3 分）
   * @returns 统一操作结果（任务无效或当日已完成时失败）
   */
  async claimTask(context: common.Context, taskId: string): Promise<PointsActionResult> {
    const taskDef: DailyTaskDef | undefined =
      DAILY_TASKS.find((item: DailyTaskDef): boolean => item.id === taskId);
    const taskPoints: number | undefined = taskDef?.points;
    const snapshot: PointsSnapshot = await this.load(context);
    if (taskPoints === undefined) {
      return this.result(false, 0, snapshot.balance, '任务信息无效');
    }
    const key: string = `task-${taskId}-${this.today()}`;
    if (snapshot.claimedTaskKeys.includes(key)) {
      return this.result(false, 0, snapshot.balance, '今天已经完成这个任务');
    }
    snapshot.claimedTaskKeys = [...snapshot.claimedTaskKeys, key];
    snapshot.balance += taskPoints;
    snapshot.totalEarned += taskPoints;
    await this.save(context, snapshot);
    return this.result(true, taskPoints, snapshot.balance, `任务完成，获得 ${taskPoints} 积分`);
  }

  /**
   * 记录一条通过定位或华为运动核验的行为。
   * 同一 operationId 只入账一次；每天最多 30 分，避免重复创建记录刷分。
   * @param context 应用上下文
   * @param operationId 本地记录操作号，入账去重依据
   * @param verified 记录是否已通过系统核验
   * @param scoreEnabled 记录是否允许计入积分
   * @param evidenceSource 数量证据来源；manual 来源一律拦截（health/sensor 为运动步数来源）
   * @param reductionKg 本条记录的减排量（kg CO₂e），按 20 分/kg 折算并夹取单条上下限
   * @returns 统一操作结果（是否成功、本次积分、最新余额与提示文案）
   */
  async rewardVerifiedRecord(context: common.Context, operationId: string,
    verified: boolean, scoreEnabled: boolean,
    evidenceSource: 'location' | 'health' | 'sensor' | 'ai_image' | 'manual' = 'manual', reductionKg: number = 0): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    // 只有系统定位或华为运动产生的证据可以入账；手动输入即使被调用方误标为
    // verified，也必须在服务层拦截，避免通过重复编辑或改写页面状态刷分。
    if (!verified || !scoreEnabled || evidenceSource === 'manual' || operationId.length === 0) {
      return this.result(false, 0, snapshot.balance, '待核实记录不增加积分');
    }
    if (snapshot.rewardedOperationIds.includes(operationId)) {
      return this.result(false, 0, snapshot.balance, '这条记录已经领取过积分');
    }
    const today: string = this.today();
    if (snapshot.recordDay !== today) {
      snapshot.recordDay = today;
      snapshot.recordDayPoints = 0;
    }
    const calculated: number = Math.max(CarbonPointsService.MIN_RECORD_POINTS,
      Math.min(CarbonPointsService.MAX_RECORD_POINTS,
        Math.round(Math.max(0, reductionKg) * CarbonPointsService.POINTS_PER_KG)));
    const points: number = Math.min(calculated,
      CarbonPointsService.DAILY_RECORD_LIMIT - snapshot.recordDayPoints);
    snapshot.rewardedOperationIds = [...snapshot.rewardedOperationIds, operationId];
    if (points <= 0) {
      await this.save(context, snapshot);
      return this.result(false, 0, snapshot.balance, '今日记录积分已达上限');
    }
    snapshot.recordDayPoints += points;
    snapshot.balance += points;
    snapshot.totalEarned += points;
    await this.save(context, snapshot);
    return this.result(true, points, snapshot.balance, `核验成功，获得 ${points} 积分`);
  }

  /**
   * 图片辅助认证积分：系统核验积分的一半，单独每日封顶。
   * 同一 operationId 或同一图片指纹只入账一次；携带风险标记的图片一律拒绝。
   * @param context 应用上下文
   * @param operationId 本地记录操作号，入账去重依据
   * @param imageHash 图片内容指纹，重复提交拦截依据
   * @param reductionKg 本条记录的减排量（kg CO₂e），按系统积分折半计算
   * @param riskFlags 本地风险标记列表；非空时不发放积分
   * @returns 统一操作结果（是否成功、本次积分、最新余额与提示文案）
   */
  async rewardAiImageRecord(context: common.Context, operationId: string,
    imageHash: string, reductionKg: number, riskFlags: string[] = []): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    if (operationId.length === 0 || imageHash.length === 0) {
      return this.result(false, 0, snapshot.balance, '图片认证信息不完整');
    }
    if (riskFlags.length > 0) {
      return this.result(false, 0, snapshot.balance,
        riskFlags.includes('重复图片') ? '图片重复提交，未获得积分' : '图片信息存在风险，未获得积分');
    }
    if (snapshot.rewardedOperationIds.includes(operationId) ||
      (snapshot.aiRewardedImageHashes ?? []).includes(imageHash)) {
      return this.result(false, 0, snapshot.balance, '该图片或记录已经认证过');
    }
    const today: string = this.today();
    if (snapshot.aiRecordDay !== today) {
      snapshot.aiRecordDay = today;
      snapshot.aiRecordDayPoints = 0;
    }
    const systemPoints: number = Math.max(CarbonPointsService.MIN_RECORD_POINTS,
      Math.min(CarbonPointsService.MAX_RECORD_POINTS,
        Math.round(Math.max(0, reductionKg) * CarbonPointsService.POINTS_PER_KG)));
    const calculated: number = Math.max(1, Math.floor(systemPoints * 0.5));
    const points: number = Math.min(calculated,
      CarbonPointsService.DAILY_AI_RECORD_LIMIT - (snapshot.aiRecordDayPoints ?? 0));
    snapshot.rewardedOperationIds = [...snapshot.rewardedOperationIds, operationId];
    snapshot.aiRewardedImageHashes = [...(snapshot.aiRewardedImageHashes ?? []), imageHash];
    if (points <= 0) {
      await this.save(context, snapshot);
      return this.result(false, 0, snapshot.balance, '今日图片认证积分已达上限');
    }
    snapshot.aiRecordDayPoints = (snapshot.aiRecordDayPoints ?? 0) + points;
    snapshot.balance += points;
    snapshot.totalEarned += points;
    await this.save(context, snapshot);
    return this.result(true, points, snapshot.balance, `AI 辅助认证成功，获得 ${points} 积分`);
  }

  /**
   * 手动记录折扣积分：光盘行动、节水节电等无法系统核验的行为按系统积分的 15% 入账。
   * 手动记录不修改 verificationStatus/scoreEnabled，不影响正式碳足迹统计，只走积分激励通道；
   * 同一 operationId 只入账一次，每天最多 5 分，防止无凭证重复记录刷分。
   * @param context 应用上下文
   * @param operationId 本地记录操作号，入账去重依据
   * @param reductionKg 本条记录的减排量（kg CO₂e），按系统口径折算后乘以折扣比例
   * @returns 统一操作结果（是否成功、本次积分、最新余额与提示文案）
   */
  async rewardManualRecord(context: common.Context, operationId: string,
    reductionKg: number): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    if (operationId.length === 0) {
      return this.result(false, 0, snapshot.balance, '记录信息不完整');
    }
    if (snapshot.rewardedOperationIds.includes(operationId)) {
      return this.result(false, 0, snapshot.balance, '这条记录已经领取过积分');
    }
    const today: string = this.today();
    if (snapshot.manualRecordDay !== today) {
      snapshot.manualRecordDay = today;
      snapshot.manualRecordDayPoints = 0;
    }
    // 与系统核验同口径计算基准积分，再按折扣比例向下取整，保证手动积分永远低于核验积分。
    const systemPoints: number = Math.max(CarbonPointsService.MIN_RECORD_POINTS,
      Math.min(CarbonPointsService.MAX_RECORD_POINTS,
        Math.round(Math.max(0, reductionKg) * CarbonPointsService.POINTS_PER_KG)));
    const calculated: number =
      Math.max(1, Math.floor(systemPoints * CarbonPointsService.MANUAL_POINTS_RATE));
    const points: number = Math.min(calculated,
      CarbonPointsService.DAILY_MANUAL_RECORD_LIMIT - (snapshot.manualRecordDayPoints ?? 0));
    snapshot.rewardedOperationIds = [...snapshot.rewardedOperationIds, operationId];
    if (points <= 0) {
      await this.save(context, snapshot);
      return this.result(false, 0, snapshot.balance, '今日手动记录积分已达上限');
    }
    snapshot.manualRecordDayPoints = (snapshot.manualRecordDayPoints ?? 0) + points;
    snapshot.balance += points;
    snapshot.totalEarned += points;
    await this.save(context, snapshot);
    return this.result(true, points, snapshot.balance, `手动记录按 ${Math.round(CarbonPointsService.MANUAL_POINTS_RATE * 100)}% 折算，获得 ${points} 积分`);
  }

  /**
   * 每日答题积分：完成一套 10 题后只结算一次，最高 4 分。
   * 答题主要承担知识激励，积分低于低碳行为核验积分，避免刷题替代真实行动。
   * @param context 应用上下文
   * @param correctCount 本套答对题数，范围按 0-10 夹取
   */
  async rewardQuiz(context: common.Context, correctCount: number): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    const today: string = this.today();
    if (snapshot.quizDay === today) {
      return this.result(false, 0, snapshot.balance, '今天已经完成过答题');
    }
    const correct: number = Math.max(0, Math.min(10, Math.floor(Number(correctCount) || 0)));
    let points: number = 1;
    if (correct >= 6 && correct <= 7) {
      points = 2;
    } else if (correct >= 8 && correct <= 9) {
      points = 3;
    } else if (correct === 10) {
      points = 4;
    }
    snapshot.quizDay = today;
    snapshot.quizDayPoints = points;
    snapshot.balance += points;
    snapshot.totalEarned += points;
    await this.save(context, snapshot);
    return this.result(true, points, snapshot.balance, `答题完成，获得 ${points} 积分`);
  }

  /** 生成本地周键；棋盘模拟权益每周最多领取一次。 */
  private footprintWeek(): string {
    const date: Date = new Date();
    const first: Date = new Date(date.getFullYear(), 0, 1);
    const dayIndex: number = Math.floor((date.getTime() - first.getTime()) / 86400000);
    return `${date.getFullYear()}-${Math.floor(dayIndex / 7).toString()}`;
  }

  /**
   * 足迹棋盘掷骰：每次消耗 5 积分，随机前进 1-6 格并结算落点。
   * 机会格每周只发放一次模拟权益；本周已领时改为展示科普内容。
   */
  async rollFootprint(context: common.Context): Promise<FootprintRollResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    const cost: number = 5;
    const currentPosition: number = snapshot.footprintPosition ?? 0;
    if (snapshot.balance < cost) {
      return {
        success: false, points: 0, balance: snapshot.balance, message: '至少需要 5 积分才能前进',
        steps: 0, position: currentPosition, rewardTitle: '', benefitId: ''
      };
    }
    const steps: number = Math.floor(Math.random() * 6) + 1;
    const position: number = (currentPosition + steps) % 16;
    snapshot.footprintPosition = position;
    snapshot.balance -= cost;
    snapshot.totalRedeemed += cost;
    let rewardPoints: number = 0;
    let rewardTitle: string = '继续沿着低碳足迹前进';
    let benefitId: string = '';
    if ([1, 2, 4, 5, 7, 9, 11, 12, 14].includes(position)) {
      rewardPoints = position === 4 ? 3 : 2;
      rewardTitle = `低碳行动格：返还 ${rewardPoints} 积分`;
    } else if ([3, 6, 10, 13].includes(position)) {
      const week: string = this.footprintWeek();
      if (snapshot.footprintBenefitWeek !== week) {
        const benefits: string[] = ['campus-green-badge', 'tree-memory-card', 'green-travel-pass'];
        benefitId = benefits[Math.floor(Math.random() * benefits.length)];
        snapshot.footprintBenefitWeek = week;
        snapshot.footprintBenefitIds = [...(snapshot.footprintBenefitIds ?? []), benefitId];
        rewardTitle = benefitId === 'campus-green-badge' ? '机会格：获得校园绿能徽章（模拟权益）'
          : benefitId === 'tree-memory-card' ? '机会格：获得虚拟植树纪念卡（模拟权益）'
          : '机会格：获得低碳出行体验券（模拟权益）';
      } else {
        rewardTitle = '本周权益已领取，获得一条低碳知识';
      }
    } else if (position === 8) {
      rewardPoints = 4;
      rewardTitle = '绿色补给站：返还 4 积分';
    } else if (position === 19) {
      rewardPoints = 5;
      rewardTitle = '终点：完成一圈，返还 5 积分';
    }
    snapshot.balance += rewardPoints;
    snapshot.totalEarned += rewardPoints;
    await this.save(context, snapshot);
    return {
      success: true, points: rewardPoints - cost, balance: snapshot.balance, message: rewardTitle,
      steps: steps, position: position, rewardTitle: rewardTitle, benefitId: benefitId
    };
  }


  /**
   * 模拟权益兑换：扣除本地积分并记录权益 id，不调用真实平台。
   * @param context 应用上下文
   * @param reward 待兑换的权益项（id 与价格由服务层白名单再次校验）
   * @returns 统一操作结果（权益无效、重复领取或余额不足时失败）
   */
  async redeem(context: common.Context, reward: PointsReward): Promise<PointsActionResult> {
    const snapshot: PointsSnapshot = await this.load(context);
    if (!this.isAllowedReward(reward)) {
      return this.result(false, 0, snapshot.balance, '权益信息无效');
    }
    if (snapshot.redeemedRewardIds.includes(reward.id)) {
      return this.result(false, 0, snapshot.balance, '该权益已经领取过');
    }
    if (snapshot.balance < reward.cost) {
      return this.result(false, 0, snapshot.balance, `还差 ${reward.cost - snapshot.balance} 积分`);
    }
    snapshot.balance -= reward.cost;
    snapshot.totalRedeemed += reward.cost;
    snapshot.redeemedRewardIds = [...snapshot.redeemedRewardIds, reward.id];
    // 记录兑换日期，供荣誉墙展示徽章获得时间与证书落款
    snapshot.redeemedRewardDates = [...(snapshot.redeemedRewardDates ?? []), this.today()];
    await this.save(context, snapshot);
    return this.result(true, reward.cost, snapshot.balance, '兑换成功（模拟权益已到账）');
  }
}
