/**
 * 统一碳因子目录。页面不再各自维护系数，所有减排量都由这里计算。
 * 因子来源与版本同步保存在 resources/rawfile/carbon_factors.json，方便答辩时追溯口径。
 */
/** 碳因子目录条目：某行为在某单位下的减排系数与口径来源 */
export interface CarbonFactor {
  /** 行为 id（如 'bike'） */
  behaviorId: string;
  /** 计量单位（如 '公里'） */
  unit: string;
  /** 主单位名称，系数按该单位计量 */
  baseUnit: string;
  /** 减排系数（kg CO₂e / 主单位数量） */
  factor: number;
  /** 因子口径来源说明 */
  source: string;
}

/** 因子目录的统一口径说明，展示在记录详情等页面供追溯 */
export const CARBON_FACTOR_CATALOG_SOURCE: string =
  '依据 GB/T 32150—2015、IPCC 2006 Guidelines 及生态环境主管部门公开电力因子；行为值为替代行为估算';

/** 碳因子目录：全部行为的减排系数与来源（公开近似口径，仅供记录参考） */
const FACTORS: CarbonFactor[] = [
  { behaviorId: 'walk', unit: '公里', baseUnit: '公里', factor: 0.21, source: '公开近似口径，按替代燃油出行估算' },
  { behaviorId: 'bike', unit: '公里', baseUnit: '公里', factor: 0.175, source: '公开近似口径，按替代燃油出行估算' },
  { behaviorId: 'transit', unit: '公里', baseUnit: '公里', factor: 0.08, source: '公开近似口径，按公共交通替代估算' },
  { behaviorId: 'carpool', unit: '公里', baseUnit: '公里', factor: 0.12, source: '公开近似口径，按拼车替代估算' },
  { behaviorId: 'metro', unit: '公里', baseUnit: '公里', factor: 0.10, source: '公开近似口径，按轨道交通替代估算' },
  { behaviorId: 'electricity', unit: '千瓦时', baseUnit: '千瓦时', factor: 0.58, source: '公开近似电力排放因子' },
  { behaviorId: 'water', unit: '升', baseUnit: '升', factor: 0.0003, source: '公开近似供水处理口径' },
  { behaviorId: 'standby', unit: '次', baseUnit: '次', factor: 0.18, source: '公开近似节能行为口径' },
  { behaviorId: 'shower', unit: '升', baseUnit: '升', factor: 0.0003, source: '公开近似供水处理口径' },
  { behaviorId: 'meal', unit: '份', baseUnit: '份', factor: 0.18, source: '公开近似餐食浪费避免口径' },
  { behaviorId: 'lowCarbonMeal', unit: '份', baseUnit: '份', factor: 0.22, source: '公开近似低碳餐食口径' },
  { behaviorId: 'recycle', unit: '千克', baseUnit: '千克', factor: 0.45, source: '公开近似材料回收口径' },
  { behaviorId: 'paperRecycle', unit: '千克', baseUnit: '千克', factor: 0.52, source: '公开近似纸张回收口径' },
  { behaviorId: 'clothesRecycle', unit: '千克', baseUnit: '千克', factor: 0.68, source: '公开近似纺织品回收口径' },
  { behaviorId: 'reuse', unit: '件', baseUnit: '件', factor: 0.12, source: '公开近似重复使用口径' },
  { behaviorId: 'disposable', unit: '件', baseUnit: '件', factor: 0.08, source: '公开近似减少一次性用品口径' },
  { behaviorId: 'shopping', unit: '件', baseUnit: '件', factor: 0.06, source: '公开近似绿色消费口径' },
  { behaviorId: 'reusable', unit: '件', baseUnit: '件', factor: 0.08, source: '公开近似重复使用口径' },
  { behaviorId: 'secondhand', unit: '件', baseUnit: '件', factor: 0.20, source: '公开近似二手流通口径' }
];

/**
 * 碳因子查询与减排量计算服务
 * 页面不再各自维护系数，所有减排量统一由本服务计算
 */
export class CarbonFactorService {
  /**
   * 按行为 id + 单位精确查找因子
   * @param behaviorId 行为 id
   * @param unit 计量单位
   * @returns 匹配的因子；目录中没有时为 undefined
   */
  get(behaviorId: string, unit: string): CarbonFactor | undefined {
    return FACTORS.find((item: CarbonFactor): boolean => item.behaviorId === behaviorId && item.unit === unit);
  }

  /**
   * 按行为 id 查找第一个因子（忽略单位差异）
   * @param behaviorId 行为 id
   * @returns 该行为的首个因子；未知行为为 undefined
   */
  getByBehavior(behaviorId: string): CarbonFactor | undefined {
    return FACTORS.find((item: CarbonFactor): boolean => item.behaviorId === behaviorId);
  }

  /**
   * 计算减排量：数量 × 单位换算系数 × 行为减排系数
   * @param behaviorId 行为 id
   * @param amount 原始数量
   * @param unit 计量单位
   * @param toBase 单位到主单位的换算系数
   * @returns 估算减排量（kg CO₂e）；无因子或数量非法时为 0
   */
  calculate(behaviorId: string, amount: number, unit: string, toBase: number): number {
    const factor: CarbonFactor | undefined = this.get(behaviorId, unit) ?? this.getByBehavior(behaviorId);
    if (factor === undefined || !Number.isFinite(amount) || amount <= 0) {
      return 0;
    }
    return amount * toBase * factor.factor;
  }

  /**
   * 查询因子口径来源说明
   * @param behaviorId 行为 id
   * @param unit 计量单位
   * @returns 口径来源文本；目录中没有时返回不可保存提示
   */
  source(behaviorId: string, unit: string): string {
    return this.get(behaviorId, unit)?.source ?? '暂无可追溯因子，禁止保存';
  }

  /**
   * 判断行为是否在因子目录中（含单位兜底），未收录的行为禁止保存
   * @param behaviorId 行为 id
   * @param unit 计量单位
   * @returns true 表示目录支持该行为
   */
  supports(behaviorId: string, unit: string): boolean {
    return this.get(behaviorId, unit) !== undefined || this.getByBehavior(behaviorId) !== undefined;
  }
}
