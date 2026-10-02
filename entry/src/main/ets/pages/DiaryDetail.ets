/**
 * 已保存日记详情页。
 * 视觉参考 HarmonyOS 日记页面：奶油白底、森林绿线性图标、宽松正文和底部悬浮编辑按钮。
 */
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BehaviorOption } from './BehaviorPicker';
import { RecordDraft } from './RecordDetail';
import { CARBON_FACTOR_CATALOG_SOURCE } from '../services/CarbonFactorService';

/**
 * 判断当前设备是否具备液态玻璃（沉浸式系统材质）能力
 * 需同时满足：系统软件 API 不低于 26 且设备声明支持沉浸式材质；
 * 短路求值保证低版本系统不会调用 isImmersiveMaterialSupported。
 * @returns true 表示可以使用 ImmersiveMaterial 液态玻璃
 */
function isGlassCapable(): boolean {
  return deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported();
}

/** 预览兜底行为：独立预览或父组件未传入草稿时，以"骑行"展示完整详情 */
class PreviewDiaryBehavior implements BehaviorOption {
  id: string = 'bike';
  name: string = '骑行';
  icon: Resource = $r('app.media.diary_bike');
}

/** 预览兜底草稿：携带完整示例日记（骑行 2.4 公里 + 长文正文） */
class PreviewDiaryDraft implements RecordDraft {
  behavior: BehaviorOption = new PreviewDiaryBehavior();
  amount: number = 2.4;
  unit: string = '公里';
  reductionKg: number = 0.42;
  note: string = '今天骑行去了图书馆，路上的风很舒服。比起开车，骑行让我更慢地观察校园，也让我发现低碳生活其实可以很自然。\n\n在图书馆待了两个多小时，读完了一本一直想看的书。安静的环境让我更专注，也感受到知识带来的踏实。\n\n回来的路上，夕阳透过树叶洒在路面上，整条路都显得很温柔。这样的出行方式，不仅让自己心情更好，也让城市多了一点清新的空气。';
  hasPhoto: boolean = true;
  evidenceSource: 'location' | 'health' | 'manual' = 'health';
  verificationStatus: 'verified' | 'pending' = 'verified';
  evidenceId: string = 'preview-health-001';
  scoreEnabled: boolean = true;
}

/**
 * 日记详情组件
 * 页面结构：顶部操作栏（返回/分享/删除） + 日期块 + 日记正文（含元信息）+ 底部悬浮编辑按钮。
 * 页面事件通过 onBack/onEdit/onDelete 回调交给入口管理。
 */
@Component
export struct DiaryDetail {
  /** 当前展示的日记草稿：由入口页传入；未传入时使用预览兜底草稿 */
  draft: RecordDraft = new PreviewDiaryDraft();
  /** 返回日记首页回调 */
  onBack?: () => void;
  /** 编辑当前日记回调：由入口页切换到记录详情页并带入原草稿 */
  onEdit?: () => void;
  /** 删除当前日记回调：由入口页从已保存列表中移除并返回首页 */
  onDelete?: () => void;

  /** 底部悬浮编辑按钮的液态玻璃材质：薄样式 + 淡绿赋色 + 交互形变与按压光晕；不具备能力时为 undefined */
  private editMaterial: uiMaterial.Material | undefined = isGlassCapable()
    ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#664C8A68',
      interactive: true,
      lightEffect: { color: undefined }
    })
    : undefined;

  /**
   * 日记正文内容
   * 备注为空时降级为"完成 数量+单位"的默认文案
   * @returns 正文文本
   */
  private content(): string {
    const note: string = this.draft.note.trim();
    if (note.length > 0) {
      return note;
    }
    return `完成 ${this.draft.amount}${this.draft.unit}，继续保持低碳生活。`;
  }

  /**
   * 正文字数统计
   * 去除换行符后按字符长度计算，展示在正文下方的元信息区
   * @returns 正文字数
   */
  private wordCount(): number {
    return this.content().replace(/\n/g, '').length;
  }

  /**
   * 日期块中的"月份 · 周几"文案
   * 以当前系统时间生成（如 '09月 · 周日'）
   * @returns 月份与星期文案
   */
  private monthWeek(): string {
    const date: Date = new Date(this.draft.recordedAt ?? this.draft.createdAt ?? Date.now());
    const weekNames: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return `${(date.getMonth() + 1).toString().padStart(2, '0')}月 · 周${weekNames[date.getDay()]}`;
  }

  /**
   * 日期块中的两位日期数字
   * @returns 如 '28'
   */
  private day(): string {
    return new Date(this.draft.recordedAt ?? this.draft.createdAt ?? Date.now()).getDate().toString().padStart(2, '0');
  }

  /**
   * 记录时间（时:分），不足两位补零
   * @returns 如 '17:40'
   */
  private time(): string {
    const date: Date = new Date(this.draft.recordedAt ?? this.draft.createdAt ?? Date.now());
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  /**
   * 核验状态文案
   * 已核验记录按证据来源显示"华为运动已核验/系统轨迹已核验"；待核实记录显示不计入提示
   * @returns 核验状态文案
   */
  private verificationLabel(): string {
    if (this.draft.verificationStatus === 'verified') {
      return this.draft.evidenceSource === 'health' ? '华为运动已核验' : '系统轨迹已核验';
    }
    return '待核实，不计入正式减排';
  }

  /**
   * 数量来源说明文案
   * 按证据来源显示华为运动、系统定位或手动填写的对应说明
   * @returns 数量来源说明文案
   */
  private evidenceText(): string {
    if (this.draft.evidenceSource === 'health') {
      return '数量来源：华为运动授权数据（步数换算，估算）';
    }
    if (this.draft.evidenceSource === 'location') {
      return '数量来源：系统定位轨迹（已过滤异常点）';
    }
    return '数量来源：手动填写，待核实';
  }

  /** 通过 HarmonyOS 系统分享面板分享当前日记文字。 */
  private async share(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.text',
        content: `${this.monthWeek()} ${this.time()}\n${this.content()}\n减排量：${this.draft.reductionKg.toFixed(3)} kg CO₂e`,
        title: '碳记日记',
        label: 'TEXT'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(context, {});
    } catch (err) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开系统分享面板', duration: 1600 });
      } catch (toastError) {
        // 分享失败不影响日记阅读。
      }
    }
  }

  /**
   * 顶部操作栏
   * 左侧返回按钮 + 右侧分享与删除按钮，透明底只显示图标
   */
  @Builder
  private Header() {
    Row() {
      // 返回按钮：点击触发 onBack 回调回到日记首页
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Text('‹')
          .fontSize(42)
          .fontColor('#15553F')
      }
      .width(48)
      .height(48)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回日记首页')
      .onClick(() => this.onBack?.())

      // 弹性占位：将操作按钮推至行尾
      Blank()

      // 右侧操作组：分享与删除
      Row({ space: 20 }) {
        // 分享按钮：调用 HarmonyOS 系统分享面板
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Image($r('app.media.diary_share'))
            .syncLoad(true)
            .width(30)
            .height(30)
        }
        .width(40)
        .height(48)
        .padding(5)
        .backgroundColor(Color.Transparent)
        .accessibilityText('分享日记')
        .onClick(() => this.share())

        // 删除按钮：触发 onDelete 回调，由入口页移除该日记
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Image($r('app.media.diary_trash'))
            .syncLoad(true)
            .width(30)
            .height(30)
        }
        .width(40)
        .height(48)
        .padding(5)
        .backgroundColor(Color.Transparent)
        .accessibilityText('删除日记')
        .onClick(() => this.onDelete?.())
      }
    }
    .width('100%')
    .height(66)
    .padding({ left: 24, right: 24 })
  }

  /**
   * 日期块：大号日期数字 + 右侧"月份 · 周几"与记录时间
   * 模拟实体日记页首的日期栏样式
   */
  @Builder
  private DateBlock() {
    Row({ space: 18 }) {
      // 大号日期数字
      Text(this.day())
        .fontSize(48)
        .fontWeight(FontWeight.Normal)
        .fontColor('#15553F')
      // 右侧：月份星期与记录时间，左对齐排列
      Column({ space: 3 }) {
        Text(this.monthWeek())
          .fontSize(19)
          .fontColor('#587167')
        Text(this.time())
          .fontSize(17)
          .fontColor('#587167')
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, top: 26, bottom: 22 })
  }

  /**
   * 日记正文区：宽松行距的正文 + 底部元信息（本机记录/字数/核验状态）
   */
  @Builder
  private DiaryBody() {
    Column({ space: 28 }) {
      // 正文：20 号字、34 行距，保持日记阅读的呼吸感
      Text(this.content())
        .width('100%')
        .fontSize(20)
        .fontColor('#174E3A')
        .lineHeight(34)
        .textAlign(TextAlign.Start)

      if (this.draft.photoUri !== undefined && this.draft.photoUri.length > 0) {
        Image(this.draft.photoUri)
          .width('100%')
          .height(220)
          .objectFit(ImageFit.Cover)
          .borderRadius(14)
          .accessibilityText('日记配图')
      }

      // 元信息区：记录位置、字数与核验状态三行
      Column({ space: 16 }) {
        // 记录于本机
        Row({ space: 14 }) {
          Image($r('app.media.diary_device'))
            .syncLoad(true)
            .width(25)
            .height(25)
          Text('记录于本机')
            .fontSize(16)
            .fontColor('#7A9489')
        }
        // 字数统计
        Row({ space: 14 }) {
          Image($r('app.media.diary_text'))
            .syncLoad(true)
            .width(25)
            .height(25)
          Text(`${this.wordCount()} 字`)
            .fontSize(16)
            .fontColor('#7A9489')
        }
        // 核验状态：已核验绿色、待核实黄棕色
        Row({ space: 14 }) {
          Image($r('app.media.diary_leaf'))
            .syncLoad(true)
            .width(25)
            .height(25)
          Text(this.verificationLabel())
            .fontSize(16)
            .fontColor(this.draft.verificationStatus === 'verified' ? '#5D806C' : '#9A8060')
        }
        Row({ space: 14 }) {
          Image($r('app.media.diary_leaf'))
            .syncLoad(true)
            .width(25)
            .height(25)
          Text(`减排量：${this.draft.reductionKg.toFixed(3)} kg CO₂e · ${this.draft.amount}${this.draft.unit}`)
            .fontSize(16)
            .fontColor('#5D806C')
        }
        Text(this.evidenceText())
          .fontSize(13)
          .fontColor('#7A9489')
          .width('100%')
        Text(`核算依据：${CARBON_FACTOR_CATALOG_SOURCE}`)
          .fontSize(11)
          .fontColor('#9AA8A1')
          .width('100%')
          .maxLines(3)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 26, right: 26, top: 25, bottom: 30 })
  }

  /**
   * 底部悬浮编辑按钮
   * 圆形玻璃按钮（磨砂兜底 + 液态玻璃升级），点击触发 onEdit 进入编辑
   */
  @Builder
  private EditButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      Image($r('app.media.diary_pen'))
        .syncLoad(true)
        .width(34)
        .height(34)
    }
    .width(66)
    .height(66)
    .padding(16)
    // 磨砂兜底层：半透明中绿底色 + 材质模糊 + 细高光描边 + 柔和阴影
    .backgroundColor('#B34C8A68')
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: '#59FFFFFF' })
    .shadow({ radius: 18, color: '#2943694A', offsetX: 0, offsetY: 6 })
    // 液态玻璃层：具备能力的设备上接管背景/描边/阴影，并提供按压光晕
    .systemMaterial(this.editMaterial)
    .accessibilityText('编辑日记')
    .onClick(() => this.onEdit?.())
  }

  /**
   * 页面布局
   * Stack 底部对齐：底层为可滚动的日记内容（顶栏 → 日期块 → 分隔线 → 正文），
   * 上层为悬浮编辑按钮
   */
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底层：可滚动内容区
      Column() {
        Scroll() {
          Column() {
            this.Header()
            this.DateBlock()
            // 分隔线：日期块与正文之间的纸面分割
            Divider()
              .color('#DDE8DE')
              .strokeWidth(1)
              .margin({ left: 24, right: 24 })
            this.DiaryBody()
          }
          .width('100%')
          .constraintSize({ maxWidth: 760, minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor('#F7F8F2')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)

      // 上层：悬浮编辑按钮容器
      Column() {
        this.EditButton()
      }
      .width('100%')
      // 与首页加号相同的悬浮高度：底部保留首页导航条占用的安全空间。
      .padding({ bottom: 90 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8F2')
  }
}

/**
 * 日记详情页 Previewer 预览壳组件
 * 仅用于 DevEco Studio 预览器中展示 DiaryDetail 组件，不参与实际页面路由
 */
@Preview({
  title: 'DiaryDetail', deviceType: 'phone', width: 1080, height: 2400,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct DiaryDetailPreview {
  /** 预览用示例草稿 */
  private previewDraft: RecordDraft = new PreviewDiaryDraft();
  build() {
    // 以预览草稿渲染日记详情
    DiaryDetail({ draft: this.previewDraft })
  }
}
