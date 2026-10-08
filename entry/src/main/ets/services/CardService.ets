/**
 * 桌面服务卡片数据服务
 * 职责一：从本地日记记录汇总卡片展示数据（今日/近7天减排量与次数）；
 * 职责二：维护"已添加到桌面的卡片 formId 列表"——卡片扩展进程与主应用分进程运行，
 *         两侧通过同一 Preferences 存储库共享该列表（卡片进程短存活，写入即落盘）。
 * 主应用在记录新增/删除/整体恢复后调用 refreshAll，把最新统计推送到全部卡片。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiaryStorageService } from './DiaryStorageService';
import { RecordDraft } from '../pages/RecordDetail';

/** hilog 日志输出域标识，用于日志过滤 */
const DOMAIN = 0x0000;

/** 卡片数据服务：仅提供静态方法，无实例状态 */
export class CardService {
  /** formId 列表的 Preferences 存储库名（独立于日记存储，避免键冲突） */
  private static readonly FORM_STORE_NAME: string = 'tanji_card_forms_v1';
  /** formId 列表在存储库中的键名 */
  private static readonly FORM_IDS_KEY: string = 'formIds';

  /**
   * 卡片首帧占位数据：onAddForm 必须同步返回，
   * 真实统计随后的 refreshOne 异步推送，通常在百毫秒内完成替换
   */
  static placeholderData(): Record<string, string> {
    return {
      'dateLabel': CardService.formatDateLabel(Date.now()),
      'todayKg': '0.00',
      'todayCount': '0',
      'weekKg': '0.0',
      'weekCount': '0'
    };
  }

  /**
   * 汇总卡片展示数据：今日与近 7 天（含今日）的减排量、记录次数与日期标签
   * 键名与卡片页 @LocalStorageProp 一一对应
   * @param context 应用上下文（主应用或卡片扩展进程均可）
   */
  static async buildCardData(context: common.Context): Promise<Record<string, string>> {
    const records: RecordDraft[] = await new DiaryStorageService().load(context);
    const now: Date = new Date();
    const startOfToday: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const weekStart: number = startOfToday - 6 * 24 * 60 * 60 * 1000;
    let todayKg: number = 0;
    let todayCount: number = 0;
    let weekKg: number = 0;
    let weekCount: number = 0;
    records.forEach((record: RecordDraft): void => {
      const at: number = record.recordedAt ?? record.createdAt ?? Date.now();
      if (at >= startOfToday) {
        todayKg += record.reductionKg;
        todayCount += 1;
      }
      if (at >= weekStart) {
        weekKg += record.reductionKg;
        weekCount += 1;
      }
    });
    return {
      'dateLabel': CardService.formatDateLabel(now.getTime()),
      'todayKg': todayKg.toFixed(2),
      'todayCount': `${todayCount}`,
      'weekKg': weekKg.toFixed(1),
      'weekCount': `${weekCount}`
    };
  }

  /**
   * 登记一张新添加的卡片
   * @param context 应用上下文
   * @param formId 卡片实例 id
   */
  static async rememberForm(context: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const ids: string[] = await CardService.loadFormIds(context);
    if (!ids.includes(formId)) {
      ids.push(formId);
      await CardService.saveFormIds(context, ids);
    }
  }

  /**
   * 移除一张已删除卡片的登记
   * @param context 应用上下文
   * @param formId 卡片实例 id
   */
  static async forgetForm(context: common.Context, formId: string): Promise<void> {
    const ids: string[] = await CardService.loadFormIds(context);
    const next: string[] = ids.filter((id: string): boolean => id !== formId);
    if (next.length !== ids.length) {
      await CardService.saveFormIds(context, next);
    }
  }

  /**
   * 重新汇总数据并推送到单张卡片（卡片添加与周期刷新时使用）
   * 刷新失败仅记录日志，不影响任何主流程
   * @param context 应用上下文
   * @param formId 卡片实例 id
   */
  static async refreshOne(context: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const data: Record<string, string> = await CardService.buildCardData(context);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (error) {
      hilog.warn(DOMAIN, 'CardService', 'refresh single card failed');
    }
  }

  /**
   * 把最新统计推送到全部已添加卡片（主应用记录变化后调用）
   * 内部消化全部异常：卡片刷新永远不阻塞、不中断日记保存流程
   * @param context 应用上下文
   */
  static async refreshAll(context: common.Context): Promise<void> {
    try {
      const ids: string[] = await CardService.loadFormIds(context);
      if (ids.length === 0) {
        return;
      }
      const data: Record<string, string> = await CardService.buildCardData(context);
      const formData: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
      ids.forEach((formId: string): void => {
        formProvider.updateForm(formId, formData).catch((): void => {
          hilog.warn(DOMAIN, 'CardService', 'update card failed');
        });
      });
    } catch (error) {
      // 读档或建绑定失败均忽略：没有卡片时本方法近似空操作
    }
  }

  /**
   * 读取已登记的卡片 id 列表
   * 先从缓存移除再重新打开：formId 多由卡片进程写入，
   * 清缓存保证主应用长期存活的 Preferences 实例也能读到最新值
   */
  private static async loadFormIds(context: common.Context): Promise<string[]> {
    try {
      await preferences.removePreferencesFromCache(context, { name: CardService.FORM_STORE_NAME });
    } catch (error) {
      // 存储库尚未缓存时清缓存会报错，忽略后正常打开即可
    }
    const store: preferences.Preferences =
      await preferences.getPreferences(context, { name: CardService.FORM_STORE_NAME });
    const value: preferences.ValueType = await store.get(CardService.FORM_IDS_KEY, '[]');
    if (typeof value !== 'string') {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(value) as string[];
      return Array.isArray(parsed) ? parsed.filter((id: string): boolean => id.length > 0) : [];
    } catch (error) {
      return [];
    }
  }

  /**
   * 覆盖保存卡片 id 列表并立即落盘
   * @param context 应用上下文
   * @param formIds 全部有效卡片 id
   */
  private static async saveFormIds(context: common.Context, formIds: string[]): Promise<void> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, { name: CardService.FORM_STORE_NAME });
    await store.put(CardService.FORM_IDS_KEY, JSON.stringify(formIds));
    await store.flush();
  }

  /**
   * 格式化日期标签，例如"10月6日"
   * @param timestamp 时间戳（毫秒）
   */
  private static formatDateLabel(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }
}
