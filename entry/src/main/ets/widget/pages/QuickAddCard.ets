/**
 * 桌面服务卡片（1x2）：记录今日快捷入口
 * 横条布局：左侧"碳"字徽标与引导文案，右侧"+"圆钮；
 * 无数据绑定，点击整卡通过 postCardAction router 拉起主应用，
 * quickAdd 参数由 EntryAbility 解析后直达新建日记的行为选择页
 */

/** 卡片数据挂载点：本卡片无动态数据，仅保留挂载结构；命名区分 CarbonCard 的 storage 避免合并作用域冲突 */
let quickCardStorage = new LocalStorage();

/** 记录今日快捷卡片页 */
@Entry(quickCardStorage)
@Component
struct QuickAddCard {
  build() {
    Row({ space: 8 }) {
      // 左侧品牌徽标：与 2x2 卡片同款的圆形"碳"字
      Stack({ alignContent: Alignment.Center }) {
        Text('碳')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .backgroundColor('#4C9576')

      // 中部文案：主标题 + 副说明，占据剩余宽度
      Column({ space: 2 }) {
        Text('记录今日')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#126046')
          .maxLines(1)
        Text('一键添加低碳日记')
          .fontSize(10)
          .fontColor('#718078')
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧"+"圆钮：与主应用按钮同色的视觉锚点
      Stack({ alignContent: Alignment.Center }) {
        Text('+')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor('#4C9576')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor('#F7F8F2')
    .onClick(() => {
      // quickAdd 参数由 EntryAbility 写入 AppStorage，Index 页消费后直达行为选择页
      postCardAction(this, {
        'action': 'router',
        'bundleName': 'com.example.tanzuji',
        'abilityName': 'EntryAbility',
        'params': { 'quickAdd': true }
      });
    })
  }
}
