/**
 * 应用入口页面
 * 应用启动后加载的第一个页面（路由 'pages/Index'），
 * 同时充当登录页与日记首页之间的切换容器：
 * - 未登录：渲染登录页 Login 组件
 * - 已登录：渲染日记首页 Home 组件
 * 页面切换由组件回调驱动（而非系统路由跳转），状态流转简单直观
 */
import { common } from '@kit.AbilityKit';
import { Login } from './Login';
import { Home } from './Home';
import { BehaviorPicker } from './BehaviorPicker';
import { RecordDetail } from './RecordDetail';
import { RecordDraft } from './RecordDetail';
import { DiaryDetail } from './DiaryDetail';
import { BehaviorOption } from './BehaviorPicker';
import { AuthService } from '../services/AuthService';
import { PreviewAuthService } from '../services/PreviewAuthService';
import { MyPage } from './MyPage';
import { FootprintPage } from './FootprintPage';
import { KnowledgeCenter } from './KnowledgeCenter';
import { QuizPage } from './QuizPage';
import { FootprintGamePage } from './FootprintGamePage';
import { HealthBindingPage } from './HealthBindingPage';
import { FamilyPage } from './FamilyPage';
import { FamilyService, FamilySnapshot } from '../services/FamilyService';
import { CarbonPointsService } from '../services/CarbonPointsService';
import { DiaryStorageService } from '../services/DiaryStorageService';

/**
 * 入口组件
 * 使用 @Entry 标记为页面级组件，作为主窗口加载的默认页面；
 * 内部维护"是否已登录"状态，登录成功后自动切换到日记首页
 */
@Entry
@Component
struct Index {
  /** 预览模式标记：true 时登录页使用内存模拟服务；真机保持 false，使用本机持久化服务 */
  previewMode: boolean = false;
  /** 认证服务实例：默认为持久化实现，预览壳组件注入 PreviewAuthService 模拟实现 */
  authService: AuthService = new AuthService();
  /** 登录状态标记：true 显示首页，false 显示登录页；登录成功后由 Login 回调置为 true */
  @State private loggedIn: boolean = false;
  /** 新建日记流程是否处于行为选择页 */
  @State private pickingBehavior: boolean = false;
  /** 新建日记流程是否处于记录详情页 */
  @State private editingRecord: boolean = false;
  /** 当前正在填写的行为 */
  @State private selectedBehavior: BehaviorOption | undefined = undefined;
  /** 已保存的真实日记草稿；保存详情后追加，返回首页时由 Home 即时渲染。 */
  @State private savedDrafts: RecordDraft[] = [];
  /** 当前打开的已保存日记下标；-1 表示没有打开详情。 */
  @State private openedDiaryIndex: number = -1;
  /** 当前打开的演示日记草稿；演示数据只存在于详情页，不写入真实记录。 */
  @State private openedPreviewDraft: RecordDraft | undefined = undefined;
  /** 当前是否处于已保存日记详情页。 */
  @State private viewingDiary: boolean = false;
  /** 当前编辑的已保存日记下标；新建记录时为 -1。 */
  @State private editingSavedIndex: number = -1;
  /** 当前底部栏目；“我的”由独立页面承载，其余栏目仍在 Home 中显示。 */
  @State private activeTab: string = '日记';
  /** 是否正在进行低碳知识答题。 */
  @State private takingQuiz: boolean = false;
  /** 是否正在进行低碳足迹棋盘。 */
  @State private takingFootprintGame: boolean = false;
  /** 是否正在进行华为运动绑定；绑定页不创建低碳记录。 */
  @State private bindingHealth: boolean = false;
  /** 是否打开家庭碳账户页；从"我的"菜单进入，返回后回到"我的"栏目。 */
  @State private showingFamily: boolean = false;
  /** 本次会话是否已经完成华为运动授权，以及读取到的今日步数。 */
  @State private healthBound: boolean = false;
  @State private healthStepsToday: number = 0;
  /** 首页当前筛选的自然日，默认今天。 */
  @State private selectedDate: number = Date.now();
  /** 已从首页删除的示例记录，避免静态样例再次出现。 */
  @State private hiddenPreviewIds: string[] = [];
  /** 本地积分服务：真实保存的核验记录才会入账，示例数据不会自动产生积分。 */
  private pointsService: CarbonPointsService = new CarbonPointsService();
  /** 本地记录服务：页面重启后仍恢复同一批记录。 */
  private diaryStorage: DiaryStorageService = new DiaryStorageService();
  /** 本地家庭碳账户服务：冷启动恢复当前记录身份。 */
  private familyService: FamilyService = new FamilyService();

  /** 组件即将出现：从本地存储恢复上次会话保存的日记记录。 */
  aboutToAppear(): void {
    this.loadSavedDrafts();
    if (!this.previewMode) {
      this.restoreLoginSession();
      this.initFamilySession();
    }
  }

  /** 冷启动恢复家庭会话：把当前记录身份同步到 AppStorage，记录页据此归属成员与显示开关。 */
  private async initFamilySession(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const family: FamilySnapshot | undefined = await this.familyService.load(context);
      if (family !== undefined) {
        FamilyService.applyCurrentMember(family);
      }
    } catch (error) {
      // 没有家庭或读取失败时保持未创建状态，不影响正常记录。
    }
  }

  /** 冷启动恢复最近一次成功登录的用户，避免把登录页误认为记录丢失。 */
  private async restoreLoginSession(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const user = await this.authService.restoreSession(context);
      if (user !== undefined) {
        AppStorage.setOrCreate<string>('loginUserId', user.userId);
        AppStorage.setOrCreate<string>('loginDisplayName', user.displayName);
        this.loggedIn = true;
      }
    } catch (error) {
      // 无会话时保留登录页，不影响本地记录读取。
    }
  }

  /** 统一底部栏目切换：同步赋值、不加过渡动画，避免切页过程暴露子页加载态图标。 */
  private switchTab(tab: string): void {
    if (tab === this.activeTab) {
      return;
    }
    this.activeTab = tab;
  }

  /**
   * 从本地 Preferences 恢复已保存的日记记录
   * 读取失败时回退为空列表，页面以全新状态启动
   */
  private async loadSavedDrafts(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      const loaded: RecordDraft[] = await this.diaryStorage.load(context);
      // 兼容早期 AI 认证记录：旧版本已完成识别确认但仍写入 pending，启动时补齐为已核验，
      // 不重新发放积分，避免重复计分；积分服务本身仍负责图片指纹去重。
      this.savedDrafts = loaded.map((draft: RecordDraft): RecordDraft => {
        const aiConfirmed: boolean = draft.verificationKind === 'ai_assisted' &&
          draft.aiStatus !== 'rejected' && (draft.riskFlags ?? []).length === 0 && draft.amount > 0;
        if (!aiConfirmed || draft.verificationStatus === 'verified') {
          return draft;
        }
        draft.verificationStatus = 'verified';
        draft.scoreEnabled = true;
        return draft;
      });
      const migrated: boolean = this.savedDrafts.some((draft: RecordDraft, index: number): boolean => {
        return draft !== loaded[index];
      });
      if (migrated) {
        await this.diaryStorage.saveAll(context, this.savedDrafts);
      }
    } catch (error) {
      this.savedDrafts = [];
    }
  }

  /** 打开系统日期选择器，选择后由首页按自然日筛选记录。 */
  private openCalendar(): void {
    this.getUIContext().showDatePickerDialog({
      selected: new Date(this.selectedDate),
      onDateAccept: (date: Date): void => {
        this.selectedDate = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
      }
    });
  }

  /** 保存成功后为记录入账：核验记录走全额、手动记录走折扣通道，去重与上限由服务层统一执行。 */
  private async rewardSavedRecord(draft: RecordDraft): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      if (draft.verificationKind === 'ai_assisted' && draft.imageHash !== undefined && draft.imageHash.length > 0) {
        await this.pointsService.rewardAiImageRecord(context, draft.operationId ?? '', draft.imageHash,
          draft.reductionKg, draft.riskFlags ?? []);
        return;
      }
      if (draft.verificationStatus === 'verified' && draft.scoreEnabled) {
        await this.pointsService.rewardVerifiedRecord(context, draft.operationId ?? '',
          true, true, draft.evidenceSource, draft.reductionKg);
        return;
      }
      // 手动记录（光盘行动、节水节电等无法系统核验）：按折扣积分入账；
      // 携带风险标记（如重复图片被拒）的记录不发放任何积分。
      if ((draft.riskFlags ?? []).length === 0) {
        await this.pointsService.rewardManualRecord(context, draft.operationId ?? '', draft.reductionKg);
      }
    } catch (error) {
      // 积分入账失败不阻断日记保存。
    }
  }

  /**
   * 获取当前打开的日记草稿
   * @returns 打开的草稿；下标越界（未打开详情）时为 undefined
   */
  private openedDraft(): RecordDraft | undefined {
    if (this.openedPreviewDraft !== undefined) {
      return this.openedPreviewDraft;
    }
    // 下标无效表示没有打开详情
    if (this.openedDiaryIndex < 0 || this.openedDiaryIndex >= this.savedDrafts.length) {
      return undefined;
    }
    return this.savedDrafts[this.openedDiaryIndex];
  }

  /**
   * 打开一条日记详情
   * 打开内置示例记录时只在详情页展示并隐藏原示例，不写入真实账本；
   * 已保存记录按 id 中的下标直接定位。
   * @param id 记录 id（'saved-下标' 或 'preview-xxx'）
   */
  private openDiary(id: string): void {
    // 内置示例记录：单独保存详情状态，同时从首页隐藏该示例
    if (!id.startsWith('saved-')) {
      const preview: RecordDraft | undefined = this.previewDraft(id);
      if (preview === undefined) {
        return;
      }
      this.hiddenPreviewIds = [...this.hiddenPreviewIds, id];
      this.openedPreviewDraft = preview;
      this.openedDiaryIndex = -1;
      this.viewingDiary = true;
      return;
    }
    // 已保存记录：解析稳定 recordId，不依赖数组下标
    const recordId: string = id.substring(6);
    const index: number = this.savedDrafts.findIndex((item: RecordDraft): boolean => {
      return (item.recordId ?? item.operationId ?? '') === recordId;
    });
    if (index >= 0) {
      this.openedDiaryIndex = index;
      this.viewingDiary = true;
    }
  }

  /**
   * 内置示例记录 id 到日记草稿的映射
   * 步行/光盘/骑行三条示例与首页静态数据保持一致
   * @param id 示例记录 id
   * @returns 对应的草稿数据；未知 id 返回 undefined
   */
  private previewDraft(id: string): RecordDraft | undefined {
    const todayAt = (hour: number, minute: number): number => {
      const date: Date = new Date();
      date.setHours(hour, minute, 0, 0);
      return date.getTime();
    };
    if (id === 'preview-walk') {
      return {
        recordId: 'preview-walk-record', createdAt: todayAt(8, 10), updatedAt: todayAt(8, 10), recordedAt: todayAt(8, 10),
        behavior: { id: 'walk', name: '步行', icon: $r('app.media.diary_walk') },
        amount: 1.2, unit: '公里', reductionKg: 0.25,
        note: '绕过操场，顺便看看早晨的树影。', hasPhoto: false,
        evidenceSource: 'manual', verificationStatus: 'pending',
        evidenceId: 'preview-only', scoreEnabled: false
      };
    }
    if (id === 'preview-meal') {
      return {
        recordId: 'preview-meal-record', createdAt: todayAt(12, 20), updatedAt: todayAt(12, 20), recordedAt: todayAt(12, 20),
        behavior: { id: 'meal', name: '光盘行动', icon: $r('app.media.diary_meal') },
        amount: 1, unit: '份', reductionKg: 0.18,
        note: '吃完了，也没有浪费。', hasPhoto: false,
        evidenceSource: 'manual', verificationStatus: 'pending',
        evidenceId: 'preview-only', scoreEnabled: false
      };
    }
    if (id === 'preview-bike') {
      return {
        recordId: 'preview-bike-record', createdAt: todayAt(17, 40), updatedAt: todayAt(17, 40), recordedAt: todayAt(17, 40),
        behavior: { id: 'bike', name: '骑行', icon: $r('app.media.diary_bike') },
        amount: 2.4, unit: '公里', reductionKg: 0.83,
        note: '晚风很舒服，今天慢一点也很好。', hasPhoto: true,
        evidenceSource: 'manual', verificationStatus: 'pending',
        evidenceId: 'preview-only', scoreEnabled: false
      };
    }
    return undefined;
  }

  /**
   * 页面布局
   * 依据登录状态条件渲染两个子页面之一（if/else 分支渲染）
   */
  build() {
    // 已登录：渲染日记首页（当前暂无退出登录入口）
    if (this.loggedIn) {
      if (this.takingFootprintGame) {
        FootprintGamePage({
          onBack: () => {
            this.takingFootprintGame = false;
            this.activeTab = '我的';
          }
        })
      } else if (this.bindingHealth) {
        HealthBindingPage({
          onBack: () => {
            this.bindingHealth = false;
          },
          onBound: (steps: number) => {
            this.healthBound = true;
            this.healthStepsToday = steps;
            this.bindingHealth = false;
            this.activeTab = '我的';
          }
        })
      } else if (this.showingFamily) {
        // 家庭碳账户：从"我的"菜单进入的整页子视图，返回后回到"我的"栏目
        FamilyPage({
          savedDrafts: this.savedDrafts,
          onBack: () => {
            this.showingFamily = false;
            this.activeTab = '我的';
          }
        })
      } else if (this.takingQuiz) {
        QuizPage({
          onBack: () => {
            this.takingQuiz = false;
            this.activeTab = '我的';
          }
        })
      } else if (this.activeTab === '成长' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        KnowledgeCenter({
          selectedTab: this.activeTab,
          savedDrafts: this.savedDrafts,
          onNavigate: (tab: string) => {
            this.switchTab(tab);
          }
        })
      } else if (this.activeTab === '足迹' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        FootprintPage({
          selectedTab: this.activeTab,
          savedDrafts: this.savedDrafts,
          onNavigate: (tab: string) => {
            this.switchTab(tab);
          }
        })
      } else if (this.activeTab === '我的' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        MyPage({
          selectedTab: this.activeTab,
          savedDrafts: this.savedDrafts,
          healthBound: this.healthBound,
          healthStepsToday: this.healthStepsToday,
          onRestoreRecords: (records: RecordDraft[]) => {
            this.savedDrafts = records;
            this.persistAllDrafts(records);
          },
          onStartImageCertification: () => {
            this.activeTab = '日记';
            this.pickingBehavior = true;
          },
          onStartHealthBinding: () => {
            this.bindingHealth = true;
          },
          onStartQuiz: () => {
            this.activeTab = '我的';
            this.takingQuiz = true;
          },
          onStartFootprintGame: () => {
            this.activeTab = '我的';
            this.takingFootprintGame = true;
          },
          onStartFamily: () => {
            this.showingFamily = true;
          },
          onNavigate: (tab: string) => {
            if (tab === '我的') {
              return;
            }
            this.switchTab(tab);
          }
        })
      } else if (this.viewingDiary && this.openedDraft() !== undefined) {
        DiaryDetail({
          draft: this.openedDraft() as RecordDraft,
          onBack: () => {
            this.viewingDiary = false;
            this.openedDiaryIndex = -1;
            this.openedPreviewDraft = undefined;
          },
          onEdit: () => {
            const current: RecordDraft | undefined = this.openedDraft();
            if (current === undefined) {
              return;
            }
            this.selectedBehavior = current.behavior;
            this.editingSavedIndex = this.openedPreviewDraft === undefined ? this.openedDiaryIndex : -1;
            this.viewingDiary = false;
            this.editingRecord = true;
          },
          onDelete: () => {
            const current: RecordDraft | undefined = this.openedDraft();
            if (current !== undefined && this.openedPreviewDraft === undefined) {
              this.removeDraft(current.recordId ?? current.operationId ?? '');
            }
            if (this.openedPreviewDraft === undefined) {
              this.savedDrafts = this.savedDrafts.filter((_item: RecordDraft, index: number) => index !== this.openedDiaryIndex);
            }
            this.viewingDiary = false;
            this.openedDiaryIndex = -1;
            this.openedPreviewDraft = undefined;
          }
        })
      } else if (this.editingRecord && this.selectedBehavior !== undefined) {
        RecordDetail({
          behavior: this.selectedBehavior,
          initialDraft: this.editingSavedIndex >= 0 ? this.savedDrafts[this.editingSavedIndex] : undefined,
          onBack: () => {
            this.editingRecord = false;
            if (this.editingSavedIndex >= 0) {
              this.viewingDiary = true;
              this.openedDiaryIndex = this.editingSavedIndex;
            } else {
              this.pickingBehavior = true;
            }
          },
          onSave: (_draft: RecordDraft) => {
            if (this.editingSavedIndex >= 0 && this.editingSavedIndex < this.savedDrafts.length) {
              const updated: RecordDraft[] = [...this.savedDrafts];
              updated[this.editingSavedIndex] = _draft;
              this.savedDrafts = updated;
            } else {
              this.savedDrafts = [...this.savedDrafts, _draft];
            }
            this.persistDraft(_draft);
            // 日记已经保存后再异步入账，不让积分异常影响记录保存。
            this.rewardSavedRecord(_draft);
            this.editingRecord = false;
            this.selectedBehavior = undefined;
            this.editingSavedIndex = -1;
            this.openedPreviewDraft = undefined;
          }
        })
      } else if (this.pickingBehavior) {
        BehaviorPicker({
          onBack: () => {
            this.pickingBehavior = false;
          },
          onNext: (behavior: BehaviorOption) => {
            this.selectedBehavior = behavior;
            this.pickingBehavior = false;
            this.editingRecord = true;
          }
        })
      } else {
        Home({
          initialTab: this.activeTab,
          hiddenExampleIds: this.hiddenPreviewIds,
          savedDrafts: this.savedDrafts,
          selectedDate: this.selectedDate,
          onOpenDiary: (id: string) => this.openDiary(id),
          onAddDiary: () => {
            this.pickingBehavior = true;
          },
          onOpenCalendar: () => this.openCalendar(),
          onSelectTab: (tab: string) => {
            this.switchTab(tab);
          }
        })
      }
    } else {
      // 未登录：渲染登录页，并注册登录成功回调
      Login({
        previewMode: this.previewMode,
        authService: this.authService,
        onLoginSuccess: (userId?: string) => {
          // 翻转登录状态，触发 build 重新渲染为首页
          if (userId !== undefined) {
            AppStorage.setOrCreate<string>('loginUserId', userId);
          }
          this.loggedIn = true;
        }
      })
    }
  }

  /**
   * 新增或更新一条记录并立即落盘
   * 落盘失败时页面内存列表仍可用，下次保存会再次尝试写入
   * @param draft 待持久化的记录草稿
   */
  private async persistDraft(draft: RecordDraft): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.savedDrafts = await this.diaryStorage.upsert(context, draft);
    } catch (error) {
      // 页面内存状态仍可继续使用，下一次保存会再次尝试落盘。
    }
  }

  /**
   * 按 recordId 从本地存储删除一条记录
   * 删除失败时由页面内存列表完成即时移除，不阻塞用户操作
   * @param recordId 记录主键；空串直接返回
   */
  private async removeDraft(recordId: string): Promise<void> {
    if (recordId.length === 0) {
      return;
    }
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.savedDrafts = await this.diaryStorage.remove(context, recordId);
    } catch (error) {
      // 删除失败时由当前页内存列表完成即时移除，避免阻塞用户操作。
    }
  }

  /**
   * 整体覆盖保存全部记录（备份恢复后使用）
   * 落盘失败时保留当前会话数据并等待下次保存
   * @param records 恢复后的完整记录列表
   */
  private async persistAllDrafts(records: RecordDraft[]): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await this.diaryStorage.saveAll(context, records);
    } catch (error) {
      // 恢复后的页面状态已经更新，落盘失败时保留当前会话数据并等待下次保存。
    }
  }
}

/**
 * 入口页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中按指定设备参数展示 Index 页面，不参与实际页面路由；
 * 预览时默认处于未登录态（显示登录页）
 */
@Preview({
  title: 'Index',          // 预览标题
  deviceType: 'phone',     // 设备类型：手机
  width: 1080,             // 预览宽度（px）
  height: 2340,            // 预览高度（px）
  colorMode: 'light',      // 浅色模式
  dpi: 480,                // 屏幕像素密度
  locale: 'zh_CN',         // 简体中文语言环境
  orientation: 'portrait', // 竖屏方向
  roundScreen: false       // 非圆屏设备
})
@Component
struct IndexPreview {
  /** 预览专用内存认证服务：避免预览器调用持久化与密码学能力 */
  private previewAuth: AuthService = new PreviewAuthService();
  build() {
    // 以预览模式渲染入口组件（登录页使用内存模拟服务）
    Index({ previewMode: true, authService: this.previewAuth })
  }
}
