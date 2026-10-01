/**
 * 新建低碳日记 · 第一步：选择低碳行为
 * 从日记首页点击"加号"进入，提供搜索过滤与网格点选两类交互；
 * 选定行为后通过 onNext 回调交给父组件（Index）驱动后续流程，
 * 下一步的详情录入页面尚未接入，当前选择完成后直接返回首页。
 */

/**
 * 低碳行为选项的数据结构
 * 描述一种可记录的低碳行为（如步行、光盘行动等）
 */
export interface BehaviorOption {
  /** 行为唯一标识：作为 ForEach 的键，同时用于选中态判断 */
  id: string;
  /** 行为名称：显示在选项卡片下方，并作为搜索匹配的关键字 */
  name: string;
  /** 行为图标资源：显示在选项卡片圆形底托中央 */
  icon: Resource;
}

/**
 * 可选低碳行为清单（静态数据）
 * 覆盖出行、节能节水、饮食回收、绿色消费四类行为；
 * 接入真实数据源后可整体替换为服务端下发或本地配置
 */
const BEHAVIOR_OPTIONS: BehaviorOption[] = [
  // 出行类：步行 / 骑行 / 公共交通
  { id: 'walk', name: '步行', icon: $r('app.media.diary_walk') },
  { id: 'bike', name: '骑行', icon: $r('app.media.diary_bike') },
  { id: 'transit', name: '公共交通', icon: $r('app.media.diary_transit') },
  { id: 'carpool', name: '拼车出行', icon: $r('app.media.diary_transit') },
  { id: 'metro', name: '地铁出行', icon: $r('app.media.diary_transit') },
  // 节能节水类：节约用电 / 节约用水
  { id: 'electricity', name: '节约用电', icon: $r('app.media.diary_electricity') },
  { id: 'water', name: '节约用水', icon: $r('app.media.diary_water') },
  { id: 'standby', name: '关闭待机', icon: $r('app.media.diary_electricity') },
  { id: 'shower', name: '缩短淋浴', icon: $r('app.media.diary_water') },
  // 减少浪费类：光盘行动 / 垃圾回收 / 旧物再利用 / 减少一次性用品
  { id: 'meal', name: '光盘行动', icon: $r('app.media.diary_meal') },
  { id: 'lowCarbonMeal', name: '低碳餐食', icon: $r('app.media.diary_meal') },
  { id: 'recycle', name: '垃圾回收', icon: $r('app.media.diary_recycle') },
  { id: 'paperRecycle', name: '纸张回收', icon: $r('app.media.diary_recycle') },
  { id: 'clothesRecycle', name: '旧衣回收', icon: $r('app.media.diary_recycle') },
  { id: 'reuse', name: '旧物再利用', icon: $r('app.media.diary_reuse') },
  { id: 'disposable', name: '减少一次性用品', icon: $r('app.media.diary_disposable') },
  // 绿色消费类：绿色购物
  { id: 'shopping', name: '绿色购物', icon: $r('app.media.diary_shopping') },
  { id: 'reusable', name: '自带水杯', icon: $r('app.media.diary_reuse') },
  { id: 'secondhand', name: '二手交易', icon: $r('app.media.diary_reuse') }
];

/**
 * 选择低碳行为页组件
 * 页面结构：顶部操作栏（返回 / 搜索框 / 下一步） + 标题区 + 行为网格列表。
 * 页面事件通过回调交给入口管理；未选择行为时"下一步"按钮置灰不可点击。
 */
@Component
export struct BehaviorPicker {
  /** 返回上一页回调：由父组件注入，未注入时点击返回按钮不产生效果 */
  onBack?: () => void;
  /** 进入下一步回调：参数为当前选中的行为选项，由父组件决定后续流程 */
  onNext?: (behavior: BehaviorOption) => void;

  /** 搜索框内容：作为行为名称过滤的关键字 */
  @State private searchText: string = '';
  /** 当前已选行为的 id：空字符串表示尚未选择任何行为 */
  @State private selectedId: string = '';
  /** 宽屏布局标记：仅平板/横向大窗口使用紧凑顶部操作栏，手机保持原布局。 */
  @State private wideLayout: boolean = false;

  aboutToAppear(): void {
    this.wideLayout = this.getUIContext().getMediaQuery()
      .matchMediaSync('(width >= 600vp)').matches;
  }

  /**
   * 获取过滤后的行为选项列表
   * 依据搜索关键字对全量行为做名称包含匹配；
   * 关键字为空（或仅空白）时返回全量列表。
   * 由于内部读取 @State searchText，关键字变化会触发列表刷新
   * @returns 与搜索关键字匹配的行为选项数组
   */
  private filteredOptions(): BehaviorOption[] {
    // 去除关键字首尾空白，避免误过滤
    const keyword: string = this.searchText.trim().toLowerCase().replace(/\s/g, '');
    // 关键字为空：返回全量选项
    if (keyword.length === 0) {
      return BEHAVIOR_OPTIONS;
    }
    // 按名称包含关键字过滤
    return BEHAVIOR_OPTIONS.filter((item: BehaviorOption) => {
      const searchable: string = `${item.name}${item.id}`.toLowerCase();
      return searchable.includes(keyword);
    });
  }

  /**
   * 选中指定行为
   * @param id 行为唯一标识
   */
  private selectBehavior(id: string): void {
    this.selectedId = id;
  }

  /**
   * 判断指定行为是否为当前选中项
   * @param id 行为唯一标识
   * @returns true 表示已选中（影响卡片底色与边框高亮）
   */
  private isSelected(id: string): boolean {
    return this.selectedId === id;
  }

  /** 返回上一页：执行父组件注入的 onBack 回调 */
  private goBack(): void {
    this.onBack?.();
  }

  /**
   * 进入下一步
   * 未选择行为时直接返回；已选择时依据 id 查找完整选项并交给 onNext 回调
   */
  private goNext(): void {
    // 未选择行为时不允许进入下一步（按钮本身已禁用，此处为双保险）
    if (this.selectedId.length === 0) {
      return;
    }
    // 依据选中 id 查找完整的选项数据
    const selected: BehaviorOption | undefined = BEHAVIOR_OPTIONS.find(
      (item: BehaviorOption) => item.id === this.selectedId
    );
    if (selected !== undefined) {
      this.onNext?.(selected);
    }
  }

  /**
   * 顶部操作栏
   * 一行布局：左侧返回按钮 + 中部搜索框 + 右侧"下一步"按钮
   */
  @Builder
  private Header() {
    Row({ space: 8 }) {
      // 返回按钮：透明背景，仅显示左箭头字符
      Button({ type: ButtonType.Normal }) {
        Text('‹')
          .fontSize(42)
          .fontColor('#174E3A')
          .fontWeight(FontWeight.Normal)
      }
      .width(44)
      .height(48)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回日记首页')
      .onClick(() => this.goBack())

      // 中部搜索框：搜索图标 + 行为名称输入框
      Row({ space: 8 }) {
        Image($r('app.media.diary_search'))
          .syncLoad(true)
          .width(25)
          .height(25)
        TextInput({ placeholder: '搜索低碳行为', text: this.searchText })
          .layoutWeight(1)
          .height(48)
          .fontSize(17)
          .fontColor('#45695A')
          .placeholderColor('#718078')
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onChange((value: string) => {
            this.searchText = value;
          })
      }
      // 搜索框始终占据返回键与“下一步”之间的剩余空间，保证手机上下一步按钮完整可点击。
      // 之前固定 60% 宽度会和两侧操作按钮一起超出 Row 的可用宽度。
      .width(0)
      .layoutWeight(1)
      .constraintSize({ minWidth: 0, maxWidth: 1100 })
      .height(48)
      .padding({ left: 18, right: 16 })
      .backgroundColor('#EAF2E8')
      .borderRadius(25)

      // "下一步"按钮：未选择行为时置灰并禁用，选中后点亮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          Text('下一步')
            .fontSize(16)
            .fontColor(this.selectedId.length > 0 ? '#174E3A' : '#AAB2AC')
          Text('›')
            .fontSize(29)
            .fontColor(this.selectedId.length > 0 ? '#174E3A' : '#B8BFBA')
        }
      }
      .width(96)
      .height(48)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.selectedId.length > 0)
      .accessibilityText(this.selectedId.length > 0 ? '下一步' : '请先选择低碳行为')
      .onClick(() => this.goNext())
    }
    .width('100%')
    .height(74)
    .padding({ left: 18, right: 18 })
  }

  /**
   * 单个行为选项卡片
   * "圆形图标底托 + 行为名称"的可点击卡片，选中态通过底色与边框高亮区分
   * @param item 行为选项数据
   */
  @Builder
  private BehaviorTile(item: BehaviorOption) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        // 圆形底托与居中图标的叠层
        Stack({ alignContent: Alignment.Center }) {
          // 底托：选中态为深一档的浅绿
          Row()
            .width(70)
            .height(70)
            .borderRadius(35)
            .backgroundColor(this.isSelected(item.id) ? '#D2E7D7' : '#EAF2E8')
          // 行为图标：骑行图标比例特殊，单独调整内边距以保证视觉大小一致
          Image(item.icon)
            .syncLoad(true)
            .width(48)
            .height(48)
            .padding(item.id === 'bike' ? 1 : 3)
        }
        // 行为名称：超长时单行省略
        Text(item.name)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#164C39')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(132)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(132)
    .padding(0)
    // 卡片底色与边框：选中态绿色描边高亮
    .backgroundColor(this.isSelected(item.id) ? '#F0F7EE' : '#FAFBF6')
    .border({ width: this.isSelected(item.id) ? 2 : 1, color: this.isSelected(item.id) ? '#3E8062' : '#E1E9DF' })
    .borderRadius(14)
    .accessibilityText(this.isSelected(item.id) ? `${item.name}，已选择` : item.name)
    .onClick(() => this.selectBehavior(item.id))
  }

  /**
   * 页面布局
   * 垂直结构：顶部操作栏 → 标题区（主/副标题） → 可滚动的两列行为网格
   */
  build() {
    Column() {
      // 顶部操作栏：返回 / 搜索 / 下一步
      this.Header()

      // 标题区：主标题与引导副标题
      Column({ space: 7 }) {
        Text('选择低碳行为')
          .fontSize(29)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
          .alignSelf(ItemAlign.Start)
        Text('选择你刚刚完成的低碳行为')
          .fontSize(18)
          .fontColor('#718078')
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 24, bottom: 24 })

      // 可滚动的行为网格：两列排布，随搜索关键字实时刷新
      Scroll() {
        Grid() {
          // 使用稳定的行为 id 作为键，保证搜索过滤后列表 diff 的稳定性
          ForEach(this.filteredOptions(), (item: BehaviorOption) => {
            GridItem() {
              this.BehaviorTile(item)
            }
          }, (item: BehaviorOption) => item.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      // 到达边缘后可回弹（弹簧效果）
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
  }
}

/**
 * 选择行为页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 BehaviorPicker 组件，不参与实际页面路由
 */
@Preview({
  title: 'BehaviorPicker',    // 预览标题
  deviceType: 'phone',        // 设备类型：手机
  width: 1260,                // 预览宽度（px）
  height: 2800,               // 预览高度（px）
  colorMode: 'light',         // 浅色模式
  dpi: 480,                   // 屏幕像素密度
  locale: 'zh_CN',            // 简体中文语言环境
  orientation: 'portrait',    // 竖屏方向
  roundScreen: false          // 非圆屏设备
})
@Component
struct BehaviorPickerPreview {
  build() {
    // 直接渲染选择行为页组件
    BehaviorPicker()
  }
}
