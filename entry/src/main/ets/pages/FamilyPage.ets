/**
 * 家庭碳账户页。
 * 本地多成员演示方案：创建者（管理员）在本机添加成员档案，切换"当前记录身份"后，
 * 保存的低碳记录归属对应成员（RecordDraft.memberId），家庭看板把全员已核验记录合并统计。
 * 页面包含创建引导、家庭看板（累计/本周减排、周目标进度、成员贡献、行为构成）、
 * 成员管理、家庭任务（由核验记录自动判定完成，不能手动领取）与家庭周报（可生成分享卡片）。
 * 统计口径统一由 FamilyService 计算；下拉刷新重新读取本机家庭数据并更新时间戳。
 */
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { RecordDraft } from './RecordDetail';
import {
  FamilyService,
  FamilySnapshot,
  FamilyMember,
  FamilyStats,
  MemberContribution,
  BehaviorBreakdown,
  FamilyTaskProgress,
  FamilyTaskDef,
  FAMILY_TASK_LIBRARY
} from '../services/FamilyService';

/**
 * 家庭碳账户组件
 * 三种顶层视图：创建引导 / 创建表单 / 家庭主页（看板、成员、任务、周报四个页签）。
 * 全部视图切换由 @State 标志在 build() 中分支渲染完成，不经过页面路由。
 */
@Component
export struct FamilyPage {
  /** 从入口页传入的全部已保存记录：家庭统计的数据来源 */
  @Prop savedDrafts: RecordDraft[] = [];
  /** 返回"我的"页回调 */
  onBack?: () => void;

  /** 家庭快照；undefined 表示尚未创建家庭 */
  @State private family: FamilySnapshot | undefined = undefined;
  /** 内容加载中标记 */
  @State private loading: boolean = true;
  /** 是否显示创建家庭表单 */
  @State private creating: boolean = false;
  /** 当前页签：看板 / 成员 / 任务 / 周报 */
  @State private tab: string = '看板';
  /** 下拉刷新进行中标记，与 Refresh 组件双向绑定 */
  @State private refreshing: boolean = false;
  /** 统计更新时间戳文案（如"数据更新于 14:32"） */
  @State private lastUpdatedLabel: string = '';
  /** 创建表单：家庭名称 */
  @State private familyNameText: string = '绿色小家';
  /** 创建表单：本周家庭目标（kg CO₂e） */
  @State private goalChoiceKg: number = 10;
  /** 创建表单：创建者昵称 */
  @State private ownerNameText: string = '';
  /** 是否展开添加成员表单 */
  @State private addingMember: boolean = false;
  /** 新成员昵称输入 */
  @State private newMemberName: string = '';
  /** 正在改名的成员 id；空串表示没有进行中的改名 */
  @State private renamingMemberId: string = '';
  /** 改名输入框文本 */
  @State private renameText: string = '';
  /** 家庭服务：家庭数据与统计的唯一数据源 */
  private service: FamilyService = new FamilyService();
  /** 统计结果缓存：家庭快照或记录列表变化前，一次渲染内的多处调用共用同一份结果 */
  private statsCache: FamilyStats | undefined = undefined;
  /** 统计缓存键：上次计算时的家庭快照引用 */
  private statsFamilyRef: FamilySnapshot | undefined = undefined;
  /** 统计缓存键：上次计算时的记录列表引用 */
  private statsDraftsRef: RecordDraft[] | undefined = undefined;
  /** 页签名列表 */
  private readonly tabs: string[] = ['看板', '成员', '任务', '周报'];
  /** 创建表单的可选周目标 */
  private readonly goalOptions: number[] = [5, 10, 15, 20];

  /** 组件即将出现：默认昵称取本地登录名，并读取本机家庭数据。 */
  aboutToAppear(): void {
    const savedName: string | undefined = AppStorage.get<string>('loginDisplayName');
    if (savedName !== undefined && savedName.length > 0) {
      this.ownerNameText = savedName;
    }
    this.loadFamily();
  }

  /**
   * 读取本机家庭快照并刷新时间戳；读取失败时保持当前状态
   */
  private async loadFamily(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.family = await this.service.load(context);
      if (this.family !== undefined) {
        FamilyService.applyCurrentMember(this.family);
      }
      this.touchTimestamp();
    } catch (error) {
      // 读取失败时保持当前页面状态，下拉刷新可重试。
    } finally {
      this.loading = false;
    }
  }

  /** 下拉刷新：重新读取家庭数据后结束刷新态 */
  private async refreshData(): Promise<void> {
    await this.loadFamily();
    this.refreshing = false;
  }

  /** 更新统计时间戳文案（精确到分钟） */
  private touchTimestamp(): void {
    const date: Date = new Date();
    const hour: string = date.getHours().toString().padStart(2, '0');
    const minute: string = date.getMinutes().toString().padStart(2, '0');
    this.lastUpdatedLabel = `数据更新于 ${hour}:${minute}`;
  }

  /**
   * 家庭统计结果：家庭页、任务与周报共用同一份口径。
   * 一次渲染会多处读取统计（看板数字、贡献榜、任务与周报），
   * 按 family 与 savedDrafts 的引用作缓存键，数据未变化时直接复用上次结果，
   * 避免每次读取都对全部记录重算一遍。
   */
  private stats(): FamilyStats {
    if (this.statsCache === undefined || this.statsFamilyRef !== this.family ||
      this.statsDraftsRef !== this.savedDrafts) {
      this.statsCache = this.family === undefined
        ? FamilyService.emptyStats()
        : FamilyService.computeStats(this.family, this.savedDrafts);
      this.statsFamilyRef = this.family;
      this.statsDraftsRef = this.savedDrafts;
    }
    return this.statsCache;
  }

  /** 家庭名称；未创建时兜底为页面标题 */
  private familyName(): string {
    return this.family !== undefined ? this.family.familyName : '家庭碳账户';
  }

  /** 成员数量 */
  private memberCount(): number {
    return this.family !== undefined ? this.family.members.length : 0;
  }

  /** 本周家庭目标（kg CO₂e） */
  private weeklyGoal(): number {
    return this.family !== undefined ? this.family.weeklyGoalKg : 10;
  }

  /** 当前记录身份昵称 */
  private currentMemberName(): string {
    if (this.family === undefined) {
      return '';
    }
    const member: FamilyMember | undefined = this.family.members.find((item: FamilyMember): boolean =>
      item.memberId === this.family?.currentMemberId);
    return member !== undefined ? member.nickname : '';
  }

  /** 成员贡献榜的最大累计值，贡献占比条按此归一化 */
  private maxMemberKg(): number {
    return this.stats().members.reduce((max: number, row: MemberContribution): number =>
      Math.max(max, row.totalKg), 1);
  }

  /** 行为构成的最大减排量，构成条按此归一化 */
  private maxBehaviorKg(): number {
    return this.stats().behaviors.reduce((max: number, row: BehaviorBreakdown): number =>
      Math.max(max, row.kg), 0.01);
  }

  /** 本周尚未发布的任务库条目 */
  private publishableTasks(): FamilyTaskDef[] {
    const family: FamilySnapshot | undefined = this.family;
    if (family === undefined) {
      return [];
    }
    const weekKey: string = FamilyService.weekKeyOf(Date.now());
    return FAMILY_TASK_LIBRARY.filter((def: FamilyTaskDef): boolean =>
      !family.tasks.some((task): boolean => task.taskId === `${def.id}-${weekKey}`));
  }

  /** 本周进行中的任务（发布当周有效） */
  private activeTasks(): FamilyTaskProgress[] {
    return this.stats().tasks.filter((item: FamilyTaskProgress): boolean => item.active);
  }

  /** 本周已结束的近期任务，仅回看展示 */
  private expiredTasks(): FamilyTaskProgress[] {
    return this.stats().tasks.filter((item: FamilyTaskProgress): boolean => !item.active);
  }

  /**
   * 显示 Toast 提示
   * @param message 提示文案
   */
  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (error) {
      // 提示失败不影响页面内容。
    }
  }

  /** 创建家庭：成功后进入家庭主页 */
  private async createFamily(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot = await this.service.create(context,
        this.familyNameText, this.goalChoiceKg, this.ownerNameText);
      this.family = snapshot;
      this.creating = false;
      this.touchTimestamp();
      this.showToast('家庭创建成功');
    } catch (error) {
      this.showToast('创建失败，请稍后重试');
    }
  }

  /** 添加成员档案：昵称必填，成功后收起表单 */
  private async confirmAddMember(): Promise<void> {
    if (this.newMemberName.trim().length === 0) {
      this.showToast('请填写成员昵称');
      return;
    }
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot | undefined = await this.service.addMember(context, this.newMemberName);
      if (snapshot === undefined) {
        this.showToast('添加失败，请稍后重试');
        return;
      }
      this.family = snapshot;
      this.addingMember = false;
      this.newMemberName = '';
      this.touchTimestamp();
      this.showToast('成员已添加');
    } catch (error) {
      this.showToast('添加失败，请稍后重试');
    }
  }

  /** 保存成员改名 */
  private async confirmRename(member: FamilyMember): Promise<void> {
    if (this.renameText.trim().length === 0) {
      this.showToast('昵称不能为空');
      return;
    }
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot | undefined =
        await this.service.renameMember(context, member.memberId, this.renameText);
      if (snapshot === undefined) {
        this.showToast('改名失败，请稍后重试');
        return;
      }
      this.family = snapshot;
      this.renamingMemberId = '';
      this.touchTimestamp();
      this.showToast('昵称已更新');
    } catch (error) {
      this.showToast('改名失败，请稍后重试');
    }
  }

  /** 删除成员前二次确认：历史记录保留但不再参与家庭统计 */
  private confirmRemove(member: FamilyMember): void {
    this.getUIContext().showAlertDialog({
      title: '删除成员',
      message: `删除后 ${member.nickname} 的历史记录仍保留在日记中，但不再参与家庭统计。`,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#B4532A',
        action: (): void => {
          this.removeMember(member);
        }
      }
    });
  }

  /** 删除成员档案；删除当前记录身份时由服务层回落到管理员 */
  private async removeMember(member: FamilyMember): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot | undefined = await this.service.removeMember(context, member.memberId);
      if (snapshot === undefined) {
        this.showToast('删除失败，请稍后重试');
        return;
      }
      this.family = snapshot;
      this.touchTimestamp();
      this.showToast('成员已删除');
    } catch (error) {
      this.showToast('删除失败，请稍后重试');
    }
  }

  /** 切换当前记录身份：之后保存的记录归属该成员 */
  private async switchTo(member: FamilyMember): Promise<void> {
    if (this.family !== undefined && member.memberId === this.family.currentMemberId) {
      this.showToast(`当前已经是 ${member.nickname} 的记录身份`);
      return;
    }
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot | undefined = await this.service.switchMember(context, member.memberId);
      if (snapshot === undefined) {
        this.showToast('切换失败，请稍后重试');
        return;
      }
      this.family = snapshot;
      this.touchTimestamp();
      this.showToast(`已切换到 ${member.nickname} 的记录身份`);
    } catch (error) {
      this.showToast('切换失败，请稍后重试');
    }
  }

  /** 发布本周任务：同一任务每周最多发布一次，由服务层按周键去重 */
  private async publishTask(def: FamilyTaskDef): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: FamilySnapshot | undefined = await this.service.publishTask(context, def);
      if (snapshot === undefined) {
        this.showToast('发布失败，请稍后重试');
        return;
      }
      this.family = snapshot;
      this.touchTimestamp();
      this.showToast(`已发布任务：${def.title}`);
    } catch (error) {
      this.showToast('发布失败，请稍后重试');
    }
  }

  /** 通过系统分享面板分享家庭周报；截图失败时回退为文字分享。 */
  private async shareReport(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const pixelMap = await this.getUIContext().getComponentSnapshot().get('family-report-root');
      // 固定文件名复写同一张缓存图，避免每次分享都在 cacheDir 里堆积新文件
      const imagePath: string = `${context.cacheDir}/tanji-family-report.jpg`;
      const file = await fileIo.open(imagePath, fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const packer: image.ImagePacker = image.createImagePacker();
        await packer.packToFile(pixelMap, file.fd, { format: 'image/jpeg', quality: 95 });
        await packer.release();
      } finally {
        await fileIo.close(file);
      }
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.image',
        uri: fileUri.getUriFromPath(imagePath),
        title: '家庭低碳周报',
        label: 'IMAGE',
        description: '来自碳记的家庭碳账户'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(context, {});
      return;
    } catch (imageError) {
      // 周报截图失败时继续使用文字分享，保证分享按钮仍可用。
    }
    try {
      const stats: FamilyStats = this.stats();
      const content: string =
        `${this.familyName()} 家庭低碳周报（${stats.weekRangeLabel}）\n` +
        `本周家庭共减少 ${stats.weekKg.toFixed(1)} kg CO₂e\n` +
        `完成低碳行为 ${stats.weekActions} 次\n` +
        `参与成员 ${stats.weekActiveMembers} 人\n` +
        `完成家庭任务 ${stats.completedTasks} 项\n` +
        `相当于少开燃油车约 ${stats.equivalentKm.toFixed(1)} km（估算）`;
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.text',
        content: content,
        title: '家庭低碳周报',
        label: 'TEXT'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(context, {});
    } catch (err) {
      this.showToast('暂时无法打开系统分享面板');
    }
  }

  /**
   * 成员头像：彩色圆底 + 昵称首字，家庭场景不使用真实照片保护隐私
   * @param color 头像底色
   * @param nickname 成员昵称
   * @param size 直径（vp）
   */
  @Builder
  private Avatar(color: string, nickname: string, size: number) {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .backgroundColor(color)
      Text(nickname.length > 0 ? nickname.substring(0, 1) : '家')
        .fontSize(Math.round(size * 0.4))
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
  }

  /**
   * 家庭主页顶栏：返回 + 家庭名 + 成员数
   */
  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Text('‹')
          .fontSize(40)
          .fontColor('#174E3A')
      }
      .width(44)
      .height(48)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回我的')
      .onClick((): void => {
        this.onBack?.();
      })
      Text(this.familyName())
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123F2E')
        .layoutWeight(1)
        .maxLines(1)
        .textAlign(TextAlign.Center)
      Text(`${this.memberCount()} 人`)
        .fontSize(12)
        .fontColor('#4C8067')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#EAF2E8')
        .borderRadius(11)
    }
    .width('100%')
    .height(58)
    .padding({ left: 10, right: 14 })
  }

  /**
   * 页签栏：看板 / 成员 / 任务 / 周报
   */
  @Builder
  private TabBar() {
    Row({ space: 8 }) {
      ForEach(this.tabs, (tab: string) => {
        Button(tab, { type: ButtonType.Normal, stateEffect: false })
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .fontColor(this.tab === tab ? '#FFFFFF' : '#64776D')
          .backgroundColor(this.tab === tab ? '#4C9576' : '#EAF2E8')
          .borderRadius(16)
          .accessibilityText(this.tab === tab ? `${tab}，当前栏目` : tab)
          .onClick(() => {
            this.tab = tab;
          })
      }, (tab: string): string => tab)
    }
    .width('100%')
    .padding({ left: 19, right: 19, top: 4, bottom: 10 })
  }

  /**
   * 家庭累计减排总览卡：大数字 + 今日/本周/本月三项小统计
   */
  @Builder
  private OverviewCard() {
    Column({ space: 10 }) {
      Row() {
        Text('家庭累计减排')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text(`${this.memberCount()} 位成员`)
          .fontSize(12)
          .fontColor('#5E776A')
      }
      .width('100%')
      Row({ space: 4 }) {
        Text(this.stats().totalKg.toFixed(2))
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#174E3A')
        Text('kg CO₂e')
          .fontSize(14)
          .fontColor('#4C8067')
          .margin({ bottom: 5 })
      }
      .alignItems(VerticalAlign.Bottom)
      Divider()
        .color('#CBE1CB')
        .strokeWidth(1)
      Row() {
        Column({ space: 3 }) {
          Text(this.stats().todayKg.toFixed(2))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#246244')
          Text('今日')
            .fontSize(11)
            .fontColor('#5E776A')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Column({ space: 3 }) {
          Text(this.stats().weekKg.toFixed(2))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#246244')
          Text('本周')
            .fontSize(11)
            .fontColor('#5E776A')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Column({ space: 3 }) {
          Text(this.stats().monthKg.toFixed(2))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#246244')
          Text('本月')
            .fontSize(11)
            .fontColor('#5E776A')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#EAF3E7')
    .borderRadius(16)
  }

  /**
   * 本周家庭目标卡：目标值 + 进度条 + 完成百分比
   */
  @Builder
  private GoalCard() {
    Column({ space: 8 }) {
      Row() {
        Text('本周家庭目标')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text(`目标 ${this.weeklyGoal()} kg CO₂e`)
          .fontSize(12)
          .fontColor('#718078')
      }
      .width('100%')
      Progress({ value: this.stats().goalPercent, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(10)
        .color('#4C9576')
        .backgroundColor('#E2EDE2')
        .borderRadius(5)
      Row() {
        Text(`本周已减排 ${this.stats().weekKg.toFixed(2)} kg · 完成 ${this.stats().goalPercent}%`)
          .fontSize(12)
          .fontColor('#4C8067')
        Blank()
        Text(this.stats().goalPercent >= 100 ? '本周目标已达成' : '全家继续加油')
          .fontSize(12)
          .fontColor(this.stats().goalPercent >= 100 ? '#4C9576' : '#8A968F')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 成员贡献榜：按累计减排排序，标签使用"本周贡献最多/新成员"等友好表达
   */
  @Builder
  private ContributionCard() {
    Column({ space: 12 }) {
      Row() {
        Text('成员贡献')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text('按累计减排排序')
          .fontSize(11)
          .fontColor('#87938C')
      }
      .width('100%')
      if (this.stats().members.length === 0) {
        Text('还没有成员数据')
          .fontSize(13)
          .fontColor('#8A968F')
      } else {
        ForEach(this.stats().members, (row: MemberContribution) => {
          this.MemberRow(row)
        }, (row: MemberContribution): string => row.memberId)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 单条成员贡献行：头像 + 昵称与标签 + 累计/本周数值 + 贡献占比条
   * @param row 成员贡献数据
   */
  @Builder
  private MemberRow(row: MemberContribution) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        this.Avatar(row.avatarColor, row.nickname, 38)
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(row.nickname)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#173F2E')
            if (row.role === 'admin') {
              Text('管理员')
                .fontSize(10)
                .fontColor('#9A7A3C')
                .backgroundColor('#F5EAD4')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
            if (row.isTop) {
              Text('本周贡献最多')
                .fontSize(10)
                .fontColor('#4C8067')
                .backgroundColor('#E3F0E3')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            } else if (row.isNew) {
              Text('新成员')
                .fontSize(10)
                .fontColor('#4C8067')
                .backgroundColor('#E3F0E3')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }
          Text(`累计 ${row.totalKg.toFixed(2)} kg · 本周 ${row.weekKg.toFixed(2)} kg · ${row.actionCount} 次记录`)
            .fontSize(11)
            .fontColor('#839087')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      // 贡献占比条：按成员头像色填充，直观对比各成员贡献
      Row() {
        Row()
          .width(`${Math.round(row.totalKg / this.maxMemberKg() * 100)}%`)
          .height(5)
          .borderRadius(3)
          .backgroundColor(row.avatarColor)
      }
      .width('100%')
      .height(5)
      .backgroundColor('#EDF2EA')
      .borderRadius(3)
    }
    .width('100%')
  }

  /**
   * 家庭行为构成：按减排量降序展示各低碳行为的累计贡献
   */
  @Builder
  private BehaviorCard() {
    Column({ space: 12 }) {
      Row() {
        Text('家庭行为构成')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Blank()
        Text('按减排量排序')
          .fontSize(11)
          .fontColor('#87938C')
      }
      .width('100%')
      if (this.stats().behaviors.length === 0) {
        Text('还没有已核验的家庭记录，保存一条核验记录后就会出现在这里')
          .fontSize(13)
          .fontColor('#8A968F')
      } else {
        ForEach(this.stats().behaviors, (item: BehaviorBreakdown) => {
          Column({ space: 6 }) {
            Row() {
              Text(item.name)
                .fontSize(14)
                .fontColor('#365C4B')
              Blank()
              Text(`${item.kg.toFixed(2)} kg · ${item.count} 次`)
                .fontSize(12)
                .fontColor('#4C8067')
            }
            .width('100%')
            Row() {
              Row()
                .width(`${Math.round(item.kg / this.maxBehaviorKg() * 100)}%`)
                .height(5)
                .borderRadius(3)
                .backgroundColor('#4C9576')
            }
            .width('100%')
            .height(5)
            .backgroundColor('#EDF2EA')
            .borderRadius(3)
          }
          .width('100%')
        }, (item: BehaviorBreakdown): string => item.name)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#DDE8DE' })
    .borderRadius(14)
  }

  /**
   * 看板页签：总览、周目标、成员贡献与行为构成
   */
  @Builder
  private DashboardTab() {
    Column({ space: 12 }) {
      this.OverviewCard()
      this.GoalCard()
      this.ContributionCard()
      this.BehaviorCard()
    }
    .width('100%')
  }

  /**
   * 成员管理行：点击整行切换记录身份，附改名与删除入口
   * @param member 成员档案
   */
  @Builder
  private MemberManageRow(member: FamilyMember) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        this.Avatar(member.avatarColor, member.nickname, 38)
        Column({ space: 3 }) {
          Text(member.nickname)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#173F2E')
          Text(member.role === 'admin' ? '管理员 · 创建者' : '成员档案')
            .fontSize(11)
            .fontColor('#839087')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.family !== undefined && member.memberId === this.family.currentMemberId) {
          Text('当前')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#4C9576')
            .borderRadius(8)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      .accessibilityText(
        this.family !== undefined && member.memberId === this.family.currentMemberId
          ? `${member.nickname}，当前身份`
          : `切换到${member.nickname}`
      )
      .onClick(() => {
        this.switchTo(member);
      })
      // 改名表单：进行中时替换操作按钮行，避免同时出现两套输入
      if (this.renamingMemberId === member.memberId) {
        Row({ space: 8 }) {
          TextInput({ text: this.renameText, placeholder: '输入新昵称' })
            .maxLength(12)
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .fontColor('#365C4B')
            .backgroundColor('#FAFCF8')
            .border({ width: 1, color: '#D5E4D8' })
            .borderRadius(10)
            .onChange((value: string) => {
              this.renameText = value;
            })
          Button('保存', { type: ButtonType.Normal, stateEffect: false })
            .height(32)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor('#4C9576')
            .borderRadius(16)
            .onClick(() => {
              this.confirmRename(member);
            })
          Button('取消', { type: ButtonType.Normal, stateEffect: false })
            .height(32)
            .fontSize(12)
            .fontColor('#64776D')
            .backgroundColor('#EAF2E8')
            .borderRadius(16)
            .onClick(() => {
              this.renamingMemberId = '';
            })
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          Button('改名', { type: ButtonType.Normal, stateEffect: false })
            .height(30)
            .fontSize(12)
            .fontColor('#64776D')
            .backgroundColor('#EAF2E8')
            .borderRadius(15)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.renamingMemberId = member.memberId;
              this.renameText = member.nickname;
            })
          if (member.role !== 'admin') {
            Button('删除', { type: ButtonType.Normal, stateEffect: false })
              .height(30)
              .fontSize(12)
              .fontColor('#B4532A')
              .backgroundColor('#F7E8DF')
              .borderRadius(15)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.confirmRemove(member);
              })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#E1E9DF' })
    .borderRadius(12)
  }

  /**
   * 成员页签：当前记录身份提示、成员列表与添加入口
   */
  @Builder
  private MembersTab() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.diary_person'))
          .syncLoad(true)
          .width(16)
          .height(16)
          .opacity(0.7)
        Text(`当前记录身份：${this.currentMemberName()}，之后保存的记录将计入 TA 的家庭贡献`)
          .fontSize(12)
          .fontColor('#4C8067')
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#EAF2E8')
      .borderRadius(10)

      Column({ space: 10 }) {
        Row() {
          Text('家庭成员')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173F2E')
          Blank()
          Text('点击成员切换记录身份')
            .fontSize(11)
            .fontColor('#87938C')
        }
        .width('100%')
        ForEach(this.family?.members ?? [], (member: FamilyMember) => {
          this.MemberManageRow(member)
        }, (member: FamilyMember): string => member.memberId)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E1E9DF' })
      .borderRadius(14)

      if (this.addingMember) {
        Column({ space: 10 }) {
          Text('新成员昵称')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#365C4B')
          TextInput({ placeholder: '如：爸爸、妈妈、同学小林', text: this.newMemberName })
            .maxLength(12)
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor('#365C4B')
            .backgroundColor('#FAFCF8')
            .border({ width: 1, color: '#D5E4D8' })
            .borderRadius(12)
            .onChange((value: string) => {
              this.newMemberName = value;
            })
          Row({ space: 8 }) {
            Button('添加', { type: ButtonType.Normal, stateEffect: false })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#4C9576')
              .borderRadius(18)
              .onClick(() => {
                this.confirmAddMember();
              })
            Button('取消', { type: ButtonType.Normal, stateEffect: false })
              .layoutWeight(1)
              .height(36)
              .fontSize(14)
              .fontColor('#64776D')
              .backgroundColor('#EAF2E8')
              .borderRadius(18)
              .onClick(() => {
                this.addingMember = false;
                this.newMemberName = '';
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FAFBF6')
        .border({ width: 1, color: '#DDE8DE' })
        .borderRadius(14)
      } else {
        Button('＋ 添加成员档案', { type: ButtonType.Normal, stateEffect: false })
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor('#376D52')
          .backgroundColor('#E5F0E5')
          .borderRadius(21)
          .onClick(() => {
            this.addingMember = true;
          })
      }
      Text('成员档案保存在本机，用于在同一台设备上演示多人协作记录。')
        .fontSize(11)
        .fontColor('#8A968F')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  /**
   * 本周任务行：标题、说明与各成员达成状态；达成由核验记录自动判定
   * @param progress 任务进度
   */
  @Builder
  private TaskRow(progress: FamilyTaskProgress) {
    Column({ space: 8 }) {
      Row() {
        Text(progress.task.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173F2E')
          .layoutWeight(1)
        if (progress.completedMemberIds.length > 0) {
          Text('已达成')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#4C9576')
            .borderRadius(8)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        } else {
          Text('进行中')
            .fontSize(10)
            .fontColor('#839087')
            .backgroundColor('#EDF2EA')
            .borderRadius(8)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      Text(progress.task.description)
        .fontSize(12)
        .fontColor('#78867D')
        .width('100%')
      // 成员达成状态：绿色为已达成，灰色为进行中
      Row({ space: 6 }) {
        ForEach(this.family?.members ?? [], (member: FamilyMember) => {
          Text(`${member.nickname} ${progress.completedMemberIds.includes(member.memberId) ? '✓' : '·'}`)
            .fontSize(11)
            .fontColor(progress.completedMemberIds.includes(member.memberId) ? '#FFFFFF' : '#839087')
            .backgroundColor(progress.completedMemberIds.includes(member.memberId) ? '#4C9576' : '#EDF2EA')
            .borderRadius(10)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }, (member: FamilyMember): string => `${progress.task.taskId}-${member.memberId}`)
      }
      .width('100%')
      Text(`达成条件：发布当周完成 ${progress.task.targetCount} 次已核验记录`)
        .fontSize(11)
        .fontColor('#8A968F')
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#E1E9DF' })
    .borderRadius(12)
  }

  /**
   * 任务库行：标题、说明与发布按钮
   * @param def 任务库定义
   */
  @Builder
  private TaskDefRow(def: FamilyTaskDef) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(def.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#365C4B')
        Text(def.description)
          .fontSize(11)
          .fontColor('#839087')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button('发布', { type: ButtonType.Normal, stateEffect: false })
        .height(30)
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor('#4C9576')
        .borderRadius(15)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.publishTask(def);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#E1E9DF' })
    .borderRadius(12)
  }

  /**
   * 任务页签：规则说明、本周任务与任务库
   */
  @Builder
  private TasksTab() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.diary_leaf'))
          .syncLoad(true)
          .width(16)
          .height(16)
          .opacity(0.7)
        Text('家庭任务由已核验记录自动判定完成，不能手动领取；待核实记录不计入任务进度。')
          .fontSize(12)
          .fontColor('#4C8067')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#EAF2E8')
      .borderRadius(10)

      Column({ space: 10 }) {
        Row() {
          Text('本周任务')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173F2E')
          Blank()
          Text(`已达成 ${this.stats().completedTasks} 项`)
            .fontSize(11)
            .fontColor('#87938C')
        }
        .width('100%')
        if (this.activeTasks().length === 0) {
          Text('还没有发布本周任务，从下方任务库发布一个吧')
            .fontSize(13)
            .fontColor('#8A968F')
        } else {
          ForEach(this.activeTasks(), (progress: FamilyTaskProgress) => {
            this.TaskRow(progress)
          }, (progress: FamilyTaskProgress): string => progress.task.taskId)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E1E9DF' })
      .borderRadius(14)

      Column({ space: 10 }) {
        Text('发布本周任务')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
          .width('100%')
        if (this.publishableTasks().length === 0) {
          Text('本周任务已全部发布')
            .fontSize(13)
            .fontColor('#8A968F')
        } else {
          ForEach(this.publishableTasks(), (def: FamilyTaskDef) => {
            this.TaskDefRow(def)
          }, (def: FamilyTaskDef): string => def.id)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E1E9DF' })
      .borderRadius(14)

      // 近几周已结束的任务，仅回看展示
      if (this.expiredTasks().length > 0) {
        Column({ space: 10 }) {
          Text('已结束的任务')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173F2E')
            .width('100%')
          ForEach(this.expiredTasks(), (progress: FamilyTaskProgress) => {
            Row() {
              Text(progress.task.title)
                .fontSize(13)
                .fontColor('#839087')
                .layoutWeight(1)
              Text(progress.completedMemberIds.length > 0 ? '曾有成员达成' : '未达成')
                .fontSize(11)
                .fontColor('#9AA8A1')
            }
            .width('100%')
          }, (progress: FamilyTaskProgress): string => progress.task.taskId)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FAFBF6')
        .border({ width: 1, color: '#E1E9DF' })
        .borderRadius(14)
      }
    }
    .width('100%')
  }

  /**
   * 周报页签：家庭低碳周报卡片（可截图分享）
   */
  @Builder
  private ReportTab() {
    Column({ space: 12 }) {
      // 周报卡片：分享截图的根节点，只含昵称与统计数据，保护成员隐私
      Column({ space: 10 }) {
        Row() {
          Text(`${this.familyName()} · 家庭低碳周报`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
            .layoutWeight(1)
          Text('碳记')
            .fontSize(12)
            .fontColor('#4C8067')
        }
        .width('100%')
        Text(this.stats().weekRangeLabel)
          .fontSize(12)
          .fontColor('#839087')
        Divider()
          .color('#E3EBE0')
          .strokeWidth(1)
        Column({ space: 4 }) {
          Text(`${this.stats().weekKg.toFixed(1)} kg CO₂e`)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#07553D')
          Text('本周家庭共减少')
            .fontSize(12)
            .fontColor('#718078')
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        Column({ space: 8 }) {
          ForEach(this.reportLines(), (line: string) => {
            Text(line)
              .fontSize(13)
              .fontColor('#567064')
              .width('100%')
          }, (line: string, index: number): string => `${index}-${line}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        Divider()
          .color('#E3EBE0')
          .strokeWidth(1)
        Text('周报只展示成员昵称与统计数据 · 燃油车按 0.175 kg CO₂e/km 估算')
          .fontSize(10)
          .fontColor('#9AA8A1')
          .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .border({ width: 1.5, color: '#BFD8BE' })
      .borderRadius(16)
      .id('family-report-root')

      Button('生成家庭分享卡片', { type: ButtonType.Normal, stateEffect: false })
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#4C9576')
        .borderRadius(21)
        .onClick(() => {
          this.shareReport();
        })
      Text('分享卡片为周报截图，仅包含家庭名称与统计数据。')
        .fontSize(11)
        .fontColor('#8A968F')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  /** 周报数据行文案：与看板共用同一份统计结果 */
  private reportLines(): string[] {
    const stats: FamilyStats = this.stats();
    return [
      `完成低碳行为 ${stats.weekActions} 次`,
      `参与成员 ${stats.weekActiveMembers} 人`,
      `完成家庭任务 ${stats.completedTasks} 项`,
      `相当于少开燃油车约 ${stats.equivalentKm.toFixed(1)} km（估算）`
    ];
  }

  /**
   * 创建引导视图：功能说明 + 创建/暂不使用按钮
   */
  @Builder
  private GuideView() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(84)
          .height(84)
          .borderRadius(42)
          .backgroundColor('#EAF2E8')
        Image($r('app.media.diary_person'))
          .syncLoad(true)
          .width(44)
          .height(44)
      }
      .margin({ top: 36 })
      Text('家庭碳账户')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123F2E')
      Text('多人协作记录低碳行为，共同完成家庭减排目标')
        .fontSize(14)
        .fontColor('#718078')
      Column({ space: 8 }) {
        this.GuideLine('在一台设备上创建家庭成员档案')
        this.GuideLine('保存的已核验记录自动汇总到家庭看板')
        this.GuideLine('家庭任务由真实记录驱动，周报一键分享')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor('#FAFBF6')
      .border({ width: 1, color: '#DDE8DE' })
      .borderRadius(14)
      Button('创建家庭', { type: ButtonType.Normal, stateEffect: false })
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .backgroundColor('#4C9576')
        .borderRadius(23)
        .margin({ top: 8 })
        .onClick(() => {
          this.creating = true;
        })
      Button('暂不使用', { type: ButtonType.Normal, stateEffect: false })
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor('#64776D')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onBack?.();
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 560 })
    .padding({ left: 24, right: 24 })
  }

  /**
   * 引导说明行
   * @param text 说明文案
   */
  @Builder
  private GuideLine(text: string) {
    Row({ space: 8 }) {
      Text('·')
        .fontSize(14)
        .fontColor('#4C9576')
      Text(text)
        .fontSize(13)
        .fontColor('#567064')
        .layoutWeight(1)
    }
    .width('100%')
  }

  /**
   * 创建家庭表单：家庭名称、周目标、创建者昵称
   */
  @Builder
  private CreateView() {
    Column() {
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Text('‹')
            .fontSize(40)
            .fontColor('#174E3A')
        }
        .width(44)
        .height(48)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick((): void => {
          this.creating = false;
        })
        Text('创建家庭')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(44)
      }
      .width('100%')
      .height(58)
      .padding({ left: 10, right: 10 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Text('家庭名称')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#365C4B')
              .width('100%')
            TextInput({ placeholder: '如：绿色小家', text: this.familyNameText })
              .maxLength(12)
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor('#365C4B')
              .backgroundColor('#FAFCF8')
              .border({ width: 1, color: '#D5E4D8' })
              .borderRadius(12)
              .onChange((value: string) => {
                this.familyNameText = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 8 }) {
            Text('本周家庭减排目标')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#365C4B')
              .width('100%')
            Row({ space: 8 }) {
              ForEach(this.goalOptions, (kg: number) => {
                Button(`${kg} kg`, { type: ButtonType.Normal, stateEffect: false })
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(13)
                  .fontColor(this.goalChoiceKg === kg ? '#FFFFFF' : '#64776D')
                  .backgroundColor(this.goalChoiceKg === kg ? '#4C9576' : '#EAF2E8')
                  .borderRadius(17)
                  .onClick(() => {
                    this.goalChoiceKg = kg;
                  })
              }, (kg: number): string => kg.toString())
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 8 }) {
            Text('你的昵称（家庭管理员）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#365C4B')
              .width('100%')
            TextInput({ placeholder: '如：小碳', text: this.ownerNameText })
              .maxLength(12)
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor('#365C4B')
              .backgroundColor('#FAFCF8')
              .border({ width: 1, color: '#D5E4D8' })
              .borderRadius(12)
              .onChange((value: string) => {
                this.ownerNameText = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Button('创建家庭', { type: ButtonType.Normal, stateEffect: false })
            .width('100%')
            .height(46)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#4C9576')
            .borderRadius(23)
            .margin({ top: 6 })
            .onClick(() => {
              this.createFamily();
            })
          Text('创建后你将成为家庭管理员，可添加成员档案、发布任务与查看周报。')
            .fontSize(11)
            .fontColor('#8A968F')
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .constraintSize({ maxWidth: 620 })
        .padding({ left: 19, right: 19, top: 10, bottom: 30 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 家庭主页：顶栏 + 页签 + 更新时间戳 + 下拉刷新内容区
   */
  @Builder
  private MainView() {
    Column() {
      this.TopBar()
      this.TabBar()
      // 统计更新时间戳：进入页面、切换成员与下拉刷新时更新
      Text(this.lastUpdatedLabel)
        .fontSize(11)
        .fontColor('#9AA8A1')
        .margin({ bottom: 6 })
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            if (this.tab === '看板') {
              this.DashboardTab()
            } else if (this.tab === '成员') {
              this.MembersTab()
            } else if (this.tab === '任务') {
              this.TasksTab()
            } else {
              this.ReportTab()
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 620 })
          .padding({ left: 19, right: 19, top: 4, bottom: 40 })
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
      .onRefreshing(() => {
        this.refreshData();
      })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 页面布局
   * 按状态切换三种视图：加载中 / 创建引导（或创建表单） / 家庭主页
   */
  build() {
    Column() {
      if (this.loading) {
        Column() {
          Text('正在读取家庭数据')
            .fontSize(15)
            .fontColor('#718078')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.family === undefined) {
        Scroll() {
          Column() {
            if (this.creating) {
              this.CreateView()
            } else {
              this.GuideView()
            }
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      } else {
        this.MainView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
  }
}

/**
 * 家庭页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 FamilyPage 组件，不参与实际页面路由
 */
@Preview({
  title: 'FamilyPage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct FamilyPagePreview {
  build() {
    // 直接渲染家庭碳账户组件（未创建家庭时显示创建引导）
    FamilyPage()
  }
}
