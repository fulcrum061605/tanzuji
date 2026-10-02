/**
 * 本地备份与 CSV 报表服务。
 * 备份内容（记录 + 积分 + 收藏）整体保存在本机 Preferences 中，不上传网络；
 * CSV 报表用于展示统计明细，同时保存为最近一次导出内容。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { picker, fileIo } from '@kit.CoreFileKit';
import { RecordDraft } from '../pages/RecordDetail';
import { PointsSnapshot } from './CarbonPointsService';

/** 一次完整备份的内容：版本号、导出时间、日记记录、积分快照与文章收藏 */
export interface BackupPayload {
  /** 备份结构版本号；当前固定为 1 */
  version: number;
  /** 备份导出时间（毫秒时间戳） */
  exportedAt: number;
  /** 全部本地日记记录 */
  records: RecordDraft[];
  /** 积分快照 */
  points: PointsSnapshot;
  /** 已收藏的文章 id 列表 */
  favoriteIds: string[];
}

  /** 本地备份与报表服务。备份不上传网络，CSV 同时保存为最近一次导出内容。 */
export class BackupService {
  /** Preferences 存储库名 */
  private static readonly STORE_NAME: string = 'tanji_backup_v1';
  /** 备份 JSON 在存储库中的键名 */
  private static readonly BACKUP_KEY: string = 'backup_json';
  /** 最近一次 CSV 报表在存储库中的键名 */
  private static readonly CSV_KEY: string = 'last_csv';

  /**
   * 备份当前全部本地数据（记录 + 积分 + 收藏）并立即落盘
   * @param context 应用上下文
   * @param records 全部日记记录
   * @param points 积分快照
   * @param favoriteIds 已收藏的文章 id 列表
   */
  async backup(context: common.Context, records: RecordDraft[], points: PointsSnapshot, favoriteIds: string[]): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: BackupService.STORE_NAME });
    const payload: BackupPayload = {
      version: 1,
      exportedAt: Date.now(),
      records: records,
      points: points,
      favoriteIds: favoriteIds
    };
    await store.put(BackupService.BACKUP_KEY, JSON.stringify(payload));
    await store.flush();
  }

  /**
   * 读取最近一次备份内容
   * 无备份、JSON 损坏或版本不符时返回 version 为 0 的空载荷
   * @param context 应用上下文
   * @returns 备份载荷
   */
  async restore(context: common.Context): Promise<BackupPayload> {
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: BackupService.STORE_NAME });
    const value: preferences.ValueType = await store.get(BackupService.BACKUP_KEY, '');
    if (typeof value !== 'string' || value.length === 0) {
      return { version: 0, exportedAt: 0, records: [], points: {
        balance: 0, totalEarned: 0, totalRedeemed: 0, claimedTaskKeys: [], rewardedOperationIds: [],
        redeemedRewardIds: [], recordDay: '', recordDayPoints: 0
      }, favoriteIds: [] };
    }
    try {
      const payload: BackupPayload = JSON.parse(value) as BackupPayload;
      return payload.version === 1 && Array.isArray(payload.records) ? payload : {
        version: 0, exportedAt: 0, records: [], points: {
          balance: 0, totalEarned: 0, totalRedeemed: 0, claimedTaskKeys: [], rewardedOperationIds: [],
          redeemedRewardIds: [], recordDay: '', recordDayPoints: 0
        }, favoriteIds: []
      };
    } catch (error) {
      return { version: 0, exportedAt: 0, records: [], points: {
        balance: 0, totalEarned: 0, totalRedeemed: 0, claimedTaskKeys: [], rewardedOperationIds: [],
        redeemedRewardIds: [], recordDay: '', recordDayPoints: 0
      }, favoriteIds: [] };
    }
  }

  /**
   * 将全部日记记录导出为 CSV 报表，保存为最近一次导出并通过系统文档选择器写入用户指定位置。
   * 单元格统一用双引号包裹，内部引号转义、换行替换为空格，保证表格可读
   * @param context 应用上下文
   * @param records 全部日记记录
   * @returns CSV 文本内容；用户取消保存时仍返回预览文本
   */
  async exportCsv(context: common.Context, records: RecordDraft[]): Promise<string> {
    const rows: string[] = ['recordId,recordedAt,behavior,amount,unit,reductionKg,verificationStatus,evidenceSource,photoUri,note'];
    records.forEach((record: RecordDraft): void => {
      const cells: string[] = [
        record.recordId ?? record.operationId ?? '',
        new Date(record.recordedAt ?? record.createdAt ?? Date.now()).toISOString(),
        record.behavior.name,
        record.amount.toString(),
        record.unit,
        record.reductionKg.toFixed(3),
        record.verificationStatus,
        record.evidenceSource,
        record.photoUri ?? '',
        record.note.replace(/"/g, '""').replace(/\n/g, ' ')
      ];
      rows.push(cells.map((cell: string): string => `"${cell}"`).join(','));
    });
    const csv: string = rows.join('\n');
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: BackupService.STORE_NAME });
    await store.put(BackupService.CSV_KEY, csv);
    await store.flush();

    try {
      // 让用户选择文件名与保存位置，再通过系统 URI 写入 CSV，不依赖应用沙箱路径。
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.save({
        newFileNames: [`tanji-carbon-report-${this.fileDate(new Date())}`],
        fileSuffixChoices: ['CSV|.csv']
      });
      if (uris.length > 0 && uris[0].length > 0) {
        const file = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          await fileIo.write(file.fd, csv);
        } finally {
          await fileIo.close(file);
        }
      }
    } catch (error) {
      // 用户取消选择位置时保留报表预览，不影响本地 CSV 内容生成。
    }
    return csv;
  }

  /** 文件名中的日期部分，避免出现系统不允许的路径字符。 */
  private fileDate(date: Date): string {
    return `${date.getFullYear()}${(date.getMonth() + 1).toString().padStart(2, '0')}${date.getDate().toString().padStart(2, '0')}`;
  }

  /**
   * 读取最近一次导出的 CSV 报表
   * @param context 应用上下文
   * @returns CSV 文本；从未导出时为空串
   */
  async lastCsv(context: common.Context): Promise<string> {
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: BackupService.STORE_NAME });
    const value: preferences.ValueType = await store.get(BackupService.CSV_KEY, '');
    return typeof value === 'string' ? value : '';
  }
}
