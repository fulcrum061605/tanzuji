/**
 * 双碳知识数据模型与服务
 * 文章正文随 HAP 打包在 rawfile 中，收藏与管理员自定义文章保存在本机 Preferences；
 * 由成长页（KnowledgeCenter）与我的页（MyPage）共用，保证收藏数据跨页同步。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

/** 知识文章数据结构：列表展示、详情阅读与收藏共用 */
export interface KnowledgeArticle {
  /** 文章唯一标识：作为 ForEach 的键，同时用于收藏状态判断 */
  id: string;
  /** 所属分类（如 '双碳基础'/'生活技巧'/'校园行动'） */
  category: string;
  /** 文章标题 */
  title: string;
  /** 一句话摘要：列表页展示 */
  summary: string;
  /** 预计阅读时长文案（如 '约 3 分钟' 或 '自定义'） */
  readTime: string;
  /** 插图类型标识：映射到对应的图标资源 */
  illustration: string;
  /** 搜索关键字列表：参与搜索匹配 */
  keywords: string[];
  /** 正文段落：详情页按序号分段渲染 */
  paragraphs: string[];
  /** 来源机构名称 */
  sourceName: string;
  /** 来源文章标题 */
  sourceTitle: string;
  /** 来源网址 */
  sourceUrl: string;
}

/** rawfile 知识库 JSON 文件的反序列化结构 */
interface KnowledgePayload {
  /** 内置文章列表 */
  articles: KnowledgeArticle[];
}

/**
 * 双碳知识资源与收藏服务。
 * 正文随 HAP 放入 rawfile，运行时通过 ResourceManager 读取，因此断网也能阅读和搜索。
 */
export class KnowledgeService {
  /** Preferences 存储名：收藏与管理员自定义文章共用同一存储 */
  private static readonly STORE_NAME: string = 'tanji_knowledge_v1';
  /** 收藏文章 id 列表的存储键 */
  private static readonly FAVORITE_KEY: string = 'favorite_article_ids';
  /** 管理员自定义文章列表的存储键 */
  private static readonly USER_ARTICLES_KEY: string = 'user_knowledge_articles';

  /**
   * 加载全部知识文章
   * 合并 rawfile 内置文章与管理员自定义文章，自定义文章排在末尾。
   * @param context 应用上下文（用于读取资源与打开存储）
   * @returns 全部文章列表
   */
  async loadArticles(context: common.Context): Promise<KnowledgeArticle[]> {
    // 读取 rawfile 中的内置知识库 JSON 并按 UTF-8 解码
    const content: Uint8Array = await context.resourceManager.getRawFileContent('carbon_knowledge.json');
    const text: string = util.TextDecoder.create('utf-8').decodeToString(content);
    const payload: KnowledgePayload = JSON.parse(text) as KnowledgePayload;
    // 追加本机保存的管理员自定义文章
    const userArticles: KnowledgeArticle[] = await this.loadUserArticles(context);
    return [...payload.articles, ...userArticles];
  }

  /**
   * 读取管理员自定义文章列表
   * 存储不存在或数据损坏时返回空列表，不影响内置文章展示。
   * @param context 应用上下文
   * @returns 自定义文章列表
   */
  private async loadUserArticles(context: common.Context): Promise<KnowledgeArticle[]> {
    const store: preferences.Preferences = await preferences.getPreferences(context, {
      name: KnowledgeService.STORE_NAME
    });
    const value: preferences.ValueType = await store.get(KnowledgeService.USER_ARTICLES_KEY, '[]');
    if (typeof value !== 'string') {
      return [];
    }
    // 反序列化失败按空列表兜底，避免脏数据导致页面崩溃
    try {
      const parsed: KnowledgeArticle[] = JSON.parse(value) as KnowledgeArticle[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }

  /**
   * 保存一篇管理员自定义文章
   * 读取已有列表后追加到末尾，避免覆盖，最后落盘。
   * @param context 应用上下文
   * @param article 待保存的文章
   */
  async saveUserArticle(context: common.Context, article: KnowledgeArticle): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, {
      name: KnowledgeService.STORE_NAME
    });
    // 读取已有列表后追加，避免覆盖历史数据
    const existing: KnowledgeArticle[] = await this.loadUserArticles(context);
    await store.put(KnowledgeService.USER_ARTICLES_KEY, JSON.stringify([...existing, article]));
    await store.flush();
  }

  /**
   * 读取收藏文章 id 列表
   * @param context 应用上下文
   * @returns 已收藏的文章 id 数组
   */
  async loadFavorites(context: common.Context): Promise<string[]> {
    const store: preferences.Preferences = await preferences.getPreferences(context, {
      name: KnowledgeService.STORE_NAME
    });
    const value: preferences.ValueType = await store.get(KnowledgeService.FAVORITE_KEY, [] as string[]);
    if (!Array.isArray(value)) {
      return [];
    }
    // 只保留字符串项，过滤掉异常写入的脏数据
    const ids: string[] = [];
    value.forEach((item: string | number | boolean): void => {
      if (typeof item === 'string') {
        ids.push(item);
      }
    });
    return ids;
  }

  /**
   * 保存收藏文章 id 列表
   * @param context 应用上下文
   * @param ids 最新的收藏 id 数组
   */
  async saveFavorites(context: common.Context, ids: string[]): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, {
      name: KnowledgeService.STORE_NAME
    });
    await store.put(KnowledgeService.FAVORITE_KEY, ids);
    await store.flush();
  }
}
