/**
 * 工程级 hvigor 构建脚本
 * 为整个应用工程注册内置构建任务插件，由 hvigor 构建系统在构建启动时加载
 */
import { appTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: appTasks, /* 内置应用级构建插件，不可修改 */
  plugins: []       /* 自定义插件，用于扩展 hvigor 构建功能 */
}