/**
 * 桌面服务卡片（2x2）：碳记今日减排速览
 * 数据由 EntryFormAbility 通过 formBindingData 注入，LocalStorage 属性名与数据键一一对应；
 * 点击整卡通过 postCardAction router 直达主应用（未启动时由系统冷启动拉起）
 */

/** 卡片数据挂载点：与 EntryFormAbility 返回的绑定数据同源 */
let storage = new LocalStorage();

/** 今日减排卡片页 */
@Entry(storage)
@Component
struct CarbonCard {
  /** 今日减排量（kg CO₂e，保留两位小数） */
  @LocalStorageProp('todayKg') todayKg: string = '0.00';
  /** 今日低碳记录次数 */
  @LocalStorageProp('todayCount') todayCount: string = '0';
  /** 近 7 天减排量（kg，保留一位小数） */
  @LocalStorageProp('weekKg') weekKg: string = '0.0';
  /** 近 7 天记录次数 */
  @LocalStorageProp('weekCount') weekCount: string = '0';
  /** 日期标签，例如"10月6日" */
  @LocalStorageProp('dateLabel') dateLabel: string = '';

  build() {
    Column() {
      // 顶部品牌行：圆形"碳"字徽标 + 应用名，右侧日期标签
      Row({ space: 6 }) {
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

        Text('碳记')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#126046')

        // 日期靠右收尾，占据剩余宽度
        Text(this.dateLabel)
          .fontSize(11)
          .fontColor('#718078')
          .maxLines(1)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 中部：今日减排大数字与次数说明，垂直居中占据主体
      Column({ space: 3 }) {
        Text(this.todayKg)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor('#126046')
          .maxLines(1)
        Text(`今日减排 ${this.todayCount} 次 · kg CO₂e`)
          .fontSize(11)
          .fontColor('#718078')
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      // 底部：近 7 天汇总条，浅绿底与主应用配色一致
      Row() {
        Text(`近7天 ${this.weekKg} kg · ${this.weekCount} 次`)
          .fontSize(11)
          .fontColor('#4C9576')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor('#EAF3E7')
      .borderRadius(10)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F7F8F2')
    .onClick(() => {
      // router 直达主应用入口；params 预留后续深链参数
      postCardAction(this, {
        'action': 'router',
        'bundleName': 'com.example.tanzuji',
        'abilityName': 'EntryAbility',
        'params': {}
      });
    })
  }
}
