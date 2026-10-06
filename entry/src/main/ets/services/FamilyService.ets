/**
 * 家庭碳账户服务。
 *
 * 家庭、成员档案与家庭任务的本机数据源：全部保存在 Preferences，不依赖服务器；
 * 成员档案用于在单台设备上演示"多人协作记录低碳行为"（比赛离线场景）。
 * 家庭统计只认已核验记录（verificationStatus=verified 且 scoreEnabled），
 * 待核实记录不计入家庭正式减排，避免随手填写刷高家庭数据；
 * 家庭任务同样由真实核验记录自动判定完成，页面不能手动领取。
 * 统计口径统一在本服务计算，家庭看板、任务与周报共用同一份结果。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { RecordDraft } from '../pages/RecordDetail';

/** 成员角色：创建者为管理员，其余为本机添加的普通成员档案 */
export type FamilyRole = 'admin' | 'member';

/** 家庭成员档案 */
export interface FamilyMember {
  /** 成员唯一标识，记录归属（RecordDraft.memberId）引用此 id */
  memberId: string;
  /** 成员昵称：家庭页与周报只展示昵称，不保存真实姓名 */
  nickname: string;
  /** 头像底色 */
  avatarColor: string;
  /** 角色：管理员管理成员与任务，创建者固定为管理员 */
  role: FamilyRole;
  /** 加入时间（毫秒时间戳） */
  joinedAt: number;
}

/** 已发布的家庭任务 */
export interface FamilyTask {
  /** 任务唯一标识：任务库 id + 发布周键，同一任务每周最多发布一次 */
  taskId: string;
  /** 任务标题 */
  title: string;
  /** 任务说明 */
  description: string;
  /** 绑定的低碳行为 id：达成判定按该行为的本周核验记录数计算 */
  behaviorId: string;
  /** 成员达成所需的本周核验记录次数 */
  targetCount: number;
  /** 发布时间（毫秒时间戳），任务在发布当周有效 */
  publishedAt: number;
}

/** 家庭快照：家庭信息、成员档案与任务一起整体持久化 */
export interface FamilySnapshot {
  /** 家庭唯一标识 */
  familyId: string;
  /** 家庭名称（如"绿色小家"） */
  familyName: string;
  /** 本周家庭减排目标（kg CO₂e） */
  weeklyGoalKg: number;
  /** 创建时间（毫秒时间戳） */
  createdAt: number;
  /** 成员档案列表，首位为管理员（创建者） */
  members: FamilyMember[];
  /** 当前记录身份：保存记录时归属的成员 id */
  currentMemberId: string;
  /** 已发布的家庭任务（保留最近四周） */
  tasks: FamilyTask[];
}

/** 可发布的家庭任务库定义 */
export interface FamilyTaskDef {
  /** 任务库 id，发布时与周键拼接为正式 taskId */
  id: string;
  /** 任务标题 */
  title: string;
  /** 任务说明 */
  description: string;
  /** 绑定的低碳行为 id */
  behaviorId: string;
  /** 达成所需次数 */
  targetCount: number;
}

/**
 * 家庭任务库：全部绑定可系统核验的出行行为。
 * 任务完成只能由已核验记录驱动，手动待核实记录不计入任务进度，
 * 因此任务库不包含光盘行动、节水节电等无法系统核验的手动行为。
 */
export const FAMILY_TASK_LIBRARY: FamilyTaskDef[] = [
  { id: 'walk-3', title: '本周至少步行 3 次', description: '每位成员完成 3 次已核验的步行记录', behaviorId: 'walk', targetCount: 3 },
  { id: 'bike-2', title: '骑行代替开车 2 次', description: '完成 2 次已核验的骑行记录', behaviorId: 'bike', targetCount: 2 },
  { id: 'transit-2', title: '乘坐 2 次公共交通', description: '公交出行留下 2 次已核验记录', behaviorId: 'transit', targetCount: 2 },
  { id: 'metro-2', title: '乘坐 2 次地铁', description: '地铁出行留下 2 次已核验记录', behaviorId: 'metro', targetCount: 2 },
  { id: 'carpool-1', title: '拼车出行 1 次', description: '完成 1 次已核验的拼车记录', behaviorId: 'carpool', targetCount: 1 }
];

/** 成员贡献行：看板贡献榜与周报参与人数共用 */
export interface MemberContribution {
  /** 成员 id */
  memberId: string;
  /** 成员昵称 */
  nickname: string;
  /** 头像底色 */
  avatarColor: string;
  /** 角色 */
  role: FamilyRole;
  /** 累计减排贡献（kg CO₂e） */
  totalKg: number;
  /** 本周减排贡献（kg CO₂e） */
  weekKg: number;
  /** 累计已核验记录次数 */
  actionCount: number;
  /** 是否为当前记录身份 */
  isCurrent: boolean;
  /** 是否为本周贡献最多的成员（友好的排行表达，避免负面比较） */
  isTop: boolean;
  /** 是否为新加入成员（3 天内） */
  isNew: boolean;
}

/** 家庭行为构成条目 */
export interface BehaviorBreakdown {
  /** 行为名称（如"步行"） */
  name: string;
  /** 该行为累计减排（kg CO₂e） */
  kg: number;
  /** 该行为累计次数 */
  count: number;
}

/** 家庭任务进度：达成成员由核验记录动态判定，不持久化避免状态过期 */
export interface FamilyTaskProgress {
  /** 任务定义 */
  task: FamilyTask;
  /** 本周已达成该任务的成员 id */
  completedMemberIds: string[];
  /** 任务是否在发布当周（过期任务仅展示，不再计入达成数） */
  active: boolean;
}

/** 家庭统计：看板、任务与周报共用同一份计算结果 */
export interface FamilyStats {
  /** 今日家庭减排（kg CO₂e） */
  todayKg: number;
  /** 本周家庭减排 */
  weekKg: number;
  /** 本月家庭减排 */
  monthKg: number;
  /** 累计家庭减排 */
  totalKg: number;
  /** 周目标完成百分比（0-100，达标后封顶） */
  goalPercent: number;
  /** 成员贡献（按累计减排降序） */
  members: MemberContribution[];
  /** 行为构成（按减排量降序） */
  behaviors: BehaviorBreakdown[];
  /** 本周家庭核验行为次数 */
  weekActions: number;
  /** 本周有核验记录的成员数 */
  weekActiveMembers: number;
  /** 任务进度（含已过期的近期任务） */
  tasks: FamilyTaskProgress[];
  /** 本周至少一名成员达成的任务数 */
  completedTasks: number;
  /** 少开燃油车等效公里数（与足迹页 0.175 kg/km 口径一致） */
  equivalentKm: number;
  /** 周报时间范围文案（如 '9月28日 - 10月4日'） */
  weekRangeLabel: string;
}

/** 反序列化时的宽松类型：字段合法性由 normalize 统一兜底 */
interface StoredFamily extends FamilySnapshot {
}

/** 本地家庭碳账户服务：家庭快照的读取、变更与统计计算 */
export class FamilyService {
  /** Preferences 存储库名 */
  private static readonly STORE_NAME: string = 'tanji_family_v1';
  /** 家庭快照在存储库中的键名 */
  private static readonly KEY: string = 'family_state';
  /** 燃油车每公里碳排放（kg CO₂e/km），等效换算与足迹页保持同源 */
  private static readonly FUEL_CAR_KG_PER_KM: number = 0.175;
  /** 成员头像底色调色板，按加入顺序循环取色 */
  private static readonly AVATAR_COLORS: string[] = ['#4C9576', '#D98E5F', '#6FA3C7', '#B78BB5', '#8FA65B', '#C77B7B'];

  /** 打开家庭专用的 Preferences 存储库 */
  private async openStore(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: FamilyService.STORE_NAME });
  }

  /**
   * 清洗家庭快照：字符串校验类型、数值夹取非负、数组兜底为空，
   * 并保证管理员存在且当前记录身份有效，防止异常 JSON 破坏不变量
   * @param value 待清洗的快照
   * @returns 字段合法的快照
   */
  private normalize(value: FamilySnapshot): FamilySnapshot {
    const members: FamilyMember[] = (Array.isArray(value.members) ? value.members : [])
      .map((item: FamilyMember): FamilyMember => {
        return {
          memberId: typeof item.memberId === 'string' && item.memberId.length > 0 ? item.memberId : `m-${Date.now()}`,
          nickname: typeof item.nickname === 'string' && item.nickname.length > 0 ? item.nickname : '成员',
          avatarColor: typeof item.avatarColor === 'string' && item.avatarColor.length > 0
            ? item.avatarColor : FamilyService.AVATAR_COLORS[0],
          role: item.role === 'admin' ? 'admin' : 'member',
          joinedAt: Number(item.joinedAt) || Date.now()
        };
      });
    // 管理员兜底：没有管理员时把首位成员提升为管理员，保证家庭始终可管理
    if (members.length > 0 && !members.some((item: FamilyMember): boolean => item.role === 'admin')) {
      members[0].role = 'admin';
    }
    const admin: FamilyMember | undefined = members.find((item: FamilyMember): boolean => item.role === 'admin');
    const currentValid: boolean = members.some((item: FamilyMember): boolean => item.memberId === value.currentMemberId);
    return {
      familyId: typeof value.familyId === 'string' && value.familyId.length > 0 ? value.familyId : `family-${Date.now()}`,
      familyName: typeof value.familyName === 'string' && value.familyName.length > 0 ? value.familyName : '绿色小家',
      weeklyGoalKg: Math.max(1, Number(value.weeklyGoalKg) || 10),
      createdAt: Number(value.createdAt) || Date.now(),
      members: members,
      currentMemberId: currentValid ? value.currentMemberId : (admin !== undefined ? admin.memberId : ''),
      tasks: (Array.isArray(value.tasks) ? value.tasks : [])
        .filter((item: FamilyTask): boolean => typeof item.taskId === 'string' && item.taskId.length > 0)
        .map((item: FamilyTask): FamilyTask => {
          return {
            taskId: item.taskId,
            title: typeof item.title === 'string' ? item.title : '家庭任务',
            description: typeof item.description === 'string' ? item.description : '',
            behaviorId: typeof item.behaviorId === 'string' ? item.behaviorId : 'walk',
            targetCount: Math.max(1, Math.floor(Number(item.targetCount) || 1)),
            publishedAt: Number(item.publishedAt) || Date.now()
          };
        })
    };
  }

  /**
   * 读取家庭快照；尚未创建家庭或数据损坏时返回 undefined
   * @param context 应用上下文
   */
  async load(context: common.Context): Promise<FamilySnapshot | undefined> {
    const store: preferences.Preferences = await this.openStore(context);
    const value: preferences.ValueType = await store.get(FamilyService.KEY, '');
    if (typeof value !== 'string' || value.length === 0) {
      return undefined;
    }
    try {
      const parsed: StoredFamily = JSON.parse(value) as StoredFamily;
      const snapshot: FamilySnapshot = this.normalize(parsed);
      return snapshot.members.length > 0 ? snapshot : undefined;
    } catch (error) {
      return undefined;
    }
  }

  /** 清洗并持久化家庭快照后立即落盘 */
  private async save(context: common.Context, snapshot: FamilySnapshot): Promise<void> {
    const store: preferences.Preferences = await this.openStore(context);
    await store.put(FamilyService.KEY, JSON.stringify(this.normalize(snapshot)));
    await store.flush();
  }

  /**
   * 创建家庭：创建者自动成为管理员（首个成员 m-1）并设为当前记录身份
   * @param context 应用上下文
   * @param familyName 家庭名称，空串时兜底为"绿色小家"
   * @param weeklyGoalKg 本周家庭减排目标（kg CO₂e）
   * @param ownerNickname 创建者昵称，空串时兜底为"我"
   * @returns 创建后的家庭快照
   */
  async create(context: common.Context, familyName: string,
    weeklyGoalKg: number, ownerNickname: string): Promise<FamilySnapshot> {
    const now: number = Date.now();
    const owner: FamilyMember = {
      memberId: 'm-1',
      nickname: ownerNickname.trim().length > 0 ? ownerNickname.trim() : '我',
      avatarColor: FamilyService.AVATAR_COLORS[0],
      role: 'admin',
      joinedAt: now
    };
    const snapshot: FamilySnapshot = {
      familyId: `family-${now}`,
      familyName: familyName.trim().length > 0 ? familyName.trim() : '绿色小家',
      weeklyGoalKg: weeklyGoalKg > 0 ? weeklyGoalKg : 10,
      createdAt: now,
      members: [owner],
      currentMemberId: owner.memberId,
      tasks: []
    };
    await this.save(context, snapshot);
    FamilyService.applyCurrentMember(snapshot);
    return snapshot;
  }

  /** 按"m-数字"规则生成下一个成员 id，删除成员后也不会重复 */
  private nextMemberId(members: FamilyMember[]): string {
    let max: number = 0;
    members.forEach((member: FamilyMember): void => {
      const suffix: number = Number.parseInt(member.memberId.replace('m-', ''), 10);
      if (!Number.isNaN(suffix) && suffix > max) {
        max = suffix;
      }
    });
    return `m-${max + 1}`;
  }

  /**
   * 添加成员档案：昵称必填，头像底色按加入顺序循环取色
   * @param context 应用上下文
   * @param nickname 成员昵称
   * @returns 更新后的快照；昵称为空或没有家庭时返回 undefined
   */
  async addMember(context: common.Context, nickname: string): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    if (snapshot === undefined || nickname.trim().length === 0) {
      return undefined;
    }
    const member: FamilyMember = {
      memberId: this.nextMemberId(snapshot.members),
      nickname: nickname.trim(),
      avatarColor: FamilyService.AVATAR_COLORS[snapshot.members.length % FamilyService.AVATAR_COLORS.length],
      role: 'member',
      joinedAt: Date.now()
    };
    snapshot.members = [...snapshot.members, member];
    await this.save(context, snapshot);
    return snapshot;
  }

  /**
   * 删除成员档案：管理员不可删除；被删成员的历史记录仍保留在日记中，
   * 但不再参与家庭统计；删除的是当前记录身份时回落到管理员
   * @param context 应用上下文
   * @param memberId 成员 id
   * @returns 更新后的快照；成员不存在或为管理员时返回 undefined
   */
  async removeMember(context: common.Context, memberId: string): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    const member: FamilyMember | undefined = snapshot === undefined
      ? undefined : snapshot.members.find((item: FamilyMember): boolean => item.memberId === memberId);
    if (snapshot === undefined || member === undefined || member.role === 'admin') {
      return undefined;
    }
    snapshot.members = snapshot.members.filter((item: FamilyMember): boolean => item.memberId !== memberId);
    if (snapshot.currentMemberId === memberId) {
      const admin: FamilyMember | undefined =
        snapshot.members.find((item: FamilyMember): boolean => item.role === 'admin');
      snapshot.currentMemberId = admin !== undefined ? admin.memberId : snapshot.currentMemberId;
    }
    await this.save(context, snapshot);
    FamilyService.applyCurrentMember(snapshot);
    return snapshot;
  }

  /**
   * 修改成员昵称；改的是当前记录身份时同步刷新 AppStorage，
   * 保证记录页"同步到家庭"开关展示的昵称即时一致
   * @param context 应用上下文
   * @param memberId 成员 id
   * @param nickname 新昵称
   * @returns 更新后的快照；参数无效时返回 undefined
   */
  async renameMember(context: common.Context, memberId: string, nickname: string): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    const member: FamilyMember | undefined = snapshot === undefined
      ? undefined : snapshot.members.find((item: FamilyMember): boolean => item.memberId === memberId);
    if (snapshot === undefined || member === undefined || nickname.trim().length === 0) {
      return undefined;
    }
    member.nickname = nickname.trim();
    await this.save(context, snapshot);
    FamilyService.applyCurrentMember(snapshot);
    return snapshot;
  }

  /**
   * 切换当前记录身份：之后保存的低碳记录归属该成员
   * @param context 应用上下文
   * @param memberId 成员 id
   * @returns 更新后的快照；成员不存在时返回 undefined
   */
  async switchMember(context: common.Context, memberId: string): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    if (snapshot === undefined || !snapshot.members.some((item: FamilyMember): boolean => item.memberId === memberId)) {
      return undefined;
    }
    snapshot.currentMemberId = memberId;
    await this.save(context, snapshot);
    FamilyService.applyCurrentMember(snapshot);
    return snapshot;
  }

  /**
   * 设置本周家庭减排目标
   * @param context 应用上下文
   * @param weeklyGoalKg 目标（kg CO₂e），夹取到 1-100
   * @returns 更新后的快照；没有家庭时返回 undefined
   */
  async setGoal(context: common.Context, weeklyGoalKg: number): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    if (snapshot === undefined) {
      return undefined;
    }
    snapshot.weeklyGoalKg = Math.max(1, Math.min(100, Math.floor(Number(weeklyGoalKg) || 10)));
    await this.save(context, snapshot);
    return snapshot;
  }

  /**
   * 从任务库发布本周任务：同一任务每周最多发布一次（taskId 含周键去重），
   * 只保留最近四周任务，避免历史任务无限累积
   * @param context 应用上下文
   * @param def 任务库定义
   * @returns 更新后的快照；没有家庭时返回 undefined
   */
  async publishTask(context: common.Context, def: FamilyTaskDef): Promise<FamilySnapshot | undefined> {
    const snapshot: FamilySnapshot | undefined = await this.load(context);
    if (snapshot === undefined) {
      return undefined;
    }
    const now: number = Date.now();
    const taskId: string = `${def.id}-${FamilyService.weekKeyOf(now)}`;
    if (snapshot.tasks.some((item: FamilyTask): boolean => item.taskId === taskId)) {
      return snapshot;
    }
    const task: FamilyTask = {
      taskId: taskId,
      title: def.title,
      description: def.description,
      behaviorId: def.behaviorId,
      targetCount: def.targetCount,
      publishedAt: now
    };
    // 只保留最近四周的任务，过期任务仅作短期回看
    snapshot.tasks = [...snapshot.tasks.filter((item: FamilyTask): boolean =>
      now - item.publishedAt < 28 * 86400000), task];
    await this.save(context, snapshot);
    return snapshot;
  }

  /**
   * 把当前记录身份同步到 AppStorage，记录页据此归属成员与展示同步开关；
   * 入口页冷启动和家庭页切换身份后都会调用，保证两处状态一致
   * @param snapshot 家庭快照
   */
  static applyCurrentMember(snapshot: FamilySnapshot): void {
    const member: FamilyMember | undefined = snapshot.members.find((item: FamilyMember): boolean =>
      item.memberId === snapshot.currentMemberId);
    if (member === undefined) {
      return;
    }
    AppStorage.setOrCreate<string>('familyCurrentMemberId', member.memberId);
    AppStorage.setOrCreate<string>('familyCurrentMemberName', member.nickname);
  }

  /** 自然日零点（毫秒时间戳） */
  static startOfDay(at: number): number {
    const date: Date = new Date(at);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  /** 本周周一零点（毫秒时间戳），家庭目标与任务均按周一到周日计算 */
  static startOfWeek(at: number): number {
    const date: Date = new Date(at);
    const day: number = date.getDay();
    const diff: number = day === 0 ? 6 : day - 1;
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() - diff).getTime();
  }

  /** 本月一号零点（毫秒时间戳） */
  static startOfMonth(at: number): number {
    const date: Date = new Date(at);
    return new Date(date.getFullYear(), date.getMonth(), 1).getTime();
  }

  /** 本地周键（周一日期 yyyy-MM-dd），用于任务发布去重 */
  static weekKeyOf(at: number): string {
    const start: Date = new Date(FamilyService.startOfWeek(at));
    const month: string = (start.getMonth() + 1).toString().padStart(2, '0');
    const day: string = start.getDate().toString().padStart(2, '0');
    return `${start.getFullYear()}-${month}-${day}`;
  }

  /** 空统计：未创建家庭时页面兜底使用，字段含义与 FamilyStats 一致 */
  static emptyStats(): FamilyStats {
    return {
      todayKg: 0,
      weekKg: 0,
      monthKg: 0,
      totalKg: 0,
      goalPercent: 0,
      members: [],
      behaviors: [],
      weekActions: 0,
      weekActiveMembers: 0,
      tasks: [],
      completedTasks: 0,
      equivalentKm: 0,
      weekRangeLabel: ''
    };
  }

  /**
   * 家庭统计的唯一口径：看板、任务进度与周报共用本结果。
   * 只统计已核验且允许计分的记录；选择"仅自己可见"的记录不参与家庭统计；
   * 归属规则：新记录按 memberId，未归属的历史记录归管理员（本机用户），
   * 已删除成员的记录保留在日记中但不再计入家庭数据。
   * @param family 家庭快照
   * @param drafts 全部本地记录
   * @returns 家庭统计结果
   */
  static computeStats(family: FamilySnapshot, drafts: RecordDraft[]): FamilyStats {
    const now: number = Date.now();
    const dayStart: number = FamilyService.startOfDay(now);
    const weekStart: number = FamilyService.startOfWeek(now);
    const monthStart: number = FamilyService.startOfMonth(now);
    const admin: FamilyMember | undefined =
      family.members.find((item: FamilyMember): boolean => item.role === 'admin');
    const adminId: string = admin !== undefined ? admin.memberId : '';
    // 记录归属：按 memberId 匹配现存成员；未归属的历史记录归管理员；已删除成员返回空串跳过
    const ownerIdOf = (draft: RecordDraft): string => {
      if (draft.memberId !== undefined && draft.memberId.length > 0) {
        return family.members.some((item: FamilyMember): boolean => item.memberId === draft.memberId)
          ? draft.memberId : '';
      }
      return adminId;
    };
    // 家庭统计只认已核验且允许计分的记录；仅自己可见的不计入
    const eligible: RecordDraft[] = drafts.filter((draft: RecordDraft): boolean =>
      draft.verificationStatus === 'verified' && draft.scoreEnabled === true && draft.familyVisible !== false);

    const contributions: MemberContribution[] = family.members.map((member: FamilyMember): MemberContribution => {
      return {
        memberId: member.memberId,
        nickname: member.nickname,
        avatarColor: member.avatarColor,
        role: member.role,
        totalKg: 0,
        weekKg: 0,
        actionCount: 0,
        isCurrent: member.memberId === family.currentMemberId,
        isTop: false,
        isNew: now - member.joinedAt < 3 * 86400000
      };
    });
    const behaviors: BehaviorBreakdown[] = [];
    let todayKg: number = 0;
    let weekKg: number = 0;
    let monthKg: number = 0;
    let totalKg: number = 0;
    let weekActions: number = 0;
    const weekMemberIds: string[] = [];
    eligible.forEach((draft: RecordDraft): void => {
      const ownerId: string = ownerIdOf(draft);
      if (ownerId.length === 0) {
        return;
      }
      const kg: number = Math.max(0, draft.reductionKg);
      const at: number = draft.recordedAt ?? draft.createdAt ?? 0;
      totalKg += kg;
      if (at >= dayStart) {
        todayKg += kg;
      }
      if (at >= weekStart) {
        weekKg += kg;
        weekActions += 1;
        if (!weekMemberIds.includes(ownerId)) {
          weekMemberIds.push(ownerId);
        }
      }
      if (at >= monthStart) {
        monthKg += kg;
      }
      const row: MemberContribution | undefined =
        contributions.find((item: MemberContribution): boolean => item.memberId === ownerId);
      if (row !== undefined) {
        row.totalKg += kg;
        row.actionCount += 1;
        if (at >= weekStart) {
          row.weekKg += kg;
        }
      }
      const behaviorName: string = draft.behavior.name.length > 0 ? draft.behavior.name : '低碳行为';
      const item: BehaviorBreakdown | undefined =
        behaviors.find((row: BehaviorBreakdown): boolean => row.name === behaviorName);
      if (item === undefined) {
        behaviors.push({ name: behaviorName, kg: kg, count: 1 });
      } else {
        item.kg += kg;
        item.count += 1;
      }
    });

    // 本周贡献最多：只在确有减排时点亮，排行用友好表达避免成员间负面比较
    let topWeekKg: number = 0;
    contributions.forEach((row: MemberContribution): void => {
      if (row.weekKg > topWeekKg) {
        topWeekKg = row.weekKg;
      }
    });
    if (topWeekKg > 0) {
      contributions.forEach((row: MemberContribution): void => {
        row.isTop = row.weekKg === topWeekKg;
      });
    }
    contributions.sort((a: MemberContribution, b: MemberContribution): number => b.totalKg - a.totalKg);
    behaviors.sort((a: BehaviorBreakdown, b: BehaviorBreakdown): number => b.kg - a.kg);

    // 任务进度：达成条件为成员在发布当周该行为的核验记录次数达到要求；
    // 结果动态判定不持久化，避免达成状态与真实记录脱节
    let completedTasks: number = 0;
    const taskProgress: FamilyTaskProgress[] = family.tasks.map((task: FamilyTask): FamilyTaskProgress => {
      const taskWeekStart: number = FamilyService.startOfWeek(task.publishedAt);
      const completed: string[] = family.members
        .filter((member: FamilyMember): boolean => {
          const count: number = eligible.filter((draft: RecordDraft): boolean => {
            return ownerIdOf(draft) === member.memberId && draft.behavior.id === task.behaviorId &&
              (draft.recordedAt ?? draft.createdAt ?? 0) >= taskWeekStart;
          }).length;
          return count >= task.targetCount;
        })
        .map((member: FamilyMember): string => member.memberId);
      const active: boolean = taskWeekStart === weekStart;
      if (active && completed.length > 0) {
        completedTasks += 1;
      }
      return { task: task, completedMemberIds: completed, active: active };
    });

    // 周报时间范围：本周一到本周日
    const rangeOf = (at: number): string => `${new Date(at).getMonth() + 1}月${new Date(at).getDate()}日`;
    const goal: number = family.weeklyGoalKg > 0 ? family.weeklyGoalKg : 10;
    return {
      todayKg: todayKg,
      weekKg: weekKg,
      monthKg: monthKg,
      totalKg: totalKg,
      goalPercent: Math.min(100, Math.round(weekKg / goal * 100)),
      members: contributions,
      behaviors: behaviors,
      weekActions: weekActions,
      weekActiveMembers: weekMemberIds.length,
      tasks: taskProgress,
      completedTasks: completedTasks,
      equivalentKm: weekKg / FamilyService.FUEL_CAR_KG_PER_KM,
      weekRangeLabel: `${rangeOf(weekStart)} - ${rangeOf(weekStart + 6 * 86400000)}`
    };
  }
}
