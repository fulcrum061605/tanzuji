/**
 * 应用备份/恢复扩展能力
 * 由系统备份框架在应用数据备份与恢复流程中自动调用
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

/** hilog 日志输出域标识，用于日志过滤 */
const DOMAIN = 0x0000;

/** 备份扩展 Ability：实现应用数据备份与恢复的钩子函数 */
export default class EntryBackupAbility extends BackupExtensionAbility {
  /** 系统触发备份时回调（当前仅记录日志，无自定义备份数据） */
  async onBackup() {
    hilog.info(DOMAIN, 'testTag', 'onBackup ok');
    await Promise.resolve();
  }

  /** 系统触发恢复时回调，携带备份时应用的版本信息（当前仅记录日志） */
  async onRestore(bundleVersion: BundleVersion) {
    hilog.info(DOMAIN, 'testTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
