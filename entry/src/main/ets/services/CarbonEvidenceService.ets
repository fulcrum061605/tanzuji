/**
 * 碳记证据服务。
 * 出行行为使用系统定位轨迹测量距离，同时读取当日步数作为辅助证据：
 * 优先走华为运动健康数据，未开通（AGC 审核中或被驳回）时自动降级为本机计步传感器。
 * 该服务不接受用户传入的距离，数量只能来自定位累计或步数换算。
 */
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { healthService, healthStore } from '@kit.HealthServiceKit';
import { sensor } from '@kit.SensorServiceKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 证据来源类型：'location' 系统定位轨迹 / 'health' 华为运动数据 / 'sensor' 本机计步传感器 / 'ai_image' 端侧 OCR 图片辅助 / 'manual' 手动记录待核实 */
export type EvidenceSource = 'location' | 'health' | 'sensor' | 'ai_image' | 'manual';

/** 本机计步日基准：计步传感器只提供开机以来累计步数，需按天记录基数换算今日步数 */
interface StepDayRecord {
  /** 基准归属日期（yyyy-MM-dd） */
  date: string;
  /** 上次读取时的开机累计步数：用于计算增量，变小视为设备重启 */
  lastCum: number;
  /** 今日已累计步数 */
  todaySteps: number;
}

/** 证据测量结果：携带数量、来源、核验状态与提示文案 */
export interface EvidenceResult {
  /** 测量数量（定位为公里数，运动为步数） */
  amount: number;
  /** 数量单位名称（'公里' 或 '步'） */
  unit: string;
  /** 证据来源 */
  source: EvidenceSource;
  /** 是否通过系统核验：只有核验通过的记录才计入正式减排 */
  verified: boolean;
  /** 结果提示文案（用于界面反馈展示） */
  message: string;
  /** 证据唯一编号：随记录保存，用于追溯 */
  evidenceId: string;
}

/** 精确定位权限 */
const LOCATION_PERMISSION: Permissions = 'ohos.permission.LOCATION';
/** 模糊定位权限 */
const APPROXIMATE_LOCATION_PERMISSION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
/** 运动状态识别权限（步数统计依赖） */
const MOTION_PERMISSION: Permissions = 'ohos.permission.ACTIVITY_MOTION';
/** 本机计步日基准的 Preferences 存储库名 */
const STEP_STORE_NAME: string = 'tanji_step_baseline_v1';
/** 本机计步日基准在存储库中的键名 */
const STEP_RECORD_KEY: string = 'step_day_record';
/** 计步传感器单次读取超时（毫秒）：防止服务异常导致界面停留在读取状态 */
const PEDOMETER_TIMEOUT_MS: number = 5000;

/** 碳证据服务：封装系统定位轨迹测量与华为运动数据读取，保证数量来源可信 */
export class CarbonEvidenceService {
  /** 是否正在定位测量中 */
  private tracking: boolean = false;
  /** 最近一次定位点：用于与最新定位点计算分段距离 */
  private lastLocation: geoLocationManager.Location | undefined = undefined;
  /** 本次测量已累计的轨迹距离（米） */
  private distanceMeters: number = 0;
  /** 距离更新回调：参数为当前累计公里数，由记录详情页注入 */
  private callback?: (distanceKm: number) => void;

  /** 定位请求参数：高精度优先、轨迹追踪场景，每 2 秒或每 5 米上报一次 */
  private readonly locationRequest: geoLocationManager.LocationRequest = {
    priority: geoLocationManager.LocationRequestPriority.ACCURACY,
    scenario: geoLocationManager.LocationRequestScenario.TRAJECTORY_TRACKING,
    timeInterval: 2,
    distanceInterval: 5
  };

  /**
   * 用 Haversine 公式计算两个定位点之间的球面距离
   * @param first 起点定位
   * @param second 终点定位
   * @returns 两点间距离（米）
   */
  private distanceBetween(first: geoLocationManager.Location, second: geoLocationManager.Location): number {
    const earthRadius: number = 6371000;
    const latitudeDelta: number = (second.latitude - first.latitude) * Math.PI / 180;
    const longitudeDelta: number = (second.longitude - first.longitude) * Math.PI / 180;
    const firstLatitude: number = first.latitude * Math.PI / 180;
    const secondLatitude: number = second.latitude * Math.PI / 180;
    const value: number = Math.sin(latitudeDelta / 2) * Math.sin(latitudeDelta / 2) +
      Math.cos(firstLatitude) * Math.cos(secondLatitude) *
      Math.sin(longitudeDelta / 2) * Math.sin(longitudeDelta / 2);
    return earthRadius * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
  }

  /**
   * 向用户批量申请权限
   * @param context 应用上下文
   * @param permissions 待申请的权限列表
   * @returns true 表示全部权限均已授予
   */
  private async requestPermissionList(context: common.Context, permissions: Permissions[]): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result: PermissionRequestResult =
      await atManager.requestPermissionsFromUser(context, permissions);
    // 授权结果数组中 0 表示授予，全部为 0 才算通过
    return result.authResults.every((status: number): boolean => status === 0);
  }

  /**
   * 申请定位测量所需权限（精确/模糊定位 + 运动识别）
   * @param context 应用上下文
   * @returns true 表示定位与运动权限均已授予
   */
  private async requestLocationPermissions(context: common.Context): Promise<boolean> {
    const permissions: Permissions[] = [
      LOCATION_PERMISSION,
      APPROXIMATE_LOCATION_PERMISSION,
      MOTION_PERMISSION
    ];
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result: PermissionRequestResult =
      await atManager.requestPermissionsFromUser(context, permissions);
    // 不同系统版本在权限被拒或权限不存在时可能返回较短数组，缺项按未授权处理。
    const authResults: number[] = result.authResults;
    const locationGranted: boolean = authResults.length > 0 &&
      (authResults[0] === 0 || (authResults.length > 1 && authResults[1] === 0));
    // 运动权限必须明确返回授权；缺少第三项不能当作已授权。
    const motionGranted: boolean = authResults.length > 2 && authResults[2] === 0;
    return locationGranted && motionGranted;
  }

  /**
   * 申请华为运动数据读取所需的运动权限
   * @param context 应用上下文
   * @returns true 表示权限已授予
   */
  private async requestHealthPermissions(context: common.Context): Promise<boolean> {
    return this.requestPermissionList(context, [MOTION_PERMISSION]);
  }

  /**
   * 开始系统定位轨迹测量
   * 重复调用直接返回当前累计距离；权限被拒时不启动定位并返回待核实结果。
   * 测量期间通过回调持续上报累计公里数；漂移点（精度>100m）与异常分段（<3m 或 >300m）会被过滤。
   * @param context 应用上下文（用于权限申请）
   * @param callback 距离更新回调（参数为累计公里数）
   * @returns 测量启动结果
   */
  async startLocationTracking(context: common.Context, callback: (distanceKm: number) => void): Promise<EvidenceResult> {
    // 已在测量中：直接返回当前累计距离
    if (this.tracking) {
      return {
        amount: this.distanceMeters / 1000,
        unit: '公里', source: 'location', verified: true,
        message: '系统正在测量', evidenceId: 'location-session'
      };
    }
    // 权限未授予：返回待核实结果，不启动定位
    const granted: boolean = await this.requestLocationPermissions(context);
    if (!granted) {
      return {
        amount: 0, unit: '公里', source: 'manual', verified: false,
        message: '未获得定位或运动权限，本次记录将标记为待核实', evidenceId: ''
      };
    }
    // 重置测量状态并注册定位监听
    this.distanceMeters = 0;
    this.lastLocation = undefined;
    this.callback = callback;
    this.tracking = true;
    geoLocationManager.onLocationChange(this.locationRequest, (location: geoLocationManager.Location): void => {
      // 已停止测量后到达的定位点直接丢弃
      if (!this.tracking) {
        return;
      }
      // 精度 100 米内的定位才参与累计；过滤漂移点与异常分段
      if (this.lastLocation !== undefined && location.accuracy <= 100) {
        const segment: number = this.distanceBetween(this.lastLocation, location);
        if (segment >= 3 && segment <= 300) {
          this.distanceMeters += segment;
          this.callback?.(this.distanceMeters / 1000);
        }
      }
      this.lastLocation = location;
    });
    return {
      amount: 0, unit: '公里', source: 'location', verified: true,
      message: '已开始系统测量，完成后点击结束测量', evidenceId: `location-${Date.now()}`
    };
  }

  /**
   * 结束定位测量并返回累计结果
   * 累计距离不足 50 米时标记为待核实，防止无效轨迹计入减排。
   * @returns 测量结果：携带累计公里数与核验状态
   */
  async stopLocationTracking(): Promise<EvidenceResult> {
    // 注销定位监听
    if (this.tracking) {
      geoLocationManager.offLocationChange();
    }
    this.tracking = false;
    // 保留 3 位小数，避免浮点误差
    const amount: number = Number((this.distanceMeters / 1000).toFixed(3));
    const result: EvidenceResult = {
      amount: amount, unit: '公里', source: 'location', verified: amount > 0.05,
      message: amount > 0.05 ? '已完成系统轨迹验证' : '轨迹距离不足，已标记为待核实',
      evidenceId: `location-${Date.now()}`
    };
    // 清理测量状态，下次测量从零开始
    this.lastLocation = undefined;
    this.callback = undefined;
    return result;
  }

  /**
   * 读取华为运动活动数据（当日步数）
   * 需先授予运动权限，再通过健康服务的独立授权弹窗申请读取"每日活动"数据。
   * 前置条件（工程外配置，缺一不可，详见 Health Service Kit 文档）：
   * 1. 在 AppGallery Connect 的 Health Service Kit 卡片申请服务并勾选"日常活动 > 日常活动数据（读）"；
   * 2. 在 module.json5 的 module.metadata 中配置 AGC 下发的 client_id；
   * 3. 真机已登录华为账号且装有华为运动健康；模拟器不支持实时三环数据（readActivityReport）。
   * @param context 应用上下文（用于权限与授权申请）
   * @returns 读取结果：成功时携带步数
   */
  async readHuaweiActivity(context: common.Context): Promise<EvidenceResult> {
    // 运动权限被拒：返回待核实结果
    const granted: boolean = await this.requestHealthPermissions(context);
    if (!granted) {
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: '未获得华为运动权限，本次记录将标记为待核实', evidenceId: ''
      };
    }
    // 健康服务使用独立的数据授权弹窗。数据范围不能作为普通模块权限声明，
    // 否则面向普通用户设备安装 HAP 时会被系统拒绝。
    try {
      await healthStore.init(context);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, 'CarbonEvidence', `healthStore.init failed: code=${err.code}, message=${err.message}`);
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: `运动健康服务初始化失败（错误码 ${err.code}），请稍后重试`, evidenceId: ''
      };
    }
    try {
      const authorization: healthStore.AuthorizationResponse =
        await healthStore.requestAuthorizations(context as common.UIAbilityContext, {
          readDataTypes: [healthStore.healthDataTypes.DAILY_ACTIVITIES],
          writeDataTypes: []
        });
      // 校验"每日活动"数据是否真正授权成功
      const activityAuthorized: boolean = authorization.readDataTypes.some(
        (dataType: healthStore.DataType): boolean =>
          dataType.id === healthStore.healthDataTypes.DAILY_ACTIVITIES.id
      );
      if (!activityAuthorized) {
        return {
          amount: 0, unit: '步', source: 'manual', verified: false,
          message: '未授权读取华为运动活动数据，本次记录将标记为待核实', evidenceId: ''
        };
      }
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, 'CarbonEvidence',
        `requestAuthorizations failed: code=${err.code}, message=${err.message}`);
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: this.healthAuthErrorMessage(err), evidenceId: ''
      };
    }
    try {
      // 读取当日活动报告并返回步数
      const report: healthService.workout.ActivityReport = await healthService.workout.readActivityReport();
      return {
        amount: report.steps,
        unit: '步', source: 'health', verified: report.steps > 0,
        message: report.steps > 0 ? '已读取今日步数（华为运动）' : '华为运动暂无可用数据',
        evidenceId: `health-${Date.now()}`
      };
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, 'CarbonEvidence',
        `readActivityReport failed: code=${err.code}, message=${err.message}`);
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: this.healthReadErrorMessage(err), evidenceId: ''
      };
    }
  }

  /**
   * 读取今日步数：华为运动优先，不可用时自动降级为本机计步传感器
   * 运动权限（ACTIVITY_MOTION）为两条路径共同前置，先统一申请；
   * 华为运动因 AGC 未开通、client_id 未配置或账号未登录失败时，改读计步传感器；
   * 两条路径都失败时返回华为运动的原始错误提示并补充本机计步失败原因。
   * @param context 应用上下文（用于权限申请与数据读取）
   * @returns 读取结果：成功时携带步数，来源为 'health' 或 'sensor'
   */
  async readTodaySteps(context: common.Context): Promise<EvidenceResult> {
    // 运动权限被拒：两条路径都无法工作，直接返回待核实结果
    const granted: boolean = await this.requestHealthPermissions(context);
    if (!granted) {
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: '未获得运动权限，本次记录将标记为待核实', evidenceId: ''
      };
    }
    // 先走华为运动官方健康服务；已授权场景下内部的权限申请为无弹窗快速通过
    const healthResult: EvidenceResult = await this.readHuaweiActivity(context);
    if (healthResult.source === 'health') {
      return healthResult;
    }
    // 华为运动不可用：降级读取本机计步传感器
    const sensorResult: EvidenceResult = await this.readTodayStepsFromSensor(context);
    if (sensorResult.source === 'sensor') {
      return sensorResult;
    }
    // 两条路径都失败：保留华为运动的错误提示（含 AGC 开通指引）并补充本机计步失败原因
    return {
      amount: 0, unit: '步', source: 'manual', verified: false,
      message: `${healthResult.message}；${sensorResult.message}`,
      evidenceId: ''
    };
  }

  /**
   * 读取本机计步传感器并换算今日步数
   * 计步传感器只提供开机以来累计步数（重启清零），需结合本地日基准做增量换算；
   * 首次读取只建立基数不计入步数，避免把开机多日的累计错误归属到今天。
   * @param context 应用上下文（用于读取日基准）
   * @returns 读取结果：成功时携带今日步数，来源为 'sensor'
   */
  private async readTodayStepsFromSensor(context: common.Context): Promise<EvidenceResult> {
    try {
      // 先确认设备具备计步传感器，避免在模拟器等无传感器设备上触发异常
      await this.hasPedometer();
      const cumulative: number = await this.readPedometerOnce();
      const todaySteps: number = await this.accumulateTodaySteps(context, cumulative);
      return {
        amount: todaySteps,
        unit: '步', source: 'sensor', verified: todaySteps > 0,
        message: todaySteps > 0 ? '已读取今日步数（本机计步）' : '本机计步已就绪，从现在开始统计今日步数',
        evidenceId: `sensor-${Date.now()}`
      };
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, 'CarbonEvidence',
        `pedometer fallback failed: code=${err.code}, message=${err.message}`);
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: `本机计步不可用（错误码 ${err.code}）：设备可能不支持计步传感器`,
        evidenceId: ''
      };
    }
  }

  /**
   * 确认设备是否具备计步传感器
   * @returns 设备支持时正常返回，不支持时抛出业务错误
   */
  private hasPedometer(): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (error: BusinessError) => void) => {
      sensor.getSingleSensor(sensor.SensorId.PEDOMETER, (err: BusinessError, data: sensor.Sensor): void => {
        if (err) {
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  /**
   * 单次读取计步传感器的开机累计步数
   * 接口异常会同步抛出，读取超时按服务异常拒绝，避免界面停留在读取状态。
   * @returns 开机以来的累计步数
   */
  private readPedometerOnce(): Promise<number> {
    return new Promise<number>((resolve: (steps: number) => void, reject: (error: BusinessError) => void) => {
      const timeoutId: number = setTimeout((): void => {
        const timeoutError: BusinessError = { code: 14500101, name: 'TimeoutError', message: '读取计步数据超时' };
        reject(timeoutError);
      }, PEDOMETER_TIMEOUT_MS);
      try {
        sensor.once(sensor.SensorId.PEDOMETER, (data: sensor.PedometerResponse): void => {
          clearTimeout(timeoutId);
          resolve(data.steps);
        });
      } catch (error) {
        clearTimeout(timeoutId);
        reject(error as BusinessError);
      }
    });
  }

  /**
   * 按日基准换算今日步数并落盘
   * 计步传感器为开机累计值，换算规则：
   * - 同一天：todaySteps += 本次与上次的增量；累计值变小视为设备重启，增量为重启后的步数；
   * - 新的一天：以上次读取为基线重新计数，跨日增量计入今天；
   * - 首次读取：只记录当前基数，今日步数从 0 开始，避免把开机多日的累计归属到今天。
   * @param context 应用上下文
   * @param cumulative 本次读取到的开机累计步数
   * @returns 换算后的今日步数
   */
  private async accumulateTodaySteps(context: common.Context, cumulative: number): Promise<number> {
    const store: preferences.Preferences =
      await preferences.getPreferences(context, { name: STEP_STORE_NAME });
    const today: string = this.todayKey();
    // 默认记录：首次读取只建立基数
    let record: StepDayRecord = { date: today, lastCum: cumulative, todaySteps: 0 };
    const raw: preferences.ValueType = await store.get(STEP_RECORD_KEY, '');
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const saved: StepDayRecord = JSON.parse(raw) as StepDayRecord;
        if (typeof saved.date === 'string' && typeof saved.lastCum === 'number' &&
          typeof saved.todaySteps === 'number') {
          // 累计值变小视为设备重启：增量为重启后新产生的步数
          const delta: number = cumulative >= saved.lastCum ? cumulative - saved.lastCum : cumulative;
          if (saved.date === today) {
            record = { date: today, lastCum: cumulative, todaySteps: Math.max(0, saved.todaySteps) + delta };
          } else {
            // 新的一天：以上次读取为基线，跨零点以来的增量计入今天
            record = { date: today, lastCum: cumulative, todaySteps: delta };
          }
        }
      } catch (error) {
        // 基准数据损坏时按首次读取重建基数
        hilog.error(0x0000, 'CarbonEvidence', 'step baseline corrupted, rebuilding');
      }
    }
    await store.put(STEP_RECORD_KEY, JSON.stringify(record));
    await store.flush();
    return Math.max(0, Math.round(record.todaySteps));
  }

  /** 生成本地日期键（yyyy-MM-dd），与我的页步数口径保持一致 */
  private todayKey(): string {
    const date: Date = new Date();
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  }

  /**
   * 将健康服务授权阶段错误码翻译为可操作的提示文案
   * @param err 授权接口抛出的业务错误
   * @returns 面向用户的提示文案（含错误码与处理建议）
   */
  private healthAuthErrorMessage(err: BusinessError): string {
    if (err.code === 1001502014) {
      return '应用未开通运动健康数据权限（1001502014）：请先在 AppGallery Connect 的 Health Service Kit 卡片申请"日常活动数据（读）"';
    }
    if (err.code === 1001502003) {
      return '应用未配置 client_id（1001502003）：请在 module.json5 的 metadata 中填写 AppGallery Connect 的 Client ID';
    }
    if (err.code === 12300001) {
      return '华为账号服务异常（12300001）：请确认设备已登录华为账号后重试';
    }
    if (err.code === 201) {
      return '健康数据鉴权失败（201）：请检查 AGC 应用的证书指纹与已申请的数据权限';
    }
    return `华为运动授权失败（错误码 ${err.code}）：${err.message}`;
  }

  /**
   * 将健康数据读取阶段错误码翻译为可操作的提示文案
   * @param err 读取接口抛出的业务错误
   * @returns 面向用户的提示文案（含错误码与处理建议）
   */
  private healthReadErrorMessage(err: BusinessError): string {
    // 模拟器自 6.0.2(22) 起支持健康服务开发，但不支持实时三环数据（readActivityReport）。
    return `读取今日步数失败（错误码 ${err.code}）：请确认真机已登录华为账号且装有华为运动健康；模拟器不支持实时步数读取`;
  }

  /** 是否正在定位测量中 */
  isTracking(): boolean {
    return this.tracking;
  }
}
