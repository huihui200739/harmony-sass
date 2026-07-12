# 贡献指南

感谢参与 Harmony Sass。

## 本地要求

- DevEco Studio（HarmonyOS 6.1.1 SDK）
- 一个鸿蒙 PC、2in1 设备或对应的模拟环境

## 提交前检查

1. 为编译器逻辑增加或更新 `entry/src/test` 下的单元测试。
2. 在 DevEco Studio 中执行 `entry` 的 `test` 和 `assembleHap` 任务。
3. 不提交 `build`、`.hvigor`、`oh_modules`、`.idea` 或 `local.properties`。

## 范围

第一阶段专注于无需外部运行时的 SCSS Lite 兼容能力。新增语法前，请同时补充相应的输入、预期 CSS 和异常场景测试。
