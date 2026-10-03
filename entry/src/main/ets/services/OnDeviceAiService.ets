/**
 * 碳记端侧 AI 服务。
 * 仅封装华为 Core Vision Kit OCR 和本地规则，不联网、不上传图片。
 * OCR 失败时返回可解释的降级结果，页面仍可继续保存为待核实记录。
 */
import { textRecognition } from '@kit.CoreVisionKit';
import image from '@ohos.multimedia.image';

/** 端侧 OCR 识别产出的可确认草稿：识别文本、解析数量与本地风险评估结果 */
export interface AiRecognitionDraft {
  /** OCR 识别出的完整文本；识别失败或图片为空时为空串 */
  text: string;
  /** 从文本中解析出的距离数量；未识别到时为 0 */
  amount: number;
  /** 解析出的距离单位（'公里' 或 '米'）；未识别到时为空串 */
  unit: string;
  /** 识别时传入的行为名称，回显给页面核对 */
  recognizedBehavior: string;
  /** 本地规则计算的识别置信度（0–1），不代表图片真实性 */
  confidence: number;
  /** 图片内容指纹，用于本机重复提交拦截与答辩追溯 */
  imageHash: string;
  /** 本地风险标记列表（如 '识别文字过少'、'行为不匹配'），为空表示未发现风险 */
  riskFlags: string[];
  /** AI 服务名称（当前固定 CoreVisionKit.OCR） */
  provider: string;
}

/** 从 OCR 文本中解析出的距离数量与单位 */
interface ParsedAmount {
  /** 距离数值；未匹配到数字时为 0 */
  amount: number;
  /** 规范化后的单位：'公里' 或 '米'；未匹配到时为空串 */
  unit: string;
}

export class OnDeviceAiService {
  /**
   * 生成本机图片 URI 的稳定摘要，拦截同一资源重复认证
   * 使用 FNV-1a 哈希逐字符计算，返回带前缀的十六进制摘要
   * @param value 图片 URI 字符串
   * @returns URI 摘要（如 'uri-fnv1a-1a2b3c4d'）
   */
  private fingerprint(value: string): string {
    let hash: number = 2166136261;
    for (let index: number = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `uri-fnv1a-${(hash >>> 0).toString(16)}`;
  }

  /**
   * API 26 设备优先按像素内容生成摘要，无法读取时回退到系统授权 URI
   * 像素级摘要按每 4 字节采样计算 FNV-1a，可识别同 URI 换图重传的场景
   * @param uri 图片 URI（回退摘要使用）
   * @param pixelMap 已解码的像素图（像素摘要使用）
   * @returns 图片内容摘要（如 'pixel-fnv1a-…'）或 URI 回退摘要
   */
  private async imageFingerprint(uri: string, pixelMap: image.PixelMap): Promise<string> {
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readAllPixelsToBuffer(buffer);
      const bytes: Uint8Array = new Uint8Array(buffer);
      let hash: number = 2166136261;
      for (let index: number = 0; index < bytes.length; index += 4) {
        hash ^= bytes[index];
        hash = Math.imul(hash, 16777619);
      }
      return `pixel-fnv1a-${(hash >>> 0).toString(16)}`;
    } catch (error) {
      return this.fingerprint(uri);
    }
  }

  /**
   * 根据 OCR 文本识别距离和单位
   * 匹配"数字 + 公里/千米/km/米/m"形式的第一个结果；'米'/'m' 归一化为 '米'，其余归一化为 '公里'
   * @param text OCR 识别文本
   * @returns 解析出的数量与单位；未匹配到时数量为 0、单位为空串
   */
  private parseAmount(text: string): ParsedAmount {
    const match: RegExpMatchArray | null = text.match(/(\d+(?:\.\d+)?)\s*(公里|千米|km|KM|米|m)/);
    if (match === null) {
      return { amount: 0, unit: '' };
    }
    const amount: number = Number.parseFloat(match[1]);
    const rawUnit: string = match[2].toLowerCase();
    return { amount: amount, unit: rawUnit === '米' || rawUnit === 'm' ? '米' : '公里' };
  }

  /**
   * 识别截图中的行为关键词，不能证明用户本人完成了行为
   * 每类行为维护一组别名（中英文），命中任意别名即视为匹配
   * @param text OCR 识别文本（小写化后匹配）
   * @param behaviorName 行为名称（如 '骑行'）
   * @returns true 表示文本中出现该行为的任一别名
   */
  private behaviorMatched(text: string, behaviorName: string): boolean {
    const aliases: string[] = behaviorName === '骑行' ? ['骑行', '单车', '自行车', '骑车', 'bike'] :
      behaviorName === '地铁出行' ? ['地铁', '轨道交通', 'metro'] :
      behaviorName === '公共交通' ? ['公交', '公共交通', '乘车', 'bus'] :
      behaviorName === '拼车出行' ? ['拼车', '顺风车', 'carpool'] :
      ['步行', '步数', 'walking'];
    const normalized: string = text.toLowerCase();
    return aliases.some((alias: string): boolean => normalized.includes(alias.toLowerCase()));
  }

  /**
   * 在本机调用 Core Vision Kit OCR 并生成可确认草稿
   * 识别后本地计算图片指纹、解析距离、校验行为关键词与日期，汇总风险标记与置信度；
   * OCR 失败或图片为空时返回带风险标记的降级结果，页面仍可保存为待核实记录。
   * @param uri 系统相册授权的图片 URI
   * @param behaviorName 当前记录的行为名称（用于关键词匹配）
   * @returns 端侧识别草稿（含数量、置信度、风险标记与图片指纹）
   */
  async recognize(uri: string, behaviorName: string): Promise<AiRecognitionDraft> {
    const riskFlags: string[] = [];
    if (uri.length === 0) {
      return {
        text: '', amount: 0, unit: '', recognizedBehavior: behaviorName, confidence: 0,
        imageHash: '', riskFlags: ['图片为空'], provider: 'CoreVisionKit.OCR'
      };
    }
    let source: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    try {
      source = image.createImageSource(uri);
      pixelMap = await source.createPixelMap();
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText({ pixelMap: pixelMap });
      const text: string = result.value ?? '';
      const imageHash: string = await this.imageFingerprint(uri, pixelMap);
      const parsed: ParsedAmount = this.parseAmount(text);
      if (text.length < 6) {
        riskFlags.push('识别文字过少');
      }
      if (parsed.amount <= 0) {
        riskFlags.push('未识别到距离');
      }
      if (!this.behaviorMatched(text, behaviorName)) {
        riskFlags.push('行为不匹配');
      }
      if (!text.match(/20\d{2}|\d{1,2}月\d{1,2}日|今天|昨天/)) {
        riskFlags.push('日期缺失');
      }
      const confidence: number = Math.max(0, Math.min(1,
        0.25 + (text.length >= 6 ? 0.25 : 0) + (parsed.amount > 0 ? 0.25 : 0) +
        (this.behaviorMatched(text, behaviorName) ? 0.25 : 0)));
      return {
        text: text,
        amount: parsed.amount,
        unit: parsed.unit,
        recognizedBehavior: behaviorName,
        confidence: confidence,
        imageHash: imageHash,
        riskFlags: riskFlags,
        provider: 'CoreVisionKit.OCR'
      };
    } catch (error) {
      return {
        text: '', amount: 0, unit: '', recognizedBehavior: behaviorName, confidence: 0,
        imageHash: this.fingerprint(uri), riskFlags: ['设备端 OCR 不可用'], provider: 'CoreVisionKit.OCR'
      };
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
      if (source !== undefined) {
        await source.release();
      }
    }
  }
}
