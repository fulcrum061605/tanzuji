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
  /** 核验记录计分所属日期（yyyy-MM-dd），跨天自动重置 */
  recordDay: string;
  /** 当日核验记录已入账积分，配合每日上限使用 */
  recordDayPoints: number;
  /** 图片辅助认证使用独立的每日积分上限。 */
  aiRecordDay?: string;
  /** 当日图片辅助认证已入账积分，配合独立每日上限使用 */
  aiRecordDayPoints?: number;
  /** 已获得图片辅助认证积分的图片摘要。 */
  aiRewardedImageHashes?: string[];
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
  recordDay: '',
  recordDayPoints: 0,
  aiRecordDay: '',
  aiRecordDayPoints: 0,
  aiRewardedImageHashes: []
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
      recordDay: typeof value.recordDay === 'string' ? value.recordDay : '',
      recordDayPoints: Math.max(0, Number(value.recordDayPoints) || 0),
      aiRecordDay: typeof value.aiRecordDay === 'string' ? value.aiRecordDay : '',
      aiRecordDayPoints: Math.max(0, Number(value.aiRecordDayPoints) || 0),
      aiRewardedImageHashes: Array.isArray(value.aiRewardedImageHashes)
        ? value.aiRewardedImageHashes.filter((item: string): boolean => item.length > 0) : []
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
   * 比赛演示只开放这三种固定权益，后续接真实平台时可替换为服务端目录。
   */
  private isAllowedReward(reward: PointsReward): boolean {
    switch (reward.id) {
      case 'green-badge': return reward.cost === 30;
      case 'tree-certificate': return reward.cost === 80;
      case 'travel-coupon': return reward.cost === 120;
      default: return false;
    }
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
    const taskPoints: number | undefined = taskId === 'verified-travel' ? 5 :
      taskId === 'knowledge-favorite' ? 3 : undefined;
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
   * @param evidenceSource 数量证据来源；manual 来源一律拦截
   * @param reductionKg 本条记录的减排量（kg CO₂e），按 20 分/kg 折算并夹取单条上下限
   * @returns 统一操作结果（是否成功、本次积分、最新余额与提示文案）
   */
  async rewardVerifiedRecord(context: common.Context, operationId: string,
    verified: boolean, scoreEnabled: boolean,
    evidenceSource: 'location' | 'health' | 'ai_image' | 'manual' = 'manual', reductionKg: number = 0): Promise<PointsActionResult> {
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
    await this.save(context, snapshot);
    return this.result(true, reward.cost, snapshot.balance, '兑换成功（模拟权益已到账）');
  }
}
