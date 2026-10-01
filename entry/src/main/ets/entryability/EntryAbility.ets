/**
 * 应用入口 UIAbility
 * 负责应用生命周期回调处理、主窗口页面加载与深浅色模式设置
 */
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** hilog 日志输出域标识，用于日志过滤 */
const DOMAIN = 0x0000;

/** 入口 Ability：应用启动时由系统拉起，管理应用生命周期 */
export default class EntryAbility extends UIAbility {
  /** Ability 创建回调：应用拉起时触发，可做全局初始化 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 当前整套日记 UI 采用浅色纸张主题；必须在加载页面前设置，避免跟随深色系统产生白字。
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (error) {
      // 页面自身也显式设置所有输入颜色，即使系统模式设置失败仍保持可读。
      hilog.warn(DOMAIN, 'testTag', 'Could not apply light color mode');
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 记录液态玻璃（沉浸式系统材质）能力与设备材质档位，便于核对悬浮条在当前设备上的实际渲染路径；
    // 低版本系统通过短路求值跳过 API 26 接口调用
    try {
      const glassCapable: boolean = deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported();
      const glassLevel: string = deviceInfo.sdkApiVersion >= 26
        ? `${uiMaterial.getGlobalMaterialLevel()}` : 'N/A';
      hilog.info(DOMAIN, 'testTag',
        'glass capable: %{public}s, material level: %{public}s', `${glassCapable}`, glassLevel);
    } catch (error) {
      hilog.warn(DOMAIN, 'testTag', 'Could not query immersive material capability');
    }
  }

  /** Ability 销毁回调：可在此释放全局资源 */
  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /** 主窗口创建回调：加载入口页面并设置应用深浅色模式 */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 加载入口页面 'pages/Index'，作为应用主窗口内容
    windowStage.loadContent('pages/Index', (err) => {
      // 加载失败：记录错误日志并终止后续处理
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 加载成功日志
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 系统状态栏与底部导航栏沿用纸张底色，保留系统安全区，不遮挡页面。
    try {
      windowStage.getMainWindowSync().setWindowSystemBarProperties({
        statusBarColor: '#F7F8F2',
        statusBarContentColor: '#123F2E',
        // 底部手势区与导航条保持同一浅绿玻璃色，避免出现一整块突兀白色空白。
        navigationBarColor: '#EAF3E7',
        navigationBarContentColor: '#123F2E'
      }).catch(() => {
        hilog.warn(DOMAIN, 'testTag', 'Could not apply system bar colors');
      });
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'Could not access main window for system bar colors');
    }
  }

  /** 主窗口销毁回调：可在此释放与窗口相关的 UI 资源 */
  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** 应用回到前台回调 */
  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  /** 应用退到后台回调 */
  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
