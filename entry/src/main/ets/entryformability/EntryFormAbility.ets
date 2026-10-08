/**
 * 桌面服务卡片生命周期管理
 * 卡片扩展进程与主应用分进程运行：formId 列表经 CardService 持久化共享；
 * onAddForm 需同步返回，先给占位数据再立即异步推送真实统计
 * （卡片进程在生命周期回调后仅存活约 10 秒，足够完成一次数据汇总）
 */
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardService } from '../services/CardService';

/** hilog 日志输出域标识，用于日志过滤 */
const DOMAIN = 0x0000;

/** 卡片扩展 Ability：由系统在卡片添加/刷新/移除时拉起 */
export default class EntryFormAbility extends FormExtensionAbility {
  /** 卡片添加到桌面：登记 formId，同步返回占位数据并异步推送真实统计 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const rawValue: Object | undefined = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = typeof rawValue === 'string' ? rawValue : '';
    if (formId.length === 0) {
      return formBindingData.createFormBindingData(CardService.placeholderData());
    }
    hilog.info(DOMAIN, 'EntryFormAbility', 'onAddForm: %{public}s', formId);
    // "记录今日"快捷卡片无动态数据：不登记、不刷新，避免无意义的统计推送
    const rawName: Object | undefined = want.parameters?.[formInfo.FormParam.NAME_KEY];
    if (rawName === 'quick_add') {
      const emptyData: Record<string, string> = {};
      return formBindingData.createFormBindingData(emptyData);
    }
    CardService.rememberForm(this.context, formId);
    CardService.refreshOne(this.context, formId);
    return formBindingData.createFormBindingData(CardService.placeholderData());
  }

  /** 周期性刷新（form_config 的 updateDuration）：重新汇总并推送 */
  onUpdateForm(formId: string): void {
    CardService.refreshOne(this.context, formId);
  }

  /** 卡片从桌面移除：清除登记的 formId，避免后续刷新空卡片 */
  onRemoveForm(formId: string): void {
    CardService.forgetForm(this.context, formId);
  }
}
