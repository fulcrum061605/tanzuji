/**
 * 本地单元测试入口
 * 汇总注册所有本地单元测试套件，供测试框架统一调度
 */
import localUnitTest from './LocalUnit.test';

export default function testsuite() {
  // 注册本地单元测试套件
  localUnitTest();
}
