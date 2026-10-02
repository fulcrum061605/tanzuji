/**
 * 我的页面。
 * 个人概览与知识文章收藏共用 KnowledgeService 的 Preferences 数据，
 * 因此在成长页收藏的文章会立即出现在“我的收藏”中，并支持离线打开。
 */
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { KnowledgeArticle, KnowledgeService } from '../services/KnowledgeService';
import { CarbonPointsService, PointsReward, PointsSnapshot } from '../services/CarbonPointsService';
import { RecordDraft } from './RecordDetail';
import { BackupPayload, BackupService } from '../services/BackupService';

/**
 * 判断当前设备是否具备液态玻璃（沉浸式系统材质）能力
 * 需同时满足：系统软件 API 不低于 26 且设备声明支持沉浸式材质；
 * 短路求值保证低版本系统不会调用 isImmersiveMaterialSupported。
 * @returns true 表示可以使用 ImmersiveMaterial 液态玻璃
 */
function isGlassCapable(): boolean {
  return deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported();
}

/**
 * 我的页组件
 * 三种视图：文章详情（打开收藏文章时） / 我的收藏列表 / 个人主页（概览 + 菜单入口 + 底部导航）。
 * 收藏数据与成长页共用同一 Preferences 存储，跨页即时同步。
 */
@Component
export struct MyPage {
  /** 由入口容器切换到其他底部栏目。 */
  @Prop selectedTab: string = '我的';
  /** 切换底部栏目回调：参数为目标栏目名，由入口页完成页面切换 */
  onNavigate?: (tab: string) => void;
  /** 从入口页传入的全部已保存记录：备份、恢复与 CSV 报表使用 */
  @Prop savedDrafts: RecordDraft[] = [];
  /** 恢复备份后回传记录列表，由入口页更新数据并落盘 */
  onRestoreRecords?: (records: RecordDraft[]) => void;
  /** 全部文章列表：用于渲染收藏项与详情 */
  @State private articles: KnowledgeArticle[] = [];
  /** 已收藏的文章 id 列表 */
  @State private favoriteIds: string[] = [];
  /** 是否显示"我的收藏"列表视图 */
  @State private showingFavorites: boolean = false;
  /** 是否显示积分与模拟权益中心 */
  @State private showingRewards: boolean = false;
  /** 是否显示数据管理视图 */
  @State private showingDataManagement: boolean = false;
  /** 最近一次导出的 CSV 报表内容；空串时不显示预览区 */
  @State private csvPreview: string = '';
  /** 当前打开的收藏文章 id：非空时进入文章详情视图 */
  @State private openedArticleId: string = '';
  /** 内容加载中标记 */
  @State private loading: boolean = true;
  /** 当前按下的底部栏目，用于与主页保持一致的轻微按压反馈。 */
  @State private pressedTab: string = '';
  /** 当前可用碳积分余额 */
  @State private points: number = 0;
  /** 累计获得积分（含已兑换消耗的部分） */
  @State private totalEarnedPoints: number = 0;
  /** 今日是否已签到：由积分快照中的签到任务键推算 */
  @State private claimedCheckIn: boolean = false;
  /** 已兑换（已领取）的模拟权益 id 列表 */
  @State private redeemedRewardIds: string[] = [];
  /** 签到请求进行中标记：防止重复点击 */
  @State private checkingIn: boolean = false;
  /** 正在兑换的权益 id：空串表示没有进行中的兑换 */
  @State private redeemingRewardId: string = '';
  /** 知识服务实例：负责文章加载与收藏持久化 */
  private service: KnowledgeService = new KnowledgeService();
  /** 本地积分服务：负责签到、核验入账与权益兑换的持久化 */
  private pointsService: CarbonPointsService = new CarbonPointsService();
  /** 本地备份服务：负责备份、恢复与 CSV 报表 */
  private backupService: BackupService = new BackupService();

  /** 可兑换的模拟权益清单：仅用于演示，兑换结果只保存在本机 */
  private readonly rewardItems: PointsReward[] = [
    { id: 'green-badge', title: '校园绿能徽章', description: '虚拟徽章，兑换后展示在碳记权益记录中', cost: 30 },
    { id: 'tree-certificate', title: '虚拟植树证书', description: '模拟生成一张低碳行动纪念证书', cost: 80 },
    { id: 'travel-coupon', title: '低碳出行优惠券', description: '模拟权益码：GREEN-TRAVEL-2026', cost: 120 }
  ];
  /** 底部导航条的液态玻璃材质：薄样式 + 低不透明度淡绿赋色；不具备能力的设备为 undefined */
  private navBarMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#59E6EEDF'
    })
    : undefined;

  /** 组件即将出现：加载文章与收藏列表 */
  aboutToAppear(): void {
    this.loadFavorites();
    this.loadPoints();
  }

  /**
   * 读取本机积分快照并刷新页面状态
   * 余额、累计积分、今日签到态与已兑换权益一次性同步；读取失败时提示
   */
  private async loadPoints(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const snapshot: PointsSnapshot = await this.pointsService.load(context);
      this.points = snapshot.balance;
      this.totalEarnedPoints = snapshot.totalEarned;
      this.claimedCheckIn = snapshot.claimedTaskKeys.includes(`check-in-${this.todayKey()}`);
      this.redeemedRewardIds = snapshot.redeemedRewardIds;
    } catch (error) {
      this.showToast('积分数据暂时无法读取');
    }
  }

  /** 生成本地日期键（yyyy-MM-dd），与积分服务的签到任务键保持一致 */
  private todayKey(): string {
    const date: Date = new Date();
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  }

  /**
   * 每日签到：领取固定 5 积分
   * 签到中或已签到时直接返回；结果与失败场景均以 Toast 提示
   */
  private async checkIn(): Promise<void> {
    if (this.checkingIn || this.claimedCheckIn) {
      return;
    }
    this.checkingIn = true;
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result = await this.pointsService.checkIn(context);
      this.showToast(result.message);
      await this.loadPoints();
    } catch (error) {
      this.showToast('签到暂时不可用');
    } finally {
      this.checkingIn = false;
    }
  }

  /**
   * 兑换模拟权益：扣除对应积分并记录权益 id
   * @param reward 待兑换的权益项
   */
  private async redeemReward(reward: PointsReward): Promise<void> {
    if (this.redeemingRewardId !== '' || this.redeemedRewardIds.includes(reward.id) || this.points < reward.cost) {
      return;
    }
    this.redeemingRewardId = reward.id;
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result = await this.pointsService.redeem(context, reward);
      this.showToast(result.message);
      await this.loadPoints();
    } catch (error) {
      this.showToast('兑换暂时不可用');
    } finally {
      this.redeemingRewardId = '';
    }
  }

  /**
   * 加载全部文章与收藏列表
   * 读取失败时提示用户；无论成败都结束加载态
   */
  private async loadFavorites(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.articles = await this.service.loadArticles(context);
      this.favoriteIds = await this.service.loadFavorites(context);
    } catch (error) {
      this.showToast('收藏内容暂时无法读取');
    } finally {
      this.loading = false;
    }
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

  /**
   * 备份当前全部本地数据（记录 + 积分 + 收藏）
   * 成功与失败均以 Toast 提示
   */
  private async backupRecords(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const pointsSnapshot: PointsSnapshot = await this.pointsService.load(context);
      await this.backupService.backup(context, this.savedDrafts, pointsSnapshot, this.favoriteIds);
      this.showToast(`已备份 ${this.savedDrafts.length} 条记录`);
    } catch (error) {
      this.showToast('备份失败，请稍后重试');
    }
  }

  /**
   * 读取最近一次备份并恢复记录、积分与收藏
   * 备份中有记录时先经回调交给入口页更新列表，再持久化积分与收藏
   */
  private async restoreRecords(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const payload: BackupPayload = await this.backupService.restore(context);
      if (payload.records.length > 0) {
        this.onRestoreRecords?.(payload.records);
        await this.pointsService.restoreSnapshot(context, payload.points);
        this.favoriteIds = payload.favoriteIds;
        await this.service.saveFavorites(context, this.favoriteIds);
      }
      this.showToast(payload.records.length === 0 ? '没有可恢复的本地备份' : `已恢复 ${payload.records.length} 条记录、积分和收藏`);
    } catch (error) {
      this.showToast('恢复失败，请稍后重试');
    }
  }

  /**
   * 生成 CSV 报表并在页面下方预览
   * 报表内容同时保存在本机，供重复查看
   */
  private async exportCsvReport(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.csvPreview = await this.backupService.exportCsv(context, this.savedDrafts);
      this.showToast('CSV 报表已生成，可在下方查看');
    } catch (error) {
      this.showToast('报表生成失败，请稍后重试');
    }
  }

  /**
   * 获取收藏的文章列表
   * @returns 全部文章中已被收藏的项
   */
  private favoriteArticles(): KnowledgeArticle[] {
    return this.articles.filter((article: KnowledgeArticle): boolean => this.favoriteIds.includes(article.id));
  }

  /**
   * 获取当前打开的文章
   * @returns 打开的文章；未打开详情时为 undefined
   */
  private openedArticle(): KnowledgeArticle | undefined {
    return this.articles.find((article: KnowledgeArticle): boolean => article.id === this.openedArticleId);
  }

  /**
   * 按插图类型映射文章图标资源
   * @param article 文章数据
   * @returns 对应的图标资源，未知类型回落到叶片图标
   */
  private articleIcon(article: KnowledgeArticle): Resource {
    switch (article.illustration) {
      case 'travel': return $r('app.media.diary_transit');
      case 'electricity': return $r('app.media.diary_electricity');
      case 'food': return $r('app.media.diary_meal');
      case 'recycle': return $r('app.media.diary_recycle');
      case 'campus': return $r('app.media.diary_sprout');
      case 'policy': return $r('app.media.diary_diary');
      default: return $r('app.media.diary_leaf');
    }
  }

  /**
   * 取消收藏指定文章
   * 先更新内存列表（立即刷新界面），再异步持久化到本机
   * @param id 文章唯一标识
   */
  private removeFavorite(id: string): void {
    this.favoriteIds = this.favoriteIds.filter((item: string): boolean => item !== id);
    this.persistFavorites();
    this.showToast('已取消收藏');
  }

  /** 将当前收藏列表持久化到本机，失败时提示重试 */
  private async persistFavorites(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await this.service.saveFavorites(context, this.favoriteIds);
    } catch (error) {
      this.showToast('收藏保存失败，请稍后重试');
    }
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
   * 标题栏：左侧"我的"大标题 + 右侧"碳记"应用名
   */
  @Builder
  private Header() {
    Row() {
      Text('我的')
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123F2E')
      Blank()
      Text('碳记')
        .fontSize(14)
        .fontColor('#718078')
    }
    .width('100%')
    .height(52)
    .padding({ left: 22, right: 22 })
  }

  /**
   * 个人资料区：圆形头像底托 + 昵称与个性签名
   */
  @Builder
  private Profile() {
    Row({ space: 16 }) {
      // 头像：圆形浅绿底托 + 人形图标
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#E2F0E2')
        Image($r('app.media.diary_person'))
          .syncLoad(true)
          .width(35)
          .height(35)
      }
      // 昵称与个性签名
      Column({ space: 5 }) {
        Text('碳记用户')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#173F2E')
        Text('把每一次低碳选择，记成一页日常')
          .fontSize(13)
          .fontColor('#718078')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 14, bottom: 18 })
  }

  /**
   * 概览卡片：收藏文章数 + 离线可读两项统计
   */
  @Builder
  private Overview() {
    Row() {
      // 收藏文章数
      Column({ space: 5 }) {
        Text(`${this.favoriteIds.length}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#246244')
        Text('收藏文章')
          .fontSize(13)
          .fontColor('#718078')
      }
      .layoutWeight(1)
      // 离线可读说明
      Column({ space: 5 }) {
        Text('离线')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#246244')
        Text('随时可读')
          .fontSize(13)
          .fontColor('#718078')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .backgroundColor('#EAF3E7')
    .borderRadius(16)
    .margin({ left: 22, right: 22, bottom: 24 })
  }

  /** 积分入口卡片：余额醒目，但明确展示积分来源和每日上限。 */
  @Builder
  private PointsCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(`${this.points}`)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#174E3A')
          Text('可用碳积分')
            .fontSize(13)
            .fontColor('#5E776A')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('兑换权益', { type: ButtonType.Capsule, stateEffect: true })
          .height(38)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#4C9576')
          .onClick((): void => {
            this.showingRewards = true;
          })
      }
      Row({ space: 8 }) {
        Image($r('app.media.diary_leaf'))
          .syncLoad(true)
          .width(18)
          .height(18)
        Text('积分按核验减排量计算，单条 2–20 分；每日最多 30 分，手动待核实不计分')
          .fontSize(12)
          .fontColor('#718078')
          .maxLines(2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 15 })
    .backgroundColor('#E7F2E7')
    .border({ width: 1, color: '#CFE3D0' })
    .borderRadius(16)
    .margin({ left: 22, right: 22, bottom: 18 })
  }

  /** 每日签到卡片：左侧勾选图标 + 任务说明 + 右侧签到按钮（已签到时置灰） */
  @Builder
  private TaskCard() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#EAF0E5')
        Text('✓')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4C9576')
      }
      Column({ space: 4 }) {
        Text('每日签到')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173F2E')
        Text('每天一次，领取 5 积分')
          .fontSize(12)
          .fontColor('#78867D')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button(this.checkingIn ? '签到中…' : (this.claimedCheckIn ? '已签到' : '签到 +5'), { type: ButtonType.Capsule, stateEffect: true })
        .height(34)
        .fontSize(13)
        .fontColor(this.claimedCheckIn ? '#6B8176' : '#FFFFFF')
        .backgroundColor(this.claimedCheckIn ? '#DDE9DF' : '#4C9576')
        .enabled(!this.claimedCheckIn && !this.checkingIn)
        .onClick((): void => { this.checkIn(); })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 13, bottom: 13 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#E1E9DF' })
    .borderRadius(14)
    .margin({ left: 22, right: 22, bottom: 18 })
  }

  /**
   * 判断指定权益是否已兑换
   * @param reward 权益项
   * @returns true 表示已领取过
   */
  private rewardClaimed(reward: PointsReward): boolean {
    return this.redeemedRewardIds.includes(reward.id);
  }

  /**
   * 单条模拟权益行：图标 + 标题/说明/所需积分 + 右侧兑换按钮
   * 余额不足或已领取时按钮置灰；兑换中显示"兑换中…"
   * @param reward 权益数据
   */
  @Builder
  private RewardRow(reward: PointsReward) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(46)
          .height(46)
          .borderRadius(23)
          .backgroundColor(this.rewardClaimed(reward) ? '#E2E9E3' : '#E6F1E4')
        Image(reward.id === 'tree-certificate' ? $r('app.media.diary_sprout')
          : reward.id === 'travel-coupon' ? $r('app.media.diary_transit') : $r('app.media.diary_leaf'))
          .syncLoad(true)
          .width(28)
          .height(28)
      }
      Column({ space: 4 }) {
        Text(reward.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173F2E')
        Text(reward.description)
          .fontSize(12)
          .fontColor('#78867D')
          .maxLines(2)
        Text(`${reward.cost} 积分`)
          .fontSize(12)
          .fontColor('#4C8067')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button(this.redeemingRewardId === reward.id ? '兑换中…' : (this.rewardClaimed(reward) ? '已领取' : '兑换'), { type: ButtonType.Capsule, stateEffect: true })
        .height(34)
        .fontSize(13)
        .fontColor(this.rewardClaimed(reward) || this.points < reward.cost ? '#8B968E' : '#FFFFFF')
        .backgroundColor(this.rewardClaimed(reward) || this.points < reward.cost ? '#E2EAE3' : '#4C9576')
        .enabled(this.redeemingRewardId === '' && !this.rewardClaimed(reward) && this.points >= reward.cost)
        .onClick((): void => { this.redeemReward(reward); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor('#FAFBF6')
    .border({ width: 1, color: '#E1E9DF' })
    .borderRadius(14)
  }

  /**
   * 积分与权益中心视图
   * 顶部标题行（返回） + 滚动区：积分卡片、签到卡片、可兑换权益列表与累计说明
   */
  @Builder
  private RewardsCenter() {
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
        .accessibilityText('返回我的')
        .onClick((): void => { this.showingRewards = false; })
        Text('积分与权益')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(44)
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })

      Scroll() {
        Column() {
          this.PointsCard()
          this.TaskCard()
          Column({ space: 6 }) {
            Text('兑换模拟权益')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#173F2E')
            Text('权益仅用于比赛演示，兑换结果保存在本机，不连接真实平台。')
              .fontSize(12)
              .fontColor('#78867D')
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 22, right: 22, bottom: 12 })
          ForEach(this.rewardItems, (reward: PointsReward) => {
            this.RewardRow(reward)
          }, (reward: PointsReward): string => reward.id)
          Text(`累计获得 ${this.totalEarnedPoints} 积分 · 核验记录每日上限 30 分`)
            .fontSize(12)
            .fontColor('#8A968F')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 26 })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
  }

  /**
   * 数据管理视图
   * 顶部标题行（返回） + 本地记录工具：备份、恢复与 CSV 报表生成及预览
   */
  @Builder
  private DataManagement() {
    Column() {
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Text('‹').fontSize(40).fontColor('#174E3A')
        }
        .width(44).height(48).padding(0).backgroundColor(Color.Transparent)
        .onClick((): void => { this.showingDataManagement = false; })
        Text('数据管理').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#123F2E').layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(44)
      }
      .width('100%').height(60).padding({ left: 14, right: 14 })
      Column({ space: 12 }) {
        Text('本地记录工具').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#123F2E')
        Text('数据只保存在本机。备份用于演示恢复，CSV 可用于老师查看统计明细。')
          .fontSize(13).fontColor('#718078').width('100%')
        Button('备份当前记录', { type: ButtonType.Capsule, stateEffect: true })
          .width('100%').height(42).backgroundColor('#4C9576').fontColor('#FFFFFF')
          .onClick((): void => { this.backupRecords(); })
        Button('读取最近备份', { type: ButtonType.Capsule, stateEffect: true })
          .width('100%').height(42).backgroundColor('#E5F0E5').fontColor('#376D52')
          .onClick((): void => { this.restoreRecords(); })
        Button('生成 CSV 报表', { type: ButtonType.Capsule, stateEffect: true })
          .width('100%').height(42).backgroundColor('#E5F0E5').fontColor('#376D52')
          .onClick((): void => { this.exportCsvReport(); })
        if (this.csvPreview.length > 0) {
          TextArea({ text: this.csvPreview })
            .width('100%').height(220).fontSize(11).fontColor('#365C4B')
            .backgroundColor('#FAFBF6').border({ width: 1, color: '#DDE8DE' }).borderRadius(12)
            .enabled(false)
        }
      }
      .width('100%').padding({ left: 22, right: 22, top: 16, bottom: 30 })
    }
    .width('100%').height('100%').backgroundColor('#F7F8F2')
  }

  /**
   * 菜单行：圆角图标底托 + 标题/副标题 + 右箭头，整行可点击
   * @param title 菜单标题
   * @param detail 副标题说明
   * @param icon 菜单图标资源
   * @param onClick 点击回调
   */
  @Builder
  private MenuRow(title: string, detail: string, icon: Resource, onClick: () => void) {
    Row({ space: 14 }) {
      // 左侧：圆角浅绿底托 + 图标
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#EAF0E5')
        Image(icon)
          .syncLoad(true)
          .width(26)
          .height(26)
      }
      // 中部：标题与副标题
      Column({ space: 4 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173F2E')
        Text(detail)
          .fontSize(13)
          .fontColor('#78867D')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 右侧：进入箭头
      Text('›')
        .fontSize(28)
        .fontColor('#8D9B91')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 14, bottom: 14 })
    .onClick(onClick)
  }

  /**
   * 单条收藏文章行
   * 图标 + 标题/分类时长 + 右侧取消收藏按钮；整行点击进入文章详情
   * @param article 收藏文章数据
   */
  @Builder
  private FavoriteRow(article: KnowledgeArticle) {
    Row({ space: 13 }) {
      // 左侧：文章图标（圆角浅绿底）
      Image(this.articleIcon(article))
        .syncLoad(true)
        .width(45)
        .height(45)
        .padding(6)
        .backgroundColor('#EAF0E5')
        .borderRadius(23)
      // 中部：标题 + 分类与阅读时长，超长省略
      Column({ space: 5 }) {
        Text(article.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#173F2E')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${article.category} · ${article.readTime}`)
          .fontSize(13)
          .fontColor('#718078')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 右侧：取消收藏按钮
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Text('♥')
          .fontSize(21)
          .fontColor('#4C9576')
      }
      .width(38)
      .height(38)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('取消收藏')
      .onClick((): void => this.removeFavorite(article.id))
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 15, bottom: 15 })
    // 整行点击进入文章详情
    .onClick((): void => {
      this.openedArticleId = article.id;
    })
  }

  /**
   * "我的收藏"列表视图
   * 顶部标题行（返回 + 标题） + 三种内容：加载中 / 空提示 / 收藏列表
   */
  @Builder
  private FavoriteList() {
    Column() {
      // 标题行：左返回 + 居中标题 + 右侧等宽留白
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
          this.showingFavorites = false;
        })
        Text('我的收藏')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(44)
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })

      if (this.loading) {
        // 加载中提示
        Column() {
          Text('正在读取收藏')
            .fontSize(16)
            .fontColor('#718078')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.favoriteArticles().length === 0) {
        // 空收藏提示：引导去成长页收藏
        Column({ space: 10 }) {
          Image($r('app.media.diary_leaf'))
            .syncLoad(true)
            .width(42)
            .height(42)
            .opacity(0.65)
          Text('还没有收藏文章')
            .fontSize(16)
            .fontColor('#718078')
          Text('在成长页收藏后，可在这里离线查看')
            .fontSize(13)
            .fontColor('#8A968F')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 收藏列表：稳定 id 作为键，底部分隔线统一绘制
        List({ space: 0 }) {
          ForEach(this.favoriteArticles(), (article: KnowledgeArticle) => {
            ListItem() {
              this.FavoriteRow(article)
            }
          }, (article: KnowledgeArticle): string => article.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: '#DBE2D8' })
        .scrollBar(BarState.Off)
        .contentEndOffset(24)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 文章详情视图
   * 顶部标题行（返回/取消收藏） + 正文滚动区（分类信息、标题、摘要块、分段正文、资料来源）
   * @param article 当前打开的文章
   */
  @Builder
  private ArticleDetail(article: KnowledgeArticle) {
    Column() {
      // 标题行：左返回 + 居中标题 + 右取消收藏（同时退出详情）
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Text('‹').fontSize(40).fontColor('#174E3A')
        }
        .width(44)
        .height(48)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回收藏列表')
        .onClick((): void => {
          this.openedArticleId = '';
        })
        Text('文章详情')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          Text('♥').fontSize(23).fontColor('#4C9576')
        }
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('取消收藏')
        .onClick((): void => {
          this.removeFavorite(article.id);
          this.openedArticleId = '';
        })
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })
      // 正文滚动区
      Scroll() {
        Column({ space: 18 }) {
          // 分类与阅读时长信息行
          Row({ space: 14 }) {
            Image(this.articleIcon(article))
              .syncLoad(true)
              .width(44)
              .height(44)
              .padding(6)
              .backgroundColor('#EAF0E5')
              .borderRadius(22)
            Column({ space: 4 }) {
              Text(article.category).fontSize(13).fontColor('#4C8067')
              Text(article.readTime).fontSize(12).fontColor('#8A968F')
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          // 文章大标题
          Text(article.title)
            .width('100%')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
            .lineHeight(39)
          // 摘要块：浅绿底提示框样式
          Text(article.summary)
            .width('100%')
            .fontSize(16)
            .fontColor('#567064')
            .lineHeight(26)
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#EDF4EA')
            .borderRadius(8)
          // 正文段落：序号圆点 + 段落文字
          ForEach(article.paragraphs, (paragraph: string, index: number) => {
            Column({ space: 8 }) {
              Text(`${index + 1}`)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .width(25)
                .height(25)
                .textAlign(TextAlign.Center)
                .backgroundColor('#4C9576')
                .borderRadius(13)
              Text(paragraph)
                .width('100%')
                .fontSize(17)
                .fontColor('#365C4B')
                .lineHeight(29)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (_paragraph: string, index: number): string => index.toString())
          // 资料来源块：机构、标题与网址
          Column({ space: 7 }) {
            Text('资料来源').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#345F4B')
            Text(article.sourceName).fontSize(14).fontColor('#567064')
            Text(article.sourceTitle).fontSize(14).fontColor('#567064').lineHeight(22)
            Text(article.sourceUrl).fontSize(12).fontColor('#4C8067').maxLines(3)
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#F0F3EC')
          .borderRadius(8)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 36 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 底部四栏导航条
   * 磨砂兜底层（半透明浅绿 + 材质模糊 + 细高光描边 + 柔和阴影）+ 液态玻璃升级层
   */
  @Builder
  private BottomNav() {
    Column({ space: 0 }) {
      Row() {
        this.NavItem('日记', $r('app.media.diary_diary'), '日记')
        this.NavItem('足迹', $r('app.media.diary_leaf'), '足迹')
        this.NavItem('成长', $r('app.media.diary_sprout'), '成长')
        this.NavItem('我的', $r('app.media.diary_person'), '我的')
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
   * 底部导航条的单个栏目项
   * 与首页 TabItem 一致：选中态淡绿底托 + 按压缩放与提亮反馈
   * @param label 栏目显示名称
   * @param icon 栏目图标资源
   * @param tab 栏目标识（用于选中态判断与导航回调）
   */
  @Builder
  private NavItem(label: string, icon: Resource, tab: string) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 5 }) {
        // 栏目图标
        Image(icon).syncLoad(true).width(26).height(26)
        // 栏目名称：选中态森林绿加粗
        Text(label)
          .fontSize(12)
          .fontColor(this.selectedTab === tab ? '#245C40' : '#8B968E')
          .fontWeight(this.selectedTab === tab ? FontWeight.Medium : FontWeight.Normal)
      }
      .width('100%')
      // 底托内边距与颜色：仅选中项显示淡绿底托，按压时提亮
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(this.selectedTab === tab
        ? (this.pressedTab === tab ? '#CCDCEDE4' : '#B3D2E7D7')
        : (this.pressedTab === tab ? '#26FFFFFF' : Color.Transparent))
      .borderRadius(18)
      .animation({ duration: 180, curve: Curve.Friction })
    }
    .layoutWeight(1)
    .height(68)
    .padding(0)
    .backgroundColor(Color.Transparent)
    // 按压缩放：轻微缩小，松开恢复
    .scale({
      x: this.pressedTab === tab ? 0.94 : 1,
      y: this.pressedTab === tab ? 0.94 : 1
    })
    .animation({ duration: 180, curve: Curve.Friction })
    .accessibilityText(this.selectedTab === tab ? `${label}，当前栏目` : label)
    .onClick((): void => this.navigate(tab))
    // 跟踪按压状态：按下记录栏目名，抬起/取消时清除
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedTab = tab;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
      }
    })
  }

  /**
   * 页面布局
   * 按状态切换三种视图：文章详情 / 收藏列表 / 个人主页（标题 + 资料 + 概览 + 菜单 + 底部导航）
   */
  build() {
    // 打开了收藏文章：整页切换为文章详情
    if (this.openedArticle() !== undefined) {
      this.ArticleDetail(this.openedArticle() as KnowledgeArticle)
    } else if (this.showingRewards) {
      // 积分中心作为“我的”页内子页面打开，返回后保留当前余额和收藏状态。
      this.RewardsCenter()
    } else if (this.showingDataManagement) {
      this.DataManagement()
    } else if (this.showingFavorites) {
      // 收藏列表视图
      this.FavoriteList()
    } else {
      // 个人主页：Stack 底部对齐，底层为可滚动内容，上层为底部导航
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column() {
            this.Header()
            this.Profile()
            this.Overview()
            // 积分入口保持在个人概览之后，方便查看余额；完整签到和兑换流程在子页面中展开。
            this.PointsCard()
            // 菜单入口：我的收藏（显示收藏数量）
            this.MenuRow('我的收藏', `${this.favoriteIds.length} 篇文章可离线阅读`, $r('app.media.diary_leaf'), () => {
              this.showingFavorites = true;
            })
            // 菜单入口：积分与权益（模拟兑换，不连接真实平台）
            this.MenuRow('积分与权益', '签到、查看积分并兑换模拟低碳权益', $r('app.media.diary_leaf'), () => {
              this.showingRewards = true;
            })
            // 菜单入口：成长知识库（切换到成长栏目）
            this.MenuRow('成长知识库', '双碳基础与校园低碳实践', $r('app.media.diary_sprout'), () => {
              this.navigate('成长');
            })
            // 菜单入口：数据管理（本机备份/恢复/CSV 报表）
            this.MenuRow('数据管理', '备份、恢复与导出 CSV 报表', $r('app.media.diary_leaf'), () => {
              this.showingDataManagement = true;
            })
          }
          .width('100%')
          .padding({ bottom: 150 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        this.BottomNav()
      }
      // 将底部液态玻璃导航的绘制范围延伸到系统手势区
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }
}

/**
 * 我的页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 MyPage 组件，不参与实际页面路由
 */
@Preview({
  title: 'MyPage', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct MyPagePreview {
  build() {
    // 直接渲染我的页组件
    MyPage()
  }
}
