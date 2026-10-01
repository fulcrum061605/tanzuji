/**
 * 应用入口页面
 * 应用启动后加载的第一个页面（路由 'pages/Index'），
 * 同时充当登录页与日记首页之间的切换容器：
 * - 未登录：渲染登录页 Login 组件
 * - 已登录：渲染日记首页 Home 组件
 * 页面切换由组件回调驱动（而非系统路由跳转），状态流转简单直观
 */
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
  /** 当前是否处于已保存日记详情页。 */
  @State private viewingDiary: boolean = false;
  /** 当前编辑的已保存日记下标；新建记录时为 -1。 */
  @State private editingSavedIndex: number = -1;
  /** 当前底部栏目；“我的”由独立页面承载，其余栏目仍在 Home 中显示。 */
  @State private activeTab: string = '日记';
  /** 已从首页删除的示例记录，避免静态样例再次出现。 */
  @State private hiddenPreviewIds: string[] = [];

  private openedDraft(): RecordDraft | undefined {
    if (this.openedDiaryIndex < 0 || this.openedDiaryIndex >= this.savedDrafts.length) {
      return undefined;
    }
    return this.savedDrafts[this.openedDiaryIndex];
  }

  private openDiary(id: string): void {
    if (!id.startsWith('saved-')) {
      const preview: RecordDraft | undefined = this.previewDraft(id);
      if (preview === undefined) {
        return;
      }
      const nextIndex: number = this.savedDrafts.length;
      this.savedDrafts = [...this.savedDrafts, preview];
      this.hiddenPreviewIds = [...this.hiddenPreviewIds, id];
      this.openedDiaryIndex = nextIndex;
      this.viewingDiary = true;
      return;
    }
    const index: number = Number.parseInt(id.substring(6));
    if (!Number.isNaN(index) && index >= 0 && index < this.savedDrafts.length) {
      this.openedDiaryIndex = index;
      this.viewingDiary = true;
    }
  }

  private previewDraft(id: string): RecordDraft | undefined {
    if (id === 'preview-walk') {
      return {
        behavior: { id: 'walk', name: '步行', icon: $r('app.media.diary_walk') },
        amount: 1.2, unit: '公里', reductionKg: 0.25,
        note: '绕过操场，顺便看看早晨的树影。', hasPhoto: false,
        evidenceSource: 'location', verificationStatus: 'verified',
        evidenceId: 'preview-location-walk', scoreEnabled: true
      };
    }
    if (id === 'preview-meal') {
      return {
        behavior: { id: 'meal', name: '光盘行动', icon: $r('app.media.diary_meal') },
        amount: 1, unit: '份', reductionKg: 0.18,
        note: '吃完了，也没有浪费。', hasPhoto: false,
        evidenceSource: 'manual', verificationStatus: 'verified',
        evidenceId: 'preview-manual-meal', scoreEnabled: true
      };
    }
    if (id === 'preview-bike') {
      return {
        behavior: { id: 'bike', name: '骑行', icon: $r('app.media.diary_bike') },
        amount: 2.4, unit: '公里', reductionKg: 0.83,
        note: '晚风很舒服，今天慢一点也很好。', hasPhoto: true,
        evidenceSource: 'health', verificationStatus: 'verified',
        evidenceId: 'preview-health-bike', scoreEnabled: true
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
      if (this.activeTab === '成长' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        KnowledgeCenter({
          selectedTab: this.activeTab,
          onNavigate: (tab: string) => {
            this.activeTab = tab;
          }
        })
      } else if (this.activeTab === '足迹' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        FootprintPage({
          selectedTab: this.activeTab,
          savedDrafts: this.savedDrafts,
          onNavigate: (tab: string) => {
            this.activeTab = tab;
          }
        })
      } else if (this.activeTab === '我的' && !this.viewingDiary && !this.editingRecord && !this.pickingBehavior) {
        MyPage({
          selectedTab: this.activeTab,
          onNavigate: (tab: string) => {
            if (tab === '我的') {
              return;
            }
            this.activeTab = tab;
          }
        })
      } else if (this.viewingDiary && this.openedDraft() !== undefined) {
        DiaryDetail({
          draft: this.openedDraft() as RecordDraft,
          onBack: () => {
            this.viewingDiary = false;
            this.openedDiaryIndex = -1;
          },
          onEdit: () => {
            this.selectedBehavior = this.savedDrafts[this.openedDiaryIndex].behavior;
            this.editingSavedIndex = this.openedDiaryIndex;
            this.viewingDiary = false;
            this.editingRecord = true;
          },
          onDelete: () => {
            this.savedDrafts = this.savedDrafts.filter((_item: RecordDraft, index: number) => {
              return index !== this.openedDiaryIndex;
            });
            this.viewingDiary = false;
            this.openedDiaryIndex = -1;
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
            this.editingRecord = false;
            this.selectedBehavior = undefined;
            this.editingSavedIndex = -1;
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
          onOpenDiary: (id: string) => this.openDiary(id),
          onAddDiary: () => {
            this.pickingBehavior = true;
          },
          onSelectTab: (tab: string) => {
            this.activeTab = tab;
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
