/**
 * 成长 · 双碳知识中心。
 * 文章正文由 rawfile 内置资源提供，可离线搜索和阅读；收藏保存在本机 Preferences。
 * 内置文章由 KnowledgeService 解析 rawfile 下的 carbon_knowledge.json，并与管理员自定义文档合并；
 * 收藏列表与自定义文档持久化在设备本地，因此搜索、阅读、收藏全程可离线使用。
 * “推荐”分类基于用户真实低碳记录（savedDrafts）与收藏偏好做本地加权排序，其余分类展示全部文章；
 * 文章详情页附可追溯的资料来源（机构/标题/网址），内容涵盖绿色校园、绿色消费、碳达峰碳中和等主题。
 */
// AbilityKit：提供 common.Context 类型，用于获取组件宿主上下文（读取 rawfile 与本机存储）
import { common } from '@kit.AbilityKit';
// ArkUI：提供 uiMaterial 模块，用于构建底部导航的沉浸式材质（液态玻璃）
import { uiMaterial } from '@kit.ArkUI';
// BasicServicesKit：提供 deviceInfo，读取 SDK API 版本以判断设备是否支持液态玻璃
import { deviceInfo } from '@kit.BasicServicesKit';
// 知识文章数据模型与知识服务：负责 rawfile 文章加载、收藏与管理员文档的持久化
import { KnowledgeArticle, KnowledgeService } from '../services/KnowledgeService';
// 低碳记录草稿模型：其 behavior.id 是“推荐”分类个性化排序的行为数据来源
import { RecordDraft } from './RecordDetail';

// 注意：管理员可输入自定义分类，不在本列表中的分类没有对应胶囊按钮，
// 此类文章仅在“推荐”（浏览全部）与“收藏”视图中可见。
/** 分类筛选栏的固定选项：'收藏' 视图复用收藏数据 */
const KNOWLEDGE_CATEGORIES: string[] = ['推荐', '双碳基础', '生活技巧', '校园行动', '收藏'];

/** 离线推荐评分后的文章包装：文章与推荐得分配对 */
interface ScoredArticle {
  /** 参与评分的文章 */
  article: KnowledgeArticle;
  /** 本地规则累计的推荐得分（收藏分类、基础补课与未覆盖行为加权），越高越靠前 */
  score: number;
}

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
 * 双碳知识中心组件
 * 页面结构：搜索头部（标题/管理员入口/搜索框） + 分类筛选栏 + 文章列表 / 文章详情 / 管理员编辑器 + 底部导航。
 * 支持关键字搜索、分类过滤、收藏切换与管理员新增文档。
 * 数据流：aboutToAppear 时经 KnowledgeService 读取 rawfile 文章与本机收藏，
 * 此后搜索/筛选/收藏/新增文档均在内存态完成并按需落盘，全程离线可用。
 */
@Component
export struct KnowledgeCenter {
  /** 入口容器传入的当前栏目，保证跨页切换后只有当前栏目高亮。 */
  @Prop selectedTab: string = '成长';
  /** 切换底部栏目回调：参数为目标栏目名，由入口页完成页面切换 */
  onNavigate?: (tab: string) => void;
  /** 当前用户的真实记录，只用于离线个性推荐。 */
  @Prop savedDrafts: RecordDraft[] = [];
  /** 全部文章列表：内置与管理员自定义文章合并后的结果 */
  @State private articles: KnowledgeArticle[] = [];
  /** 本地规则生成的文章推荐，不参与搜索结果。 */
  @State private recommendedArticles: KnowledgeArticle[] = [];
  /** 已收藏的文章 id 列表 */
  @State private favoriteIds: string[] = [];
  /** 搜索框内容：作为标题/摘要/关键字/正文的过滤条件 */
  @State private searchText: string = '';
  /** 当前选中的分类：'推荐' 使用本地个性化推荐，'收藏' 表示只看收藏 */
  @State private selectedCategory: string = '推荐';
  /** 当前打开的文章 id：非空时进入文章详情视图 */
  @State private openedArticleId: string = '';
  /** 内容加载中标记：控制加载态与列表视图的切换 */
  @State private loading: boolean = true;
  /** 管理员模式标记：演示账号登录时显示新增文档入口 */
  @State private adminMode: boolean = false;
  /** 是否显示管理员编辑器 */
  @State private showingEditor: boolean = false;
  /** 编辑器：文档标题 */
  @State private editorTitle: string = '';
  /** 编辑器：一句话摘要 */
  @State private editorSummary: string = '';
  /** 编辑器：正文内容 */
  @State private editorContent: string = '';
  /** 编辑器：所属分类 */
  @State private editorCategory: string = '校园行动';
  /** 编辑器：来源机构 */
  @State private editorSourceName: string = '';
  /** 编辑器：来源网址 */
  @State private editorSourceUrl: string = '';
  /** 当前按下的底部栏目，用于与主页保持一致的轻微按压反馈。 */
  @State private pressedTab: string = '';
  /** 知识服务实例：负责文章加载与收藏持久化 */
  private knowledgeService: KnowledgeService = new KnowledgeService();
  /** 底部导航条的液态玻璃材质：薄样式 + 低不透明度淡绿赋色；不具备能力的设备为 undefined */
  private navBarMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#59E6EEDF'
    })
    : undefined;

  /** 组件即将出现：按登录用户判断管理员模式并加载文章与收藏 */
  aboutToAppear(): void {
    const userId: string | undefined = AppStorage.get<string>('loginUserId');
    // 演示账号（真机）与预览管理员账号可使用新增文档能力
    this.adminMode = userId === 'demo-user-001' || userId === 'preview-admin';
    this.loadContent();
  }

  /**
   * 加载全部文章与收藏列表
   * 读取失败时提示用户；无论成败都结束加载态
   */
  private async loadContent(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      this.articles = await this.knowledgeService.loadArticles(context);
      this.favoriteIds = await this.knowledgeService.loadFavorites(context);
      this.refreshRecommendations();
    } catch (error) {
      this.showToast('知识资源暂时无法读取');
    } finally {
      this.loading = false;
    }
  }

  /** 根据真实记录、收藏分类和未覆盖行为生成可解释的离线推荐。 */
  private refreshRecommendations(): void {
    const recordedIds: string[] = this.savedDrafts.map((draft: RecordDraft): string => draft.behavior.id);
    const favoriteCategories: string[] = this.articles
      .filter((article: KnowledgeArticle): boolean => this.favoriteIds.includes(article.id))
      .map((article: KnowledgeArticle): string => article.category);
    const scored: ScoredArticle[] = this.articles.map((article: KnowledgeArticle): ScoredArticle => {
      let score: number = 1;
      const searchable: string = `${article.title}${article.summary}${article.keywords.join('')}`.toLowerCase();
      if (favoriteCategories.includes(article.category)) {
        score += 3;
      }
      if (article.category === '双碳基础' && recordedIds.length === 0) {
        score += 3;
      }
      const missingBehaviorTopic: boolean =
        (!recordedIds.includes('bike') && (searchable.includes('骑行') || searchable.includes('出行'))) ||
        (!recordedIds.includes('recycle') && (searchable.includes('回收') || searchable.includes('垃圾'))) ||
        (!recordedIds.includes('electricity') && searchable.includes('用电'));
      if (missingBehaviorTopic) {
        score += 4;
      }
      return { article: article, score: score };
    });
    scored.sort((left: ScoredArticle, right: ScoredArticle): number => right.score - left.score);
    this.recommendedArticles = scored.slice(0, 3).map((item: ScoredArticle): KnowledgeArticle => item.article);
  }

  /** 推荐文章区域：搜索或分类筛选时隐藏，避免干扰用户主动查找。 */
  @Builder
  private RecommendationSection() {
    if (this.searchText.trim().length === 0 && this.selectedCategory === '__legacy__' && this.recommendedArticles.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text('为你推荐')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#123F2E')
          Blank()
          // 推荐理由与事实保持一致：尚无低碳记录时说明是入门推荐
          Text(this.savedDrafts.length > 0 ? '根据你的低碳记录' : '为你挑选的入门内容')
            .fontSize(11)
            .fontColor('#7B8B82')
        }
        .width('100%')
        ForEach(this.recommendedArticles, (article: KnowledgeArticle) => {
          this.ArticleRow(article)
        }, (article: KnowledgeArticle): string => `recommend-${article.id}`)
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 8, bottom: 4 })
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
      // 非关键提示失败时不影响离线阅读。
    }
  }

  /**
   * 判断文章是否已收藏
   * @param id 文章唯一标识
   * @returns true 表示已收藏
   */
  private isFavorite(id: string): boolean {
    return this.favoriteIds.includes(id);
  }

  /**
   * 切换文章收藏状态
   * 先更新内存列表（立即刷新界面），再异步持久化到本机
   * @param id 文章唯一标识
   */
  private toggleFavorite(id: string): void {
    if (this.isFavorite(id)) {
      this.favoriteIds = this.favoriteIds.filter((item: string): boolean => item !== id);
      this.showToast('已取消收藏');
    } else {
      this.favoriteIds = [...this.favoriteIds, id];
      this.showToast('已收藏，可离线查看');
    }
    this.refreshRecommendations();
    this.persistFavorites();
  }

  /** 将当前收藏列表持久化到本机，失败时提示重试 */
  private async persistFavorites(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await this.knowledgeService.saveFavorites(context, this.favoriteIds);
    } catch (error) {
      this.showToast('收藏保存失败，请稍后重试');
    }
  }

  /**
   * 获取过滤后的文章列表
   * 先按分类过滤（'全部' 不限、'收藏' 只看已收藏、其余按分类名匹配），
   * 再按关键字对标题/摘要/分类/关键字/来源/正文做包含匹配
   * @returns 符合分类与关键字条件的文章列表
   */
  private filteredArticles(): KnowledgeArticle[] {
    const keyword: string = this.searchText.trim().toLowerCase().replace(/\s/g, '');
    const filtered: KnowledgeArticle[] = this.articles.filter((article: KnowledgeArticle): boolean => {
      // 分类过滤
      // “推荐”沿用原“全部”的浏览范围；个性化文章只作为推荐顺序依据，不隐藏其余文章。
      const categoryMatched: boolean = this.selectedCategory === '推荐' ||
        (this.selectedCategory === '收藏' && this.isFavorite(article.id)) ||
        article.category === this.selectedCategory;
      if (!categoryMatched) {
        return false;
      }
      // 关键字为空：不做内容过滤
      if (keyword.length === 0) {
        return true;
      }
      // 关键字匹配：标题 + 摘要 + 分类 + 关键字 + 来源 + 正文
      const searchable: string = `${article.title}${article.summary}${article.category}` +
        `${article.keywords.join('')}${article.sourceName}${article.sourceTitle}` +
        `${article.sourceUrl}${article.paragraphs.join('')}`;
      return searchable.toLowerCase().replace(/\s/g, '').includes(keyword);
    });
    if (this.selectedCategory === '推荐' && keyword.length === 0) {
      const rank = (article: KnowledgeArticle): number => {
        const index: number = this.recommendedArticles.findIndex((item: KnowledgeArticle): boolean => item.id === article.id);
        return index < 0 ? 999 : index;
      };
      return filtered.slice().sort((left: KnowledgeArticle, right: KnowledgeArticle): number => rank(left) - rank(right));
    }
    return filtered;
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
   * @returns 对应的图标资源，未知类型回落到幼苗图标
   */
  private articleIcon(article: KnowledgeArticle): Resource {
    switch (article.illustration) {
      case 'travel': return $r('app.media.diary_walk');
      case 'electricity': return $r('app.media.diary_electricity');
      case 'food': return $r('app.media.diary_meal');
      case 'recycle': return $r('app.media.diary_recycle');
      case 'campus': return $r('app.media.diary_sprout');
      case 'policy': return $r('app.media.diary_diary');
      case 'neutral': return $r('app.media.diary_leaf');
      default: return $r('app.media.diary_sprout');
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
      }, 180);
      return;
    }
    if (this.onNavigate) {
      // 保留短暂按压反馈，再切换页面，保证跨页点击也能看到动效。
      setTimeout(() => {
        if (this.pressedTab === tab) {
          this.pressedTab = '';
        }
        this.onNavigate?.(tab);
      }, 180);
    }
  }

  /**
   * 搜索头部：标题行（页面标题/管理员入口/文章数） + 搜索框
   */
  @Builder
  private SearchHeader() {
    Column({ space: 12 }) {
      // 顶行：左侧页面标题 + 右侧管理员入口与文章总数（底部导航已标明"成长"栏目，页内不再重复）
      Row() {
        Text('成长')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
        Blank()
        // 管理员模式：显示新增文档按钮，点击展开/收起编辑器
        if (this.adminMode) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            Image($r('app.media.diary_pen'))
              .syncLoad(true)
              .width(19)
              .height(19)
          }
          .width(34)
          .height(34)
          .padding(7)
          .backgroundColor(this.showingEditor ? '#CFE5D5' : '#EDF3EA')
          .accessibilityText('管理员新增文档')
          .onClick((): void => {
            this.showingEditor = !this.showingEditor;
          })
        }
        // 右侧文章总数
        Text(`${this.articles.length} 篇`)
          .fontSize(14)
          .fontColor('#718078')
      }
      .width('100%')
      .height(52)

      // 搜索框：搜索图标 + 输入框，关键字变化实时刷新列表
      Row({ space: 9 }) {
        Image($r('app.media.diary_search'))
          .syncLoad(true)
          .width(23)
          .height(23)
        TextInput({ placeholder: '搜索碳达峰、绿色出行……', text: this.searchText })
          .layoutWeight(1)
          .height(46)
          .fontSize(16)
          .fontColor('#365C4B')
          .placeholderColor('#89958E')
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onChange((value: string): void => {
            this.searchText = value;
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#EAF2E8')
      .borderRadius(24)
    }
    .width('100%')
    .padding({ left: 22, right: 22 })
  }

  /** 清空管理员编辑器全部字段，恢复默认分类 */
  private clearEditor(): void {
    this.editorTitle = '';
    this.editorSummary = '';
    this.editorContent = '';
    this.editorCategory = '校园行动';
    this.editorSourceName = '';
    this.editorSourceUrl = '';
  }

  /**
   * 保存管理员编辑器中的新文档
   * 标题与正文必填；保存成功后追加到列表、清空表单并收起编辑器
   */
  private async saveEditorArticle(): Promise<void> {
    // 必填校验：标题与正文
    if (this.editorTitle.trim().length === 0 || this.editorContent.trim().length === 0) {
      this.showToast('请至少填写标题和正文');
      return;
    }
    // 组装文章结构：id 用时间戳保证唯一，缺省字段使用默认值
    const article: KnowledgeArticle = {
      id: `admin-${Date.now()}`,
      category: this.editorCategory.trim() || '校园行动',
      title: this.editorTitle.trim(),
      summary: this.editorSummary.trim() || '管理员补充的双碳学习内容。',
      readTime: '自定义',
      illustration: 'neutral',
      keywords: [this.editorTitle.trim(), this.editorCategory.trim() || '校园行动'],
      paragraphs: [this.editorContent.trim()],
      sourceName: this.editorSourceName.trim() || '碳记管理员',
      sourceTitle: '管理员补充资料',
      sourceUrl: this.editorSourceUrl.trim() || '应用内置资料'
    };
    try {
      // 先持久化到本机，再更新内存列表
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      await this.knowledgeService.saveUserArticle(context, article);
      this.articles = [...this.articles, article];
      this.clearEditor();
      this.showingEditor = false;
      this.showToast('文档已加入知识库');
    } catch (error) {
      this.showToast('文档保存失败，请稍后重试');
    }
  }

  /**
   * 管理员文档编辑器
   * 固定高度的面板：标题行（含取消按钮） + 标题/摘要/分类/正文/来源输入框 + 保存按钮
   */
  @Builder
  private AdminEditor() {
    Scroll() {
      Column({ space: 12 }) {
        // 标题行：面板标题 + 取消按钮
        Row() {
          Text('新增知识文档')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173F2E')
          Blank()
          Button('取消', { type: ButtonType.Normal, stateEffect: false })
            .fontSize(14)
            .fontColor('#5E7468')
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.clearEditor();
              this.showingEditor = false;
            })
        }
        .width('100%')
        // 文档标题输入框
        TextInput({ placeholder: '文档标题', text: this.editorTitle })
          .height(46)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorTitle = value; })
        // 一句话摘要输入框（可选）
        TextInput({ placeholder: '一句话摘要（可选）', text: this.editorSummary })
          .height(46)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorSummary = value; })
        // 分类输入框（默认校园行动）
        TextInput({ placeholder: '分类，例如：校园行动', text: this.editorCategory })
          .height(46)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorCategory = value; })
        // 正文内容多行输入域
        TextArea({ placeholder: '正文内容', text: this.editorContent })
          .height(140)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorContent = value; })
        // 来源机构输入框（可选）
        TextInput({ placeholder: '来源机构（可选）', text: this.editorSourceName })
          .height(46)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorSourceName = value; })
        // 来源网址输入框（可选）
        TextInput({ placeholder: '来源网址（可选）', text: this.editorSourceUrl })
          .height(46)
          .backgroundColor('#EAF2E8')
          .borderRadius(12)
          .onChange((value: string): void => { this.editorSourceUrl = value; })
        // 保存按钮：触发保存流程
        Button('保存到知识库', { type: ButtonType.Capsule, stateEffect: true })
          .width('100%')
          .height(46)
          .fontColor('#FFFFFF')
          .backgroundColor('#4C9576')
          .onClick((): void => { this.saveEditorArticle(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 20 })
    }
    .width('100%')
    .height(360)
    .backgroundColor('#F0F5EE')
  }

  /**
   * 分类筛选栏
   * 横向可滚动的胶囊按钮组：选中项绿底白字，点击切换分类
   */
  @Builder
  private CategoryBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(KNOWLEDGE_CATEGORIES, (category: string) => {
          Button(category, { type: ButtonType.Normal, stateEffect: false })
            .height(34)
            .fontSize(14)
            .fontColor(this.selectedCategory === category ? '#FFFFFF' : '#527060')
            .backgroundColor(this.selectedCategory === category ? '#4C9576' : '#EDF3EA')
            .borderRadius(17)
            .padding({ left: 15, right: 15 })
            .onClick((): void => {
              this.selectedCategory = category;
            })
        }, (category: string): string => category)
      }
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height(50)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  /**
   * 单篇文章列表行
   * 左侧文字信息 + 右侧收藏按钮；整行点击进入详情
   * @param article 文章数据
   */
  @Builder
  private ArticleRow(article: KnowledgeArticle) {
    Row({ space: 10 }) {
      // 文字从行首开始，保证成长页文章列表紧凑、连续
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(article.category)
            .fontSize(12)
            .fontColor('#4C8067')
          Text(article.readTime)
            .fontSize(12)
            .fontColor('#8A968F')
        }
        .width('100%')
        Text(article.title)
          .width('100%')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#153F2E')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(article.summary)
          .width('100%')
          .fontSize(14)
          .fontColor('#65756B')
          .lineHeight(21)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧：收藏按钮，心形图标切换收藏状态
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Image(this.isFavorite(article.id) ? $r('app.media.diary_heart_filled') : $r('app.media.diary_heart'))
          .syncLoad(true)
          .width(24)
          .height(24)
      }
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.isFavorite(article.id) ? '取消收藏' : '收藏文章')
      .onClick((): void => this.toggleFavorite(article.id))
    }
    .width('100%')
    .padding({ top: 15, bottom: 15 })
    .alignItems(VerticalAlign.Top)
    // 整行点击进入文章详情
    .onClick((): void => {
      this.openedArticleId = article.id;
    })
  }

  /**
   * 文章列表区
   * 三种视图：加载中（幼苗提示）/ 空结果（分类与关键字区分文案）/ 文章列表
   */
  @Builder
  private ArticleList() {
    if (this.loading) {
      // 加载中：幼苗图标 + 提示文案
      Column({ space: 12 }) {
        Image($r('app.media.diary_sprout'))
          .syncLoad(true)
          .width(44)
          .height(44)
        Text('正在整理知识内容')
          .fontSize(15)
          .fontColor('#718078')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.filteredArticles().length === 0) {
      // 空结果：按是否处于收藏视图区分提示文案
      Column({ space: 10 }) {
        Image($r('app.media.diary_search'))
          .syncLoad(true)
          .width(38)
          .height(38)
          .opacity(0.6)
        Text(this.selectedCategory === '收藏' ? '还没有收藏文章' : '没有找到相关内容')
          .fontSize(16)
          .fontColor('#718078')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      // 文章列表：稳定 id 作为键，底部分隔线统一绘制
      List({ space: 0 }) {
        ForEach(this.filteredArticles(), (article: KnowledgeArticle) => {
          ListItem() {
            this.ArticleRow(article)
          }
        }, (article: KnowledgeArticle): string => article.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 22, right: 22 })
      .divider({ strokeWidth: 0.5, color: '#DBE2D8' })
      .contentEndOffset(220)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  /**
   * 文章详情视图
   * 顶部操作栏（返回/收藏） + 正文滚动区（分类信息、标题、摘要块、分段正文、资料来源）
   * @param article 当前打开的文章
   */
  @Builder
  private ArticleDetail(article: KnowledgeArticle) {
    Column() {
      // 顶部操作栏：居中标题"双碳科普" + 左返回 + 右收藏
      Stack({ alignContent: Alignment.Center }) {
        Row() {
          // 返回按钮：清空打开状态回到列表
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Text('‹')
              .fontSize(40)
              .fontColor('#174E3A')
          }
          .width(44)
          .height(48)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('返回知识列表')
          .onClick((): void => {
            this.openedArticleId = '';
          })
          Blank()
          // 收藏按钮：与列表行一致
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            Image(this.isFavorite(article.id) ? $r('app.media.diary_heart_filled') : $r('app.media.diary_heart'))
              .syncLoad(true)
              .width(25)
              .height(25)
          }
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.isFavorite(article.id) ? '取消收藏' : '收藏文章')
          .onClick((): void => this.toggleFavorite(article.id))
        }
        .width('100%')

        Text('双碳科普')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
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
              .width(42)
              .height(42)
              .padding(6)
              .backgroundColor('#EAF0E5')
              .borderRadius(21)
            Column({ space: 4 }) {
              Text(article.category)
                .fontSize(13)
                .fontColor('#4C8067')
              Text(article.readTime)
                .fontSize(12)
                .fontColor('#8A968F')
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
            Text('资料来源')
              .width('100%')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#345F4B')
            Text(article.sourceName)
              .width('100%')
              .fontSize(14)
              .fontColor('#567064')
            Text(article.sourceTitle)
              .width('100%')
              .fontSize(14)
              .fontColor('#567064')
              .lineHeight(22)
            Text(article.sourceUrl)
              .width('100%')
              .fontSize(12)
              .fontColor('#4C8067')
              .maxLines(3)
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#F0F3EC')
          .borderRadius(8)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 185 })
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
   * 底部导航条的单个栏目项
   * 与首页 TabItem 一致：选中态淡绿底托 + 按压缩放与提亮反馈
   * @param label 栏目名称
   * @param icon 栏目图标资源
   */
  @Builder
  private NavItem(label: string, icon: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 5 }) {
        // 栏目图标
        Image(icon)
          .syncLoad(true)
          .width(26)
          .height(26)
        // 栏目名称：选中态森林绿加粗
        Text(label)
          .fontSize(12)
          .fontColor(this.selectedTab === label ? '#245C40' : '#8B968E')
          .fontWeight(this.selectedTab === label ? FontWeight.Medium : FontWeight.Normal)
      }
      .width('100%')
      // 底托内边距与颜色：仅选中项显示淡绿底托，按压时提亮
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(this.selectedTab === label
        ? (this.pressedTab === label ? '#CCDCEDE4' : '#B3D2E7D7')
        : (this.pressedTab === label ? '#26FFFFFF' : Color.Transparent))
      .borderRadius(18)
      .animation({ duration: 180, curve: Curve.Friction })
    }
    .layoutWeight(1)
    .height(68)
    .padding(0)
    .backgroundColor(Color.Transparent)
    // 按压缩放：轻微缩小，松开恢复
    .scale({
      x: this.pressedTab === label ? 0.94 : 1,
      y: this.pressedTab === label ? 0.94 : 1
    })
    .animation({ duration: 180, curve: Curve.Friction })
    .accessibilityText(this.selectedTab === label ? `${label}，当前栏目` : label)
    .onClick((): void => this.navigate(label))
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
   * 底部四栏导航条
   * 磨砂兜底层（半透明浅绿 + 材质模糊 + 细高光描边 + 柔和阴影）+ 液态玻璃升级层
   */
  @Builder
  private BottomNav() {
    Column({ space: 0 }) {
      Row() {
        this.NavItem('日记', $r('app.media.diary_diary'))
        this.NavItem('足迹', $r('app.media.diary_leaf'))
        this.NavItem('成长', $r('app.media.diary_sprout'))
        this.NavItem('我的', $r('app.media.diary_person'))
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
   * 页面布局
   * Stack 底部对齐：底层按状态切换文章详情/编辑器/列表视图，上层为底部导航
   */
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 文章详情优先级最高：打开文章时整页切换为详情视图
        if (this.openedArticle() !== undefined) {
          this.ArticleDetail(this.openedArticle() as KnowledgeArticle)
        } else {
          // 列表视图：搜索头部固定，下面的正文区独立占据剩余高度。
          this.SearchHeader()
          if (this.showingEditor && this.adminMode) {
            this.AdminEditor()
          } else {
            // 推荐区、筛选栏和文章列表在同一受限容器内排版，
            // 推荐内容变长时只压缩列表，不会把底部导航推入正文流。
            Column() {
              // 分类栏固定紧跟搜索框；点击“全部”时也不会被推荐区挤到下面。
              this.CategoryBar()
              this.ArticleList()
            }
            .width('100%')
            .layoutWeight(1)
            // 给滚动内容留出底栏的可视安全区，最后一条文章不会被玻璃底栏盖住。
            .padding({ bottom: 104 })
          }
        }
      }
      .width('100%')
      .height('100%')
      this.BottomNav()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
    // 将底部液态玻璃导航的绘制范围延伸到系统手势区，避免导航条与退出手势栏之间出现突兀空白。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

/**
 * 知识中心 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 KnowledgeCenter 组件，不参与实际页面路由
 */
@Preview({
  title: 'KnowledgeCenter', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct KnowledgeCenterPreview {
  build() {
    // 直接渲染知识中心组件
    KnowledgeCenter()
  }
}
