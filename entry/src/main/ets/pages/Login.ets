/**
 * 碳记登录 / 注册页：与 Home 共用奶油白、森林绿视觉风格
 * 单卡片承载登录与注册两种模式，通过"立即注册/返回登录"链接切换；
 * 真机使用本机持久化账号服务（AuthService），预览入口注入内存模拟服务（PreviewAuthService），
 * 页面绘制不依赖设备 API。
 */
import { AuthService, LoginResult } from '../services/AuthService';
import { PreviewAuthService } from '../services/PreviewAuthService';

/**
 * 登录页组件
 * 通过注入的认证服务完成账号注册与登录校验，并以 feedback 状态展示结果反馈
 */
@Component
export struct Login {
  /** 登录成功回调：由父组件（Index）注入，用于将页面切换到日记首页 */
  onLoginSuccess?: (userId?: string) => void;
  /** 认证服务实例：默认为持久化实现，预览壳组件注入内存模拟实现 */
  authService: AuthService = new AuthService();
  /** 预览模式标记：true 时不读取设备上下文、不写全局 AppStorage */
  previewMode: boolean = false;
  /** 当前是否处于注册模式：false 为登录模式 */
  @State private registering: boolean = false;
  /** 账号输入框内容 */
  @State private account: string = '';
  /** 密码输入框内容 */
  @State private password: string = '';
  /** 确认密码输入框内容（仅注册模式使用） */
  @State private confirmPassword: string = '';
  /** 是否明文显示密码 */
  @State private showPassword: boolean = false;
  /** 结果反馈文案（成功或失败的提示信息） */
  @State private feedback: string = '';
  /** 反馈是否为成功态：控制反馈文字颜色（绿/红） */
  @State private feedbackSuccess: boolean = false;
  /** 是否正在提交：用于防止重复提交并控制输入框与按钮的可用状态 */
  @State private isSubmitting: boolean = false;

  /**
   * 切换登录/注册模式
   * 切换时清空密码相关输入与历史反馈，避免敏感内容跨模式残留
   */
  private switchMode(): void {
    // 提交中不允许切换，防止状态错乱
    if (this.isSubmitting) {
      return;
    }
    // 翻转模式标记
    this.registering = !this.registering;
    // 清空密码、明文开关与历史反馈
    this.password = '';
    this.confirmPassword = '';
    this.showPassword = false;
    this.feedback = '';
  }

  /**
   * 提交登录或注册
   * 注册模式先校验两次密码一致，再调用认证服务；
   * 成功后按模式分流：注册成功切回登录页，登录成功写入全局用户信息并回调父组件
   */
  private async submit(): Promise<void> {
    // 正在提交时直接返回，防止重复触发
    if (this.isSubmitting) {
      return;
    }
    // 清空上一次反馈，进入新一轮提交
    this.feedback = '';
    this.feedbackSuccess = false;
    // 注册模式：两次密码不一致直接提示，不发起服务调用
    if (this.registering && this.password !== this.confirmPassword) {
      this.feedback = '两次输入的密码不一致';
      return;
    }
    this.isSubmitting = true;
    try {
      // 按模式调用注册或登录；真机传入宿主上下文供服务打开本机存储，预览传 undefined
      const result: LoginResult = this.registering
        ? await this.authService.register(this.account, this.password,
          this.previewMode ? undefined : this.getUIContext().getHostContext())
        : await this.authService.login(this.account, this.password,
          this.previewMode ? undefined : this.getUIContext().getHostContext());
      // 展示结果反馈
      this.feedback = result.message;
      this.feedbackSuccess = result.success;
      if (result.success && this.registering) {
        // 注册成功：切回登录模式并清空密码，引导用户直接登录
        this.registering = false;
        this.password = '';
        this.confirmPassword = '';
        this.showPassword = false;
      } else if (result.success && result.user !== undefined) {
        // 登录成功：真机写入全局用户信息供 Home 等页面读取（预览不污染全局状态）
        if (!this.previewMode) {
          AppStorage.setOrCreate<string>('loginUserId', result.user.userId);
          AppStorage.setOrCreate<string>('loginDisplayName', result.user.displayName);
        }
        // 清空密码后回调父组件切换页面
        this.password = '';
        this.onLoginSuccess?.(result.user.userId);
      }
    } catch (error) {
      // 存储/加密等系统调用异常：统一转化为友好提示
      this.feedback = '暂时无法读取或保存本机账号，请稍后重试';
      this.feedbackSuccess = false;
    } finally {
      // 无论成败都恢复可提交状态
      this.isSubmitting = false;
    }
  }

  /**
   * 账号输入域
   * 字段标题 + 账号输入框；注册模式展示格式要求占位文案
   */
  @Builder
  private AccountField() {
    Column({ space: 8 }) {
      // 字段标题
      Text('账号')
        .fontSize(14)
        .fontColor('#45695A')
      // 账号输入框：内容变化时同步状态并清除历史反馈；提交中禁用
      TextInput({ placeholder: this.registering ? '4–20 位字母、数字或下划线' : '请输入账号', text: this.account })
        .width('100%')
        .height(50)
        .type(InputType.Normal)
        .fontSize(15)
        .fontColor('#164C39')
        .placeholderColor('#78877D')
        .caretColor('#174E3A')
        .backgroundColor('#EAF2E8')
        .borderRadius(14)
        .padding({ left: 16, right: 16 })
        .maxLength(20)
        .enabled(!this.isSubmitting)
        .onChange((value: string) => {
          this.account = value;
          this.feedback = '';
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 密码输入域
   * 字段标题 + 密码输入框；非确认框时附带明文/密文切换按钮
   * @param confirm 是否为"确认密码"输入框（仅注册模式渲染）
   */
  @Builder
  private PasswordField(confirm: boolean) {
    Column({ space: 8 }) {
      // 字段标题：按是否为确认框切换文案
      Text(confirm ? '确认密码' : '密码')
        .fontSize(14)
        .fontColor('#45695A')
      Row() {
        // 密码输入框：按明文开关切换输入类型；内容变化时同步状态并清除历史反馈
        TextInput({
          placeholder: confirm ? '再次输入密码' : (this.registering ? '8–64 位，包含字母和数字' : '请输入密码'),
          text: confirm ? this.confirmPassword : this.password
        })
          .layoutWeight(1)
          .height(50)
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          // 使用明确配色的切换按钮，避免系统眼睛图标在深色模式下变白。
          .showPasswordIcon(false)
          .fontSize(15)
          .fontColor('#164C39')
          .placeholderColor('#78877D')
          .caretColor('#174E3A')
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 4 })
          .maxLength(64)
          .enabled(!this.isSubmitting)
          .onChange((value: string) => {
            if (confirm) {
              this.confirmPassword = value;
            } else {
              this.password = value;
            }
            this.feedback = '';
          })
        // 明文切换按钮：仅主密码框显示
        if (!confirm) {
          Button({ type: ButtonType.Normal }) {
            Image(this.showPassword ? $r('app.media.auth_eye_open') : $r('app.media.auth_eye_closed'))
              .syncLoad(true)
              .width(22)
              .height(22)
              .objectFit(ImageFit.Contain)
          }
            .width(52)
            .height(48)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .enabled(!this.isSubmitting)
            .accessibilityText(this.showPassword ? '隐藏密码' : '显示密码')
            .onClick(() => { this.showPassword = !this.showPassword; })
        }
      }
      .width('100%')
      .backgroundColor('#EAF2E8')
      .borderRadius(14)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 页面布局
   * 外层滚动容器（小屏键盘弹出时可滚动） + 居中内容列：
   * 品牌区（图标/名称/标语） + 登录卡片（标题、输入域、反馈、提交按钮、模式切换链接） + 本机存储提示
   */
  build() {
    Scroll() {
      Column() {
        // 品牌区：叶片图标
        Image($r('app.media.diary_leaf'))
          .syncLoad(true)
          .width(36)
          .height(36)
          .margin({ bottom: 12 })
        // 应用名称
        Text('碳记')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#123F2E')
        // 应用标语
        Text('记录每一次低碳选择')
          .fontSize(15)
          .fontColor('#718078')
          .margin({ top: 8, bottom: 28 })

        // 登录卡片
        Column({ space: 18 }) {
          // 卡片标题区：按模式显示"欢迎回来/开启绿色日记"，注册模式附引导副标题
          Column({ space: 8 }) {
            Text(this.registering ? '开启绿色日记' : '欢迎回来')
              .width('100%')
              .textAlign(TextAlign.Center)
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor('#123F2E')
            if (this.registering) {
              Text('从今天起，留下你的绿色足迹')
                .width('100%')
                .textAlign(TextAlign.Center)
                .fontSize(13)
                .fontColor('#718078')
            }
          }
          .width('100%')
          .margin({ bottom: 6 })

          // 账号输入域
          this.AccountField()
          // 密码输入域
          this.PasswordField(false)
          // 注册模式：追加确认密码输入域
          if (this.registering) {
            this.PasswordField(true)
          }
          // 结果反馈：仅有内容时渲染，成功为绿色、失败为红色
          if (this.feedback.length > 0) {
            Text(this.feedback)
              .width('100%')
              .fontSize(13)
              .fontColor(this.feedbackSuccess ? '#357A55' : '#A43E36')
          }
          // 提交按钮：提交中禁用并显示"请稍候…"
          Button(this.isSubmitting ? '请稍候…' : (this.registering ? '注册' : '登录'), { type: ButtonType.Normal })
            .width('100%')
            .height(50)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor('#174E3A')
            .borderRadius(16)
            .enabled(!this.isSubmitting)
            .onClick(() => { this.submit(); })

          // 模式切换链接：登录 ↔ 注册
          Row({ space: 4 }) {
            Text(this.registering ? '已有账号？' : '还没有账号？')
              .fontSize(14)
              .fontColor('#718078')
            Button(this.registering ? '返回登录' : '立即注册', { type: ButtonType.Normal })
              .height(40)
              .padding({ left: 6, right: 6 })
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#174E3A')
              .backgroundColor(Color.Transparent)
              .enabled(!this.isSubmitting)
              .onClick(() => this.switchMode())
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FAFBF6')
        .border({ width: 1, color: '#E1E9DF' })
        .borderRadius(22)

        // 真机提示文案：账号仅保存在本机（预览模式不显示）
      }
      .width('100%')
      // 限制内容最大宽度，宽屏/平板上保持卡片可读性
      .constraintSize({ maxWidth: 440 })
      .padding({ left: 24, right: 24, top: 36, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Center)
    .scrollBar(BarState.Off)
    .backgroundColor('#F7F8F2')
  }
}

/**
 * 登录页 Previewer 预览壳组件（浅色）
 * 注入内存模拟认证服务，预览器中可直接体验注册/登录全流程
 */
@Preview({
  title: 'Login', deviceType: 'phone', width: 1260, height: 2800,
  colorMode: 'light', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct LoginPreview {
  /** 预览专用内存认证服务 */
  private previewAuth: AuthService = new PreviewAuthService();
  build() {
    // 以预览模式渲染登录页
    Login({ authService: this.previewAuth, previewMode: true })
  }
}

/** 深色系统配置下也要保持明确的输入框颜色，便于预览检查真机同类问题。 */
@Preview({
  title: 'LoginDarkSystem', deviceType: 'phone', width: 1260, height: 2800,
  colorMode: 'dark', dpi: 480, locale: 'zh_CN', orientation: 'portrait', roundScreen: false
})
@Component
struct LoginDarkPreview {
  /** 预览专用内存认证服务 */
  private previewAuth: AuthService = new PreviewAuthService();
  build() {
    // 以预览模式渲染登录页（深色系统配置）
    Login({ authService: this.previewAuth, previewMode: true })
  }
}
