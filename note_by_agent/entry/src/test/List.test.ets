// 汇总并注册本地单元测试套件。
import localUnitTest from './LocalUnit.test';

export default function testsuite() {
  localUnitTest();
}