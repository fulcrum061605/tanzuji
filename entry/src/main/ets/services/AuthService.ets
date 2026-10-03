/**
 * 本机账号服务
 * 基于 Preferences 持久化"盐 + PBKDF2 密码派生值"，不保存明文密码，不提供云端账号；
 * 提供注册规则校验、注册落盘与登录校验能力，由登录页（Login）调用。
 * 预览器场景请改用子类 PreviewAuthService（内存模拟实现）。
 */
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** 登录用户信息 */
export interface LoginUser {
  /** 用户唯一标识 */
  userId: string;
  /** 用户昵称（展示名称） */
  displayName: string;
}

/** 登录/注册结果 */
export interface LoginResult {
  /** 是否成功 */
  success: boolean;
  /** 提示消息（用于界面反馈展示） */
  message: string;
  /** 成功时返回的用户信息，失败时不存在 */
  user?: LoginUser;
}

/** 最近一次成功登录的本机会话，只保存用户标识和昵称，不保存密码。 */
interface StoredSession {
  userId: string;
  displayName: string;
}

/**
 * Preferences 中存储的账号结构（JSON 序列化后的形态）
 * 只包含盐与派生值，不包含明文密码
 */
interface StoredAccount {
  /** 存储结构版本号：用于后续结构升级时做兼容判断 */
  version: number;
  /** 账号名（去除首尾空白后的规范化形态） */
  account: string;
  /** 随机盐（16 字节，按字节数组存储以便 JSON 序列化） */
  salt: number[];
  /** PBKDF2 派生后的密码哈希（十六进制字符串） */
  passwordHash: string;
}

/** 认证服务类：本机持久化实现，管理本地账号的注册与登录校验 */
export class AuthService {
  /** PBKDF2 迭代次数：放大计算成本，提高暴力破解难度 */
  private static readonly ITERATIONS: number = 600000;
  private static readonly SESSION_STORE: string = 'tanji_local_session_v1';

  /**
   * 注册信息预校验（纯规则校验，不涉及存储）
   * @param account 用户输入的账号
   * @param password 用户输入的密码
   * @returns 校验结果文案；空字符串表示全部通过
   */
  public static validateRegistration(account: string, password: string): string {
    // 账号规则：4–20 位字母、数字或下划线
    if (!/^[A-Za-z0-9_]{4,20}$/.test(account.trim())) {
      return '账号需为 4–20 位字母、数字或下划线';
    }
    // 密码规则：8–64 位且同时包含字母和数字
    if (password.length < 8 || password.length > 64 ||
      !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
      return '密码需为 8–64 位，包含字母和数字';
    }
    // 演示账号名保留占用，禁止注册同名账号
    if (account.trim() === 'admin') {
      return '该账号已被使用，请换一个账号';
    }
    return '';
  }

  /**
   * 打开本机账号存储
   * @param context 应用上下文（真机由页面通过 getHostContext 传入）
   * @returns Preferences 存储实例
   * @throws 上下文不可用时抛出异常
   */
  private async openStore(context?: common.Context): Promise<preferences.Preferences> {
    if (context === undefined) {
      throw new Error('Application context unavailable');
    }
    // 打开（不存在则创建）本机账号偏好存储
    return preferences.getPreferences(context, { name: 'tanji_local_accounts_v1' });
  }

  /** 保存成功登录会话，供应用冷启动恢复登录态。 */
  public async rememberSession(context: common.Context | undefined, user: LoginUser): Promise<void> {
    if (context === undefined) {
      return;
    }
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: AuthService.SESSION_STORE });
    await store.put('current_user', JSON.stringify({ userId: user.userId, displayName: user.displayName } as StoredSession));
    await store.flush();
  }

  /** 读取最近一次登录会话；无会话或数据损坏时返回 undefined。 */
  public async restoreSession(context: common.Context | undefined): Promise<LoginUser | undefined> {
    try {
      if (context === undefined) {
        return undefined;
      }
      const store: preferences.Preferences = await preferences.getPreferences(context, { name: AuthService.SESSION_STORE });
      const value: preferences.ValueType = await store.get('current_user', '');
      if (typeof value !== 'string' || value.length === 0) {
        return undefined;
      }
      const session: StoredSession = JSON.parse(value) as StoredSession;
      return session.userId.length > 0 && session.displayName.length > 0 ? session : undefined;
    } catch (error) {
      return undefined;
    }
  }

  /**
   * 用 PBKDF2 派生密码哈希
   * @param password 明文密码
   * @param salt 随机盐
   * @returns 十六进制字符串形式的派生值
   */
  private async derivePassword(password: string, salt: Uint8Array): Promise<string> {
    // PBKDF2 参数：SHA256 摘要、固定迭代次数、输出 32 字节密钥
    const params: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2', password: password, salt: salt,
      iterations: AuthService.ITERATIONS, keySize: 32
    };
    const secret: cryptoFramework.DataBlob = await cryptoFramework.createKdf('PBKDF2|SHA256')
      .generateSecret(params);
    // 逐字节转为两位十六进制，拼接成定长字符串
    let hex: string = '';
    for (let i: number = 0; i < secret.data.length; i++) {
      hex += secret.data[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  /**
   * 登录校验
   * 依次尝试演示账号与本机注册账号；本机账号用存储盐重新派生后比对
   * @param account 用户输入的账号
   * @param password 用户输入的密码
   * @param context 应用上下文（用于打开本机存储）
   * @returns 登录结果：成功时携带用户信息
   */
  public async login(account: string, password: string, context?: common.Context): Promise<LoginResult> {
    const normalized: string = account.trim();
    // 空输入直接提示，不进入存储查询
    if (normalized.length === 0 || password.length === 0) {
      return { success: false, message: '请输入账号和密码' };
    }
    // 保留原演示账号，便于课堂演示；不代表远程身份认证。
    if (normalized === 'admin' && password === '123456') {
      const user: LoginUser = { userId: 'demo-user-001', displayName: '碳记用户' };
      await this.rememberSession(context, user);
      return { success: true, message: '登录成功', user: user };
    }
    // 读取本机账号记录；无记录按"账号或密码错误"提示（不暴露账号是否存在）
    const store: preferences.Preferences = await this.openStore(context);
    const value: preferences.ValueType = await store.get(`user_${normalized}`, '');
    if (typeof value !== 'string' || value.length === 0) {
      return { success: false, message: '账号或密码不正确' };
    }
    // 反序列化并校验结构版本与账号一致性，防止脏数据进入比对流程
    const saved: StoredAccount = JSON.parse(value) as StoredAccount;
    if (saved.version !== 1 || saved.account !== normalized) {
      return { success: false, message: '账号数据异常，请稍后重试' };
    }
    // 用存储盐重新派生并与存储哈希比对
    const hash: string = await this.derivePassword(password, new Uint8Array(saved.salt));
    if (hash !== saved.passwordHash) {
      return { success: false, message: '账号或密码不正确' };
    }
    // 校验通过：返回本机账号的用户信息
    const user: LoginUser = { userId: `local-${normalized}`, displayName: normalized };
    await this.rememberSession(context, user);
    return { success: true, message: '登录成功', user: user };
  }

  /**
   * 注册新账号
   * 规则校验通过后生成随机盐，仅将"盐 + 派生值"写入本机存储
   * @param account 用户输入的账号
   * @param password 用户输入的密码
   * @param context 应用上下文（用于打开本机存储）
   * @returns 注册结果
   * @throws 落盘失败时抛出异常（已回滚本次写入）
   */
  public async register(account: string, password: string, context?: common.Context): Promise<LoginResult> {
    const normalized: string = account.trim();
    // 先做纯规则校验，不通过直接返回文案
    const validation: string = AuthService.validateRegistration(normalized, password);
    if (validation.length > 0) {
      return { success: false, message: validation };
    }
    // 打开存储并检查账号是否已被占用
    const store: preferences.Preferences = await this.openStore(context);
    const key: string = `user_${normalized}`;
    if (await store.has(key)) {
      return { success: false, message: '该账号已被使用，请换一个账号' };
    }
    // 生成 16 字节随机盐，并派生密码哈希
    const random: cryptoFramework.DataBlob = await cryptoFramework.createRandom().generateRandom(16);
    const hash: string = await this.derivePassword(password, random.data);
    // 盐转普通数组以便 JSON 序列化
    const salt: number[] = [];
    for (let i: number = 0; i < random.data.length; i++) {
      salt.push(random.data[i]);
    }
    // 组装账号结构并写入缓存
    const saved: StoredAccount = { version: 1, account: normalized, salt: salt, passwordHash: hash };
    await store.put(key, JSON.stringify(saved));
    try {
      // 落盘成功才向界面报告注册成功。
      await store.flush();
    } catch (error) {
      // 落盘失败：回滚缓存中的写入并抛出异常，由调用方统一提示
      await store.delete(key);
      throw new Error('Could not persist local account');
    }
    return { success: true, message: '注册成功，请登录' };
  }
}
