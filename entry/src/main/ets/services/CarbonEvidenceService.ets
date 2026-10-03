/**
 * 碳记证据服务。
 * 出行行为使用系统定位轨迹测量距离，同时读取华为运动活动数据作为辅助证据。
 * 该服务不接受用户传入的距离，数量只能来自定位累计或运动数据换算。
 */
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { healthService, healthStore } from '@kit.HealthServiceKit';

/** 证据来源类型：'location' 系统定位轨迹 / 'health' 华为运动数据 / 'ai_image' 端侧 OCR 图片辅助 / 'manual' 手动记录待核实 */
export type EvidenceSource = 'location' | 'health' | 'ai_image' | 'manual';

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
    try {
      // 健康服务使用独立的数据授权弹窗。数据范围不能作为普通模块权限声明，
      // 否则面向普通用户设备安装 HAP 时会被系统拒绝。
      await healthStore.init(context);
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
      // 读取当日活动报告并返回步数
      const report: healthService.workout.ActivityReport = await healthService.workout.readActivityReport();
      return {
        amount: report.steps,
        unit: '步', source: 'health', verified: report.steps > 0,
        message: report.steps > 0 ? '已读取华为运动步数' : '华为运动暂无可用数据',
        evidenceId: `health-${Date.now()}`
      };
    } catch (error) {
      // 健康服务不可用（未安装/未登录等）：降级为待核实
      return {
        amount: 0, unit: '步', source: 'manual', verified: false,
        message: '华为运动数据暂不可用，本次记录将标记为待核实', evidenceId: ''
      };
    }
  }

  /** 是否正在定位测量中 */
  isTracking(): boolean {
    return this.tracking;
  }
}
