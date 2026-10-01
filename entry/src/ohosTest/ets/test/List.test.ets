/**
 * 仪器测试入口
 * 汇总注册所有 ohosTest 仪器测试套件，供测试框架统一调度
 */
import abilityTest from './Ability.test';

export default function testsuite() {
  // 注册 Ability 仪器测试套件
  abilityTest();
}
