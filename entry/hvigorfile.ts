/**
 * entry 模块级 hvigor 构建脚本
 * 为 HAP 模块注册内置构建任务插件，由 hvigor 构建系统在构建启动时加载
 */
import { hapTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hapTasks, /* 内置 HAP 模块构建插件，不可修改 */
  plugins: []       /* 自定义插件，用于扩展 hvigor 构建功能 */
}