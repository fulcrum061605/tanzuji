/**
 * 本地日记记录持久化服务。
 * 记录列表整体以 JSON 存入 Preferences，应用重启后仍恢复同一批记录；
 * 图标等 Resource 无法序列化，读取时按行为 id 统一还原。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { RecordDraft } from '../pages/RecordDetail';
import { BehaviorOption } from '../pages/BehaviorPicker';

/** 本地日记存储：记录字段使用 JSON 友好的值，图标在读取时按行为 id 恢复。 */
export class DiaryStorageService {
  /** Preferences 存储库名 */
  private static readonly STORE_NAME: string = 'tanji_diary_records_v2';
  /** 记录列表在存储库中的键名 */
  private static readonly KEY: string = 'records';

  /**
   * 按行为 id 恢复图标资源
   * 持久化 JSON 无法保存 Resource，读取时统一在此还原
   * @param id 行为 id
   * @returns 对应的图标资源，未知行为回落到旧物再利用图标
   */
  private iconFor(id: string): Resource {
    switch (id) {
      case 'walk': return $r('app.media.diary_walk');
      case 'bike': return $r('app.media.diary_bike');
      case 'transit':
      case 'carpool':
      case 'metro': return $r('app.media.diary_transit');
      case 'electricity':
      case 'standby': return $r('app.media.diary_electricity');
      case 'water':
      case 'shower': return $r('app.media.diary_water');
      case 'meal':
      case 'lowCarbonMeal': return $r('app.media.diary_meal');
      case 'recycle':
      case 'paperRecycle':
      case 'clothesRecycle': return $r('app.media.diary_recycle');
      case 'shopping': return $r('app.media.diary_shopping');
      default: return $r('app.media.diary_reuse');
    }
  }

  /**
   * 清洗单条记录：补全缺失的主键与时间戳、数值夹取非负、枚举兜底，
   * 防止历史数据或异常 JSON 破坏记录不变量
   * @param value 待清洗的记录
   * @returns 字段合法的记录
   */
  private normalize(value: RecordDraft): RecordDraft {
    const behavior: BehaviorOption = {
      id: value.behavior?.id ?? 'reuse',
      name: value.behavior?.name ?? '旧物再利用',
      icon: this.iconFor(value.behavior?.id ?? 'reuse')
    };
    const now: number = Date.now();
    return {
      recordId: value.recordId ?? value.operationId ?? `record-${now}-${Math.floor(Math.random() * 100000)}`,
      operationId: value.operationId ?? value.recordId ?? `record-${now}`,
      createdAt: value.createdAt ?? value.recordedAt ?? now,
      updatedAt: value.updatedAt ?? value.recordedAt ?? now,
      recordedAt: value.recordedAt ?? value.createdAt ?? now,
      behavior: behavior,
      amount: Math.max(0, Number(value.amount) || 0),
      unit: value.unit ?? '',
      reductionKg: Math.max(0, Number(value.reductionKg) || 0),
      note: typeof value.note === 'string' ? value.note : '',
      // 图片状态只由真实相册 URI 决定，避免历史的模拟 hasPhoto 标志再次显示假图片。
      hasPhoto: typeof value.photoUri === 'string' && value.photoUri.length > 0,
      photoUri: typeof value.photoUri === 'string' ? value.photoUri : '',
      evidenceSource: value.evidenceSource ?? 'manual',
      verificationStatus: value.verificationStatus === 'verified' ? 'verified' : 'pending',
      evidenceId: value.evidenceId ?? '',
      scoreEnabled: value.scoreEnabled === true
    };
  }

  /**
   * 读取全部本地记录；无数据或 JSON 解析失败时返回空数组
   * @param context 应用上下文
   * @returns 清洗后的记录数组
   */
  async load(context: common.Context): Promise<RecordDraft[]> {
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: DiaryStorageService.STORE_NAME });
    const value: preferences.ValueType = await store.get(DiaryStorageService.KEY, '[]');
    if (typeof value !== 'string') {
      return [];
    }
    try {
      const parsed: RecordDraft[] = JSON.parse(value) as RecordDraft[];
      return Array.isArray(parsed) ? parsed.map((item: RecordDraft): RecordDraft => this.normalize(item)) : [];
    } catch (error) {
      return [];
    }
  }

  /**
   * 清洗并整体覆盖保存全部记录，立即落盘
   * @param context 应用上下文
   * @param records 全部记录
   */
  async saveAll(context: common.Context, records: RecordDraft[]): Promise<void> {
    const normalized: RecordDraft[] = records.map((item: RecordDraft): RecordDraft => this.normalize(item));
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: DiaryStorageService.STORE_NAME });
    await store.put(DiaryStorageService.KEY, JSON.stringify(normalized));
    await store.flush();
  }

  /**
   * 新增或更新一条记录并返回最新列表
   * recordId 已存在时保留原创建时间并原位更新，否则插入到列表最前
   * @param context 应用上下文
   * @param record 待写入的记录
   * @returns 保存后的完整记录列表
   */
  async upsert(context: common.Context, record: RecordDraft): Promise<RecordDraft[]> {
    const current: RecordDraft[] = await this.load(context);
    const normalized: RecordDraft = this.normalize(record);
    const index: number = current.findIndex((item: RecordDraft): boolean => item.recordId === normalized.recordId);
    if (index >= 0) {
      normalized.createdAt = current[index].createdAt;
      current[index] = normalized;
    } else {
      current.unshift(normalized);
    }
    await this.saveAll(context, current);
    return current;
  }

  /**
   * 按 recordId 删除一条记录并返回最新列表
   * @param context 应用上下文
   * @param recordId 记录主键
   * @returns 删除后的完整记录列表
   */
  async remove(context: common.Context, recordId: string): Promise<RecordDraft[]> {
    const current: RecordDraft[] = await this.load(context);
    const next: RecordDraft[] = current.filter((item: RecordDraft): boolean => item.recordId !== recordId);
    await this.saveAll(context, next);
    return next;
  }
}
