/**
 * Ability 仪器测试用例
 * 运行在设备/模拟器上的应用级测试套件，验证 Ability 相关行为
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';

export default function abilityTest() {
  // 定义测试套件：第一个参数为套件名称，第二个参数为套件函数
  describe('ActsAbilityTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    // 所有测试用例开始前执行一次的预设动作（仅支持一个参数：预设动作函数）
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    })
    // 每个测试用例开始前执行的预设动作，执行次数与 it 定义的用例数一致
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    })
    // 每个测试用例结束后执行的清理动作，执行次数与 it 定义的用例数一致
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    })
    // 所有测试用例结束后执行一次的清理动作
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    })
    // 定义测试用例：参数依次为用例名称、过滤参数、用例函数
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      hilog.info(0x0000, 'testTag', '%{public}s', 'it begin');
      let a = 'abc';
      let b = 'b';
      // 断言方法：声明期望的布尔条件（包含断言与相等断言）
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    })
  })
}
