/**
 * 预览专用认证服务（仅由 @Preview 入口注入）
 * 用内存 Map 模拟账号注册与登录，不调用预览器不支持的存储和密码学能力；
 * 预览器销毁后数据即消失，真机始终使用基类 AuthService 的持久化实现。
 */
import { common } from '@kit.AbilityKit';
import { AuthService, LoginResult } from './AuthService';

/** 预览用认证服务：继承 AuthService 并以内存实现替换持久化与加密逻辑 */
export class PreviewAuthService extends AuthService {
  /** 内存账号表：账号 → 明文密码（仅预览演示使用，不落盘） */
  private accounts: Map<string, string> = new Map<string, string>();

  /**
   * 注册（内存模拟）
   * 复用基类规则校验，通过后写入内存表即算注册成功
   * @param account 用户输入的账号
   * @param password 用户输入的密码
   * @param _context 预览场景不使用上下文
   * @returns 注册结果
   */
  public async register(account: string, password: string, _context?: common.Context): Promise<LoginResult> {
    const normalized: string = account.trim();
    // 复用基类的账号/密码规则校验，保证预览提示与真机一致
    const validation: string = AuthService.validateRegistration(normalized, password);
    if (validation.length > 0) {
      return { success: false, message: validation };
    }
    // 账号已存在时不允许重复注册
    if (this.accounts.has(normalized)) {
      return { success: false, message: '该账号已被使用，请换一个账号' };
    }
    // 写入内存表（明文保存，仅预览演示）
    this.accounts.set(normalized, password);
    return { success: true, message: '注册成功，请登录' };
  }

  /**
   * 登录（内存模拟）
   * 支持演示账号 admin/123456 与内存注册账号，比对通过即登录
   * @param account 用户输入的账号
   * @param password 用户输入的密码
   * @param _context 预览场景不使用上下文
   * @returns 登录结果：成功时携带带 preview 前缀的用户信息
   */
  public async login(account: string, password: string, _context?: common.Context): Promise<LoginResult> {
    const normalized: string = account.trim();
    // 空输入直接提示
    if (normalized.length === 0 || password.length === 0) {
      return { success: false, message: '请输入账号和密码' };
    }
    // 演示账号或内存注册账号比对通过：返回预览用户信息
    if ((normalized === 'admin' && password === '123456') ||
      this.accounts.get(normalized) === password) {
      return { success: true, message: '登录成功',
        user: { userId: `preview-${normalized}`, displayName: normalized } };
    }
    return { success: false, message: '账号或密码不正确' };
  }
}
