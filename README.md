# 碳记

基于 OpenHarmony/ArkTS 的本地碳足迹记录应用。用户记录低碳行为，系统根据内置碳因子估算减排量；出行类行为可使用系统定位或华为运动数据核验，核验记录才计入正式足迹和积分。

## 赛题功能对照

- 低碳行为核算：步行、骑行、公共交通、节水节电、光盘、回收和绿色消费等行为；支持单位换算、文字和图片记录。
- 数据可视化：足迹页支持日、周、月、年切换，提供折线图、柱状图、饼图、分类汇总和核验率。
- 碳积分激励：每日签到、核验出行任务、科普收藏任务；积分按核验减排量计算并设置单条与每日上限，可兑换本地模拟权益。
- 双碳科普：内置权威来源图文，支持搜索、收藏和离线阅读；管理员演示账号可新增文档。
- 本地数据管理：Preferences 持久化记录、积分和收藏，支持备份、恢复和 CSV 报表导出。

## 演示路线

1. 使用演示账号 `admin / 123456` 登录，或注册本机账号。
2. 在首页点击 `+`，选择行为并填写记录；手动记录会标记为“待核实”，不会计入正式足迹和积分。
3. 出行行为选择“开始系统测量”或读取华为运动数据，获得权限并完成测量后保存，记录才会显示“已核验”。
4. 打开“足迹”，切换日/周/月/年查看三种图表；打开“成长”搜索文章并收藏；在“我的”查看任务、积分、权益和数据管理。

首页的“演示示例”仅用于课堂讲解，明确标注为不计入真实记录、足迹和积分的数据。

## 计算与可信性

碳因子集中维护在 `entry/src/main/ets/services/CarbonFactorService.ets`，审计快照位于 `entry/src/main/resources/rawfile/carbon_factors.json`。核算边界参考 GB/T 32150—2015、IPCC 2006 Guidelines 和生态环境主管部门公开电力因子；生活行为系数属于替代行为估算，详情页会展示口径说明，不能当作官方核证结果。

数据证据分为系统定位、华为运动和手动待核实三类。手动数量可以保存为日记，但不能伪造系统核验，也不能增加正式积分。

## 关键本地数据

- `tanji_diary_records_v2`：真实日记记录。
- `tanji_carbon_points_v1`：积分、任务去重和模拟权益。
- `tanji_knowledge_v1`：科普收藏与管理员文档。
- `tanji_local_session_v1`：最近登录会话。

这些 Preferences 只有在首次完成相应操作后才会创建；未保存过记录时不存在 `tanji_diary_records_v2` 是正常现象。

## 构建

在 DevEco Studio 打开工程，或使用命令行：

```bash
DEVECO_SDK_HOME="$HOME/.local/opt/deveco-26.0.0.851/command-line-tools/sdk" \
  "$HOME/.local/opt/deveco-26.0.0.851/command-line-tools/bin/hvigorw" \
  --mode module -p product=default assembleHap --no-daemon
```

签名包输出在 `entry/build/default/outputs/default/entry-default-signed.hap`。安装新包后再做一次“记一笔 → 强制停止 → 冷启动”的持久化验证。
